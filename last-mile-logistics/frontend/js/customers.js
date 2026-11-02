"use strict";
(function () {
  const UI = window.LogisticsUI, Router = window.Router;
  const { el, button, table, summary, date } = UI;
  let active = null, serial = 0;
  const types = { INDIVIDUAL: "Cá nhân", BUSINESS: "Doanh nghiệp" };
  const alive = s => active === s && !s.abort.signal.aborted;
  const can = (s, code) => s.permissions?.known === true && s.permissions.codes.has(code);
  const read = (s, path, signal) => window.ApiClient.request(path, { signal: signal || s.abort.signal });
  function alert(box, message, tone = "danger") {
    box.replaceChildren();
    if (message) { const node = el("div", "alert alert-" + tone, message); node.setAttribute("role", tone === "success" ? "status" : "alert"); box.append(node); }
  }
  function status(value) { return el("span", "badge " + (value ? "text-bg-success" : "text-bg-secondary"), value ? "Đang sử dụng" : "Ngừng sử dụng"); }
  function select(items, value) {
    const node = el("select", "form-select");
    for (const [key, label] of items) { const opt = el("option", "", label); opt.value = key; node.append(opt); }
    node.value = value ?? ""; return node;
  }
  function link(label, href) { const node = el("a", "btn btn-outline-orange btn-sm", label); node.href = href; return node; }
  function actions(...nodes) { const box = el("div", "customer-actions"); box.append(...nodes); return box; }
  function failure(s, box, error, retry) {
    if (!alive(s) || error.name === "AbortError" || error.sessionExpired) return;
    const title = error.status === 404 ? "Không tìm thấy khách hàng." : error.status === 403 ? "Không có quyền truy cập." : "Không thể tải dữ liệu.";
    alert(box, title + " " + error.message);
    if (retry && error.status !== 403 && error.status !== 404) box.append(button("Thử lại", retry, "btn btn-outline-orange"));
  }
  function customerPayload(c) { return { fullName: c.fullName, phone: c.phone, email: c.email || null, type: c.type, isActive: c.isActive }; }
  function addressPayload(a) {
    return { label: a.label || null, contactName: a.contactName || null, phone: a.phone || null, address: a.address,
      areaId: a.areaId ?? null, latitude: a.latitude ?? null, longitude: a.longitude ?? null, isDefault: a.isDefault, isActive: a.isActive };
  }
  function dialog(s, title) {
    if (s.dialog) return null;
    const node = el("dialog", "customer-modal"), header = el("div", "customer-modal-header");
    const heading = el("h2", "h5 mb-0", title); heading.id = "customer-modal-" + (++serial); node.setAttribute("aria-labelledby", heading.id);
    const controller = new AbortController();
    const abort = () => controller.abort(); s.abort.signal.addEventListener("abort", abort, { once: true });
    const d = { node, heading, body: el("div", "customer-modal-body"), busy: false, signal: controller.signal, closed: false };
    d.close = () => {
      if (d.closed) return; d.closed = true; controller.abort(); s.abort.signal.removeEventListener("abort", abort);
      if (node.open) node.close(); node.remove(); if (s.dialog === d) s.dialog = null;
    };
    const close = button("Đóng", () => { if (!d.busy) d.close(); }, "btn btn-outline-secondary btn-sm");
    d.setBusy = value => { d.busy = value; close.disabled = value; };
    header.append(heading, close); node.append(header, d.body);
    node.addEventListener("cancel", event => { if (d.busy) event.preventDefault(); else d.close(); });
    node.addEventListener("close", d.close); s.root.append(node); s.dialog = d; node.showModal();
    return d;
  }
  function formField(form, fields, key, label, value, config = {}) {
    const wrap = el("div", config.full ? "col-12" : "col-md-6"), caption = el("label", "form-label", label);
    let control;
    if (config.items) control = select(config.items, value);
    else { control = el(config.multiline ? "textarea" : "input", "form-control");
      if (!config.multiline) control.type = config.check ? "checkbox" : "text";
      if (config.check) { control.className = "form-check-input d-block"; control.checked = Boolean(value); }
      else control.value = value ?? "";
    }
    control.id = "customer-field-" + (++serial); control.name = key; caption.htmlFor = control.id;
    if (config.max) control.maxLength = config.max;
    if (config.required) control.required = true;
    if (config.mode) control.inputMode = config.mode;
    const error = el("div", "invalid-feedback"); error.id = control.id + "-error"; control.setAttribute("aria-describedby", error.id);
    wrap.append(caption, control, error); form.append(wrap); fields[key] = { control, error }; return control;
  }
  function fieldError(fields, key, message) {
    const field = fields[key]; if (!field) return false;
    field.control.classList.add("is-invalid"); field.control.setAttribute("aria-invalid", "true"); field.error.textContent = message; return true;
  }
  function clearErrors(fields) { for (const f of Object.values(fields)) { f.control.classList.remove("is-invalid"); f.control.removeAttribute("aria-invalid"); f.error.textContent = ""; } }
  function values(fields) { return Object.fromEntries(Object.entries(fields).map(([key, {control}]) => [key, control.type === "checkbox" ? control.checked : control.value.trim()])); }
  function validate(fields, isAddress) {
    clearErrors(fields); const v = values(fields);
    for (const [key, {control}] of Object.entries(fields)) {
      if (control.required && !v[key]) fieldError(fields, key, "Vui lòng nhập trường này.");
      if (control.maxLength > 0 && String(v[key]).length > control.maxLength) fieldError(fields, key, "Tối đa " + control.maxLength + " ký tự.");
    }
    if (v.phone && !/^\+?[0-9]{9,15}$/.test(v.phone)) fieldError(fields, "phone", "Số điện thoại phải có từ 9 đến 15 chữ số, có thể bắt đầu bằng +.");
    if (!isAddress && v.email && (v.email.indexOf("@") < 1 || v.email.indexOf("@") !== v.email.lastIndexOf("@") || v.email.endsWith("@"))) fieldError(fields, "email", "Email không hợp lệ.");
    if (isAddress) {
      if (Boolean(v.latitude) !== Boolean(v.longitude)) for (const key of ["latitude", "longitude"]) fieldError(fields, key, "Nhập cả vĩ độ và kinh độ hoặc bỏ trống cả hai.");
      for (const [key, max] of [["latitude", 90], ["longitude", 180]]) {
        if (v[key] && (!/^[+-]?(?:\d+(?:\.\d*)?|\.\d+)$/.test(v[key]) || !Number.isFinite(Number(v[key])) || Math.abs(Number(v[key])) > max)) fieldError(fields, key, "Giá trị phải nằm trong khoảng -" + max + " đến " + max + ".");
        else if (v[key].includes(".") && v[key].split(".")[1].replace(/0+$/, "").length > 6) fieldError(fields, key, "Tọa độ chỉ được có tối đa 6 chữ số thập phân.");
      }
      if (v.isDefault && v.isActive === false) fieldError(fields, "isDefault", "Địa chỉ ngừng sử dụng không thể là mặc định.");
    }
    const invalid = Object.values(fields).find(f => f.control.classList.contains("is-invalid")); invalid?.control.focus(); return invalid ? null : v;
  }
  function serverErrors(fields, error) {
    const errors = error.data?.errors;
    if (errors && typeof errors === "object") for (const [key, messages] of Object.entries(errors)) {
      const name = key.split(".").at(-1); const actual = Object.keys(fields).find(f => f.toLowerCase() === name.toLowerCase());
      if (actual) fieldError(fields, actual, [].concat(messages).join(" "));
    }
    const message = error.data?.message || "";
    if (/khu vực/i.test(message)) fieldError(fields, "areaId", message);
    Object.values(fields).find(f => f.control.classList.contains("is-invalid"))?.control.focus();
  }
  function saveForm(s, d, form, fields, isAddress, path, method, makePayload, reload) {
    const box = el("div", "col-12"), footer = el("div", "col-12 customer-actions"), save = button("Lưu", null, "btn btn-orange"); save.type = "submit";
    let conflicted = false;
    footer.append(save); form.append(box, footer); form.noValidate = true;
    form.addEventListener("submit", async event => {
      event.preventDefault(); if (d.busy || conflicted || d.writeUnknown) return;
      const v = validate(fields, isAddress); if (!v) return;
      const payload = makePayload(v); alert(box, ""); d.setBusy(true);
      const controls = [...form.querySelectorAll("input, select, textarea, button")].map(control => [control, control.disabled]);
      for (const [control] of controls) control.disabled = true;
      save.textContent = "Đang lưu…";
      try {
        window.WriteOutcome.assertCanSend(d,{path,payload,method});
        await window.ApiClient.request(path, { method, body: JSON.stringify(payload), signal: d.signal });
        if (!alive(s) || d.closed) return;
        d.close(); s.message = "Đã lưu thay đổi."; await refresh(s);
      } catch (error) {
        if (!alive(s) || d.closed) return;
        if (window.WriteOutcome.lock(d,box,error,{path,payload,scope:form})) return;
        if (error.name === "AbortError" || error.sessionExpired) return;
        serverErrors(fields, error); alert(box, error.message);
        if (error.status === 409) {
          conflicted = true;
          box.append(el("p", "text-secondary mt-2", "Nội dung đang nhập được giữ lại để bạn xem và sao chép. Tải dữ liệu mới sẽ bỏ toàn bộ nội dung chưa lưu trong biểu mẫu này."));
          if (reload) {
            const reloadFeedback = el("div");
            const latest = button("Tải dữ liệu mới", async () => {
              if (d.busy || d.closed) return;
              if (!window.confirm("Tải dữ liệu mới sẽ bỏ toàn bộ nội dung chưa lưu trong biểu mẫu này. Bạn có muốn tiếp tục?")) return;
              d.setBusy(true); latest.disabled = true; form.inert = true; alert(reloadFeedback, "");
              try { await reload(true); }
              catch (error) { if (!d.closed) failure(s, reloadFeedback, error); }
              finally { if (!d.closed) { d.setBusy(false); latest.disabled = false; form.inert = false; } }
            }, "btn btn-outline-orange");
            box.append(latest, reloadFeedback);
          }
        }
      } finally { if (!d.closed) { d.setBusy(false); window.WriteOutcome.restore(controls,d); save.disabled = conflicted || !!d.writeUnknown; save.textContent = "Lưu"; } }
    });
  }
  async function customerEditor(s, id, toggle = false) {
    if (!can(s, id ? "DONHANG_CAPNHAT" : "DONHANG_TAO")) return;
    const d = dialog(s, id ? "Cập nhật khách hàng" : "Thêm khách hàng"); if (!d) return;
    d.body.append(el("p", "text-secondary", "Đang tải…"));
    async function load(preserveForm = false) {
      try {
        const c = id ? await read(s, "/api/v1/customers/" + id + "?includeInactiveAddresses=true", d.signal) : {type: "INDIVIDUAL", isActive: true};
        if (!alive(s) || d.closed) return;
        if (id && (typeof c.version !== "string" || !/^[A-Za-z0-9+/]{11}=$/.test(c.version))) throw new Error("Chưa đọc được phiên bản khách hàng hợp lệ. Hãy tải lại dữ liệu.");
        if (toggle) d.heading.textContent = (c.isActive ? "Ngừng sử dụng: " : "Kích hoạt lại: ") + c.fullName;
        const form = el("form", "row g-3"), fields = {};
        formField(form, fields, "fullName", "Họ tên / Tên doanh nghiệp *", c.fullName, {required: true, max: 150, full: true});
        formField(form, fields, "phone", "Số điện thoại *", c.phone, {required: true, mode: "tel"});
        formField(form, fields, "email", "Email", c.email, {max: 150, mode: "email"});
        formField(form, fields, "type", "Loại khách hàng *", c.type, {required: true, items: Object.entries(types)});
        if (id) formField(form, fields, "isActive", "Đang sử dụng", toggle ? !c.isActive : c.isActive, {check: true});
        form.append(el("p", "col-12 text-secondary mb-0", id ? "Mã khách hàng: " + c.customerCode : "Mã khách hàng được hệ thống sinh tự động."));
        // Keep the version displayed when this form opened; never refresh it on submit.
        saveForm(s, d, form, fields, false, "/api/v1/customers" + (id ? "/" + id : ""), id ? "PUT" : "POST", v => id ? {...customerPayload(v), expectedVersion: c.version} : {fullName: v.fullName, phone: v.phone, email: v.email || null, type: v.type}, load);
        d.body.replaceChildren(form); fields.fullName.control.focus();
      } catch (error) { if (preserveForm === true) throw error; if (!d.closed) failure(s, d.body, error, () => load()); }
    }
    await load();
  }
  async function addressEditor(s, customerId, addressId, overrides = {}) {
    if (!can(s, "DONHANG_CAPNHAT")) return;
    const d = dialog(s, addressId ? "Cập nhật địa chỉ" : "Thêm địa chỉ"); if (!d) return;
    d.body.append(el("p", "text-secondary", "Đang tải khách hàng và danh mục khu vực…"));
    async function load(preserveForm = false) {
      try {
        const [c, options] = await Promise.all([read(s, "/api/v1/customers/" + customerId + "?includeInactiveAddresses=true", d.signal), read(s, "/api/v1/order-form/options", d.signal)]);
        if (!alive(s) || d.closed) return;
        if (!c.isActive) throw new Error("Khách hàng đã ngừng sử dụng. Hãy kích hoạt lại trước.");
        const existing = addressId ? c.addresses.find(a => a.id === addressId) : {isActive: true, isDefault: false};
        if (!existing) throw new Error("Không tìm thấy địa chỉ của khách hàng này.");
        if (addressId && (typeof existing.version !== "string" || !/^[A-Za-z0-9+/]{11}=$/.test(existing.version))) throw new Error("Chưa đọc được phiên bản địa chỉ hợp lệ. Hãy tải lại dữ liệu.");
        if (!Array.isArray(options.areas)) throw new Error("API không trả danh mục khu vực hợp lệ.");
        const a = {...existing, ...overrides}, form = el("form", "row g-3"), fields = {};
        if (overrides.isDefault) d.heading.textContent = "Đặt địa chỉ mặc định";
        else if (overrides.isActive !== undefined) d.heading.textContent = overrides.isActive ? "Kích hoạt lại địa chỉ" : "Ngừng sử dụng địa chỉ";
        formField(form, fields, "label", "Nhãn địa chỉ", a.label, {max: 100});
        formField(form, fields, "contactName", "Tên người liên hệ", a.contactName, {max: 150});
        formField(form, fields, "phone", "Điện thoại liên hệ", a.phone, {mode: "tel"});
        const areaItems = [["", "Không chọn khu vực"], ...options.areas.map(a => [a.id, a.name])];
        if (a.areaId && !options.areas.some(k => k.id === a.areaId)) areaItems.push([a.areaId, (a.areaName || "Khu vực #" + a.areaId) + " (đã ngừng sử dụng; chọn lại)"]);
        formField(form, fields, "areaId", "Khu vực", a.areaId, {items: areaItems});
        formField(form, fields, "address", "Địa chỉ *", a.address, {required: true, max: 300, multiline: true, full: true});
        formField(form, fields, "latitude", "Vĩ độ (tùy chọn)", a.latitude, {mode: "decimal"});
        formField(form, fields, "longitude", "Kinh độ (tùy chọn)", a.longitude, {mode: "decimal"});
        const def = formField(form, fields, "isDefault", "Địa chỉ mặc định", a.isDefault, {check: true});
        if (addressId) {
          const enabled = formField(form, fields, "isActive", "Đang sử dụng", a.isActive, {check: true});
          enabled.addEventListener("change", () => { if (!enabled.checked) def.checked = false; def.disabled = !enabled.checked; }); def.disabled = !a.isActive;
        }
        form.append(el("p", "col-12 text-secondary mb-0", "Bỏ trống người liên hệ/điện thoại để dùng thông tin khách hàng. Hệ thống tự chọn địa chỉ mặc định nếu chưa có."));
        saveForm(s, d, form, fields, true, "/api/v1/customers/" + customerId + "/addresses" + (addressId ? "/" + addressId : ""), addressId ? "PUT" : "POST", v => {
          const payload = addressPayload({...v, areaId: v.areaId ? Number(v.areaId) : null, latitude: v.latitude === "" ? null : Number(v.latitude), longitude: v.longitude === "" ? null : Number(v.longitude), isActive: addressId ? v.isActive : true});
          if (!addressId) delete payload.isActive;
          else payload.expectedVersion = existing.version;
          return payload;
        }, load);
        d.body.replaceChildren(form); fields.label.control.focus();
      } catch (error) { if (preserveForm === true) throw error; if (!d.closed) failure(s, d.body, error, () => load()); }
    }
    await load();
  }
  function mountList(s) {
    const q = s.route.query; s.filters = {page: q.page || 1, pageSize: q.pageSize || 10, keyword: q.keyword || "", type: q.type || "", status: q.status || "ALL"};
    const tools = el("div", "customer-toolbar");
    if (can(s, "DONHANG_TAO")) tools.append(button("Thêm khách hàng", () => customerEditor(s), "btn btn-orange"));
    tools.append(button("Làm mới", () => refresh(s), "btn btn-outline-orange"));
    const filter = el("form", "row g-3 customer-filters"), fields = {};
    formField(filter, fields, "keyword", "Tìm mã, tên hoặc số điện thoại", s.filters.keyword, {max: 100});
    formField(filter, fields, "type", "Loại khách hàng", s.filters.type, {items: [["", "Tất cả loại"], ...Object.entries(types)]});
    formField(filter, fields, "status", "Trạng thái", s.filters.status, {items: [["ALL", "Tất cả trạng thái"], ["ACTIVE", "Đang sử dụng"], ["INACTIVE", "Ngừng sử dụng"]]});
    const submit = button("Tìm kiếm", null, "btn btn-outline-orange"); submit.type = "submit"; filter.append(actions(submit));
    filter.addEventListener("submit", event => { event.preventDefault(); s.filters = {...s.filters, ...values(fields), page: 1}; refresh(s); });
    for (const key of ["type", "status"]) fields[key].control.addEventListener("change", () => filter.requestSubmit());
    s.feedback = el("div"); s.results = el("div"); s.pager = el("div", "customer-pagination");
    s.root.append(tools, filter, s.feedback, s.results, s.pager); refresh(s);
  }
  async function loadList(s) {
    s.listAbort?.abort(); s.listAbort = new AbortController(); const controller = s.listAbort;
    const signal = AbortSignal.any([s.abort.signal, controller.signal]);
    Router.updateQuery(s.filters, s.route); s.route = Router.current() || s.route;
    const q = new URLSearchParams(Object.entries(s.filters).filter(([,v]) => v !== ""));
    s.results.replaceChildren(el("p", "customer-empty", "Đang tải khách hàng…")); s.pager.replaceChildren(); alert(s.feedback, "");
    try {
      const path = "/api/v1/customers?" + q, data = window.ApiClient.validatePage(await read(s, path, signal), path, ["id"]);
      if (!alive(s) || signal.aborted) return;
      const pages = Math.max(1, Math.ceil(data.totalItems / data.pageSize));
      if (data.page > pages) { s.filters.page = pages; return loadList(s); }
      const rows = data.items.map(c => {
        const tools = actions(link("Xem chi tiết", Router.href("customer-detail", {id: c.id}, s.filters)));
        if (can(s, "DONHANG_CAPNHAT")) tools.append(button("Sửa", () => customerEditor(s, c.id)), button(c.isActive ? "Ngừng sử dụng" : "Kích hoạt lại", () => customerEditor(s, c.id, true)));
        return [c.customerCode, c.fullName, c.phone, c.email, types[c.type] || c.type, status(c.isActive), tools];
      });
      s.results.replaceChildren(rows.length ? table(["Mã khách hàng", "Tên", "Điện thoại", "Email", "Loại", "Trạng thái", "Thao tác"], rows) : el("p", "customer-empty", "Không có khách hàng phù hợp với bộ lọc."));
      const prev = button("‹ Trước", () => {s.filters.page--; refresh(s);}); prev.disabled = data.page <= 1;
      const next = button("Sau ›", () => {s.filters.page++; refresh(s);}); next.disabled = data.page >= pages;
      const size = select([...new Set([10,20,50,100,data.pageSize])].sort((a,b) => a-b).map(n => [n, n + " dòng"]), data.pageSize); size.setAttribute("aria-label", "Số dòng mỗi trang");
      size.addEventListener("change", () => {s.filters.pageSize = Number(size.value); s.filters.page = 1; refresh(s);});
      s.pager.append(el("span", "text-secondary", data.totalItems + " kết quả · Trang " + data.page + " / " + pages), size, prev, next);
      if (s.message) {alert(s.feedback, s.message, "success"); s.message = "";}
    } catch (error) { if (!signal.aborted) {s.results.replaceChildren(); failure(s, s.feedback, error, () => refresh(s));} }
  }
  async function loadDetail(s) {
    const epoch = ++s.detailEpoch; s.root.replaceChildren(el("p", "customer-empty", "Đang tải khách hàng…"));
    const back = link("‹ Quay về danh sách", Router.href("customers", {}, s.route.query));
    try {
      const c = await read(s, "/api/v1/customers/" + s.route.params.id + "?includeInactiveAddresses=true");
      if (!alive(s) || epoch !== s.detailEpoch) return;
      if (c.id !== s.route.params.id || !Array.isArray(c.addresses) || !Array.isArray(c.recentOrders)) throw new Error("API chi tiết khách hàng trả dữ liệu không hợp lệ.");
      const toolbar = actions(back, button("Làm mới", () => refresh(s), "btn btn-outline-orange"));
      if (can(s, "DONHANG_CAPNHAT")) toolbar.append(button("Sửa khách hàng", () => customerEditor(s, c.id), "btn btn-orange"), button(c.isActive ? "Ngừng sử dụng" : "Kích hoạt lại", () => customerEditor(s, c.id, true)));
      s.root.replaceChildren(toolbar);
      const feedback = el("div"); s.root.append(feedback);
      if (s.message) {alert(feedback, s.message, "success"); s.message = "";}
      s.root.append(summary([["Mã khách hàng", c.customerCode], ["Họ tên / Tên doanh nghiệp", c.fullName], ["Điện thoại", c.phone], ["Email", c.email], ["Loại", types[c.type]], ["Trạng thái", c.isActive ? "Đang sử dụng" : "Ngừng sử dụng"], ["Ngày tạo", date(c.createdAt)]]));
      const tabs = el("div", "nav nav-tabs customer-tabs"), addresses = el("section"), orders = el("section");
      const aTab = button("Địa chỉ (" + c.addresses.length + ")", () => showTab(false), "nav-link"), oTab = button("Đơn hàng", () => showTab(true), "nav-link");
      tabs.setAttribute("role", "tablist"); addresses.id = "customer-addresses"; orders.id = "customer-orders";
      for (const [btn, panel] of [[aTab, addresses], [oTab, orders]]) { btn.setAttribute("role", "tab"); btn.id = panel.id + "-tab"; btn.setAttribute("aria-controls", panel.id); panel.setAttribute("role", "tabpanel"); panel.setAttribute("aria-labelledby", btn.id); }
      function showTab(isOrders) {addresses.hidden = isOrders; orders.hidden = !isOrders; aTab.classList.toggle("active", !isOrders); oTab.classList.toggle("active", isOrders); aTab.setAttribute("aria-selected", String(!isOrders)); oTab.setAttribute("aria-selected", String(isOrders));}
      tabs.append(aTab, oTab); showTab(false);
      if (can(s, "DONHANG_CAPNHAT") && c.isActive) addresses.append(button("Thêm địa chỉ", () => addressEditor(s, c.id), "btn btn-orange mb-3"));
      if (!c.isActive) addresses.append(el("p", "text-secondary", "Kích hoạt lại khách hàng để quản lý địa chỉ."));
      const rows = c.addresses.map(a => {
        const tools = actions();
        if (can(s, "DONHANG_CAPNHAT") && c.isActive) {
          tools.append(button("Sửa", () => addressEditor(s, c.id, a.id)));
          if (a.isActive && !a.isDefault) tools.append(button("Đặt mặc định", () => addressEditor(s, c.id, a.id, {isDefault: true})));
          tools.append(button(a.isActive ? "Ngừng sử dụng" : "Kích hoạt lại", () => addressEditor(s, c.id, a.id, {isActive: !a.isActive, isDefault: false})));
        }
        return [a.label, a.contactName || c.fullName, a.phone || c.phone, a.address, a.areaName, a.latitude == null ? "—" : a.latitude + ", " + a.longitude, a.isDefault ? "Mặc định" : "—", status(a.isActive), tools];
      });
      addresses.append(rows.length ? table(["Nhãn", "Người liên hệ", "Điện thoại", "Địa chỉ", "Khu vực", "Tọa độ", "Mặc định", "Trạng thái", "Thao tác"], rows) : el("p", "customer-empty", "Khách hàng chưa có địa chỉ."));
      orders.append(el("p", "text-secondary", "Tổng " + c.statistics.totalOrders + " đơn trong phạm vi " + (c.statistics.scope === "ALL_BRANCHES" ? "toàn hệ thống" : "bưu cục hiện tại") + ". Hiển thị tối đa 10 đơn gần nhất."));
      orders.append(table(["Mã đơn", "Mã vận đơn", "Vai trò", "Bưu cục", "Trạng thái", "Ngày tạo", "Thao tác"], c.recentOrders.map(o => [o.orderCode, o.trackingNumber, [o.isSender ? "Người gửi" : "", o.isReceiver ? "Người nhận" : ""].filter(Boolean).join(", "), o.branchName, o.statusName, date(o.createdAt), link("Xem đơn", Router.href("order-detail", {id: o.id}, {returnTo: Router.href("customer-detail", {id: c.id}, s.route.query)}))])));
      s.root.append(tabs, addresses, orders);
    } catch (error) { if (alive(s) && epoch === s.detailEpoch) {s.root.replaceChildren(back); const box = el("div"); s.root.append(box); failure(s, box, error, () => refresh(s));} }
  }
  function refresh(s) { if (!alive(s)) return; return s.route.mode === "detail" ? loadDetail(s) : loadList(s); }
  function destroy() { if (!active) return; active.dialog?.close(); active.abort.abort(); active.listAbort?.abort(); active = null; }
  function mount(container, user, route, context) {
    destroy(); const root = el("div", "customers-page"); container.replaceChildren(root);
    const s = {root, user, route, permissions: context.permissions, abort: new AbortController(), detailEpoch: 0}; active = s;
    context.signal?.addEventListener("abort", () => {s.abort.abort(); s.dialog?.close();}, {once: true, signal: s.abort.signal});
    if (!can(s, "DONHANG_XEM")) {alert(root, "Bạn không có quyền xem khách hàng."); return;}
    if (route.mode === "detail") loadDetail(s); else mountList(s);
  }
  window.CustomersPage = Object.freeze({mount, destroy});
}());
