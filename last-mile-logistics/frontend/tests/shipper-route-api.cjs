'use strict';
// Real HTTP + SignalR checks against an isolated GUID LocalDB database.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto'),assert=require('node:assert/strict');
const {spawn,execFile}=require('node:child_process'),{promisify}=require('node:util');
const root=path.resolve(__dirname,'../..'),backendDir=path.join(root,'backend/LastMile/LastMile.Api');
const artifacts=path.join(__dirname,'.artifacts/route-coverage'),database='CodexAdmin_'+crypto.randomBytes(16).toString('hex');
const apiBuild=process.env.SHIPPER_TEST_BUILD||path.join(artifacts,'build');
const key=crypto.randomBytes(64).toString('hex'),checks=[],sockets=[];let processApi,origin,fixture;
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
async function fixtureCommand(mode){const {stdout}=await promisify(execFile)('powershell.exe',['-NoProfile','-ExecutionPolicy','Bypass','-File',path.join(__dirname,'dispatch-fixture.ps1'),'-Mode',mode,'-Database',database],{windowsHide:true,maxBuffer:8*1024*1024});return JSON.parse(stdout);}
function token(actor){const h=Buffer.from(JSON.stringify({alg:'HS256',typ:'JWT'})).toString('base64url'),p=Buffer.from(JSON.stringify({iss:'ShipperQA',aud:'ShipperQA',exp:Math.floor(Date.now()/1000)+3600,sid:'0000000000000000'+BigInt(actor.accountId).toString(16).padStart(16,'0'),'http://schemas.xmlsoap.org/ws/2005/05/identity/claims/nameidentifier':String(actor.accountId),'http://schemas.microsoft.com/ws/2008/06/identity/claims/role':actor.role})).toString('base64url');return h+'.'+p+'.'+crypto.createHmac('sha256',key).update(h+'.'+p).digest('base64url');}
async function api(url,actor,method='GET',body,expected=200){const form=body instanceof FormData;const r=await fetch(origin+url,{method,headers:{...(form?{}:{'Content-Type':'application/json'}),...(actor?{Authorization:'Bearer '+token(actor)}:{})},body:body===undefined?undefined:form?body:JSON.stringify(body)});const text=await r.text();let data;try{data=text?JSON.parse(text):null}catch{throw Error(url+' returned non-JSON HTTP '+r.status)}assert.equal(r.status,expected,url+' '+JSON.stringify(data));return data;}
async function sql(query){assert.match(database,/^CodexAdmin_[a-f0-9]{32}$/);const {stdout}=await promisify(execFile)('sqlcmd',['-S','(localdb)\\MSSQLLocalDB','-d',database,'-E','-C','-I','-b','-h','-1','-W','-Q','SET NOCOUNT ON; '+query],{windowsHide:true,maxBuffer:1024*1024});return stdout.trim();}
async function connect(actor){const n=await api('/hubs/shipper/negotiate?negotiateVersion=1',actor,'POST');const events=[];const socket=new WebSocket(origin.replace('http:','ws:')+'/hubs/shipper?id='+encodeURIComponent(n.connectionToken)+'&access_token='+encodeURIComponent(token(actor)));sockets.push(socket);let ready=false;
socket.addEventListener('message',e=>{for(const part of String(e.data).split('\x1e').filter(Boolean)){const message=JSON.parse(part);if(message.type===1)events.push(message);else if(!message.type&&!message.error)ready=true;}});
await new Promise((resolve,reject)=>{socket.addEventListener('open',()=>{socket.send('{"protocol":"json","version":1}\x1e');resolve()},{once:true});socket.addEventListener('error',()=>reject(Error('SignalR WebSocket failed')),{once:true});});
for(let i=0;i<50&&!ready;i++)await sleep(100);assert(ready,'SignalR handshake');return events;}
async function event(events,target,assignmentId){for(let i=0;i<50;i++){const found=events.find(e=>e.target===target&&e.arguments[0].assignmentId===assignmentId);if(found)return found;await sleep(100);}assert.fail('Missing '+target+' for assignment '+assignmentId);}
(async()=>{
 fixture=await fixtureCommand('Create');let log='';
 processApi=spawn('dotnet',[path.join(apiBuild,'LastMile.Api.dll'),'--contentRoot',apiBuild,'--urls','http://127.0.0.1:0'],{cwd:backendDir,windowsHide:true,env:{...process.env,ASPNETCORE_ENVIRONMENT:'Development',ConnectionStrings__DefaultConnection:fixture.connectionString,Jwt__Key:key,Jwt__Issuer:'ShipperQA',Jwt__Audience:'ShipperQA'},stdio:['ignore','pipe','pipe']});
 processApi.stdout.on('data',d=>log+=d);processApi.stderr.on('data',d=>log+=d);
 for(let i=0;i<200&&!/Now listening on: (http:\/\/127.0.0.1:\d+)/.test(log);i++)await sleep(100);
 origin=log.match(/Now listening on: (http:\/\/127.0.0.1:\d+)/)?.[1];assert(origin,'Isolated API started');
 const admin=fixture.actors.find(a=>a.role==='ADMIN'),test=fixture.testData,driver=test.drivers[0],other=test.drivers[1];
 const shipper={accountId:driver.accountId,role:'SHIPPER'},otherShipper={accountId:other.accountId,role:'SHIPPER'},order=test.orders[0];
 const assignment=await api('/api/v1/dispatch/assignments',admin,'POST',{orderId:order.id,shipperId:driver.id,vehicleId:driver.vehicleId},201);
 const route='/api/v1/my/tasks/'+assignment.id+'/route',gps='?navigation=true&latitude=10.7769&longitude=106.7009';
 await api(route+gps,null,'GET',undefined,401);await api(route+gps,otherShipper,'GET',undefined,404);await api(route+gps,admin,'GET',undefined,404);
 await api(route+gps,shipper,'GET',undefined,404);
 checks.push('Route reads require the authenticated owning shipper and an accepted/current task');
 await api('/api/v1/my/tasks/'+assignment.id+'/accept',shipper,'POST');
 const auditBefore=await sql('SELECT COUNT(*) FROM dbo.NhatKyHoatDong;');
 const pickup=await api(route+gps,shipper);assert.equal(pickup.stage,'PICKUP');assert.equal(pickup.source,'LIVE_ROAD_GRAPH');assert.equal(pickup.orderId,order.id);
 assert(pickup.leg.distanceMeters>0&&pickup.leg.geometry.length>2);assert(pickup.originRoadDistanceMeters<=200);
 assert.equal(await sql('SELECT COUNT(*) FROM dbo.NhatKyHoatDong;'),auditBefore);assert.equal(await sql(`SELECT TrangThaiTonKho FROM dbo.TonKhoDonHang WHERE MaDonHang=${order.id};`),'STORED');
 checks.push('Reported GPS reaches the real assigned depot without exporting stock or writing audit/order state');
 assert.equal((await api(route+'?navigation=true&latitude=40&longitude=-74',shipper,'GET',undefined,409)).code,'ORIGIN_NOT_CONNECTED');
 assert.equal((await api(route,shipper,'GET',undefined,409)).code,'ORIGIN_REQUIRED');
 await api(route+'?latitude=10',shipper,'GET',undefined,400);
 const depot=JSON.parse(await sql(`SELECT ViDo latitude,KinhDo longitude FROM dbo.Kho WHERE MaKho=${test.warehouseId} FOR JSON PATH,WITHOUT_ARRAY_WRAPPER;`));
 try{await sql(`UPDATE dbo.Kho SET ViDo=40,KinhDo=-74 WHERE MaKho=${test.warehouseId};`);assert.equal((await api(route+gps,shipper,'GET',undefined,409)).code,'DESTINATION_NOT_CONNECTED');}
 finally{await sql(`UPDATE dbo.Kho SET ViDo=${depot.latitude},KinhDo=${depot.longitude} WHERE MaKho=${test.warehouseId};`);}
 checks.push('Unreachable origin/destination and missing GPS return distinct normal JSON 409 results; malformed input returns 400');
 const task=await api('/api/v1/my/tasks/'+assignment.id,shipper);
 await api('/api/v1/my/tasks/'+assignment.id+'/pickup',shipper,'POST',{trackingNumber:task.trackingNumber});
 const delivery=await api(route+gps,shipper);assert.equal(delivery.stage,'DELIVERY');assert.equal(delivery.source,'LIVE_ROAD_GRAPH');assert(delivery.leg.distanceMeters>0);
 checks.push('After real pickup the same reported GPS leads to the delivery point, not the warehouse');
 const permission=await sql("SELECT MaQuyen FROM dbo.Quyen WHERE KyHieuQuyen='NHIEMVU_XEM';"),role=await sql("SELECT MaVaiTro FROM dbo.VaiTro WHERE KyHieuVaiTro='SHIPPER';");
 try{await sql(`DELETE dbo.VaiTroQuyen WHERE MaVaiTro=${role} AND MaQuyen=${permission};`);await api(route+gps,shipper,'GET',undefined,404);}
 finally{await sql(`INSERT dbo.VaiTroQuyen(MaVaiTro,MaQuyen) VALUES(${role},${permission});`);}
 try{await sql(`UPDATE dbo.BuuCuc SET DangHoatDong=0 WHERE MaBuuCuc=${test.branchId};`);await api(route+gps,shipper,'GET',undefined,404);}
 finally{await sql(`UPDATE dbo.BuuCuc SET DangHoatDong=1 WHERE MaBuuCuc=${test.branchId};`);}
 checks.push('Revoked view permission or inactive current branch disables route reads immediately');
 const ids=test.orders.slice(2,4).map(o=>o.id);
 await sql(`UPDATE dbo.ChiTietDonHang SET KhoiLuongDonViKg=1 WHERE MaDonHang IN(${ids.join(',')}); UPDATE dbo.DonHang SET TongKhoiLuongKg=1 WHERE MaDonHang IN(${ids.join(',')});`);
 const plan=await api('/api/v1/dispatch/plans',admin,'POST',{warehouseId:test.warehouseId,orderIds:ids,shipperIds:[other.id],departureAt:new Date(Date.now()+600000).toISOString(),serviceMinutes:5,returnToDepot:true});
 assert.equal(plan.routes.length,1);
 const confirmation=await api('/api/v1/dispatch/plans/'+plan.id+'/confirm',admin,'POST');assert.equal(confirmation.trips.length,1);
 const plannedTask=(await api('/api/v1/my/tasks',otherShipper)).items.find(t=>ids.includes(t.orderId));assert(plannedTask);
 await api('/api/v1/my/tasks/'+plannedTask.id+'/accept',otherShipper,'POST');
 await sql(`UPDATE dbo.ChuyenGiaoHang SET ThoiGianBatDauDuKien=DATEADD(MINUTE,-1,SYSUTCDATETIME()) WHERE MaChuyenGiao=${plannedTask.tripId};`);
 await api('/api/v1/my/tasks/'+plannedTask.id+'/pickup',otherShipper,'POST',{trackingNumber:plannedTask.trackingNumber});
 const saved=await sql(`SELECT RouteJson FROM dbo.TripRouteGeometry WHERE TripId=${plannedTask.tripId};`),tripRoute='/api/v1/my/tasks/'+plannedTask.id+'/route';
 const overview=await api(tripRoute,otherShipper);assert.equal(overview.source,'ADMIN_PLAN');
 const index=plan.routes[0].stops.findIndex(s=>s.orderId===plannedTask.orderId);assert.equal(overview.stopSequence,index+1);assert.deepEqual(overview.leg.geometry,plan.routes[0].legs[index].geometry);
 const live=await api(tripRoute+gps,otherShipper);assert.equal(live.source,'LIVE_ROAD_GRAPH');assert.equal(live.stopSequence,overview.stopSequence);assert(live.leg.distanceMeters>0);
 assert.equal(await sql(`SELECT RouteJson FROM dbo.TripRouteGeometry WHERE TripId=${plannedTask.tripId};`),saved);
 checks.push('Saved admin geometry/order remain unchanged while live navigation from the reported GPS reads a new road leg');
 fs.writeFileSync(path.join(artifacts,'route-api-results.json'),JSON.stringify({checkedAt:new Date().toISOString(),checks,operationalWrites:false},null,2));
 console.log(JSON.stringify({passed:checks.length,checks}));
})().catch(e=>{console.error(e.stack);process.exitCode=1}).finally(async()=>{
 for(const socket of sockets)socket.close();processApi?.kill();await sleep(500);
 try{await fixtureCommand('Drop');console.log('Isolated database removed.')}catch{console.error('Test database cleanup failed: '+database);process.exitCode=1;}
});
