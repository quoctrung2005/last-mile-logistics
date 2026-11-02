"use strict";
const { test } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const http = require("node:http");
const { createServer } = require("../dev-server.cjs");
const source = fs.readFileSync(path.join(__dirname, "../js/api.js"), "utf8");
const authSource = fs.readFileSync(path.join(__dirname, "../js/auth.js"), "utf8");
const user = { accountId: 1, username: "test", role: "ADMIN", fullName: "Test", branchId: null };
function tokens(letter = "a", exp = 1800000000) {
  return { accessToken: "eyJhbGciOiJIUzI1NiJ9." + Buffer.from(JSON.stringify({ exp, jti: letter })).toString("base64url") + ".signature",
    refreshToken: letter.repeat(43), expiresAt: new Date(exp * 1000).toISOString(), user };
}
function json(status, data = { message: "Test response" }) {
  return new Response(JSON.stringify(data), { status, headers: { "content-type": "application/json" } });
}
function browser(fetchImpl, storage = new Map()) {
  const events = [];
  const storageApi = { getItem: key => storage.get(key) ?? null, setItem: (key, value) => storage.set(key, String(value)), removeItem: key => storage.delete(key) };
  const window = { APP_CONFIG: { API_BASE_URL: "" }, dispatchEvent: event => events.push(event.type) };
  const context = vm.createContext({ window, sessionStorage: storageApi, localStorage: storageApi,
    fetch: fetchImpl, Headers, AbortController, DOMException, CustomEvent, setTimeout, clearTimeout, atob });
  vm.runInContext(source, context);
  vm.runInContext(authSource, context);
  return { api: window.ApiClient, auth: window.Auth, events, storage };
}
function deferred() { let resolve; const promise = new Promise(r => { resolve = r; }); return { promise, resolve }; }

test("login persists the full session, immediately changes Authorization, and survives reload", async () => {
  const fresh = tokens("b");
  const b = browser(async (url, options) => {
    assert.equal(options.redirect, "error");
    if (url.endsWith("/login")) {
      assert.equal(options.headers.has("Authorization"), false);
      assert.deepEqual(JSON.parse(options.body), { username: "test", password: "test-only" });
      return json(200, fresh);
    }
    assert.equal(options.headers.get("Authorization"), "Bearer " + fresh.accessToken);
    return json(200, user);
  });
  b.api.storeTokens(tokens());
  await b.auth.login("test", "test-only");
  assert.equal(b.api.getSession().expiresAt, fresh.expiresAt);
  assert.equal(b.api.getSession().user.username, "test");
  await b.api.request("/api/v1/orders", { headers: { Authorization: "Bearer stale" } });
  const reload = browser(async (url, options) => {
    assert.equal(options.headers.get("Authorization"), "Bearer " + fresh.accessToken);
    return json(200, user);
  }, b.storage);
  await reload.auth.getCurrentUser();
  assert.equal(reload.storage.size, 1);
});

test("rejects invalid token values atomically and normalizes Bearer and ISO offsets", () => {
  const b = browser(() => { throw new Error("Unexpected request"); });
  const initial = tokens(); b.api.storeTokens(initial);
  for (const bad of [undefined, null, "undefined", "null", "", {}, initial]) {
    assert.throws(() => b.api.storeTokens({ ...initial, accessToken: bad }));
    assert.equal(b.api.getAccessToken(), initial.accessToken);
  }
  assert.throws(() => b.api.storeTokens({ ...initial, refreshToken: "undefined" }));
  assert.throws(() => b.api.storeTokens({ ...initial, expiresAt: "2027-01-15T08:00:00" }));
  b.api.storeTokens({ ...initial, accessToken: "Bearer Bearer " + initial.accessToken, expiresAt: "2027-01-15T15:00:00+07:00" });
  assert.equal(b.api.getAccessToken(), initial.accessToken);
  assert.equal(b.api.getSession().expiresAt, "2027-01-15T08:00:00.000Z");
});

test("legacy session migrates using JWT exp in seconds", () => {
  const initial = tokens();
  const b = browser(() => {}, new Map([["tvd.accessToken", initial.accessToken], ["tvd.refreshToken", initial.refreshToken]]));
  assert.equal(Date.parse(b.api.getSession().expiresAt), 1800000000 * 1000);
  assert.equal(b.storage.has("tvd.accessToken"), false);
});

test("403, validation/conflict/rate limit/server errors and network failures preserve session", async () => {
  for (const status of [400, 403, 404, 409, 429, 500, 502]) {
    const b = browser(async () => json(status)); b.api.storeTokens(tokens());
    await assert.rejects(b.api.request("/api/v1/orders"), error => error.status === status && error.url === "/api/v1/orders" && error.data.message === "Test response");
    assert.ok(b.api.getAccessToken()); assert.equal(b.events.length, 0);
  }
  const b = browser(async () => { throw new TypeError("Network unavailable"); }); b.api.storeTokens(tokens());
  await assert.rejects(b.api.request("/api/v1/orders"), error => error.networkError);
  assert.ok(b.api.getAccessToken()); assert.equal(b.events.length, 0);
});

test("simultaneous and delayed 401 responses rotate only once and retry with the new token", async () => {
  const initial = tokens(), next = tokens("b"), gate = deferred(), refreshStarted = deferred(), late = deferred();
  let refreshCount = 0, retryCount = 0;
  const b = browser(async (url, options) => {
    if (url.endsWith("/refresh")) {
      refreshCount++; assert.equal(options.headers.has("Authorization"), false);
      assert.equal(JSON.parse(options.body).refreshToken, initial.refreshToken);
      refreshStarted.resolve(); await gate.promise; return json(200, next);
    }
    if (options.headers.get("Authorization") === "Bearer " + initial.accessToken) {
      if (url.endsWith("/late")) await late.promise;
      return json(401);
    }
    assert.equal(options.headers.get("Authorization"), "Bearer " + next.accessToken);
    retryCount++; return json(200, { ok: true });
  });
  b.api.storeTokens(initial);
  const delayed = b.api.request("/api/v1/late");
  const requests = Array.from({ length: 8 }, (_, i) => b.api.request("/api/v1/request/" + i));
  await refreshStarted.promise; gate.resolve(); await Promise.all(requests);
  late.resolve(); await delayed;
  assert.equal(refreshCount, 1); assert.equal(retryCount, 9);
  assert.equal(b.api.getRefreshToken(), next.refreshToken); assert.equal(b.events.length, 0);
});

test("retry is bounded to once; another 401 does not invalidate a successfully refreshed session", async () => {
  let refreshCount = 0, calls = 0;
  const b = browser(async url => {
    if (url.endsWith("/refresh")) { refreshCount++; return json(200, tokens("b")); }
    calls++; return json(401);
  }); b.api.storeTokens(tokens());
  await assert.rejects(b.api.request("/api/v1/orders"), error => error.status === 401 && !error.sessionExpired);
  assert.equal(calls, 2); assert.equal(refreshCount, 1); assert.equal(b.events.length, 0);
  assert.equal(b.api.getRefreshToken(), tokens("b").refreshToken);
});

test("refresh failures preserve session unless backend confirms invalid refresh token", async () => {
  const failures = [json(400), json(403), json(409), json(429), json(500), new TypeError("Network unavailable"),
    json(200, { accessToken: "undefined" }), json(401), json(400, { errors: { RefreshToken: ["Invalid format"] } })];
  for (let i = 0; i < failures.length; i++) {
    let refreshCount = 0;
    const b = browser(async url => {
      if (!url.endsWith("/refresh")) return json(401);
      refreshCount++; if (failures[i] instanceof Error) throw failures[i]; return failures[i];
    }); b.api.storeTokens(tokens());
    const invalid = i >= 7;
    await assert.rejects(b.api.request("/api/v1/orders"), error => Boolean(error.sessionExpired) === invalid);
    assert.equal(refreshCount, 1);
    assert.equal(Boolean(b.api.getAccessToken()), !invalid);
    assert.equal(b.events.length, invalid ? 1 : 0);
  }
});

test("login/refresh 401 never recurse into refresh", async () => {
  let calls = 0; const b = browser(async () => { calls++; return json(401); }); b.api.storeTokens(tokens());
  await assert.rejects(b.api.request("/api/v1/auth/login", { method: "POST" }));
  await assert.rejects(b.api.request("/api/v1/auth/refresh", { method: "POST" }));
  await assert.rejects(b.api.request("/api/v1/auth/refresh/", { method: "POST" }));
  assert.equal(calls, 3); assert.equal(b.events.length, 0); assert.ok(b.api.getAccessToken());
});

test("old refresh success/failure cannot overwrite or clear a newly logged-in session", async () => {
  for (const status of [200, 401]) {
    const gate = deferred(), started = deferred();
    const b = browser(async url => {
      if (!url.endsWith("/refresh")) return json(401);
      started.resolve(); await gate.promise; return json(status, status === 200 ? tokens("b") : undefined);
    }); b.api.storeTokens(tokens());
    const pending = b.api.request("/api/v1/orders");
    await started.promise; b.api.storeTokens(tokens("c")); gate.resolve();
    await assert.rejects(pending);
    assert.equal(b.api.getRefreshToken(), tokens("c").refreshToken); assert.equal(b.events.length, 0);
  }
});

test("real HTTP proxy forwards Authorization/body, blocks redirects, and reports unavailable upstream as 502", async t => {
  const upstream = http.createServer((request, response) => {
    if (request.url === "/api/redirect") { response.writeHead(307, { Location: "https://localhost:7255/api/redirect" }); response.end(); return; }
    let body = ""; request.on("data", chunk => { body += chunk; });
    request.on("end", () => {
      assert.equal(request.headers.authorization, "Bearer proxy-test");
      assert.equal(request.method, "POST"); assert.equal(body, '{"refreshToken":"proxy-body"}');
      response.writeHead(200, { "content-type": "application/json" }); response.end('{"ok":true}');
    });
  });
  await new Promise(resolve => upstream.listen(0, "127.0.0.1", resolve));
  const proxy = createServer(new URL("http://127.0.0.1:" + upstream.address().port));
  await new Promise(resolve => proxy.listen(0, "127.0.0.1", resolve));
  t.after(() => { proxy.closeAllConnections(); proxy.close(); upstream.closeAllConnections(); upstream.close(); });
  const base = "http://127.0.0.1:" + proxy.address().port;
  const result = await fetch(base + "/api/echo", { method: "POST", headers: { Authorization: "Bearer proxy-test", "content-type": "application/json" }, body: '{"refreshToken":"proxy-body"}' });
  assert.equal(result.status, 200); assert.deepEqual(await result.json(), { ok: true });
  const redirect = await fetch(base + "/api/redirect", { redirect: "manual" });
  assert.equal(redirect.status, 502); assert.equal(redirect.headers.has("location"), false);
  assert.match((await redirect.json()).message, /chuyển hướng API/);
  upstream.closeAllConnections(); await new Promise(resolve => upstream.close(resolve));
  const down = await fetch(base + "/api/echo"); assert.equal(down.status, 502);
});
