import QtQuick

QtObject {
    id: fsHelper

    function listDir(absPath) {
        const comp = Qt.createComponent("FsListModel.qml")
        if (comp.status !== Component.Ready) {
            console.warn("FsHelper: component not ready:", comp.errorString())
            return []
        }
        const m = comp.createObject(fsHelper, { folder: "file://" + absPath })
        const out = []
        for (let i = 0; i < m.count; i++) {
            out.push({
                name: m.get(i, "fileName"),
                isFile: m.get(i, "fileIsDir") === false,
                isDirectory: m.get(i, "fileIsDir") === true,
            })
        }
        m.destroy()
        return out
    }

    function stat(absPath) {
        const sepIdx = absPath.lastIndexOf("/")
        const dir = absPath.slice(0, sepIdx)
        const name = absPath.slice(sepIdx + 1)
        const comp = Qt.createComponent("FsListModel.qml")
        const m = comp.createObject(fsHelper, { folder: "file://" + dir })
        let mtimeMs = 0
        for (let i = 0; i < m.count; i++) {
            if (m.get(i, "fileName") === name) {
                const d = m.get(i, "fileModified")
                mtimeMs = d ? d.getTime() : 0
                break
            }
        }
        m.destroy()
        return { mtimeMs: mtimeMs }
    }
}
