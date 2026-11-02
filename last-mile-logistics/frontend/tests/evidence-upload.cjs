"use strict";
// Actual JWT/SQL/HTTP/file pipeline, exclusively a GUID LocalDB and a private content root.
const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const { spawn, execFile } = require("node:child_process");
const { promisify } = require("node:util");
const root = path.resolve(__dirname, "../..");
const artifact = path.join(__dirname, ".artifacts/evidence");
const contentRoot = path.join(artifact, "run-" + crypto.randomBytes(16).toString("hex"));
const database = "CodexAccounts_" + crypto.randomBytes(16).toString("hex");
const jwtKey = crypto.randomBytes(64).toString("hex");
const checks = [];
let apiProcess, origin, created = false;
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
async function fixture(mode) {
  const { stdout } = await promisify(execFile)("powershell.exe", ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
    path.join(__dirname, "evidence-fixture.ps1"), "-Mode", mode, "-Database", database], { windowsHide: true, maxBuffer: 8 * 1024 * 1024 });
  return JSON.parse(stdout);
}
function jwt(actor) {
  const header = Buffer.from(JSON.stringify({ alg: "HS256", typ: "JWT" })).toString("base64url");
  // Matches accounts-fixture's deterministic session UUID from BINARY(16) account ID.
  const sid = "0000000000000000" + BigInt(actor.accountId).toString(16).padStart(16, "0");
  const payload = Buffer.from(JSON.stringify({ iss: "EvidenceQA", aud: "EvidenceQA", exp: Math.floor(Date.now() / 1000) + 3600, sid,
    "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/nameidentifier": String(actor.accountId),
    "http://schemas.microsoft.com/ws/2008/06/identity/claims/role": actor.role })).toString("base64url");
  return header + "." + payload + "." + crypto.createHmac("sha256", jwtKey).update(header + "." + payload).digest("base64url");
}
const files = () => fs.existsSync(path.join(contentRoot, "App_Data"))
  ? fs.readdirSync(path.join(contentRoot, "App_Data"), { recursive: true, withFileTypes: true }).filter(entry => entry.isFile()).length : 0;
function check(label) { checks.push(label); console.log("PASS " + label); }
async function upload(name, actor, attempt, status, extra = {}) {
  const data = fs.readFileSync(path.join(artifact, "images", name));
  const form = new FormData();
  form.set("DeliveryAttemptId", String(attempt.id)); form.set("Type", "PHOTO");
  form.set("File", new Blob([data], { type: "application/octet-stream" }), "../../misleading.txt");
  for (const [key, value] of Object.entries(extra)) form.set(key, value);
  const response = await fetch(origin + "/api/v1/orders/" + attempt.orderId + "/evidence", {
    method: "POST", headers: actor ? { Authorization: "Bearer " + jwt(actor) } : {}, body: form
  });
  const result = await response.json();
  assert.equal(response.status, status, name + " HTTP status: " + JSON.stringify(result));
  if (status !== 201) assert.ok(result.message || result.errors, "Vietnamese error body");
  return result;
}
(async () => {
  created = true; // Cleanup also covers partially initialized fixtures.
  const setup = await fixture("Create");
  fs.mkdirSync(contentRoot, { recursive: true });
  const attempt = setup.attempts[0]; assert.ok(attempt, "Seeded delivery attempt required");
  const shipper = setup.actors.find(actor => actor.accountId === attempt.accountId);
  const admin = setup.actors.find(actor => actor.role === "ADMIN");
  let log = "";
  apiProcess = spawn("dotnet", [path.join(artifact, "release/LastMile.Api.dll"), "--urls", "http://127.0.0.1:0", "--contentRoot", contentRoot], {
    cwd: contentRoot, windowsHide: true, stdio: ["ignore", "pipe", "pipe"],
    env: { ...process.env, ASPNETCORE_ENVIRONMENT: "Development", ConnectionStrings__DefaultConnection: setup.connectionString,
      Jwt__Key: jwtKey, Jwt__Issuer: "EvidenceQA", Jwt__Audience: "EvidenceQA" }
  });
  apiProcess.stdout.on("data", data => { log += data; }); apiProcess.stderr.on("data", data => { log += data; });
  for (let i = 0; i < 150 && !/Now listening on: (http:\/\/127.0.0.1:\d+)/.test(log); i++) await sleep(100);
  origin = log.match(/Now listening on: (http:\/\/127.0.0.1:\d+)/)?.[1]; assert.ok(origin, "Isolated API startup");
  const baseline = setup.counts;
  const invalid = ["text.jpg", "signature.png", "signature.jpg", "truncated.png", "truncated.jpg", "missing-end.png", "missing-end.jpg",
    "oversize.png", "wide.png", "pixels.png", "bad-idat.png", "bad-entropy.jpg", "animated.png", "unsupported.gif"];
  for (const name of invalid) {
    const status = ["text.jpg", "animated.png", "unsupported.gif", "signature.jpg"].includes(name) ? 415 : 400;
    // A JPEG signature is selected as JPEG, then fails the complete-container check (400).
    await upload(name, shipper, attempt, name === "signature.jpg" ? 400 : status);
    assert.equal(files(), 0, name + " must not leave a file");
    check("Reject " + name + " with 4xx and no file");
  }
  await upload("valid.png", admin, attempt, 403); check("Non-shipper cannot upload even with an administrator JWT");
  await fixture("Deny"); await upload("valid.png", shipper, attempt, 403);
  await upload("signature.png", shipper, attempt, 403); check("Missing permission is rejected before image processing");
  await fixture("Grant");
  await upload("valid.png", shipper, { ...attempt, id: 922337203685477 }, 404); check("Attempt ownership check remains active");
  await upload("valid.png", shipper, attempt, 400, { Latitude: "91", Longitude: "106" });
  await upload("valid.png", shipper, attempt, 400, { Latitude: "10" }); check("Coordinate range and pair validation remain active");
  assert.deepEqual((await fixture("Inspect")).counts, baseline); assert.equal(files(), 0);
  check("All rejected uploads leave evidence and success audit counts unchanged");
  for (const name of ["valid.png", "valid.jpg", "max-size.png"]) {
    const evidence = await upload(name, shipper, attempt, 201, { Latitude: "10", Longitude: "106" });
    const response = await fetch(origin + "/api/v1/orders/" + attempt.orderId + "/evidence/" + evidence.id + "/file", {
      headers: { Authorization: "Bearer " + jwt(shipper) }
    });
    assert.equal(response.status, 200); assert.equal(response.headers.get("content-type"), name.endsWith("jpg") ? "image/jpeg" : "image/png");
    assert.equal(response.headers.get("x-content-type-options"), "nosniff");
    assert.deepEqual(Buffer.from(await response.arrayBuffer()), fs.readFileSync(path.join(artifact, "images", name)));
    check("Upload and authenticated download " + name + " despite misleading filename/MIME");
  }
  const after = await fixture("Inspect");
  assert.equal(after.counts.evidence, baseline.evidence + 3); assert.equal(after.counts.uploads, baseline.uploads + 3); assert.equal(files(), 3);
  for (const file of after.files) assert.match(file.path, /^App_Data\/DeliveryEvidence\/\d+\/[a-f0-9]{32}\.(png|jpg)$/);
  check("Successful uploads produce exactly one evidence, file and audit each, with generated safe paths");
  await fixture("FailInsert"); await upload("valid.png", shipper, attempt, 404); await fixture("RestoreInsert");
  assert.deepEqual((await fixture("Inspect")).counts, after.counts); assert.equal(files(), 3);
  check("SQL failure before commit rolls back evidence/audit and deletes the staged file");
  fs.writeFileSync(path.join(root, "docs/evidence-upload-verification.json"), JSON.stringify({ mode: "Real HTTP/JWT/SQL/native decoder on isolated LocalDB and private content root", checks, count: checks.length }, null, 2) + "\n");
  console.log(JSON.stringify({ checks: checks.length }));
})().catch(error => { console.error(error.message); process.exitCode = 1; }).finally(async () => {
  if (apiProcess) { const exited = new Promise(resolve => apiProcess.once("exit", resolve)); apiProcess.kill(); await Promise.race([exited, sleep(5000)]); }
  if (created) await fixture("Drop");
  const absolute = path.resolve(contentRoot);
  if (path.dirname(absolute) !== path.resolve(artifact) || !/^run-[a-f0-9]{32}$/.test(path.basename(absolute))) throw Error("Unsafe test cleanup target");
  fs.rmSync(absolute, { recursive: true, force: true });
});
