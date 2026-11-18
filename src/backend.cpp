#include "backend.h"

#include <QClipboard>
#include <QFile>
#include <QGuiApplication>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QMimeData>
#include <QStandardPaths>
#include <QUrl>
#include <cmath>

Backend::Backend(const Places &places, QObject *parent)
    : QObject(parent), m_models(places.engineState, places.engineKey, places.engineCommand),
      m_generator(&m_models, places.folder), m_history(m_generator.folder()) {
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
                m_screenSize = turned ? fitMegapixel(height, width) : fitMegapixel(width, height);
                emit screenSizeChanged();
            }
        }
    });
    m_monitors.start(hyprctl, {"-j", "monitors"});
}

QSize Backend::fitMegapixel(int width, int height) {
    const double area = 1024.0 * 1024.0, aspect = double(width) / height;
    const int w = std::max(1, int(std::lround(std::sqrt(area * aspect) / 64))) * 64;
    const int h = std::max(1, int(std::lround(area / w / 64))) * 64;
    return {w, h};
}

void Backend::setBackground(const QString &url) {
    const QString path = QUrl(url).toLocalFile();
    if (!path.isEmpty())
        QProcess::startDetached("omarchy-theme-bg-set", {path});
}

void Backend::copy(const QString &url) {
    QFile file(QUrl(url).toLocalFile());
    if (!file.open(QIODevice::ReadOnly))
        return;
    auto *data = new QMimeData;
    data->setData("image/png", file.readAll());
    QGuiApplication::clipboard()->setMimeData(data);
}
