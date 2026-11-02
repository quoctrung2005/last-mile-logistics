"use strict";
// Real app/router/forms in headless Edge; all API calls are isolated fixtures.
// No database access and no real order writes.
const fs=require("node:fs"),path=require("node:path"),http=require("node:http"),assert=require("node:assert/strict"),crypto=require("node:crypto");
const {spawn}=require("node:child_process"),{createServer}=require("../dev-server.cjs");
const root=path.resolve(__dirname,"../.."),artifact=path.join(__dirname,".artifacts/order-unsaved");
const profile=path.join(artifact,"edge-"+crypto.randomBytes(8).toString("hex"));
const checks=[],errors=[],dialogs=[],pending=new Map();let server,edge,socket,origin,serial=0,nativeAccept=false;
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
function send(method,params={}){return new Promise((resolve,reject)=>{const id=++serial;pending.set(id,{resolve,reject});socket.send(JSON.stringify({id,method,params}));});}
async function evaluate(expression,userGesture=false){const r=await send("Runtime.evaluate",{expression,awaitPromise:true,returnByValue:true,userGesture});if(r.exceptionDetails)throw Error(r.exceptionDetails.exception?.description||r.exceptionDetails.text);return r.result.value;}
async function until(expression){for(let i=0;i<300;i++){if(await evaluate(`(()=>{try{return Boolean(${expression})}catch{return false}})()`))return;await sleep(30);}throw Error("Timed out: "+expression+" "+await evaluate("document.querySelector('#page-content')?.textContent"));}
async function check(label,expression){assert.equal(await evaluate(expression),true,label);checks.push(label);}
const ready="document.querySelector('.order-form')&&!document.querySelector('.order-form>fieldset').disabled&&!document.querySelector('#page-content [aria-busy=true]')";
const detail="Router.current()?.name==='order-detail'&&document.querySelector('.order-detail-code')&&!document.querySelector('#page-content [aria-busy=true]')";
const list="Router.current()?.name==='orders'&&document.querySelector('.orders-table')";
const control=label=>`document.getElementById([...document.querySelectorAll('.order-form label')].find(n=>n.textContent===${JSON.stringify(label)}).htmlFor)`;
const change=(label,value)=>evaluate(`(()=>{const n=${control(label)};n.value=${JSON.stringify(String(value))};n.dispatchEvent(new Event('input',{bubbles:true}));n.dispatchEvent(new Event('change',{bubbles:true}));})()`);
const click=label=>evaluate(`(()=>{const n=[...document.querySelectorAll('#page-content button,#page-content a')].find(n=>n.textContent===${JSON.stringify(label)});if(!n)throw Error('Missing '+${JSON.stringify(label)});n.click();})()`);
async function openEdit(){await evaluate("qa.confirmNext=true;Router.navigate('#/orders/'+qa.order.id+'/edit')");await until(ready);await evaluate("qa.confirmNext=false;qa.formRef=document.querySelector('.order-form')");}
async function openCreate(){await evaluate("qa.confirmNext=true;Router.navigate('#/orders/create')");await until(ready);await evaluate("qa.confirmNext=false;qa.formRef=document.querySelector('.order-form')");}
const beforeUnload="(()=>{const e=new Event('beforeunload',{cancelable:true});window.dispatchEvent(e);return e.defaultPrevented;})()";

const adapter=`
window.qa={documentId:crypto.randomUUID(),errors:[],confirms:[],alerts:[],confirmNext:false,loggedIn:true,signouts:0,writes:[],requests:[],status:200,holdWrite:false,holdAddresses:false,beforeListeners:new Set()};
const originalAdd=window.addEventListener.bind(window),originalRemove=window.removeEventListener.bind(window);
window.addEventListener=(name,fn,...rest)=>{if(name==='beforeunload')qa.beforeListeners.add(fn);originalAdd(name,fn,...rest);};
window.removeEventListener=(name,fn,...rest)=>{if(name==='beforeunload')qa.beforeListeners.delete(fn);originalRemove(name,fn,...rest);};
addEventListener('error',e=>qa.errors.push(e.message));addEventListener('unhandledrejection',e=>qa.errors.push(String(e.reason)));
window.confirm=message=>{qa.confirms.push(message);return qa.confirmNext;};window.alert=message=>qa.alerts.push(message);
qa.order={id:17,orderCode:'QA-ORDER-17',trackingNumber:'QA-TRACK-17',status:'NEW',statusName:'Mới tạo',version:'AAAAAAAAAAE=',branchId:1,branchName:'QA branch',
senderId:1,receiverId:2,senderName:'QA sender',receiverName:'QA receiver',serviceId:1,serviceName:'QA service',pickupAddressId:101,deliveryAddressId:201,
priority:3,codAmount:0,declaredValue:0,notes:'Initial QA note',requestedDeliveryAt:'2030-01-01T02:00:00Z',expectedDeliveryAt:'2030-01-02T02:00:00Z',
weightKg:1,items:[{name:'QA parcel',type:'QA type',quantity:1,unitWeightKg:1,lengthCm:10,widthCm:10,heightCm:10,value:0,fragile:false,notes:''}],deliveryPoints:[],fees:[]};
const delay=ms=>new Promise(r=>setTimeout(r,ms));
window.ApiClient={...window.ApiClient,getAccessToken:()=>qa.loggedIn?'isolated-qa':null,getRefreshToken:()=>null,clearTokens:()=>{qa.loggedIn=false;},request:async(url,options={})=>{
 const method=options.method||'GET';qa.requests.push({url,method});options.signal?.throwIfAborted();
 if((method==='POST'&&url==='/api/v1/orders')||(method==='PUT'&&url==='/api/v1/orders/'+qa.order.id)){
  const body=JSON.parse(options.body);qa.writes.push({method,body});
  if(qa.holdWrite)await new Promise((resolve,reject)=>{qa.releaseWrite=resolve;options.signal?.addEventListener('abort',()=>reject(new DOMException('Aborted','AbortError')),{once:true});});else await delay(80);
  options.signal?.throwIfAborted();
  if(qa.status!==200)throw Object.assign(Error(qa.unknownResult?'Không đọc được kết quả xử lý. Hãy tải lại để kiểm tra trạng thái.':qa.status===0?'Chưa xác định được kết quả thao tác. Hãy tải lại dữ liệu để kiểm tra.':'QA save error '+qa.status),{status:qa.status||undefined,resultUnknown:qa.status===0||qa.unknownResult===true,networkError:qa.status===0});
  qa.order={...qa.order,...body,id:method==='POST'?18:qa.order.id,version:'AAAAAAAAAAI='};return{id:qa.order.id,status:'NEW',message:'Đã lưu đơn QA.'};
 }
 if(url==='/api/v1/shipping-fees/quote'&&method==='POST')return{distanceKm:2,weightKg:1,baseFee:1000,distanceFee:0,weightFee:0,shippingFee:1000,serviceName:'QA service',quotedAt:new Date().toISOString()};
 if(method==='POST'&&url==='/api/v1/orders/'+qa.order.id+'/confirm'){qa.writes.push({method,body:JSON.parse(options.body),action:'confirm'});await delay(50);throw Object.assign(Error('Không đọc được kết quả xử lý. Hãy tải lại để kiểm tra trạng thái.'),{status:500,resultUnknown:true});}
 if(method!=='GET')throw Error('Unexpected mutation in isolated QA');
 if(url==='/api/v1/order-form/options'){await delay(30);return{branches:[{id:1,name:'QA branch'}],services:[{id:1,name:'QA service'},{id:2,name:'QA service 2'}]};}
 if(url==='/api/v1/orders/'+qa.order.id)return structuredClone(qa.order);
 if(url.startsWith('/api/v1/orders?'))return{page:1,pageSize:20,totalItems:1,items:[structuredClone(qa.order)]};
 if(url.startsWith('/api/v1/customers?'))return{page:1,pageSize:20,totalItems:3,items:[{id:1,fullName:'QA sender'},{id:2,fullName:'QA receiver'},{id:3,fullName:'QA other customer'}]};
 const match=url.match(/^\\/api\\/v1\\/customers\\/(\\d+)(\\/addresses)?$/);
 if(match){await delay(60);if(qa.holdAddresses&&match[2])await new Promise(resolve=>qa.releaseAddresses=resolve);options.signal?.throwIfAborted();const id=Number(match[1]);return match[2]?{customerId:id,addresses:[{id:id*100+1,address:'QA address '+id,isDefault:true},{id:id*100+2,address:'QA alternative '+id}]}:{id,fullName:'QA customer '+id,isActive:true};}
 throw Error('Unsupported QA API '+url);
}};
window.Auth={...window.Auth,getCurrentUser:async()=>({accountId:1,username:'isolated-qa',role:'BRANCH_MANAGER',branchId:1}),getPermissions:async()=>({known:true,codes:new Set(['DONHANG_XEM','DONHANG_CAPNHAT','DONHANG_TAO'])}),logout:async()=>{qa.loggedIn=false;qa.signouts++;}};
`;

(async()=>{
  const html=fs.readFileSync(path.join(root,"frontend/index.html"),"utf8").replace('<script src="./js/router.js','<script src="/__unsaved_qa__.js" defer></script><script src="./js/router.js');
  const staticHandler=createServer(new URL("http://127.0.0.1:1")).listeners("request")[0];
  server=http.createServer((req,res)=>{
    if(req.url==="/"||req.url.startsWith("/?")){res.writeHead(200,{"Content-Type":"text/html; charset=utf-8"});res.end(html);}
    else if(req.url==="/__unsaved_qa__.js"){res.writeHead(200,{"Content-Type":"application/javascript; charset=utf-8"});res.end(adapter);}
    else if(req.url.startsWith("/api/")){errors.push("Real API call attempted");res.writeHead(500);res.end();}
    else staticHandler(req,res);
  });
  await new Promise(r=>server.listen(0,"127.0.0.1",r));origin="http://127.0.0.1:"+server.address().port;
  fs.mkdirSync(profile,{recursive:true});
  edge=spawn("C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe",["--headless","--disable-gpu","--no-first-run","--no-default-browser-check","--remote-debugging-address=127.0.0.1","--remote-debugging-port=0","--user-data-dir="+profile,"about:blank"],{windowsHide:true,stdio:"ignore"});
  const portFile=path.join(profile,"DevToolsActivePort");for(let i=0;i<150&&!fs.existsSync(portFile);i++)await sleep(100);
  const port=fs.readFileSync(portFile,"utf8").split("\n")[0],tabs=await(await fetch("http://127.0.0.1:"+port+"/json/list")).json();
  socket=new WebSocket(tabs.find(t=>t.type==="page").webSocketDebuggerUrl);await new Promise((r,j)=>{socket.addEventListener("open",r,{once:true});socket.addEventListener("error",j,{once:true});});
  socket.addEventListener("message",event=>{const data=JSON.parse(event.data);if(data.id){const item=pending.get(data.id);pending.delete(data.id);data.error?item.reject(Error(data.error.message)):item.resolve(data.result);}else if(data.method==="Runtime.exceptionThrown")errors.push(data.params.exceptionDetails.text);else if(data.method==="Page.javascriptDialogOpening"){dialogs.push(data.params);send("Page.handleJavaScriptDialog",{accept:nativeAccept}).catch(e=>errors.push(e.message));}});
  await send("Page.enable");await send("Runtime.enable");await send("Page.navigate",{url:origin+"/#/orders"});await until("Router.current()?.name==='orders'&&document.querySelector('.orders-card')");
  await openEdit();
  await check("Initial options, customer/address hydration and item population leave edit form clean","Router.canLeave()&&qa.beforeListeners.size===1&&qa.confirms.length===0");
  assert.equal(await evaluate(beforeUnload),false);
  await click("Quay lại");await until(detail);await check("Untouched Back link leaves without a prompt and removes beforeunload","qa.confirms.length===0&&qa.beforeListeners.size===0");
  await openCreate();await check("Untouched create form is clean after options initialize","Router.canLeave()");await click("Đóng");await until("Router.current()?.name==='orders'");
  await openEdit();await click("Tính phí tham khảo");await until("document.querySelector('.order-form').textContent.includes('Kết quả báo giá tham khảo')&&!document.querySelector('.order-form>fieldset').disabled");
  await evaluate("(()=>{const n=document.querySelector('.order-customer input[type=search]');n.value='QA search only';n.dispatchEvent(new Event('input',{bubbles:true}));})()");await click("Tìm");
  await check("Quote output and customer search are not order edits","Router.canLeave()&&qa.confirms.length===0");
  for(const [label,value] of [["Ghi chú","QA dirty"],["Dịch vụ *","2"],["Độ ưu tiên (1–5) *","4"],["COD (VND) *","500"],["Giá trị khai báo (VND) *","500"],["Thời gian yêu cầu giao","2030-01-01T10:00:00"],["Hạn giao *","2030-01-03T10:00:00"],["Tên hàng *","QA changed parcel"],["Số lượng *","2"],["Dài (cm) *","11"]]){
    const old=await evaluate(control(label)+".value");await change(label,value);assert.equal(await evaluate("Router.canLeave()"),false,label);await change(label,old);assert.equal(await evaluate("Router.canLeave()"),true,label+" reverted");
  }
  checks.push("General fields, delivery times and item edits become dirty; restoring original values becomes clean");
  await evaluate("(()=>{const n=document.querySelectorAll('.order-customer select')[1];n.value='102';n.dispatchEvent(new Event('change',{bubbles:true}));})()");await check("Address choice is tracked","!Router.canLeave()");
  await evaluate("(()=>{const n=document.querySelectorAll('.order-customer select')[1];n.value='101';n.dispatchEvent(new Event('change',{bubbles:true}));const c=document.querySelectorAll('.order-customer select')[0];c.value='3';c.dispatchEvent(new Event('change',{bubbles:true}));})()");
  await until("document.querySelectorAll('.order-customer select')[1].value==='301'");await check("Customer choice and its asynchronously filled default address are tracked","!Router.canLeave()");
  await change("Ghi chú","Keep this draft");
  for(const action of ["Đóng","Quay lại","menu"]){
    const count=await evaluate("qa.confirms.length");
    if(action==="menu")await evaluate("document.querySelector('a[data-page=orders]').click()");else await click(action);
    await until("qa.confirms.length==="+(count+1)+"&&location.hash.includes('/edit')");
    await check("Reject "+action+" preserves the same form and draft","document.querySelector('.order-form')===qa.formRef&&"+control("Ghi chú")+".value==='Keep this draft'");
  }
  await evaluate("qa.confirmNext=true");await click("Đóng");await until(detail);await check("Accept leaving destroys the form and its unload listener","!document.querySelector('.order-form')&&qa.beforeListeners.size===0");

  await openEdit();await click("+ Thêm hàng");await check("Adding an item is dirty","!Router.canLeave()&&document.querySelectorAll('.order-item').length===2");
  await evaluate("document.querySelectorAll('.order-item')[1].querySelector('button').click()");await check("Removing the added row restores the initial snapshot","Router.canLeave()");
  await click("Xóa hàng");await check("Removing an original item is dirty","!Router.canLeave()&&document.querySelectorAll('.order-item').length===0");await evaluate("qa.confirmNext=true");await click("Đóng");await until(detail);

  await openEdit();await change("Ghi chú","Back draft");
  await evaluate("history.back()");await until("qa.confirms.at(-1)?.includes('chưa lưu')&&location.hash.endsWith('/edit')");await check("Cancelled browser Back preserves the original entry and form","document.querySelector('.order-form')===qa.formRef");
  await evaluate("qa.confirmNext=true;history.back()");await until(detail);
  await evaluate("history.forward()");await until(ready);await click("Đóng");await until(detail);await evaluate("history.back()");await until(ready);
  await evaluate("qa.confirmNext=false;qa.formRef=document.querySelector('.order-form')");await change("Ghi chú","Forward draft");
  const countForward=await evaluate("qa.confirms.length");await evaluate("history.forward()");await until("qa.confirms.length==="+(countForward+1)+"&&location.hash.endsWith('/edit')");
  await check("Cancelled Forward keeps the draft and correct history position","document.querySelector('.order-form')===qa.formRef");await evaluate("qa.confirmNext=true;history.forward()");await until(detail);

  for(const status of [400,409,500]){
    await openEdit();await change("Ghi chú","Failed draft "+status);await evaluate("qa.status="+status);const count=await evaluate("qa.writes.length");await click("Lưu thay đổi");
    await until("document.querySelector('#page-content').textContent.includes('QA save error "+status+"')&&!document.querySelector('#page-content [aria-busy=true]')");
    await check("Save "+status+" retains dirty content without automatic resubmission",control("Ghi chú")+".value==='Failed draft "+status+"'&&qa.writes.length==="+(count+1)+"&&!Router.canLeave()");
    assert.equal(await evaluate(beforeUnload),true);
    if(status===409)await check("409 stays blocked with the original version","document.querySelector('.order-form button[type=submit]').disabled&&qa.writes.at(-1).body.expectedVersion===qa.order.version");
    await evaluate("qa.confirmNext=true");await click("Đóng");await until(detail);
  }
  await openEdit();await change("Ghi chú","Successful draft");await evaluate("qa.status=200;qa.holdWrite=true");const count=await evaluate("qa.writes.length"),prompts=await evaluate("qa.confirms.length");
  await click("Lưu thay đổi");await until("qa.writes.length==="+(count+1));await evaluate("document.querySelector('.order-form').dispatchEvent(new Event('submit',{bubbles:true,cancelable:true}))");
  await evaluate("document.querySelector('a[data-page=orders]').click()");await until("qa.alerts.length>0&&location.hash.endsWith('/edit')");
  await check("Saving blocks internal leave and duplicate submits with an explanatory message","qa.writes.length==="+(count+1)+"&&document.querySelector('.order-form>fieldset').disabled&&qa.alerts.at(-1).includes('Đang lưu đơn')&&qa.confirms.length==="+prompts);
  assert.equal(await evaluate(beforeUnload),true);
  await evaluate("qa.holdWrite=false;qa.releaseWrite()");await until(detail);
  await check("Successful save opens detail without discard confirmation and cleans its guard","qa.confirms.length==="+prompts+"&&qa.beforeListeners.size===0&&qa.writes.at(-1).body.expectedVersion==='AAAAAAAAAAE='&&qa.writes.at(-1).body.expectedDeliveryAt==='2030-01-02T02:00:00.000Z'");

  async function fillCreate(){
    await change("Dịch vụ *","1");await change("Hạn giao *","2030-01-02T10:00:00");await change("Tên hàng *","QA created parcel");await change("Kg / đơn vị *","1");for(const name of ["Dài (cm) *","Rộng (cm) *","Cao (cm) *"])await change(name,"10");
    await evaluate("[...document.querySelectorAll('.order-customer')].forEach((box,i)=>{const n=box.querySelector('select');n.value=String(i+1);n.dispatchEvent(new Event('change',{bubbles:true}));})");await until("[...document.querySelectorAll('.order-customer')].every(box=>box.querySelectorAll('select')[1].value)");
  }
  for(const status of [400,409,500]){
    await openCreate();await fillCreate();await change("Ghi chú","Create failed "+status);await evaluate("qa.status="+status);const count=await evaluate("qa.writes.length");await click("Tạo đơn");
    await until("document.querySelector('#page-content').textContent.includes('QA save error "+status+"')&&!document.querySelector('#page-content [aria-busy=true]')");
    await check("Create "+status+" retains its draft and leave warning without retry",control("Ghi chú")+".value==='Create failed "+status+"'&&qa.writes.length==="+(count+1)+"&&!Router.canLeave()");
    await evaluate("qa.confirmNext=true");await click("Đóng");await until("Router.current()?.name==='orders'");
  }
  await openCreate();await fillCreate();await evaluate("qa.status=200");const createPrompts=await evaluate("qa.confirms.length");await click("Tạo đơn");await until(detail);
  await check("Create saves its full form and reaches detail without a discard prompt","qa.writes.at(-1).method==='POST'&&!('expectedVersion' in qa.writes.at(-1).body)&&qa.confirms.length==="+createPrompts+"&&qa.beforeListeners.size===0");
  await openEdit();await change("Ghi chú","Uncertain draft");await evaluate("qa.status=0");await click("Lưu thay đổi");await until("document.querySelector('.order-form button[type=submit]').disabled&&!document.querySelector('#page-content [aria-busy=true]')");
  await check("Unknown write result keeps draft, blocks resubmission and asks to verify orders","document.querySelector('#page-content').textContent.includes('Kiểm tra danh sách đơn')&&!Router.canLeave()");await evaluate("qa.confirmNext=true");await click("Đóng");await until(detail);
  await openEdit();await change("Ghi chú","SQL result draft");await evaluate("qa.status=500;qa.unknownResult=true");const sqlWrites=await evaluate("qa.writes.length");await click("Lưu thay đổi");await until("document.querySelector('.order-form button[type=submit]').disabled&&!document.querySelector('#page-content [aria-busy=true]')");
  await check("SQL result 500 preserves draft, displays reload guidance and blocks another send",control("Ghi chú")+".value==='SQL result draft'&&qa.writes.length==="+(sqlWrites+1)+"&&document.querySelector('#page-content').textContent.includes('Không đọc được kết quả xử lý. Hãy tải lại để kiểm tra trạng thái.')&&document.querySelector('#page-content').textContent.includes('Kiểm tra danh sách đơn')");await click("Lưu thay đổi");await check("A blocked SQL result cannot resubmit the write","qa.writes.length==="+(sqlWrites+1));await evaluate("qa.confirmNext=true;qa.unknownResult=false");await click("Đóng");await until(detail);
  const confirmWrites=await evaluate("qa.writes.length");await click("Xác nhận");await until("document.querySelector('dialog button[type=submit]')");await evaluate("document.querySelector('dialog button[type=submit]').click()");await until("document.querySelector('dialog button[type=submit]').disabled&&!document.querySelector('dialog [aria-busy=true]')&&document.querySelector('dialog').textContent.includes('Tải lại chi tiết')");
  await check("Confirmation SQL result error keeps the dialog, reload guidance and blocks another submit","document.querySelector('dialog').textContent.includes('Không đọc được kết quả xử lý. Hãy tải lại để kiểm tra trạng thái.')&&qa.writes.length==="+(confirmWrites+1));await evaluate("document.querySelector('dialog button[type=submit]').click()");await check("Confirmation SQL result error never resends automatically or via disabled submit","qa.writes.length==="+(confirmWrites+1));await click("Quay lại");await until("!document.querySelector('dialog')");
  await openEdit();await change("Ghi chú","Logout draft");await evaluate("document.getElementById('header-signout').click()");await check("Cancelled logout remains in the existing auth flow","qa.signouts===0&&document.querySelector('.order-form')===qa.formRef");
  await evaluate("qa.confirmNext=true;document.getElementById('header-signout').click()");await until("Router.current()?.name==='login'");await check("Confirmed logout reaches Login and cleans order guard","qa.signouts===1&&qa.beforeListeners.size===0");
  await send("Page.navigate",{url:origin+"/?qa=expiry#/orders"});await until("Router.current()?.name==='orders'");await openEdit();await change("Ghi chú","Expired draft");const expiryPrompts=await evaluate("qa.confirms.length");
  await evaluate("qa.loggedIn=false;window.dispatchEvent(new CustomEvent('auth:expired'))");await until("Router.current()?.name==='login'");await check("Session expiry bypasses the discard prompt and cleans listeners","qa.confirms.length==="+expiryPrompts+"&&qa.beforeListeners.size===0");

  await send("Page.navigate",{url:origin+"/?qa=native#/orders"});await until("Router.current()?.name==='orders'");await openEdit();
  async function realEdit(){const point=await evaluate("(()=>{const n="+control("Ghi chú")+";n.scrollIntoView({block:'center'});const r=n.getBoundingClientRect();return{x:r.x+20,y:r.y+10};})()");await send("Input.dispatchMouseEvent",{type:"mousePressed",button:"left",clickCount:1,...point});await send("Input.dispatchMouseEvent",{type:"mouseReleased",button:"left",clickCount:1,...point});await evaluate(control("Ghi chú")+".focus()",true);await send("Input.insertText",{text:" native draft"});assert.equal(await evaluate(control("Ghi chú")+".value.includes('native draft')"),true);}
  await realEdit();nativeAccept=false;let nativeCount=dialogs.length;await send("Page.reload",{ignoreCache:true});for(let i=0;i<100&&dialogs.length===nativeCount;i++)await sleep(30);
  assert.equal(dialogs.at(-1)?.type,"beforeunload");assert.equal(dialogs.length,nativeCount+1);await check("Native beforeunload cancels real reload and preserves draft","document.querySelector('.order-form')===qa.formRef&&"+control("Ghi chú")+".value.includes('native draft')");
  nativeAccept=true;nativeCount=dialogs.length;const oldDocument=await evaluate("qa.documentId");await send("Page.reload",{ignoreCache:true});await until("window.qa?.documentId!=="+JSON.stringify(oldDocument)+"&&("+ready+")");assert.equal(dialogs.length,nativeCount+1);await check("Accepting native reload discards edits and initializes a clean form","Router.canLeave()");
  await realEdit();nativeAccept=false;nativeCount=dialogs.length;await send("Page.close");for(let i=0;i<100&&dialogs.length===nativeCount;i++)await sleep(30);assert.equal(dialogs.length,nativeCount+1);await check("Native beforeunload also cancels tab close","!!document.querySelector('.order-form')");
  await evaluate("qa.confirmNext=true");await click("Đóng");await until(detail);await evaluate("Router.navigate('#/orders')");await until("Router.current()?.name==='orders'");await check("After leaving orders form there is no residual guard or unload warning","qa.beforeListeners.size===0&&Router.canLeave()");assert.equal(await evaluate(beforeUnload),false);
  await check("No browser errors or unhandled rejections","qa.errors.length===0");assert.deepEqual(errors,[]);
  const report={mode:"Real Edge/app/router with isolated API fixtures, no database access or real writes",checks,nativeBeforeUnloadDialogs:dialogs.map(d=>d.type),consoleErrors:errors};
  fs.writeFileSync(path.join(root,"docs/order-unsaved-verification.json"),JSON.stringify(report,null,2));console.log(JSON.stringify({checks:checks.length,nativeBeforeUnloadDialogs:dialogs.length,consoleErrors:errors}));
})().catch(e=>{console.error(e.stack);process.exitCode=1;}).finally(async()=>{
  try{if(socket?.readyState===1){nativeAccept=true;await send("Browser.close");}}catch{}socket?.close();edge?.kill();if(server){server.closeAllConnections();await new Promise(r=>server.close(r));}
  const resolved=path.resolve(profile);if(path.dirname(resolved)!==path.resolve(artifact)||!path.basename(resolved).startsWith("edge-"))throw Error("Unsafe profile cleanup");
  for(let i=0;i<15;i++){try{fs.rmSync(resolved,{recursive:true,force:true});break;}catch{await sleep(200);}}
});
