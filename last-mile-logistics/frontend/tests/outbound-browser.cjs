"use strict";
// Opt-in browser QA. Existing app server only; no SQL writes or real outbound POST.
// Screenshots use actual read-only DB results. Contract scenarios exist only in this headless tab.
const fs = require('node:fs'), path = require('node:path');
const { spawn, execFile } = require('node:child_process');
const { promisify } = require('node:util');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '../..'), profile = path.join(__dirname, '.artifacts/outbound/edge-profile');
const appUrl = process.env.OUTBOUND_QA_URL || 'http://127.0.0.1:5500';
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
let edge, socket, nextId = 0; const pending = new Map(), errors = [];
const report = { mode: 'read-only LocalDB SQL + isolated browser contract scenarios; no real mutation', viewports: [], checks: [], consoleErrors: errors };
function send(method, params = {}) { return new Promise((resolve, reject) => { const id = ++nextId; pending.set(id, {resolve, reject}); socket.send(JSON.stringify({id, method, params})); }); }
async function evaluate(expression) { const r = await send('Runtime.evaluate', {expression, awaitPromise: true, returnByValue: true}); if(r.exceptionDetails) throw Error(r.exceptionDetails.exception?.description || r.exceptionDetails.text); return r.result.value; }
async function until(expression) { for(let i=0;i<150;i++) { if(await evaluate(expression)) return; await sleep(40); } const diagnostic=await evaluate("({readyState:document.readyState,qa:typeof qa,errors:window.qa?.errors,route:window.Router?.current()?.name,heading:document.getElementById('page-title')?.textContent,busy:[...document.querySelectorAll('[aria-busy=true]')].map(n=>n.className),alert:document.querySelector('#page-content .alert')?.textContent})"); throw Error('Timed out: '+expression+' '+JSON.stringify(diagnostic)+' '+JSON.stringify(errors)); }
async function check(label, expression) { assert.equal(await evaluate(expression), true, label); report.checks.push(label); }
const click = label => evaluate(`(()=>{const b=[...document.querySelectorAll('#page-content button,dialog button')].find(n=>n.textContent.trim()===${JSON.stringify(label)});if(!b)throw Error('Missing control: '+${JSON.stringify(label)});b.click()})()`);
const control = label => `document.querySelector([...document.querySelectorAll('#page-content label')].find(n=>n.textContent===${JSON.stringify(label)}).getAttribute('for')?'#'+[...document.querySelectorAll('#page-content label')].find(n=>n.textContent===${JSON.stringify(label)}).htmlFor:'missing')`;
const change = (label,value) => evaluate(`(()=>{const n=${control(label)};n.value=${JSON.stringify(String(value))};n.dispatchEvent(new Event('change',{bubbles:true}))})()`);
const ready = "document.querySelector('.outbound-card')&&!document.querySelector('[aria-busy=\"true\"]')&&![...document.querySelectorAll('#page-content select option:checked')].some(n=>n.textContent.includes('Đang tải'))";
(async()=>{
  const runPs = file => promisify(execFile)('powershell.exe', ['-NoProfile','-ExecutionPolicy','Bypass','-File',path.join(__dirname,file)], {windowsHide:true,maxBuffer:4*1024*1024}).then(r=>JSON.parse(r.stdout));
  const [data, details] = await Promise.all([runPs('read-outbound-data.ps1'),runPs('read-order-detail.ps1')]);
  report.sqlChecks=data.sqlChecks;
  report.actualWarehouses=data.warehouses.map(w=>({id:w.id,rows:data.orders[w.id]?.length||0}));
  const html=await(await fetch(appUrl+'/')).text(); assert(html.includes('js/warehouse.js'));
  const adapter = `
    window.qa={requests:[],writes:[],errors:[],scenarios:false,delay:0,ignoreAbort:false,failure:0,writeStatus:201,writeDelay:80};
    addEventListener('error',e=>qa.errors.push(e.message));addEventListener('unhandledrejection',e=>qa.errors.push(String(e.reason)));
    const records=${JSON.stringify(data)}, details=${JSON.stringify(details)};
    const real=window.ApiClient;let session=true;
    window.ApiClient={...real,getAccessToken:()=>session?'isolated-qa':null,getRefreshToken:()=>null,getSession:()=>null,clearTokens:()=>{session=false},request:async(path,options={})=>{
      qa.requests.push({path,method:options.method||'GET'});const query=new URLSearchParams(path.split('?')[1]);
      if(options.method==='POST') {
        if(!qa.scenarios||path!=='/api/v1/warehouse-transactions/outbound')throw Error('No real mutations authorized in browser QA');
        qa.writes.push(JSON.parse(options.body));await new Promise(r=>setTimeout(r,qa.writeDelay));
        if(qa.writeStatus!==201)throw Object.assign(Error('Isolated conflict'),{status:qa.writeStatus});
        return {handoverId:90001,handoverCode:'QA-ONLY',transactionCode:'QA-ONLY'};
      }
      const delay=qa.delay,ignoreAbort=qa.ignoreAbort,failure=qa.failure;await new Promise(r=>setTimeout(r,delay));if(!ignoreAbort)options.signal?.throwIfAborted();
      if(failure)throw Object.assign(Error('Isolated read failure'),{status:failure===-1?undefined:failure});
      if(path==='/api/v1/warehouses')return structuredClone(records.warehouses);
      const match=path.match(/^\\/api\\/v1\\/warehouses\\/(\\d+)\\/(locations|handover-orders)/);
      if(match){const warehouse=Number(match[1]);if(match[2]==='locations')return structuredClone(records.locations[warehouse]);
        let rows=qa.scenarios?(warehouse===records.warehouses[0].id?qa.rows:[]):records.orders[warehouse];
        rows=rows.filter(r=>(!query.get('locationId')||r.locationId===Number(query.get('locationId')))&&(!query.get('assignmentStatus')||r.assignmentStatus===query.get('assignmentStatus'))&&(query.get('acceptedOnly')!=='true'||r.assignmentStatus==='ACCEPTED')&&(!query.get('keyword')||[r.orderCode,r.trackingNumber,r.shipperName,r.employeeCode].some(v=>v?.includes(query.get('keyword')))));
        const page=Number(query.get('page')||1),pageSize=Number(query.get('pageSize')||10);return{warehouseId:warehouse,page,pageSize,totalItems:rows.length,items:structuredClone(rows.slice((page-1)*pageSize,page*pageSize))};
      }
      if(path.startsWith('/api/v1/orders/')) {const id=Number(path.split('/')[4]);const row=details.find(r=>r.id===id);if(!row)throw Error('Read-only detail unavailable');return structuredClone(row);}
      throw Error('Unsupported QA request '+path);
    }};
    window.Auth={...window.Auth,getCurrentUser:async()=>({role:'ADMIN',accountId:1,username:'isolated-qa'}),getPermissions:async()=>({known:true,codes:new Set(['KHO_XEM','KHO_XUAT','DONHANG_XEM'])})};
    qa.warehouse=records.warehouses[0].id;qa.otherWarehouse=records.warehouses[1].id;qa.location=records.locations[qa.warehouse][0].id;
    qa.rows=Array.from({length:12},(_,i)=>({orderId:i+1,assignmentId:7001+i,orderCode:'QA-CONTRACT-ONLY-ORDER-'+String(i+1).padStart(3,'0')+'-LONG-CODE',trackingNumber:'QA-CONTRACT-ONLY-TRACKING-LONG-'+i,locationId:qa.location,locationCode:records.locations[qa.warehouse][0].code,shipperName:'QA contract shipper',employeeCode:'QA-ONLY',vehicleType:'QA vehicle',licensePlate:'QA-ONLY',assignmentStatus:i===0?'PENDING':'ACCEPTED',orderStatus:'ASSIGNED',stockStatus:'ALLOCATED',weightKg:2.5,canHandover:i!==0}));
  `;
  fs.mkdirSync(profile,{recursive:true});
  const portFile=path.join(profile,'DevToolsActivePort');if(fs.existsSync(portFile))fs.unlinkSync(portFile);
  edge=spawn('C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',['--headless','--disable-gpu','--no-first-run','--no-default-browser-check','--remote-debugging-address=127.0.0.1','--remote-debugging-port=0','--user-data-dir='+profile,'about:blank'],{windowsHide:true,stdio:'ignore'});
  for(let i=0;i<100&&!fs.existsSync(portFile);i++)await sleep(100);
  const port=fs.readFileSync(portFile,'utf8').split('\n')[0];
  const tabs=await(await fetch('http://127.0.0.1:'+port+'/json/list')).json();
  socket=new WebSocket(tabs.find(t=>t.type==='page').webSocketDebuggerUrl);
  await new Promise((resolve,reject)=>{socket.addEventListener('open',resolve,{once:true});socket.addEventListener('error',reject,{once:true});});
  socket.addEventListener('message',async event=>{const d=JSON.parse(event.data);if(d.id){const p=pending.get(d.id);pending.delete(d.id);d.error?p.reject(Error(d.error.message)):p.resolve(d.result);}else if(d.method==='Runtime.exceptionThrown')errors.push(d.params.exceptionDetails.text);else if(d.method==='Fetch.requestPaused'){
    try {
      const isAdapter=d.params.request.url.endsWith('/__outbound_qa__.js');
      const content=isAdapter?adapter:html.replace('<script src="./js/router.js', '<script src="/__outbound_qa__.js" defer></script><script src="./js/router.js');
      await send('Fetch.fulfillRequest',{requestId:d.params.requestId,responseCode:200,responseHeaders:[{name:'Content-Type',value:isAdapter?'application/javascript; charset=utf-8':'text/html; charset=utf-8'}],body:Buffer.from(content).toString('base64')});
    }catch(e){errors.push(e.message);}
  }});
  await send('Page.enable');await send('Runtime.enable');await send('Fetch.enable',{patterns:[{urlPattern:appUrl+'/*',resourceType:'Document',requestStage:'Request'},{urlPattern:appUrl+'/__outbound_qa__.js',resourceType:'Script',requestStage:'Request'}]});
  for(const [width,height] of [[1366,768],[768,1024],[390,844]]){
    await send('Emulation.setDeviceMetricsOverride',{width,height,deviceScaleFactor:1,mobile:width<992});
    await send('Page.navigate',{url:appUrl+'/?outboundQA='+width+'#/warehouse/outbound'});await until(ready);await evaluate('document.fonts.ready');
    await check('one page heading / one list at '+width,"document.querySelectorAll('#page-content h2,#page-content h3').length===0&&document.querySelectorAll('.warehouse-list').length===1&&document.getElementById('page-description').textContent==='Bàn giao hàng trong kho cho shipper đã nhận nhiệm vụ'");
    await check('initial choose-warehouse state at '+width,"document.querySelector('.orders-empty').textContent==='Chọn kho để xem đơn bàn giao'");
    await change('Kho',await evaluate('qa.warehouse'));await until(ready);
    await check('actual empty result is not an error at '+width,"document.querySelector('.orders-empty').textContent==='Không có đơn phù hợp tại kho này'&&!document.querySelector('#page-content .alert-danger')");
    const metrics=await evaluate("({width:innerWidth,pageWidth:document.documentElement.scrollWidth,emptyHeight:document.querySelector('.orders-empty').getBoundingClientRect().height,filterTop:document.querySelector('form').getBoundingClientRect().top,emptyTop:document.querySelector('.orders-empty').getBoundingClientRect().top,errors:qa.errors})");
    assert(metrics.pageWidth<=width);assert(metrics.emptyHeight<120);assert.equal(metrics.errors.length,0);report.viewports.push(metrics);
    const picture=await send('Page.captureScreenshot',{format:'png',captureBeyondViewport:false});fs.writeFileSync(path.join(root,'docs/outbound-'+width+'.png'),Buffer.from(picture.data,'base64'));
  }
  await evaluate('qa.scenarios=true');await click('Làm mới');await until(ready);
  await evaluate("Object.defineProperty(navigator,'clipboard',{configurable:true,value:{writeText:async()=>{throw Error('QA clipboard unavailable')}}})");
  await click('Sao chép');await until("document.querySelector('dialog input[readonly]')");
  await check('copy fallback displays the complete code',"document.querySelector('dialog input[readonly]').value===qa.rows[0].orderCode");await click('Đóng');
  for(const width of [1366,390]) {
    await send('Emulation.setDeviceMetricsOverride',{width,height:844,deviceScaleFactor:1,mobile:width<992});
    await check('populated table scrolls inside card at '+width,"document.documentElement.scrollWidth<=innerWidth&&document.querySelector('.table-responsive').scrollWidth>document.querySelector('.table-responsive').clientWidth");
  }
  await check('8 columns, codes truncate and full code is available',"document.querySelectorAll('thead th').length===8&&[...document.querySelectorAll('.inventory-code')].every(n=>n.title&&n.tabIndex===0)&&getComputedStyle(document.querySelector('.inventory-code')).textOverflow==='ellipsis'");
  await check('PENDING cannot hand over and explains why',"document.querySelector('tbody tr button[data-stock-action]').disabled&&document.querySelector('tbody tr').textContent.includes('Chờ shipper nhận nhiệm vụ')");
  await change('Trạng thái phân công','PENDING');await click('Lọc');await until(ready);
  await check('assignment filtering reaches API before pagination',"qa.requests.at(-1).path.includes('assignmentStatus=PENDING')&&document.querySelectorAll('tbody tr').length===1");
  await change('Vị trí lưu kho',await evaluate('qa.location'));await evaluate(`${control('Tìm kiếm')}.value='ORDER-001'`);
  await evaluate(`(()=>{const n=${control('Tìm kiếm')};n.focus();})()`);await send('Input.dispatchKeyEvent',{type:'keyDown',key:'Enter',code:'Enter',text:'\r',unmodifiedText:'\r',windowsVirtualKeyCode:13});await send('Input.dispatchKeyEvent',{type:'keyUp',key:'Enter',code:'Enter',windowsVirtualKeyCode:13});await until("qa.requests.at(-1).path.includes('keyword=ORDER-001')");await until(ready);
  await check('Enter applies keyword and location',"qa.requests.at(-1).path.includes('locationId=')&&qa.requests.at(-1).path.includes('keyword=ORDER-001')");
  await click('Xóa bộ lọc');await until(ready);
  await check('clear filters preserves warehouse',`Number(${control('Kho')}.value)===qa.warehouse&&${control('Vị trí lưu kho')}.value===''&&${control('Tìm kiếm')}.value===''&&!qa.requests.at(-1).path.includes('assignmentStatus')`);
  await click('Sau ›');await until(ready);await check('pagination loads page 2',"qa.requests.at(-1).path.includes('page=2')&&document.querySelectorAll('tbody tr').length===2");
  await change('Số dòng',20);await until(ready);await check('page size resets page',"qa.requests.at(-1).path.includes('page=1')&&qa.requests.at(-1).path.includes('pageSize=20')&&document.querySelectorAll('tbody tr').length===12");
  await click('Chi tiết');await until("document.querySelector('.order-detail-code')");await check('detail opens exact orderId and retains return filters',"Router.current().params.id===1&&Router.current().query.returnTo.includes('/warehouse/outbound')");
  await evaluate("Router.navigate(Router.current().query.returnTo)");await until(ready);
  await change('Trạng thái phân công','ACCEPTED');await click('Lọc');await until(ready);
  await evaluate("(()=>{const b=document.querySelector('button[data-stock-action]');b.click();b.click()})()");await until("document.querySelector('dialog textarea')");
  await check('double open creates exactly one modal',"document.querySelectorAll('dialog').length===1&&document.querySelector('dialog').textContent.includes('Mã vận đơn')");
  await click('Hủy');await check('cancel releases modal and backdrop',"!document.querySelector('dialog')&&!document.querySelector('.modal-backdrop')&&!document.body.classList.contains('modal-open')");
  await evaluate("qa.rows[1].canHandover=false;qa.rows[2].orderStatus='HANDED_OVER';qa.rows[3].stockStatus='HANDED_OVER'");await click('Làm mới');await until(ready);
  await check('invalid shipper/vehicle, order and stock all disable handover',"[...document.querySelectorAll('button[data-stock-action]')].slice(0,3).every(b=>b.disabled)&&document.querySelector('tbody').textContent.includes('Hàng không còn tồn kho hợp lệ')");
  await evaluate("qa.rows[1].canHandover=true;qa.rows[2].orderStatus='ASSIGNED';qa.rows[3].stockStatus='ALLOCATED'");await click('Làm mới');await until(ready);
  await evaluate("qa.rows[1].locationId=9007;qa.rows[1].locationCode='QA-current-source'");
  await click('Bàn giao');await until("document.querySelector('dialog textarea')");
  await check('modal rechecks current stock source rather than selected filter',"document.querySelector('dialog').textContent.includes('QA-current-source')");
  await evaluate("(()=>{const b=[...document.querySelectorAll('dialog button')].find(n=>n.textContent==='Xác nhận bàn giao');b.click();b.click()})()");
  await check('submit locks controls',"document.querySelector('dialog fieldset').disabled&&document.querySelector('dialog').getAttribute('aria-busy')==='true'");await until("!document.querySelector('dialog')");await until(ready);
  await check('one POST and distinct IDs / stock source',"qa.writes.length===1&&qa.writes[0].orderId===2&&qa.writes[0].assignmentId===7002&&qa.writes[0].warehouseId===qa.warehouse&&qa.writes[0].fromLocationId===9007&&qa.writes[0].notes===null");
  await check('success closes modal and informs shipper confirmation',"document.querySelector('.alert-success').textContent.includes('Chờ shipper xác nhận nhận hàng')&&!document.querySelector('dialog')");
  await evaluate('qa.writeStatus=409');await click('Bàn giao');await until("document.querySelector('dialog textarea')");await click('Xác nhận bàn giao');await until("document.querySelector('dialog .alert-danger')&&!document.querySelector('dialog').getAttribute('aria-busy').includes('true')");
  await check('409 refreshes without automatic POST retry',"qa.writes.length===2&&document.querySelector('dialog fieldset').disabled&&document.querySelector('dialog').textContent.includes('Dữ liệu đã thay đổi')&&qa.requests.at(-1).method==='GET'");
  await click('Đóng');await check('conflict close leaves no dialog/backdrop',"!document.querySelector('dialog')&&!document.querySelector('.modal-backdrop')");
  await evaluate('qa.writeStatus=201');await click('Bàn giao');await until("document.querySelector('dialog textarea')");
  await send('Input.dispatchKeyEvent',{type:'keyDown',key:'Escape',code:'Escape',windowsVirtualKeyCode:27});await send('Input.dispatchKeyEvent',{type:'keyUp',key:'Escape',code:'Escape',windowsVirtualKeyCode:27});
  await check('Escape closes modal without scroll lock',"!document.querySelector('dialog')&&!document.body.classList.contains('modal-open')");
  await evaluate("qa.rows[1].assignmentStatus='PENDING'");await click('Bàn giao');await until("document.querySelector('dialog .alert-danger')");
  await check('changed assignment is rejected before POST',"qa.writes.length===2&&!document.querySelector('dialog textarea')");await click('Đóng');
  await evaluate("qa.rows[1].assignmentStatus='ACCEPTED'");
  for(const failure of [403,500,-1]){
    await evaluate('qa.failure='+failure);await click('Làm mới');await until(ready);
    await check('read failure '+failure+' preserves session and shows retry',"!!document.querySelector('.alert-danger')&&!document.querySelector('.outbound-card').textContent.includes('hết hạn')&&!!ApiClient.getAccessToken()&&[...document.querySelectorAll('#page-content button')].some(b=>b.textContent==='Thử lại')");
    await evaluate('qa.failure=0');await click('Thử lại');await until(ready);
  }
  await evaluate('qa.delay=250;qa.ignoreAbort=true');await click('Làm mới');await change('Kho',await evaluate('qa.otherWarehouse'));await until("Router.current().query.warehouseId===qa.otherWarehouse&&document.querySelector('.orders-empty')?.textContent==='Không có đơn phù hợp tại kho này'");await until(ready);await sleep(100);
  await check('old request cannot overwrite changed warehouse',"Router.current().query.warehouseId===qa.otherWarehouse&&Router.current().query.page===1&&!document.querySelector('tbody')&&document.querySelector('.orders-empty').textContent==='Không có đơn phù hợp tại kho này'");
  await evaluate('qa.delay=0;qa.ignoreAbort=false');
  for(let i=0;i<3;i++){await evaluate("Router.navigate('#/dashboard')");await until("Router.current().name==='overview'");await evaluate("Router.navigate('#/warehouse/outbound?warehouseId='+qa.warehouse)");await until(ready);}
  const before=await evaluate('qa.requests.length');await click('Lọc');await until(ready);assert.equal(await evaluate('qa.requests.length'),before+1);report.checks.push('remount attaches each filter listener once');
  await check('no runtime errors in all browser scenarios',"qa.errors.length===0");assert.equal(errors.length,0);
  fs.writeFileSync(path.join(root,'docs/outbound-browser-verification.json'),JSON.stringify(report,null,2));
  console.log(JSON.stringify({actualWarehouses:report.actualWarehouses,viewports:report.viewports.map(v=>({width:v.width,pageWidth:v.pageWidth,emptyHeight:v.emptyHeight})),checks:report.checks.length,consoleErrors:errors},null,2));
})().catch(e=>{console.error(e.stack);process.exitCode=1;}).finally(async()=>{if(socket){try{await send('Browser.close')}catch(_){}socket.close();}if(edge&&!edge.killed)edge.kill();});
