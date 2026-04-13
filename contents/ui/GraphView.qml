import QtQuick
import QtQuick.Controls
import org.kde.kirigami as Kirigami
import "../code/graph-physics.js" as Physics

Item {
    id: root

    property var vaultModel: null
    property var nodeColors: ({})
    property bool showLabels: true
    property int labelFontSize: 10
    onLabelFontSizeChanged: canvas.requestPaint()
    property var physicsConfig: null
    signal nodeActivated(string path)

    property var sim: null
    property real panX: 0
    property real panY: 0
    property real zoom: 1.0

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
        running: root.sim !== null
        repeat: true
        onTriggered: {
            root.sim.tick()
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
            const ctx = getContext("2d")
            ctx.reset()
            ctx.clearRect(0, 0, width, height)

            if (!root.sim) return

            ctx.save()
            ctx.translate(width / 2 + root.panX, height / 2 + root.panY)
            ctx.scale(root.zoom, root.zoom)

            const edges = root.sim.getEdges()
            const nodes = root.sim.getNodes()
            const byId = {}
            for (const n of nodes) byId[n.id] = n

            // When a node is selected, build the set of "focused" ids
            // (the node itself + its direct neighbors). Everything else is
            // dimmed and its label hidden, mirroring Obsidian's hover focus.
            const hasSelection = root.selectedNodeId !== "" && byId[root.selectedNodeId]
            const focused = {}
            if (hasSelection) {
                focused[root.selectedNodeId] = true
                for (const e of edges) {
                    if (e.source === root.selectedNodeId) focused[e.target] = true
                    else if (e.target === root.selectedNodeId) focused[e.source] = true
                }
            }
            const dimAlpha = 0.3

            ctx.lineWidth = 1 / root.zoom
            // Dimmed edges first
            if (hasSelection) {
                ctx.strokeStyle = Qt.rgba(0.5, 0.5, 0.5, 0.4 * dimAlpha)
                ctx.beginPath()
                for (const e of edges) {
                    if (focused[e.source] && focused[e.target]) continue
                    const a = byId[e.source], b = byId[e.target]
                    if (!a || !b) continue
                    ctx.moveTo(a.x, a.y)
                    ctx.lineTo(b.x, b.y)
                }
                ctx.stroke()
            }
            // Normal edges
            ctx.strokeStyle = Qt.rgba(0.5, 0.5, 0.5, 0.4)
            ctx.beginPath()
            for (const e of edges) {
                if (hasSelection && !(focused[e.source] && focused[e.target])) continue
                const a = byId[e.source], b = byId[e.target]
                if (!a || !b) continue
                ctx.moveTo(a.x, a.y)
                ctx.lineTo(b.x, b.y)
            }
            ctx.stroke()

            const defaultColor = Kirigami.Theme.highlightColor
            const colors = root.nodeColors || {}
            for (const n of nodes) {
                ctx.globalAlpha = (hasSelection && !focused[n.id]) ? dimAlpha : 1.0
                ctx.fillStyle = colors[n.id] || defaultColor
                ctx.beginPath()
                ctx.arc(n.x, n.y, 5, 0, Math.PI * 2)
                ctx.fill()
            }
            ctx.globalAlpha = 1.0

            if (root.showLabels && root.zoom > 0.6) {
                ctx.fillStyle = Kirigami.Theme.textColor
                ctx.font = (root.labelFontSize / root.zoom) + "px sans-serif"
                ctx.textAlign = "center"
                for (const n of nodes) {
                    if (hasSelection && !focused[n.id]) continue
                    const note = root.vaultModel.getNote(n.id)
                    if (note) ctx.fillText(note.title, n.x, n.y - 10)
                }
            }

            // Selected-node highlight ring (drawn last so it sits on top).
            if (root.selectedNodeId) {
                const sel = byId[root.selectedNodeId]
                if (sel) {
                    ctx.strokeStyle = Kirigami.Theme.highlightColor
                    ctx.lineWidth = 2 / root.zoom
                    ctx.beginPath()
                    ctx.arc(sel.x, sel.y, 9, 0, Math.PI * 2)
                    ctx.stroke()
                }
            }

            ctx.restore()
        }
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
            if (root.zoom < 0.1) root.zoom = 0.1
            if (root.zoom > 5.0) root.zoom = 5.0
            root.panX = mx - root.width / 2 - worldBefore.x * root.zoom
            root.panY = my - root.height / 2 - worldBefore.y * root.zoom
            canvas.requestPaint()
        }
    }
}
