#include "backend.h"

#include <QClipboard>
#include <QFile>
#include <QGuiApplication>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QFileInfo>
#include <QImageReader>
#include <QMimeData>
#include <QSaveFile>
#include <QStandardPaths>
#include <QUrl>
#include <cmath>
#include <utility>

#include "portalfilepicker.h"

Backend::Backend(const Places &places, FilePicker *picker, QObject *parent)
    : QObject(parent), m_models(places.engineState, places.engineKey, places.engineCommand),
      m_generator(&m_models, places.folder), m_history(m_generator.folder()),
      m_picker(picker ? picker : new PortalFilePicker(this)) {
    connect(m_picker, &FilePicker::failed, this, [this](const QString &message) {
        m_saving.clear();
        m_error = message;
        emit errorChanged();
    });
    connect(m_picker, &FilePicker::openSelected, this, [this](const QUrl &url) { emit pictureChosen(url.toString()); });
    connect(m_picker, &FilePicker::saveSelected, this, [this](const QUrl &target) {
        const QString source = std::exchange(m_saving, {});
        QFile in(source);
        QSaveFile out(target.toLocalFile());
        // Never truncate the file in place when its folder takes no
        // temporary file: the save fails instead.
        out.setDirectWriteFallback(false);
        const bool written = in.open(QIODevice::ReadOnly) && out.open(QIODevice::WriteOnly)
                          && out.write(in.readAll()) == in.size() && out.commit();
        m_error = written ? QString() : tr("Couldn't save the image as %1").arg(target.toLocalFile());
        emit errorChanged();
    });

    const QString hyprctl = !places.hyprctl.isEmpty() ? places.hyprctl
                          : !qEnvironmentVariableIsEmpty("HYPRLAND_INSTANCE_SIGNATURE")
                              ? QStandardPaths::findExecutable("hyprctl")
                              : QString();
    if (hyprctl.isEmpty())
        return;
    connect(&m_monitors, &QProcess::finished, this, [this] {
        for (const QJsonValue &value : QJsonDocument::fromJson(m_monitors.readAllStandardOutput()).array()) {
            const QJsonObject monitor = value.toObject();
            if (!monitor.value("focused").toBool())
                continue;
            // A monitor on its side is taller than it is wide.
            const bool turned = monitor.value("transform").toInt() % 2 == 1;
            const int width = monitor.value("width").toInt(), height = monitor.value("height").toInt();
            if (width > 0 && height > 0) {
                m_screenSize = turned ? Generator::fitMegapixel(height, width) : Generator::fitMegapixel(width, height);
                emit screenSizeChanged();
            }
        }
    });
    m_monitors.start(hyprctl, {"-j", "monitors"});
}

void Backend::open(const QString &model, const QString &prompt) {
    if (!model.isEmpty())
        m_models.choose(model);
    if (!prompt.isEmpty())
        emit promptRequested(prompt);
}

void Backend::copy(const QString &url) {
    QFile file(QUrl(url).toLocalFile());
    if (!file.open(QIODevice::ReadOnly))
        return;
    auto *data = new QMimeData;
    data->setData("image/png", file.readAll());
    QGuiApplication::clipboard()->setMimeData(data);
}

void Backend::saveAs(const QString &url) {
    const QString path = QUrl(url).toLocalFile();
    if (path.isEmpty())
        return;
    m_saving = path;
    m_error.clear();
    emit errorChanged();
    // The picker starts in Pictures, with the image's own name.
    const QString pictures = QStandardPaths::writableLocation(QStandardPaths::PicturesLocation);
    m_picker->saveImage(QUrl::fromLocalFile(pictures + "/" + QFileInfo(path).fileName()));
}

void Backend::openPicture() {
    m_error.clear();
    emit errorChanged();
    m_picker->openImage();
}

bool Backend::isPicture(const QString &url) const {
    const QUrl parsed(url);
    return parsed.isLocalFile() && QImageReader(parsed.toLocalFile()).canRead();
}
