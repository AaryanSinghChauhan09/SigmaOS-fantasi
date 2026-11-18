import QtQuick
import QtQuick.Controls
import QtMultimedia

// A song playing in the frame: its title over its own shape, which fills
// with the accent as it plays. A click on the shape plays from there; a click
// on the round button pauses and plays. Loaded only once a song is shown,
// since Qt Multimedia takes a moment to start.
Item {
    id: root
    property url source
    // The song's shape, how loud it is from start to end, and what it goes by.
    property var wave: []
    property string title
    property color played
    property color unplayed

    readonly property real progress: player.duration > 0 ? player.position / player.duration : 0
    function clock(ms) {
        const seconds = Math.floor(ms / 1000)
        return Math.floor(seconds / 60) + ":" + String(seconds % 60).padStart(2, "0")
    }

    MediaPlayer {
        id: player
        source: root.source
        audioOutput: AudioOutput {}
        onSourceChanged: if (source.toString() !== "") play()
    }
    Component.onCompleted: if (source.toString() !== "") player.play()

    Label {
        id: heading
        objectName: "songTitle"
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        text: root.title
        font.pixelSize: 20
        font.bold: true
    }

    Item {
        id: shape
        anchors.top: heading.bottom
        anchors.bottom: controls.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: 8
        anchors.bottomMargin: 8

        // A bar for each stretch of the song, as tall as it's loud, in the
        // accent once played. Never mirrored: a song runs left to right in
        // every language.
        Row {
            anchors.fill: parent
            LayoutMirroring.enabled: false
            Repeater {
                model: root.wave
                Item {
                    required property real modelData
                    required property int index
                    width: shape.width / root.wave.length
                    height: shape.height
                    Rectangle {
                        anchors.centerIn: parent
                        width: Math.max(1, parent.width * 0.6)
                        height: Math.max(2, parent.modelData * parent.height)
                        radius: Math.min(width / 2, theme.radius)
                        color: (parent.index + 0.5) / root.wave.length <= root.progress ? root.played : root.unplayed
                    }
                }
            }
        }
        TapHandler {
            onTapped: point => {
                if (player.seekable)
                    player.position = player.duration * point.position.x / shape.width
                player.play()
            }
        }
    }

    Row {
        id: controls
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 12
        LayoutMirroring.enabled: false
        ToolButton {
            id: toggle
            objectName: "playPause"
            readonly property bool playing: player.playbackState === MediaPlayer.PlayingState
            width: 32
            height: 32
            padding: 0
            focusPolicy: Qt.NoFocus
            Accessible.name: playing ? qsTr("Pause") : qsTr("Play")
            onClicked: playing ? player.pause() : player.play()
            background: Rectangle {
                radius: width / 2
                color: root.played
                opacity: toggle.hovered ? 0.88 : 1
            }
            contentItem: Label {
                text: toggle.playing ? "❚❚" : "▶"
                color: theme.accentForeground
                font.pixelSize: toggle.playing ? 9 : 12
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
        }
        Label {
            anchors.verticalCenter: parent.verticalCenter
            color: root.unplayed
            font.pixelSize: 13
            text: root.clock(player.position) + " / " + root.clock(player.duration)
        }
    }
}
