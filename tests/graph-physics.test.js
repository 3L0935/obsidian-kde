const { createSimulation } = require("../contents/code/graph-physics.js");

describe("graph-physics", () => {
  it("initializes nodes with positions", () => {
    const sim = createSimulation();
    sim.setGraph(
      [{ id: "a" }, { id: "b" }],
      [{ source: "a", target: "b" }]
    );
    const nodes = sim.getNodes();
    assertEqual(nodes.length, 2);
    assertTrue(Number.isFinite(nodes[0].x));
    assertTrue(Number.isFinite(nodes[0].y));
  });

  it("two connected nodes stabilize near the spring rest length", () => {
    const sim = createSimulation({ springLength: 80 });
    sim.setGraph(
      [{ id: "a" }, { id: "b" }],
      [{ source: "a", target: "b" }]
    );
    sim.setPosition("a", -300, 0);
    sim.setPosition("b", 300, 0);
    for (let i = 0; i < 500; i++) sim.tick();
    const a = sim.getNode("a"), b = sim.getNode("b");
    const dx = a.x - b.x, dy = a.y - b.y;
    const dist = Math.sqrt(dx * dx + dy * dy);
    assertTrue(dist > 40 && dist < 160, "expected ~80, got " + dist);
  });

  it("kinetic energy decays over time", () => {
    const sim = createSimulation();
    const nodes = [];
    for (let i = 0; i < 10; i++) nodes.push({ id: String(i) });
    sim.setGraph(nodes, []);
    for (let i = 0; i < 200; i++) sim.tick();
    assertTrue(sim.kineticEnergy() < 5.0, "KE should decay");
  });

  it("pinned nodes do not move", () => {
    const sim = createSimulation();
    sim.setGraph(
      [{ id: "a" }, { id: "b" }],
      [{ source: "a", target: "b" }]
    );
    sim.setPosition("a", 0, 0);
    sim.setPosition("b", 50, 0);
    sim.pin("a", 0, 0);
    for (let i = 0; i < 200; i++) sim.tick();
    const a = sim.getNode("a");
    assertEqual(a.x, 0);
    assertEqual(a.y, 0);
  });

  it("addNode / removeNode update the graph without resetting others", () => {
    const sim = createSimulation();
    sim.setGraph([{ id: "a" }], []);
    sim.setPosition("a", 100, 100);
    sim.addNode({ id: "b" });
    sim.tick();
    const a = sim.getNode("a");
    assertTrue(Math.abs(a.x - 100) < 50, "a should not teleport when b is added");
    sim.removeNode("b");
    assertEqual(sim.getNodes().length, 1);
  });

  it("setEdges replaces the edge set without disturbing node positions", () => {
    const sim = createSimulation();
    sim.setGraph(
      [{ id: "a" }, { id: "b" }, { id: "c" }],
      [{ source: "a", target: "b" }]
    );
    sim.setPosition("a", 10, 20);
    sim.setPosition("b", 30, 40);
    sim.setPosition("c", 50, 60);
    sim.setEdges([
      { source: "a", target: "c" },
      { source: "b", target: "c" },
    ]);
    const edges = sim.getEdges();
    assertEqual(edges.length, 2);
    const a = sim.getNode("a"), b = sim.getNode("b"), c = sim.getNode("c");
    assertEqual(a.x, 10); assertEqual(a.y, 20);
    assertEqual(b.x, 30); assertEqual(b.y, 40);
    assertEqual(c.x, 50); assertEqual(c.y, 60);
  });

  it("setEdges drops edges referencing unknown nodes", () => {
    const sim = createSimulation();
    sim.setGraph([{ id: "a" }, { id: "b" }], []);
    sim.setEdges([
      { source: "a", target: "b" },
      { source: "a", target: "ghost" },
    ]);
    assertEqual(sim.getEdges().length, 1);
  });
});

describe("freezeOutsideBounds", () => {
    it("nodes outside bounds keep their position and velocity unchanged across a tick", () => {
        const sim = createSimulation();
        sim.setGraph(
            [{ id: "a" }, { id: "b" }, { id: "c" }],
            [{ source: "a", target: "b" }],
        );
        // Place "c" far out so any force we apply would move it.
        sim.setPosition("c", 10000, 10000);
        sim.freezeOutsideBounds(-100, -100, 100, 100, 0);
        const before = { x: sim.getNode("c").x, y: sim.getNode("c").y };
        sim.tick();
        const after = sim.getNode("c");
        assertEqual(after.x, before.x, "frozen node x unchanged");
        assertEqual(after.y, before.y, "frozen node y unchanged");
        assertEqual(after.vx, 0);
        assertEqual(after.vy, 0);
    });

    it("clearing freeze restores normal motion", () => {
        const sim = createSimulation();
        sim.setGraph([{ id: "a" }], []);
        sim.setPosition("a", 1000, 0);
        sim.freezeOutsideBounds(-100, -100, 100, 100, 0);
        sim.tick();
        const xFrozen = sim.getNode("a").x;
        sim.freezeOutsideBounds(null);  // clear
        sim.tick();
        // With centering pull, x should now drift toward 0.
        assertTrue(sim.getNode("a").x < xFrozen, "node moves once unfrozen");
    });
});
