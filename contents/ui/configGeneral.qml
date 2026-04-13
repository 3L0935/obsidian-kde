import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import org.kde.kirigami as Kirigami

Kirigami.FormLayout {
    id: root

    property alias cfg_vaultPath: vaultPathField.text
    property string cfg_mode: dynamicRadio.checked ? "dynamic" : "pinned"
    property alias cfg_pinnedNote: pinnedNoteField.text
    property alias cfg_idleTimeoutSec: idleTimeoutSpin.value
    property alias cfg_autosaveDebounceMs: autosaveSpin.value
    property alias cfg_showLabels: showLabelsCheck.checked

    RowLayout {
        Kirigami.FormData.label: i18n("Vault path:")
        TextField {
            id: vaultPathField
            Layout.fillWidth: true
            placeholderText: "/home/you/.obsidian-vault"
        }
        Button {
            text: i18n("Browse…")
            onClicked: folderDialog.open()
        }
    }

    FolderDialog {
        id: folderDialog
        onAccepted: vaultPathField.text = selectedFolder.toString().replace("file://", "")
    }

    RowLayout {
        Kirigami.FormData.label: i18n("Mode:")
        RadioButton { id: dynamicRadio; text: i18n("Dynamic (graph → page)"); checked: true }
        RadioButton { id: pinnedRadio;  text: i18n("Pinned page") }
    }

    TextField {
        id: pinnedNoteField
        Kirigami.FormData.label: i18n("Pinned note:")
        Layout.fillWidth: true
        enabled: pinnedRadio.checked
        placeholderText: "folder/note.md"
    }

    SpinBox {
        id: idleTimeoutSpin
        Kirigami.FormData.label: i18n("Idle timeout (seconds):")
        from: 5; to: 600; value: 30
    }

    SpinBox {
        id: autosaveSpin
        Kirigami.FormData.label: i18n("Autosave debounce (ms):")
        from: 100; to: 5000; stepSize: 50; value: 500
    }

    CheckBox {
        id: showLabelsCheck
        Kirigami.FormData.label: i18n("Show node labels:")
        text: i18n("Display note titles in graph")
        checked: true
    }

    Component.onCompleted: {
        if (cfg_mode === "pinned") pinnedRadio.checked = true
    }
}
