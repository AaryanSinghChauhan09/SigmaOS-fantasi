import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import QtQuick.Shapes

// This machine's first image model: what it is and a way to set it up, then
// its download and first start, drawn as a ring filling around its maker's mark.
Item {
    id: root
    required property var models
    required property color muted

    // offer, waiting, downloading, starting or failed. An error comes first:
    // a setup the engine refused before it began leaves the model installable.
    readonly property string phase: models.error !== "" ? "failed"
                                  : models.state === "installable" ? "offer" : models.setupPhase || "waiting"
    readonly property bool working: ["waiting", "downloading", "starting"].indexOf(phase) >= 0
    readonly property var locale: Qt.locale(translator.language)
    readonly property string logo: models.logo(models.vendor, theme.light)

    // The download fills the ring to 85%, and the first start the rest, over
    // the time the catalog measured a start to take.
    readonly property real downloaded: models.totalBytes > 0 ? Math.min(1, models.doneBytes / models.totalBytes) : 0
    property real startShare: 0
    readonly property real progress: phase === "downloading" ? 0.85 * downloaded
                                   : phase === "starting" ? 0.85 + 0.15 * startShare : 0
    onPhaseChanged: if (phase === "starting") startFill.restart()
    NumberAnimation {
        id: startFill
        target: root
        property: "startShare"
        from: 0
        to: 0.95
        duration: Math.max(3, root.models.loadSeconds || 10) * 1000
        easing.type: Easing.OutCubic
    }

    // Something to read while it works, changing every few seconds.
    readonly property var quips: [
        qsTr("Mixing the paints…"),
        qsTr("Stretching the canvas…"),
        qsTr("Sharpening the pencils…"),
        qsTr("Teaching it what a sunset looks like…"),
        qsTr("Counting the colors of the rainbow…"),
        qsTr("Warming up the brushes…")
    ]
    property int quip: 0
    Timer {
        running: root.visible && (root.phase === "downloading" || root.phase === "waiting")
        interval: 3500
        repeat: true
        onTriggered: root.quip = (root.quip + 1) % root.quips.length
    }

    Shortcut {
        sequences: ["Return", "Enter"]
        enabled: (root.phase === "offer" || root.phase === "failed") && !root.models.working
        onActivated: root.models.install()
    }

    function minutesLeft() {
        if (models.rateBytes <= 0 || models.totalBytes <= 0)
            return -1
        return Math.ceil((models.totalBytes - models.doneBytes) / models.rateBytes / 60)
    }

    ColumnLayout {
        anchors.centerIn: parent
        width: Math.min(parent.width - 80, 520)
        spacing: 18

        // ------------------------------------------------- the ring and the mark
        Item {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: 200
            Layout.preferredHeight: 200

            // A glow behind the mark that breathes while it waits to begin.
            Rectangle {
                anchors.centerIn: parent
                width: 150
                height: 150
                radius: width / 2
                color: Qt.rgba(theme.accent.r, theme.accent.g, theme.accent.b, 0.10)
                SequentialAnimation on scale {
                    running: root.visible && root.phase === "offer"
                    loops: Animation.Infinite
                    NumberAnimation { from: 0.92; to: 1.06; duration: 1800; easing.type: Easing.InOutSine }
                    NumberAnimation { from: 1.06; to: 0.92; duration: 1800; easing.type: Easing.InOutSine }
                }
            }

            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                // The track.
                ShapePath {
                    strokeColor: Qt.rgba(theme.foreground.r, theme.foreground.g, theme.foreground.b, 0.12)
                    strokeWidth: 8
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    PathAngleArc { centerX: 100; centerY: 100; radiusX: 92; radiusY: 92; startAngle: -90; sweepAngle: 360 }
                }
                // How far it has come, clockwise from the top.
                ShapePath {
                    strokeColor: root.phase === "failed" ? theme.colors.red : theme.accent
                    strokeWidth: 8
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    PathAngleArc {
                        centerX: 100; centerY: 100; radiusX: 92; radiusY: 92; startAngle: -90
                        sweepAngle: 360 * displayed.value
                    }
                }
            }
            // Eased, so a jump in the download's figures glides.
            QtObject {
                id: displayed
                property real value: root.progress
                Behavior on value { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
            }

            // A spark circling the ring while it works, so it's plainly busy
            // even while the figures hold still.
            Item {
                anchors.fill: parent
                visible: root.working
                RotationAnimation on rotation {
                    running: root.visible && root.working
                    loops: Animation.Infinite
                    from: 0
                    to: 360
                    duration: 2400
                }
                Rectangle {
                    x: 100 - width / 2
                    y: 8 - height / 2
                    width: 12
                    height: 12
                    radius: 6
                    color: theme.accent
                    opacity: 0.9
                }
            }

            Image {
                anchors.centerIn: parent
                width: 72
                height: 72
                sourceSize: Qt.size(144, 144)
                fillMode: Image.PreserveAspectFit
                source: root.logo !== "" ? root.logo : "qrc:/icons/model.svg"
            }
        }

        // ------------------------------------------------------------ the words
        Label {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            font.pixelSize: 26
            font.weight: Font.DemiBold
            color: theme.foreground
            text: root.phase === "offer" ? qsTr("Let's set up your first image model")
                : root.phase === "failed" ? qsTr("The setup didn't finish")
                : qsTr("Setting up %1").arg(root.models.modelName)
        }

        Label {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            font.pixelSize: 15
            color: root.muted
            visible: text !== ""
            text: {
                switch (root.phase) {
                case "offer":
                    return qsTr("%1 is the best fit for this machine. It downloads once, then makes every picture right here on your computer, even offline.").arg(root.models.modelName)
                case "failed":
                    return root.models.error || root.models.reason
                case "starting":
                    return qsTr("Waking it up for its first picture…")
                default:
                    return root.quips[root.quip]
                }
            }
        }

        // The figures: what it has fetched of how much, how fast, and how long it has left.
        Label {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            font.pixelSize: 13
            font.features: { "tnum": 1 }
            color: root.muted
            visible: root.phase === "downloading" && root.models.totalBytes > 0
            text: {
                const parts = [qsTr("%1 of %2").arg(root.locale.formattedDataSize(root.models.doneBytes, 1))
                                               .arg(root.locale.formattedDataSize(root.models.totalBytes, 1))]
                if (root.models.rateBytes > 0)
                    parts.push(qsTr("%1/s").arg(root.locale.formattedDataSize(root.models.rateBytes, 1)))
                const minutes = root.minutesLeft()
                if (minutes > 1)
                    parts.push(qsTr("about %Ln minutes left", "", minutes))
                else if (minutes >= 0)
                    parts.push(qsTr("less than a minute left"))
                return parts.join("  ·  ")
            }
        }

        // Where it is: downloaded, started, ready.
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            visible: root.working
            spacing: 22
            Repeater {
                model: [qsTr("Download"), qsTr("First start"), qsTr("Ready")]
                delegate: RowLayout {
                    id: step
                    required property string modelData
                    required property int index
                    readonly property int reached: root.phase === "starting" ? 1 : 0
                    spacing: 7
                    Rectangle {
                        Layout.preferredWidth: 10
                        Layout.preferredHeight: 10
                        radius: 5
                        color: step.index <= step.reached ? theme.accent : "transparent"
                        border.width: 2
                        border.color: step.index <= step.reached ? theme.accent : Qt.rgba(theme.foreground.r, theme.foreground.g, theme.foreground.b, 0.3)
                        opacity: step.index === step.reached ? pulse.value : 1
                    }
                    Label {
                        text: step.modelData
                        font.pixelSize: 13
                        color: step.index <= step.reached ? theme.foreground : root.muted
                    }
                }
            }
            QtObject {
                id: pulse
                property real value: 1
                SequentialAnimation on value {
                    running: root.visible && root.working
                    loops: Animation.Infinite
                    NumberAnimation { from: 1; to: 0.35; duration: 700; easing.type: Easing.InOutSine }
                    NumberAnimation { from: 0.35; to: 1; duration: 700; easing.type: Easing.InOutSine }
                }
            }
        }

        Button {
            id: begin
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: 6
            visible: root.phase === "offer" || root.phase === "failed"
            enabled: !root.models.working
            highlighted: true
            Material.roundedScale: theme.radius
            focusPolicy: Qt.NoFocus
            text: root.phase === "failed" ? qsTr("Try again") : qsTr("Set up %1").arg(root.models.modelName)
            onClicked: root.models.install()
            // A highlighted button colors its caption by Material's own rule,
            // which doesn't read on every accent.
            contentItem: Label {
                text: begin.text
                font: begin.font
                color: theme.accentForeground
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
        }
    }
}
