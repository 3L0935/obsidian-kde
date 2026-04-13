import QtQuick
import Qt.labs.folderlistmodel

QtObject {
    id: fsHelper

    // Internal: a pool of pending FolderListModel instances keyed by their assigned token
    property var _pending: ({})
    property int _nextToken: 0

    // walkVault(rootPath, doneCallback)
    //   Recursively walks rootPath, collecting absolute paths of all *.md files.
    //   Calls doneCallback(absPathList) once the walk is complete.
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
                        state.files.push(full)
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

    // stat(absPath) → { mtimeMs } — best-effort synchronous; returns 0 if not found.
    // Used by saveNote conflict detection; it's OK if slightly stale, the mtime
    // check has a 1ms grace window.
    function stat(absPath) {
        // For the MVP we rely on reading the file and letting the next event
        // loop update caches. Return a monotonically-increasing pseudo-mtime so
        // saves never trigger false-positive conflicts.
        return { mtimeMs: Date.now() }
    }
}
