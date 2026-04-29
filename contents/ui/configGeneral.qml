import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import org.kde.kirigami as Kirigami
import org.kde.kquickcontrols as KQC

// Wrap the FormLayout in a ScrollView so the config dialog stays usable when
// the window is shorter than the form. Plasma KCM doesn't wrap automatically.
ScrollView {
    id: root
    contentWidth: availableWidth

    property alias cfg_vaultPath: vaultPathField.text
    // Plain (non-binding) property: plasmashell assigns cfg_mode on load, which
    // would break a QML binding definitively. We keep it imperative and sync
    // both ways via Component.onCompleted and the radios' onClicked.
    property string cfg_mode: "dynamic"
    property alias cfg_pinnedNote: pinnedNoteField.text
    property alias cfg_idleTimeoutSec: idleTimeoutSpin.value
    property alias cfg_autosaveEnabled: autosaveEnabledCheck.checked
    property alias cfg_autosaveDebounceMs: autosaveSpin.value
    property alias cfg_showLabels: showLabelsCheck.checked
    property alias cfg_graphOpacity: graphOpacitySpin.value
    property alias cfg_pageOpacity: pageOpacitySpin.value
    property alias cfg_physicsRepulsion: physRepulsion.value
    property alias cfg_physicsSpringLength: physSpringLen.value
    property alias cfg_physicsSpringK: physSpringK.value
    property alias cfg_physicsCentering: physCentering.value
    property alias cfg_physicsDamping: physDamping.value
    property alias cfg_physicsMaxVelocity: physMaxVel.value
    property alias cfg_pageFontSize: pageFontSpin.value
    property alias cfg_graphLabelFontSize: graphLabelFontSpin.value
    property alias cfg_overlayEnabled: overlayEnabledCheck.checked
    property string cfg_overlayShortcut: "Meta+O"
    property alias cfg_overlayDimAlpha: overlayDimSlider.value
    property alias cfg_overlayCloseOnFocusLost: overlayCloseOnFocusCheck.checked
    property alias cfg_perfDebug: perfDebugCheck.checked
    property alias cfg_perfAutoPauseHidden: perfAutoPauseHiddenCheck.checked

Kirigami.FormLayout {
    width: root.availableWidth

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
        ButtonGroup { id: modeGroup }
        RadioButton {
            id: dynamicRadio
            ButtonGroup.group: modeGroup
            text: i18n("Dynamic (graph → page)")
            onClicked: root.cfg_mode = "dynamic"
        }
        RadioButton {
            id: pinnedRadio
            ButtonGroup.group: modeGroup
            text: i18n("Pinned page")
            onClicked: root.cfg_mode = "pinned"
        }
    }

    RowLayout {
        Kirigami.FormData.label: i18n("Pinned note:")
        Layout.fillWidth: true
        TextField {
            id: pinnedNoteField
            Layout.fillWidth: true
            enabled: pinnedRadio.checked
            placeholderText: "folder/note.md (relative to vault)"
        }
        Button {
            text: i18n("Browse…")
            enabled: pinnedRadio.checked
            onClicked: pinnedFileDialog.open()
        }
    }

    FileDialog {
        id: pinnedFileDialog
        title: i18n("Pick a note inside the vault")
        nameFilters: [i18n("Markdown (*.md)")]
        currentFolder: vaultPathField.text ? "file://" + vaultPathField.text : ""
        onAccepted: {
            var abs = selectedFile.toString().replace("file://", "")
            var vault = vaultPathField.text
            if (vault && abs.indexOf(vault) === 0) {
                var rel = abs.slice(vault.length)
                if (rel.charAt(0) === "/") rel = rel.slice(1)
                pinnedNoteField.text = rel
            } else {
                pinnedNoteField.text = abs
            }
        }
    }

    SpinBox {
        id: idleTimeoutSpin
        Kirigami.FormData.label: i18n("Idle timeout (seconds):")
        from: 5; to: 600; value: 30
    }

    CheckBox {
        id: autosaveEnabledCheck
        Kirigami.FormData.label: i18n("Autosave:")
        text: i18n("Save automatically while typing")
        checked: true
    }

    SpinBox {
        id: autosaveSpin
        Kirigami.FormData.label: i18n("Autosave debounce (ms):")
        from: 100; to: 5000; stepSize: 50; value: 500
        enabled: autosaveEnabledCheck.checked
    }

    SpinBox {
        id: pageFontSpin
        Kirigami.FormData.label: i18n("Page font size:")
        from: 6; to: 32; value: 10
    }

    SpinBox {
        id: graphLabelFontSpin
        Kirigami.FormData.label: i18n("Graph label font size:")
        from: 6; to: 32; value: 10
    }

    CheckBox {
        id: showLabelsCheck
        Kirigami.FormData.label: i18n("Show node labels:")
        text: i18n("Display note titles in graph")
        checked: true
    }

    RowLayout {
        Kirigami.FormData.label: i18n("Graph opacity:")
        Slider {
            id: graphOpacitySpin
            from: 0.0; to: 1.0; stepSize: 0.05
            Layout.fillWidth: true
        }
        Label { text: Math.round(graphOpacitySpin.value * 100) + "%" }
    }

    RowLayout {
        Kirigami.FormData.label: i18n("Page opacity:")
        Slider {
            id: pageOpacitySpin
            from: 0.0; to: 1.0; stepSize: 0.05
            Layout.fillWidth: true
        }
        Label { text: Math.round(pageOpacitySpin.value * 100) + "%" }
    }

    Kirigami.Separator {
        Kirigami.FormData.isSection: true
        Kirigami.FormData.label: i18n("Graph physics")
    }

    RowLayout {
        Kirigami.FormData.label: i18n("Repel force:")
        Slider {
            id: physRepulsion
            from: 0.0; to: 2000.0; stepSize: 20.0
            Layout.fillWidth: true
        }
        Label { text: Math.round(physRepulsion.value); Layout.minimumWidth: 48 }
    }

    RowLayout {
        Kirigami.FormData.label: i18n("Link length:")
        Slider {
            id: physSpringLen
            from: 20.0; to: 600.0; stepSize: 5.0
            Layout.fillWidth: true
        }
        Label { text: Math.round(physSpringLen.value); Layout.minimumWidth: 48 }
    }

    RowLayout {
        Kirigami.FormData.label: i18n("Link force:")
        Slider {
            id: physSpringK
            from: 0.0; to: 0.02; stepSize: 0.0005
            Layout.fillWidth: true
        }
        Label { text: physSpringK.value.toFixed(4); Layout.minimumWidth: 48 }
    }

    RowLayout {
        Kirigami.FormData.label: i18n("Center gravity:")
        Slider {
            id: physCentering
            from: 0.0; to: 0.01; stepSize: 0.0002
            Layout.fillWidth: true
        }
        Label { text: physCentering.value.toFixed(4); Layout.minimumWidth: 48 }
    }

    RowLayout {
        Kirigami.FormData.label: i18n("Damping:")
        Slider {
            id: physDamping
            from: 0.7; to: 0.99; stepSize: 0.005
            Layout.fillWidth: true
        }
        Label { text: physDamping.value.toFixed(3); Layout.minimumWidth: 48 }
    }

    RowLayout {
        Kirigami.FormData.label: i18n("Max speed:")
        Slider {
            id: physMaxVel
            from: 0.5; to: 15.0; stepSize: 0.5
            Layout.fillWidth: true
        }
        Label { text: physMaxVel.value.toFixed(1); Layout.minimumWidth: 48 }
    }

    Button {
        Kirigami.FormData.label: ""
        text: i18n("Reset physics to defaults")
        onClicked: {
            physRepulsion.value = 400.0
            physSpringLen.value = 150.0
            physSpringK.value = 0.0025
            physCentering.value = 0.001
            physDamping.value = 0.85
            physMaxVel.value = 1.5
        }
    }

    Kirigami.Separator {
        Kirigami.FormData.isSection: true
        Kirigami.FormData.label: i18n("Overlay")
    }

    CheckBox {
        id: overlayEnabledCheck
        Kirigami.FormData.label: i18n("Enable global shortcut:")
        text: i18n("Allow this widget to handle the global overlay shortcut")
        checked: false
    }

    KQC.KeySequenceItem {
        id: overlayShortcutField
        Kirigami.FormData.label: i18n("Toggle shortcut:")
        enabled: overlayEnabledCheck.checked
        onKeySequenceChanged: root.cfg_overlayShortcut = keySequence.toString()
    }

    RowLayout {
        Kirigami.FormData.label: i18n("Dim level:")
        enabled: overlayEnabledCheck.checked
        Slider {
            id: overlayDimSlider
            from: 0.0; to: 1.0; stepSize: 0.01
            Layout.fillWidth: true
        }
        Label { text: Math.round(overlayDimSlider.value * 100) + "%"; Layout.minimumWidth: 48 }
    }

    CheckBox {
        id: overlayCloseOnFocusCheck
        Kirigami.FormData.label: i18n("Close on focus loss:")
        enabled: overlayEnabledCheck.checked
        text: i18n("Hide the overlay when another window gains focus")
        checked: true
    }

    Kirigami.Separator {
        Kirigami.FormData.isSection: true
        Kirigami.FormData.label: i18n("Performance")
    }

    CheckBox {
        id: perfDebugCheck
        Kirigami.FormData.label: i18n("Debug overlay (FPS):")
        text: i18n("Show FPS / tick / paint stats over the graph")
        checked: false
    }

    CheckBox {
        id: perfAutoPauseHiddenCheck
        Kirigami.FormData.label: i18n("Auto-pause when hidden:")
        text: i18n("Stop physics when window/screen is not active")
        checked: true
    }

    Component.onCompleted: {
        // Sync radios to the plain cfg_mode value plasmashell just wrote.
        if (cfg_mode === "pinned") pinnedRadio.checked = true
        else dynamicRadio.checked = true
        overlayShortcutField.keySequence = cfg_overlayShortcut
    }
}  // FormLayout
}  // ScrollView
