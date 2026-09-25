import QtQuick
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: UptimeService.pluginId

    readonly property var methods: ["GET", "HEAD", "POST", "PUT", "DELETE"]

    component NumberSetting: Item {
        id: numberSetting

        required property string settingKey
        required property string label
        property string description: ""
        property int defaultValue: 0
        property int minimum: 0
        property int maximum: 86400

        width: parent.width
        implicitHeight: settingRow.implicitHeight
        height: implicitHeight

        function findSettings() {
            let item = parent;
            while (item) {
                if (item.saveValue !== undefined && item.loadValue !== undefined)
                    return item;
                item = item.parent;
            }
            return null;
        }

        function loadValue() {
            // every child reloads whenever any other setting saves
            if (field.activeFocus)
                return;
            const settings = findSettings();
            if (settings)
                field.text = String(settings.loadValue(settingKey, defaultValue));
        }

        function commit() {
            const parsed = parseInt(field.text);
            const value = Math.min(maximum, Math.max(minimum, isNaN(parsed) ? defaultValue : parsed));
            field.text = String(value);
            const settings = findSettings();
            if (settings)
                settings.saveValue(settingKey, value);
        }

        Component.onCompleted: Qt.callLater(loadValue)

        Row {
            id: settingRow
            width: parent.width
            spacing: Theme.spacingM

            Column {
                width: parent.width - field.width - Theme.spacingM
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.spacingXS

                StyledText {
                    text: numberSetting.label
                    font.pixelSize: Theme.fontSizeLarge
                    font.weight: Font.Medium
                    color: Theme.surfaceText
                }

                StyledText {
                    width: parent.width
                    text: numberSetting.description
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    wrapMode: Text.WordWrap
                    visible: numberSetting.description !== ""
                }
            }

            DankTextField {
                id: field
                width: 110
                anchors.verticalCenter: parent.verticalCenter
                placeholderText: String(numberSetting.defaultValue)
                validator: IntValidator {
                    bottom: numberSetting.minimum
                    top: numberSetting.maximum
                }
                onEditingFinished: numberSetting.commit()
            }
        }
    }

    component MultilineField: Rectangle {
        id: field

        property alias text: input.text
        property string placeholderText: ""
        property int minimumLines: 3

        signal editingFinished

        implicitHeight: Math.max(input.contentHeight, minimumLines * input.font.pixelSize * 1.4) + Theme.spacingS * 2
        radius: Theme.cornerRadius
        color: Theme.surfaceContainerHigh
        border.width: input.activeFocus ? 2 : 1
        border.color: input.activeFocus ? Theme.primary : Theme.outlineMedium

        TextEdit {
            id: input

            anchors.fill: parent
            anchors.margins: Theme.spacingS
            color: Theme.surfaceText
            font.family: Theme.monoFontFamily
            font.pixelSize: Theme.fontSizeSmall
            selectByMouse: true
            selectionColor: Theme.primarySelected
            wrapMode: TextEdit.Wrap

            onActiveFocusChanged: {
                if (!activeFocus)
                    field.editingFinished();
            }
        }

        StyledText {
            anchors.left: input.left
            anchors.top: input.top
            width: input.width
            elide: Text.ElideRight
            text: field.placeholderText
            font.family: input.font.family
            font.pixelSize: input.font.pixelSize
            color: Theme.outlineButton
            visible: input.text.length === 0
        }
    }

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
                    method: String(t.method || UptimeService.defaults.method),
                    expect: String(t.expect || UptimeService.defaults.expect),
                    headers: String(t.headers || ""),
                    body: String(t.body || ""),
                    paused: t.paused === true
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
                    expect: t.expect,
                    headers: t.headers,
                    body: t.body,
                    paused: t.paused
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

        function remove(index) {
            targetsModel.remove(index);
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
                text: "An endpoint whose response status code differs from the expected one turns yellow and is retried; a notification fires once the retries are exhausted."
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
                    required property string expect
                    required property string headers
                    required property string body
                    required property bool paused

                    property bool advancedOpen: false
                    readonly property bool hasAdvanced: headers.length > 0 || body.length > 0
                    property string testResult: ""
                    property bool testOk: false
                    property bool testing: false
                    property bool alive: true
                    property bool expectFocused: false
                    readonly property bool expectInvalid: !expectFocused && !UptimeService.expectPattern.test(expectField.text)

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
                        const wanted = UptimeService.normalizeExpect(expectField.text);
                        const timeout = UptimeService.timeoutSec;
                        Proc.runCommand(`${UptimeService.pluginId}:test:${card.tid}`, UptimeService.curlCommand(target, methodDropdown.currentValue, timeout, headersField.text, bodyField.text), (stdout, exitCode) => {
                            if (!card || !card.alive)
                                return;
                            card.testing = false;
                            const result = UptimeService.parseResult(stdout, exitCode, wanted);
                            card.testOk = result.ok;
                            card.testResult = result.ok ? "HTTP " + result.code + " · " + result.timeMs + " ms" : UptimeService.describeFailure(result.code, exitCode) + ", expected " + wanted;
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
                                opacity: card.paused ? 0.5 : 1
                                text: card.label
                                onEditingFinished: targetsEditor.update(card.index, "label", text)
                            }

                            DankTextField {
                                id: urlField
                                width: parent.width - labelField.width - rowActions.width - Theme.spacingS * 2
                                placeholderText: "https://example.com/health"
                                opacity: card.paused ? 0.5 : 1
                                text: card.url
                                onEditingFinished: targetsEditor.update(card.index, "url", text.trim())
                            }

                            Row {
                                id: rowActions
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: Theme.spacingXS

                                DankActionButton {
                                    iconName: card.paused ? "play_arrow" : "pause"
                                    iconColor: card.paused ? Theme.primary : Theme.surfaceText
                                    tooltipText: card.paused ? "Resume checks" : "Pause checks"
                                    onClicked: {
                                        card.commitPendingEdit();
                                        targetsEditor.update(card.index, "paused", !card.paused);
                                    }
                                }

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
                                        targetsEditor.remove(card.index);
                                    }
                                }
                            }
                        }

                        Row {
                            id: optionsRow
                            width: parent.width
                            spacing: Theme.spacingS
                            opacity: card.paused ? 0.5 : 1

                            readonly property real fieldWidth: Math.max(64, (width - advancedButton.width - testButton.width - spacing * 3) / 2)

                            DankDropdown {
                                id: methodDropdown
                                width: optionsRow.fieldWidth
                                dropdownWidth: 110
                                options: root.methods
                                currentValue: card.method
                                onValueChanged: value => targetsEditor.update(card.index, "method", value)
                            }

                            DankTextField {
                                id: expectField
                                width: optionsRow.fieldWidth
                                placeholderText: "Expect"
                                text: card.expect
                                validator: RegularExpressionValidator {
                                    regularExpression: UptimeService.expectPattern
                                }
                                onFocusStateChanged: hasFocus => card.expectFocused = hasFocus
                                onEditingFinished: targetsEditor.update(card.index, "expect", UptimeService.normalizeExpect(text))
                            }

                            DankActionButton {
                                id: advancedButton
                                anchors.verticalCenter: parent.verticalCenter
                                iconName: card.advancedOpen ? "expand_less" : "tune"
                                tooltipText: card.hasAdvanced ? "Headers and body (set)" : "Headers and body"
                                iconColor: card.hasAdvanced ? Theme.primary : Theme.surfaceText
                                onClicked: card.advancedOpen = !card.advancedOpen
                            }

                            DankButton {
                                id: testButton
                                anchors.verticalCenter: parent.verticalCenter
                                text: card.testing ? "Testing…" : "Test"
                                iconName: "play_arrow"
                                onClicked: card.runTest()
                            }
                        }

                        StyledText {
                            width: parent.width
                            visible: card.expectInvalid
                            text: "Expect not saved — use status codes or classes like 200, 204 or 2xx (still using " + card.expect + ")"
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.error
                            wrapMode: Text.WordWrap
                        }

                        Column {
                            width: parent.width
                            spacing: Theme.spacingXS
                            visible: card.advancedOpen

                            StyledText {
                                text: "Request headers — one \"Name: value\" per line"
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                            }

                            MultilineField {
                                id: headersField
                                width: parent.width
                                placeholderText: "Authorization: Bearer …"
                                text: card.headers
                                onEditingFinished: targetsEditor.update(card.index, "headers", text)
                            }

                            StyledText {
                                text: "Request body"
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                                topPadding: Theme.spacingXS
                            }

                            MultilineField {
                                id: bodyField
                                width: parent.width
                                placeholderText: "{ \"ping\": true }"
                                text: card.body
                                onEditingFinished: targetsEditor.update(card.index, "body", text)
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
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Add endpoint"
                iconName: "add"
                onClicked: {
                    targetsModel.append({
                        tid: targetsEditor.nextId(),
                        label: "",
                        url: "",
                        method: UptimeService.defaults.method,
                        expect: UptimeService.defaults.expect,
                        headers: "",
                        body: "",
                        paused: false
                    });
                    targetsEditor.commit();
                }
            }
        }
    }

    NumberSetting {
        settingKey: "period"
        label: "Check interval"
        description: "Seconds between checks, shared by every endpoint (minimum " + UptimeService.defaults.minPeriod + ")"
        defaultValue: UptimeService.defaults.period
        minimum: UptimeService.defaults.minPeriod
        maximum: 86400
    }

    NumberSetting {
        settingKey: "timeoutSec"
        label: "Request timeout"
        description: "Seconds to wait for a response before giving up"
        defaultValue: UptimeService.defaults.timeoutSec
        minimum: UptimeService.defaults.minTimeoutSec
        maximum: 300
    }

    NumberSetting {
        settingKey: "retryCount"
        label: "Retries before down"
        description: "Extra attempts after a failed check before the endpoint is declared down and notified (0 disables retrying)"
        defaultValue: UptimeService.defaults.retryCount
        minimum: 0
        maximum: 10
    }

    NumberSetting {
        settingKey: "retryDelaySec"
        label: "Retry delay"
        description: "Seconds to wait between retries while an endpoint is in the warning state"
        defaultValue: UptimeService.defaults.retryDelaySec
        minimum: 1
        maximum: 3600
    }

    NumberSetting {
        settingKey: "settleSec"
        label: "Reconnect grace period"
        description: "Seconds to wait before checking again after the network comes back or the machine wakes from suspend (0 disables the delay)"
        defaultValue: UptimeService.defaults.settleSec
        minimum: 0
        maximum: 600
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
        defaultValue: UptimeService.defaults.notifyOnRecovery
    }
}
