import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    popoutWidth: 420

    readonly property bool failuresFirst: pluginData.failuresFirst ?? true

    readonly property var sortedResults: {
        const list = UptimeService.results;
        if (!failuresFirst)
            return list;
        return list.filter(r => r.ok === false).concat(list.filter(r => r.ok !== false));
    }

    function statusColor(status) {
        switch (status) {
        case "ok":
            return Theme.success;
        case "fail":
            return Theme.error;
        default:
            return "transparent";
        }
    }

    function dotColor(ok) {
        if (ok === null || ok === undefined)
            return Theme.outlineButton;
        return ok ? Theme.success : Theme.error;
    }

    function relativeTime(epochMs) {
        if (!epochMs)
            return "never";
        const secs = Math.max(0, Math.round((Date.now() - epochMs) / 1000));
        if (secs < 5)
            return "just now";
        if (secs < 60)
            return secs + "s ago";
        if (secs < 3600)
            return Math.floor(secs / 60) + "m ago";
        return Math.floor(secs / 3600) + "h ago";
    }

    // Singletons are lazy-loaded in QML; touching UptimeService here starts the poller
    Component.onCompleted: UptimeService.targets

    component StatusIcon: Item {
        implicitWidth: root.iconSize
        implicitHeight: root.iconSize

        DankIcon {
            anchors.centerIn: parent
            name: "cell_tower"
            size: root.iconSize
            color: UptimeService.status === "fail" ? Theme.error : Theme.surfaceText
        }

        Rectangle {
            width: 7
            height: 7
            radius: 4
            visible: UptimeService.status !== "empty"
            color: root.statusColor(UptimeService.status)
            border.width: 1
            border.color: Theme.surfaceContainer
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.rightMargin: -1
            anchors.topMargin: -1
        }
    }

    horizontalBarPill: Row {
        spacing: Theme.spacingXS

        StatusIcon {
            anchors.verticalCenter: parent.verticalCenter
        }

        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            visible: UptimeService.failCount > 0
            text: String(UptimeService.failCount)
            font.pixelSize: Theme.fontSizeSmall
            font.weight: Font.Normal
            color: Theme.error
        }
    }

    verticalBarPill: Column {
        spacing: Theme.spacingXS

        StatusIcon {
            anchors.horizontalCenter: parent.horizontalCenter
        }

        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: UptimeService.failCount > 0
            text: String(UptimeService.failCount)
            font.pixelSize: Theme.fontSizeSmall
            font.weight: Font.Normal
            color: Theme.error
        }
    }

    popoutContent: Component {
        Item {
            id: popoutRoot

            property var closePopout: null
            property var parentPopout: null

            implicitHeight: layout.implicitHeight

            Timer {
                interval: 1000
                repeat: true
                running: popoutRoot.visible
                onTriggered: tick.value = Date.now()
            }

            QtObject {
                id: tick
                property double value: 0
            }

            PopoutComponent {
                id: layout
                width: parent.width
                headerText: "Uptime Monitor"
                showCloseButton: true
                closePopout: popoutRoot.closePopout
                detailsText: UptimeService.results.length === 0 ? "No targets configured. Add some in Settings → Plugins → Uptime Monitor." : ""

                headerActions: Component {
                    DankActionButton {
                        iconName: "refresh"
                        tooltipText: "Check all now"
                        onClicked: UptimeService.checkAll()
                    }
                }

                Column {
                    width: parent.width
                    spacing: Theme.spacingXS

                    Repeater {
                        model: root.sortedResults

                        Rectangle {
                            required property var modelData

                            width: parent.width
                            height: rowContent.implicitHeight + Theme.spacingM * 2
                            radius: Theme.cornerRadius
                            color: Theme.surfaceContainerHigh

                            Row {
                                id: rowContent
                                anchors.fill: parent
                                anchors.margins: Theme.spacingM
                                spacing: Theme.spacingM

                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 10
                                    height: 10
                                    radius: 5
                                    color: root.dotColor(modelData.ok)
                                    opacity: modelData.checking ? 0.4 : 1
                                }

                                Column {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - 10 - checkButton.width - Theme.spacingM * 2
                                    spacing: 2

                                    StyledText {
                                        width: parent.width
                                        text: modelData.label
                                        font.pixelSize: Theme.fontSizeMedium
                                        font.weight: Font.Medium
                                        color: Theme.surfaceText
                                        elide: Text.ElideRight
                                    }

                                    StyledText {
                                        width: parent.width
                                        text: modelData.url
                                        font.pixelSize: Theme.fontSizeSmall
                                        color: Theme.surfaceVariantText
                                        elide: Text.ElideMiddle
                                    }

                                    StyledText {
                                        width: parent.width
                                        text: {
                                            tick.value;
                                            if (modelData.checking)
                                                return "checking…";
                                            if (modelData.ok === null)
                                                return "pending";
                                            const when = root.relativeTime(modelData.lastChecked);
                                            if (modelData.ok)
                                                return "HTTP " + modelData.code + " · " + modelData.timeMs + " ms · " + when;
                                            return UptimeService.describeFailure(modelData.code, modelData.exitCode) + " (expected " + modelData.expect + ") · " + when;
                                        }
                                        font.pixelSize: Theme.fontSizeSmall
                                        color: modelData.ok === false ? Theme.error : Theme.surfaceVariantText
                                        elide: Text.ElideRight
                                    }
                                }

                                DankActionButton {
                                    id: checkButton
                                    anchors.verticalCenter: parent.verticalCenter
                                    iconName: "refresh"
                                    tooltipText: "Check now"
                                    onClicked: UptimeService.check(modelData.key)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
