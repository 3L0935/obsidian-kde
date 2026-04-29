// Rolling-window stats for FPS, tick time, paint time, etc.
// Pure JS; works in Node and QML.

function createProbe(opts) {
    var windowSize = (opts && opts.window) || 120;
    var channels = {};

    function get(name) {
        if (!channels[name]) channels[name] = [];
        return channels[name];
    }

    function record(name, value) {
        var arr = get(name);
        arr.push(value);
        if (arr.length > windowSize) arr.shift();
    }

    function stats(name) {
        var arr = channels[name] || [];
        if (arr.length === 0) return { count: 0, p50: 0, p95: 0, min: 0, max: 0, avg: 0 };
        var sorted = arr.slice().sort(function (a, b) { return a - b; });
        var n = sorted.length;
        var p = function (q) { return sorted[Math.floor(q * (n - 1))]; };
        var sum = 0;
        for (var i = 0; i < n; i++) sum += sorted[i];
        return {
            count: n,
            p50: p(0.5),
            p95: p(0.95),
            min: sorted[0],
            max: sorted[n - 1],
            avg: sum / n,
        };
    }

    function reset() { channels = {}; }

    function last(name) {
        var arr = channels[name];
        if (!arr || arr.length === 0) return 0;
        return arr[arr.length - 1];
    }

    return { record: record, stats: stats, reset: reset, last: last };
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = { createProbe: createProbe };
}
