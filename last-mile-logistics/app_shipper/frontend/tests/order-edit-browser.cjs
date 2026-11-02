"use strict";
// Opt-in contract QA in a headless tab. No PUT reaches the real API or database.
const fs = require('node:fs'), path = require('node:path');
const {spawn,execFile} = require('node:child_process'), {promisify} = require('node:util');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname,'../..'), profile = path.join(__dirname,'.artifacts/order-edit/edge-profile');
const appUrl = process.env.ORDER_EDIT_QA_URL || 'http://127.0.0.1:5500';
const sleep = ms => new Promise(r=>setTimeout(r,ms));
let edge,socket,id=0; const pending=new Map(),errors=[],checks=[];
function send(method,params={}) {return new Promise((resolve,reject)=>{const key=++id;pending.set(key,{resolve,reject});socket.send(JSON.stringify({id:key,method,params}));});}
async function evaluate(expression) {const r=await send('Runtime.evaluate',{expression,awaitPromise:true,returnByValue:true});if(r.exceptionDetails)throw Error(r.exceptionDetails.exception?.description||r.exceptionDetails.text);return r.result.value;}
async function until(expression) {for(let i=0;i<150;i++){if(await evaluate(expression))return;await sleep(40);}throw Error('Timed out: '+expression+' '+JSON.stringify(await evaluate('window.qa?.errors')));}
async function check(label,expression) {assert.equal(await evaluate(expression),true,label);checks.push(label);}
async function click(label) {await evaluate(`(()=>{const n=[...document.querySelectorAll('#page-content button')].find(n=>n.textContent===${JSON.stringify(label)});if(!n)throw Error('Missing '+${JSON.stringify(label)});n.click()})()`);}
const ready="document.querySelector('.order-form')&&!document.querySelector('#page-content [aria-busy=true]')";
(async()=>{
  const readArgs=['-NoProfile','-ExecutionPolicy','Bypass','-File',path.join(__dirname,'read-order-detail.ps1')];
  if(process.env.ORDER_EDIT_QA_ORDER_CODE)readArgs.push('-OrderCode',process.env.ORDER_EDIT_QA_ORDER_CODE);
  const {stdout}=await promisify(execFile)('powershell.exe',readArgs,{windowsHide:true,maxBuffer:2*1024*1024});
  const parsedOrders=JSON.parse(stdout), realOrders=Array.isArray(parsedOrders)?parsedOrders:[parsedOrders], real=realOrders[0];assert(real?.version&&real.senderId&&real.receiverId&&real.serviceId);
  const html=await(await fetch(appUrl+'/')).text();assert(html.includes('js/orders.js'));
  const adapter=`
    window.qa={errors:[],requests:[],writes:[],writeStatus:200,customerDelay:100,permissions:['DONHANG_XEM','DONHANG_CAPNHAT']};
    addEventListener('error',e=>qa.errors.push(e.message));addEventListener('unhandledrejection',e=>qa.errors.push(String(e.reason)));
    qa.order={...${JSON.stringify(real)},status:'NEW',statusName:'Mới tạo',pickupAddressId:null,deliveryAddressId:402,requiresAddressSelection:true};
    const original=window.ApiClient;
    window.ApiClient={...original,getAccessToken:()=> 'isolated-qa',getRefreshToken:()=>null,request:async(url,options={})=>{
      qa.requests.push({url,method:options.method||'GET'});
      if(options.method==='PUT'){
        if(url!=='/api/v1/orders/'+qa.order.id)throw Error('Unexpected mutation');qa.writes.push(JSON.parse(options.body));await new Promise(r=>setTimeout(r,100));
        if(qa.writeStatus!==200)throw Object.assign(Error('Isolated edit conflict'),{status:qa.writeStatus});
        return {id:qa.order.id,status:'NEW',version:'AAAAAAAAAAI=',message:'Đã sửa đơn.'};
      }
      if(options.method&&options.method!=='GET')throw Error('Real mutations prohibited in QA');
      if(url==='/api/v1/orders/'+qa.order.id)return structuredClone(qa.order);
      if(url==='/api/v1/order-form/options')return{branches:[{id:qa.order.branchId,name:'QA branch'}],services:[{id:qa.order.serviceId,name:'QA service'}]};
      if(url.startsWith('/api/v1/customers?'))return{page:1,pageSize:20,totalItems:2,items:[{id:qa.order.senderId,fullName:'QA sender'},{id:qa.order.receiverId,fullName:'QA receiver'}]};
      const match=url.match(/^\\/api\\/v1\\/customers\\/(\\d+)(\\/addresses)?$/);
      if(match){await new Promise(r=>setTimeout(r,qa.customerDelay));options.signal?.throwIfAborted();const customer=Number(match[1]);
        if(!match[2])return{id:customer,fullName:customer===qa.order.senderId?'QA sender':'QA receiver',isActive:true};
        return{customerId:customer,addresses:customer===qa.order.senderId?[{id:301,address:'QA pickup',isDefault:true},{id:302,address:'QA pickup alternative'}]:[{id:401,address:'QA delivery default',isDefault:true},{id:402,address:'QA delivery saved'}]};
      }
      throw Error('Unsupported QA route '+url);
    }};
    window.Auth={...window.Auth,getCurrentUser:async()=>({accountId:1,username:'isolated-qa',role:'BRANCH_MANAGER',branchId:qa.order.branchId}),getPermissions:async()=>({known:true,codes:new Set(qa.permissions)})};
  `;
  fs.mkdirSync(profile,{recursive:true});const portFile=path.join(profile,'DevToolsActivePort');if(fs.existsSync(portFile))fs.unlinkSync(portFile);
  edge=spawn('C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',['--headless','--disable-gpu','--no-first-run','--no-default-browser-check','--remote-debugging-address=127.0.0.1','--remote-debugging-port=0','--user-data-dir='+profile,'about:blank'],{windowsHide:true,stdio:'ignore'});
  for(let i=0;i<100&&!fs.existsSync(portFile);i++)await sleep(100);
  const port=fs.readFileSync(portFile,'utf8').split('\n')[0],tabs=await(await fetch('http://127.0.0.1:'+port+'/json/list')).json();
  socket=new WebSocket(tabs.find(t=>t.type==='page').webSocketDebuggerUrl);await new Promise((r,j)=>{socket.addEventListener('open',r,{once:true});socket.addEventListener('error',j,{once:true});});
  socket.addEventListener('message',async event=>{const d=JSON.parse(event.data);if(d.id){const p=pending.get(d.id);pending.delete(d.id);d.error?p.reject(Error(d.error.message)):p.resolve(d.result);}else if(d.method==='Runtime.exceptionThrown')errors.push(d.params.exceptionDetails.text);else if(d.method==='Fetch.requestPaused'){
    try{const isAdapter=d.params.request.url.endsWith('/__order_edit_qa__.js');const content=isAdapter?adapter:html.replace('<script src="./js/router.js','<script src="/__order_edit_qa__.js" defer></script><script src="./js/router.js');await send('Fetch.fulfillRequest',{requestId:d.params.requestId,responseCode:200,responseHeaders:[{name:'Content-Type',value:isAdapter?'application/javascript; charset=utf-8':'text/html; charset=utf-8'}],body:Buffer.from(content).toString('base64')});}catch(e){errors.push(e.message);}
  }});
  await send('Page.enable');await send('Runtime.enable');await send('Fetch.enable',{patterns:[{urlPattern:appUrl+'/*',resourceType:'Document',requestStage:'Request'},{urlPattern:appUrl+'/__order_edit_qa__.js',resourceType:'Script',requestStage:'Request'}]});
  await send('Page.navigate',{url:appUrl+'/#/orders/'+real.id});await until("document.querySelector('.order-detail-code')");
  await check('NEW order with unknown address allows editing',"[...document.querySelectorAll('.order-detail-actions button')].some(n=>n.textContent==='Sửa'&&!n.disabled)&&document.querySelector('.alert-info').textContent.includes('chọn lại địa chỉ')");
  await click('Sửa');await until("document.querySelector('.order-form')");
  await check('form cannot save while customer data initializes',"document.querySelector('.order-form>fieldset').disabled");await until(ready);
  await check('update-only user opens form without quote requiring create permission',"!document.querySelector('.order-form').textContent.includes('Lấy báo giá')&&document.querySelectorAll('.order-customer').length===2");
  await check('unknown pickup address is not silently replaced by default',"document.querySelectorAll('.order-customer select')[1].value===''");
  await check('known customer address is selected by its ID',"document.querySelectorAll('.order-customer select')[3].value==='402'");
  await check('original delivery snapshot remains visible',"document.querySelector('.order-form').textContent.includes('Địa chỉ trên đơn hiện tại:')");
  await click('Lưu thay đổi');await check('missing address blocks PUT',"qa.writes.length===0");
  await evaluate("(()=>{const n=document.querySelectorAll('.order-customer select')[1];n.value='302';n.dispatchEvent(new Event('change',{bubbles:true}))})()");
  for(const width of [1366,390]){await send('Emulation.setDeviceMetricsOverride',{width,height:844,deviceScaleFactor:1,mobile:width<992});await check('edit form fits viewport '+width,"document.documentElement.scrollWidth<=innerWidth");}
  await evaluate("(()=>{const b=[...document.querySelectorAll('.order-form button')].find(n=>n.textContent==='Lưu thay đổi');b.click();b.click()})()");
  await check('save locks form while sending',"document.querySelector('.order-form>fieldset').disabled");await until("Router.current().name==='order-detail'&&document.querySelector('.alert-success')");
  await check('PUT sends complete DTO and exact expectedVersion once',"qa.writes.length===1&&qa.writes[0].expectedVersion===qa.order.version&&qa.writes[0].senderId===qa.order.senderId&&qa.writes[0].receiverId===qa.order.receiverId&&qa.writes[0].pickupAddressId===302&&qa.writes[0].deliveryAddressId===402&&qa.writes[0].serviceId===qa.order.serviceId&&qa.writes[0].items.length===qa.order.items.length");
  await check('save returns to correct detail',"Router.current().params.id===qa.order.id");
  await evaluate("qa.order.pickupAddressId=301;qa.order.requiresAddressSelection=false;qa.writeStatus=409");await click('Sửa');await until(ready);
  await check('matched address automatically preloads exact ID',"document.querySelectorAll('.order-customer select')[1].value==='301'");
  await click('Lưu thay đổi');await until("document.querySelector('.order-form button[type=submit]').disabled&&!document.querySelector('#page-content [aria-busy=true]')");
  await check('409 keeps entered form and blocks duplicate PUT',"qa.writes.length===2&&document.querySelector('.order-form')&&document.querySelector('#page-content').textContent.includes('Tải lại dữ liệu mới')");
  await click('Lưu thay đổi');await sleep(150);await check('409 never auto retries PUT',"qa.writes.length===2");
  await click('Tải lại dữ liệu mới');await until("Router.current().name==='order-detail'&&document.querySelector('.order-detail-code')");
  await evaluate("qa.order.status='COMPLETED';Router.reload()");await until("document.querySelector('.order-detail-code')&&!document.querySelector('#page-content [aria-busy=true]')");
  await check('completed orders remain uneditable',"![...document.querySelectorAll('.order-detail-actions button')].some(n=>n.textContent==='Sửa')");
  await evaluate("qa.order.status='NEW';qa.order.version=null;Router.reload()");await until("document.querySelector('.order-detail-code')&&!document.querySelector('#page-content [aria-busy=true]')");
  await check('missing version still locks edit with a specific reason',"[...document.querySelectorAll('.order-detail-actions button')].find(n=>n.textContent==='Sửa').disabled&&document.querySelector('.alert-warning').textContent.includes('phiên bản dữ liệu')&&[...document.querySelectorAll('.alert-warning button')].some(n=>n.textContent==='Tải lại chi tiết')");
  await check('no console errors',"qa.errors.length===0");assert.equal(errors.length,0);
  const result={mode:'Actual detail SQL read + isolated edit contract fixture; no real PUT',actualOrders:realOrders.map(o=>({id:o.id,status:o.status,requiresAddressSelection:o.requiresAddressSelection,hasVersion:!!o.version})),checks,consoleErrors:errors};
  fs.writeFileSync(path.join(__dirname,'.artifacts/order-edit/order-edit-browser-verification.json'),JSON.stringify(result,null,2));console.log(JSON.stringify({checks:checks.length,consoleErrors:errors,actualOrders:result.actualOrders}));
})().catch(e=>{console.error(e.stack);process.exitCode=1;}).finally(async()=>{try{if(socket?.readyState===1)await send('Browser.close')}catch(_){}socket?.close();edge?.kill();});
