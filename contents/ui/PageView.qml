import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "components"
import "../code/markdown.js" as MD

Item {
    id: root

    property var vaultModel: null
    property string notePath: ""
    property bool autosaveEnabled: true
    property int autosaveDebounceMs: 500
    property bool showBackButton: false

    signal wikilinkClicked(string target)
    signal dismissed()

    // _reloadTick is bumped after a successful save; reading it inside the
    // `note` binding makes QML re-evaluate, which forces a fresh lookup from
    // vaultModel after addOrUpdateNote replaced the underlying note object.
    // Without this, `note` stays frozen on the stale reference and the
    // rendered view keeps showing the pre-save content (hence "clicking View
    // reverts").
    property int _reloadTick: 0
    readonly property var note: {
        _reloadTick
        return vaultModel && notePath ? vaultModel.getNote(notePath) : null
    }

    property string mode: "rendered"
    property string saveState: "saved"
    property real loadedMtime: 0

    function _renderedHtml() {
        if (!note) return ""
        const parsed = MD.parseFrontmatter(note.content)
        let html = MD.renderHtml(parsed.body)
        html = html.replace(/\[\[([^\]|]+)\|([^\]]+)\]\]/g,
            function (_, t, l) { return "<a href=\"obsidian-wiki://" + encodeURIComponent(t) + "\">" + l + "</a>" })
        html = html.replace(/\[\[([^\]]+)\]\]/g,
            function (_, t) { return "<a href=\"obsidian-wiki://" + encodeURIComponent(t) + "\">" + t + "</a>" })
        html = html.replace(/(^|\s)#([a-zA-Z][a-zA-Z0-9_/-]*)/g,
            function (_, pre, tag) { return pre + "<span style=\"color:#6a9fb5\">#" + tag + "</span>" })
        return html
    }

    function _loadIntoEditor() {
        if (!note) return
        editor.text = note.content
        root.loadedMtime = note.mtime
        root.saveState = "saved"
    }

    function _saveNow() {
        if (!vaultModel || !note) return
        vaultModel.saveNote(note.path, editor.text, root.loadedMtime, function (err, result) {
            if (err) {
                console.warn("[obsidian-kde] save failed:", err && err.message)
                root.saveState = "dirty"
                return
            }
            if (result.conflict) { root.saveState = "conflict"; return }
            root.loadedMtime = result.mtime
            root._reloadTick = root._reloadTick + 1
            root.saveState = "saved"
        })
    }

    Timer {
        id: debounceTimer
        interval: root.autosaveDebounceMs
        repeat: false
        onTriggered: root._saveNow()
    }

    onNotePathChanged: { if (root.mode === "editing") _loadIntoEditor() }

    Keys.onEscapePressed: {
        if (root.saveState === "dirty") _saveNow()
        root.dismissed()
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        RowLayout {
            Layout.fillWidth: true
            Layout.margins: 4
            Button {
                visible: root.showBackButton
                text: "←"
                flat: true
                onClicked: {
                    if (root.saveState === "dirty") _saveNow()
                    root.dismissed()
                }
            }
            SaveIndicator { indicatorState: root.saveState }
            Label {
                text: root.note ? root.note.title : ""
                font.bold: true
                Layout.fillWidth: true
                elide: Label.ElideRight
            }
            Button {
                visible: root.mode === "editing"
                         && root.saveState === "dirty"
                         && !root.autosaveEnabled
                text: qsTr("Save")
                highlighted: true
                onClicked: root._saveNow()
            }
            Button {
                text: root.mode === "rendered" ? qsTr("Edit") : qsTr("View")
                onClicked: {
                    if (root.mode === "rendered") {
                        root._loadIntoEditor()
                        root.mode = "editing"
                    } else {
                        if (root.saveState === "dirty") root._saveNow()
                        root.mode = "rendered"
                    }
                }
            }
        }

        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: root.mode === "rendered" ? 0 : 1

            ScrollView {
                TextEdit {
                    width: parent.width
                    readOnly: true
                    textFormat: TextEdit.RichText
                    wrapMode: TextEdit.Wrap
                    text: root._renderedHtml()
                    selectByMouse: true
                    color: Kirigami.Theme.textColor
                    onLinkActivated: (url) => {
                        if (url.startsWith("obsidian-wiki://")) {
                            const target = decodeURIComponent(url.replace("obsidian-wiki://", ""))
                            root.wikilinkClicked(target)
                        } else {
                            Qt.openUrlExternally(url)
                        }
                    }
                }
            }

            ScrollView {
                TextArea {
                    id: editor
                    font.family: "monospace"
                    wrapMode: TextEdit.Wrap
                    onTextChanged: {
                        if (root.mode !== "editing") return
                        if (root.saveState !== "conflict") root.saveState = "dirty"
                        if (root.autosaveEnabled) debounceTimer.restart()
                    }
                }
            }
        }
    }
}
