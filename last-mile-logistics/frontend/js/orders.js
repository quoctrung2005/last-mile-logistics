"use strict";

(function () {
  const statuses = {
    NEW: "Mới tạo",
    CONFIRMED: "Đã tiếp nhận",
    WAITING_INBOUND: "Chờ nhập kho",
    IN_WAREHOUSE: "Đã nhập kho",
    WAITING_ASSIGNMENT: "Chờ phân công",
    ASSIGNED: "Đã phân công",
    HANDED_OVER: "Đã xuất kho / Bàn giao",
    EN_ROUTE_PICKUP: "Đang đến lấy hàng",
    PICKED_UP: "Đã lấy hàng",
    IN_DELIVERY: "Đang giao",
    DELIVERED: "Giao thành công",
    FAILED: "Giao thất bại",
    RETRY_WAITING: "Chờ giao lại",
    RETURNING: "Chuyển hoàn",
    RETURNED: "Đã hoàn hàng",
    COMPLETED: "Hoàn tất",
    CANCELLED: "Đã hủy",
  };

  const cancelStates = new Set([
    "NEW",
    "CONFIRMED",
    "WAITING_INBOUND",
    "IN_WAREHOUSE",
    "WAITING_ASSIGNMENT",
    "ASSIGNED",
  ]);

  const grants = {
    create: ["ADMIN", "DISPATCHER"],
    update: ["ADMIN", "BRANCH_MANAGER", "DISPATCHER"],
    cancel: ["ADMIN", "BRANCH_MANAGER"],
  };

  const currency = new Intl.NumberFormat("vi-VN", {
    style: "currency",
    currency: "VND",
    maximumFractionDigits: 2,
  });

  const number = new Intl.NumberFormat("vi-VN", {
    maximumFractionDigits: 3,
  });

  const volumeNumber = new Intl.NumberFormat("vi-VN", {
    maximumFractionDigits: 6,
  });

  const dates = new Intl.DateTimeFormat("vi-VN", {
    timeZone: "Asia/Ho_Chi_Minh",
    dateStyle: "short",
    timeStyle: "short",
  });

  const vietnamOffsetMs = 7 * 60 * 60 * 1000;

  let active = null;
  let uniqueId = 0;
  let detailFeedback = null;

  const dialogDisposers = new WeakMap();

  function text(value) {
    return value === null || value === undefined || value === ""
      ? "—"
      : String(value);
  }

  function money(value) {
    return value == null || !Number.isFinite(Number(value))
      ? "—"
      : currency.format(Number(value));
  }

  function weight(value) {
    return value == null || !Number.isFinite(Number(value))
      ? "—"
      : number.format(Number(value)) + " kg";
  }

  function parseApiDate(value) {
    if (value == null || value === "") return null;

    const raw = String(value).trim();

    // Tương thích dữ liệu UTC cũ chưa có đuôi Z.
    const normalized = /(?:Z|[+-]\d{2}:\d{2})$/i.test(raw) ? raw : raw + "Z";

    const parsed = new Date(normalized);

    return Number.isNaN(parsed.getTime()) ? null : parsed;
  }

  function date(value) {
    const parsed = parseApiDate(value);
    return parsed ? dates.format(parsed) : "—";
  }

  function toVietnamInput(value) {
    const parsed = parseApiDate(value);
    if (!parsed) return "";

    const shifted = new Date(parsed.getTime() + vietnamOffsetMs);
    const year = shifted.getUTCFullYear();

    if (year < 1 || year > 9999) return "";

    // Giữ đến giây, không phụ thuộc múi giờ máy đang mở trình duyệt.
    return shifted.toISOString().slice(0, 19);
  }

  function vietnamInputToIso(value) {
    if (!value) return null;

    if (!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(?::\d{2})?$/.test(value)) {
      throw new Error("Thời gian không hợp lệ.");
    }

    const normalized = value.length === 16 ? value + ":00" : value;
    const parsed = new Date(normalized + "+07:00");

    if (
      Number.isNaN(parsed.getTime()) ||
      parsed.getUTCFullYear() < 1 ||
      parsed.getUTCFullYear() > 9999
    ) {
      throw new Error("Thời gian nằm ngoài phạm vi được hỗ trợ.");
    }

    const iso = parsed.toISOString();

    // Chặn trường hợp Date tự chuẩn hóa ngày không tồn tại.
    if (toVietnamInput(iso) !== normalized) {
      throw new Error("Ngày hoặc giờ không hợp lệ.");
    }

    return iso;
  }

  function sameSecond(left, right) {
    const a = parseApiDate(left);
    const b = parseApiDate(right);

    return (
      a !== null &&
      b !== null &&
      Math.floor(a.getTime() / 1000) === Math.floor(b.getTime() / 1000)
    );
  }

  function el(tag, className, value) {
    const node = document.createElement(tag);

    if (className) node.className = className;
    if (value instanceof Node) {
      node.append(value);
    } else if (value !== undefined) {
      node.textContent = text(value);
    }

    return node;
  }

  function button(label, callback, className) {
    const node = el(
      "button",
      className || "btn btn-outline-secondary btn-sm",
      label,
    );

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

  function option(selectNode, value, label) {
    const node = el("option", "", label);
    node.value = value;
    selectNode.append(node);
  }

  function select(items, label, selected) {
    const node = el("select", "form-select");
    node.required = true;

    option(node, "", label);

    for (const item of items || []) {
      option(node, item.id, item.name);
    }

    node.value = selected == null ? "" : selected;
    return node;
  }

  function field(label, control, className) {
    const wrapper = el("div", className || "col-md-6");
    control.id = "order-field-" + ++uniqueId;

    const caption = el(
      control.tagName === "BUTTON" ? "span" : "label",
      "form-label d-block",
      label,
    );

    if (control.tagName !== "BUTTON") {
      caption.htmlFor = control.id;
    }

    wrapper.append(caption, control);
    return wrapper;
  }

  function notice(container, message, type) {
    container.replaceChildren();

    if (!message) return;

    const node = el("div", "alert alert-" + (type || "danger"), message);
    node.setAttribute("role", type === "success" ? "status" : "alert");
    container.append(node);
  }

  function badge(code, label) {
    const tone = ["DELIVERED", "COMPLETED"].includes(code)
      ? "success"
      : ["FAILED", "CANCELLED"].includes(code)
        ? "danger"
        : code === "NEW"
          ? "neutral"
          : "orange";

    return el(
      "span",
      "order-status order-status-" + tone,
      label || statuses[code] || text(code),
    );
  }

  function table(headers, rows) {
    const wrapper = el("div", "table-responsive");
    const node = el("table", "table orders-table align-middle mb-0");
    const head = el("thead");
    const heading = el("tr");

    for (const label of headers) {
      const cell = el("th");
      cell.scope = "col";
      if (label instanceof Node) {
        cell.append(label);
      } else {
        cell.textContent = text(label);
      }
      heading.append(cell);
    }

    head.append(heading);

    const body = el("tbody");

    for (const values of rows) {
      const row = el("tr");

      for (const value of values) {
        const cell = el("td");
        cell.append(
          value instanceof Node ? value : document.createTextNode(text(value)),
        );
        row.append(cell);
      }

      body.append(row);
    }

    if (!rows.length) {
      const row = el("tr");
      const cell = el(
        "td",
        "text-center text-secondary py-4",
        "Chưa có dữ liệu.",
      );

      cell.colSpan = headers.length;
      row.append(cell);
      body.append(row);
    }

    node.append(head, body);
    wrapper.append(node);
    return wrapper;
  }

  function summary(pairs) {
    const grid = el("dl", "order-summary");

    for (const [label, value] of pairs) {
      const item = el("div");
      item.append(el("dt", "", label), el("dd", "", value));
      grid.append(item);
    }

    return grid;
  }

  function section(title, ...children) {
    const node = el("section", "order-section");
    node.append(el("h3", "", title), ...children);
    return node;
  }

  function pagination(container, page, pageSize, totalItems, onPage, noun) {
    const pages = Math.min(
      100000,
      Math.max(1, Math.ceil(totalItems / pageSize)),
    );

    const previous = button("‹ Trước", () => onPage(page - 1));
    previous.disabled = page <= 1;

    const next = button("Sau ›", () => onPage(page + 1));
    next.disabled = page >= pages;

    container.replaceChildren(
      el(
        "span",
        "text-secondary",
        number.format(totalItems) +
          " " +
          (noun || "dòng") +
          " · Trang " +
          page +
          " / " +
          pages,
      ),
      previous,
      next,
    );
  }

  function permitted(s, action) {
    const code = {
      create: "DONHANG_TAO",
      update: "DONHANG_CAPNHAT",
      cancel: "DONHANG_HUY",
    }[action];

    return s.permissions?.known
      ? s.permissions.codes.has(code)
      : grants[action].includes(s.user.role);
  }

  function inScope(s, order) {
    if (!s?.user || !order) return false;

    if (s.user.role === "ADMIN") return true;

    const accountBranchId = Number(s.user.branchId);
    const orderBranchId = Number(order.branchId);

    return (
      Number.isSafeInteger(accountBranchId) &&
      accountBranchId > 0 &&
      Number.isSafeInteger(orderBranchId) &&
      orderBranchId > 0 &&
      accountBranchId === orderBranchId
    );
  }

  function missingEditFields(order) {
    const missing = ["branchId", "senderId", "receiverId", "serviceId"].filter(
      (key) => !Number.isSafeInteger(order[key]) || order[key] <= 0,
    );

    if (
      typeof order.version !== "string" ||
      !/^[A-Za-z0-9+/]{11}=$/.test(order.version)
    ) {
      missing.push("version");
    }

    for (const key of ["requestedDeliveryAt", "expectedDeliveryAt"]) {
      // null hợp lệ với đơn cũ, nhưng API phải trả rõ trường này.
      if (
        !Object.prototype.hasOwnProperty.call(order, key) ||
        (order[key] !== null &&
          (typeof order[key] !== "string" ||
            !parseApiDate(order[key]) ||
            !toVietnamInput(order[key])))
      ) {
        missing.push(key);
      }
    }

    return missing;
  }

  function needsAddressSelection(order) {
    return (
      order.requiresAddressSelection === true ||
      ["pickupAddressId", "deliveryAddressId"].some(
        (key) => !Number.isSafeInteger(order[key]) || order[key] <= 0,
      )
    );
  }

  function missingEditMessage(missing) {
    const labels = {
      branchId: "bưu cục",
      senderId: "người gửi",
      receiverId: "người nhận",
      serviceId: "dịch vụ",
      version: "phiên bản dữ liệu",
      requestedDeliveryAt: "thời gian yêu cầu giao",
      expectedDeliveryAt: "hạn giao",
    };

    return (
      "Chưa tải đủ dữ liệu để sửa đơn: " +
      missing.map((key) => labels[key] || key).join(", ") +
      ". Hãy tải lại chi tiết."
    );
  }

  async function read(s, path, signal) {
    return window.ApiClient.request(path, {
      signal: signal
        ? AbortSignal.any([s.abort.signal, signal])
        : s.abort.signal,
    });
  }

  function dialog(s, title, wide) {
    const node = el(
      "dialog",
      "orders-dialog" + (wide ? " orders-dialog-wide" : ""),
    );

    const header = el("div", "orders-dialog-header");
    const heading = el("h2", "", title);

    heading.id = "order-dialog-title-" + ++uniqueId;
    node.setAttribute("aria-labelledby", heading.id);

    let closed = false;
    let busy = false;

    const controller = new AbortController();
    const closeHandlers = new Set();

    function dispose() {
      if (closed) return;

      closed = true;
      controller.abort();
      s.dialogs.delete(node);
      node.remove();
      dialogDisposers.delete(node);

      for (const callback of closeHandlers) callback();
      closeHandlers.clear();
    }

    function closeDialog() {
      node.close();
      dispose();
    }

    const close = button("Đóng", closeDialog);
    header.append(heading, close);

    const body = el("div", "orders-dialog-body");

    node.append(header, body);
    document.body.append(node);

    s.dialogs.add(node);
    dialogDisposers.set(node, dispose);

    node.addEventListener("cancel", (event) => {
      event.preventDefault();
      if (!busy) closeDialog();
    });

    node.addEventListener("close", dispose);
    node.showModal();

    return {
      node,
      body,
      signal: AbortSignal.any([s.abort.signal, controller.signal]),
      close: closeDialog,
      onClose(callback) {
        if (closed) callback();
        else closeHandlers.add(callback);
      },
      setBusy(value) {
        busy = value;
        close.disabled = value;
        node.setAttribute("aria-busy", String(value));
      },
    };
  }

  function closeDialogs(s) {
    for (const node of [...s.dialogs]) {
      node.close();
      dialogDisposers.get(node)?.();
    }
  }

  function routeView(s, title, backHash) {
    const detail = s.route?.name === "order-detail";
    const node = el("section", detail ? "order-detail" : "orders-card");

    const header = el(
      "div",
      detail ? "order-detail-navigation" : "orders-toolbar",
    );

    const body = el("div", "orders-route-body");
    const back = el("a", "btn btn-outline-secondary", "Quay lại");
    back.href = backHash;

    if (detail) {
      const breadcrumb = el("nav", "order-breadcrumb");
      breadcrumb.setAttribute("aria-label", "Đường dẫn đơn hàng");

      const parent = window.Router.parse(backHash);
      const link = el("a", "", parent.label);
      link.href = backHash;

      breadcrumb.append(link, el("span", "", "/"), el("span", "", title));
      header.append(breadcrumb, back);
    } else {
      header.append(el("h2", "", title), back);
    }

    node.append(header, body);
    s.container.replaceChildren(node);

    return {
      node,
      body,
      close: () => window.Router.navigate(backHash),
      setBusy(value) {
        node.setAttribute("aria-busy", String(value));
        back.classList.toggle("disabled", value);
        back.setAttribute("aria-disabled", String(value));
      },
    };
  }

  function navigateDetail(id, message, query = {}, replace = false) {
    detailFeedback = message ? { id: Number(id), message } : null;

    window.Router.navigate(window.Router.href("order-detail", { id }, query), {
      replace,
      force: true,
    });
  }

  function orderQuery(s) {
    return s.route?.pageId === "orders"
      ? window.Router.current()?.query || s.route.query
      : {};
  }

  function destroy() {
    if (!active) return;

    active.dead = true;
    active.releaseFormGuard?.();
    clearTimeout(active.searchTimer);
    active.abort.abort();

    if (active.listAbort) active.listAbort.abort();

    closeDialogs(active);
    active = null;
  }

  
  function updateBulkBar(s) {
    if (!s.bulkBar) return;
    const count = s.selectedOrders ? s.selectedOrders.size : 0;
    if (count === 0) {
      s.bulkBar.classList.add("d-none");
      s.bulkBar.replaceChildren();
      return;
    }
    s.bulkBar.classList.remove("d-none");
    const newCount = [...s.selectedOrders.values()].filter(o => o.status === "NEW").length;

    const countText = el("span", "fw-bold me-auto text-dark", "Đã chọn " + count + " đơn hàng");
    const actions = el("div", "d-flex gap-2 align-items-center flex-wrap");

    if (permitted(s, "update") && newCount > 0) {
      const confirmBtn = button("⚡ Tiếp nhận hàng loạt (" + newCount + " đơn NEW)", () => executeBatchConfirmOrders(s), "btn btn-orange btn-sm");
      actions.append(confirmBtn);
    }

    const printBtn = button("🖨️ In tem vận đơn (" + count + " đơn)", () => {
      if (window.WaybillPrinter) {
        window.WaybillPrinter.print([...s.selectedOrders.values()]);
      }
    }, "btn btn-outline-dark btn-sm");
    actions.append(printBtn);

    const clearBtn = button("✕ Bỏ chọn", () => {
      s.selectedOrders.clear();
      updateBulkBar(s);
      if (s.list) s.list.querySelectorAll(".order-row-check").forEach(c => c.checked = false);
      const headCheck = s.list ? s.list.querySelector(".order-head-check") : null;
      if (headCheck) headCheck.checked = false;
    }, "btn btn-outline-secondary btn-sm");
    actions.append(clearBtn);

    s.bulkBar.replaceChildren(countText, actions);
  }

  async function executeBatchConfirmOrders(s) {
    const newOrders = [...s.selectedOrders.values()].filter(o => o.status === "NEW");
    if (!newOrders.length) {
      notice(s.alert, "Không có đơn hàng nào ở trạng thái Mới tạo (NEW) để tiếp nhận.", "warning");
      return;
    }
    const confirmed = confirm("Xác nhận tiếp nhận " + newOrders.length + " đơn hàng đã chọn sang trạng thái Đã tiếp nhận (CONFIRMED)?");
    if (!confirmed) return;

    notice(s.alert, "Đang xử lý tiếp nhận " + newOrders.length + " đơn hàng...", "info");
    let successCount = 0;
    let failCount = 0;

    for (const order of newOrders) {
      try {
        await window.ApiClient.request("/api/v1/orders/" + order.id + "/confirm", {
          method: "POST",
          body: JSON.stringify({}),
          signal: s.abort.signal
        });
        successCount++;
        s.selectedOrders.delete(order.id);
      } catch (err) {
        failCount++;
      }
    }

    updateBulkBar(s);
    notice(s.alert, "Đã tiếp nhận thành công " + successCount + " đơn hàng" + (failCount ? " (thất bại: " + failCount + " đơn)" : "") + ".", successCount ? "success" : "danger");
    await loadList(s);
  }

  function mount(container, user, route, context) {
    destroy();

    const query = route.query;

    const s = {
      container,
      user,
      route,
      permissions: context.permissions,
      page: query.page || 1,
      pageSize: query.pageSize || 10,
      keyword: query.keyword || "",
      status: query.status || "",
      branchId: query.branchId || "",
      operationalGroup: query.operationalGroup || "",
      abort: new AbortController(),
      dialogs: new Set(),
      dead: false,
      sequence: 0,
    };

    active = s;
    container.replaceChildren();

    s.returnHref = query.returnTo || window.Router.href("orders", {}, query);
    s.selectedOrders = new Map();
    s.bulkBar = el("div", "orders-bulk-bar d-none d-flex justify-content-between align-items-center p-2 mb-3 bg-light border rounded");

    if (route.mode === "create") {
      openForm(s);
      return;
    }

    if (route.mode === "detail") {
      const message =
        detailFeedback?.id === Number(route.params.id)
          ? detailFeedback.message
          : "";

      detailFeedback = null;
      openDetail(s, route.params.id, message);
      return;
    }

    if (route.mode === "edit") {
      openEditRoute(s, route.params.id);
      return;
    }

    const card = el("section", "orders-card");
    const toolbar = el("div", "orders-toolbar");
    const intro = el("div");

    intro.append(
      el("h2", "", "Quản lý đơn hàng"),
      el(
        "p",
        "text-secondary mb-0",
        "Tra cứu mã đơn, mã vận đơn và xử lý đơn trong phạm vi bưu cục.",
      ),
    );

    const actions = el("div", "order-actions");
    actions.append(button("Tải lại", () => loadList(s)));

    if (permitted(s, "create")) {
      actions.append(
        button(
          "+ Tạo đơn",
          () =>
            window.Router.navigate(
              window.Router.href("order-create", {}, orderQuery(s)),
            ),
          "btn btn-orange",
        ),
      );
    }

    toolbar.append(intro, actions);

    const filters = el("form", "row g-3 orders-filters");

    const keyword = input("search", s.keyword, {
      maxLength: 100,
      placeholder: "Mã đơn hoặc mã vận đơn",
    });

    const status = select(
      Object.entries(statuses).map(([id, name]) => ({ id, name })),
      "Tất cả trạng thái",
    );

    status.required = false;
    status.value = s.status;
    status.disabled = !!s.operationalGroup;

    const size = select(
      [...new Set([s.pageSize, 10, 20, 50, 100])]
        .sort((a, b) => a - b)
        .map((id) => ({ id, name: id + " đơn / trang" })),
      "Số dòng",
      s.pageSize,
    );

    const search = button("Tìm kiếm", null, "btn btn-orange w-100");
    search.type = "submit";

    filters.append(
      field("Tìm đơn", keyword, "col-lg-5 col-md-6"),
      field("Trạng thái", status, "col-lg-3 col-md-6"),
      field("Số dòng", size, "col-lg-2 col-md-6"),
      field("Tra cứu", search, "col-lg-2 col-md-6"),
    );

    filters.addEventListener("submit", (event) => {
      event.preventDefault();
      s.keyword = keyword.value.trim();
      s.page = 1;
      loadList(s);
    });

    keyword.addEventListener("input", () => {
      s.keyword = keyword.value.trim();
      s.page = 1;

      if (s.listAbort) s.listAbort.abort();

      s.sequence++;
      s.pager.replaceChildren();

      clearTimeout(s.searchTimer);
      s.searchTimer = setTimeout(() => loadList(s), 300);
    });

    keyword.addEventListener("search", () => {
      s.keyword = keyword.value.trim();
      s.page = 1;
      loadList(s);
    });

    status.addEventListener("change", () => {
      s.status = status.value;
      s.keyword = keyword.value.trim();
      s.page = 1;
      loadList(s);
    });

    size.addEventListener("change", () => {
      s.pageSize = Number(size.value);
      s.keyword = keyword.value.trim();
      s.page = 1;
      loadList(s);
    });

    s.alert = el("div", "orders-message");
    s.list = el("div");
    s.pager = el("nav", "orders-pagination");
    s.pager.setAttribute("aria-label", "Phân trang đơn hàng");

    card.append(toolbar);

    if (s.operationalGroup || s.branchId) {
      const scope = el("div", "alert alert-info mx-3 my-2");

      const labels = {
        waitingInbound: "Chờ nhập kho",
        inWarehouse: "Trong kho",
        waitingHandover: "Chờ bàn giao",
        overdue: "Đơn quá hạn giao",
        waitingAssignment: "Chờ phân công",
        inDelivery: "Đang giao",
        failedNeedsAction: "Giao thất bại chưa có phương án",
      };

      scope.append(
        document.createTextNode(
          (labels[s.operationalGroup] || "Đơn hàng") +
            " · " +
            (s.branchId ? "Bưu cục #" + s.branchId : "Phạm vi tài khoản") +
            " ",
        ),
      );

      if (s.operationalGroup) {
        scope.append(
          button("Bỏ lọc nhóm", () =>
            window.Router.navigate(
              window.Router.href("orders", {}, { branchId: s.branchId }),
            ),
          ),
        );
      }

      card.append(scope);
    }

    card.append(filters, s.alert, s.bulkBar, s.list, s.pager);
    container.append(card);

    loadList(s);
  }

  async function loadList(s) {
    if (s.dead || !s.list) return;

    window.Router.updateQuery(
      {
        page: s.page,
        pageSize: s.pageSize,
        keyword: s.keyword,
        status: s.status,
        branchId: s.branchId,
        operationalGroup: s.operationalGroup,
      },
      s.route,
    );

    clearTimeout(s.searchTimer);

    if (s.listAbort) s.listAbort.abort();

    const controller = new AbortController();
    s.listAbort = controller;

    const sequence = ++s.sequence;

    s.list.setAttribute("aria-busy", "true");
    s.list.replaceChildren(
      el("p", "orders-empty", "Đang tải danh sách đơn hàng…"),
    );

    s.pager.replaceChildren();
    notice(s.alert, "");

    const query = new URLSearchParams({
      page: s.page,
      pageSize: s.pageSize,
    });

    if (s.keyword) query.set("keyword", s.keyword);
    if (s.status) query.set("status", s.status);
    if (s.branchId) query.set("branchId", s.branchId);

    if (s.operationalGroup) {
      query.set("operationalGroup", s.operationalGroup);
    }

    try {
      const result = await read(
        s,
        "/api/v1/orders?" + query,
        controller.signal,
      );

      if (s.dead || sequence !== s.sequence) return;

      window.ApiClient.validatePage(result, "/api/v1/orders", ["id"]);

      const pages = Math.min(
        100000,
        Math.max(1, Math.ceil(result.totalItems / s.pageSize)),
      );

      if (s.page > pages) {
        s.page = pages;
        await loadList(s);
        return;
      }

      if (!result.items.length) {
        s.list.replaceChildren(
          el(
            "p",
            "orders-empty",
            "Không có đơn hàng phù hợp. Hãy đổi từ khóa hoặc bộ lọc.",
          ),
        );
      } else {
        const checkAll = el("input", "form-check-input order-head-check");
        checkAll.type = "checkbox";
        checkAll.setAttribute("aria-label", "Chọn tất cả đơn trên trang");
        checkAll.checked = result.items.length > 0 && result.items.every(o => s.selectedOrders.has(o.id));
        checkAll.addEventListener("change", () => {
          for (const order of result.items) {
            if (checkAll.checked) s.selectedOrders.set(order.id, order);
            else s.selectedOrders.delete(order.id);
          }
          updateBulkBar(s);
          s.list.querySelectorAll(".order-row-check").forEach(c => c.checked = checkAll.checked);
        });

        s.list.replaceChildren(
          table(
            [
              checkAll,
              "Mã đơn",
              "Mã vận đơn",
              "Bưu cục",
              "Người gửi",
              "Người nhận",
              "Trạng thái",
              "Khối lượng",
              "COD",
              "Phí",
              "Hạn giao (VN)",
              "Ngày tạo (VN)",
              "Thao tác",
            ],
            result.items.map((order) => {
              const checkRow = el("input", "form-check-input order-row-check");
              checkRow.type = "checkbox";
              checkRow.checked = s.selectedOrders.has(order.id);
              checkRow.addEventListener("change", () => {
                if (checkRow.checked) s.selectedOrders.set(order.id, order);
                else s.selectedOrders.delete(order.id);
                checkAll.checked = result.items.every(o => s.selectedOrders.has(o.id));
                updateBulkBar(s);
              });

              const actionsCol = el("div", "d-flex gap-1 align-items-center");
              actionsCol.append(
                button("Chi tiết", () => navigateDetail(order.id, "", orderQuery(s))),
                button("🖨️", () => window.WaybillPrinter ? window.WaybillPrinter.print([order]) : null, "btn btn-outline-secondary btn-sm p-1", "In phiếu gửi")
              );

              return [
                checkRow,
                button(
                  text(order.orderCode),
                  () => navigateDetail(order.id, "", orderQuery(s)),
                  "btn btn-link order-code p-0",
                ),
                order.trackingNumber,
                order.branchName,
                order.senderName,
                order.receiverName,
                badge(order.status, order.statusName),
                weight(order.weightKg),
                money(order.codAmount),
                money(order.shippingFee),
                date(order.expectedDeliveryAt),
                date(order.createdAt),
                actionsCol,
              ];
            }),
          ),
        );
        updateBulkBar(s);
      }

      pagination(
        s.pager,
        s.page,
        s.pageSize,
        result.totalItems,
        (page) => {
          s.page = page;
          loadList(s);
        },
        "đơn",
      );
    } catch (error) {
      if (s.dead || sequence !== s.sequence || error.name === "AbortError") {
        return;
      }

      s.list.replaceChildren(
        el("p", "orders-empty", "Chưa tải được danh sách."),
      );

      notice(s.alert, error.message);
      s.pager.append(button("Thử lại", () => loadList(s)));
    } finally {
      if (!s.dead && sequence === s.sequence) {
        s.list.setAttribute("aria-busy", "false");
      }
    }
  }

  async function openDetail(s, id, message) {
    if (s.dead) return;

    const view = routeView(s, "Chi tiết đơn hàng", s.returnHref);

    async function reload() {
      if (s.dead) return;

      s.detailAbort?.abort();

      const controller = new AbortController();
      s.detailAbort = controller;

      const sequence = ++s.sequence;

      view.node.setAttribute("aria-busy", "true");
      view.body.replaceChildren(
        el("p", "text-secondary", "Đang tải chi tiết…"),
      );

      try {
        const order = await read(
          s,
          "/api/v1/orders/" + encodeURIComponent(id),
          controller.signal,
        );

        if (
          s.dead ||
          controller.signal.aborted ||
          sequence !== s.sequence ||
          !view.node.isConnected
        ) {
          return;
        }

        if (!order || Number(order.id) !== Number(id)) {
          throw new Error("API chi tiết trả dữ liệu không hợp lệ.");
        }

        renderDetail(s, view, order, reload, message);
      } catch (error) {
        if (
          s.dead ||
          controller.signal.aborted ||
          sequence !== s.sequence ||
          !view.node.isConnected ||
          error.name === "AbortError"
        ) {
          return;
        }

        const errorBox = el("div");
        notice(errorBox, error.message);

        view.body.replaceChildren(errorBox, button("Tải lại chi tiết", reload));
      } finally {
        if (!s.dead && sequence === s.sequence) {
          view.node.setAttribute("aria-busy", "false");
        }
      }
    }

    await reload();
  }

  function renderDetail(s, view, order, reload, message) {
    const body = view.body;
    body.replaceChildren();

    const feedback = el("div");
    if (message) notice(feedback, message, "success");

    const top = el("div", "order-detail-hero");
    const identity = el("div", "order-detail-identity");

    identity.append(
      el("h2", "order-detail-code", order.orderCode),
      el("p", "order-tracking", "Mã vận đơn: " + text(order.trackingNumber)),
    );

    const actions = el("div", "order-actions order-detail-actions");

    const actionButton = (label, callback, style) =>
      button(
        label,
        () => {
          if (!s.dead && !s.dialogs.size) callback();
        },
        style,
      );

    actions.append(actionButton("Làm mới", reload));
    actions.append(actionButton("🖨️ In phiếu gửi", () => window.WaybillPrinter ? window.WaybillPrinter.print([order]) : null, "btn btn-outline-dark btn-sm"));
    if(window.PickupReceipts)actions.append(actionButton("Biên nhận tài xế nhận kiện",()=>window.PickupReceipts.show(s,order.id)));
    if(window.PickupIssues)actions.append(actionButton("Sự cố nhận kiện / Xử lý",()=>window.PickupIssues.show(s,order.id)));

    const scoped = !s.readOnly && inScope(s, order);
    const missing = missingEditFields(order);

    if (scoped && order.status === "NEW" && permitted(s, "update")) {
      const edit = actionButton(
        "Sửa",
        () =>
          window.Router.navigate(
            window.Router.href("order-edit", { id: order.id }, orderQuery(s)),
          ),
        "btn btn-orange btn-sm",
      );

      edit.disabled = missing.length > 0;
      edit.title = missing.length
        ? "API chi tiết thiếu hoặc sai dữ liệu: " + missing.join(", ")
        : "Sửa đơn mới tạo";

      actions.append(edit);
    }
    if (scoped && order.status === "IN_WAREHOUSE" && permitted(s, "update")) {
      actions.append(
        actionButton(
          "Sửa lịch giao",
          () => openDeliverySchedule(s, order),
          "btn btn-outline-orange btn-sm",
        ),
      );
    }
    if (scoped && permitted(s, "create")) {
      actions.append(actionButton("Báo giá", () => openQuote(s, order)));
    }

    if (scoped && order.status === "NEW" && permitted(s, "update")) {
      actions.append(
        actionButton(
          "Xác nhận",
          () => openAction(s, view, order, "confirm"),
          "btn btn-outline-orange btn-sm",
        ),
      );
    }

    if (scoped && cancelStates.has(order.status) && permitted(s, "cancel")) {
      actions.append(
        actionButton(
          "Hủy đơn",
          () => openAction(s, view, order, "cancel"),
          "btn btn-outline-danger btn-sm",
        ),
      );
    }

    top.append(identity, badge(order.status, order.statusName));
    body.append(feedback, top, actions);

    if (
      scoped &&
      permitted(s, "update") &&
      order.status === "NEW" &&
      missing.length
    ) {
      const warning = el("div", "alert alert-warning");

      warning.append(
        el("p", "mb-2", missingEditMessage(missing)),
        button("Tải lại chi tiết", reload),
      );

      body.append(warning);
    } else if (
      scoped &&
      permitted(s, "update") &&
      order.status === "NEW" &&
      needsAddressSelection(order)
    ) {
      body.append(
        el(
          "p",
          "alert alert-info",
          "Khi sửa đơn, cần chọn lại địa chỉ lấy / giao từ danh sách địa chỉ của khách hàng.",
        ),
      );
    }

    const grid = el("div", "order-detail-grid");

    const general = section(
      "Thông tin chung",
      summary([
        ["Bưu cục", order.branchName],
        ["Dịch vụ", order.serviceName],
        ["Ưu tiên (1–5)", order.priority],
        ["Khối lượng", weight(order.weightKg)],
        ["Ngày tạo (giờ VN)", date(order.createdAt)],
        ["Cập nhật (giờ VN)", date(order.updatedAt)],
        ["Yêu cầu giao (giờ VN)", date(order.requestedDeliveryAt)],
        ["Hạn giao (giờ VN)", date(order.expectedDeliveryAt)],
      ]),
      el("p", "order-note", "Ghi chú: " + text(order.notes)),
    );

    const finance = section(
      "Phí và COD",
      summary([
        ["Phí vận chuyển", money(order.shippingFee)],
        ["Thu hộ COD", money(order.codAmount)],
        ["Giá trị khai báo", money(order.declaredValue)],
      ]),
      table(
        ["Khoản phí", "Số tiền", "Mô tả"],
        (order.fees || []).map((fee) => [
          {
            SHIPPING: "Phí vận chuyển",
            RETURN: "Phí chuyển hoàn",
            SURCHARGE: "Phụ phí",
            DISCOUNT: "Giảm giá",
            OTHER: "Phí khác",
          }[fee.type] || fee.type,
          money(fee.amount),
          fee.description,
        ]),
      ),
    );

    grid.append(general, finance);

    for (const type of ["PICKUP", "DELIVERY"]) {
      const point = (order.deliveryPoints || []).find(
        (item) => item.type === type,
      );

      const contact = section(
        type === "PICKUP"
          ? "Người gửi · Điểm lấy hàng"
          : "Người nhận · Điểm giao hàng",
        summary([
          [
            type === "PICKUP" ? "Người gửi" : "Người nhận",
            type === "PICKUP" ? order.senderName : order.receiverName,
          ],
          ["Người liên hệ", point?.contactName],
          ["Điện thoại", point?.phone],
        ]),
      );

      contact.append(
        point
          ? el("p", "order-address", point.address)
          : el("p", "text-secondary", "Chưa có điểm giao nhận."),
      );

      if (point?.notes) {
        contact.append(el("p", "order-note", "Ghi chú: " + point.notes));
      }

      grid.append(contact);
    }

    const goods = section(
      "Hàng hóa",
      table(
        [
          "Tên hàng",
          "Loại",
          "SL",
          "Kg / đơn vị",
          "Giá trị",
          "Dễ vỡ",
          "Kích thước (cm)",
          "Ghi chú",
        ],
        (order.items || []).map((item) => [
          item.name,
          item.type,
          item.quantity,
          weight(item.unitWeightKg),
          money(item.value),
          item.fragile ? "Có" : "Không",
          [item.lengthCm, item.widthCm, item.heightCm].map(text).join(" × "),
          item.notes,
        ]),
      ),
    );

    goods.classList.add("order-detail-wide");
    grid.append(goods);

    const timeline = el("ol", "order-timeline");

    for (const history of order.statusHistory || []) {
      const entry = el("li");
      const title = el("div", "order-history-title");
      const time = el("time", "", date(history.changedAt));

      title.append(badge(history.newStatus), time);
      entry.append(title);

      entry.append(
        el(
          "p",
          "order-history-meta",
          "Người thực hiện: " +
            text(
              history.changedByName ||
                (history.changedBy != null
                  ? "Tài khoản #" + history.changedBy
                  : null),
            ),
        ),
      );

      if (history.previousStatus) {
        entry.append(
          el(
            "p",
            "order-history-meta",
            "Từ: " +
              (statuses[history.previousStatus] || history.previousStatus),
          ),
        );
      }

      if (history.reason) {
        entry.append(el("p", "order-history-reason", history.reason));
      }

      timeline.append(entry);
    }

    const historyCard = section(
      "Lịch sử trạng thái",
      timeline.children.length
        ? timeline
        : el("p", "text-secondary mb-0", "Chưa có lịch sử trạng thái."),
    );

    historyCard.classList.add("order-detail-wide");
    grid.append(historyCard);
    body.append(grid);

    const internal = el("details", "order-internal");

    internal.append(
      el("summary", "", "Dữ liệu kỹ thuật"),
      summary([
        ["ID", order.id],
        ["Version", order.version || "API chi tiết chưa trả version"],
      ]),
    );

    body.append(internal);

    for (const point of order.deliveryPoints || []) {
      internal.append(
        section(
          point.type === "PICKUP" ? "Tọa độ lấy hàng" : "Tọa độ giao hàng",
          summary([
            ["ID điểm", point.id],
            ["Vĩ độ", point.latitude],
            ["Kinh độ", point.longitude],
          ]),
        ),
      );
    }

    if (order.statusHistory?.length) {
      internal.append(
        section(
          "Nguồn cập nhật",
          summary(
            order.statusHistory.map((history) => [
              date(history.changedAt),
              history.source,
            ]),
          ),
        ),
      );
    }
  }

  function customerPicker(
    s,
    title,
    initialId,
    initialAddressId,
    editing = false,
    snapshot = null,
  ) {
    const wrapper = el("fieldset", "order-customer");
    wrapper.append(el("legend", "", title));

    const lookup = el("div", "input-group mb-2");

    const keyword = input("search", "", {
      maxLength: 100,
      placeholder: "Tên, điện thoại hoặc mã khách hàng",
    });

    keyword.setAttribute("aria-label", "Tìm " + title.toLowerCase());

    const go = button("Tìm", () => {
      page = 1;
      loadCustomers();
    });

    lookup.append(keyword, go);

    const customers = select([], "Chọn khách hàng");
    const addresses = select([], "Chọn khách hàng trước");
    addresses.disabled = true;

    const preview = el("p", "order-address-preview text-secondary");
    const errorBox = el("div");
    const pager = el("div", "order-actions my-2");

    let page = 1;
    let selected = null;
    let addressList = [];
    let customerSequence = 0;
    let addressSequence = 0;

    wrapper.append(
      lookup,
      field("Khách hàng *", customers, "mb-2"),
      pager,
      field("Địa chỉ *", addresses, "mb-2"),
      preview,
      errorBox,
    );

    if (editing && snapshot) {
      wrapper.insertBefore(
        el(
          "p",
          "text-secondary order-address-preview",
          "Địa chỉ trên đơn hiện tại: " +
            [snapshot.contactName, snapshot.phone, snapshot.address]
              .filter(Boolean)
              .join(" · "),
        ),
        lookup,
      );
    }

    keyword.addEventListener("keydown", (event) => {
      if (event.key === "Enter") {
        event.preventDefault();
        page = 1;
        loadCustomers();
      }
    });

    function fillCustomers(items) {
      customers.replaceChildren();
      option(customers, "", "Chọn khách hàng");

      const all =
        selected && !items.some((item) => item.id === selected.id)
          ? [selected, ...items]
          : items;

      for (const item of all) {
        option(
          customers,
          item.id,
          item.fullName +
            " · " +
            text(item.phone) +
            " · " +
            text(item.customerCode),
        );
      }

      if (selected) customers.value = selected.id;
      customers._records = all;
    }

    async function loadCustomers() {
      const seq = ++customerSequence;

      notice(errorBox, "");
      go.disabled = true;

      pager.replaceChildren(
        el("span", "text-secondary", "Đang tải khách hàng…"),
      );

      try {
        const query = new URLSearchParams({
          keyword: keyword.value.trim(),
          page,
          pageSize: 20,
        });

        const result = await read(s, "/api/v1/customers?" + query);

        if (s.dead || seq !== customerSequence || !wrapper.isConnected) {
          return;
        }

        fillCustomers(result.items || []);

        const prev = button("‹", () => {
          page--;
          loadCustomers();
        });

        prev.setAttribute("aria-label", "Khách hàng: trang trước");
        prev.disabled = page <= 1;

        const next = button("›", () => {
          page++;
          loadCustomers();
        });

        next.setAttribute("aria-label", "Khách hàng: trang sau");
        next.disabled = page * 20 >= result.totalItems || page >= 100000;

        pager.replaceChildren(
          prev,
          el(
            "span",
            "text-secondary",
            "Trang " +
              page +
              " · " +
              number.format(result.totalItems) +
              " khách",
          ),
          next,
        );

        if (!result.items?.length) {
          notice(errorBox, "Không có khách hàng phù hợp.", "warning");
        }
      } catch (error) {
        if (s.dead || seq !== customerSequence || !wrapper.isConnected) {
          return;
        }

        notice(errorBox, error.message);
        pager.replaceChildren(button("Tải lại khách hàng", loadCustomers));
      } finally {
        if (seq === customerSequence) go.disabled = false;
      }
    }

    function showAddress() {
      const address = addressList.find(
        (item) => String(item.id) === addresses.value,
      );

      preview.textContent = address
        ? [address.contactName, address.phone, address.address]
            .map(text)
            .join(" · ")
        : "Chọn địa chỉ lấy / giao của khách hàng này.";
    }

    async function loadAddresses(id, addressId, requireSelection = false) {
      const seq = ++addressSequence;

      addressList = [];
      addresses.disabled = true;
      addresses.replaceChildren();

      option(addresses, "", "Đang tải địa chỉ…");
      preview.textContent = "";
      notice(errorBox, "");

      try {
        const result = await read(
          s,
          "/api/v1/customers/" + encodeURIComponent(id) + "/addresses",
        );

        if (s.dead || seq !== addressSequence || !wrapper.isConnected) {
          return;
        }

        addressList = result.addresses || [];

        addresses.replaceChildren();
        option(addresses, "", "Chọn địa chỉ");

        for (const address of addressList) {
          option(
            addresses,
            address.id,
            (address.label ? address.label + " · " : "") +
              text(address.address),
          );
        }

        addresses.disabled = !addressList.length;

        const preferred = requireSelection
          ? null
          : addressId == null
            ? addressList.find((item) => item.isDefault)?.id
            : addressId;

        addresses.value = preferred == null ? "" : preferred;

        if (!addressList.length) {
          notice(
            errorBox,
            "Khách hàng chưa có địa chỉ đang hoạt động. Cần bổ sung địa chỉ trước khi tạo đơn.",
            "warning",
          );
        } else if (addressId != null && !addresses.value) {
          notice(
            errorBox,
            "Địa chỉ cũ không còn hoạt động. Hãy chọn địa chỉ khác.",
            "warning",
          );
        } else if (requireSelection) {
          notice(
            errorBox,
            "Không xác định được địa chỉ cũ. Hãy chọn địa chỉ lấy / giao trước khi lưu thay đổi.",
            "warning",
          );
        }

        showAddress();
      } catch (error) {
        if (s.dead || seq !== addressSequence || !wrapper.isConnected) {
          return;
        }

        addresses.replaceChildren();
        option(addresses, "", "Chưa tải được địa chỉ");
        notice(errorBox, error.message);

        errorBox.append(
          button("Tải lại địa chỉ", () =>
            loadAddresses(id, addressId, requireSelection),
          ),
        );
      }
    }

    customers.addEventListener("change", () => {
      selected =
        customers._records?.find(
          (item) => String(item.id) === customers.value,
        ) || null;

      if (selected) {
        loadAddresses(selected.id);
      } else {
        addressSequence++;
        addressList = [];
        addresses.replaceChildren();

        option(addresses, "", "Chọn khách hàng trước");

        addresses.disabled = true;
        preview.textContent = "";
      }
    });

    addresses.addEventListener("change", showAddress);

    return {
      wrapper,
      selection() {
        return { customerId: customers.value, addressId: addresses.value };
      },

      async start() {
        if (initialId != null) {
          try {
            const customer = await read(s, "/api/v1/customers/" + initialId);

            if (s.dead || !wrapper.isConnected) return;

            if (
              !customer ||
              Number(customer.id) !== Number(initialId) ||
              customer.isActive !== true
            ) {
              throw new Error(
                "Khách hàng của đơn không còn hợp lệ hoặc đã ngừng hoạt động. Hãy chọn khách hàng khác.",
              );
            }

            selected = customer;
            fillCustomers([selected]);

            await loadAddresses(
              initialId,
              initialAddressId,
              editing && !Number.isSafeInteger(initialAddressId),
            );
          } catch (error) {
            if (s.dead || error.name === "AbortError" || !wrapper.isConnected) {
              return;
            }

            notice(errorBox, error.message);
          }
        }

        await loadCustomers();
      },

      value() {
        if (
          !selected ||
          !customers.value ||
          !addresses.value ||
          addresses.disabled
        ) {
          throw new Error(
            "Hãy chọn khách hàng và địa chỉ hợp lệ cho " +
              title.toLowerCase() +
              ".",
          );
        }

        return {
          customerId: Number(customers.value),
          addressId: Number(addresses.value),
        };
      },
    };
  }

  async function openEditRoute(s, id) {
    const view = routeView(
      s,
      "Sửa đơn hàng",
      window.Router.href("order-detail", { id }, orderQuery(s)),
    );

    view.body.append(el("p", "text-secondary", "Đang tải dữ liệu sửa…"));

    try {
      const order = await read(s, "/api/v1/orders/" + id);

      if (s.dead || !view.node.isConnected) return;

      if (!order || Number(order.id) !== Number(id)) {
        throw new Error("API chi tiết trả dữ liệu không hợp lệ.");
      }

      if (!inScope(s, order) || !permitted(s, "update")) {
        notice(view.body, "Không có quyền sửa đơn này.");
        return;
      }

      const missing = missingEditFields(order);

      if (order.status !== "NEW" || missing.length) {
        notice(
          view.body,
          order.status !== "NEW"
            ? "Chỉ sửa được đơn ở trạng thái mới tạo."
            : missingEditMessage(missing),
          "warning",
        );

        return;
      }

      await openForm(s, order);
    } catch (error) {
      if (s.dead || error.name === "AbortError") return;

      notice(view.body, error.message);
      view.body.append(button("Thử lại", () => openEditRoute(s, id)));
    }
  }

  async function openForm(s, existing) {
    if (s.dead) return;

    if (
      existing &&
      (existing.status !== "NEW" ||
        !permitted(s, "update") ||
        !inScope(s, existing) ||
        missingEditFields(existing).length)
    ) {
      return;
    }

    const view = routeView(
      s,
      existing ? "Sửa đơn " + text(existing.orderCode) : "Tạo đơn hàng",
      existing
        ? window.Router.href("order-detail", { id: existing.id }, orderQuery(s))
        : s.returnHref,
    );

    const errorBox = el("div");

    view.body.append(
      errorBox,
      el("p", "text-secondary", "Đang tải bưu cục và dịch vụ…"),
    );

    let options;

    try {
      options = await read(s, "/api/v1/order-form/options");
    } catch (error) {
      if (!s.dead && view.node.isConnected) {
        view.body.replaceChildren(errorBox);
        notice(errorBox, error.message);
        view.body.append(button("Thử lại", () => openForm(s, existing)));
      }

      return;
    }

    if (s.dead || !view.node.isConnected) return;

    const form = el("form", "order-form");
    form.noValidate = true;

    const fields = el("fieldset");

    const branch = select(
      options.branches,
      "Chọn bưu cục",
      existing?.branchId ||
        (options.branches.length === 1 ? options.branches[0].id : null),
    );

    if (existing?.warehouseId != null) branch.disabled = true;

    const service = select(
      options.services,
      "Chọn dịch vụ",
      existing?.serviceId,
    );

    const priority = input("number", existing?.priority ?? 3, {
      required: true,
      min: "1",
      max: "5",
      step: "1",
    });

    const cod = input("number", existing?.codAmount ?? 0, {
      required: true,
      min: "0",
      max: "1000000000000",
      step: "0.01",
    });

    const declared = input("number", existing?.declaredValue ?? 0, {
      required: true,
      min: "0",
      max: "1000000000000",
      step: "0.01",
    });

    const notes = el("textarea", "form-control");
    notes.rows = 2;
    notes.maxLength = 1000;
    notes.value = existing?.notes || "";

    const requestedDelivery = input(
      "datetime-local",
      toVietnamInput(existing?.requestedDeliveryAt),
      {
        required: false,
        step: "1",
        min: "0001-01-02T00:00:00",
        max: "9999-12-31T23:59:59",
      },
    );

    const expectedDelivery = input(
      "datetime-local",
      toVietnamInput(existing?.expectedDeliveryAt),
      {
        required: true,
        step: "1",
        min: "0001-01-02T00:00:00",
        max: "9999-12-31T23:59:59",
      },
    );

    const general = el("div", "row g-3");

    general.append(
      field("Bưu cục *", branch),
      field("Dịch vụ *", service),
      field("Độ ưu tiên (1–5) *", priority, "col-md-4"),
      field("COD (VND) *", cod, "col-md-4"),
      field("Giá trị khai báo (VND) *", declared, "col-md-4"),
      field("Ghi chú", notes, "col-12"),
    );

    const schedule = el("div", "row g-3");

    const requestedField = field("Thời gian yêu cầu giao", requestedDelivery);

    const requestedHint = el(
      "div",
      "form-text",
      "Không bắt buộc. Nhập thời gian khách hàng mong muốn nhận hàng.",
    );

    requestedHint.id = "order-time-hint-" + ++uniqueId;
    requestedDelivery.setAttribute("aria-describedby", requestedHint.id);
    requestedField.append(requestedHint);

    const expectedField = field("Hạn giao *", expectedDelivery);

    const expectedHint = el(
      "div",
      "form-text",
      "Thời hạn giao muộn nhất; không được trước thời gian yêu cầu giao.",
    );

    expectedHint.id = "order-time-hint-" + ++uniqueId;
    expectedDelivery.setAttribute("aria-describedby", expectedHint.id);
    expectedField.append(expectedHint);

    schedule.append(
      requestedField,
      expectedField,
      el(
        "p",
        "col-12 text-secondary small mb-0",
        "Tất cả thời gian nhập tại đây là giờ Việt Nam (UTC+7).",
      ),
    );

    if (existing && existing.expectedDeliveryAt == null) {
      schedule.append(
        el(
          "p",
          "col-12 text-warning small mb-0",
          "Đơn cũ chưa có hạn giao. Hãy bổ sung hạn giao trước khi lưu.",
        ),
      );
    }

    function resetTimeValidity() {
      requestedDelivery.setCustomValidity("");
      expectedDelivery.setCustomValidity("");
    }

    for (const control of [requestedDelivery, expectedDelivery]) {
      control.addEventListener("input", resetTimeValidity);
      control.addEventListener("change", resetTimeValidity);
    }

    function deliveryTimeValues() {
      resetTimeValidity();

      let requestedAt = null;
      let expectedAt = null;

      if (requestedDelivery.value) {
        try {
          requestedAt = vietnamInputToIso(requestedDelivery.value);
        } catch (error) {
          requestedDelivery.setCustomValidity(error.message);
        }
      } else if (requestedDelivery.validity.badInput) {
        requestedDelivery.setCustomValidity(
          "Thời gian yêu cầu giao không hợp lệ.",
        );
      }

      if (!expectedDelivery.value) {
        expectedDelivery.setCustomValidity("Phải nhập hạn giao.");
      } else {
        try {
          expectedAt = vietnamInputToIso(expectedDelivery.value);
        } catch (error) {
          expectedDelivery.setCustomValidity(error.message);
        }
      }

      const now = Date.now();

      if (
        requestedAt &&
        new Date(requestedAt).getTime() <= now &&
        !(existing && sameSecond(requestedAt, existing.requestedDeliveryAt))
      ) {
        requestedDelivery.setCustomValidity(
          "Thời gian yêu cầu giao mới phải sau thời điểm hiện tại.",
        );
      }

      if (
        expectedAt &&
        new Date(expectedAt).getTime() <= now &&
        !(existing && sameSecond(expectedAt, existing.expectedDeliveryAt))
      ) {
        expectedDelivery.setCustomValidity(
          "Hạn giao mới phải sau thời điểm hiện tại.",
        );
      }

      if (
        requestedAt &&
        expectedAt &&
        new Date(expectedAt).getTime() < new Date(requestedAt).getTime()
      ) {
        expectedDelivery.setCustomValidity(
          "Hạn giao phải bằng hoặc sau thời gian yêu cầu giao.",
        );
      }

      return {
        requestedDeliveryAt: requestedAt,
        expectedDeliveryAt: expectedAt,
      };
    }

    const sender = customerPicker(
      s,
      "Người gửi / điểm lấy",
      existing?.senderId,
      existing?.pickupAddressId,
      Boolean(existing),
      existing?.deliveryPoints?.find((point) => point.type === "PICKUP"),
    );

    const receiver = customerPicker(
      s,
      "Người nhận / điểm giao",
      existing?.receiverId,
      existing?.deliveryAddressId,
      Boolean(existing),
      existing?.deliveryPoints?.find((point) => point.type === "DELIVERY"),
    );

    const parties = el("div", "order-points");
    parties.append(sender.wrapper, receiver.wrapper);

    const items = el("div", "order-item-list");
    const itemRows = [];

    const totalLabel = el("strong", "order-weight-total");
    const volumeLabel = el("span", "text-secondary order-volume-total");
    const quoteResult = el("div");

    const add = button(
      "+ Thêm hàng",
      () => addItem(),
      "btn btn-outline-orange",
    );

    let quoted = false;

    function clearQuote() {
      if (!quoted) return;

      notice(quoteResult, "Dữ liệu đã thay đổi. Hãy báo giá lại.", "warning");
      quoted = false;
    }

    function totalWeight() {
      return itemRows.reduce(
        (sum, row) =>
          sum + Number(row.quantity.value) * Number(row.unitWeightKg.value),
        0,
      );
    }

    function updateWeight() {
      totalLabel.textContent =
        "Tổng khối lượng tham khảo: " + weight(totalWeight());

      const complete =
        itemRows.length > 0 &&
        itemRows.every((row) =>
          [row.quantity, row.lengthCm, row.widthCm, row.heightCm].every(
            (control) => control.value !== "" && control.checkValidity(),
          ),
        );

      const volume = complete
        ? itemRows.reduce(
            (sum, row) =>
              sum +
              (Number(row.quantity.value) *
                Number(row.lengthCm.value) *
                Number(row.widthCm.value) *
                Number(row.heightCm.value)) /
                1000000,
            0,
          )
        : null;

      volumeLabel.textContent =
        "Tổng thể tích tham khảo: " +
        (volume == null
          ? "chưa đủ kích thước hợp lệ"
          : (volume < 0.000001 ? "< 0,000001" : volumeNumber.format(volume)) +
            " m³");

      add.disabled = itemRows.length >= 100;
      clearQuote();
    }

    function addItem(item) {
      if (itemRows.length >= 100) return;

      const row = {
        node: el("fieldset", "order-item"),

        name: input("text", item?.name, {
          required: true,
          maxLength: 200,
        }),

        type: input("text", item?.type, {
          maxLength: 100,
        }),

        quantity: input("number", item?.quantity ?? 1, {
          required: true,
          min: "1",
          max: "100000",
          step: "1",
        }),

        unitWeightKg: input("number", item?.unitWeightKg ?? "", {
          required: true,
          min: "0.001",
          max: "1000000",
          step: "0.001",
        }),

        lengthCm: input("number", item?.lengthCm ?? "", {
          required: true,
          min: "0.01",
          max: "99999999.99",
          step: "0.01",
        }),

        widthCm: input("number", item?.widthCm ?? "", {
          required: true,
          min: "0.01",
          max: "99999999.99",
          step: "0.01",
        }),

        heightCm: input("number", item?.heightCm ?? "", {
          required: true,
          min: "0.01",
          max: "99999999.99",
          step: "0.01",
        }),

        value: input("number", item?.value ?? 0, {
          required: true,
          min: "0",
          max: "1000000000000",
          step: "0.01",
        }),

        fragile: input("checkbox", ""),

        notes: input("text", item?.notes, {
          maxLength: 500,
        }),
      };

      row.fragile.className = "form-check-input";
      row.fragile.checked = Boolean(item?.fragile);

      const legend = el("legend", "", "Hàng hóa");
      const grid = el("div", "row g-3");

      grid.append(
        field("Tên hàng *", row.name),
        field("Loại hàng", row.type),
        field("Số lượng *", row.quantity, "col-md-4"),
        field("Kg / đơn vị *", row.unitWeightKg, "col-md-4"),
        field("Giá trị hàng (VND) *", row.value, "col-md-4"),
        field("Dài (cm) *", row.lengthCm, "col-12 col-sm-4"),
        field("Rộng (cm) *", row.widthCm, "col-12 col-sm-4"),
        field("Cao (cm) *", row.heightCm, "col-12 col-sm-4"),
      );

      const dimensionHint = el(
        "p",
        "col-12 text-secondary small mb-0",
        "Nhập kích thước đóng gói của 1 đơn vị hàng, tối đa 2 số lẻ. Thể tích tổng được nhân theo số lượng.",
      );

      if (
        existing &&
        item &&
        [item.lengthCm, item.widthCm, item.heightCm].some(
          (value) => value == null,
        )
      ) {
        dimensionHint.textContent =
          "Hàng trên đơn cũ chưa đủ kích thước. Hãy bổ sung kích thước đóng gói của 1 đơn vị hàng trước khi lưu.";
      }

      grid.append(
        dimensionHint,
        field("Ghi chú hàng", row.notes, "col-md-9"),
        field("Dễ vỡ", row.fragile, "col-md-3"),
      );

      const remove = button(
        "Xóa hàng",
        () => {
          itemRows.splice(itemRows.indexOf(row), 1);
          row.node.remove();
          renumber();
          updateWeight();
        },
        "btn btn-outline-danger btn-sm mt-3",
      );

      row.node.append(legend, grid, remove);
      items.append(row.node);
      itemRows.push(row);

      renumber();
      updateWeight();
    }

    function renumber() {
      itemRows.forEach((row, index) => {
        row.node.querySelector("legend").textContent = "Hàng " + (index + 1);
      });
    }

    function payload() {
      for (const row of itemRows) {
        row.name.setCustomValidity(
          row.name.value.trim() ? "" : "Tên hàng không được trống.",
        );
      }

      const deliveryTimes = deliveryTimeValues();

      if (!form.reportValidity()) {
        throw new Error(
          "Hãy kiểm tra các trường bắt buộc, thời gian giao, số lượng, khối lượng, kích thước và giá trị.",
        );
      }

      if (!itemRows.length) {
        throw new Error("Đơn cần ít nhất 1 dòng hàng (tối đa 100).");
      }

      if (!Number.isFinite(totalWeight()) || totalWeight() > 999999999.999) {
        throw new Error("Tổng khối lượng vượt giới hạn 999.999.999,999 kg.");
      }

      const from = sender.value();
      const to = receiver.value();

      const result = {
        branchId: Number(branch.value),
        serviceId: Number(service.value),
        senderId: from.customerId,
        receiverId: to.customerId,
        pickupAddressId: from.addressId,
        deliveryAddressId: to.addressId,
        priority: Number(priority.value),
        codAmount: Number(cod.value),
        declaredValue: Number(declared.value),
        notes: notes.value.trim() || null,
        requestedDeliveryAt: deliveryTimes.requestedDeliveryAt,
        expectedDeliveryAt: deliveryTimes.expectedDeliveryAt,

        items: itemRows.map((row) => ({
          name: row.name.value.trim(),
          type: row.type.value.trim() || null,
          quantity: Number(row.quantity.value),
          unitWeightKg: Number(row.unitWeightKg.value),
          lengthCm: Number(row.lengthCm.value),
          widthCm: Number(row.widthCm.value),
          heightCm: Number(row.heightCm.value),
          value: Number(row.value.value),
          fragile: row.fragile.checked,
          notes: row.notes.value.trim() || null,
        })),
      };

      if (existing) result.expectedVersion = existing.version;

      return result;
    }

    let quoting = false;

    function quotePayload() {
      const branchId = Number(branch.value);
      const serviceId = Number(service.value);

      if (!Number.isSafeInteger(branchId) || branchId <= 0) {
        branch.reportValidity();
        throw new Error("Hãy chọn bưu cục để báo giá.");
      }

      if (!Number.isSafeInteger(serviceId) || serviceId <= 0) {
        service.reportValidity();
        throw new Error("Hãy chọn dịch vụ để báo giá.");
      }

      if (!itemRows.length) {
        throw new Error("Hãy thêm ít nhất một dòng hàng.");
      }

      // Báo giá chỉ cần số lượng và khối lượng.
      // Các trường còn lại vẫn được kiểm tra khi lưu đơn.
      for (const row of itemRows) {
        for (const control of [row.quantity, row.unitWeightKg]) {
          if (!control.reportValidity()) {
            throw new Error("Hãy nhập số lượng và khối lượng hàng hợp lệ.");
          }
        }
      }

      const kg = totalWeight();

      if (!Number.isFinite(kg) || kg < 0.001 || kg > 1000000) {
        throw new Error("Khối lượng báo giá phải từ 0,001 đến 1.000.000 kg.");
      }

      const from = sender.value();
      const to = receiver.value();

      // Khi đang sửa, báo giá theo dữ liệu đang nhập trên form,
      // gồm địa chỉ và khối lượng có thể chưa được lưu.
      return {
        branchId,
        serviceId,
        pickupAddressId: from.addressId,
        deliveryAddressId: to.addressId,
        weightKg: Number(kg.toFixed(3)),
      };
    }

    const quote = button(
      "Tính phí tham khảo",
      async () => {
        if (
          initializing ||
          submitting ||
          quoting ||
          s.dead ||
          !view.node.isConnected
        ) {
          return;
        }

        notice(errorBox, "");

        let data;

        try {
          data = quotePayload();
        } catch (error) {
          notice(errorBox, error.message);
          return;
        }

        quoting = true;
        quoted = false;

        quoteResult.replaceChildren(
          el("p", "text-secondary", "Đang tính khoảng cách và phí vận chuyển…"),
        );

        fields.disabled = true;
        view.setBusy(true);
        quote.textContent = "Đang tính phí…";

        try {
          const result = await window.ApiClient.request(
            "/api/v1/shipping-fees/quote",
            {
              method: "POST",
              signal: s.abort.signal,
              body: JSON.stringify(data),
            },
          );

          if (s.dead || !view.node.isConnected) return;

          quoteResult.replaceChildren(quoteSummary(result));
          quoted = true;
        } catch (error) {
          if (!s.dead && view.node.isConnected && error.name !== "AbortError") {
            quoteResult.replaceChildren();
            notice(errorBox, error.message);
          }
        } finally {
          quoting = false;

          if (!s.dead && view.node.isConnected) {
            fields.disabled = false;
            view.setBusy(false);
            quote.textContent = "Tính phí tham khảo";
          }
        }
      },
      "btn btn-outline-orange",
    );

    const quoteFields = el("div", "order-actions");
    quoteFields.append(quote);

    const footer = el("div", "order-actions mt-4");

    const submit = button(
      existing ? "Lưu thay đổi" : "Tạo đơn",
      null,
      "btn btn-orange",
    );

    submit.type = "submit";

    footer.append(
      submit,
      button("Đóng", () => view.close()),
    );

    const goodsActions = el("div", "order-actions mt-3");
    goodsActions.append(add, totalLabel, volumeLabel);

    fields.append(
      section("Thông tin chung", general),
      section("Thời gian giao hàng", schedule),
      parties,
      section("Danh sách hàng", items, goodsActions),
      ...(permitted(s, "create")
        ? [
            section(
              "Báo giá tham khảo",
              el(
                "p",
                "text-secondary",
                "Hệ thống tính khoảng cách theo mạng đường từ địa chỉ lấy đến địa chỉ giao. Phí tham khảo có thể thay đổi; phí chính thức được tính khi xác nhận đơn.",
              ),
              quoteFields,
              quoteResult,
            ),
          ]
        : []),
      footer,
    );

    form.append(fields);
    view.body.replaceChildren(errorBox, form);

    (existing?.items || [{}]).forEach(addItem);

    fields.addEventListener("input", (event) => {
      if (event.target.type === "text") {
        event.target.setCustomValidity("");
      }

      updateWeight();
    });

    fields.addEventListener("change", clearQuote);

    let submitting = false;
    let conflicted = false;
    let initializing = true;
    let uncertain = false;
    let initialSnapshot = null;

    function formSnapshot() {
      return JSON.stringify({
        general: [branch, service, priority, cod, declared, notes, requestedDelivery, expectedDelivery].map(control => control.value),
        sender: sender.selection(), receiver: receiver.selection(),
        items: itemRows.map(row => Object.fromEntries(Object.entries(row)
          .filter(([key]) => key !== "node")
          .map(([key, control]) => [key, control.type === "checkbox" ? control.checked : control.value]))),
      });
    }
    function hasUnsavedChanges() {
      return !initializing && initialSnapshot !== null && formSnapshot() !== initialSnapshot;
    }
    function installFormGuard() {
      const leave = () => {
        if (s.dead) return true;
        if (submitting) {
          window.alert("Đang lưu đơn. Vui lòng chờ kết quả trước khi rời trang để tránh gửi lặp.");
          return false;
        }
        if (uncertain) return window.confirm("Chưa xác định được kết quả lưu đơn. Hãy kiểm tra danh sách hoặc chi tiết đơn trước khi gửi lại. Bạn muốn rời biểu mẫu này?");
        return !hasUnsavedChanges() || window.confirm("Đơn hàng có thay đổi chưa lưu. Bạn muốn bỏ nội dung đang nhập và rời trang?");
      };
      const beforeUnload = event => {
        if (submitting || uncertain || hasUnsavedChanges()) {
          event.preventDefault(); event.returnValue = "";
        }
      };
      const release = window.Router.setLeaveGuard(leave);
      window.addEventListener("beforeunload", beforeUnload);
      let released = false;
      s.releaseFormGuard = () => {
        if (released) return;
        released = true;
        release();
        window.removeEventListener("beforeunload", beforeUnload);
      };
    }

    form.addEventListener("submit", async (event) => {
      event.preventDefault();

      if (initializing || submitting || conflicted) return;

      notice(errorBox, "");

      let data;

      try {
        data = payload();
      } catch (error) {
        notice(errorBox, error.message);
        return;
      }

      submitting = true;
      fields.disabled = true;
      view.setBusy(true);
      submit.textContent = "Đang lưu…";

      try {
        const result = await window.ApiClient.request(
          "/api/v1/orders" + (existing ? "/" + existing.id : ""),
          {
            method: existing ? "PUT" : "POST",
            signal: s.abort.signal,
            body: JSON.stringify(data),
          },
        );

        if (s.dead || !view.node.isConnected) return;

        s.releaseFormGuard?.();
        navigateDetail(
          result.id,
          result.message || "Đã lưu đơn thành công.",
          orderQuery(s),
          true,
        );
      } catch (error) {
        if (s.dead || !view.node.isConnected) return;

        notice(errorBox, error.message);

        if (error.resultUnknown) {
          uncertain = true;
          conflicted = true;
          errorBox.append(button("Kiểm tra danh sách đơn", () => window.Router.navigate(s.returnHref)));
        } else if (existing && error.status === 409) {
          conflicted = true;

          errorBox.append(
            el(
              "p",
              "text-secondary",
              "Bản sửa chưa được gửi lại. Tải lại để xem dữ liệu mới; bản nhập hiện tại sẽ được bỏ khi bạn chọn tải lại.",
            ),
            button("Tải lại dữ liệu mới", () =>
              navigateDetail(existing.id, "", orderQuery(s), true),
            ),
          );
        }
      } finally {
        submitting = false;
        fields.disabled = false;
        submit.disabled = conflicted;
        submit.textContent = existing ? "Lưu thay đổi" : "Tạo đơn";
        view.setBusy(false);
      }
    });

    fields.disabled = true;
    view.setBusy(true);
    submit.textContent = "Đang tải dữ liệu…";

    try {
      await Promise.allSettled([sender.start(), receiver.start()]);
    } finally {
      initializing = false;

      if (!s.dead && view.node.isConnected) {
        initialSnapshot = formSnapshot();
        installFormGuard();
        fields.disabled = false;
        view.setBusy(false);
        submit.textContent = existing ? "Lưu thay đổi" : "Tạo đơn";
      }
    }
  }

  function quoteSummary(result) {
    if (
      !result ||
      ![
        "distanceKm",
        "weightKg",
        "baseFee",
        "distanceFee",
        "weightFee",
        "shippingFee",
      ].every(
        (key) =>
          typeof result[key] === "number" && Number.isFinite(result[key]),
      )
    ) {
      throw new Error("API báo giá trả dữ liệu không hợp lệ.");
    }

    return section(
      "Kết quả báo giá tham khảo",
      summary([
        ["Dịch vụ", result.serviceName],
        ["Khoảng cách tính phí", number.format(result.distanceKm) + " km"],
        ["Khối lượng", weight(result.weightKg)],
        ["Phí cơ bản", money(result.baseFee)],
        ["Phí khoảng cách", money(result.distanceFee)],
        ["Phí khối lượng", money(result.weightFee)],
        ["Tổng phí tham khảo", money(result.shippingFee)],
        ["Thời điểm báo giá (giờ VN)", date(result.quotedAt)],
      ]),
      el(
        "p",
        "text-secondary small mb-0",
        "Phí vận chuyển tham khảo được tính theo mạng đường. Phụ phí hoặc giảm giá của đơn, nếu có, được xử lý khi xác nhận.",
      ),
    );
  }

  async function openQuote(s, order) {
    if (s.dead) return;

    const view = dialog(s, "Báo giá tham khảo");
    const errorBox = el("div");

    view.body.append(errorBox, el("p", "text-secondary", "Đang tải dịch vụ…"));

    try {
      const orderId = Number(order.id);
      const branchId = Number(order.branchId);

      if (
        !Number.isSafeInteger(orderId) ||
        orderId <= 0 ||
        !Number.isSafeInteger(branchId) ||
        branchId <= 0
      ) {
        throw new Error(
          "Chưa có đủ thông tin đơn và bưu cục để báo giá. Hãy tải lại chi tiết.",
        );
      }

      const options = await read(s, "/api/v1/order-form/options", view.signal);

      if (s.dead || !view.node.isConnected) return;

      if (!Array.isArray(options?.services)) {
        throw new Error("Chưa tải được danh sách dịch vụ hợp lệ.");
      }

      const form = el("form");
      form.noValidate = true;

      const fields = el("fieldset");

      const service = select(
        options.services,
        "Chọn dịch vụ báo giá",
        order.serviceId,
      );

      const output = el("div");
      const progress = el("div", "text-secondary small mt-3");

      progress.setAttribute("role", "status");
      progress.setAttribute("aria-live", "polite");

      const submit = button("Tính phí tham khảo", null, "btn btn-orange");

      submit.type = "submit";

      const actions = el("div", "order-actions");
      actions.append(
        submit,
        button("Đóng", () => view.close()),
      );

      fields.append(
        summary([
          ["Mã đơn", order.orderCode],
          ["Người gửi", order.senderName],
          ["Người nhận", order.receiverName],
          ["Dịch vụ trên đơn", order.serviceName],
        ]),
        el(
          "p",
          "text-secondary",
          "Hệ thống lấy điểm lấy, điểm giao và khối lượng đã lưu của đơn để tính phí. Bạn có thể chọn dịch vụ khác để tham khảo; thao tác này không thay đổi đơn.",
        ),
        field("Dịch vụ báo giá *", service, "mb-3"),
        actions,
      );

      form.append(fields);

      view.body.replaceChildren(errorBox, form, progress, output);

      service.addEventListener("change", () => {
        output.replaceChildren();
        progress.textContent = "";
        notice(errorBox, "");
      });

      let busy = false;

      form.addEventListener("submit", async (event) => {
        event.preventDefault();

        if (
          busy ||
          s.dead ||
          !view.node.isConnected ||
          !form.reportValidity()
        ) {
          return;
        }

        const serviceId = Number(service.value);

        if (!Number.isSafeInteger(serviceId) || serviceId <= 0) {
          notice(errorBox, "Hãy chọn dịch vụ báo giá.");
          return;
        }

        notice(errorBox, "");
        output.replaceChildren();

        const data = {
          branchId,
          serviceId,
          orderId,
        };

        busy = true;
        fields.disabled = true;
        view.setBusy(true);

        submit.textContent = "Đang tính phí…";
        progress.textContent = "Đang tính khoảng cách và phí vận chuyển…";

        try {
          const result = await window.ApiClient.request(
            "/api/v1/shipping-fees/quote",
            {
              method: "POST",
              signal: view.signal,
              body: JSON.stringify(data),
            },
          );

          if (s.dead || !view.node.isConnected) return;

          output.replaceChildren(quoteSummary(result));
        } catch (error) {
          if (!s.dead && view.node.isConnected && error.name !== "AbortError") {
            notice(errorBox, error.message);
          }
        } finally {
          busy = false;

          if (!s.dead && view.node.isConnected) {
            fields.disabled = false;
            view.setBusy(false);

            submit.textContent = "Tính phí tham khảo";
            progress.textContent = "";
          }
        }
      });
    } catch (error) {
      if (!s.dead && view.node.isConnected && error.name !== "AbortError") {
        view.body.replaceChildren(errorBox);
        notice(errorBox, error.message);

        view.body.append(
          button("Thử lại", () => {
            view.close();
            openQuote(s, order);
          }),
        );
      }
    }
  }
  function openDeliverySchedule(s, order) {
    if (
      s.dead ||
      s.readOnly ||
      !inScope(s, order) ||
      !permitted(s, "update") ||
      order.status !== "IN_WAREHOUSE"
    ) {
      return;
    }

    const view = dialog(s, "Sửa lịch giao · " + text(order.orderCode));

    const errorBox = el("div");
    view.body.append(errorBox);

    function reloadDetail() {
      view.close();
      navigateDetail(order.id, "", orderQuery(s), true);
    }

    // Phải phân biệt trường null hợp lệ với trường API chưa trả.
    const validDates = ["requestedDeliveryAt", "expectedDeliveryAt"].every(
      (key) =>
        Object.prototype.hasOwnProperty.call(order, key) &&
        (order[key] === null ||
          (typeof order[key] === "string" &&
            !!parseApiDate(order[key]) &&
            !!toVietnamInput(order[key]))),
    );

    if (
      typeof order.version !== "string" ||
      !/^[A-Za-z0-9+/]{11}=$/.test(order.version) ||
      !validDates
    ) {
      notice(
        errorBox,
        "Chưa có đủ phiên bản và lịch giao hợp lệ. Hãy tải lại chi tiết.",
      );

      view.body.append(button("Tải lại chi tiết", reloadDetail));
      return;
    }

    const form = el("form");
    form.noValidate = true;

    const fields = el("fieldset");

    const requested = input(
      "datetime-local",
      toVietnamInput(order.requestedDeliveryAt),
      { step: 1 },
    );

    const expected = input(
      "datetime-local",
      toVietnamInput(order.expectedDeliveryAt),
      { required: true, step: 1 },
    );

    const reason = el("textarea", "form-control");
    reason.required = true;
    reason.maxLength = 500;
    reason.rows = 3;
    reason.placeholder = "Nhập lý do điều chỉnh lịch giao";

    const times = el("div", "row g-3");

    times.append(
      field("Khách yêu cầu giao", requested),
      field("Hạn giao *", expected),
      field("Lý do điều chỉnh *", reason, "col-12"),
    );

    const submit = button("Lưu lịch giao", null, "btn btn-orange");
    submit.type = "submit";

    const actions = el("div", "order-actions mt-3");

    actions.append(
      submit,
      button("Quay lại", () => view.close()),
    );

    fields.append(
      summary([
        ["Mã đơn", order.orderCode],
        ["Trạng thái", order.statusName || statuses[order.status]],
        ["Yêu cầu giao hiện tại", date(order.requestedDeliveryAt)],
        ["Hạn giao hiện tại", date(order.expectedDeliveryAt)],
      ]),
      el(
        "p",
        "alert alert-info",
        "Nhập theo giờ Việt Nam. Hạn giao phải ở tương lai. Để trống thời gian khách yêu cầu giao sẽ xóa mốc này.",
      ),
      times,
      actions,
    );

    const progress = el("div", "text-secondary small mt-3");
    progress.setAttribute("role", "status");
    progress.setAttribute("aria-live", "polite");

    form.append(fields);
    view.body.append(form, progress);

    let busy = false;
    let requiresReload = false;

    reason.addEventListener("input", () => {
      reason.setCustomValidity("");
    });

    form.addEventListener("submit", async (event) => {
      event.preventDefault();

      if (busy || requiresReload || s.dead || !view.node.isConnected) {
        return;
      }

      notice(errorBox, "");

      const reasonValue = reason.value.trim();

      reason.setCustomValidity(
        reasonValue ? "" : "Phải nhập lý do điều chỉnh lịch giao.",
      );

      if (!form.reportValidity()) return;

      let requestedAt;
      let expectedAt;

      try {
        requestedAt = vietnamInputToIso(requested.value);
        expectedAt = vietnamInputToIso(expected.value);

        const now = Date.now();

        if (!expectedAt || Date.parse(expectedAt) <= now) {
          throw new Error("Hạn giao phải nằm trong tương lai.");
        }

        if (
          requestedAt &&
          Date.parse(requestedAt) <= now &&
          !sameSecond(requestedAt, order.requestedDeliveryAt)
        ) {
          throw new Error(
            "Thời điểm yêu cầu giao mới phải nằm trong tương lai.",
          );
        }

        if (requestedAt && Date.parse(expectedAt) < Date.parse(requestedAt)) {
          throw new Error(
            "Hạn giao không được trước thời điểm khách yêu cầu giao.",
          );
        }
      } catch (error) {
        notice(errorBox, error.message);
        return;
      }

      busy = true;
      fields.disabled = true;
      view.setBusy(true);

      submit.textContent = "Đang lưu…";
      progress.textContent = "Đang cập nhật lịch giao…";

      try {
        const result = await window.ApiClient.request(
          "/api/v1/orders/" +
            encodeURIComponent(order.id) +
            "/delivery-schedule",
          {
            method: "PUT",
            signal: view.signal,
            body: JSON.stringify({
              expectedVersion: order.version,
              requestedDeliveryAt: requestedAt,
              expectedDeliveryAt: expectedAt,
              reason: reasonValue,
            }),
          },
        );

        if (s.dead || !view.node.isConnected) return;

        view.close();

        // Tải lại chi tiết để lấy lịch giao và version mới.
        navigateDetail(
          order.id,
          result?.message || "Đã cập nhật lịch giao.",
          orderQuery(s),
          true,
        );
      } catch (error) {
        if (s.dead || !view.node.isConnected || error.name === "AbortError") {
          return;
        }

        notice(errorBox, error.message || "Không cập nhật được lịch giao.");

        if (error.resultUnknown || [404, 409].includes(error.status)) {
          requiresReload = true;

          errorBox.append(
            el(
              "p",
              "text-secondary small",
              "Hãy tải lại chi tiết để kiểm tra dữ liệu mới. Nội dung đang nhập sẽ được bỏ khi tải lại.",
            ),
            button("Tải lại chi tiết", reloadDetail),
          );
        }
      } finally {
        busy = false;

        if (!s.dead && view.node.isConnected) {
          fields.disabled = false;
          submit.disabled = requiresReload;
          submit.textContent = "Lưu lịch giao";
          progress.textContent = "";
          view.setBusy(false);
        }
      }
    });
  }
  function openAction(s, detailView, order, action) {
    if (s.dead || !["confirm", "cancel"].includes(action)) return;

    const cancelling = action === "cancel";

    const view = dialog(
      s,
      (cancelling ? "Hủy đơn " : "Xác nhận đơn ") + text(order.orderCode),
    );

    const errorBox = el("div");
    const progress = el("div", "text-secondary small mt-3");

    progress.setAttribute("role", "status");
    progress.setAttribute("aria-live", "polite");

    const form = el("form");
    form.noValidate = true;

    const fields = el("fieldset");

    fields.append(
      summary([
        ["Mã đơn", order.orderCode],
        ["Người gửi", order.senderName],
        ["Người nhận", order.receiverName],
        ["Dịch vụ", order.serviceName],
        ["Khối lượng", weight(order.weightKg)],
      ]),
    );

    let reason = null;

    if (cancelling) {
      fields.append(
        el(
          "p",
          "",
          "Bạn có muốn hủy đơn này? Lý do hủy sẽ được ghi vào lịch sử.",
        ),
      );

      reason = el("textarea", "form-control");
      reason.required = true;
      reason.maxLength = 500;
      reason.rows = 3;
      reason.placeholder = "Nhập lý do hủy đơn";

      fields.append(field("Lý do hủy (1–500 ký tự) *", reason, "mb-3"));

      reason.addEventListener("input", () => {
        reason.setCustomValidity("");
      });
    } else {
      fields.append(
        el(
          "p",
          "alert alert-info",
          "Hệ thống sẽ tự tính khoảng cách từ điểm lấy đến điểm giao và tính phí vận chuyển khi xác nhận.",
        ),
        el(
          "p",
          "text-secondary small",
          "Nếu thiếu tọa độ hoặc chưa tìm được đường phù hợp, đơn sẽ chưa được xác nhận.",
        ),
      );
    }

    const submit = button(
      cancelling ? "Đồng ý hủy đơn" : "Xác nhận đơn",
      null,
      cancelling ? "btn btn-danger" : "btn btn-orange",
    );

    submit.type = "submit";

    const back = button("Quay lại", () => view.close());
    const actions = el("div", "order-actions mt-3");

    actions.append(submit, back);
    fields.append(actions);
    form.append(fields);
    view.body.append(errorBox, form, progress);

    let busy = false;
    let requiresReload = false;

    form.addEventListener("submit", async (event) => {
      event.preventDefault();

      if (busy || requiresReload || s.dead || !view.node.isConnected) {
        return;
      }

      notice(errorBox, "");
      progress.textContent = "";

      let payload;

      if (cancelling) {
        const value = reason.value.trim();

        reason.setCustomValidity(value ? "" : "Phải nhập lý do hủy.");

        if (!form.reportValidity()) return;

        if (
          typeof order.version !== "string" ||
          !/^[A-Za-z0-9+/]{11}=$/.test(order.version)
        ) {
          notice(
            errorBox,
            "Chưa có phiên bản dữ liệu hợp lệ. Hãy tải lại chi tiết đơn trước khi hủy.",
          );

          requiresReload = true;
          submit.disabled = true;

          appendReloadButton();
          return;
        }

        payload = {
          reason: value,
          expectedVersion: order.version,
        };
      } else {
        if (
          typeof order.version !== "string" ||
          !/^[A-Za-z0-9+/]{11}=$/.test(order.version)
        ) {
          notice(
            errorBox,
            "Chưa có phiên bản dữ liệu hợp lệ. Hãy tải lại chi tiết đơn trước khi xác nhận.",
          );

          requiresReload = true;
          submit.disabled = true;

          appendReloadButton();
          return;
        }

        payload = {
          expectedVersion: order.version,
        };
      }

      busy = true;
      fields.disabled = true;
      view.setBusy(true);

      submit.textContent = cancelling ? "Đang hủy…" : "Đang xác nhận…";

      progress.textContent = cancelling
        ? "Đang xử lý yêu cầu hủy đơn…"
        : "Đang tính đường, tính phí và xác nhận đơn…";

      try {
        const result = await window.ApiClient.request(
          "/api/v1/orders/" + encodeURIComponent(order.id) + "/" + action,
          {
            method: "POST",
            signal: view.signal,
            body: JSON.stringify(payload),
          },
        );

        if (s.dead || !view.node.isConnected) return;

        let message =
          result?.message ||
          (cancelling
            ? "Đã hủy đơn thành công."
            : "Đã xác nhận đơn thành công.");

        if (!cancelling) {
          if (
            typeof result?.distanceKm === "number" &&
            Number.isFinite(result.distanceKm)
          ) {
            message +=
              " Khoảng cách tính phí: " +
              number.format(result.distanceKm) +
              " km.";
          }

          if (
            typeof result?.shippingFee === "number" &&
            Number.isFinite(result.shippingFee)
          ) {
            message += " Phí chính thức: " + money(result.shippingFee) + ".";
          }
        }

        view.close();

        navigateDetail(order.id, message, orderQuery(s), true);
      } catch (error) {
        if (s.dead || !view.node.isConnected || error.name === "AbortError") {
          return;
        }

        notice(errorBox, error.message || "Chưa xử lý được đơn. Hãy thử lại.");

        if (error.resultUnknown || [404, 409].includes(error.status)) {
          requiresReload = true;

          errorBox.append(
            el(
              "p",
              "text-secondary small",
              "Dữ liệu đơn có thể đã thay đổi. Hãy tải lại chi tiết trước khi thao tác tiếp.",
            ),
          );

          appendReloadButton();
        }
      } finally {
        busy = false;

        if (!s.dead && view.node.isConnected) {
          fields.disabled = false;
          submit.disabled = requiresReload;

          submit.textContent = cancelling ? "Đồng ý hủy đơn" : "Xác nhận đơn";

          progress.textContent = "";
          view.setBusy(false);
        }
      }
    });

    function appendReloadButton() {
      errorBox.append(
        button("Tải lại chi tiết", () => {
          view.close();
          navigateDetail(order.id, "", orderQuery(s), true);
        }),
      );
    }
  }

  window.LogisticsUI = Object.freeze({
    text,
    money,
    weight,
    date,
    el,
    button,
    input,
    option,
    select,
    field,
    notice,
    badge,
    table,
    summary,
    section,
    dialog,
    closeDialogs,
    routeView,
    pagination,
  });

  window.OrdersPage = Object.freeze({
    mount,
    destroy,

    showDetail(owner, id) {
      if (owner.route?.pageId === "orders") {
        return navigateDetail(id, "", orderQuery(owner));
      }

      const source = window.Router.current() || owner.route;

      const returnTo =
        source.name === "transaction-detail"
          ? window.Router.href("warehouse-transactions", {}, source.query)
          : source.hash;

      return navigateDetail(id, "", { returnTo });
    },
  });
})();
