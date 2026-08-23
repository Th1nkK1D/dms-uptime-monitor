pragma Singleton

import QtQuick
import Quickshell
import qs.Common
import qs.Services

Item {
    id: root

    readonly property string pluginId: "uptimeMonitor"

    readonly property var defaults: ({
            period: 60,
            expect: 200,
            method: "GET",
            timeoutSec: 15,
            notifyOnRecovery: true,
            minPeriod: 5
        })

    property var targets: []
    property bool notifyOnRecovery: defaults.notifyOnRecovery
    property int timeoutSec: defaults.timeoutSec

    property var results: []

    readonly property string status: {
        if (results.length === 0)
            return "empty";
        for (var i = 0; i < results.length; i++) {
            if (results[i].ok === false)
                return "fail";
        }
        return "ok";
    }

    readonly property int failCount: results.filter(r => r.ok === false).length

    property var _runtime: ({})

    function _normalize(raw, index) {
        const period = Math.max(defaults.minPeriod, parseInt(raw.period) || defaults.period);
        const expect = parseInt(raw.expect) || defaults.expect;
        const method = String(raw.method || defaults.method).toUpperCase();
        const url = String(raw.url || "").trim();
        return {
            key: String(raw.id || (method + ":" + url)),
            label: String(raw.label || url || "Target " + (index + 1)),
            url: url,
            method: method,
            period: period,
            expect: expect
        };
    }

    function loadSettings() {
        const raw = PluginService.loadPluginData(pluginId, "targets", []) || [];
        notifyOnRecovery = PluginService.loadPluginData(pluginId, "notifyOnRecovery", defaults.notifyOnRecovery);
        timeoutSec = Math.max(1, parseInt(PluginService.loadPluginData(pluginId, "timeoutSec", defaults.timeoutSec)) || defaults.timeoutSec);

        const normalized = [];
        for (var i = 0; i < raw.length; i++) {
            const t = _normalize(raw[i], i);
            if (t.url.length > 0)
                normalized.push(t);
        }
        targets = normalized;
        _syncRuntime();
    }

    function _syncRuntime() {
        const persisted = PluginService.loadPluginState(pluginId, "status", {}) || {};
        const next = {};
        const now = Date.now();

        for (var i = 0; i < targets.length; i++) {
            const t = targets[i];
            const live = _runtime[t.key] || null;
            const prev = live || persisted[t.key] || null;
            const sig = t.method + "|" + t.url + "|" + t.period + "|" + t.expect;
            const unchanged = live && live.sig === sig;
            next[t.key] = {
                ok: prev ? prev.ok : null,
                code: prev ? prev.code : "",
                timeMs: prev ? prev.timeMs : 0,
                exitCode: prev ? prev.exitCode : 0,
                lastChecked: prev ? prev.lastChecked : 0,
                checking: unchanged ? live.checking : false,
                nextDue: unchanged ? live.nextDue : now,
                sig: sig
            };
        }
        _runtime = next;
        _publish();
    }

    function _publish() {
        const list = [];
        for (var i = 0; i < targets.length; i++) {
            const t = targets[i];
            const s = _runtime[t.key] || {};
            list.push({
                key: t.key,
                label: t.label,
                url: t.url,
                method: t.method,
                period: t.period,
                expect: t.expect,
                ok: s.ok !== undefined ? s.ok : null,
                code: s.code || "",
                timeMs: s.timeMs || 0,
                exitCode: s.exitCode || 0,
                lastChecked: s.lastChecked || 0,
                checking: s.checking === true
            });
        }
        results = list;
    }

    function _persist() {
        const out = {};
        for (var key in _runtime) {
            out[key] = {
                ok: _runtime[key].ok,
                code: _runtime[key].code,
                timeMs: _runtime[key].timeMs,
                exitCode: _runtime[key].exitCode,
                lastChecked: _runtime[key].lastChecked
            };
        }
        PluginService.savePluginState(pluginId, "status", out);
    }

    function curlCommand(url, method, timeout) {
        const base = ["curl", "-s", "-o", "/dev/null", "-w", "%{http_code} %{time_total}", "-L", "--connect-timeout", "5", "--max-time", String(timeout)];
        const verb = method === "HEAD" ? ["--head"] : ["-X", method];
        return base.concat(verb).concat([url]);
    }

    function _findTarget(key) {
        for (var i = 0; i < targets.length; i++) {
            if (targets[i].key === key)
                return targets[i];
        }
        return null;
    }

    function check(key) {
        const t = _findTarget(key);
        const state = _runtime[key];
        if (!t || !state || state.checking)
            return;

        state.checking = true;
        state.nextDue = Date.now() + t.period * 1000;
        _publish();

        const sig = state.sig;
        Proc.runCommand(`${pluginId}:check:${key}`, curlCommand(t.url, t.method, timeoutSec), (stdout, exitCode) => {
            _onResult(key, sig, stdout, exitCode);
        }, 0, (timeoutSec + 5) * 1000);
    }

    function checkAll() {
        for (var i = 0; i < targets.length; i++)
            check(targets[i].key);
    }

    function _onResult(key, sig, stdout, exitCode) {
        const t = _findTarget(key);
        const state = _runtime[key];
        if (!t || !state || state.sig !== sig)
            return;

        const parts = String(stdout).trim().split(/\s+/);
        const code = parts[0] || "000";
        const timeMs = Math.round((parseFloat(parts[1]) || 0) * 1000);
        const ok = exitCode === 0 && parseInt(code) === t.expect;
        const wasOk = state.ok;

        state.ok = ok;
        state.code = code;
        state.timeMs = timeMs;
        state.exitCode = exitCode;
        state.lastChecked = Date.now();
        state.checking = false;
        _publish();
        _persist();

        if (!ok && wasOk !== false)
            _notify(t, code, exitCode, false);
        else if (ok && wasOk === false && notifyOnRecovery)
            _notify(t, code, exitCode, true);
    }

    function describeFailure(code, exitCode) {
        if (exitCode === 124)
            return "timed out";
        if (exitCode !== 0 || code === "000")
            return "unreachable (curl exit " + exitCode + ")";
        return "HTTP " + code;
    }

    function _notify(t, code, exitCode, recovered) {
        const title = recovered ? (t.label + " is back up") : (t.label + " is down");
        const body = recovered ? (t.url + " — HTTP " + code) : (t.url + " — " + describeFailure(code, exitCode) + ", expected " + t.expect);
        Quickshell.execDetached(["notify-send", "-a", "Uptime Monitor", "-u", recovered ? "normal" : "critical", title, body]);
    }

    Timer {
        interval: 1000
        repeat: true
        running: root.targets.length > 0
        onTriggered: {
            const now = Date.now();
            for (var i = 0; i < root.targets.length; i++) {
                const key = root.targets[i].key;
                const state = root._runtime[key];
                if (state && !state.checking && now >= state.nextDue)
                    root.check(key);
            }
        }
    }

    Connections {
        target: PluginService
        function onPluginDataChanged(changedPluginId) {
            if (changedPluginId === root.pluginId)
                root.loadSettings();
        }
    }

    Component.onCompleted: loadSettings()
}
