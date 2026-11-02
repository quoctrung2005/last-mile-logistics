"use strict";
const { test } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const source = fs.readFileSync(path.join(__dirname, "../js/dispatch.js"), "utf8");
const message = "Thông tin đã thay đổi. Vui lòng tính lại đề xuất.";
const clone = value => JSON.parse(JSON.stringify(value));

// Minimal DOM for running the real wizard, controls and event handlers without
// browser packages or a database. HTTP/timeout behavior has separate API tests.
class Element {
  constructor(tag, cls = "", text = "") {
    this.tag = tag; this.className = cls; this.text = text; this.children = [];
    this.events = {}; this.attributes = {}; this.value = ""; this.style = {};
    this.dataset = {}; this.disabled = false; this.isConnected = true;
  }
  get textContent() { return this.text + this.children.map(n => n.textContent).join(""); }
  set textContent(value) { this.text = value; this.children = []; }
  append(...nodes) { for (const n of nodes) { n.parent = this; this.children.push(n); } }
  replaceChildren(...nodes) { this.text = ""; this.children = []; this.append(...nodes); }
  setAttribute(name, value) { this.attributes[name] = value; }
  addEventListener(type, callback) { (this.events[type] ||= []).push(callback); }
  async emit(type) {
    const event = { preventDefault() {} };
    for (let n = this; n; n = n.parent) for (const callback of n.events[type] || []) await callback(event);
  }
  querySelectorAll(selector) {
    const matches = node => selector.startsWith(".") ? node.className.split(" ").includes(selector.slice(1))
      : selector.startsWith("[name") ? node.name === selector.match(/name=["']?([^\]"']+)/)[1] && (!selector.includes(":checked") || node.checked && !node.disabled)
      : node.tag === selector;
    const found = [];
    const visit = n => { for (const child of n.children) { if (matches(child)) found.push(child); visit(child); } };
    visit(this); return found;
  }
  querySelector(selector) { return this.querySelectorAll(selector)[0] || null; }
  get elements() { return Object.fromEntries(this.querySelectorAll("input").filter(n => n.name).map(n => [n.name, n])); }
  reportValidity() { return true; }
}

function environment() {
  const storage = new Map(), writes = [], failures = [];
  const el = (...args) => new Element(...args);
  const U = {
    el, button(label, callback, cls) { const n = el("button", cls, label); n.click = callback; return n; },
    field(host, fields, key, label, value, config) {
      const n = el("input"); n.name = key; n.value = String(value ?? ""); n.type = config.type;
      fields[key] = { control: n }; host.append(n);
    },
    notice(box, text) { box.textContent = text; },
    failure(_s, box, error) { failures.push(error); box.textContent = error.message; }
  };
  const window = {
    AdminUI: U, LogisticsUI: { table: () => el("table"), el, button:U.button }, TrackingPage: { date: String },
    Router: { updateQuery() {}, current() { return null; }, href: () => "#/trips/1" },
    ApiClient: { async request(url, settings) {
      const body = JSON.parse(settings.body); writes.push({ url, body });
      if (env.respond) return env.respond(url, body);
      return url.endsWith("/confirm") ? { message: "Đã xác nhận", trips: [] } : proposal("plan-" + writes.length);
    } }
  };
  const context = vm.createContext({
    window, AbortController, AbortSignal, URLSearchParams, sessionStorage: {
      getItem: key => storage.get(key) ?? null, setItem: (key, value) => storage.set(key, value)
    }, document: { createTextNode: text => el("text", "", text) },
    cancelAnimationFrame() {}, requestAnimationFrame() { return 1; }
  });
  vm.runInContext(fs.readFileSync(path.join(__dirname,"../js/write-outcome.js"),"utf8"),context);
  vm.runInContext(source.replace("Object.freeze({mount,destroy})", "Object.freeze({mount,destroy,wizard,calculatePlan,confirmPlan,persist,restoreProposal,planningKey,editRoute,selectionBar,isOverdue})"), context);
  const env = { page: window.DispatchPage, storage, writes, failures, el };
  env.state = () => ({
    abort: new AbortController(), query: {}, route: {}, page: "route-optimization", depotSequence: 0,
    draft: { warehouseId: 1, shipperIds: [3], departure: "2030-01-01T09:00", serviceMinutes: 5, returnToDepot: true },
    selected: new Map([[1, { id: 1, warehouseId: 1 }], [2, { id: 2, warehouseId: 1 }]]),
    options: { warehouses: [{ id: 1, branchId: 1, name: "Kho 1" }], shippers: [3, 4].map(id => ({ id, branchId: 1, vehicleId: id, name: "Shipper " + id })), routing: { available: true } },
    content: el("div"), feedback: el("div"), can: () => true, alive: () => true, guard() {},
    read: async () => ({ id: 1, branchId: 1, latitude: 10, longitude: 106 })
  });
  return env;
}

function proposal(id = "plan-original") {
  return { id, warehouseId: 1, warehouseName: "Kho 1", departureAt: "2030-01-01T02:00:00+00:00", serviceMinutes: 5, returnToDepot: true,
    expiresAt: "2099-01-01T00:00:00Z", warnings: [], unplanned: [],
    routes: [{ shipperId: 3, shipperName: "Shipper 3", distanceKm: 2, stops: [1, 2].map(orderId => ({ orderId, serviceStartAt: "2030-01-01T02:05:00Z", waitingMinutes: 0 })) }] };
}
async function calculate(b, s) { await b.page.calculatePlan(s, b.el("button")); assert.equal(b.failures.length, 0); }
const confirms = b => b.writes.filter(r => r.url.endsWith("/confirm"));

for (const field of ["shipper", "departure", "serviceMinutes", "returnToDepot"]) {
  test(`calculate -> edit ${field} -> directly open step 3 blocks old ID; recalculation enables confirmation`, async () => {
    const b = environment(), s = b.state();
    await calculate(b, s);
    assert.equal(s.confirmButton.disabled, false);
    const oldId = s.proposal.id;
    await b.page.wizard(s, 2);
    const form = s.content.querySelector(".dispatch-planning-form");
    if (field === "shipper") {
      const drivers = form.querySelectorAll("[name=shipper]"); drivers[0].checked = false; drivers[1].checked = true;
      await drivers[1].emit("change");
    } else {
      const n = form.elements[field];
      if (field === "departure") n.value = "2030-01-01T10:00";
      if (field === "serviceMinutes") n.value = "8";
      if (field === "returnToDepot") n.checked = false;
      await n.emit("input");
    }
    const step3 = s.content.querySelectorAll("button").find(n => n.textContent === "3. Xem đề xuất");
    await step3.click();
    assert.equal(s.confirmButton.disabled, true);
    assert.equal(s.feedback.textContent, message);
    // Even a stale/programmatically re-enabled button cannot bypass the handler.
    s.confirmButton.disabled = false;
    await b.page.confirmPlan(s, s.confirmButton);
    assert.equal(confirms(b).length, 0);
    await calculate(b, s);
    assert.notEqual(s.proposal.id, oldId);
    assert.equal(s.confirmButton.disabled, false);
    await s.confirmButton.click();
    assert.equal(confirms(b).length, 1);
    assert.equal(confirms(b)[0].url, "/api/v1/dispatch/plans/" + s.proposal.id + "/confirm");
  });
}

for (const [label, change] of [
  ["selected orders", s => s.selected.delete(2)],
  ["warehouse", s => { s.draft.warehouseId = 2; }],
  ["trip", s => { s.query.tripId = 7; }],
  ["invalid departure", s => { s.draft.departure = ""; }]
]) {
  test(`confirmation rechecks ${label}, even without a form change event`, async () => {
    const b = environment(), s = b.state(); await calculate(b, s);
    change(s);
    await b.page.confirmPlan(s, s.confirmButton);
    assert.equal(confirms(b).length, 0);
    assert.equal(s.confirmButton.disabled, true);
    assert.equal(s.feedback.textContent, message);
  });
}

test("step navigation captures edits even if no change event fired", async () => {
  const b = environment(), s = b.state(); await calculate(b, s);
  await b.page.wizard(s, 2);
  s.content.querySelector(".dispatch-planning-form").elements.departure.value = "2030-01-01T11:00";
  await b.page.wizard(s, 3);
  assert.equal(s.confirmButton.disabled, true);
});

test("a changed input stays invalid even when changed back to its original value", async () => {
  const b = environment(), s = b.state(); await calculate(b, s);
  s.draft.shipperIds = [4]; b.page.persist(s);
  s.draft.shipperIds = [3]; b.page.persist(s);
  await b.page.confirmPlan(s, s.confirmButton);
  assert.equal(confirms(b).length, 0);
});

test("an obsolete response cannot replace the proposal, including input changes then undo during calculation", async () => {
  for (const undo of [false, true]) {
    const b = environment(), s = b.state(); await calculate(b, s);
    const original = s.proposal;
    let complete;
    b.respond = () => new Promise(resolve => { complete = resolve; });
    const pending = b.page.calculatePlan(s, b.el("button"));
    s.draft.departure = "2030-01-01T10:00"; b.page.persist(s);
    if (undo) { s.draft.departure = "2030-01-01T09:00"; b.page.persist(s); }
    complete(proposal("late-plan")); await pending;
    assert.equal(s.proposal, original);
    assert.equal(s.proposalBinding, null);
    assert.equal(s.feedback.textContent, message);
    await b.page.confirmPlan(s, s.confirmButton);
    assert.equal(confirms(b).length, 0);
  }
});

test("failed recalculation cannot revive an older proposal, including after restoring storage", async () => {
  const b = environment(), s = b.state(); await calculate(b, s);
  b.respond = async () => { throw Error("Calculation failed"); };
  await b.page.calculatePlan(s, b.el("button"));
  const loaded = b.state(); loaded.draft = JSON.parse(b.storage.get("tvd.dispatch.selection"));
  b.page.restoreProposal(loaded, s.proposal);
  await b.page.confirmPlan(loaded, b.el("button"));
  assert.equal(loaded.proposalBinding, null);
  assert.equal(confirms(b).length, 0);
});

test("restored binding preserves a matching full shipper set, including an unused shipper", async () => {
  const b = environment(), s = b.state(); s.draft.shipperIds = [3, 4]; await calculate(b, s);
  const loaded = b.state(); loaded.draft = JSON.parse(b.storage.get("tvd.dispatch.selection"));
  b.page.restoreProposal(loaded, clone(s.proposal));
  await b.page.wizard(loaded, 3);
  assert.equal(loaded.confirmButton.disabled, false);
  await loaded.confirmButton.click();
  assert.equal(confirms(b).length, 1);
});

test("legacy/bookmarked plans without an input binding require recalculation", async () => {
  const b = environment(), s = b.state();
  b.page.restoreProposal(s, proposal());
  await b.page.wizard(s, 3);
  assert.equal(s.confirmButton.disabled, true);
  await b.page.confirmPlan(s, b.el("button"));
  assert.equal(confirms(b).length, 0);
  await calculate(b, s); await s.confirmButton.click();
  assert.equal(confirms(b).length, 1);
});

for (const [label, change] of [
  ["different draft shipper", s => { s.draft.shipperIds = [4]; }],
  ["different draft departure", s => { s.draft.departure = "2030-01-01T10:00"; }],
  ["orders removed by hydration", s => s.selected.delete(2)],
  ["different backend result", (_s, p) => { p.serviceMinutes = 9; }],
  ["different plan ID", (_s, p) => { p.id = "another-plan"; }]
]) {
  test(`restoring ${label} never authorizes the old ID`, async () => {
    const b = environment(), s = b.state(); await calculate(b, s);
    const loaded = b.state(), p = clone(s.proposal);
    loaded.draft = JSON.parse(b.storage.get("tvd.dispatch.selection")); change(loaded, p);
    b.page.restoreProposal(loaded, p);
    await b.page.confirmPlan(loaded, b.el("button"));
    assert.equal(confirms(b).length, 0);
  });
}

test("manual route edits invalidate the binding and are checked again before confirmation", async () => {
  const b = environment(), s = b.state(); await calculate(b, s);
  b.page.editRoute(s, 3, 2, -1);
  assert.equal(s.confirmButton.disabled, true);
  await b.page.confirmPlan(s, b.el("button")); assert.equal(confirms(b).length, 0);
  await b.page.calculatePlan(s, b.el("button"), true);
  assert.deepEqual(b.writes.at(-1).body.manualRoutes, [{ shipperId: 3, orderIds: [2, 1] }]);
  assert.equal(s.confirmButton.disabled, false);
  await s.confirmButton.click(); assert.equal(confirms(b).length, 1);
});

for(const operation of ["calculate","confirm"]){
  test(`unknown ${operation} outcome blocks a second plan write even if the button is re-enabled`,async()=>{
    const b=environment(),s=b.state();await calculate(b,s);
    b.respond=async()=>{throw Object.assign(Error("Lost response"),{resultUnknown:true});};
    if(operation==="calculate")await b.page.calculatePlan(s,b.el("button"));
    else await b.page.confirmPlan(s,s.confirmButton);
    const count=b.writes.length;
    s.confirmButton.disabled=false;
    await b.page.confirmPlan(s,s.confirmButton);await b.page.calculatePlan(s,b.el("button"));
    assert.equal(b.writes.length,count);assert.equal(s.writeUnknown,true);
  });
}

test('New route cannot calculate with all shippers busy, including after depot loads', async () => {
  const b=environment(),s=b.state();
  s.options.shippers.forEach(n=>n.eligibilityReason='Đang có nhiệm vụ');
  await b.page.wizard(s,2);await Promise.resolve();await Promise.resolve();
  const calculate=s.content.querySelectorAll('button').find(n=>n.textContent==='Tính đề xuất');
  assert.equal(calculate.disabled,true);assert.equal(b.writes.length,0);
});
test('New route requires a selected available driver, valid departure and service minutes', async () => {
  const b=environment(),s=b.state();s.draft.shipperIds=[];
  await b.page.wizard(s,2);await Promise.resolve();await Promise.resolve();
  const form=s.content.querySelector('.dispatch-planning-form');
  const calculate=form.querySelectorAll('button').find(n=>n.textContent==='Tính đề xuất');
  assert.equal(calculate.disabled,true);
  const driver=form.querySelectorAll('[name=shipper]')[0];driver.checked=true;await driver.emit('change');
  assert.equal(calculate.disabled,false);
  form.elements.serviceMinutes.value='2.5';await form.elements.serviceMinutes.emit('input');
  assert.equal(calculate.disabled,true);
  form.elements.serviceMinutes.value='5';await form.elements.serviceMinutes.emit('input');
  assert.equal(calculate.disabled,false);
  form.elements.departure.value='2000-01-01T09:00';await form.elements.departure.emit('input');
  assert.equal(calculate.disabled,true);
});
test('Missing depot cannot be bypassed by selecting a valid driver', async () => {
  const b=environment(),s=b.state();s.read=async()=>({id:1,branchId:1,latitude:null,longitude:null});
  await b.page.wizard(s,2);await Promise.resolve();await Promise.resolve();
  s.updateCalculate();
  assert.equal(s.content.querySelectorAll('button').find(n=>n.textContent==='Tính đề xuất').disabled,true);
});
test('Mixed warehouse selections cannot open optimization or create a manual trip', () => {
  const b=environment(),s=b.state();s.page='dispatch-queue';
  s.selected.set(2,{id:2,warehouseId:2});
  const bar=b.page.selectionBar(s),buttons=bar.querySelectorAll('button');
  assert.equal(buttons.find(n=>n.textContent==='Lập phương án giao').disabled,true);
  assert.equal(buttons.find(n=>n.textContent==='Tạo chuyến thủ công').disabled,true);
  s.selected.delete(2);s.selectionUpdate();
  assert.equal(buttons.find(n=>n.textContent==='Lập phương án giao').disabled,false);
});
test('Overdue detection treats offsetless SQL timestamps as UTC and preserves missing deadlines',()=>{
 const b=environment(),past=new Date(Date.now()-60000).toISOString(),future=new Date(Date.now()+60000).toISOString();
 assert.equal(b.page.isOverdue({expectedDeliveryAt:past}),true);
 assert.equal(b.page.isOverdue({expectedDeliveryAt:past.replace('Z','')}),true);
 assert.equal(b.page.isOverdue({expectedDeliveryAt:future}),false);
 assert.equal(b.page.isOverdue({expectedDeliveryAt:null}),false);
});