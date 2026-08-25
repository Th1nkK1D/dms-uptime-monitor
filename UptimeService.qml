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
            minPeriod: 5,
            retryCount: 2,
            retryDelaySec: 10
        })

    property var targets: []
    property bool notifyOnRecovery: defaults.notifyOnRecovery
    property int timeoutSec: defaults.timeoutSec
    property int period: defaults.period
    property int retryCount: defaults.retryCount
    property int retryDelaySec: defaults.retryDelaySec

    property var results: []

    readonly property string status: {
        if (results.length === 0)
            return "empty";
        if (failCount > 0)
            return "fail";
        if (warnCount > 0)
            return "warn";
        return "ok";
    }

    readonly property int failCount: results.filter(r => r.ok === false).length
    readonly property int warnCount: results.filter(r => r.ok !== false && r.warning).length

    property var _runtime: ({})

    property double nextDue: 0

    property int _runSeq: 0

    function _normalize(raw, index) {
        const expect = parseInt(raw.expect) || defaults.expect;
        const method = String(raw.method || defaults.method).toUpperCase();
        const url = String(raw.url || "").trim();
        return {
            key: String(raw.id || (method + ":" + url)),
            label: String(raw.label || url || "Target " + (index + 1)),
            url: url,
            method: method,
            expect: expect,
            headers: String(raw.headers || ""),
            body: String(raw.body || "")
        };
    }

    function loadSettings() {
        const raw = PluginService.loadPluginData(pluginId, "targets", []) || [];
        notifyOnRecovery = PluginService.loadPluginData(pluginId, "notifyOnRecovery", defaults.notifyOnRecovery);
        timeoutSec = Math.max(1, parseInt(PluginService.loadPluginData(pluginId, "timeoutSec", defaults.timeoutSec)) || defaults.timeoutSec);
        period = Math.max(defaults.minPeriod, parseInt(PluginService.loadPluginData(pluginId, "period", defaults.period)) || defaults.period);
        retryCount = Math.max(0, parseInt(PluginService.loadPluginData(pluginId, "retryCount", defaults.retryCount)) || 0);
        retryDelaySec = Math.max(1, parseInt(PluginService.loadPluginData(pluginId, "retryDelaySec", defaults.retryDelaySec)) || defaults.retryDelaySec);

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
            const sig = JSON.stringify([t.method, t.url, t.expect, t.headers, t.body]);
            const unchanged = live && live.sig === sig;
            const reconfigured = live && live.sig !== sig;
            next[t.key] = {
                ok: prev ? prev.ok : null,
                code: prev ? prev.code : "",
                timeMs: prev ? prev.timeMs : 0,
                exitCode: prev ? prev.exitCode : 0,
                lastChecked: prev ? prev.lastChecked : 0,
                attempt: prev && prev.attempt && !reconfigured ? prev.attempt : 0,
                warning: prev ? prev.warning === true && !reconfigured : false,
                retryDue: unchanged && live.retryDue ? live.retryDue : 0,
                checking: unchanged ? live.checking : false,
                needsCheck: unchanged ? live.needsCheck === true : true,
                runId: unchanged ? live.runId : 0,
                sig: sig
            };
        }
        _runtime = next;
        if (nextDue > now + period * 1000)
            nextDue = now + period * 1000;
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
                expect: t.expect,
                ok: s.ok !== undefined ? s.ok : null,
                code: s.code || "",
                timeMs: s.timeMs || 0,
                exitCode: s.exitCode || 0,
                lastChecked: s.lastChecked || 0,
                warning: s.warning === true,
                attempt: s.attempt || 0,
                retriesLeft: Math.max(0, retryCount - (s.attempt || 0) + 1),
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
                lastChecked: _runtime[key].lastChecked,
                attempt: _runtime[key].attempt,
                warning: _runtime[key].warning
            };
        }
        PluginService.savePluginState(pluginId, "status", out);
    }

    function parseHeaders(headers) {
        const out = [];
        const lines = String(headers || "").split("\n");
        for (var i = 0; i < lines.length; i++) {
            const line = lines[i].trim();
            // A leading "@" makes curl read headers from a file — never from user text.
            if (line.length > 0 && line[0] !== "@" && line.indexOf(":") > 0)
                out.push("-H", line);
        }
        return out;
    }

    function curlCommand(url, method, timeout, headers, body) {
        const base = ["curl", "-s", "-o", "/dev/null", "-w", "%{http_code} %{time_total}", "-L", "--connect-timeout", "5", "--max-time", String(timeout)];
        const verb = method === "HEAD" ? ["--head"] : ["-X", method];
        const data = method !== "HEAD" && String(body || "").length > 0 ? ["--data-raw", String(body)] : [];
        return base.concat(verb).concat(parseHeaders(headers)).concat(data).concat([url]);
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
        state.needsCheck = false;
        state.retryDue = 0;
        _publish();

        const runId = ++_runSeq;
        state.runId = runId;

        // No Proc id: reusing one only swaps the stored callback without killing the
        // running process, so a stale curl would deliver its output to the newest
        // closure. A null id gets its own entry, which Proc also destroys on completion.
        Proc.runCommand(null, curlCommand(t.url, t.method, timeoutSec, t.headers, t.body), (stdout, exitCode) => {
            _onResult(key, runId, stdout, exitCode);
        }, 0, (timeoutSec + 5) * 1000);
    }

    function checkAll() {
        nextDue = Date.now() + period * 1000;
        for (var i = 0; i < targets.length; i++) {
            const key = targets[i].key;
            const state = _runtime[key];
            if (state && state.checking)
                state.needsCheck = true;
            else
                check(key);
        }
    }

    function _onResult(key, runId, stdout, exitCode) {
        const t = _findTarget(key);
        const state = _runtime[key];
        if (!t || !state || state.runId !== runId)
            return;

        const parts = String(stdout).trim().split(/\s+/);
        const code = parts[0] || "000";
        const timeMs = Math.round((parseFloat(parts[1]) || 0) * 1000);
        const ok = exitCode === 0 && parseInt(code) === t.expect;
        const wasOk = state.ok;

        state.code = code;
        state.timeMs = timeMs;
        state.exitCode = exitCode;
        state.lastChecked = Date.now();
        state.checking = false;

        const retrying = !ok && state.ok !== false && state.attempt < retryCount;
        state.attempt = ok ? 0 : state.attempt + 1;
        state.warning = retrying;
        state.retryDue = retrying ? state.lastChecked + retryDelaySec * 1000 : 0;
        if (ok || !retrying)
            state.ok = ok;

        _publish();
        _persist();

        if (retrying)
            return;

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
            if (Date.now() >= root.nextDue) {
                root.checkAll();
                return;
            }
            const now = Date.now();
            for (var i = 0; i < root.targets.length; i++) {
                const key = root.targets[i].key;
                const state = root._runtime[key];
                if (!state || state.checking)
                    continue;
                if (state.needsCheck || (state.retryDue > 0 && now >= state.retryDue))
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
