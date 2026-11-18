#include "cli.h"

#include "backend.h"

#include <QCommandLineParser>
#include <QCoreApplication>
#include <QJsonDocument>
#include <QJsonObject>
#include <QTimer>
#include <cstdio>

namespace {

void print(FILE *stream, const QString &text) {
    std::fputs(qPrintable(text + '\n'), stream);
    std::fflush(stream);
}

const char *usage = "Usage:\n"
                    "  fantasi                      Open the window\n"
                    "  fantasi open [prompt]        Open the window with a prompt\n"
                    "  fantasi generate <prompt>    Make an image, print where it's saved\n"
                    "      --width <px> --height <px> --steps <n> --seed <n> --json\n";

} // namespace

bool isCliCommand(const char *argument) {
    const QByteArray command(argument);
    return command == "generate" || command == "--help" || command == "-h" || command == "--version"
        || command == "-v";
}

int runCli(const QStringList &arguments) {
    const QString command = arguments.value(1);
    if (command == "--version" || command == "-v") {
        print(stdout, "fantasi " + QCoreApplication::applicationVersion());
        return 0;
    }
    if (command != "generate") {
        print(stdout, usage);
        return 0;
    }

    QCommandLineParser parser;
    parser.addPositionalArgument("prompt", "What to make");
    parser.addOption({"width", "Width in pixels", "px", "1024"});
    parser.addOption({"height", "Height in pixels", "px", "1024"});
    parser.addOption({"steps", "Sampling steps; the model's own when left out", "n", "0"});
    parser.addOption({"seed", "Seed; a random one when left out", "n", "-1"});
    parser.addOption({"json", "Print the result as JSON"});
    // The parser takes its first argument as the program's name: here,
    // `generate`, which leaves the prompt as the positional arguments.
    if (!parser.parse(arguments.mid(1))) {
        print(stderr, "Error: " + parser.errorText());
        return 1;
    }
    const QString prompt = parser.positionalArguments().join(' ').trimmed();
    const bool json = parser.isSet("json");
    if (prompt.isEmpty()) {
        print(stderr, "Error: say what to make: fantasi generate \"a calm lake at dusk\"");
        return 1;
    }

    Backend backend;
    Models *models = backend.models();
    Generator *generator = backend.generator();
    if (models->state() != "ready") {
        const QString how = models->state() == "installed" || models->state() == "blocked"
                              ? " Start it with: omarchy agent local start " + models->modelId()
                          : models->state() == "installable" ? " Set one up with: omarchy agent local use " + models->modelId()
                                                             : QString();
        print(stderr, "Error: no image model is running." + how);
        return 1;
    }

    int code = 1;
    QString path;
    QObject::connect(generator, &Generator::saved, [&path](const QString &saved) { path = saved; });
    QObject::connect(generator, &Generator::finished, [&](const QString &error) {
        if (!error.isEmpty() || path.isEmpty()) {
            print(stderr, "Error: " + (error.isEmpty() ? QString("the image was cancelled") : error));
        } else {
            code = 0;
            print(stdout, json ? QString::fromUtf8(QJsonDocument(QJsonObject{{"path", path}}).toJson(QJsonDocument::Compact))
                               : path);
        }
        QCoreApplication::quit();
    });
    // Starts on the model's own defaults once they're known, or without them
    // after a moment.
    bool started = false;
    auto start = [&] {
        if (started)
            return;
        started = true;
        generator->generate(prompt, parser.value("width").toInt(), parser.value("height").toInt(),
                            parser.value("steps").toInt(), parser.value("seed").toLongLong());
        if (!generator->busy()) {
            print(stderr, "Error: " + generator->error());
            QCoreApplication::exit(1);
        }
    };
    QObject::connect(generator, &Generator::defaultsChanged, start);
    QTimer::singleShot(3000, start);
    QCoreApplication::exec();
    return code;
}
