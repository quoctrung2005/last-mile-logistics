"use strict";

(function () {
  const UI = window.LogisticsUI;
  const { el, button, input, select, option, field, notice, table, badge, summary, dialog, text, date } = UI;
  const types = { INBOUND: "Nhập kho", MOVE: "Chuyển vị trí", OUTBOUND: "Xuất kho", RETURN_IN: "Nhập hàng hoàn" };
  const states = { PENDING: "Chờ xử lý", COMPLETED: "Hoàn tất", CANCELLED: "Đã hủy" };
  const conditions = { NORMAL: "Bình thường", DAMAGED: "Hư hỏng", OTHER: "Tình trạng khác" };
  const number = new Intl.NumberFormat("vi-VN");
  const positive = value => Number.isSafeInteger(value) && value > 0;
  let active = null;
  const alive = s => active === s && !s.dead;
  function message(error) {
    if (error.sessionExpired) return "Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.";
    if (error.status === 403) return "Bạn không có quyền xem lịch sử giao dịch kho.";
    if (error.networkError || error.status >= 500) return "Không thể kết nối hoặc tải dữ liệu lúc này. Vui lòng thử lại.";
    return (error.message || "Không thể tải dữ liệu.").replace(/\s*\(HTTP \d+\)/g, "");
  }
  function typeBadge(value) { return el("span", "transaction-type transaction-type-" + (types[value] ? value.toLowerCase() : "unknown"), types[value] || text(value)); }
  function code(value) { const node = el("span", "transaction-code", text(value)); node.title = text(value); node.tabIndex = 0; return node; }
  async function read(s, url, signal) { return window.ApiClient.request(url, { signal: signal ? AbortSignal.any([s.abort.signal, signal]) : s.abort.signal }); }
  function destroy() {
    if (!active) return;
    const s = active; s.dead = true; s.abort.abort(); s.controller?.abort(); UI.closeDialogs(s); s.refresh.remove(); active = null;
  }
  function mount(container, user, route, context) {
    destroy();
    const s = { container, user, route, permissions: context.permissions, abort: new AbortController(), dialogs: new Set(), sequence: 0, dead: false,
      page: route.query.page || 1, pageSize: route.query.pageSize || 10, legacyOrderId: route.query.orderId || null, applied: {} };
    active = s;
    const card = el("section", "orders-card transactions-card");
    s.refresh = button("Làm mới", () => reload(s), "btn btn-outline-orange transactions-refresh"); document.querySelector(".page-heading").append(s.refresh);
    s.warehouse = select([], "Tất cả kho trong phạm vi"); s.warehouse.required = false; s.warehouse.disabled = true;
    s.type = select(Object.entries(types).map(([id, name]) => ({ id, name })), "Tất cả loại giao dịch", route.query.type); s.type.required = false;
    s.keyword = input("search", route.query.keyword || "", { maxLength: 100, placeholder: "Mã giao dịch, mã đơn hoặc mã vận đơn" });
    s.fromDate = input("date", route.query.fromDate || ""); s.toDate = input("date", route.query.toDate || "");
    s.form = el("form", "transactions-filters"); s.form.noValidate = true;
    const search = button("Tìm kiếm", null, "btn btn-orange"); search.type = "submit";
    const clear = button("Xóa bộ lọc", () => {
      s.warehouse.value = s.type.value = s.keyword.value = s.fromDate.value = s.toDate.value = "";
      s.legacyOrderId = null; s.legacyHint.hidden = true; apply(s);
    });
    const actions = el("div", "transactions-filter-actions"); actions.append(search, clear);
    s.form.append(field("Kho", s.warehouse, "transaction-filter"), field("Loại giao dịch", s.type, "transaction-filter"), field("Tìm kiếm", s.keyword, "transaction-filter transaction-search"),
      field("Từ ngày (VN)", s.fromDate, "transaction-filter transaction-date"), field("Đến ngày (VN)", s.toDate, "transaction-filter transaction-date"), actions);
    s.legacyHint = el("p", "transaction-legacy-hint text-secondary", "Đang xem lịch sử của một đơn được chọn. Dùng Xóa bộ lọc để xem toàn bộ."); s.legacyHint.hidden = !s.legacyOrderId;
    s.catalogMessage = el("div", "transactions-message"); s.alert = el("div", "transactions-message"); s.body = el("div", "transactions-list");
    s.footer = el("div", "transactions-footer"); s.footer.hidden = true;
    s.size = select([...new Set([s.pageSize,10,20,50,100])].sort((a,b) => a-b).map(id => ({ id, name: id + " dòng / trang" })), "Số dòng", s.pageSize);
    s.total = el("span", "text-secondary"); s.pager = el("nav", "transactions-pagination"); s.pager.setAttribute("aria-label", "Phân trang giao dịch kho");
    s.footer.append(field("Số dòng", s.size, "warehouse-page-size"), s.total, s.pager);
    card.append(s.form, s.legacyHint, s.catalogMessage, s.alert, s.body, s.footer); container.replaceChildren(card);
    if (route.query.warehouseId) option(s.warehouse, route.query.warehouseId, "Kho theo liên kết"); s.warehouse.value = route.query.warehouseId || "";
    s.applied = collect(s);
    s.form.addEventListener("submit", event => { event.preventDefault(); apply(s); });
    for (const node of [s.warehouse, s.type, s.fromDate, s.toDate]) node.addEventListener("change", () => apply(s));
    s.size.addEventListener("change", () => { s.pageSize = Number(s.size.value); s.page = 1; reload(s); });
    loadWarehouses(s); reload(s);
    if (route.mode === "detail") openDetail(s, route.params.id);
  }
  function collect(s) {
    const values = {};
    if (s.warehouse.value) values.warehouseId = Number(s.warehouse.value);
    if (s.type.value) values.type = s.type.value;
    if (s.keyword.value.trim()) values.keyword = s.keyword.value.trim();
    if (s.fromDate.value) values.fromDate = s.fromDate.value;
    if (s.toDate.value) values.toDate = s.toDate.value;
    if (s.legacyOrderId) values.orderId = s.legacyOrderId;
    return values;
  }
  function apply(s) {
    if (!alive(s)) return;
    s.toDate.setCustomValidity(s.fromDate.value && s.toDate.value && s.fromDate.value > s.toDate.value ? "Đến ngày phải bằng hoặc sau từ ngày." : "");
    if (!s.form.reportValidity()) { notice(s.alert, "Kiểm tra khoảng ngày: từ ngày không được sau đến ngày."); return; }
    s.applied = collect(s); s.page = 1; UI.closeDialogs(s); reload(s);
  }
  async function loadWarehouses(s) {
    try {
      const rows = await read(s, "/api/v1/warehouses");
      if (!alive(s)) return;
      if (!Array.isArray(rows) || rows.some(row => !positive(row.id))) throw new Error("API danh sách kho trả dữ liệu không hợp lệ.");
      const selected = s.applied.warehouseId || "";
      s.warehouse.replaceChildren(); option(s.warehouse, "", "Tất cả kho trong phạm vi");
      for (const row of rows) option(s.warehouse, row.id, row.name + " · " + text(row.branchName));
      if (selected && !rows.some(row => row.id === selected)) option(s.warehouse, selected, "Kho theo liên kết lịch sử");
      s.warehouse.value = selected; s.warehouse.disabled = false; notice(s.catalogMessage, "");
    } catch (error) {
      if (!alive(s) || error.name === "AbortError") return;
      notice(s.catalogMessage, message(error)); s.catalogMessage.append(button("Tải lại danh sách kho", () => loadWarehouses(s)));
    }
  }
  function renderPager(s, totalItems) {
    s.footer.hidden = totalItems === 0; s.total.textContent = number.format(totalItems) + " giao dịch";
    const pages = Math.max(1, Math.ceil(totalItems / s.pageSize)); s.pager.hidden = pages <= 1;
    const previous = button("‹ Trước", () => { s.page--; reload(s); }); previous.disabled = s.page <= 1;
    const next = button("Sau ›", () => { s.page++; reload(s); }); next.disabled = s.page >= pages;
    s.pager.replaceChildren(previous, el("span", "text-secondary", "Trang " + s.page + " / " + pages), next);
  }
  async function reload(s) {
    if (!alive(s)) return;
    s.controller?.abort(); s.controller = new AbortController(); const seq = ++s.sequence;
    const values = { ...s.applied, page: s.page, pageSize: s.pageSize };
    window.Router.updateQuery(values, s.route);
    s.body.setAttribute("aria-busy", "true"); s.body.replaceChildren(el("p", "orders-empty", "Đang tải giao dịch kho…")); notice(s.alert, ""); s.footer.hidden = true;
    try {
      const url = "/api/v1/warehouse-transactions?" + new URLSearchParams(values);
      const result = window.ApiClient.validatePage(await read(s, url, s.controller.signal), url, ["id", "warehouseId", "branchId"]);
      if (!alive(s) || seq !== s.sequence) return;
      if (result.items.some(row => !positive(row.performedBy) || !Number.isSafeInteger(row.orderCount) || row.orderCount < 0 || (s.applied.warehouseId && row.warehouseId !== s.applied.warehouseId)
        || (s.user.role !== "ADMIN" && row.branchId !== s.user.branchId))) throw new Error("API giao dịch trả dữ liệu không hợp lệ hoặc không thuộc phạm vi tài khoản.");
      const pages = Math.min(100000, Math.max(1, Math.ceil(result.totalItems / s.pageSize)));
      if (s.page > pages) { s.page = pages; reload(s); return; }
      s.body.replaceChildren(result.items.length ? table(["Mã giao dịch", "Loại giao dịch", "Kho", "Số đơn", "Người thực hiện", "Thời gian (VN)", "Trạng thái", "Thao tác"], result.items.map(row => [
        code(row.transactionCode), typeBadge(row.type), row.warehouseName, number.format(row.orderCount), row.performedByName || "Tài khoản #" + row.performedBy,
        date(row.performedAt), badge(row.status, states[row.status] || text(row.status)), button("Xem chi tiết", () => openDetail(s, row.id), "btn btn-outline-orange btn-sm")
      ])) : el("p", "orders-empty", "Không có giao dịch phù hợp với bộ lọc"));
      renderPager(s, result.totalItems);
    } catch (error) {
      if (!alive(s) || seq !== s.sequence || error.name === "AbortError") return;
      notice(s.alert, message(error)); s.alert.append(button("Thử lại", () => reload(s))); s.body.replaceChildren(el("p", "orders-empty", "Chưa tải được lịch sử giao dịch kho."));
    } finally { if (alive(s) && seq === s.sequence) s.body.setAttribute("aria-busy", "false"); }
  }
  function openDetail(s, id) {
    if (!alive(s) || !positive(id) || s.dialogs.size) return;
    const view = dialog(s, "Chi tiết giao dịch kho", true); view.node.classList.add("transactions-dialog");
    let sequence = 0, controller;
    async function load() {
      controller?.abort(); controller = new AbortController(); const seq = ++sequence;
      view.body.setAttribute("aria-busy", "true"); view.body.replaceChildren(el("p", "orders-empty", "Đang tải chi tiết giao dịch…"));
      try {
        const result = await read(s, "/api/v1/warehouse-transactions/" + id, AbortSignal.any([view.signal, controller.signal]));
        if (!alive(s) || !view.node.isConnected || seq !== sequence) return;
        if (!result || result.id !== id || !positive(result.warehouseId) || !positive(result.branchId) || !Array.isArray(result.items) || result.items.some(item => !positive(item.orderId))
          || (s.user.role !== "ADMIN" && result.branchId !== s.user.branchId)) throw new Error("API chi tiết giao dịch trả dữ liệu không hợp lệ hoặc ngoài phạm vi tài khoản.");
        const identity = el("div", "transaction-detail-identity"); identity.append(code(result.transactionCode), typeBadge(result.type), badge(result.status, states[result.status] || text(result.status)));
        const info = summary([["Kho", result.warehouseName], ["Bưu cục", result.branchName || "Bưu cục #" + result.branchId],
          ["Người thực hiện", result.performedByName || "Tài khoản #" + result.performedBy], ["Thời gian (VN)", date(result.performedAt)], ["Ghi chú", result.notes]]);
        const canViewOrder = s.permissions.known && s.permissions.codes.has("DONHANG_XEM");
        view.body.replaceChildren(identity, info, el("h3", "transaction-detail-heading", "Các đơn trong giao dịch"),
          result.items.length ? table(["Mã đơn", "Mã vận đơn", "Vị trí nguồn", "Vị trí đích", "Tình trạng hàng", "Ghi chú"], result.items.map(item => {
            const order = canViewOrder ? button(text(item.orderCode), () => window.OrdersPage.showDetail(s, item.orderId), "btn btn-link order-code p-0 transaction-order-link") : code(item.orderCode);
            order.title = text(item.orderCode);
            return [order, code(item.trackingNumber), item.fromLocationCode || "—", item.toLocationCode || "—", conditions[item.condition] || text(item.condition), item.notes];
          })) : el("p", "orders-empty", "Giao dịch chưa có chi tiết đơn hàng."));
      } catch (error) {
        if (!alive(s) || !view.node.isConnected || seq !== sequence || error.name === "AbortError") return;
        const box = el("div"); notice(box, message(error)); view.body.replaceChildren(box, button("Thử lại", load));
      } finally { if (view.node.isConnected && seq === sequence) view.body.setAttribute("aria-busy", "false"); }
    }
    view.onClose(() => {
      sequence++; controller?.abort();
      if (alive(s) && window.Router.current()?.name === "transaction-detail") window.Router.navigate(window.Router.href("warehouse-transactions", {}, window.Router.current().query), { replace: true });
    });
    load();
  }
  window.TransactionsPage = Object.freeze({ mount, destroy });
}());
