import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Passive mirror of BarWidget: it renders what the widget hands it and calls
// back for every read and write.
//
// The panel is laid out around the one thing that is always true of a macro
// tool -- you are either recording, holding a take you have not named yet, or
// looking at the ones you kept -- so the top block is whichever of those three
// applies and never all of them at once.
Panel {
  id: root
  moduleName: "io.github.hpolthof.macros"

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  // Mirrored from BarWidget, which owns every read and write.
  property var state: ({ recording: false, seconds: 0, keys: 0, pending: false, pendingKeys: 0, error: "" })
  property var rows: []
  property var problems: []
  property string fix: ""
  property string lastError: ""
  property bool busy: false
  property var shortcutProbe: ({ shortcut: "", conflict: "" })
  property bool recording: false
  property bool pending: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.45)
  readonly property color faint: Qt.darker(foreground, 1.7)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // The take that has been recorded but not yet saved. It lives here, not in
  // the widget, because it is only ever half-entered: until Save is pressed
  // there is nothing worth persisting.
  property string takeName: ""
  property string takeShortcut: ""
  property string takeSpeed: "fast"

  // At most one of these is set. Each one hands the keyboard to a field, so a
  // second would have nothing to type into.
  property string editingId: ""
  property string capturingId: ""

  property string confirmId: ""
  property string confirmName: ""
  property bool confirmOpened: false

  // The cursor runs over the primary button and then the saved macros, so the
  // panel is usable without the mouse.
  readonly property int rowCount: root.rows.length
  readonly property int cursorCount: root.rowCount + 1
  property int selectedIndex: 0
  property bool cursorActive: false

  // A field owns every key while it is up, including the ones the catcher
  // would otherwise read as navigation. The unsaved take counts: its name
  // field is a text input, and PanelKeyCatcher runs at Keys.BeforeItem, so
  // anything it recognises never reaches the field -- which took Enter, Space
  // and the letters h, j, k, l and x out of every macro name.
  readonly property bool typing: root.editingId !== "" || root.capturingId !== ""
                                 || root.confirmOpened || root.pending

  // Where the keyboard belongs right now. The panel can open on its own when
  // a recording stops, so this has to be right without a click having chosen
  // anything.
  function restoreFocus() {
    if (!root.opened || root.capturingId !== "" || root.editingId !== "") return
    if (root.pending) takeField.forceActiveFocus()
    else keyCatcher.forceActiveFocus()
  }

  function open() {
    root.controller.show()
    Qt.callLater(root.restoreFocus)
  }

  function close() {
    root.controller.hide()
    root.cursorActive = false
    root.editingId = ""
    root.capturingId = ""
    root.confirmOpened = false
    root.confirmId = ""
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  onPendingChanged: Qt.callLater(root.restoreFocus)

  function hasCursorAt(index) { return root.cursorActive && root.selectedIndex === index }

  function takeCursor(index) {
    root.selectedIndex = index
    root.cursorActive = true
  }

  function moveCursor(delta) {
    if (root.cursorCount === 0) return
    var at = root.cursorActive ? root.selectedIndex : (delta > 0 ? -1 : 0)
    root.takeCursor(((at + delta) % root.cursorCount + root.cursorCount) % root.cursorCount)
  }

  function selectedRow() {
    if (!root.cursorActive || root.selectedIndex < 1) return null
    return root.rows[root.selectedIndex - 1] || null
  }

  // ----------------------------------------------------------------- actions

  function startRecording() {
    if (root.hostWidget) root.hostWidget.startRecording()
  }

  function stopRecording() {
    if (root.hostWidget) root.hostWidget.stopRecording()
  }

  function cancelRecording() {
    if (root.hostWidget) root.hostWidget.cancelRecording()
  }

  function saveTake() {
    var name = root.takeName.trim()
    if (name === "" || !root.hostWidget) return
    root.hostWidget.saveTake(name, root.takeShortcut, root.takeSpeed)
    root.resetTake()
  }

  function discardTake() {
    if (root.hostWidget) root.hostWidget.discardTake()
    root.resetTake()
  }

  function resetTake() {
    root.takeName = ""
    root.takeShortcut = ""
    root.takeSpeed = "fast"
    root.capturingId = ""
    if (root.hostWidget) root.hostWidget.clearProbe()
  }

  function playRow(row) {
    if (!row || !root.hostWidget) return
    root.hostWidget.play(row.id)
  }

  function startEditing(id) {
    root.capturingId = ""
    root.editingId = root.editingId === id ? "" : id
  }

  function commitEdit(id, text) {
    root.editingId = ""
    var name = String(text).trim()
    if (name !== "" && root.hostWidget) root.hostWidget.rename(id, name)
    Qt.callLater(root.restoreFocus)
  }

  function startCapture(id) {
    root.editingId = ""
    root.capturingId = root.capturingId === id ? "" : id
    if (root.hostWidget) root.hostWidget.clearProbe()
  }

  // A capture that produced a usable combination. `id` is a macro id, or one
  // of two sentinels: the take that has not been saved yet, and the plugin's
  // own record key.
  function commitShortcut(id, keys) {
    root.capturingId = ""
    if (id === "pending") {
      root.takeShortcut = keys
      if (root.hostWidget) root.hostWidget.probeShortcut(keys, "")
    } else if (root.hostWidget) {
      if (id === "record") root.hostWidget.setRecordShortcut(keys)
      else root.hostWidget.setShortcut(id, keys)
      root.hostWidget.probeShortcut(keys, id)
    }
    Qt.callLater(root.restoreFocus)
  }

  function clearShortcut(id) {
    root.capturingId = ""
    if (id === "pending") root.takeShortcut = ""
    else if (root.hostWidget) {
      if (id === "record") root.hostWidget.setRecordShortcut("")
      else root.hostWidget.setShortcut(id, "")
    }
    if (root.hostWidget) root.hostWidget.clearProbe()
    Qt.callLater(root.restoreFocus)
  }

  function toggleRecordShortcut() {
    if (!root.hostWidget) return
    root.hostWidget.setRecordShortcutEnabled(root.state.recordShortcutEnabled !== true)
  }

  function toggleSpeed(row) {
    if (!row || !root.hostWidget) return
    root.hostWidget.setSpeed(row.id, row.speed === "real" ? "fast" : "real")
  }

  function askDelete(row) {
    if (!row) return
    root.confirmId = row.id
    root.confirmName = row.name
    root.confirmOpened = true
    deleteConfirm.selectedIndex = 0
  }

  function confirmDelete() {
    var id = root.confirmId
    root.confirmOpened = false
    root.confirmId = ""
    if (id !== "" && root.hostWidget) root.hostWidget.remove(id)
  }

  // Enter means "do the thing this cursor position is for".
  function activateCursor() {
    if (!root.cursorActive) return
    if (root.selectedIndex === 0) root.primary()
    else root.playRow(root.selectedRow())
  }

  // The one button whose meaning changes with the state, and the only control
  // that is always present.
  function primary() {
    if (root.recording) root.stopRecording()
    else if (!root.pending) root.startRecording()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  // A conflict warning only applies to the shortcut it was measured against.
  function conflictFor(keys) {
    if (!keys || keys === "") return ""
    if (root.shortcutProbe.shortcut !== keys) return ""
    return root.shortcutProbe.conflict || ""
  }

  // ------------------------------------------------------------- components

  component MacroRow: CursorSurface {
    id: rowSurface
    required property int rowIndex
    readonly property bool selected: root.hasCursorAt(rowIndex)

    width: parent ? parent.width : 0
    hasCursor: selected
    foreground: root.foreground
    accent: Color.accent

    onSelectedChanged: if (selected) scrollArea.ensureVisible(rowSurface)

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.NoButton
      onContainsMouseChanged: if (containsMouse) root.takeCursor(rowSurface.rowIndex)
    }
  }

  // Captures a real key combination instead of asking the user to type the
  // name of one, so what is stored is what was pressed.
  component ShortcutField: Rectangle {
    id: capture
    required property string targetId
    required property string value

    readonly property bool active: root.capturingId === capture.targetId
    readonly property string conflict: root.conflictFor(capture.value)

    // Wide enough that "Press a combination…" does not resize the row the
    // moment it is clicked, and no wider than it needs to be after that.
    implicitWidth: Math.max(Style.space(132),
                            captureRow.implicitWidth + Style.spacing.sm * 2)
    implicitHeight: Style.space(24)
    radius: Style.cornerRadius
    // A shortcut that is set reads as a key cap: filled, no outline. An empty
    // one keeps the outline, because there it marks a slot to click into
    // rather than a box drawn around something already there.
    color: capture.active ? Util.alpha(Color.accent, 0.14)
         : (capture.value !== "" ? Util.alpha(root.foreground, 0.09) : "transparent")
    border.width: capture.active || capture.conflict !== ""
                  || capture.value === "" ? 1 : 0
    border.color: capture.active ? Color.accent
                : (capture.conflict !== "" ? Color.urgent : Util.alpha(root.foreground, 0.22))

    onActiveChanged: if (capture.active) capture.forceActiveFocus()

    focus: capture.active
    Keys.onPressed: function(event) {
      if (!capture.active) return
      event.accepted = true
      if (event.key === 0x01000000) {          // Escape: leave it as it was
        root.capturingId = ""
        root.restoreFocus()
        return
      }
      // A shortcut needs a modifier, so a bare Tab could never have been
      // captured anyway -- it moves on instead of being swallowed here.
      if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
        root.capturingId = ""
        root.restoreFocus()
        return
      }
      if (event.key === 0x01000003 || event.key === 0x01000007) {
        root.clearShortcut(capture.targetId)   // Backspace or Delete: none
        return
      }
      // A modifier on its own is the first half of a combination, not one.
      if (Model.isModifierKey(event.key)) return
      var keys = Model.shortcutFrom(event.key, event.modifiers)
      if (keys !== "") root.commitShortcut(capture.targetId, keys)
    }

    Row {
      id: captureRow
      anchors.left: parent.left
      anchors.leftMargin: Style.spacing.sm
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.spacing.xs

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: Model.GLYPH.shortcut
        color: capture.active ? Color.accent : root.faint
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: capture.active ? "Press a combination…"
            : (capture.value !== "" ? capture.value : "No shortcut")
        color: capture.active ? Color.accent
             : (capture.value !== "" ? root.foreground : root.faint)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }

    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: root.startCapture(capture.targetId)
    }
  }

  component SpeedButton: PanelActionButton {
    required property string speed
    iconText: speed === "real" ? Model.GLYPH.real : Model.GLYPH.fast
    foreground: speed === "real" ? Color.accent : root.dim
    hoverColor: root.foreground
    tooltipText: speed === "real"
      ? "Replays the pauses that were recorded  ·  s"
      : "Replays as fast as is reliable  ·  s"
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: root.pending ? takeField : keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(460))
    contentHeight: panel.fittedContentHeight(contentColumn.implicitHeight, Style.space(640))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.typing
      onMoveRequested: function(dx, dy) { root.moveCursor(dx !== 0 ? dx : dy) }
      onActivateRequested: root.activateCursor()
      onDeleteRequested: root.askDelete(root.selectedRow())
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) {
        var key = String(text).toLowerCase()
        var row = root.selectedRow()
        if (key === "r" && row) root.startEditing(row.id)
        else if (key === "k" && row) root.startCapture(row.id)
        else if (key === "s" && row) root.toggleSpeed(row)
        else if (key === " ") root.primary()
      }

      Flickable {
        id: scrollArea
        anchors.fill: parent
        contentWidth: width
        contentHeight: contentColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        function ensureVisible(item) {
          if (!item) return
          var top = item.mapToItem(contentColumn, 0, 0).y
          var bottom = top + item.height
          if (top < contentY) contentY = top
          else if (bottom > contentY + height) contentY = bottom - height
        }

        Column {
          id: contentColumn
          width: scrollArea.width
          spacing: Style.spacing.sm

          PanelHero {
            width: parent.width
            title: "Macros"
            foreground: root.foreground
            fontFamily: root.fontFamily

            iconComponent: Component {
              Text {
                text: Model.GLYPH.keyboard
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
              }
            }
          }

          Item { width: 1; height: Style.spacing.md }

          // Something in the stack is missing, and nothing below will work
          // until it is fixed, so it is said here rather than on failure.
          Column {
            width: parent.width
            visible: root.problems.length > 0
            spacing: Style.spacing.xxs

            Repeater {
              model: root.problems
              delegate: Text {
                required property string modelData
                width: contentColumn.width
                text: Model.GLYPH.warn + "  " + modelData
                color: Color.urgent
                wrapMode: Text.Wrap
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
            }

            // A list of what is broken is only half an answer, and on a fresh
            // install it is the whole panel, so the command that fixes it is
            // right underneath.
            Text {
              width: contentColumn.width
              visible: root.fix !== ""
              topPadding: Style.spacing.xs
              text: "Run  " + root.fix + "  to put these in place."
              color: Util.alpha(root.foreground, 0.75)
              wrapMode: Text.Wrap
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }

          Text {
            width: parent.width
            visible: root.lastError !== ""
            text: root.lastError
            color: Color.urgent
            wrapMode: Text.Wrap
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          PanelSeparator { width: parent.width; foreground: root.foreground }

          // -------------------------------------------------- recording

          PanelSectionHeader {
            width: parent.width
            text: root.recording ? "RECORDING" : (root.pending ? "UNSAVED TAKE" : "RECORD")
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          // Idle: one button, and a word about what recording means.
          Column {
            width: parent.width
            visible: !root.recording && !root.pending
            spacing: Style.spacing.xs

            CursorSurface {
              width: parent.width
              hasCursor: root.hasCursorAt(0)
              foreground: root.foreground
              accent: Color.accent
              radius: Style.cornerRadius
              implicitHeight: startRow.implicitHeight + Style.spacing.md * 2

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onContainsMouseChanged: if (containsMouse) root.takeCursor(0)
                onClicked: root.startRecording()
              }

              Row {
                id: startRow
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Style.spacing.rowPaddingX
                spacing: Style.spacing.controlGap

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: Model.GLYPH.record
                  color: Color.urgent
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.iconLarge
                }

                Column {
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.spacing.xxs

                  Text {
                    text: "Start recording"
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                  }

                  Text {
                    text: "Every key, in any window, until you stop"
                    color: root.faint
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }
              }
            }

            // The plugin proposes a key and leaves it switched off. Being
            // installed does not entitle it to a key on the keyboard, so the
            // line says plainly that nothing is bound until the switch is on.
            Item {
              width: parent.width
              implicitHeight: Math.max(recordChip.implicitHeight,
                                       recordSwitch.implicitHeight)

              ShortcutField {
                id: recordChip
                anchors.left: parent.left
                anchors.leftMargin: Style.spacing.rowPaddingX
                anchors.verticalCenter: parent.verticalCenter
                targetId: "record"
                value: root.state.recordShortcut || ""
                opacity: root.state.recordShortcutEnabled === true ? 1 : 0.6
              }

              Text {
                anchors.left: recordChip.right
                anchors.leftMargin: Style.spacing.controlGap
                anchors.right: recordSwitch.left
                anchors.rightMargin: Style.spacing.controlGap
                anchors.verticalCenter: parent.verticalCenter
                // Short enough to survive between the chip and the switch;
                // the panel is not wide and eliding this said nothing.
                text: root.state.recordShortcutEnabled === true
                  ? "starts and stops recording"
                  : "switch on to bind it"
                color: root.state.recordShortcutEnabled === true ? root.dim : root.faint
                elide: Text.ElideRight
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              ToggleSwitch {
                id: recordSwitch
                anchors.right: parent.right
                anchors.rightMargin: Style.spacing.rowPaddingX
                anchors.verticalCenter: parent.verticalCenter
                checked: root.state.recordShortcutEnabled === true
                foreground: root.foreground
                accent: Color.accent
                onToggled: root.toggleRecordShortcut()
              }
            }

            Text {
              width: parent.width
              visible: root.conflictFor(root.state.recordShortcut || "") !== ""
              text: Model.GLYPH.warn + "  Already used by "
                    + root.conflictFor(root.state.recordShortcut || "")
              color: Color.urgent
              wrapMode: Text.Wrap
              leftPadding: Style.spacing.rowPaddingX
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          // Recording: the counter, and the two ways out of it.
          CursorSurface {
            width: parent.width
            visible: root.recording
            hasCursor: root.hasCursorAt(0)
            foreground: root.foreground
            accent: Color.accent
            radius: Style.cornerRadius
            implicitHeight: liveRow.implicitHeight + Style.spacing.md * 2

            // The two buttons anchor to the right edge and the counter fills
            // what is left, rather than both sides sharing one arithmetic
            // spacer that only holds while the numbers stay short.
            Item {
              id: liveRow
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.spacing.rowPaddingX
              anchors.rightMargin: Style.spacing.rowPaddingX
              implicitHeight: Math.max(liveInfo.implicitHeight, stopActions.implicitHeight)

              Row {
                id: liveInfo
                anchors.left: parent.left
                anchors.right: stopActions.left
                anchors.rightMargin: Style.spacing.controlGap
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.spacing.controlGap

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: Model.GLYPH.record
                  color: Color.urgent
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.iconLarge

                  SequentialAnimation on opacity {
                    running: root.recording
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.3; duration: 600 }
                    NumberAnimation { to: 1.0; duration: 600 }
                  }
                }

                Column {
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.spacing.xxs

                  Text {
                    text: Model.clock(root.state.seconds) + "  ·  "
                          + Model.keyCount(root.state.keys)
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                  }

                  Text {
                    // While recording, the key worth showing is the one
                    // that ends it -- if it was switched on.
                    text: root.state.recordShortcutEnabled === true
                          && root.state.recordShortcut
                      ? root.state.recordShortcut + " to stop  ·  10:00 max"
                      : "Everything, everywhere  ·  stops itself at 10:00"
                    color: root.faint
                    elide: Text.ElideRight
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }
              }

              Row {
                id: stopActions
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.spacing.xs

                PanelActionButton {
                  iconText: Model.GLYPH.stop
                  foreground: Color.accent
                  hoverColor: root.foreground
                  tooltipText: "Stop and keep  ·  ⏎"
                  onClicked: root.stopRecording()
                }

                PanelActionButton {
                  iconText: Model.GLYPH.discard
                  foreground: root.dim
                  hoverColor: Color.urgent
                  tooltipText: "Stop and throw away"
                  onClicked: root.cancelRecording()
                }
              }
            }
          }

          // A take in hand: name it, optionally give it a key, then keep it.
          Column {
            width: parent.width
            visible: root.pending
            spacing: Style.spacing.sm
            leftPadding: Style.spacing.rowPaddingX
            rightPadding: Style.spacing.rowPaddingX

            Text {
              width: parent.width - Style.spacing.rowPaddingX * 2
              text: Model.keyCount(root.state.pendingKeys) + " recorded. Give it a name to keep it."
              color: root.dim
              wrapMode: Text.Wrap
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            TextField {
              id: takeField
              width: parent.width - Style.spacing.rowPaddingX * 2
              foreground: root.foreground
              verticalPadding: Style.spacing.xs
              placeholderText: "What does this macro do?"
              text: root.takeName
              onTextChanged: root.takeName = text
              // The take is the only thing on screen that is not yet safe on
              // disk, so it takes the keyboard the moment it appears.
              onVisibleChanged: if (visible) { forceActiveFocus(); selectAll() }
              onAccepted: root.saveTake()
              // Escape leaves the panel; it does not throw the recording
              // away. The take survives a closed panel, and losing one to a
              // keypress meant for "get out of here" is not a fair trade --
              // the × button is the way to discard it.
              Keys.onEscapePressed: root.close()
              // Tab reaches the shortcut, which otherwise had no keyboard
              // route at all: the catcher is blocked here, so its "k" does
              // not apply, and Tab would walk out to the next bar widget.
              Keys.priority: Keys.BeforeItem
              Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
                  event.accepted = true
                  root.startCapture("pending")
                }
              }
            }

            ShortcutField {
              width: parent.width - Style.spacing.rowPaddingX * 2
              targetId: "pending"
              value: root.takeShortcut
            }

            Text {
              width: parent.width - Style.spacing.rowPaddingX * 2
              visible: root.conflictFor(root.takeShortcut) !== ""
              text: Model.GLYPH.warn + "  Already used by "
                    + root.conflictFor(root.takeShortcut)
              color: Color.urgent
              wrapMode: Text.Wrap
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            Text {
              width: parent.width - Style.spacing.rowPaddingX * 2
              text: "⏎ save   ⇥ shortcut   Esc close"
              color: root.faint
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            Row {
              spacing: Style.spacing.xs

              PanelActionButton {
                iconText: Model.GLYPH.save
                foreground: root.takeName.trim() !== "" ? Color.accent : root.faint
                hoverColor: root.foreground
                enabled: root.takeName.trim() !== "" && !root.busy
                tooltipText: "Save this macro  ·  ⏎"
                onClicked: root.saveTake()
              }

              SpeedButton {
                speed: root.takeSpeed
                onClicked: root.takeSpeed = root.takeSpeed === "real" ? "fast" : "real"
              }

              PanelActionButton {
                iconText: Model.GLYPH.discard
                foreground: root.dim
                hoverColor: Color.urgent
                tooltipText: "Throw the recording away"
                onClicked: root.discardTake()
              }
            }
          }

          // ------------------------------------------------------- saved

          PanelSeparator {
            width: parent.width
            visible: root.rowCount > 0
            foreground: root.foreground
          }

          PanelSectionHeader {
            width: parent.width
            visible: root.rowCount > 0
            text: "SAVED – " + root.rowCount
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Repeater {
            model: root.rows

            delegate: MacroRow {
              id: macroRow
              required property int index
              required property var modelData

              rowIndex: index + 1
              implicitHeight: rowContent.implicitHeight + Style.spacing.md * 2
              radius: Style.cornerRadius

              Column {
                id: rowContent
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Style.spacing.rowPaddingX
                anchors.rightMargin: Style.spacing.rowPaddingX
                spacing: Style.spacing.xs

                // What it is called, and what you can do to it.
                Item {
                  width: parent.width
                  implicitHeight: Math.max(nameHolder.implicitHeight,
                                           rowActions.implicitHeight)

                  Item {
                    id: nameHolder
                    anchors.left: parent.left
                    anchors.right: rowActions.left
                    anchors.rightMargin: Style.spacing.controlGap
                    anchors.verticalCenter: parent.verticalCenter
                    implicitHeight: root.editingId === macroRow.modelData.id
                      ? nameField.implicitHeight : nameText.implicitHeight

                    Text {
                      id: nameText
                      anchors.left: parent.left
                      anchors.right: parent.right
                      anchors.verticalCenter: parent.verticalCenter
                      visible: root.editingId !== macroRow.modelData.id
                      text: macroRow.modelData.name
                      color: root.foreground
                      elide: Text.ElideRight
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                    }

                    TextField {
                      id: nameField
                      anchors.left: parent.left
                      anchors.right: parent.right
                      anchors.verticalCenter: parent.verticalCenter
                      visible: root.editingId === macroRow.modelData.id
                      foreground: root.foreground
                      verticalPadding: Style.spacing.xs
                      placeholderText: macroRow.modelData.name
                      onVisibleChanged: {
                        if (!visible) return
                        text = macroRow.modelData.name
                        forceActiveFocus()
                        selectAll()
                      }
                      onAccepted: root.commitEdit(macroRow.modelData.id, text)
                      Keys.onEscapePressed: root.editingId = ""
                    }
                  }

                  Row {
                    id: rowActions
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.spacing.xs

                    PanelActionButton {
                      iconText: Model.GLYPH.play
                      foreground: root.dim
                      hoverColor: Color.accent
                      tooltipText: "Play it here  ·  ⏎"
                      onClicked: root.playRow(macroRow.modelData)
                    }

                    PanelActionButton {
                      iconText: Model.GLYPH.rename
                      foreground: root.editingId === macroRow.modelData.id ? Color.accent : root.dim
                      hoverColor: root.foreground
                      tooltipText: "Rename  ·  r"
                      onClicked: root.startEditing(macroRow.modelData.id)
                    }

                    SpeedButton {
                      speed: macroRow.modelData.speed
                      onClicked: root.toggleSpeed(macroRow.modelData)
                    }

                    PanelActionButton {
                      iconText: Model.GLYPH.trash
                      foreground: root.dim
                      hoverColor: Color.urgent
                      tooltipText: "Delete this macro  ·  ⌦"
                      onClicked: root.askDelete(macroRow.modelData)
                    }
                  }
                }

                // The shortcut is the one thing on the row you click into
                // rather than read, so it keeps a field of its own -- but only
                // as wide as it needs, with the size and timing sharing the
                // line and lining up under the buttons above.
                Item {
                  width: parent.width
                  implicitHeight: shortcutChip.implicitHeight

                  ShortcutField {
                    id: shortcutChip
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    targetId: macroRow.modelData.id
                    value: macroRow.modelData.shortcut
                  }

                  Text {
                    anchors.left: shortcutChip.right
                    anchors.leftMargin: Style.spacing.controlGap
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: Model.rowDetail(macroRow.modelData)
                    color: root.faint
                    elide: Text.ElideRight
                    horizontalAlignment: Text.AlignRight
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }

                Text {
                  width: parent.width
                  visible: root.conflictFor(macroRow.modelData.shortcut) !== ""
                  text: Model.GLYPH.warn + "  Also used by "
                        + root.conflictFor(macroRow.modelData.shortcut)
                  color: Color.urgent
                  wrapMode: Text.Wrap
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }
            }
          }

          Text {
            width: parent.width
            visible: root.rowCount === 0 && !root.pending
            text: "Nothing saved yet — record something and give it a name."
            color: root.dim
            wrapMode: Text.Wrap
            topPadding: Style.spacing.md
            bottomPadding: Style.spacing.md
            leftPadding: Style.spacing.rowPaddingX
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          PanelSeparator {
            width: parent.width
            visible: root.rowCount > 0
            foreground: root.foreground
          }

          Text {
            width: parent.width
            // Every key listed here acts on a saved macro, so with none saved
            // the line is a list of things that do nothing.
            visible: root.rowCount > 0
            text: "↑↓ move   ⏎ play   r rename   k shortcut   s timing   ⌦ delete"
            color: root.faint
            elide: Text.ElideRight
            topPadding: Style.spacing.xs
            leftPadding: Style.spacing.rowPaddingX
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          // Hyprland eats a combination it already has a binding for, so it
          // never reaches the capture field. Saying so up front turns a dead
          // key into information.
          Text {
            width: parent.width
            visible: root.capturingId !== ""
            text: "A combination Hyprland already uses is swallowed before it "
                + "gets here. If nothing happens, that key is taken."
            color: root.faint
            wrapMode: Text.Wrap
            topPadding: Style.spacing.xxs
            leftPadding: Style.spacing.rowPaddingX
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }
    }

    ConfirmDialog {
      id: deleteConfirm
      anchors.fill: parent
      opened: root.confirmOpened
      // Starts on Cancel: a stray Enter must never be what deletes a macro.
      selectedIndex: 0
      message: "Delete " + root.confirmName + "? The recording and its shortcut go with it."
      cancelText: "Cancel"
      confirmText: "Delete"
      foreground: root.foreground
      fontFamily: root.fontFamily
      onCanceled: { root.confirmOpened = false; root.confirmId = "" }
      onConfirmed: root.confirmDelete()
    }
  }
}
