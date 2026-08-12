pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import "../../"
import "../CdPlayer"
import "../Shared"

Item {
    id: root

    implicitWidth: 400
    implicitHeight: 340

    readonly property bool _hasCd: CdPlayerService.cdState === "audio-cd"
    readonly property bool _isPlaying: CdPlayerService.state === "playing"
    readonly property int _track: CdPlayerService.trackNum
    readonly property string _posStr:    CdPlayerService.posStr
    readonly property string _totalStr:   CdPlayerService.totalStr
    readonly property string _displayLine: CdPlayerService.displayLine
    readonly property string _clockStr:   CdPlayerService.clockStr
    readonly property color _seg:   CdPlayerService.colLcdSeg
    readonly property color _dim:   CdPlayerService.colLcdDim
    readonly property color _bg:    CdPlayerService.colLcdBg
    readonly property color _ghost: CdPlayerService.colLcdGhost

    readonly property real _hdr: 38
    readonly property real _eqH: 200
    readonly property real _ctrl: 36
    readonly property real _bezel: 8
    readonly property real _ctrlGap: 6    // visible gap so buttons look like physical outside-LCD controls

    // Bezel piano-black
    Rectangle {
        anchors.fill: parent
        radius: 8
        color: "#0a0a0a"
        border.color: "#202020"
        border.width: 1
    }

    // LCD cutout — fills everything except the bottom control strip
    Rectangle {
        id: lcdFrame
        anchors.fill: parent
        anchors.margins: root._bezel
        anchors.bottomMargin: root._ctrl + root._ctrlGap + root._bezel
        radius: 4
        color: "#000000"
        clip: true

        // InnerShadow tunnel via MultiEffect (large soft blur inward shadow)
        // Implemented as inverted glow on overlay below:
        Rectangle {
            id: tunnelShadow
            anchors.fill: parent
            color: "transparent"
            z: 10
            layer.enabled: true
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: "#000000"
                shadowOpacity: 0.85
                shadowBlur: 1.0
                shadowHorizontalOffset: 0
                shadowVerticalOffset: 0
                shadowScale: 1.18
                brightness: -0.18
                contrast: 0.10
            }
            Rectangle {
                anchors.fill: parent
                color: root._bg
                opacity: 0.0   // visible only via shadow layer
            }
        }

        // Glass overlay — subtle dark-blue tint over the whole display, 3-5% opacity
        // simulating the front polarizer/lens unification
        Rectangle {
            anchors.fill: parent
            z: 11
            color: "transparent"
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(0.03, 0.06, 0.10, 0.045) }
                GradientStop { position: 0.5; color: Qt.rgba(0.02, 0.04, 0.07, 0.035) }
                GradientStop { position: 1.0; color: Qt.rgba(0.01, 0.03, 0.05, 0.050) }
            }
        }

        // Main content
        Column {
            anchors.fill: parent
            z: 30
            spacing: 0

            // ───────────── HEADER ─────────────
            Item {
                id: header
                width: parent.width
                height: root._hdr

                // LEFT group — clock + source + play pip
                Row {
                    id: hdrLeft
                    anchors.left: parent.left
                    anchors.leftMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 18

                    // Clock — ghost "88:88" + active
                    Item {
                        width: 60
                        height: 26
                        anchors.verticalCenter: parent.verticalCenter

                        Text {
                            anchors.centerIn: parent
                            text: "88:88"
                            color: root._ghost
                            font.family: CdPlayerService.fontSegment7
                            font.pixelSize: 22
                            font.bold: true
                        }
                        Text {
                            anchors.centerIn: parent
                            text: root._clockStr
                            color: root._seg
                            font.family: CdPlayerService.fontSegment7
                            font.pixelSize: 22
                            font.bold: true
                            layer.enabled: true
                            layer.effect: MultiEffect {
                                shadowEnabled: true
                                shadowColor: Qt.rgba(root._seg.r, root._seg.g, root._seg.b, 0.85)
                                shadowOpacity: 0.45
                                shadowBlur: 0.6
                            }
                        }
                    }

                    // Source — CD / MD / FM (only CD wired)
                    Item {
                        width: 28
                        height: 16
                        anchors.verticalCenter: parent.verticalCenter
                        Text {
                            anchors.centerIn: parent
                            text: "CD"
                            color: root._ghost
                            font.family: CdPlayerService.fontMono
                            font.pixelSize: 11
                            font.bold: true
                            font.letterSpacing: 1.5
                            opacity: 0.4
                        }
                        Text {
                            anchors.centerIn: parent
                            text: root._hasCd ? "CD" : "  "
                            color: root._seg
                            font.family: CdPlayerService.fontMono
                            font.pixelSize: 11
                            font.bold: true
                            font.letterSpacing: 1.5
                        }
                    }

                    // Play state pip
                    Text {
                        text: root._isPlaying ? "▶" : (CdPlayerService.state === "paused" ? "||" : "■")
                        color: root._isPlaying ? root._seg : root._dim
                        font.family: CdPlayerService.fontMono
                        font.pixelSize: 11
                        font.bold: true
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                // RIGHT group — TRK + pos/total
                Row {
                    id: hdrRight
                    anchors.right: parent.right
                    anchors.rightMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 16

                    // TRK label
                    Text {
                        text: "TRK"
                        color: root._dim
                        font.family: CdPlayerService.fontMono
                        font.pixelSize: 9
                        font.bold: true
                        font.letterSpacing: 1
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    // Track number ghost "88" + active
                    Item {
                        width: 26
                        height: 24
                        anchors.verticalCenter: parent.verticalCenter

                        Text {
                            anchors.centerIn: parent
                            text: "88"
                            color: root._ghost
                            font.family: CdPlayerService.fontSegment7
                            font.pixelSize: 18
                            font.bold: true
                        }
                        Text {
                            anchors.centerIn: parent
                            text: root._track > 0 ? String(root._track).padStart(2, '0') : "--"
                            color: root._seg
                            font.family: CdPlayerService.fontSegment7
                            font.pixelSize: 18
                            font.bold: true
                        }
                    }

                    // pos / total — ghost "88:88" + active
                    Row {
                        spacing: 12
                        anchors.verticalCenter: parent.verticalCenter

                        Item {
                            width: 36
                            height: 22
                            Text {
                                anchors.centerIn: parent
                                text: "88:88"
                                color: root._ghost
                                font.family: CdPlayerService.fontSegment7
                                font.pixelSize: 15
                            }
                            Text {
                                anchors.centerIn: parent
                                text: root._posStr
                                color: root._seg
                                font.family: CdPlayerService.fontSegment7
                                font.pixelSize: 15
                                font.bold: true
                            }
                        }

                        Text {
                            text: "/"
                            color: root._dim
                            font.family: CdPlayerService.fontMono
                            font.pixelSize: 12
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Item {
                            width: 36
                            height: 22
                            Text {
                                anchors.centerIn: parent
                                text: "88:88"
                                color: root._ghost
                                font.family: CdPlayerService.fontSegment7
                                font.pixelSize: 15
                                opacity: 0.6
                            }
                            Text {
                                anchors.centerIn: parent
                                text: root._totalStr
                                color: root._dim
                                font.family: CdPlayerService.fontSegment7
                                font.pixelSize: 15
                            }
                        }
                    }
                }
            }

            // Divider
            Rectangle {
                width: parent.width
                height: 1
                color: root._dim
                opacity: 0.35
            }

            // ───────────── CENTER: DOT-MATRIX PANEL (fixed cells) ─────────────
            Item {
                id: centerZone
                width: parent.width
                height: 24   // tighter — no extra room above/below the matrix
                clip: false

                DotMatrixPanel {
                    id: dotMatrix
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    cellCount: 28
                    cellPixelSize: 22
                    text: root._displayLine
                    running: root._isPlaying && root._hasCd
                    segmentColor: root._seg
                    ghostColor: root._ghost
                    bgColor: root._bg
                }
            }

            // ───────────── EQ VISUALIZER (Kenwood VFD: dots as frame top+bottom, bars grow ↑ from floor) ─────────────
            Item {
                id: eqRow
                width: parent.width
                height: root._eqH
                anchors.left: parent.left
                anchors.right: parent.right
                clip: true

                // 3D perspective wrapper — tilted on X axis, anchor to top of eqRow to pull content up under the matrix
                Item {
                    id: eq3DWrapper
                    anchors.fill: parent
                    layer.enabled: true
                    layer.smooth: true

                    transform: Rotation {
                        id: eqTilt
                        axis { x: 1; y: 0; z: 0 }
                        angle: 38
                        origin.x: eq3DWrapper.width / 2
                        origin.y: 0    // pivot at TOP — content folds up from the top edge
                    }

                    Column {
                        id: eqMain
                        anchors.fill: parent
                        spacing: 0

                        // Bars row — 11 columns, bars grow UP from the floor
                        // Each column: [left lit dots] [animated bar with -- segments] [right lit dots]
                        Row {
                            spacing: 2
                            anchors.horizontalCenter: parent.horizontalCenter

                            Repeater {
                                model: 11
                                Item {
                                    required property int index
                                    width: 30
                                    height: 188   // total bar area height

                                    property real _barLevel: (CdPlayerService._eqBars[index] || 0) * 16.0
                                    property int _litCount: Math.floor(_barLevel)

                                    // Left side-dots column — lit while playing
                                    Column {
                                        anchors.bottom: parent.bottom
                                        anchors.left: parent.left
                                        anchors.leftMargin: 1
                                        spacing: 2

                                        Repeater {
                                            model: 16
                                            Item {
                                                width: 5; height: 8
                                                Rectangle {
                                                    anchors.centerIn: parent
                                                    width: 3; height: 3; radius: 1.5
                                                    color: Qt.rgba(root._seg.r, root._seg.g, root._seg.b, root._isPlaying ? 0.70 : 0.20)
                                                }
                                            }
                                        }
                                    }

                                    // Right side-dots column — mirror
                                    Column {
                                        anchors.bottom: parent.bottom
                                        anchors.right: parent.right
                                        anchors.rightMargin: 1
                                        spacing: 2

                                        Repeater {
                                            model: 16
                                            Item {
                                                width: 5; height: 8
                                                Rectangle {
                                                    anchors.centerIn: parent
                                                    width: 3; height: 3; radius: 1.5
                                                    color: Qt.rgba(root._seg.r, root._seg.g, root._seg.b, root._isPlaying ? 0.70 : 0.20)
                                                }
                                            }
                                        }
                                    }

                                    // 16 segments stacked vertically — each segment drawn as "--" (two parallel rects)
                                    // index 0 = TOP (ceiling), 15 = BOTTOM (floor)
                                    // Bar fills from bottom up: lit if (15 - idx) < barLevel
                                    Column {
                                        anchors.bottom: parent.bottom
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        spacing: 1

                                        Repeater {
                                            model: 16
                                            Item {
                                                required property int index
                                                width: 18
                                                height: 8

                                                property color _segColor: {
                                                    var lit = (15 - index) < parent.parent._litCount
                                                    var peak = lit && (15 - index) === parent.parent._litCount - 1
                                                    return lit
                                                        ? (peak ? Qt.lighter(root._seg, 1.15) : root._seg)
                                                        : Qt.rgba(root._seg.r, root._seg.g, root._seg.b, 0.18)
                                                }

                                                // Two parallel horizontal rects with 1px gap in the middle
                                                Row {
                                                    anchors.centerIn: parent
                                                    spacing: 1
                                                    Rectangle {
                                                        width: 8; height: 8; radius: 1
                                                        color: parent.parent._segColor
                                                        Behavior on color { ColorAnimation { duration: 70 } }
                                                    }
                                                    Rectangle {
                                                        width: 8; height: 8; radius: 1
                                                        color: parent.parent._segColor
                                                        Behavior on color { ColorAnimation { duration: 70 } }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // Fixed frequency labels — at the bottom (floor), centered to match the bars
                        Row {
                            spacing: 2
                            anchors.horizontalCenter: parent.horizontalCenter

                            Repeater {
                                model: ["31", "63", "125", "250", "500", "1k", "2k", "4k", "8k", "16k", "32k"]
                                Item {
                                    required property string modelData
                                    width: 30
                                    height: 12
                                    Text {
                                        anchors.centerIn: parent
                                        text: modelData
                                        color: root._seg
                                        font.family: "DSEG7 Classic"
                                        font.pixelSize: 9
                                        font.bold: true
                                        font.letterSpacing: 0.5
                                        layer.enabled: true
                                        layer.effect: MultiEffect {
                                            shadowEnabled: true
                                            shadowColor: Qt.rgba(root._seg.r, root._seg.g, root._seg.b, 0.7)
                                            shadowOpacity: 0.6
                                            shadowBlur: 0.6
                                            shadowScale: 1.3
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ───────────── CONTROL ROW — physical buttons outside the LCD, on the bezel ─────────────
    Rectangle {
        id: controlRowBg
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root._bezel
        anchors.horizontalCenter: parent.horizontalCenter
        width: parent.width - root._bezel * 2
        height: root._ctrl
        radius: 4
        color: "#181818"
        border.color: "#2a2a2a"
        border.width: 1

        Row {
            anchors.centerIn: parent
            spacing: 6

            CdButton {
                label: "|◀◀"
                onClicked: CdPlayerService.prev()
                highlightColor: root._seg
            }
            CdButton {
                label: root._isPlaying ? "||" : "▶"
                highlight: root._isPlaying
                onClicked: CdPlayerService.toggle()
                highlightColor: root._seg
            }
            CdButton {
                label: "■"
                onClicked: CdPlayerService.stop()
                highlightColor: root._seg
            }
            CdButton {
                label: "▶▶|"
                onClicked: CdPlayerService.next()
                highlightColor: root._seg
            }
            CdButton {
                label: "▲"
                onClicked: CdPlayerService.eject()
                highlightColor: root._seg
            }
            CdButton {
                label: "CLR"
                onClicked: CdPlayerService.cycleTheme()
                highlightColor: root._seg
            }
        }
    }
}
