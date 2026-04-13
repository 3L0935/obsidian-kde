// Minimal test runner. No deps. Run: node tests/run.js
const path = require("path");
const fs = require("fs");

const state = { suites: [], current: null, pass: 0, fail: 0 };

function describe(name, fn) {
  const suite = { name, tests: [] };
  state.suites.push(suite);
  state.current = suite;
  fn();
  state.current = null;
}

function it(name, fn) {
  state.current.tests.push({ name, fn });
}

function assertEqual(a, b, msg) {
  if (a !== b) throw new Error((msg || "assertEqual") + ": expected " + JSON.stringify(b) + ", got " + JSON.stringify(a));
}

function assertDeepEqual(a, b, msg) {
  const sa = JSON.stringify(a), sb = JSON.stringify(b);
  if (sa !== sb) throw new Error((msg || "assertDeepEqual") + ": expected " + sb + ", got " + sa);
}

function assertTrue(cond, msg) {
  if (!cond) throw new Error(msg || "assertTrue failed");
}

global.describe = describe;
global.it = it;
global.assertEqual = assertEqual;
global.assertDeepEqual = assertDeepEqual;
global.assertTrue = assertTrue;

const testsDir = __dirname;
const files = fs.readdirSync(testsDir).filter((f) => f.endsWith(".test.js"));
for (const f of files) require(path.join(testsDir, f));

for (const suite of state.suites) {
  console.log("\n" + suite.name);
  for (const t of suite.tests) {
    try {
      t.fn();
      console.log("  OK  " + t.name);
      state.pass++;
    } catch (e) {
      console.log("  FAIL " + t.name);
      console.log("       " + e.message);
      state.fail++;
    }
  }
}

console.log("\n" + state.pass + " passed, " + state.fail + " failed");
process.exit(state.fail > 0 ? 1 : 0);
