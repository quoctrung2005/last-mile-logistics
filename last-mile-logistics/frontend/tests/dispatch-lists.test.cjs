"use strict";
const {test}=require("node:test");
const assert=require("node:assert/strict"),fs=require("node:fs"),path=require("node:path"),vm=require("node:vm");
const source=fs.readFileSync(path.join(__dirname,"../js/dispatch.js"),"utf8");
const tick=()=>new Promise(resolve=>setImmediate(resolve));

class Element {
  constructor(tag,cls="",text=""){this.tag=tag;this.className=cls;this.text=text;this.children=[];this.events={};this.attributes={};this.value="";this.disabled=false;this.style={};}
  get textContent(){return this.text+this.children.map(n=>n.textContent).join("");}
  set textContent(value){this.text=value;this.children=[];}
  append(...nodes){this.children.push(...nodes);}
  replaceChildren(...nodes){this.text="";this.children=[];this.append(...nodes);}
  setAttribute(name,value){this.attributes[name]=value;}
  addEventListener(type,fn){this.events[type]=fn;}
  reportValidity(){return true;}
  emit(type){return this.events[type]?.({preventDefault(){}});}
  click(){assert.equal(this.disabled,false,"test must click an enabled control");return this.emit("click");}
  querySelectorAll(selector){const found=[];const visit=n=>{for(const child of n.children){if(selector.startsWith(".")?child.className.split(" ").includes(selector.slice(1)):selector.startsWith("[name=")?child.name===selector.slice(6,-1):child.tag===selector)found.push(child);visit(child);}};visit(this);return found;}
  querySelector(selector){return this.querySelectorAll(selector)[0];}
}

function environment(kind,{ignoreAbortState=false,permissions=false}={}){
  const requests=[],failures=[],validated=[],writes=[],el=(...args)=>new Element(...args),container=el("main");
  const options={branches:[],shippers:[]};
  const env={requests,failures,validated,container};
  const window={Router:{updateQuery(){},current(){return null;},href:(name,_params,query)=>name+"?"+new URLSearchParams(query)},TrackingPage:{date:String}};
  const U={el,
    button(label,fn,cls){const n=el("button",cls,label);if(fn)n.addEventListener("click",fn);return n;},
    field(form,fields,key,_label,value){const n=el("input");n.name=key;n.value=value??"";fields[key]={control:n};form.append(n);},
    query:query=>new URLSearchParams(Object.entries(query).filter(([,v])=>v!==undefined&&v!=="")).toString(),
    notice(box,message){box.textContent=message;},
    failure(s,box,error,retry){if(!s.alive())return;failures.push(error.message);box.textContent=error.message;if(retry)box.append(U.button("Thử lại",retry));},
    state(host,_user,route){const abort=new AbortController(),s={root:el("section"),abort,route,alive:()=>!abort.signal.aborted,can:()=>permissions,destroy:()=>abort.abort()};
      // Deliberately ignore signal cancellation in the transport. Even aborted
      // requests may resolve/reject later, so only the latest may change the UI.
      s.read=(url,signal=abort.signal)=>{if(url==="/api/v1/dispatch/options")return Promise.resolve(options);let resolve,reject;const promise=new Promise((r,j)=>{resolve=r;reject=j;});requests.push({url,signal,resolve,reject});return promise;};
      env.s=s;host.replaceChildren(s.root);return s;}
  };
  U.dialog=(_s,title)=>env.dialog={title,body:el("div"),signal:env.s.abort.signal,busyState(){},close(){env.closed=true;}};
  window.WriteOutcome={assertCanSend(){},lock(){return false;}};
  window.Router.reload=()=>env.reloaded=true;
  window.AdminUI=U;window.LogisticsUI={table(_headers,rows){const table=el("table");for(const row of rows){const tr=el("tr");for(const cell of row)tr.append(cell instanceof Element?cell:el("td","",String(cell)));table.append(tr);}return table;}};
  env.writes=writes;
  window.ApiClient={async request(url,request){writes.push({url,...request});return {};},validatePage(data){validated.push(data);if(!Array.isArray(data?.items))throw Error("Invalid page");return data;}};
  const context=vm.createContext({window,AbortController,AbortSignal:ignoreAbortState?{any:()=>({aborted:false})}:AbortSignal,cancelAnimationFrame(){},sessionStorage:{getItem(){return null;}}});
  vm.runInContext(source,context);
  env.start=()=>window.DispatchPage.mount(container,{}, {pageId:kind==="trips"?"delivery-trips":"assignments",query:{keyword:"A",page:1,pageSize:10}},{});
  env.leave=()=>window.DispatchPage.destroy();
  env.body=()=>env.s.content.querySelector(".dispatch-table-host");
  env.pages=()=>env.s.content.querySelector(".dispatch-pager");
  env.form=()=>env.s.content.querySelector(".dispatch-filters");
  env.button=label=>env.s.content.querySelectorAll("button").find(n=>n.textContent===label);
  env.search=async(keyword)=>{env.form().querySelector("[name=keyword]").value=keyword;env.form().emit("submit");await tick();};
  return env;
}

function data(kind,label,{page=1,total=25}={}){
  return {items:[kind==="trips"?{id:1,tripCode:label,warehouseName:"Kho",status:"PLANNED",orderCount:1,totalWeightKg:1,plannedStartAt:"2030-01-01T00:00:00Z"}
    :{id:1,trackingNumber:label,orderCode:"ORDER",shipperName:"Shipper",licensePlate:"51A",assignmentStatus:"PENDING",assignedAt:"2030-01-01T00:00:00Z"}],totalItems:total,page,pageSize:10};
}
function assertLatest(b,label,total=47,page=1){
  assert(b.body().textContent.includes(label),b.body().textContent);
  assert(b.body().textContent.includes(String(total)));
  assert.equal(b.pages().textContent,"TrướcTrang "+page+" / "+Math.ceil(total/10)+"Sau");
  assert.equal(b.body().attributes["aria-busy"],"false");assert.equal(b.s.loading,false);
}

for(const kind of ["trips","assignments"]){
  test(`${kind}: B then A retains B's table, count and pagination; aborts A`,async()=>{
    const b=environment(kind),mounted=b.start();await tick();const first=b.requests[0];
    await b.search("B");assert.equal(first.signal.aborted,true);assert.equal(b.requests.length,2);assert.equal(new URL(b.requests[1].url,"http://localhost").searchParams.get("keyword"),"B");
    b.requests[1].resolve(data(kind,"RESULT-B",{total:47}));await tick();assertLatest(b,"RESULT-B");
    first.resolve(data(kind,"RESULT-A",{total:200}));await mounted;assertLatest(b,"RESULT-B");assert(!b.body().textContent.includes("RESULT-A"));assert.equal(b.failures.length,0);
  });

  test(`${kind}: sequence check works even when cancellation state is not honored`,async()=>{
    const b=environment(kind,{ignoreAbortState:true}),mounted=b.start();await tick();await b.search("B");assert.equal(b.requests[0].signal.aborted,false);
    b.requests[1].resolve(data(kind,"RESULT-B",{total:47}));await tick();b.requests[0].resolve(data(kind,"RESULT-A"));await mounted;assertLatest(b,"RESULT-B");
    assert.equal(b.validated.length,1,"stale response must be ignored before page validation/rendering");
  });

  test(`${kind}: a late A error cannot replace B's success or show an error`,async()=>{
    const b=environment(kind),mounted=b.start();await tick();await b.search("B");b.requests[1].resolve(data(kind,"RESULT-B",{total:47}));await tick();
    b.requests[0].reject(Error("OLD-A-ERROR"));await mounted;assertLatest(b,"RESULT-B");assert.equal(b.s.feedback.textContent,"");assert.deepEqual(b.failures,[]);
  });

  for(const completion of ["success","error"]){
    test(`${kind}: old A ${completion}/finally cannot stop B's loading`,async()=>{
      const b=environment(kind),mounted=b.start();await tick();await b.search("B");
      if(completion==="success")b.requests[0].resolve(data(kind,"RESULT-A"));else b.requests[0].reject(Error("OLD-A-ERROR"));
      await mounted;assert.equal(b.s.loading,true);assert.equal(b.body().attributes["aria-busy"],"true");assert(!b.body().textContent.includes("RESULT-A"));assert.equal(b.pages().textContent,"");assert.deepEqual(b.failures,[]);
      b.requests[1].resolve(data(kind,"RESULT-B",{total:47}));await tick();assertLatest(b,"RESULT-B");
    });
  }

  test(`${kind}: latest error and read-only retry are protected from stale successes`,async()=>{
    const b=environment(kind),mounted=b.start();await tick();await b.search("B");b.requests[1].reject(Error("LATEST-B-ERROR"));await tick();
    assert.equal(b.s.loading,false);assert.equal(b.s.feedback.textContent,"LATEST-B-ERRORThử lại");assert.equal(b.pages().textContent,"");
    b.s.feedback.querySelector("button").click();assert.equal(b.requests.length,3);assert.equal(b.requests[2].url,b.requests[1].url);
    b.requests[0].resolve(data(kind,"RESULT-A"));await mounted;assert.equal(b.s.loading,true);assert.equal(b.s.feedback.textContent,"");assert(!b.body().textContent.includes("RESULT-A"));
    b.requests[2].resolve(data(kind,"RETRY-B",{total:47}));await tick();assertLatest(b,"RETRY-B");
  });

  test(`${kind}: page change and refresh use the same latest-request protection`,async()=>{
    const b=environment(kind),mounted=b.start();await tick();b.requests[0].resolve(data(kind,"PAGE-1"));await mounted;
    b.button("Sau").click();const pageRequest=b.requests[1];assert.equal(new URL(pageRequest.url,"http://localhost").searchParams.get("page"),"2");
    b.button("Làm mới").click();assert.equal(b.requests.length,3);assert.equal(pageRequest.signal.aborted,true);assert.equal(b.requests[2].url,pageRequest.url);
    b.requests[2].resolve(data(kind,"REFRESHED-PAGE-2",{page:2,total:47}));await tick();pageRequest.resolve(data(kind,"OLD-PAGE-2",{page:2,total:200}));await tick();assertLatest(b,"REFRESHED-PAGE-2",47,2);assert(!b.body().textContent.includes("OLD-PAGE-2"));
    await b.search("C");assert.equal(new URL(b.requests[3].url,"http://localhost").searchParams.get("page"),"1");b.requests[3].resolve(data(kind,"SEARCH-C",{total:47}));await tick();assertLatest(b,"SEARCH-C");
  });

  for(const completion of ["success","abort error"]){
    test(`${kind}: leaving aborts pending reads and ignores late ${completion}`,async()=>{
      const b=environment(kind),mounted=b.start();await tick();const s=b.s,body=b.body(),before=body.textContent;
      b.leave();assert.equal(b.requests[0].signal.aborted,true);assert.equal(s.abort.signal.aborted,true);
      if(completion==="success")b.requests[0].resolve(data(kind,"LEFT-SCREEN"));else b.requests[0].reject(Object.assign(Error("Leaving"),{name:"AbortError"}));
      await mounted;assert.equal(body.textContent,before);assert.deepEqual(b.failures,[]);assert.equal(body.attributes["aria-busy"],"true","old finally must not write to a departed screen");
    });
  }
}

for(const clear of [false,true])test(`pickup deadline form ${clear?"clears explicitly":"uses Vietnam time"} and sends PATCH with stale-edit protection`,async()=>{
 const b=environment("assignments",{permissions:true}),mounted=b.start();await tick();
 const page=data("assignments","DEADLINE");Object.assign(page.items[0],{isActive:true,orderStatus:"ASSIGNED",pickupDueAt:"2035-01-01T03:00:00"});
 b.requests[0].resolve(page);await mounted;b.button("Đặt hạn lấy hàng").click();
 const form=b.dialog.body.querySelector("form");form.querySelector('[name=due]').value=clear?"":"2035-01-02T08:00";form.querySelector('[name=reason]').value="  Điều phối điều chỉnh giờ  ";
 await form.emit("submit");assert.equal(b.writes.length,1);const write=b.writes[0],payload=JSON.parse(write.body);
 assert.equal(write.method,"PATCH");assert.equal(write.url,"/api/v1/dispatch/assignments/1/pickup-deadline");assert.equal(payload.expectedPickupDueAt,"2035-01-01T03:00:00.000Z");
 assert.equal(payload.pickupDueAt,clear?null:"2035-01-02T01:00:00.000Z");assert.equal(payload.reason,"Điều phối điều chỉnh giờ");assert.equal(b.reloaded,true);
});
