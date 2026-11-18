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

    // The theme's own colors, said in the prompt when asked for.
    readonly property var themePalette: ["background", "selection", "blue", "accent", "foreground"].map(key => theme.colors[key] || (key === "accent" ? theme.accent : theme.foreground))
    function promptText() {
        if (!themeColors.checked)
            return prompt.text
        // English, whatever the language: the model reads English best.
        return prompt.text.trim() + ". Use the color palette " + themePalette.map(c => c.toString()).join(", ")
    }
    function generate(seed) {
        if (!canGenerate)
            return
        const fixed = seedField.text.trim() === "" ? -1 : Number(seedField.text)
        generator.generate(promptText(), outputSize.width, outputSize.height, steps.value, seed !== undefined ? seed : fixed)
    }
    // Shows a history image, and takes its prompt and seed into the panel.
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
    Shortcut { sequence: "Ctrl+R"; enabled: win.canGenerate; onActivated: win.generate(-1) }
    Shortcut { sequence: "Escape"; enabled: generator.busy; onActivated: generator.cancel() }
    Shortcut { sequence: "Ctrl+1"; onActivated: win.sizeChoice = 0 }
    Shortcut { sequence: "Ctrl+2"; onActivated: win.sizeChoice = 1 }
    Shortcut { sequence: "Ctrl+3"; onActivated: win.sizeChoice = 2 }
    Shortcut { sequence: "Ctrl+B"; enabled: win.shownFile !== ""; onActivated: backend.setBackground(win.shownFile) }
    Shortcut { sequence: "Ctrl+Shift+C"; enabled: win.shownFile !== ""; onActivated: backend.copy(win.shownFile) }
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

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        ScrollView {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 132
                            TextArea {
                                id: prompt
                                objectName: "prompt"
                                focus: true
                                wrapMode: TextEdit.Wrap
                                placeholderText: qsTr("Describe an image")
                                Material.roundedScale: theme.radius
                                Keys.onReturnPressed: event => {
                                    if (event.modifiers & Qt.ControlModifier)
                                        win.generate()
                                    else
                                        event.accepted = false
                                }
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 6
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

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 6
                            Label { text: qsTr("Steps"); color: win.muted; font.pixelSize: 12 }
                            SpinBox {
                                id: steps
                                Layout.fillWidth: true
                                from: 1
                                to: 60
                                value: generator.defaultSteps
                                editable: true
                                Material.roundedScale: theme.radius
                            }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 6
                            Label { text: qsTr("Seed"); color: win.muted; font.pixelSize: 12 }
                            TextField {
                                id: seedField
                                Layout.fillWidth: true
                                placeholderText: qsTr("Random")
                                validator: RegularExpressionValidator { regularExpression: /[0-9]{0,18}/ }
                                Material.roundedScale: theme.radius
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4
                        CheckBox {
                            id: themeColors
                            objectName: "themeColors"
                            text: qsTr("Use the theme's colors")
                            leftPadding: 0
                            focusPolicy: Qt.NoFocus
                        }
                        Row {
                            spacing: 4
                            opacity: themeColors.checked ? 1 : 0.4
                            Repeater {
                                model: win.themePalette
                                delegate: Rectangle {
                                    required property color modelData
                                    width: 22
                                    height: 22
                                    color: modelData
                                    border.color: win.line
                                    radius: Math.min(4, theme.radius)
                                }
                            }
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
                        text: models.error || generator.error
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
                            case "blocked": return qsTr("Stop %1 and start").arg(models.blockers.join(", "))
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

                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 8
                    visible: win.shownFile !== "" || generator.unsaved
                    Repeater {
                        model: [
                            { label: qsTr("Set as background"), key: "Ctrl+B", run: () => backend.setBackground(win.shownFile), show: win.shownFile !== "" },
                            { label: qsTr("Copy"), key: "Ctrl+Shift+C", run: () => backend.copy(win.shownFile), show: win.shownFile !== "" },
                            { label: qsTr("Again"), key: "Ctrl+R", run: () => win.generate(-1), show: win.shownFile !== "" },
                            { label: qsTr("Try saving again"), key: "", run: () => generator.retrySave(), show: generator.unsaved }
                        ]
                        delegate: Button {
                            required property var modelData
                            visible: modelData.show
                            flat: true
                            focusPolicy: Qt.NoFocus
                            Material.roundedScale: theme.radius
                            text: modelData.key ? modelData.label + "  " + modelData.key : modelData.label
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
                        required property var seed
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
                            // Takes the image's prompt and seed back into the panel.
                            onDoubleClicked: {
                                win.pick(entry.index)
                                prompt.text = entry.prompt
                                seedField.text = entry.seed >= 0 ? String(entry.seed) : ""
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
                    { keys: "Esc", action: qsTr("Stop making it") },
                    { keys: "Ctrl+R", action: qsTr("Make another with a new seed") },
                    { keys: "Ctrl+1 2 3", action: qsTr("Square, screen or portrait") },
                    { keys: "Ctrl+B", action: qsTr("Set it as the background") },
                    { keys: "Ctrl+Shift+C", action: qsTr("Copy it") },
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
