"use strict";
const { test } = require("node:test");
const assert = require("node:assert/strict");
const http = require("node:http");
const { once } = require("node:events");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const { createServer } = require("../dev-server.cjs");

const planningPaths = ["/api/v1/dispatch/plans", "/api/v1/trips/7/optimize", "/api/v1/dispatch/plans/test-plan/confirm"];
const apiSource = fs.readFileSync(path.join(__dirname, "../js/api.js"), "utf8");

async function listen(server) {
  server.listen(0, "127.0.0.1");
  await once(server, "listening");
  return "http://127.0.0.1:" + server.address().port;
}

async function fixture(t, handler, options) {
  const sockets = new Set(), requests = [];
  const backend = http.createServer((req, res) => { requests.push(req.url); handler(req, res); });
  backend.on("connection", socket => {
    sockets.add(socket);
    socket.once("close", () => sockets.delete(socket));
  });
  const backendUrl = await listen(backend);
  const proxy = createServer(new URL(backendUrl), options);
  t.after(async () => {
    await Promise.all([proxy, backend].map(server => new Promise(resolve => {
      server.close(resolve);
      server.closeAllConnections();
    })));
  });
  return { base: await listen(proxy), backend, proxy, sockets, requests };
}

function later(response, ms, callback) {
  const timer = setTimeout(callback, ms);
  response.once("close", () => clearTimeout(timer));
}

function browser(base) {
  const window = { APP_CONFIG: { API_BASE_URL: base } };
  vm.runInNewContext(apiSource, {
    window, fetch, Headers, AbortController, DOMException, setTimeout, clearTimeout,
    sessionStorage: { getItem: () => null }
  });
  return window.ApiClient;
}

test("default proxy allows all planning POSTs past 18s with the real 60s frontend deadline", { timeout: 30000 }, async t => {
  const f = await fixture(t, (req, res) => {
    let body = "";
    req.setEncoding("utf8");
    req.on("data", chunk => { body += chunk; });
    req.on("end", () => {
      assert.equal(req.method, "POST");
      assert.equal(body, '{"orders":[1,2]}');
      later(res, 21000, () => {
        res.writeHead(200, { "content-type": "application/json" });
        res.end('{"ok":true}');
      });
    });
  });
  const api = browser(f.base), start = Date.now();
  await Promise.all(planningPaths.map(async (url, index) => {
    const data = await api.request(url + (index === 0 ? "/?manual=true" : ""), {
      method: "POST", body: '{"orders":[1,2]}', timeoutMs: 60000
    });
    assert.equal(data.ok, true);
  }));
  assert(Date.now() - start >= 21000);
  assert(Date.now() - start < 60000);
  assert.equal(f.requests.length, 3);
  // Existing static serving and the frontend client remain compatible.
  assert.equal((await fetch(f.base + "/")).status, 200);
});

test("default planning proxy includes a buffer beyond the frontend's 60s", { timeout: 75000, concurrency: true }, async t => {
  const f = await fixture(t, (_req, res) => {
    later(res, 61000, () => res.end('{"ok":true}'));
  });
  const start = Date.now();
  const response = await fetch(f.base + planningPaths[0], { method: "POST", body: "{}", signal: AbortSignal.timeout(72000) });
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { ok: true });
  assert(Date.now() - start >= 61000);
  assert.equal(f.requests.length, 1);
});

test("planning deadline returns 504, flags uncertain writes, closes backend and never replays", async t => {
  const f = await fixture(t, () => {}, { planningTimeoutMs: 100 });
  const api = browser(f.base);
  for (const url of planningPaths) {
    await assert.rejects(api.request(url, { method: "POST", body: "{}", timeoutMs: 60000 }), error => {
      assert.equal(error.status, 504);
      assert.equal(error.timeout, true);
      assert.equal(error.resultUnknown, true);
      assert.equal(error.data.code, "UPSTREAM_TIMEOUT");
      assert.match(error.message, /Backend xử lý yêu cầu quá thời gian/);
      assert.match(error.message, /tải lại dữ liệu để kiểm tra/);
      assert.doesNotMatch(error.message, /khởi chạy API/);
      return true;
    });
  }
  assert.equal(f.requests.length, 3);
  await new Promise(resolve => setTimeout(resolve, 50));
  assert.equal(f.sockets.size, 0);
});

test("connection refusal is 502 unavailable, distinct from processing timeout", async t => {
  const f = await fixture(t, () => {});
  await new Promise(resolve => f.backend.close(resolve));
  const response = await fetch(f.base + planningPaths[0], { method: "POST", body: "{}" });
  assert.equal(response.status, 502);
  const data = await response.json();
  assert.equal(data.code, "UPSTREAM_UNAVAILABLE");
  assert.equal(data.resultUnknown, false);
  assert.match(data.message, /Không thể kết nối backend/);
  assert.match(data.message, /khởi chạy API/);
  assert.equal(f.requests.length, 0);
});

test("connected backend resetting a write reports interruption and does not replay", async t => {
  const f = await fixture(t, req => { req.socket.destroy(); });
  await assert.rejects(browser(f.base).request(planningPaths[0], { method: "POST", body: "{}" }), error => {
    assert.equal(error.status, 502);
    assert.equal(error.data.code, "UPSTREAM_CONNECTION_LOST");
    assert.equal(error.resultUnknown, true);
    assert.match(error.message, /bị gián đoạn/);
    assert.doesNotMatch(error.message, /khởi chạy API/);
    return true;
  });
  assert.equal(f.requests.length, 1);
});

test("frontend cancellation after uploading a POST closes the pending backend response", async t => {
  let arrived;
  const ready = new Promise(resolve => { arrived = resolve; });
  const f = await fixture(t, (req, res) => {
    req.resume();
    req.on("end", () => arrived(res));
  });
  const controller = new AbortController();
  const pending = browser(f.base).request(planningPaths[0], { method: "POST", body: "{}", signal: controller.signal });
  const rejected = assert.rejects(pending, error => error.name === "AbortError" && error.resultUnknown);
  const res = await ready;
  const closed = once(res, "close", { signal: AbortSignal.timeout(2000) });
  controller.abort();
  await Promise.all([closed, rejected]);
  assert.equal(f.requests.length, 1);
});

test("deadline stays active for stalled bodies even after headers were forwarded", async t => {
  const f = await fixture(t, (_req, res) => {
    res.writeHead(200, { "content-type": "application/json" });
    res.write('{"ok":');
  }, { planningTimeoutMs: 150 });
  const response = await fetch(f.base + planningPaths[0], { method: "POST", body: "{}" });
  assert.equal(response.status, 200);
  await assert.rejects(response.text());
  await new Promise(resolve => setTimeout(resolve, 50));
  assert.equal(f.sockets.size, 0);
  assert.equal(f.requests.length, 1);
});

test("cancellation during POST upload also releases the backend connection", async t => {
  let arrived;
  const ready = new Promise(resolve => { arrived = resolve; });
  const f = await fixture(t, (req, res) => {
    req.resume();
    arrived(res);
  });
  const client = http.request(f.base + planningPaths[0], { method: "POST" });
  client.on("error", () => {});
  t.after(() => client.destroy());
  client.write('{"orders":[');
  const res = await ready;
  const closed = once(res, "close", { signal: AbortSignal.timeout(2000) });
  client.destroy();
  await closed;
  assert.equal(f.requests.length, 1);
});

test("partial backend body errors close downstream without a second response or retry", async t => {
  const f = await fixture(t, (_req, res) => {
    res.writeHead(200, { "content-type": "application/json" });
    res.write('{"ok":');
    later(res, 50, () => res.destroy());
  });
  await assert.rejects(browser(f.base).request(planningPaths[0], { method: "POST", body: "{}" }), error => error.networkError && error.resultUnknown);
  assert.equal(f.requests.length, 1);
});

test("normal APIs keep their existing deadline; route matching includes query and trailing slash", async t => {
  const f = await fixture(t, (_req, res) => {
    later(res, 200, () => res.end('{"ok":true}'));
  }, { timeoutMs: 80, planningTimeoutMs: 1000 });
  for (const url of planningPaths) {
    const response = await fetch(f.base + url + "/?test=1", { method: "POST", body: "{}" });
    assert.equal(response.status, 200);
    await response.text();
  }
  for (const [url, method] of [["/api/v1/trips", "POST"], [planningPaths[0], "GET"], ["/api/v1/dispatch/plans/other/action", "POST"]]) {
    const response = await fetch(f.base + url, { method });
    assert.equal(response.status, 504);
    const data = await response.json();
    assert.equal(data.resultUnknown, method === "POST");
  }
});

test("successful requests cancel their deadline and release upstream connections", async t => {
  const f = await fixture(t, (_req, res) => res.end('{"ok":true}'), { planningTimeoutMs: 100 });
  assert.equal((await browser(f.base).request(planningPaths[0], { method: "POST", body: "{}" })).ok, true);
  await new Promise(resolve => setTimeout(resolve, 150));
  assert.equal(f.sockets.size, 0);
  assert.equal(f.requests.length, 1);
});

function observeResponses(proxy) {
  const records = [];
  proxy.on("request", (request, response) => {
    const record = { request, response, writes: [], finishes: 0 };
    for (const method of ["writeHead", "write", "end"]) {
      const original = response[method];
      response[method] = function (...args) {
        record.writes.push({ method, closed: this.destroyed || this.socket?.destroyed || this.writableEnded });
        return original.apply(this, args);
      };
    }
    response.once("finish", () => { record.finishes++; });
    records.push(record);
  });
  return records;
}

test("client disconnect after a complete upload cancels upstream, clears deadline and absorbs late errors", { timeout: 5000 }, async t => {
  const originalSetTimeout = global.setTimeout, originalClearTimeout = global.clearTimeout;
  const timers = [], cleared = new Set();
  t.mock.method(global, "setTimeout", (callback, delay, ...args) => {
    const timer = originalSetTimeout(callback, delay, ...args);
    if (delay === 347) timers.push(timer);
    return timer;
  });
  t.mock.method(global, "clearTimeout", timer => { cleared.add(timer); return originalClearTimeout(timer); });
  let arrived, recordedWrite = false;
  const ready = new Promise(resolve => { arrived = resolve; });
  const f = await fixture(t, (req, res) => {
    req.resume();
    req.once("end", () => {
      // A simulated write can finish before the HTTP reply. Disconnecting must
      // close transport, not claim or attempt to roll back this application state.
      recordedWrite = true;
      arrived({ req, res });
    });
  }, { planningTimeoutMs: 347 });
  const records = observeResponses(f.proxy);
  const client = http.request(f.base + planningPaths[0], { method: "POST" });
  client.on("error", () => {});
  t.after(() => client.destroy());
  client.end('{"orders":[1]}');
  const { req, res } = await ready;
  assert.equal(req.complete, true);
  assert.equal(records[0].request.complete, true);
  const closed = once(res, "close", { signal: AbortSignal.timeout(2000) });
  client.destroy();
  await closed;
  assert.equal(res.destroyed, true);
  assert.equal(timers.length, 1);
  assert(cleared.has(timers[0]), "proxy deadline must be cleared, not just ignored later");
  assert.equal(records[0].writes.length, 0, "client cancellation must not produce a 502 or any response write");
  assert.doesNotThrow(() => records[0].request.emit("error", Error("Late request reset")));
  assert.doesNotThrow(() => records[0].response.emit("error", Error("Late response reset")));
  assert.equal(recordedWrite, true);
  assert.equal(f.requests.length, 1);
});

test("client disconnect midway through a response closes the backend stream without another header or body", { timeout: 5000 }, async t => {
  let backendResponse;
  const totalBytes = 512 * 1024;
  const f = await fixture(t, (_req, res) => {
    backendResponse = res;
    res.writeHead(200, { "content-type": "application/octet-stream", "content-length": totalBytes });
    res.write(Buffer.alloc(64 * 1024, 97));
    // Intentionally leave the remaining response pending until client cancellation.
  });
  const records = observeResponses(f.proxy);
  const client = http.request(f.base + planningPaths[0], { method: "POST" });
  client.on("error", () => {});
  t.after(() => client.destroy());
  const headers = once(client, "response", { signal: AbortSignal.timeout(2000) });
  client.end("{}");
  const [result] = await headers;
  result.on("error", () => {});
  const [chunk] = await once(result, "data", { signal: AbortSignal.timeout(2000) });
  assert(chunk.length > 0 && chunk.length < totalBytes);
  const writesBeforeCancel = records[0].writes.length;
  const closed = once(backendResponse, "close", { signal: AbortSignal.timeout(2000) });
  result.destroy(); client.destroy();
  await closed;
  assert.equal(backendResponse.destroyed, true);
  assert.equal(backendResponse.writableFinished, false);
  assert.equal(records[0].response.writableFinished, false);
  assert.equal(records[0].writes.length, writesBeforeCancel);
  assert(records[0].writes.every(write => !write.closed));
  assert.doesNotThrow(() => records[0].response.emit("error", Error("Late stream reset")));
  assert.equal(f.requests.length, 1);
});

test("a successful streamed response delivers every byte and finishes normally under backpressure", { timeout: 5000 }, async t => {
  const payload = Buffer.alloc(4 * 1024 * 1024, 123);
  let backendResponse;
  const f = await fixture(t, (_req, res) => {
    backendResponse = res;
    res.writeHead(200, { "content-type": "application/octet-stream", "content-length": payload.length });
    res.end(payload);
  }, { planningTimeoutMs: 2000 });
  const records = observeResponses(f.proxy);
  const client = http.request(f.base + planningPaths[0], { method: "POST" });
  client.on("error", () => {});
  t.after(() => client.destroy());
  const headers = once(client, "response", { signal: AbortSignal.timeout(2000) });
  client.end("{}");
  const [result] = await headers;
  const chunks = [];
  result.on("data", chunk => { chunks.push(chunk); });
  const ended = once(result, "end", { signal: AbortSignal.timeout(3000) });
  result.pause();
  setTimeout(() => result.resume(), 30);
  await ended;
  assert.deepEqual(Buffer.concat(chunks), payload);
  assert.equal(result.complete, true);
  assert.equal(result.aborted, false);
  assert.equal(backendResponse.writableFinished, true);
  assert.equal(records[0].response.writableFinished, true);
  assert.equal(records[0].finishes, 1);
  assert(records[0].writes.every(write => !write.closed));
  assert.doesNotThrow(() => records[0].response.emit("error", Error("Late error after normal finish")));
});

test("backend HTTP failures and connection resets remain valid proxy responses", async t => {
  const f = await fixture(t, (req, res) => {
    if (req.url === "/api/reset") { req.socket.destroy(); return; }
    if (req.url === "/api/error") {
      res.writeHead(503, { "content-type": "application/json" });
      res.end('{"message":"Backend temporarily busy"}'); return;
    }
    res.end('{"ok":true}');
  });
  const records = observeResponses(f.proxy);
  const error = await fetch(f.base + "/api/error");
  assert.equal(error.status, 503);
  assert.deepEqual(await error.json(), { message: "Backend temporarily busy" });
  const reset = await fetch(f.base + "/api/reset", { method: "POST", body: "{}" });
  assert.equal(reset.status, 502);
  const data = await reset.json();
  assert.equal(data.code, "UPSTREAM_CONNECTION_LOST");
  assert.equal(data.resultUnknown, true);
  const success = await fetch(f.base + "/api/ok");
  assert.equal(success.status, 200);
  assert.deepEqual(await success.json(), { ok: true });
  assert(records.every(record => record.writes.every(write => !write.closed)));
});
