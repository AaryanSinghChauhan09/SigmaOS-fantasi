#pragma once

#include <QObject>
#include <QProcess>
#include <QSize>

#include "filepicker.h"
#include "generator.h"
#include "history.h"
#include "models.h"

// The app's state for the window: the model it uses, the image being made,
// the images made before, and what the desktop does with one.
class Backend : public QObject {
    Q_OBJECT
    Q_PROPERTY(Models *models READ models CONSTANT)
    Q_PROPERTY(Generator *generator READ generator CONSTANT)
    Q_PROPERTY(History *history READ history CONSTANT)
    // The Screen size: the focused monitor's shape at about a megapixel.
    Q_PROPERTY(QSize screenSize READ screenSize NOTIFY screenSizeChanged)
    // The prompt `fantasi open` was given.
    Q_PROPERTY(QString initialPrompt MEMBER m_initialPrompt CONSTANT)
    // Why the last thing done with an image (Save as) didn't happen.
    Q_PROPERTY(QString error READ error NOTIFY errorChanged)

public:
    // Where things live; an empty one is the user's own.
    struct Places {
        QString engineState;
        QString engineKey;
        QString engineCommand;
        QString folder;
        QString hyprctl;
    };

    // The picker asks where Save as writes; without one, the desktop portal's.
    explicit Backend(const Places &places = {}, FilePicker *picker = nullptr, QObject *parent = nullptr);

    Models *models() { return &m_models; }
    Generator *generator() { return &m_generator; }
    History *history() { return &m_history; }
    QSize screenSize() const { return m_screenSize; }

    // A size near a megapixel in the shape of `width` by `height`, in the
    // steps of 64 the models work in.
    static QSize fitMegapixel(int width, int height);

    void setInitialPrompt(const QString &prompt) { m_initialPrompt = prompt; }

    QString error() const { return m_error; }

    Q_INVOKABLE void setBackground(const QString &url);
    Q_INVOKABLE void copy(const QString &url);
    // Asks where, then writes a copy of the image there.
    Q_INVOKABLE void saveAs(const QString &url);

signals:
    void screenSizeChanged();
    void errorChanged();

private:
    Models m_models;
    Generator m_generator;
    History m_history;
    QSize m_screenSize{1344, 768};
    QString m_initialPrompt;
    QString m_error;
    QString m_saving;
    FilePicker *m_picker;
    QProcess m_monitors;
};
