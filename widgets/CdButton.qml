pragma ComponentBehavior: Bound

import QtQuick
import "../../"

Item {
    id: btn

    property string label
    property bool highlight: false
    property color highlightColor: "#00FFFF"
    property color dimColor: "#003333"
    signal clicked

    width: 44
    height: 28

    Rectangle {
        anchors.fill: parent
        radius: 2
        color: "#000000"
        border.color: btn.highlight ? btn.highlightColor : "#1a1a1a"
        border.width: 1
        opacity: btnMA.containsPress ? 0.6 : 1

        Behavior on opacity { NumberAnimation { duration: 60 } }

        Text {
            anchors.centerIn: parent
            text: btn.label
            color: btn.highlight ? btn.highlightColor : "#7a8a8a"
            font.family: "JetBrains Mono"
            font.pixelSize: 13
            font.bold: true
            font.letterSpacing: 1
        }
    }

    MouseArea {
        id: btnMA
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: btn.clicked()
    }
}
