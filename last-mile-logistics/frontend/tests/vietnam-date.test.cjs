"use strict";
const { test } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const { execFileSync } = require("node:child_process");
const source = fs.readFileSync(path.join(__dirname, "../js/vietnam-date.js"), "utf8");

const cases = [
  ["2026-10-19T23:59:00+07:00", "2026-10-19", false],
  ["2026-10-20T00:00:00+07:00", "2026-10-20", true],
  ["2026-10-20T06:59:00+07:00", "2026-10-20", true],
  ["2026-10-20T23:59:59+07:00", "2026-10-20", true],
];

for (const [instant, today, expired] of cases) {
  test("Vietnam licence date at " + instant, () => {
    const window = {};
    // Exercise the actual default clock used by the form without changing the OS.
    class FrozenDate extends Date { constructor(...args) { super(...(args.length ? args : [instant])); } }
    vm.runInNewContext(source, { window, Date: FrozenDate, Intl });
    assert.equal(window.VietnamDate.today(), today);
    assert.equal(window.VietnamDate.isLicenseExpired("2026-10-19"), expired);
    assert.equal(window.VietnamDate.isLicenseExpired("2026-10-20"), false);
    assert.equal(window.VietnamDate.isLicenseExpired(null), false);
    assert.equal(window.VietnamDate.isLicenseExpired(""), false);
  });
}

test("Browser local time zones cannot change the Vietnam expiry result", () => {
  const script = `${source}; process.stdout.write(JSON.stringify([
    window.VietnamDate.today(new Date('2026-10-19T17:00:00Z')),
    window.VietnamDate.isLicenseExpired('2026-10-19',new Date('2026-10-19T17:00:00Z'))
  ]));`;
  for (const TZ of ["UTC", "America/Los_Angeles", "Asia/Tokyo", "Asia/Ho_Chi_Minh"]) {
    const result = execFileSync(process.execPath, ["-e", "global.window={};" + script], { env: { ...process.env, TZ }, encoding: "utf8" });
    assert.deepEqual(JSON.parse(result), ["2026-10-20", true], TZ);
  }
});

test("Vietnam date handles month/leap-day boundaries and equivalent instants", () => {
  const window = {}; vm.runInNewContext(source, { window, Date, Intl });
  for (const instant of ["2028-02-29T17:00:00Z", "2028-03-01T02:00:00+09:00", "2028-03-01T00:00:00+07:00"]) {
    assert.equal(window.VietnamDate.today(new Date(instant)), "2028-03-01");
    assert.equal(window.VietnamDate.isLicenseExpired("2028-02-29", new Date(instant)), true);
  }
});
