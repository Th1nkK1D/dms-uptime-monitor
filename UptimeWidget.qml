import QtQuick
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    popoutWidth: 420

    readonly property bool failuresFirst: pluginData.failuresFirst ?? true

    readonly property var sortedResults: {
        const list = UptimeService.displayResults;
        if (!failuresFirst)
            return list;
        const active = list.filter(r => !r.paused);
        return active.filter(r => r.ok === false).concat(active.filter(r => r.ok !== false && r.warning)).concat(active.filter(r => r.ok !== false && !r.warning)).concat(list.filter(r => r.paused));
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
        if (result.paused || UptimeService.offline)
            return Theme.outlineButton;
        if (result.ok === false)
            return Theme.error;
        if (result.warning)
            return Theme.warning;
        if (result.ok === null)
            return Theme.outlineButton;
        return Theme.success;
    }

    function elapsedSince(epochMs) {
        return UptimeService.formatDuration(Date.now() - epochMs);
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

    component FailCount: StyledText {
        visible: UptimeService.failCount > 0 && !UptimeService.offline
        text: String(UptimeService.failCount)
        font.pixelSize: Theme.fontSizeSmall
        font.weight: Font.Normal
        color: Theme.error
    }

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

        FailCount {
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    verticalBarPill: Column {
        spacing: Theme.spacingXS

        StatusIcon {
            anchors.horizontalCenter: parent.horizontalCenter
        }

        FailCount {
            anchors.horizontalCenter: parent.horizontalCenter
        }
    }

    popoutContent: Component {
        Item {
            id: popoutRoot

            property var closePopout: null
            property var parentPopout: null
            property string expandedKey: ""

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
                    if (UptimeService.displayResults.length === 0)
                        return "Nothing to monitor yet. Use the settings button above to add a URL and the status code it should answer with.";
                    if (UptimeService.results.length === 0)
                        return "Nothing is being checked";
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
                            tooltipText: "Check all now"
                            enabled: !UptimeService.linkDown
                            opacity: enabled ? 1 : 0.35
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
                            id: endpointRow

                            required property var modelData
                            readonly property bool expanded: popoutRoot.expandedKey === modelData.key

                            width: parent.width
                            height: rowContent.implicitHeight + Theme.spacingM * 2
                            radius: Theme.cornerRadius
                            color: rowHover.hovered ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh

                            HoverHandler {
                                id: rowHover
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: popoutRoot.expandedKey = endpointRow.expanded ? "" : endpointRow.modelData.key
                            }

                            Column {
                                id: rowContent
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: Theme.spacingM
                                spacing: Theme.spacingS

                                Row {
                                    width: parent.width
                                    spacing: Theme.spacingM
                                    opacity: modelData.paused ? 0.5 : 1

                                    Rectangle {
                                        anchors.top: parent.top
                                        anchors.topMargin: Math.round((labelText.height - height) / 2)
                                        width: 10
                                        height: 10
                                        radius: 5
                                        color: root.dotColor(modelData)
                                        opacity: modelData.checking ? 0.4 : 1
                                    }

                                    Item {
                                        anchors.top: parent.top
                                        width: parent.width - 10 - chevron.width - Theme.spacingM * 2
                                        height: labelText.height

                                        StyledText {
                                            id: statusText
                                            anchors.right: parent.right
                                            anchors.baseline: labelText.baseline
                                            width: Math.min(implicitWidth, parent.width - Theme.spacingS)
                                            text: {
                                                if (modelData.paused)
                                                    return "Paused";
                                                if (modelData.checking)
                                                    return "Checking…";
                                                if (modelData.warning)
                                                    return UptimeService.describeFailure(modelData.code, modelData.exitCode) + " · retrying (" + modelData.retriesLeft + " left)";
                                                if (modelData.ok === null)
                                                    return "Pending";
                                                if (modelData.ok)
                                                    return "HTTP " + modelData.code + " · " + modelData.timeMs + " ms";
                                                tick.value;
                                                const downFor = modelData.failingSince > 0 ? "Down " + root.elapsedSince(modelData.failingSince) + " · " : "";
                                                return downFor + UptimeService.describeFailure(modelData.code, modelData.exitCode) + " (expected " + modelData.expect + ")";
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

                                    DankIcon {
                                        id: chevron
                                        anchors.top: parent.top
                                        anchors.topMargin: Math.round((labelText.height - height) / 2)
                                        name: endpointRow.expanded ? "expand_less" : "expand_more"
                                        size: 18
                                        color: Theme.surfaceVariantText
                                    }
                                }

                                Item {
                                    width: parent.width
                                    height: endpointRow.expanded ? details.implicitHeight : 0
                                    visible: height > 0
                                    clip: true

                                    Behavior on height {
                                        NumberAnimation {
                                            duration: Theme.shortDuration
                                            easing.type: Theme.standardEasing
                                        }
                                    }

                                    Column {
                                        id: details
                                        width: parent.width
                                        leftPadding: 10 + Theme.spacingM
                                        spacing: Theme.spacingS

                                        StyledText {
                                            width: parent.width - parent.leftPadding
                                            text: modelData.url
                                            font.pixelSize: Theme.fontSizeSmall
                                            color: Theme.surfaceVariantText
                                            wrapMode: Text.WrapAnywhere
                                        }

                                        StyledText {
                                            text: modelData.method + " · expects " + modelData.expect
                                            font.pixelSize: Theme.fontSizeSmall
                                            color: Theme.surfaceVariantText
                                        }

                                        Row {
                                            spacing: Theme.spacingS

                                            DankButton {
                                                buttonHeight: 32
                                                text: modelData.paused ? "Resume" : "Pause"
                                                iconName: modelData.paused ? "play_arrow" : "pause"
                                                onClicked: UptimeService.setPaused(modelData.key, !modelData.paused)
                                            }

                                            DankButton {
                                                buttonHeight: 32
                                                text: "Open"
                                                iconName: "open_in_new"
                                                onClicked: {
                                                    Qt.openUrlExternally(modelData.url);
                                                    if (popoutRoot.closePopout)
                                                        popoutRoot.closePopout();
                                                }
                                            }

                                            DankButton {
                                                buttonHeight: 32
                                                visible: !modelData.paused
                                                text: "Check now"
                                                iconName: "refresh"
                                                enabled: !UptimeService.linkDown && !modelData.checking
                                                opacity: enabled ? 1 : 0.35
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
        }
    }
}
