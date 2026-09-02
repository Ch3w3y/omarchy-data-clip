import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Ui

Item {
  id: root

  property string pluginDir: Quickshell.env("HOME") + "/.config/omarchy/plugins/daryn.data-clip"
  property bool opened: false
  property int selectedIndex: 0
  property string detectedFormat: ""
  property int rowCount: 0
  property int colCount: 0
  property var options: []
  property string errorMessage: ""
  property bool copiedFlash: false

  // Theme tokens
  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color scrim: Color.menu.scrim
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  readonly property int cornerRadius: Style.cornerRadius
  property string fontFamily: Style.font.menuFamily
  property int cardWidth: Math.min(Style.space(880), panel.width - Style.gapsOut * 2)
  property int cardHeight: Math.min(Style.space(560), panel.height - Style.gapsOut * 2)

  function open(payloadJson) {
    root.opened = true
    root.errorMessage = ""
    root.copiedFlash = false
    root.selectedIndex = 0
    root.options = []

    transformProc.running = true
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.opened = false
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open("{}")
  }

  function applyAndCopy(index) {
    if (index < 0 || index >= root.options.length) return
    var opt = root.options[index]
    if (!opt || !opt.code) return

    Quickshell.execDetached(["wl-copy", "--", opt.code])
    root.copiedFlash = true
    closeTimer.start()
  }

  Timer {
    id: closeTimer
    interval: 220
    repeat: false
    onTriggered: root.close()
  }

  Process {
    id: transformProc
    command: [root.pluginDir + "/transform.py"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var res = JSON.parse(text)
          if (res.error) {
            root.errorMessage = res.error
            return
          }
          root.detectedFormat = res.format || "Tabular Text"
          root.rowCount = res.rowCount || 0
          root.colCount = res.colCount || 0
          root.options = res.options || []
        } catch (e) {
          root.errorMessage = "Failed to parse clipboard: " + e
        }
      }
    }
    onExited: function(code) {
      if (code !== 0 && !root.errorMessage) {
        root.errorMessage = "Unable to read clipboard data"
      }
    }
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-data-clip"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.close()
    }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: root.cardHeight
      radius: root.cornerRadius
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec
      padding: Style.spacing.panelPadding

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            root.close()
            event.accepted = true
          } else if (event.key >= Qt.Key_1 && event.key <= Qt.Key_6) {
            var targetIdx = event.key - Qt.Key_1
            if (targetIdx < root.options.length) {
              root.selectedIndex = targetIdx
              root.applyAndCopy(targetIdx)
              event.accepted = true
            }
          } else if (event.key === Qt.Key_Up) {
            if (root.options.length > 0) {
              root.selectedIndex = (root.selectedIndex - 1 + root.options.length) % root.options.length
            }
            event.accepted = true
          } else if (event.key === Qt.Key_Down) {
            if (root.options.length > 0) {
              root.selectedIndex = (root.selectedIndex + 1) % root.options.length
            }
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.applyAndCopy(root.selectedIndex)
            event.accepted = true
          }
        }
      }

      ColumnLayout {
        anchors.fill: parent
        spacing: Style.spacing.md

        // --- HEADER ---
        RowLayout {
          Layout.fillWidth: true
          spacing: Style.spacing.md

          Text {
            text: "📋"
            font.pixelSize: Style.font.heading * 1.2
          }

          ColumnLayout {
            spacing: 2
            Layout.fillWidth: true

            Text {
              text: "Data Science Clipboard Transformer"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.heading
              font.bold: true
            }

            Text {
              text: root.errorMessage || ("Source: " + root.detectedFormat + " • " + root.rowCount + " rows × " + root.colCount + " cols")
              color: root.errorMessage ? "#ff8888" : root.foreground
              opacity: root.errorMessage ? 1 : 0.6
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          // Close button
          Rectangle {
            width: 26
            height: 26
            radius: 13
            color: closeMouse.containsMouse ? Qt.rgba(1, 0, 0, 0.3) : "transparent"
            Text {
              anchors.centerIn: parent
              text: "✕"
              color: root.foreground
              font.pixelSize: 13
            }
            MouseArea {
              id: closeMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.close()
            }
          }
        }

        // --- MAIN TWO-COLUMN WORKSPACE ---
        RowLayout {
          Layout.fillWidth: true
          Layout.fillHeight: true
          spacing: Style.spacing.md

          // LEFT COLUMN: Format list
          ListView {
            id: optListView
            Layout.preferredWidth: 300
            Layout.fillHeight: true
            clip: true
            model: root.options
            spacing: 6

            delegate: Rectangle {
              width: optListView.width
              height: 48
              radius: root.cornerRadius / 2
              color: root.selectedIndex === index ? root.selectedBackground : (optMouse.containsMouse ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08) : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.03))

              RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 10

                // Number badge
                Rectangle {
                  width: 22
                  height: 22
                  radius: 11
                  color: root.selectedIndex === index ? Qt.rgba(0, 0, 0, 0.2) : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
                  Text {
                    anchors.centerIn: parent
                    text: modelData.key
                    color: root.selectedIndex === index ? root.selectedText : root.foreground
                    font.bold: true
                    font.pixelSize: Style.font.caption
                  }
                }

                Text {
                  text: modelData.name
                  color: root.selectedIndex === index ? root.selectedText : root.foreground
                  font.bold: root.selectedIndex === index
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  Layout.fillWidth: true
                }

                Text {
                  text: "⏎"
                  color: root.selectedIndex === index ? root.selectedText : root.foreground
                  opacity: root.selectedIndex === index ? 0.8 : 0.3
                  font.pixelSize: 12
                }
              }

              MouseArea {
                id: optMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  root.selectedIndex = index
                  root.applyAndCopy(index)
                }
              }
            }
          }

          // RIGHT COLUMN: Live Code Preview Box
          Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: root.cornerRadius / 2
            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04)
            border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
            border.width: 1

            ColumnLayout {
              anchors.fill: parent
              anchors.margins: 14
              spacing: 8

              RowLayout {
                Layout.fillWidth: true
                Text {
                  text: root.options[root.selectedIndex] ? root.options[root.selectedIndex].name + " Preview" : "Preview"
                  color: root.foreground
                  font.bold: true
                  font.pixelSize: Style.font.caption
                  Layout.fillWidth: true
                }

                Rectangle {
                  height: 24
                  width: copyPillText.implicitWidth + 16
                  radius: 12
                  color: root.copiedFlash ? "#2ecc71" : root.selectedBackground

                  Text {
                    id: copyPillText
                    anchors.centerIn: parent
                    text: root.copiedFlash ? "✓ Copied!" : "Copy & Close (Enter)"
                    color: root.selectedText
                    font.bold: true
                    font.pixelSize: Style.font.caption
                  }

                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.applyAndCopy(root.selectedIndex)
                  }
                }
              }

              ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true

                TextArea {
                  readOnly: true
                  text: root.options[root.selectedIndex] ? root.options[root.selectedIndex].code : ""
                  color: root.foreground
                  font.family: "monospace"
                  font.pixelSize: Style.font.body
                  wrapMode: Text.NoWrap
                  background: Item {}
                  selectByMouse: true
                }
              }
            }
          }
        }

        // --- FOOTER HINTS ---
        RowLayout {
          Layout.fillWidth: true
          Text {
            text: "Press 1–6 to copy instantly • ↑/↓ navigate • Enter copies selected • Esc cancels"
            color: root.foreground
            opacity: 0.5
            font.pixelSize: Style.font.caption
            Layout.fillWidth: true
          }
        }
      }
    }
  }
}
