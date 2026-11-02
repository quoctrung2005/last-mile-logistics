"use strict";
const {test}=require("node:test"),assert=require("node:assert/strict"),fs=require("node:fs"),path=require("node:path"),vm=require("node:vm"),crypto=require("node:crypto");
const source=fs.readFileSync(path.join(__dirname,"../js/pickup-issues.js"),"utf8"),tick=()=>new Promise(r=>setImmediate(r));
class Element{
  constructor(tag,cls="",text=""){this.tag=tag;this.className=cls;this.text=text;this.children=[];this.events={};this.style={};this.value="";this.disabled=false;}
  get textContent(){return this.text+this.children.map(c=>c.textContent).join("");}set textContent(v){this.text=v;this.children=[];}
  append(...children){this.children.push(...children);}replaceChildren(...children){this.text="";this.children=children;}
  querySelectorAll(tag){return this.children.flatMap(c=>[...(c.tag===tag?[c]:[]),...c.querySelectorAll(tag)]);}
  addEventListener(type,fn){(this.events[type]||=[]).push(fn);}
  async emit(type){for(const fn of this.events[type]||[])await fn({preventDefault(){}});}
  click(){return this.emit("click");}
}
function page({review=true,image=true}={}){return {orderId:99,assignmentId:null,available:true,pickupBlocked:true,canReport:false,items:[{
  id:31,assignmentId:8,orderId:99,shipperId:25,warehouseId:6,warehouseName:"Kho A",shipperName:"Tài xế A",kind:"DAMAGED",status:"OPEN",revision:1,
  reportedAt:"2035-01-01T02:00:00Z",closedAt:null,canReview:review,canSupplement:false,
  events:[{id:41,requestId:"782b4ab7-9baf-481f-af93-52122c4740c4",eventType:"REPORT",revision:1,status:"OPEN",recordedAt:"2035-01-01T02:00:00Z",authorAccountId:7,authorName:"Tài xế A",notes:"Bao bì bị rách",hasEvidence:image}]
}]};}
function respond(data,payload){const r=data.items[0];r.revision++;r.status=payload.action==="RESOLVE"?"RESOLVED":"NEED_MORE";r.closedAt=r.status==="RESOLVED"?"2035-01-01T02:01:00Z":null;r.canReview=r.status!=="RESOLVED";
  r.events.push({id:42,requestId:payload.requestId,eventType:payload.action,revision:r.revision,status:r.status,recordedAt:"2035-01-01T02:01:00Z",authorAccountId:1,authorName:"Kho A",notes:payload.reason,hasEvidence:false});
  return {issueId:31,orderId:99,assignmentId:8,eventId:42,requestId:payload.requestId,eventType:payload.action,revision:r.revision,status:r.status,reason:payload.reason,hasEvidence:false,recordedAt:"2035-01-01T02:01:00Z",alreadyRecorded:false};
}
function environment(data=page()){
  const abort=new AbortController(),body=new Element("div"),created=[],revoked=[],requests=[],busyStates=[];
  const env={data,body,created,revoked,requests,busyStates,close:()=>{abort.abort();env.onClose?.();},image:()=>new Blob(["png"],{type:"image/png"})};
  const U={el:(...args)=>new Element(...args),date:String,button(label,fn){const b=new Element("button","",label);b.addEventListener("click",fn);return b;},
    dialog(){return {body,signal:abort.signal,onClose(fn){env.onClose=fn;},setBusy(v){busyStates.push(v);}};}};
  const window={LogisticsUI:U,ApiClient:{async request(url,options){requests.push({url,...options});if(options?.method==="POST")return env.reply(options.body);return url.endsWith("/image")?env.image():structuredClone(env.data);}}};
  env.reply=payload=>respond(env.data,payload);
  vm.runInNewContext(source,{window,crypto,URL:{createObjectURL(){const v="blob:"+created.length;created.push(v);return v;},revokeObjectURL(v){revoked.push(v);}}});
  env.module=window.PickupIssues;env.open=()=>env.module.show({abort},99);env.form=()=>body.querySelectorAll("form")[0];
  env.notes=()=>env.form().querySelectorAll("textarea")[0];env.button=label=>body.querySelectorAll("button").find(b=>b.textContent===label);
  env.fill=async(reason="Bổ sung ảnh mặt sau",action="REQUEST_INFO")=>{env.notes().value=reason;env.form().querySelectorAll("select")[0].value=action;await env.notes().emit("input");};
  return env;
}
test("Issue metadata rejects missing arrays, wrong order, duplicate event IDs and status/revision mismatch",()=>{
  const validate=environment().module.validate;validate(page(),99);
  for(const value of [{},{...page(),items:null},{...page(),orderId:98},...[
    {revision:2},{status:"__proto__"},{closedAt:"bad"},{canReview:"yes"},{events:[]},
  ].map(change=>{const d=page();Object.assign(d.items[0],change);return d;})])assert.throws(()=>validate(value,99));
});
test("Read-only staff see history/photos without response controls",async()=>{
  const e=environment(page({review:false}));await e.open();assert.equal(e.form(),undefined);assert.match(e.body.textContent,/Bao bì bị rách/);assert(e.button("Xem ảnh minh chứng"));
});
test("Response uses exact issue, stable UUID/revision and locks duplicate submits",async()=>{
  const e=environment();let resolve;e.reply=payload=>new Promise(r=>{resolve=()=>r(respond(e.data,payload));});
  await e.open();await e.fill();const form=e.form(),sending=form.emit("submit");await tick();await form.emit("submit");
  const posts=e.requests.filter(r=>r.method==="POST");assert.equal(posts.length,1);assert.equal(posts[0].url,"/api/v1/orders/99/pickup-issues/31/response");assert.equal(posts[0].body.expectedRevision,1);
  assert.match(posts[0].body.requestId,/^[\da-f-]{36}$/);assert.equal(e.notes().disabled,true);resolve();await sending;
  assert.match(e.body.textContent,/Cần tài xế bổ sung/);assert.deepEqual(e.busyStates,[true,false]);
});
test("Lost reply acknowledgement is recovered read-only by request ID",async()=>{
  const e=environment();e.reply=payload=>{respond(e.data,payload);throw Object.assign(Error("Lost response"),{resultUnknown:true});};
  await e.open();await e.fill();await e.form().emit("submit");
  assert.equal(e.requests.filter(r=>r.method==="POST").length,1);assert.match(e.body.textContent,/Đã tìm thấy biên nhận/);assert.equal(e.button("Gửi lại đúng yêu cầu này"),undefined);
});
test("Unresolved outcome permits only explicit retry with the same payload/key",async()=>{
  const e=environment();let first;e.reply=payload=>{first=payload;throw Object.assign(Error("Offline"),{resultUnknown:true});};
  await e.open();await e.fill();await e.form().emit("submit");assert.equal(e.form(),undefined);assert(e.button("Gửi lại đúng yêu cầu này"));
  e.reply=payload=>{assert.equal(payload,first);return respond(e.data,payload);};await e.button("Gửi lại đúng yêu cầu này").click();
  assert.equal(e.requests.filter(r=>r.method==="POST").length,2);assert.match(e.body.textContent,/Máy chủ đã ghi nhận/);
});
test("Stale revision reload preserves the operator's notes and selected resolution",async()=>{
  const e=environment();e.reply=()=>{respond(e.data,{requestId:crypto.randomUUID(),action:"REQUEST_INFO",reason:"Cần ảnh thêm"});throw Object.assign(Error("Hồ sơ đã thay đổi"),{status:409});};
  await e.open();await e.fill("Đã kiểm tra tại kho","RESOLVE");await e.form().emit("submit");
  assert.equal(e.notes().value,"Đã kiểm tra tại kho");assert.equal(e.form().querySelectorAll("select")[0].value,"RESOLVE");assert.match(e.body.textContent,/Hồ sơ đã thay đổi/);
});
test("Private proof is fetched only by IDs and disposed when the dialog closes",async()=>{
  const e=environment();await e.open();await e.button("Xem ảnh minh chứng").click();
  assert.equal(e.requests[1].url,"/api/v1/orders/99/pickup-issues/31/events/41/image");assert.equal(e.requests[1].responseType,"blob");assert.equal(e.created.length,1);
  e.close();assert.deepEqual(e.revoked,["blob:0"]);
});
test("A late photo after close and an invalid MIME cannot create a private image URL",async()=>{
  const e=environment();let resolve;e.image=()=>new Promise(r=>resolve=r);await e.open();const loading=e.button("Xem ảnh minh chứng").click();e.close();resolve(new Blob(["x"],{type:"image/png"}));await loading;assert.equal(e.created.length,0);
  const invalid=environment();invalid.image=()=>new Blob(["html"],{type:"text/html"});await invalid.open();await invalid.button("Xem ảnh minh chứng").click();assert.equal(invalid.created.length,0);assert.match(invalid.body.textContent,/Ảnh sự cố không hợp lệ/);
});
test("Missing migration shows no actionable report/review controls",async()=>{
  const e=environment({orderId:99,assignmentId:null,available:false,pickupBlocked:false,canReport:false,items:[]});await e.open();assert.equal(e.form(),undefined);assert.match(e.body.textContent,/Chưa áp dụng SQL/);
});
test("Refreshing away private history discards a late image from the prior view",async()=>{
  const e=environment();let resolve;e.image=()=>new Promise(r=>resolve=r);await e.open();
  const image=e.button("Xem ảnh minh chứng").click();
  e.data={orderId:99,assignmentId:null,available:true,pickupBlocked:false,canReport:false,items:[]};
  await e.button("Kiểm tra / làm mới").click();resolve(new Blob(["png"],{type:"image/png"}));await image;
  assert.equal(e.created.length,0);assert.match(e.body.textContent,/Chưa có hồ sơ/);
});
