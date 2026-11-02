'use strict';
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict'),crypto=require('node:crypto');
const {spawn}=require('node:child_process');
const {createServer}=require('../dev-server.cjs');
const sleep=ms=>new Promise(resolve=>setTimeout(resolve,ms));
module.exports=async function checkRegistrationBrowser(apiOrigin,session,username){
 const artifact=path.join(__dirname,'.artifacts/shipper-registration'),profile=path.join(artifact,'browser-'+crypto.randomUUID());
 fs.mkdirSync(profile,{recursive:true});
 let server,edge,socket,sequence=0;const pending=new Map();
 try{
  server=createServer(new URL(apiOrigin));await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  const origin='http://127.0.0.1:'+server.address().port;
  edge=spawn('C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',['--headless','--disable-gpu','--no-first-run','--no-default-browser-check','--remote-debugging-address=127.0.0.1','--remote-debugging-port=0','--user-data-dir='+profile,'about:blank'],{windowsHide:true,stdio:'ignore'});
  const portFile=path.join(profile,'DevToolsActivePort');for(let i=0;i<150&&!fs.existsSync(portFile);i++)await sleep(100);
  assert(fs.existsSync(portFile),'Headless QA browser startup');
  const port=fs.readFileSync(portFile,'utf8').split(/\r?\n/)[0];
  const tabs=await(await fetch('http://127.0.0.1:'+port+'/json')).json();
  socket=new WebSocket(tabs.find(tab=>tab.type==='page').webSocketDebuggerUrl);
  await new Promise((resolve,reject)=>{socket.addEventListener('open',resolve,{once:true});socket.addEventListener('error',reject,{once:true});});
  socket.addEventListener('message',event=>{const message=JSON.parse(event.data);if(message.id&&pending.has(message.id)){const entry=pending.get(message.id);pending.delete(message.id);message.error?entry.reject(Error(message.error.message)):entry.resolve(message.result);}});
  const send=(method,params={})=>new Promise((resolve,reject)=>{const id=++sequence;pending.set(id,{resolve,reject});socket.send(JSON.stringify({id,method,params}));});
  const evaluate=async expression=>{const result=await send('Runtime.evaluate',{expression,awaitPromise:true,returnByValue:true});if(result.exceptionDetails)throw Error('Browser evaluation failed');return result.result.value;};
  const until=async expression=>{for(let i=0;i<150;i++){if(await evaluate(expression))return;await sleep(100);}throw Error('Registration browser timed out: '+expression.replace(/qa\.reg\.[0-9]+/g,'QA username'));};
  await send('Page.enable');await send('Runtime.enable');
  await send('Emulation.setDeviceMetricsOverride',{width:1440,height:1000,deviceScaleFactor:1,mobile:false});
  await send('Page.addScriptToEvaluateOnNewDocument',{source:`if(location.origin===${JSON.stringify(origin)}){sessionStorage.setItem('tvd.session',${JSON.stringify(JSON.stringify(session))});window.qaRegistration={errors:[],writes:0};addEventListener('error',e=>qaRegistration.errors.push(e.message));addEventListener('unhandledrejection',()=>qaRegistration.errors.push('Unhandled promise'));const original=fetch;window.fetch=(...args)=>{if(String(args[0]).includes('/review')&&args[1]?.method==='POST')qaRegistration.writes++;return original(...args);};}`});
  await send('Page.navigate',{url:origin+'/#/fleet/registrations'});
  await until(`!!Array.from(document.querySelectorAll('table tbody tr')).find(row=>row.textContent.includes(${JSON.stringify(username)}))`);
  await evaluate(`Array.from(document.querySelectorAll('table tbody tr')).find(row=>row.textContent.includes(${JSON.stringify(username)})).querySelector('button').click()`);
  await until("document.querySelectorAll('dialog img').length===4 && Array.from(document.querySelectorAll('dialog img')).every(image=>image.complete&&image.naturalWidth>0)");
  assert.equal(await evaluate("document.querySelector('dialog').textContent.includes('kiểm tra thủ công')"),true);
  const desktop=await send('Page.captureScreenshot',{format:'png',captureBeyondViewport:false});fs.writeFileSync(path.join(artifact,'registration-admin-desktop.png'),Buffer.from(desktop.data,'base64'));
  await evaluate("document.querySelector('dialog form').requestSubmit()");
  await until("document.querySelector('dialog textarea').classList.contains('is-invalid')");
  assert.equal(await evaluate('qaRegistration.writes'),0);
  await evaluate("const reason=document.querySelector('dialog textarea');reason.value='QA: bổ sung giấy phép và ảnh rõ.';reason.dispatchEvent(new Event('input',{bubbles:true}));document.querySelector('dialog form').requestSubmit()");
  await until("!document.querySelector('dialog') && document.body.textContent.includes('Không có hồ sơ phù hợp.')");
  assert.equal(await evaluate('qaRegistration.writes'),1);
  await send('Emulation.setDeviceMetricsOverride',{width:390,height:844,deviceScaleFactor:1,mobile:true});
  await evaluate("const status=document.querySelector('select[name=status]');status.value='NEEDS_INFO';status.closest('form').requestSubmit()");
  await until("document.querySelectorAll('table tbody button').length===1");
  await evaluate("document.querySelector('table tbody button').click()");
  await until("document.querySelectorAll('dialog img').length===4");
  assert.equal(await evaluate('document.documentElement.scrollWidth<=innerWidth+1'),true,'Mobile page has no horizontal overflow');
  const mobile=await send('Page.captureScreenshot',{format:'png'});fs.writeFileSync(path.join(artifact,'registration-admin-mobile.png'),Buffer.from(mobile.data,'base64'));
  assert.deepEqual(await evaluate('qaRegistration.errors'),[],'No frontend errors');
  return {desktop:path.join(artifact,'registration-admin-desktop.png'),mobile:path.join(artifact,'registration-admin-mobile.png')};
 }finally{
  socket?.close();
  if(edge&&edge.exitCode===null){const stopped=new Promise(resolve=>edge.once('exit',resolve));edge.kill();await stopped;}
  if(server)await new Promise(resolve=>server.close(resolve));
 }
};
