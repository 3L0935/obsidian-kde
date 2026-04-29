const { createProbe } = require("../contents/code/perf-probe.js");

describe("perf-probe", () => {
  it("records samples and reports p50/p95/max", () => {
    const probe = createProbe({ window: 100 });
    for (let i = 1; i <= 100; i++) probe.record("tick", i);
    const stats = probe.stats("tick");
    assertEqual(stats.count, 100);
    assertEqual(stats.p50, 50);
    assertEqual(stats.p95, 95);
    assertEqual(stats.max, 100);
  });

  it("rolls oldest samples out of the window", () => {
    const probe = createProbe({ window: 10 });
    for (let i = 1; i <= 20; i++) probe.record("paint", i);
    const stats = probe.stats("paint");
    assertEqual(stats.count, 10);
    assertEqual(stats.min, 11);
    assertEqual(stats.max, 20);
  });

  it("returns zeroed stats when no samples recorded", () => {
    const probe = createProbe({ window: 10 });
    const stats = probe.stats("nothing");
    assertEqual(stats.count, 0);
    assertEqual(stats.p50, 0);
  });

  it("reset clears all channels", () => {
    const probe = createProbe({ window: 10 });
    probe.record("a", 1); probe.record("b", 2);
    probe.reset();
    assertEqual(probe.stats("a").count, 0);
    assertEqual(probe.stats("b").count, 0);
  });
});
