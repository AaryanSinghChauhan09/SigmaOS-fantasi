#include "models.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QSettings>
#include <QStandardPaths>
#include <QUrl>
#include <algorithm>

namespace {

QJsonDocument readJson(const QString &path) {
    QFile file(path);
    return file.open(QIODevice::ReadOnly) ? QJsonDocument::fromJson(file.readAll()) : QJsonDocument();
}

bool isImage(const QJsonObject &row) { return row.value("kind").toString() == "image"; }

} // namespace

Models::Models(const QString &stateDirectory, const QString &keyPath, const QString &command, QObject *parent)
    : QObject(parent),
      m_directory(!stateDirectory.isEmpty() ? stateDirectory : QDir::homePath() + "/.local/state/omarchy/agent-local"),
      m_keyPath(!keyPath.isEmpty() ? keyPath : QDir::homePath() + "/.config/omarchy/agent-local/key"),
      m_command(!command.isEmpty() ? command : QStandardPaths::findExecutable("omarchy-agent-local")) {
    // The engine replaces its files whole, which drops a file watch, so the
    // watch is armed again after every change.
    m_debounce.setSingleShot(true);
    m_debounce.setInterval(80);
    connect(&m_watcher, &QFileSystemWatcher::directoryChanged, this, [this] { m_debounce.start(); });
    connect(&m_watcher, &QFileSystemWatcher::fileChanged, this, [this] { m_debounce.start(); });
    connect(&m_debounce, &QTimer::timeout, this, &Models::reload);

    connect(&m_process, &QProcess::finished, this, [this](int code, QProcess::ExitStatus status) {
        if (code != 0 || status != QProcess::NormalExit) {
            // The engine says what went wrong on a line of its own.
            const QStringList lines = QString::fromUtf8(m_process.readAllStandardError() + m_process.readAllStandardOutput())
                                          .split('\n', Qt::SkipEmptyParts);
            const auto said = std::find_if(lines.rbegin(), lines.rend(), [](const QString &l) { return l.startsWith("Error: "); });
            m_error = said != lines.rend() ? said->mid(7).trimmed() : tr("The model couldn't be started");
            m_queue.clear();
            emit changed();
            return;
        }
        runNext();
    });
    connect(&m_process, &QProcess::errorOccurred, this, [this](QProcess::ProcessError error) {
        if (error != QProcess::FailedToStart)
            return;
        m_error = tr("omarchy-agent-local couldn't be run");
        m_queue.clear();
        emit changed();
    });

    reload();
    // The engine's list is rewritten after package updates; refreshing once
    // here means a newly installed engine's models show without a restart.
    // Its result arrives through the watched files, and a refresh that fails
    // is nothing to tell the user about.
    if (!m_command.isEmpty()) {
        QProcess refresh;
        refresh.setProgram(m_command);
        refresh.setArguments({"refresh", "--quiet"});
        refresh.setStandardOutputFile(QProcess::nullDevice());
        refresh.setStandardErrorFile(QProcess::nullDevice());
        refresh.startDetached();
    }
}

Models::Discovery Models::discover(const QJsonObject &status, const QJsonArray &list, bool engine,
                                   const QString &preferred) {
    Discovery found;
    if (!engine && status.isEmpty() && list.isEmpty()) {
        found.state = "noEngine";
        return found;
    }

    // The set-up models, preferring the one used last, then by name.
    const QJsonObject models = status.value("models").toObject();
    QList<QJsonObject> images;
    QStringList runningText, runningTextIds;
    for (auto it = models.begin(); it != models.end(); ++it) {
        QJsonObject row = it.value().toObject();
        row.insert("id", it.key());
        if (isImage(row))
            images << row;
        else if (row.value("unit").toString() == "active") {
            runningText << row.value("name").toString(it.key());
            runningTextIds << it.key();
        }
    }
    std::sort(images.begin(), images.end(), [&](const QJsonObject &a, const QJsonObject &b) {
        const bool aPreferred = a.value("id").toString() == preferred, bPreferred = b.value("id").toString() == preferred;
        if (aPreferred != bPreferred)
            return aPreferred;
        return a.value("name").toString() < b.value("name").toString();
    });

    // A running model wins, then one on its way, then one that's set up.
    for (const char *unit : {"active", "activating", "installing"}) {
        for (const QJsonObject &row : images) {
            if (row.value("unit").toString() != unit)
                continue;
            found.id = row.value("id").toString();
            found.name = row.value("name").toString(found.id);
            found.endpoint = row.value("endpoint").toString();
            found.edits = row.value("edit").toBool();
            found.state = QString(unit) == "active" ? "ready" : QString(unit) == "activating" ? "starting" : "installing";
            return found;
        }
    }
    if (!images.isEmpty()) {
        const QJsonObject &row = images.first();
        found.id = row.value("id").toString();
        found.name = row.value("name").toString(found.id);
        // An installed model the memory can't hold right now waits for the
        // text models in its way.
        if (row.value("fits").toBool(true) || runningText.isEmpty()) {
            found.state = "installed";
            found.reason = row.value("fit_reason").toString();
        } else {
            found.state = "blocked";
            found.reason = row.value("fit_reason").toString();
            found.blockers = runningText;
            found.blockerIds = runningTextIds;
        }
        return found;
    }

    // Nothing set up: the best image model that runs here, else why none does.
    QList<QJsonObject> candidates;
    QString reason;
    for (const QJsonValue &value : list) {
        const QJsonObject row = value.toObject();
        if (!isImage(row))
            continue;
        if (row.value("available").toBool())
            candidates << row;
        else if (reason.isEmpty())
            reason = row.value("reason").toString();
    }
    std::stable_sort(candidates.begin(), candidates.end(), [](const QJsonObject &a, const QJsonObject &b) {
        return a.value("best").toBool() && !b.value("best").toBool();
    });
    if (!candidates.isEmpty()) {
        found.state = "installable";
        found.id = candidates.first().value("id").toString();
        found.name = candidates.first().value("name").toString(found.id);
        return found;
    }
    found.state = "none";
    found.reason = reason;
    return found;
}

QString Models::origin() const {
    // The engine's endpoint is the OpenAI base, ending in /v1; the native
    // API lives beside it.
    QUrl url(m_found.endpoint);
    if (!url.isValid() || url.host().isEmpty())
        return {};
    url.setPath({});
    return url.toString(QUrl::StripTrailingSlash);
}

QByteArray Models::key() const {
    QFile file(m_keyPath);
    return file.open(QIODevice::ReadOnly) ? file.readAll().trimmed() : QByteArray();
}

void Models::start() {
    if (m_found.state == "installed")
        run({{"start", m_found.id}});
}

void Models::install() {
    if (m_found.state == "installable")
        run({{"use", m_found.id, "--detach"}});
}

void Models::switchTo() {
    if (m_found.state != "blocked")
        return;
    QList<QStringList> commands;
    for (const QString &id : m_found.blockerIds)
        commands << QStringList{"stop", id};
    commands << QStringList{"start", m_found.id};
    run(commands);
}

void Models::run(const QList<QStringList> &commands) {
    if (m_command.isEmpty() || working())
        return;
    m_error.clear();
    m_queue = commands;
    runNext();
    emit changed();
}

void Models::runNext() {
    if (m_queue.isEmpty()) {
        emit changed();
        return;
    }
    m_process.start(m_command, m_queue.takeFirst());
}

void Models::reload() {
    const auto paths = m_watcher.files() + m_watcher.directories();
    if (!paths.isEmpty())
        m_watcher.removePaths(paths);
    // Watching the nearest folder that exists means a first install of the
    // engine shows without a restart.
    QString ancestor = m_directory;
    while (!QFileInfo::exists(ancestor) && ancestor != "/")
        ancestor = QFileInfo(ancestor).absolutePath();
    QStringList candidates{ancestor, m_directory, m_directory + "/status.json", m_directory + "/list.json"};
    candidates.removeDuplicates();
    for (const QString &path : candidates)
        if (QFileInfo::exists(path))
            m_watcher.addPath(path);

    QSettings settings;
    const QString preferred = settings.value("model").toString();
    const Discovery found = discover(readJson(m_directory + "/status.json").object(),
                                     readJson(m_directory + "/list.json").array(), !m_command.isEmpty(), preferred);
    if (found.state == "ready" && found.id != preferred)
        settings.setValue("model", found.id);

    if (found.state != m_found.state || found.id != m_found.id || found.endpoint != m_found.endpoint || found.edits != m_found.edits
        || found.reason != m_found.reason || found.blockers != m_found.blockers) {
        m_found = found;
        emit changed();
    }
}
