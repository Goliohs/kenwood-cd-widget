pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects

Item {
    id: root

    property int cellCount: 20
    property int cellPixelSize: 22
    property string text: ""
    property bool running: false
    property color segmentColor: "#00FFFF"
    property color ghostColor: "#003333"
    property color bgColor: "#000000"

    readonly property real _cellW: cellPixelSize * 0.68  // 14-seg approx aspect
    readonly property real _cellGap: 1.5

    // Precompute the padded string that will scroll through the window
    property string _scrollText: ""
    property int _charIndex: 0
    property real _subStep: 0

    // Build initial scroll text: pad with spaces on both sides for entry/exit
    function _buildScrollText() {
        var s = text.trim()
        if (s.length === 0) { _scrollText = ""; return }
        // Pad left: cellCount spaces so text enters from right
        // Pad right: cellCount spaces so text exits fully
        var pad = " ".repeat(cellCount)
        _scrollText = pad + s + "  " + pad
    }

    Component.onCompleted: _buildScrollText()
    onTextChanged: _buildScrollText()

    // Timer for discrete character-step scrolling (like real dot-matrix)
    Timer {
        id: stepTimer
        interval: 420  // ms per character step — slower, more readable
        running: root.running && _scrollText.length > cellCount
        repeat: true
        onTriggered: {
            if (root._charIndex < root._scrollText.length - cellCount) {
                root._charIndex++
            } else {
                // Loop: restart after brief pause
                root._charIndex = 0
            }
        }
    }

    // When stopped, slowly return to start (or stay at 0)
    Connections {
        target: root
        function onRunningChanged() {
            if (!running) {
                stepTimer.stop()
                // Optionally animate back to 0
            } else {
                stepTimer.start()
            }
        }
    }

    // Render the visible window of characters
    Row {
        anchors.centerIn: parent
        spacing: _cellGap

        Repeater {
            model: cellCount
            Item {
                required property int index
                width: root._cellW
                height: cellPixelSize

                // Character at position _charIndex + index in the scroll buffer
                property int _srcIdx: root._charIndex + index
                property string _ch: (_srcIdx >= 0 && _srcIdx < root._scrollText.length)
                    ? root._scrollText[_srcIdx] : " "

                // Ghost "8" behind + active char on top
                Text {
                    anchors.centerIn: parent
                    text: "8"
                    color: root.ghostColor
                    font.family: "DSEG14 Classic"
                    font.pixelSize: root.cellPixelSize
                    font.bold: true
                }
                Text {
                    anchors.centerIn: parent
                    text: parent._ch
                    color: root.segmentColor
                    font.family: "DSEG14 Classic"
                    font.pixelSize: root.cellPixelSize
                    font.bold: true
                    layer.enabled: true
                    layer.effect: MultiEffect {
                        shadowEnabled: true
                        shadowColor: Qt.rgba(root.segmentColor.r, root.segmentColor.g, root.segmentColor.b, 0.85)
                        shadowOpacity: 0.75
                        shadowBlur: 0.85
                        shadowHorizontalOffset: 0
                        shadowVerticalOffset: 0
                        shadowScale: 1.35
                        brightness: 0.15
                        contrast: 0.08
                    }
                }
            }
        }
    }
}