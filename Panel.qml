import QtQuick
import Quickshell
import qs.Ui
import qs.Commons
import "Model.js" as Model

// GPU Monitor details panel: utilization / temperature / VRAM / clocks / power
// / fan tiles, a VRAM bar, throttling reasons, and processes using the GPU.
//
// Loaded by BarWidget.qml as its nested popup (single bar-widget contract, no
// separate panel kind). It shares the widget's GpuService instance through the
// hostWidget, and only creates a private, idle service when instantiated bare
// (e.g. while the bar is still injecting itself).
Panel {
  id: root
  moduleName: "vichu.gpu-monitor"
  ipcTarget: "vichu.gpu-monitor"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  // The bar tracks the widget mounted in its slot — BarWidget.qml — not this
  // nested panel, so everything the bar identifies a panel by uses barIdentity.
  property QtObject stats: hostWidget && "stats" in hostWidget ? hostWidget.stats : fallbackStats

  // Private fallback service for bare instantiation (while the bar is still
  // injecting itself into the panel). Never polls; the bar's own service
  // instance is what feeds render in practice.
  GpuService {
    id: fallbackStats
    enabled: false
  }

  readonly property color contentForeground: root.barForeground
  readonly property string contentFontFamily: root.bar ? root.bar.fontFamily : Style.font.family

  function open() {
    root.refresh()
    root.controller.show()
  }

  function close() {
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function refresh() {
    if (stats.refresh) stats.refresh()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  readonly property int tempThreshold: root.setting("tempThreshold", 80)
  readonly property int utilThreshold: root.setting("utilThreshold", 90)
  readonly property int memThreshold: root.setting("memThreshold", 90)

  readonly property color warnColor: root.bar ? root.bar.urgent : Color.urgent
  readonly property color accentColor: Color.accent

  readonly property bool tempWarn: stats.tempGpu >= tempThreshold
  readonly property bool utilWarn: stats.gpuUtil >= utilThreshold
  readonly property bool memWarn: stats.vramPct >= memThreshold

  onOpenedChanged: if (root.opened) root.refresh()

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: false
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(470))
    contentHeight: panel.fittedContentHeight(panelColumn.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      // Read-only panel: arrow keys just scroll, Escape closes, Tab hops to
      // the neighboring panel. A wheel or scrollbar does the rest.
      onMoveRequested: function(dx, dy) {
        if (dy !== 0) scrollArea.contentY = Math.max(0, Math.min(scrollArea.contentHeight - scrollArea.height, scrollArea.contentY + dy * Style.space(28)))
      }
      onActivateRequested: { /* no action for a read-only panel */ }
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "g" || t === "G" || t === "r" || t === "R") root.refresh()
      }

      Flickable {
        id: scrollArea
        anchors.fill: parent
        contentWidth: width
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: panelColumn.implicitHeight > height || panelColumn.implicitWidth > width

        Column {
          id: panelColumn
          width: parent.width
          spacing: Style.space(14)

          // ---------- Hero: GPU chip · name / driver ----------
          PanelHero {
            width: parent.width
            title: stats.available ? stats.gpuName : "GPU"
            meta: stats.available ? (stats.driver + " · " + stats.pstate) : "no NVIDIA GPU detected"
            detail: stats.available ? stats.pstate : ""
            foreground: root.contentForeground
            fontFamily: root.contentFontFamily

            iconComponent: Component {
              Text {
                readonly property bool hot: stats.available && (root.tempWarn || root.utilWarn)
                text: ""  // fa-microchip
                color: hot ? root.warnColor : root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.display
                anchors.verticalCenter: parent ? parent.verticalCenter : undefined
              }
            }
          }

          PanelSeparator { foreground: root.contentForeground }

          // ---------- Stat tiles ----------
          Grid {
            id: statGrid
            width: parent.width
            columns: 4
            spacing: Style.space(8)

            readonly property real cellWidth: (width - spacing * (columns - 1)) / columns

            StatTile {
              width: statGrid.cellWidth
              label: "UTILIZATION"
              value: stats.gpuUtil + " %"
              sub: "mem " + stats.memUtil + " %"
              warn: root.utilWarn
              foreground: root.contentForeground
              warnColor: root.warnColor
              fontFamily: root.contentFontFamily
            }
            StatTile {
              width: statGrid.cellWidth
              label: "TEMPERATURE"
              value: stats.tempGpu + " °C"
              sub: "pstate " + stats.pstate
              warn: root.tempWarn
              foreground: root.contentForeground
              warnColor: root.warnColor
              fontFamily: root.contentFontFamily
            }
            StatTile {
              width: statGrid.cellWidth
              label: "FAN SPEED"
              value: stats.fanSpeed > 0 ? stats.fanSpeed + " %" : "off"
              sub: stats.fanSpeed > 0 ? "cooling" : "stopped · 0-rpm"
              foreground: root.contentForeground
              warnColor: root.warnColor
              fontFamily: root.contentFontFamily
            }
            StatTile {
              width: statGrid.cellWidth
              label: "VRAM"
              value: Model.mibAlloc(stats.vramUsed)
              sub: "of " + Model.mibAlloc(stats.vramTotal)
              warn: root.memWarn
              foreground: root.contentForeground
              warnColor: root.warnColor
              fontFamily: root.contentFontFamily
            }
            StatTile {
              width: statGrid.cellWidth
              label: "POWER"
              value: Model.watts(stats.powerDraw)
              sub: "limit " + Model.watts(stats.powerLimit)
              foreground: root.contentForeground
              warnColor: root.warnColor
              fontFamily: root.contentFontFamily
            }
            StatTile {
              width: statGrid.cellWidth
              label: "GRAPHICS CLOCK"
              value: Model.speedMhz(stats.gfxClock)
              sub: "max " + Model.speedMhz(stats.gfxMaxClock)
              warn: root.utilWarn
              foreground: root.contentForeground
              warnColor: root.warnColor
              fontFamily: root.contentFontFamily
            }
            StatTile {
              width: statGrid.cellWidth
              label: "MEMORY CLOCK"
              value: Model.speedMhz(stats.memClock)
              sub: "max " + Model.speedMhz(stats.memMaxClock)
              foreground: root.contentForeground
              warnColor: root.warnColor
              fontFamily: root.contentFontFamily
            }
            StatTile {
              width: statGrid.cellWidth
              label: "PCIE LINK"
              value: "x" + stats.pcieWidth
              sub: "gen " + stats.pcieGen
              foreground: root.contentForeground
              warnColor: root.warnColor
              fontFamily: root.contentFontFamily
            }
          }

          // ---------- Throttling ----------
          Column {
            width: parent.width
            spacing: Style.space(8)

            PanelSectionHeader {
              text: "THROTTLING"
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
            }

            Row {
              width: parent.width
              spacing: Style.space(6)

              ThrottleChip { text: "HW SLOWDOWN"; active: stats.throttleHwSlowdown; chipForeground: root.contentForeground; chipBackground: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.06); accentColor: root.accentColor; warnColor: root.warnColor; fontFamily: root.contentFontFamily }
              ThrottleChip { text: "SW THERMAL"; active: stats.throttleSwThermal; chipForeground: root.contentForeground; chipBackground: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.06); accentColor: root.accentColor; warnColor: root.warnColor; fontFamily: root.contentFontFamily }
              ThrottleChip { text: "HW THERMAL"; active: stats.throttleHwThermal; chipForeground: root.contentForeground; chipBackground: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.06); accentColor: root.accentColor; warnColor: root.warnColor; fontFamily: root.contentFontFamily }
              ThrottleChip { text: "POWER BRAKE"; active: stats.throttleHwPowerBrake; chipForeground: root.contentForeground; chipBackground: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.06); accentColor: root.accentColor; warnColor: root.warnColor; fontFamily: root.contentFontFamily }
            }

            Text {
              visible: stats.available && !stats.throttleActive
              text: "No slowdown — clocks are running freely. (GPU has idled to a lower state.)"
              color: Qt.darker(root.contentForeground, 1.4)
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
              width: parent.width
            }
          }

          // ---------- GPU processes ----------
          Column {
            width: parent.width
            spacing: Style.space(6)

            Item {
              width: parent.width
              height: procHeader.implicitHeight

              PanelSectionHeader {
                id: procHeader
                text: "GPU PROCESSES"
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                text: stats.processes.length + (stats.processes.length === 1 ? " process" : " processes")
                color: Qt.darker(root.contentForeground, 1.4)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.caption
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            Rectangle {
              visible: stats.processes.length === 0
              width: parent.width
              implicitHeight: Math.max(Style.space(30), emptyProcText.implicitHeight + Style.space(16))
              radius: Style.cornerRadius
              color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.05)

              Text {
                id: emptyProcText
                anchors.centerIn: parent
                text: stats.available ? "No compute workloads on the GPU." : "No GPU available."
                color: Qt.darker(root.contentForeground, 1.4)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.caption
              }
            }

            Repeater {
              model: stats.processes

              Row {
                required property var modelData
                width: parent ? parent.width : 0
                spacing: Style.space(10)

                Rectangle {
                  id: pidBadge
                  width: Math.max(Style.space(56), Style.space(10) + pidText.implicitWidth + Style.space(10))
                  height: Style.space(20)
                  radius: Style.cornerRadius
                  color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.06)

                  Text {
                    id: pidText
                    anchors.centerIn: parent
                    text: modelData.pid
                    color: Qt.darker(root.contentForeground, 1.25)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                  }
                }

                Text {
                  text: modelData.name
                  elide: Text.ElideMiddle
                  width: Math.max(0, parent.width - pidBadge.width - Style.space(10) - memText.implicitWidth - Style.space(10))
                  color: root.contentForeground
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.body
                  anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                  id: memText
                  text: Model.mibAlloc(modelData.memory)
                  color: Qt.darker(root.contentForeground, 1.4)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.body
                  anchors.verticalCenter: parent.verticalCenter
                }
              }
            }
          }

          PanelSeparator { foreground: root.contentForeground }

          // ---------- Footer ----------
          Text {
            text: "via nvidia-smi · driver " + (stats.driver || "—") + " · updated every " + Math.round(root.setting("updateInterval", 2000) / 1000) + " s"
            color: Qt.darker(root.contentForeground, 1.6)
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
            width: parent.width
          }

          Item {
            width: parent.width
            height: Style.space(4)
          }
        }
      }
    }
  }

  component StatTile: Column {
    id: tile
    required property string label
    required property string value
    required property string sub
    property bool warn: false
    property color foreground: Color.foreground
    property color warnColor: Color.urgent
    property string fontFamily: Style.font.family

    spacing: Style.space(1)

    Text {
      text: tile.label
      color: Qt.darker(tile.foreground, 1.4)
      font.family: tile.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
      height: implicitHeight
    }

    Text {
      text: tile.value
      color: tile.warn ? tile.warnColor : tile.foreground
      font.family: tile.fontFamily
      font.pixelSize: Style.font.title
      font.bold: true
      height: implicitHeight
    }

    Text {
      text: tile.sub
      color: Qt.darker(tile.foreground, 1.45)
      font.family: tile.fontFamily
      font.pixelSize: Style.font.caption
      height: implicitHeight
    }
  }

  component ThrottleChip: Row {
    id: chip
    required property string text
    property bool active: false
    property color chipForeground: Color.foreground
    property color chipBackground: Color.background
    property color accentColor: Color.accent
    property color warnColor: Color.urgent
    property string fontFamily: Style.font.family

    spacing: Style.space(4)

    Rectangle {
      id: chipDot
      width: Style.space(6)
      height: Style.space(6)
      radius: width / 2
      anchors.verticalCenter: parent.verticalCenter
      color: chip.active ? chip.warnColor : Qt.darker(chip.chipForeground, 1.7)
    }

    Text {
      text: chip.text
      color: chip.active ? chip.chipForeground : Qt.darker(chip.chipForeground, 1.7)
      font.family: chip.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: chip.active
      anchors.verticalCenter: parent.verticalCenter
    }
  }
}