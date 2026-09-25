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
            minTimeoutSec: 3,
            retryCount: 2,
            retryDelaySec: 10,
            settleSec: 10
        })

    property var targets: []
    property bool notifyOnRecovery: defaults.notifyOnRecovery
    property int timeoutSec: defaults.timeoutSec
    property int period: defaults.period
    property int retryCount: defaults.retryCount
    property int retryDelaySec: defaults.retryDelaySec
    property int settleSec: defaults.settleSec

    property var results: []

    readonly property bool linkDown: NetworkService.networkStatus === "disconnected"

    // Every endpoint failing to *reach* its host at once says more about our uplink than
    // about the endpoints, but one endpoint can't tell the two apart. Final verdicts only:
    // counting retrying endpoints would flicker this on a single blip.
    readonly property bool uplinkSuspect: {
        if (results.length < 2)
            return false;
        for (var i = 0; i < results.length; i++) {
            const r = results[i];
            if (r.ok !== false)
                return false;
            if (!isConnectivityFailure(r.code, r.exitCode))
                return false;
        }
        return true;
    }

    readonly property bool offline: linkDown || uplinkSuspect

    readonly property string status: {
        if (results.length === 0)
            return "empty";
        if (offline)
            return "offline";
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

    property double _pendingSince: 0

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
        timeoutSec = Math.max(defaults.minTimeoutSec, parseInt(PluginService.loadPluginData(pluginId, "timeoutSec", defaults.timeoutSec)) || defaults.timeoutSec);
        period = Math.max(defaults.minPeriod, parseInt(PluginService.loadPluginData(pluginId, "period", defaults.period)) || defaults.period);
        retryCount = Math.max(0, parseInt(PluginService.loadPluginData(pluginId, "retryCount", defaults.retryCount)) || 0);
        retryDelaySec = Math.max(1, parseInt(PluginService.loadPluginData(pluginId, "retryDelaySec", defaults.retryDelaySec)) || defaults.retryDelaySec);
        const settle = parseInt(PluginService.loadPluginData(pluginId, "settleSec", defaults.settleSec));
        settleSec = isNaN(settle) ? defaults.settleSec : Math.max(0, settle);

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
            const sig = JSON.stringify([t.method, t.url, t.expect, t.headers, t.body]);
            const stored = live || persisted[t.key] || null;
            const prev = stored && (stored.sig === undefined || stored.sig === sig) ? stored : null;
            const unchanged = live && live.sig === sig;
            next[t.key] = {
                ok: prev ? prev.ok : null,
                code: prev ? prev.code : "",
                timeMs: prev ? prev.timeMs : 0,
                exitCode: prev ? prev.exitCode : 0,
                lastChecked: prev ? prev.lastChecked : 0,
                attempt: prev && prev.attempt ? prev.attempt : 0,
                warning: prev ? prev.warning === true : false,
                notifiedOk: prev && prev.notifiedOk !== undefined ? prev.notifiedOk : (prev ? prev.ok : null),
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
                warning: _runtime[key].warning,
                notifiedOk: _runtime[key].notifiedOk,
                sig: _runtime[key].sig
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
        const base = ["curl", "-s", "-o", "/dev/null", "-w", "%{http_code} %{time_total}", "--connect-timeout", "5", "--max-time", String(timeout)];
        const verb = method === "HEAD" ? ["--head"] : ["-X", method];
        const data = method !== "HEAD" && String(body || "").length > 0 ? ["--data-raw", String(body)] : [];
        // --url so a URL starting with "-" can't be parsed as a curl option.
        return base.concat(verb).concat(parseHeaders(headers)).concat(data).concat(["--url", url]);
    }

    function parseResult(stdout, exitCode, expect) {
        const parts = String(stdout).trim().split(/\s+/);
        const code = parts[0] || "000";
        return {
            code: code,
            timeMs: Math.round((parseFloat(parts[1]) || 0) * 1000),
            ok: exitCode === 0 && parseInt(code) === expect
        };
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
        if (linkDown)
            return;
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

    // A check that was in flight across a link drop or a suspend measured the outage,
    // not the endpoint. Bumping runId makes _onResult discard the late callback.
    function _clearPending() {
        for (var key in _runtime) {
            const state = _runtime[key];
            if (state.checking)
                state.runId = ++_runSeq;
            state.checking = false;
            state.attempt = 0;
            state.retryDue = 0;
            state.warning = false;
            state.needsCheck = false;
        }
        _pendingSince = 0;
        _publish();
    }

    function _onResult(key, runId, stdout, exitCode) {
        const t = _findTarget(key);
        const state = _runtime[key];
        if (!t || !state || state.runId !== runId)
            return;

        state.checking = false;

        const result = parseResult(stdout, exitCode, t.expect);
        const ok = result.ok;

        state.code = result.code;
        state.timeMs = result.timeMs;
        state.exitCode = exitCode;
        state.lastChecked = Date.now();

        const retrying = !ok && state.ok !== false && state.attempt < retryCount;
        state.attempt = ok ? 0 : state.attempt + 1;
        state.warning = retrying;
        state.retryDue = retrying ? state.lastChecked + retryDelaySec * 1000 : 0;
        if (ok || !retrying)
            state.ok = ok;

        _publish();
        _persist();
        _flushNotifications();
    }

    function _settled() {
        for (var i = 0; i < targets.length; i++) {
            const s = _runtime[targets[i].key];
            if (!s)
                continue;
            if (s.checking || s.needsCheck || s.retryDue > 0 || s.lastChecked === 0)
                return false;
        }
        return true;
    }

    // uplinkSuspect for a cycle that hasn't settled yet: every endpoint that has a verdict
    // failed to reach its host, and the ones still checking may well do the same.
    function _uplinkPlausible() {
        if (targets.length < 2)
            return false;
        var unsettled = 0;
        var fails = 0;
        for (var i = 0; i < targets.length; i++) {
            const s = _runtime[targets[i].key];
            if (!s)
                continue;
            if (s.checking || s.needsCheck || s.retryDue > 0 || s.lastChecked === 0) {
                unsettled++;
                continue;
            }
            if (s.ok !== false || !isConnectivityFailure(s.code, s.exitCode))
                return false;
            fails++;
        }
        return unsettled > 0 && fails > 0;
    }

    function _hasPending() {
        for (var i = 0; i < targets.length; i++) {
            const s = _runtime[targets[i].key];
            if (s && s.ok !== null && s.ok !== s.notifiedOk)
                return true;
        }
        return false;
    }

    // Held until the cycle settles, so a whole-uplink outage is recognised before it can
    // fire one notification per endpoint. Capped, because an endpoint slower than the
    // poll interval must not sit on everyone else's alerts — but the cap is waived while
    // the cycle still looks like an outage, or it would release the very alerts the wait
    // exists to suppress. Every check ends within its timeout, so that wait is bounded.
    function _flushNotifications() {
        if (linkDown || targets.length === 0)
            return;

        if (!_hasPending()) {
            _pendingSince = 0;
            return;
        }

        const now = Date.now();
        if (_pendingSince === 0)
            _pendingSince = now;
        if (!_settled() && (now - _pendingSince < (timeoutSec + 5) * 1000 || _uplinkPlausible()))
            return;
        _pendingSince = 0;

        if (uplinkSuspect)
            return;

        var changed = false;
        for (var i = 0; i < targets.length; i++) {
            const t = targets[i];
            const state = _runtime[t.key];
            if (!state || state.ok === null || state.ok === state.notifiedOk)
                continue;
            if (state.ok === false)
                _notify(t, state.code, state.exitCode, false);
            else if (state.notifiedOk === false && notifyOnRecovery)
                _notify(t, state.code, state.exitCode, true);
            state.notifiedOk = state.ok;
            changed = true;
        }
        if (changed)
            _persist();
    }

    function isConnectivityFailure(code, exitCode) {
        // 124 is Proc's timeout killing curl, not a curl exit code.
        return exitCode === 6 || exitCode === 7 || exitCode === 28 || exitCode === 124 || code === "000";
    }

    function describeFailure(code, exitCode) {
        switch (exitCode) {
        case 6:
            return "DNS lookup failed";
        case 7:
            return "could not connect";
        case 28:
        case 124:
            return "timed out";
        case 35:
            return "TLS handshake failed";
        case 60:
            return "certificate not trusted";
        }
        if (exitCode !== 0 || code === "000")
            return "unreachable (curl exit " + exitCode + ")";
        return "HTTP " + code;
    }

    function _notify(t, code, exitCode, recovered) {
        const title = recovered ? (t.label + " is back up") : (t.label + " is down");
        const body = recovered ? (t.url + " — HTTP " + code) : (t.url + " — " + describeFailure(code, exitCode) + ", expected " + t.expect);
        Quickshell.execDetached(["notify-send", "-a", "Uptime Monitor", "-u", recovered ? "normal" : "critical", title, body]);
    }

    onLinkDownChanged: {
        _clearPending();
        if (!linkDown)
            nextDue = Date.now() + settleSec * 1000;
    }

    Timer {
        interval: 1000
        repeat: true
        running: root.targets.length > 0 && !root.linkDown

        property double lastTick: 0

        onTriggered: {
            const now = Date.now();
            const gap = lastTick > 0 ? now - lastTick : 0;
            lastTick = now;

            // A 1s timer that jumped means the machine was suspended: the link is up on
            // paper but wifi is still reassociating, so give it the same grace as a reconnect.
            if (gap > 15000) {
                root._clearPending();
                root.nextDue = now + root.settleSec * 1000;
                return;
            }

            if (now >= root.nextDue) {
                root.checkAll();
                return;
            }
            for (var i = 0; i < root.targets.length; i++) {
                const key = root.targets[i].key;
                const state = root._runtime[key];
                if (!state || state.checking)
                    continue;
                if (state.needsCheck || (state.retryDue > 0 && now >= state.retryDue))
                    root.check(key);
            }
            root._flushNotifications();
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
