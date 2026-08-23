import QtQuick
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: UptimeService.pluginId

    readonly property var methods: ["GET", "HEAD", "POST", "PUT", "DELETE"]

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
        id: intervalSetting

        width: parent.width
        implicitHeight: intervalRow.implicitHeight
        height: implicitHeight

        function loadValue() {
            if (intervalField.activeFocus)
                return;
            intervalField.text = String(root.loadValue("period", 60));
        }

        function commit() {
            const secs = Math.min(86400, Math.max(5, parseInt(intervalField.text) || 60));
            intervalField.text = String(secs);
            root.saveValue("period", secs);
        }

        Component.onCompleted: loadValue()

        Row {
            id: intervalRow
            width: parent.width
            spacing: Theme.spacingM

            Column {
                width: parent.width - intervalField.width - Theme.spacingM
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.spacingXS

                StyledText {
                    text: "Check interval"
                    font.pixelSize: Theme.fontSizeLarge
                    font.weight: Font.Medium
                    color: Theme.surfaceText
                }

                StyledText {
                    width: parent.width
                    text: "Seconds between checks, shared by every endpoint (minimum 5)"
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    wrapMode: Text.WordWrap
                }
            }

            DankTextField {
                id: intervalField
                width: 110
                anchors.verticalCenter: parent.verticalCenter
                placeholderText: "60"
                validator: IntValidator {
                    bottom: 5
                    top: 86400
                }
                onEditingFinished: intervalSetting.commit()
            }
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
                    method: String(t.method || "GET"),
                    expect: String(t.expect || "200"),
                    headers: String(t.headers || ""),
                    body: String(t.body || "")
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
                    body: t.body
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
                text: "A notification fires when an endpoint's response status differs from the expected one."
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

                    property bool advancedOpen: false
                    readonly property bool hasAdvanced: headers.length > 0 || body.length > 0
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
                        Proc.runCommand(`${UptimeService.pluginId}:test:${card.tid}`, UptimeService.curlCommand(target, methodDropdown.currentValue, timeout, headersField.text, bodyField.text), (stdout, exitCode) => {
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
                            id: optionsRow
                            width: parent.width
                            spacing: Theme.spacingS

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
                                validator: IntValidator {
                                    bottom: 100
                                    top: 599
                                }
                                onEditingFinished: targetsEditor.update(card.index, "expect", text)
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
                text: "Add endpoint"
                iconName: "add"
                onClicked: {
                    targetsModel.append({
                        tid: targetsEditor.nextId(),
                        label: "",
                        url: "",
                        method: "GET",
                        expect: "200",
                        headers: "",
                        body: ""
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
