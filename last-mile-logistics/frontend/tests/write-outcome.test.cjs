"use strict";
const {test}=require("node:test"),assert=require("node:assert/strict"),fs=require("node:fs"),path=require("node:path"),vm=require("node:vm");
const source=name=>fs.readFileSync(path.join(__dirname,"../js/"+name+".js"),"utf8");
class Element {
  constructor(tag,cls="",text=""){this.tagName=tag.toUpperCase();this.className=cls;this.text=text;this.children=[];this.events={};this.dataset={};this.value="";this.type="text";this.disabled=false;this.maxLength=-1;this.style={};this.isConnected=true;this.classList={add:v=>{this.className+=" "+v;},remove:v=>{this.className=this.className.split(" ").filter(x=>x!==v).join(" ");},contains:v=>this.className.split(" ").includes(v)};}
  get textContent(){return this.text+this.children.map(n=>n.textContent).join("");}set textContent(v){this.text=v;this.children=[];}
  append(...nodes){for(const n of nodes){n.parent=this;this.children.push(n);}}
  replaceChildren(...nodes){this.children=[];this.text="";this.append(...nodes);}
  setAttribute(k,v){this[k]=v;}removeAttribute(k){delete this[k];}focus(){}checkValidity(){return true;}reportValidity(){return true;}showModal(){this.open=true;}close(){this.open=false;}remove(){}scrollIntoView(){}
  addEventListener(type,fn){(this.events[type]||=[]).push(fn);}
  async emit(type){for(const fn of this.events[type]||[])await fn({preventDefault(){},target:this});}
  click(){return this.emit("click");}
  querySelectorAll(selector){const selectors=selector.split(",").map(s=>s.trim());const out=[];const visit=n=>{for(const c of n.children){if(selectors.some(s=>s.startsWith(".")?c.classList.contains(s.slice(1)):s.startsWith("[name=")?c.name===s.match(/name=["']?([^\]"']+)/)[1]:c.tagName===s.toUpperCase()))out.push(c);visit(c);}};visit(this);return out;}
  querySelector(s){return this.querySelectorAll(s)[0]||null;}
}
function environment(storage=new Map()){
  const requests=[],el=(...args)=>new Element(...args);
  const UI={el,button(text,fn,cls){const n=el("button",cls,text);n.type="button";if(fn)n.addEventListener("click",fn);return n;},table:()=>el("table"),date:String,summary:()=>el("dl")};
  const env={requests,el,error:Object.assign(Error("Simulated lost response"),{resultUnknown:true}),readData:{items:[],totalItems:0,page:1,pageSize:100}};
  const window={LogisticsUI:UI,Router:{setLeaveGuard(){},reload(){},updateQuery(){},current(){return null;},href(){return "#/test";}},ApiClient:{request:async(url,options={})=>{requests.push({url,...options});if(options.method&&options.method!=="GET")throw env.error;if(env.readError)throw env.readError;return env.readData;}},addEventListener(){},removeEventListener(){}};
  const context=vm.createContext({window,URL,URLSearchParams,AbortController,AbortSignal,TextEncoder,Node:Element,document:{activeElement:null,createTextNode:text=>el("span","",text)},cancelAnimationFrame(){},requestAnimationFrame(){},sessionStorage:{setItem:(k,v)=>storage.set(k,v),getItem:k=>storage.get(k)||null}});
  vm.runInContext(source("write-outcome"),context);vm.runInContext(source("admin-ui"),context);
  for(const [name,exportText,extra]of [
    ["customers","{mount, destroy}","saveForm,activate:s=>{active=s;}"],
    ["accounts","{mount, destroy}","save,activate:s=>{active=s;}"],
    ["shippers","{mount,destroy}","save,activate:s=>{active=s;}"],
    ["cod","{mount,destroy,dateRange,cents,depositJson}","submit,createDeposit,createRecon,detail"],
    ["dispatch","{mount,destroy}","reasonDialog,createTrip,editTrip,assignmentDialog"]
  ])vm.runInContext(source(name).replace("Object.freeze("+exportText+")","Object.freeze("+exportText.slice(0,-1)+","+extra+"})"),context);
  const s={abort:new AbortController(),root:el("div"),feedback:el("div"),alive:()=>true,can:()=>true,read:(url,signal)=>window.ApiClient.request(url,{signal}),user:{role:"ADMIN"},permissions:{known:true,codes:new Set(["DONHANG_TAO","DONHANG_CAPNHAT","TAIKHOAN_QUANLY"])},options:{shippers:[],warehouses:[{id:1,branchId:1,name:"Kho"}]},selected:new Map([[1,{id:1,warehouseId:1,weightKg:1}]]),draft:{departure:"2030-01-01T09:00"},query:{},route:{}};
  window.CustomersPage.activate(s);window.AccountsPage.activate(s);window.ShippersPage.activate(s);
  const form=el("form"),input=el("input"),error=el("div");input.value="Dữ liệu đang nhập";input.name="fullName";form.append(input,error);
  const d={body:el("div"),signal:s.abort.signal,busy:false,closed:false,setBusy(v){this.busy=v;},busyState(v){this.busy=v;},close(){this.closed=true;}};d.body.append(form);
  return Object.assign(env,{window,s,d,form,input,fields:{fullName:{control:input,error}}});
}
const writes=b=>b.requests.filter(r=>r.method&&r.method!=="GET");
const checkButton=body=>body.querySelectorAll("button").find(n=>n.textContent==="Tải lại để kiểm tra");

for(const kind of ["customers","accounts","shippers","admin"]){
  for(const unknown of [true,false])test(`${kind}: ${unknown?"unknown result locks writes after GET review":"validation failure still permits editing and another submission"}`,async()=>{
    const b=environment(),{s,d,form,fields,window}=b;
    if(!unknown)b.error=Object.assign(Error("Validation"),{status:400,data:{errors:{fullName:["Sửa họ tên"]}}});
    const build=()=>({fullName:b.input.value});
    if(kind==="customers")window.CustomersPage.saveForm(s,d,form,fields,false,"/api/v1/customers/7","PUT",build,()=>{throw Error("must not replace draft");});
    if(kind==="accounts")window.AccountsPage.save(s,d,form,fields,"/api/v1/accounts/7","PUT",build);
    if(kind==="shippers")window.ShippersPage.save(s,d,form,fields,"/api/v1/shippers/7/vehicle","PUT",build);
    if(kind==="admin")window.AdminUI.save(s,d,form,fields,"/api/v1/roles","POST",build,()=>{});
    await form.emit("submit");assert.equal(writes(b).length,1);
    const save=form.querySelectorAll("button").find(n=>n.type==="submit");
    if(unknown){assert.equal(d.writeUnknown,true);assert.equal(save.disabled,true);assert(form.textContent.includes(window.WriteOutcome.message));assert.equal(b.input.value,"Dữ liệu đang nhập");
      await checkButton(form).click();assert.equal(b.requests.length,2);assert.equal(save.disabled,true);assert.equal(b.input.value,"Dữ liệu đang nhập");
      save.disabled=false;await form.emit("submit");assert.equal(writes(b).length,1);
    }else{assert.equal(save.disabled,false);b.input.value="Đã sửa họ tên";await form.emit("submit");assert.equal(writes(b).length,2);}
  });
}

for(const url of ["/api/v1/cod/deposits","/api/v1/cod/deposits/8/confirm","/api/v1/cod/reconciliations","/api/v1/cod/reconciliations/9/confirm"]){
  for(const unknown of [true,false])test(`${url}: ${unknown?"unknown financial write is sent once":"known validation failure can be retried"}`,async()=>{
    const b=environment(),box=b.el("div"),save=b.el("button");b.d.body.append(box,save);
    if(!unknown)b.error=Object.assign(Error("Validation"),{status:400});
    const send=()=>b.window.CodPage.submit(b.s,b.d,box,url,JSON.stringify({branchId:1,shipperId:2,notes:"Giữ ghi chú",items:[{orderId:1,amount:100}]}),()=>{},()=>{throw Error("must not run destructive reload");});
    await send();assert.equal(writes(b).length,1);
    if(unknown){assert.equal(save.disabled,true);assert(box.textContent.includes(b.window.WriteOutcome.message));await checkButton(box).click();save.disabled=false;await send();assert.equal(writes(b).length,1);assert.equal(b.input.value,"Dữ liệu đang nhập");}
    else{assert.equal(save.disabled,false);await send();assert.equal(writes(b).length,2);}
  });
}

for(const operation of ["reason","createTrip","editTrip"]){
  for(const unknown of [true,false])test(`dispatch ${operation}: ${unknown?"unknown outcome cannot send a second write":"normal validation stays retryable"}`,async()=>{
    const b=environment();if(!unknown)b.error=Object.assign(Error("Validation"),{status:400});
    if(operation==="reason")b.window.DispatchPage.reasonDialog(b.s,"Hủy chuyến","/api/v1/trips/7/actions",{action:"CANCEL"});
    if(operation==="createTrip")await b.window.DispatchPage.createTrip(b.s);
    if(operation==="editTrip")b.window.DispatchPage.editTrip(b.s,{id:7,branchId:1,plannedStartAt:"2030-01-01T02:00:00Z",orders:[{orderId:1,trackingNumber:"LM1"}]});
    const d=b.s.dialog,form=d.body.querySelector("form");assert(form);await form.emit("submit");assert.equal(writes(b).length,1);
    if(unknown){assert.equal(d.writeUnknown,true);await checkButton(d.body).click();for(const n of form.querySelectorAll("button"))n.disabled=false;await form.emit("submit");assert.equal(writes(b).length,1);}
    else{await form.emit("submit");assert.equal(writes(b).length,2);}
  });
}

test("failed or empty GET review never clears uncertainty or erases the draft",async()=>{
  const b=environment(),box=b.el("div");b.form.append(box);b.window.WriteOutcome.lock(b.d,box,b.error,{path:"/api/v1/cod/deposits",payload:{shipperId:2},scope:b.form});
  const check=checkButton(box);b.readError=Error("Read failed");await check.click();assert.equal(b.d.writeUnknown,true);assert.equal(b.input.value,"Dữ liệu đang nhập");
  b.readError=null;await check.click();assert.equal(b.d.writeUnknown,true);assert.equal(b.input.value,"Dữ liệu đang nhập");assert.equal(writes(b).length,0);
});

test("review uses known read paths and never exposes secrets or sends write headers",async()=>{
  const b=environment(),box=b.el("div");b.form.append(box);b.readData={id:7,username:"test",password:"secret",accessToken:"secret-token",version:"private-version"};
  b.window.WriteOutcome.lock(b.d,box,b.error,{path:"/api/v1/accounts/7/reset-password",scope:b.form});await checkButton(box).click();
  assert.equal(b.requests[0].url,"/api/v1/accounts?id=7");assert.equal(b.requests[0].method,undefined);assert.equal(b.requests[0].headers,undefined);assert(!box.textContent.includes("secret"));assert(!box.textContent.includes("private-version"));assert(box.textContent.includes("quản trị viên"));
});

test("reopening or reloading a form cannot replay the same unresolved write",async()=>{
  const storage=new Map();
  for(const expected of [1,0]){
    const b=environment(storage);
    b.window.CustomersPage.saveForm(b.s,b.d,b.form,b.fields,false,"/api/v1/customers/7","PUT",()=>({fullName:b.input.value}),null);
    await b.form.emit("submit");assert.equal(writes(b).length,expected);assert.equal(b.d.writeUnknown,true);
  }
  assert(!JSON.stringify([...storage]).includes("Dữ liệu đang nhập"));
});

for(const unknown of [true,false])test(`dispatch assignment ${unknown?"unknown outcome is locked":"validation error remains retryable"}`,async()=>{
  const b=environment();b.readData={items:[{id:3,vehicleId:5,fullName:"Shipper 3",maxWeightKg:100,remainingWeightKg:80}],excludedVehicles:[],excludedShippers:[]};
  if(!unknown)b.error=Object.assign(Error("Validation"),{status:400});
  await b.window.DispatchPage.assignmentDialog(b.s,{id:1,trackingNumber:"LM1"});
  const d=b.s.dialog,form=d.body.querySelector("form");await form.emit("submit");assert.equal(writes(b).length,1);
  if(unknown){assert.equal(d.writeUnknown,true);await checkButton(form).click();for(const n of form.querySelectorAll("button"))n.disabled=false;await form.emit("submit");assert.equal(writes(b).length,1);}
  else{await form.emit("submit");assert.equal(writes(b).length,2);}
});

for(const kind of ["deposits","reconciliations"])test(`COD ${kind} confirmation checkbox cannot re-enable a write with unknown result`,async()=>{
  const b=environment();b.s.options.canReconcile=true;b.readData={id:8,status:kind==="deposits"?"PENDING":"DRAFT",amount:100,shipperName:"Shipper 2",depositCode:"P8",reconciliationCode:"R8",orderCount:1,items:[]};
  await b.window.CodPage.detail(b.s,8,kind);
  const d=b.s.dialog,check=d.body.querySelector("input"),save=d.body.querySelectorAll("button").find(n=>n.textContent===(kind==="deposits"?"Xác nhận đã nhận tiền":"Xác nhận đối soát"));
  check.checked=true;await check.emit("change");await save.click();assert.equal(writes(b).length,1);assert.equal(save.disabled,true);
  await checkButton(d.body).click();check.disabled=false;check.checked=true;await check.emit("change");assert.equal(save.disabled,true);
  save.disabled=false;await save.click();assert.equal(writes(b).length,1);
});

test("customer version conflict keeps the original conflict flow and input",async()=>{
  const b=environment();b.error=Object.assign(Error("Conflict"),{status:409});
  b.window.CustomersPage.saveForm(b.s,b.d,b.form,b.fields,false,"/api/v1/customers/7","PUT",()=>({fullName:b.input.value,expectedVersion:"original"}),()=>{});
  await b.form.emit("submit");await b.form.emit("submit");assert.equal(writes(b).length,1);assert.equal(b.d.writeUnknown,undefined);assert.equal(b.input.value,"Dữ liệu đang nhập");assert(b.form.querySelectorAll("button").some(n=>n.textContent==="Tải dữ liệu mới"));
});

test("tab replay fingerprints exclude passwords and do not change when only a password changes",()=>{
  const b=environment(),box=b.el("div"),first={},second={};
  b.window.WriteOutcome.assertCanSend(first,{path:"/api/v1/accounts/7/reset-password",payload:{newPassword:"first-secret",expectedVersion:"v1"}});
  b.window.WriteOutcome.lock(first,box,b.error,{path:"/api/v1/accounts/7/reset-password"});
  assert.throws(()=>b.window.WriteOutcome.assertCanSend(second,{path:"/api/v1/accounts/7/reset-password",payload:{newPassword:"different-secret",expectedVersion:"v1"}}),e=>e.resultUnknown);
});
