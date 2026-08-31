import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons

// NVIDIA GPU monitor bar label — temperature + utilization by default — and
// the host for the details panel loaded from Panel.qml.
//
// Contract mirrors the built-in clock bar-widget: the Loader hosts Panel.qml,
// open/close/opened are forwarded so `omarchy-shell shell summon/hide` route
// through the bar-widget root, and the single IpcHandler lives here.
BarWidget {
  id: root
  moduleName: "vichu.gpu-monitor"

  // ---- settings (inline shell.json entry; fallback = manifest defaults) ----
  readonly property int updateIntervalMs: Math.max(500, root.setting("updateInterval", 2000))
  readonly property int tempThreshold: root.setting("tempThreshold", 80)
  readonly property int utilThreshold: root.setting("utilThreshold", 90)
  readonly property int memThreshold: root.setting("memThreshold", 90)

  // ---- data service (one per widget; bar label + panel share it) ----
  property QtObject stats: GpuService {
    id: svc
    statInterval: root.updateIntervalMs
    enabled: root.visible || (panelLoader.item && panelLoader.item.opened)
  }

  onSettingsChanged: {
    svc.statInterval = Math.max(500, root.setting("updateInterval", 2000))
    root.injectPanel()
  }

  readonly property color normalColor: root.bar ? root.bar.barForeground : Color.foreground
  readonly property color warnColor: root.bar ? root.bar.urgent : Color.urgent
  readonly property string fam: root.bar ? root.bar.fontFamily : Style.font.family

  // ---- label content ----
  readonly property string mode: String(root.setting("displayMode", "Both")).toLowerCase()
  readonly property bool showTemp: mode === "both" || mode === "temp" || mode === "t"
  readonly property bool showUtil: mode === "both" || mode === "usage" || mode === "u"

  readonly property string displayText: {
    if (!stats.available) return "GPU —"
    var parts = []
    if (showTemp) parts.push(stats.tempGpu + "°")
    if (showUtil) parts.push(stats.gpuUtil + "%")
    return parts.length > 0 ? parts.join(" ") : "GPU"
  }

  readonly property bool warnNow: stats.available
    && (stats.tempGpu >= tempThreshold || stats.gpuUtil >= utilThreshold || stats.cpuUtil >= utilThreshold)

  function refresh() {
    svc.refresh()
    svc.refreshProcesses()
    if (panelLoader.item && panelLoader.item.refresh) panelLoader.item.refresh()
  }

  readonly property string hoverText: {
    if (!stats.available) return "GPU —"
    return "GPU " + stats.tempGpu + " °C · " + stats.gpuUtil + " % · CPU " + stats.cpuUtil + " %"
  }

  // The bar's tooltip shows a snapshot copied inside showTooltip(); mutating
  // bar.tooltipText in place keeps the popup live while hovered WITHOUT the
  // clear-then-refill that showTooltip() performs (which made it blink each
  // poll). The bubble stays visible as long as tooltipText is non-empty.
  onHoverTextChanged: {
    if (button && button.tooltipHovered && root.bar)
      root.bar.tooltipText = root.hoverText
  }

  // Right-click walks the label modes, persisted to shell.json (same pattern
  // as the clock's format cycling).
  readonly property var modeRing: ["Both", "Temp", "Usage"]

  function cycleMode() {
    var current = String(root.setting("displayMode", "Both"))
    var idx = root.modeRing.indexOf(current)
    var next = root.modeRing[(idx + 1) % root.modeRing.length]

    var entry = { id: root.moduleName }
    for (var key in root.settings) if (key !== "id") entry[key] = root.settings[key]
    entry.displayMode = next

    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  // ---- panel forwarding (shape contract for shell.summon/hide/toggle) ----
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function togglePanel() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  // The open-panel dot under the slot: same width as the text label, so the
  // indicator lies centered under the widget's content rather than its box.
  readonly property real openPanelIndicatorWidth: button.labelWidth
  readonly property real openPanelIndicatorHeight: Math.max(Style.space(10), Math.round(Style.bar.iconSlot * 0.55))

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  IpcHandler {
    target: "vichu.gpu-monitor"

    function refresh(): void { root.broadcast("refresh") }
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.togglePanel() }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.displayText
    active: root.warnNow
    foreground: root.normalColor
    activeColor: root.warnColor
    fontSize: Style.font.body
    hasVisualContent: root.displayText !== ""
    tooltipText: root.hoverText

    onPressed: function(b) {
      if (b === Qt.RightButton) root.cycleMode()
      else if (b === Qt.MiddleButton) root.refresh()
      else root.togglePanel()
    }
  }
}