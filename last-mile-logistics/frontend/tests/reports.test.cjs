"use strict";
const {test}=require("node:test"),assert=require("node:assert/strict"),fs=require("node:fs"),vm=require("node:vm"),path=require("node:path");
const window={AdminUI:{},Router:{}};
vm.runInNewContext(fs.readFileSync(path.join(__dirname,"../js/reports.js"),"utf8"),{window,Intl,Date});
const reports=window.ReportsPage;
test("report date validation includes leap days and exactly 366 calendar days",()=>{
  assert.equal(reports.validateDates("2024-02-29","2024-02-29"),"");
  assert.equal(reports.validateDates("2024-01-01","2024-12-31"),"");
  for(const range of [["2026-02-29","2026-03-01"],["2026-10-02","2026-10-01"],["2024-01-01","2025-01-01"],["1899-12-31","1900-01-01"],["9999-12-31","9999-12-31"],["","2026-10-01"]])assert(reports.validateDates(...range));
});
test("CSV preserves Vietnamese, CRLF, quotes and blocks formulas even after whitespace",()=>{
  const csv=reports.csvRows([["Bưu cục, \"Bình Tân\"","Dòng 1\nDòng 2",12.25],["=1+1"," \t@SUM(A1)","-42","+123","\r\n=1",-42]]);
  assert(csv.startsWith('\uFEFF"Bưu cục, ""Bình Tân"""'));
  assert(csv.includes('"Dòng 1\nDòng 2"'));assert(csv.endsWith('\r\n'));
  for(const value of ["'=1+1","' \t@SUM(A1)","'-42","'+123","'\r\n=1"])assert(csv.includes('"'+value+'"'));
  assert(csv.includes(',"-42"\r\n'));
});
