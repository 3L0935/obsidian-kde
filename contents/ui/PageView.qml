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
    property int autosaveDebounceMs: 500

    signal wikilinkClicked(string target)
    signal dismissed()

    readonly property var note: vaultModel && notePath ? vaultModel.getNote(notePath) : null

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
        const result = vaultModel.saveNote(note.path, editor.text, root.loadedMtime)
        if (result.conflict) { root.saveState = "conflict"; return }
        root.loadedMtime = result.mtime
        root.saveState = "saved"
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

        ConflictBanner {
            Layout.fillWidth: true
            visible: root.saveState === "conflict"
            onReload: { root._loadIntoEditor() }
            onOverwrite: {
                root.loadedMtime = root.note ? root.note.mtime : 0
                root._saveNow()
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.margins: 4
            SaveIndicator { indicatorState: root.saveState }
            Label {
                text: root.note ? root.note.title : ""
                font.bold: true
                Layout.fillWidth: true
                elide: Label.ElideRight
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
                        debounceTimer.restart()
                    }
                }
            }
        }
    }
}
