import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import QtQuick.Shapes

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
    readonly property string problem: models.error || generator.error || backend.error
    // What the model is doing, for its icon's tooltip and the empty stage.
    readonly property string modelStatus: {
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
    // What was last sent, to tell it from what is typed while it's made.
    property string sentPrompt
    // How far along the image is being made, 0 to 1: the steps, then whole
    // once they're done and it's finishing.
    readonly property real progress: !generator.busy ? 0
        : generator.stage === "decoding" || generator.stage === "saving" ? 1
        : generator.totalSteps > 0 ? Math.min(1, generator.step / generator.totalSteps) : 0

    // The model's own steps and a new seed every time: what matters is said
    // in the prompt. While changing, the prompt says what to change.
    function generate() {
        if (!canGenerate)
            return
        sentPrompt = prompt.text
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
                // Unless the next instruction is already being typed.
                if (prompt.text === win.sentPrompt)
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
                                                   : previous.status === Image.Ready && previous.implicitHeight > 0
                                                   ? previous.implicitWidth / previous.implicitHeight
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
                        // While a picture is being changed, it stays in the frame,
                        // faded, and the new one grows in over it as it's made.
                        Image {
                            id: previous
                            anchors.fill: parent
                            source: generator.busy && win.changing ? win.baseImage : ""
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                            visible: source !== ""
                            opacity: 0.45 * (1 - win.progress)
                            Behavior on opacity { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
                        }
                        Image {
                            id: shown
                            objectName: "image"
                            anchors.fill: parent
                            source: generator.image
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                            smooth: true
                            opacity: generator.busy && win.changing ? 0.2 + 0.8 * win.progress : 1
                            Behavior on opacity { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
                        }

                        // While it's being made, its edge says how far along it is:
                        // a faint track, an accent line growing clockwise from
                        // the top with each step, and a bright spark circling
                        // all the while, so it's plainly at work even before the
                        // first step.
                        Shape {
                            id: edge
                            objectName: "working"
                            anchors.fill: parent
                            anchors.margins: -5
                            visible: generator.busy
                            preferredRendererType: Shape.CurveRenderer
                            readonly property real perimeter: 2 * (width + height)
                            readonly property real line: 2
                            readonly property real spark: 3
                            readonly property var outline: [Qt.point(width / 2, 0), Qt.point(width, 0), Qt.point(width, height),
                                                            Qt.point(0, height), Qt.point(0, 0), Qt.point(width / 2, 0)]
                            property real shown: win.progress
                            Behavior on shown { NumberAnimation { duration: 500; easing.type: Easing.OutCubic } }
                            property real travel: 0
                            NumberAnimation on travel {
                                running: generator.busy
                                loops: Animation.Infinite
                                from: 0
                                to: 1
                                duration: 2400
                            }

                            ShapePath {
                                strokeColor: Qt.rgba(theme.accent.r, theme.accent.g, theme.accent.b, 0.22)
                                strokeWidth: edge.line
                                fillColor: "transparent"
                                joinStyle: ShapePath.MiterJoin
                                PathPolyline { path: edge.outline }
                            }
                            ShapePath {
                                strokeColor: theme.accent
                                strokeWidth: edge.line
                                fillColor: "transparent"
                                joinStyle: ShapePath.MiterJoin
                                capStyle: ShapePath.FlatCap
                                strokeStyle: ShapePath.DashLine
                                // A dash as long as the share done, then a gap
                                // as long as the whole: in units of the width.
                                dashPattern: [Math.max(0.01, edge.perimeter * edge.shown / edge.line), edge.perimeter / edge.line]
                                PathPolyline { path: edge.outline }
                            }
                            ShapePath {
                                strokeColor: Qt.lighter(theme.accent, 1.35)
                                strokeWidth: edge.spark
                                fillColor: "transparent"
                                capStyle: ShapePath.RoundCap
                                strokeStyle: ShapePath.DashLine
                                dashPattern: [edge.perimeter * 0.06 / edge.spark, edge.perimeter * 0.94 / edge.spark]
                                dashOffset: edge.perimeter * (1 - edge.travel) / edge.spark
                                PathPolyline { path: edge.outline }
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
                    // What to do with a finished image: a small bar of icons on
                    // it, their names and keys in tooltips.
                    Rectangle {
                        objectName: "tools"
                        anchors.bottom: frame.bottom
                        anchors.bottomMargin: 14
                        anchors.horizontalCenter: frame.horizontalCenter
                        width: tools.implicitWidth + 12
                        height: tools.implicitHeight + 8
                        radius: Math.min(height / 2, theme.radius + 6)
                        color: Qt.rgba(theme.background.r, theme.background.g, theme.background.b, 0.82)
                        border.color: Qt.rgba(theme.foreground.r, theme.foreground.g, theme.foreground.b, 0.12)
                        readonly property bool ready: win.shownFile !== "" && !generator.busy
                        visible: opacity > 0
                        opacity: ready ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                        Row {
                            id: tools
                            anchors.centerIn: parent
                            spacing: 2
                            Repeater {
                                model: [
                                    { icon: "change", label: qsTr("Change this image"), key: "Ctrl+E", run: () => win.changeImage() },
                                    { icon: "background", label: qsTr("Set as background"), key: "Ctrl+B", run: () => backend.setBackground(win.shownFile) },
                                    { icon: "copy", label: qsTr("Copy"), key: "Ctrl+Shift+C", run: () => backend.copy(win.shownFile) },
                                    { icon: "save", label: qsTr("Save as…"), key: "Ctrl+S", run: () => backend.saveAs(win.shownFile) }
                                ]
                                delegate: ToolButton {
                                    required property var modelData
                                    focusPolicy: Qt.NoFocus
                                    display: AbstractButton.IconOnly
                                    icon.source: "qrc:/icons/" + modelData.icon + ".svg"
                                    icon.width: 20
                                    icon.height: 20
                                    icon.color: hovered ? theme.accent : theme.foreground
                                    Accessible.name: modelData.label
                                    ToolTip.visible: hovered
                                    ToolTip.text: modelData.label + "  " + modelData.key
                                    ToolTip.delay: 300
                                    onClicked: modelData.run()
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
                        text: models.state === "ready" ? qsTr("Your image appears here") : win.modelStatus
                    }

                    // What went wrong, over the top of the image.
                    Rectangle {
                        objectName: "problem"
                        anchors.top: parent.top
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.topMargin: 10
                        width: Math.min(parent.width - 24, problemRow.implicitWidth + 24)
                        height: problemRow.implicitHeight + 12
                        radius: Math.min(height / 2, theme.radius + 6)
                        visible: win.problem !== ""
                        color: Qt.rgba(theme.background.r, theme.background.g, theme.background.b, 0.9)
                        border.color: theme.colors.red
                        RowLayout {
                            id: problemRow
                            anchors.centerIn: parent
                            width: Math.min(implicitWidth, parent.width - 24)
                            spacing: 8
                            Label {
                                id: error
                                objectName: "error"
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                color: theme.colors.red
                                font.pixelSize: 13
                                text: win.problem
                            }
                            Button {
                                visible: generator.unsaved
                                flat: true
                                focusPolicy: Qt.NoFocus
                                topInset: 0
                                bottomInset: 0
                                Material.roundedScale: theme.radius
                                text: qsTr("Try saving again")
                                onClicked: generator.retrySave()
                            }
                        }
                    }
                    // The shortcuts, out of the way in the corner.
                    ToolButton {
                        objectName: "shortcuts"
                        anchors.top: parent.top
                        anchors.right: parent.right
                        focusPolicy: Qt.NoFocus
                        text: "?"
                        font.pixelSize: 15
                        Material.foreground: hovered ? theme.accent : win.muted
                        Accessible.name: qsTr("Show or hide the shortcuts")
                        ToolTip.visible: hovered
                        ToolTip.text: qsTr("Show or hide the shortcuts") + "  F1"
                        ToolTip.delay: 300
                        onClicked: help.opened ? help.close() : help.open()
                    }
                }

                // ------------------------------------------------ the prompt bar
                // One pill: the picture to start from, the prompt, the shape,
                // the model, and the round button that sends it.
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: bar.implicitHeight + 12
                    color: win.panel
                    // A pill on every theme: its shape is the design, like a circle's.
                    radius: Math.min(height / 2, 28)
                    border.color: prompt.activeFocus ? theme.accent : win.line

                    RowLayout {
                        id: bar
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 6
                        anchors.topMargin: 6
                        anchors.bottomMargin: 6
                        spacing: 4

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
                                ToolTip.visible: hovered
                                ToolTip.text: qsTr("Make a new image instead") + "  Esc"
                                ToolTip.delay: 300
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
                                // Enter sends the prompt; Shift+Enter is a new line.
                                Keys.onReturnPressed: event => {
                                    if (event.modifiers & Qt.ShiftModifier)
                                        event.accepted = false
                                    else
                                        win.generate()
                                }
                                Keys.onEnterPressed: event => {
                                    if (event.modifiers & Qt.ShiftModifier)
                                        event.accepted = false
                                    else
                                        win.generate()
                                }
                            }
                        }

                        // The shape of a new image, one button that steps through
                        // square, screen and portrait; a change keeps its own.
                        ToolButton {
                            id: shape
                            objectName: "size"
                            Layout.alignment: Qt.AlignVCenter
                            visible: !win.changing
                            focusPolicy: Qt.NoFocus
                            readonly property var shapes: [
                                { name: qsTr("Square"), w: 15, h: 15 },
                                { name: qsTr("Screen"), w: 20, h: 12 },
                                { name: qsTr("Portrait"), w: 12, h: 20 }
                            ]
                            readonly property var current: shapes[win.sizeChoice]
                            Accessible.name: current.name
                            ToolTip.visible: hovered
                            ToolTip.text: current.name + "  " + win.outputSize.width + " × " + win.outputSize.height
                            ToolTip.delay: 400
                            onClicked: win.sizeChoice = (win.sizeChoice + 1) % 3
                            contentItem: Item {
                                implicitWidth: 24
                                implicitHeight: 24
                                Rectangle {
                                    anchors.centerIn: parent
                                    width: shape.current.w
                                    height: shape.current.h
                                    color: "transparent"
                                    border.color: shape.hovered ? theme.accent : win.muted
                                    border.width: 1.5
                                    radius: 2
                                    Behavior on width { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                                    Behavior on height { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                                }
                            }
                        }

                        // The model: its state as a dot, what it's doing in the
                        // tooltip, and with more than one set up, a click steps to
                        // the next.
                        ToolButton {
                            id: modelButton
                            objectName: "model"
                            Layout.alignment: Qt.AlignVCenter
                            focusPolicy: Qt.NoFocus
                            display: AbstractButton.IconOnly
                            icon.source: "qrc:/icons/model.svg"
                            icon.width: 20
                            icon.height: 20
                            icon.color: hovered && canStep ? theme.accent : win.muted
                            readonly property int current: models.choices.findIndex(c => c.id === models.modelId)
                            readonly property bool canStep: models.choices.length > 1 && !models.working && !generator.busy
                            readonly property var next: models.choices.length > 1 ? models.choices[(current + 1) % models.choices.length] : null
                            Accessible.name: win.modelStatus
                            ToolTip.visible: hovered
                            ToolTip.text: win.modelStatus + (canStep ? "\n" + qsTr("Click to use %1").arg(next.name) : "")
                            ToolTip.delay: 300
                            onClicked: if (canStep) models.choose(next.id)
                            Rectangle {
                                width: 7
                                height: 7
                                radius: 3.5
                                x: parent.width - width - 9
                                y: 9
                                visible: models.state !== "noEngine"
                                color: win.problem ? theme.colors.red
                                     : models.state === "ready" ? theme.accent : win.muted
                                SequentialAnimation on opacity {
                                    running: models.state === "starting" || models.state === "installing" || models.working
                                    loops: Animation.Infinite
                                    onRunningChanged: if (!running) parent.opacity = 1
                                    NumberAnimation { from: 1; to: 0.3; duration: 700; easing.type: Easing.InOutSine }
                                    NumberAnimation { from: 0.3; to: 1; duration: 700; easing.type: Easing.InOutSine }
                                }
                            }
                        }

                        Rectangle {
                            Layout.preferredWidth: 1
                            Layout.preferredHeight: 20
                            Layout.leftMargin: 2
                            Layout.rightMargin: 4
                            Layout.alignment: Qt.AlignVCenter
                            color: win.line
                        }

                        // Ready, a round arrow to send (a square to stop while
                        // it's making one); otherwise, in words, what gets a
                        // model going.
                        Button {
                            id: action
                            objectName: "action"
                            readonly property bool round: models.state === "ready"
                            Layout.alignment: Qt.AlignVCenter
                            Layout.preferredWidth: round ? 36 : implicitWidth
                            Layout.preferredHeight: 36
                            visible: ["ready", "installed", "blocked", "installable", "starting", "installing"].indexOf(models.state) >= 0
                            focusPolicy: Qt.NoFocus
                            topInset: 0
                            bottomInset: 0
                            leftInset: 0
                            rightInset: 0
                            padding: round ? 0 : 14
                            Accessible.name: text
                            ToolTip.visible: round && hovered
                            ToolTip.text: text + (generator.busy ? "  Esc" : "  Enter")
                            ToolTip.delay: 400
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
                            contentItem: Item {
                                id: face
                                // What's drawn on the accent: the arrow, the square or the words.
                                readonly property color color: theme.accentForeground
                                implicitWidth: action.round ? 20 : caption.implicitWidth
                                implicitHeight: 20
                                Label {
                                    id: caption
                                    anchors.centerIn: parent
                                    visible: !action.round
                                    text: action.text
                                    font: action.font
                                    color: face.color
                                }
                                // An arrow up to send.
                                Shape {
                                    anchors.centerIn: parent
                                    width: 16
                                    height: 16
                                    visible: action.round && !generator.busy
                                    preferredRendererType: Shape.CurveRenderer
                                    ShapePath {
                                        strokeColor: face.color
                                        strokeWidth: 2.2
                                        fillColor: "transparent"
                                        capStyle: ShapePath.RoundCap
                                        joinStyle: ShapePath.RoundJoin
                                        PathPolyline { path: [Qt.point(8, 15), Qt.point(8, 2)] }
                                    }
                                    ShapePath {
                                        strokeColor: face.color
                                        strokeWidth: 2.2
                                        fillColor: "transparent"
                                        capStyle: ShapePath.RoundCap
                                        joinStyle: ShapePath.RoundJoin
                                        PathPolyline { path: [Qt.point(2.5, 7.5), Qt.point(8, 2), Qt.point(13.5, 7.5)] }
                                    }
                                }
                                // A square to stop.
                                Rectangle {
                                    anchors.centerIn: parent
                                    width: 11
                                    height: 11
                                    radius: Math.min(2, theme.radius)
                                    visible: action.round && generator.busy
                                    color: face.color
                                }
                            }
                            background: Rectangle {
                                radius: height / 2
                                color: theme.accent
                                opacity: action.enabled ? (action.hovered ? 0.88 : 1) : 0.35
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
                    { keys: "Enter", action: qsTr("Make the image") },
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
