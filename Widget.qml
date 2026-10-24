import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "io.github.zzhan111.mihomo"
  ipcTarget: "io.github.zzhan111.mihomo"
  manageIpc: false

  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.rgba(fg.r, fg.g, fg.b, 0.45)
  readonly property color faint: Qt.rgba(fg.r, fg.g, fg.b, 0.20)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  property var sample: null
  property double nowMs: Date.now()

  readonly property string status: computeStatus(sample, nowMs)
  readonly property int ageSeconds: Math.floor(snapshotAge(sample, nowMs))

  function snapshotAge(snapshot, now) {
    if (!snapshot || snapshot.ts === undefined || snapshot.ts === null) return -1
    var ts = Number(snapshot.ts)
    if (!isFinite(ts)) return -1
    return Math.max(0, now / 1000 - ts)
  }

  function computeStatus(snapshot, now) {
    if (!snapshot) return "starting"
    if (snapshot.ok !== true) return "offline"
    var age = snapshotAge(snapshot, now)
    return age >= 0 && age <= 8 ? "live" : "stale"
  }

  // Status has to age without waiting for another sample.
  Timer {
    interval: 1000
    running: true
    repeat: true
    onTriggered: root.nowMs = Date.now()
  }

  function formatRate(value) {
    if (value === undefined || value === null || value === "") return "—"
    var n = Number(value)
    if (!isFinite(n) || n < 0) return "—"
    if (n < 1024) return Math.round(n) + " B/s"
    if (n < 1048576) return Math.round(n / 1024) + "K/s"
    return (n / 1048576).toFixed(1) + "M/s"
  }

  function formatBytes(value) {
    if (value === undefined || value === null || value === "") return "—"
    var n = Number(value)
    if (!isFinite(n) || n < 0) return "—"
    if (n < 1024) return Math.round(n) + " B"
    var units = ["K", "M", "G", "T", "P"]
    var i = -1
    do {
      n /= 1024
      i++
    } while (n >= 1024 && i < units.length - 1)
    return n.toFixed(1) + " " + units[i] + "B"
  }

  function formatCount(value) {
    if (value === undefined || value === null || value === "") return "—"
    var n = Number(value)
    return isFinite(n) && n >= 0 ? String(Math.round(n)) : "—"
  }

  function field(value) {
    return (value === undefined || value === null || value === "") ? "—" : String(value)
  }

  function numeric(value) {
    if (value === undefined || value === null || value === "") return null
    var n = Number(value)
    return isFinite(n) ? n : null
  }

  readonly property string barLabel: {
    if (status === "starting") return "…"
    if (status === "offline") return "off"
    return formatRate(sample ? sample.down : undefined)
  }

  readonly property string barTooltip: {
    if (!sample) return "mihomo · — · —"
    if (sample.ok !== true) return "mihomo · 未连接 (" + field(sample.error) + ")"
    return "mihomo · " + field(sample.mode) + " · " + field(sample.node)
  }

  Process {
    id: watcherProc
    command: [root.watcher, "--interval", "2"]
    running: true
    stdout: SplitParser {
      onRead: function(line) { root.parseSample(line) }
    }
    stderr: SplitParser {
      onRead: function(line) {
        var text = String(line).trim()
        if (text !== "") console.warn("mihomo", text)
      }
    }
    onExited: function() { restartTimer.start() }
  }

  Timer {
    id: restartTimer
    interval: 30000
    onTriggered: {
      interval = 30000
      watcherProc.running = true
    }
  }

  readonly property string watcher: Qt.resolvedUrl("bin/mihomo-watch").toString().replace(/^file:\/\//, "")

  function parseSample(line) {
    try {
      var parsed = JSON.parse(String(line || ""))
      if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) {
        root.sample = parsed
        root.nowMs = Date.now()
      }
    } catch (e) {
      console.warn("mihomo", "bad sample line", e)
    }
  }

  function refresh() {
    restartTimer.stop()
    // A running Process cannot be re-run until the child exits; a zero-interval
    // timer makes onExited relaunch it immediately instead of after 30s.
    restartTimer.interval = 0
    if (watcherProc.running) watcherProc.running = false
    else restartTimer.start()
  }

  function stateJson() {
    var s = root.sample
    var data = {
      status: root.status,
      ok: !!(s && s.ok === true),
      mode: field(s ? s.mode : undefined),
      node: field(s ? s.node : undefined),
      up: numeric(s ? s.up : undefined),
      down: numeric(s ? s.down : undefined),
      upTotal: numeric(s ? s.upTotal : undefined),
      downTotal: numeric(s ? s.downTotal : undefined),
      conns: numeric(s ? s.conns : undefined),
      ts: numeric(s ? s.ts : undefined),
      age: root.ageSeconds >= 0 ? root.ageSeconds : null
    }
    if (root.status === "offline") data.error = field(s ? s.error : undefined)
    return JSON.stringify(data)
  }

  readonly property bool vertical: !!(bar && bar.vertical)

  implicitWidth: vertical ? (bar ? bar.barSize : Style.bar.sizeHorizontal) : row.implicitWidth
  implicitHeight: vertical ? row.implicitHeight : (bar ? bar.barSize : Style.bar.sizeHorizontal)

  Grid {
    id: row
    anchors.centerIn: parent
    columns: root.vertical ? 1 : 2
    horizontalItemAlignment: Grid.AlignHCenter
    verticalItemAlignment: Grid.AlignVCenter
    spacing: Style.space(2)

    BarIconButton {
      bar: root.bar
      text: "\u{f059f}"
      onPressed: function(buttonCode) { if (buttonCode === Qt.LeftButton) root.toggle() }
    }

    Text {
      id: barLabel
      textFormat: Text.PlainText
      text: root.barLabel
      color: root.status === "offline" ? root.urgent : root.fg
      opacity: root.status === "stale" ? 0.45 : 1.0
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      verticalAlignment: Text.AlignVCenter
    }
  }

  MouseArea {
    anchors.fill: row
    acceptedButtons: Qt.LeftButton
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.toggle()
    onEntered: if (root.bar) root.bar.showTooltip(row, root.barTooltip)
    onExited: if (root.bar) root.bar.hideTooltip(row)
  }

  KeyboardPanel {
    id: panel
    anchorItem: row
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(300))
    contentHeight: panel.fittedContentHeight(column.implicitHeight + Style.space(16), Style.space(600))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTextKey: function(t) { if (t === "r" || t === "R") root.refresh() }
    }

    Flickable {
      anchors.fill: parent
      contentWidth: width
      contentHeight: column.implicitHeight + Style.space(8)
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      flickableDirection: Flickable.VerticalFlick
      interactive: contentHeight > height

      Column {
        id: column
        x: Style.space(4)
        width: parent.width - Style.space(8)
        spacing: Style.space(6)

        Text {
          textFormat: Text.PlainText
          text: "MIHOMO"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        Rectangle { width: parent.width; height: 1; color: root.faint }

        Column {
          width: parent.width
          spacing: Style.space(3)
          DetailRow {
            label: "模式"
            value: root.field(root.sample ? root.sample.mode : undefined)
          }
          DetailRow {
            label: "当前节点"
            value: root.field(root.sample ? root.sample.node : undefined)
          }
          DetailRow {
            label: "下行"
            value: root.formatRate(root.sample ? root.sample.down : undefined)
          }
          DetailRow {
            label: "上行"
            value: root.formatRate(root.sample ? root.sample.up : undefined)
          }
          DetailRow {
            label: "累计下行"
            value: root.formatBytes(root.sample ? root.sample.downTotal : undefined)
          }
          DetailRow {
            label: "累计上行"
            value: root.formatBytes(root.sample ? root.sample.upTotal : undefined)
          }
          DetailRow {
            label: "连接数"
            value: root.formatCount(root.sample ? root.sample.conns : undefined)
          }
          DetailRow {
            label: "最后更新"
            value: root.ageSeconds >= 0 ? root.ageSeconds + " 秒前" : "—"
          }
          DetailRow {
            label: "错误"
            value: root.field(root.sample ? root.sample.error : undefined)
            alert: true
            visible: root.status === "offline"
          }
        }
      }
    }
  }

  component DetailRow: Item {
    property string label: ""
    property string value: ""
    property bool alert: false
    width: parent ? parent.width : 0
    height: visible ? Math.max(l.implicitHeight, v.implicitHeight) : 0
    Text {
      id: l
      anchors.left: parent.left
      anchors.leftMargin: Style.space(2)
      textFormat: Text.PlainText
      text: parent.label
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
    Text {
      id: v
      anchors.right: parent.right
      anchors.rightMargin: Style.space(2)
      textFormat: Text.PlainText
      text: parent.value
      color: parent.alert ? root.urgent : root.fg
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
  }

  IpcHandler {
    enabled: root.bar !== null
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): void { root.refresh() }
    function state(): string { return root.stateJson() }
  }
}
