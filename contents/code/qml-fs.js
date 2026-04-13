// Qt/QML filesystem adapter matching the shape expected by vault.js.
//
// readFileSync  — sync XHR GET on file:// (works in Qt 6).
// writeFile     — ASYNC XHR PUT. Must be async: Qt 6.11's sync XHR PUT on
//                 file:// opens the target but silently drops the body
//                 (verified: 0-byte output). Only the async path writes.
// readdirSync, statSync provided by the QML host.

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

  function writeFile(absPath, content, cb) {
    const xhr = new XMLHttpRequest();
    xhr.onreadystatechange = function () {
      if (xhr.readyState !== 4) return;
      if (xhr.status !== 200 && xhr.status !== 0 && xhr.status !== 201) {
        cb(new Error("failed to write " + absPath + ": " + xhr.status));
      } else {
        cb(null);
      }
    };
    try {
      xhr.open("PUT", "file://" + absPath, true);
      xhr.send(content);
    } catch (e) {
      cb(e);
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
    writeFile: writeFile,
    readdirSync: readdirSync,
    statSync: statSync,
    join: function (a, b) { return a.endsWith("/") ? a + b : a + "/" + b; },
    sep: "/",
  };
}
