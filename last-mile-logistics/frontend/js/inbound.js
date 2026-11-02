"use strict";

(function () {
  const UI = window.LogisticsUI;
  const statuses = { CONFIRMED: "Đã tiếp nhận", WAITING_INBOUND: "Chờ nhập kho" };
  let active = null;
  const id = value => Number.isSafeInteger(value) && value > 0;
  const locationName = row => [row.code, row.storageArea, row.rack ? "Kệ " + row.rack : "", row.slot ? "Ô " + row.slot : ""].filter(Boolean).join(" · ");
  const canImport = s => s.permissions.known && s.permissions.codes.has("KHO_NHAP");
  const alive = s => !s.dead && active === s;
  const selectedLocation = s => s.locations.find(row => String(row.id) === s.location.value);

  async function read(s, path, signal) {
    return window.ApiClient.request(path, { signal: signal ? AbortSignal.any([s.abort.signal, signal]) : s.abort.signal });
  }
  function message(error) {
    if (error.sessionExpired) return "Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.";
    if (error.status === 403) return "Bạn không có quyền thực hiện thao tác này.";
    if (error.resultUnknown) return "Không đọc được kết quả xử lý. Hãy tải lại để kiểm tra trạng thái.";
    if (error.networkError || error.status >= 500) return "Không thể kết nối hoặc xử lý dữ liệu lúc này. Vui lòng thử lại.";
    let result = (error.message || "Không thể thực hiện thao tác.").replace(/\s*\(HTTP \d+\)/g, "");
    for (const [code, label] of Object.entries(statuses)) result = result.replaceAll(code, label.toLowerCase());
    return result;
  }
  function validateLocations(rows, warehouseId) {
    if (!Array.isArray(rows) || rows.some(row => !row || !id(row.id) || row.warehouseId !== warehouseId)
      || new Set(rows.map(row => row.id)).size !== rows.length) throw new Error("API vị trí trả dữ liệu không hợp lệ hoặc không thuộc kho đã chọn.");
    return rows; // The backend's locations endpoint selects only active positions.
  }
  function syncRoute(s) {
    if (!alive(s)) return;
    window.Router.updateQuery({ ...s.filters, warehouseId: s.warehouse?.id, locationId: selectedLocation(s)?.id }, s.route);
  }
  function updateControls(s) {
    if (!alive(s)) return;
    const locked = s.pending || Boolean(s.modal);
    s.warehouseSelect.disabled = locked || s.catalogBusy || !s.catalogReady;
    s.location.disabled = locked || !s.warehouse || s.catalogBusy || s.locationsBusy || !s.locationsReady || !s.locations.length;
    s.keyword.disabled = s.status.disabled = s.filterButton.disabled = s.clearButton.disabled = locked || !s.warehouse || s.catalogBusy;
    s.pageSize.disabled = locked || !s.warehouse || s.catalogBusy;
    s.refreshCatalog.disabled = locked || s.catalogBusy;
    s.refreshList.disabled = locked || !s.warehouse || s.catalogBusy;
    for (const node of s.table.querySelectorAll("[data-inbound-order]")) {
      node.disabled = locked || !canImport(s) || !selectedLocation(s) || !s.locationsReady || s.catalogBusy || s.locationsBusy;
      node.title = !canImport(s) ? "Thiếu quyền KHO_NHAP" : !selectedLocation(s) ? "Chọn vị trí lưu kho trước khi nhập" : "";
    }
    for (const node of s.table.querySelectorAll("[data-order-detail]")) node.disabled = s.pending;
    for (const node of s.pager.querySelectorAll("button")) node.disabled = locked || s.listBusy || node.dataset.boundary === "true";
  }
  function showPermission(s) {
    UI.notice(s.permissionMessage, canImport(s) ? "" : "Bạn có thể xem danh sách nhưng không có quyền KHO_NHAP để nhập hàng.", "warning");
  }
  function destroy() {
    if (!active) return;
    const s = active; s.dead = true; s.abort.abort(); s.catalogController?.abort(); s.locationController?.abort(); s.listController?.abort();
    s.modalController?.abort();
    if (s.scannerHandler) window.removeEventListener("keydown", s.scannerHandler);
    UI.closeDialogs(s);
    active = null;
  }
  function mount(container, user, route, context) {
    destroy();
    const query = route.query;
    const s = { container, user, route, permissions: context.permissions, abort: new AbortController(), dialogs: new Set(),
      dead: false, warehouse: null, warehouses: [], locations: [], records: [], catalogReady: false, locationsReady: false,
      catalogBusy: false, locationsBusy: false, listBusy: false, pending: false, modal: null, scope: 0, catalogSequence: 0, listSequence: 0,
      filters: { page: query.page || 1, pageSize: query.pageSize || 10, keyword: query.keyword || "", status: query.status || "" }, uncertain: new Map() };
    active = s;
    const card = UI.el("section", "orders-card inbound-card");
    const toolbar = UI.el("div", "inbound-toolbar");
    s.refreshCatalog = UI.button("Làm mới kho", () => loadCatalog(s), "btn btn-outline-orange");
    s.refreshList = UI.button("Làm mới danh sách", () => applyFilters(s, false), "btn btn-outline-orange");
    toolbar.append(s.refreshCatalog, s.refreshList);
    const form = UI.el("form", "inbound-filters"); form.noValidate = true; s.filterForm = form;
    s.warehouseSelect = UI.select([], "Đang tải kho…"); s.warehouseSelect.required = false;
    s.location = UI.select([], "Chọn kho trước"); s.location.required = false;
    s.keyword = UI.input("search", s.filters.keyword, { maxLength: 100, placeholder: "Mã đơn hoặc mã vận đơn" });
    s.status = UI.select(Object.entries(statuses).map(([value, label]) => ({ id: value, name: label })), "Tất cả đơn đủ điều kiện", s.filters.status); s.status.required = false;
    s.filterButton = UI.button("Lọc", null, "btn btn-orange"); s.filterButton.type = "submit";
    s.clearButton = UI.button("Xóa bộ lọc", () => {
      if (s.pending || s.modal || !s.warehouse) return;
      s.keyword.value = ""; s.status.value = ""; s.filters = { ...s.filters, page: 1, keyword: "", status: "" }; loadOrders(s);
    }, "btn btn-outline-secondary");
    const actions = UI.el("div", "inbound-filter-actions"); actions.append(s.filterButton, s.clearButton);
    form.append(UI.field("Kho", s.warehouseSelect, "inbound-filter"), UI.field("Vị trí lưu", s.location, "inbound-filter"),
      UI.field("Tìm đơn", s.keyword, "inbound-filter inbound-search"), UI.field("Trạng thái", s.status, "inbound-filter"), actions);
    s.catalogMessage = UI.el("div", "inbound-message"); s.permissionMessage = UI.el("div", "inbound-message");
    s.feedback = UI.el("div", "inbound-message"); s.uncertaintyBox = UI.el("div", "inbound-message"); s.listMessage = UI.el("div", "inbound-message");
    s.table = UI.el("div", "inbound-table"); s.table.setAttribute("aria-live", "polite");
    s.pager = UI.el("nav", "orders-pagination"); s.pager.setAttribute("aria-label", "Phân trang đơn đủ điều kiện nhập kho");
    s.pageSize = UI.select([...new Set([s.filters.pageSize, 10, 20, 50, 100])].sort((a, b) => a - b).map(value => ({ id: value, name: value + " đơn / trang" })), "Số dòng", s.filters.pageSize);
    const footer = UI.el("div", "warehouse-list-footer"); footer.append(UI.field("Số dòng", s.pageSize, "warehouse-page-size"), s.pager);
    card.append(toolbar, form, s.catalogMessage, s.permissionMessage, s.feedback, s.uncertaintyBox, s.listMessage, s.table, footer); container.replaceChildren(card);
    form.addEventListener("submit", event => {
      event.preventDefault(); applyFilters(s, true);
    });
    s.keyword.addEventListener("input", () => s.keyword.setCustomValidity(""));
    s.keyword.addEventListener("keydown", event => { if (event.key === "Enter") { event.preventDefault(); form.requestSubmit(); } });
    s.warehouseSelect.addEventListener("change", () => chooseWarehouse(s, s.warehouseSelect.value));
    s.location.addEventListener("change", () => { syncRoute(s); updateControls(s); });
    s.pageSize.addEventListener("change", () => { s.filters.pageSize = Number(s.pageSize.value); s.filters.page = 1; loadOrders(s); });
    // USB Barcode Scanner HID Listener
    let barcodeBuffer = "";
    let lastKeyTime = 0;
    const scannerKeyHandler = (e) => {
      if (!alive(s) || s.pending || s.modal) return;
      const now = Date.now();
      if (e.key === "Enter") {
        if (barcodeBuffer.length >= 6 && (now - lastKeyTime < 120)) {
          e.preventDefault();
          const scannedCode = barcodeBuffer.trim();
          barcodeBuffer = "";
          try {
            const ctx = new (window.AudioContext || window.webkitAudioContext)();
            const osc = ctx.createOscillator();
            osc.frequency.setValueAtTime(1400, ctx.currentTime);
            osc.connect(ctx.destination);
            osc.start();
            osc.stop(ctx.currentTime + 0.1);
          } catch {}
          s.keyword.value = scannedCode;
          s.filters = { ...s.filters, page: 1, keyword: scannedCode };
          UI.notice(s.feedback, "⚡ Súng quét mã USB: Đã nhận mã [" + scannedCode + "]", "success");
          loadOrders(s);
          return;
        }
        barcodeBuffer = "";
        return;
      }
      if (e.key.length === 1) {
        if (now - lastKeyTime < 60) {
          barcodeBuffer += e.key;
        } else {
          barcodeBuffer = e.key;
        }
        lastKeyTime = now;
      }
    };
    window.addEventListener("keydown", scannerKeyHandler);
    s.scannerHandler = scannerKeyHandler;

    showPermission(s); emptyScope(s); updateControls(s); loadCatalog(s, true);
  }
  function applyFilters(s, resetPage) {
    if (!alive(s) || !s.warehouse || s.pending || s.modal || s.catalogBusy) return;
    s.keyword.setCustomValidity(s.keyword.value.length <= 100 ? "" : "Từ khóa tối đa 100 ký tự.");
    if (!s.filterForm.reportValidity() || (s.status.value && !Object.hasOwn(statuses, s.status.value))) return;
    const keyword = s.keyword.value.trim(), status = s.status.value;
    const changed = keyword !== s.filters.keyword || status !== s.filters.status;
    s.filters = { ...s.filters, page: resetPage || changed ? 1 : s.filters.page, keyword, status }; loadOrders(s);
  }
  function emptyScope(s) {
    s.records = []; s.listLoaded = false; s.pager.replaceChildren(); UI.notice(s.listMessage, "");
    s.table.setAttribute("aria-busy", "false");
    s.table.replaceChildren(UI.el("p", "orders-empty", "Chọn kho để xem đơn đủ điều kiện nhập kho."));
  }
  async function loadCatalog(s, initial = false) {
    if (!alive(s) || s.pending || s.modal) return;
    const previous = s.warehouse;
    const wantedId = previous?.id || (initial ? s.route.query.warehouseId || window.WarehousePage.preferredWarehouse(s.user) : null);
    const wantedLocation = selectedLocation(s)?.id || (initial ? s.route.query.locationId : null);
    const needsList = initial || !s.listLoaded || s.listBusy;
    const seq = ++s.catalogSequence; s.catalogController?.abort(); s.catalogController = new AbortController();
    s.catalogBusy = true; s.catalogReady = false; s.locationsReady = false; updateControls(s); UI.notice(s.catalogMessage, "");
    try {
      const rows = await read(s, "/api/v1/warehouses", s.catalogController.signal);
      if (!alive(s) || seq !== s.catalogSequence) return;
      if (!Array.isArray(rows) || rows.some(row => !row || !id(row.id) || !id(row.branchId)) || new Set(rows.map(row => row.id)).size !== rows.length)
        throw new Error("API kho trả dữ liệu không hợp lệ.");
      s.warehouses = rows; s.catalogReady = true;
      s.warehouseSelect.replaceChildren(); UI.option(s.warehouseSelect, "", "Chọn kho");
      for (const row of rows) UI.option(s.warehouseSelect, row.id, row.name + " · " + row.branchName);
      const next = rows.find(row => row.id === wantedId) || (!wantedId && rows.length === 1 ? rows[0] : null);
      if (!rows.length) UI.notice(s.catalogMessage, "Không có kho hoạt động trong phạm vi tài khoản.", "info");
      else if (wantedId && !next) UI.notice(s.catalogMessage, "Kho đã chọn không còn hoạt động hoặc không còn trong phạm vi tài khoản. Hãy chọn kho khác.", "warning");
      const same = previous && next && previous.id === next.id && previous.branchId === next.branchId;
      await chooseWarehouse(s, next?.id || "", { preservePage: Boolean(same) || initial, locationId: wantedLocation, refreshList: needsList || !same });
    } catch (error) {
      if (!alive(s) || seq !== s.catalogSequence || error.name === "AbortError") return;
      UI.notice(s.catalogMessage, message(error)); s.catalogMessage.append(UI.button("Thử lại kho", () => loadCatalog(s), "btn btn-outline-orange"));
    } finally { if (alive(s) && seq === s.catalogSequence) { s.catalogBusy = false; updateControls(s); } }
  }
  async function chooseWarehouse(s, value, options = {}) {
    if (!alive(s) || s.pending || s.modal) { if (alive(s)) s.warehouseSelect.value = s.warehouse?.id || ""; return; }
    const scope = ++s.scope; s.locationController?.abort(); s.listController?.abort();
    s.warehouse = s.warehouses.find(row => String(row.id) === String(value)) || null;
    window.WarehousePage.rememberWarehouse(s.user, s.warehouse?.id);
    s.warehouseSelect.value = s.warehouse?.id || ""; s.locations = []; s.locationsReady = false;
    s.location.replaceChildren(); UI.option(s.location, "", s.warehouse ? "Đang tải vị trí…" : "Chọn kho trước");
    if (!options.preservePage) s.filters.page = 1;
    if (options.refreshList !== false) emptyScope(s);
    syncRoute(s); updateControls(s);
    if (!s.warehouse) { s.locationsBusy = false; s.listBusy = false; emptyScope(s); updateControls(s); return; }
    await Promise.allSettled([loadLocations(s, scope, options.locationId), ...(options.refreshList !== false ? [loadOrders(s)] : [])]);
  }
  async function loadLocations(s, scope = s.scope, wantedId = selectedLocation(s)?.id) {
    if (!alive(s) || !s.warehouse) return;
    const warehouseId = s.warehouse.id; s.locationController?.abort(); s.locationController = new AbortController();
    s.locationsBusy = true; s.locationsReady = false; updateControls(s);
    try {
      const rows = validateLocations(await read(s, "/api/v1/warehouses/" + warehouseId + "/locations", s.locationController.signal), warehouseId);
      if (!alive(s) || scope !== s.scope) return;
      s.locations = rows; s.locationsReady = true; s.location.replaceChildren(); UI.option(s.location, "", "Chọn vị trí");
      for (const row of rows) UI.option(s.location, row.id, locationName(row));
      s.location.value = rows.some(row => row.id === wantedId) ? wantedId : "";
      if (!rows.length) UI.notice(s.catalogMessage, "Kho chưa có vị trí đang hoạt động. Không thể nhập kho.", "warning");
      else if (wantedId && !selectedLocation(s)) UI.notice(s.catalogMessage, "Vị trí đã chọn không còn hợp lệ. Hãy chọn vị trí khác.", "warning");
      syncRoute(s);
    } catch (error) {
      if (!alive(s) || scope !== s.scope || error.name === "AbortError") return;
      UI.notice(s.catalogMessage, message(error)); s.catalogMessage.append(UI.button("Thử lại vị trí", () => loadLocations(s), "btn btn-outline-orange"));
    } finally { if (alive(s) && scope === s.scope) { s.locationsBusy = false; updateControls(s); } }
  }
  async function loadOrders(s) {
    if (!alive(s) || !s.warehouse || s.pending || s.modal && !s.modal.blocked) return;
    const scope = s.scope, warehouse = s.warehouse, seq = ++s.listSequence;
    s.listController?.abort(); s.listController = new AbortController(); s.listBusy = true;
    s.table.setAttribute("aria-busy", "true"); s.table.replaceChildren(UI.el("p", "orders-empty", "Đang tải đơn đủ điều kiện nhập kho…"));
    s.records = []; s.pager.replaceChildren(); UI.notice(s.listMessage, ""); syncRoute(s); updateControls(s);
    const query = new URLSearchParams({ warehouseId: warehouse.id, inboundOnly: true, page: s.filters.page, pageSize: s.filters.pageSize });
    if (s.filters.keyword) query.set("keyword", s.filters.keyword);
    if (s.filters.status) query.set("status", s.filters.status);
    try {
      const result = await read(s, "/api/v1/orders?" + query, s.listController.signal);
      if (!alive(s) || scope !== s.scope || seq !== s.listSequence) return;
      window.ApiClient.validatePage(result, "/api/v1/orders", ["id", "branchId"]);
      if (result.page !== s.filters.page || result.pageSize !== s.filters.pageSize || result.items.length > result.pageSize || result.totalItems < result.items.length)
        throw new Error("API danh sách trả thông tin phân trang không khớp yêu cầu.");
      if (result.items.some(row => row.branchId !== warehouse.branchId || !Object.hasOwn(statuses, row.status))
        || new Set(result.items.map(row => row.id)).size !== result.items.length) throw new Error("API trả đơn không đủ điều kiện hoặc ngoài bưu cục của kho.");
      const pages = Math.max(1, Math.ceil(result.totalItems / s.filters.pageSize));
      if (s.filters.page > pages) { s.filters.page = pages; await loadOrders(s); return; }
      s.records = result.items; s.listLoaded = true; renderTable(s);
      UI.pagination(s.pager, s.filters.page, s.filters.pageSize, result.totalItems, page => { s.filters.page = page; loadOrders(s); }, "đơn");
      for (const node of s.pager.querySelectorAll("button")) node.dataset.boundary = String(node.disabled);
    } catch (error) {
      if (!alive(s) || scope !== s.scope || seq !== s.listSequence || error.name === "AbortError") return;
      s.listLoaded = false; UI.notice(s.listMessage, message(error));
      s.table.replaceChildren(UI.el("p", "orders-empty", "Chưa tải được danh sách đơn.")); s.listMessage.append(UI.button("Thử lại danh sách", () => loadOrders(s), "btn btn-outline-orange"));
    } finally {
      if (alive(s) && scope === s.scope && seq === s.listSequence) { s.listBusy = false; s.table.setAttribute("aria-busy", "false"); updateControls(s); }
    }
  }
  function renderTable(s) {
    if (!s.records.length) { s.table.replaceChildren(UI.el("p", "orders-empty", "Không có đơn đủ điều kiện nhập kho")); return; }
    s.table.replaceChildren(UI.table(["Mã đơn", "Mã vận đơn", "Bưu cục", "Trạng thái", "Khối lượng", "Thao tác"], s.records.map(row => {
      const actions = UI.el("div", "order-actions");
      const detail = UI.button("Chi tiết đơn", () => { if (alive(s) && !s.pending) window.OrdersPage.showDetail(s, row.id); }); detail.dataset.orderDetail = String(row.id);
      const receive = UI.button("Nhập kho", () => openImport(s, row), "btn btn-outline-orange btn-sm"); receive.dataset.inboundOrder = String(row.id);
      actions.append(detail, receive);
      const code = UI.el("span", "inbound-code", row.orderCode); code.title = row.orderCode;
      const tracking = UI.el("span", "inbound-code", row.trackingNumber); tracking.title = row.trackingNumber;
      return [code, tracking, row.branchName, UI.badge(row.status, statuses[row.status]), UI.weight(row.weightKg), actions];
    })));
  }
  async function openImport(s, row) {
    if (!alive(s) || s.pending || s.modal) return;
    if (s.uncertain.has(row.id)) { await verifyAttempt(s, s.uncertain.get(row.id)); return; }
    if (!canImport(s)) { UI.notice(s.feedback, "Bạn không có quyền KHO_NHAP."); return; }
    const chosen = selectedLocation(s), warehouse = s.warehouse, scope = s.scope;
    if (!warehouse || !chosen || !s.locationsReady || s.catalogBusy || s.locationsBusy) { UI.notice(s.feedback, "Hãy chọn kho và vị trí đang hoạt động trước khi nhập."); s.location.focus(); return; }
    if (!s.records.some(item => item.id === row.id) || row.branchId !== warehouse.branchId || !Object.hasOwn(statuses, row.status)) return;
    const view = UI.dialog(s, "Nhập kho · " + row.orderCode); view.node.classList.add("inbound-dialog"); s.modal = view;
    const modalController = new AbortController(); s.modalController = modalController; updateControls(s);
    const signal = modalController.signal;
    view.onClose(() => { modalController.abort(); if (s.modal === view) s.modal = null; updateControls(s); });
    view.body.append(UI.el("p", "text-secondary", "Đang kiểm tra đơn, quyền và vị trí hiện tại…"));
    try {
      const [order, positions, permissions] = await Promise.all([read(s, "/api/v1/orders/" + row.id, signal),
        read(s, "/api/v1/warehouses/" + warehouse.id + "/locations", signal), window.Auth.getPermissions(s.user, AbortSignal.any([s.abort.signal, signal]))]);
      if (!alive(s) || scope !== s.scope || !view.node.isConnected) return;
      s.permissions = permissions; showPermission(s);
      if (!canImport(s)) throw new Error("Bạn không còn quyền KHO_NHAP.");
      if (!order || order.id !== row.id || order.branchId !== warehouse.branchId) throw new Error("Đơn không thuộc bưu cục của kho đã chọn.");
      if (!Object.hasOwn(statuses, order.status) || order.warehouseId != null) throw new Error("Đơn không còn đủ điều kiện nhập kho. Hãy làm mới danh sách.");
      const locations = validateLocations(positions, warehouse.id);
      s.locations = locations; s.location.replaceChildren(); UI.option(s.location, "", "Chọn vị trí");
      for (const position of locations) UI.option(s.location, position.id, locationName(position));
      s.location.value = locations.some(position => position.id === chosen.id) ? chosen.id : "";
      syncRoute(s);
      if (!locations.some(position => position.id === chosen.id)) throw new Error("Vị trí đã chọn không còn hoạt động hoặc không thuộc kho. Hãy làm mới kho.");
      renderImport(s, view, { order, warehouse, locations, locationId: chosen.id }, scope);
    } catch (error) {
      if (!alive(s) || scope !== s.scope || !view.node.isConnected || error.name === "AbortError") return;
      view.blocked = true; UI.notice(view.body, message(error));
      view.body.append(UI.button("Đóng và làm mới danh sách", () => { view.close(); s.modal = null; loadOrders(s); }, "btn btn-outline-orange"));
    } finally { updateControls(s); }
  }
  function renderImport(s, view, context, scope) {
    const errorBox = UI.el("div"); const form = UI.el("form"); form.noValidate = true;
    const fields = UI.el("fieldset");
    const location = UI.select(context.locations.map(row => ({ id: row.id, name: locationName(row) })), "Chọn vị trí", context.locationId);
    const notes = UI.el("textarea", "form-control"); notes.maxLength = 500; notes.rows = 3;
    const review = UI.button("Xem và xác nhận", null, "btn btn-orange"); review.type = "submit";
    const confirmation = UI.el("div", "warehouse-confirmation d-none"); const confirmText = UI.el("p");
    const send = UI.button("Xác nhận nhập kho", null, "btn btn-orange");
    const back = UI.button("Sửa lại", () => { confirmation.classList.add("d-none"); review.classList.remove("d-none"); });
    const confirmActions = UI.el("div", "order-actions"); confirmActions.append(send, back); confirmation.append(confirmText, confirmActions);
    fields.append(UI.summary([["Đơn", context.order.orderCode], ["Kho", context.warehouse.name], ["Bưu cục", context.warehouse.branchName], ["Trạng thái", statuses[context.order.status]]]),
      UI.field("Vị trí nhập *", location, "mb-3"), UI.field("Ghi chú (tối đa 500 ký tự)", notes, "mb-3"), review, confirmation);
    form.append(fields); view.body.replaceChildren(errorBox, form); let reviewed = null;
    function payload() {
      if (notes.value.length > 500) notes.setCustomValidity("Ghi chú tối đa 500 ký tự.");
      if (!context.locations.some(row => String(row.id) === location.value)) location.setCustomValidity("Chọn vị trí thuộc kho đang hoạt động.");
      if (!form.reportValidity()) throw new Error("Kiểm tra vị trí và ghi chú trước khi xác nhận.");
      return { orderId: context.order.id, warehouseId: context.warehouse.id, locationId: Number(location.value), notes: notes.value.trim() || null };
    }
    form.addEventListener("input", resetReview); form.addEventListener("change", resetReview);
    function resetReview() { if (s.pending) return; notes.setCustomValidity(""); location.setCustomValidity(""); reviewed = null; confirmation.classList.add("d-none"); review.classList.remove("d-none"); }
    form.addEventListener("submit", event => {
      event.preventDefault(); if (s.pending || view.blocked || !alive(s)) return; UI.notice(errorBox, "");
      try { reviewed = payload(); confirmText.textContent = "Nhập " + context.order.orderCode + " vào " + context.warehouse.name + " tại " + location.selectedOptions[0].textContent + (reviewed.notes ? ". Ghi chú: " + reviewed.notes : "") + "?";
        confirmation.classList.remove("d-none"); review.classList.add("d-none"); send.focus(); }
      catch (error) { UI.notice(errorBox, message(error)); }
    });
    send.addEventListener("click", async () => {
      if (!alive(s) || scope !== s.scope || s.pending || view.blocked || !reviewed || !canImport(s)) return;
      let body; try { body = payload(); } catch (error) { UI.notice(errorBox, message(error)); return; }
      if (JSON.stringify(body) !== JSON.stringify(reviewed)) { resetReview(); UI.notice(errorBox, "Dữ liệu đã thay đổi. Hãy xác nhận lại."); return; }
      s.pending = true; fields.disabled = true; view.setBusy(true); updateControls(s); UI.notice(errorBox, "");
      try {
        const result = await window.ApiClient.request("/api/v1/warehouse-transactions/inbound", { method: "POST", body: JSON.stringify(body), signal: AbortSignal.any([s.abort.signal, s.modalController.signal]) });
        if (!alive(s) || scope !== s.scope || !view.node.isConnected) return;
        if (!result || !id(result.transactionId) || typeof result.transactionCode !== "string" || !result.transactionCode.trim()
          || result.orderStatus !== "IN_WAREHOUSE" || result.inventoryStatus !== "STORED"
          || result.orderId !== body.orderId || result.warehouseId !== body.warehouseId || result.locationId !== body.locationId)
          throw new Error("Chưa xác nhận được kết quả nhập kho. Hãy kiểm tra trạng thái đơn.");
        view.close(); s.modal = null; s.pending = false;
        UI.notice(s.feedback, "Nhập kho thành công. Giao dịch: " + result.transactionCode, "success"); await loadOrders(s);
      } catch (error) {
        if (!alive(s) || scope !== s.scope || !view.node.isConnected) return;
        UI.notice(errorBox, message(error));
        if (error.status === 400) {
          reviewed = null; confirmation.classList.add("d-none"); review.classList.remove("d-none");
          notes.setCustomValidity(""); location.setCustomValidity("");
          const errors = error.data?.errors;
          if (errors && typeof errors === "object") for (const [key, values] of Object.entries(errors)) {
            const control = key.toLowerCase() === "notes" ? notes : key.toLowerCase() === "locationid" ? location : null;
            if (control && Array.isArray(values)) control.setCustomValidity(values.join(" "));
          }
        } else {
          view.blocked = true;
          if (error.status === 403) { s.permissions = { known: true, codes: new Set([...s.permissions.codes].filter(code => code !== "KHO_NHAP")) }; showPermission(s); }
          if (!error.status || error.status >= 500) {
            const attempt = { ...body, orderCode: context.order.orderCode }; s.uncertain.set(body.orderId, attempt); renderUncertain(s);
            errorBox.append(UI.el("p", "text-secondary", "Giao dịch có thể đã hoàn thành. Kiểm tra trạng thái trước khi mở thao tác mới; không gửi lại bản xác nhận này."),
              UI.button("Kiểm tra trạng thái đơn", () => verifyAttempt(s, attempt), "btn btn-outline-orange"));
          } else {
            errorBox.append(UI.el("p", "text-secondary", error.status === 409 ? "Đơn đã thay đổi. Danh sách được tải lại; không tự gửi lại thao tác." : "Không thể tiếp tục bản thao tác này."),
              UI.button("Đóng và làm mới danh sách", () => { view.close(); s.modal = null; loadOrders(s); }, "btn btn-outline-orange"));
          }
          s.pending = false; await loadOrders(s);
        }
      } finally {
        if (alive(s)) { s.pending = false; fields.disabled = Boolean(view.blocked); view.setBusy(false); updateControls(s); }
      }
    });
  }
  function renderUncertain(s) {
    s.uncertaintyBox.replaceChildren();
    for (const attempt of s.uncertain.values()) {
      const alert = UI.el("div", "alert alert-warning", "Chưa xác nhận kết quả nhập " + attempt.orderCode + ". ");
      alert.append(UI.button("Kiểm tra trạng thái đơn", () => verifyAttempt(s, attempt), "btn btn-outline-orange btn-sm")); s.uncertaintyBox.append(alert);
    }
  }
  async function verifyAttempt(s, attempt) {
    if (!alive(s) || s.pending || attempt.checking) return; attempt.checking = true;
    const verifiedModal = s.modal;
    try {
      const order = await read(s, "/api/v1/orders/" + attempt.orderId);
      if (!alive(s)) return;
      if (!order || order.id !== attempt.orderId) throw new Error("Không đọc được trạng thái đơn.");
      s.uncertain.delete(attempt.orderId); renderUncertain(s);
      if (verifiedModal && s.modal === verifiedModal) { verifiedModal.close(); s.modal = null; }
      const imported = order.warehouseId === attempt.warehouseId && order.status === "IN_WAREHOUSE";
      UI.notice(s.feedback, imported ? "Đơn đã nhập kho thành công. Không cần gửi lại."
        : Object.hasOwn(statuses, order.status) && order.warehouseId == null ? "Đã đọc lại trạng thái đơn. Hãy kiểm tra danh sách đủ điều kiện và mở thao tác mới để xác nhận lại nếu cần."
          : "Đơn đang ở trạng thái khác hoặc đã được xử lý. Không gửi lại bản thao tác cũ.", imported ? "success" : "info");
      await loadOrders(s);
    } catch (error) { if (alive(s)) UI.notice(s.feedback, "Chưa kiểm tra được trạng thái. " + message(error)); }
    finally { attempt.checking = false; updateControls(s); }
  }
  window.InboundPage = Object.freeze({ mount, destroy });
}());
