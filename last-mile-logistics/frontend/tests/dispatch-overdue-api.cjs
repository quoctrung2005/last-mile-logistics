"use strict";
// Opt-in integration checks; all writes go to a GUID LocalDB test database.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto'),assert=require('node:assert/strict');
const {spawn,execFile}=require('node:child_process'),{promisify}=require('node:util'),{createServer}=require('../dev-server.cjs');
const phase='dispatch';
const root=path.resolve(__dirname,'../..'),backendDir=path.join(root,'backend/LastMile/LastMile.Api'),artifactRoot=path.join(__dirname,'.artifacts/dispatch-deadlines');
const database='CodexAdmin_'+crypto.randomBytes(16).toString('hex'),profile=path.join(artifactRoot,database),key=crypto.randomBytes(64).toString('hex');
const checks=[],errors=[],networkFailures=[],pending=new Map();let backendLog='';let fixture,apiProcess,server,edge,socket,origin,scriptId,id=0;const answers=[];
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
async function fixtureCommand(mode){const {stdout}=await promisify(execFile)('powershell.exe',['-NoProfile','-ExecutionPolicy','Bypass','-File',path.join(__dirname,'dispatch-fixture.ps1'),'-Mode',mode,'-Database',database],{windowsHide:true,maxBuffer:8*1024*1024});return JSON.parse(stdout);}
function session(actor){const exp=Math.floor(Date.now()/1000)+3600,h=Buffer.from(JSON.stringify({alg:'HS256',typ:'JWT'})).toString('base64url'),p=Buffer.from(JSON.stringify({iss:'AdminQA',aud:'AdminQA',exp,nbf:Math.floor(Date.now()/1000)-10,sid:'0000000000000000'+BigInt(actor.accountId).toString(16).padStart(16,'0'),'http://schemas.xmlsoap.org/ws/2005/05/identity/claims/nameidentifier':String(actor.accountId),'http://schemas.xmlsoap.org/ws/2005/05/identity/claims/name':actor.username,'http://schemas.microsoft.com/ws/2008/06/identity/claims/role':actor.role,fullName:actor.fullName,branchId:actor.branchId==null?undefined:String(actor.branchId)})).toString('base64url');return {accessToken:h+'.'+p+'.'+crypto.createHmac('sha256',key).update(h+'.'+p).digest('base64url'),refreshToken:crypto.randomBytes(32).toString('base64url'),expiresAt:new Date(exp*1000).toISOString(),user:actor};}
async function api(url,actor,method='GET',body,expected=200){const r=await fetch(origin+url,{method,headers:{'Content-Type':'application/json',...(actor?{Authorization:'Bearer '+(actor.accessToken||session(actor).accessToken)}:{})},body:body===undefined?undefined:JSON.stringify(body)});const raw=await r.text();let data;try{data=raw?JSON.parse(raw):null}catch{const sqlError=raw.match(/(?:Microsoft.Data.SqlClient.SqlException[^\r\n]*|Invalid column name[^\r\n]*|Incorrect syntax[^\r\n]*)/);throw Error(url+' non-JSON HTTP '+r.status+' '+(sqlError?.[0]||'See backend logs'))}assert(Array.isArray(expected)?expected.includes(r.status):r.status===expected,url+' '+(/\/auth\//.test(url)?'[auth response omitted]':JSON.stringify(data)));return Array.isArray(expected)?{...data,_httpStatus:r.status}:data;}
(async()=>{
 fixture=await fixtureCommand('Create');let log='';
 apiProcess=spawn('dotnet',[path.join(artifactRoot,'build/LastMile.Api.dll'),'--urls','http://127.0.0.1:0'],{cwd:backendDir,windowsHide:true,env:{...process.env,ASPNETCORE_ENVIRONMENT:'Development',ConnectionStrings__DefaultConnection:fixture.connectionString,Jwt__Key:key,Jwt__Issuer:'AdminQA',Jwt__Audience:'AdminQA'},stdio:['ignore','pipe','pipe']});
 apiProcess.stdout.on('data',d=>log+=d.toString());apiProcess.stderr.on('data',d=>log+=d.toString());
 for(let n=0;n<150&&!/Now listening on: (http:\/\/127.0.0.1:\d+)/.test(log);n++)await sleep(100);
 const match=log.match(/Now listening on: (http:\/\/127.0.0.1:\d+)/);if(!match)throw Error('Isolated API did not start');
 server=createServer(new URL(match[1]));await new Promise(r=>server.listen(0,'127.0.0.1',r));origin='http://127.0.0.1:'+server.address().port;
 const admin=fixture.actors.find(a=>a.role==='ADMIN'),denied=fixture.actors.find(a=>a.role==='ACCOUNTANT'),test=fixture.testData;
 async function sql(text){assert.match(database,/^CodexAdmin_[a-f0-9]{32}$/);const {stdout}=await promisify(execFile)('sqlcmd',['-S','(localdb)\\MSSQLLocalDB','-d',database,'-E','-C','-I','-b','-h','-1','-W','-Q','SET NOCOUNT ON; '+text],{windowsHide:true,maxBuffer:1024*1024});return stdout.trim();}
 async function expire(id){await sql(`UPDATE dbo.DonHang SET ThoiGianSanSang=DATEADD(DAY,-2,SYSUTCDATETIME()),ThoiGianYeuCauGiao=DATEADD(DAY,-1,SYSUTCDATETIME()),ThoiGianDuKienGiao=DATEADD(MINUTE,-1,SYSUTCDATETIME()) WHERE MaDonHang=${id};`);}
 const pathFor=id=>'/api/v1/dispatch/orders/'+id+'/resolve-overdue';
 const keep={decision:'KEEP',contactNote:'Isolated QA: customer confirmed acceptance',deliveryDeadline:new Date(Date.now()+86400000).toISOString()};
 await api(pathFor(test.orders[0].id),denied,'POST',keep,403);checks.push('Account without order update permission cannot resolve overdue orders');
 await api(pathFor(test.orders[0].id),admin,'POST',{...keep,contactNote:' '},400);
 await api(pathFor(test.orders[0].id),admin,'POST',{...keep,deliveryDeadline:new Date(0).toISOString()},400);
 await api(pathFor(test.orders[0].id),admin,'POST',keep,409);checks.push('Contact note and future deadline are required; an on-time order is rejected');
 await expire(test.orders[0].id);
 const visible=await api('/api/v1/dispatch/orders?ids='+test.orders[0].id,admin);assert.equal(visible.totalItems,1);checks.push('An overdue order remains visible in the dispatch queue');
 await api(pathFor(test.orders[0].id),admin,'POST',keep);
 const updated=(await api('/api/v1/dispatch/orders?ids='+test.orders[0].id,admin)).items[0];assert.equal(updated.priority,1);assert.equal(updated.status,'WAITING_ASSIGNMENT');assert(new Date(updated.expectedDeliveryAt+'Z')>new Date());
 await api(pathFor(test.orders[0].id),admin,'POST',keep,409);checks.push('Customer keeps order: highest priority, new future deadline, still waiting; replay rejected');
 await expire(test.orders[1].id);
 const order=(await api('/api/v1/dispatch/orders?ids='+test.orders[1].id,admin)).items[0];
 const locations=await api('/api/v1/warehouses/'+test.warehouseId+'/locations',admin);
 const target=locations.find(n=>n.id!==order.locationId);assert(target);
 const cancel={decision:'CANCEL',contactNote:'Isolated QA: customer confirmed cancellation',locationId:order.locationId};
 await api(pathFor(order.id),admin,'POST',cancel,409);
 await api(pathFor(order.id),admin,'POST',{...cancel,locationId:999999999},409);checks.push('Cancellation rejects source location and an invalid destination');
 const before=Number(await sql('SELECT COUNT(*) FROM dbo.GiaoDichKho;'));
 const result=await api(pathFor(order.id),admin,'POST',{...cancel,locationId:target.id});assert(result.transactionId>0);
 const verified=await sql(`SELECT CONCAT(s.KyHieuTrangThai,'|',t.TrangThaiTonKho,'|',t.MaViTriLuuKho) FROM dbo.DonHang d JOIN dbo.TrangThaiDonHang s ON s.MaTrangThaiDonHang=d.MaTrangThaiHienTai JOIN dbo.TonKhoDonHang t ON t.MaDonHang=d.MaDonHang WHERE d.MaDonHang=${order.id};`);
 assert.equal(verified,'CANCELLED|STORED|'+target.id);assert.equal(Number(await sql('SELECT COUNT(*) FROM dbo.GiaoDichKho;')),before+1);
 await api(pathFor(order.id),admin,'POST',{...cancel,locationId:target.id},409);assert.equal(Number(await sql('SELECT COUNT(*) FROM dbo.GiaoDichKho;')),before+1);
 checks.push('Customer cancels: cancelled order, stock retained at destination, one move slip, replay cannot duplicate it');
 const visibleAfter=await api('/api/v1/dispatch/orders?ids='+order.id,admin);assert.equal(visibleAfter.totalItems,0);
 checks.push('A cancelled order leaves dispatch only after customer confirmation');
 fs.writeFileSync(path.join(artifactRoot,'customer-resolution-results.json'),JSON.stringify({checkedAt:new Date().toISOString(),checks,operationalWrites:false},null,2));
 console.log(JSON.stringify({passed:checks.length,checks}));
})().catch(e=>{console.error(e.message);process.exitCode=1}).finally(async()=>{
 if(server)await new Promise(r=>server.close(r));apiProcess?.kill();
 try{await fixtureCommand('Drop');console.log('Isolated database removed.')}catch{console.error('Test database cleanup failed: '+database);process.exitCode=1;}
});