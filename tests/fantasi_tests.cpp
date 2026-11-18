#include <QBuffer>
#include <QDir>
#include <QFile>
#include <QImage>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSignalSpy>
#include <QStandardPaths>
#include <QTcpServer>
#include <QTcpSocket>
#include <algorithm>
#include <functional>
#include <QLocalServer>
#include <QLocalSocket>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickItem>
#include <QQuickStyle>
#include <QQuickWindow>
#include <QRegularExpression>
#include <QTemporaryDir>
#include <QtTest>

#include "backend.h"
#include "theme.h"
#include "translator.h"

namespace {

bool write(const QString &path, const QByteArray &contents) {
    QFile file(path);
    return file.open(QIODevice::WriteOnly) && file.write(contents) == contents.size();
}

int lines(const QString &path) {
    QFile file(path);
    return file.open(QIODevice::ReadOnly) ? file.readAll().count('\n') : 0;
}

// The window's item with this objectName. What a Repeater, ListView or Loader
// makes isn't a QObject child of the window, so findChild never finds it; walk
// the items instead. Popups aren't items: find those with findChild.
QQuickItem *item(QQuickItem *from, const QString &name) {
    for (auto *child : from->childItems()) {
        if (child->objectName() == name)
            return child;
        if (auto *found = item(child, name))
            return found;
    }
    return nullptr;
}

// A hyprctl that answers with response.json beside it and counts its calls.
QString fakeHyprctl(const QString &directory) {
    const QString command = directory + "/hyprctl";
    write(command, "#!/bin/bash\necho >> '" + directory.toUtf8() + "/calls'\ncat '" + directory.toUtf8()
                       + "/response.json'\n");
    QFile::setPermissions(command, QFile::ReadOwner | QFile::WriteOwner | QFile::ExeOwner);
    return command;
}

QJsonObject readCatalog(const QString &path) {
    QFile file(path);
    return file.open(QIODevice::ReadOnly) ? QJsonDocument::fromJson(file.readAll()).object() : QJsonObject();
}

// The placeholders in a text, sorted: %1 to %99, and the count (%n, %Ln).
QStringList placeholders(const QString &text) {
    static const QRegularExpression placeholder("%L?(?:[1-9][0-9]?|n)");
    QStringList found;
    for (auto it = placeholder.globalMatch(text); it.hasNext();)
        found << it.next().captured();
    found.sort();
    return found;
}

// Every text the sources hand to qsTr() or tr(), and whether a call passes it
// a count. It walks the code a token at a time, so a string never hides a
// comment or the other way round, C++'s adjacent literals join, and QML's
// single quotes count. A text that isn't a literal can't be in a catalog.
QMap<QString, bool> translatables(const QString &folder, QStringList *problems) {
    QMap<QString, bool> found;
    for (const QFileInfo &info : QDir(folder).entryInfoList({"*.qml", "*.js", "*.cpp", "*.h"}, QDir::Files)) {
        QFile file(info.filePath());
        if (!file.open(QIODevice::ReadOnly))
            continue;
        const QString code = QString::fromUtf8(file.readAll());
        qsizetype i = 0;
        auto literal = [&](QString *text) {
            const QChar quote = code[i++];
            for (; i < code.size() && code[i] != quote; ++i) {
                if (code[i] == '\\' && i + 1 < code.size()) {
                    const QChar escaped = code[++i];
                    const int digits = escaped == 'u' ? 4 : escaped == 'x' ? 2 : 0;
                    bool hex = false;
                    const ushort unit = code.mid(i + 1, digits).toUShort(&hex, 16);
                    if (digits && hex) {
                        *text += QChar(unit);
                        i += digits;
                    } else {
                        *text += escaped == 'n' ? QChar('\n') : escaped == 't' ? QChar('\t') : escaped;
                    }
                } else {
                    *text += code[i];
                }
            }
            ++i;
        };
        auto skipSpace = [&] {
            while (i < code.size() && code[i].isSpace())
                ++i;
        };
        while (i < code.size()) {
            const QChar c = code[i];
            if (code.mid(i, 2) == "//") {
                i = code.indexOf('\n', i);
                if (i < 0)
                    break;
            } else if (code.mid(i, 2) == "/*") {
                i = code.indexOf("*/", i + 2);
                if (i < 0)
                    break;
                i += 2;
            } else if (c == '"' || c == '\'') {
                QString skipped;
                literal(&skipped);
            } else if (c.isLetter() || c == '_') {
                const qsizetype start = i;
                while (i < code.size() && (code[i].isLetterOrNumber() || code[i] == '_'))
                    ++i;
                const QString word = code.mid(start, i - start);
                skipSpace();
                if ((word != "qsTr" && word != "tr") || i >= code.size() || code[i] != '(')
                    continue;
                ++i;
                skipSpace();
                if (i >= code.size() || (code[i] != '"' && code[i] != '\'')) {
                    *problems << info.fileName() + ": not a literal: " + code.mid(start, 40);
                    continue;
                }
                QString text;
                do {
                    literal(&text);
                    skipSpace();
                } while (i < code.size() && code[i] == '"');
                // The arguments after the text, to the call's closing parenthesis.
                int depth = 0, commas = 0;
                while (i < code.size()) {
                    const QChar d = code[i];
                    if (d == '"' || d == '\'') {
                        QString skipped;
                        literal(&skipped);
                        continue;
                    }
                    if (d == '(' || d == '[' || d == '{')
                        ++depth;
                    else if ((d == ')' || d == ']' || d == '}') && depth-- == 0)
                        break;
                    else if (d == ',' && depth == 0)
                        ++commas;
                    ++i;
                }
                found[text] = found.value(text) || commas >= 2;
            } else {
                ++i;
            }
        }
    }
    return found;
}

// JSON written with ' for ", so moc, which doesn't understand raw literals,
// never meets one.
QByteArray q(const char *text) { return QByteArray(text).replace('\'', '"'); }
QJsonObject json(const QByteArray &text) { return QJsonDocument::fromJson(text).object(); }
QJsonArray jsonArray(const QByteArray &text) { return QJsonDocument::fromJson(text).array(); }

// A stand-in for stable-diffusion.cpp's server: answers each request with
// what `answer` returns for its method and path, and records the bodies.
class FakeServer : public QObject {
public:
    std::function<QPair<int, QByteArray>(const QString &, const QString &)> answer;
    QList<QPair<QString, QJsonObject>> requests;
    QTcpServer server;

    FakeServer() {
        server.listen(QHostAddress::LocalHost);
        connect(&server, &QTcpServer::newConnection, this, [this] {
            while (QTcpSocket *socket = server.nextPendingConnection()) {
                auto *buffer = new QByteArray;
                connect(socket, &QTcpSocket::readyRead, socket, [this, socket, buffer] {
                    *buffer += socket->readAll();
                    const qsizetype end = buffer->indexOf("\r\n\r\n");
                    if (end < 0)
                        return;
                    const QList<QByteArray> head = buffer->left(end).split('\n');
                    qsizetype length = 0;
                    for (const QByteArray &line : head)
                        if (line.toLower().startsWith("content-length:"))
                            length = line.mid(15).trimmed().toLongLong();
                    if (buffer->size() < end + 4 + length)
                        return;
                    const QList<QByteArray> request = head.first().split(' ');
                    const QString method = request.value(0), path = request.value(1);
                    requests << qMakePair(method + " " + path, QJsonDocument::fromJson(buffer->mid(end + 4, length)).object());
                    const auto [status, body] = answer(method, path);
                    socket->write("HTTP/1.1 " + QByteArray::number(status) + " X\r\nContent-Type: application/json\r\n"
                                  "Content-Length: " + QByteArray::number(body.size()) + "\r\nConnection: close\r\n\r\n" + body);
                    socket->disconnectFromHost();
                    delete buffer;
                });
                connect(socket, &QTcpSocket::disconnected, socket, &QObject::deleteLater);
            }
        });
    }
    QString origin() const { return QString("http://127.0.0.1:%1").arg(server.serverPort()); }
};

// An engine state folder with one image model ready at `origin`, and a key.
void readyEngine(const QString &folder, const QString &origin) {
    QDir().mkpath(folder);
    write(folder + "/status.json", QJsonDocument(QJsonObject{{"models", QJsonObject{{"z-image-turbo", QJsonObject{
        {"kind", "image"}, {"name", "Z-Image Turbo"}, {"unit", "active"}, {"endpoint", origin + "/v1"}}}}}}).toJson());
    write(folder + "/list.json", "[]");
    write(folder + "/key", "secret\n");
}

QByteArray png(int size = 8) {
    QImage image(size, size, QImage::Format_RGB32);
    image.fill(Qt::darkCyan);
    QByteArray bytes;
    QBuffer buffer(&bytes);
    buffer.open(QIODevice::WriteOnly);
    image.save(&buffer, "PNG");
    return bytes;
}

// A save dialog that answers with `answer` at once.
class FakePicker : public FilePicker {
public:
    QUrl answer;
    QUrl suggested;
    void openImage() override { emit openSelected(answer); }
    void saveImage(const QUrl &suggestedUrl) override {
        suggested = suggestedUrl;
        emit saveSelected(answer);
    }
};

} // namespace

class FantasiTests : public QObject {
    Q_OBJECT

private slots:
    void initTestCase() {
        QQuickStyle::setStyle("Material");
        // The model used last is remembered in settings; never the user's own.
        QStandardPaths::setTestModeEnabled(true);
    }

    void discoveryWithoutTheEngine() {
        QCOMPARE(Models::discover({}, {}, false).state, QString("noEngine"));
    }

    void discoveryIgnoresTextModels() {
        // Rows without a kind are the text models the engine always had.
        const auto found = Models::discover(json(q("{'models': {'qwen': {'name': 'Qwen', 'unit': 'active'}}}")),
                                            jsonArray(q("[{'id': 'qwen', 'available': true}]")), true);
        QCOMPARE(found.state, QString("none"));
    }

    void discoveryUsesTheRunningModel() {
        const auto found = Models::discover(json(q("{'models': { 'a': {'kind': 'image', 'name': 'A', 'unit': 'active', 'endpoint': 'http://127.0.0.1:1/v1'}, 'b': {'kind': 'image', 'name': 'B', 'unit': 'active', 'endpoint': 'http://127.0.0.1:2/v1'}}}")), {}, true, "b");
        QCOMPARE(found.state, QString("ready"));
        QCOMPARE(found.id, QString("b"));
    }

    void discoveryOffersToStartAnInstalledModel() {
        const auto found = Models::discover(json(q("{'models': {'z': {'kind': 'image', 'name': 'Z', 'unit': 'inactive'}}}")), {}, true);
        QCOMPARE(found.state, QString("installed"));
        QCOMPARE(found.id, QString("z"));
    }

    void discoveryNamesTheTextModelInTheWay() {
        const auto found = Models::discover(json(q("{'models': { 'z': {'kind': 'image', 'name': 'Z', 'unit': 'inactive', 'fits': false, 'fit_reason': 'Not enough memory'}, 'qwen': {'name': 'Qwen3.8 27B', 'unit': 'active'}}}")), {}, true);
        QCOMPARE(found.state, QString("blocked"));
        QCOMPARE(found.blockers, QStringList{"Qwen3.8 27B"});
        QCOMPARE(found.blockerIds, QStringList{"qwen"});
    }

    void discoveryOffersTheBestModelThatRunsHere() {
        const auto found = Models::discover({}, jsonArray(q("[ {'id': 'big', 'kind': 'image', 'name': 'Big', 'available': false, 'reason': 'needs 128 GB'}, {'id': 'ok', 'kind': 'image', 'name': 'Ok', 'available': true}, {'id': 'best', 'kind': 'image', 'name': 'Best', 'available': true, 'best': true}]")), true);
        QCOMPARE(found.state, QString("installable"));
        QCOMPARE(found.id, QString("best"));
    }

    void discoverySaysWhyNothingRunsHere() {
        const auto found = Models::discover({}, jsonArray(q("[ {'id': 'big', 'kind': 'image', 'available': false, 'reason': 'needs 128 GB'}]")), true);
        QCOMPARE(found.state, QString("none"));
        QCOMPARE(found.reason, QString("needs 128 GB"));
    }

    void modelsFollowTheEngineFiles() {
        QTemporaryDir dir;
        Models models(dir.path() + "/state", dir.path() + "/state/key", "/bin/true");
        QCOMPARE(models.state(), QString("none"));
        // The engine writes its files whole, after the app has started.
        readyEngine(dir.path() + "/state", "http://127.0.0.1:4321");
        QTRY_COMPARE(models.state(), QString("ready"));
        QCOMPARE(models.origin(), QString("http://127.0.0.1:4321"));
        QCOMPARE(models.key(), QByteArray("secret"));
    }

    void fileNamesStartWithTheTime() {
        const QDateTime when(QDate(2026, 11, 18), QTime(15, 4, 5));
        QCOMPARE(Generator::fileName("A calm lake, at dusk! With mist over the water", when),
                 QString("20261118-150405-a-calm-lake-at-dusk-with"));
        QCOMPARE(Generator::fileName("!!!", when), QString("20261118-150405"));
    }

    void generatorSavesTheFinishedImageWithItsPreviews() {
        QTemporaryDir dir;
        FakeServer server;
        int polls = 0;
        const QByteArray image = png().toBase64();
        server.answer = [&](const QString &method, const QString &path) -> QPair<int, QByteArray> {
            if (path == "/sdcpp/v1/capabilities")
                return {200, q("{'defaults_by_mode': {'img_gen': {'sample_params': {'sample_steps': 4, 'guidance': {'txt_cfg': 1.0}}}}}")};
            if (method == "POST" && path == "/sdcpp/v1/img_gen")
                return {202, q("{'id': 'job1', 'status': 'queued'}")};
            if (path == "/sdcpp/v1/jobs/job1") {
                ++polls;
                // Escaped, not raw: moc misreads a raw literal with a lone quote.
                const QByteArray step = QByteArray::number(polls);
                if (polls < 3)
                    return {200, "{\"status\": \"generating\", \"progress\": {\"stage\": \"sampling\", \"unit\": \"steps\", "
                                 "\"completed\": " + step + ", \"total\": 4}, \"preview\": {\"step\": " + step
                                     + ", \"total_steps\": 4, \"b64_json\": \"" + image + "\"}}"};
                return {200, "{\"status\": \"completed\", \"result\": {\"images\": [{\"index\": 0, \"b64_json\": \"" + image + "\"}]}}"};
            }
            return {404, "{}"};
        };
        readyEngine(dir.path() + "/state", server.origin());
        Models models(dir.path() + "/state", dir.path() + "/state/key", "/bin/true");
        Generator generator(&models, dir.path() + "/out");
        QTRY_COMPARE(generator.defaultSteps(), 4);

        QSignalSpy saved(&generator, &Generator::saved);
        generator.generate("a lake", 1024, 768, 0, -1);
        QVERIFY(generator.busy());
        QTRY_VERIFY_WITH_TIMEOUT(saved.size() == 1, 10000);
        QVERIFY(!generator.busy());
        QVERIFY(generator.error().isEmpty());

        // The request carries the model's defaults under what the window set.
        const QJsonObject body = server.requests.at(1).second;
        QCOMPARE(server.requests.at(1).first, QString("POST /sdcpp/v1/img_gen"));
        QCOMPARE(body.value("width").toInt(), 1024);
        QCOMPARE(body.value("height").toInt(), 768);
        QCOMPARE(body.value("sample_params").toObject().value("sample_steps").toInt(), 4);
        QCOMPARE(body.value("sample_params").toObject().value("guidance").toObject().value("txt_cfg").toDouble(), 1.0);
        QCOMPARE(body.value("preview").toString(), QString("proj"));

        // Two steps were caught as they rendered; the rest were not.
        QCOMPARE(generator.previews().size(), 4);
        QVERIFY(generator.previews().at(0).startsWith("data:image/png;base64,"));
        QVERIFY(generator.previews().at(1).startsWith("data:image/png;base64,"));
        QVERIFY(generator.previews().at(2).isEmpty());

        const QString path = saved.first().first().toString();
        QVERIFY(QFileInfo(path).fileName().endsWith("-a-lake.png"));
        QCOMPARE(generator.image(), QUrl::fromLocalFile(path).toString());
        QFile file(path);
        QVERIFY(file.open(QIODevice::ReadOnly));
        QCOMPARE(file.readAll(), QByteArray::fromBase64(image));
        // Nothing half-written is left beside it.
        QCOMPARE(QDir(dir.path() + "/out").entryList(QDir::Files | QDir::Hidden).size(), 1);
    }

    void generatorStartsFromABaseImageAtItsSize() {
        QTemporaryDir dir;
        FakeServer server;
        server.answer = [&](const QString &method, const QString &path) -> QPair<int, QByteArray> {
            if (method == "POST" && path == "/sdcpp/v1/img_gen")
                return {202, q("{'id': 'job4'}")};
            if (path == "/sdcpp/v1/jobs/job4")
                return {200, q("{'status': 'cancelled'}")};
            return {404, "{}"};
        };
        readyEngine(dir.path() + "/state", server.origin());
        QImage base(1344, 768, QImage::Format_RGB32);
        base.fill(Qt::darkBlue);
        QVERIFY(base.save(dir.filePath("base.png")));

        Models models(dir.path() + "/state", dir.path() + "/state/key", "/bin/true");
        Generator generator(&models, dir.path() + "/out");
        generator.generate("the same, with snow", 1024, 1024, 0, -1, QUrl::fromLocalFile(dir.filePath("base.png")).toString());
        QTRY_VERIFY(!server.requests.isEmpty() && server.requests.last().first == "POST /sdcpp/v1/img_gen");
        const QJsonObject body = server.requests.last().second;
        QFile file(dir.filePath("base.png"));
        QVERIFY(file.open(QIODevice::ReadOnly));
        const QString sent = QString::fromLatin1(file.readAll().toBase64());
        QCOMPARE(body.value("init_image").toString(), sent);
        QCOMPARE(body.value("strength").toDouble(), Generator::baseStrength);
        QVERIFY(!body.contains("ref_images"));
        QCOMPARE(body.value("width").toInt(), 1344);
        QCOMPARE(body.value("height").toInt(), 768);
        QTRY_VERIFY(!generator.busy());

        // An edit model gets the image as a reference and the prompt as the change.
        generator.generate("include a red balloon", 1024, 1024, 0, -1, QUrl::fromLocalFile(dir.filePath("base.png")).toString(), true);
        QTRY_VERIFY(std::count_if(server.requests.begin(), server.requests.end(), [](const auto &r) { return r.first == "POST /sdcpp/v1/img_gen"; }) == 2);
        const QJsonObject edit = server.requests.last().second;
        QCOMPARE(edit.value("ref_images").toArray(), QJsonArray{sent});
        QVERIFY(!edit.contains("init_image") && !edit.contains("strength"));
        QCOMPARE(edit.value("width").toInt(), 1344);
        QTRY_VERIFY(!generator.busy());
    }

    void generatorCancelsAndSavesNothing() {
        QTemporaryDir dir;
        FakeServer server;
        bool cancelled = false;
        server.answer = [&](const QString &method, const QString &path) -> QPair<int, QByteArray> {
            if (method == "POST" && path == "/sdcpp/v1/img_gen")
                return {202, q("{'id': 'job2'}")};
            if (path == "/sdcpp/v1/jobs/job2/cancel") {
                cancelled = true;
                return {200, q("{'cancel_requested': true}")};
            }
            if (path == "/sdcpp/v1/jobs/job2")
                return {200, cancelled ? q("{'status': 'cancelled'}") : q("{'status': 'generating', 'progress': {'stage': 'sampling'}}")};
            return {404, "{}"};
        };
        readyEngine(dir.path() + "/state", server.origin());
        Models models(dir.path() + "/state", dir.path() + "/state/key", "/bin/true");
        Generator generator(&models, dir.path() + "/out");
        generator.generate("a lake", 512, 512, 4, 7);
        QTRY_VERIFY(!server.requests.isEmpty());
        QTRY_VERIFY(generator.stage() == "sampling");
        generator.cancel();
        QTRY_VERIFY_WITH_TIMEOUT(!generator.busy(), 10000);
        QVERIFY(cancelled);
        QVERIFY(generator.error().isEmpty());
        QVERIFY(!QFileInfo::exists(dir.path() + "/out") || QDir(dir.path() + "/out").isEmpty());
    }

    void generatorSaysWhyAnImageFailed() {
        QTemporaryDir dir;
        FakeServer server;
        server.answer = [&](const QString &method, const QString &path) -> QPair<int, QByteArray> {
            if (method == "POST" && path == "/sdcpp/v1/img_gen")
                return {202, q("{'id': 'job3'}")};
            if (path == "/sdcpp/v1/jobs/job3")
                return {200, q("{'status': 'failed', 'error': {'code': 'generation_failed', 'message': 'out of memory'}}")};
            return {404, "{}"};
        };
        readyEngine(dir.path() + "/state", server.origin());
        Models models(dir.path() + "/state", dir.path() + "/state/key", "/bin/true");
        Generator generator(&models, dir.path() + "/out");
        generator.generate("a lake", 512, 512, 4, -1);
        QTRY_COMPARE_WITH_TIMEOUT(generator.error(), QString("out of memory"), 10000);
        QVERIFY(!generator.busy());
    }

    void historyReadsWhatTheImagesCarry() {
        QTemporaryDir dir;
        QImage image(4, 4, QImage::Format_RGB32);
        image.fill(Qt::red);
        image.setText("parameters", "a lake\nat dusk\nSteps: 8, Sampler: Euler, CFG scale: 1.0, Seed: 42, Size: 1024x768, Model: z");
        QVERIFY(image.save(dir.filePath("old.png")));
        QFile old(dir.filePath("old.png"));
        QVERIFY(old.open(QIODevice::ReadWrite));
        QVERIFY(old.setFileTime(QDateTime::currentDateTime().addSecs(-60), QFileDevice::FileModificationTime));
        old.close();
        QVERIFY(write(dir.filePath("new.png"), png()));
        QVERIFY(write(dir.filePath(".fantasi-partial.png"), "half"));

        const QList<History::Entry> entries = History::scan(dir.path());
        QCOMPARE(entries.size(), 2);
        QCOMPARE(QFileInfo(entries.at(0).path).fileName(), QString("new.png"));
        QCOMPARE(entries.at(1).prompt, QString("a lake\nat dusk"));
        QCOMPARE(entries.at(1).seed, 42);
        QCOMPARE(entries.at(1).size, QString("1024x768"));
    }

    void saveAsCopiesTheImageWhereThePickerSays() {
        QTemporaryDir dir;
        QVERIFY(write(dir.filePath("made.png"), png()));
        auto *picker = new FakePicker;
        Backend backend({dir.path() + "/state", {}, "/bin/true", dir.path() + "/out", "/bin/true"}, picker);
        picker->setParent(&backend);

        picker->answer = QUrl::fromLocalFile(dir.filePath("copy.png"));
        backend.saveAs(QUrl::fromLocalFile(dir.filePath("made.png")).toString());
        QVERIFY(picker->suggested.toLocalFile().endsWith("/made.png"));
        QVERIFY(backend.error().isEmpty());
        QFile copy(dir.filePath("copy.png"));
        QVERIFY(copy.open(QIODevice::ReadOnly));
        QCOMPARE(copy.readAll(), png());

        // A folder that isn't there: said so, and nothing half-written.
        picker->answer = QUrl::fromLocalFile(dir.filePath("missing/copy.png"));
        backend.saveAs(QUrl::fromLocalFile(dir.filePath("made.png")).toString());
        QVERIFY(backend.error().startsWith("Couldn't save the image as"));
        QVERIFY(!QFileInfo::exists(dir.filePath("missing")));
    }

    void aPictureOfOnesOwnBecomesABaseTheModelWorksIn() {
        QTemporaryDir dir;
        // A camera's picture: any size, any shape, a JPEG.
        QImage photo(4000, 3000, QImage::Format_RGB32);
        photo.fill(Qt::darkGreen);
        QVERIFY(photo.save(dir.filePath("photo.jpg")));
        const Generator::Base base = Generator::prepareBase(dir.filePath("photo.jpg"));
        QCOMPARE(base.size, QSize(1152, 896));
        QImage sent;
        QVERIFY(sent.loadFromData(base.png, "PNG"));
        QCOMPARE(sent.size(), QSize(1152, 896));

        // Fantasi's own image goes as it is, byte for byte.
        QVERIFY(write(dir.filePath("made.png"), png(1024)));
        QCOMPARE(Generator::prepareBase(dir.filePath("made.png")).png, png(1024));
        QVERIFY(Generator::prepareBase(dir.filePath("missing.png")).png.isEmpty());
    }

    void aPictureChosenInTheDialogReachesTheWindow() {
        QTemporaryDir dir;
        auto *picker = new FakePicker;
        Backend backend({dir.path() + "/state", {}, "/bin/true", dir.path() + "/out", "/bin/true"}, picker);
        picker->setParent(&backend);
        picker->answer = QUrl::fromLocalFile(dir.filePath("mine.jpg"));
        QSignalSpy chosen(&backend, &Backend::pictureChosen);
        backend.openPicture();
        QCOMPARE(chosen.size(), 1);
        QCOMPARE(chosen.first().first().toString(), picker->answer.toString());
    }

    void screenSizeIsAMegapixelInTheMonitorsShape() {
        QCOMPARE(Generator::fitMegapixel(2560, 1440), QSize(1344, 768));
        QCOMPARE(Generator::fitMegapixel(1440, 2560), QSize(768, 1344));
        QCOMPARE(Generator::fitMegapixel(1000, 1000), QSize(1024, 1024));
    }

    void themeFallsBack() {
        QTemporaryDir dir;
        Theme theme(dir.path());
        QCOMPARE(theme.accent(), QColor("#FFD60A"));
        QCOMPARE(theme.accentForeground(), QColor("black"));
        QVERIFY(!theme.light());
        QCOMPARE(theme.radius(), 0);
    }

    void themeReadsThePalette() {
        QTemporaryDir dir;
        QVERIFY(QDir(dir.path()).mkpath("theme"));
        QVERIFY(write(dir.path() + "/theme/colors.toml", "mode = \"light\"\n"
                                                         "theme_type = \"dark\"\n"
                                                         "accent = \"#112233\"\n"
                                                         "bg = #fafafa # paper\n"
                                                         "foreground = '#202020'\n"
                                                         "color1 = \"#aa0000\"\n"));

        Theme theme(dir.path());
        QCOMPARE(theme.accent(), QColor("#112233"));
        QCOMPARE(theme.accentForeground(), QColor("white"));
        QCOMPARE(theme.background(), QColor("#fafafa"));
        QCOMPARE(theme.foreground(), QColor("#202020"));
        QCOMPARE(theme.colors().value("red").value<QColor>(), QColor("#aa0000"));
        QVERIFY(theme.light());
    }

    void themeAsksHyprlandAgainOnlyWhenItReloads() {
        // The fake Hyprland lives outside the theme directory, whose changes
        // the Theme also follows.
        QTemporaryDir dir, hypr;
        const QString command = fakeHyprctl(hypr.path());
        QVERIFY(write(hypr.filePath("response.json"), "{\"int\":4}"));
        QLocalServer events;
        QVERIFY(events.listen(hypr.filePath("events.sock")));

        // Once on start, and once more when the event socket connects.
        Theme theme(dir.path(), nullptr, command, events.fullServerName());
        QTRY_VERIFY(events.hasPendingConnections());
        QLocalSocket *hyprland = events.nextPendingConnection();
        QTRY_COMPARE(lines(hypr.filePath("calls")), 2);
        QTRY_COMPARE(theme.radius(), 4);

        QVERIFY(write(hypr.filePath("response.json"), "{\"int\":10}"));
        QTest::qWait(300);
        QCOMPARE(lines(hypr.filePath("calls")), 2);
        // Events arrive in pieces; only a whole configreloaded line counts.
        hyprland->write("activewindow>>kitty,~\nconfigrel");
        hyprland->flush();
        QTest::qWait(100);
        QCOMPARE(lines(hypr.filePath("calls")), 2);
        hyprland->write("oaded>>\n");
        QTRY_COMPARE(theme.radius(), 10);
        QCOMPARE(lines(hypr.filePath("calls")), 3);
    }

    void themeReachesHyprlandOnceItListens() {
        QTemporaryDir dir, hypr;
        const QString command = fakeHyprctl(hypr.path());
        QVERIFY(write(hypr.filePath("response.json"), "{\"int\":4}"));
        Theme theme(dir.path(), nullptr, command, hypr.filePath("events.sock"));
        QTRY_COMPARE(theme.radius(), 4);

        QVERIFY(write(hypr.filePath("response.json"), "{\"int\":8}"));
        QLocalServer events;
        QVERIFY(events.listen(hypr.filePath("events.sock")));
        QTRY_VERIFY_WITH_TIMEOUT(events.hasPendingConnections(), 5000);
        QTRY_COMPARE(theme.radius(), 8);
    }

    void translatorFallsBackToEnglish() {
        QTemporaryDir dir;
        Translator translator(dir.path() + "/language", dir.path());
        QCOMPARE(translator.language(), QString("en"));
        QVERIFY(translator.translate("Main", "Save").isNull());
    }

    void translatorFollowsTheLanguageFile() {
        QTemporaryDir dir;
        QVERIFY(write(dir.path() + "/language", "pt-BR\n"));
        QVERIFY(write(dir.path() + "/pt.json", R"({"Save": "Guardar", "Open": "Abrir"})"));
        QVERIFY(write(dir.path() + "/pt-BR.json", R"({"Save": "Salvar"})"));

        Translator translator(dir.path() + "/language", dir.path());
        QCOMPARE(translator.language(), QString("pt-BR"));
        QCOMPARE(translator.translate("Main", "Save"), QString("Salvar"));
        QCOMPARE(translator.translate("Main", "Open"), QString("Abrir"));
        QVERIFY(translator.translate("Main", "Quit").isNull());
    }

    void translatorSeesAFirstPick() {
        // Before the first pick there is no ~/.config/omarchy to watch.
        QTemporaryDir dir;
        QVERIFY(write(dir.path() + "/da.json", R"({"Save": "Gem"})"));
        Translator translator(dir.path() + "/omarchy/language", dir.path());
        QVERIFY(QDir(dir.path()).mkpath("omarchy"));
        QVERIFY(write(dir.path() + "/omarchy/language", "da\n"));
        QTRY_COMPARE(translator.translate("Main", "Save"), QString("Gem"));
    }

    void translatorPicksPluralForms() {
        QTemporaryDir dir;
        QVERIFY(write(dir.path() + "/language", "ru\n"));
        QVERIFY(write(dir.path() + "/en.json", R"({"%n clips": {"one": "%n clip", "other": "%n clips"},
                                                   "%n files": {"one": "%n file", "other": "%n files"}})"));
        QVERIFY(write(dir.path() + "/ru.json", R"({"%n clips": {"one": "%n клип", "few": "%n клипа", "many": "%n клипов", "other": "%n клипа"}})"));

        Translator translator(dir.path() + "/language", dir.path());
        QCOMPARE(translator.translate("Main", "%n clips", nullptr, 21), QString("%n клип"));
        QCOMPARE(translator.translate("Main", "%n clips", nullptr, 22), QString("%n клипа"));
        QCOMPARE(translator.translate("Main", "%n clips", nullptr, 25), QString("%n клипов"));
        // An untranslated counted string falls back to English, with English rules.
        QCOMPARE(translator.translate("Main", "%n files", nullptr, 21), QString("%n files"));
    }

    void englishCatalogListsEveryString() {
        // en.json is what translators work from: every text the sources
        // translate is in it, as itself or, when counted, as its English
        // plural forms, and nothing else is.
        const QString sources = QFileInfo(QFINDTESTDATA("../src/Main.qml")).absolutePath();
        QStringList problems;
        const QMap<QString, bool> used = translatables(sources, &problems);
        const QJsonObject english = readCatalog(sources + "/i18n/en.json");
        for (auto it = used.begin(); it != used.end(); ++it) {
            const QJsonValue value = english.value(it.key());
            if (value.isUndefined())
                problems << "missing from en.json: " + it.key();
            else if (it.value() && (value.toObject().keys() != QStringList{"one", "other"}
                                    || value.toObject().value("other").toString() != it.key()))
                problems << "counted, so needs its one and other forms: " + it.key();
            else if (!it.value() && value.toString() != it.key())
                problems << "should be itself: " + it.key();
        }
        for (const QString &key : english.keys())
            if (!used.contains(key))
                problems << "in en.json but no source translates it: " + key;
        QVERIFY2(problems.isEmpty(), qPrintable(problems.join('\n')));
    }

    void catalogsMatchTheEnglishOne() {
        // A catalog may lack a string (it shows in English meanwhile), but what
        // it has translates something in en.json, with the same placeholders,
        // and a counted string has every form its language uses.
        const QString folder = QFileInfo(QFINDTESTDATA("../src/i18n/en.json")).absolutePath();
        const QJsonObject english = readCatalog(folder + "/en.json");
        QStringList problems;
        for (const QFileInfo &file : QDir(folder).entryInfoList({"*.json"}, QDir::Files)) {
            const QString code = file.completeBaseName();
            const QJsonObject catalog = readCatalog(file.filePath());
            if (catalog.isEmpty())
                problems << code + ": not a JSON object, or empty";
            // Some languages reach a form only at a million ("many" in French).
            QSet<QString> categories{"other", Translator::pluralCategory(code, 1000000)};
            for (long long n = 0; n <= 1000; ++n)
                categories << Translator::pluralCategory(code, n);
            for (auto it = catalog.begin(); it != catalog.end(); ++it) {
                const QString where = code + ": " + it.key() + ": ";
                const QJsonValue source = english.value(it.key());
                if (source.isUndefined()) {
                    problems << where + "not in en.json";
                } else if (source.isString()) {
                    if (!it.value().isString() || it.value().toString().isEmpty())
                        problems << where + "needs a translation";
                    else if (placeholders(it.value().toString()) != placeholders(it.key()))
                        problems << where + "has other placeholders than the English";
                } else {
                    const QJsonObject forms = it.value().toObject();
                    const QStringList wanted = placeholders(source.toObject().value("other").toString());
                    for (const QString &category : categories)
                        if (forms.value(category).toString().isEmpty())
                            problems << where + "needs its " + category + " form";
                    // A form other than "other" may say its number in words.
                    for (auto form = forms.begin(); form != forms.end(); ++form) {
                        const QStringList has = placeholders(form.value().toString());
                        QStringList needed = wanted;
                        if (form.key() != "other")
                            needed.removeIf([&](const QString &p) { return p.endsWith('n') && !has.contains(p); });
                        if (has != needed)
                            problems << where + form.key() + " has other placeholders than the English";
                    }
                }
            }
        }
        QVERIFY2(problems.isEmpty(), qPrintable(problems.join('\n')));
    }

    void windowLoadsAndAnswersTheKeyboard() {
        // A temp language and theme, so the test never depends on the desktop's.
        QTemporaryDir dir;
        Translator translator(dir.path() + "/language");
        QCoreApplication::installTranslator(&translator);
        Theme theme(dir.path());
        // A ready model at an address nothing answers, so nothing is made.
        readyEngine(dir.path() + "/state", "http://127.0.0.1:9");
        Backend backend({dir.path() + "/state", dir.path() + "/state/key", "/bin/true", dir.path() + "/out", "/bin/true"});

        QQmlApplicationEngine engine;
        QStringList warnings;
        connect(&engine, &QQmlEngine::warnings, this, [&](const QList<QQmlError> &errors) {
            for (const auto &error : errors)
                warnings << error.toString();
        });
        engine.rootContext()->setContextProperty("translator", &translator);
        engine.rootContext()->setContextProperty("theme", &theme);
        engine.rootContext()->setContextProperty("backend", &backend);
        engine.load(QUrl("qrc:/Main.qml"));
        QVERIFY(!engine.rootObjects().isEmpty());
        auto *window = qobject_cast<QQuickWindow *>(engine.rootObjects().first());
        QVERIFY(window);
        QVERIFY(QTest::qWaitForWindowExposed(window));
        window->requestActivate();
        QVERIFY(QTest::qWaitForWindowActive(window));

        auto *modelLine = item(window->contentItem(), "modelLine");
        auto *action = item(window->contentItem(), "action");
        QVERIFY(modelLine && action);
        QTRY_COMPARE(modelLine->property("text").toString(), QString("Z-Image Turbo is ready"));
        QCOMPARE(action->property("text").toString(), QString("Generate"));
        // Nothing to make until there's a prompt, which takes the keyboard.
        QVERIFY(!action->property("enabled").toBool());
        for (const char c : QByteArray("a calm lake"))
            QTest::keyClick(window, c);
        QCOMPARE(item(window->contentItem(), "prompt")->property("text").toString(), QString("a calm lake"));
        QVERIFY(action->property("enabled").toBool());

        // The caption reads on the accent: black on the fallback yellow.
        QCOMPARE(action->property("contentItem").value<QQuickItem *>()->property("color").value<QColor>(),
                 theme.accentForeground());

        // The size buttons pick one of three.
        // One button steps through the shapes; Ctrl+3 goes straight to portrait.
        auto *shape = item(window->contentItem(), "size");
        QVERIFY(shape);
        QTest::keyClick(window, Qt::Key_3, Qt::ControlModifier);
        QCOMPARE(shape->property("current").toMap().value("name").toString(), QString("Portrait"));
        QMetaObject::invokeMethod(shape, "clicked");
        QCOMPARE(shape->property("current").toMap().value("name").toString(), QString("Square"));

        auto *help = window->findChild<QObject *>("help");
        QTest::keyClick(window, Qt::Key_F1);
        QTRY_VERIFY(help->property("opened").toBool());
        // A Material popup animates out: `opened` drops at once, `visible` after.
        QTest::keyClick(window, Qt::Key_Escape);
        QTRY_VERIFY(!help->property("visible").toBool());

        QVERIFY2(warnings.isEmpty(), qPrintable(warnings.join('\n')));
        QCoreApplication::removeTranslator(&translator);
    }
};

QTEST_MAIN(FantasiTests)
#include "fantasi_tests.moc"
