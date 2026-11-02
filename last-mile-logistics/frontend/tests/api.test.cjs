"use strict";
const { test } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const apiSource = fs.readFileSync(path.join(__dirname, "../js/api.js"), "utf8");
const dispatchSource = fs.readFileSync(path.join(__dirname, "../js/dispatch.js"), "utf8");

function deferred() {
  let resolve;
  const promise = new Promise(r => { resolve = r; });
  return { promise, resolve };
}

function browser(fetchImpl) {
  const timers = new Map(), storage = new Map();
  let now = 0, nextTimer = 0;
  const window = { APP_CONFIG: { API_BASE_URL: "" }, dispatchEvent() {} };
  const context = vm.createContext({
    window, Headers, AbortController, DOMException, CustomEvent, atob, URLSearchParams,
    fetch: fetchImpl,
    sessionStorage: {
      getItem: key => storage.get(key) ?? null,
      setItem: (key, value) => storage.set(key, value),
      removeItem: key => storage.delete(key)
    },
    setTimeout(callback, delay) {
      const id = ++nextTimer;
      timers.set(id, { callback, at: now + delay });
      return id;
    },
    clearTimeout: id => timers.delete(id)
  });
  vm.runInContext(apiSource, context);
  vm.runInContext(fs.readFileSync(path.join(__dirname,"../js/write-outcome.js"),"utf8"),context);
  return {
    api: window.ApiClient, window, context, timers,
    advance(ms) {
      now += ms;
      for (const [id, timer] of timers) {
        if (timer.at <= now) { timers.delete(id); timer.callback(); }
      }
    }
  };
}

function watchedSignal() {
  const controller = new AbortController(), listeners = new Set();
  const signal = controller.signal;
  const add = signal.addEventListener.bind(signal), remove = signal.removeEventListener.bind(signal);
  signal.addEventListener = (type, listener, options) => {
    if (type === "abort") listeners.add(listener);
    add(type, listener, options);
  };
  signal.removeEventListener = (type, listener) => {
    if (type === "abort") listeners.delete(listener);
    remove(type, listener);
  };
  return { controller, signal, listeners };
}

// A real Response body stream that stays open after fetch has returned headers.
function slowResponse(signal, status = 200) {
  let body;
  const response = new Response(new ReadableStream({
    start(controller) {
      body = controller;
      controller.enqueue(new TextEncoder().encode('{"ok":'));
      signal.addEventListener("abort", () => controller.error(new DOMException("Aborted", "AbortError")), { once: true });
    }
  }), { status, headers: { "content-type": "application/json" } });
  return { response, finish() { body.enqueue(new TextEncoder().encode("true}")); body.close(); } };
}

for (const [label, status, responseType] of [["JSON", 200], ["HTTP error", 409], ["blob", 200, "blob"], ["blob HTTP error", 403, "blob"]]) {
  test(`${label}: fast headers do not end timeout or cancellation before the body`, async () => {
    const caller = watchedSignal(), headers = deferred();
    let stream, calls = 0;
    const b = browser(async (_url, options) => {
      calls++;
      stream = slowResponse(options.signal, status);
      headers.resolve();
      return stream.response;
    });
    const pending = b.api.request("/api/v1/test", { signal: caller.signal, responseType });
    const rejected = assert.rejects(pending, error => error.name === "TimeoutError" && error.timeout && !error.networkError);
    await headers.promise;
    assert.equal(b.timers.size, 1);
    assert.equal(caller.listeners.size, 1);
    b.advance(19999);
    assert.equal(b.timers.size, 1);
    b.advance(1);
    await rejected;
    assert.equal(calls, 1);
    assert.equal(b.timers.size, 0);
    assert.equal(caller.listeners.size, 0);
  });

  test(`${label}: caller can abort while reading the body, including a custom reason`, async () => {
    const caller = watchedSignal(), headers = deferred();
    const b = browser(async (_url, options) => {
      const stream = slowResponse(options.signal, status);
      headers.resolve();
      return stream.response;
    });
    const pending = b.api.request("/api/v1/test", { signal: caller.signal, responseType });
    const rejected = assert.rejects(pending, error => error.name === "AbortError" && !error.timeout && !error.networkError);
    await headers.promise;
    caller.controller.abort(new Error("Leaving the page"));
    await rejected;
    assert.equal(b.timers.size, 0);
    assert.equal(caller.listeners.size, 0);
  });
}

test("slow body can complete before its deadline and all resources are cleaned", async () => {
  const caller = watchedSignal(), headers = deferred();
  let stream;
  const b = browser(async (_url, options) => {
    stream = slowResponse(options.signal); headers.resolve(); return stream.response;
  });
  const pending = b.api.request("/api/v1/test", { signal: caller.signal });
  await headers.promise;
  b.advance(19000);
  stream.finish();
  assert.equal((await pending).ok, true);
  assert.equal(b.timers.size, 0);
  assert.equal(caller.listeners.size, 0);
  b.advance(1000);
});

test("cleanup also happens for HTTP, malformed JSON, network and body read failures", async () => {
  for (const kind of ["http", "invalid", "network", "body"]) {
    const caller = watchedSignal();
    const b = browser(async () => {
      if (kind === "network") throw new TypeError("Offline");
      if (kind === "body") return { text: async () => { throw new TypeError("Broken stream"); } };
      return new Response(kind === "invalid" ? "not JSON" : '{"message":"Conflict"}', { status: kind === "http" ? 409 : 200 });
    });
    await assert.rejects(b.api.request("/api/v1/test", { signal: caller.signal }), error =>
      kind === "http" ? error.status === 409 : kind === "invalid" ? error.invalidResponse : error.networkError && !error.timeout);
    assert.equal(b.timers.size, 0, kind);
    assert.equal(caller.listeners.size, 0, kind);
  }
});

test("pre-aborted requests do not fetch or report an uncertain write", async () => {
  const caller = watchedSignal(); caller.controller.abort();
  let calls = 0;
  const b = browser(async () => { calls++; });
  await assert.rejects(b.api.request("/api/v1/test", { method: "POST", signal: caller.signal }), error =>
    error.name === "AbortError" && error.resultUnknown === false);
  assert.equal(calls, 0);
  assert.equal(b.timers.size, 0);
  assert.equal(caller.listeners.size, 0);
});

test("uncertain writes are sent once and instruct reloading for timeout and network failures", async () => {
  for (const kind of ["timeout", "network", "body"]) {
    const headers = deferred();
    let calls = 0;
    const b = browser(async (_url, options) => {
      calls++; headers.resolve();
      if (kind === "network") throw new TypeError("Offline");
      if (kind === "body") return { text: async () => { throw new TypeError("Broken stream"); } };
      return slowResponse(options.signal).response;
    });
    const pending = b.api.request("/api/v1/test", { method: "POST", body: "{}" });
    const rejected = assert.rejects(pending, error => error.resultUnknown && /tải lại dữ liệu để kiểm tra/.test(error.message)
      && (kind === "timeout" ? error.timeout && !error.networkError : error.networkError && !error.timeout));
    await headers.promise;
    if (kind === "timeout") b.advance(20000);
    await rejected;
    assert.equal(calls, 1);
    assert.equal(b.timers.size, 0);
  }
});

test("401 body completes before refresh; refreshed retry retains the request timeout", async () => {
  const headers = deferred(), retried = deferred(), caller = watchedSignal();
  const tokens = letter => ({
    accessToken: `header.${Buffer.from(JSON.stringify({ exp: 2000000000, jti: letter })).toString("base64url")}.signature`,
    refreshToken: letter.repeat(43), expiresAt: "2033-05-18T03:33:20Z",
    user: { accountId: 1, username: "test", role: "ADMIN" }
  });
  const old = tokens("a"), fresh = tokens("b");
  let firstBody, retryBody, refreshCount = 0, calls = 0;
  const b = browser(async (url, options) => {
    if (url.endsWith("/refresh")) {
      refreshCount++;
      assert.equal(caller.listeners.size, 0);
      return new Response(JSON.stringify(fresh));
    }
    calls++;
    if (calls === 1) {
      firstBody = slowResponse(options.signal, 401); headers.resolve(); return firstBody.response;
    }
    assert.equal(options.headers.get("Authorization"), "Bearer " + fresh.accessToken);
    retryBody = slowResponse(options.signal); retried.resolve(); return retryBody.response;
  });
  b.api.storeTokens(old);
  const pending = b.api.request("/api/v1/dispatch/plans/test-plan", { timeoutMs: 60000, signal: caller.signal });
  await headers.promise;
  b.advance(21000);
  assert.equal(refreshCount, 0);
  firstBody.finish();
  await retried.promise;
  b.advance(21000);
  assert.equal(b.timers.size, 1);
  retryBody.finish();
  assert.equal((await pending).ok, true);
  assert.equal(refreshCount, 1);
  assert.equal(calls, 2);
  assert.equal(b.api.getRefreshToken(), fresh.refreshToken);
  assert.equal(b.timers.size, 0);
  assert.equal(caller.listeners.size, 0);
});

test("invalid timeout overrides fail without fetching or leaking resources", async () => {
  let calls = 0;
  const b = browser(async () => { calls++; });
  for (const timeoutMs of [0, -1, NaN, Infinity, "60000"]) {
    await assert.rejects(b.api.request("/api/v1/test", { timeoutMs }), /Thời gian chờ/);
  }
  assert.equal(calls, 0);
  assert.equal(b.timers.size, 0);
});

test("ordinary dispatch writes retain 20s timeout even before headers arrive", async () => {
  const caller = watchedSignal();
  let calls = 0;
  const b = browser((_url, options) => {
    calls++;
    return new Promise((_resolve, reject) => {
      options.signal.addEventListener("abort", () => reject(new DOMException("Aborted", "AbortError")), { once: true });
    });
  });
  b.window.AdminUI = {};
  b.window.Router = {};
  b.window.LogisticsUI = {};
  vm.runInContext(dispatchSource.replace("Object.freeze({mount,destroy})", "Object.freeze({mount,destroy,write})"), b.context);
  const pending = b.window.DispatchPage.write({}, "/api/v1/trips", {}, caller.signal);
  const rejected = assert.rejects(pending, error => error.timeout && error.resultUnknown);
  b.advance(19999);
  assert.equal(b.timers.size, 1);
  b.advance(1);
  await rejected;
  assert.equal(calls, 1);
  assert.equal(b.timers.size, 0);
  assert.equal(caller.listeners.size, 0);
});

test("invalid JSON after a successful write requires checking data before resubmitting", async () => {
  let calls = 0;
  const b = browser(async () => { calls++; return new Response("truncated JSON"); });
  await assert.rejects(b.api.request("/api/v1/trips", { method: "POST", body: "{}" }), error =>
    error.invalidResponse && error.resultUnknown && /tải lại dữ liệu để kiểm tra/.test(error.message));
  assert.equal(calls, 1);
  assert.equal(b.timers.size, 0);
});

test("HTTP 504 has a processing-timeout fallback distinct from a connection failure", async () => {
  for (const status of [502, 504]) {
    let calls = 0;
    const b = browser(async () => { calls++; return new Response(null, { status }); });
    await assert.rejects(b.api.request("/api/v1/dispatch/plans", { method: "POST", body: "{}" }), error => {
      assert.equal(error.status, status);
      assert.equal(error.timeout, status === 504);
      assert.match(error.message, status === 504 ? /quá thời gian chờ/ : /kết nối hoặc đọc phản hồi/);
      return true;
    });
    assert.equal(calls, 1);
    assert.equal(b.timers.size, 0);
  }
});

for (const [method, url] of [["PUT", "/api/v1/orders/17"], ["POST", "/api/v1/orders/17/confirm"],
  ["POST", "/api/v1/warehouse-transactions/move"], ["POST", "/api/v1/orders"], ["POST", "/api/v1/warehouse-transactions/inbound"]]) {
  test(`SQL result unavailable: ${method} ${url} is sent once and retains the unknown-result flag`, async () => {
    let calls = 0;
    const message = "Không đọc được kết quả xử lý. Hãy tải lại để kiểm tra trạng thái.";
    const b = browser(async () => { calls++; return Response.json({ message, code: "SQL_RESULT_UNAVAILABLE", resultUnknown: true }, { status: 500 }); });
    await assert.rejects(b.api.request(url, { method, body: "{}" }), error =>
      error.status === 500 && error.resultUnknown === true && error.data.code === "SQL_RESULT_UNAVAILABLE" && error.message.includes(message));
    assert.equal(calls, 1);
    assert.equal(b.timers.size, 0);
  });
}

for (const operation of ["create", "optimize", "manual", "confirm"]) {
  test(`dispatch ${operation} actually waits 60s and sends the write once`, async () => {
    const headers = deferred(), errors = [], buttons = [], notices = [];
    let calls = 0, actualUrl;
    const b = browser(async (url, options) => {
      calls++; actualUrl = url; headers.resolve(); return slowResponse(options.signal).response;
    });
    b.window.AdminUI = {
      el() {}, notice() {}, failure: (_s, _box, error) => errors.push(error),
      button(label, callback) { const node = { label, callback, dataset:{} }; buttons.push(node); return node; }
    };
    b.window.Router = { reload() {} };
    b.window.LogisticsUI = {el(_tag,_cls,text){if(text)notices.push(text);return {append(){}};},button:b.window.AdminUI.button};
    // Expose private handlers in this VM only; exercise the actual call sites.
    vm.runInContext(dispatchSource.replace("Object.freeze({mount,destroy})", "Object.freeze({mount,destroy,calculatePlan,confirmPlan,write,planningKey})"), b.context);
    const s = {
      abort: new AbortController(), query: operation === "optimize" ? { tripId: 7 } : {},
      draft: { warehouseId: 1, departure: "2030-01-01T09:00", shipperIds: [3] },
      selected: new Map([[1, {}]]), edits: [], proposal: { id: "test-plan" },
      content: { setAttribute() {}, querySelector() { return null; }, querySelectorAll(){return [];} }, feedback: { append() {}, replaceChildren(){} }, alive: () => true
    };
    s.proposalBinding = { id: s.proposal.id, key: b.window.DispatchPage.planningKey(s) };
    const control = { textContent: "Submit", disabled: false };
    const pending = operation === "confirm" ? b.window.DispatchPage.confirmPlan(s, control)
      : b.window.DispatchPage.calculatePlan(s, control, operation === "manual");
    await headers.promise;
    b.advance(20000);
    assert.equal(errors.length, 0);
    assert.equal(b.timers.size, 1);
    b.advance(39999);
    assert.equal(errors.length, 0);
    b.advance(1);
    await pending;
    assert.equal(errors.length, 0);
    assert.equal(s.writeUnknown, true);
    assert(notices.includes("Chưa xác định được kết quả lưu. Hãy kiểm tra dữ liệu trước khi thực hiện lại."));
    assert.equal(calls, 1);
    assert.equal(b.timers.size, 0);
    assert.equal(actualUrl, operation === "confirm" ? "/api/v1/dispatch/plans/test-plan/confirm"
      : operation === "optimize" ? "/api/v1/trips/7/optimize" : "/api/v1/dispatch/plans");
    if (operation === "confirm") {
      assert.equal(control.disabled, true);
      assert.equal(buttons[0].label, "Tải lại để kiểm tra");
    }
  });
}
