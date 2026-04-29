// Pure JS force-directed simulation with Barnes-Hut quadtree.
// Works under both Node and QML JS import.

// Floaty defaults — gradual motion, no snap. Dominated by maxVelocity
// (per-tick cap) and the absolute magnitude of the force constants. Users
// can tune all six via the config page.
var PHYSICS_DEFAULTS = {
    repulsion: 400,
    springLength: 150,
    springK: 0.0025,
    centering: 0.001,
    damping: 0.85,
    theta: 0.8,
    maxVelocity: 1.5,
};

function createSimulation(opts) {
    var cfg = Object.assign({}, PHYSICS_DEFAULTS, opts || {});
    var nodes = [];
    var nodeById = new Map();
    var edges = [];
    var frozenBounds = null;  // { minX, minY, maxX, maxY } or null when no freeze active
    // Set by setGraph before any randomPos() call, so spawn radius can scale
    // with the FINAL expected node count rather than the (still-growing) live
    // array length during construction.
    var _expectedN = 0;

    // Spawn radius scales with sqrt(N) and the spring length so dense vaults
    // don't all spawn on top of each other. With N=5000 and springLength=150,
    // half-size ≈ 5300 units — each node gets ~150 unit² to itself, matching
    // the spring rest length. Otherwise the quadtree degenerates trying to
    // separate hundreds of overlapping bodies on tick 1, and the physics tick
    // can take 100x longer for the first few seconds.
    function spawnHalfSize() {
        var n = _expectedN || nodes.length;
        if (n < 4) return 100;
        return Math.sqrt(n) * (cfg.springLength * 0.5);
    }

    function randomPos() {
        var h = spawnHalfSize();
        return { x: (Math.random() - 0.5) * h * 2, y: (Math.random() - 0.5) * h * 2 };
    }

    function ensureNode(spec) {
        var p = randomPos();
        return { id: spec.id, x: p.x, y: p.y, vx: 0, vy: 0, fx: null, fy: null };
    }

    function setGraph(nodeSpecs, edgeSpecs) {
        nodes.length = 0;
        nodeById.clear();
        edges.length = 0;
        _expectedN = nodeSpecs.length;
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

    // Replace the whole edge set without touching node positions. Used after
    // an on-demand vault rescan, where link resolution may have shifted
    // across many notes but nodes should stay where the user left them.
    function setEdges(edgeSpecs) {
        edges.length = 0;
        for (var e of edgeSpecs) {
            if (nodeById.has(e.source) && nodeById.has(e.target)) {
                edges.push({ source: e.source, target: e.target });
            }
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

    function freezeOutsideBounds(minXOrNull, minY, maxX, maxY, margin) {
        if (minXOrNull === null || minXOrNull === undefined) { frozenBounds = null; return; }
        var m = margin || 0;
        frozenBounds = {
            minX: minXOrNull - m,
            minY: minY - m,
            maxX: maxX + m,
            maxY: maxY + m,
        };
    }

    function isFrozen(n) {
        if (!frozenBounds) return false;
        return n.x < frozenBounds.minX || n.x > frozenBounds.maxX
            || n.y < frozenBounds.minY || n.y > frozenBounds.maxY;
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
        // Frozen nodes (tagged in tick() before this is called) are excluded
        // entirely. Massive win when zoomed in: a 5000-node vault with 50
        // visible nodes builds a 50-node tree (50 inserts) instead of 5000.
        // Reads n._frozen directly to avoid the 5000+ isFrozen() function
        // calls that dominated tick cost in V4.
        var minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
        var any = false;
        var i, len = nodes.length;
        for (i = 0; i < len; i++) {
            var n = nodes[i];
            if (n._frozen) continue;
            if (n.x < minX) minX = n.x;
            if (n.y < minY) minY = n.y;
            if (n.x > maxX) maxX = n.x;
            if (n.y > maxY) maxY = n.y;
            any = true;
        }
        if (!any) return null;
        var size = Math.max(maxX - minX, maxY - minY) + 1;
        var q = newQnode(minX - 1, minY - 1, size + 2);
        for (i = 0; i < len; i++) {
            var n2 = nodes[i];
            if (n2._frozen) continue;
            insert(q, n2);
        }
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

        // Tag nodes once with their freeze state. Avoids ~75k isFrozen()
        // function calls per tick (V4 JS engine is slow on calls — measured
        // ~525ms wasted per tick on a 5000-node vault). Inline access to
        // n._frozen costs ~10x less than a function call in V4.
        // Build the active list at the same time so subsequent loops only
        // iterate the relevant subset (typically a few dozen nodes when zoomed).
        var fb = frozenBounds;
        var active = [];
        var i, len = nodes.length;
        if (fb) {
            for (i = 0; i < len; i++) {
                var nn = nodes[i];
                if (nn.x < fb.minX || nn.x > fb.maxX
                    || nn.y < fb.minY || nn.y > fb.maxY) {
                    nn._frozen = true;
                    nn.vx = 0; nn.vy = 0;
                } else {
                    nn._frozen = false;
                    if (nn.fx === null) active.push(nn);
                }
            }
        } else {
            for (i = 0; i < len; i++) {
                var nn = nodes[i];
                nn._frozen = false;
                if (nn.fx === null) active.push(nn);
            }
        }

        var tree = buildQuadtree();
        var aLen = active.length;

        // Repulsion: only on active nodes; tree already excludes frozen ones.
        for (i = 0; i < aLen; i++) applyRepulsion(tree, active[i]);

        // Spring: must walk all edges, but skip edges with both ends frozen
        // and only apply forces to the active endpoints (matches the
        // "frozen end still pulls unfrozen one" semantics from before).
        for (var e of edges) {
            var a = nodeById.get(e.source);
            var b = nodeById.get(e.target);
            if (!a || !b) continue;
            if (a._frozen && b._frozen) continue;
            var dx = b.x - a.x;
            var dy = b.y - a.y;
            var dist = Math.sqrt(dx * dx + dy * dy) || 0.01;
            var diff = dist - cfg.springLength;
            var force = cfg.springK * diff;
            var fx = (dx / dist) * force;
            var fy = (dy / dist) * force;
            if (a.fx === null && !a._frozen) { a.vx += fx; a.vy += fy; }
            if (b.fx === null && !b._frozen) { b.vx -= fx; b.vy -= fy; }
        }

        // Centering: only on active.
        var c = cfg.centering;
        for (i = 0; i < aLen; i++) {
            var na = active[i];
            na.vx -= na.x * c;
            na.vy -= na.y * c;
        }

        // Pinned snap: still walks all nodes (pinned can be anywhere).
        for (i = 0; i < len; i++) {
            var np = nodes[i];
            if (np.fx !== null) { np.x = np.fx; np.y = np.fy; }
        }

        // Damping + clamp + integrate: only on active.
        var d = cfg.damping;
        var mv = cfg.maxVelocity;
        var negMv = -mv;
        for (i = 0; i < aLen; i++) {
            var nb = active[i];
            nb.vx *= d;
            nb.vy *= d;
            if (nb.vx > mv) nb.vx = mv;
            else if (nb.vx < negMv) nb.vx = negMv;
            if (nb.vy > mv) nb.vy = mv;
            else if (nb.vy < negMv) nb.vy = negMv;
            nb.x += nb.vx;
            nb.y += nb.vy;
        }
    }

    function kineticEnergy() {
        var ke = 0;
        for (var n of nodes) ke += n.vx * n.vx + n.vy * n.vy;
        return ke;
    }

    function unfrozenCount() {
        if (!frozenBounds) return nodes.length;
        var c = 0;
        for (var n of nodes) if (!isFrozen(n)) c++;
        return c;
    }

    function updateConfig(opts) {
        if (!opts) return;
        for (var k in opts) {
            if (opts[k] !== undefined && opts[k] !== null) cfg[k] = opts[k];
        }
    }

    return {
        setGraph: setGraph,
        addNode: addNode,
        removeNode: removeNode,
        addEdge: addEdge,
        removeEdge: removeEdge,
        setEdges: setEdges,
        setPosition: setPosition,
        pin: pin,
        unpin: unpin,
        freezeOutsideBounds: freezeOutsideBounds,
        tick: tick,
        updateConfig: updateConfig,
        getNodes: function () { return nodes; },
        getNode: function (id) { return nodeById.get(id) || null; },
        getEdges: function () { return edges; },
        kineticEnergy: kineticEnergy,
        unfrozenCount: unfrozenCount,
        centroid: centroid,
    };
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = { createSimulation: createSimulation };
}
