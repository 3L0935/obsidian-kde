import QtQuick
import Qt.labs.folderlistmodel

QtObject {
    id: fsHelper

    // Internal: a pool of pending FolderListModel instances keyed by their assigned token
    property var _pending: ({})
    property int _nextToken: 0

    // Per-path serialization. Concurrent writes to the same file via XHR PUT
    // can corrupt it; we serialize them with a path-keyed in-flight flag and
    // collapse intermediate writes (only the latest payload matters for an
    // index cache).
    property var _writesInFlight: ({})
    property var _writesPending: ({})

    // walkVault(rootPath, doneCallback)
    //   Recursively walks rootPath, collecting {path, mtime} entries for all
    //   *.md files. The mtime is read from FolderListModel's fileModified role
    //   (free during the walk) so no follow-up stat pass is needed.
    //   Calls doneCallback(entries) once the walk is complete.
    //   Uses asynchronous FolderListModel instances; callback fires after event loop turns.
    function walkVault(rootPath, doneCallback) {
        const state = {
            rootPath: rootPath,
            pending: 0,
            files: [],
            done: doneCallback,
        }
        _walkOne(rootPath, state)
    }

    function _walkOne(dirPath, state) {
        state.pending += 1
        const comp = Qt.createComponent("FsListModel.qml")
        if (comp.status !== Component.Ready) {
            console.warn("FsHelper: FsListModel.qml not ready:", comp.errorString())
            state.pending -= 1
            _maybeFinish(state)
            return
        }
        const model = comp.createObject(fsHelper, { folder: "file://" + dirPath })
        if (!model) {
            console.warn("FsHelper: failed to create FsListModel for", dirPath)
            state.pending -= 1
            _maybeFinish(state)
            return
        }

        // Connect to statusChanged and process when Ready
        const token = _nextToken++
        _pending[token] = model

        let _processed = false
        function processWhenReady() {
            if (_processed || model.status !== FolderListModel.Ready) return
            _processed = true
            model.statusChanged.disconnect(processWhenReady)
            try {
                for (let i = 0; i < model.count; i++) {
                    const name = model.get(i, "fileName")
                    const isDir = model.get(i, "fileIsDir") === true
                    const full = dirPath + "/" + name
                    if (isDir) {
                        _walkOne(full, state)
                    } else if (name.endsWith(".md")) {
                        // fileModified is exposed as a JS Date by FolderListModel.
                        // Fall back to 0 if the role is unavailable; rescanFiles
                        // treats 0 as "unknown mtime, always reload on first sight".
                        const modified = model.get(i, "fileModified")
                        const mtime = modified && typeof modified.getTime === "function"
                            ? modified.getTime()
                            : 0
                        state.files.push({ path: full, mtime: mtime })
                    }
                }
            } finally {
                delete _pending[token]
                model.destroy()
                state.pending -= 1
                _maybeFinish(state)
            }
        }

        model.statusChanged.connect(processWhenReady)
        // Also try immediately in case it's already Ready (synchronous case)
        if (model.status === FolderListModel.Ready) {
            processWhenReady()
        }
    }

    function _maybeFinish(state) {
        if (state.pending === 0) {
            try {
                state.done(state.files)
            } catch (e) {
                console.warn("FsHelper: walk callback error:", e)
            }
        }
    }

    // Per-path mtime cache. Qt/QML has no sync single-file stat, so we seed a
    // stable value on first lookup and return it for every subsequent call.
    // This means no false-positive conflicts in saveNote; it also means we
    // cannot detect EXTERNAL mid-session changes (real conflict detection
    // needs a filesystem watcher — out of scope for MVP).
    property var _statCache: ({})

    function stat(absPath) {
        if (_statCache[absPath] === undefined) {
            _statCache[absPath] = Date.now()
        }
        return { mtimeMs: _statCache[absPath] }
    }

    // readJsonFile / writeJsonFile: same XHR file:// pattern used elsewhere
    // (see _loadGraphConfig in main.qml). cb receives parsed object or null
    // on read; cb receives a boolean on write. All async — Qt 6 doesn't
    // reliably support sync XHR over file:// URLs.
    function readJsonFile(absPath, cb) {
        const xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== 4) return
            if (xhr.status !== 200 && xhr.status !== 0) { cb(null); return }
            try { cb(JSON.parse(xhr.responseText)) } catch (e) { cb(null) }
        }
        try {
            xhr.open("GET", "file://" + absPath, true)
            xhr.send(null)
        } catch (e) {
            cb(null)
        }
    }

    function writeJsonFile(absPath, obj, cb) {
        if (_writesInFlight[absPath]) {
            // A write is already running for this path; just remember the
            // latest payload. The completion handler picks it up.
            _writesPending[absPath] = { obj: obj, cb: cb || null }
            return
        }
        _writesInFlight[absPath] = true
        const xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== 4) return
            const ok = xhr.status === 200 || xhr.status === 0 || xhr.status === 201
            if (cb) cb(ok)
            _writesInFlight[absPath] = false
            // If a write came in while we were busy, kick it now with the
            // latest payload only.
            var pending = _writesPending[absPath]
            if (pending) {
                delete _writesPending[absPath]
                writeJsonFile(absPath, pending.obj, pending.cb)
            }
        }
        try {
            xhr.open("PUT", "file://" + absPath, true)
            xhr.send(JSON.stringify(obj))
        } catch (e) {
            _writesInFlight[absPath] = false
            if (cb) cb(false)
        }
    }
}
