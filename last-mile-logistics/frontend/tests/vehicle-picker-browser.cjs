"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs"), path = require("node:path");
const ready = "document.querySelector('dialog .vehicle-choice-results[aria-busy=false]')&&document.querySelector('dialog .vehicle-choice-pagination span')";
async function choose({ change, click, until, evaluate, vehicle }) {
  await until(ready);
  await change("Biển số hoặc mã phương tiện", vehicle.licensePlate);
  await click("Tìm kiếm", "dialog .vehicle-choice button");
  await until(`document.querySelector('[data-choose-vehicle="${vehicle.id}"]')&&document.querySelector('.vehicle-choice-results[aria-busy=false]')`);
  await evaluate(`document.querySelector('[data-choose-vehicle="${vehicle.id}"]').click()`);
}
module.exports = async context => {
  const { api, admin, manager, created, accountB, change, click, until, evaluate, check, checks, send, navigate, root } = context;
  const start = checks.length;
  const busy = (await api("/api/v1/shippers?pageSize=100", admin)).items.find(s => s.activeAssignmentCount > 0);
  assert(busy);
  const selectionUrl = shipper => "/api/v1/vehicles?assignableOnly=true&includeUnavailable=true&forShipperId=" + shipper.id + "&branchId=" + shipper.branchId;
  const unavailable = await api(selectionUrl(busy) + "&pageSize=100", admin);
  assert(unavailable.scopedTotalItems > 0); assert.equal(unavailable.eligibleTotalItems, 0);
  assert(unavailable.items.every(v => !v.canSelect && v.unavailableReason));
  assert(unavailable.items.every(v => v.currentShipperBranchId == null || v.currentShipperBranchId === busy.branchId));
  const own = unavailable.items.find(v => v.currentShipperId === busy.id);
  assert(own?.isCurrentVehicle); assert(own.unavailableReason.includes("chính shipper"));
  await api(selectionUrl(busy).replace("branchId=" + busy.branchId, "branchId=999999"), admin, "GET", undefined, 409);
  await api("/api/v1/vehicles?includeUnavailable=true", admin, "GET", undefined, 400);
  await navigate("#/fleet/couriers/" + busy.id); await until("document.querySelector('.shippers-page .order-summary')");
  await click("Quản lý phương tiện"); await until(ready);
  await check("Real busy shipper lists unavailable vehicles and explains why none can be assigned",
    "document.querySelectorAll('.vehicle-choice-row').length>0&&document.querySelector('.vehicle-choice-feedback').textContent.includes('Có phương tiện nhưng không có xe đủ điều kiện')&&[...document.querySelectorAll('[data-choose-vehicle]')].every(b=>b.disabled&&b.title)");
  await check("The shipper's own current vehicle is visible but cannot be selected",
    `document.querySelector('[data-choose-vehicle="${own.id}"]').disabled&&document.querySelector('[data-choose-vehicle="${own.id}"]').title.includes('chính shipper')`);
  checks.push("Real SQL scope excludes assigned vehicles from other branches and rejects a stale branch context");
  await click("Đóng", "dialog button");
  await navigate("#/fleet/couriers/" + created.id); await until("document.querySelector('.shippers-page .order-summary')");
  const { items: types } = await api("/api/v1/vehicles/types", admin);
  const pool = [];
  for (let i = 0; i < 12; i++) pool.push(await api("/api/v1/vehicles", admin, "POST", {
    licensePlate: "QA-PICK-" + String(i).padStart(2, "0"), vehicleType: types[i % types.length].code,
    useTypeCapacity: true, status: "AVAILABLE", isActive: true
  }, 201));
  const base = "/api/v1/vehicles?assignableOnly=true&forShipperId=" + created.id;
  const all = await api(base + "&pageSize=100", admin);
  assert.equal(all.totalItems, all.eligibleTotalItems); assert(all.totalItems > 10);
  assert.equal(all.selectionBranchId, created.branchId); assert.equal(all.selectionShipperId, created.id);
  await api(base, manager, "GET", undefined, 403);
  await api("/api/v1/vehicles?assignableOnly=true&forShipperId=99999999", admin, "GET", undefined, 404);
  await api("/api/v1/vehicles?forShipperId=" + created.id, admin, "GET", undefined, 400);
  checks.push("Assignment lookup validates target shipper, branch context and live management grants");
  const p1 = await api(base, admin), p2 = await api(base + "&page=2", admin);
  assert.equal(p1.totalItems, p2.totalItems); assert(!p1.items.some(a => p2.items.some(b => b.id === a.id)));
  for (const type of types) {
    const data = await api(base + "&vehicleType=" + type.code, admin);
    assert(data.items.length > 0); assert(data.items.every(v => v.vehicleType === type.code)); assert.equal(data.eligibleTotalItems, all.totalItems);
  }
  checks.push("Each catalog type filters on the server before pagination; eligible count remains unfiltered");
  for (const value of [pool[0].code, pool[0].licensePlate]) {
    const data = await api(base + "&keyword=" + encodeURIComponent(value), admin); assert(data.items.some(v => v.id === pool[0].id));
  }
  const unmatched = await api(base + "&keyword=Motobike", admin); assert.equal(unmatched.totalItems, 0); assert(unmatched.eligibleTotalItems > 0);
  checks.push("API searches code/plate and distinguishes an unmatched keyword from an empty eligible pool");

  await click("Quản lý phương tiện"); await until(ready);
  await check("Opening picker automatically loads page 1 with an empty keyword",
    "document.querySelector('.vehicle-choice input[name=vehicleKeyword]').value===''&&document.querySelector('.vehicle-choice select[name=vehicleType]').value===''&&document.querySelectorAll('.vehicle-choice-row').length===10");
  await check("Automatic request carries the target shipper's actual branch and unavailable-row contract",
    `qa.requests.some(r=>r.url.includes('forShipperId=${created.id}')&&r.url.includes('branchId=${created.branchId}')&&r.url.includes('includeUnavailable=true'))&&document.querySelectorAll('.vehicle-choice-row dt').length===60`);
  await check("Vietnamese catalog labels and explicit plate/code search are displayed",
    "document.querySelector('.vehicle-choice input[name=vehicleKeyword]').placeholder==='Nhập biển số hoặc mã phương tiện'&&[...document.querySelector('.vehicle-choice select').options].some(o=>o.textContent==='Xe máy')&&!document.querySelector('dialog select[name=vehicleId]')");
  for (const type of types) {
    await change("Loại phương tiện", type.code); await until(ready);
    await check("Picker filters " + type.name,
      `[...document.querySelectorAll('.vehicle-choice-row')].length>0&&[...document.querySelectorAll('.vehicle-choice-row')].every(row=>row.querySelectorAll('dd')[2].textContent===${JSON.stringify(type.name)})`);
  }
  await click("Xóa bộ lọc", "dialog .vehicle-choice button"); await until(ready);
  const first = await evaluate("document.querySelector('[data-choose-vehicle][data-selectable=true]').dataset.chooseVehicle");
  await evaluate("document.querySelector('[data-choose-vehicle][data-selectable=true]').click()");
  await click("Sau ›", "dialog .vehicle-choice button"); await until(ready);
  await check("Selected vehicle stays visible and selected across server pages",
    `document.querySelector('input[name=vehicleId]').value===${JSON.stringify(first)}&&!document.querySelector('.vehicle-choice-selected').hidden&&document.querySelector('.vehicle-choice-pagination').textContent.includes('Trang 2')`);
  await click("Xóa bộ lọc", "dialog .vehicle-choice button"); await until(ready);
  await check("Clearing filters resets page but preserves the chosen vehicle",
    `document.querySelector('input[name=vehicleId]').value===${JSON.stringify(first)}&&document.querySelector('.vehicle-choice-pagination').textContent.includes('Trang 1')`);
  await check("Selecting a free vehicle never enables an unavailable vehicle's button",
    "[...document.querySelectorAll('[data-selectable=false]')].length>0&&[...document.querySelectorAll('[data-selectable=false]')].every(b=>b.disabled&&b.title)");
  await click("Đổi lựa chọn", "dialog .vehicle-choice button");
  await check("Change choice clears the previous selection", "document.querySelector('input[name=vehicleId]').value===''&&document.querySelector('.vehicle-choice-selected').hidden");
  for (const term of [pool[0].code, pool[0].licensePlate]) {
    await change("Biển số hoặc mã phương tiện", term); await click("Tìm kiếm", "dialog .vehicle-choice button"); await until(ready);
    await check("Picker searches " + (term === pool[0].code ? "vehicle code" : "plate"), `!!document.querySelector('[data-choose-vehicle="${pool[0].id}"]')`);
  }
  await change("Biển số hoặc mã phương tiện", "Motobike"); await click("Tìm kiếm", "dialog .vehicle-choice button"); await until(ready);
  await check("Unmatched filters show guidance rather than an empty-pool message",
    "document.querySelector('.vehicle-choice-results').textContent.includes('Không có xe khớp bộ lọc')&&!document.querySelector('.vehicle-choice-results').textContent.includes('Không có xe đủ điều kiện')");

  // Only the zero-record presentation is controlled; never alter vehicle statuses.
  await evaluate(`qa.pickerFetch=window.fetch;window.fetch=async(...args)=>String(args[0]).includes('/api/v1/vehicles?')?new Response(JSON.stringify({page:1,pageSize:10,totalItems:0,scopedTotalItems:0,eligibleTotalItems:0,selectionShipperId:${created.id},selectionBranchId:${created.branchId},items:[]}),{status:200,headers:{'Content-Type':'application/json'}}):qa.pickerFetch(...args);`);
  try {
    await click("Xóa bộ lọc", "dialog .vehicle-choice button"); await until(ready);
    await check("Zero scoped vehicles has a separate state (controlled empty response)", "document.querySelector('.vehicle-choice-results').textContent.includes('Không có phương tiện trong bưu cục')&&!document.querySelector('.vehicle-choice-feedback').textContent.includes('Có phương tiện nhưng')");
  } finally { await evaluate("window.fetch=qa.pickerFetch;"); }
  await evaluate(`qa.pickerFetch=window.fetch;window.fetch=async(...args)=>String(args[0]).includes('/api/v1/vehicles?')?new Response(JSON.stringify({message:'Lỗi tải xe thử.'}),{status:500,headers:{'Content-Type':'application/json'}}):qa.pickerFetch(...args);`);
  try {
    await click("Xóa bộ lọc", "dialog .vehicle-choice button");
    await until("document.querySelector('.vehicle-choice-feedback').textContent.includes('Không tải được danh sách xe')");
    await check("Load failure is distinct and offers retry", "document.querySelector('.vehicle-choice-feedback button').textContent==='Thử lại'&&document.querySelectorAll('.vehicle-choice-row').length===0");
  } finally { await evaluate("window.fetch=qa.pickerFetch;"); }
  await click("Thử lại", "dialog .vehicle-choice button"); await until(ready);
  checks.push("Retry reloads the real eligible API after a controlled 500");

  await choose({ ...context, vehicle: pool[0] });
  await evaluate(`qa.pickerFetch=window.fetch;window.fetch=async(...args)=>String(args[0]).includes('/api/v1/vehicles?')?new Response(JSON.stringify({message:'Bưu cục của shipper đã thay đổi. Hãy mở lại form chọn xe.'}),{status:409,headers:{'Content-Type':'application/json'}}):qa.pickerFetch(...args);`);
  try {
    await click("Xóa bộ lọc", "dialog .vehicle-choice button");
    await until("document.querySelector('.vehicle-choice-feedback').textContent.includes('Bưu cục của shipper đã thay đổi')");
    await check("A stale branch response clears and blocks the previous choice (controlled 409)", "document.querySelector('input[name=vehicleId]').value===''&&document.querySelector('.vehicle-choice-selected').hidden&&!document.querySelector('.vehicle-choice-feedback button')");
  } finally { await evaluate("window.fetch=qa.pickerFetch;"); }
  await click("Đóng", "dialog button");
  await click("Quản lý phương tiện"); await until(ready);

  await choose({ ...context, vehicle: pool[0] });
  await change("Ghi chú *", "QA delayed list draft");
  await evaluate(`(()=>{
    qa.pickerFetch=window.fetch;qa.delayPickerList=true;
    window.fetch=async(...args)=>{
      const url=String(args[0]),method=args[1]?.method||'GET';
      if(method==='GET'&&url.includes('/api/v1/vehicles?')&&qa.delayPickerList){
        qa.delayPickerList=false;const response=await qa.pickerFetch(...args);
        await new Promise(resolve=>qa.releasePickerList=resolve);return response;
      }
      if(method==='PUT'&&url.endsWith('/vehicle')){
        await new Promise(resolve=>qa.releasePickerSave=resolve);
        return new Response(JSON.stringify({message:'Lỗi lưu thử, giữ nội dung.'}),{status:400,headers:{'Content-Type':'application/json'}});
      }
      return qa.pickerFetch(...args);
    };
  })()`);
  try {
    await click("Xóa bộ lọc", "dialog .vehicle-choice button"); await until("qa.releasePickerList");
    await click("Xác nhận", "dialog button"); await until("qa.releasePickerSave");
    await evaluate("qa.releasePickerList()"); await until("document.querySelector('.vehicle-choice-results[aria-busy=false]')");
    await evaluate("qa.releasePickerSave()"); await until(ready);
    await check("A list response arriving during save reloads after a 400, preserving choice and notes",
      `document.querySelector('input[name=vehicleId]').value==='${pool[0].id}'&&document.querySelectorAll('.vehicle-choice-row').length>0&&document.querySelector('textarea[name=notes]').value==='QA delayed list draft'`);
  } finally { await evaluate("window.fetch=qa.pickerFetch;"); }

  await choose({ ...context, vehicle: pool[1] });
  for (const width of [1440, 390]) {
    await send("Emulation.setDeviceMetricsOverride", { width, height: 1000, deviceScaleFactor: 1, mobile: width === 390 });
    const metrics = await evaluate(`(()=>{const d=document.querySelector('dialog');return {width:innerWidth,dialogWidth:d.getBoundingClientRect().width,bodyWidth:d.clientWidth,scrollWidth:d.scrollWidth,rowWidth:document.querySelector('.vehicle-choice-row').getBoundingClientRect().width}})()`);
    assert(metrics.dialogWidth <= width); assert(metrics.scrollWidth <= metrics.bodyWidth + 1);
    const picture = await send("Page.captureScreenshot", { format: "png" });
    fs.writeFileSync(path.join(root, "docs/vehicle-picker-" + width + ".png"), Buffer.from(picture.data, "base64"));
    checks.push("Picker fits " + width + "px without dialog horizontal overflow");
  }
  await send("Emulation.setDeviceMetricsOverride", { width: 1440, height: 1000, deviceScaleFactor: 1, mobile: false });

  // Another real shipper claims the selected car while this form remains open.
  const other = await api("/api/v1/shippers", admin, "POST", { accountId: accountB.id, licenseNumber: "QA-PICKER-LIC", licenseExpiresAt: "2099-12-31", areas: [] }, 201);
  await api("/api/v1/shippers/" + other.id + "/vehicle", admin, "PUT", { vehicleId: pool[1].id, expectedAssignmentId: null, notes: "Isolated concurrent assignment" });
  await change("Ghi chú *", "QA choice raced"); await click("Xác nhận", "dialog button");
  await until("document.querySelector('dialog .alert-danger')?.textContent.includes('HTTP 409')");
  await until(ready);
  await check("A vehicle claimed after selection is rejected by the save transaction; draft notes remain",
    "document.querySelector('input[name=vehicleId]').value===''&&document.querySelector('textarea[name=notes]').value==='QA choice raced'&&document.querySelector('dialog')");
  const afterRace = await api("/api/v1/shippers?id=" + created.id, admin); assert.equal(afterRace.currentVehicle, null);
  const holder = await api("/api/v1/shippers?id=" + other.id, admin);
  await api("/api/v1/shippers/" + other.id + "/vehicle", admin, "PUT", { vehicleId: null, expectedAssignmentId: holder.currentVehicle.assignmentId, notes: "Isolated cleanup assignment" });
  await click("Đóng", "dialog button");
  await navigate("#/fleet/couriers/" + other.id); await until("document.querySelector('.shippers-page .order-summary')&&!document.querySelector('#page-content [aria-busy=true]')");
  await click("Quản lý phương tiện"); await until(ready);
  await check("Opening a different shipper/branch starts a new selection scope",
    `document.querySelector('input[name=vehicleId]').value===''&&qa.requests.some(r=>r.url.includes('forShipperId=${other.id}'))`);
  await click("Đóng", "dialog button");
  await navigate("#/fleet/vehicles/" + pool[2].id);
  await until("document.querySelector('.vehicles-page .order-summary')");
  await click("Liên kết nhân viên");
  await until("document.querySelector('.vehicles-page dialog select')&&!document.querySelector('.vehicles-page dialog select').disabled");
  await evaluate(`(()=>{const select=document.querySelector('.vehicles-page dialog select');select.value='${created.id}';select.dispatchEvent(new Event('change',{bubbles:true}));})()`);
  await click("Tiếp tục", "dialog button"); await until(ready);
  await until(`document.querySelector('input[name=vehicleId]').value==='${pool[2].id}'`);
  await check("Vehicle-page entry verifies and preselects its vehicle while still loading an unfiltered list",
    `document.querySelector('.vehicles-page .vehicle-choice-selected').textContent.includes('${pool[2].licensePlate}')&&document.querySelector('input[name=vehicleKeyword]').value===''&&document.querySelectorAll('.vehicle-choice-row').length===10`);
  await click("Đóng", "dialog button");
  await navigate("#/fleet/couriers/" + created.id); await until("document.querySelector('.shippers-page .order-summary')&&!document.querySelector('#page-content [aria-busy=true]')");
  const report = { checks: checks.slice(start), count: checks.length - start, realSql: true, operationalWrites: false,
    controlledResponses: ["zero scoped vehicles", "one list 500", "stale branch list 409", "one delayed list with save 400"], scope: "Vehicles have no owning branch; assigned vehicles in target branch plus free ADMIN pool; branch and availability rechecked from database" };
  fs.writeFileSync(path.join(root, "docs/vehicle-picker-verification.json"), JSON.stringify(report, null, 2) + "\n");
};
module.exports.choose = choose;
