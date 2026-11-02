"use strict";
// Real HTTP and LocalDB. Only GUID fixtures and qa.login.* test accounts are changed.
// Ephemeral passwords/key/tokens stay in memory and are never printed.
const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const path = require("node:path");
const { spawn, execFile } = require("node:child_process");
const { promisify } = require("node:util");
const database = "CodexAccounts_" + crypto.randomBytes(16).toString("hex");
const backend = path.resolve(__dirname, "../../backend/LastMile/LastMile.Api");
const jwtKey = crypto.randomBytes(64).toString("hex");
const secret = () => "Qa!" + crypto.randomBytes(18).toString("hex");
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
const processes = [];
const checks = [];
const check = label => { checks.push(label); console.log("PASS " + label); };
function args(file, mode, id = 0, source = 0) {
  return ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", path.join(__dirname, file), "-Mode", mode,
    "-Database", database, "-TargetId", String(id), ...(source ? ["-SourceId", String(source)] : [])];
}
async function fixture(mode, id = 0) {
  const file = ["Create", "Drop"].includes(mode) ? "accounts-fixture.ps1" : "auth-login-fixture.ps1";
  try {
    const { stdout } = await promisify(execFile)("powershell.exe", args(file, mode, id), { windowsHide: true, maxBuffer: 8 * 1024 * 1024 });
    return JSON.parse(stdout);
  } catch { throw new Error("Isolated fixture failed: " + mode); }
}
async function start(connectionString, overrides = {}) {
  let output = "";
  const child = spawn("dotnet", [path.join(__dirname, ".artifacts/auth/build/LastMile.Api.dll"), "--urls", "http://127.0.0.1:0"], {
    cwd: backend, windowsHide: true, stdio: ["ignore", "pipe", "pipe"],
    env: { ...process.env, ASPNETCORE_ENVIRONMENT: "Development", ConnectionStrings__DefaultConnection: connectionString,
      Jwt__Key: jwtKey, Jwt__Issuer: "LoginQA", Jwt__Audience: "LoginQA", ...overrides }
  });
  processes.push(child);
  child.stdout.on("data", chunk => { output += chunk; });
  child.stderr.resume();
  for (let i = 0; i < 150 && !/Now listening on: (http:\/\/127.0.0.1:\d+)/.test(output); i++) await sleep(100);
  const origin = output.match(/Now listening on: (http:\/\/127.0.0.1:\d+)/)?.[1];
  assert.ok(origin, "Isolated API started");
  return async (url, session, body, expected = 200, headers = {}) => {
    const response = await fetch(origin + url, {
      method: body === undefined ? "GET" : "POST",
      headers: { "Content-Type": "application/json", ...(session ? { Authorization: "Bearer " + session.accessToken } : {}), ...headers },
      body: body === undefined ? undefined : JSON.stringify(body)
    });
    assert.equal(response.status, expected, "HTTP status for " + url);
    const text = await response.text();
    return text ? JSON.parse(text) : null;
  };
}
function bootstrap(actor) {
  const header = Buffer.from('{"alg":"HS256","typ":"JWT"}').toString("base64url");
  const payload = Buffer.from(JSON.stringify({ iss: "LoginQA", aud: "LoginQA", exp: Math.floor(Date.now() / 1000) + 3600,
    sid: Number(actor.accountId).toString(16).padStart(32, "0"),
    "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/nameidentifier": String(actor.accountId),
    "http://schemas.microsoft.com/ws/2008/06/identity/claims/role": "ADMIN" })).toString("base64url");
  return { accessToken: header + "." + payload + "." + crypto.createHmac("sha256", jwtKey).update(header + "." + payload).digest("base64url") };
}

(async () => {
  const setup = await fixture("Create");
  // Raise only the test host's IP budget so account-lock tests isolate that layer.
  const api = await start(setup.connectionString, { LoginSecurity__IpPermitLimit: "1000" });
  const admin = bootstrap(setup.actors.find(actor => actor.role === "ADMIN"));
  const role = (await api("/api/v1/roles?lookupOnly=true", admin)).items.find(role => role.code === "WAREHOUSE_STAFF");
  const branchId = setup.actors.find(actor => actor.role === "BRANCH_MANAGER").branchId;
  const create = async name => {
    const password = secret();
    const data = await api("/api/v1/accounts", admin, { username: "qa.login." + name, fullName: "QA Login", password, roleId: role.id, branchId }, 201);
    return { ...data, password };
  };
  const login = (account, password = account.password, expected = 200, client = api) => client("/api/v1/auth/login", null, { username: account.username, password }, expected);
  const target = await create("threshold");
  const wrong = secret();
  const generic = (await api("/api/v1/auth/login", null, { username: "qa.login.missing", password: wrong }, 401)).message;
  for (let i = 1; i < 5; i++) {
    assert.equal((await login(target, wrong, 401)).message, generic);
    const state = await fixture("State", target.id);
    assert.equal(state.failedCount, i); assert.equal(state.lockedUntil, null); assert.equal(state.sessionCount, 0);
  }
  check("Wrong attempts 1-4 increment exactly; nonexistent user and wrong password share the generic response");
  assert.equal((await login(target, wrong, 401)).message, generic);
  let state = await fixture("State", target.id);
  assert.equal(state.failedCount, 5); assert.ok(state.secondsUntilUnlock > 880 && state.secondsUntilUnlock <= 900);
  assert.equal(state.status, "ACTIVE");
  check("Fifth failure sets a 15-minute temporary lock without changing administrative status");
  assert.equal((await login(target, target.password, 401)).message, generic);
  await login(target, wrong, 401);
  const stillLocked = await fixture("State", target.id);
  assert.equal(stillLocked.failedCount, 5); assert.equal(stillLocked.lockedUntil, state.lockedUntil); assert.equal(stillLocked.sessionCount, 0);
  check("Correct and wrong passwords during a lock cannot issue tokens, extend the lock or increment further");

  await fixture("Expire", target.id);
  const session = await login(target);
  state = await fixture("State", target.id);
  assert.equal(state.failedCount, 0); assert.equal(state.lockedUntil, null); assert.ok(state.lastLoginAt);
  assert.equal(state.sessionCount, 1);
  await api("/api/v1/auth/me", session);
  check("Correct login after expiry clears count/temporary lock, records last login and preserves the success contract");
  await login(target, wrong, 401); await login(target);
  assert.equal((await fixture("State", target.id)).failedCount, 0);
  check("A successful login also resets a below-threshold consecutive-failure count");

  const expiry = await create("expiry");
  for (let i = 0; i < 5; i++) await login(expiry, wrong, 401);
  await fixture("Expire", expiry.id); await login(expiry, wrong, 401);
  state = await fixture("State", expiry.id);
  assert.equal(state.failedCount, 1); assert.equal(state.lockedUntil, null);
  check("Wrong login after an expired lock starts a new round at one");

  const concurrent = await create("concurrent");
  await Promise.all(Array.from({ length: 4 }, () => login(concurrent, wrong, 401)));
  assert.equal((await fixture("State", concurrent.id)).failedCount, 4);
  await Promise.all(Array.from({ length: 4 }, () => login(concurrent, wrong, 401)));
  state = await fixture("State", concurrent.id);
  assert.equal(state.failedCount, 5); assert.ok(state.secondsUntilUnlock > 880); assert.equal(state.sessionCount, 0);
  check("Concurrent wrong passwords lose no increments below the threshold and serialize at the lock threshold");

  for (const action of ["LOCK", "DEACTIVATE"]) {
    const account = await create(action.toLowerCase());
    const detail = await api("/api/v1/accounts?id=" + account.id, admin);
    await api(`/api/v1/accounts/${account.id}/actions`, admin, { action, reason: "QA login admin status", expectedVersion: detail.version });
    assert.equal((await login(account, account.password, 401)).message, generic);
    await login(account, wrong, 401);
    state = await fixture("State", account.id);
    assert.equal(state.status, action === "LOCK" ? "LOCKED" : "INACTIVE");
    assert.equal(state.failedCount, 0); assert.equal(state.sessionCount, 0);
  }
  check("Admin LOCKED and INACTIVE accounts remain blocked and unchanged by correct or wrong logins");

  const racingLock = await create("race.lock");
  let done;
  // Acquire the fixture lock, then begin the HTTP request before it commits.
  // Keep the promise wrapped: an async function returning it would await the gate.
  const runRace = async (mode, account, source) => {
    const child = spawn("powershell.exe", args("auth-login-fixture.ps1", mode, account.id, source?.id), { windowsHide: true, stdio: ["ignore", "pipe", "pipe"] });
    let output = "";
    const finished = new Promise((resolve, reject) => {
      child.on("error", () => reject(new Error("Race fixture failed to start")));
      child.on("exit", code => code === 0 ? resolve() : reject(new Error("Race fixture failed")));
    });
    child.stderr.resume();
    await new Promise((resolve, reject) => {
      child.stdout.on("data", chunk => { output += chunk; if (output.includes("READY")) resolve(); });
      finished.then(() => { if (!output.includes("READY")) reject(new Error("Missing race gate")); }, reject);
    });
    return { finished };
  };
  ({ finished: done } = await runRace("RaceLock", racingLock));
  await login(racingLock, racingLock.password, 401); await done;
  assert.equal((await fixture("State", racingLock.id)).sessionCount, 0);
  check("A lock committed while a correct login is in flight is rechecked before token issuance");

  const racingHash = await create("race.hash"), replacement = await create("replacement");
  ({ finished: done } = await runRace("RaceHash", racingHash, replacement));
  await Promise.all([login(racingHash, racingHash.password, 401), login(racingHash, wrong, 401)]); await done;
  state = await fixture("State", racingHash.id);
  assert.equal(state.failedCount, 0); assert.equal(state.sessionCount, 0);
  await login(racingHash, replacement.password);
  check("Hash changes during BCrypt invalidate stale success and stale failure without issuing tokens or counting against the new hash");

  const lengths = await create("lengths");
  await login(lengths, "x".repeat(73), 400);
  assert.equal((await login(lengths, "ệ".repeat(25), 401)).message, generic);
  assert.equal((await fixture("State", lengths.id)).failedCount, 0);
  check("Inputs exceeding 72 characters or 72 UTF-8 bytes are rejected before BCrypt and do not mutate counters");

  const configured = await create("configured");
  const customApi = await start(setup.connectionString, { LoginSecurity__MaxFailedAttempts: "3", LoginSecurity__LockoutMinutes: "2", LoginSecurity__IpPermitLimit: "1000" });
  for (let i = 0; i < 3; i++) await login(configured, wrong, 401, customApi);
  state = await fixture("State", configured.id);
  assert.equal(state.failedCount, 3); assert.ok(state.secondsUntilUnlock > 100 && state.secondsUntilUnlock <= 120);
  check("Configured threshold and lock duration override the 5-attempt/15-minute defaults");

  // New hosts give an empty IP bucket without relaxing the production defaults.
  const limited = await start(setup.connectionString);
  for (let i = 0; i < 20; i++) await limited("/api/v1/auth/login", null, { username: "qa.login.absent", password: wrong }, 401);
  assert.match((await limited("/api/v1/auth/login", null, { username: "qa.login.other.absent", password: wrong }, 429,
    { "X-Forwarded-For": "192.0.2.99" })).message, /Quá nhiều yêu cầu đăng nhập/);
  await limited("/api/v1/auth/me", admin);
  check("Default shared-IP login budget rejects request 21 with JSON 429; spoofed forwarded headers do not bypass it; other APIs remain available");

  const smallBucket = await start(setup.connectionString, { LoginSecurity__IpPermitLimit: "2", LoginSecurity__IpWindowSeconds: "1" });
  for (let i = 0; i < 2; i++) await smallBucket("/api/v1/auth/login", null, { username: "qa.login.absent", password: wrong }, 401);
  await smallBucket("/api/v1/auth/login", null, { username: "qa.login.absent", password: wrong }, 429);
  await sleep(1100);
  await smallBucket("/api/v1/auth/login", null, { username: "qa.login.absent", password: wrong }, 401);
  check("Configured IP window replenishes the budget and allows requests again");
  console.log(JSON.stringify({ checks: checks.length, passed: checks.length, operationalDatabaseWrites: false }));
})().catch(error => { console.error(error.stack); process.exitCode = 1; }).finally(async () => {
  for (const child of processes) {
    if (child.exitCode === null) {
      const done = new Promise(resolve => child.once("exit", resolve)); child.kill(); await done;
    }
  }
  try { await fixture("Drop"); console.log("Isolated login test database removed."); }
  catch { console.error("Isolated login test database cleanup failed"); process.exitCode = 1; }
});
