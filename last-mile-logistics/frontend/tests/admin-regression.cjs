"use strict";
module.exports=async c=>{const {api,admin,checks,assert,visit,until,evaluate,click,check,snapshot}=c;
 const warehouses=await api('/api/v1/warehouses',admin),warehouse=warehouses[0],locations=await api('/api/v1/warehouses/'+warehouse.id+'/locations',admin);assert(locations.length);const location=locations[0];const options=await api('/api/v1/order-form/options',admin);assert(options.services.length&&options.branches.some(b=>b.id===warehouse.branchId));
 await visit(admin,'#/orders/create');await until("document.querySelector('.order-form')&&!document.querySelector('.order-form fieldset').disabled&&document.querySelectorAll('.order-customer select').length===4");
 await evaluate(`(()=>{const form=document.querySelector('.order-form');const set=(label,value)=>{const cap=[...form.querySelectorAll('label')].find(n=>n.textContent===label);const input=document.getElementById(cap.htmlFor);input.value=value;input.dispatchEvent(new Event('change',{bubbles:true}));};set('Bưu cục *',${JSON.stringify(String(warehouse.branchId))});set('Dịch vụ *',${JSON.stringify(String(options.services[0].id))});set('Tên hàng *','QA admin regression parcel');set('Kg / đơn vị *','1');for(const field of form.querySelectorAll('.order-customer')){const customer=field.querySelector('select');customer.value=customer.options[1].value;customer.dispatchEvent(new Event('change',{bubbles:true}));}})()`);
 await until("[...document.querySelectorAll('.order-customer')].every(p=>p.querySelectorAll('select')[1].options.length>1)");await evaluate("(()=>{for(const p of document.querySelectorAll('.order-customer')){const a=p.querySelectorAll('select')[1];a.value=a.options[1].value;a.dispatchEvent(new Event('change',{bubbles:true}));}document.querySelector('.order-form').requestSubmit()})()");await until("Router.current()?.name==='order-detail'&&document.querySelector('.order-summary')");const orderId=await evaluate('Router.current().params.id'),created=await api('/api/v1/orders/'+orderId,admin);assert.equal(created.status,'NEW');checks.push('Existing create-order form submits to real API with actual customers/addresses/services');
 await api('/api/v1/orders/'+orderId+'/confirm',admin,'POST',{distanceKm:1});await visit(admin,'#/warehouse/inbound?warehouseId='+warehouse.id+'&locationId='+location.id+'&keyword='+encodeURIComponent(created.orderCode));await until(`document.querySelector('[data-inbound-order="${orderId}"]')&&!document.querySelector('[data-inbound-order="${orderId}"]').disabled`);await evaluate(`document.querySelector('[data-inbound-order="${orderId}"]').click()`);await until("document.querySelector('dialog.inbound-dialog form')");await click('Xem và xác nhận','dialog');await until("!document.querySelector('.warehouse-confirmation').classList.contains('d-none')");await click('Xác nhận nhập kho','dialog');await until("!document.querySelector('dialog')&&document.querySelector('.alert-success')?.textContent.includes('Nhập kho thành công')");const stored=await api('/api/v1/orders/'+orderId,admin);assert.equal(stored.status,'IN_WAREHOUSE');checks.push('Existing inbound modal performs real confirmation and stores new order in warehouse');
 await api('/api/v1/orders/'+orderId+'/ready-for-dispatch',admin,'POST');const queue=await api('/api/v1/dispatch/orders?pageSize=100',admin);assert(queue.items.some(r=>(r.id??r.orderId)===orderId));const candidates=await api('/api/v1/dispatch/shippers?orderId='+orderId,admin);assert(Array.isArray(candidates.items)&&Array.isArray(candidates.excludedVehicles));checks.push('Dispatch queue/candidate APIs still accept the warehouse-ready order; dispatch UI is existing placeholder');
 for(const [route,ready,name] of [
  ['#/admin/roles',"document.querySelector('.admin-roles tbody')",'roles-list'],
  ['#/admin/catalogs?type=AREAS',"document.querySelector('.admin-catalogs tbody')",'catalogs-areas'],
  ['#/admin/catalogs?type=LOCATIONS&warehouseId='+warehouse.id,"document.querySelector('.locations-list tbody')",'catalogs-locations'],
  ['#/admin/pricing',"document.querySelector('.admin-pricing tbody')",'pricing-list'],
  ['#/admin/audit-logs',"document.querySelector('.admin-audit-logs tbody')",'audit-list']
 ]) {
  await visit(admin,route);
  await until(`(${ready})||document.getElementById('page-title').textContent==='Chưa thể mở trang'`);
  if(await evaluate("document.getElementById('page-title').textContent==='Chưa thể mở trang'")) {
   await check('Transport error retains session','ApiClient.getSession()!==null');
   await click('Thử lại'); await until(ready);
   checks.push('Transient route transport error recovers through explicit Retry');
  }
  await check(name+' renders one shell title and real rows',"document.querySelectorAll('#page-title').length===1&&!document.querySelector('#page-content').textContent.includes('Chưa triển khai')");
  await snapshot(name,1440);await snapshot(name,390);
  if(name==='catalogs-locations') await check('Selected catalog tab is readable',"(()=>{const n=document.querySelector('.admin-catalogs a[aria-current=page]');const css=getComputedStyle(n);return css.color!==css.backgroundColor&&n.textContent==='Vị trí lưu kho';})()");
 }

};
