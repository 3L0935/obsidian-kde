// Pure function for picking a QScreen-like object by output name,
// with a fallback cascade. Exported so it can be unit-tested from Node
// and imported from QML as a JS resource.

function pickScreen(screens, activeOutputName, fallbackScreen) {
    if (!screens || screens.length === 0) return null;
    if (activeOutputName) {
        for (var i = 0; i < screens.length; i++) {
            if (screens[i] && screens[i].name === activeOutputName) {
                return screens[i];
            }
        }
    }
    if (fallbackScreen) return fallbackScreen;
    return screens[0];
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = { pickScreen };
}
