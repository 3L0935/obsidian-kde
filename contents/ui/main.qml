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
import "../code/index-cache.js" as IndexCache

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
    property int lastRssKb: 0
    // Persistent index-cache state: resolved on first save, then reused.
    // _cachedPositions holds {path: {x,y}} from a hydrated cache so the
    // GraphView simulation can apply them once the sim is created (the sim
    // doesn't exist at hydrate time, only after vaultReady triggers the
    // GraphView delegate). _currentSim is set by VaultView when its
    // GraphView mounts so _saveCache can read live positions.
    property string _cacheDirPath: ""
    property var _cachedPositions: ({})
    property var _currentSim: null

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

    Plasma5Support.DataSource {
        id: rssRunner
        engine: "executable"
        connectedSources: []
        onNewData: (sourceName, data) => {
            disconnectSource(sourceName)
            var out = ((data && data["stdout"]) || "").trim()
            var m = out.match(/(\d+)/)
            if (m) root.lastRssKb = parseInt(m[1], 10)
        }
    }

    // Separate DataSource so the cache-dir resolution doesn't collide with
    // dbusRunner's _pendingCallback (e.g. if the user activates the overlay
    // shortcut during the initial $HOME query). _cb is per-instance.
    Plasma5Support.DataSource {
        id: cacheRunner
        engine: "executable"
        connectedSources: []
        property var _cb: null
        onNewData: (sourceName, data) => {
            disconnectSource(sourceName)
            var out = ((data && data["stdout"]) || "").trim()
            if (_cb) { var f = _cb; _cb = null; f(out) }
        }
        function run(cmd, cb) {
            _cb = cb
            connectSource(cmd)
        }
    }

    Timer {
        id: rssSamplerTimer
        interval: 2000
        running: Plasmoid.configuration.perfDebug
        repeat: true
        // /proc/self/status would point to the awk child, not us. $PPID in
        // the shell expands to the shell's parent — i.e. plasmoidviewer or
        // plasmashell. Expected normal range: 200-500 MB. 4MB means we're
        // still looking at the wrong process.
        onTriggered: rssRunner.connectSource("grep VmRSS /proc/$PPID/status | awk '{print $2}'")
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

    // Cheap djb2 hash so we can have one cache file per vault path without
    // worrying about path-encoding collisions across filesystems. Result
    // is hex-encoded; collisions on practical vault-path counts are nil.
    function _hashStr(s) {
        var h = 5381
        for (var i = 0; i < s.length; i++) {
            h = ((h << 5) + h) + s.charCodeAt(i)
            h = h & 0xffffffff
        }
        return (h >>> 0).toString(16)
    }

    function _cachePath(vaultPath) {
        if (!root._cacheDirPath) return ""
        return root._cacheDirPath + "/" + _hashStr(vaultPath) + ".json"
    }

    // Resolve $HOME via the executable engine once, then mkdir -p the
    // cache dir. Subsequent calls hit the cached value. Both shell calls
    // are sequential — _cb is single-slot but never overlaps here.
    function _resolveCacheDir(cb) {
        if (root._cacheDirPath) { cb(root._cacheDirPath); return }
        cacheRunner.run("echo $HOME", function (home) {
            if (!home) { cb(""); return }
            root._cacheDirPath = home + "/.cache/obsidian-kde"
            cacheRunner.run("mkdir -p " + JSON.stringify(root._cacheDirPath), function () {
                cb(root._cacheDirPath)
            })
        })
    }

    function _saveCache() {
        if (!root.vault || !Plasmoid.configuration.vaultPath || !root._cacheDirPath) return
        var positions = {}
        if (root._currentSim) {
            try {
                var nodes = root._currentSim.getNodes()
                for (var i = 0; i < nodes.length; i++) {
                    positions[nodes[i].id] = { x: nodes[i].x, y: nodes[i].y }
                }
            } catch (e) {
                // sim may have been torn down between vaultReady toggles —
                // fall through with empty positions, the cache still beats
                // a full re-walk on next launch.
            }
        }
        var blob = IndexCache.serializeIndex({
            vaultPath: Plasmoid.configuration.vaultPath,
            notes: root.vault.allNotes(),
            positions: positions,
        })
        var p = _cachePath(Plasmoid.configuration.vaultPath)
        fsHelper.writeJsonFile(p, blob, function (ok) {
            if (!ok) console.warn("[obsidian-kde] cache write failed:", p)
        })
    }

    // Apply cached positions to a freshly-built simulation. Called by
    // VaultView when it sets _currentSim after mounting GraphView. Only
    // touches nodes for which we have a stored (non-zero) position; the
    // others keep their random spawn so newly-added notes blend in.
    function _applyCachedPositionsToSim() {
        if (!root._currentSim) return
        var pos = root._cachedPositions || {}
        if (Object.keys(pos).length === 0) return
        try {
            var nodes = root._currentSim.getNodes()
            for (var i = 0; i < nodes.length; i++) {
                var p = pos[nodes[i].id]
                if (p) { nodes[i].x = p.x; nodes[i].y = p.y }
            }
        } catch (e) {
            console.warn("[obsidian-kde] applyCachedPositions failed:", e)
        }
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
        // Reset any stale cached positions left from a previous vault.
        root._cachedPositions = ({})

        _resolveCacheDir(function () {
            var cachePath = _cachePath(vaultPath)
            // No cache dir resolved → fall through to full scan only.
            var doFullScan = function (entries) {
                var paths = entries.map(function (e) { return e.path })
                root.vault.scanFilesAsync(vaultPath, paths, 200,
                    function (done, total) {
                        if (done % 1000 === 0) console.log("[obsidian-kde] scanned " + done + "/" + total)
                    },
                    function () {
                        root.nodeColors = _computeNodeColors(_loadGraphConfig(vaultPath))
                        _saveCache()
                    }
                )
            }

            var afterCacheRead = function (cacheBlob) {
                var hydrated = cacheBlob ? IndexCache.hydrateIndex(cacheBlob) : null
                fsHelper.walkVault(vaultPath, function (entries) {
                    try {
                        if (hydrated && hydrated.vaultPath === vaultPath) {
                            // Fast path: hydrate metadata from cache, then
                            // diff against the walk. rescanFiles re-parses
                            // only mtime-changed files, leaves the rest alone.
                            root.vault.hydrateFromCache(vaultPath, hydrated.notes)
                            root.vault.rescanFiles(vaultPath, entries)
                            // Stash positions so VaultView can apply them
                            // when it mounts GraphView.
                            var pos = {}
                            for (var i = 0; i < hydrated.notes.length; i++) {
                                var hn = hydrated.notes[i]
                                if (hn.x !== 0 || hn.y !== 0) pos[hn.path] = { x: hn.x, y: hn.y }
                            }
                            root._cachedPositions = pos
                            root.nodeColors = _computeNodeColors(_loadGraphConfig(vaultPath))
                            _saveCache()
                        } else {
                            doFullScan(entries)
                        }
                    } catch (e) {
                        console.warn("[obsidian-kde] _initVault failed:", e, e.stack)
                    }
                })
            }

            if (cachePath) {
                fsHelper.readJsonFile(cachePath, afterCacheRead)
            } else {
                fsHelper.walkVault(vaultPath, doFullScan)
            }
        })

        if (Plasmoid.configuration.mode === "pinned" && Plasmoid.configuration.pinnedNote) {
            root.activeNotePath = _normalizePinnedPath(Plasmoid.configuration.pinnedNote, vaultPath)
            root.currentView = "page"
        } else {
            root.currentView = "graph"
        }
    }

    // Periodic cache writer so positions and any newly-added notes
    // (rescan after a press, etc.) get persisted without waiting for
    // a clean shutdown signal we don't have.
    Timer {
        id: cacheSaveTimer
        interval: 30000
        repeat: true
        running: root.vaultReady
        onTriggered: _saveCache()
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
