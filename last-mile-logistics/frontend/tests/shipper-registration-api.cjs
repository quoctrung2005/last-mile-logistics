'use strict';
// Every write is confined to a GUID LocalDB fixture; credentials stay in memory.
const assert=require('node:assert/strict'),crypto=require('node:crypto'),fs=require('node:fs'),path=require('node:path');
const {spawn,execFile}=require('node:child_process'),{promisify}=require('node:util');
const root=path.resolve(__dirname,'../..'),database='CodexAdmin_'+crypto.randomBytes(16).toString('hex');
const build=path.join(__dirname,'.artifacts/shipper-registration/build'),key=crypto.randomBytes(64).toString('hex'),checks=[];
let child,origin,fixture;
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
async function setup(mode){try{const {stdout}=await promisify(execFile)('powershell.exe',['-NoProfile','-ExecutionPolicy','Bypass','-File',path.join(__dirname,'dispatch-fixture.ps1'),'-Mode',mode,'-Database',database],{windowsHide:true,maxBuffer:8*1024*1024});return JSON.parse(stdout);}catch{throw Error('Isolated registration fixture failed: '+mode);}}
async function sql(query){assert.match(database,/^CodexAdmin_[a-f0-9]{32}$/);const{stdout}=await promisify(execFile)('sqlcmd',['-S','(localdb)\\MSSQLLocalDB','-d',database,'-E','-C','-I','-b','-h','-1','-W','-Q','SET NOCOUNT ON;'+query],{windowsHide:true,maxBuffer:1024*1024});return stdout.trim();}
function jwt(actor){const a=Buffer.from(JSON.stringify({alg:'HS256',typ:'JWT'})).toString('base64url'),b=Buffer.from(JSON.stringify({iss:'RegistrationQA',aud:'RegistrationQA',exp:Math.floor(Date.now()/1000)+3600,sid:'0000000000000000'+BigInt(actor.accountId).toString(16).padStart(16,'0'),'http://schemas.xmlsoap.org/ws/2005/05/identity/claims/nameidentifier':String(actor.accountId),'http://schemas.microsoft.com/ws/2008/06/identity/claims/role':actor.role,'http://schemas.xmlsoap.org/ws/2005/05/identity/claims/name':actor.username,fullName:actor.fullName,branchId:actor.branchId==null?undefined:String(actor.branchId)})).toString('base64url');return a+'.'+b+'.'+crypto.createHmac('sha256',key).update(a+'.'+b).digest('base64url');}
async function request(url,{actor,token,method='GET',body,expected=200,session}={}){
 const form=body instanceof FormData;const response=await fetch(origin+url,{method,headers:{...(form?{}:{'Content-Type':'application/json'}),...(actor?{Authorization:'Bearer '+jwt(actor)}:{}),...(session?{Authorization:'Bearer '+session.accessToken}:{}),...(token?{'X-Application-Token':token}:{})},body:body===undefined?undefined:form?body:JSON.stringify(body)});
 assert([].concat(expected).includes(response.status),method+' '+url+' unexpected HTTP '+response.status);
 const text=await response.text();let data;try{data=text?JSON.parse(text):null;}catch{throw Error(url+' returned non-JSON');}return{status:response.status,data};
}
const photo=Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAEAAAAAwAQMAAACbhe5cAAAAIGNIUk0AAHomAACAhAAA+gAAAIDoAAB1MAAA6mAAADqYAAAXcJy6UTwAAAADUExURWSV7TopvrwAAAABYktHRACIBR1IAAAAB3RJTUUH6goTATgxNJSkYgAAACV0RVh0ZGF0ZTpjcmVhdGUAMjAyNi0xMC0xOVQwMTo1Njo0OSswMDowMPHajAAAAAAldEVYdGRhdGU6bW9kaWZ5ADIwMjYtMTAtMTlUMDE6NTY6NDkrMDA6MDCAhzS8AAAAKHRFWHRkYXRlOnRpbWVzdGFtcAAyMDI2LTEwLTE5VDAxOjU2OjQ5KzAwOjAw15IVYwAAAA5JREFUGNNjYBgFQwkAAAGwAAGHcNqeAAAAAElFTkSuQmCC','base64');
const prefix='/api/v1/shipper-registrations',adminPrefix='/api/v1/admin/shipper-registrations';
function applicant(branchId,areaId){const suffix=String(crypto.randomInt(10000000,99999999));return{id:crypto.randomUUID(),token:crypto.randomBytes(32).toString('base64url'),fields:{Username:'qa.reg.'+suffix,Password:'Qa!'+crypto.randomBytes(18).toString('hex'),FullName:'QA Registration '+suffix,Phone:'09'+suffix,Email:'qa.reg.'+suffix+'@example.invalid',IdentityNumber:'0000'+suffix,LicenseNumber:'QA-'+suffix,LicenseExpiresAt:'2035-01-01',BranchId:String(branchId),AreaId:String(areaId),VehicleType:'MOTORBIKE',LicensePlate:'QA-'+suffix,Role:'ADMIN'}};}
function form(candidate,{missing=false,bad=false,version}={}){const body=new FormData();for(const[k,v]of Object.entries({...candidate.fields,ConfirmPassword:candidate.fields.Password,ApplicationId:candidate.id,...(version?{ExpectedVersion:version}:{})}))body.set(k,v);for(const kind of ['IdentityFront','IdentityBack','LicensePhoto','Portrait']){if(missing&&kind==='Portrait')continue;body.set(kind,new Blob([bad&&kind==='Portrait'?Buffer.from('<svg/>'):photo],{type:'image/png'}),kind+'.png');}return body;}
const status=c=>request(prefix+'/'+c.id+'/status',{token:c.token}).then(r=>r.data);
const send=(c,options={})=>request(prefix+(options.version?'/'+c.id:''),{token:c.token,method:options.version?'PUT':'POST',body:form(c,options),expected:options.expected||200}).then(r=>r.data);
function review(actor,id,data,action,reason,commandId=crypto.randomUUID(),expected=200){return request(adminPrefix+'/'+id+'/review',{actor,method:'POST',body:{action,reason,commandId,expectedVersion:data.version},expected});}
function check(message){checks.push(message);console.log('PASS '+message);}
(async()=>{
 fixture=await setup('Create');let log='';child=spawn('dotnet',[path.join(build,'LastMile.Api.dll'),'--urls','http://127.0.0.1:0'],{cwd:path.join(root,'backend/LastMile/LastMile.Api'),windowsHide:true,stdio:['ignore','pipe','pipe'],env:{...process.env,ASPNETCORE_ENVIRONMENT:'Development',ConnectionStrings__DefaultConnection:fixture.connectionString,Jwt__Key:key,Jwt__Issuer:'RegistrationQA',Jwt__Audience:'RegistrationQA'}});
 child.stdout.on('data',v=>log+=v);child.stderr.on('data',v=>log+=v);for(let i=0;i<150&&!/Now listening on: (http:\/\/127.0.0.1:\d+)/.test(log);i++)await sleep(100);origin=log.match(/Now listening on: (http:\/\/127.0.0.1:\d+)/)?.[1];assert(origin,'Isolated API startup');
 const admin=fixture.actors.find(a=>a.role==='ADMIN'),driver={accountId:fixture.testData.drivers[0].accountId,role:'SHIPPER'};
 const catalog=(await request(prefix+'/catalogs')).data;assert(Array.isArray(catalog.items));assert(catalog.items.length);
 const branch=catalog.items.find(b=>b.id===fixture.testData.branchId);assert(branch?.areas.length);
 const candidate=applicant(branch.id,branch.areas[0].id);
 await request(prefix+'/'+candidate.id+'/status',{expected:404});await request(adminPrefix,{expected:401});await request(adminPrefix,{actor:driver,expected:403});
 await send(candidate,{missing:true,expected:400});await send(candidate,{bad:true,expected:415});
 assert.equal(await sql(`SELECT COUNT(*) FROM dbo.ShipperRegistration WHERE Id='${candidate.id}';`),'0');
 check('Catalogs use real active branches/areas; missing or invalid documents create no registration; private admin access is enforced');
 let pending=await send(candidate);assert.equal(pending.status,'PENDING');assert.equal(pending.documents.length,4);
 assert.equal(await sql(`SELECT COUNT(*) FROM dbo.TaiKhoan WHERE TenDangNhap='${candidate.fields.Username}';`),'0');
 await request('/api/v1/auth/login',{method:'POST',body:{username:candidate.fields.Username,password:candidate.fields.Password},expected:401});
 await send(candidate);assert.equal(await sql(`SELECT COUNT(*) FROM dbo.ShipperRegistrationEvent WHERE RegistrationId='${candidate.id}';`),'1');
 const collision={...candidate,id:crypto.randomUUID(),token:crypto.randomBytes(32).toString('base64url')};await send(collision,{expected:409});
 await request(prefix+'/'+candidate.id+'/status',{token:collision.token,expected:404});
 const own=await status(candidate);assert.equal(own.id.toLowerCase(),candidate.id);for(const forbidden of ['password','passwordHash','token','tokenHash'])assert.equal(forbidden in own,false);
 check('Submission stores a pending application without granting login; replay is idempotent, duplicate identity is blocked and tracking requires its secret');
 const detail=(await request(adminPrefix+'/'+candidate.id,{actor:admin})).data;assert.equal(detail.fullName,candidate.fields.FullName);
 const file=adminPrefix+'/'+candidate.id+'/documents/IDENTITY_FRONT';assert.equal((await fetch(origin+file)).status,401);assert.equal((await fetch(origin+file,{headers:{Authorization:'Bearer '+jwt(driver)}})).status,403);
 const image=await fetch(origin+file,{headers:{Authorization:'Bearer '+jwt(admin)}});assert.equal(image.status,200);assert.equal(image.headers.get('content-type'),'image/png');assert.equal((await image.arrayBuffer()).byteLength,photo.length);assert.match(image.headers.get('cache-control'),/no-store/);
 await review(driver,candidate.id,pending,'APPROVE',null,crypto.randomUUID(),403);
 await review(admin,candidate.id,pending,'NEEDS_INFO','',crypto.randomUUID(),400);
 await sql(`UPDATE dbo.ShipperRegistration SET LicenseExpiresAt='2020-01-01' WHERE Id='${candidate.id}';`);pending=await status(candidate);
 await review(admin,candidate.id,pending,'APPROVE',null,crypto.randomUUID(),409);
 await require('./registration-browser-check.cjs')(origin,{accessToken:jwt(admin),refreshToken:crypto.randomBytes(32).toString('base64url'),expiresAt:new Date(Date.now()+3600000).toISOString(),user:admin},candidate.fields.Username);
 check('Admin browser shows private photos, requires a review reason, submits once and fits a mobile viewport');
 const needs=await status(candidate);assert.equal(needs.status,'NEEDS_INFO');assert(needs.reviewReason);
 check('Admin can read private proof and request supplements; wrong role, missing reason and expired licence cannot approve');
 candidate.fields.FullName='QA Supplemented Driver';pending=await send(candidate,{version:needs.version});assert.equal(pending.status,'PENDING');assert.notEqual(pending.version,needs.version);
 await send(candidate,{version:needs.version,expected:409});
 const command1=crypto.randomUUID(),command2=crypto.randomUUID();
 const results=await Promise.all([review(admin,candidate.id,pending,'APPROVE',null,command1,[200,409]),review(admin,candidate.id,pending,'APPROVE',null,command2,[200,409])]);
 assert.deepEqual(results.map(r=>r.status).sort(),[200,409]);const winner=results[0].status===200?command1:command2;
 const approved=await status(candidate);assert.equal(approved.status,'APPROVED');assert(approved.accountId>0&&approved.shipperId>0);
 await review(admin,candidate.id,pending,'APPROVE',null,winner);assert.equal(await sql(`SELECT COUNT(*) FROM dbo.TaiKhoan WHERE TenDangNhap='${candidate.fields.Username}';`),'1');
 assert.equal(await sql(`SELECT COUNT(*) FROM dbo.ShipperRegistration WHERE Id='${candidate.id}' AND PasswordHash IS NULL;`),'1');
 const session=(await request('/api/v1/auth/login',{method:'POST',body:{username:candidate.fields.Username,password:candidate.fields.Password}})).data;
 assert.equal(session.user.role,'SHIPPER');const profile=(await request('/api/v1/my/profile',{session})).data;assert.equal(profile.fullName,'QA Supplemented Driver');assert.equal(profile.availability,'OFFLINE');assert.equal(profile.currentVehicle,null);assert.equal(profile.areas[0].id,Number(candidate.fields.AreaId));
 check('Supplement submission checks version; concurrent approval creates exactly one SHIPPER account/profile and area; declared vehicle does not auto-assign a fleet vehicle');
 const rejected=applicant(branch.id,branch.areas[0].id),rejectPending=await send(rejected);await review(admin,rejected.id,rejectPending,'REJECT','QA: hồ sơ không đạt.');
 assert.equal((await status(rejected)).status,'REJECTED');await request('/api/v1/auth/login',{method:'POST',body:{username:rejected.fields.Username,password:rejected.fields.Password},expected:401});
 await send(rejected,{version:(await status(rejected)).version,expected:409});
 check('Rejection includes applicant-visible reason, never grants a login and cannot be overwritten through resubmission');
 const before=await sql('SELECT COUNT(*) FROM dbo.ShipperRegistration;');const migration=fs.readFileSync(path.join(root,'database/migrations/20261030_shipper_registrations.sql'),'utf8').replaceAll("N'QLGiaoHangChangCuoi'","N'"+database+"'");await sql(migration);await sql(migration);assert.equal(await sql('SELECT COUNT(*) FROM dbo.ShipperRegistration;'),before);
 check('Additive registration migration is repeatable without erasing existing submissions');
 console.log(JSON.stringify({passed:checks.length,checks,operationalDatabaseWrites:false}));
})().catch(e=>{console.error(e.stack);process.exitCode=1;}).finally(async()=>{
 if(child&&child.exitCode===null){const stopped=new Promise(r=>child.once('exit',r));child.kill();await stopped;}
 try{await setup('Drop');console.log('Isolated registration database removed.');}catch{console.error('Isolated registration database cleanup failed.');process.exitCode=1;}
});
