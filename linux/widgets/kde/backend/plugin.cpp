#include "deadline_model.h"
#include <QQmlExtensionPlugin>
#include <qqml.h>

class DeadlinePlugin : public QQmlExtensionPlugin {
    Q_OBJECT
    Q_PLUGIN_METADATA(IID QQmlExtensionInterface_iid)
public:
    void registerTypes(const char* uri) override {
        qmlRegisterType<DeadlineModel>(uri, 1, 0, "DeadlineModel");
    }
};
#include "plugin.moc"
