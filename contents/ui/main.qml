import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support as Plasma5Support
import "components"
import "../code/vault.js" as VaultJs
import "../code/markdown.js" as MarkdownJs
import "../code/qml-fs.js" as QmlFs
import "../code/screen-resolver.js" as ScreenResolver

PlasmoidItem {
    id: root

    Layout.minimumWidth: 300
    Layout.minimumHeight: 300
    Layout.preferredWidth: 500
    Layout.preferredHeight: 500

    preferredRepresentation: fullRepresentation
    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground
    Plasmoid.globalShortcut: Plasmoid.configuration.overlayEnabled
        ? Plasmoid.configuration.overlayShortcut
        : ""

    property var vault: null
    property string currentView: "graph"
    property string activeNotePath: ""
    property bool vaultReady: false
    property var nodeColors: ({})
    property bool overlayActive: false
    property bool _rescanInFlight: false
    // Bumped when a rescan reveals that the currently-open note was modified
    // externally. PageView reads this tick in its note binding to re-pull
    // fresh content from the vault cache after the async walk completes.
    property int _pageReloadTick: 0

    FsHelper { id: fsHelper }

    Plasma5Support.DataSource {
        id: dbusRunner
        engine: "executable"
        connectedSources: []

        property var _pendingCallback: null

        onNewData: (sourceName, data) => {
            disconnectSource(sourceName)
            var out = ((data && data["stdout"]) || "").trim()
            if (_pendingCallback) {
                var cb = _pendingCallback
                _pendingCallback = null
                cb(out)
            }
        }

        function queryActiveOutputName(callback) {
            _pendingCallback = callback
            // Try qdbus6 first (Plasma 6 / Qt 6), fall back to qdbus (older).
            // If the activeOutputName method doesn't exist on this KWin build,
            // the command prints an empty line and the resolver falls back.
            var cmd = "qdbus6 org.kde.KWin /KWin activeOutputName 2>/dev/null || qdbus org.kde.KWin /KWin activeOutputName 2>/dev/null || echo ''"
            connectSource(cmd)
        }
    }

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
        // OR = union (any group matches); whitespace within a group = AND (all clauses match).
        // Mirrors Obsidian's graph color-group query semantics.
        var orGroups = query.split(/\s+OR\s+/)
        for (var i = 0; i < orGroups.length; i++) {
            var group = orGroups[i].trim()
            if (!group) continue
            var clauses = group.split(/\s+/)
            var allMatch = true
            for (var j = 0; j < clauses.length; j++) {
                if (!_matchClause(clauses[j], note)) { allMatch = false; break }
            }
            if (allMatch) return true
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

    function _normalizePinnedPath(raw, vaultPath) {
        if (!raw) return ""
        var p = String(raw)
        var base = vaultPath.endsWith("/") ? vaultPath : vaultPath + "/"
        if (p.indexOf(base) === 0) p = p.slice(base.length)
        else if (p === vaultPath) p = ""
        if (p.charAt(0) === "/") p = p.slice(1)
        return p
    }

    function _initVault() {
        if (!Plasmoid.configuration.vaultPath) return
        const fs = _buildVaultFs()
        root.vault = VaultJs.createVaultModel({ fs: fs, markdown: MarkdownJs })
        root.vault.on("ready", function () { root.vaultReady = true })

        const vaultPath = Plasmoid.configuration.vaultPath
        fsHelper.walkVault(vaultPath, function (entries) {
            try {
                var paths = entries.map(function (e) { return e.path })
                root.vault.scanFiles(vaultPath, paths)
                root.nodeColors = _computeNodeColors(_loadGraphConfig(vaultPath))
            } catch (e) {
                console.warn("[obsidian-kde] scanFiles failed:", e, e.stack)
            }
        })

        if (Plasmoid.configuration.mode === "pinned" && Plasmoid.configuration.pinnedNote) {
            root.activeNotePath = _normalizePinnedPath(Plasmoid.configuration.pinnedNote, vaultPath)
            root.currentView = "page"
        } else {
            root.currentView = "graph"
        }
    }

    // On-demand vault rescan. Only guard is _rescanInFlight so a caller
    // whose press lands while the previous walk is still running gets
    // dropped rather than queued. Per-press debouncing lives inside the
    // caller (GraphView has its own press-session armed flag), keeping
    // this function reusable from any entry point that wants a refresh
    // (graph press, PageView navigation, pinned mode open).
    function _rescanVault(onDone) {
        if (!root.vault || !root.vaultReady) return
        if (root._rescanInFlight) return
        var vaultPath = Plasmoid.configuration.vaultPath
        if (!vaultPath) return
        root._rescanInFlight = true
        fsHelper.walkVault(vaultPath, function (entries) {
            try {
                var diff = root.vault.rescanFiles(vaultPath, entries)
                if (diff.added.length || diff.changed.length || diff.removed.length) {
                    root.nodeColors = _computeNodeColors(_loadGraphConfig(vaultPath))
                }
                // If the currently-displayed note was modified externally,
                // nudge PageView so its binding re-reads from the cache.
                if (root.activeNotePath && diff.changed.indexOf(root.activeNotePath) >= 0) {
                    root._pageReloadTick = root._pageReloadTick + 1
                }
                if (onDone) onDone(diff)
            } catch (e) {
                console.warn("[obsidian-kde] rescan failed:", e, e.stack)
            } finally {
                root._rescanInFlight = false
            }
        })
    }

    function _toggleOverlay() {
        if (!Plasmoid.configuration.overlayEnabled) return
        if (overlayWindow.visible) {
            overlayWindow.hide()
            return
        }
        dbusRunner.queryActiveOutputName(function (outputName) {
            var fallback = root.Window.window ? root.Window.window.screen : null
            var target = ScreenResolver.pickScreen(Qt.application.screens, outputName, fallback)
            if (target) overlayWindow.screen = target
            overlayWindow.showFullScreen()
        })
    }

    Plasmoid.onActivated: _toggleOverlay()

    Component.onCompleted: _initVault()

    Connections {
        target: Plasmoid.configuration
        function onVaultPathChanged() { root.vaultReady = false; _initVault() }
        function onModeChanged() { _initVault() }
        function onPinnedNoteChanged() {
            if (Plasmoid.configuration.mode === "pinned") {
                root.activeNotePath = _normalizePinnedPath(
                    Plasmoid.configuration.pinnedNote,
                    Plasmoid.configuration.vaultPath)
                root.currentView = "page"
            }
        }
        function onOverlayShortcutChanged() {
            Plasmoid.globalShortcut = Plasmoid.configuration.overlayEnabled
                ? Plasmoid.configuration.overlayShortcut
                : ""
        }
        function onOverlayEnabledChanged() {
            Plasmoid.globalShortcut = Plasmoid.configuration.overlayEnabled
                ? Plasmoid.configuration.overlayShortcut
                : ""
        }
    }

    Connections {
        target: Qt.application
        function onScreenRemoved(screen) {
            if (overlayWindow.visible && overlayWindow.screen === screen) {
                overlayWindow.hide()
                overlayWindow.screen = null
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
        Loader {
            anchors.fill: parent
            active: !root.overlayActive
            sourceComponent: desktopVaultComponent
        }
        Component {
            id: desktopVaultComponent
            VaultView {
                stateOwner: root
                idleTimer: idleTimer
            }
        }
    }

    Window {
        id: overlayWindow
        visible: false
        flags: Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint | Qt.Tool
        color: Qt.rgba(0, 0, 0, Plasmoid.configuration.overlayDimAlpha)

        Loader {
            id: overlayLoader
            anchors.fill: parent
            active: overlayWindow.visible
            sourceComponent: overlayVaultComponent
        }

        Component {
            id: overlayVaultComponent
            VaultView {
                stateOwner: root
                idleTimer: idleTimer
            }
        }

        onVisibleChanged: {
            root.overlayActive = overlayWindow.visible
            if (overlayWindow.visible) overlayWindow.requestActivate()
        }

        onActiveChanged: {
            if (!overlayWindow.active
                && overlayWindow.visible
                && Plasmoid.configuration.overlayCloseOnFocusLost) {
                overlayWindow.hide()
            }
        }

        Shortcut {
            sequence: "Escape"
            enabled: overlayWindow.visible
            context: Qt.WindowShortcut
            onActivated: overlayWindow.hide()
        }
    }
}
