#pragma once

#include <QByteArray>
#include <QEventLoopLocker>
#include <QJsonObject>
#include <QNetworkAccessManager>
#include <QObject>
#include <QSize>
#include <QStringList>
#include <QTimer>
#include <memory>

class Models;
class QNetworkReply;

// Makes one image at a time on the ready model's stable-diffusion.cpp server:
// submits a job, follows it with its previews step by step, and saves the
// finished image to the output folder.
class Generator : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool busy READ busy NOTIFY changed)
    // "", queued, conditioning, sampling, decoding, saving
    Q_PROPERTY(QString stage READ stage NOTIFY changed)
    Q_PROPERTY(int step READ step NOTIFY changed)
    Q_PROPERTY(int totalSteps READ totalSteps NOTIFY changed)
    // One preview per step as a data URL; an empty one is a step the
    // server moved past before it was asked.
    Q_PROPERTY(QStringList previews READ previews NOTIFY changed)
    // What the center shows: the newest preview, or the finished file.
    Q_PROPERTY(QString image READ image NOTIFY changed)
    Q_PROPERTY(QString error READ error NOTIFY changed)
    Q_PROPERTY(bool unsaved READ unsaved NOTIFY changed)
    Q_PROPERTY(int defaultSteps READ defaultSteps NOTIFY defaultsChanged)

public:
    explicit Generator(Models *models, const QString &folder = {}, QObject *parent = nullptr);
    ~Generator() override;

    bool busy() const { return !m_job.isEmpty() || m_submitting; }
    QString stage() const { return m_stage; }
    int step() const { return m_step; }
    int totalSteps() const { return m_totalSteps; }
    QStringList previews() const { return m_previews; }
    QString image() const { return m_image; }
    QString error() const { return m_error; }
    bool unsaved() const { return !m_pending.isEmpty(); }
    int defaultSteps() const;
    QString folder() const { return m_folder; }

    // A seed below zero asks the server for a random one; steps of zero take
    // the model's own default. With a base image the new one is a change of
    // it, at its size: an edit model takes the prompt as the instruction for
    // what to change; any other starts from the image and redraws it as the
    // prompt describes.
    Q_INVOKABLE void generate(const QString &prompt, int width, int height, int steps = 0, qint64 seed = -1,
                              const QString &baseUrl = {}, bool edit = false);

    // How far a redrawn image may move from its base: far enough that a change
    // asked for shows, near enough that the picture stays the same picture.
    static constexpr double baseStrength = 0.7;

    // A size near a megapixel in the shape of `width` by `height`, in the
    // steps of 64 the models work in.
    static QSize fitMegapixel(int width, int height);

    // A picture ready to start from: its PNG, at a size the model works in.
    struct Base {
        QByteArray png;
        QSize size;
    };
    static Base prepareBase(const QString &path);

    Q_INVOKABLE void cancel();
    // Writes a finished image the folder refused last time.
    Q_INVOKABLE void retrySave();
    // Shows an image from the history in the center.
    Q_INVOKABLE void show(const QString &url);

    // A new name in `folder` for an image made from `prompt` at `when`, which
    // no existing file has: the time, then the prompt's first words.
    static QString fileName(const QString &prompt, const QDateTime &when);

signals:
    void changed();
    void defaultsChanged();
    void saved(const QString &path);
    // A job has ended: made and saved, cancelled, or failed with `error`.
    void finished(const QString &error);

private:
    QNetworkReply *send(const QString &method, const QString &path, const QJsonObject &body = {});
    void fetchDefaults();
    void poll();
    void follow(const QJsonObject &job);
    void finish(const QString &error = {});
    bool save();

    Models *m_models;
    QString m_folder;
    QNetworkAccessManager m_network;
    QTimer m_poll;
    QJsonObject m_defaults;
    QString m_origin;
    // The server the job in hand runs on, when a change goes to a running
    // edit model rather than the one in use.
    QString m_jobOrigin;
    QByteArray m_jobKey;
    QByteArray m_key;

    QString m_job;
    bool m_submitting = false;
    bool m_cancelling = false;
    QString m_stage;
    int m_step = 0;
    int m_totalSteps = 0;
    QStringList m_previews;
    QString m_image;
    QString m_error;
    QString m_prompt;
    QByteArray m_pending;
    // The app keeps running until a started image is saved, even when its
    // window closes.
    std::unique_ptr<QEventLoopLocker> m_locker;
};
