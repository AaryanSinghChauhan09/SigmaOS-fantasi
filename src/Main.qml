import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

ApplicationWindow {
    id: win
    width: 1200
    height: 800
    minimumWidth: 900
    minimumHeight: 600
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
    // The image the next one changes, while changing one. Each change that
    // finishes becomes the base for the next, until it's let go.
    property string baseImage: ""
    readonly property bool changing: baseImage !== ""

    // The model's own steps and a new seed every time: what matters is said
    // in the prompt. While changing, the prompt says what to change.
    function generate() {
        if (canGenerate)
            generator.generate(prompt.text, outputSize.width, outputSize.height, 0, -1, baseImage, models.edits)
    }
    // Makes the shown image the one to change, with an empty prompt for
    // what should change.
    function changeImage() {
        if (shownFile === "" || generator.busy)
            return
        baseImage = shownFile
        prompt.text = ""
        prompt.forceActiveFocus()
    }
    // A picture of the user's own becomes the one to change.
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
    // Esc stops an image being made, or else goes back to a new image.
    Shortcut { sequence: "Escape"; enabled: generator.busy; onActivated: generator.cancel() }
    Shortcut { sequence: "Escape"; enabled: !generator.busy && win.changing; onActivated: win.baseImage = "" }
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

    Connections {
        target: generator
        // A new image shows first in the history, selected; a change that
        // finishes is the next one to change.
        function onSaved() {
            historyList.currentIndex = 0
            if (win.changing) {
                win.baseImage = generator.image
                prompt.text = ""
            }
        }
    }
    Connections {
        target: backend
        function onPictureChosen(url) { win.startFrom(url) }
    }

    // A picture dropped anywhere on the window becomes the one to change,
    // but not while an image is being made, so a drop then is refused.
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

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.margins: 20
                spacing: 12

                // ----------------------------------------------------- the image
                Item {
                    id: stage
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    // The shape the image will have: the one shown once it's
                    // there, the size asked for while it isn't.
                    readonly property real aspect: shown.status === Image.Ready && shown.implicitHeight > 0
                                                   ? shown.implicitWidth / shown.implicitHeight
                                                   : win.outputSize.width / win.outputSize.height

                    Item {
                        id: frame
                        anchors.centerIn: parent
                        width: Math.min(parent.width, parent.height * stage.aspect)
                        height: width / stage.aspect
                        visible: generator.busy || generator.image !== ""

                        Rectangle {
                            anchors.fill: parent
                            color: win.panel
                            radius: Math.min(4, theme.radius)
                            visible: generator.image === ""
                        }
                        Image {
                            id: shown
                            objectName: "image"
                            anchors.fill: parent
                            source: generator.image
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                            smooth: true
                        }

                        // While it's being made, a soft glow breathes around it
                        // and a band of light sweeps across, so it's plain the
                        // work isn't done even before the first step shows.
                        Rectangle {
                            objectName: "working"
                            anchors.fill: parent
                            anchors.margins: -5
                            color: "transparent"
                            border.color: theme.accent
                            border.width: 2
                            radius: Math.min(6, theme.radius + 3)
                            visible: generator.busy
                            SequentialAnimation on opacity {
                                running: generator.busy
                                loops: Animation.Infinite
                                NumberAnimation { from: 0.25; to: 0.85; duration: 900; easing.type: Easing.InOutSine }
                                NumberAnimation { from: 0.85; to: 0.25; duration: 900; easing.type: Easing.InOutSine }
                            }
                        }
                        Item {
                            anchors.fill: parent
                            clip: true
                            visible: generator.busy
                            Rectangle {
                                width: frame.width * 0.45
                                height: frame.height * 2
                                y: -frame.height / 2
                                rotation: 18
                                gradient: Gradient {
                                    orientation: Gradient.Horizontal
                                    GradientStop { position: 0.0; color: "transparent" }
                                    GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, theme.light ? 0.28 : 0.14) }
                                    GradientStop { position: 1.0; color: "transparent" }
                                }
                                NumberAnimation on x {
                                    running: generator.busy
                                    loops: Animation.Infinite
                                    from: -frame.width * 0.6
                                    to: frame.width * 1.1
                                    duration: 1800
                                    easing.type: Easing.InOutSine
                                }
                            }
                        }
                    }
                    Label {
                        anchors.centerIn: parent
                        width: parent.width * 0.6
                        visible: !frame.visible
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                        color: win.muted
                        text: qsTr("Your image appears here")
                    }
                }

                // How far along it is, under the image.
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 2
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: frame.width
                        height: 2
                        color: win.line
                        visible: generator.busy && generator.totalSteps > 0
                        Rectangle {
                            width: parent.width * Math.min(1, generator.step / Math.max(1, generator.totalSteps))
                            height: 2
                            color: theme.accent
                            Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
                        }
                    }
                }

                // What to do with the image. A Flow wraps when the window is
                // narrow, where a row would push the history out of it.
                Flow {
                    Layout.fillWidth: true
                    Layout.preferredHeight: implicitHeight
                    spacing: 4
                    visible: !generator.busy && (win.shownFile !== "" || generator.unsaved)
                    Repeater {
                        model: [
                            { label: qsTr("Change this image"), key: "Ctrl+E", run: () => win.changeImage(), show: win.shownFile !== "" },
                            { label: qsTr("Set as background"), key: "Ctrl+B", run: () => backend.setBackground(win.shownFile), show: win.shownFile !== "" },
                            { label: qsTr("Copy"), key: "Ctrl+Shift+C", run: () => backend.copy(win.shownFile), show: win.shownFile !== "" },
                            { label: qsTr("Save as…"), key: "Ctrl+S", run: () => backend.saveAs(win.shownFile), show: win.shownFile !== "" },
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

                // ------------------------------------------------ the prompt bar
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: bar.implicitHeight + 16
                    color: win.panel
                    radius: Math.min(8, theme.radius + 4)
                    border.color: prompt.activeFocus ? theme.accent : win.line

                    RowLayout {
                        id: bar
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 8

                        // The image being changed, like an attachment: its
                        // thumbnail, with a × to go back to a new image.
                        Item {
                            objectName: "base"
                            Layout.preferredWidth: 48
                            Layout.preferredHeight: 48
                            Layout.alignment: Qt.AlignVCenter
                            visible: win.changing
                            Image {
                                anchors.fill: parent
                                source: win.baseImage
                                sourceSize: Qt.size(96, 96)
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                            }
                            ToolTip.visible: baseHover.hovered
                            ToolTip.text: qsTr("Changing this image")
                            HoverHandler { id: baseHover }
                            // The × sits on the thumbnail's corner, as on an attachment.
                            ToolButton {
                                id: letGo
                                width: 22
                                height: 22
                                padding: 0
                                anchors.top: parent.top
                                anchors.right: parent.right
                                anchors.topMargin: -7
                                anchors.rightMargin: -7
                                focusPolicy: Qt.NoFocus
                                Accessible.name: qsTr("Make a new image instead")
                                onClicked: win.baseImage = ""
                                background: Rectangle {
                                    radius: width / 2
                                    color: letGo.hovered ? theme.colors.selection : theme.background
                                    border.color: win.line
                                }
                                contentItem: Label {
                                    text: "×"
                                    color: theme.foreground
                                    font.pixelSize: 15
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                            }
                        }

                        // Or start from a picture of one's own, which a drop
                        // onto the window does too.
                        ToolButton {
                            objectName: "startFrom"
                            Layout.alignment: Qt.AlignVCenter
                            visible: !win.changing
                            focusPolicy: Qt.NoFocus
                            Accessible.name: qsTr("Start from a picture…")
                            ToolTip.visible: hovered
                            ToolTip.text: qsTr("Start from a picture…") + "  Ctrl+O"
                            ToolTip.delay: 400
                            onClicked: backend.openPicture()
                            // A picture frame with a plus.
                            contentItem: Item {
                                implicitWidth: 22
                                implicitHeight: 22
                                Rectangle {
                                    anchors.centerIn: parent
                                    width: 18
                                    height: 15
                                    color: "transparent"
                                    border.color: win.muted
                                    border.width: 1.5
                                    radius: 2
                                }
                                Label {
                                    anchors.centerIn: parent
                                    text: "+"
                                    color: win.muted
                                    font.pixelSize: 14
                                    font.bold: true
                                }
                            }
                        }

                        ScrollView {
                            Layout.fillWidth: true
                            Layout.preferredHeight: Math.min(Math.max(prompt.implicitHeight, 40), 96)
                            Layout.alignment: Qt.AlignVCenter
                            TextArea {
                                id: prompt
                                objectName: "prompt"
                                focus: true
                                wrapMode: TextEdit.Wrap
                                background: null
                                topPadding: 10
                                bottomPadding: 10
                                // Drawn here: Material floats its own placeholder up
                                // as a label, out of this borderless bar.
                                Label {
                                    x: prompt.leftPadding
                                    y: prompt.topPadding
                                    visible: prompt.length === 0 && prompt.preeditText === ""
                                    color: win.muted
                                    font: prompt.font
                                    text: win.changing ? qsTr("What should change?") : qsTr("Describe an image")
                                }
                                Keys.onReturnPressed: event => {
                                    if (event.modifiers & Qt.ControlModifier)
                                        win.generate()
                                    else
                                        event.accepted = false
                                }
                            }
                        }

                        // The shape of a new image; a change keeps its own.
                        Row {
                            Layout.alignment: Qt.AlignVCenter
                            visible: !win.changing
                            spacing: 0
                            Repeater {
                                model: [
                                    { name: qsTr("Square"), w: 14, h: 14 },
                                    { name: qsTr("Screen"), w: 18, h: 11 },
                                    { name: qsTr("Portrait"), w: 11, h: 18 }
                                ]
                                delegate: ToolButton {
                                    id: sizeButton
                                    required property int index
                                    required property var modelData
                                    objectName: "size" + index
                                    checkable: true
                                    checked: win.sizeChoice === index
                                    focusPolicy: Qt.NoFocus
                                    Accessible.name: modelData.name
                                    ToolTip.visible: hovered
                                    ToolTip.text: modelData.name + "  " + (index === 1 ? backend.screenSize.width + " × " + backend.screenSize.height
                                                                                      : index === 2 ? "832 × 1216" : "1024 × 1024")
                                    ToolTip.delay: 400
                                    onClicked: win.sizeChoice = index
                                    contentItem: Item {
                                        implicitWidth: 22
                                        implicitHeight: 22
                                        Rectangle {
                                            anchors.centerIn: parent
                                            width: sizeButton.modelData.w
                                            height: sizeButton.modelData.h
                                            color: sizeButton.checked ? theme.accent : "transparent"
                                            border.color: sizeButton.checked ? theme.accent : win.muted
                                            border.width: 1.5
                                            radius: 2
                                        }
                                    }
                                }
                            }
                        }

                        Button {
                            id: action
                            objectName: "action"
                            Layout.alignment: Qt.AlignVCenter
                            visible: ["ready", "installed", "blocked", "installable", "starting", "installing"].indexOf(models.state) >= 0
                            highlighted: true
                            focusPolicy: Qt.NoFocus
                            Material.roundedScale: theme.radius
                            topInset: 0
                            bottomInset: 0
                            leftPadding: 16
                            rightPadding: 16
                            enabled: models.state === "ready" ? (generator.busy || prompt.text.trim() !== "")
                                   : ["installed", "blocked", "installable"].indexOf(models.state) >= 0 && !models.working
                            text: {
                                switch (models.state) {
                                case "ready": return generator.busy ? qsTr("Cancel") : win.changing ? qsTr("Change") : qsTr("Generate")
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

                // The model's state, what went wrong, and how far along it is.
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12
                    Label {
                        objectName: "modelLine"
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        color: win.muted
                        font.pixelSize: 12
                        visible: error.text === ""
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
                        id: error
                        objectName: "error"
                        Layout.fillWidth: true
                        visible: text !== ""
                        elide: Text.ElideRight
                        color: theme.colors.red
                        font.pixelSize: 12
                        text: models.error || generator.error || backend.error
                    }
                    Label {
                        color: win.muted
                        font.pixelSize: 12
                        visible: generator.busy
                        text: {
                            switch (generator.stage) {
                            case "queued": return qsTr("Waiting for the model")
                            case "conditioning": return qsTr("Reading the prompt")
                            case "sampling": return qsTr("Step %1 of %2").arg(generator.step).arg(generator.totalSteps)
                            case "decoding": return qsTr("Finishing")
                            case "saving": return qsTr("Saving")
                            default: return qsTr("Preparing the model…")
                            }
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
                            // Takes the image's prompt back into the bar.
                            onDoubleClicked: {
                                win.pick(entry.index)
                                win.baseImage = ""
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
                    { keys: "Ctrl+E", action: qsTr("Change it: say what should change") },
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
