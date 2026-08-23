import QtQuick
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: UptimeService.pluginId

    readonly property var methods: ["GET", "HEAD", "POST", "PUT", "DELETE"]

    Item {
        id: targetsEditor

        width: parent.width
        implicitHeight: editorColumn.implicitHeight
        height: implicitHeight

        property int idCounter: 0

        function loadValue() {
            const stored = root.loadValue("targets", []) || [];
            if (JSON.stringify(stored) === JSON.stringify(serialize()))
                return;

            targetsModel.clear();
            for (var i = 0; i < stored.length; i++) {
                const t = stored[i];
                targetsModel.append({
                    tid: String(t.id || nextId()),
                    label: String(t.label || ""),
                    url: String(t.url || ""),
                    method: String(t.method || "GET"),
                    period: String(t.period || "60"),
                    expect: String(t.expect || "200")
                });
            }
        }

        function nextId() {
            idCounter += 1;
            return "t" + Date.now() + "-" + idCounter;
        }

        function serialize() {
            const out = [];
            for (var i = 0; i < targetsModel.count; i++) {
                const t = targetsModel.get(i);
                out.push({
                    id: t.tid,
                    label: t.label,
                    url: t.url,
                    method: t.method,
                    period: t.period,
                    expect: t.expect
                });
            }
            return out;
        }

        function commit() {
            root.saveValue("targets", serialize());
        }

        function move(index, delta) {
            const to = index + delta;
            if (to < 0 || to >= targetsModel.count)
                return;
            targetsModel.move(index, to, 1);
            commit();
        }
        function update(index, key, value) {
            if (index < 0 || index >= targetsModel.count)
                return;
            if (targetsModel.get(index)[key] === value)
                return;
            targetsModel.setProperty(index, key, value);
            commit();
        }

        Component.onCompleted: loadValue()

        ListModel {
            id: targetsModel
        }

        Column {
            id: editorColumn
            width: parent.width
            spacing: Theme.spacingM

            StyledText {
                text: "Monitored endpoints"
                font.pixelSize: Theme.fontSizeLarge
                font.weight: Font.Medium
                color: Theme.surfaceText
            }

            StyledText {
                width: parent.width
                text: "Each endpoint is polled on its own interval. A notification fires when the response status differs from the expected one."
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
                wrapMode: Text.WordWrap
            }

            Repeater {
                model: targetsModel

                Rectangle {
                    id: card

                    required property int index
                    required property string tid
                    required property string label
                    required property string url
                    required property string method
                    required property string period
                    required property string expect

                    property string testResult: ""
                    property bool testOk: false
                    property bool testing: false
                    property bool alive: true

                    Component.onDestruction: alive = false

                    width: editorColumn.width
                    height: cardColumn.implicitHeight + Theme.spacingM * 2
                    radius: Theme.cornerRadius
                    color: Theme.surfaceContainerHigh

                    function commitPendingEdit() {
                        card.forceActiveFocus();
                    }

                    function runTest() {
                        const target = urlField.text.trim();
                        if (target.length === 0) {
                            card.testOk = false;
                            card.testResult = "Enter a URL first";
                            return;
                        }
                        card.testing = true;
                        card.testResult = "";
                        const wanted = parseInt(expectField.text) || 200;
                        const timeout = UptimeService.timeoutSec;
                        Proc.runCommand(`${UptimeService.pluginId}:test:${card.tid}`, UptimeService.curlCommand(target, methodDropdown.currentValue, timeout), (stdout, exitCode) => {
                            if (!card || !card.alive)
                                return;
                            card.testing = false;
                            const parts = String(stdout).trim().split(/\s+/);
                            const code = parts[0] || "000";
                            const ms = Math.round((parseFloat(parts[1]) || 0) * 1000);
                            if (exitCode === 0 && parseInt(code) === wanted) {
                                card.testOk = true;
                                card.testResult = "HTTP " + code + " · " + ms + " ms";
                            } else {
                                card.testOk = false;
                                card.testResult = UptimeService.describeFailure(code, exitCode) + ", expected " + wanted;
                            }
                        }, 0, (timeout + 5) * 1000);
                    }

                    Column {
                        id: cardColumn
                        anchors.fill: parent
                        anchors.margins: Theme.spacingM
                        spacing: Theme.spacingS

                        Row {
                            width: parent.width
                            spacing: Theme.spacingS

                            DankTextField {
                                id: labelField
                                width: (parent.width - Theme.spacingS * 2 - rowActions.width) * 0.32
                                placeholderText: "Label"
                                text: card.label
                                onEditingFinished: targetsEditor.update(card.index, "label", text)
                            }

                            DankTextField {
                                id: urlField
                                width: parent.width - labelField.width - rowActions.width - Theme.spacingS * 2
                                placeholderText: "https://example.com/health"
                                text: card.url
                                onEditingFinished: targetsEditor.update(card.index, "url", text.trim())
                            }

                            Row {
                                id: rowActions
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: Theme.spacingXS

                                DankActionButton {
                                    iconName: "arrow_upward"
                                    tooltipText: "Move up"
                                    enabled: card.index > 0
                                    opacity: enabled ? 1 : 0.35
                                    onClicked: {
                                        card.commitPendingEdit();
                                        targetsEditor.move(card.index, -1);
                                    }
                                }

                                DankActionButton {
                                    iconName: "arrow_downward"
                                    tooltipText: "Move down"
                                    enabled: card.index < targetsModel.count - 1
                                    opacity: enabled ? 1 : 0.35
                                    onClicked: {
                                        card.commitPendingEdit();
                                        targetsEditor.move(card.index, 1);
                                    }
                                }

                                DankActionButton {
                                    iconName: "delete"
                                    iconColor: Theme.error
                                    tooltipText: "Remove endpoint"
                                    onClicked: {
                                        card.commitPendingEdit();
                                        targetsModel.remove(card.index);
                                        targetsEditor.commit();
                                    }
                                }
                            }
                        }

                        Row {
                            width: parent.width
                            spacing: Theme.spacingS

                            DankDropdown {
                                id: methodDropdown
                                width: 110
                                dropdownWidth: 110
                                options: root.methods
                                currentValue: card.method
                                onValueChanged: value => targetsEditor.update(card.index, "method", value)
                            }

                            DankTextField {
                                id: periodField
                                width: 110
                                placeholderText: "Period (s)"
                                text: card.period
                                validator: IntValidator {
                                    bottom: 5
                                    top: 86400
                                }
                                onEditingFinished: targetsEditor.update(card.index, "period", text)
                            }

                            DankTextField {
                                id: expectField
                                width: 110
                                placeholderText: "Expect"
                                text: card.expect
                                validator: IntValidator {
                                    bottom: 100
                                    top: 599
                                }
                                onEditingFinished: targetsEditor.update(card.index, "expect", text)
                            }

                            DankButton {
                                anchors.verticalCenter: parent.verticalCenter
                                text: card.testing ? "Testing…" : "Test"
                                iconName: "play_arrow"
                                onClicked: card.runTest()
                            }
                        }

                        StyledText {
                            width: parent.width
                            visible: card.testResult.length > 0
                            text: (card.testOk ? "✓ " : "✗ ") + card.testResult
                            font.pixelSize: Theme.fontSizeSmall
                            color: card.testOk ? Theme.success : Theme.error
                            wrapMode: Text.WordWrap
                        }
                    }
                }
            }

            DankButton {
                text: "Add endpoint"
                iconName: "add"
                onClicked: {
                    targetsModel.append({
                        tid: targetsEditor.nextId(),
                        label: "",
                        url: "",
                        method: "GET",
                        period: "60",
                        expect: "200"
                    });
                }
            }
        }
    }

    ToggleSetting {
        settingKey: "failuresFirst"
        label: "Failing endpoints first"
        description: "Lift failing endpoints to the top of the popout, keeping the order above within each group"
        defaultValue: true
    }

    ToggleSetting {
        settingKey: "notifyOnRecovery"
        label: "Notify on recovery"
        description: "Also send a notification when a failing endpoint comes back up"
        defaultValue: true
    }

    SliderSetting {
        settingKey: "timeoutSec"
        label: "Request timeout"
        description: "Maximum time to wait for a response"
        defaultValue: 15
        minimum: 3
        maximum: 60
        unit: "s"
    }
}
