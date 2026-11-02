"use strict";
// Existing frontend server + real read-only LocalDB list for screenshots.
// Mutation scenarios are isolated contract fixtures; no POST reaches the real API.
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const {spawn,execFile}=require('node:child_process'),{promisify}=require('node:util');
const root=path.resolve(__dirname,'../..'),profile=path.join(__dirname,'.artifacts/returns/edge-profile');
const appUrl=process.env.RETURN_QA_URL||'http://localhost:5500';
const sleep=ms=>new Promise(r=>setTimeout(r,ms));let edge,socket,id=0;
const pending=new Map(),errors=[],report={mode:'Actual return candidate SQL + isolated browser mutation fixtures; no real POST',checks:[],viewports:[],consoleErrors:errors};
function send(method,params={}){return new Promise((resolve,reject)=>{const key=++id;pending.set(key,{resolve,reject});socket.send(JSON.stringify({id:key,method,params}));});}
async function evaluate(expression){const r=await send('Runtime.evaluate',{expression,awaitPromise:true,returnByValue:true});if(r.exceptionDetails)throw Error(r.exceptionDetails.exception?.description||r.exceptionDetails.text);return r.result.value;}
async function until(expression){for(let i=0;i<180;i++){if(await evaluate(expression))return;await sleep(40);}throw Error('Timed out: '+expression+' '+JSON.stringify(await evaluate('({errors:window.qa?.errors,route:window.Router?.current()?.name,alert:document.querySelector("#page-content .alert")?.textContent})')));}
async function check(label,expression){assert.equal(await evaluate(expression),true,label);report.checks.push(label);}
async function click(label){await evaluate(`(()=>{const n=[...document.querySelectorAll('.page-heading button,#page-content button,dialog button')].find(n=>n.textContent.trim()===${JSON.stringify(label)});if(!n)throw Error('Missing '+${JSON.stringify(label)});n.click()})()`);}
const control=label=>`document.getElementById([...document.querySelectorAll('#page-content label,dialog label')].find(n=>n.textContent===${JSON.stringify(label)}).htmlFor)`;
const change=(label,value)=>evaluate(`(()=>{const n=${control(label)};n.value=${JSON.stringify(String(value))};n.dispatchEvent(new Event('change',{bubbles:true}))})()`);
const ready="document.querySelector('.return-card')&&!document.querySelector('[aria-busy=true]')&&![...document.querySelectorAll('#page-content select option:checked')].some(n=>n.textContent.includes('Đang tải'))";
(async()=>{
  const {stdout}=await promisify(execFile)('powershell.exe',['-NoProfile','-ExecutionPolicy','Bypass','-File',path.join(__dirname,'read-return-data.ps1')],{windowsHide:true,maxBuffer:4*1024*1024});
  const data=JSON.parse(stdout);report.sqlChecks=data.sqlChecks;
  const html=await(await fetch(appUrl+'/')).text();assert(html.includes('js/warehouse.js'));
  const adapter=`
    window.qa={requests:[],writes:[],errors:[],scenarios:false,delay:0,ignoreAbort:false,failure:0,writeStatus:201,shapeFailure:false};
    addEventListener('error',e=>qa.errors.push(e.message));addEventListener('unhandledrejection',e=>qa.errors.push(String(e.reason)));
    const records=${JSON.stringify(data)}, original=window.ApiClient;
    qa.warehouse=records.warehouses[0].id;qa.otherWarehouse=records.warehouses[1].id;qa.branch=records.warehouses[0].branchId;qa.location=records.locations[qa.warehouse][0].id;
    qa.resetRows=()=>{qa.rows=Array.from({length:12},(_,i)=>({orderId:801+i,returnRequestId:6001+i,orderCode:'QA-RETURN-ONLY-'+String(i+1).padStart(3,'0'),trackingNumber:'QA-TRACK-ONLY-'+i,branchId:qa.branch,returnBranchId:qa.branch,orderStatus:'RETURNING',orderStatusName:'Chuyển hoàn',requestStatus:'IN_PROGRESS',stockStatus:'HANDED_OVER',reason:'QA contract return reason',requestedAt:'2026-10-09T00:00:00Z'}));};qa.resetRows();
    window.ApiClient={...original,getAccessToken:()=> 'isolated-qa',getRefreshToken:()=>null,request:async(url,options={})=>{
      qa.requests.push({url,method:options.method||'GET'});const query=new URLSearchParams(url.split('?')[1]);
      if(options.method==='POST'){
        if(!qa.scenarios||url!=='/api/v1/warehouse-transactions/return-in')throw Error('No real mutations authorized');
        const payload=JSON.parse(options.body);qa.writes.push(payload);await new Promise(r=>setTimeout(r,100));
        if(qa.writeStatus!==201)throw Object.assign(Error(qa.writeStatus===409?'Vị trí nhận hoàn đã thay đổi.':qa.writeStatus===400?'Ghi chú chưa hợp lệ.':'Lỗi máy chủ mô phỏng.'),{status:qa.writeStatus});
        qa.rows=qa.rows.filter(r=>r.returnRequestId!==payload.returnRequestId);return{orderId:payload.orderId,returnRequestId:payload.returnRequestId,transactionCode:'QA-RETURN-IN-ONLY'};
      }
      const delay=qa.delay,ignore=qa.ignoreAbort,failure=qa.failure;await new Promise(r=>setTimeout(r,delay));if(!ignore)options.signal?.throwIfAborted();
      if(failure)throw Object.assign(Error(failure===401?'Máy chủ từ chối xác thực.':'Không tải được dữ liệu mô phỏng.'),{status:failure===-1?undefined:failure});
      if(url==='/api/v1/warehouses')return structuredClone(records.warehouses);
      const match=url.match(/^\\/api\\/v1\\/warehouses\\/(\\d+)\\/(locations|return-requests)/);
      if(!match)throw Error('Unsupported QA API '+url);const warehouse=Number(match[1]);
      if(match[2]==='locations')return structuredClone(records.locations[warehouse]);
      let rows=qa.scenarios?(warehouse===qa.warehouse?qa.rows:[]):records.requests[warehouse];
      rows=rows.filter(r=>(!query.get('keyword')||r.orderCode.includes(query.get('keyword'))||r.trackingNumber.includes(query.get('keyword')))&&(!query.get('orderId')||r.orderId===Number(query.get('orderId')))&&(!query.get('returnRequestId')||r.returnRequestId===Number(query.get('returnRequestId'))));
      const page=Number(query.get('page')||1),pageSize=Number(query.get('pageSize')||10);
      return{warehouseId:warehouse,canReturnIn:true,page,pageSize,totalItems:rows.length,items:qa.shapeFailure?null:structuredClone(rows.slice((page-1)*pageSize,page*pageSize))};
    }};
    window.Auth={...window.Auth,getCurrentUser:async()=>({accountId:1,username:'isolated-qa',role:'WAREHOUSE_STAFF',branchId:qa.branch}),getPermissions:async()=>({known:true,codes:new Set(['KHO_XEM','KHO_NHAP'])})};
  `;
  fs.mkdirSync(profile,{recursive:true});const portFile=path.join(profile,'DevToolsActivePort');if(fs.existsSync(portFile))fs.unlinkSync(portFile);
  edge=spawn('C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',['--headless','--disable-gpu','--no-first-run','--no-default-browser-check','--remote-debugging-address=127.0.0.1','--remote-debugging-port=0','--user-data-dir='+profile,'about:blank'],{windowsHide:true,stdio:'ignore'});
  for(let i=0;i<100&&!fs.existsSync(portFile);i++)await sleep(100);
  const port=fs.readFileSync(portFile,'utf8').split('\n')[0],tabs=await(await fetch('http://127.0.0.1:'+port+'/json/list')).json();
  socket=new WebSocket(tabs.find(t=>t.type==='page').webSocketDebuggerUrl);await new Promise((r,j)=>{socket.addEventListener('open',r,{once:true});socket.addEventListener('error',j,{once:true});});
  socket.addEventListener('message',async event=>{const d=JSON.parse(event.data);if(d.id){const p=pending.get(d.id);pending.delete(d.id);d.error?p.reject(Error(d.error.message)):p.resolve(d.result);}else if(d.method==='Runtime.exceptionThrown')errors.push(d.params.exceptionDetails.text);else if(d.method==='Fetch.requestPaused'){
    try{const isAdapter=d.params.request.url.endsWith('/__return_qa__.js');const content=isAdapter?adapter:html.replace('<script src="./js/router.js','<script src="/__return_qa__.js" defer></script><script src="./js/router.js');await send('Fetch.fulfillRequest',{requestId:d.params.requestId,responseCode:200,responseHeaders:[{name:'Content-Type',value:isAdapter?'application/javascript; charset=utf-8':'text/html; charset=utf-8'}],body:Buffer.from(content).toString('base64')});}catch(e){errors.push(e.message);}
  }});
  await send('Page.enable');await send('Runtime.enable');await send('Fetch.enable',{patterns:[{urlPattern:appUrl+'/*',resourceType:'Document',requestStage:'Request'},{urlPattern:appUrl+'/__return_qa__.js',resourceType:'Script',requestStage:'Request'}]});
  for(const [width,height] of [[1366,768],[768,1024],[390,844]]){
    await send('Emulation.setDeviceMetricsOverride',{width,height,deviceScaleFactor:1,mobile:width<992});await send('Page.navigate',{url:appUrl+'/?returnQA='+width+'#/warehouse/returns'});await until(ready);await evaluate('document.fonts.ready');
    await check('one heading and one refresh '+width,"document.querySelectorAll('#page-content h2,#page-content h3').length===0&&document.getElementById('page-title').textContent==='Nhập hàng hoàn'&&document.getElementById('page-description').textContent==='Tiếp nhận hàng hoàn từ shipper và đưa vào vị trí lưu kho.'&&[...document.querySelectorAll('.page-heading button,#page-content button')].filter(n=>n.textContent==='Làm mới').length===1");
    await check('no tables, paging or links before choosing warehouse '+width,"document.querySelector('.orders-empty').textContent==='Chọn kho để xem yêu cầu hoàn'&&!document.querySelector('table')&&document.querySelector('.warehouse-list-footer').hidden&&document.querySelector('.return-links').hidden");
    await change('Kho',await evaluate('qa.warehouse'));await until(ready);
    await check('only return candidates API loads '+width,"qa.requests.every(r=>!r.url.includes('/inventory')&&!r.url.includes('/warehouse-transactions?')&&!r.url.includes('/orders/'))&&document.querySelectorAll('.warehouse-list').length===1");
    await check('links retain selected warehouse '+width,"[...document.querySelectorAll('.return-links a')].every(a=>new URL(a.href).hash.includes('warehouseId='+qa.warehouse))");
    const metrics=await evaluate("({width:innerWidth,pageWidth:document.documentElement.scrollWidth,emptyHeight:document.querySelector('.orders-empty')?.getBoundingClientRect().height,errors:qa.errors})");assert(metrics.pageWidth<=width);assert(!metrics.emptyHeight||metrics.emptyHeight<120);report.viewports.push(metrics);
    const picture=await send('Page.captureScreenshot',{format:'png',captureBeyondViewport:false});fs.writeFileSync(path.join(root,'docs/return-'+width+'.png'),Buffer.from(picture.data,'base64'));
  }
  await evaluate('qa.scenarios=true');await click('Làm mới');await until(ready);
  await check('only supplied columns and pagination when needed',"document.querySelectorAll('thead th').length===6&&!document.querySelector('.warehouse-list-footer').hidden&&document.querySelectorAll('tbody tr').length===10");
  for(const width of [1366,390]){await send('Emulation.setDeviceMetricsOverride',{width,height:844,deviceScaleFactor:1,mobile:width<992});await check('table scroll stays inside card '+width,"document.documentElement.scrollWidth<=innerWidth&&document.querySelector('.table-responsive').scrollWidth"+(width<992?'>':'>=')+"document.querySelector('.table-responsive').clientWidth");}
  await evaluate(`${control('Mã đơn / mã vận đơn')}.value='QA-RETURN-ONLY-001'`);await click('Tìm kiếm');await until(ready);
  await check('keyword filters server before pagination',"qa.requests.at(-1).url.includes('keyword=QA-RETURN-ONLY-001')&&document.querySelectorAll('tbody tr').length===1&&document.querySelector('.warehouse-list-footer').hidden");
  await evaluate(`${control('Mã đơn / mã vận đơn')}.value=''`);await evaluate(`${control('Mã đơn / mã vận đơn')}.focus()`);await send('Input.dispatchKeyEvent',{type:'keyDown',key:'Enter',code:'Enter',text:'\r',windowsVirtualKeyCode:13});await send('Input.dispatchKeyEvent',{type:'keyUp',key:'Enter',code:'Enter',windowsVirtualKeyCode:13});await until("!qa.requests.at(-1).url.includes('keyword=')&&document.querySelectorAll('tbody tr').length===10");
  await click('Sau ›');await until(ready);await check('page 2 loads from API',"qa.requests.at(-1).url.includes('page=2')&&document.querySelectorAll('tbody tr').length===2");await click('‹ Trước');await until(ready);
  await evaluate("qa.delay=100;document.querySelector('[data-stock-action]').click();document.querySelector('[data-stock-action]').click()");await until("document.querySelector('.return-dialog textarea')");
  await check('one modal, matching compound IDs, no order detail permission required',"document.querySelectorAll('dialog').length===1&&qa.requests.some(r=>r.url.includes('orderId=801')&&r.url.includes('returnRequestId=6001'))&&qa.requests.every(r=>!r.url.includes('/orders/'))");
  await check('condition options exactly match DTO',"[...document.querySelectorAll('.return-dialog select')[1].options].map(n=>n.value).join(',')===',NORMAL,DAMAGED,OTHER'");
  await click('Xác nhận nhập hàng hoàn');await check('location required before POST',"qa.writes.length===0");
  await change('Vị trí lưu kho *',await evaluate('qa.location'));await change('Tình trạng hàng *','DAMAGED');await click('Xác nhận nhập hàng hoàn');await check('damaged goods require notes',"qa.writes.length===0&&document.querySelector('dialog .alert-danger').textContent.includes('ghi chú')");
  await evaluate("document.querySelector('dialog textarea').value='QA damaged package';qa.delay=0");await evaluate("(()=>{const b=[...document.querySelectorAll('dialog button')].find(n=>n.textContent==='Xác nhận nhập hàng hoàn');b.click();b.click()})()");
  await check('submit and cancel locked while sending',"document.querySelector('dialog fieldset').disabled&&[...document.querySelectorAll('dialog button')].filter(n=>['Hủy','Xác nhận nhập hàng hoàn'].includes(n.textContent)).every(n=>n.disabled)");await until("!document.querySelector('dialog')");await until(ready);
  await check('one POST contains exact DTO and distinct request/order IDs',"qa.writes.length===1&&Object.keys(qa.writes[0]).sort().join(',')==='condition,locationId,notes,orderId,returnRequestId,warehouseId'&&qa.writes[0].orderId===801&&qa.writes[0].returnRequestId===6001&&qa.writes[0].warehouseId===qa.warehouse&&qa.writes[0].locationId===qa.location&&qa.writes[0].condition==='DAMAGED'&&qa.writes[0].notes==='QA damaged package'");
  await check('success closes, reports and refreshes candidates',"document.querySelector('.alert-success').textContent.includes('Đã nhập hàng hoàn')&&qa.requests.at(-1).method==='GET'&&![...document.querySelectorAll('tbody tr')].some(n=>n.textContent.includes('QA-RETURN-ONLY-001'))&&!document.querySelector('.modal-backdrop')");
  await evaluate('qa.writeStatus=409');await click('Nhận hàng hoàn');await until("document.querySelector('.return-dialog textarea')");await change('Vị trí lưu kho *',await evaluate('qa.location'));await click('Xác nhận nhập hàng hoàn');await until("document.querySelector('dialog .alert-danger')&&!document.querySelector('dialog[aria-busy=true]')");
  await check('409 shows backend message and refreshes without retry',"qa.writes.length===2&&document.querySelector('dialog .alert-danger').textContent.includes('Vị trí nhận hoàn đã thay đổi.')&&qa.requests.at(-1).method==='GET'&&[...document.querySelectorAll('dialog button')].find(n=>n.textContent==='Xác nhận nhập hàng hoàn').disabled");
  await click('Hủy');await check('cancel after conflict closes cleanly',"!document.querySelector('dialog')&&!document.body.classList.contains('modal-open')&&!document.querySelector('.modal-backdrop')");
  for(const status of [400,500]){
    await evaluate('qa.writeStatus='+status);await click('Nhận hàng hoàn');await until("document.querySelector('.return-dialog textarea')");await change('Vị trí lưu kho *',await evaluate('qa.location'));await change('Tình trạng hàng *','OTHER');await evaluate("document.querySelector('dialog textarea').value='QA preserve notes'");await click('Xác nhận nhập hàng hoàn');await until("document.querySelector('dialog .alert-danger')&&!document.querySelector('dialog[aria-busy=true]')");
    await check('error '+status+' preserves editable form and session',"document.querySelector('dialog textarea').value==='QA preserve notes'&&document.querySelectorAll('dialog select')[0].value===String(qa.location)&&document.querySelectorAll('dialog select')[1].value==='OTHER'&&!document.querySelector('dialog fieldset').disabled&&!document.querySelector('dialog').textContent.includes('hết hạn')&&!!ApiClient.getAccessToken()");await click('Hủy');
  }
  await evaluate("qa.rows[0].orderStatus='FAILED';qa.rows[1].requestStatus='COMPLETED'");await click('Làm mới');await until(ready);await check('FAILED order and completed request cannot be received',"[...document.querySelectorAll('[data-stock-action]')].slice(0,2).every(n=>n.disabled)");
  await evaluate('qa.resetRows();qa.shapeFailure=true');await click('Làm mới');await until(ready);await check('invalid API shape is a load error, not empty results',"!!document.querySelector('.alert-danger')&&!document.querySelector('table')&&[...document.querySelectorAll('#page-content button')].some(n=>n.textContent==='Thử lại')");await evaluate('qa.shapeFailure=false');await click('Thử lại');await until(ready);
  for(const failure of [401,403,500,-1]){await evaluate('qa.failure='+failure);await click('Làm mới');await until(ready);await check('read failure '+failure+' preserves session and offers retry',"!!document.querySelector('.alert-danger')&&!document.querySelector('.return-card').textContent.includes('hết hạn')&&!!ApiClient.getAccessToken()&&document.querySelector('.warehouse-list-footer').hidden");await evaluate('qa.failure=0');await click('Thử lại');await until(ready);}
  await evaluate('qa.delay=200;qa.ignoreAbort=true');await click('Làm mới');await change('Kho',await evaluate('qa.otherWarehouse'));await until("Router.current().query.warehouseId===qa.otherWarehouse&&document.querySelector('.orders-empty')?.textContent==='Không có yêu cầu hoàn phù hợp tại kho này'");await sleep(250);
  await check('changing warehouse resets page and rejects stale list',"Router.current().query.page===1&&!document.querySelector('table')&&document.querySelector('.warehouse-list-footer').hidden&&document.querySelector('.orders-empty').textContent==='Không có yêu cầu hoàn phù hợp tại kho này'");
  await evaluate('qa.delay=0;qa.ignoreAbort=false');await change('Kho',await evaluate('qa.warehouse'));await until(ready);await click('Nhận hàng hoàn');await until("document.querySelector('.return-dialog textarea')");
  await change('Kho',await evaluate('qa.otherWarehouse'));await until(ready);await check('warehouse change clears selected request and modal',"!document.querySelector('dialog')");
  await change('Kho',await evaluate('qa.warehouse'));await until(ready);await click('Nhận hàng hoàn');await until("document.querySelector('.return-dialog textarea')");await check('new selection has no old location',"document.querySelectorAll('dialog select')[0].value===''");await click('Hủy');
  for(let i=0;i<3;i++){await evaluate("Router.navigate('#/dashboard')");await until("Router.current().name==='overview'");await check('refresh control removed on leaving page '+i,"!document.querySelector('.return-refresh')");await evaluate("Router.navigate('#/warehouse/returns?warehouseId='+qa.warehouse)");await until(ready);}
  const before=await evaluate('qa.requests.length');await click('Tìm kiếm');await until(ready);assert.equal(await evaluate('qa.requests.length'),before+1);report.checks.push('remount search listener fires once');
  await check('no runtime exceptions',"qa.errors.length===0");assert.equal(errors.length,0);
  fs.writeFileSync(path.join(root,'docs/return-browser-verification.json'),JSON.stringify(report,null,2));console.log(JSON.stringify({checks:report.checks.length,viewports:report.viewports,sqlChecks:report.sqlChecks,consoleErrors:errors},null,2));
})().catch(e=>{console.error(e.stack);process.exitCode=1;}).finally(async()=>{try{if(socket?.readyState===1)await send('Browser.close')}catch(_){}socket?.close();edge?.kill();});
