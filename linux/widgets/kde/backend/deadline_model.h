#pragma once

#include <QObject>
#include <QFileSystemWatcher>
#include <QTimer>
#include <QVariantList>

class DeadlineModel : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString state READ state NOTIFY changed)
    Q_PROPERTY(QVariantList items READ items NOTIFY changed)
    Q_PROPERTY(double writtenAt READ writtenAt NOTIFY changed)
    Q_PROPERTY(double now READ now NOTIFY changed)
public:
    explicit DeadlineModel(QObject* parent = nullptr);
    QString state() const { return m_state; }
    QVariantList items() const { return m_items; }
    double writtenAt() const { return m_writtenAt; }
    double now() const { return m_now; }
    Q_INVOKABLE void refresh();
    Q_INVOKABLE bool openApp();
signals:
    void changed();
private:
    QFileSystemWatcher m_watcher;
    QTimer m_timer;
    QString m_path;
    QString m_state = "notSynced";
    QVariantList m_items;
    double m_writtenAt = 0;
    double m_now = 0;
};
