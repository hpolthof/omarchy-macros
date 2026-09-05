import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Bar half of the plugin. Every read and every write goes through bin/macros
// from here, and the results are mirrored into Panel.qml, which renders them
// and calls back but owns no state of its own.
//
// Nothing on a timer lives here except polling that is off unless something
// is actually happening: this component is created once per monitor, so a
// timer that always ran would run twice on a two-head setup.
BarWidget {
  id: root
  moduleName: "io.github.hpolthof.macros"

  readonly property string binPath: String(Qt.resolvedUrl("bin/macros")).replace(/^file:\/\//, "")

  // What bin/macros last said. `state` covers the recorder, `rows` the saved
  // macros, `problems` the parts of the stack that are missing.
  property var state: ({ recording: false, seconds: 0, keys: 0, pending: false, pendingKeys: 0, error: "" })
  property var rows: []
  property var problems: []
  // The one command that puts a missing stack in place. Comes from doctor so
  // the panel never has to know where the plugin was installed.
  property string fix: ""
  property string lastError: ""
  property bool busy: false

  // The answer to "is this shortcut already taken", filled in as the user
  // captures one. Kept here rather than in the panel so a reopened panel does
  // not go back to claiming a key is free.
  property var shortcutProbe: ({ shortcut: "", conflict: "" })

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool recording: root.state.recording === true
  readonly property bool pending: root.state.pending === true

  readonly property var mirroredProperties: [
    "bar", "settings", "state", "rows", "problems", "fix", "lastError", "busy",
    "shortcutProbe", "recording", "pending"
  ]

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
    for (var i = 0; i < root.mirroredProperties.length; i++) {
      var name = root.mirroredProperties[i]
      if (name in target) target[name] = root[name]
    }
  }

  // ---------------------------------------------------------------- reading

  function refreshState() {
    if (stateProc.running) return
    stateProc.command = [root.binPath, "state"]
    stateProc.running = true
  }

  function refreshList() {
    if (listProc.running) return
    listProc.command = [root.binPath, "list"]
    listProc.running = true
  }

  function refreshAll() {
    root.refreshState()
    root.refreshList()
  }

  // ---------------------------------------------------------------- writing

  // Shared path for everything that changes what `state` and `list` will say
  // next, so the panel is never left rendering the state from before a click.
  function runAction(args) {
    if (actionProc.running) return
    root.busy = true
    root.lastError = ""
    root.injectPanel()
    actionProc.command = [root.binPath].concat(args)
    actionProc.running = true
  }

  // Recording and the panel cannot share the keyboard: whatever is typed
  // while the panel has focus goes into the panel, not into the macro. So
  // starting a recording puts the panel away, and stopping brings it back
  // with the take waiting to be named.
  function startRecording() {
    root.close()
    root.runAction(["record"])
  }

  function stopRecording() {
    root.runAction(["stop"])
  }

  function cancelRecording() {
    root.runAction(["cancel"])
  }

  function saveTake(name, shortcut, speed) {
    root.runAction(["save", String(name), String(shortcut || ""), String(speed || "fast")])
  }

  function discardTake() {
    root.runAction(["discard"])
  }

  function rename(id, name) {
    root.runAction(["rename", String(id), String(name)])
  }

  function setShortcut(id, keys) {
    root.runAction(["shortcut", String(id), String(keys || "")])
  }

  // The key that starts and stops recording. It is the plugin's own binding
  // rather than any one macro's, so it lives in the plugin config and not on
  // a row.
  function setRecordShortcut(keys) {
    root.runAction(["record-shortcut", String(keys || "")])
  }

  // Choosing a combination and binding it are separate on purpose: being
  // installed does not entitle a plugin to a key on the user's keyboard.
  function setRecordShortcutEnabled(on) {
    root.runAction(["record-shortcut-enabled", on ? "true" : "false"])
  }

  function setSpeed(id, speed) {
    root.runAction(["speed", String(id), String(speed)])
  }

  function remove(id) {
    root.runAction(["delete", String(id)])
  }

  // Playback types into whatever has focus, so the panel gets out of the way
  // first. bin/macros waits out its own lead-in before the first key, which
  // is also what gives a shortcut-triggered playback time to see the
  // modifiers released.
  function play(id) {
    if (playProc.running) return
    root.close()
    root.lastError = ""
    playProc.command = [root.binPath, "play", String(id)]
    playProc.running = true
  }

  function probeShortcut(keys, id) {
    if (probeProc.running) return
    probeProc.command = [root.binPath, "check-shortcut", String(keys || ""), String(id || "")]
    probeProc.running = true
  }

  function clearProbe() {
    root.shortcutProbe = ({ shortcut: "", conflict: "" })
    root.injectPanel()
  }

  // -------------------------------------------------------------- lifecycle

  function open() {
    if (panelLoader.item) panelLoader.item.open()
    root.refreshAll()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  // One click on the bar does the obvious next thing rather than always the
  // same thing: stop a running recording, name a take that is waiting, or
  // otherwise show the list.
  function primaryAction() {
    if (root.recording) root.stopRecording()
    else root.toggle()
  }

  Component.onCompleted: {
    doctorProc.command = [root.binPath, "doctor"]
    doctorProc.running = true
    root.refreshAll()
  }
  onBarChanged: root.injectPanel()
  onSettingsChanged: root.injectPanel()
  onOpenedChanged: if (root.opened) root.refreshAll()

  Process {
    id: stateProc
    property string outText: ""
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: stateProc.outText = text }
    onExited: function(code) {
      if (code === 0) {
        var next = Model.parse(stateProc.outText, null)
        if (next) {
          var wasPending = root.state.pending === true
          root.state = next
          // A recording that has just stopped leaves a take behind. Bringing
          // the panel up here means the stop can come from the bar, an IPC
          // call or a keybinding and still land on the same screen.
          if (next.pending === true && !wasPending && !root.opened) root.open()
        }
      }
      stateProc.outText = ""
      root.injectPanel()
    }
  }

  Process {
    id: listProc
    property string outText: ""
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: listProc.outText = text }
    onExited: function(code) {
      if (code === 0) root.rows = Model.parse(listProc.outText, [])
      listProc.outText = ""
      root.injectPanel()
    }
  }

  Process {
    id: doctorProc
    property string outText: ""
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: doctorProc.outText = text }
    onExited: function() {
      var result = Model.parse(doctorProc.outText, null)
      root.problems = result && result.problems ? result.problems : []
      root.fix = result && result.fix ? String(result.fix) : ""
      doctorProc.outText = ""
      root.injectPanel()
    }
  }

  Process {
    id: actionProc
    property string errText: ""
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true; onStreamFinished: actionProc.errText = text }
    onExited: function(code) {
      if (code !== 0) root.lastError = Model.clean(actionProc.errText) || "that did not work"
      actionProc.errText = ""
      root.busy = false
      root.refreshAll()
    }
  }

  Process {
    id: playProc
    property string errText: ""
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true; onStreamFinished: playProc.errText = text }
    onExited: function(code) {
      if (code !== 0) root.lastError = Model.clean(playProc.errText) || "playback failed"
      playProc.errText = ""
      root.injectPanel()
    }
  }

  Process {
    id: probeProc
    property string outText: ""
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: probeProc.outText = text }
    onExited: function(code) {
      if (code === 0)
        root.shortcutProbe = Model.parse(probeProc.outText, ({ shortcut: "", conflict: "" }))
      probeProc.outText = ""
      root.injectPanel()
    }
  }

  // Off unless there is something to watch: a running recording, whose
  // counter is the whole point, or an open panel.
  Timer {
    interval: root.recording ? 500 : 3000
    repeat: true
    running: root.recording || root.opened
    onTriggered: root.refreshState()
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      // `bar` and `settings` are injected by the host and can land after this.
      Qt.callLater(root.injectPanel)
    }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  IpcHandler {
    target: "io.github.hpolthof.macros"
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function record(): void { root.startRecording() }
    function stop(): void { root.stopRecording() }
    // One key for both halves of a recording, which is how a macro gets
    // recorded without the bar being clicked in the middle of it.
    function toggleRecording(): void {
      if (root.recording) root.stopRecording()
      else root.startRecording()
    }
    function play(id: string): void { root.play(id) }
    function refresh(): void { root.refreshAll() }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.recording ? Model.GLYPH.record
        : (root.pending ? Model.GLYPH.save : Model.GLYPH.keyboard)
    fontSize: Style.font.icon
    // Recording is the one state that has to be impossible to miss, so it
    // takes the urgent colour and pulses; a waiting take only tints.
    active: root.recording || root.problems.length > 0
    dimmed: !root.recording && !root.pending && root.rows.length === 0
    tooltipText: root.lastError !== ""
      ? root.lastError
      : Model.tooltip(root.state, root.rows, root.problems)
    onPressed: function(mouseButton) {
      if (mouseButton === Qt.RightButton) {
        if (root.recording) root.cancelRecording()
        else root.startRecording()
        return
      }
      root.primaryAction()
    }

    SequentialAnimation {
      running: root.recording
      loops: Animation.Infinite
      onStopped: button.opacity = 1
      NumberAnimation { target: button; property: "opacity"; to: 0.35; duration: 600; easing.type: Easing.InOutQuad }
      NumberAnimation { target: button; property: "opacity"; to: 1.0; duration: 600; easing.type: Easing.InOutQuad }
    }
  }
}
