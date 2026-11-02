"use strict";
// Real SQL/API/browser checks; writes only inside dispatch-browser's GUID fixture.
module.exports=async c=>{
  const {api,fixture,fixtureCommand,admin,checks,assert,visit,evaluate,until,check,click,change,snapshot,root}=c;
  const {promisify}=require('node:util'),{execFile}=require('node:child_process'),path=require('node:path');
  await fixtureCommand('DepotNoSource');
  const sql=(await fixtureCommand('Inspect')).testData.depots;
  const bt=sql.find(w=>w.code==='KHO-BT-PL'),tp=sql.find(w=>w.code==='KHO-TP-PL');
  const options=await api('/api/v1/dispatch/options',admin);
  for(const warehouse of [tp,bt]){
    const response=await api('/api/v1/warehouses/'+warehouse.id+'/depot',admin);
    const option=options.warehouses.find(w=>w.id===warehouse.id);
    assert.equal(response.latitude,warehouse.latitude);assert.equal(response.longitude,warehouse.longitude);
    assert.equal(response.id,warehouse.id);assert.equal(response.branchId,warehouse.branchId);
    assert.equal(typeof response.latitude,'number');assert.equal(typeof response.longitude,'number');
    assert.equal(response.coordinateState,'CONFIGURED');assert.equal(response.coordinateSource,null);
    assert.equal(option.latitude,response.latitude);assert.equal(option.longitude,response.longitude);
  }
  assert.notEqual(bt.latitude,tp.latitude);assert.notEqual(bt.longitude,tp.longitude);
  checks.push('KHO-TP-PL and KHO-BT-PL HTTP depot/options return their exact SQL decimal coordinates as numeric latitude/longitude, including a NULL source');
  const diagnostic=await promisify(execFile)('dotnet',[path.join(root,'frontend/tests/.artifacts/depot-diagnostics/DepotDiagnostics.dll'),root,path.join(root,'docs/dispatch/warehouse-depot-isolated.json')],{cwd:root,windowsHide:true,env:{...process.env,ConnectionStrings__DefaultConnection:fixture.connectionString},maxBuffer:4*1024*1024});
  const mappings=JSON.parse(diagnostic.stdout).depotMapping;assert.equal(mappings.length,2);
  for(const mapping of mappings){const warehouse=sql.find(w=>w.id===mapping.warehouseId);assert.equal(mapping.state,'CONFIGURED');assert(mapping.sameDepot);assert.equal(mapping.inputDepot.Latitude,warehouse.latitude);assert.equal(mapping.inputDepot.Longitude,warehouse.longitude);assert.deepEqual(mapping.inputDepot,mapping.proposalDepot);}
  checks.push('Real DispatchData.Load and VrpPlanner preserve both selected SQL depots; diagnostic selections are empty and create no business records');
  const outside=fixture.actors.find(a=>a.role==='DISPATCHER'&&a.branchId!==bt.branchId);
  await api('/api/v1/warehouses/'+bt.id+'/depot',outside,'GET',undefined,404);
  await api('/api/v1/warehouses/'+bt.id+'/depot',null,'GET',undefined,401);
  checks.push('Automatic depot reads retain authentication and branch scope');
  const ready="document.querySelector('.dispatch-depot-status')?.getAttribute('aria-busy')==='false'";
  await visit(admin,'#/dispatch/optimization?warehouseId='+tp.id+'&step=1');await until(ready);
  await check('Opening optimization auto-fetches the explicitly selected warehouse and removes coordinate management controls',"document.querySelector('.dispatch-depot [name=warehouseId]').value==='"+tp.id+"'&&qa.requests.some(r=>r.url.endsWith('/warehouses/"+tp.id+"/depot'))&&!document.querySelector('.dispatch-depot-panel')&&![...document.querySelectorAll('button')].some(n=>n.textContent.includes('Tải lại tọa độ kho')||n.textContent.includes('Nhập / cập nhật tọa độ'))");
  await evaluate(`(()=>{qa.depotFetch=window.fetch;window.fetch=(...args)=>{if(String(args[0]).endsWith('/warehouses/${bt.id}/depot')){qa.oldDepotSignal=args[1].signal;return new Promise(resolve=>{qa.releaseDepot=()=>resolve(new Response(JSON.stringify({id:${bt.id},branchId:${bt.branchId},latitude:null,longitude:null}),{status:200,headers:{'Content-Type':'application/json'}}));});}return qa.depotFetch(...args);};})()`);
  await change('warehouseId',bt.id,'.dispatch-depot');await until("typeof qa.releaseDepot==='function'");
  await change('warehouseId',tp.id,'.dispatch-depot');await until(ready);
  await evaluate('qa.releaseDepot();new Promise(resolve=>setTimeout(resolve,40))');
  await check('Changing warehouse aborts the previous request and ignores its delayed missing-coordinate response',"qa.oldDepotSignal.aborted&&document.querySelector('.dispatch-depot [name=warehouseId]').value==='"+tp.id+"'&&!document.querySelector('.dispatch-depot-status').textContent.includes('chưa có tọa độ')");
  await evaluate('window.fetch=qa.depotFetch');
  await change('warehouseId',bt.id,'.dispatch-depot');await until(ready);
  await until("document.querySelector('input[data-order=\""+fixture.testData.orders[0].id+"\"]')&&!document.querySelector('.dispatch-table-host[aria-busy=true]')");
  await evaluate("document.querySelector('input[data-order=\""+fixture.testData.orders[0].id+"\"]').click()");await click('Lập phương án giao');
  await until("document.querySelector('.dispatch-drivers')&&"+ready+"&&[...document.querySelectorAll('button')].some(n=>n.textContent==='Tính đề xuất'&&!n.disabled)");
  await check('A valid SQL depot with no source metadata allows calculation while busy shippers remain disabled',"!document.querySelector('.dispatch-depot-status').textContent.includes('chưa có tọa độ')&&[...document.querySelectorAll('.dispatch-driver')].some(n=>n.textContent.includes('Shipper chưa sẵn sàng')&&n.querySelector('input').disabled)");
  const request={warehouseId:bt.id,orderIds:[fixture.testData.orders[0].id],shipperIds:[fixture.testData.drivers[0].id],departureAt:new Date(Date.now()+45*60000).toISOString(),serviceMinutes:5,returnToDepot:true};
  const plan=await api('/api/v1/dispatch/plans',admin,'POST',request);assert.equal(plan.depot.latitude,bt.latitude);assert.equal(plan.depot.longitude,bt.longitude);
  await fixtureCommand('OffRoadDepot');
  await api('/api/v1/dispatch/plans/'+plan.id+'/confirm',admin,'POST',{},409);
  const disconnected=await api('/api/v1/dispatch/plans',admin,'POST',request);assert.equal(disconnected.routes.length,0);assert(disconnected.unplanned[0].reason.includes('mạng đường'));
  checks.push('Preview uses the selected SQL depot; confirmation re-reads the same source and rejects changed coordinates with 409');
  await evaluate('Router.reload()');await until(ready+"&&document.querySelector('.dispatch-depot-status').textContent.includes('mạng đường')");
  await check('Off-network coordinates display a short connectivity reason without an input form or false missing warning',"!document.querySelector('dialog')&&!document.querySelector('.dispatch-depot-status').textContent.includes('chưa có tọa độ')");
  await snapshot('dispatch-depot-auto',1366);await snapshot('dispatch-depot-auto',390);
  try{
    await fixtureCommand('NoDepot');await evaluate('Router.reload()');await until(ready+"&&document.querySelector('.dispatch-depot-status').textContent.includes('chưa có tọa độ')");
    await check('Truly missing SQL coordinates block calculation with a short reason and no entry form',"[...document.querySelectorAll('button')].find(n=>n.textContent==='Tính đề xuất').disabled&&!document.querySelector('dialog')");
    await fixtureCommand('InvalidDepot');await evaluate('Router.reload()');await until(ready+"&&document.querySelector('.dispatch-depot-status').textContent.includes('không hợp lệ')");
    await api('/api/v1/dispatch/plans',admin,'POST',request,409);
    checks.push('Invalid SQL coordinates are rejected in API and UI without swapping values or silently substituting a branch location');
  }finally{await fixtureCommand('RestoreDepot');}
  await evaluate('Router.reload()');await until(ready+"&&[...document.querySelectorAll('button')].some(n=>n.textContent==='Tính đề xuất'&&!n.disabled)");
  const current=await api('/api/v1/dispatch/options',admin);
  assert.deepEqual(current.shippers.map(s=>[s.id,s.availability,s.eligibilityReason]),options.shippers.map(s=>[s.id,s.availability,s.eligibilityReason]));
  await check('The optimization screen only reads depot APIs and never sends a coordinate write',"!qa.requests.some(r=>r.url.endsWith('/depot')&&r.method!=='GET')");
};
