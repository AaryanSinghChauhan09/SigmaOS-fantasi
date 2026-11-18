import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

ApplicationWindow {
    id: win
    width: 1200
    height: 800
    minimumWidth: 960
    minimumHeight: 640
    visible: true
    title: "Fantasi"
    color: theme.background

    Material.theme: theme.light ? Material.Light : Material.Dark
    Material.accent: theme.accent
    Material.background: theme.background
    Material.foreground: theme.foreground

    readonly property bool rightToLeft: Qt.application.layoutDirection === Qt.RightToLeft
    readonly property var models: backend.models
    readonly property var generator: backend.generator
    readonly property var history: backend.history
    // Quieter text, from the foreground itself: a theme's own muted colors
    // can be too faint to read at label size.
    readonly property color muted: Qt.rgba(theme.foreground.r, theme.foreground.g, theme.foreground.b, 0.68)
    readonly property color line: theme.colors.selection
    readonly property color panel: theme.light ? Qt.darker(theme.background, 1.04) : Qt.darker(theme.background, 1.3)

    // 0 Square, 1 Screen, 2 Portrait.
    property int sizeChoice: 0
    readonly property size outputSize: sizeChoice === 1 ? backend.screenSize
                                     : sizeChoice === 2 ? Qt.size(832, 1216) : Qt.size(1024, 1024)
    // The file in the center, when it is one rather than a preview.
    readonly property string shownFile: generator.image.startsWith("file:") ? generator.image : ""
    readonly property bool canGenerate: models.state === "ready" && !generator.busy && prompt.text.trim() !== ""
    // The image the next one starts from, while changing one; it stays the
    // base turn after turn until another is picked or it's let go.
    property string baseImage: ""

    // The model's own steps and a new seed every time: what matters is said
    // in the prompt.
    function generate() {
        if (canGenerate)
            generator.generate(prompt.text, outputSize.width, outputSize.height, 0, -1, baseImage)
    }
    // Makes the shown image the base for the next, with its prompt to edit.
    function changeImage() {
        if (shownFile === "" || generator.busy)
            return
        baseImage = shownFile
        const said = historyList.currentIndex >= 0 ? history.promptAt(historyList.currentIndex) : ""
        if (said !== "")
            prompt.text = said
        prompt.forceActiveFocus()
        prompt.cursorPosition = prompt.length
    }
    // A picture of the user's own becomes the base; its prompt is theirs to write.
    function startFrom(url) {
        if (generator.busy)
            return
        baseImage = url
        prompt.forceActiveFocus()
        prompt.cursorPosition = prompt.length
    }
    // Shows a history image in the center.
    function pick(index) {
        if (index < 0 || index >= history.count || generator.busy)
            return
        historyList.currentIndex = index
        generator.show(history.urlAt(index))
    }

    Shortcut { sequence: "F1"; onActivated: help.opened ? help.close() : help.open() }
    Shortcut { sequence: "Ctrl+?"; onActivated: help.opened ? help.close() : help.open() }
    Shortcut { sequence: "Ctrl+Q"; onActivated: Qt.quit() }
    Shortcut { sequence: "Ctrl+Return"; enabled: win.canGenerate; onActivated: win.generate() }
    Shortcut { sequence: "Ctrl+Enter"; enabled: win.canGenerate; onActivated: win.generate() }
    Shortcut { sequence: "Ctrl+R"; enabled: win.canGenerate; onActivated: win.generate() }
    Shortcut { sequence: "Ctrl+E"; enabled: win.shownFile !== "" && !generator.busy; onActivated: win.changeImage() }
    Shortcut { sequence: "Ctrl+O"; enabled: !generator.busy; onActivated: backend.openPicture() }
    // Esc stops an image being made, or else lets go of the base image.
    Shortcut { sequence: "Escape"; enabled: generator.busy; onActivated: generator.cancel() }
    Shortcut { sequence: "Escape"; enabled: !generator.busy && win.baseImage !== ""; onActivated: win.baseImage = "" }
    Shortcut { sequence: "Ctrl+1"; onActivated: win.sizeChoice = 0 }
    Shortcut { sequence: "Ctrl+2"; onActivated: win.sizeChoice = 1 }
    Shortcut { sequence: "Ctrl+3"; onActivated: win.sizeChoice = 2 }
    Shortcut { sequence: "Ctrl+B"; enabled: win.shownFile !== ""; onActivated: backend.setBackground(win.shownFile) }
    Shortcut { sequence: "Ctrl+Shift+C"; enabled: win.shownFile !== ""; onActivated: backend.copy(win.shownFile) }
    Shortcut { sequence: "Ctrl+S"; enabled: win.shownFile !== ""; onActivated: backend.saveAs(win.shownFile) }
    Shortcut { sequence: "Ctrl+Up"; onActivated: win.pick(historyList.currentIndex - 1) }
    Shortcut { sequence: "Ctrl+Down"; onActivated: win.pick(historyList.currentIndex + 1) }
    Shortcut {
        sequence: "Ctrl+Delete"
        enabled: win.shownFile !== "" && historyList.currentIndex >= 0
        onActivated: if (history.remove(historyList.currentIndex)) generator.show("")
    }

    // Typing goes to the prompt from the start; it sits in a ScrollView, a
    // focus scope of its own, so `focus: true` alone doesn't reach it.
    Component.onCompleted: {
        prompt.text = backend.initialPrompt
        prompt.forceActiveFocus()
    }

    // A new image shows first in the history, selected.
    Connections {
        target: generator
        function onSaved() { historyList.currentIndex = 0 }
    }
    Connections {
        target: backend
        function onPictureChosen(url) { win.startFrom(url) }
    }

    // A picture dropped anywhere on the window becomes the base, but not
    // while an image is being made, so a drop then is refused, not lost.
    DropArea {
        anchors.fill: parent
        keys: ["text/uri-list"]
        onEntered: drag => drag.accept(!generator.busy && drag.hasUrls && drag.urls.length === 1 && backend.isPicture(drag.urls[0]))
        onDropped: drop => {
            if (!generator.busy && drop.hasUrls && backend.isPicture(drop.urls[0])) {
                win.startFrom(drop.urls[0].toString())
                drop.accept()
            }
        }
    }

    Item {
        anchors.fill: parent
        LayoutMirroring.enabled: win.rightToLeft
        LayoutMirroring.childrenInherit: true

        RowLayout {
            anchors.fill: parent
            spacing: 0

            // ---------------------------------------------------------- settings
            Rectangle {
                Layout.preferredWidth: 320
                Layout.fillHeight: true
                color: win.panel

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 18
                    spacing: 16

                    Label { text: "Fantasi"; font.pixelSize: 16; font.bold: true }

                    // The image the next one starts from, while changing one.
                    Rectangle {
                        objectName: "base"
                        Layout.fillWidth: true
                        Layout.preferredHeight: 56
                        visible: win.baseImage !== ""
                        color: "transparent"
                        border.color: win.line
                        radius: Math.min(4, theme.radius)
                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 10
                            Image {
                                Layout.preferredWidth: 40
                                Layout.preferredHeight: 40
                                source: win.baseImage
                                sourceSize: Qt.size(80, 80)
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                            }
                            Label {
                                Layout.fillWidth: true
                                text: qsTr("Changing this image")
                                elide: Text.ElideRight
                            }
                            ToolButton {
                                text: "×"
                                focusPolicy: Qt.NoFocus
                                Accessible.name: qsTr("Make a new image instead")
                                onClicked: win.baseImage = ""
                            }
                        }
                    }

                    // Or start from a picture of one's own, which a drop onto
                    // the window does too.
                    Button {
                        objectName: "startFrom"
                        Layout.fillWidth: true
                        visible: win.baseImage === ""
                        flat: true
                        focusPolicy: Qt.NoFocus
                        Material.roundedScale: theme.radius
                        text: qsTr("Start from a picture…")
                        onClicked: backend.openPicture()
                    }

                    ScrollView {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 132
                        TextArea {
                            id: prompt
                            objectName: "prompt"
                            focus: true
                            wrapMode: TextEdit.Wrap
                            placeholderText: win.baseImage !== "" ? qsTr("Describe the new image")
                                                                  : qsTr("Describe an image")
                            Material.roundedScale: theme.radius
                            Keys.onReturnPressed: event => {
                                if (event.modifiers & Qt.ControlModifier)
                                    win.generate()
                                else
                                    event.accepted = false
                            }
                        }
                    }

                    // A change keeps its base image's size, so there's no size to pick.
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        visible: win.baseImage === ""
                        Label { text: qsTr("Size"); color: win.muted; font.pixelSize: 12 }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6
                            Repeater {
                                model: [qsTr("Square"), qsTr("Screen"), qsTr("Portrait")]
                                delegate: Button {
                                    id: sizeButton
                                    required property int index
                                    required property string modelData
                                    objectName: "size" + index
                                    Layout.fillWidth: true
                                    text: modelData
                                    flat: win.sizeChoice !== index
                                    highlighted: win.sizeChoice === index
                                    focusPolicy: Qt.NoFocus
                                    Material.roundedScale: theme.radius
                                    onClicked: win.sizeChoice = index
                                    contentItem: Label {
                                        text: sizeButton.text
                                        font: sizeButton.font
                                        color: sizeButton.highlighted ? theme.accentForeground : theme.foreground
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                        elide: Text.ElideRight
                                    }
                                }
                            }
                        }
                        Label {
                            text: win.outputSize.width + " × " + win.outputSize.height
                            color: win.muted
                            font.pixelSize: 12
                        }
                    }

                    Item { Layout.fillHeight: true }

                    // What the model can do now, and the one thing to press.
                    Label {
                        objectName: "modelLine"
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        color: win.muted
                        font.pixelSize: 12
                        text: {
                            switch (models.state) {
                            case "ready": return generator.busy ? qsTr("%1 is making your image").arg(models.modelName)
                                                                : qsTr("%1 is ready").arg(models.modelName)
                            case "starting": return qsTr("Starting %1…").arg(models.modelName)
                            case "installing": return qsTr("Setting up %1…").arg(models.modelName)
                            case "installed": return qsTr("%1 is set up but not running").arg(models.modelName)
                            case "blocked": return qsTr("%1 needs the memory %2 is using").arg(models.modelName).arg(models.blockers.join(", "))
                            case "installable": return qsTr("No image model is set up. %1 runs on this machine.").arg(models.modelName)
                            case "none": return qsTr("No image model runs on this machine yet.") + (models.reason ? " " + models.reason : "")
                            case "noEngine": return qsTr("Fantasi makes images with Omarchy's local models, which aren't installed.")
                            default: return ""
                            }
                        }
                    }
                    Label {
                        objectName: "error"
                        Layout.fillWidth: true
                        visible: text !== ""
                        wrapMode: Text.Wrap
                        color: theme.colors.red
                        font.pixelSize: 12
                        text: models.error || generator.error || backend.error
                    }
                    Button {
                        id: action
                        objectName: "action"
                        Layout.fillWidth: true
                        visible: ["ready", "installed", "blocked", "installable", "starting", "installing"].indexOf(models.state) >= 0
                        highlighted: true
                        focusPolicy: Qt.NoFocus
                        Material.roundedScale: theme.radius
                        enabled: models.state === "ready" ? (generator.busy || prompt.text.trim() !== "")
                               : ["installed", "blocked", "installable"].indexOf(models.state) >= 0 && !models.working
                        text: {
                            switch (models.state) {
                            case "ready": return generator.busy ? qsTr("Cancel") : qsTr("Generate")
                            case "installed": return qsTr("Start %1").arg(models.modelName)
                            case "blocked": return qsTr("Stop %1 and start %2").arg(models.blockers.join(", ")).arg(models.modelName)
                            case "installable": return qsTr("Install %1").arg(models.modelName)
                            case "starting": return qsTr("Starting…")
                            default: return qsTr("Setting up…")
                            }
                        }
                        onClicked: {
                            switch (models.state) {
                            case "ready": generator.busy ? generator.cancel() : win.generate(); break
                            case "installed": models.start(); break
                            case "blocked": models.switchTo(); break
                            case "installable": models.install(); break
                            }
                        }
                        contentItem: Label {
                            text: action.text
                            font: action.font
                            color: theme.accentForeground
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            elide: Text.ElideRight
                        }
                    }
                }
            }

            Rectangle { Layout.preferredWidth: 1; Layout.fillHeight: true; color: win.line }

            // ------------------------------------------------------------- image
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.margins: 22
                spacing: 14

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    Image {
                        id: shown
                        objectName: "image"
                        anchors.fill: parent
                        source: generator.image
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                        smooth: true
                        visible: generator.image !== ""
                    }
                    Label {
                        anchors.centerIn: parent
                        width: parent.width * 0.6
                        visible: generator.image === ""
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                        color: win.muted
                        text: generator.busy ? qsTr("Preparing the model…") : qsTr("Your image appears here")
                    }
                }

                // The steps so far, each as it looked then.
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.maximumWidth: 640
                    Layout.alignment: Qt.AlignHCenter
                    visible: generator.previews.length > 0
                    spacing: 8

                    RowLayout {
                        Layout.fillWidth: true
                        Label {
                            Layout.fillWidth: true
                            color: win.muted
                            font.pixelSize: 12
                            text: {
                                switch (generator.stage) {
                                case "queued": return qsTr("Waiting for the model")
                                case "conditioning": return qsTr("Reading the prompt")
                                case "sampling": return qsTr("Step %1 of %2").arg(generator.step).arg(generator.totalSteps)
                                case "decoding": return qsTr("Finishing")
                                case "saving": return qsTr("Saving")
                                default: return qsTr("%Ln steps", "", generator.totalSteps)
                                }
                            }
                        }
                    }
                    GridLayout {
                        Layout.fillWidth: true
                        columns: Math.max(1, generator.previews.length)
                        columnSpacing: 6
                        Repeater {
                            model: generator.previews
                            delegate: Rectangle {
                                required property int index
                                required property string modelData
                                Layout.fillWidth: true
                                Layout.preferredHeight: width
                                color: "transparent"
                                border.color: generator.busy && index === generator.step - 1 ? theme.accent : win.line
                                border.width: generator.busy && index === generator.step - 1 ? 2 : 1
                                radius: Math.min(4, theme.radius)
                                Image {
                                    anchors.fill: parent
                                    anchors.margins: parent.border.width
                                    source: modelData
                                    fillMode: Image.PreserveAspectCrop
                                    visible: modelData !== ""
                                }
                            }
                        }
                    }
                }

                // What to do with the image. A Flow wraps when the column is
                // narrow, where a row would push the history out of the window.
                Flow {
                    Layout.fillWidth: true
                    Layout.preferredHeight: implicitHeight
                    spacing: 4
                    visible: win.shownFile !== "" || generator.unsaved
                    Repeater {
                        model: [
                            { label: qsTr("Change this image"), key: "Ctrl+E", run: () => win.changeImage(), show: win.shownFile !== "" },
                            { label: qsTr("Set as background"), key: "Ctrl+B", run: () => backend.setBackground(win.shownFile), show: win.shownFile !== "" },
                            { label: qsTr("Copy"), key: "Ctrl+Shift+C", run: () => backend.copy(win.shownFile), show: win.shownFile !== "" },
                            { label: qsTr("Save as…"), key: "Ctrl+S", run: () => backend.saveAs(win.shownFile), show: win.shownFile !== "" },
                            { label: qsTr("Again"), key: "Ctrl+R", run: () => win.generate(), show: win.shownFile !== "" },
                            { label: qsTr("Try saving again"), key: "", run: () => generator.retrySave(), show: generator.unsaved }
                        ]
                        delegate: Button {
                            required property var modelData
                            visible: modelData.show
                            flat: true
                            focusPolicy: Qt.NoFocus
                            Material.roundedScale: theme.radius
                            text: modelData.label
                            // The key is in the tooltip and on F1.
                            ToolTip.visible: hovered && modelData.key !== ""
                            ToolTip.text: modelData.key
                            ToolTip.delay: 600
                            onClicked: modelData.run()
                        }
                    }
                }
            }

            Rectangle { Layout.preferredWidth: 1; Layout.fillHeight: true; color: win.line }

            // ----------------------------------------------------------- history
            // A rail of its own width: its list fills the column, which would
            // otherwise make the column take the image's space.
            ColumnLayout {
                Layout.preferredWidth: 124
                Layout.maximumWidth: 124
                Layout.fillWidth: false
                Layout.fillHeight: true
                Layout.margins: 14
                spacing: 10

                Label { text: qsTr("History"); color: win.muted; font.pixelSize: 12 }
                ListView {
                    id: historyList
                    objectName: "history"
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 10
                    currentIndex: -1
                    model: history
                    delegate: Item {
                        id: entry
                        required property int index
                        required property string url
                        required property string prompt
                        width: ListView.view.width
                        height: width
                        Image {
                            anchors.fill: parent
                            source: entry.url
                            sourceSize: Qt.size(192, 192)
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                        }
                        Rectangle {
                            anchors.fill: parent
                            color: "transparent"
                            border.color: theme.accent
                            border.width: 2
                            visible: entry.ListView.isCurrentItem
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: win.pick(entry.index)
                            // Takes the image's prompt back into the panel.
                            onDoubleClicked: {
                                win.pick(entry.index)
                                prompt.text = entry.prompt
                            }
                        }
                    }
                }
                Label {
                    Layout.fillWidth: true
                    visible: history.count === 0
                    wrapMode: Text.Wrap
                    color: win.muted
                    font.pixelSize: 12
                    text: qsTr("Your images appear here")
                }
            }
        }
    }

    Popup {
        id: help
        objectName: "help"
        anchors.centerIn: Overlay.overlay
        modal: true
        focus: true
        padding: 24
        background: Rectangle {
            color: theme.background
            border.color: win.line
            radius: theme.radius
        }

        ColumnLayout {
            spacing: 8
            LayoutMirroring.enabled: win.rightToLeft
            LayoutMirroring.childrenInherit: true

            Repeater {
                model: [
                    { keys: "Ctrl+Enter", action: qsTr("Make the image") },
                    { keys: "Esc", action: qsTr("Stop making it, or go back to a new image") },
                    { keys: "Ctrl+R", action: qsTr("Make another like it") },
                    { keys: "Ctrl+E", action: qsTr("Change it: the next image starts from it") },
                    { keys: "Ctrl+O", action: qsTr("Start from a picture of your own") },
                    { keys: "Ctrl+1 2 3", action: qsTr("Square, screen or portrait") },
                    { keys: "Ctrl+B", action: qsTr("Set it as the background") },
                    { keys: "Ctrl+Shift+C", action: qsTr("Copy it") },
                    { keys: "Ctrl+S", action: qsTr("Save a copy somewhere else") },
                    { keys: "Ctrl+↑ ↓", action: qsTr("Move through the history") },
                    { keys: "Ctrl+Delete", action: qsTr("Move it to the trash") },
                    { keys: "F1", action: qsTr("Show or hide the shortcuts") },
                    { keys: "Ctrl+Q", action: qsTr("Quit") }
                ]
                delegate: RowLayout {
                    required property var modelData
                    spacing: 24
                    Label {
                        Layout.preferredWidth: 120
                        text: modelData.keys
                        color: theme.accent
                        font.bold: true
                    }
                    Label { text: modelData.action }
                }
            }
        }
    }
}
