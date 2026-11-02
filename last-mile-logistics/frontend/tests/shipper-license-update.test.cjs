"use strict";
const {test}=require("node:test"),assert=require("node:assert/strict"),fs=require("node:fs"),path=require("node:path"),vm=require("node:vm");
const source=name=>fs.readFileSync(path.join(__dirname,"../js/"+name+".js"),"utf8");

// Only DOM and HTTP boundaries are simulated; exercise the real editor/toggle,
// form submission and VietnamDate helper, without a browser or database server.
class Element {
  constructor(tag,cls="",text=""){
    Object.assign(this,{tagName:tag.toUpperCase(),className:cls,text,children:[],events:{},value:"",type:"text",disabled:false,maxLength:-1});
    this.classList={add:v=>{this.className+=" "+v;},remove:v=>{this.className=this.className.split(" ").filter(x=>x!==v).join(" ");},contains:v=>this.className.split(" ").includes(v)};
  }
  get textContent(){return this.text+this.children.map(n=>n.textContent).join("");} set textContent(v){this.text=v;this.children=[];}
  append(...nodes){for(const n of nodes){n.parent=this;this.children.push(n);}}
  prepend(...nodes){for(const n of nodes)n.parent=this;this.children.unshift(...nodes);}
  replaceChildren(...nodes){this.children=[];this.text="";this.append(...nodes);}
  setAttribute(k,v){this[k]=v;} removeAttribute(k){delete this[k];} focus(){} showModal(){this.open=true;} close(){this.open=false;} remove(){}
  addEventListener(type,fn){(this.events[type]||=[]).push(fn);}
  async emit(type){for(const fn of this.events[type]||[])await fn({preventDefault(){},target:this});}
  querySelectorAll(selector){const tags=selector.split(",").map(s=>s.trim().toUpperCase()),out=[];const visit=n=>{for(const c of n.children){if(tags.includes(c.tagName))out.push(c);visit(c);}};visit(this);return out;}
  querySelector(s){return this.querySelectorAll(s)[0]||null;}
}

function environment(record,instant="2026-10-20T06:59:00+07:00"){
  const requests=[],el=(...args)=>new Element(...args),window={};
  class FrozenDate extends Date {constructor(...args){super(...(args.length?args:[instant]));}}
  window.LogisticsUI={el,button(text,fn,cls){const n=el("button",cls,text);n.type="button";if(fn)n.addEventListener("click",fn);return n;},summary(){},table(){},date:String};
  window.Router={href:()=>"#/accounts"};
  window.WriteOutcome={assertCanSend(){},lock:()=>false,restore:controls=>{for(const [c,disabled] of controls)c.disabled=disabled;}};
  window.ApiClient={validatePage:data=>data,request:async(url,options={})=>{
    requests.push({url,...options});
    if(options.method){throw Object.assign(Error("Simulated validation; no database write"),{status:400});}
    if(url.startsWith("/api/v1/catalogs?"))return {areas:[],branches:[]};
    if(url.startsWith("/api/v1/accounts?"))return {items:[{id:7,username:"mock",fullName:"Mock",branchName:"BC"}],page:1,pageSize:10,totalItems:1};
    return record;
  }};
  const context=vm.createContext({window,Date:FrozenDate,Intl,URLSearchParams,AbortController,AbortSignal,Event});
  vm.runInContext(source("vietnam-date"),context);
  vm.runInContext(source("shippers").replace("Object.freeze({mount,destroy})","Object.freeze({mount,destroy,editor,toggle,activate:s=>{active=s;}})"),context);
  const s={abort:new AbortController(),root:el("div"),user:{role:"ADMIN"},permissions:{known:true,codes:new Set(["TAIKHOAN_QUANLY"])}};
  window.ShippersPage.activate(s);
  return {window,s,requests,writes:()=>requests.filter(r=>r.method),form:()=>s.dialog.body.querySelector("form")};
}
const record=(expiry,isActive=true)=>({id:3,employeeCode:"NV3",fullName:"Mock",username:"mock",branchName:"BC",identityNumber:"012345678901",licenseNumber:"AB-123",licenseExpiresAt:expiry,isActive,areas:[]});
const input=(form,key)=>form.querySelectorAll("input,select").find(n=>n.name===key);

for(const expiry of ["2026-10-19","2026-10-20","2026-10-21"]){
  test("deactivate: preserve licence expiring "+expiry,async()=>{
    const b=environment(record(expiry));await b.window.ShippersPage.toggle(b.s,3);await b.form().emit("submit");
    assert.equal(b.writes().length,1);const payload=JSON.parse(b.writes()[0].body);
    assert.equal(payload.isActive,false);assert.equal(payload.licenseNumber,"AB-123");assert.equal(payload.licenseExpiresAt,expiry);
  });
  test("reactivate: Vietnam date "+expiry,async()=>{
    const b=environment(record(expiry,false));await b.window.ShippersPage.toggle(b.s,3);await b.form().emit("submit");
    assert.equal(b.writes().length,expiry==="2026-10-19"?0:1);
    if(!b.writes().length)assert(b.form().textContent.includes("Hãy cập nhật thông tin bằng lái hợp lệ"));
  });
  test("new expiry entry: Vietnam date "+expiry,async()=>{
    const b=environment(record("2026-11-01",false));await b.window.ShippersPage.editor(b.s,3);const form=b.form();
    input(form,"licenseExpiresAt").value=expiry;await form.emit("submit");
    assert.equal(b.writes().length,expiry==="2026-10-19"?0:1);
    assert.equal(input(form,"licenseExpiresAt").value,expiry);
    assert.equal(input(form,"licenseExpiresAt").classList.contains("is-invalid"),expiry==="2026-10-19");
  });
}

for(const active of [false,true])test("edit other data: retain historical expired licence while active="+active,async()=>{
  const b=environment(record("2026-10-19T00:00:00",active));await b.window.ShippersPage.editor(b.s,3);const form=b.form();
  input(form,"identityNumber").value="112345678901";await form.emit("submit");
  assert.equal(b.writes().length,1);assert.equal(JSON.parse(b.writes()[0].body).licenseExpiresAt,"2026-10-19");
});

test("changing licence number cannot carry forward an expired date",async()=>{
  const b=environment(record("2026-10-19",false));await b.window.ShippersPage.editor(b.s,3);const form=b.form();
  input(form,"licenseNumber").value="NEW-123";await form.emit("submit");
  assert.equal(b.writes().length,0);assert.equal(input(form,"licenseExpiresAt").value,"2026-10-19");
  input(form,"licenseExpiresAt").value="2026-10-21";await form.emit("submit");assert.equal(b.writes().length,1);
});

test("creating a profile cannot enter an expired licence",async()=>{
  const b=environment(null);await b.window.ShippersPage.editor(b.s);const form=b.form();
  input(form,"accountId").value="7";input(form,"licenseNumber").value="NEW-123";
  input(form,"licenseExpiresAt").value="2026-10-19";await form.emit("submit");assert.equal(b.writes().length,0);
  input(form,"licenseExpiresAt").value="2026-10-20";await form.emit("submit");assert.equal(b.writes().length,1);
});

for(const [instant,allowed] of [["2026-10-19T16:59:59Z",true],["2026-10-19T17:00:00Z",false]])
  test("reactivation changes at Vietnamese midnight "+instant,async()=>{
    const b=environment(record("2026-10-19",false),instant);await b.window.ShippersPage.toggle(b.s,3);await b.form().emit("submit");
    assert.equal(b.writes().length,allowed?1:0);
  });

test("optional licence remains optional on reactivation",async()=>{
  const b=environment({...record(null,false),licenseNumber:null});await b.window.ShippersPage.toggle(b.s,3);await b.form().emit("submit");
  assert.equal(b.writes().length,1);assert.equal(JSON.parse(b.writes()[0].body).licenseExpiresAt,null);
});
