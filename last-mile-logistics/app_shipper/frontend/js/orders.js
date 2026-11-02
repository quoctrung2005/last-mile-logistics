"use strict";

(function () {
  // Codes and labels from database/QLGiaoHangChangCuoi_SQLServer_V5 .sql.
  // Role hints reflect its seed grants. The backend checks current DB permissions on every request.
  const statuses = {
    NEW: "Mới tạo", CONFIRMED: "Đã tiếp nhận", WAITING_INBOUND: "Chờ nhập kho",
    IN_WAREHOUSE: "Đã nhập kho", WAITING_ASSIGNMENT: "Chờ phân công", ASSIGNED: "Đã phân công",
    HANDED_OVER: "Đã xuất kho / Bàn giao", EN_ROUTE_PICKUP: "Đang đến lấy hàng", PICKED_UP: "Đã lấy hàng",
    IN_DELIVERY: "Đang giao", DELIVERED: "Giao thành công", FAILED: "Giao thất bại",
    RETRY_WAITING: "Chờ giao lại", RETURNING: "Chuyển hoàn", RETURNED: "Đã hoàn hàng",
    COMPLETED: "Hoàn tất", CANCELLED: "Đã hủy"
  };
  const cancelStates = new Set(["NEW", "CONFIRMED", "WAITING_INBOUND", "IN_WAREHOUSE", "WAITING_ASSIGNMENT", "ASSIGNED"]);
  const grants = { create: ["ADMIN", "DISPATCHER"], update: ["ADMIN", "BRANCH_MANAGER", "DISPATCHER"], cancel: ["ADMIN", "BRANCH_MANAGER"] };
  const currency = new Intl.NumberFormat("vi-VN", { style: "currency", currency: "VND", maximumFractionDigits: 2 });
  const number = new Intl.NumberFormat("vi-VN", { maximumFractionDigits: 3 });
  const dates = new Intl.DateTimeFormat("vi-VN", { timeZone: "Asia/Ho_Chi_Minh", dateStyle: "short", timeStyle: "short" });
  let active = null;
  let uniqueId = 0;
  let detailFeedback = null;
  const dialogDisposers = new WeakMap();

  function text(value) { return value === null || value === undefined || value === "" ? "—" : String(value); }
  function money(value) { return value == null || !Number.isFinite(Number(value)) ? "—" : currency.format(Number(value)); }
  function weight(value) { return value == null || !Number.isFinite(Number(value)) ? "—" : number.format(Number(value)) + " kg"; }
  function date(value) {
    if (!value) return "—";
    // SQL DATETIME2 -> FOR JSON has no offset; schema explicitly stores UTC.
    const raw = String(value);
    const utc = /(?:Z|[+-]\d{2}:\d{2})$/i.test(raw) ? raw : raw + "Z";
    const parsed = new Date(utc);
    return Number.isNaN(parsed.getTime()) ? "—" : dates.format(parsed);
  }
  function el(tag, className, value) {
    const node = document.createElement(tag);
    if (className) node.className = className;
    if (value !== undefined) node.textContent = text(value);
    return node;
  }
  function button(label, callback, className) {
    const node = el("button", className || "btn btn-outline-secondary btn-sm", label);
    node.type = "button";
    if (callback) node.addEventListener("click", callback);
    return node;
  }
  function input(type, value, limits) {
    const node = el("input", "form-control");
    node.type = type;
    node.value = value == null ? "" : value;
    Object.assign(node, limits || {});
    return node;
  }
  function option(select, value, label) {
    const node = el("option", "", label);
    node.value = value;
    select.append(node);
  }
  function select(items, label, selected) {
    const node = el("select", "form-select");
    node.required = true;
    option(node, "", label);
    for (const item of items || []) option(node, item.id, item.name);
    node.value = selected == null ? "" : selected;
    return node;
  }
  function field(label, control, className) {
    const wrapper = el("div", className || "col-md-6");
    control.id = "order-field-" + (++uniqueId);
    const caption = el(control.tagName === "BUTTON" ? "span" : "label", "form-label d-block", label);
    if (control.tagName !== "BUTTON") caption.htmlFor = control.id;
    wrapper.append(caption, control);
    return wrapper;
  }
  function notice(container, message, type) {
    container.replaceChildren();
    if (message) {
      const node = el("div", "alert alert-" + (type || "danger"), message);
      node.setAttribute("role", type === "success" ? "status" : "alert");
      container.append(node);
    }
  }
  function badge(code, label) {
    const tone = ["DELIVERED", "COMPLETED"].includes(code) ? "success" : ["FAILED", "CANCELLED"].includes(code) ? "danger"
      : code === "NEW" ? "neutral" : "orange";
    return el("span", "order-status order-status-" + tone, label || statuses[code] || text(code));
  }
  function table(headers, rows) {
    const wrapper = el("div", "table-responsive");
    const node = el("table", "table orders-table align-middle mb-0");
    const head = el("thead");
    const heading = el("tr");
    for (const label of headers) { const cell = el("th", "", label); cell.scope = "col"; heading.append(cell); }
    head.append(heading);
    const body = el("tbody");
    for (const values of rows) {
      const row = el("tr");
      for (const value of values) { const cell = el("td"); cell.append(value instanceof Node ? value : document.createTextNode(text(value))); row.append(cell); }
      body.append(row);
    }
    if (!rows.length) { const row = el("tr"); const cell = el("td", "text-center text-secondary py-4", "Chưa có dữ liệu."); cell.colSpan = headers.length; row.append(cell); body.append(row); }
    node.append(head, body); wrapper.append(node); return wrapper;
  }
  function summary(pairs) {
    const grid = el("dl", "order-summary");
    for (const [label, value] of pairs) { const item = el("div"); item.append(el("dt", "", label), el("dd", "", value)); grid.append(item); }
    return grid;
  }
  function section(title, ...children) { const node = el("section", "order-section"); node.append(el("h3", "", title), ...children); return node; }
  function pagination(container, page, pageSize, totalItems, onPage, noun) {
    const pages = Math.min(100000, Math.max(1, Math.ceil(totalItems / pageSize)));
    const previous = button("‹ Trước", () => onPage(page - 1)); previous.disabled = page <= 1;
    const next = button("Sau ›", () => onPage(page + 1)); next.disabled = page >= pages;
    container.replaceChildren(el("span", "text-secondary", number.format(totalItems) + " " + (noun || "dòng") + " · Trang " + page + " / " + pages), previous, next);
  }
  function permitted(s, action) {
    const code = { create: "DONHANG_TAO", update: "DONHANG_CAPNHAT", cancel: "DONHANG_HUY" }[action];
    return s.permissions?.known ? s.permissions.codes.has(code) : grants[action].includes(s.user.role);
  }
  function inScope(s, order) { return s.user.role === "ADMIN" || Number(s.user.branchId) === Number(order.branchId); }
  function missingEditFields(order) {
    const missing = ["branchId", "senderId", "receiverId", "serviceId"].filter(key => !Number.isSafeInteger(order[key]) || order[key] <= 0);
    if (typeof order.version !== "string" || !/^[A-Za-z0-9+/]{11}=$/.test(order.version)) missing.push("version");
    return missing;
  }
  function needsAddressSelection(order) {
    return order.requiresAddressSelection === true || ["pickupAddressId", "deliveryAddressId"].some(key => !Number.isSafeInteger(order[key]) || order[key] <= 0);
  }
  function missingEditMessage(missing) {
    const labels = { branchId: "bưu cục", senderId: "người gửi", receiverId: "người nhận", serviceId: "dịch vụ", version: "phiên bản dữ liệu" };
    return "Chưa tải đủ dữ liệu để sửa đơn: " + missing.map(key => labels[key] || key).join(", ") + ". Hãy tải lại chi tiết.";
  }
  async function read(s, path, signal) {
    return window.ApiClient.request(path, { signal: signal ? AbortSignal.any([s.abort.signal, signal]) : s.abort.signal });
  }
  function dialog(s, title, wide) {
    const node = el("dialog", "orders-dialog" + (wide ? " orders-dialog-wide" : ""));
    const header = el("div", "orders-dialog-header");
    const heading = el("h2", "", title);
    heading.id = "order-dialog-title-" + (++uniqueId);
    node.setAttribute("aria-labelledby", heading.id);
    let closed = false;
    const controller = new AbortController();
    const closeHandlers = new Set();
    function dispose() {
      if (closed) return;
      closed = true; controller.abort(); s.dialogs.delete(node); node.remove(); dialogDisposers.delete(node);
      for (const callback of closeHandlers) callback();
      closeHandlers.clear();
    }
    function closeDialog() { node.close(); dispose(); }
    const close = button("Đóng", closeDialog);
    header.append(heading, close);
    const body = el("div", "orders-dialog-body");
    node.append(header, body);
    document.body.append(node);
    s.dialogs.add(node);
    dialogDisposers.set(node, dispose);
    let busy = false;
    node.addEventListener("cancel", event => { event.preventDefault(); if (!busy) closeDialog(); });
    node.addEventListener("close", dispose);
    node.showModal();
    return { node, body, signal: AbortSignal.any([s.abort.signal, controller.signal]), close: closeDialog, onClose(callback) { if (closed) callback(); else closeHandlers.add(callback); },
      setBusy(value) { busy = value; close.disabled = value; node.setAttribute("aria-busy", String(value)); } };
  }
  function closeDialogs(s) {
    for (const node of [...s.dialogs]) { node.close(); dialogDisposers.get(node)?.(); }
  }

  function routeView(s, title, backHash) {
    const detail = s.route?.name === "order-detail";
    const node = el("section", detail ? "order-detail" : "orders-card");
    const header = el("div", detail ? "order-detail-navigation" : "orders-toolbar"), body = el("div", "orders-route-body");
    const back = el("a", "btn btn-outline-secondary", "Quay lại"); back.href = backHash;
    if (detail) {
      const breadcrumb = el("nav", "order-breadcrumb"); breadcrumb.setAttribute("aria-label", "Đường dẫn đơn hàng");
      const parent = window.Router.parse(backHash), link = el("a", "", parent.label); link.href = backHash;
      breadcrumb.append(link, el("span", "", "/"), el("span", "", title)); header.append(breadcrumb, back);
    } else header.append(el("h2", "", title), back);
    node.append(header, body); s.container.replaceChildren(node);
    return { node, body, close: () => window.Router.navigate(backHash), setBusy(value) {
      node.setAttribute("aria-busy", String(value)); back.classList.toggle("disabled", value);
      back.setAttribute("aria-disabled", String(value));
    } };
  }
  function navigateDetail(id, message, query = {}, replace = false) {
    detailFeedback = message ? { id: Number(id), message } : null;
    window.Router.navigate(window.Router.href("order-detail", { id }, query), { replace, force: true });
  }
  function orderQuery(s) { return s.route?.pageId === "orders" ? window.Router.current()?.query || s.route.query : {}; }

  function destroy() {
    if (!active) return;
    active.dead = true;
    clearTimeout(active.searchTimer);
    active.abort.abort();
    if (active.listAbort) active.listAbort.abort();
    closeDialogs(active);
    active = null;
  }
  function mount(container, user, route, context) {
    destroy();
    const query = route.query;
    const s = { container, user, route, permissions: context.permissions, page: query.page || 1, pageSize: query.pageSize || 10,
      keyword: query.keyword || "", status: query.status || "", abort: new AbortController(), dialogs: new Set(), dead: false, sequence: 0 };
    active = s;
    container.replaceChildren();
    s.returnHref = query.returnTo || window.Router.href("orders", {}, query);
    if (route.mode === "create") { openForm(s); return; }
    if (route.mode === "detail") {
      const message = detailFeedback?.id === route.params.id ? detailFeedback.message : ""; detailFeedback = null;
      openDetail(s, route.params.id, message); return;
    }
    if (route.mode === "edit") { openEditRoute(s, route.params.id); return; }
    const card = el("section", "orders-card");
    const toolbar = el("div", "orders-toolbar");
    const intro = el("div"); intro.append(el("h2", "", "Quản lý đơn hàng"), el("p", "text-secondary mb-0", "Tra cứu mã đơn, mã vận đơn và xử lý đơn trong phạm vi bưu cục."));
    const actions = el("div", "order-actions");
    actions.append(button("Tải lại", () => loadList(s)));
    if (permitted(s, "create")) actions.append(button("+ Tạo đơn", () => window.Router.navigate(window.Router.href("order-create", {}, orderQuery(s))), "btn btn-orange"));
    toolbar.append(intro, actions);
    const filters = el("form", "row g-3 orders-filters");
    const keyword = input("search", s.keyword, { maxLength: 100, placeholder: "Mã đơn hoặc mã vận đơn" });
    const status = select(Object.entries(statuses).map(([id, name]) => ({ id, name })), "Tất cả trạng thái"); status.required = false;
    status.value = s.status;
    const size = select([...new Set([s.pageSize, 10, 20, 50, 100])].sort((a, b) => a - b).map(id => ({ id, name: id + " đơn / trang" })), "Số dòng", s.pageSize);
    const search = button("Tìm kiếm", null, "btn btn-orange w-100"); search.type = "submit";
    filters.append(field("Tìm đơn", keyword, "col-lg-5 col-md-6"), field("Trạng thái", status, "col-lg-3 col-md-6"), field("Số dòng", size, "col-lg-2 col-md-6"), field("Tra cứu", search, "col-lg-2 col-md-6"));
    filters.addEventListener("submit", event => { event.preventDefault(); s.keyword = keyword.value.trim(); s.page = 1; loadList(s); });
    keyword.addEventListener("input", () => {
      s.keyword = keyword.value.trim(); s.page = 1;
      if (s.listAbort) s.listAbort.abort();
      s.sequence++; s.pager.replaceChildren();
      clearTimeout(s.searchTimer); s.searchTimer = setTimeout(() => loadList(s), 300);
    });
    // Native search clear should immediately restore all results.
    keyword.addEventListener("search", () => { s.keyword = keyword.value.trim(); s.page = 1; loadList(s); });
    status.addEventListener("change", () => { s.status = status.value; s.keyword = keyword.value.trim(); s.page = 1; loadList(s); });
    size.addEventListener("change", () => { s.pageSize = Number(size.value); s.keyword = keyword.value.trim(); s.page = 1; loadList(s); });
    s.alert = el("div", "orders-message");
    s.list = el("div");
    s.pager = el("nav", "orders-pagination"); s.pager.setAttribute("aria-label", "Phân trang đơn hàng");
    card.append(toolbar, filters, s.alert, s.list, s.pager); container.append(card);
    loadList(s);
  }
  async function loadList(s) {
    if (s.dead || !s.list) return;
    window.Router.updateQuery({ page: s.page, pageSize: s.pageSize, keyword: s.keyword, status: s.status }, s.route);
    clearTimeout(s.searchTimer);
    if (s.listAbort) s.listAbort.abort();
    const controller = new AbortController(); s.listAbort = controller;
    const sequence = ++s.sequence;
    s.list.setAttribute("aria-busy", "true");
    s.list.replaceChildren(el("p", "orders-empty", "Đang tải danh sách đơn hàng…"));
    s.pager.replaceChildren(); notice(s.alert, "");
    const query = new URLSearchParams({ page: s.page, pageSize: s.pageSize });
    if (s.keyword) query.set("keyword", s.keyword);
    if (s.status) query.set("status", s.status);
    try {
      const result = await read(s, "/api/v1/orders?" + query, controller.signal);
      if (s.dead || sequence !== s.sequence) return;
      window.ApiClient.validatePage(result, "/api/v1/orders", ["id"]);
      const pages = Math.min(100000, Math.max(1, Math.ceil(result.totalItems / s.pageSize)));
      if (s.page > pages) { s.page = pages; await loadList(s); return; }
      if (!result.items.length) s.list.replaceChildren(el("p", "orders-empty", "Không có đơn hàng phù hợp. Hãy đổi từ khóa hoặc bộ lọc."));
      else s.list.replaceChildren(table(["Mã đơn", "Mã vận đơn", "Bưu cục", "Người gửi", "Người nhận", "Trạng thái", "Khối lượng", "COD", "Phí", "Ngày tạo (VN)", "Thao tác"], result.items.map(order => [
        button(text(order.orderCode), () => navigateDetail(order.id, "", orderQuery(s)), "btn btn-link order-code p-0"), order.trackingNumber, order.branchName,
        order.senderName, order.receiverName, badge(order.status, order.statusName), weight(order.weightKg), money(order.codAmount), money(order.shippingFee), date(order.createdAt),
        button("Chi tiết", () => navigateDetail(order.id, "", orderQuery(s)))
      ])));
      pagination(s.pager, s.page, s.pageSize, result.totalItems, page => { s.page = page; loadList(s); }, "đơn");
    } catch (error) {
      if (s.dead || sequence !== s.sequence || error.name === "AbortError") return;
      s.list.replaceChildren(el("p", "orders-empty", "Chưa tải được danh sách."));
      notice(s.alert, error.message);
      s.pager.append(button("Thử lại", () => loadList(s)));
    } finally { if (!s.dead && sequence === s.sequence) s.list.setAttribute("aria-busy", "false"); }
  }

  async function openDetail(s, id, message) {
    if (s.dead) return;
    const view = routeView(s, "Chi tiết đơn hàng", s.returnHref);
    async function reload() {
      if (s.dead) return;
      s.detailAbort?.abort(); const controller = new AbortController(); s.detailAbort = controller;
      const sequence = ++s.sequence;
      view.node.setAttribute("aria-busy", "true");
      view.body.replaceChildren(el("p", "text-secondary", "Đang tải chi tiết…"));
      try {
        const order = await read(s, "/api/v1/orders/" + encodeURIComponent(id), controller.signal);
        if (s.dead || controller.signal.aborted || sequence !== s.sequence || !view.node.isConnected) return;
        if (!order || Number(order.id) !== Number(id)) throw new Error("API chi tiết trả dữ liệu không hợp lệ.");
        renderDetail(s, view, order, reload, message);
      } catch (error) {
        if (s.dead || controller.signal.aborted || sequence !== s.sequence || !view.node.isConnected || error.name === "AbortError") return;
        const errorBox = el("div"); notice(errorBox, error.message);
        view.body.replaceChildren(errorBox, button("Tải lại chi tiết", reload));
      } finally { if (!s.dead && sequence === s.sequence) view.node.setAttribute("aria-busy", "false"); }
    }
    await reload();
  }
  function renderDetail(s, view, order, reload, message) {
    const body = view.body; body.replaceChildren();
    const feedback = el("div"); if (message) notice(feedback, message, "success");
    const top = el("div", "order-detail-hero");
    const identity = el("div", "order-detail-identity"); identity.append(el("h2", "order-detail-code", order.orderCode), el("p", "order-tracking", "Mã vận đơn: " + text(order.trackingNumber)));
    const actions = el("div", "order-actions order-detail-actions");
    const actionButton = (label, callback, style) => button(label, () => { if (!s.dead && !s.dialogs.size) callback(); }, style);
    actions.append(actionButton("Làm mới", reload));
    const scoped = !s.readOnly && inScope(s, order);
    const missing = missingEditFields(order);
    if (scoped && order.status === "NEW" && permitted(s, "update")) {
      const edit = actionButton("Sửa", () => window.Router.navigate(window.Router.href("order-edit", { id: order.id }, orderQuery(s))), "btn btn-orange btn-sm");
      edit.disabled = missing.length > 0;
      edit.title = missing.length ? "API chi tiết thiếu: " + missing.join(", ") : "Sửa đơn mới tạo";
      actions.append(edit);
    }
    if (scoped && permitted(s, "create")) actions.append(actionButton("Báo giá", () => openQuote(s, order)));
    if (scoped && order.status === "NEW" && permitted(s, "update")) actions.append(actionButton("Xác nhận", () => openAction(s, view, order, "confirm"), "btn btn-outline-orange btn-sm"));
    if (scoped && cancelStates.has(order.status) && permitted(s, "cancel")) actions.append(actionButton("Hủy đơn", () => openAction(s, view, order, "cancel"), "btn btn-outline-danger btn-sm"));
    top.append(identity, badge(order.status, order.statusName)); body.append(feedback, top, actions);
    if (scoped && permitted(s, "update") && order.status === "NEW" && missing.length) {
      const warning = el("div", "alert alert-warning");
      warning.append(el("p", "mb-2", missingEditMessage(missing)), button("Tải lại chi tiết", reload)); body.append(warning);
    }
    else if (scoped && permitted(s, "update") && order.status === "NEW" && needsAddressSelection(order)) body.append(el("p", "alert alert-info", "Khi sửa đơn, cần chọn lại địa chỉ lấy / giao từ danh sách địa chỉ của khách hàng."));
    const grid = el("div", "order-detail-grid");
    const general = section("Thông tin chung", summary([
      ["Bưu cục", order.branchName], ["Dịch vụ", order.serviceName], ["Ưu tiên (1–5)", order.priority], ["Khối lượng", weight(order.weightKg)],
      ["Ngày tạo (giờ VN)", date(order.createdAt)], ["Cập nhật (giờ VN)", date(order.updatedAt)], ["Dự kiến giao (giờ VN)", date(order.expectedDeliveryAt)]
    ]), el("p", "order-note", "Ghi chú: " + text(order.notes)));
    const finance = section("Phí và COD", summary([
      ["Phí vận chuyển", money(order.shippingFee)], ["Thu hộ COD", money(order.codAmount)], ["Giá trị khai báo", money(order.declaredValue)]
    ]), table(["Khoản phí", "Số tiền", "Mô tả"], (order.fees || []).map(fee => [
      ({ SHIPPING: "Phí vận chuyển", RETURN: "Phí chuyển hoàn", SURCHARGE: "Phụ phí", DISCOUNT: "Giảm giá", OTHER: "Phí khác" })[fee.type] || fee.type,
      money(fee.amount), fee.description
    ])));
    grid.append(general, finance);
    for (const type of ["PICKUP", "DELIVERY"]) {
      const point = (order.deliveryPoints || []).find(item => item.type === type);
      const contact = section(type === "PICKUP" ? "Người gửi · Điểm lấy hàng" : "Người nhận · Điểm giao hàng", summary([
        [type === "PICKUP" ? "Người gửi" : "Người nhận", type === "PICKUP" ? order.senderName : order.receiverName],
        ["Người liên hệ", point?.contactName], ["Điện thoại", point?.phone]
      ]));
      contact.append(point ? el("p", "order-address", point.address) : el("p", "text-secondary", "Chưa có điểm giao nhận."));
      if (point?.notes) contact.append(el("p", "order-note", "Ghi chú: " + point.notes));
      grid.append(contact);
    }
    const goods = section("Hàng hóa", table(["Tên hàng", "Loại", "SL", "Kg / đơn vị", "Giá trị", "Dễ vỡ", "Kích thước (cm)", "Ghi chú"], (order.items || []).map(item => [
      item.name, item.type, item.quantity, weight(item.unitWeightKg), money(item.value), item.fragile ? "Có" : "Không",
      [item.lengthCm, item.widthCm, item.heightCm].map(text).join(" × "), item.notes
    ]))); goods.classList.add("order-detail-wide"); grid.append(goods);
    const timeline = el("ol", "order-timeline");
    for (const history of order.statusHistory || []) {
      const entry = el("li"); const title = el("div", "order-history-title");
      const time = el("time", "", date(history.changedAt));
      title.append(badge(history.newStatus), time); entry.append(title);
      entry.append(el("p", "order-history-meta", "Người thực hiện: " + text(history.changedByName || (history.changedBy != null ? "Tài khoản #" + history.changedBy : null))));
      if (history.previousStatus) entry.append(el("p", "order-history-meta", "Từ: " + (statuses[history.previousStatus] || history.previousStatus)));
      if (history.reason) entry.append(el("p", "order-history-reason", history.reason));
      timeline.append(entry);
    }
    const historyCard = section("Lịch sử trạng thái", timeline.children.length ? timeline : el("p", "text-secondary mb-0", "Chưa có lịch sử trạng thái."));
    historyCard.classList.add("order-detail-wide"); grid.append(historyCard); body.append(grid);
    const internal = el("details", "order-internal"); internal.append(el("summary", "", "Dữ liệu kỹ thuật"), summary([
      ["ID", order.id], ["Version", order.version || "API chi tiết chưa trả version"]
    ])); body.append(internal);
    for (const point of order.deliveryPoints || []) internal.append(section(point.type === "PICKUP" ? "Tọa độ lấy hàng" : "Tọa độ giao hàng", summary([["ID điểm", point.id], ["Vĩ độ", point.latitude], ["Kinh độ", point.longitude]])));
    if (order.statusHistory?.length) internal.append(section("Nguồn cập nhật", summary(order.statusHistory.map(history => [date(history.changedAt), history.source]))));
  }

  function customerPicker(s, title, initialId, initialAddressId, editing = false, snapshot = null) {
    const wrapper = el("fieldset", "order-customer"); wrapper.append(el("legend", "", title));
    const lookup = el("div", "input-group mb-2");
    const keyword = input("search", "", { maxLength: 100, placeholder: "Tên, điện thoại hoặc mã khách hàng" });
    keyword.setAttribute("aria-label", "Tìm " + title.toLowerCase());
    const go = button("Tìm", () => { page = 1; loadCustomers(); }); lookup.append(keyword, go);
    const customers = select([], "Chọn khách hàng");
    const addresses = select([], "Chọn khách hàng trước"); addresses.disabled = true;
    const preview = el("p", "order-address-preview text-secondary");
    const errorBox = el("div");
    const pager = el("div", "order-actions my-2");
    let page = 1, selected = null, addressList = [], customerSequence = 0, addressSequence = 0;
    wrapper.append(lookup, field("Khách hàng *", customers, "mb-2"), pager, field("Địa chỉ *", addresses, "mb-2"), preview, errorBox);
    if (editing && snapshot) wrapper.insertBefore(el("p", "text-secondary order-address-preview", "Địa chỉ trên đơn hiện tại: " + [snapshot.contactName, snapshot.phone, snapshot.address].filter(Boolean).join(" · ")), lookup);
    keyword.addEventListener("keydown", event => { if (event.key === "Enter") { event.preventDefault(); page = 1; loadCustomers(); } });
    function fillCustomers(items) {
      customers.replaceChildren(); option(customers, "", "Chọn khách hàng");
      const all = selected && !items.some(item => item.id === selected.id) ? [selected, ...items] : items;
      for (const item of all) option(customers, item.id, item.fullName + " · " + text(item.phone) + " · " + text(item.customerCode));
      if (selected) customers.value = selected.id;
      customers._records = all;
    }
    async function loadCustomers() {
      const seq = ++customerSequence;
      notice(errorBox, ""); go.disabled = true;
      pager.replaceChildren(el("span", "text-secondary", "Đang tải khách hàng…"));
      try {
        const query = new URLSearchParams({ keyword: keyword.value.trim(), page, pageSize: 20 });
        const result = await read(s, "/api/v1/customers?" + query);
        if (s.dead || seq !== customerSequence || !wrapper.isConnected) return;
        fillCustomers(result.items || []);
        const prev = button("‹", () => { page--; loadCustomers(); }); prev.setAttribute("aria-label", "Khách hàng: trang trước"); prev.disabled = page <= 1;
        const next = button("›", () => { page++; loadCustomers(); }); next.setAttribute("aria-label", "Khách hàng: trang sau"); next.disabled = page * 20 >= result.totalItems || page >= 100000;
        pager.replaceChildren(prev, el("span", "text-secondary", "Trang " + page + " · " + number.format(result.totalItems) + " khách"), next);
        if (!result.items?.length) notice(errorBox, "Không có khách hàng phù hợp.", "warning");
      } catch (error) {
        if (s.dead || seq !== customerSequence || !wrapper.isConnected) return;
        notice(errorBox, error.message); pager.replaceChildren(button("Tải lại khách hàng", loadCustomers));
      } finally { if (seq === customerSequence) go.disabled = false; }
    }
    function showAddress() {
      const address = addressList.find(item => String(item.id) === addresses.value);
      preview.textContent = address ? [address.contactName, address.phone, address.address].map(text).join(" · ") : "Chọn địa chỉ lấy / giao của khách hàng này.";
    }
    async function loadAddresses(id, addressId, requireSelection = false) {
      const seq = ++addressSequence;
      addressList = []; addresses.disabled = true; addresses.replaceChildren(); option(addresses, "", "Đang tải địa chỉ…"); preview.textContent = "";
      notice(errorBox, "");
      try {
        const result = await read(s, "/api/v1/customers/" + encodeURIComponent(id) + "/addresses");
        if (s.dead || seq !== addressSequence || !wrapper.isConnected) return;
        addressList = result.addresses || [];
        addresses.replaceChildren(); option(addresses, "", "Chọn địa chỉ");
        for (const address of addressList) option(addresses, address.id, (address.label ? address.label + " · " : "") + text(address.address));
        addresses.disabled = !addressList.length;
        const preferred = requireSelection ? null : addressId == null ? addressList.find(item => item.isDefault)?.id : addressId;
        addresses.value = preferred == null ? "" : preferred;
        if (!addressList.length) notice(errorBox, "Khách hàng chưa có địa chỉ đang hoạt động. Cần bổ sung địa chỉ trước khi tạo đơn.", "warning");
        else if (addressId != null && !addresses.value) notice(errorBox, "Địa chỉ cũ không còn hoạt động. Hãy chọn địa chỉ khác.", "warning");
        else if (requireSelection) notice(errorBox, "Không xác định được địa chỉ cũ. Hãy chọn địa chỉ lấy / giao trước khi lưu thay đổi.", "warning");
        showAddress();
      } catch (error) {
        if (s.dead || seq !== addressSequence || !wrapper.isConnected) return;
        addresses.replaceChildren(); option(addresses, "", "Chưa tải được địa chỉ"); notice(errorBox, error.message);
        errorBox.append(button("Tải lại địa chỉ", () => loadAddresses(id, addressId, requireSelection)));
      }
    }
    customers.addEventListener("change", () => {
      selected = customers._records?.find(item => String(item.id) === customers.value) || null;
      if (selected) loadAddresses(selected.id);
      else { addressSequence++; addressList = []; addresses.replaceChildren(); option(addresses, "", "Chọn khách hàng trước"); addresses.disabled = true; preview.textContent = ""; }
    });
    addresses.addEventListener("change", showAddress);
    return { wrapper, async start() {
      if (initialId != null) {
        try {
          const customer = await read(s, "/api/v1/customers/" + initialId);
          if (s.dead || !wrapper.isConnected) return;
          if (!customer || Number(customer.id) !== Number(initialId) || customer.isActive !== true) throw new Error("Khách hàng của đơn không còn hợp lệ hoặc đã ngừng hoạt động. Hãy chọn khách hàng khác.");
          selected = customer;
          fillCustomers([selected]); await loadAddresses(initialId, initialAddressId, editing && !Number.isSafeInteger(initialAddressId));
        } catch (error) { if (s.dead || error.name === "AbortError" || !wrapper.isConnected) return; notice(errorBox, error.message); }
      }
      await loadCustomers();
    }, value() {
      if (!selected || !customers.value || !addresses.value || addresses.disabled) throw new Error("Hãy chọn khách hàng và địa chỉ hợp lệ cho " + title.toLowerCase() + ".");
      return { customerId: Number(customers.value), addressId: Number(addresses.value) };
    } };
  }

  async function openEditRoute(s, id) {
    const view = routeView(s, "Sửa đơn hàng", window.Router.href("order-detail", { id }, orderQuery(s)));
    view.body.append(el("p", "text-secondary", "Đang tải dữ liệu sửa…"));
    try {
      const order = await read(s, "/api/v1/orders/" + id);
      if (s.dead || !view.node.isConnected) return;
      if (!order || Number(order.id) !== id) throw new Error("API chi tiết trả dữ liệu không hợp lệ.");
      if (!inScope(s, order) || !permitted(s, "update")) { notice(view.body, "Không có quyền sửa đơn này."); return; }
      const missing = missingEditFields(order);
      if (order.status !== "NEW" || missing.length) {
        notice(view.body, order.status !== "NEW" ? "Chỉ sửa được đơn ở trạng thái mới tạo." : missingEditMessage(missing), "warning"); return;
      }
      await openForm(s, order);
    } catch (error) {
      if (s.dead || error.name === "AbortError") return;
      notice(view.body, error.message); view.body.append(button("Thử lại", () => openEditRoute(s, id)));
    }
  }
  async function openForm(s, existing) {
    if (s.dead) return;
    if (existing && (existing.status !== "NEW" || !permitted(s, "update") || !inScope(s, existing) || missingEditFields(existing).length)) return;
    const view = routeView(s, existing ? "Sửa đơn " + text(existing.orderCode) : "Tạo đơn hàng",
      existing ? window.Router.href("order-detail", { id: existing.id }, orderQuery(s)) : s.returnHref);
    const errorBox = el("div"); view.body.append(errorBox, el("p", "text-secondary", "Đang tải bưu cục và dịch vụ…"));
    let options;
    try { options = await read(s, "/api/v1/order-form/options"); }
    catch (error) {
      if (!s.dead && view.node.isConnected) { view.body.replaceChildren(errorBox); notice(errorBox, error.message); view.body.append(button("Thử lại", () => openForm(s, existing))); }
      return;
    }
    if (s.dead || !view.node.isConnected) return;
    const form = el("form", "order-form"); form.noValidate = true;
    const fields = el("fieldset");
    const branch = select(options.branches, "Chọn bưu cục", existing?.branchId || (options.branches.length === 1 ? options.branches[0].id : null));
    if (existing?.warehouseId != null) branch.disabled = true;
    const service = select(options.services, "Chọn dịch vụ", existing?.serviceId);
    const priority = input("number", existing?.priority ?? 3, { required: true, min: "1", max: "5", step: "1" });
    const cod = input("number", existing?.codAmount ?? 0, { required: true, min: "0", max: "1000000000000", step: "0.01" });
    const declared = input("number", existing?.declaredValue ?? 0, { required: true, min: "0", max: "1000000000000", step: "0.01" });
    const notes = el("textarea", "form-control"); notes.rows = 2; notes.maxLength = 1000; notes.value = existing?.notes || "";
    const general = el("div", "row g-3"); general.append(field("Bưu cục *", branch), field("Dịch vụ *", service), field("Độ ưu tiên (1–5) *", priority, "col-md-4"), field("COD (VND) *", cod, "col-md-4"), field("Giá trị khai báo (VND) *", declared, "col-md-4"), field("Ghi chú", notes, "col-12"));
    const sender = customerPicker(s, "Người gửi / điểm lấy", existing?.senderId, existing?.pickupAddressId, Boolean(existing), existing?.deliveryPoints?.find(point => point.type === "PICKUP"));
    const receiver = customerPicker(s, "Người nhận / điểm giao", existing?.receiverId, existing?.deliveryAddressId, Boolean(existing), existing?.deliveryPoints?.find(point => point.type === "DELIVERY"));
    const parties = el("div", "order-points"); parties.append(sender.wrapper, receiver.wrapper);
    const items = el("div", "order-item-list");
    const itemRows = [];
    const totalLabel = el("strong", "order-weight-total");
    const quoteResult = el("div");
    const add = button("+ Thêm hàng", () => addItem(), "btn btn-outline-orange");
    let quoted = false;
    function clearQuote() { if (quoted) { notice(quoteResult, "Dữ liệu đã thay đổi. Hãy báo giá lại.", "warning"); quoted = false; } }
    function totalWeight() { return itemRows.reduce((sum, row) => sum + Number(row.quantity.value) * Number(row.unitWeightKg.value), 0); }
    function updateWeight() { totalLabel.textContent = "Tổng khối lượng tham khảo: " + weight(totalWeight()); add.disabled = itemRows.length >= 100; clearQuote(); }
    function addItem(item) {
      if (itemRows.length >= 100) return;
      const row = { node: el("fieldset", "order-item"), name: input("text", item?.name, { required: true, maxLength: 200 }),
        type: input("text", item?.type, { maxLength: 100 }), quantity: input("number", item?.quantity ?? 1, { required: true, min: "1", max: "100000", step: "1" }),
        unitWeightKg: input("number", item?.unitWeightKg ?? "", { required: true, min: "0.001", max: "1000000", step: "0.001" }),
        value: input("number", item?.value ?? 0, { required: true, min: "0", max: "1000000000000", step: "0.01" }),
        fragile: input("checkbox", ""), notes: input("text", item?.notes, { maxLength: 500 }) };
      row.fragile.className = "form-check-input"; row.fragile.checked = Boolean(item?.fragile);
      const legend = el("legend", "", "Hàng hóa");
      const grid = el("div", "row g-3"); grid.append(field("Tên hàng *", row.name), field("Loại hàng", row.type), field("Số lượng *", row.quantity, "col-md-4"), field("Kg / đơn vị *", row.unitWeightKg, "col-md-4"), field("Giá trị hàng (VND) *", row.value, "col-md-4"), field("Ghi chú hàng", row.notes, "col-md-9"), field("Dễ vỡ", row.fragile, "col-md-3"));
      const remove = button("Xóa hàng", () => { itemRows.splice(itemRows.indexOf(row), 1); row.node.remove(); renumber(); updateWeight(); }, "btn btn-outline-danger btn-sm mt-3");
      row.node.append(legend, grid, remove); items.append(row.node); itemRows.push(row); renumber(); updateWeight();
    }
    function renumber() { itemRows.forEach((row, index) => { row.node.querySelector("legend").textContent = "Hàng " + (index + 1); }); }
    function payload() {
      for (const row of itemRows) row.name.setCustomValidity(row.name.value.trim() ? "" : "Tên hàng không được trống.");
      if (!form.reportValidity()) throw new Error("Hãy kiểm tra các trường bắt buộc và giới hạn số lượng, khối lượng, giá trị.");
      if (!itemRows.length) throw new Error("Đơn cần ít nhất 1 dòng hàng (tối đa 100).");
      if (!Number.isFinite(totalWeight()) || totalWeight() > 999999999.999) throw new Error("Tổng khối lượng vượt giới hạn 999.999.999,999 kg.");
      const from = sender.value(), to = receiver.value();
      const result = { branchId: Number(branch.value), serviceId: Number(service.value), senderId: from.customerId, receiverId: to.customerId,
        pickupAddressId: from.addressId, deliveryAddressId: to.addressId, priority: Number(priority.value), codAmount: Number(cod.value), declaredValue: Number(declared.value), notes: notes.value.trim() || null,
        items: itemRows.map(row => ({ name: row.name.value.trim(), type: row.type.value.trim() || null, quantity: Number(row.quantity.value), unitWeightKg: Number(row.unitWeightKg.value), value: Number(row.value.value), fragile: row.fragile.checked, notes: row.notes.value.trim() || null })) };
      if (existing) result.expectedVersion = existing.version;
      return result;
    }
    const distance = input("number", "", { min: "0", max: "1000000", step: "0.01" });
    const quote = button("Lấy báo giá", async () => {
      notice(errorBox, "");
      try {
        const data = payload(); const km = distanceValue(distance);
        const kg = totalWeight(); if (kg > 1000000) throw new Error("API báo giá chỉ hỗ trợ khối lượng tối đa 1.000.000 kg.");
        fields.disabled = true; view.setBusy(true);
        const result = await window.ApiClient.request("/api/v1/shipping-fees/quote", { method: "POST", signal: s.abort.signal, body: JSON.stringify({ branchId: data.branchId, serviceId: data.serviceId, distanceKm: km, weightKg: Number(kg.toFixed(3)) }) });
        if (s.dead || !view.node.isConnected) return;
        quoteResult.replaceChildren(quoteSummary(result)); quoted = true;
      } catch (error) { notice(errorBox, error.message); }
      finally { fields.disabled = false; view.setBusy(false); }
    });
    const quoteFields = el("div", "row g-3 align-items-end"); quoteFields.append(field("Khoảng cách nhập thủ công (km)", distance), field("Phí tham khảo", quote));
    const footer = el("div", "order-actions mt-4");
    const submit = button(existing ? "Lưu thay đổi" : "Tạo đơn", null, "btn btn-orange"); submit.type = "submit";
    footer.append(submit, button("Đóng", () => view.close()));
    fields.append(section("Thông tin chung", general), parties, section("Danh sách hàng", items, el("div", "order-actions mt-3")),
      ...(permitted(s, "create") ? [section("Báo giá tham khảo", el("p", "text-secondary", "Khoảng cách do bạn nhập; chưa tích hợp tính đường đi. Phí chính thức được backend tính khi xác nhận đơn."), quoteFields, quoteResult)] : []), footer);
    fields.querySelector(".order-section .order-actions").append(add, totalLabel);
    form.append(fields); view.body.replaceChildren(errorBox, form);
    (existing?.items || [{}]).forEach(addItem);
    fields.addEventListener("input", event => {
      if (event.target.type === "text") event.target.setCustomValidity("");
      updateWeight();
    });
    fields.addEventListener("change", clearQuote);
    let submitting = false, conflicted = false, initializing = true;
    form.addEventListener("submit", async event => {
      event.preventDefault(); if (initializing || submitting || conflicted) return;
      notice(errorBox, "");
      let data;
      try { data = payload(); } catch (error) { notice(errorBox, error.message); return; }
      submitting = true; fields.disabled = true; view.setBusy(true); submit.textContent = "Đang lưu…";
      try {
        const result = await window.ApiClient.request("/api/v1/orders" + (existing ? "/" + existing.id : ""), { method: existing ? "PUT" : "POST", signal: s.abort.signal, body: JSON.stringify(data) });
        if (s.dead || !view.node.isConnected) return;
        navigateDetail(result.id, result.message || "Đã lưu đơn thành công.", orderQuery(s), true);
      } catch (error) {
        if (s.dead || !view.node.isConnected) return;
        notice(errorBox, error.message);
        if (existing && error.status === 409) {
          conflicted = true;
          errorBox.append(el("p", "text-secondary", "Bản sửa chưa được gửi lại. Tải lại để xem dữ liệu mới; bản nhập hiện tại sẽ được bỏ khi bạn chọn tải lại."), button("Tải lại dữ liệu mới", () => navigateDetail(existing.id, "", orderQuery(s), true)));
        }
      } finally { submitting = false; fields.disabled = false; submit.disabled = conflicted; submit.textContent = existing ? "Lưu thay đổi" : "Tạo đơn"; view.setBusy(false); }
    });
    fields.disabled = true; view.setBusy(true); submit.textContent = "Đang tải dữ liệu…";
    try { await Promise.allSettled([sender.start(), receiver.start()]); }
    finally {
      initializing = false;
      if (!s.dead && view.node.isConnected) { fields.disabled = false; view.setBusy(false); submit.textContent = existing ? "Lưu thay đổi" : "Tạo đơn"; }
    }
  }
  function distanceValue(control) {
    const required = control.required; control.required = true;
    const valid = control.reportValidity(); control.required = required;
    if (!valid || control.value === "") throw new Error("Nhập khoảng cách từ 0 đến 1.000.000 km, tối đa 2 số lẻ.");
    return Number(control.value);
  }
  function quoteSummary(result) {
    return section("Kết quả báo giá tham khảo", summary([
      ["Dịch vụ", result.serviceName], ["Khoảng cách", number.format(result.distanceKm) + " km"], ["Khối lượng", weight(result.weightKg)],
      ["Phí cơ bản", money(result.baseFee)], ["Phí khoảng cách", money(result.distanceFee)], ["Phí khối lượng", money(result.weightFee)],
      ["Tổng phí tham khảo", money(result.shippingFee)], ["Thời điểm báo giá (giờ VN)", date(result.quotedAt)]
    ]));
  }
  async function openQuote(s, order) {
    const view = dialog(s, "Báo giá tham khảo");
    const errorBox = el("div"); view.body.append(errorBox, el("p", "text-secondary", "Đang tải dịch vụ…"));
    try {
      const options = await read(s, "/api/v1/order-form/options", view.signal);
      if (s.dead || !view.node.isConnected) return;
      const form = el("form"); const fields = el("fieldset");
      const service = select(options.services, "Chọn dịch vụ báo giá", order.serviceId);
      const distance = input("number", "", { required: true, min: "0", max: "1000000", step: "0.01" });
      const output = el("div"); const submit = button("Báo giá", null, "btn btn-orange"); submit.type = "submit";
      fields.append(el("p", "text-secondary", "Dịch vụ đơn: " + text(order.serviceName) + ". " + (order.serviceId ? "" : "API chi tiết chưa trả ID dịch vụ; hãy chọn dịch vụ muốn báo giá. ") + "Khoảng cách nhập thủ công. Đây là phí tham khảo, phí chính thức lấy từ backend khi xác nhận."), field("Dịch vụ báo giá *", service, "mb-3"), field("Khoảng cách (km) *", distance, "mb-3"), submit);
      form.append(fields); view.body.replaceChildren(errorBox, form, output);
      fields.addEventListener("input", () => output.replaceChildren()); fields.addEventListener("change", () => output.replaceChildren());
      let busy = false;
      form.addEventListener("submit", async event => {
        event.preventDefault(); if (busy || !form.reportValidity()) return;
        notice(errorBox, ""); output.replaceChildren();
        if (!(order.weightKg > 0 && order.weightKg <= 1000000)) { notice(errorBox, "Khối lượng để báo giá phải từ 0,001 đến 1.000.000 kg."); return; }
        const payload = { branchId: order.branchId, serviceId: Number(service.value), distanceKm: Number(distance.value), weightKg: order.weightKg };
        busy = true; fields.disabled = true; view.setBusy(true);
        try {
          const result = await window.ApiClient.request("/api/v1/shipping-fees/quote", { method: "POST", signal: view.signal, body: JSON.stringify(payload) });
          if (!s.dead && view.node.isConnected) output.append(quoteSummary(result));
        } catch (error) { if (!s.dead && view.node.isConnected && error.name !== "AbortError") notice(errorBox, error.message); }
        finally { busy = false; fields.disabled = false; view.setBusy(false); }
      });
    } catch (error) { if (!s.dead && view.node.isConnected && error.name !== "AbortError") { view.body.replaceChildren(errorBox); notice(errorBox, error.message); } }
  }
  function openAction(s, detailView, order, action) {
    const cancelling = action === "cancel";
    const view = dialog(s, cancelling ? "Hủy đơn " + text(order.orderCode) : "Xác nhận đơn " + text(order.orderCode));
    const errorBox = el("div");
    const form = el("form"); const fields = el("fieldset");
    const control = cancelling ? el("textarea", "form-control") : input("number", "", { min: "0", max: "1000000", step: "0.01" });
    control.required = true;
    if (cancelling) { control.maxLength = 500; control.rows = 3; }
    fields.append(el("p", "", cancelling ? "Bạn xác nhận hủy đơn này? Thao tác sẽ được ghi vào lịch sử với lý do bên dưới."
      : "Bạn xác nhận tiếp nhận đơn này? Backend sẽ tính lại phí chính thức theo dịch vụ của đơn và khoảng cách bạn nhập."), field(cancelling ? "Lý do hủy (1–500 ký tự) *" : "Khoảng cách nhập thủ công (km) *", control, "mb-3"));
    if (!cancelling) fields.append(el("p", "text-secondary", "Chưa tích hợp thuật toán tính đường đi. Phí báo giá có thể thay đổi ở thời điểm xác nhận."));
    const submit = button(cancelling ? "Đồng ý hủy đơn" : "Đồng ý xác nhận", null, cancelling ? "btn btn-danger" : "btn btn-orange"); submit.type = "submit";
    const actions = el("div", "order-actions"); actions.append(submit, button("Quay lại", () => view.close()));
    fields.append(actions); form.append(fields); view.body.append(errorBox, form);
    control.addEventListener("input", () => control.setCustomValidity(""));
    let busy = false, conflicted = false;
    form.addEventListener("submit", async event => {
      event.preventDefault(); if (busy || conflicted) return;
      if (cancelling) control.setCustomValidity(control.value.trim() ? "" : "Phải nhập lý do hủy.");
      if (!form.reportValidity()) return;
      const payload = cancelling ? { reason: control.value.trim() } : { distanceKm: Number(control.value) };
      notice(errorBox, ""); busy = true; fields.disabled = true; view.setBusy(true);
      try {
        const result = await window.ApiClient.request("/api/v1/orders/" + order.id + "/" + action, { method: "POST", signal: view.signal, body: JSON.stringify(payload) });
        if (s.dead || !view.node.isConnected) return;
        view.close();
        navigateDetail(order.id, (result.message || "Đã xử lý đơn.") + (!cancelling ? " Phí chính thức: " + money(result.shippingFee) + "." : ""), orderQuery(s), true);
      } catch (error) {
        if (s.dead || !view.node.isConnected) return;
        notice(errorBox, error.message);
        if ([404, 409].includes(error.status)) {
          conflicted = true;
          errorBox.append(button("Tải lại chi tiết", () => { view.close(); navigateDetail(order.id, "", orderQuery(s), true); }));
        }
      } finally { busy = false; fields.disabled = false; submit.disabled = conflicted; view.setBusy(false); }
    });
  }
  window.LogisticsUI = Object.freeze({ text, money, weight, date, el, button, input, option, select, field, notice, badge, table, summary, section, dialog, closeDialogs, routeView, pagination });
  window.OrdersPage = Object.freeze({ mount, destroy, showDetail(owner, id) {
    if (owner.route?.pageId === "orders") return navigateDetail(id, "", orderQuery(owner));
    const source = window.Router.current() || owner.route;
    const returnTo = source.name === "transaction-detail" ? window.Router.href("warehouse-transactions", {}, source.query) : source.hash;
    return navigateDetail(id, "", { returnTo });
  } });
}());
