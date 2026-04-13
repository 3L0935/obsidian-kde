// Pure JS force-directed simulation with Barnes-Hut quadtree.
// Works under both Node and QML JS import.

var PHYSICS_DEFAULTS = {
    repulsion: 1500,
    springLength: 180,
    springK: 0.012,
    centering: 0.006,
    damping: 0.92,
    theta: 0.8,
    maxVelocity: 20,
};

function createSimulation(opts) {
    var cfg = Object.assign({}, PHYSICS_DEFAULTS, opts || {});
    var nodes = [];
    var nodeById = new Map();
    var edges = [];

    function randomPos() {
        return { x: (Math.random() - 0.5) * 200, y: (Math.random() - 0.5) * 200 };
    }

    function ensureNode(spec) {
        var p = randomPos();
        return { id: spec.id, x: p.x, y: p.y, vx: 0, vy: 0, fx: null, fy: null };
    }

    function setGraph(nodeSpecs, edgeSpecs) {
        nodes.length = 0;
        nodeById.clear();
        edges.length = 0;
        for (var s of nodeSpecs) {
            var n = ensureNode(s);
            nodes.push(n);
            nodeById.set(n.id, n);
        }
        for (var e of edgeSpecs) {
            if (nodeById.has(e.source) && nodeById.has(e.target)) {
                edges.push({ source: e.source, target: e.target });
            }
        }
    }

    function centroid() {
        if (nodes.length === 0) return { x: 0, y: 0 };
        var sx = 0, sy = 0;
        for (var n of nodes) { sx += n.x; sy += n.y; }
        return { x: sx / nodes.length, y: sy / nodes.length };
    }

    function addNode(spec) {
        if (nodeById.has(spec.id)) return;
        var n = ensureNode(spec);
        var c = centroid();
        n.x = c.x + (Math.random() - 0.5) * 20;
        n.y = c.y + (Math.random() - 0.5) * 20;
        nodes.push(n);
        nodeById.set(n.id, n);
    }

    function removeNode(id) {
        var n = nodeById.get(id);
        if (!n) return;
        nodeById.delete(id);
        var i = nodes.indexOf(n);
        if (i >= 0) nodes.splice(i, 1);
        for (var j = edges.length - 1; j >= 0; j--) {
            if (edges[j].source === id || edges[j].target === id) edges.splice(j, 1);
        }
    }

    function addEdge(source, target) {
        if (nodeById.has(source) && nodeById.has(target)) {
            edges.push({ source: source, target: target });
        }
    }

    function removeEdge(source, target) {
        for (var j = edges.length - 1; j >= 0; j--) {
            if (edges[j].source === source && edges[j].target === target) edges.splice(j, 1);
        }
    }

    function setPosition(id, x, y) {
        var n = nodeById.get(id);
        if (!n) return;
        n.x = x; n.y = y; n.vx = 0; n.vy = 0;
    }

    function pin(id, x, y) {
        var n = nodeById.get(id);
        if (!n) return;
        n.fx = x; n.fy = y; n.x = x; n.y = y; n.vx = 0; n.vy = 0;
    }

    function unpin(id) {
        var n = nodeById.get(id);
        if (!n) return;
        n.fx = null; n.fy = null;
    }

    function newQnode(x, y, size) {
        return { x: x, y: y, size: size, cx: 0, cy: 0, mass: 0, body: null, children: null };
    }

    function pickChild(q, body) {
        var mid = q.size / 2;
        var right = body.x >= q.x + mid;
        var bottom = body.y >= q.y + mid;
        return q.children[(bottom ? 2 : 0) + (right ? 1 : 0)];
    }

    function insert(q, body) {
        if (q.mass === 0) {
            q.body = body; q.mass = 1;
            q.cx = body.x; q.cy = body.y;
            return;
        }
        if (q.children === null) {
            q.children = [
                newQnode(q.x, q.y, q.size / 2),
                newQnode(q.x + q.size / 2, q.y, q.size / 2),
                newQnode(q.x, q.y + q.size / 2, q.size / 2),
                newQnode(q.x + q.size / 2, q.y + q.size / 2, q.size / 2),
            ];
            var existing = q.body;
            q.body = null;
            insert(pickChild(q, existing), existing);
        }
        insert(pickChild(q, body), body);
        var total = q.mass + 1;
        q.cx = (q.cx * q.mass + body.x) / total;
        q.cy = (q.cy * q.mass + body.y) / total;
        q.mass = total;
    }

    function buildQuadtree() {
        if (nodes.length === 0) return null;
        var minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
        for (var n of nodes) {
            if (n.x < minX) minX = n.x;
            if (n.y < minY) minY = n.y;
            if (n.x > maxX) maxX = n.x;
            if (n.y > maxY) maxY = n.y;
        }
        var size = Math.max(maxX - minX, maxY - minY) + 1;
        var q = newQnode(minX - 1, minY - 1, size + 2);
        for (var n2 of nodes) insert(q, n2);
        return q;
    }

    function applyRepulsion(q, body) {
        if (q === null || q.mass === 0) return;
        if (q.body === body) return;
        var dx = q.cx - body.x;
        var dy = q.cy - body.y;
        var dist2 = dx * dx + dy * dy;
        if (dist2 < 0.01) dist2 = 0.01;
        var dist = Math.sqrt(dist2);
        if (q.children === null || q.size / dist < cfg.theta) {
            var force = -cfg.repulsion * q.mass / dist2;
            body.vx += (dx / dist) * force;
            body.vy += (dy / dist) * force;
            return;
        }
        for (var c of q.children) applyRepulsion(c, body);
    }

    function tick() {
        if (nodes.length === 0) return;
        var tree = buildQuadtree();

        for (var n of nodes) {
            if (n.fx !== null) continue;
            applyRepulsion(tree, n);
        }

        for (var e of edges) {
            var a = nodeById.get(e.source);
            var b = nodeById.get(e.target);
            if (!a || !b) continue;
            var dx = b.x - a.x;
            var dy = b.y - a.y;
            var dist = Math.sqrt(dx * dx + dy * dy) || 0.01;
            var diff = dist - cfg.springLength;
            var force = cfg.springK * diff;
            var fx = (dx / dist) * force;
            var fy = (dy / dist) * force;
            if (a.fx === null) { a.vx += fx; a.vy += fy; }
            if (b.fx === null) { b.vx -= fx; b.vy -= fy; }
        }

        for (var n2 of nodes) {
            if (n2.fx !== null) continue;
            n2.vx -= n2.x * cfg.centering;
            n2.vy -= n2.y * cfg.centering;
        }

        for (var n3 of nodes) {
            if (n3.fx !== null) { n3.x = n3.fx; n3.y = n3.fy; continue; }
            n3.vx *= cfg.damping;
            n3.vy *= cfg.damping;
            if (n3.vx > cfg.maxVelocity) n3.vx = cfg.maxVelocity;
            if (n3.vx < -cfg.maxVelocity) n3.vx = -cfg.maxVelocity;
            if (n3.vy > cfg.maxVelocity) n3.vy = cfg.maxVelocity;
            if (n3.vy < -cfg.maxVelocity) n3.vy = -cfg.maxVelocity;
            n3.x += n3.vx;
            n3.y += n3.vy;
        }
    }

    function kineticEnergy() {
        var ke = 0;
        for (var n of nodes) ke += n.vx * n.vx + n.vy * n.vy;
        return ke;
    }

    return {
        setGraph: setGraph,
        addNode: addNode,
        removeNode: removeNode,
        addEdge: addEdge,
        removeEdge: removeEdge,
        setPosition: setPosition,
        pin: pin,
        unpin: unpin,
        tick: tick,
        getNodes: function () { return nodes; },
        getNode: function (id) { return nodeById.get(id) || null; },
        getEdges: function () { return edges; },
        kineticEnergy: kineticEnergy,
        centroid: centroid,
    };
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = { createSimulation: createSimulation };
}
