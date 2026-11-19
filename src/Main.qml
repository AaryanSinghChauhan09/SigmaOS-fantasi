import QtCore
import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Effects
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

    // 0 Screen, 1 Square, 2 Portrait; a new image starts in the screen's shape.
    property int sizeChoice: 0
    readonly property size outputSize: sizeChoice === 0 ? backend.screenSize
                                     : sizeChoice === 2 ? Qt.size(832, 1216) : Qt.size(1024, 1024)
    // The file in the center, when it is one rather than a preview.
    readonly property string shownFile: generator.image.startsWith("file:") ? generator.image : ""
    readonly property bool canGenerate: models.state === "ready" && !generator.busy && prompt.text.trim() !== ""
    // The image the next one changes, while changing one. Each change that
    // finishes becomes the base for the next, until it's let go.
    // The pictures the next one changes or combines, while changing: one, or
    // with a model that edits, up to four.
    property var baseImages: []
    readonly property bool changing: baseImages.length > 0
    // A clip starts from one picture; a change combines up to four with a model that edits.
    readonly property bool canAddPicture: !musicMode && (!changing || (!videoMode && models.canEdit && baseImages.length < 4))
    // Writing a prompt, or looking at a finished image and choosing what's
    // next: change it, make a new one, or use it.
    property bool composing: true
    // The model in use makes clips: from the prompt alone, or animating the
    // picture being changed.
    readonly property bool videoMode: models.video
    function remainingText(seconds) {
        if (seconds < 0)
            return qsTr("Working out how long this takes…")
        if (seconds < 10)
            return qsTr("Almost done")
        if (seconds < 90)
            return qsTr("About %1 s left").arg(Math.max(10, Math.round(seconds / 10) * 10))
        return qsTr("About %1 min left").arg(Math.round(seconds / 60))
    }
    // How long a clip is, stepped through with the length button.
    // As long as the video model makes here: 2, 5 and 10 seconds on most
    // machines, up to its own longest on one with the memory for it.
    readonly property var clipLengths: models.clipLengths
    property int clipSeconds: 5
    // A length that no longer fits, say once another model starts, drops to
    // the longest that still does.
    onClipLengthsChanged: if (clipLengths.indexOf(clipSeconds) < 0)
        clipSeconds = clipLengths.filter(length => length < clipSeconds).pop() || clipLengths[0]
    // A clip starts from one picture: switching to a video model keeps the first.
    onVideoModeChanged: if (videoMode && baseImages.length > 1) baseImages = [baseImages[0]]
    // The model in use makes songs, from the prompt and the lyrics alone.
    readonly property bool musicMode: models.music
    onMusicModeChanged: if (musicMode) baseImages = []
    // A song's lyrics: 0 written by the model, 1 one's own, 2 none.
    property int lyricsChoice: 0
    // How long a song is, stepped through with the length button.
    readonly property var songLengths: [30, 60, 120, 180]
    property int songSeconds: 60
    // A clip in the frame: its poster stands in for it as an image. A song
    // has the player alone, in the shape of its waveform.
    readonly property bool showingClip: shownFile.endsWith(".webm")
    readonly property bool showingSong: shownFile.endsWith(".mp3")
    readonly property string shownImage: showingClip ? shownFile.slice(0, -5) + ".png" : showingSong ? "" : generator.image
    // The title and shape of the song in the frame, by the file it is,
    // looked up again whenever the history has listed its files anew.
    readonly property var shownSong: { history.count; return history.song(showingSong ? shownFile : "") }
    // What only an image takes: being changed.
    readonly property bool showingImage: shownFile !== "" && !showingClip && !showingSong
    // The player loads with the first clip shown, and stays; a song's too.
    property bool playerWanted: false
    onShowingClipChanged: if (showingClip) playerWanted = true
    property bool songPlayerWanted: false
    onShowingSongChanged: if (showingSong) songPlayerWanted = true
    readonly property bool choosing: !composing && shownFile !== "" && !generator.busy
    // The history image a new one was started from, for Esc to go back to.
    property int returnIndex: -1
    readonly property string problem: models.error || generator.error || backend.error
    // What the model is doing, for its icon's tooltip and the empty stage.
    readonly property string modelStatus: {
        switch (models.state) {
        case "ready": return generator.busy ? (models.music ? qsTr("%1 is making your song") : models.video ? qsTr("%1 is making your clip") : qsTr("%1 is making your image")).arg(models.modelName)
                                            : qsTr("%1 is ready").arg(models.modelName)
        case "starting": return qsTr("Starting %1…").arg(models.modelName)
        case "installing": return qsTr("Setting up %1…").arg(models.modelName)
        case "installed": return qsTr("%1 is set up but not running").arg(models.modelName)
        case "blocked": return qsTr("%1 needs the memory %2 is using").arg(models.modelName).arg(models.blockers.join(", "))
        default: return ""
        }
    }
    // Set up but not running: the stage offers to start it, and the bar waits.
    readonly property bool asleep: ["installed", "blocked"].indexOf(models.state) >= 0 && !models.working
    readonly property string wakeText: models.state === "blocked"
        ? qsTr("Stop %1 and start %2").arg(models.blockers.join(", ")).arg(models.modelName)
        : qsTr("Start %1").arg(models.modelName)
    function wake() {
        if (!asleep)
            return
        if (models.state === "blocked")
            models.switchTo()
        else
            models.start()
    }
    // Nothing in the bar changes while something is made, or with no model running.
    readonly property bool locked: generator.busy || asleep
    // Which screen shows: setting up the first image model, sorry there's
    // none for this machine, or the studio once one is set up.
    readonly property string page: models.settingUp ? "setup"
                                 : models.state === "none" || models.state === "noEngine" ? "sorry" : "studio"
    // What was last sent, to tell it from what is typed while it's made.
    property string sentPrompt
    property var sentPictures: []
    property bool sentVideo: false
    property bool sentMusic: false
    property string sentLyrics
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
        sentPictures = baseImages
        sentVideo = videoMode
        sentMusic = musicMode
        sentLyrics = lyricsChoice === 1 ? lyrics.text : lyricsChoice === 2 ? "[Instrumental]" : ""
        if (musicMode)
            generator.makeSong(prompt.text, sentLyrics, songSeconds, translator.language)
        else if (videoMode)
            generator.makeVideo(prompt.text, outputSize.width, outputSize.height, baseImages.length > 0 ? baseImages[0] : "", clipSeconds)
        else
            generator.generate(prompt.text, outputSize.width, outputSize.height, 0, -1, baseImages, models.edits)
    }
    // Makes another like the last one asked for, though the prompt has cleared.
    function repeat() {
        if (models.state !== "ready" || generator.busy || sentPrompt.trim() === "")
            return
        // A song or a clip again as one, while the model in use still makes them.
        if (sentMusic && musicMode)
            generator.makeSong(sentPrompt, sentLyrics, songSeconds, translator.language)
        else if (sentMusic || musicMode)
            return
        else if (sentVideo && videoMode)
            generator.makeVideo(sentPrompt, outputSize.width, outputSize.height, sentPictures.length > 0 ? sentPictures[0] : "", clipSeconds)
        else if (!sentVideo && !videoMode)
            generator.generate(sentPrompt, outputSize.width, outputSize.height, 0, -1, sentPictures, models.edits)
    }
    // Makes the shown image the one to change, with an empty prompt for
    // what should change.
    function changeImage() {
        if (!showingImage || musicMode || generator.busy)
            return
        composing = true
        baseImages = [shownFile]
        prompt.text = ""
        prompt.forceActiveFocus()
    }
    // A picture of the user's own becomes the one to change, or with a model
    // that edits, one more to combine.
    function startFrom(url) {
        if (generator.busy || musicMode)
            return
        // With four already, another is refused rather than replacing them.
        if (changing && models.canEdit && !videoMode && !canAddPicture)
            return
        composing = true
        if (changing && models.canEdit && !videoMode)
            baseImages = baseImages.indexOf(url) < 0 ? baseImages.concat([url]) : baseImages
        else
            baseImages = [url]
        prompt.forceActiveFocus()
        prompt.cursorPosition = prompt.length
    }
    // Shows a history image in the center.
    function pick(index) {
        if (index < 0 || index >= history.count || generator.busy)
            return
        historyList.currentIndex = index
        generator.show(history.urlAt(index))
        baseImages = []
        composing = false
    }
    // An empty frame and an empty prompt for a new image.
    function newImage() {
        if (generator.busy)
            return
        // A second Ctrl+N keeps the image the first one left.
        if (historyList.currentIndex >= 0)
            returnIndex = historyList.currentIndex
        historyList.currentIndex = -1
        generator.show("")
        baseImages = []
        prompt.text = ""
        composing = true
        prompt.forceActiveFocus()
    }
    // Back from writing to the image that was shown, if there was one.
    function backToImage() {
        if (changing) {
            baseImages = []
                composing = false
        } else if (prompt.text === "" && returnIndex >= 0) {
            pick(returnIndex)
        }
    }

    Shortcut { sequence: "F1"; onActivated: help.opened ? help.close() : help.open() }
    Shortcut { sequence: "Ctrl+?"; onActivated: help.opened ? help.close() : help.open() }
    Shortcut { sequence: "Ctrl+Q"; onActivated: Qt.quit() }
    Shortcut { sequence: "Ctrl+Return"; enabled: win.canGenerate; onActivated: win.generate() }
    Shortcut { sequence: "Ctrl+Enter"; enabled: win.canGenerate; onActivated: win.generate() }
    Shortcut { sequence: "Ctrl+R"; enabled: models.state === "ready" && !generator.busy; onActivated: win.canGenerate ? win.generate() : win.repeat() }
    Shortcut { sequence: "Ctrl+E"; enabled: win.showingImage && !win.musicMode && !generator.busy; onActivated: win.changeImage() }
    Shortcut { sequence: "Ctrl+O"; enabled: win.page === "studio" && !generator.busy && !win.musicMode; onActivated: backend.openPicture() }
    // Esc stops an image being made, or else goes back to the image shown.
    Shortcut { sequence: "Escape"; enabled: generator.busy; onActivated: generator.cancel() }
    Shortcut { sequence: "Escape"; enabled: !generator.busy && win.composing; onActivated: win.backToImage() }
    Shortcut { sequence: "Ctrl+N"; enabled: win.page === "studio" && !generator.busy; onActivated: win.newImage() }
    Shortcut { sequence: "Ctrl+1"; enabled: !generator.busy; onActivated: win.sizeChoice = 0 }
    Shortcut { sequence: "Ctrl+2"; enabled: !generator.busy; onActivated: win.sizeChoice = 1 }
    Shortcut { sequence: "Ctrl+3"; enabled: !generator.busy; onActivated: win.sizeChoice = 2 }
    Shortcut { sequence: "Ctrl+B"; onActivated: layout.historyShown = !layout.historyShown }
    // Whether the history sidebar is shown, kept between runs.
    Settings {
        id: layout
        category: "window"
        property bool historyShown: true
    }
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
            if (prompt.text !== win.sentPrompt) {
                // The next one is already being typed: a change goes on
                // from the image just made.
                if (win.changing)
                    win.baseImages = [generator.image]
            } else {
                win.baseImages = []
                prompt.text = ""
                win.composing = false
            }
        }
    }
    Connections {
        target: backend
        function onPictureChosen(url) { win.startFrom(url) }
        // Another `fantasi open` with a prompt: a new image from it.
        function onPromptRequested(text) {
            win.newImage()
            prompt.text = text
        }
    }

    // A picture dropped anywhere on the window becomes the one to change,
    // but not while an image is being made, so a drop then is refused.
    DropArea {
        anchors.fill: parent
        keys: ["text/uri-list"]
        onEntered: drag => drag.accept(win.page === "studio" && !generator.busy && !win.musicMode && drag.hasUrls && drag.urls.length === 1 && backend.isPicture(drag.urls[0]))
        onDropped: drop => {
            if (win.page === "studio" && !generator.busy && !win.musicMode && drop.hasUrls && backend.isPicture(drop.urls[0])) {
                win.startFrom(drop.urls[0].toString())
                drop.accept()
            }
        }
    }

    Setup {
        anchors.fill: parent
        visible: win.page === "setup"
        models: win.models
        muted: win.muted
        LayoutMirroring.enabled: win.rightToLeft
        LayoutMirroring.childrenInherit: true
    }

    NoModel {
        anchors.fill: parent
        visible: win.page === "sorry"
        models: win.models
        muted: win.muted
        LayoutMirroring.enabled: win.rightToLeft
        LayoutMirroring.childrenInherit: true
    }

    // The studio: the image, its prompt, and the history beside it.
    Item {
        anchors.fill: parent
        visible: win.page === "studio"
        enabled: visible
        LayoutMirroring.enabled: win.rightToLeft
        LayoutMirroring.childrenInherit: true

        // An aurora plays over the whole window, under the image, the prompt
        // bar and the history: at full strength while something is made,
        // softer the rest of the time.
        Aurora {
            id: making
            objectName: "making"
            anchors.fill: parent
            colorA: theme.colors.cyan || theme.accent
            colorB: theme.accent
            colorC: theme.colors.magenta || theme.accent
            intensity: generator.busy ? 1 : 0.5
            Behavior on intensity { NumberAnimation { duration: 600; easing.type: Easing.InOutSine } }
        }

        RowLayout {
            anchors.fill: parent
            spacing: 0

            Item {
                id: work
                Layout.fillWidth: true
                Layout.fillHeight: true

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 20
                spacing: 12

                // ----------------------------------------------------- the image
                Item {
                    id: stage
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    // The shape the image will have: the one shown once it's
                    // there, the size asked for while it isn't.
                    readonly property real aspect: win.showingSong ? 3
                                                   : shown.status === Image.Ready && shown.implicitHeight > 0
                                                   ? shown.implicitWidth / shown.implicitHeight
                                                   : previous.status === Image.Ready && previous.implicitHeight > 0
                                                   ? previous.implicitWidth / previous.implicitHeight
                                                   : win.musicMode ? 3 : win.outputSize.width / win.outputSize.height

                    // A model starting to take over from the one in use: its mark in a
                    // ring with a spark circling it, as on the setup screen. One
                    // set up but not running waits in the same ring, over a glow
                    // that breathes, for a click to start it.
                    Item {
                        id: starting
                        objectName: "starting"
                        readonly property bool active: models.working || models.state === "starting"
                        readonly property bool offer: !active && win.asleep && win.composing
                        readonly property string name: models.switchingTo !== "" ? models.switchingTo : models.modelName
                        readonly property string mark: models.logo(models.switchingTo !== "" ? models.switchingVendor : models.vendor, theme.light)
                        anchors.centerIn: parent
                        width: 220
                        height: 200
                        z: 2
                        visible: (active || offer) && !generator.busy
                        Item {
                            id: ring
                            width: 120
                            height: 120
                            anchors.horizontalCenter: parent.horizontalCenter
                            Rectangle {
                                anchors.centerIn: parent
                                width: 92
                                height: 92
                                radius: width / 2
                                visible: starting.offer
                                color: Qt.rgba(theme.accent.r, theme.accent.g, theme.accent.b, wake.containsMouse ? 0.2 : 0.1)
                                SequentialAnimation on scale {
                                    running: starting.visible && starting.offer
                                    loops: Animation.Infinite
                                    NumberAnimation { from: 0.92; to: 1.06; duration: 1800; easing.type: Easing.InOutSine }
                                    NumberAnimation { from: 1.06; to: 0.92; duration: 1800; easing.type: Easing.InOutSine }
                                }
                            }
                            Shape {
                                anchors.fill: parent
                                preferredRendererType: Shape.CurveRenderer
                                ShapePath {
                                    strokeColor: starting.offer && wake.containsMouse ? theme.accent
                                               : Qt.rgba(theme.foreground.r, theme.foreground.g, theme.foreground.b, 0.12)
                                    strokeWidth: 5
                                    fillColor: "transparent"
                                    PathAngleArc { centerX: 60; centerY: 60; radiusX: 55; radiusY: 55; startAngle: -90; sweepAngle: 360 }
                                }
                            }
                            Item {
                                anchors.fill: parent
                                visible: starting.active
                                RotationAnimation on rotation {
                                    running: starting.visible && starting.active
                                    loops: Animation.Infinite
                                    from: 0
                                    to: 360
                                    duration: 2400
                                }
                                Rectangle {
                                    x: 60 - width / 2
                                    y: 5 - height / 2
                                    width: 9
                                    height: 9
                                    radius: 4.5
                                    color: theme.accent
                                }
                            }
                            Image {
                                anchors.centerIn: parent
                                width: 44
                                height: 44
                                sourceSize: Qt.size(88, 88)
                                fillMode: Image.PreserveAspectFit
                                source: starting.mark !== "" ? starting.mark : "qrc:/icons/model.svg"
                            }
                            MouseArea {
                                id: wake
                                objectName: "wake"
                                anchors.fill: parent
                                enabled: starting.offer
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                Accessible.role: Accessible.Button
                                Accessible.name: win.wakeText
                                Accessible.onPressAction: win.wake()
                                onClicked: win.wake()
                            }
                        }
                        Label {
                            anchors.top: ring.bottom
                            anchors.topMargin: 16
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: Math.min(implicitWidth, stage.width * 0.6)
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.Wrap
                            color: starting.offer && wake.containsMouse ? theme.foreground : win.muted
                            text: starting.offer ? win.wakeText : qsTr("Starting %1…").arg(starting.name)
                        }
                    }

                    Item {
                        id: frame
                        anchors.centerIn: parent
                        width: Math.min(parent.width, parent.height * stage.aspect)
                        height: width / stage.aspect
                        // Empty while a new one is written, shimmering once it's asked for.
                        visible: !starting.visible && (generator.busy || generator.image !== "" || (win.composing && models.state === "ready"))

                        // While a picture is being changed, it stays in the frame,
                        // faded, and the new one grows in over it as it's made.
                        Image {
                            id: previous
                            anchors.fill: parent
                            source: generator.busy && win.changing ? win.baseImages[0] : ""
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
                            source: win.shownImage
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                            smooth: true
                            opacity: (generator.busy && win.changing ? 0.2 + 0.8 * win.progress : 1) * arrival
                            Behavior on opacity { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
                            // A job's first picture fades in rather than popping up.
                            property real arrival: 1
                            property bool awaitingFirst: false
                            property bool wasBusy: false
                            Connections {
                                target: generator
                                function onChanged() {
                                    if (generator.busy !== shown.wasBusy)
                                        shown.awaitingFirst = generator.busy
                                    shown.wasBusy = generator.busy
                                }
                            }
                            function fadeIn() {
                                awaitingFirst = false
                                arrive.restart()
                            }
                            onSourceChanged: if (awaitingFirst && source.toString() !== "") {
                                arrival = 0
                                if (status === Image.Ready)
                                    fadeIn()
                            }
                            onStatusChanged: if (awaitingFirst && arrival === 0 && status !== Image.Loading) fadeIn()
                            NumberAnimation { id: arrive; target: shown; property: "arrival"; from: 0; to: 1; duration: 900; easing.type: Easing.InOutSine }
                        }
                        // A thin edge round the picture, in the inactive window
                        // border's colour, hugging what's drawn.
                        Rectangle {
                            objectName: "imageEdge"
                            visible: shown.status === Image.Ready && shown.opacity > 0
                            opacity: shown.opacity
                            width: shown.paintedWidth + 2
                            height: shown.paintedHeight + 2
                            anchors.centerIn: parent
                            color: "transparent"
                            border.color: theme.inactiveBorder
                            border.width: 1
                            z: 2
                        }
                        Loader {
                            id: player
                            objectName: "player"
                            anchors.fill: parent
                            active: win.playerWanted
                            visible: win.showingClip
                            source: "qrc:/VideoPlayer.qml"
                        }
                        // How long a clip or a song has left, in the middle of the frame. An
                        // image needs none: it comes to life before your eyes.
                        Rectangle {
                            objectName: "remaining"
                            anchors.centerIn: parent
                            visible: generator.busy && (win.videoMode || win.musicMode)
                            width: remainingLabel.implicitWidth + 28
                            height: remainingLabel.implicitHeight + 14
                            radius: Math.min(height / 2, theme.radius + 6)
                            color: Qt.rgba(theme.background.r, theme.background.g, theme.background.b, 0.78)
                            Label {
                                id: remainingLabel
                                anchors.centerIn: parent
                                color: theme.foreground
                                font.pixelSize: 14
                                text: win.remainingText(generator.remainingSeconds)
                            }
                        }
                        Binding {
                            target: player.item
                            property: "source"
                            value: win.showingClip ? win.shownFile : ""
                            when: player.status === Loader.Ready
                        }
                        Loader {
                            id: songPlayer
                            objectName: "songPlayer"
                            anchors.fill: parent
                            active: win.songPlayerWanted
                            visible: win.showingSong
                            source: "qrc:/SongPlayer.qml"
                            onLoaded: {
                                item.source = Qt.binding(() => win.showingSong ? win.shownFile : "")
                                item.wave = Qt.binding(() => win.shownSong.wave)
                                item.title = Qt.binding(() => win.shownSong.title)
                                item.played = Qt.binding(() => theme.accent)
                                item.unplayed = Qt.binding(() => win.muted)
                            }
                        }

                    }
                    Label {
                        anchors.centerIn: parent
                        width: parent.width * 0.6
                        visible: !frame.visible && !starting.visible
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
                }

                // -------------------------------------------------- the lyrics
                // One's own lyrics for a song, in a pill of their own above
                // the prompt's.
                Rectangle {
                    objectName: "lyricsBar"
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(Math.max(lyrics.implicitHeight, 34), 160) + 10
                    visible: win.musicMode && win.lyricsChoice === 1 && !win.choosing
                    color: win.panel
                    radius: Math.min(height / 2, theme.radius)
                    border.color: lyrics.activeFocus ? theme.accent : win.line
                    ScrollView {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        anchors.topMargin: 5
                        anchors.bottomMargin: 5
                        TextArea {
                            id: lyrics
                            objectName: "lyrics"
                            wrapMode: TextEdit.Wrap
                            background: null
                            topPadding: 7
                            bottomPadding: 7
                            leftPadding: 6
                            rightPadding: 6
                            Label {
                                x: lyrics.leftPadding
                                y: lyrics.topPadding
                                visible: lyrics.length === 0 && lyrics.preeditText === ""
                                color: win.muted
                                font: lyrics.font
                                text: qsTr("Write the lyrics, with [verse] and [chorus] over their parts")
                            }
                        }
                    }
                }

                // ------------------------------------------------ the prompt bar
                // One pill: the picture to start from, the prompt, the shape,
                // the model, and the round button that sends it.
                Rectangle {
                    id: promptBar
                    Layout.fillWidth: true
                    Layout.preferredHeight: (win.choosing ? nextBar.implicitHeight : bar.implicitHeight) + 10
                    // What's next has no box: just its icons, centred.
                    color: win.choosing ? "transparent" : win.panel
                    // Rounded as the theme rounds windows, sharp where it doesn't.
                    radius: Math.min(height / 2, theme.radius)
                    // While something is made, the edge below takes the border's place.
                    border.color: win.choosing || generator.busy ? "transparent" : prompt.activeFocus && !win.asleep ? theme.accent : win.line

                    // While it's being made, the bar's edge says how far along it
                    // is: a faint track, an accent line growing clockwise with each
                    // step, and a bright spark circling all the while.
                    Shape {
                        id: edge
                        objectName: "working"
                        anchors.fill: parent
                        z: 1
                        visible: generator.busy
                        preferredRendererType: Shape.CurveRenderer
                        readonly property real line: 2
                        readonly property real spark: 3
                        readonly property real corner: Math.max(0, promptBar.radius - line / 2)
                        readonly property real perimeter: 2 * (width + height - 2 * line) - (8 - 2 * Math.PI) * corner
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
                            PathRectangle { x: edge.line / 2; y: edge.line / 2; width: edge.width - edge.line; height: edge.height - edge.line; radius: edge.corner }
                        }
                        ShapePath {
                            strokeColor: theme.accent
                            strokeWidth: edge.line
                            fillColor: "transparent"
                            capStyle: ShapePath.FlatCap
                            strokeStyle: ShapePath.DashLine
                            // A dash as long as the share done, then a gap as long
                            // as the whole: in units of the line's width.
                            dashPattern: [Math.max(0.01, edge.perimeter * edge.shown / edge.line), edge.perimeter / edge.line]
                            PathRectangle { x: edge.line / 2; y: edge.line / 2; width: edge.width - edge.line; height: edge.height - edge.line; radius: edge.corner }
                        }
                        ShapePath {
                            strokeColor: Qt.lighter(theme.accent, 1.35)
                            strokeWidth: edge.spark
                            fillColor: "transparent"
                            capStyle: ShapePath.RoundCap
                            strokeStyle: ShapePath.DashLine
                            dashPattern: [edge.perimeter * 0.06 / edge.spark, edge.perimeter * 0.94 / edge.spark]
                            dashOffset: edge.perimeter * (1 - edge.travel) / edge.spark
                            PathRectangle { x: edge.line / 2; y: edge.line / 2; width: edge.width - edge.line; height: edge.height - edge.line; radius: edge.corner }
                        }
                    }

                    // What's next, once an image is done: change it, start a new
                    // one, or use it.
                    RowLayout {
                        id: nextBar
                        objectName: "next"
                        visible: win.choosing
                        anchors.fill: parent
                        anchors.topMargin: 5
                        anchors.bottomMargin: 5
                        spacing: 4
                        Item { Layout.fillWidth: true }
                        Repeater {
                            model: [
                                { name: "changeIt", icon: "change", label: win.videoMode ? qsTr("Animate it") : qsTr("Change it"), key: "Ctrl+E", run: () => win.changeImage(), shown: win.showingImage && !win.musicMode },
                                { name: "newImage", icon: "new", label: qsTr("New generation"), key: "Ctrl+N", run: () => win.newImage() },
                                { name: "copy", icon: "copy", label: qsTr("Copy"), key: "Ctrl+Shift+C", run: () => backend.copy(win.shownFile) },
                                { name: "save", icon: "save", label: qsTr("Save as…"), key: "Ctrl+S", run: () => backend.saveAs(win.shownFile) }
                            ]
                            delegate: ToolButton {
                                required property var modelData
                                objectName: modelData.name
                                visible: modelData.shown !== false
                                Layout.preferredWidth: 32
                                Layout.preferredHeight: 32
                                padding: 0
                                focusPolicy: Qt.NoFocus
                                background: Item {}
                                display: AbstractButton.IconOnly
                                icon.source: "qrc:/icons/" + modelData.icon + ".svg"
                                icon.width: 18
                                icon.height: 18
                                icon.color: hovered ? theme.accent : win.muted
                                Accessible.name: modelData.label
                                ToolTip.visible: hovered
                                ToolTip.text: modelData.label + "  " + modelData.key
                                ToolTip.delay: 300
                                onClicked: modelData.run()
                            }
                        }
                        Item { Layout.fillWidth: true }
                    }

                    RowLayout {
                        id: bar
                        // While a model starts, the bar keeps its controls as they
                        // are and greys out as a whole.
                        enabled: !starting.active
                        opacity: starting.active ? 0.4 : 1
                        visible: !win.choosing
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 5
                        anchors.topMargin: 5
                        anchors.bottomMargin: 5
                        spacing: 4

                        // The pictures being changed, like attachments: a thumbnail
                        // each, with a × to let it go.
                        Repeater {
                            model: win.baseImages
                            delegate: Item {
                                id: attachment
                                required property string modelData
                                required property int index
                                objectName: "base" + index
                                // The row's own height, so changing doesn't make the bar taller.
                                Layout.preferredWidth: 34
                                Layout.preferredHeight: 34
                                Layout.alignment: Qt.AlignVCenter
                                Image {
                                    anchors.fill: parent
                                    source: attachment.modelData
                                    sourceSize: Qt.size(68, 68)
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                }
                                ToolTip.visible: baseHover.hovered
                                ToolTip.text: win.baseImages.length > 1 ? qsTr("Combining this picture") : qsTr("Changing this image")
                                HoverHandler { id: baseHover }
                                // The × sits on the thumbnail's corner, as on an attachment.
                                ToolButton {
                                    id: letGo
                                    visible: !generator.busy
                                    width: 16
                                    height: 16
                                    padding: 0
                                    anchors.top: parent.top
                                    anchors.right: parent.right
                                    anchors.topMargin: -5
                                    anchors.rightMargin: -5
                                    focusPolicy: Qt.NoFocus
                                    Accessible.name: qsTr("Let this picture go")
                                    ToolTip.visible: hovered
                                    ToolTip.text: qsTr("Let this picture go")
                                    ToolTip.delay: 300
                                    onClicked: win.baseImages = win.baseImages.filter((_, i) => i !== attachment.index)
                                    background: Rectangle {
                                        radius: width / 2
                                        color: letGo.hovered ? theme.colors.selection : theme.background
                                        border.color: win.line
                                    }
                                    contentItem: Label {
                                        text: "×"
                                        color: theme.foreground
                                        font.pixelSize: 12
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                    }
                                }
                            }
                        }

                        // Or start from a picture of one's own, which a drop
                        // onto the window does too.
                        ToolButton {
                            objectName: "startFrom"
                            // Nothing changes while something is made: only stop works.
                            enabled: !win.locked
                            opacity: win.locked ? 0.4 : 1
                            Layout.alignment: Qt.AlignVCenter
                            visible: win.canAddPicture
                            Layout.preferredWidth: 32
                            Layout.preferredHeight: 32
                            padding: 0
                            topInset: 0
                            bottomInset: 0
                            leftInset: 0
                            rightInset: 0
                            // No hover blot behind it: the icon itself answers the pointer.
                            background: Item {}
                            focusPolicy: Qt.NoFocus
                            readonly property string label: win.changing ? qsTr("Add a picture to combine…") : qsTr("Start from a picture…")
                            Accessible.name: label
                            ToolTip.visible: hovered
                            ToolTip.text: label + "  Ctrl+O"
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
                            Layout.preferredHeight: Math.min(Math.max(prompt.implicitHeight, 34), 96)
                            Layout.alignment: Qt.AlignVCenter
                            TextArea {
                                id: prompt
                                objectName: "prompt"
                                readOnly: win.locked
                                opacity: win.locked ? 0.5 : 1
                                focus: true
                                wrapMode: TextEdit.Wrap
                                background: null
                                topPadding: 7
                                bottomPadding: 7
                                leftPadding: 6
                                rightPadding: 6
                                // Drawn here: Material floats its own placeholder up
                                // as a label, out of this borderless bar.
                                Label {
                                    x: prompt.leftPadding
                                    y: prompt.topPadding
                                    visible: prompt.length === 0 && prompt.preeditText === ""
                                    color: win.muted
                                    font: prompt.font
                                    text: win.musicMode ? qsTr("Describe a song")
                                          : win.videoMode ? (win.changing ? qsTr("How should it move?") : qsTr("Describe a clip"))
                                          : win.baseImages.length > 1 ? qsTr("How should they come together?")
                                          : win.changing ? qsTr("What should change?") : qsTr("Describe an image")
                                }
                                // Enter sends the prompt, or starts a model that waits
                                // to be; Shift+Enter is a new line.
                                Keys.onReturnPressed: event => {
                                    if (event.modifiers & Qt.ShiftModifier)
                                        event.accepted = false
                                    else if (win.asleep)
                                        win.wake()
                                    else
                                        win.generate()
                                }
                                Keys.onEnterPressed: event => {
                                    if (event.modifiers & Qt.ShiftModifier)
                                        event.accepted = false
                                    else if (win.asleep)
                                        win.wake()
                                    else
                                        win.generate()
                                }
                            }
                        }

                        // A song's lyrics, one button that steps through written
                        // for you, your own and none.
                        ToolButton {
                            id: lyricsButton
                            objectName: "lyricsChoice"
                            // Nothing changes while something is made: only stop works.
                            enabled: !win.locked
                            opacity: win.locked ? 0.4 : 1
                            Layout.alignment: Qt.AlignVCenter
                            visible: win.musicMode
                            Layout.preferredWidth: 32
                            Layout.preferredHeight: 32
                            padding: 0
                            topInset: 0
                            bottomInset: 0
                            leftInset: 0
                            rightInset: 0
                            background: Item {}
                            focusPolicy: Qt.NoFocus
                            readonly property string label: [qsTr("Lyrics written for you"), qsTr("Your own lyrics"), qsTr("No lyrics, only music")][win.lyricsChoice]
                            readonly property color ink: hovered || win.lyricsChoice === 1 ? theme.accent : win.muted
                            Accessible.name: label
                            ToolTip.visible: hovered
                            ToolTip.text: label
                            ToolTip.delay: 300
                            onClicked: {
                                win.lyricsChoice = (win.lyricsChoice + 1) % 3
                                if (win.lyricsChoice === 1)
                                    lyrics.forceActiveFocus()
                                else
                                    prompt.forceActiveFocus()
                            }
                            // Lines of a verse; struck through when there are none.
                            contentItem: Item {
                                implicitWidth: 24
                                implicitHeight: 24
                                Column {
                                    anchors.centerIn: parent
                                    spacing: 3
                                    Repeater {
                                        model: [16, 12, 16, 9]
                                        Rectangle {
                                            required property int modelData
                                            width: modelData
                                            height: 1.5
                                            color: lyricsButton.ink
                                        }
                                    }
                                }
                                Rectangle {
                                    anchors.centerIn: parent
                                    visible: win.lyricsChoice === 2
                                    width: 24
                                    height: 1.5
                                    rotation: -45
                                    color: lyricsButton.ink
                                }
                            }
                        }

                        // A song's length, while a music model is in use.
                        ToolButton {
                            objectName: "songLength"
                            // Nothing changes while something is made: only stop works.
                            enabled: !win.locked
                            opacity: win.locked ? 0.4 : 1
                            Layout.alignment: Qt.AlignVCenter
                            Layout.preferredWidth: 32
                            Layout.preferredHeight: 32
                            padding: 0
                            topInset: 0
                            bottomInset: 0
                            leftInset: 0
                            rightInset: 0
                            background: Item {}
                            focusPolicy: Qt.NoFocus
                            visible: win.musicMode
                            text: Math.floor(win.songSeconds / 60) + ":" + String(win.songSeconds % 60).padStart(2, "0")
                            font.pixelSize: 12
                            Material.foreground: hovered ? theme.accent : win.muted
                            readonly property string label: qsTr("Song length: %1").arg(text)
                            Accessible.name: label
                            ToolTip.visible: hovered
                            ToolTip.text: label
                            ToolTip.delay: 300
                            onClicked: win.songSeconds = win.songLengths[(win.songLengths.indexOf(win.songSeconds) + 1) % win.songLengths.length]
                        }

                        // A clip's length, as long as the video model makes here, while one is in use.
                        ToolButton {
                            objectName: "clipLength"
                            // Nothing changes while something is made: only stop works.
                            enabled: !win.locked
                            opacity: win.locked ? 0.4 : 1
                            Layout.alignment: Qt.AlignVCenter
                            Layout.preferredWidth: 32
                            Layout.preferredHeight: 32
                            padding: 0
                            topInset: 0
                            bottomInset: 0
                            leftInset: 0
                            rightInset: 0
                            background: Item {}
                            focusPolicy: Qt.NoFocus
                            visible: win.videoMode
                            text: win.clipSeconds + "s"
                            font.pixelSize: 12
                            Material.foreground: hovered ? theme.accent : win.muted
                            readonly property string label: qsTr("Clip length: %1 s").arg(win.clipSeconds)
                            Accessible.name: label
                            ToolTip.visible: hovered
                            ToolTip.text: label
                            ToolTip.delay: 300
                            onClicked: win.clipSeconds = win.clipLengths[(win.clipLengths.indexOf(win.clipSeconds) + 1) % win.clipLengths.length]
                        }

                        // The shape of a new image, one button that steps through
                        // square, screen and portrait; a change keeps its own.
                        ToolButton {
                            id: shape
                            objectName: "size"
                            // Nothing changes while something is made: only stop works.
                            enabled: !win.locked
                            opacity: win.locked ? 0.4 : 1
                            Layout.alignment: Qt.AlignVCenter
                            visible: !win.changing && !win.musicMode
                            Layout.preferredWidth: 32
                            Layout.preferredHeight: 32
                            padding: 0
                            topInset: 0
                            bottomInset: 0
                            leftInset: 0
                            rightInset: 0
                            // No hover blot behind it: the icon itself answers the pointer.
                            background: Item {}
                            focusPolicy: Qt.NoFocus
                            readonly property var shapes: [
                                { name: qsTr("Screen"), w: 20, h: 12 },
                                { name: qsTr("Square"), w: 15, h: 15 },
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

                        // The model in use, as its maker's mark. With more than one
                        // set up, the others fan out beside it while the pointer is on
                        // it or it has the keyboard, to pick from; with one, its
                        // tooltip says what it's doing.
                        FocusScope {
                            id: picker
                            // The others, the next one nearest the mark in use.
                            readonly property var others: {
                                const all = models.choices
                                const at = all.findIndex(c => c.id === models.modelId)
                                const rest = []
                                for (let i = 1; i < all.length; i++)
                                    rest.push(all[(at + i) % all.length])
                                return rest.reverse()
                            }
                            readonly property bool open: others.length > 0 && enabled && (pickerHover.hovered || picker.activeFocus)
                            // Nothing changes while something is made: only stop works.
                            enabled: !generator.busy && !models.working
                            opacity: generator.busy ? 0.4 : 1
                            Layout.alignment: Qt.AlignVCenter
                            Layout.preferredWidth: pickerRow.width
                            Layout.preferredHeight: 32
                            HoverHandler { id: pickerHover }

                            Row {
                                id: pickerRow
                                height: 32
                                Item {
                                    id: fan
                                    width: picker.open ? picker.others.length * 32 : 0
                                    height: 32
                                    clip: true
                                    Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                    Row {
                                        anchors.right: parent.right
                                        Repeater {
                                            model: picker.others
                                            delegate: ToolButton {
                                                id: choice
                                                required property var modelData
                                                readonly property string logo: models.logo(modelData.vendor || "", theme.light)
                                                objectName: "choice-" + modelData.id
                                                width: 32
                                                height: 32
                                                padding: 0
                                                topInset: 0
                                                bottomInset: 0
                                                leftInset: 0
                                                rightInset: 0
                                                background: Item {}
                                                focusPolicy: Qt.TabFocus
                                                display: AbstractButton.IconOnly
                                                icon.source: logo !== "" ? logo : "qrc:/icons/model.svg"
                                                icon.color: logo !== "" ? "transparent" : (hovered || activeFocus ? theme.accent : win.muted)
                                                icon.width: 18
                                                icon.height: 18
                                                opacity: hovered || activeFocus ? 1 : 0.6
                                                scale: hovered || activeFocus ? 1.15 : 1
                                                Behavior on scale { NumberAnimation { duration: 120 } }
                                                Accessible.name: ToolTip.text
                                                ToolTip.visible: hovered || visualFocus
                                                ToolTip.text: (modelData.music ? qsTr("Music with %1") : modelData.video ? qsTr("Video with %1") : qsTr("Images with %1")).arg(modelData.name)
                                                ToolTip.delay: 150
                                                onClicked: models.choose(modelData.id)
                                            }
                                        }
                                    }
                                }

                                ToolButton {
                                    id: modelButton
                                    objectName: "model"
                                    width: 32
                                    height: 32
                                    padding: 0
                                    topInset: 0
                                    bottomInset: 0
                                    leftInset: 0
                                    rightInset: 0
                                    // No hover blot behind it: the icon itself answers the pointer.
                                    background: Item {}
                                    focusPolicy: Qt.TabFocus
                                    readonly property string logo: models.logo(models.vendor, theme.light)
                                    // A short pulse when it switches to another running model;
                                    // one that must start shows in the stage instead.
                                    property string shownModel: models.modelId
                                    Connections {
                                        target: models
                                        function onChanged() {
                                            if (models.modelId !== modelButton.shownModel && models.state === "ready" && !models.working && modelButton.shownModel !== "")
                                                switched.restart()
                                            modelButton.shownModel = models.modelId
                                        }
                                    }
                                    SequentialAnimation {
                                        id: switched
                                        loops: 2
                                        NumberAnimation { target: modelButton; property: "scale"; from: 1; to: 1.25; duration: 160; easing.type: Easing.OutCubic }
                                        NumberAnimation { target: modelButton; property: "scale"; from: 1.25; to: 1; duration: 220; easing.type: Easing.InOutSine }
                                    }
                                    // A mark in its own colours; without one, a chip in the quiet colour.
                                    display: AbstractButton.IconOnly
                                    icon.source: logo !== "" ? logo : "qrc:/icons/model.svg"
                                    icon.color: logo !== "" ? "transparent" : win.muted
                                    icon.width: 18
                                    icon.height: 18
                                    Accessible.name: win.modelStatus
                                    // With others fanned out, their names say the rest.
                                    ToolTip.visible: (hovered || visualFocus) && picker.others.length === 0
                                    // What it makes once it's ready; until then, what it's doing.
                                    ToolTip.text: models.state !== "ready" ? win.modelStatus
                                        : (models.music ? qsTr("Music with %1") : models.video ? qsTr("Video with %1") : qsTr("Images with %1")).arg(models.modelName)
                                    ToolTip.delay: 300
                                }
                            }
                        }

                        // A round arrow to send, or a square to stop while it's
                        // making one. Starting a model is the stage's to offer.
                        Button {
                            id: action
                            objectName: "action"
                            // The round arrow stays while a model starts or waits to: the
                            // bar keeps its shape and greys out; words only for a setup.
                            readonly property bool round: models.state === "ready" || starting.active || win.asleep
                            // The same gap from the model's mark as between the icons.
                            Layout.leftMargin: 9
                            Layout.alignment: Qt.AlignVCenter
                            Layout.preferredWidth: round ? 34 : implicitWidth
                            Layout.preferredHeight: 34
                            visible: ["ready", "installed", "blocked", "starting", "installing"].indexOf(models.state) >= 0
                            focusPolicy: Qt.NoFocus
                            topInset: 0
                            bottomInset: 0
                            leftInset: 0
                            rightInset: 0
                            padding: round ? 0 : 14
                            // Material sets these itself, over padding.
                            leftPadding: round ? 0 : 14
                            rightPadding: round ? 0 : 14
                            Accessible.name: text
                            ToolTip.visible: round && hovered
                            ToolTip.text: text + (generator.busy ? "  Esc" : "  Enter")
                            ToolTip.delay: 400
                            enabled: models.state === "ready" && (generator.busy || prompt.text.trim() !== "")
                            text: {
                                switch (models.state) {
                                case "ready": return generator.busy ? qsTr("Cancel") : win.changing ? qsTr("Change") : qsTr("Generate")
                                case "installed":
                                case "blocked": return win.wakeText
                                case "starting": return qsTr("Starting…")
                                default: return qsTr("Setting up…")
                                }
                            }
                            onClicked: generator.busy ? generator.cancel() : win.generate()
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
                                radius: Math.min(height / 2, theme.radius)
                                color: theme.accent
                                opacity: action.enabled ? (action.hovered ? 0.88 : 1) : 0.35
                            }
                        }
                    }
                }
            }
            }


            // ----------------------------------------------------------- history
            // A rail of its own width, with no background: its list fills
            // the column, which would otherwise take the image's space. Only
            // once there's an image to list, and Ctrl+B hides it.
            Rectangle {
                objectName: "rail"
                visible: history.count > 0 && layout.historyShown
                Layout.preferredWidth: 152
                Layout.maximumWidth: 152
                Layout.fillWidth: false
                Layout.fillHeight: true
                // No background of its own: the aurora runs under it too.
                color: "transparent"
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 10

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
                        required property string video
                            required property string audio
                            required property string title
                            required property var wave
                            width: ListView.view.width
                            height: width
                            // A song: its own shape in the accent, over what it goes by.
                            Rectangle {
                                anchors.fill: parent
                                visible: entry.audio !== ""
                                radius: theme.radius
                                color: win.panel
                                Row {
                                    id: tileWave
                                    anchors.top: parent.top
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.bottom: tileTitle.top
                                    anchors.margins: 8
                                    LayoutMirroring.enabled: false
                                    // Every third bar: the tile is a third as wide as there are bars.
                                    Repeater {
                                        model: entry.wave.filter((_, i) => i % 3 === 1)
                                        Item {
                                            required property real modelData
                                            width: tileWave.width / 32
                                            height: tileWave.height
                                            Rectangle {
                                                anchors.centerIn: parent
                                                width: Math.max(1, parent.width * 0.6)
                                                height: Math.max(2, parent.modelData * parent.height)
                                                color: theme.accent
                                            }
                                        }
                                    }
                                }
                                Label {
                                    id: tileTitle
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    anchors.margins: 8
                                    text: entry.title
                                    font.pixelSize: 12
                                    wrapMode: Text.Wrap
                                    maximumLineCount: 2
                                    elide: Text.ElideRight
                                }
                            }
                            // Its corners rounded as the theme rounds windows.
                            Image {
                                anchors.fill: parent
                                visible: entry.audio === ""
                                source: entry.url
                                sourceSize: Qt.size(192, 192)
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                layer.enabled: theme.radius > 0
                                layer.effect: MultiEffect {
                                    maskEnabled: true
                                    maskSource: thumbMask
                                    maskThresholdMin: 0.5
                                    maskSpreadAtMin: 1.0
                                }
                            }
                            Item {
                                id: thumbMask
                                anchors.fill: parent
                                visible: false
                                layer.enabled: true
                                Rectangle { anchors.fill: parent; radius: theme.radius; color: "black" }
                            }
                            // A thin edge in the inactive window border's colour, or
                            // the accent for the one shown.
                            Rectangle {
                                anchors.fill: parent
                                color: "transparent"
                                radius: theme.radius
                                border.color: entry.ListView.isCurrentItem ? theme.accent : theme.inactiveBorder
                                border.width: entry.ListView.isCurrentItem ? 2 : 1
                            }
                            // A clip: a play mark on its poster.
                        Rectangle {
                            visible: entry.video !== ""
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.margins: 6
                            width: 22
                            height: 22
                            radius: 11
                            color: Qt.rgba(0, 0, 0, 0.6)
                            Label {
                                anchors.centerIn: parent
                                anchors.horizontalCenterOffset: 1
                                text: "▶"
                                color: "white"
                                font.pixelSize: 10
                            }
                        }
                        MouseArea {
                                anchors.fill: parent
                                onClicked: win.pick(entry.index)
                                // Takes the image's prompt back into the bar.
                                onDoubleClicked: {
                                    win.pick(entry.index)
                                    win.composing = true
                                    prompt.text = entry.prompt
                                    prompt.forceActiveFocus()
                                }
                            }
                        }
                    }
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
                    { keys: "Ctrl+N", action: qsTr("Start a new generation") },
                    { keys: "Ctrl+O", action: qsTr("Start from a picture of your own") },
                    { keys: "Ctrl+1 2 3", action: qsTr("Screen, square or portrait") },
                    { keys: "Ctrl+B", action: qsTr("Show or hide the history") },
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
