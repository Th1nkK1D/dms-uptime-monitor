import QtQuick
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    popoutWidth: 420

    readonly property bool failuresFirst: pluginData.failuresFirst ?? true
    readonly property bool showUrl: pluginData.showUrl ?? false

    readonly property var sortedResults: {
        const list = UptimeService.results;
        if (!failuresFirst)
            return list;
        return list.filter(r => r.ok === false).concat(list.filter(r => r.ok !== false && r.warning)).concat(list.filter(r => r.ok !== false && !r.warning));
    }

    function statusColor(status) {
        switch (status) {
        case "ok":
            return Theme.success;
        case "warn":
            return Theme.warning;
        case "fail":
            return Theme.error;
        case "offline":
            return Theme.outlineButton;
        default:
            return "transparent";
        }
    }

    function dotColor(result) {
        if (UptimeService.offline)
            return Theme.outlineButton;
        if (result.ok === false)
            return Theme.error;
        if (result.warning)
            return Theme.warning;
        if (result.ok === null || result.ok === undefined)
            return Theme.outlineButton;
        return Theme.success;
    }

    function formatDuration(seconds) {
        const secs = Math.max(0, Math.round(seconds));
        if (secs < 60)
            return secs + "s";
        if (secs < 3600)
            return Math.floor(secs / 60) + "m";
        return Math.floor(secs / 3600) + "h";
    }

    function elapsedSince(epochMs) {
        return formatDuration((Date.now() - epochMs) / 1000);
    }

    function formatInterval(seconds) {
        const secs = Math.max(0, Math.round(seconds));
        const parts = [];
        const hours = Math.floor(secs / 3600);
        const minutes = Math.floor((secs % 3600) / 60);
        if (hours > 0)
            parts.push(hours + "h");
        if (minutes > 0)
            parts.push(minutes + "m");
        if (secs % 60 > 0 || parts.length === 0)
            parts.push(secs % 60 + "s");
        return parts.join(" ");
    }

    Component.onCompleted: UptimeService.targets

    component StatusIcon: Item {
        implicitWidth: root.iconSize
        implicitHeight: root.iconSize

        DankIcon {
            anchors.centerIn: parent
            name: "cell_tower"
            size: root.iconSize
            color: UptimeService.status === "fail" ? Theme.error : (UptimeService.status === "warn" ? Theme.warning : (UptimeService.status === "offline" ? Theme.surfaceVariantText : Theme.surfaceText))
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
            visible: UptimeService.failCount > 0 && !UptimeService.offline
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
            visible: UptimeService.failCount > 0 && !UptimeService.offline
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

            // Oldest, not newest: the header speaks for every endpoint at once.
            readonly property double lastCheckedAt: {
                var oldest = -1;
                for (var i = 0; i < UptimeService.results.length; i++) {
                    const at = UptimeService.results[i].lastChecked;
                    if (oldest < 0 || at < oldest)
                        oldest = at;
                }
                return Math.max(0, oldest);
            }

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
                detailsText: {
                    if (UptimeService.results.length === 0)
                        return "No targets configured. Add some in Settings → Plugins → Uptime Monitor.";
                    tick.value;
                    if (UptimeService.linkDown)
                        return "No network connection — checks are paused.";
                    if (UptimeService.uplinkSuspect)
                        return "Every endpoint is unreachable — likely a connection problem.";
                    const every = "every " + root.formatInterval(UptimeService.period || 60);
                    if (!popoutRoot.lastCheckedAt)
                        return every + " · no checks yet";
                    return every + " · checked " + root.elapsedSince(popoutRoot.lastCheckedAt) + " ago";
                }

                headerActions: Component {
                    Row {
                        spacing: Theme.spacingXS

                        DankActionButton {
                            iconName: "settings"
                            tooltipText: "Open plugin settings"
                            onClicked: {
                                if (popoutRoot.closePopout)
                                    popoutRoot.closePopout();
                                if (PopoutService.openSettingsWithTab)
                                    PopoutService.openSettingsWithTab("plugins");
                                else
                                    PopoutService.openSettings();
                            }
                        }

                        DankActionButton {
                            iconName: "refresh"
                            tooltipText: UptimeService.linkDown ? "Check all now (no network)" : "Check all now"
                            onClicked: UptimeService.checkAll()
                        }
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
                            height: infoColumn.implicitHeight + Theme.spacingM * 2
                            radius: Theme.cornerRadius
                            color: Theme.surfaceContainerHigh

                            Row {
                                anchors.fill: parent
                                anchors.margins: Theme.spacingM
                                spacing: Theme.spacingM

                                Rectangle {
                                    anchors.top: parent.top
                                    anchors.topMargin: Math.round((labelText.height - height) / 2)
                                    width: 10
                                    height: 10
                                    radius: 5
                                    color: root.dotColor(modelData)
                                    opacity: modelData.checking ? 0.4 : 1
                                }

                                Column {
                                    id: infoColumn
                                    anchors.top: parent.top
                                    width: parent.width - 10 - Theme.spacingM
                                    spacing: 2

                                    Item {
                                        width: parent.width
                                        height: labelText.height

                                        StyledText {
                                            id: statusText
                                            anchors.right: parent.right
                                            anchors.baseline: labelText.baseline
                                            width: Math.min(implicitWidth, parent.width - Theme.spacingS)
                                            text: {
                                                if (modelData.checking)
                                                    return "checking…";
                                                if (modelData.warning)
                                                    return UptimeService.describeFailure(modelData.code, modelData.exitCode) + " · retrying (" + modelData.retriesLeft + " left)";
                                                if (modelData.ok === null)
                                                    return "pending";
                                                if (modelData.ok)
                                                    return "HTTP " + modelData.code + " · " + modelData.timeMs + " ms";
                                                return UptimeService.describeFailure(modelData.code, modelData.exitCode) + " (expected " + modelData.expect + ")";
                                            }
                                            font.pixelSize: Theme.fontSizeSmall
                                            color: UptimeService.offline ? Theme.surfaceVariantText : (modelData.ok === false ? Theme.error : (modelData.warning ? Theme.warning : Theme.surfaceVariantText))
                                            wrapMode: Text.NoWrap
                                            elide: Text.ElideRight
                                        }

                                        StyledText {
                                            id: labelText
                                            anchors.left: parent.left
                                            anchors.top: parent.top
                                            width: parent.width - statusText.width - Theme.spacingS
                                            text: modelData.label
                                            font.pixelSize: Theme.fontSizeMedium
                                            font.weight: Font.Medium
                                            color: Theme.surfaceText
                                            wrapMode: Text.NoWrap
                                            elide: Text.ElideRight
                                        }
                                    }

                                    StyledText {
                                        width: parent.width
                                        visible: root.showUrl
                                        text: modelData.url
                                        font.pixelSize: Theme.fontSizeSmall
                                        color: Theme.surfaceVariantText
                                        wrapMode: Text.NoWrap
                                        elide: Text.ElideMiddle
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
