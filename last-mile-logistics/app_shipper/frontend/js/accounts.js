"use strict";
(function () {
  const {el, button, table, summary, date} = window.LogisticsUI;
  const Router = window.Router;
  const states = {ACTIVE: "Đang hoạt động", LOCKED: "Bị khóa", INACTIVE: "Ngừng hoạt động"};
  const actionNames = {LOCK: "Khóa tài khoản", UNLOCK: "Mở khóa", DEACTIVATE: "Ngừng hoạt động", ACTIVATE: "Kích hoạt lại"};
  let active = null, unique = 0;
  const alive = s => active === s && !s.abort.signal.aborted;
  const can = (s, code) => s.permissions?.known && s.permissions.codes.has(code);
  const query = values => new URLSearchParams(Object.entries(values).filter(([,v]) => v !== "" && v != null)).toString();
  const read = (s, path, signal = s.abort.signal) => window.ApiClient.request(path, {signal});
  const branchText = c => c.branchId == null ? "Toàn hệ thống" : c.branchName || "Bưu cục #" + c.branchId;
  const temporary = c => c.lockedUntil && Date.parse(/(?:Z|[+-]\d{2}:\d{2})$/i.test(c.lockedUntil) ? c.lockedUntil : c.lockedUntil + "Z") > Date.now();
  function actions(...nodes) { const n = el("div", "account-actions"); n.append(...nodes); return n; }
  function link(label, href) { const n = el("a", "btn btn-outline-orange btn-sm", label); n.href = href; return n; }
  function alert(box, message, tone = "danger") {
    box.replaceChildren();
    if (message) { const n = el("div", "alert alert-" + tone, message); n.setAttribute("role", tone === "success" ? "status" : "alert"); box.append(n); }
  }
  function failure(s, box, error, retry) {
    if (!alive(s) || error.name === "AbortError" || error.sessionExpired) return;
    alert(box, (error.status === 403 ? "Không có quyền truy cập. " : "") + error.message);
    if (retry && ![403,404].includes(error.status)) box.append(button("Thử lại", retry, "btn btn-outline-orange"));
  }
  function status(c) {
    const n = el("div", "account-status");
    n.append(el("span", "badge " + ({ACTIVE:"text-bg-success", LOCKED:"text-bg-warning", INACTIVE:"text-bg-secondary"}[c.status] || "text-bg-secondary"), states[c.status] || c.status));
    if (temporary(c)) n.append(el("small", "text-warning-emphasis d-block mt-1", "Khóa tạm đến " + date(c.lockedUntil)));
    return n;
  }
  function select(items, value) {
    const n = el("select", "form-select");
    for (const [v, label, disabled] of items) { const o = el("option", "", label); o.value = v; o.disabled = !!disabled; n.append(o); }
    n.value = value ?? ""; return n;
  }
  function field(form, fields, key, label, value, config = {}) {
    const wrap = el("div", config.full ? "col-12" : "col-md-6"), cap = el("label", "form-label", label);
    const control = config.items ? select(config.items, value) : el(config.multiline ? "textarea" : "input", "form-control");
    if (!config.items) { if (!config.multiline) control.type = config.type || "text"; control.value = value ?? ""; }
    control.id = "account-field-" + (++unique); control.name = key; cap.htmlFor = control.id;
    if (config.max) control.maxLength = config.max;
    control.required = !!config.required;
    if (config.type === "password") control.autocomplete = "new-password";
    const error = el("div", "invalid-feedback"); error.id = control.id + "-error";
    control.setAttribute("aria-describedby", error.id); wrap.append(cap);
    if (config.type === "password") {
      const group = el("div", "input-group"), toggle = button("Hiện", () => {
        control.type = control.type === "password" ? "text" : "password";
        toggle.textContent = control.type === "password" ? "Hiện" : "Ẩn";
        toggle.setAttribute("aria-pressed", String(control.type === "text"));
      }, "btn btn-outline-secondary");
      toggle.setAttribute("aria-label", "Hiện hoặc ẩn " + label.toLowerCase()); toggle.setAttribute("aria-pressed", "false");
      group.append(control, toggle, error); wrap.append(group);
    } else wrap.append(control, error);
    form.append(wrap); fields[key] = {control, error}; return control;
  }
  function invalid(fields, key, message) {
    const f = fields[key]; if (!f) return;
    f.control.classList.add("is-invalid"); f.control.setAttribute("aria-invalid", "true"); f.error.textContent = message;
  }
  function clearErrors(fields) {
    for (const f of Object.values(fields)) { f.control.classList.remove("is-invalid"); f.control.removeAttribute("aria-invalid"); f.error.textContent = ""; }
  }
  function validate(fields) {
    for (const [key, f] of Object.entries(fields)) {
      if (f.control.disabled) continue;
      if (f.control.required && !f.control.value.trim()) invalid(fields, key, "Vui lòng nhập trường này.");
      else if (!f.control.checkValidity()) invalid(fields, key, f.control.type === "email" ? "Email không hợp lệ." : "Dữ liệu không hợp lệ.");
    }
    if (fields.phone?.control.value && !/^\+?[0-9]{9,15}$/.test(fields.phone.control.value.trim())) invalid(fields, "phone", "Điện thoại phải có từ 9 đến 15 chữ số.");
    if (fields.username && !/^[A-Za-z0-9][A-Za-z0-9._-]{2,99}$/.test(fields.username.control.value.trim())) invalid(fields, "username", "Tên đăng nhập từ 3–100 ký tự: chữ Latin, số, dấu chấm, gạch dưới hoặc gạch ngang.");
    const password = fields.password || fields.newPassword;
    if (password) {
      const value = password.control.value;
      if (value.length < 8 || value.length > 72 || new TextEncoder().encode(value).length > 72 || !value.trim()) invalid(fields, fields.password ? "password" : "newPassword", "Mật khẩu từ 8–72 ký tự, tối đa 72 byte UTF-8 và không chỉ chứa khoảng trắng.");
      if (value !== fields.confirmPassword.control.value) invalid(fields, "confirmPassword", "Xác nhận mật khẩu không khớp.");
    }
  }
  function serverErrors(fields, error) {
    for (const [key, messages] of Object.entries(error.data?.errors || {})) {
      const actual = Object.keys(fields).find(k => k.toLowerCase() === key.split(".").at(-1).toLowerCase());
      if (actual) invalid(fields, actual, [].concat(messages).join(" "));
    }
  }
  function dialog(s, title) {
    if (s.dialog) return null;
    const node = el("dialog", "account-modal"), header = el("div", "account-modal-header"), body = el("div", "account-modal-body"), heading = el("h2", "h5 mb-0", title);
    heading.id = "account-dialog-" + (++unique); node.setAttribute("aria-labelledby", heading.id);
    const abort = new AbortController(), cancel = () => abort.abort(), focus = document.activeElement;
    s.abort.signal.addEventListener("abort", cancel, {once:true});
    const d = {node, body, heading, signal:abort.signal, busy:false, closed:false};
    d.close = () => {
      if (d.closed) return; d.closed = true; abort.abort(); s.abort.signal.removeEventListener("abort", cancel);
      if (node.open) node.close(); node.remove(); if (s.dialog === d) s.dialog = null;
      if (focus?.isConnected && alive(s)) focus.focus();
    };
    const close = button("Đóng", () => { if (!d.busy) d.close(); }, "btn btn-outline-secondary btn-sm");
    d.setBusy = busy => { d.busy = busy; close.disabled = busy; };
    header.append(heading, close); node.append(header, body); s.root.append(node); s.dialog = d;
    node.addEventListener("cancel", e => { e.preventDefault(); if (!d.busy) d.close(); });
    node.addEventListener("close", d.close); body.append(el("p", "text-secondary", "Đang tải dữ liệu…")); node.showModal(); return d;
  }
  function save(s, d, form, fields, path, method, build, reload, label = "Lưu") {
    const box = el("div", "col-12"), submit = button(label, null, "btn btn-orange"); submit.type = "submit";
    form.noValidate = true; form.append(box, actions(submit));
    form.addEventListener("submit", async e => {
      e.preventDefault(); if (d.busy) return; clearErrors(fields); alert(box, ""); validate(fields);
      const payload = build();
      const first = Object.values(fields).find(f => f.control.classList.contains("is-invalid"));
      if (first || !payload) { first?.control.focus(); return; }
      const controls = [...form.querySelectorAll("input,select,textarea,button")].map(c => [c,c.disabled]);
      for (const [c] of controls) c.disabled = true; d.setBusy(true); submit.textContent = "Đang gửi…";
      try {
        const result = await window.ApiClient.request(path, {method, body:JSON.stringify(payload), signal:d.signal});
        if (!alive(s) || d.closed) return;
        d.close(); s.message = result.message || "Đã lưu tài khoản.";
        if (result.needsOperationalReview) s.message += " Tài khoản còn nhiệm vụ đang thực hiện; cần rà soát và điều phối lại.";
        await refresh(s);
      } catch (error) {
        if (!alive(s) || d.closed || error.name === "AbortError" || error.sessionExpired) return;
        serverErrors(fields, error); alert(box, error.message + (error.status === 409 && reload ? " Hãy tải lại dữ liệu trước khi thử lại." : ""));
        if (error.status === 409 && reload) box.append(button("Tải lại dữ liệu tài khoản", () => { if (!d.busy) reload(); }, "btn btn-outline-orange"));
        Object.values(fields).find(f => f.control.classList.contains("is-invalid"))?.control.focus();
      } finally {
        if (!d.closed) { d.setBusy(false); for (const [c, disabled] of controls) c.disabled = disabled; submit.textContent = label; }
      }
    });
  }
  async function lookups(s, signal) {
    const [roles, branches] = await Promise.all([read(s, "/api/v1/roles?lookupOnly=true", signal), read(s, "/api/v1/catalogs?type=BRANCHES", signal)]);
    if (!Array.isArray(roles.items) || !Array.isArray(branches.branches)) throw new Error("API danh mục vai trò/bưu cục trả dữ liệu không hợp lệ.");
    return {roles:roles.items, branches:branches.branches};
  }
  async function editor(s, id) {
    if (!can(s, "TAIKHOAN_QUANLY")) return;
    const d = dialog(s, id ? "Sửa tài khoản" : "Thêm tài khoản"); if (!d) return;
    async function load() {
      d.body.replaceChildren(el("p", "text-secondary", "Đang tải dữ liệu…"));
      try {
        const [record, options] = await Promise.all([id ? read(s, "/api/v1/accounts?id=" + id, d.signal) : null, lookups(s, d.signal)]);
        if (!alive(s) || d.closed) return;
        const form = el("form", "row g-3"), fields = {}, self = record && String(record.id) === String(s.user.accountId);
        if (record) form.append(el("p", "col-12 fw-semibold mb-0", record.username + " · " + states[record.status]));
        else {
          field(form, fields, "username", "Tên đăng nhập *", "", {required:true, max:100});
          field(form, fields, "password", "Mật khẩu *", "", {required:true, type:"password", max:72});
          field(form, fields, "confirmPassword", "Xác nhận mật khẩu *", "", {required:true, type:"password", max:72});
        }
        field(form, fields, "fullName", "Họ tên *", record?.fullName, {required:true, max:150});
        field(form, fields, "phone", "Điện thoại", record?.phone, {max:16, type:"tel"});
        field(form, fields, "email", "Email", record?.email, {max:150, type:"email"});
        const role = field(form, fields, "roleId", "Vai trò *", record?.roleId, {required:true, items:[["", "Chọn vai trò"], ...options.roles.filter(r => r.canAssign || r.id === record?.roleId).map(r => [r.id, r.name + (r.isActive ? "" : " (ngừng hoạt động)"), !r.canAssign])]});
        const branch = field(form, fields, "branchId", "Bưu cục", record?.branchId, {items:[["", "Toàn hệ thống (chỉ quản trị viên)"], ...options.branches.filter(b => b.isActive || b.id === record?.branchId).map(b => [b.id, b.name + (b.isActive ? "" : " (ngừng hoạt động)"), !b.isActive])]});
        if (self) { role.disabled = true; branch.disabled = true; form.append(el("p", "col-12 small text-secondary", "Bạn không được tự đổi vai trò hoặc bưu cục của mình.")); }
        if (record?.linkedShipperId) {
          role.disabled = true;
          form.append(el("p", "col-12 small text-secondary", "Tài khoản đã liên kết nhân viên giao hàng. Giữ vai trò SHIPPER; chỉ chuyển bưu cục khi đã kết thúc nhiệm vụ, chuyến, hoàn hàng và phân công xe."), link("Xem nhân viên giao hàng", Router.href("shipper-detail", {id:record.linkedShipperId})));
        }
        const scope = el("p", "col-12 small text-secondary mb-0");
        function rules() {
          const selected = options.roles.find(r => String(r.id) === role.value);
          branch.required = !!selected?.requiresBranch;
          branch.options[0].disabled = !!selected?.requiresBranch;
          branch.options[0].textContent = selected?.requiresBranch ? "Chọn bưu cục" : "Toàn hệ thống (chỉ quản trị viên)";
          scope.textContent = !selected ? "Chọn vai trò để xác định phạm vi bưu cục." : selected.requiresBranch ? "Vai trò này bắt buộc thuộc bưu cục đang hoạt động." : "Quản trị viên có thể thuộc bưu cục hoặc có phạm vi toàn hệ thống.";
        }
        role.addEventListener("change", rules); rules(); form.append(scope);
        const state = field(form, fields, "status", "Trạng thái", record?.status || "ACTIVE", {items:Object.entries(states)}); state.disabled = true;
        form.append(el("p", "col-12 small text-secondary", record ? "Thay đổi trạng thái và đặt lại mật khẩu bằng thao tác riêng. Đổi vai trò hoặc bưu cục sẽ thu hồi refresh token; backend kiểm tra quyền và liên kết nghiệp vụ." : "Tài khoản mới luôn ở trạng thái Đang hoạt động. Mật khẩu tối thiểu 8 ký tự, tối đa 72 byte UTF-8; hệ thống kiểm tra trùng tên đăng nhập và băm mật khẩu."));
        if (can(s, "PHANQUYEN_QUANLY") && s.user.role === "ADMIN") form.append(link("Vai trò & quyền", Router.href("roles")));
        save(s, d, form, fields, "/api/v1/accounts" + (id ? "/" + id : ""), id ? "PUT" : "POST", () => {
          const chosen = options.roles.find(r => String(r.id) === role.value);
          if (!chosen || (!role.disabled && !chosen.canAssign)) invalid(fields, "roleId", "Không được cấp vai trò này.");
          if (chosen?.requiresBranch && !branch.value) invalid(fields, "branchId", "Vai trò này bắt buộc chọn bưu cục.");
          const payload = {fullName:fields.fullName.control.value.trim(), phone:fields.phone.control.value.trim() || null, email:fields.email.control.value.trim() || null, roleId:Number(role.value), branchId:branch.value ? Number(branch.value) : null};
          if (record) payload.expectedVersion = record.version;
          else { payload.username = fields.username.control.value.trim(); payload.password = fields.password.control.value; }
          return payload;
        }, record ? load : null);
        d.body.replaceChildren(form);
      } catch (error) { if (!d.closed) failure(s, d.body, error, load); }
    }
    await load();
  }
  async function accountAction(s, id, action) {
    if (!can(s, "TAIKHOAN_QUANLY")) return;
    const d = dialog(s, actionNames[action]); if (!d) return;
    async function load() {
      try {
        const c = await read(s, "/api/v1/accounts?id=" + id, d.signal); if (!alive(s) || d.closed) return;
        const form = el("form", "row g-3"), fields = {};
        form.append(el("p", "col-12 fw-semibold", c.username + " · " + c.fullName + " · " + branchText(c)), el("div", "col-12", "Trạng thái hiện tại: " + states[c.status] + (temporary(c) ? "; khóa tạm đến " + date(c.lockedUntil) : "")));
        const descriptions = {LOCK:"Xác nhận khóa tài khoản này. Tài khoản sẽ không thể đăng nhập; refresh token bị thu hồi. Nếu còn nhiệm vụ, cần rà soát và điều phối lại.", UNLOCK:"Xác nhận mở khóa tài khoản, xóa thời điểm khóa tạm và đặt số lần đăng nhập sai về 0.", DEACTIVATE:"Xác nhận ngừng hoạt động tài khoản. Tài khoản còn nhiệm vụ, chuyến, hoàn hàng hoặc phân công xe sẽ bị từ chối; lịch sử nghiệp vụ được giữ lại.", ACTIVATE:"Xác nhận kích hoạt lại tài khoản, xóa khóa tạm và đặt số lần đăng nhập sai về 0. Vai trò và bưu cục phải còn hoạt động."};
        form.append(el("p", "col-12 text-secondary", descriptions[action]));
        field(form, fields, "reason", "Lý do *", "", {required:true, max:500, full:true, multiline:true});
        save(s, d, form, fields, "/api/v1/accounts/" + id + "/actions", "POST", () => ({action, reason:fields.reason.control.value.trim(), expectedVersion:c.version}), load, "Xác nhận " + actionNames[action].toLowerCase());
        d.body.replaceChildren(form);
      } catch (error) { if (!d.closed) failure(s, d.body, error, load); }
    }
    await load();
  }
  async function resetPassword(s, id) {
    if (!can(s, "TAIKHOAN_QUANLY") || s.user.role !== "ADMIN") return;
    const d = dialog(s, "Đặt lại mật khẩu"); if (!d) return;
    async function load() {
      try {
        const c = await read(s, "/api/v1/accounts?id=" + id, d.signal); if (!alive(s) || d.closed) return;
        const form = el("form", "row g-3"), fields = {};
        form.append(el("p", "col-12 fw-semibold", "Đặt lại mật khẩu cho " + c.username + " · " + c.fullName), el("p", "col-12 text-secondary", "Refresh token và mã khôi phục chưa dùng sẽ bị thu hồi. Access token đã cấp vẫn có thể dùng đến khi hết hạn. Thao tác này giữ trạng thái tài khoản, khóa tạm và số lần đăng nhập sai. Không nhập mật khẩu hoặc token vào lý do."));
        field(form, fields, "newPassword", "Mật khẩu mới *", "", {required:true, type:"password", max:72});
        field(form, fields, "confirmPassword", "Xác nhận mật khẩu *", "", {required:true, type:"password", max:72});
        field(form, fields, "reason", "Lý do *", "", {required:true, full:true, multiline:true, max:500});
        save(s, d, form, fields, "/api/v1/accounts/" + id + "/reset-password", "POST", () => {
          if (fields.reason.control.value.includes(fields.newPassword.control.value)) invalid(fields, "reason", "Không ghi mật khẩu vào lý do.");
          return {newPassword:fields.newPassword.control.value, reason:fields.reason.control.value.trim(), expectedVersion:c.version};
        }, load, "Xác nhận đặt lại mật khẩu"); d.body.replaceChildren(form);
      } catch (error) { if (!d.closed) failure(s, d.body, error, load); }
    }
    await load();
  }
  function rowActions(s, c, detail = false) {
    const n = actions();
    if (!detail) n.append(link("Chi tiết", Router.href("account-detail", {id:c.id}, s.filters)));
    if (!can(s, "TAIKHOAN_QUANLY")) return n;
    n.append(button("Sửa", () => editor(s, c.id)));
    if (String(c.id) === String(s.user.accountId)) return n;
    if (c.status === "ACTIVE") n.append(button("Khóa", () => accountAction(s, c.id, "LOCK")));
    if (c.status === "LOCKED" || (c.status === "ACTIVE" && temporary(c))) n.append(button("Mở khóa", () => accountAction(s, c.id, "UNLOCK")));
    if (c.status !== "INACTIVE") n.append(button("Ngừng hoạt động", () => accountAction(s, c.id, "DEACTIVATE")));
    else n.append(button("Kích hoạt lại", () => accountAction(s, c.id, "ACTIVATE")));
    if (s.user.role === "ADMIN") n.append(button("Đặt lại mật khẩu", () => resetPassword(s, c.id)));
    return n;
  }
  async function list(s) {
    s.pending?.abort(); s.pending = new AbortController(); const epoch = ++s.epoch, signal = AbortSignal.any([s.abort.signal, s.pending.signal]);
    Router.updateQuery(s.filters, s.route); s.route = Router.current() || s.route;
    s.results.replaceChildren(el("p", "account-empty", "Đang tải tài khoản…")); s.results.setAttribute("aria-busy", "true"); s.pager.replaceChildren(); alert(s.feedback, "");
    try {
      const path = "/api/v1/accounts?" + query(s.filters), data = window.ApiClient.validatePage(await read(s, path, signal), path, ["id", "roleId"]);
      if (!alive(s) || signal.aborted || epoch !== s.epoch) return;
      const pages = Math.max(1, Math.ceil(data.totalItems / data.pageSize));
      if (data.page > pages) { s.filters.page = pages; return list(s); }
      s.results.replaceChildren(data.items.length ? table(["Tên đăng nhập", "Họ tên", "Điện thoại", "Vai trò", "Bưu cục", "Trạng thái", "Đăng nhập gần nhất", "Thao tác"], data.items.map(c => [c.username, c.fullName, c.phone, c.roleName || c.role, branchText(c), status(c), date(c.lastLoginAt), rowActions(s,c)])) : el("p", "account-empty", "Không có tài khoản phù hợp với bộ lọc."));
      const prev = button("‹ Trước", () => { s.filters.page--; list(s); }), next = button("Sau ›", () => { s.filters.page++; list(s); });
      prev.disabled = data.page <= 1; next.disabled = data.page >= pages;
      const size = select([...new Set([10,20,50,100,data.pageSize])].sort((a,b) => a-b).map(n => [n,n + " dòng"]), data.pageSize); size.setAttribute("aria-label", "Số dòng mỗi trang");
      size.addEventListener("change", () => { s.filters.pageSize = Number(size.value); s.filters.page = 1; list(s); });
      s.pager.append(el("span", "text-secondary", data.totalItems + " kết quả · Trang " + data.page + " / " + pages), prev, next, size);
      if (s.message) { alert(s.feedback, s.message, "success"); s.message = ""; }
    } catch (error) { if (!signal.aborted && epoch === s.epoch) { s.results.replaceChildren(); failure(s, s.feedback, error, () => list(s)); } }
    finally { if (alive(s) && epoch === s.epoch) s.results.setAttribute("aria-busy", "false"); }
  }
  async function mountList(s) {
    const q = s.route.query; s.filters = {page:q.page || 1, pageSize:q.pageSize || 10, keyword:q.keyword || "", roleId:q.roleId || "", branchId:q.branchId || "", status:q.status || ""};
    const toolbar = actions(); toolbar.classList.add("account-toolbar");
    if (can(s, "TAIKHOAN_QUANLY")) toolbar.append(button("Thêm tài khoản", () => editor(s), "btn btn-orange"));
    toolbar.append(button("Làm mới", () => list(s), "btn btn-outline-orange"));
    if (can(s, "PHANQUYEN_QUANLY") && s.user.role === "ADMIN") toolbar.append(link("Vai trò & quyền", Router.href("roles")));
    const form = el("form", "row g-3 account-filters"), fields = {};
    field(form, fields, "keyword", "Tên đăng nhập, họ tên hoặc điện thoại", s.filters.keyword, {max:150, type:"search"});
    const role = field(form, fields, "roleId", "Vai trò", s.filters.roleId, {items:[["", "Đang tải vai trò…"]]}); role.disabled = true;
    const branch = field(form, fields, "branchId", "Bưu cục", s.filters.branchId, {items:[["", "Đang tải bưu cục…"]]}); branch.disabled = true;
    field(form, fields, "status", "Trạng thái", s.filters.status, {items:[["", "Tất cả trạng thái"], ...Object.entries(states)]});
    const submit = button("Tìm kiếm", null, "btn btn-outline-orange"); submit.type = "submit"; form.append(actions(submit));
    form.addEventListener("submit", e => {
      e.preventDefault(); for (const [key, f] of Object.entries(fields)) if (!f.control.disabled) s.filters[key] = f.control.value.trim();
      s.filters.page = 1; list(s);
    });
    for (const key of ["roleId", "branchId", "status"]) fields[key].control.addEventListener("change", () => form.requestSubmit());
    const catalogBox = el("div", "col-12"); form.append(catalogBox);
    s.feedback = el("div"); s.results = el("div", "account-results"); s.pager = el("div", "account-pagination"); s.root.append(toolbar, form, s.feedback, s.results, s.pager); list(s);
    async function loadOptions() {
      try {
        const options = await lookups(s); if (!alive(s)) return;
        role.replaceChildren(...select([["", "Tất cả vai trò"], ...options.roles.map(r => [r.id,r.name + (r.isActive ? "" : " (ngừng hoạt động)")])]).children); role.value = s.filters.roleId; role.disabled = false;
        branch.replaceChildren(...select([["", "Tất cả bưu cục / toàn hệ thống"], ...options.branches.map(b => [b.id,b.name + (b.isActive ? "" : " (ngừng hoạt động)")])]).children); branch.value = s.filters.branchId; branch.disabled = false; alert(catalogBox, "");
      } catch (error) { failure(s, catalogBox, error, loadOptions); }
    }
    loadOptions();
  }
  async function detail(s) {
    s.pending?.abort(); s.pending = new AbortController(); const epoch = ++s.epoch, signal = AbortSignal.any([s.abort.signal,s.pending.signal]);
    s.root.replaceChildren(el("p", "account-empty", "Đang tải tài khoản…"));
    try {
      const c = await read(s, "/api/v1/accounts?id=" + s.route.params.id, signal); if (!alive(s) || signal.aborted || epoch !== s.epoch) return;
      const toolbar = actions(link("Quay về danh sách", Router.href("accounts", {}, s.route.query)), button("Làm mới", () => detail(s), "btn btn-outline-orange"));
      if (can(s, "PHANQUYEN_QUANLY") && s.user.role === "ADMIN") toolbar.append(link("Vai trò & quyền", Router.href("roles")));
      const info = summary([["Tên đăng nhập",c.username],["Mã tài khoản",c.accountCode],["Họ tên",c.fullName],["Điện thoại",c.phone],["Email",c.email],["Vai trò",c.roleName || c.role],["Hoạt động vai trò",c.roleActive ? "Đang hoạt động" : "Ngừng hoạt động"],["Phạm vi bưu cục",branchText(c)],["Trạng thái tài khoản",states[c.status] || c.status],["Khóa tạm thời đến",date(c.lockedUntil)],["Số lần đăng nhập sai",c.failedLoginCount],["Đăng nhập gần nhất",date(c.lastLoginAt)],["Thời điểm tạo",date(c.createdAt)],["Cập nhật gần nhất",date(c.updatedAt)]]);
      s.feedback = el("div"); s.root.replaceChildren(toolbar, s.feedback, info, rowActions(s,c,true));
      if (c.linkedShipperId) s.root.append(link("Nhân viên giao hàng liên kết", Router.href("shipper-detail", {id:c.linkedShipperId})));
      if (s.message) { alert(s.feedback, s.message, "success"); s.message = ""; }
    } catch (error) { if (!signal.aborted && epoch === s.epoch) { s.root.replaceChildren(link("Quay về danh sách", Router.href("accounts", {}, s.route.query))); const box = el("div", "mt-3"); s.root.append(box); failure(s, box, error, () => detail(s)); } }
  }
  function refresh(s) { return s.route.mode === "detail" ? detail(s) : list(s); }
  function destroy() {
    if (!active) return; const s = active; s.dialog?.close(); s.pending?.abort(); s.abort.abort(); s.routeSignal?.removeEventListener("abort", s.onAbort); active = null;
  }
  function mount(container, user, route, context) {
    destroy(); const s = {root:el("section", "accounts-page"), user, route, permissions:context.permissions, abort:new AbortController(), epoch:0}; active = s;
    s.routeSignal = context.signal; s.onAbort = () => { if (active === s) destroy(); }; context.signal?.addEventListener("abort", s.onAbort, {once:true});
    container.replaceChildren(s.root);
    if (context.signal?.aborted) { destroy(); return; }
    if (!can(s, "TAIKHOAN_XEM")) { alert(s.root, "Bạn không có quyền xem tài khoản."); return; }
    if (route.mode === "detail") detail(s); else mountList(s);
  }
  window.AccountsPage = Object.freeze({mount, destroy});
}());
