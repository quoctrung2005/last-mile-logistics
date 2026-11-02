"use strict";

(function () {
  const UI = window.LogisticsUI;
  const { el, button, input, select, field, notice, table, badge, summary, dialog, pagination, text, weight, date } = UI;
  let active = null;
  const positive = value => Number.isSafeInteger(value) && value > 0;
  const alive = s => active === s && !s.dead;
  const manage = s => s.user.role === "ADMIN" && s.permissions.known && s.permissions.codes.has("BUUCUC_QUANLY");
  function message(error) {
    if (error.sessionExpired) return "Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.";
    if (error.networkError || error.status >= 500) return "Không thể kết nối hoặc xử lý dữ liệu lúc này. Vui lòng thử lại.";
    return (error.message || "Không thể thực hiện thao tác.").replace(/\s*\(HTTP \d+\)/g, "");
  }
  async function request(s, url, signal, options = {}) {
    return window.ApiClient.request(url, { ...options, signal: AbortSignal.any([s.abort.signal, s.scopeAbort.signal, ...(signal ? [signal] : [])]) });
  }
  function validateRows(rows, warehouseId) {
    if (!Array.isArray(rows) || rows.some(row => !row || !positive(row.id) || row.warehouseId !== warehouseId || typeof row.code !== "string" || typeof row.isActive !== "boolean")
      || new Set(rows.map(row => row.id)).size !== rows.length) throw new Error("API vị trí chưa trả đầy đủ dữ liệu hoặc không khớp kho đã chọn.");
    return rows;
  }
  function destroy() {
    if (!active) return;
    const s = active; s.dead = true; s.abort.abort(); s.scopeAbort.abort(); s.listAbort?.abort();
    UI.closeDialogs(s); s.toolbar.remove(); active = null;
  }
  function update(s) {
    if (!alive(s)) return;
    s.add.hidden = !manage(s); s.add.disabled = !s.warehouse || s.pending || s.catalogBusy;
    s.refresh.disabled = s.pending || s.catalogBusy;
    s.filters.inert = s.pending;
    for (const node of s.body.querySelectorAll("[data-manage]")) { node.hidden = !manage(s); node.disabled = s.pending; }
    notice(s.permissionMessage, manage(s) ? "" : "Bạn có thể xem vị trí và hàng tồn; không có quyền quản lý danh mục vị trí.", "info");
  }
  function syncRoute(s) {
    if (alive(s)) window.Router.updateQuery({ ...(s.catalogMode ? {type:"LOCATIONS"} : {}), warehouseId: s.warehouse?.id, ...s.applied }, s.route);
  }
  function mount(container, user, route, context) {
    destroy();
    const s = { container, user, route, permissions: context.permissions, warehouse: null, warehouses: [], rows: [],
      epoch: 0, sequence: 0, pending: false, catalogBusy: false, dead: false, abort: new AbortController(), scopeAbort: new AbortController(), dialogs: new Set(), catalogMode:route.pageId === "catalogs", applied: { status: "ACTIVE" } };
    active = s;
    const card = el("section", "orders-card locations-card");
    s.toolbar = el("div", "order-actions locations-toolbar");
    s.add = button("Thêm vị trí", () => openEdit(s), "btn btn-orange");
    s.refresh = button("Làm mới", () => { if (s.warehouse) reload(s); else loadWarehouses(s); }, "btn btn-outline-orange");
    s.toolbar.append(s.add, s.refresh); document.querySelector(".page-heading").append(s.toolbar);
    s.warehouseSelect = select([], "Đang tải kho…"); s.warehouseSelect.required = false; s.warehouseSelect.disabled = true;
    s.keyword = input("search", "", { maxLength: 100, placeholder: "Mã vị trí, khu lưu, kệ hoặc ô" });
    s.status = select([{ id: "ACTIVE", name: "Đang hoạt động" }, { id: "INACTIVE", name: "Ngừng sử dụng" }, { id: "ALL", name: "Tất cả" }], "Chọn trạng thái", "ACTIVE");
    s.filters = el("form", "locations-filters");
    const apply = button("Lọc", null, "btn btn-orange"); apply.type = "submit";
    s.filters.append(field("Kho", s.warehouseSelect, "locations-filter"), field("Tìm kiếm", s.keyword, "locations-filter locations-search"), field("Trạng thái", s.status, "locations-filter"), apply);
    s.alert = el("div", "locations-message"); s.permissionMessage = el("div", "locations-message");
    s.body = el("div", "locations-list"); s.body.append(el("p", "orders-empty", "Chọn kho để xem vị trí lưu kho"));
    card.append(s.filters, s.alert, s.permissionMessage, s.body); container.replaceChildren(card);
    s.filters.addEventListener("submit", event => { event.preventDefault(); if (s.pending || !s.filters.reportValidity()) return; s.applied = { status: s.status.value, ...(s.keyword.value.trim() ? { keyword: s.keyword.value.trim() } : {}) }; reload(s); });
    s.warehouseSelect.addEventListener("change", () => chooseWarehouse(s, s.warehouseSelect.value));
    s.status.addEventListener("change", () => { s.applied = { status: s.status.value, ...(s.keyword.value.trim() ? { keyword: s.keyword.value.trim() } : {}) }; reload(s); });
    update(s); loadWarehouses(s, true);
  }
  async function loadWarehouses(s, restore = false) {
    if (!alive(s)) return;
    s.catalogBusy = true; update(s);
    try {
      const result = await request(s, s.catalogMode ? "/api/v1/catalogs?type=WAREHOUSES" : "/api/v1/warehouses");
      const rows = s.catalogMode ? result.warehouses : result;
      if (!alive(s)) return;
      if (!Array.isArray(rows) || rows.some(row => !positive(row.id) || !positive(row.branchId))) throw new Error("API danh sách kho trả dữ liệu không hợp lệ.");
      s.warehouses = rows; s.warehouseSelect.replaceChildren(); UI.option(s.warehouseSelect, "", "Chọn kho");
      for (const row of rows) UI.option(s.warehouseSelect, row.id, row.name + " · " + row.branchName);
      s.warehouseSelect.disabled = !rows.length; notice(s.alert, rows.length ? "" : "Không có kho hoạt động trong phạm vi tài khoản.", "info");
      const preferredId = restore ? s.route.query.warehouseId || window.WarehousePage.preferredWarehouse(s.user) : null;
      const preferred = rows.find(row => row.id === Number(preferredId));
      if (preferred) { s.warehouseSelect.value = preferred.id; await chooseWarehouse(s, preferred.id, restore); }
      else if (restore && s.route.query.warehouseId) notice(s.alert, "Kho trong URL không còn hoạt động hoặc không thuộc phạm vi được phép.");
    } catch (error) {
      if (!alive(s) || error.name === "AbortError") return;
      notice(s.alert, message(error)); s.alert.append(button("Thử lại", () => loadWarehouses(s, restore)));
    } finally { if (alive(s)) { s.catalogBusy = false; update(s); } }
  }
  async function chooseWarehouse(s, id, restore = false) {
    if (!alive(s) || s.pending) return;
    s.epoch++; s.sequence++; s.scopeAbort.abort(); s.scopeAbort = new AbortController(); s.listAbort?.abort(); UI.closeDialogs(s);
    s.rows = []; s.warehouse = s.warehouses.find(row => String(row.id) === String(id)) || null;
    s.keyword.value = restore ? s.route.query.keyword || "" : ""; s.status.value = restore ? s.route.query.status || (s.catalogMode ? "ALL" : "ACTIVE") : (s.catalogMode ? "ALL" : "ACTIVE");
    s.applied = { status: s.status.value, ...(s.keyword.value ? { keyword: s.keyword.value } : {}) };
    window.WarehousePage.rememberWarehouse(s.user, s.warehouse?.id || null);
    notice(s.alert, ""); s.body.setAttribute("aria-busy", "false"); s.body.replaceChildren(el("p", "orders-empty", "Chọn kho để xem vị trí lưu kho"));
    update(s); syncRoute(s); if (s.warehouse) await reload(s);
  }
  async function reload(s) {
    if (!alive(s) || !s.warehouse) return;
    s.listAbort?.abort(); s.listAbort = new AbortController(); const seq = ++s.sequence, epoch = s.epoch, warehouse = s.warehouse;
    syncRoute(s); notice(s.alert, ""); s.rows = []; s.body.setAttribute("aria-busy", "true"); s.body.replaceChildren(el("p", "orders-empty", "Đang tải vị trí lưu kho…"));
    try {
      const query = new URLSearchParams(s.applied);
      const rows = await locationRows(s, warehouse.id, s.applied, s.listAbort.signal);
      if (!alive(s) || epoch !== s.epoch || seq !== s.sequence) return;
      s.rows = rows;
      s.body.replaceChildren(rows.length ? table(["Mã vị trí", "Khu lưu", "Kệ", "Ô", "Trạng thái hoạt động", "Thao tác"], rows.map(row => {
        const actions = el("div", "location-actions");
        if(s.permissions.codes.has("KHO_XEM") && warehouse.isActive !== false) actions.append(button("Xem hàng", () => openStock(s, row), "btn btn-outline-orange btn-sm"));
        for (const [label, callback] of [["Sửa", () => openEdit(s, row)], [row.isActive ? "Ngừng sử dụng" : "Kích hoạt lại", () => openToggle(s, row)]]) {
          const node = button(label, callback, "btn btn-outline-orange btn-sm"); node.dataset.manage = "true"; actions.append(node);
        }
        return [row.code, row.storageArea, row.rack, row.slot, badge(row.isActive ? "COMPLETED" : "CANCELLED", row.isActive ? "Đang hoạt động" : "Ngừng sử dụng"), actions];
      })) : el("p", "orders-empty", "Không có vị trí phù hợp tại kho này"));
      update(s);
    } catch (error) {
      if (!alive(s) || epoch !== s.epoch || seq !== s.sequence || error.name === "AbortError") return;
      notice(s.alert, message(error)); s.alert.append(button("Thử lại", () => reload(s))); s.body.replaceChildren(el("p", "orders-empty", "Chưa tải được danh sách vị trí."));
    } finally { if (alive(s) && epoch === s.epoch && seq === s.sequence) s.body.setAttribute("aria-busy", "false"); }
  }
  async function fresh(s, row, view, warehouse) {
    const rows = await locationRows(s, warehouse.id, {status:"ALL",keyword:row.code}, view.signal);
    const current = rows.find(item => item.id === row.id);
    if (!current) throw Object.assign(new Error("Vị trí không còn tồn tại. Hãy tải lại danh sách."), { status: 404 });
    return current;
  }
  async function locationRows(s, warehouseId, filters, signal) {
    if(!s.catalogMode)return validateRows(await request(s,"/api/v1/warehouses/"+warehouseId+"/locations?"+new URLSearchParams(filters),signal),warehouseId);
    const result=await request(s,"/api/v1/catalogs?type=LOCATIONS&warehouseId="+warehouseId,signal);
    return validateRows(result.locations,warehouseId).filter(r=>(!filters.status||filters.status==="ALL"||r.isActive===(filters.status==="ACTIVE"))&&(!filters.keyword||[r.code,r.storageArea,r.rack,r.slot].some(v=>v?.toLocaleLowerCase("vi").includes(filters.keyword.toLocaleLowerCase("vi")))));
  }
  function payload(row, warehouseId, isActive) {
    return { type: "LOCATIONS", id: row?.id || null, warehouseId, code: row.code, storageArea: row.storageArea || null, rack: row.rack || null, slot: row.slot || null, isActive };
  }
  function fieldError(control, feedback, value) {
    control.classList.toggle("is-invalid", Boolean(value)); control.setAttribute("aria-invalid", String(Boolean(value))); feedback.textContent = value || "";
  }
  async function openEdit(s, row) {
    if (!alive(s) || !s.warehouse || !manage(s) || s.pending || s.dialogs.size) return;
    const warehouse = s.warehouse, epoch = s.epoch, view = dialog(s, row ? "Sửa vị trí lưu kho" : "Thêm vị trí lưu kho"); view.node.classList.add("locations-dialog");
    view.body.append(el("p", "text-secondary", "Đang tải dữ liệu vị trí…"));
    try {
      const current = row ? await fresh(s, row, view, warehouse) : null;
      if (!alive(s) || epoch !== s.epoch || !view.node.isConnected) return;
      const form = el("form"); form.noValidate = true; const fields = el("fieldset"), errorBox = el("div"), controls = {};
      fields.append(summary([["Kho đang chọn", warehouse.name], ["Bưu cục", warehouse.branchName]]));
      for (const [key, label, maxLength] of [["code", "Mã vị trí *", 50], ["storageArea", "Tên khu lưu", 100], ["rack", "Kệ", 50], ["slot", "Ô", 50]]) {
        const control = input("text", current?.[key] || "", { maxLength, required: key === "code" });
        if (key === "code" && current) control.readOnly = true;
        const wrapper = field(label, control, "mb-3"), feedback = el("div", "invalid-feedback"); feedback.id = control.id + "-error"; control.setAttribute("aria-describedby", feedback.id); wrapper.append(feedback);
        if (key === "code") wrapper.append(el("small", "text-secondary", current ? "Mã và kho được giữ cố định theo quy tắc danh mục." : "Tối đa 50 ký tự: chữ in hoa, số, gạch ngang hoặc gạch dưới. Mã duy nhất trong kho."));
        fields.append(wrapper); controls[key] = { control, feedback, maxLength };
        control.addEventListener("input", () => fieldError(control, feedback, ""));
      }
      const cancel = button("Hủy", () => view.close()), save = button("Lưu", null, "btn btn-orange"); save.type = "submit";
      const footer = el("div", "order-actions"); footer.append(cancel, save); form.append(fields, footer); view.body.replaceChildren(errorBox, form);
      let pending = false, blocked = false;
      function errorsFromBackend(error) {
        const details = error.data?.errors || {};
        for (const [name, values] of Object.entries(details)) {
          const key = name.replace(/^\$\./, "").split(".").at(-1).toLowerCase();
          const entry = Object.entries(controls).find(([fieldName]) => fieldName.toLowerCase() === key)?.[1];
          if (entry) fieldError(entry.control, entry.feedback, Array.isArray(values) ? values.join(" ") : String(values));
        }
        const entry = controls[error.data?.field]; if (entry) fieldError(entry.control, entry.feedback, error.data.message || message(error));
      }
      form.addEventListener("submit", async event => {
        event.preventDefault(); if (pending || blocked || !manage(s) || !alive(s) || epoch !== s.epoch) return;
        notice(errorBox, ""); let first = null;
        for (const [key, entry] of Object.entries(controls)) {
          const value = entry.control.value;
          const error = value.length > entry.maxLength ? "Tối đa " + entry.maxLength + " ký tự."
            : key === "code" && !/^[A-Z0-9][A-Z0-9_-]*$/.test(value) ? "Mã phải bắt đầu bằng chữ in hoa hoặc số, chỉ dùng chữ in hoa, số, gạch ngang hoặc gạch dưới."
            : ["rack", "slot"].includes(key) && value.trim() && !/^[A-Za-z0-9 ._-]+$/.test(value) ? "Chỉ dùng chữ, số, khoảng trắng, dấu chấm, gạch ngang hoặc gạch dưới." : "";
          fieldError(entry.control, entry.feedback, error); if (error && !first) first = entry.control;
        }
        if (first) { first.focus(); return; }
        const values = Object.fromEntries(Object.entries(controls).map(([key, entry]) => [key, key === "code" ? entry.control.value : entry.control.value.trim() || null]));
        const data = payload({ ...current, ...values }, warehouse.id, current?.isActive ?? true);
        pending = true; s.pending = true; fields.disabled = save.disabled = cancel.disabled = true; view.setBusy(true); update(s);
        try {
          const result = await request(s, "/api/v1/catalogs", view.signal, { method: "POST", body: JSON.stringify(data) });
          if (!alive(s) || epoch !== s.epoch || !view.node.isConnected) return;
          if (!positive(result?.id) || result.warehouseId !== warehouse.id || result.code !== data.code || result.type !== "LOCATIONS") throw new Error("API lưu vị trí trả dữ liệu không hợp lệ. Hãy kiểm tra lại danh sách trước khi gửi tiếp.");
          view.close(); notice(s.alert, current ? "Đã cập nhật vị trí " + result.code + "." : "Đã thêm vị trí " + result.code + ".", "success"); await reload(s);
          // reload clears load errors; keep the operation feedback when it succeeded.
          if (alive(s) && epoch === s.epoch && !s.alert.querySelector('.alert-danger')) notice(s.alert, current ? "Đã cập nhật vị trí " + result.code + "." : "Đã thêm vị trí " + result.code + ".", "success");
        } catch (error) {
          if (!alive(s) || epoch !== s.epoch || !view.node.isConnected || error.name === "AbortError") return;
          notice(errorBox, message(error)); errorsFromBackend(error);
          if (error.status === 403) { s.permissions = { known: true, codes: new Set() }; blocked = true; }
          if (!error.status || error.networkError) { blocked = true; errorBox.append(button("Đóng và tải lại", () => { view.close(); reload(s); })); }
        } finally {
          pending = false; s.pending = false; fields.disabled = blocked; save.disabled = blocked; cancel.disabled = false; view.setBusy(false); update(s);
        }
      });
    } catch (error) {
      if (!alive(s) || epoch !== s.epoch || !view.node.isConnected || error.name === "AbortError") return;
      const box = el("div"); notice(box, message(error)); view.body.replaceChildren(box, button("Hủy", () => view.close()));
    }
  }
  async function openToggle(s, row) {
    if (!alive(s) || !s.warehouse || !manage(s) || s.pending || s.dialogs.size) return;
    const warehouse = s.warehouse, epoch = s.epoch, view = dialog(s, row.isActive ? "Ngừng sử dụng vị trí" : "Kích hoạt lại vị trí"); view.node.classList.add("locations-dialog");
    view.body.append(el("p", "text-secondary", "Đang kiểm tra vị trí hiện tại…"));
    try {
      const current = await fresh(s, row, view, warehouse);
      if (!alive(s) || epoch !== s.epoch || !view.node.isConnected) return;
      if (current.isActive !== row.isActive) throw Object.assign(new Error("Trạng thái vị trí đã thay đổi. Hãy tải lại danh sách."), { status: 409 });
      const box = el("div"), cancel = button("Hủy", () => view.close());
      const confirm = button(current.isActive ? "Xác nhận ngừng sử dụng" : "Xác nhận kích hoạt lại", null, "btn btn-orange");
      const actions = el("div", "order-actions"); actions.append(cancel, confirm);
      view.body.replaceChildren(box, summary([["Mã vị trí", current.code], ["Kho", warehouse.name]]), el("p", "", (current.isActive ? "Ngừng sử dụng" : "Kích hoạt lại") + " vị trí " + current.code + "?"),
        el("p", "text-secondary", current.isActive ? "Vị trí chỉ được ngừng sử dụng khi không còn hàng tồn. Lịch sử vẫn được giữ lại." : "Vị trí sẽ xuất hiện lại trong danh sách chọn của các form kho."), actions);
      let pending = false, blocked = false;
      confirm.addEventListener("click", async () => {
        if (pending || blocked || !alive(s) || epoch !== s.epoch || !manage(s)) return;
        pending = true; s.pending = true; cancel.disabled = confirm.disabled = true; view.setBusy(true); update(s);
        try {
          const result = await request(s, "/api/v1/catalogs", view.signal, { method: "POST", body: JSON.stringify(payload(current, warehouse.id, !current.isActive)) });
          if (!alive(s) || epoch !== s.epoch || !view.node.isConnected) return;
          if (result?.id !== current.id || result.warehouseId !== warehouse.id || result.isActive !== !current.isActive) throw new Error("Phản hồi lưu vị trí không hợp lệ. Hãy kiểm tra lại danh sách.");
          view.close(); await reload(s); if (alive(s) && epoch === s.epoch && !s.alert.querySelector('.alert-danger')) notice(s.alert, "Đã " + (current.isActive ? "ngừng sử dụng" : "kích hoạt lại") + " vị trí " + current.code + ".", "success");
        } catch (error) {
          if (!alive(s) || epoch !== s.epoch || !view.node.isConnected || error.name === "AbortError") return;
          notice(box, message(error)); blocked = [403,404,409].includes(error.status) || !error.status;
          if (error.status === 403) s.permissions = { known: true, codes: new Set() };
          if (blocked) { await reload(s); box.append(button("Đóng", () => view.close())); }
        } finally { pending = false; s.pending = false; cancel.disabled = false; confirm.disabled = blocked; view.setBusy(false); update(s); }
      });
    } catch (error) {
      if (!alive(s) || epoch !== s.epoch || !view.node.isConnected || error.name === "AbortError") return;
      const box = el("div"); notice(box, message(error)); view.body.replaceChildren(box, button("Hủy", () => { view.close(); reload(s); }));
    }
  }
  function openStock(s, row) {
    if (!alive(s) || !s.warehouse || s.pending || s.dialogs.size) return;
    const warehouse = s.warehouse, epoch = s.epoch, view = dialog(s, "Hàng tại vị trí " + row.code, true); view.node.classList.add("locations-dialog");
    const body = el("div"), feedback = el("div"), pager = el("nav", "orders-pagination"), footer = el("div", "locations-stock-footer");
    const size = select([{id:10,name:"10 dòng"},{id:20,name:"20 dòng"},{id:50,name:"50 dòng"}], "Số dòng", 10);
    footer.append(field("Số dòng", size, "warehouse-page-size"), pager); view.body.append(summary([["Kho", warehouse.name], ["Vị trí", row.code]]), feedback, body, footer);
    let page = 1, sequence = 0, controller;
    async function load() {
      controller?.abort(); controller = new AbortController(); const seq = ++sequence;
      body.setAttribute("aria-busy", "true"); body.replaceChildren(el("p", "orders-empty", "Đang tải hàng tại vị trí…")); notice(feedback, ""); footer.hidden = true;
      try {
        const query = new URLSearchParams({ locationId: row.id, page, pageSize: size.value });
        const url = "/api/v1/warehouses/" + warehouse.id + "/inventory?" + query;
        const result = window.ApiClient.validatePage(await request(s, url, AbortSignal.any([view.signal, controller.signal])), url, ["orderId", "warehouseId"]);
        if (!alive(s) || epoch !== s.epoch || !view.node.isConnected || seq !== sequence) return;
        if (result.warehouseId !== warehouse.id || result.items.some(item => item.warehouseId !== warehouse.id || item.locationId !== row.id)) throw new Error("API tồn kho không khớp kho và vị trí đã chọn.");
        const pages = Math.max(1, Math.ceil(result.totalItems / Number(size.value))); if (page > pages) { page = pages; load(); return; }
        body.replaceChildren(result.items.length ? table(["Mã đơn", "Mã vận đơn", "Trạng thái đơn", "Trạng thái tồn kho", "Khối lượng", "Thời gian nhập kho (VN)"], result.items.map(item => [item.orderCode, item.trackingNumber,
          badge(item.orderStatus, item.orderStatusName), badge(item.inventoryStatus, {RECEIVED:"Đã nhận vào kho",STORED:"Đang lưu kho",ALLOCATED:"Đã giữ cho phân công",RETURNED:"Hàng hoàn trong kho"}[item.inventoryStatus]),weight(item.weightKg),date(item.receivedAt)])) : el("p", "orders-empty", "Không có hàng tại vị trí này"));
        pagination(pager, page, Number(size.value), result.totalItems, next => { page = next; load(); }); footer.hidden = result.totalItems === 0;
      } catch (error) {
        if (!alive(s) || epoch !== s.epoch || !view.node.isConnected || seq !== sequence || error.name === "AbortError") return;
        notice(feedback, message(error)); feedback.append(button("Thử lại", load)); body.replaceChildren(el("p", "orders-empty", "Chưa tải được hàng tại vị trí."));
      } finally { if (view.node.isConnected && seq === sequence) body.setAttribute("aria-busy", "false"); }
    }
    size.addEventListener("change", () => { page = 1; load(); }); view.onClose(() => { sequence++; controller?.abort(); }); load();
  }
  window.LocationsPage = Object.freeze({ mount, destroy });
}());
