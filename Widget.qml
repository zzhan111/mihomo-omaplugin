import QtQuick
import QtQuick.Controls
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

  readonly property string statusText: {
    if (status === "starting") return "启动中"
    if (status === "offline") return "离线"
    if (status === "stale") return "数据过期"
    return "实时"
  }

  readonly property string statusDetail: {
    if (status === "starting") return "启动中 · 等待第一个采样"
    if (status === "offline") return "离线"
    if (ageSeconds < 0) return statusText
    return statusText + " · " + ageSeconds + " 秒前"
  }

  readonly property color statusColor: status === "offline" ? urgent : (status === "live" ? fg : dim)

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

  readonly property string toggler: Qt.resolvedUrl("bin/mihomo-toggle").toString().replace(/^file:\/\//, "")
  property bool toggleBusy: false
  property string busyAction: ""
  property string toggleError: ""
  property string toggleNotice: ""
  property bool toggleResultSeen: false

  readonly property string sampleMode: sample && sample.mode !== undefined && sample.mode !== null ? String(sample.mode) : ""
  readonly property string sampleNode: sample ? field(sample.node) : "—"
  readonly property bool directMode: sampleMode === "direct"
  readonly property string nodeTarget: sampleNode === "hy2-154" ? "Enet-FB" : "hy2-154"
  readonly property string modeTarget: sampleMode === "global" ? "rule" : "global"
  readonly property bool actionsReady: status === "live" && !toggleBusy
  readonly property bool nodeActionEnabled: actionsReady && !directMode
  readonly property bool modeActionEnabled: actionsReady
  onNodeActionEnabledChanged: if (!nodeActionEnabled && root.opened) keyCatcher.forceActiveFocus()
  onModeActionEnabledChanged: if (!modeActionEnabled && root.opened) keyCatcher.forceActiveFocus()

  readonly property string nodeButtonText: {
    if (toggleBusy && busyAction === "node") return "节点：切换中…"
    if (!sample) return "节点：等待状态"
    if (status === "offline") return "节点：状态离线"
    if (directMode) return "节点：direct 模式不可切换"
    return "节点：当前 " + sampleNode + " → " + nodeTarget
  }

  readonly property string modeButtonText: {
    if (toggleBusy && busyAction === "mode") return "模式：切换中…"
    if (!sample) return "模式：等待状态"
    if (status === "offline") return "模式：状态离线"
    return "模式：当前 " + field(sampleMode) + " → " + modeTarget
  }

  Process {
    id: toggleProc
    stdout: SplitParser {
      onRead: function(line) {
        try {
          var parsed = JSON.parse(String(line || ""))
          if (parsed && parsed.ok === true) {
            root.toggleResultSeen = true
            root.toggleError = ""
            var from = root.field(parsed.from)
            var to = root.field(parsed.to)
            if (String(parsed.action) === "node") root.toggleNotice = "已切换节点：" + from + " → " + to
            else if (String(parsed.action) === "mode") root.toggleNotice = "已切换模式：" + from + " → " + to
            else root.toggleNotice = "切换完成：" + from + " → " + to
            root.refresh()
          } else if (parsed && parsed.error) {
            root.toggleResultSeen = true
            root.toggleError = String(parsed.error)
          }
        } catch (e) {
          console.warn("mihomo", "bad toggle line", e)
        }
      }
    }
    stderr: SplitParser {
      onRead: function(line) {
        var text = String(line).trim()
        if (text !== "") console.warn("mihomo", text)
      }
    }
    onExited: function(code) {
      var action = root.busyAction
      root.toggleBusy = false
      root.busyAction = ""
      if (!root.toggleResultSeen) {
        var prefix = action === "node" ? "节点" : (action === "mode" ? "模式" : "操作")
        root.toggleError = prefix + "切换失败（退出码 " + code + "）"
      } else if (code !== 0 && root.toggleError === "") {
        root.toggleError = "切换异常（退出码 " + code + "）"
      }
    }
  }

  function runToggle(action) {
    if (root.toggleBusy) return
    if (action === "node" && !root.nodeActionEnabled) return
    if (action === "mode" && !root.modeActionEnabled) return
    root.toggleBusy = true
    root.busyAction = action
    root.toggleError = ""
    root.toggleNotice = ""
    root.toggleResultSeen = false
    if (root.opened) keyCatcher.forceActiveFocus()
    toggleProc.command = [root.toggler, action]
    toggleProc.running = true
  }

  function toggleNode() { root.runToggle("node") }
  function toggleMode() { root.runToggle("mode") }

  function moveButtonFocus(direction) {
    var list = []
    if (nodeButton.enabled) list.push(nodeButton)
    if (modeButton.enabled) list.push(modeButton)
    if (list.length === 0) {
      keyCatcher.forceActiveFocus()
      return
    }
    var index = -1
    for (var i = 0; i < list.length; i++) {
      if (list[i].activeFocus) {
        index = i
        break
      }
    }
    var next
    if (index < 0) next = direction > 0 ? 0 : list.length - 1
    else next = (index + direction + list.length) % list.length
    list[next].forceActiveFocus()
  }

  function activateFocusedButton() {
    if (nodeButton.activeFocus) root.toggleNode()
    else if (modeButton.activeFocus) root.toggleMode()
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
      onTabRequested: function(direction) { root.moveButtonFocus(direction) }
      onActivateRequested: root.activateFocusedButton()
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

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: "状态：" + root.statusDetail
          color: root.statusColor
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
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
            label: root.sample && root.sample.mode === "rule" ? "默认组节点" : "当前节点"
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
            wrapValue: true
            visible: root.status === "offline"
          }
        }

        Rectangle { width: parent.width; height: 1; color: root.faint }

        Column {
          width: parent.width
          spacing: Style.space(2)
          Button {
            id: nodeButton
            Keys.forwardTo: [keyCatcher]
            width: parent.width
            leftAlign: true
            bordered: true
            focusable: true
            enabled: root.nodeActionEnabled
            opacity: enabled ? 1.0 : 0.45
            text: root.nodeButtonText
            fontSize: Style.font.bodySmall
            fontFamily: root.fontFamily
            foreground: root.fg
            onClicked: root.toggleNode()
          }
          Button {
            id: modeButton
            Keys.forwardTo: [keyCatcher]
            width: parent.width
            leftAlign: true
            bordered: true
            focusable: true
            enabled: root.modeActionEnabled
            opacity: enabled ? 1.0 : 0.45
            text: root.modeButtonText
            fontSize: Style.font.bodySmall
            fontFamily: root.fontFamily
            foreground: root.fg
            onClicked: root.toggleMode()
          }
        }

        Text {
          visible: root.sample !== null && root.sample.mode === "rule"
          width: parent.width
          textFormat: Text.PlainText
          text: "rule 模式的节点取默认组「🚀 节点选择」，其他规则可能走别的组。"
          color: root.dim
          wrapMode: Text.Wrap
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        Text {
          visible: root.sample !== null && root.sample.mode === "direct"
          width: parent.width
          textFormat: Text.PlainText
          text: "direct 模式不使用节点选择，节点按钮不可用。"
          color: root.dim
          wrapMode: Text.Wrap
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        Text {
          visible: root.toggleNotice !== ""
          width: parent.width
          wrapMode: Text.Wrap
          textFormat: Text.PlainText
          text: root.toggleNotice
          color: root.fg
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        Text {
          visible: root.toggleError !== ""
          width: parent.width
          wrapMode: Text.Wrap
          textFormat: Text.PlainText
          text: root.toggleError
          color: root.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
      }
    }
  }

  component DetailRow: Item {
    property string label: ""
    property string value: ""
    property bool alert: false
    property bool wrapValue: false
    width: parent ? parent.width : 0
    height: visible ? Math.max(l.implicitHeight, v.implicitHeight) : 0
    Text {
      id: l
      anchors.left: parent.left
      anchors.leftMargin: Style.space(2)
      width: Math.min(implicitWidth, parent.width * 0.45)
      elide: Text.ElideRight
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
      width: Math.max(0, parent.width - l.width - Style.space(8))
      textFormat: Text.PlainText
      text: parent.value
      wrapMode: parent.wrapValue ? Text.Wrap : Text.NoWrap
      maximumLineCount: parent.wrapValue ? 4 : 1
      elide: Text.ElideRight
      horizontalAlignment: parent.wrapValue ? Text.AlignLeft : Text.AlignRight
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
    function toggleNode(): void { root.toggleNode() }
    function toggleMode(): void { root.toggleMode() }
    function uiState(): string { return JSON.stringify({opened:root.opened,ready:root.actionsReady,nodeEnabled:nodeButton.enabled,nodeFocus:nodeButton.activeFocus,modeFocus:modeButton.activeFocus,keyFocus:keyCatcher.activeFocus,busy:root.toggleBusy,error:root.toggleError,notice:root.toggleNotice}) }
    function state(): string { return root.stateJson() }
  }
}
