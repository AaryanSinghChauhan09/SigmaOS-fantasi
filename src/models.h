#pragma once

#include <QFileSystemWatcher>
#include <QJsonArray>
#include <QJsonObject>
#include <QObject>
#include <QProcess>
#include <QStringList>
#include <QTimer>

// The image models omarchy-local-ai knows about, and which one Fantasi uses.
// It reads the engine's own status.json and list.json, follows their changes,
// and starts or sets up a model through omarchy-agent-local.
class Models : public QObject {
    Q_OBJECT
    // noEngine, none, installable, installing, installed, blocked, starting, ready
    Q_PROPERTY(QString state READ state NOTIFY changed)
    Q_PROPERTY(QString modelId READ modelId NOTIFY changed)
    Q_PROPERTY(QString modelName READ modelName NOTIFY changed)
    // Whether the model changes an image by an instruction (an edit model),
    // rather than redrawing it from a description.
    Q_PROPERTY(bool edits READ edits NOTIFY changed)
    // Why nothing runs here, or why the model can't start now.
    Q_PROPERTY(QString reason READ reason NOTIFY changed)
    // The running text models that hold the memory a blocked model needs.
    Q_PROPERTY(QStringList blockers READ blockers NOTIFY changed)
    Q_PROPERTY(bool working READ working NOTIFY changed)
    Q_PROPERTY(QString error READ error NOTIFY changed)

public:
    struct Discovery {
        QString state;
        QString id;
        QString name;
        QString endpoint;
        bool edits = false;
        QString reason;
        QStringList blockers;
        QStringList blockerIds;
    };

    // The engine's state folder, its key file, and the command that drives
    // it; empty means the user's own.
    explicit Models(const QString &stateDirectory = {}, const QString &keyPath = {}, const QString &command = {},
                    QObject *parent = nullptr);

    // What to use or offer, from the engine's two files. A row without a kind
    // is a text model, as every row was before the engine had image models.
    static Discovery discover(const QJsonObject &status, const QJsonArray &list, bool engine,
                              const QString &preferred = {});

    QString state() const { return m_found.state; }
    QString modelId() const { return m_found.id; }
    QString modelName() const { return m_found.name; }
    bool edits() const { return m_found.edits; }
    QString reason() const { return m_found.reason; }
    QStringList blockers() const { return m_found.blockers; }
    bool working() const { return m_process.state() != QProcess::NotRunning || !m_queue.isEmpty(); }
    QString error() const { return m_error; }

    // The ready model's server, as scheme://host:port, and the engine's key.
    QString origin() const;
    QByteArray key() const;

    Q_INVOKABLE void start();
    Q_INVOKABLE void install();
    // Stops the text models in the way, then starts the image model.
    Q_INVOKABLE void switchTo();

signals:
    void changed();

private:
    void reload();
    void run(const QList<QStringList> &commands);
    void runNext();

    QString m_directory;
    QString m_keyPath;
    QString m_command;
    Discovery m_found;
    QString m_error;
    QFileSystemWatcher m_watcher;
    QTimer m_debounce;
    QProcess m_process;
    QList<QStringList> m_queue;
};
