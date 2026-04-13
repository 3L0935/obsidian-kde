const { pickScreen } = require("../contents/code/screen-resolver.js");

describe("screen-resolver: pickScreen", function () {
  it("returns the screen whose name matches activeOutputName", function () {
    const screens = [
      { name: "HDMI-1", geometry: { x: 0, y: 0, width: 1920, height: 1080 } },
      { name: "DP-2",   geometry: { x: 1920, y: 0, width: 2560, height: 1440 } },
    ];
    const result = pickScreen(screens, "DP-2", screens[0]);
    assertEqual(result, screens[1], "should return DP-2 screen");
  });

  it("falls back to fallbackScreen when name does not match any screen", function () {
    const screens = [{ name: "HDMI-1" }];
    const fallback = screens[0];
    const result = pickScreen(screens, "DP-99", fallback);
    assertEqual(result, fallback, "should return fallback");
  });

  it("falls back to screens[0] when fallback is null and name is empty", function () {
    const screens = [{ name: "HDMI-1" }, { name: "DP-2" }];
    const result = pickScreen(screens, "", null);
    assertEqual(result, screens[0], "should return first screen");
  });

  it("returns null for an empty screen list", function () {
    const result = pickScreen([], "HDMI-1", null);
    assertEqual(result, null, "should return null");
  });

  it("falls back when activeOutputName is undefined", function () {
    const screens = [{ name: "HDMI-1" }, { name: "DP-2" }];
    const fallback = screens[1];
    const result = pickScreen(screens, undefined, fallback);
    assertEqual(result, fallback, "should use fallback when name is undefined");
  });
});
