(function (root, factory) {
  if (typeof module === "object" && module.exports) module.exports = factory();
  else root.GraphPhysics = factory();
})(typeof self !== "undefined" ? self : this, function () {

  const DEFAULTS = {
    repulsion: 2000,
    springLength: 80,
    springK: 0.04,
    centering: 0.01,
    damping: 0.9,
    theta: 0.8,
    maxVelocity: 50,
  };

  function createSimulation(opts) {
    const cfg = Object.assign({}, DEFAULTS, opts || {});
    const nodes = [];
    const nodeById = new Map();
    const edges = [];

    function randomPos() {
      return { x: (Math.random() - 0.5) * 200, y: (Math.random() - 0.5) * 200 };
    }

    function ensureNode(spec) {
      const p = randomPos();
      return { id: spec.id, x: p.x, y: p.y, vx: 0, vy: 0, fx: null, fy: null };
    }

    function setGraph(nodeSpecs, edgeSpecs) {
      nodes.length = 0;
      nodeById.clear();
      edges.length = 0;
      for (const s of nodeSpecs) {
        const n = ensureNode(s);
        nodes.push(n);
        nodeById.set(n.id, n);
      }
      for (const e of edgeSpecs) {
        if (nodeById.has(e.source) && nodeById.has(e.target)) {
          edges.push({ source: e.source, target: e.target });
        }
      }
    }

    function centroid() {
      if (nodes.length === 0) return { x: 0, y: 0 };
      let sx = 0, sy = 0;
      for (const n of nodes) { sx += n.x; sy += n.y; }
      return { x: sx / nodes.length, y: sy / nodes.length };
    }

    function addNode(spec) {
      if (nodeById.has(spec.id)) return;
      const n = ensureNode(spec);
      const c = centroid();
      n.x = c.x + (Math.random() - 0.5) * 20;
      n.y = c.y + (Math.random() - 0.5) * 20;
      nodes.push(n);
      nodeById.set(n.id, n);
    }

    function removeNode(id) {
      const n = nodeById.get(id);
      if (!n) return;
      nodeById.delete(id);
      const i = nodes.indexOf(n);
      if (i >= 0) nodes.splice(i, 1);
      for (let j = edges.length - 1; j >= 0; j--) {
        if (edges[j].source === id || edges[j].target === id) edges.splice(j, 1);
      }
    }

    function addEdge(source, target) {
      if (nodeById.has(source) && nodeById.has(target)) {
        edges.push({ source: source, target: target });
      }
    }

    function removeEdge(source, target) {
      for (let j = edges.length - 1; j >= 0; j--) {
        if (edges[j].source === source && edges[j].target === target) edges.splice(j, 1);
      }
    }

    function setPosition(id, x, y) {
      const n = nodeById.get(id);
      if (!n) return;
      n.x = x; n.y = y; n.vx = 0; n.vy = 0;
    }

    function pin(id, x, y) {
      const n = nodeById.get(id);
      if (!n) return;
      n.fx = x; n.fy = y; n.x = x; n.y = y; n.vx = 0; n.vy = 0;
    }

    function unpin(id) {
      const n = nodeById.get(id);
      if (!n) return;
      n.fx = null; n.fy = null;
    }

    function newQnode(x, y, size) {
      return { x: x, y: y, size: size, cx: 0, cy: 0, mass: 0, body: null, children: null };
    }

    function pickChild(q, body) {
      const mid = q.size / 2;
      const right = body.x >= q.x + mid;
      const bottom = body.y >= q.y + mid;
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
        const existing = q.body;
        q.body = null;
        insert(pickChild(q, existing), existing);
      }
      insert(pickChild(q, body), body);
      const total = q.mass + 1;
      q.cx = (q.cx * q.mass + body.x) / total;
      q.cy = (q.cy * q.mass + body.y) / total;
      q.mass = total;
    }

    function buildQuadtree() {
      if (nodes.length === 0) return null;
      let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
      for (const n of nodes) {
        if (n.x < minX) minX = n.x;
        if (n.y < minY) minY = n.y;
        if (n.x > maxX) maxX = n.x;
        if (n.y > maxY) maxY = n.y;
      }
      const size = Math.max(maxX - minX, maxY - minY) + 1;
      const q = newQnode(minX - 1, minY - 1, size + 2);
      for (const n of nodes) insert(q, n);
      return q;
    }

    function applyRepulsion(q, body) {
      if (q === null || q.mass === 0) return;
      if (q.body === body) return;
      const dx = q.cx - body.x;
      const dy = q.cy - body.y;
      let dist2 = dx * dx + dy * dy;
      if (dist2 < 0.01) dist2 = 0.01;
      const dist = Math.sqrt(dist2);
      if (q.children === null || q.size / dist < cfg.theta) {
        const force = -cfg.repulsion * q.mass / dist2;
        body.vx += (dx / dist) * force;
        body.vy += (dy / dist) * force;
        return;
      }
      for (const c of q.children) applyRepulsion(c, body);
    }

    function tick() {
      if (nodes.length === 0) return;
      const tree = buildQuadtree();

      for (const n of nodes) {
        if (n.fx !== null) continue;
        applyRepulsion(tree, n);
      }

      for (const e of edges) {
        const a = nodeById.get(e.source);
        const b = nodeById.get(e.target);
        if (!a || !b) continue;
        const dx = b.x - a.x;
        const dy = b.y - a.y;
        const dist = Math.sqrt(dx * dx + dy * dy) || 0.01;
        const diff = dist - cfg.springLength;
        const force = cfg.springK * diff;
        const fx = (dx / dist) * force;
        const fy = (dy / dist) * force;
        if (a.fx === null) { a.vx += fx; a.vy += fy; }
        if (b.fx === null) { b.vx -= fx; b.vy -= fy; }
      }

      const c = centroid();
      for (const n of nodes) {
        if (n.fx !== null) continue;
        n.vx -= c.x * cfg.centering;
        n.vy -= c.y * cfg.centering;
      }

      for (const n of nodes) {
        if (n.fx !== null) { n.x = n.fx; n.y = n.fy; continue; }
        n.vx *= cfg.damping;
        n.vy *= cfg.damping;
        if (n.vx > cfg.maxVelocity) n.vx = cfg.maxVelocity;
        if (n.vx < -cfg.maxVelocity) n.vx = -cfg.maxVelocity;
        if (n.vy > cfg.maxVelocity) n.vy = cfg.maxVelocity;
        if (n.vy < -cfg.maxVelocity) n.vy = -cfg.maxVelocity;
        n.x += n.vx;
        n.y += n.vy;
      }
    }

    function kineticEnergy() {
      let ke = 0;
      for (const n of nodes) ke += n.vx * n.vx + n.vy * n.vy;
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

  return { createSimulation: createSimulation };
});
