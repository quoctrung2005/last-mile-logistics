"use strict";
// Real HTTP + SQL integration. Every database write uses a GUID LocalDB fixture;
// passwords, JWT key, access/refresh/recovery tokens stay in memory and logs omit them.
const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const { spawn, execFile } = require("node:child_process");
const { promisify } = require("node:util");
const root = path.resolve(__dirname, "../..");
const backend = path.join(root, "backend/LastMile/LastMile.Api");
const database = "CodexAccounts_" + crypto.randomBytes(16).toString("hex");
const jwtKey = crypto.randomBytes(64).toString("hex");
const secret = () => "Qa!" + crypto.randomBytes(18).toString("hex");
const rawToken = () => crypto.randomBytes(32).toString("base64url");
const checks = [];
let processApi, origin;
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
const check = label => { checks.push(label); console.log("PASS " + label); };
async function fixture(mode, targetId = 0, token) {
  const auth = !["Create", "Drop"].includes(mode);
  try {
    const { stdout } = await promisify(execFile)("powershell.exe", ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
      path.join(__dirname, auth ? "auth-sessions-fixture.ps1" : "accounts-fixture.ps1"),
      "-Mode", mode, "-Database", database, "-TargetId", String(targetId)], {
      windowsHide: true, maxBuffer: 8 * 1024 * 1024,
      env: { ...process.env, AUTH_SESSION_TEST_TOKEN: token || "" }
    });
    return JSON.parse(stdout);
  } catch { throw new Error("Isolated fixture failed in mode " + mode); }
}
function jwt(payload) {
  const head = Buffer.from(JSON.stringify({ alg: "HS256", typ: "JWT" })).toString("base64url");
  const data = Buffer.from(JSON.stringify(payload)).toString("base64url");
  return head + "." + data + "." + crypto.createHmac("sha256", jwtKey).update(head + "." + data).digest("base64url");
}
const payload = token => JSON.parse(Buffer.from(token.split(".")[1], "base64url"));
async function request(url, session, method = "GET", body) {
  const response = await fetch(origin + url, { method,
    headers: { "Content-Type": "application/json", ...(session ? { Authorization: "Bearer " + session.accessToken } : {}) },
    body: body === undefined ? undefined : JSON.stringify(body)
  });
  const text = await response.text();
  let data; try { data = text ? JSON.parse(text) : null; } catch { data = null; }
  return { status: response.status, data };
}
async function api(url, session, method = "GET", body, status = 200) {
  const result = await request(url, session, method, body);
  assert.equal(result.status, status, method + " " + url + " status");
  return result.data;
}
const me = (session, status = 200) => api("/api/v1/auth/me", session, "GET", undefined, status);
const refresh = session => api("/api/v1/auth/refresh", null, "POST", { refreshToken: session.refreshToken });
const logout = (session, allSessions = false) => api("/api/v1/auth/logout", null, "POST", { refreshToken: session.refreshToken, allSessions });
const denied = async session => {
  await me(session, 401);
  await api("/api/v1/auth/refresh", null, "POST", { refreshToken: session.refreshToken }, 401);
};

(async () => {
  const setup = await fixture("Create");
  const { sessionId } = await fixture("Prepare");
  const actor = setup.actors.find(actor => actor.role === "ADMIN");
  const exp = Math.floor(Date.now() / 1000) + 3600;
  // Only bootstrap uses a signed test JWT tied to an actual test session row.
  const bootstrap = { accessToken: jwt({ iss: "SessionQA", aud: "SessionQA", exp, sid: sessionId,
    "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/nameidentifier": String(actor.accountId),
    "http://schemas.microsoft.com/ws/2008/06/identity/claims/role": "ADMIN" }) };
  let log = "";
  processApi = spawn("dotnet", [path.join(__dirname, ".artifacts/auth/build/LastMile.Api.dll"), "--urls", "http://127.0.0.1:0"], {
    cwd: backend, windowsHide: true, stdio: ["ignore", "pipe", "pipe"],
    env: { ...process.env, ASPNETCORE_ENVIRONMENT: "Development", ConnectionStrings__DefaultConnection: setup.connectionString + ";MultipleActiveResultSets=False",
      Jwt__Key: jwtKey, Jwt__Issuer: "SessionQA", Jwt__Audience: "SessionQA", LoginSecurity__IpPermitLimit: "1000" }
  });
  processApi.stdout.on("data", data => { log += data; });
  processApi.stderr.on("data", data => { log += data; });
  for (let i = 0; i < 150 && !/Now listening on: (http:\/\/127.0.0.1:\d+)/.test(log); i++) await sleep(100);
  origin = log.match(/Now listening on: (http:\/\/127.0.0.1:\d+)/)?.[1];
  assert.ok(origin, "Isolated API startup");
  await fixture("BreakLookup");
  await api("/api/v1/auth/refresh", null, "POST", { refreshToken: rawToken() }, 500);
  assert.match(log, /SQL 207/, "Schema failure preserves its SQL cause in server logs");
  await fixture("Migrate");
  await api("/api/v1/auth/refresh", null, "POST", { refreshToken: rawToken() }, 401);
  check("Missing MaPhien returns 500 and logs SQL 207; applying migration restores authentication failures to 401");
  const roles = (await api("/api/v1/roles?lookupOnly=true", bootstrap)).items;
  const adminRole = roles.find(role => role.code === "ADMIN");
  const warehouseRole = roles.find(role => role.code === "WAREHOUSE_STAFF");
  const branchId = setup.actors.find(actor => actor.role === "BRANCH_MANAGER").branchId;
  const adminPassword = secret();
  let password = secret();
  const adminAccount = await api("/api/v1/accounts", bootstrap, "POST", {
    username: "qa.session.admin", password: adminPassword, fullName: "QA Session Admin", roleId: adminRole.id, branchId: null
  }, 201);
  const account = await api("/api/v1/accounts", bootstrap, "POST", {
    username: "qa.session.user", password, fullName: "QA Session User", roleId: warehouseRole.id, branchId
  }, 201);
  const login = () => api("/api/v1/auth/login", null, "POST", { username: account.username, password });
  const admin = await api("/api/v1/auth/login", null, "POST", { username: adminAccount.username, password: adminPassword });

  let a = await login();
  await me(a);
  await logout(a);
  await denied(a);
  check("Login -> protected API succeeds -> logout invalidates access and refresh");

  a = await login(); let b = await login();
  assert.notEqual(payload(a.accessToken).sid, payload(b.accessToken).sid);
  await logout(a); await denied(a); await me(b);
  b = await refresh(b); await me(b);
  check("Independent sessions: logout one leaves the other accessible and refreshable");

  a = await login(); b = await login();
  await logout(a, true); await denied(a); await denied(b);
  check("Logout all invalidates both access and refresh tokens");

  a = await login(); b = await refresh(a);
  assert.equal(payload(a.accessToken).sid, payload(b.accessToken).sid);
  assert.notEqual(a.refreshToken, b.refreshToken);
  await me(a); await me(b);
  await api("/api/v1/auth/refresh", null, "POST", { refreshToken: a.refreshToken }, 401);
  await me(b);
  await logout(a); await denied(a); await denied(b);
  check("Refresh works with MARS disabled, keeps sid and older access valid; predecessor logout revokes the rotated session");

  a = await login(); b = await login();
  const rotated = await refresh(a);
  let nextPassword = secret();
  await api("/api/v1/auth/change-password", b, "POST", {
    currentPassword: password, newPassword: nextPassword, confirmPassword: nextPassword
  });
  await denied(a); await denied(b); await denied(rotated);
  await api("/api/v1/auth/login", null, "POST", { username: account.username, password }, 401);
  password = nextPassword; await me(await login());
  check("Password change revokes every pre-existing session including rotated tokens; new login works");

  a = await login(); b = await login(); nextPassword = secret();
  const detail = await api("/api/v1/accounts?id=" + account.id, admin);
  await api(`/api/v1/accounts/${account.id}/reset-password`, b, "POST", {
    newPassword: nextPassword, reason: "QA permission", expectedVersion: detail.version
  }, 403);
  const reset = await api(`/api/v1/accounts/${account.id}/reset-password`, admin, "POST", {
    newPassword: nextPassword, reason: "QA session reset", expectedVersion: detail.version
  });
  assert.equal(reset.refreshTokensRevoked, true); assert.equal(reset.accessTokensRevoked, true);
  await denied(a); await denied(b); await me(admin);
  password = nextPassword; await me(await login());
  check("Admin reset revokes all target sessions, preserves admin session and enforces management permission");

  a = await login(); b = await login(); nextPassword = secret();
  const recoveryToken = rawToken();
  await fixture("Recovery", account.id, recoveryToken);
  await api("/api/v1/auth/password-recovery", null, "POST", {
    action: "RESET", recoveryToken, newPassword: nextPassword, confirmPassword: nextPassword
  });
  await denied(a); await denied(b);
  await api("/api/v1/auth/password-recovery", null, "POST", {
    action: "RESET", recoveryToken, newPassword: nextPassword, confirmPassword: nextPassword
  }, 401);
  password = nextPassword; await me(await login());
  check("Recovery reset consumes its code, revokes all prior sessions and allows new-password login");

  const legacy = rawToken();
  await fixture("Legacy", account.id, legacy);
  await api("/api/v1/auth/refresh", null, "POST", { refreshToken: legacy }, 401);
  a = await login();
  const withoutSid = payload(a.accessToken); delete withoutSid.sid;
  await me({ accessToken: jwt(withoutSid) }, 401);
  await me({ accessToken: jwt({ ...payload(a.accessToken), sid: crypto.randomBytes(16).toString("hex") }) }, 401);
  await me({ accessToken: jwt({ ...payload(a.accessToken), sid: payload(admin.accessToken).sid }) }, 401);
  await fixture("Migrate"); await me(a); await me(admin);
  check("Legacy/no-session/wrong-owner JWTs and legacy refresh fail closed; repeated migration preserves live sessions");

  for (const allSessions of [false, true]) {
    for (let i = 0; i < 4; i++) {
      a = await login(); b = await login();
      const [refreshResult, logoutResult] = await Promise.all([
        request("/api/v1/auth/refresh", null, "POST", { refreshToken: a.refreshToken }),
        request("/api/v1/auth/logout", null, "POST", { refreshToken: a.refreshToken, allSessions })
      ]);
      assert.equal(logoutResult.status, 200);
      assert.ok([200, 401].includes(refreshResult.status), "Concurrent refresh status");
      await denied(a);
      if (refreshResult.status === 200) await denied(refreshResult.data);
      if (allSessions) await denied(b); else { await me(b); await logout(b); }
    }
  }
  check("8 real refresh/logout races cannot leave a live rotated session or revoke unrelated sessions");

  a = await login();
  const double = await Promise.all([request("/api/v1/auth/refresh", null, "POST", { refreshToken: a.refreshToken }),
    request("/api/v1/auth/refresh", null, "POST", { refreshToken: a.refreshToken })]);
  assert.deepEqual(double.map(result => result.status).sort(), [200, 401]);
  await me(double.find(result => result.status === 200).data);
  check("Concurrent refresh of one token rotates exactly once without revoking its session");

  // Exercise ApiClient's real single-flight refresh against concurrent HTTP 401s.
  a = await login();
  const expired = payload(a.accessToken); expired.exp = Math.floor(Date.now() / 1000) - 10;
  expired.nbf = expired.exp - 3600;
  const storage = new Map(); let refreshCalls = 0;
  const window = { APP_CONFIG: { API_BASE_URL: origin }, dispatchEvent() {} };
  const context = vm.createContext({ window, Headers, AbortController, DOMException, CustomEvent, setTimeout, clearTimeout, atob,
    sessionStorage: { getItem: key => storage.get(key) ?? null, setItem: (key, value) => storage.set(key, value), removeItem: key => storage.delete(key) },
    fetch: async (url, options) => { if (url.endsWith("/refresh")) refreshCalls++; return fetch(url, options); }
  });
  vm.runInContext(fs.readFileSync(path.join(__dirname, "../js/api.js"), "utf8"), context);
  window.ApiClient.storeTokens({ ...a, accessToken: jwt(expired) });
  const results = await Promise.all(Array.from({ length: 8 }, () => window.ApiClient.request("/api/v1/auth/me")));
  assert.ok(results.every(result => Number(result.accountId) === account.id));
  assert.equal(refreshCalls, 1);
  check("8 simultaneous real 401s refresh once through ApiClient and all retry successfully");

  for (const operation of ["change", "admin", "recovery"]) {
    a = await login(); b = await login(); nextPassword = secret();
    let url, session, body;
    if (operation === "change") {
      url = "/api/v1/auth/change-password"; session = b;
      body = { currentPassword: password, newPassword: nextPassword, confirmPassword: nextPassword };
    } else if (operation === "admin") {
      url = `/api/v1/accounts/${account.id}/reset-password`; session = admin;
      body = { newPassword: nextPassword, reason: "QA concurrent reset", expectedVersion: (await api("/api/v1/accounts?id=" + account.id, admin)).version };
    } else {
      const recoveryToken = rawToken(); await fixture("Recovery", account.id, recoveryToken);
      url = "/api/v1/auth/password-recovery"; session = null;
      body = { action: "RESET", recoveryToken, newPassword: nextPassword, confirmPassword: nextPassword };
    }
    const [refreshResult, resetResult] = await Promise.all([
      request("/api/v1/auth/refresh", null, "POST", { refreshToken: a.refreshToken }), request(url, session, "POST", body)
    ]);
    assert.equal(resetResult.status, 200, operation + " concurrent reset");
    assert.ok([200, 401].includes(refreshResult.status));
    await denied(a); await denied(b);
    if (refreshResult.status === 200) await denied(refreshResult.data);
    password = nextPassword; await me(await login());
    check("Concurrent refresh/" + operation + "-password cannot escape all-session revocation");
  }
  console.log(JSON.stringify({ checks: checks.length, passed: checks.length, operationalDatabaseWrites: false }));
})().catch(error => { console.error(error.stack); process.exitCode = 1; }).finally(async () => {
  if (processApi && processApi.exitCode === null) {
    const stopped = new Promise(resolve => processApi.once("exit", resolve));
    processApi.kill(); await stopped;
  }
  try { await fixture("Drop"); console.log("Isolated auth test database removed."); }
  catch { console.error("Isolated auth fixture cleanup failed"); process.exitCode = 1; }
});
