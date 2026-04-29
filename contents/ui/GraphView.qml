import QtQuick
import QtQuick.Controls
import QtQuick.Window
import org.kde.kirigami as Kirigami
import "../code/graph-physics.js" as Physics
import "../code/perf-probe.js" as PerfProbe

Item {
    id: root

    property var vaultModel: null
    property var nodeColors: ({})
    property bool showLabels: true
    property int labelFontSize: 10
    onLabelFontSizeChanged: canvas.requestPaint()
    property var physicsConfig: null
    signal nodeActivated(string path)
    signal requestRescan()

    // Press-session debouncing: one rescan per press, re-armed on release.
    // A long drag or held button therefore produces a single request, and
    // pressing again only after releasing is what counts as a new "intent".
    property bool _pressRescanArmed: true

    property var sim: null
    property real panX: 0
    property real panY: 0
    property real zoom: 1.0

    property bool perfDebug: false
    property int lastRssKb: 0
    property var _probe: PerfProbe.createProbe({ window: 120 })

    // View-bounds cache: written by Canvas.onPaint after computing world-space
    // viewport, read by physicsTimer.onTriggered to freeze off-screen nodes.
    property real _viewMinX: -Infinity
    property real _viewMaxX:  Infinity
    property real _viewMinY: -Infinity
    property real _viewMaxY:  Infinity

    property bool autoPauseHidden: true

    // Physics runs only when:
    //   - sim is initialized,
    //   - the widget's window is visible (or autoPauseHidden is off), AND
    //   - the application is in a foregroundable state.
    // Qt.ApplicationActive = focused, Qt.ApplicationInactive = not focused but visible.
    // Qt.ApplicationSuspended/Hidden = no point ticking.
    property bool _shouldRun: {
        if (!sim) return false
        if (!autoPauseHidden) return true
        if (Qt.application.state !== Qt.ApplicationActive
            && Qt.application.state !== Qt.ApplicationInactive) return false
        var win = root.Window.window
        if (win && win.visibility === Window.Hidden) return false
        return true
    }

    property string selectedNodeId: ""

    focus: true
    Keys.onPressed: (e) => {
        if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Space) {
            if (root.selectedNodeId) root.nodeActivated(root.selectedNodeId)
            e.accepted = true
        } else if (e.key === Qt.Key_Escape) {
            root.selectedNodeId = ""
            canvas.requestPaint()
            e.accepted = true
        }
    }

    function _selectedTitle() {
        if (!root.selectedNodeId || !root.vaultModel) return ""
        const n = root.vaultModel.getNote(root.selectedNodeId)
        return n ? n.title : root.selectedNodeId
    }

    // Apply an on-demand rescan diff without rebuilding the simulation.
    // Existing node positions stay put; new notes spawn near the centroid
    // (see physics.addNode), removed notes drop out, and the full edge set
    // is replaced so that wikilink resolution changes elsewhere in the vault
    // also land on the canvas.
    function applyVaultDiff(diff) {
        if (!sim || !vaultModel || !diff) return
        var touched = false
        for (var i = 0; i < diff.removed.length; i++) {
            sim.removeNode(diff.removed[i])
            if (root.selectedNodeId === diff.removed[i]) root.selectedNodeId = ""
            touched = true
        }
        for (var j = 0; j < diff.added.length; j++) {
            sim.addNode({ id: diff.added[j] })
            touched = true
        }
        if (diff.changed.length > 0) touched = true
        if (touched) {
            sim.setEdges(vaultModel.getEdges())
            _wakePhysics()
            canvas.requestPaint()
        }
    }

    function _resetFromVault() {
        if (!vaultModel) return
        sim = Physics.createSimulation(physicsConfig || undefined)
        const notes = vaultModel.allNotes()
        const nodeSpecs = notes.map(function (n) { return { id: n.path } })
        const edges = vaultModel.getEdges()
        sim.setGraph(nodeSpecs, edges)
        _wakePhysics()
        canvas.requestPaint()
    }

    onVaultModelChanged: _resetFromVault()

    onPhysicsConfigChanged: {
        if (sim) {
            sim.updateConfig(physicsConfig)
            _wakePhysics()
        }
    }

    Timer {
        id: physicsTimer
        interval: 16
        running: root._shouldRun
        repeat: true
        onTriggered: {
            if (root._viewMinX > -Infinity) {
                // 50% extra physics margin so nodes drifting in from off-screen
                // don't pop visually — they get a few ticks of warm-up before
                // becoming visible.
                var pm = (root._viewMaxX - root._viewMinX) * 0.5
                root.sim.freezeOutsideBounds(
                    root._viewMinX - pm, root._viewMinY - pm,
                    root._viewMaxX + pm, root._viewMaxY + pm,
                )
            }
            var t0 = Date.now()
            root.sim.tick()
            root._probe.record("tick", Date.now() - t0)
            // Throttle only: at rest we tick at 5 FPS. Never fully stop —
            // resuming from a hard stop causes visible snaps because velocity
            // residuals balance the graph and re-applying forces after a gap
            // produces sudden jumps.
            interval = root.sim.kineticEnergy() < 0.5 ? 200 : 16
            canvas.requestPaint()
        }
    }

    function _wakePhysics() {
        // Kept for interaction points that want to nudge back to 60 FPS
        // immediately instead of waiting one 200 ms tick.
        if (root.sim) physicsTimer.interval = 16
    }

    Canvas {
        id: canvas
        anchors.fill: parent

        onPaint: {
            var paintT0 = Date.now()
            const ctx = getContext("2d")
            ctx.reset()
            ctx.clearRect(0, 0, width, height)

            if (!root.sim) return

            ctx.save()
            ctx.translate(width / 2 + root.panX, height / 2 + root.panY)
            ctx.scale(root.zoom, root.zoom)

            // World-space rectangle currently visible, with margin.
            // We translate by (width/2 + panX) and scale by zoom, so the world-space
            // origin sits at screen pixel (width/2 + panX, height/2 + panY). Inverting
            // gives us the world bounds of the screen rectangle.
            var marginPct = 0.20  // 20% past the viewport edges to avoid pop-in on pan
            var halfW = (width / root.zoom) * (0.5 + marginPct)
            var halfH = (height / root.zoom) * (0.5 + marginPct)
            var viewMinX = -halfW - root.panX / root.zoom
            var viewMaxX =  halfW - root.panX / root.zoom
            var viewMinY = -halfH - root.panY / root.zoom
            var viewMaxY =  halfH - root.panY / root.zoom

            root._viewMinX = viewMinX
            root._viewMaxX = viewMaxX
            root._viewMinY = viewMinY
            root._viewMaxY = viewMaxY

            const edges = root.sim.getEdges()
            const nodes = root.sim.getNodes()

            // Tag visibility once per paint (5000 inline checks) so all four
            // draw passes can read n._inView in O(1) instead of calling a
            // closure-scoped inView() function ~70k times per paint.
            for (var ti = 0, tlen = nodes.length; ti < tlen; ti++) {
                var tn = nodes[ti]
                tn._inView = (tn.x >= viewMinX && tn.x <= viewMaxX
                              && tn.y >= viewMinY && tn.y <= viewMaxY)
            }

            // edges now carry direct refs e.a / e.b populated by the physics
            // module (no per-paint byId map needed). selectedNodeRef lookup
            // still needs nodeById since we have an id, not a ref.
            var selectedNodeRef = null
            if (root.selectedNodeId) {
                selectedNodeRef = root.sim.getNode(root.selectedNodeId) || null
            }

            // When a node is selected, build the set of "focused" ids
            // (the node itself + its direct neighbors). Everything else is
            // dimmed and its label hidden, mirroring Obsidian's hover focus.
            const hasSelection = selectedNodeRef !== null
            const focused = {}
            if (hasSelection) {
                focused[root.selectedNodeId] = true
                for (var fi = 0, flen = edges.length; fi < flen; fi++) {
                    var fe = edges[fi]
                    if (fe.source === root.selectedNodeId) focused[fe.target] = true
                    else if (fe.target === root.selectedNodeId) focused[fe.source] = true
                }
            }
            const dimAlpha = 0.3
            var eLen = edges.length
            var nLen = nodes.length

            ctx.lineWidth = 1 / root.zoom
            // Dimmed edges first
            if (hasSelection) {
                ctx.strokeStyle = Qt.rgba(0.5, 0.5, 0.5, 0.4 * dimAlpha)
                ctx.beginPath()
                for (var di = 0; di < eLen; di++) {
                    var de = edges[di]
                    if (focused[de.source] && focused[de.target]) continue
                    var da = de.a, db = de.b
                    if (!da || !db) continue
                    if (!da._inView && !db._inView) continue
                    ctx.moveTo(da.x, da.y)
                    ctx.lineTo(db.x, db.y)
                }
                ctx.stroke()
            }
            // Normal edges
            ctx.strokeStyle = Qt.rgba(0.5, 0.5, 0.5, 0.4)
            ctx.beginPath()
            for (var ei = 0; ei < eLen; ei++) {
                var e = edges[ei]
                if (hasSelection && !(focused[e.source] && focused[e.target])) continue
                var ea = e.a, eb = e.b
                if (!ea || !eb) continue
                if (!ea._inView && !eb._inView) continue
                ctx.moveTo(ea.x, ea.y)
                ctx.lineTo(eb.x, eb.y)
            }
            ctx.stroke()

            const defaultColor = Kirigami.Theme.highlightColor
            const colors = root.nodeColors || {}
            for (var ni = 0; ni < nLen; ni++) {
                var nn = nodes[ni]
                if (!nn._inView) continue
                ctx.globalAlpha = (hasSelection && !focused[nn.id]) ? dimAlpha : 1.0
                ctx.fillStyle = colors[nn.id] || defaultColor
                ctx.beginPath()
                ctx.arc(nn.x, nn.y, 5, 0, Math.PI * 2)
                ctx.fill()
            }
            ctx.globalAlpha = 1.0

            if (root.showLabels && root.zoom > 0.6) {
                ctx.fillStyle = Kirigami.Theme.textColor
                ctx.font = (root.labelFontSize / root.zoom) + "px sans-serif"
                ctx.textAlign = "center"
                for (var li = 0; li < nLen; li++) {
                    var ln = nodes[li]
                    if (!ln._inView) continue
                    if (hasSelection && !focused[ln.id]) continue
                    var note = root.vaultModel.getNote(ln.id)
                    if (note) ctx.fillText(note.title, ln.x, ln.y - 10)
                }
            }

            // Selected-node highlight ring (drawn last so it sits on top).
            if (selectedNodeRef) {
                ctx.strokeStyle = Kirigami.Theme.highlightColor
                ctx.lineWidth = 2 / root.zoom
                ctx.beginPath()
                ctx.arc(selectedNodeRef.x, selectedNodeRef.y, 9, 0, Math.PI * 2)
                ctx.stroke()
            }

            ctx.restore()
            root._probe.record("paint", Date.now() - paintT0)
            root._probe.record("frame", Date.now())
        }
    }

    Rectangle {
        visible: root.perfDebug
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.margins: 4
        color: Qt.rgba(0, 0, 0, 0.6)
        radius: 3
        width: hudText.implicitWidth + 8
        height: hudText.implicitHeight + 4
        z: 100  // sit above the canvas but below modal selection ring (none)

        Timer {
            interval: 500
            running: root.perfDebug
            repeat: true
            onTriggered: hudText.text = root._fmtStats()
        }

        Text {
            id: hudText
            anchors.centerIn: parent
            font.family: "monospace"
            font.pixelSize: 10
            color: "#0f0"
        }
    }

    function _fmtStats() {
        var tick = root._probe.stats("tick")
        var paint = root._probe.stats("paint")
        var frame = root._probe.stats("frame")
        var fps = 0
        if (frame.count > 1) {
            var span = frame.max - frame.min
            fps = span > 0 ? ((frame.count - 1) * 1000 / span) : 0
        }
        var n = root.sim ? root.sim.getNodes().length : 0
        var u = root.sim ? root.sim.unfrozenCount() : 0
        var rssMb = root.lastRssKb > 0 ? (root.lastRssKb / 1024).toFixed(0) + "MB" : "?"
        // tickNow / paintNow = most-recent sample, useful when the rolling
        // window still holds older ticks from a different viewport state.
        var tickNow = root._probe.last("tick")
        var paintNow = root._probe.last("paint")
        return "FPS " + fps.toFixed(0) +
               "  tick " + tickNow + " (p50 " + tick.p50 + " p95 " + tick.p95 + ")ms" +
               "  paint " + paintNow + " (p50 " + paint.p50 + ")ms" +
               "  N=" + n + "(U=" + u + ")" +
               "  RSS=" + rssMb
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        hoverEnabled: true

        property real dragStartX: 0
        property real dragStartY: 0
        property real panStartX: 0
        property real panStartY: 0
        property string draggedNodeId: ""
        property bool movedSignificantly: false

        function worldCoords(mx, my) {
            return {
                x: (mx - root.width / 2 - root.panX) / root.zoom,
                y: (my - root.height / 2 - root.panY) / root.zoom,
            }
        }

        function hitNode(mx, my) {
            if (!root.sim) return null
            const w = worldCoords(mx, my)
            // Visible node = 5 world-units. Hit target = max(14/zoom, 6) so
            // it stays at least ~14 screen pixels wide at any zoom level and
            // never shrinks below the visible glyph.
            const r = Math.max(14 / root.zoom, 6)
            for (const n of root.sim.getNodes()) {
                const dx = n.x - w.x, dy = n.y - w.y
                if (dx * dx + dy * dy <= r * r) return n
            }
            return null
        }

        onPressed: (e) => {
            root.forceActiveFocus()
            root._wakePhysics()
            if (root._pressRescanArmed) {
                root._pressRescanArmed = false
                root.requestRescan()
            }
            dragStartX = e.x; dragStartY = e.y
            panStartX = root.panX; panStartY = root.panY
            movedSignificantly = false
            const hit = hitNode(e.x, e.y)
            if (hit) {
                draggedNodeId = hit.id
                root.sim.pin(hit.id, hit.x, hit.y)
            } else {
                draggedNodeId = ""
            }
        }

        onPositionChanged: (e) => {
            if (!pressed) return
            const dx = e.x - dragStartX, dy = e.y - dragStartY
            if (dx * dx + dy * dy > 16) movedSignificantly = true
            if (draggedNodeId) {
                const w = worldCoords(e.x, e.y)
                root.sim.pin(draggedNodeId, w.x, w.y)
            } else {
                root.panX = panStartX + (e.x - dragStartX)
                root.panY = panStartY + (e.y - dragStartY)
            }
            canvas.requestPaint()
        }

        onReleased: (e) => {
            if (!movedSignificantly) {
                // A click (press+release with no drag): select the node under
                // the cursor, or clear selection on empty space.
                root.selectedNodeId = draggedNodeId
                canvas.requestPaint()
            }
            if (draggedNodeId) {
                root.sim.unpin(draggedNodeId)
                draggedNodeId = ""
            }
            root._pressRescanArmed = true
        }
    }

    Button {
        visible: root.selectedNodeId !== ""
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: 8
        padding: 6
        text: root.selectedNodeId ? (qsTr("Open: ") + root._selectedTitle()) : ""
        onClicked: {
            if (root.selectedNodeId) root.nodeActivated(root.selectedNodeId)
        }
    }

    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: (ev) => {
            const mx = ev.x
            const my = ev.y
            const worldBefore = {
                x: (mx - root.width / 2 - root.panX) / root.zoom,
                y: (my - root.height / 2 - root.panY) / root.zoom,
            }
            const factor = ev.angleDelta.y > 0 ? 1.1 : (1 / 1.1)
            root.zoom *= factor
            if (root.zoom < 0.05) root.zoom = 0.05
            if (root.zoom > 20.0) root.zoom = 20.0
            root.panX = mx - root.width / 2 - worldBefore.x * root.zoom
            root.panY = my - root.height / 2 - worldBefore.y * root.zoom
            canvas.requestPaint()
        }
    }
}
