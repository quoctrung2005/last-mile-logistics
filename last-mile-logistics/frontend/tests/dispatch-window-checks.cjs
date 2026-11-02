"use strict";
// Real HTTP/JWT/SQL checks, called only inside the GUID dispatch fixture.
module.exports = async c => {
  const {api, fixtureCommand, fixture, admin, checks, assert, root} = c;
  const start = checks.length, data = fixture.testData;
  const request = () => ({warehouseId:data.warehouseId, orderIds:data.orders.slice(0,3).map(o=>o.id),
    shipperIds:data.drivers.map(d=>d.id), departureAt:new Date(Date.now()+45*60000).toISOString(), serviceMinutes:5, returnToDepot:true});
  const preview = body => api('/api/v1/dispatch/plans',admin,'POST',body||request());
  const confirm = (p,status=200) => api('/api/v1/dispatch/plans/'+p.id+'/confirm',admin,'POST',{},status);
  const close = async result => {for(const trip of result.trips) await api('/api/v1/trips/'+trip.id+'/actions',admin,'POST',{action:'CANCEL',reason:'Isolated window test cleanup'});};
  function timing(route, departure) {
    let clock=Date.parse(departure);
    for(const stop of route.stops) {
      const arrival=clock+stop.travelMinutes*60000;
      const earliest=stop.requestedDeliveryAt?Date.parse(stop.requestedDeliveryAt):arrival;
      const service=Math.max(arrival,earliest);
      assert(Math.abs(Date.parse(stop.arrivalAt)-arrival)<2);
      assert(Math.abs(Date.parse(stop.serviceStartAt)-service)<2);
      assert(Math.abs(stop.waitingMinutes-(service-arrival)/60000)<1e-6);
      assert(Math.abs(Date.parse(stop.departureAt)-(service+5*60000))<2);
      if(stop.expectedDeliveryAt) assert(service<=Date.parse(stop.expectedDeliveryAt));
      clock=Date.parse(stop.departureAt);
    }
    if(route.legs.length>route.stops.length)clock+=route.legs.at(-1).travelSeconds*1000;
    assert(Math.abs(Date.parse(route.endAt)-clock)<2);
    assert(Math.abs(route.durationMinutes-(clock-Date.parse(departure))/60000)<1e-6);
  }
  try {
    await fixtureCommand('WindowSchedule');
    const queue=await api('/api/v1/dispatch/orders?keyword=QA-ROUTE&pageSize=100',admin);
    assert(queue.items.every(o=>o.requestedDeliveryAt&&o.expectedDeliveryAt));
    checks.push('Queue API exposes the actual earliest and latest service-start times from SQL');
    const before=(await fixtureCommand('Inspect')).testData;
    const plan=await preview();assert.equal(plan.unplanned.length,0);
    assert(plan.routes.some(r=>r.stops.some(s=>s.waitingMinutes>0)));
    for(const route of plan.routes)timing(route,plan.departureAt);
    const stored=await api('/api/v1/dispatch/plans/'+plan.id,admin);
    assert.deepEqual(stored.routes,plan.routes);
    checks.push('Real SQL requestedDeliveryAt becomes persisted proposal timing; totals include waiting, service and depot return');
    await fixtureCommand('ChangeRequestedTime');
    const changed=await confirm(plan,409);assert(changed.message.includes('lịch giao')&&changed.message.includes('tính lại'));
    const after=(await fixtureCommand('Inspect')).testData;
    assert.equal(after.assignmentCount,before.assignmentCount);assert.equal(after.tripCount,before.tripCount);
    checks.push('Changing requestedDeliveryAt after preview returns 409 and creates no trip or assignment');
    const deadlinePlan=await preview();await fixtureCommand('ChangeExpectedTime');
    await confirm(deadlinePlan,409);
    checks.push('Changing expectedDeliveryAt after preview also invalidates the plan fingerprint with 409');
    const manual=await preview({...request(),manualRoutes:plan.routes.map(r=>({shipperId:r.shipperId,orderIds:r.stops.map(s=>s.orderId)}))});
    assert.equal(manual.method,'MANUAL_VALIDATED');for(const route of manual.routes)timing(route,manual.departureAt);
    checks.push('Manual API uses the same service-start/wait/departure evaluator as automatic planning');
    const ready=await preview();await fixtureCommand('TamperTimings');
    const confirmed=await confirm(ready);
    try {
      for(const trip of confirmed.trips) {
        const route=(await api('/api/v1/trips/'+trip.id+'/route',admin)).route;
        timing(route,ready.departureAt);
        assert(route.stops.some(s=>s.waitingMinutes>0));
        assert(route.stops.every(s=>Date.parse(s.serviceStartAt)>=Date.parse(s.requestedDeliveryAt)));
        const detail=await api('/api/v1/trips?id='+trip.id,admin);
        assert.equal(detail.estimatedDurationMinutes,Math.ceil(route.durationMinutes));
        for(const order of detail.orders) {
          const stop=route.stops.find(s=>s.orderId===order.orderId);
          const planned=/Z$|[+-]\d{2}:\d{2}$/.test(order.plannedArrivalAt)?order.plannedArrivalAt:order.plannedArrivalAt+'Z';
          assert(Math.abs(Date.parse(planned)-Date.parse(stop.arrivalAt))<=1000);
        }
      }
      checks.push('Confirmation recomputes tampered saved timing, persists UTC route JSON with waiting and preserves planned-arrival column meaning');
    } finally {await close(confirmed);}

    // The existing missing-deadline behavior is unbounded; never fabricate one.
    await fixtureCommand('NoDeadline');const noDeadline=await preview();
    assert.equal(noDeadline.unplanned.length,0);assert(noDeadline.routes.flatMap(r=>r.stops).every(s=>s.expectedDeliveryAt===null));
    assert(noDeadline.routes.some(r=>r.stops.some(s=>s.waitingMinutes>0)));
    checks.push('Missing expectedDeliveryAt stays null and unbounded while a requested start still causes waiting');
    await fixtureCommand('ResetSchedule');const noRequest=await preview();
    assert(noRequest.routes.flatMap(r=>r.stops).every(s=>s.requestedDeliveryAt===null&&s.waitingMinutes===0&&s.serviceStartAt===s.arrivalAt));
    checks.push('Null requestedDeliveryAt preserves the prior zero-wait schedule over real API/SQL');
    await fixtureCommand('InvalidSchedule');const invalid=await preview();
    assert(invalid.unplanned.some(o=>o.orderId===data.orders[0].id&&o.reason.includes('Lịch giao không hợp lệ')));
    const badManual={...request(),manualRoutes:[{shipperId:data.drivers[0].id,orderIds:[data.orders[0].id]}]};
    const bad=await api('/api/v1/dispatch/plans',admin,'POST',badManual,422);assert(bad.message.includes('Lịch giao không hợp lệ'));
    checks.push('Reversed SQL delivery windows have explicit per-order errors and manual planning returns 422');
  } finally {await fixtureCommand('ResetSchedule');}
  require('node:fs').writeFileSync(require('node:path').join(root,'docs/dispatch/delivery-window-verification.json'),JSON.stringify({
    mode:'Real HTTP/JWT/API/SQL with GUID test database; no operational writes',checks:checks.slice(start),count:checks.length-start
  },null,2)+'\n');
};
