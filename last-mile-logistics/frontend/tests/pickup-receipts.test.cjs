"use strict";
const {test}=require("node:test"),assert=require("node:assert/strict"),fs=require("node:fs"),path=require("node:path"),vm=require("node:vm");
const source=fs.readFileSync(path.join(__dirname,"../js/pickup-receipts.js"),"utf8");
const receipt=()=>({assignmentId:8,orderId:99,handoverId:12,shipperId:25,warehouseId:6,warehouseName:"Kho A",confirmedCode:"LABEL-99",parcelCondition:"PREEXISTING_DAMAGE",notes:"Trầy sẵn",hasEvidence:true,receivedAt:"2035-01-01T02:00:00Z",latitude:10.8,longitude:106.6,accuracyMeters:5});
class Element{
  constructor(tag,cls="",text=""){this.tag=tag;this.className=cls;this.text=text;this.children=[];this.style={};}
  get textContent(){return this.text+this.children.map(c=>c.textContent).join("");}
  set textContent(v){this.text=v;this.children=[];}
  append(...children){this.children.push(...children);}
  replaceChildren(...children){this.text="";this.children=children;}
  all(tag){return this.children.flatMap(c=>[...(c.tag===tag?[c]:[]),...c.all(tag)]);}
}
function environment(data={items:[receipt()]}){
  const abort=new AbortController(),requests=[],created=[],revoked=[],owner={abort};
  const body=new Element("div"),el=(...args)=>new Element(...args);
  let close;
  const env={owner,body,requests,created,revoked,image:()=>new Blob(["png"],{type:"image/png"}),close:()=>{abort.abort();close?.();}};
  const window={LogisticsUI:{el,date:String,button(label,action){const b=el("button","",label);b.click=action;return b;},dialog(){return {body,signal:abort.signal,onClose(fn){close=fn;}};}},
    ApiClient:{async request(url,options){requests.push({url,...options});return url.endsWith("/image")?env.image():data;}}};
  vm.runInNewContext(source,{window,URL:{createObjectURL(){const url="blob:"+created.length;created.push(url);return url;},revokeObjectURL(url){revoked.push(url);}}});
  env.module=window.PickupReceipts;env.open=()=>env.module.show(owner,99);return env;
}
test("Metadata requires explicit items, correct order, unique receipt IDs and valid condition/GPS",()=>{
  const {validate}=environment().module;
  assert.equal(validate({items:[]},99).length,0);
  for(const invalid of [{}, {items:null}, {items:[receipt(),receipt()]},...[
    {orderId:98},{assignmentId:0},{warehouseId:0},{confirmedCode:" "},{parcelCondition:"__proto__"},
    {latitude:null},{longitude:181},{accuracyMeters:101},{accuracyMeters:"5"},
    {hasEvidence:false},{notes:" "},{receivedAt:"bad"},
  ].map(change=>({items:[{...receipt(),...change}]}))])assert.throws(()=>validate(invalid,99));
});
test("Legacy receipts show unknown condition/GPS; empty collection explains missing metadata",async()=>{
  const e=environment({items:[{...receipt(),parcelCondition:null,latitude:null,longitude:null,accuracyMeters:null,hasEvidence:false}]});
  await e.open();assert.match(e.body.textContent,/Chưa ghi nhận/);assert.match(e.body.textContent,/Chưa ghi vị trí GPS/);assert.doesNotMatch(e.body.textContent,/Nguyên vẹn/);
  const empty=environment({items:[]});await empty.open();assert.match(empty.body.textContent,/Chưa có dữ liệu/);
});
test("Private image uses authenticated client by IDs and cleans image URLs on leaving",async()=>{
  const e=environment();await e.open();await e.body.all("button")[0].click();
  assert.equal(e.requests[1].url,"/api/v1/orders/99/pickup-receipts/8/image");
  assert.equal(e.requests[1].responseType,"blob");assert.equal(e.requests[1].signal,e.owner.abort.signal);
  assert.equal(e.body.all("img")[0].src,"blob:0");e.close();assert.deepEqual(e.revoked,["blob:0"]);
});
test("Late image after dialog close is discarded",async()=>{
  const e=environment();let resolve;e.image=()=>new Promise(r=>resolve=r);await e.open();
  const loading=e.body.all("button")[0].click();e.close();resolve(new Blob(["png"],{type:"image/png"}));await loading;
  assert.equal(e.created.length,0);assert.equal(e.body.all("img").length,0);
});
test("Invalid image response explains error and cannot create an image URL",async()=>{
  const e=environment();e.image=()=>new Blob(["html"],{type:"text/html"});await e.open();await e.body.all("button")[0].click();
  assert.match(e.body.textContent,/Ảnh nhận kiện không hợp lệ/);assert.equal(e.created.length,0);
});
test("Replacing photo releases old URL and close releases the last URL once",async()=>{
  const e=environment();await e.open();const button=e.body.all("button")[0];await button.click();await button.click();
  assert.deepEqual(e.revoked,["blob:0"]);assert.equal(e.body.all("img")[0].src,"blob:1");
  e.close();assert.deepEqual(e.revoked,["blob:0","blob:1"]);
});
