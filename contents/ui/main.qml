import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
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
    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground

    property var vault: null
    property string currentView: "graph"
    property string activeNotePath: ""
    property bool vaultReady: false
    property var nodeColors: ({})

    FsHelper { id: fsHelper }

    function _rgbIntToHex(rgb) {
        var hex = ((rgb >>> 0) & 0xffffff).toString(16)
        while (hex.length < 6) hex = "0" + hex
        return "#" + hex
    }

    function _matchClause(clause, note) {
        var c = clause.trim()
        if (!c) return false
        if (c.indexOf("path:") === 0) {
            return note.path.toLowerCase().indexOf(c.slice(5).toLowerCase()) >= 0
        }
        if (c.indexOf("file:") === 0) {
            return note.basename.toLowerCase().indexOf(c.slice(5).toLowerCase()) >= 0
        }
        if (c.indexOf("tag:") === 0) {
            var t = c.slice(4).replace(/^#/, "")
            return (note.tags || []).indexOf(t) >= 0
        }
        if (c.charAt(0) === "#") {
            return (note.tags || []).indexOf(c.slice(1)) >= 0
        }
        return note.path.toLowerCase().indexOf(c.toLowerCase()) >= 0
    }

    function _matchQuery(query, note) {
        var clauses = query.split(/\s+OR\s+/)
        for (var i = 0; i < clauses.length; i++) {
            if (_matchClause(clauses[i], note)) return true
        }
        return false
    }

    function _loadGraphConfig(vaultPath) {
        try {
            var xhr = new XMLHttpRequest()
            xhr.open("GET", "file://" + vaultPath + "/.obsidian/graph.json", false)
            xhr.send(null)
            if (xhr.status !== 200 && xhr.status !== 0) return []
            var data = JSON.parse(xhr.responseText)
            var raw = data.colorGroups || []
            var groups = []
            for (var i = 0; i < raw.length; i++) {
                var g = raw[i]
                if (!g || !g.color) continue
                groups.push({ query: g.query || "", color: _rgbIntToHex(g.color.rgb) })
            }
            return groups
        } catch (e) {
            console.warn("[obsidian-kde] graph.json load failed:", e)
            return []
        }
    }

    function _computeNodeColors(groups) {
        var map = {}
        if (!groups.length || !root.vault) return map
        var notes = root.vault.allNotes()
        for (var i = 0; i < notes.length; i++) {
            var note = notes[i]
            for (var j = 0; j < groups.length; j++) {
                if (_matchQuery(groups[j].query, note)) {
                    map[note.path] = groups[j].color
                    break
                }
            }
        }
        return map
    }

    function _buildVaultFs() {
        const base = QmlFs.create(Qt)
        // readdirSync is no longer used — walkVault handles the async walk
        base.statSync = function (p) { return fsHelper.stat(p) }
        return base
    }

    function _initVault() {
        if (!Plasmoid.configuration.vaultPath) return
        const fs = _buildVaultFs()
        root.vault = VaultJs.createVaultModel({ fs: fs, markdown: MarkdownJs })
        root.vault.on("ready", function () { root.vaultReady = true })

        const vaultPath = Plasmoid.configuration.vaultPath
        fsHelper.walkVault(vaultPath, function (files) {
            try {
                root.vault.scanFiles(vaultPath, files)
                root.nodeColors = _computeNodeColors(_loadGraphConfig(vaultPath))
            } catch (e) {
                console.warn("[obsidian-kde] scanFiles failed:", e, e.stack)
            }
        })

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

        Rectangle {
            anchors.fill: parent
            radius: 6
            color: Kirigami.Theme.backgroundColor
            opacity: root.currentView === "graph"
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
            visible: Plasmoid.configuration.vaultPath && !root.vaultReady
            text: qsTr("Loading vault…")
        }

        Loader {
            id: viewLoader
            anchors.fill: parent
            active: root.vaultReady
            visible: root.vaultReady
            sourceComponent: root.currentView === "graph" ? graphComponent : pageComponent
        }

        Component {
            id: graphComponent
            GraphView {
                vaultModel: root.vault
                nodeColors: root.nodeColors
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
                showBackButton: Plasmoid.configuration.mode === "dynamic"
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
