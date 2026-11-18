#pragma once

#include <QAbstractListModel>
#include <QDateTime>
#include <QFileSystemWatcher>
#include <QFutureWatcher>
#include <QTimer>

// The images in the output folder, newest first, with the prompt, seed and
// size each one carries. Images an agent made with the command line are here
// too: it is the folder, not the app's own list.
class History : public QAbstractListModel {
    Q_OBJECT
    Q_PROPERTY(int count READ count NOTIFY countChanged)

public:
    struct Entry {
        QString path;
        QString prompt;
        qint64 seed = -1;
        QString size;
        QDateTime modified;
    };
    enum Role { UrlRole = Qt::UserRole + 1, PathRole, PromptRole, SeedRole, SizeRole };

    explicit History(const QString &folder, QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;
    int count() const { return int(m_entries.size()); }

    // The settings stable-diffusion.cpp writes into a PNG's `parameters`:
    // the prompt, then a line of `Key: value` pairs.
    static Entry readEntry(const QString &path);
    static QList<Entry> scan(const QString &folder);

    Q_INVOKABLE QString urlAt(int row) const { return data(index(row), UrlRole).toString(); }
    // Moves the image to the trash, from where it can come back.
    Q_INVOKABLE bool remove(int row);

signals:
    void countChanged();

private:
    void rescan();
    void watch();

    QString m_folder;
    QList<Entry> m_entries;
    QFileSystemWatcher m_watcher;
    QTimer m_debounce;
    QFutureWatcher<QList<Entry>> m_scan;
    bool m_again = false;
};
