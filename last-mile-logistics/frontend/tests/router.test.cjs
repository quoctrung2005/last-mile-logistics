"use strict";
const { test } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const source = fs.readFileSync(path.join(__dirname, "../js/router.js"), "utf8");
const admin = { role: "ADMIN", accountId: 1 };
const tick = () => new Promise(resolve => setImmediate(resolve));
test("driver registration review is admin-only and accepts application status filters",()=>{
  const{router}=environment();const route=router.parse('#/fleet/registrations?status=NEEDS_INFO&page=2&pageSize=20');
  assert.equal(route.error,null);assert.equal(route.pageId,'driver-registrations');
  const grants={known:true,codes:new Set(['TAIKHOAN_XEM'])};
  assert(router.allowed(route,admin,grants));
  assert(!router.allowed(route,{role:'BRANCH_MANAGER'},grants));
  assert(!router.allowed(route,{role:'SHIPPER'},grants));
  assert(router.parse('#/fleet/registrations?status=ACTIVE').error);
});
test("COD routes use live reconciliation permission and preserve scoped filters/detail return",()=>{
  const{router}=environment(),query={from:"2026-09-01",to:"2026-09-30",branchId:1,shipperId:3,tab:"deposits",status:"PENDING",keyword:"NC-",page:2,pageSize:20};
  for(const name of ["cod-collections","cod-collection-detail","cod-deposit-detail"]){const route=router.parse(router.href(name,{id:7},query));assert.equal(route.error,null);assert.deepEqual(JSON.parse(JSON.stringify(route.query)),query);assert(!router.allowed(route,admin,{known:true,codes:new Set()}));assert(router.allowed(route,{role:"ACCOUNTANT"},{known:true,codes:new Set(["COD_DOISOAT"])}));}
  assert.equal(router.parse('#/cod/reconciliation?status=CONFIRMED').error,null);for(const q of ['shipperId=0','status=PAID','tab=finance','from=2026-10-02&to=2026-10-01'])assert(router.parse('#/cod/collections?'+q).error);
  const back=router.href('cod-collections',{},query);assert.equal(router.parse(router.href('order-detail',{id:7},{returnTo:back})).query.returnTo,back);
});
test("reports preserve shared filters and validate tab and live report permission",()=>{
  const {router}=environment(),query={from:"2026-10-01",to:"2026-10-17",branchId:2,tab:"delivery",page:2,pageSize:20};
  const route=router.parse(router.href("reports",{},query));assert.equal(route.error,null);assert.deepEqual(JSON.parse(JSON.stringify(route.query)),query);
  assert.equal(router.allowed(route,admin,{known:true,codes:new Set()}),false);
  assert.equal(router.allowed(route,{role:"BRANCH_MANAGER"},{known:true,codes:new Set(["BAOCAO_XEM"])}),true);
  for(const hash of ["#/reports?tab=wrong","#/reports?tab=orders&tab=finance","#/reports?branchId=0","#/reports?from=2026-10-17&to=2026-10-01"])assert(router.parse(hash).error);
});
function environment(initial = "", initialUser = admin, loadPermissions) {
  const listeners = new Map(), storage = new Map(), entries = [initial], states = [null]; let index = 0, user = initialUser;
  const rendered = [], errors = [], signals = []; let permissionCalls = 0, leaves = 0;
  const emit = () => queueMicrotask(() => { for (const listener of listeners.get("hashchange") || []) listener(); });
  const location = { get hash() { return entries[index]; }, set hash(hash) { entries.splice(index + 1); states.splice(index + 1); entries.push(hash); states.push(null); index++; emit(); } };
  const window = { location, history: {
    get state() { return states[index]; },
    replaceState: (state, __, hash) => { entries[index] = hash; states[index] = state; },
    go: delta => { const next=index+delta;if(next>=0&&next<entries.length){index=next;emit();} },
    back: () => { if (index) { index--; emit(); } }, forward: () => { if (index < entries.length - 1) { index++; emit(); } }
  }, addEventListener: (name, fn) => { if (!listeners.has(name)) listeners.set(name, new Set()); listeners.get(name).add(fn); },
  removeEventListener: (name, fn) => listeners.get(name)?.delete(fn), Auth: { getPermissions: async (account, signal) => {
    permissionCalls++; signals.push(signal);
    if (loadPermissions) return loadPermissions(account, signal);
    return { known: true, codes: new Set(["DONHANG_XEM", "DONHANG_TAO", "DONHANG_CAPNHAT", "KHO_XEM"]) };
  } } };
  const sessionStorage = { getItem: key => storage.get(key) ?? null, setItem: (key, value) => storage.set(key, value), removeItem: key => storage.delete(key) };
  vm.runInContext(source, vm.createContext({ window, sessionStorage, URLSearchParams, AbortController }));
  const router = window.Router;
  return { router, window, storage, rendered, errors, signals, setUser: value => { user = value; },
    start() { router.start({ getUser: () => user, onLeave: () => { leaves++; }, onLoading: () => {},
      onRoute: (route, context) => rendered.push({ name: route.name, route, context }), onError: (route, title, message) => errors.push({ route, title, message }) }); },
    counts: () => ({ permissionCalls, leaves, listeners: listeners.get("hashchange")?.size || 0 }) };
}

test("account routes preserve backend filters and require live account-view permission", () => {
  const {router} = environment();
  const filters = {page:2,pageSize:20,keyword:"Nguyễn",roleId:1,branchId:2,status:"LOCKED"};
  for (const name of ["accounts","account-detail"]) {
    const route = router.parse(router.href(name,{id:15},filters));
    assert.equal(route.error,null); assert.deepEqual(JSON.parse(JSON.stringify(route.query)),filters);
    assert.equal(router.allowed(route,admin,{known:true,codes:new Set()}),false);
    assert.equal(router.allowed(route,{role:"BRANCH_MANAGER"},{known:true,codes:new Set(["TAIKHOAN_XEM"])}),true);
  }
  for (const query of ["roleId=0","roleId=2147483648","status=NEW","pageSize=101","keyword="+"x".repeat(151)]) assert.ok(router.parse("#/admin/accounts?"+query).error);
  assert.equal(router.parse("#/admin/accounts/0").name,"not-found");
});

test("admin filters and detail URLs use real permissions and validated query fields", () => {
  const {router}=environment();
  for(const [name,query,grant]of [["roles",{keyword:"ADMIN",isActive:"false"},"PHANQUYEN_QUANLY"],["catalogs",{type:"LOCATIONS",warehouseId:2,status:"ALL"},"BUUCUC_QUANLY"],["pricing",{page:2,pageSize:20,serviceId:1,areaId:2,globalOnly:"false",isActive:"false"},"BANGGIA_QUANLY"],["audit-detail",{from:"2026-10-01",to:"2026-10-10",accountId:1,action:"CREATE_ROLE",objectType:"VaiTro",objectId:"7",keyword:"admin",page:2},"NHATKY_XEM"]]){
    const route=router.parse(router.href(name,{id:7},query));assert.equal(route.error,null);assert.deepEqual(JSON.parse(JSON.stringify(route.query)),query);assert.equal(router.allowed(route,admin,{known:true,codes:new Set()}),false);assert.equal(router.allowed(route,admin,{known:true,codes:new Set([grant])}),true);
  }
  for(const hash of ['#/admin/catalogs?type=FAKE','#/admin/pricing?serviceId=0','#/admin/pricing?globalOnly=yes','#/admin/audit-logs?from=2026-10-10&to=2026-10-01','#/admin/audit-logs?action='+"x".repeat(51)])assert.ok(router.parse(hash).error);
});

test("leave guard cancels route changes without destroying unsaved page; accepted navigation still works", async () => {
  const e=environment('#/admin/roles',admin,async()=>({known:true,codes:new Set(['PHANQUYEN_QUANLY'])}));e.start();await tick();e.router.setLeaveGuard(()=>false);e.router.navigate('#/dashboard');await tick();assert.equal(e.window.location.hash,'#/admin/roles');assert.equal(e.rendered.length,1);assert.equal(e.router.canLeave(),false);e.router.setLeaveGuard(()=>true);e.router.navigate('#/dashboard');await tick();assert.equal(e.rendered.length,2);assert.equal(e.router.current().name,'overview');e.router.stop();
});

test("cancelled Back and Forward restore the original history entry without remounting", async () => {
  const e=environment('#/orders');e.start();await tick();
  e.router.navigate('#/orders/14');await tick();e.router.navigate('#/orders/14/edit');await tick();
  let prompts=0;const release=e.router.setLeaveGuard(()=>{prompts++;return false;});
  const count=e.rendered.length;
  e.window.history.back();await tick();
  assert.equal(e.window.location.hash,'#/orders/14/edit');assert.equal(e.router.current().name,'order-edit');assert.equal(e.rendered.length,count);assert.equal(prompts,1);
  release();e.window.history.back();await tick();assert.equal(e.router.current().name,'order-detail');
  const releaseNext=e.router.setLeaveGuard(()=>{prompts++;return false;});
  e.window.history.forward();await tick();assert.equal(e.window.location.hash,'#/orders/14');assert.equal(e.router.current().name,'order-detail');assert.equal(prompts,2);
  releaseNext();e.window.history.forward();await tick();assert.equal(e.router.current().name,'order-edit');
  e.window.history.back();await tick();e.window.history.back();await tick();assert.equal(e.router.current().name,'orders');e.router.stop();
});

test("disposing an old leave guard cannot remove a newer registration, even with the same callback", () => {
  const {router}=environment(),guard=()=>false;
  const first=router.setLeaveGuard(guard),second=router.setLeaveGuard(guard);
  first();assert.equal(router.canLeave(),false);second();assert.equal(router.canLeave(),true);
});

test("session expiry bypasses an unsaved page guard and old cleanup preserves the next guard", async () => {
  const e=environment('#/orders/14/edit');e.start();await tick();
  const release=e.router.setLeaveGuard(()=>false);e.setUser(null);e.router.goLogin(true);await tick();
  assert.equal(e.router.current().name,'login');
  const releaseNew=e.router.setLeaveGuard(()=>false);release();assert.equal(e.router.canLeave(),false);releaseNew();e.router.stop();
});

test("custom roles can open implemented screens only with live grants and never inherit admin management", () => {
  const {router}=environment(),user={role:"QA_CUSTOM",accountId:22},permissions={known:true,codes:new Set(["DONHANG_XEM","KHO_XEM"])};
  assert.equal(router.allowed(router.parse('#/orders'),user,permissions),true);assert.equal(router.allowed(router.parse('#/warehouse/inventory'),user,permissions),true);assert.equal(router.allowed(router.parse('#/admin/roles'),user,{known:true,codes:new Set(['PHANQUYEN_QUANLY'])}),false);
  const menus=router.visibleMenus(user,permissions);assert(menus.some(m=>m.id==='orders'));assert(menus.some(m=>m.id==='warehouse'));assert(!menus.some(m=>m.id==='admin'));assert(!menus.some(m=>m.id==='fleet'));
});

test("every existing menu has a unique route, and IDs match only positive safe integers", () => {
  const { router } = environment(); const hashes = [];
  for (const menu of router.visibleMenus(admin)) for (const page of menu.children || [menu]) {
    const hash = router.href(page.id); hashes.push(hash); assert.equal(router.parse(hash).pageId, page.id); assert.notEqual(hash, "#");
  }
  assert.equal(new Set(hashes).size, hashes.length);
  assert.equal(router.parse("#/orders/14").params.id, 14);
  assert.equal(router.parse("#/orders/14/edit").mode, "edit");
  assert.equal(router.parse("#/warehouse/transactions/8").params.id, 8);
  for (const hash of ["#/orders/0", "#/orders/-1", "#/orders/1.5", "#/orders/9007199254740992", "#/orders/x", "#/missing"]) assert.equal(router.parse(hash).name, "not-found");
});

test("query validation rejects bad, duplicate and unsupported parameters before permission/API work", async () => {
  for (const hash of ["#/orders?page=0", "#/orders?page=100001", "#/orders?pageSize=101", "#/orders?status=INVALID", "#/orders?page=1&page=2", "#/orders?page=&page=2", "#/orders?status=&status=NEW", "#/orders?keyword=" + "a".repeat(101),
    "#/warehouse/inventory?warehouseId=-1", "#/warehouse/inbound?status=NEW", "#/warehouse/outbound?acceptedOnly=1", "#/warehouse/transactions?type=INVALID", "#/orders?returnUrl=https://evil.example"]) {
    const e = environment(hash); e.start(); await tick();
    assert.equal(e.errors[0].title, "URL không hợp lệ"); assert.equal(e.counts().permissionCalls, 0); assert.equal(e.rendered.length, 0); e.router.stop();
  }
  const { router } = environment();
  const route = router.parse("#/orders?page=2&status=NEW&keyword=%C4%91%C6%A1n");
  assert.equal(route.query.page, 2); assert.equal(route.query.keyword, "đơn");
});

test("empty hash resolves Login anonymously or Dashboard with a session", async () => {
  for (const user of [null, admin]) {
    const e = environment("", user); e.start(); await tick();
    assert.equal(e.window.location.hash, user ? "#/dashboard" : "#/login"); assert.equal(e.rendered.length, 1); e.router.stop();
  }
});

test("warehouse transaction filters preserve calendar dates and legacy IDs", () => {
  const {router}=environment();
  const query={warehouseId:1,orderId:14,type:'MOVE',keyword:'XK-',fromDate:'2026-10-01',toDate:'2026-10-09',page:2,pageSize:20};
  for(const name of ['warehouse-transactions','transaction-detail']){
    const route=router.parse(router.href(name,{id:8},query));assert.equal(route.error,null);assert.deepEqual(JSON.parse(JSON.stringify(route.query)),query);
  }
  for(const query of ['fromDate=2026-02-30','toDate=bad','fromDate=2026-10-10&toDate=2026-10-09','fromDate=0000-01-01'])assert.ok(router.parse('#/warehouse/transactions?'+query).error);
  const source=router.href('warehouse-transactions',{},query);assert.equal(router.parse(router.href('order-detail',{id:14},{returnTo:source})).query.returnTo,source);
});

test("location management supports state and search without changing order state validation", () => {
  const { router } = environment();
  for (const status of ["ACTIVE", "INACTIVE", "ALL"]) {
    const hash = router.href("warehouse-locations", {}, { warehouseId: 1, keyword: "Kệ", status });
    const route = router.parse(hash); assert.equal(route.error, null); assert.equal(route.query.status, status); assert.equal(route.query.keyword, "Kệ");
  }
  assert.ok(router.parse("#/warehouse/locations?status=NEW").error);
  assert.ok(router.parse("#/orders?status=ACTIVE").error);
});

test("outbound filters and detail return link preserve warehouse, location and assignment status", () => {
  const { router } = environment();
  const hash = router.href("warehouse-outbound", {}, { warehouseId: 2, locationId: 7, page: 3, pageSize: 20, keyword: "đơn", assignmentStatus: "PENDING" });
  const route = router.parse(hash);
  assert.equal(route.error, null);
  assert.deepEqual(JSON.parse(JSON.stringify(route.query)), { warehouseId: 2, locationId: 7, page: 3, pageSize: 20, keyword: "đơn", assignmentStatus: "PENDING" });
  assert.equal(router.parse(router.href("order-detail", { id: 14 }, { returnTo: hash })).query.returnTo, hash);
  for (const query of ["assignmentStatus=INVALID", "locationId=0", "assignmentStatus=PENDING&assignmentStatus=ACCEPTED"]) {
    assert.ok(router.parse("#/warehouse/outbound?" + query).error);
  }
  assert.equal(router.parse("#/warehouse/outbound?acceptedOnly=true").query.acceptedOnly, "true");
});

test("order detail/edit preserve an internal source list and its filters; unsafe/nested return targets fail", () => {
  const { router } = environment();
  const source = router.href("inventory", {}, { warehouseId: 2, page: 3, keyword: "đơn", status: "IN_WAREHOUSE" });
  for (const name of ["order-detail", "order-edit"]) {
    const hash = router.href(name, { id: 14 }, { returnTo: source });
    assert.equal(router.parse(hash).query.returnTo, source);
    assert.equal(router.parse(router.parse(hash).query.returnTo).query.page, 3);
    for (const target of ["https://evil.example", "#//evil.example", "#/login", "#/missing", "#/orders/1", "#/orders?page=0", "#/orders?returnTo=%23%2Forders", "#/warehouse/inventory?returnTo=%23%2Forders"]) {
      assert.throws(() => router.href(name, { id: 14 }, { returnTo: target }));
    }
  }
  assert.equal(router.parse("#/orders?returnTo=%23%2Forders").error != null, true);
});

test("deep link is remembered through Login; outside/malformed return URLs are rejected", async () => {
  const e = environment("#/orders/14?page=2", null); e.start(); await tick();
  assert.equal(e.window.location.hash, "#/login"); assert.equal(e.storage.get("tvd.returnRoute"), "#/orders/14?page=2");
  e.setUser(admin); e.router.completeLogin(); await tick();
  assert.equal(e.window.location.hash, "#/orders/14?page=2"); assert.equal(e.rendered.at(-1).name, "order-detail");
  for (const outside of ["https://evil.example", "//evil.example", "#/\\evil.example", "#/%2f%2fevil.example", "javascript:alert(1)", "#/orders?returnUrl=https://evil.example"]) {
    if (!outside.startsWith("#/orders")) assert.throws(() => e.router.navigate(outside));
    e.storage.set("tvd.returnRoute", outside); e.router.completeLogin(); await tick(); assert.equal(e.window.location.hash, "#/dashboard");
  }
  e.router.stop();
});

test("normal navigation and Back/Forward render once; query updates preserve the current view", async () => {
  const e = environment("#/orders?page=2&status=NEW"); e.start(); await tick();
  assert.equal(e.rendered.length, 1); assert.equal(e.counts().permissionCalls, 1);
  e.router.updateQuery({ page: 3, status: "NEW", keyword: "test" }); await tick(); assert.equal(e.rendered.length, 1);
  e.router.navigate(e.router.href("order-detail", { id: 14 })); await tick(); assert.equal(e.rendered.length, 2);
  e.window.history.back(); await tick(); assert.equal(e.rendered.length, 3); assert.equal(e.rendered.at(-1).route.query.page, 3);
  e.window.history.forward(); await tick(); assert.equal(e.rendered.length, 4); assert.equal(e.rendered.at(-1).route.params.id, 14);
  e.router.navigate(e.window.location.hash); await tick(); assert.equal(e.rendered.length, 4);
  const reload = environment(e.window.location.hash); reload.start(); await tick(); assert.equal(reload.rendered[0].route.params.id, 14);
  e.router.stop(); reload.router.stop(); assert.equal(e.counts().listeners, 0);
});

test("restricted role or missing live permission shows Forbidden while keeping the session", async () => {
  const role = environment("#/admin/roles", { role: "DISPATCHER", accountId: 2 }); role.start(); await tick();
  assert.equal(role.errors[0].title, "Không có quyền"); assert.equal(role.window.location.hash, "#/admin/roles"); assert.equal(role.counts().permissionCalls, 0);
  const permission = environment("#/orders/create", admin, async () => ({ known: true, codes: new Set(["DONHANG_XEM"]) })); permission.start(); await tick();
  assert.equal(permission.errors[0].title, "Không có quyền"); assert.equal(permission.window.location.hash, "#/orders/create");
  const unavailable = environment("#/orders", admin, async () => { throw new Error("Network unavailable"); }); unavailable.start(); await tick();
  assert.equal(unavailable.errors[0].title, "Chưa thể mở trang"); assert.equal(unavailable.window.location.hash, "#/orders");
  role.router.stop(); permission.router.stop(); unavailable.router.stop();
});

test("leaving a pending route aborts its work and a late result cannot render over the destination", async () => {
  let finish; const wait = new Promise(resolve => { finish = resolve; });
  const e = environment("#/orders", admin, async () => { await wait; return { known: true, codes: new Set(["DONHANG_XEM"]) }; });
  e.start(); e.router.navigate("#/dashboard"); await tick(); assert.equal(e.signals[0].aborted, true);
  finish(); await tick(); assert.equal(e.rendered.length, 1); assert.equal(e.rendered[0].name, "overview"); e.router.stop();
});

test("unknown routes show Not Found and logout cannot reopen protected pages via Back", async () => {
  const unknown = environment("#/does-not-exist", null); unknown.start(); await tick(); assert.equal(unknown.errors[0].title, "Không tìm thấy"); unknown.router.stop();
  const e = environment("#/dashboard"); e.start(); await tick(); e.router.navigate("#/orders"); await tick();
  e.setUser(null); e.router.goLogin(false); await tick(); assert.equal(e.window.location.hash, "#/login"); assert.equal(e.storage.has("tvd.returnRoute"), false);
  e.window.history.back(); await tick(); assert.equal(e.window.location.hash, "#/login"); assert.equal(e.rendered.at(-1).name, "login"); e.router.stop();
});

test("customer filters, detail reload and return links preserve server-side list state", async () => {
  const {router}=environment();
  const query={page:2,pageSize:20,keyword:'KH-',type:'BUSINESS',status:'INACTIVE'};
  for(const name of ['customers','customer-detail']) {
    const route=router.parse(router.href(name,{id:7},query)); assert.equal(route.error,null);
    assert.deepEqual(JSON.parse(JSON.stringify(route.query)),query);
  }
  for(const q of ['status=NEW','type=INVALID','page=0','pageSize=101','type=BUSINESS&type=INDIVIDUAL']) assert.ok(router.parse('#/customers?'+q).error);
  const detail=router.href('customer-detail',{id:7},query);
  assert.equal(router.parse(router.href('order-detail',{id:14},{returnTo:detail})).query.returnTo,detail);
  const e=environment(detail);e.start();await tick(); assert.equal(e.rendered[0].name,'customer-detail');e.router.stop();
});

test("customer routes require live read grants and support dispatcher customer workflow", async () => {
  const e=environment('#/customers',{accountId:5,role:'DISPATCHER'},async()=>({known:true,codes:new Set(['DONHANG_XEM'])}));
  e.start();await tick();assert.equal(e.rendered[0].name,'customers');e.router.stop();
  const denied=environment('#/customers',admin,async()=>({known:true,codes:new Set(['DONHANG_TAO'])}));
  denied.start();await tick();assert.equal(denied.errors[0].title,'Không có quyền');denied.router.stop();
});

test("courier list/detail validate backend filters and preserve them across reload", async () => {
 const {router}=environment();const query={page:2,pageSize:20,keyword:'NV-',branchId:1,isActive:'false',availability:'OFFLINE'};
 for(const name of ['couriers','shipper-detail']){const route=router.parse(router.href(name,{id:5},query));assert.equal(route.error,null);assert.deepEqual(JSON.parse(JSON.stringify(route.query)),query);}
 assert.equal(router.parse('#/fleet/couriers?keyword='+'x'.repeat(150)).error,null);
 for(const q of ['keyword='+'x'.repeat(151),'branchId=0','branchId=2147483648','isActive=INACTIVE','availability=ACTIVE','page=0','pageSize=101','branchId=1&branchId=2'])assert.ok(router.parse('#/fleet/couriers?'+q).error);
 const e=environment(router.href('shipper-detail',{id:5},query),admin,async()=>({known:true,codes:new Set(['TAIKHOAN_XEM'])}));e.start();await tick();assert.equal(e.rendered[0].name,'shipper-detail');e.router.stop();
});
test("courier route requires actual account read permission even for ADMIN", async()=>{
 const e=environment('#/fleet/couriers',admin,async()=>({known:true,codes:new Set(['TAIKHOAN_QUANLY'])}));e.start();await tick();assert.equal(e.errors[0].title,'Không có quyền');e.router.stop();
});

test("vehicle list/detail preserve actual filters and reject invented states",async()=>{
 const {router}=environment();const query={page:2,pageSize:20,keyword:'59A',vehicleType:'VAN',branchId:1,status:'MAINTENANCE'};
 for(const name of ['vehicles','vehicle-detail']){const route=router.parse(router.href(name,{id:3},query));assert.equal(route.error,null);assert.deepEqual(JSON.parse(JSON.stringify(route.query)),query);}
 for(const q of ['status=ACTIVE','vehicleType='+'x'.repeat(31),'branchId=0','status=AVAILABLE&status=INACTIVE','page=0'])assert.ok(router.parse('#/fleet/vehicles?'+q).error);
 const e=environment(router.href('vehicle-detail',{id:3},query),admin,async()=>({known:true,codes:new Set(['DIEUPHOI_GIAMSAT'])}));e.start();await tick();assert.equal(e.rendered[0].name,'vehicle-detail');e.router.stop();
});
test("vehicle route requires live surveillance permission even for ADMIN",async()=>{
 const e=environment('#/fleet/vehicles',admin,async()=>({known:true,codes:new Set(['TAIKHOAN_QUANLY'])}));e.start();await tick();assert.equal(e.errors[0].title,'Không có quyền');e.router.stop();
});

test("Tracking route preserves filters/selection and requires both live permissions",()=>{
 const {router}=environment(),query={keyword:"LM0001",branchId:2,shipperId:3,statusGroup:"ATTENTION",fromDate:"2026-10-01",toDate:"2026-10-17",page:2,pageSize:10,orderId:8,view:"history",auto:"false"};
 const hash=router.href("tracking",{},query),route=router.parse(hash);assert.equal(route.error,null);assert.deepEqual(JSON.parse(JSON.stringify(route.query)),query);
 assert(!router.allowed(route,admin,{known:true,codes:new Set(["DONHANG_XEM"])}));
 assert(router.allowed(route,{role:"DISPATCHER"},{known:true,codes:new Set(["DONHANG_XEM","DIEUPHOI_GIAMSAT"])}));
 assert.equal(router.parse(router.href("order-detail",{id:8},{returnTo:hash})).query.returnTo,hash);
 for(const q of ["view=live","auto=yes","statusGroup=UNKNOWN","shipperId=0","orderId=-1","fromDate=2026-10-18&toDate=2026-10-17"])assert(router.parse("#/tracking?"+q).error);
});

test("Dispatch routes require live per-screen grants and retain selection/filters/plan URLs",()=>{
 const {router}=environment(),grants={"dispatch-queue":["DIEUPHOI_GOMDON"],assignments:["DIEUPHOI_GIAMSAT"],"delivery-trips":["DIEUPHOI_GIAMSAT"],"route-optimization":["DIEUPHOI_GOMDON","DIEUPHOI_TOIUUTUYEN"]};
 for(const [name,codes]of Object.entries(grants)){
  const route=router.parse(router.href(name,{}, {warehouseId:2,branchId:1,page:2,pageSize:10,priority:1,deadlineDate:"2026-10-17"}));assert.equal(route.error,null);assert.equal(route.group,"dispatch");
  assert(!router.allowed(route,admin,{known:true,codes:new Set()}));assert(router.allowed(route,{role:"BRANCH_MANAGER"},{known:true,codes:new Set(codes)}));
 }
 const query={planId:"12345678-1234-1234-1234-123456789abc",tripId:8,step:3},route=router.parse(router.href("route-optimization",{},query));assert.equal(route.error,null);assert.deepEqual(JSON.parse(JSON.stringify(route.query)),query);
 const back=router.href("dispatch-queue",{},{warehouseId:1});assert.equal(router.parse(router.href("order-detail",{id:1},{returnTo:back})).query.returnTo,back);
});

test("Dispatch URL validation distinguishes trip/assignment statuses and rejects invalid planning state",()=>{
 const {router}=environment();for(const q of ["step=4","planId=wrong","priority=0","tripId=0","deadlineDate=2026-02-30"])assert(router.parse("#/dispatch/optimization?"+q).error);
 assert.equal(router.parse("#/dispatch/assignments?status=ATTEMPT_FAILED").error,null);assert(router.parse("#/dispatch/trips?status=ATTEMPT_FAILED").error);assert.equal(router.parse("#/dispatch/trips?status=PLANNED&fromDate=2026-10-01&toDate=2026-10-17").error,null);
});

test("Dashboard scopes, operational cards and task return links preserve exact filters",()=>{
 const {router}=environment();const home=router.href("overview",{},{branchId:2});assert.equal(router.parse(home).query.branchId,2);
 for(const group of ["waitingInbound","inWarehouse","waitingAssignment","waitingHandover","inDelivery","failedNeedsAction","overdue"]){const route=router.parse(router.href("orders",{},{branchId:2,operationalGroup:group,page:1}));assert.equal(route.error,null);assert.equal(route.query.operationalGroup,group);assert.equal(route.query.branchId,2);}
 const detail=router.parse(router.href("order-detail",{id:7},{returnTo:home}));assert.equal(detail.error,null);assert.equal(detail.query.returnTo,home);
 assert(router.parse("#/orders?operationalGroup=arbitrary").error);assert(router.parse("#/dashboard?branchId=0").error);
});
