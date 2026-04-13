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
});
