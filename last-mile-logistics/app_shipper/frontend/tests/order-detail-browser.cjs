"use strict";
const fs = require('node:fs'), path = require('node:path'), http = require('node:http');
const { spawn, execFile } = require('node:child_process');
const { promisify } = require('node:util');
const assert = require('node:assert/strict');
// Opt-in, read-only layout QA. Reads exactly IDs 1 and 2 into memory and saves only screenshots/metrics.
// The auth/transport adapter below is isolated to this test server, never shipped in frontend/index.html.
const root = path.resolve(__dirname, '../..');
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
const profile = path.join(__dirname, '.artifacts/order-detail', 'edge-profile');
const proxy = require('../dev-server.cjs').createServer(new URL('http://localhost:5038'));
let edge, socket, id = 0; const pending = new Map(), errors = [], events = [];
const result = { mode:'component QA with exactly two existing SQL orders; auth and API transport are test adapters, no JWT or payload persisted', viewports:[], checks:[], consoleErrors:errors };
function send(method, params = {}) { return new Promise((resolve,reject) => { const key=++id; pending.set(key,{resolve,reject}); socket.send(JSON.stringify({id:key,method,params})); }); }
async function evaluate(expression) { const value=await send('Runtime.evaluate',{expression,awaitPromise:true,returnByValue:true}); if(value.exceptionDetails) throw new Error(value.exceptionDetails.text + ' ' + (value.exceptionDetails.exception?.description||'')); return value.result.value; }
async function until(expression) { for(let i=0;i<100;i++){ if(await evaluate(expression)) return; await sleep(50); } throw new Error('Timed out: '+expression); }
async function check(label,expression){ assert.equal(await evaluate(expression),true,label); result.checks.push(label); }
async function click(label) { await evaluate(`(()=>{const b=[...document.querySelectorAll('button,a')].find(n=>n.textContent.trim()===${JSON.stringify(label)});if(!b)throw Error('Control unavailable');b.click()})()`); }
(async()=>{
  const { stdout }=await promisify(execFile)('powershell.exe',['-NoProfile','-ExecutionPolicy','Bypass','-File',path.join(__dirname,'read-order-detail.ps1')],{windowsHide:true,maxBuffer:2*1024*1024});
  const orders=JSON.parse(stdout); assert.deepEqual(orders.map(order=>order.id),[1,2]);
  result.orders=orders.map(order=>({id:order.id,status:order.status,itemCount:order.items?.length,feeCount:order.fees?.length,historyCount:order.statusHistory?.length}));
  const adapter = `
    window.qa={requests:[],delay:0,ignoreAbort:false,permissions:['DONHANG_XEM','DONHANG_TAO','DONHANG_CAPNHAT','DONHANG_HUY','KHO_XEM'],errors:[]};
    window.addEventListener('error',e=>qa.errors.push(e.message));window.addEventListener('unhandledrejection',e=>qa.errors.push(String(e.reason)));
    const records=${JSON.stringify(orders)};const original=window.ApiClient;
    let session=true;
    window.ApiClient={...original,getAccessToken:()=>session?'qa-adapter':null,getRefreshToken:()=>null,getSession:()=>null,clearTokens:()=>{session=false},request:async(path,options={})=>{
      qa.requests.push({path,method:options.method||'GET'});
      if(options.method&&options.method!=='GET') throw Error('QA is read-only: no mutation allowed');
      if(path.startsWith('/api/v1/orders/')) {const n=Number(path.split('/')[4]);const order=records.find(v=>v.id===n);if(!order)throw Error('Only IDs 1 and 2 are authorized');
        const delay=qa.delay, ignore=qa.ignoreAbort;await new Promise(resolve=>setTimeout(resolve,delay));if(!ignore)options.signal?.throwIfAborted();return structuredClone(order);}
      if(path.startsWith('/api/v1/orders?')){const query=new URLSearchParams(path.split('?')[1]);let rows=records.filter(v=>(!query.get('keyword')||v.orderCode.includes(query.get('keyword'))||v.trackingNumber?.includes(query.get('keyword')))&&(!query.get('status')||v.status===query.get('status')));const page=Number(query.get('page')||1),size=Number(query.get('pageSize')||10);return{page,pageSize:size,totalItems:rows.length,items:structuredClone(rows.slice((page-1)*size,page*size))};}
      throw Error('QA does not provide this API; no data fabricated');
    }};
    window.Auth={...window.Auth,getCurrentUser:async()=>({role:'ADMIN'}),getPermissions:async()=>({known:true,codes:new Set(qa.permissions)}),logout:async()=>{session=false}};
  `;
  const originalListeners=proxy.listeners('request'); proxy.removeAllListeners('request');
  proxy.on('request',(req,res)=>{
    if(req.url==='/qa.js'){res.writeHead(200,{'Content-Type':'application/javascript','Cache-Control':'no-store'});res.end(adapter);return;}
    if(req.url==='/'||req.url==='/index.html'){const html=fs.readFileSync(path.join(root,'frontend/index.html'),'utf8').replace('<script src="./js/router.js','<script src="/qa.js" defer></script>\n  <script src="./js/router.js');res.writeHead(200,{'Content-Type':'text/html; charset=utf-8','Cache-Control':'no-store'});res.end(html);return;}
    originalListeners.forEach(fn=>fn(req,res));
  });
  await new Promise(resolve=>proxy.listen(0,'127.0.0.1',resolve));
  const url='http://127.0.0.1:'+proxy.address().port;
  fs.mkdirSync(profile,{recursive:true});
  fs.rmSync(path.join(profile,'DevToolsActivePort'),{force:true});
  edge=spawn('C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',['--headless','--disable-gpu','--no-first-run','--no-default-browser-check','--remote-debugging-address=127.0.0.1','--remote-debugging-port=0','--user-data-dir='+profile,'about:blank'],{windowsHide:true,stdio:'ignore'});
  let port;for(let i=0;i<100;i++){const file=path.join(profile,'DevToolsActivePort');if(fs.existsSync(file)){port=fs.readFileSync(file,'utf8').split('\n')[0];break}await sleep(100)}if(!port)throw Error('DevTools not ready');
  const tabs=await(await fetch('http://127.0.0.1:'+port+'/json/list')).json();
  socket=new WebSocket(tabs.find(tab=>tab.type==='page').webSocketDebuggerUrl);
  await new Promise((resolve,reject)=>{socket.addEventListener('open',resolve,{once:true});socket.addEventListener('error',reject,{once:true})});
  socket.addEventListener('message',event=>{const data=JSON.parse(event.data);if(data.id){const item=pending.get(data.id);pending.delete(data.id);data.error?item.reject(Error(data.error.message)):item.resolve(data.result)}else{events.push(data);if(data.method==='Runtime.exceptionThrown')errors.push(data.params.exceptionDetails.text)}});
  await send('Page.enable');await send('Runtime.enable');
  for(const [width,height] of [[1366,768],[1920,1080],[768,1024],[390,844]]){
    await send('Emulation.setDeviceMetricsOverride',{width,height,deviceScaleFactor:1,mobile:width<992});
    await send('Page.navigate',{url:url+'/#/orders/1'});
    await until("document.querySelector('.order-detail-code')&&document.querySelector('.order-detail-code').textContent.length>0");
    await evaluate('document.fonts.ready');await sleep(250);
    const metrics=await evaluate(`(()=>{const rect=n=>{const r=n.getBoundingClientRect();return{left:r.left,right:r.right,top:r.top,bottom:r.bottom,width:r.width}};const shell=document.querySelector('.workspace'),header=document.querySelector('.topbar'),detail=document.querySelector('.order-detail');return{width:innerWidth,height:innerHeight,pageWidth:document.documentElement.scrollWidth,workspace:rect(shell),header:rect(header),detail:rect(detail),sidebarWidth:rect(document.querySelector('.sidebar')).width,columns:getComputedStyle(document.querySelector('.order-detail-grid')).gridTemplateColumns,detailCount:document.querySelectorAll('.order-detail').length,h1Count:document.querySelectorAll('#page-content h1').length,feeTranslated:document.querySelector('.order-detail-grid').textContent.includes('Phí vận chuyển'),actorFallback:document.querySelector('.order-timeline').textContent.includes('Tài khoản #'),bodyLock:document.body.classList.contains('sidebar-open'),stylesLoaded:getComputedStyle(document.querySelector('.btn')).display,errors:qa.errors}})()`);
    assert.equal(metrics.width,width);assert(metrics.pageWidth<=width, 'Whole page overflow');assert.equal(metrics.detailCount,1);assert(metrics.detail.top>=metrics.header.bottom);assert.equal(metrics.feeTranslated,true);assert.equal(metrics.actorFallback,true);
    if(width>=992)assert(metrics.detail.left>=metrics.sidebarWidth);
    const picture=await send('Page.captureScreenshot',{format:'png',captureBeyondViewport:false});
    fs.writeFileSync(path.join(__dirname,'.artifacts/order-detail','order-detail-'+width+'.png'),Buffer.from(picture.data,'base64'));
    if(width<992){
      await evaluate("document.getElementById('mobile-menu').click()");await sleep(300);
      await check('sidebar accessible and workspace inert at '+width,"!document.getElementById('sidebar').inert&&document.querySelector('.workspace').inert&&document.body.classList.contains('sidebar-open')");
    }
    await evaluate("document.querySelectorAll('.navigation-children').forEach(n=>n.classList.remove('d-none'))");
    await check('sidebar footer remains visible with expanded menu at '+width,"(()=>{const f=document.querySelector('.sidebar-footer').getBoundingClientRect(),s=document.querySelector('.sidebar-scroll').getBoundingClientRect();return f.bottom<=innerHeight+.5&&f.top>=s.bottom-.5&&document.getElementById('sidebar-signout').getBoundingClientRect().bottom<=innerHeight+.5})()");
    if(width===390){const drawer=await send('Page.captureScreenshot',{format:'png',captureBeyondViewport:false});fs.writeFileSync(path.join(__dirname,'.artifacts/order-detail/order-detail-390-sidebar.png'),Buffer.from(drawer.data,'base64'));}
    if(width<992){
      await evaluate("document.getElementById('sidebar-backdrop').click()");
      await check('backdrop closes drawer and releases scrolling at '+width,"!document.querySelector('.workspace').inert&&!document.body.classList.contains('sidebar-open')&&document.getElementById('sidebar').inert");
      await evaluate("document.getElementById('mobile-menu').click();document.dispatchEvent(new KeyboardEvent('keydown',{key:'Escape',bubbles:true}))");
      await check('Escape closes drawer at '+width,"!document.body.classList.contains('sidebar-open')");
    }
    await evaluate('window.scrollTo(0,400)');
    await check('sticky header stays at viewport top at '+width,"Math.abs(document.querySelector('.topbar').getBoundingClientRect().top)<1");
    await evaluate('window.scrollTo(0,0)');
    await evaluate("document.querySelector('.order-internal').open=true");
    await check('Expanded technical details and long fields do not overflow page at '+width,"document.documentElement.scrollWidth<=innerWidth");
    await evaluate("document.querySelector('.order-internal').open=false");
    if(width===1366||width===390){
      await evaluate("[...document.querySelectorAll('.order-detail-grid>section')].find(n=>n.querySelector('h3').textContent.startsWith('Người gửi')).scrollIntoView({block:'start',behavior:'instant'})");
      await evaluate("new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve)))");
      const contacts=await send('Page.captureScreenshot',{format:'png',captureBeyondViewport:false});fs.writeFileSync(path.join(__dirname,'.artifacts/order-detail','order-detail-'+width+'-contacts.png'),Buffer.from(contacts.data,'base64'));
      await evaluate("document.querySelector('.order-timeline').closest('section').scrollIntoView({block:'start',behavior:'instant'})");
      await evaluate("new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve)))");
      const timeline=await send('Page.captureScreenshot',{format:'png',captureBeyondViewport:false});fs.writeFileSync(path.join(__dirname,'.artifacts/order-detail','order-detail-'+width+'-history.png'),Buffer.from(timeline.data,'base64'));
      await evaluate('window.scrollTo(0,0)');
    }
    result.viewports.push(metrics);
  }
  await send('Emulation.setDeviceMetricsOverride',{width:1366,height:768,deviceScaleFactor:1,mobile:false});
  const before=await evaluate("qa.requests.filter(v=>v.path==='/api/v1/orders/1').length");
  await click('Làm mới');await until("!!document.querySelector('.order-detail-code')");
  assert.equal(await evaluate("qa.requests.filter(v=>v.path==='/api/v1/orders/1').length"),before+1);result.checks.push('Refresh fetches detail exactly once');
  await evaluate("qa.delay=400;qa.ignoreAbort=true;const body=document.querySelector('.orders-route-body');qa.detailRenders=0;qa.observer=new MutationObserver(()=>{if(body.querySelector('.order-detail-hero'))qa.detailRenders++});qa.observer.observe(body,{childList:true});const reload=[...document.querySelectorAll('.order-detail-actions button')].find(n=>n.textContent==='Làm mới');reload.click();qa.delay=0;reload.click()");
  await until("!!document.querySelector('.order-detail-code')");await sleep(500);
  await check('Overlapping refreshes render only latest response',"qa.detailRenders===1");await evaluate("qa.observer.disconnect();qa.ignoreAbort=false");
  await evaluate("Router.navigate('#/orders/1?returnTo='+encodeURIComponent('#/warehouse/inventory?warehouseId=1&page=2&keyword=abc'))");
  await until("document.querySelector('.order-breadcrumb a')?.textContent==='Tồn kho'&&!!document.querySelector('.order-detail-code')");
  await check('Warehouse and Orders use the same single detail renderer',"document.querySelectorAll('.order-detail').length===1&&document.querySelector('.order-detail-navigation .btn').getAttribute('href')==='#/warehouse/inventory?warehouseId=1&page=2&keyword=abc'");
  await click('Quay lại');await until("Router.current()?.name==='inventory'");
  await check('Warehouse return keeps selected warehouse/page/keyword',"Router.current().query.warehouseId===1&&Router.current().query.page===2&&Router.current().query.keyword==='abc'");
  await evaluate("OrdersPage.showDetail({route:Router.current()},1)");await until("Router.current()?.name==='order-detail'&&!!document.querySelector('.order-detail-code')");
  await check('Shared helper from warehouse preserves internal source',"Router.current().query.returnTo.startsWith('#/warehouse/inventory?')");
  await evaluate("Router.navigate('#/warehouse/transactions/8?warehouseId=1&orderId=1')");await until("Router.current()?.name==='transaction-detail'");
  await evaluate("OrdersPage.showDetail({route:Router.current()},1)");await until("Router.current()?.name==='order-detail'&&!!document.querySelector('.order-detail-code')");
  await check('Opening order from transaction detail returns to transaction list',"Router.current().query.returnTo==='#/warehouse/transactions?warehouseId=1&orderId=1'");
  await evaluate("Router.navigate('#/orders/1?page=1&pageSize=10')");await until("!!document.querySelector('.order-detail-code')");
  await click('Quay lại');await until("Router.current()?.name==='orders'&&document.querySelectorAll('.orders-table tbody tr').length===2");
  await click('Chi tiết');await until("Router.current()?.params.id===1&&!!document.querySelector('.order-detail-code')");
  result.checks.push('Actual Orders list detail button routes to order ID 1');
  await evaluate("history.back()");await until("Router.current()?.name==='orders'");
  await evaluate("history.forward()");await until("Router.current()?.params.id===1&&!!document.querySelector('.order-detail-code')");
  result.checks.push('Back/Forward preserve detail and list filters');
  await send('Page.reload');await until("window.Router?.current()?.params.id===1&&!!document.querySelector('.order-detail-code')");
  result.checks.push('Browser reload reopens detail ID 1');
  await evaluate("qa.delay=400;qa.ignoreAbort=true;Router.navigate('#/orders/2')");await until("qa.requests.some(v=>v.path==='/api/v1/orders/2')");
  await evaluate("qa.delay=0;Router.navigate('#/orders/1')");await until("Router.current()?.params.id===1&&!!document.querySelector('.order-detail-code')");await sleep(500);
  await check('Late response for ID 2 cannot overwrite ID 1',"Router.current().params.id===1&&document.querySelectorAll('.order-detail').length===1&&document.querySelector('.order-detail-code').textContent===records.find(v=>v.id===1).orderCode");
  await evaluate("qa.ignoreAbort=false;qa.delay=0;Router.navigate('#/orders/2')");await until("Router.current()?.params.id===2&&!!document.querySelector('.order-detail-code')");
  await check('ID 2 replaces old detail',"document.querySelectorAll('.order-detail').length===1&&document.querySelector('.order-detail-code').textContent===records.find(v=>v.id===2).orderCode");
  await click('Báo giá');await click('Báo giá');
  await check('Double click on action opens only one dialog',"document.querySelectorAll('dialog[open]').length===1");
  await click('Đóng');await check('Closing modal removes dialog and top-layer backdrop',"!document.querySelector('dialog')&&!document.querySelector('.modal-backdrop')");
  await click('Báo giá');await evaluate("Router.navigate('#/orders/1')");await until("Router.current()?.params.id===1&&!!document.querySelector('.order-detail-code')");
  await check('Route change removes all dialogs/backdrops and body locks',"!document.querySelector('dialog')&&!document.querySelector('.modal-backdrop')&&!document.body.classList.contains('sidebar-open')&&getComputedStyle(document.body).overflow!=='hidden'");
  await evaluate("qa.dialogOwner={abort:new AbortController(),dialogs:new Set()};qa.closedCount=0;qa.testDialog=LogisticsUI.dialog(qa.dialogOwner,'Kiểm tra vòng đời modal');qa.testDialog.onClose(()=>qa.closedCount++);LogisticsUI.closeDialogs(qa.dialogOwner);qa.testDialog.close()");
  await check('Shared modal cleanup aborts its signal once and clears ownership',"qa.testDialog.signal.aborted&&qa.closedCount===1&&qa.dialogOwner.dialogs.size===0&&!document.querySelector('dialog')");
  await evaluate("document.querySelector('.order-detail-grid').scrollIntoView({behavior:'instant'});Router.navigate('#/orders/2')");await until("Router.current()?.params.id===2&&!!document.querySelector('.order-detail-code')");
  await check('Route navigation scrolls instantly to top',"window.scrollY===0");
  await evaluate("qa.permissions=['DONHANG_XEM'];Router.reload()");await until("!!document.querySelector('.order-detail-code')");
  await check('Viewer permission exposes only refresh',"[...document.querySelectorAll('.order-detail-actions button')].map(n=>n.textContent).join(',')==='Làm mới'");
  await evaluate("qa.permissions=[];Router.reload()");await until("document.getElementById('page-title').textContent==='Không có quyền'");
  await check('Forbidden route retains session adapter',"!!ApiClient.getAccessToken()&&Router.current().name==='order-detail'");
  assert.deepEqual(await evaluate('qa.errors'),[]);assert.deepEqual(errors,[]);
  result.checks.push('No error/unhandledrejection/DevTools exception in completed checks');
})().catch(error=>{result.failure=error.message;process.exitCode=1}).finally(async()=>{
  try{if(socket?.readyState===1)await send('Browser.close')}catch{}socket?.close();edge?.kill();await new Promise(resolve=>proxy.close(resolve));
  // Delete only this test's own profile, with an explicit workspace boundary check.
  assert(profile.startsWith(root+path.sep));
  fs.rmSync(profile,{recursive:true,force:true,maxRetries:10,retryDelay:200});
  fs.writeFileSync(path.join(__dirname,'.artifacts/order-detail/order-detail-browser-verification.json'),JSON.stringify(result,null,2));
  console.log(JSON.stringify({viewports:result.viewports.map(v=>({width:v.width,pageWidth:v.pageWidth,columns:v.columns})),checks:result.checks,errors:result.consoleErrors,failure:result.failure}));
});
