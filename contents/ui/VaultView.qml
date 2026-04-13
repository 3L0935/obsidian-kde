import QtQuick
import org.kde.plasma.plasmoid
import org.kde.kirigami as Kirigami
import "components"

Item {
    id: view

    // Reference to the PlasmoidItem root that owns the shared state
    // (vault, vaultReady, currentView, activeNotePath, nodeColors).
    property var stateOwner: null

    // Re-expose the idleTimer hook so PageView / GraphView callbacks can kick it.
    property var idleTimer: null

    Rectangle {
        anchors.fill: parent
        radius: 6
        color: Kirigami.Theme.backgroundColor
        opacity: view.stateOwner && view.stateOwner.currentView === "graph"
            ? Plasmoid.configuration.graphOpacity
            : Plasmoid.configuration.pageOpacity
    }

    Kirigami.PlaceholderMessage {
        anchors.centerIn: parent
        visible: !Plasmoid.configuration.vaultPath
        text: qsTr("Configure a vault path in the widget settings.")
    }

    Kirigami.PlaceholderMessage {
        anchors.centerIn: parent
        visible: Plasmoid.configuration.vaultPath && view.stateOwner && !view.stateOwner.vaultReady
        text: qsTr("Loading vault…")
    }

    Loader {
        id: viewLoader
        anchors.fill: parent
        active: view.stateOwner && view.stateOwner.vaultReady
        visible: view.stateOwner && view.stateOwner.vaultReady
        sourceComponent: view.stateOwner && view.stateOwner.currentView === "graph"
            ? graphComponent : pageComponent
    }

    Component {
        id: graphComponent
        GraphView {
            vaultModel: view.stateOwner ? view.stateOwner.vault : null
            nodeColors: view.stateOwner ? view.stateOwner.nodeColors : ({})
            showLabels: Plasmoid.configuration.showLabels
            labelFontSize: Plasmoid.configuration.graphLabelFontSize
            physicsConfig: ({
                repulsion: Plasmoid.configuration.physicsRepulsion,
                springLength: Plasmoid.configuration.physicsSpringLength,
                springK: Plasmoid.configuration.physicsSpringK,
                centering: Plasmoid.configuration.physicsCentering,
                damping: Plasmoid.configuration.physicsDamping,
                maxVelocity: Plasmoid.configuration.physicsMaxVelocity,
            })
            onNodeActivated: (path) => {
                if (view.stateOwner) {
                    view.stateOwner.activeNotePath = path
                    view.stateOwner.currentView = "page"
                }
                if (view.idleTimer) view.idleTimer.restart()
            }
        }
    }

    Component {
        id: pageComponent
        PageView {
            vaultModel: view.stateOwner ? view.stateOwner.vault : null
            notePath: view.stateOwner ? view.stateOwner.activeNotePath : ""
            autosaveEnabled: Plasmoid.configuration.autosaveEnabled
            autosaveDebounceMs: Plasmoid.configuration.autosaveDebounceMs
            fontSize: Plasmoid.configuration.pageFontSize
            showBackButton: Plasmoid.configuration.mode === "dynamic"
            onWikilinkClicked: (target) => {
                if (view.stateOwner && view.stateOwner.vault) {
                    for (const n of view.stateOwner.vault.allNotes()) {
                        if (n.basename === target || n.path === target) {
                            view.stateOwner.activeNotePath = n.path
                            break
                        }
                    }
                }
                if (view.idleTimer) view.idleTimer.restart()
            }
            onDismissed: {
                if (Plasmoid.configuration.mode === "dynamic") {
                    view.stateOwner.currentView = "graph"
                    view.stateOwner.activeNotePath = ""
                }
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        propagateComposedEvents: true
        hoverEnabled: true
        enabled: view.stateOwner && view.stateOwner.currentView === "page"
                 && Plasmoid.configuration.mode === "dynamic"
        onPositionChanged: { if (view.idleTimer) view.idleTimer.restart() }
        onPressed: (e) => { if (view.idleTimer) view.idleTimer.restart(); e.accepted = false }
    }
}
