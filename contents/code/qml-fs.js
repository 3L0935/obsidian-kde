// Qt/QML filesystem adapter matching the shape expected by vault.js.
// readFileSync uses XMLHttpRequest on file:// URLs.
// readdirSync, statSync, writeFileSync are provided by the QML host.

function create(Qt) {
  function readFileSync(absPath) {
    const xhr = new XMLHttpRequest();
    xhr.open("GET", "file://" + absPath, false);
    xhr.send(null);
    if (xhr.status !== 200 && xhr.status !== 0) {
      throw new Error("failed to read " + absPath + ": " + xhr.status);
    }
    return xhr.responseText;
  }

  function writeFileSync(absPath, content) {
    const xhr = new XMLHttpRequest();
    xhr.open("PUT", "file://" + absPath, false);
    xhr.send(content);
    if (xhr.status !== 200 && xhr.status !== 0 && xhr.status !== 201) {
      throw new Error("failed to write " + absPath + ": " + xhr.status);
    }
  }

  function readdirSync(absPath) {
    throw new Error("qml-fs: readdirSync must be provided by QML host");
  }

  function statSync(absPath) {
    throw new Error("qml-fs: statSync must be provided by QML host");
  }

  return {
    readFileSync: readFileSync,
    writeFileSync: writeFileSync,
    readdirSync: readdirSync,
    statSync: statSync,
    join: function (a, b) { return a.endsWith("/") ? a + b : a + "/" + b; },
    sep: "/",
  };
}
