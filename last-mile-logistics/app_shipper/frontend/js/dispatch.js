"use strict";

(function () {
  const U = window.AdminUI;
  const stateLabels = {
    PENDING: "Chờ shipper nhận", ACCEPTED: "Đã nhận",
    IN_PROGRESS: "Đang giao", COMPLETED: "Hoàn tất",
    ATTEMPT_FAILED: "Giao thất bại", REJECTED: "Đã từ chối",
    CANCELLED: "Đã hủy", REASSIGNED: "Đã phân công lại"
  };
  let active = null;

  function query(values) { return U.query(values); }
  function status(code, label) {
    return U.el("span", "badge rounded-pill text-bg-" +
      (code === "WAITING_ASSIGNMENT" ? "warning" :
        ["COMPLETED", "ACCEPTED"].includes(code) ? "success" :
          ["CANCELLED", "REJECTED"].includes(code) ? "secondary" : "primary"),
      label || stateLabels[code] || code || "—");
  }

  function card(order, assign) {
    const box = U.el("article", "card border-0 shadow-sm h-100");
    const body = U.el("div", "card-body p-3 p-md-4");
    const top = U.el("div", "d-flex justify-content-between align-items-start gap-2 mb-3");
    const heading = U.el("div");
    heading.append(U.el("h2", "h6 mb-1", order.orderCode || "Đơn #" + order.id),
      U.el("div", "small text-secondary", order.trackingNumber || ""));
    top.append(heading, status(order.status, order.statusName));
    const details = U.el("div", "row g-2 small");
    const values = [
      ["Người nhận", order.receiverName], ["Điện thoại", order.receiverPhone],
      ["Địa chỉ giao", order.deliveryAddress], ["Khối lượng", order.weightKg == null ? "—" : Number(order.weightKg).toLocaleString("vi-VN") + " kg"],
      ["Bưu cục", order.branchName], ["Kho", order.warehouseName]
    ];
    for (const [label, value] of values) {
      const item = U.el("div", "col-12 col-sm-6");
      item.append(U.el("span", "text-secondary", label + ": "), U.el("strong", "", value || "—"));
      details.append(item);
    }
    const actions = U.el("div", "d-flex justify-content-end mt-3");
    const button = U.button("Chọn shipper", () => assign(order), "btn btn-orange");
    button.disabled = order.status !== "WAITING_ASSIGNMENT";
    actions.append(button);
    body.append(top, details, actions);
    box.append(body);
    return box;
  }

  async function chooseShipper(s, order) {
    const d = U.dialog(s, "Phân công " + (order.orderCode || "đơn hàng"));
    if (!d) return;
    const error = U.el("div", "mb-3");
    const intro = U.el("p", "text-secondary", "Chọn shipper và xe đủ điều kiện. Hệ thống sẽ gửi nhiệm vụ tới app shipper ngay sau khi lưu.");
    const loading = U.el("div", "d-flex align-items-center gap-2 text-secondary py-3");
    loading.append(U.el("span", "spinner-border spinner-border-sm"), U.el("span", "", "Đang tìm shipper phù hợp…"));
    d.body.replaceChildren(intro, loading, error);

    try {
      const path = "/api/v1/dispatch/shippers?" + query({ orderId: order.id });
      const result = await s.read(path, d.signal);
      if (!s.alive() || d.closed) return;
      loading.remove();

      const candidates = Array.isArray(result?.items) ? result.items : [];
      if (!candidates.length) {
        U.notice(error, "Chưa có shipper và xe đủ điều kiện cho đơn này.");
        if (result?.excludedVehicles?.length) {
          const excluded = U.el("details", "mt-2");
          excluded.append(U.el("summary", "small", "Xem lý do loại trừ"));
          const list = U.el("ul", "small text-secondary mt-2");
          for (const item of result.excludedVehicles) {
            list.append(U.el("li", "", (item.fullName || item.employeeCode || "Shipper") + " · " + (item.eligibilityReason || "Xe không đủ điều kiện")));
          }
          excluded.append(list); error.append(excluded);
        }
        return;
      }

      const form = U.el("form", "row g-3");
      const wrap = U.el("div", "col-12");
      const label = U.el("label", "form-label", "Shipper · phương tiện");
      const select = U.el("select", "form-select");
      select.required = true;
      const blank = U.el("option", "", "Chọn shipper và xe"); blank.value = ""; select.append(blank);
      for (const item of candidates) {
        const option = U.el("option", "", `${item.fullName} · ${item.employeeCode} · ${item.licensePlate} (${Number(item.remainingWeightKg || 0).toLocaleString("vi-VN")} kg tải còn lại)`);
        option.value = String(item.id) + ":" + String(item.vehicleId);
        select.append(option);
      }
      label.htmlFor = "dispatch-shipper-select"; select.id = label.htmlFor;
      wrap.append(label, select);
      const noteWrap = U.el("div", "col-12");
      const noteLabel = U.el("label", "form-label", "Ghi chú (không bắt buộc)");
      const notes = U.el("textarea", "form-control"); notes.rows = 2; notes.maxLength = 500;
      noteLabel.htmlFor = "dispatch-notes"; notes.id = noteLabel.htmlFor; noteWrap.append(noteLabel, notes);
      const feedback = U.el("div", "col-12");
      const actions = U.el("div", "col-12 d-flex justify-content-end");
      const submit = U.button("Xác nhận phân công", null, "btn btn-orange"); submit.type = "submit";
      actions.append(submit); form.append(wrap, noteWrap, feedback, actions); d.body.append(form);
      form.addEventListener("submit", async event => {
        event.preventDefault();
        if (d.busy || !select.value) { select.reportValidity(); return; }
        const [shipperId, vehicleId] = select.value.split(":").map(Number);
        d.busyState(true); submit.disabled = true; submit.textContent = "Đang lưu…";
        U.notice(feedback, "");
        try {
          await window.ApiClient.request("/api/v1/dispatch/assignments", {
            method: "POST", signal: d.signal,
            body: JSON.stringify({ orderId: order.id, shipperId, vehicleId, notes: notes.value.trim() || null })
          });
          if (!s.alive() || d.closed) return;
          d.close();
          s.message = "Đã phân công " + (order.orderCode || "đơn hàng") + ". Shipper sẽ nhận cập nhật realtime trong app.";
          await load(s, 1);
        } catch (requestError) {
          if (!s.alive() || d.closed || requestError.name === "AbortError" || requestError.sessionExpired) return;
          U.failure(s, feedback, requestError);
        } finally {
          if (!d.closed) { d.busyState(false); submit.disabled = false; submit.textContent = "Xác nhận phân công"; }
        }
      }, { signal: d.signal });
    } catch (requestError) {
      if (!s.alive() || d.closed || requestError.name === "AbortError" || requestError.sessionExpired) return;
      loading.remove(); U.failure(s, error, requestError);
    }
  }

  async function load(s, page = s.page || 1) {
    if (!s.alive()) return;
    s.page = page;
    const epoch = ++s.epoch;
    const keyword = s.search.value.trim();
    const isQueue = s.route.pageId === "dispatch-queue";
    const path = isQueue
      ? "/api/v1/dispatch/orders?" + query({ page, pageSize: 10, keyword })
      : "/api/v1/dispatch/assignments?" + query({ page, pageSize: 10, activeOnly: true, keyword });
    s.list.replaceChildren(U.el("p", "orders-empty", "Đang tải dữ liệu điều phối…"));
    U.notice(s.feedback, "");
    try {
      const result = await s.read(path);
      if (!s.alive() || epoch !== s.epoch) return;
      const items = Array.isArray(result?.items) ? result.items : [];
      s.list.replaceChildren();
      if (!items.length) s.list.append(U.el("p", "orders-empty", isQueue ? "Không có đơn đang chờ phân công." : "Chưa có phân công đang hoạt động."));
      else if (isQueue) {
        const grid = U.el("div", "row g-3");
        for (const order of items) { const cell = U.el("div", "col-12 col-xl-6"); cell.append(card(order, item => chooseShipper(s, item))); grid.append(cell); }
        s.list.append(grid);
      } else {
        const rows = items.map(item => [item.orderCode, item.trackingNumber, item.shipperName, item.licensePlate, status(item.assignmentStatus), item.branchName]);
        s.list.append(U.table(["Mã đơn", "Mã vận đơn", "Shipper", "Xe", "Trạng thái", "Bưu cục"], rows));
      }
      const total = Number(result.totalItems || 0), pages = Math.max(1, Math.ceil(total / Number(result.pageSize || 10)));
      const previous = U.button("‹ Trước", () => load(s, page - 1), "btn btn-outline-orange btn-sm"); previous.disabled = page <= 1;
      const next = U.button("Sau ›", () => load(s, page + 1), "btn btn-outline-orange btn-sm"); next.disabled = page >= pages;
      s.pager.replaceChildren(U.el("span", "small text-secondary me-auto", `${total.toLocaleString("vi-VN")} kết quả · Trang ${page} / ${pages}`), previous, next);
      if (s.message) { U.notice(s.feedback, s.message, "success"); s.message = ""; }
    } catch (error) {
      if (!s.alive() || epoch !== s.epoch || error.name === "AbortError" || error.sessionExpired) return;
      s.list.replaceChildren(); U.failure(s, s.feedback, error, () => load(s, page));
    }
  }

  function mount(container, user, route, context) {
    destroy();
    const s = U.state(container, user, route, context); active = s;
    const card = U.el("section", "orders-card");
    const intro = U.el("p", "text-secondary mb-3", route.pageId === "dispatch-queue"
      ? "Chọn đơn đã sẵn sàng và phân công shipper phù hợp. Nhiệm vụ được đẩy tới app sau khi lưu."
      : "Theo dõi các phân công giao hàng đang hoạt động.");
    const toolbar = U.el("form", "orders-toolbar d-flex flex-column flex-sm-row gap-2 mb-3");
    s.search = U.el("input", "form-control"); s.search.type = "search"; s.search.maxLength = 100;
    s.search.placeholder = "Tìm mã đơn, vận đơn hoặc người nhận";
    const search = U.button("Tìm kiếm", null, "btn btn-outline-orange"); search.type = "submit";
    toolbar.append(s.search, search);
    s.feedback = U.el("div", ""); s.list = U.el("div", "dispatch-list"); s.pager = U.el("nav", "d-flex align-items-center gap-2 mt-3");
    toolbar.addEventListener("submit", event => { event.preventDefault(); load(s, 1); }, { signal: s.abort.signal });
    card.append(intro, toolbar, s.feedback, s.list, s.pager); s.root.append(card);
    load(s, 1);
  }

  function destroy() {
    if (active) { active.destroy(); active = null; }
  }

  window.DispatchPage = Object.freeze({ mount, destroy });
}());
