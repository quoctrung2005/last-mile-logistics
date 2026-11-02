"use strict";
const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const source=fs.readFileSync(path.join(__dirname,'../js/dispatch.js'),'utf8');
const body=source.slice(source.indexOf('  function depotIssue('),source.indexOf('  function capturePlanning('));
const issue=vm.runInNewContext('(()=>{'+body+';return depotIssue;})()');
const valid={latitude:10.81,longitude:106.60,coordinateSource:'Confirmed location'};
test('Depot UI distinguishes missing JSON fields, absent data and invalid coordinates',()=>{
  assert.match(issue({latitude:null}),/API chưa trả đủ/);
  assert.match(issue({...valid,latitude:null,longitude:null}),/chưa có tọa độ/);
  for(const changes of [{latitude:null},{longitude:null},{latitude:91},{longitude:181},{latitude:NaN},{longitude:'106.6'},{latitude:0,longitude:0}])
    assert.match(issue({...valid,...changes}),/không hợp lệ/);
  assert.equal(issue({latitude:10.81,longitude:106.6}),'');
  assert.equal(issue({...valid,coordinateSource:null}),'');
  assert.equal(issue(valid),'');
});
test('Depot UI does not mislabel verified off-network positions as missing data',()=>{
  assert.equal(issue({...valid,latitude:12,longitude:108}),'');
});
