import QtQuick
import QtQuick.Controls
import org.kde.kirigami as Kirigami
import "../code/graph-physics.js" as Physics

Item {
    id: root

    property var vaultModel: null
    property bool showLabels: true
    signal nodeActivated(string path)

    property var sim: null
    property real panX: 0
    property real panY: 0
    property real zoom: 1.0

    function _resetFromVault() {
        if (!vaultModel) return
        sim = Physics.createSimulation()
        const notes = vaultModel.allNotes()
        const nodeSpecs = notes.map(function (n) { return { id: n.path } })
        const edges = vaultModel.getEdges()
        sim.setGraph(nodeSpecs, edges)
        canvas.requestPaint()
    }

    onVaultModelChanged: _resetFromVault()

    Timer {
        id: physicsTimer
        interval: 16
        running: root.sim !== null
        repeat: true
        onTriggered: {
            root.sim.tick()
            interval = root.sim.kineticEnergy() < 0.5 ? 200 : 16
            canvas.requestPaint()
        }
    }

    Canvas {
        id: canvas
        anchors.fill: parent
        renderStrategy: Canvas.Threaded

        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            ctx.fillStyle = Kirigami.Theme.backgroundColor
            ctx.fillRect(0, 0, width, height)

            if (!root.sim) return

            ctx.save()
            ctx.translate(width / 2 + root.panX, height / 2 + root.panY)
            ctx.scale(root.zoom, root.zoom)

            ctx.strokeStyle = Qt.rgba(0.5, 0.5, 0.5, 0.4)
            ctx.lineWidth = 1 / root.zoom
            const edges = root.sim.getEdges()
            const nodes = root.sim.getNodes()
            const byId = {}
            for (const n of nodes) byId[n.id] = n
            ctx.beginPath()
            for (const e of edges) {
                const a = byId[e.source], b = byId[e.target]
                if (!a || !b) continue
                ctx.moveTo(a.x, a.y)
                ctx.lineTo(b.x, b.y)
            }
            ctx.stroke()

            for (const n of nodes) {
                ctx.fillStyle = Kirigami.Theme.highlightColor
                ctx.beginPath()
                ctx.arc(n.x, n.y, 5, 0, Math.PI * 2)
                ctx.fill()
            }

            if (root.showLabels && root.zoom > 0.6) {
                ctx.fillStyle = Kirigami.Theme.textColor
                ctx.font = (10 / root.zoom) + "px sans-serif"
                ctx.textAlign = "center"
                for (const n of nodes) {
                    const note = root.vaultModel.getNote(n.id)
                    if (note) ctx.fillText(note.title, n.x, n.y - 10)
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

        function worldCoords(mx, my) {
            return {
                x: (mx - root.width / 2 - root.panX) / root.zoom,
                y: (my - root.height / 2 - root.panY) / root.zoom,
            }
        }

        function hitNode(mx, my) {
            if (!root.sim) return null
            const w = worldCoords(mx, my)
            const r = 8 / root.zoom
            for (const n of root.sim.getNodes()) {
                const dx = n.x - w.x, dy = n.y - w.y
                if (dx * dx + dy * dy <= r * r) return n
            }
            return null
        }

        onPressed: (e) => {
            dragStartX = e.x; dragStartY = e.y
            panStartX = root.panX; panStartY = root.panY
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
            if (draggedNodeId) {
                root.sim.unpin(draggedNodeId)
                draggedNodeId = ""
            }
        }

        onDoubleClicked: (e) => {
            const hit = hitNode(e.x, e.y)
            if (hit) root.nodeActivated(hit.id)
        }

        WheelHandler {
            target: null
            onWheel: (ev) => {
                const worldBefore = mouseArea.worldCoords(ev.x, ev.y)
                const factor = ev.angleDelta.y > 0 ? 1.1 : (1 / 1.1)
                root.zoom *= factor
                if (root.zoom < 0.1) root.zoom = 0.1
                if (root.zoom > 5.0) root.zoom = 5.0
                root.panX = ev.x - root.width / 2 - worldBefore.x * root.zoom
                root.panY = ev.y - root.height / 2 - worldBefore.y * root.zoom
                canvas.requestPaint()
            }
        }
    }
}
