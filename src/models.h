#pragma once

#include <QFileSystemWatcher>
#include <QJsonArray>
#include <QJsonObject>
#include <QObject>
#include <QProcess>
#include <QStringList>
#include <QTimer>
#include <QVariantList>

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
    // Every image model that's set up, as {id, name}, in the order to step
    // through them; the one in use among them.
    Q_PROPERTY(QVariantList choices READ choices NOTIFY changed)
    Q_PROPERTY(QString vendor READ vendor NOTIFY changed)
    Q_PROPERTY(bool canEdit READ canEdit NOTIFY changed)
    // Whether a video model is running, and which, for its mark and tooltip.
    Q_PROPERTY(bool makesVideo READ makesVideo NOTIFY changed)
    Q_PROPERTY(QString videoName READ videoName NOTIFY changed)
    Q_PROPERTY(QString videoVendor READ videoVendor NOTIFY changed)
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
        QVariantList choices;
        // A running model that edits by instruction, for changing a picture
        // whichever model makes new ones.
        QString editEndpoint;
        QString editId;
        // Who makes the model, as Omarchy names vendors: bfl, alibaba, qwen.
        QString vendor;
        // A running video model, which makes clips beside the image model.
        QString videoEndpoint;
        QString videoId;
        QString videoName;
        QString videoVendor;
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
    QVariantList choices() const { return m_found.choices; }
    // Whether a running model edits by instruction, which can take several pictures.
    bool canEdit() const { return !m_found.editEndpoint.isEmpty(); }
    bool makesVideo() const { return !m_found.videoEndpoint.isEmpty(); }
    QString videoName() const { return m_found.videoName; }
    QString videoId() const { return m_found.videoId; }
    QString videoVendor() const { return m_found.videoVendor; }
    // The running video model's server, and its key.
    QString videoOrigin() const;
    QByteArray videoKey() const { return keyFor(m_found.videoId); }
    QString vendor() const { return m_found.vendor; }

    // The vendor's mark as the agents panel draws it, from Omarchy's own
    // set: its dark version on a light theme where there is one, the local
    // model's for a vendor without a mark, and empty without Omarchy.
    Q_INVOKABLE static QString logo(const QString &vendor, bool light);
    bool working() const { return m_process.state() != QProcess::NotRunning || !m_queue.isEmpty(); }
    QString error() const { return m_error; }

    // The ready model's server, as scheme://host:port, and the engine's key.
    QString origin() const;
    // The server of a running edit model, empty when none runs.
    QString editOrigin() const;
    QByteArray key() const { return keyFor(m_found.id); }
    // The key a model takes: the engine's own, or for a paired host's model
    // (host/recipe), the one that host gave when pairing.
    QByteArray keyFor(const QString &id) const;
    QByteArray editKey() const { return keyFor(m_found.editId); }

    Q_INVOKABLE void start();
    Q_INVOKABLE void install();
    // Stops the text models in the way, then starts the image model.
    Q_INVOKABLE void switchTo();
    // Uses another set-up image model from now on: stops the running one
    // and starts it.
    Q_INVOKABLE void choose(const QString &id);

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
    // The model chosen, kept as the one to use once it has started.
    QString m_chosen;
};
