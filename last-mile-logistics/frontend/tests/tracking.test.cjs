"use strict";
const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm'),path=require('node:path');
const window={AdminUI:{},Router:{}};vm.runInNewContext(fs.readFileSync(path.join(__dirname,'../js/tracking.js'),'utf8'),{window,Date,Intl});
const T=window.TrackingPage;
test('Tracking times interpret SQL UTC exactly once and preserve explicit offsets',()=>{
 assert.equal(T.date('2026-09-30T16:59:00'),'30/09/2026, 23:59');
 assert.equal(T.date('2026-10-01T00:01:00+07:00'),'01/10/2026, 00:01');
 assert.equal(T.date('2026-09-30T17:01:00Z'),'01/10/2026, 00:01');
 assert.equal(T.date(null),'—');assert.equal(T.date('invalid'),'—');
});
test('Tracking GPS distinguishes missing, invalid, old, undated and future positions',()=>{
 const now=Date.parse('2026-10-17T00:10:00Z'),point={latitude:10,longitude:106,locationUpdatedAt:'2026-10-17T00:09:00'};
 assert.equal(T.interval,30000);assert.equal(T.locationState(point,now),'recent');
 assert.equal(T.locationState({...point,locationUpdatedAt:'2026-10-17T00:00:00Z'},now),'stale');
 assert.equal(T.locationState({...point,locationUpdatedAt:null},now),'undated');
 assert.equal(T.locationState({...point,locationUpdatedAt:'2026-10-17T01:00:00Z'},now),'future');
 for(const p of [null,{latitude:null,longitude:106},{latitude:91,longitude:106},{latitude:10,longitude:181},{latitude:'10',longitude:106}])assert.equal(T.locationState(p,now),'missing');
 assert.equal(T.coordinates({latitude:0,longitude:0}),true);
});
