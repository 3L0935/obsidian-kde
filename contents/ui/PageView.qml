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
    property int fontSize: 10
    property bool showBackButton: false
    // External tick bumped by main.qml when a vault rescan discovered that
    // the currently-open note was modified externally. Reading it inside
    // the `note` binding forces a fresh vaultModel lookup so the rendered
    // view picks up the new content without needing a plasmoid reload.
    property int reloadTick: 0

    signal wikilinkClicked(string target)
    signal dismissed()
    // Asks the host to run a vault rescan. Fires on note open so that
    // wikilink navigation or pinned-mode opens still see external edits,
    // even when the user didn't interact with the graph first.
    signal requestVaultRescan()

    // _reloadTick is bumped after a successful save; reading it inside the
    // `note` binding makes QML re-evaluate, which forces a fresh lookup from
    // vaultModel after addOrUpdateNote replaced the underlying note object.
    // Without this, `note` stays frozen on the stale reference and the
    // rendered view keeps showing the pre-save content (hence "clicking View
    // reverts").
    property int _reloadTick: 0
    readonly property var note: {
        _reloadTick
        reloadTick
        return vaultModel && notePath ? vaultModel.getNote(notePath) : null
    }

    property string mode: "rendered"
    property string saveState: "saved"
    property real loadedMtime: 0
    property string _renderedContent: ""
    property bool _contentLoading: false

    function _renderedHtml() {
        if (!root._renderedContent) return ""
        const parsed = MD.parseFrontmatter(root._renderedContent)
        let html = MD.renderHtml(parsed.body)
        html = html.replace(/\[\[([^\]|]+)\|([^\]]+)\]\]/g,
            function (_, t, l) { return "<a href=\"obsidian-wiki://" + encodeURIComponent(t) + "\">" + l + "</a>" })
        html = html.replace(/\[\[([^\]]+)\]\]/g,
            function (_, t) { return "<a href=\"obsidian-wiki://" + encodeURIComponent(t) + "\">" + t + "</a>" })
        html = html.replace(/(^|\s)#([a-zA-Z][a-zA-Z0-9_/-]*)/g,
            function (_, pre, tag) { return pre + "<span style=\"color:#6a9fb5\">#" + tag + "</span>" })
        return html
    }

    function _refreshContent() {
        if (!vaultModel || !notePath) { root._renderedContent = ""; return }
        root._contentLoading = true
        // loadNoteContent is a sync XHR read — Qt.callLater just defers it to the
        // next event-loop tick so any prior binding update lands first; the read
        // itself still blocks the UI thread for the file's duration. For a single
        // open note this is acceptable (single small file). The graph view never
        // calls this function.
        Qt.callLater(function () {
            root._renderedContent = vaultModel.loadNoteContent(notePath) || ""
            root._contentLoading = false
        })
    }

    function _loadIntoEditor() {
        if (!note) return
        var c = vaultModel.loadNoteContent(notePath)
        editor.text = c || ""
        root.loadedMtime = note.mtime
        root.saveState = "saved"
    }


    function _discardChanges() {
        root.saveState = "saved"
    }

    function _flushOrDiscard() {
        if (root.saveState !== "dirty") return
        if (root.autosaveEnabled) _saveNow()
        else _discardChanges()
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

    onNotePathChanged: {
        if (notePath) {
            root.requestVaultRescan()
            _refreshContent()
            if (root.mode === "editing") _loadIntoEditor()
        } else {
            root._renderedContent = ""
        }
    }

    on_ReloadTickChanged: _refreshContent()
    onReloadTickChanged: _refreshContent()
    Component.onCompleted: _refreshContent()

    onVisibleChanged: { if (visible && notePath) root.requestVaultRescan() }

    Keys.onEscapePressed: {
        _flushOrDiscard()
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
                    _flushOrDiscard()
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
                        root._flushOrDiscard()
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
                id: renderedScroll
                contentWidth: availableWidth
                TextEdit {
                    width: renderedScroll.availableWidth
                    readOnly: true
                    textFormat: TextEdit.RichText
                    wrapMode: TextEdit.Wrap
                    font.pointSize: root.fontSize
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
                    font.pointSize: root.fontSize
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
