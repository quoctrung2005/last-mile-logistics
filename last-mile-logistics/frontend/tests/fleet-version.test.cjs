"use strict";
const {test}=require("node:test"),assert=require("node:assert/strict"),fs=require("node:fs"),path=require("node:path"),vm=require("node:vm");
const source=name=>fs.readFileSync(path.join(__dirname,"../js/"+name+".js"),"utf8");
class Element {
  constructor(tag,cls="",text=""){
    Object.assign(this,{tagName:tag.toUpperCase(),className:cls,text,children:[],events:{},dataset:{},value:"",type:"text",disabled:false,maxLength:-1});
    this.classList={add:v=>{this.className+=" "+v;},remove:v=>{this.className=this.className.split(" ").filter(x=>x!==v).join(" ");},contains:v=>this.className.split(" ").includes(v)};
  }
  get textContent(){return this.text+this.children.map(n=>n.textContent).join("");} set textContent(v){this.text=v;this.children=[];}
  append(...nodes){for(const n of nodes){n.parent=this;this.children.push(n);}}
  prepend(...nodes){for(const n of nodes)n.parent=this;this.children.unshift(...nodes);}
  replaceChildren(...nodes){this.children=[];this.text="";this.append(...nodes);}
  setAttribute(k,v){this[k]=v;} removeAttribute(k){delete this[k];} focus(){} showModal(){this.open=true;} close(){this.open=false;} remove(){}
  addEventListener(type,fn){(this.events[type]||=[]).push(fn);}
  async emit(type){for(const fn of this.events[type]||[])await fn({preventDefault(){},target:this});}
  click(){return this.emit("click");}
  querySelectorAll(selector){const tags=selector.split(",").map(s=>s.trim().toUpperCase()),out=[];const visit=n=>{for(const c of n.children){if(tags.includes(c.tagName))out.push(c);visit(c);}};visit(this);return out;}
  querySelector(s){return this.querySelectorAll(s)[0]||null;}
}
const token=n=>{const bytes=Buffer.alloc(8);bytes.writeBigUInt64BE(BigInt(n));return bytes.toString("base64");};
function server(kind){
  return {revision:1,audits:0,error:null,readError:null,
    record:kind==="shippers"?{id:3,version:token(1),licenseNumber:"ORIGINAL",licenseExpiresAt:"2030-01-01",identityNumber:"012345678901",isActive:true,areas:[],employeeCode:"NV3",fullName:"Mock",username:"mock"}:
      {id:3,version:token(1),licensePlate:"ORIGINAL",vehicleType:"MOTORBIKE",maxWeightKg:100,maxVolumeM3:0.38,status:"AVAILABLE",isActive:true,code:"XE3"},
    read(){if(this.readError)throw this.readError;return structuredClone(this.record);},
    save(payload){
      if(this.error)throw this.error;
      if(payload.expectedVersion!==this.record.version)throw Object.assign(Error("Bản ghi đã thay đổi"),{status:409,data:{code:"VERSION_CONFLICT"}});
      this.revision++;this.audits++;Object.assign(this.record,payload,{version:token(this.revision)});return this.read();
    }
  };
}
function environment(kind,backend){
  const requests=[],el=(...args)=>new Element(...args),storage=new Map(),window={};
  window.LogisticsUI={el,button(text,fn,cls){const n=el("button",cls,text);n.type="button";if(fn)n.addEventListener("click",fn);return n;},summary:rows=>{const n=el("dl");for(const [key,value]of rows)n.append(el("dt","",key),el("dd","",String(value??"—")));return n;},table(){},date:String};
  window.Router={href:()=>"#/accounts"};
  window.ApiClient={request:async(url,options={})=>{
    requests.push({url,...options});
    if(options.method)return backend.save(JSON.parse(options.body));
    if(url.startsWith("/api/v1/catalogs?"))return {areas:[],branches:[]};
    if(url==="/api/v1/vehicles/types")return {items:[{code:"MOTORBIKE",name:"Xe máy",maxCargoWeightKg:100,maxCargoVolumeM3:0.38}]};
    return backend.read();
  }};
  const context=vm.createContext({window,Date,Intl,URL,URLSearchParams,AbortController,AbortSignal,Event,sessionStorage:{getItem:k=>storage.get(k)||null,setItem:(k,v)=>storage.set(k,v)}});
  vm.runInContext(source("vietnam-date"),context);vm.runInContext(source("write-outcome"),context);
  // Expose only test entry points and stop refresh at its page boundary.
  vm.runInContext(source(kind).replace("Object.freeze({mount,destroy})","Object.freeze({mount,destroy,editor,"+(kind==="shippers"?"toggle,":"")+"activate:s=>{active=s;}})").replace("function refresh(s){","function refresh(s){if(s.externalRefresh)return s.externalRefresh();"),context);
  const s={abort:new AbortController(),root:el("div"),externalRefresh:async()=>{},user:{role:"ADMIN"},permissions:{known:true,codes:new Set(["TAIKHOAN_QUANLY"])}};
  const page=kind==="shippers"?window.ShippersPage:window.VehiclesPage;page.activate(s);
  return {s,page,window,requests,writes:()=>requests.filter(r=>r.method),form:()=>s.dialog.body.querySelector("form")};
}
const input=(form,key)=>form.querySelectorAll("input,select").find(n=>n.name===key);
const submit=form=>form.querySelectorAll("button").find(n=>n.type==="submit");
const review=form=>form.querySelectorAll("button").find(n=>n.textContent==="Tải bản mới để đối chiếu");
async function open(b,kind,toggle=false){if(kind==="shippers"&&toggle)await b.page.toggle(b.s,3);else await b.page.editor(b.s,3,toggle);return b.form();}

for(const kind of ["shippers","vehicles"])
for(const toggle of [false,true])test(`${kind} ${toggle?"status":"editor"}: stale form cannot overwrite A, review keeps draft, intentional reopen succeeds`,async()=>{
  const backend=server(kind),a=environment(kind,backend),b=environment(kind,backend),key=kind==="shippers"?"licenseNumber":"licensePlate";
  const formA=await open(a,kind),formB=await open(b,kind,toggle);
  if(toggle&&kind==="vehicles"){input(formB,"status").value="INACTIVE";await input(formB,"status").emit("change");input(formB,"confirmStatus").checked=true;}
  if(!toggle)input(formB,key).value="B-123";
  input(formA,key).value="A-123";await formA.emit("submit");assert.equal(backend.record.version,token(2));
  await formB.emit("submit");assert.equal(b.writes().length,1);assert.equal(JSON.parse(b.writes()[0].body).expectedVersion,token(1));
  assert.equal(backend.record[key],"A-123");assert.equal(backend.audits,1);assert.equal(submit(formB).disabled,true);
  if(!toggle)assert.equal(input(formB,key).value,"B-123");
  const readsBefore=b.requests.filter(r=>!r.method).length;assert.equal(readsBefore,kind==="shippers"&&toggle?1:2,"409 triggers no automatic GET");
  await review(formB).click();assert.equal(b.requests.filter(r=>!r.method).length,readsBefore+1);assert(formB.textContent.includes("A-123"));
  if(!toggle)assert.equal(input(formB,key).value,"B-123");
  submit(formB).disabled=false;await formB.emit("submit");assert.equal(b.writes().length,1,"GET review never unlocks or replaces the old version");
  b.s.dialog.close();const reopened=await open(b,kind);input(reopened,key).value="INTENTIONAL-123";await reopened.emit("submit");
  assert.equal(b.writes().length,2);assert.equal(JSON.parse(b.writes()[1].body).expectedVersion,token(2));
  assert.equal(backend.record[key],"INTENTIONAL-123");assert.equal(backend.record.version,token(3));assert.equal(backend.audits,2);
});

for(const kind of ["shippers","vehicles"])test(kind+": read failure preserves stale input and locked submit",async()=>{
  const backend=server(kind),b=environment(kind,backend),form=await open(b,kind),key=kind==="shippers"?"licenseNumber":"licensePlate";
  input(form,key).value="MY-DRAFT";backend.record.version=token(2);await form.emit("submit");
  backend.readError=Error("Mock GET unavailable");await review(form).click();
  assert.equal(input(form,key).value,"MY-DRAFT");assert.equal(submit(form).disabled,true);assert(form.textContent.includes("Mock GET unavailable"));
  await form.emit("submit");assert.equal(b.writes().length,1);
});

for(const kind of ["shippers","vehicles"])test(kind+": ordinary validation and business conflicts remain editable",async()=>{
  const backend=server(kind),b=environment(kind,backend),form=await open(b,kind),key=kind==="shippers"?"licenseNumber":"licensePlate";
  for(const status of [400,409]){
    backend.error=Object.assign(Error("Validation or business conflict"),{status,data:{}});await form.emit("submit");
    assert.equal(submit(form).disabled,false);assert.equal(b.s.dialog.versionConflict,undefined);
  }
  backend.error=null;input(form,key).value="CORRECTED";await form.emit("submit");assert.equal(backend.record[key],"CORRECTED");assert.equal(b.writes().length,3);
});

test("vehicle creation omits ExpectedVersion",async()=>{
  const backend=server("vehicles"),b=environment("vehicles",backend);backend.error=Object.assign(Error("Mock validation"),{status:400});
  await b.page.editor(b.s);const form=b.form();input(form,"licensePlate").value="NEW-123";input(form,"vehicleType").value="MOTORBIKE";await input(form,"vehicleType").emit("change");
  await form.emit("submit");assert.equal(b.writes().length,1);assert.equal(Object.hasOwn(JSON.parse(b.writes()[0].body),"expectedVersion"),false);
});

test("uncertain vehicle write stays locked after read review",async()=>{
  const backend=server("vehicles"),b=environment("vehicles",backend),form=await open(b,"vehicles");
  backend.error=Object.assign(Error("Lost response"),{resultUnknown:true});await form.emit("submit");
  assert.equal(b.s.dialog.writeUnknown,true);assert.equal(submit(form).disabled,true);
  const check=form.querySelectorAll("button").find(n=>n.textContent==="Tải lại để kiểm tra");await check.click();
  submit(form).disabled=false;await form.emit("submit");assert.equal(b.writes().length,1);assert(b.requests.some(r=>r.url==="/api/v1/vehicles?id=3"&&!r.method));
});
