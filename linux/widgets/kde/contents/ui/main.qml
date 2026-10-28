import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami
import "backend" as Backend

PlasmoidItem {
    id: root
    Backend.DeadlineModel { id: deadlines }
    preferredRepresentation: Plasmoid.formFactor === PlasmaCore.Types.Horizontal ||
        Plasmoid.formFactor === PlasmaCore.Types.Vertical ? compactRepresentation : fullRepresentation
    switchWidth: Kirigami.Units.gridUnit * 12
    switchHeight: Kirigami.Units.gridUnit * 8

    compactRepresentation: PlasmaComponents.ToolButton {
        icon.name: "view-calendar-tasks"
        text: deadlines.items.length ? root.remaining(deadlines.items[0].dueAt) : "TechPie"
        display: Controls.AbstractButton.TextBesideIcon
        onClicked: root.expanded = !root.expanded
    }

    function remaining(dueAt) {
        const hours = Math.floor((dueAt - deadlines.now) / 3600)
        return hours < 1 ? "<1h" : hours < 24 ? hours + "h" :
            Math.floor(hours / 24) + "d " + hours % 24 + "h"
    }

    fullRepresentation: ColumnLayout {
        Layout.minimumWidth: Kirigami.Units.gridUnit * 12
        Layout.minimumHeight: Kirigami.Units.gridUnit * 8
        Layout.preferredWidth: Kirigami.Units.gridUnit * 20
        Layout.preferredHeight: Kirigami.Units.gridUnit * 16
        spacing: Kirigami.Units.smallSpacing
        RowLayout {
            Layout.fillWidth: true
            PlasmaComponents.Label { text: "TechPie Deadlines"; font.bold: true; Layout.fillWidth: true }
            PlasmaComponents.ToolButton {
                icon.name: "document-open"
                Accessible.name: "Open TechPie Deadlines"
                onClicked: deadlines.openApp()
            }
        }
        PlasmaComponents.Label {
            visible: deadlines.state !== "ready" || deadlines.items.length === 0
            Layout.fillWidth: true
            Layout.fillHeight: true
            wrapMode: Text.Wrap
            text: deadlines.state === "unavailable" ? "Deadline data is unavailable" :
                deadlines.state === "notSynced" ? "Enable Deadline widgets in TechPie Settings" :
                "No upcoming deadlines"
        }
        ListView {
            id: list
            visible: deadlines.state === "ready" && deadlines.items.length > 0
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: Kirigami.Units.smallSpacing
            model: deadlines.items.slice(0, height < Kirigami.Units.gridUnit * 8 ? 2 :
                height < Kirigami.Units.gridUnit * 14 ? 4 : 8)
            delegate: PlasmaComponents.ItemDelegate {
                required property var modelData
                width: list.width
                Accessible.name: modelData.title + ", " + modelData.course + ", " +
                    new Date(modelData.dueAt * 1000).toLocaleString()
                onClicked: deadlines.openApp()
                contentItem: ColumnLayout {
                    RowLayout {
                        Layout.fillWidth: true
                        Kirigami.Icon {
                            source: modelData.kind === "exam" ? "view-calendar-tasks" : "document-edit"
                            Layout.preferredWidth: Kirigami.Units.iconSizes.small
                            Layout.preferredHeight: Kirigami.Units.iconSizes.small
                        }
                        PlasmaComponents.Label {
                            text: modelData.title; font.bold: true
                            elide: Text.ElideRight; Layout.fillWidth: true
                        }
                        PlasmaComponents.Label {
                            text: root.remaining(modelData.dueAt)
                            color: modelData.dueAt - deadlines.now < 3600 ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
                        }
                    }
                    PlasmaComponents.Label {
                        text: modelData.course + " · " + new Date(modelData.dueAt * 1000).toLocaleString()
                        elide: Text.ElideRight; Layout.fillWidth: true; opacity: 0.7
                    }
                }
            }
        }
        PlasmaComponents.Label {
            visible: deadlines.state === "ready"
            text: "Cached snapshot · " + new Date(deadlines.writtenAt * 1000).toLocaleString()
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            elide: Text.ElideRight; Layout.fillWidth: true; opacity: 0.7
        }
    }
}
