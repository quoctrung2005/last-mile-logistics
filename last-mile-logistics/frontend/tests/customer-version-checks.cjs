"use strict";
const assert = require("node:assert/strict");
module.exports = async ({ api, admin, fixtureCommand, fixture, checks }) => {
  const read = () => api("/api/v1/customers/2?includeInactiveAddresses=true", admin);
  const customerBody = (c, extra = {}) => ({ fullName: c.fullName, phone: c.phone, email: c.email,
    type: c.type, isActive: c.isActive, expectedVersion: c.version, ...extra });
  const addressBody = (a, extra = {}) => ({ label: a.label, contactName: a.contactName, phone: a.phone,
    address: a.address, areaId: a.areaId, latitude: a.latitude, longitude: a.longitude,
    isDefault: a.isDefault, isActive: a.isActive, expectedVersion: a.version, ...extra });
  const version = value => assert.equal(Buffer.from(value, "base64").length, 8);
  assert.equal(fixture.migrationIdempotent, true);
  const a = await read(), b = await read();
  version(a.version); a.addresses.forEach(row => version(row.version));
  assert.equal(a.version, b.version);
  checks.push("Customer and address reads return independent 8-byte Base64 versions; migration rerun preserves versions");
  const address = a.addresses[0];
  for (const bad of [undefined, null, "", "not-base64", Buffer.alloc(7).toString("base64"), Buffer.alloc(9).toString("base64")]) {
    await api("/api/v1/customers/2", admin, "PUT", customerBody(a, { expectedVersion: bad }), 400);
    await api("/api/v1/customers/2/addresses/" + address.id, admin, "PUT", addressBody(address, { expectedVersion: bad }), 400);
  }
  checks.push("Both update APIs reject missing, null, malformed, 7-byte and 9-byte expectedVersion with 400");

  const saved = await api("/api/v1/customers/2", admin, "PUT", customerBody(a, { email: "qa.customer.a@example.test" }));
  version(saved.version); assert.notEqual(saved.version, a.version);
  assert.equal((await read()).version, saved.version);
  let before = await fixtureCommand("Inspect");
  await api("/api/v1/customers/2", admin, "PUT", customerBody(b, { email: "qa.customer.b@example.test" }), 409);
  let after = await fixtureCommand("Inspect"), current = await read();
  assert.equal(after.counts.audits, before.counts.audits);
  assert.equal(current.email, saved.email); assert.equal(current.version, saved.version);
  const customerAudit = after.audits.filter(row => row.action === "UPDATE_CUSTOMER" && row.objectId === "2").at(-1);
  assert.equal(JSON.parse(customerAudit.oldJson).version, a.version);
  assert.equal(JSON.parse(customerAudit.newJson).version, saved.version);
  checks.push("Customer stale update gets 409, preserves the winner and writes no success audit; successful audit includes before/after versions");

  const parentVersion = current.version;
  const old = current.addresses[0];
  const updated = await api("/api/v1/customers/2/addresses/" + old.id, admin, "PUT", addressBody(old, { address: "QA version A address", latitude: 10.123456, longitude: 106.123456 }));
  version(updated.version); assert.notEqual(updated.version, old.version);
  current = await read();
  assert.equal(current.version, parentVersion);
  assert.equal(current.addresses.find(row => row.id === old.id).version, updated.version);
  before = await fixtureCommand("Inspect");
  await api("/api/v1/customers/2/addresses/" + old.id, admin, "PUT", addressBody(old, { address: "QA stale B address" }), 409);
  after = await fixtureCommand("Inspect"); current = await read();
  assert.equal(after.counts.audits, before.counts.audits);
  assert.equal(current.addresses.find(row => row.id === old.id).address, updated.address);
  assert.equal(current.addresses.find(row => row.id === old.id).version, updated.version);
  checks.push("Address stale update gets 409 without data/audit changes; returned version matches post-coordinate-trigger version and parent version is unchanged");

  const extra1 = await api("/api/v1/customers/2/addresses", admin, "POST", { label: "QA Concurrent Default B", address: "QA default B", isDefault: false }, 201);
  const extra2 = await api("/api/v1/customers/2/addresses", admin, "POST", { label: "QA Concurrent Default C", address: "QA default C", isDefault: false }, 201);
  const beforeDefaults = await read();
  const first = beforeDefaults.addresses.find(row => row.id === extra1.id), second = beforeDefaults.addresses.find(row => row.id === extra2.id);
  const results = await Promise.all([
    api("/api/v1/customers/2/addresses/" + first.id, admin, "PUT", addressBody(first, { isDefault: true })),
    api("/api/v1/customers/2/addresses/" + second.id, admin, "PUT", addressBody(second, { isDefault: true }))
  ]);
  results.forEach(row => { version(row.version); row.affectedAddresses.forEach(item => version(item.version)); });
  current = await read();
  assert.equal(current.addresses.filter(row => row.isActive && row.isDefault).length, 1);
  const oldDefault = beforeDefaults.addresses.find(row => row.isDefault);
  const demoted = current.addresses.find(row => row.id === oldDefault.id);
  assert.equal(demoted.isDefault, false); assert.notEqual(demoted.version, oldDefault.version);
  before = await fixtureCommand("Inspect");
  await api("/api/v1/customers/2/addresses/" + oldDefault.id, admin, "PUT", addressBody(oldDefault), 409);
  after = await fixtureCommand("Inspect"); assert.equal(after.counts.audits, before.counts.audits);
  const defaultAudit = after.audits.filter(row => row.action === "UPDATE_CUSTOMER_ADDRESS").at(-1);
  assert.ok(JSON.parse(defaultAudit.oldJson).affectedAddresses.length >= 2);
  assert.ok(JSON.parse(defaultAudit.newJson).affectedAddresses.length >= 2);
  checks.push("Concurrent default changes serialize to exactly one default; implicitly demoted addresses get new versions and before/after audit entries");

  const defaultBeforeCreate = current.addresses.find(row => row.isDefault);
  await api("/api/v1/customers/2/addresses", admin, "POST", { label: "QA new default", address: "QA created default", isDefault: true }, 201);
  current = await read();
  assert.notEqual(current.addresses.find(row => row.id === defaultBeforeCreate.id).version, defaultBeforeCreate.version);
  assert.equal(current.addresses.filter(row => row.isActive && row.isDefault).length, 1);
  checks.push("Creating a default address also advances the previous default's version atomically");
};
