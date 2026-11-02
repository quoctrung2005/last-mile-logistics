"use strict";
const assert = require("node:assert/strict");
module.exports = async ({send,debugPort,origin,session,admin,customerId,click,change,rowClick,until,checks}) => {
  const {targetId} = await send("Target.createTarget", {url:"about:blank"});
  let socket;
  try {
    const targets = await (await fetch("http://127.0.0.1:"+debugPort+"/json/list")).json();
    socket = new WebSocket(targets.find(tab=>tab.id===targetId).webSocketDebuggerUrl);
    await new Promise((resolve,reject)=>{socket.addEventListener("open",resolve,{once:true});socket.addEventListener("error",reject,{once:true});});
    let serial=0;
    const pending=new Map();
    socket.addEventListener("message",event=>{const data=JSON.parse(event.data);if(data.id){const item=pending.get(data.id);pending.delete(data.id);data.error?item.reject(Error(data.error.message)):item.resolve(data.result);}});
    const call=(method,params={})=>new Promise((resolve,reject)=>{const id=++serial;pending.set(id,{resolve,reject});socket.send(JSON.stringify({id,method,params}));});
    const evaluate=async expression=>{const result=await call("Runtime.evaluate",{expression,awaitPromise:true,returnByValue:true});if(result.exceptionDetails)throw Error(result.exceptionDetails.text);return result.result.value;};
    const wait=async expression=>{for(let i=0;i<250;i++){if(await evaluate(`(()=>{try{return Boolean(${expression})}catch{return false}})()`))return;await new Promise(r=>setTimeout(r,40));}throw Error("Second tab timed out: "+expression);};
    const press=label=>evaluate(`(()=>{const b=[...document.querySelectorAll('dialog button,#page-content button')].find(b=>b.textContent===${JSON.stringify(label)});if(!b)throw Error('Missing button');b.click();})()`);
    const edit=(name,value)=>evaluate(`(()=>{const n=document.querySelector('dialog [name=${name}]');n.value=${JSON.stringify(value)};n.dispatchEvent(new Event('input',{bubbles:true}));})()`);
    const isOpen="document.querySelector('dialog form')";
    const detail="!document.querySelector('dialog')&&document.querySelector('#customer-addresses')";
    await call("Page.enable");await call("Runtime.enable");
    await call("Page.addScriptToEvaluateOnNewDocument",{source:`if(location.origin===${JSON.stringify(origin)}){
      sessionStorage.setItem('tvd.session',${JSON.stringify(JSON.stringify(session(admin)))});
      window.versionQA={requests:[],readVersions:[],confirmMessages:[],confirmNext:false,failRead:false,errors:[]};
      addEventListener('error',e=>versionQA.errors.push(e.message));addEventListener('unhandledrejection',e=>versionQA.errors.push(String(e.reason)));
      window.confirm=message=>{versionQA.confirmMessages.push(message);return versionQA.confirmNext;};
      const original=fetch;window.fetch=async(url,options={})=>{
        const method=options.method||'GET',tracked=String(url).startsWith('/api/v1/customers/${customerId}');
        if(tracked)versionQA.requests.push({url,method,payload:options.body?JSON.parse(options.body):null});
        if(tracked&&method==='GET'&&versionQA.failRead){versionQA.failRead=false;return new Response(JSON.stringify({message:'QA reload unavailable'}),{status:503,headers:{'Content-Type':'application/json'}});}
        const result=await original(url,options);if(tracked&&method==='GET'&&result.ok){const data=await result.clone().json();versionQA.readVersions.push(data.version);}
        return result;
      };
    }`});
    await call("Page.navigate",{url:origin+"/#/customers/"+customerId});await wait(detail);
    await click("Sửa khách hàng");await until(isOpen);
    await press("Sửa khách hàng");await wait(isOpen);
    const opened=await evaluate("versionQA.readVersions.at(-1)");
    await change("Email","qa.tab.a@example.test");await edit("email","qa.tab.b@example.test");
    await click("Lưu","dialog button");await until(detail);
    const reads=await evaluate("versionQA.requests.filter(r=>r.method==='GET').length");
    await press("Lưu");await wait("document.querySelector('dialog .alert-danger')?.textContent.includes('409')");
    assert.equal(await evaluate("document.querySelector('dialog [name=email]').value"),"qa.tab.b@example.test");
    assert.equal(await evaluate("document.querySelector('dialog button[type=submit]').disabled"),true);
    assert.equal(await evaluate("versionQA.requests.filter(r=>r.method==='PUT').at(-1).payload.expectedVersion"),opened);
    assert.equal(await evaluate("versionQA.requests.filter(r=>r.method==='GET').length"),reads);
    await evaluate("document.querySelector('dialog form').dispatchEvent(new Event('submit',{bubbles:true,cancelable:true}))");
    assert.equal(await evaluate("versionQA.requests.filter(r=>r.method==='PUT').length"),1);
    checks.push("Two browser tabs edit one customer: A saves; B sends its opened version, gets real 409, retains text and cannot submit again or refresh version silently");

    await press("Tải dữ liệu mới");
    assert.equal(await evaluate("document.querySelector('dialog [name=email]').value"),"qa.tab.b@example.test");
    assert.equal(await evaluate("versionQA.requests.filter(r=>r.method==='GET').length"),reads);
    assert.match(await evaluate("versionQA.confirmMessages.at(-1)"),/bỏ toàn bộ nội dung chưa lưu/);
    await evaluate("versionQA.confirmNext=true;versionQA.failRead=true");await press("Tải dữ liệu mới");
    await wait("document.querySelector('dialog').textContent.includes('QA reload unavailable')&&!document.querySelector('dialog form').inert");
    assert.equal(await evaluate("document.querySelector('dialog [name=email]').value"),"qa.tab.b@example.test");
    assert.equal(await evaluate("document.querySelector('dialog button[type=submit]').disabled"),true);
    await press("Tải dữ liệu mới");
    await wait("document.querySelector('dialog [name=email]')?.value==='qa.tab.a@example.test'&&!document.querySelector('dialog button[type=submit]').disabled");
    const reloaded=await evaluate("versionQA.readVersions.at(-1)");assert.notEqual(reloaded,opened);
    await edit("email","qa.tab.b.after.reload@example.test");await press("Lưu");await wait(detail);
    assert.equal(await evaluate("versionQA.requests.filter(r=>r.method==='PUT').at(-1).payload.expectedVersion"),reloaded);
    checks.push("Reload warns before discarding edits; cancel and failed GET preserve the blocked form; confirmed successful reload opens a new version that can save");

    await rowClick("QA Address Two","Sửa");await until(isOpen);
    await evaluate("(()=>{const row=[...document.querySelectorAll('#customer-addresses tbody tr')].find(r=>r.cells[0].textContent==='QA Address Two');[...row.querySelectorAll('button')].find(b=>b.textContent==='Sửa').click();})()");await wait(isOpen);
    await change("Địa chỉ *","QA address tab A");await edit("address","QA address tab B");
    await click("Lưu","dialog button");await until(detail);
    const beforeReads=await evaluate("versionQA.requests.filter(r=>r.method==='GET').length");
    await press("Lưu");await wait("document.querySelector('dialog .alert-danger')?.textContent.includes('409')");
    assert.equal(await evaluate("document.querySelector('dialog [name=address]').value"),"QA address tab B");
    assert.equal(await evaluate("document.querySelector('dialog button[type=submit]').disabled"),true);
    assert.equal(await evaluate("versionQA.requests.filter(r=>r.method==='GET').length"),beforeReads);
    const puts=await evaluate("versionQA.requests.filter(r=>r.method==='PUT').length");
    await evaluate("document.querySelector('dialog form').dispatchEvent(new Event('submit',{bubbles:true,cancelable:true}))");
    assert.equal(await evaluate("versionQA.requests.filter(r=>r.method==='PUT').length"),puts);
    await press("Tải dữ liệu mới");await wait("document.querySelector('dialog [name=address]')?.value==='QA address tab A'&&!document.querySelector('dialog button[type=submit]').disabled");
    await edit("address","QA updated address 2");await press("Lưu");await wait(detail);
    assert.deepEqual(await evaluate("versionQA.errors"),[]);
    checks.push("Two browser tabs edit one address: stale form receives real 409, retains edits and stays blocked until explicit reload, then saves successfully");
  } finally {socket?.close();await send("Target.closeTarget",{targetId});}
};
