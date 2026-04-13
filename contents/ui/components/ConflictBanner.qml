import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: root
    color: "#f44336"
    height: 40
    signal reload()
    signal overwrite()

    RowLayout {
        anchors.fill: parent
        anchors.margins: 8
        Label {
            text: qsTr("File modified on disk since loaded")
            color: "white"
            Layout.fillWidth: true
        }
        Button { text: qsTr("Reload"); onClicked: root.reload() }
        Button { text: qsTr("Overwrite"); onClicked: root.overwrite() }
    }
}
