#include "deadline_model.h"

#include <QDateTime>
#include <QDesktopServices>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSet>
#include <QStandardPaths>
#include <QUrl>
#include <algorithm>
#include <cmath>

static bool timestamp(const QJsonValue& value) {
    return value.isDouble() && std::isfinite(value.toDouble()) && value.toDouble() >= 0 &&
        value.toDouble() <= 253402300799.0;
}
static bool text(const QJsonValue& value) {
    return value.isString() && value.toString().toUtf8().size() <= 4096;
}

DeadlineModel::DeadlineModel(QObject* parent) : QObject(parent) {
    m_path = QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation) +
        "/techpie/widgets/deadline-widget-v1.json";
    connect(&m_watcher, &QFileSystemWatcher::directoryChanged, this, &DeadlineModel::refresh);
    connect(&m_timer, &QTimer::timeout, this, &DeadlineModel::refresh);
    m_timer.start(30000);
    refresh();
}

void DeadlineModel::refresh() {
    m_now = QDateTime::currentMSecsSinceEpoch() / 1000.0;
    m_items.clear();
    m_writtenAt = 0;
    m_state = "unavailable";
    QString directory = QFileInfo(m_path).absolutePath();
    while (!QDir(directory).exists() && directory != "/")
        directory = QFileInfo(directory).absolutePath();
    if (m_watcher.directories() != QStringList{directory}) {
        if (!m_watcher.directories().isEmpty()) m_watcher.removePaths(m_watcher.directories());
        m_watcher.addPath(directory);
    }
    QFile file(m_path);
    if (!file.exists()) { m_state = "notSynced"; emit changed(); return; }
    if (!file.open(QIODevice::ReadOnly)) { emit changed(); return; }
    const QByteArray data = file.read(262145);
    if (data.size() > 262144) { emit changed(); return; }
    const auto document = QJsonDocument::fromJson(data);
    const auto object = document.object();
    const auto array = object.value("items").toArray();
    if (!document.isObject() || object.size() != 3 || object.value("schemaVersion").toDouble() != 1 ||
        !timestamp(object.value("writtenAt")) || !object.value("items").isArray() || array.size() > 512) {
        emit changed(); return;
    }
    QSet<QString> ids;
    for (const auto& value : array) {
        const auto item = value.toObject();
        const QString id = item.value("id").toString();
        const QString kind = item.value("kind").toString();
        if (!value.isObject() || item.size() != 5 || !text(item.value("id")) || id.isEmpty() ||
            ids.contains(id) || (kind != "assignment" && kind != "exam") ||
            !text(item.value("title")) || !text(item.value("course")) || !timestamp(item.value("dueAt"))) {
            m_items.clear(); emit changed(); return;
        }
        ids.insert(id);
        if (item.value("dueAt").toDouble() > m_now) m_items.append(item.toVariantMap());
    }
    std::sort(m_items.begin(), m_items.end(), [](const QVariant& a, const QVariant& b) {
        const auto x = a.toMap(), y = b.toMap();
        const double dx = x.value("dueAt").toDouble(), dy = y.value("dueAt").toDouble();
        return dx == dy ? x.value("id").toString() < y.value("id").toString() : dx < dy;
    });
    m_writtenAt = object.value("writtenAt").toDouble();
    m_state = "ready";
    emit changed();
}

bool DeadlineModel::openApp() {
    return QDesktopServices::openUrl(QUrl(QStringLiteral("techpie://deadlines")));
}
