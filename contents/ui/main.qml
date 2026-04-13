import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.kirigami as Kirigami
import "components"
import "../code/vault.js" as VaultJs
import "../code/markdown.js" as MarkdownJs
import "../code/qml-fs.js" as QmlFs

PlasmoidItem {
    id: root

    Layout.minimumWidth: 300
    Layout.minimumHeight: 300
    Layout.preferredWidth: 500
    Layout.preferredHeight: 500

    preferredRepresentation: fullRepresentation

    property var vault: null
    property string currentView: "graph"
    property string activeNotePath: ""
    property bool vaultReady: false

    FsHelper { id: fsHelper }

    function _buildVaultFs() {
        const base = QmlFs.create(Qt)
        base.readdirSync = function (p) { return fsHelper.listDir(p) }
        base.statSync = function (p) { return fsHelper.stat(p) }
        return base
    }

    function _initVault() {
        if (!Plasmoid.configuration.vaultPath) return
        const fs = _buildVaultFs()
        root.vault = VaultJs.createVaultModel({ fs: fs, markdown: MarkdownJs })
        root.vault.on("ready", function () { root.vaultReady = true })
        try {
            root.vault.scan(Plasmoid.configuration.vaultPath)
        } catch (e) {
            console.warn("vault scan failed:", e)
        }
        if (Plasmoid.configuration.mode === "pinned" && Plasmoid.configuration.pinnedNote) {
            root.activeNotePath = Plasmoid.configuration.pinnedNote
            root.currentView = "page"
        } else {
            root.currentView = "graph"
        }
    }

    Component.onCompleted: _initVault()

    Connections {
        target: Plasmoid.configuration
        function onVaultPathChanged() { root.vaultReady = false; _initVault() }
        function onModeChanged() { _initVault() }
        function onPinnedNoteChanged() {
            if (Plasmoid.configuration.mode === "pinned") {
                root.activeNotePath = Plasmoid.configuration.pinnedNote
                root.currentView = "page"
            }
        }
    }

    Timer {
        id: idleTimer
        interval: Plasmoid.configuration.idleTimeoutSec * 1000
        repeat: false
        onTriggered: {
            if (Plasmoid.configuration.mode === "dynamic" && root.currentView === "page") {
                root.currentView = "graph"
                root.activeNotePath = ""
            }
        }
    }

    fullRepresentation: Item {
        anchors.fill: parent

        Kirigami.PlaceholderMessage {
            anchors.centerIn: parent
            visible: !Plasmoid.configuration.vaultPath
            text: qsTr("Configure a vault path in the widget settings.")
        }

        Kirigami.PlaceholderMessage {
            anchors.centerIn: parent
            visible: Plasmoid.configuration.vaultPath && !root.vaultReady
            text: qsTr("Loading vault…")
        }

        Loader {
            id: viewLoader
            anchors.fill: parent
            visible: root.vaultReady
            sourceComponent: root.currentView === "graph" ? graphComponent : pageComponent
        }

        Component {
            id: graphComponent
            GraphView {
                vaultModel: root.vault
                showLabels: Plasmoid.configuration.showLabels
                onNodeActivated: (path) => {
                    root.activeNotePath = path
                    root.currentView = "page"
                    idleTimer.restart()
                }
            }
        }

        Component {
            id: pageComponent
            PageView {
                vaultModel: root.vault
                notePath: root.activeNotePath
                autosaveDebounceMs: Plasmoid.configuration.autosaveDebounceMs
                onWikilinkClicked: (target) => {
                    for (const n of root.vault.allNotes()) {
                        if (n.basename === target || n.path === target) {
                            root.activeNotePath = n.path
                            break
                        }
                    }
                    idleTimer.restart()
                }
                onDismissed: {
                    if (Plasmoid.configuration.mode === "dynamic") {
                        root.currentView = "graph"
                        root.activeNotePath = ""
                    }
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            propagateComposedEvents: true
            hoverEnabled: true
            enabled: root.currentView === "page" && Plasmoid.configuration.mode === "dynamic"
            onPositionChanged: idleTimer.restart()
            onPressed: (e) => { idleTimer.restart(); e.accepted = false }
        }
    }
}
