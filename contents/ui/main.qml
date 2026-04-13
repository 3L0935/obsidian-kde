import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root
    preferredRepresentation: fullRepresentation
    Layout.minimumWidth: 300
    Layout.minimumHeight: 300
    Layout.preferredWidth: 500
    Layout.preferredHeight: 500

    fullRepresentation: Rectangle {
        color: Kirigami.Theme.backgroundColor
        anchors.fill: parent
        Kirigami.Heading {
            anchors.centerIn: parent
            text: "Obsidian Vault Widget"
            level: 3
        }
    }
}
