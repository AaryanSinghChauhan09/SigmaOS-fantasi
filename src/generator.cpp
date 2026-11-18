#include "generator.h"

#include "models.h"

#include <QBuffer>
#include <QDateTime>
#include <QImage>
#include <cmath>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QImageReader>
#include <QJsonArray>
#include <QJsonDocument>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QRegularExpression>
#include <QStandardPaths>
#include <QTemporaryFile>
#include <QUrl>

namespace {

QJsonObject parse(QNetworkReply *reply) { return QJsonDocument::fromJson(reply->readAll()).object(); }

// The server's error text: a string, or an object with a message.
QString errorText(const QJsonObject &body) {
    const QJsonValue error = body.value("error");
    return error.isObject() ? error.toObject().value("message").toString() : error.toString();
}

// The server's stages, named the way the window says them.
QString stageFor(const QString &server) {
    if (server == "sampling")
        return "sampling";
    if (server == "vae_decode" || server == "encoding" || server == "upscaling" || server == "adetailer")
        return "decoding";
    if (server == "queued" || server == "waiting")
        return "queued";
    return "conditioning";
}

} // namespace

Generator::Generator(Models *models, const QString &folder, QObject *parent)
    : QObject(parent), m_models(models),
      m_folder(!folder.isEmpty() ? folder
                                 : QStandardPaths::writableLocation(QStandardPaths::PicturesLocation) + "/Generated") {
    // A job has no change signal of its own, so it is asked about while it
    // runs, and only then: a request at a time, half a second apart.
    m_poll.setSingleShot(true);
    m_poll.setInterval(500);
    connect(&m_poll, &QTimer::timeout, this, &Generator::poll);

    // The server's defaults are the model's own steps, size and guidance.
    auto follow = [this] {
        const QString origin = m_models->state() == "ready" ? m_models->origin() : QString();
        if (origin == m_origin)
            return;
        m_origin = origin;
        m_key = m_models->key();
        m_defaults = {};
        emit defaultsChanged();
        if (!m_origin.isEmpty())
            fetchDefaults();
    };
    connect(m_models, &Models::changed, this, follow);
    follow();
}

Generator::~Generator() { m_poll.stop(); }

int Generator::defaultSteps() const {
    return m_defaults.value("sample_params").toObject().value("sample_steps").toInt(8);
}

QNetworkReply *Generator::send(const QString &method, const QString &path, const QJsonObject &body) {
    QNetworkRequest request(QUrl((m_jobOrigin.isEmpty() ? m_origin : m_jobOrigin) + path));
    request.setRawHeader("Authorization", "Bearer " + m_key);
    request.setHeader(QNetworkRequest::ContentTypeHeader, "application/json");
    request.setTransferTimeout(15000);
    if (method == "POST")
        return m_network.post(request, QJsonDocument(body).toJson(QJsonDocument::Compact));
    return m_network.get(request);
}

void Generator::fetchDefaults() {
    QNetworkReply *reply = send("GET", "/sdcpp/v1/capabilities");
    connect(reply, &QNetworkReply::finished, this, [this, reply, origin = m_origin] {
        reply->deleteLater();
        if (origin != m_origin || reply->error() != QNetworkReply::NoError)
            return;
        const QJsonObject capabilities = parse(reply);
        const QJsonObject byMode = capabilities.value("defaults_by_mode").toObject().value("img_gen").toObject();
        m_defaults = !byMode.isEmpty() ? byMode : capabilities.value("defaults").toObject();
        emit defaultsChanged();
    });
}

QSize Generator::fitMegapixel(int width, int height) {
    const double area = 1024.0 * 1024.0, aspect = double(width) / height;
    const int w = std::max(1, int(std::lround(std::sqrt(area * aspect) / 64))) * 64;
    const int h = std::max(1, int(std::lround(area / w / 64))) * 64;
    return {w, h};
}

Generator::Base Generator::prepareBase(const QString &path) {
    QImageReader reader(path);
    // A camera's picture stands the way it was taken.
    reader.setAutoTransform(true);
    const QSize size = reader.size();
    if (!size.isValid())
        return {};
    // A size the model works in, near a megapixel, goes as it is: Fantasi's
    // own images, which a change keeps pixel for pixel.
    const bool fits = size.width() % 64 == 0 && size.height() % 64 == 0
                   && double(size.width()) * size.height() <= 1.6 * 1024 * 1024
                   && double(size.width()) * size.height() >= 0.4 * 1024 * 1024;
    if (fits && reader.format() == "png" && reader.transformation() == QImageIOHandler::TransformationNone) {
        QFile file(path);
        if (file.open(QIODevice::ReadOnly))
            return {file.readAll(), size};
    }
    // Anything else is scaled to cover the nearest size in its own shape,
    // then cut to it from the middle.
    const QImage image = reader.read();
    if (image.isNull())
        return {};
    const QSize target = fitMegapixel(image.width(), image.height());
    const QImage scaled = image.scaled(target, Qt::KeepAspectRatioByExpanding, Qt::SmoothTransformation);
    const QImage cropped = scaled.copy((scaled.width() - target.width()) / 2, (scaled.height() - target.height()) / 2,
                                       target.width(), target.height());
    QByteArray png;
    QBuffer buffer(&png);
    if (!buffer.open(QIODevice::WriteOnly) || !cropped.convertToFormat(QImage::Format_RGB32).save(&buffer, "PNG"))
        return {};
    return {png, target};
}

void Generator::generate(const QString &prompt, int width, int height, int steps, qint64 seed, const QString &baseUrl, bool edit) {
    if (busy() || prompt.trimmed().isEmpty())
        return;
    if (m_origin.isEmpty()) {
        m_error = tr("No image model is running");
        emit changed();
        return;
    }

    // The model's defaults, with what the window sets on top. A change goes
    // to a running edit model when the one in use isn't one, with that
    // server's own defaults.
    QJsonObject body = m_defaults;
    m_jobOrigin.clear();
    if (!baseUrl.isEmpty() && !edit && !m_models->editOrigin().isEmpty()) {
        m_jobOrigin = m_models->editOrigin();
        body = {};
        edit = true;
    }
    if (!baseUrl.isEmpty()) {
        const QString path = QUrl(baseUrl).isLocalFile() ? QUrl(baseUrl).toLocalFile() : baseUrl;
        const Base base = prepareBase(path);
        if (base.png.isEmpty()) {
            m_error = tr("Couldn't read the image to start from");
            emit changed();
            return;
        }
        if (edit) {
            body.insert("ref_images", QJsonArray{QString::fromLatin1(base.png.toBase64())});
        } else {
            body.insert("init_image", QString::fromLatin1(base.png.toBase64()));
            body.insert("strength", baseStrength);
        }
        width = base.size.width();
        height = base.size.height();
    }
    QJsonObject sample = body.value("sample_params").toObject();
    if (steps > 0)
        sample.insert("sample_steps", steps);
    body.insert("sample_params", sample);
    body.insert("prompt", prompt.trimmed());
    body.insert("width", width);
    body.insert("height", height);
    body.insert("seed", seed);
    body.insert("batch_count", 1);
    body.insert("preview", "proj");
    body.insert("preview_interval", 1);
    body.insert("output_format", "png");
    // The settings travel inside the PNG, which is how the history knows
    // each image's prompt and seed.
    body.insert("embed_image_metadata", true);

    m_prompt = prompt.trimmed();
    m_pending.clear();
    m_error.clear();
    m_submitting = true;
    m_cancelling = false;
    m_stage = "queued";
    m_step = 0;
    m_totalSteps = sample.value("sample_steps").toInt(defaultSteps());
    m_previews = QStringList(m_totalSteps, QString());
    m_image.clear();
    m_locker = std::make_unique<QEventLoopLocker>();
    emit changed();

    QNetworkReply *reply = send("POST", "/sdcpp/v1/img_gen", body);
    connect(reply, &QNetworkReply::finished, this, [this, reply] {
        reply->deleteLater();
        const QJsonObject answer = parse(reply);
        m_submitting = false;
        if (reply->error() != QNetworkReply::NoError || answer.value("id").toString().isEmpty()) {
            const QString said = errorText(answer);
            finish(!said.isEmpty() ? said : tr("The image model didn't answer: %1").arg(reply->errorString()));
            return;
        }
        m_job = answer.value("id").toString();
        // Cancelled while the job was being submitted.
        if (m_cancelling)
            send("POST", "/sdcpp/v1/jobs/" + m_job + "/cancel")->deleteLater();
        emit changed();
        m_poll.start();
    });
}

void Generator::cancel() {
    if (!busy() || m_cancelling)
        return;
    m_cancelling = true;
    // The server stops at its next checkpoint; the job is followed until it
    // says it has, since it may finish first.
    if (!m_job.isEmpty()) {
        QNetworkReply *reply = send("POST", "/sdcpp/v1/jobs/" + m_job + "/cancel");
        connect(reply, &QNetworkReply::finished, reply, &QObject::deleteLater);
    }
    emit changed();
}

void Generator::poll() {
    if (m_job.isEmpty())
        return;
    QNetworkReply *reply = send("GET", "/sdcpp/v1/jobs/" + m_job);
    connect(reply, &QNetworkReply::finished, this, [this, reply] {
        reply->deleteLater();
        if (reply->error() != QNetworkReply::NoError) {
            const QString said = errorText(parse(reply));
            finish(!said.isEmpty() ? said : tr("The image model stopped answering: %1").arg(reply->errorString()));
            return;
        }
        follow(parse(reply));
    });
}

void Generator::follow(const QJsonObject &job) {
    const QString status = job.value("status").toString();
    const QJsonObject progress = job.value("progress").toObject();
    m_stage = stageFor(progress.value("stage").toString(status));
    if (progress.value("unit").toString() == "steps") {
        m_step = progress.value("completed").toInt(m_step);
        const int total = progress.value("total").toInt(m_totalSteps);
        if (total > 0 && total != m_totalSteps) {
            m_totalSteps = total;
            m_previews.resize(total);
        }
    }
    const QJsonObject preview = job.value("preview").toObject();
    const int previewStep = preview.value("step").toInt();
    if (previewStep >= 1 && previewStep <= m_previews.size() && !preview.value("b64_json").toString().isEmpty()) {
        m_previews[previewStep - 1] = "data:image/png;base64," + preview.value("b64_json").toString();
        m_image = m_previews[previewStep - 1];
    }

    if (status == "completed") {
        const QJsonArray images = job.value("result").toObject().value("images").toArray();
        m_pending = QByteArray::fromBase64(images.first().toObject().value("b64_json").toString().toLatin1());
        if (m_pending.isEmpty()) {
            finish(tr("The image model finished without an image"));
            return;
        }
        m_step = m_totalSteps;
        m_stage = "saving";
        emit changed();
        finish(save() ? QString() : m_error);
    } else if (status == "failed") {
        finish(errorText(job).isEmpty() ? tr("The image couldn't be made") : errorText(job));
    } else if (status == "cancelled") {
        finish();
    } else {
        emit changed();
        m_poll.start();
    }
}

void Generator::finish(const QString &error) {
    m_poll.stop();
    m_job.clear();
    m_submitting = false;
    m_cancelling = false;
    m_stage.clear();
    m_jobOrigin.clear();
    m_error = error;
    m_locker.reset();
    emit changed();
    emit finished(error);
}

QString Generator::fileName(const QString &prompt, const QDateTime &when) {
    static const QRegularExpression word("[a-z0-9]+");
    QStringList words;
    for (auto it = word.globalMatch(prompt.toLower()); it.hasNext() && words.size() < 6;)
        words << it.next().captured();
    QString name = when.toString("yyyyMMdd-HHmmss");
    if (!words.isEmpty())
        name += "-" + words.join('-').left(48);
    return name;
}

bool Generator::save() {
    if (!QDir().mkpath(m_folder)) {
        m_error = tr("Couldn't make the folder %1").arg(m_folder);
        return false;
    }
    // Written beside its final name, then renamed into place: the history
    // never sees half a file, and a rename never replaces another image the
    // app or the command line saved in the same second.
    QTemporaryFile temporary(m_folder + "/.fantasi-XXXXXX.png");
    if (!temporary.open() || temporary.write(m_pending) != m_pending.size() || !temporary.flush()) {
        m_error = tr("Couldn't save the image in %1").arg(m_folder);
        return false;
    }
    // A temporary file is private; the image is as readable as a new file.
    temporary.setPermissions(QFile::ReadOwner | QFile::WriteOwner | QFile::ReadGroup | QFile::ReadOther);
    const QString base = m_folder + "/" + fileName(m_prompt, QDateTime::currentDateTime());
    for (int n = 1; n < 1000; ++n) {
        const QString path = base + (n == 1 ? QString() : "-" + QString::number(n)) + ".png";
        if (!QFileInfo::exists(path) && temporary.rename(path)) {
            temporary.setAutoRemove(false);
            m_pending.clear();
            m_image = QUrl::fromLocalFile(path).toString();
            emit saved(path);
            return true;
        }
    }
    m_error = tr("Couldn't save the image in %1").arg(m_folder);
    return false;
}

void Generator::retrySave() {
    if (m_pending.isEmpty() || busy())
        return;
    m_error.clear();
    save();
    emit changed();
}

void Generator::show(const QString &url) {
    if (busy())
        return;
    m_image = url;
    m_previews.clear();
    m_step = 0;
    m_totalSteps = 0;
    emit changed();
}
