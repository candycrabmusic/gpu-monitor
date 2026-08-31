import QtQuick
import Quickshell.Io
import "Model.js" as Model

// Polled NVIDIA GPU monitor.
//
// Everything is read through `nvidia-smi` — the standard, read-only, no-
// privilege source for NVIDIA GPUs — so the plugin needs nothing installed
// beyond the driver's own userland tools and touches no sysfs, no device
// nodes, and no privileged helpers.
//
// One snapshot per poll: a single `nvidia-smi --query-gpu=...` call that
// returns one CSV line, parsed in parseStats(). Compute-app processes are
// polled at half rate by a second Process. A missing nvidia-smi (or a
// machine with no NVIDIA GPU) just sets `available` false and every UI
// surface falls back to a "—" sentinel; the widget never crashes.
QtObject {
  id: root

  // ---- public read-only surface (bound by the bar label + panel) ----
  property bool available: false
  property bool firstSample: false
  property bool cpuAvailable: false   // true once a valid /proc/stat sample lands

  property string gpuName: ""
  property string driver: ""
  property string pstate: ""

  property int gpuUtil: 0          // percent 0..100
  property int memUtil: 0          // memory-controller utilization percent
  property int tempGpu: 0
  property string tempMem: "N/A"   // "N/A" when the card does not expose it
  property int fanSpeed: 0         // percent 0..100; 0 = fans at rest

  property real powerDraw: 0       // watts
  property real powerLimit: 0      // watts
  property int gfxClock: 0         // MHz
  property int smClock: 0          // MHz
  property int memClock: 0         // MHz
  property int gfxMaxClock: 0      // MHz
  property int memMaxClock: 0      // MHz

  property int vramUsed: 0         // MiB
  property int vramFree: 0         // MiB
  property int vramTotal: 0        // MiB

  property bool throttleActive: false     // any real slowdown condition below
  property bool throttleHwSlowdown: false
  property bool throttleSwThermal: false
  property bool throttleHwThermal: false
  property bool throttleHwPowerBrake: false
  property bool throttleSyncBoost: false
  property bool throttleGpuIdle: true

  property int pcieGen: 0           // current PCIe link generation
  property int pcieWidth: 0         // current PCIe link lanes

  property real cpuUtil: 0          // CPU usage percent 0..100 (delta over one poll)

  property var processes: []       // [{pid, name, memory(MiB)}]

  readonly property int vramPct: Model.percent(root.vramUsed, root.vramTotal)

  // ---- tuning ----
  property int statInterval: 2000
  property bool enabled: true

  // ---- state ----
  property int tick: 0

  // Column order of the --query-gpu CSV, mirrored in parseStats().
  readonly property string gpuQuery: [
    "name",
    "driver_version",
    "pstate",
    "utilization.gpu",
    "utilization.memory",
    "temperature.gpu",
    "temperature.memory",
    "fan.speed",
    "power.draw",
    "power.limit",
    "clocks.current.graphics",
    "clocks.current.sm",
    "clocks.current.memory",
    "clocks.max.graphics",
    "clocks.max.memory",
    "memory.used",
    "memory.free",
    "memory.total",
    "clocks_throttle_reasons.active",
    "clocks_throttle_reasons.hw_slowdown",
    "clocks_throttle_reasons.sw_thermal_slowdown",
    "clocks_throttle_reasons.hw_thermal_slowdown",
    "clocks_throttle_reasons.hw_power_brake_slowdown",
    "clocks_throttle_reasons.sync_boost",
    "clocks_throttle_reasons.gpu_idle",
    "pcie.link.gen.current",
    "pcie.link.width.current"
  ].join(",")

  function refresh() {
    if (!statProc.running) statProc.running = true
  }

  function refreshProcesses() {
    if (!procProc.running) procProc.running = true
  }

  function refreshCpu() {
    if (!cpuProc.running) cpuProc.running = true
  }

  property Timer pollTimer: Timer {
    interval: root.statInterval
    running: root.enabled
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      root.tick = root.tick + 1
      root.refresh()
      root.refreshCpu()
      // Processes are heavier and change slowly; poll them on alternate ticks.
      if (root.tick % 2 === 0) root.refreshProcesses()
    }
  }

  property Process statProc: Process {
    command: ["nvidia-smi", "--query-gpu=" + root.gpuQuery, "--format=csv,noheader,nounits"]
    stdout: StdioCollector {
      id: statOutput
      waitForEnd: true
      onStreamFinished: root.parseStats(statOutput.text)
    }
  }

  property Process procProc: Process {
    command: ["nvidia-smi", "--query-compute-apps=pid,process_name,used_memory", "--format=csv,noheader"]
    stdout: StdioCollector {
      id: procOutput
      waitForEnd: true
      onStreamFinished: root.parseProcesses(procOutput.text)
    }
  }

  // CPU utilization is read from /proc/stat (no privileges, no extra tools).
  // Utilization is the delta in non-idle CPU time between two consecutive
  // reads, so the previous sample's raw counters are stashed below.
  property var cpuPrev: null   // [{total, idle}] raw jiffies from last read
  property int cpuCores: 0     // thread count (from `cpuN` lines), for the sum/max

  property Process cpuProc: Process {
    command: ["cat", "/proc/stat"]
    stdout: StdioCollector {
      id: cpuOutput
      waitForEnd: true
      onStreamFinished: root.parseCpu(cpuOutput.text)
    }
  }

  function parseCpu(text) {
    var lines = String(text || "").split("\n")
    var agg = null
    var cores = 0
    for (var i = 0; i < lines.length; i++) {
      var line = String(lines[i]).trim()
      if (line.indexOf("cpu") !== 0) break
      var tokens = line.split(/\s+/)
      if (tokens.length < 5) continue
      if (tokens[0] === "cpu") {
        agg = tokens
      } else if (tokens[0].indexOf("cpu") === 0) {
        cores = cores + 1
      }
    }
    if (!agg) { root.cpuUtil = 0; root.cpuAvailable = false; return }

    // The aggregate `cpu` line reports the *system-wide* jiffies summed over
    // all cores, so utilization over it is already the whole-machine percent.
    var curTotal = 0
    var curIdle = 0
    for (var j = 1; j < agg.length; j++) {
      var v = Model.posInt(agg[j], 0)
      if (j === 4) curIdle = v + (j + 1 < agg.length ? Model.posInt(agg[j + 1], 0) : 0)
      curTotal += v
    }

    root.cpuCores = cores
    root.cpuAvailable = true

    if (root.cpuPrev) {
      var dTotal = curTotal - root.cpuPrev.total
      var dIdle = curIdle - root.cpuPrev.idle
      if (dTotal > 0) {
        root.cpuUtil = Math.max(0, Math.min(100, Math.round(((dTotal - dIdle) / dTotal) * 100)))
      }
    }

    root.cpuPrev = { total: curTotal, idle: curIdle }
    if (cores > 0) root.firstSample = true
  }

  function boolField(value) {
    return String(value || "").indexOf("Active") >= 0
  }

  function parseStats(text) {
    var line = String(text || "").trim().split("\n")[0] || ""
    var f = line.split(", ")
    if (f.length < 27 || line === "") {
      root.available = false
      return
    }

    root.gpuName = f[0] || ""
    root.driver = f[1] || ""
    root.pstate = f[2] || ""
    root.gpuUtil = Model.posInt(f[3], 0)
    root.memUtil = Model.posInt(f[4], 0)
    root.tempGpu = Model.posInt(f[5], 0)
    root.tempMem = String(f[6] || "N/A").trim()
    root.fanSpeed = Model.posInt(f[7], 0)
    root.powerDraw = Model.floatOr(f[8], 0)
    root.powerLimit = Model.floatOr(f[9], 0)
    root.gfxClock = Model.posInt(f[10], 0)
    root.smClock = Model.posInt(f[11], 0)
    root.memClock = Model.posInt(f[12], 0)
    root.gfxMaxClock = Model.posInt(f[13], 0)
    root.memMaxClock = Model.posInt(f[14], 0)
    root.vramUsed = Model.posInt(f[15], 0)
    root.vramFree = Model.posInt(f[16], 0)
    root.vramTotal = Model.posInt(f[17], 0)

    root.throttleHwSlowdown = root.boolField(f[19])
    root.throttleSwThermal = root.boolField(f[20])
    root.throttleHwThermal = root.boolField(f[21])
    root.throttleHwPowerBrake = root.boolField(f[22])
    root.throttleSyncBoost = root.boolField(f[23])
    root.throttleGpuIdle = root.boolField(f[24])
    root.pcieGen = Model.posInt(f[25], 0)
    root.pcieWidth = Model.posInt(f[26], 0)
    root.throttleActive = root.throttleHwSlowdown
      || root.throttleSwThermal
      || root.throttleHwThermal
      || root.throttleHwPowerBrake

    root.available = true
    root.firstSample = true
  }

  function parseProcesses(text) {
    var result = []
    var lines = String(text || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var line = String(lines[i]).trim()
      if (line === "") continue
      // pid, process_name, used_memory — process names can contain ", ", so
      // take the first token as pid and the last as MiB, with the middle the
      // name. No comma ever appears in a numeric pid or a "123 MiB" suffix.
      var firstSpace = line.indexOf(", ")
      var lastComma = line.lastIndexOf(", ")
      if (firstSpace < 0 || lastComma <= firstSpace) continue
      var pid = line.slice(0, firstSpace).trim()
      var mem = line.slice(lastComma + 2).trim()
      var name = line.slice(firstSpace + 2, lastComma).trim()
      result.push({
        pid: pid,
        name: name,
        memory: Model.posInt(mem, 0)
      })
    }
    root.processes = result
  }
}