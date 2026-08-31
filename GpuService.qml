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

  property Timer pollTimer: Timer {
    interval: root.statInterval
    running: root.enabled
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      root.tick = root.tick + 1
      root.refresh()
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