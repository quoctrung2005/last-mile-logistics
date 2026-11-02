"use strict";

(function () {
  const UI = window.LogisticsUI;
  const {
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
    pagination,
    text,
    date,
    weight,
  } = UI;
  const inventoryLabels = {
    RECEIVED: "Đã nhận vào kho",
    STORED: "Đang lưu kho",
    ALLOCATED: "Đã giữ cho phân công",
    RETURNED: "Hàng hoàn trong kho",
    HANDED_OVER: "Đã bàn giao khỏi kho",
  };
  const types = {
    INBOUND: "Nhập kho",
    MOVE: "Chuyển vị trí",
    OUTBOUND: "Xuất kho",
    RETURN_IN: "Nhập hàng hoàn",
  };
  const conditions = {
    NORMAL: "Bình thường",
    DAMAGED: "Hư hỏng",
    OTHER: "Tình trạng khác",
  };
  const transactionStates = {
    PENDING: "Chờ xử lý",
    COMPLETED: "Hoàn tất",
    CANCELLED: "Đã hủy",
  };
  const assignmentStates = {
    PENDING: "Chờ shipper nhận nhiệm vụ",
    ACCEPTED: "Shipper đã nhận nhiệm vụ",
  };
  const viewTitles = {
    inventory: "Tồn kho",
    "inbound-outbound": "Nhập kho",
    "warehouse-outbound": "Xuất kho",
    "warehouse-return": "Nhập hàng hoàn",
    "warehouse-locations": "Vị trí lưu kho",
    "warehouse-transactions": "Lịch sử giao dịch kho",
  };
  const orderStates = {
    NEW: "Mới tạo",
    CONFIRMED: "Đã tiếp nhận",
    WAITING_INBOUND: "Chờ nhập kho",
    IN_WAREHOUSE: "Đã nhập kho",
    WAITING_ASSIGNMENT: "Chờ phân công",
    ASSIGNED: "Đã phân công",
    HANDED_OVER: "Đã xuất kho / bàn giao",
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
  let active = null;
  let remembered = { account: null, warehouseId: null };

  function destroy() {
    window.LocationsPage?.destroy();
    window.TransactionsPage?.destroy();
    if (!active) return;
    active.dead = true;
    active.abort.abort();
    active.scopeAbort.abort();
    for (const list of active.lists) list.dispose();
    UI.closeDialogs(active);
    active.returnRefresh?.remove();
    active = null;
  }
  function reset() {
    destroy();
    remembered = { account: null, warehouseId: null };
  }
  function can(s, code) {
    return (
      (code === "KHO_NHAP" && s.returnPermissionVerified === true) ||
      (s.permissions.known && s.permissions.codes.has(code))
    );
  }
  function locationName(location) {
    return [
      location.code,
      location.storageArea,
      location.rack ? "Kệ " + location.rack : null,
      location.slot ? "Ô " + location.slot : null,
    ]
      .filter((value) => value != null && value !== "")
      .join(" · ");
  }
  function valid(s, epoch) {
    return !s.dead && s.epoch === epoch;
  }
  async function read(s, path, signal) {
    const signals = [s.abort.signal, s.scopeAbort.signal];
    if (signal) signals.push(signal);
    return window.ApiClient.request(path, { signal: AbortSignal.any(signals) });
  }
  function stockBadge(code) {
    return badge(code, inventoryLabels[code] || text(code));
  }
  function errorMessage(error) {
    if (error.sessionExpired)
      return "Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.";
    if (error.status === 403)
      return "Bạn không có quyền thực hiện thao tác này.";
    if (error.resultUnknown)
      return "Không đọc được kết quả xử lý. Hãy tải lại để kiểm tra trạng thái.";
    if (error.status >= 500)
      return "Không thể tải hoặc xử lý dữ liệu lúc này. Vui lòng thử lại sau.";
    if (!error.status)
      return /API|JSON|backend|Content-Type|CORS|máy chủ/i.test(
        error.message || "",
      )
        ? "Không thể tải hoặc xử lý dữ liệu. Vui lòng thử lại."
        : error.message || "Không thể thực hiện thao tác. Vui lòng thử lại.";
    let message = (error.message || "Thao tác không thành công.").replace(
      /\s*\(HTTP \d+\)/g,
      "",
    );
    for (const [code, label] of Object.entries({
      ...orderStates,
      ...inventoryLabels,
    }))
      message = message.replaceAll(code, label.toLowerCase());
    return error.status === 409 ? "Chưa thể thực hiện. " + message : message;
  }
  function updateActions(s) {
    if (s.outboundFilters) s.outboundFilters.inert = s.pendingWrite;
    if (s.returnFilters) s.returnFilters.inert = s.pendingWrite;
    if (s.returnRefresh) s.returnRefresh.disabled = s.pendingWrite;
    for (const node of s.toolbar.querySelectorAll("[data-permission]")) {
      node.hidden = !can(s, node.dataset.permission);
      node.disabled = !s.warehouse || s.pendingWrite;
    }
    for (const node of s.container.querySelectorAll("[data-stock-action]"))
      node.disabled = s.pendingWrite || node.dataset.eligible === "false";
  }
  function writeButton(s, label, callback, eligible = true) {
    const node = button(label, callback, "btn btn-outline-orange btn-sm");
    node.dataset.stockAction = "true";
    node.dataset.eligible = String(eligible);
    node.disabled = s.pendingWrite || !eligible;
    return node;
  }
  function orderCell(s, row) {
    const cell = el("div", "inventory-order");
    for (const [label, value] of [
      ["Mã đơn", row.orderCode],
      ["Mã vận đơn", row.trackingNumber],
    ]) {
      const line = el("div", "inventory-code-line");
      const code = el("span", "inventory-code", value);
      code.title = text(value);
      code.tabIndex = 0;
      code.setAttribute("aria-label", label + ": " + text(value));
      const copy = button("Sao chép", async () => {
        copy.disabled = true;
        try {
          await navigator.clipboard.writeText(String(value));
          notice(
            s.alert,
            "Đã sao chép " + label.toLowerCase() + ".",
            "success",
          );
        } catch (_) {
          const view = dialog(s, "Sao chép " + label.toLowerCase());
          const full = input("text", value);
          full.readOnly = true;
          view.body.append(
            field(label, full, "mb-2"),
            el(
              "p",
              "text-secondary",
              "Chọn mã rồi sao chép bằng Ctrl+C hoặc thao tác sao chép trên thiết bị.",
            ),
          );
          full.focus();
          full.select();
        } finally {
          copy.disabled = false;
        }
      });
      copy.disabled = value == null || value === "";
      copy.setAttribute("aria-label", "Sao chép " + label.toLowerCase());
      line.append(code, copy);
      cell.append(line);
    }
    if(window.PickupReceipts&&can(s,"KHO_XEM"))cell.append(button("Biên nhận nhận kiện",()=>window.PickupReceipts.show(s,row.orderId||row.id),"btn btn-outline-orange btn-sm"));
    return cell;
  }
  function orderLink(s, row) {
    return button(
      text(row.orderCode),
      () => window.OrdersPage.showDetail(s, row.orderId || row.id),
      "btn btn-link order-code p-0",
    );
  }
  function loading(node, message) {
    node.setAttribute("aria-busy", "true");
    node.replaceChildren(
      el("p", "orders-empty", message || "Đang tải dữ liệu…"),
    );
  }

  function mount(container, user, mode, route, routeContext) {
    destroy();
    if (mode === "inbound-outbound") {
      window.InboundPage.mount(container, user, route, routeContext);
      return;
    }
    if (mode === "warehouse-locations") {
      window.LocationsPage.mount(container, user, route, routeContext);
      return;
    }
    if (mode === "warehouse-transactions") {
      window.TransactionsPage.mount(container, user, route, routeContext);
      return;
    }
    const account = String(user.accountId || user.username);
    if (remembered.account !== account)
      remembered = { account, warehouseId: null };
    const s = {
      container,
      user,
      mode,
      route,
      permissions: routeContext.permissions,
      warehouse: null,
      locations: [],
      epoch: 0,
      abort: new AbortController(),
      scopeAbort: new AbortController(),
      dialogs: new Set(),
      lists: [],
      dead: false,
      pendingWrite: false,
    };
    active = s;
    if (route.mode === "detail") {
      openTransaction(s, route.params.id);
      return;
    }
    const outbound = mode === "warehouse-outbound";
    const returning = mode === "warehouse-return";
    const compact = mode === "inventory" || outbound || returning;
    const card = el(
      "section",
      "orders-card warehouse-card" +
        (compact && !returning ? " inventory-card" : "") +
        (outbound ? " outbound-card" : "") +
        (returning ? " return-card" : ""),
    );
    const heading = el("div", "orders-toolbar");
    const intro = el("div");
    intro.append(
      el("h2", "", viewTitles[mode]),
      el(
        "p",
        "text-secondary mb-0",
        "Quản lý hàng trong kho theo phạm vi tài khoản.",
      ),
    );
    s.toolbar = heading;
    if (mode === "inventory") {
      const actions = el("div", "order-actions");
      for (const [label, modeId, permission] of [
        ["Nhập kho", "inbound-outbound", "KHO_NHAP"],
        ["Xuất kho", "warehouse-outbound", "KHO_XUAT"],
      ]) {
        const action = button(
          label,
          () =>
            window.Router.navigate(
              window.Router.href(modeId, {}, { warehouseId: s.warehouse?.id }),
            ),
          "btn btn-outline-orange",
        );
        action.dataset.permission = permission;
        action.hidden = true;
        actions.append(action);
      }
      actions.append(
        button("Làm mới", () => {
          if (s.warehouse) refresh(s);
          else loadWarehouses(s);
        }),
      );
      heading.append(actions);
    } else
      heading.append(
        intro,
        button("Tải lại kho", () => loadWarehouses(s)),
      );
    const context = el("div", "warehouse-context row g-3");
    s.warehouseSelect = select([], "Đang tải kho…");
    s.warehouseSelect.required = false;
    s.warehouseSelect.disabled = true;
    s.locationSelect = select([], "Chọn kho trước");
    s.locationSelect.required = false;
    s.locationSelect.disabled = true;
    s.contextInfo = el("div", "col-12 text-secondary warehouse-context-info");
    context.append(
      field("Kho", s.warehouseSelect),
      field("Vị trí lưu kho", s.locationSelect),
      s.contextInfo,
    );
    s.alert = el("div", "warehouse-message");
    s.permissionMessage = el("div", "warehouse-message");
    s.content = el("div", "warehouse-content");
    card.append(
      ...(outbound || returning ? [] : [heading]),
      ...(compact ? [] : [context]),
      s.alert,
      s.permissionMessage,
      s.content,
    );
    container.replaceChildren(card);
    if (returning) {
      s.returnRefresh = button(
        "Làm mới",
        () => {
          if (s.warehouse) refresh(s);
          else loadWarehouses(s);
        },
        "btn btn-outline-orange return-refresh",
      );
      document.querySelector(".page-heading").append(s.returnRefresh);
    }
    s.warehouseSelect.addEventListener("change", () =>
      chooseWarehouse(s, s.warehouseSelect.value),
    );
    s.locationSelect.addEventListener("change", () => showContext(s));
    buildContent(s);
    updateActions(s);
    loadWarehouses(s, true);
  }
  async function loadPermissions(s) {
    notice(s.permissionMessage, "Đang kiểm tra quyền thao tác kho…", "info");
    try {
      const result = await window.Auth.getPermissions(s.user, s.abort.signal);
      if (s.dead) return;
      s.permissions = result;
      notice(
        s.permissionMessage,
        result.known ? "" : result.message,
        "warning",
      );
    } catch (error) {
      if (s.dead || error.name === "AbortError") return;
      s.permissions = { known: false, codes: new Set() };
      notice(
        s.permissionMessage,
        "Chưa kiểm tra được quyền thao tác. " + errorMessage(error),
        "warning",
      );
      s.permissionMessage.append(
        button("Kiểm tra lại quyền", () => loadPermissions(s)),
      );
    }
    if (!s.dead) {
      updateActions(s);
      refresh(s);
    }
  }
  async function loadWarehouses(s, restore = false) {
    const oldId =
      restore && s.route.query.warehouseId
        ? s.route.query.warehouseId
        : s.warehouse?.id || remembered.warehouseId;
    clearScope(s);
    s.warehouseSelect.disabled = true;
    s.warehouseSelect.replaceChildren();
    option(s.warehouseSelect, "", "Đang tải kho…");
    notice(s.alert, "");
    const epoch = s.epoch;
    try {
      const warehouses = await read(s, "/api/v1/warehouses");
      if (!valid(s, epoch)) return;
      if (!Array.isArray(warehouses))
        throw new Error("API danh sách kho trả dữ liệu không hợp lệ.");
      s.warehouses = warehouses;
      s.warehouseSelect.replaceChildren();
      option(s.warehouseSelect, "", "Chọn kho");
      for (const warehouse of warehouses)
        option(
          s.warehouseSelect,
          warehouse.id,
          text(warehouse.name) +
            " · " +
            text(warehouse.branchName) +
            " · " +
            text(warehouse.code),
        );
      s.warehouseSelect.disabled = !warehouses.length;
      if (!warehouses.length)
        notice(
          s.alert,
          "Không có kho hoạt động trong phạm vi tài khoản.",
          "info",
        );
      const preferred =
        warehouses.find((item) => Number(item.id) === Number(oldId)) ||
        (warehouses.length === 1 ? warehouses[0] : null);
      if (
        restore &&
        s.route.query.warehouseId &&
        !warehouses.some((item) => item.id === s.route.query.warehouseId)
      ) {
        notice(
          s.alert,
          "Không tìm thấy kho hoạt động trong phạm vi tài khoản. Hãy chọn kho được phép.",
        );
        return;
      }
      if (preferred) {
        s.warehouseSelect.value = preferred.id;
        await chooseWarehouse(s, preferred.id, restore);
      }
    } catch (error) {
      if (!valid(s, epoch) || error.name === "AbortError") return;
      s.warehouseSelect.replaceChildren();
      option(s.warehouseSelect, "", "Chưa tải được kho");
      notice(s.alert, errorMessage(error));
      s.alert.append(button("Thử lại", () => loadWarehouses(s)));
    }
  }
  function clearScope(s) {
    s.epoch++;
    s.scopeAbort.abort();
    s.scopeAbort = new AbortController();
    s.warehouse = null;
    s.locations = [];
    s.returnPermissionVerified = false;
    UI.closeDialogs(s);
    s.locationSelect.replaceChildren();
    option(s.locationSelect, "", "Chọn kho trước");
    s.locationSelect.disabled = true;
    s.contextInfo.textContent = "";
    if (s.returnLinks) s.returnLinks.hidden = true;
    for (const list of s.lists) list.clear();
    updateActions(s);
    if (s.locationTable)
      s.locationTable.replaceChildren(
        el("p", "orders-empty", "Chọn kho để xem vị trí."),
      );
  }
  async function chooseWarehouse(s, id, restore = false) {
    clearScope(s);
    notice(s.alert, "");
    s.warehouse =
      s.warehouses?.find((item) => String(item.id) === String(id)) || null;
    remembered.warehouseId = s.warehouse?.id || null;
    updateActions(s);
    if (!s.warehouse) {
      window.Router.updateQuery({}, s.route);
      return;
    }
    if (s.mode === "warehouse-return") {
      if (restore) for (const list of s.lists) list.restore(s.route.query);
      for (const link of s.returnLinks.querySelectorAll("a"))
        link.href = window.Router.href(
          link.dataset.route,
          {},
          { warehouseId: s.warehouse.id },
        );
      s.returnLinks.hidden = false;
      refresh(s);
      return;
    }
    showContext(s);
    s.locationSelect.replaceChildren();
    option(s.locationSelect, "", "Đang tải vị trí…");
    const epoch = s.epoch;
    try {
      const locations = await read(
        s,
        "/api/v1/warehouses/" + s.warehouse.id + "/locations",
      );
      if (!valid(s, epoch)) return;
      if (
        !Array.isArray(locations) ||
        locations.some(
          (item) => Number(item.warehouseId) !== Number(s.warehouse.id),
        )
      )
        throw new Error("API vị trí không khớp kho đã chọn.");
      s.locations = locations;
      s.locationSelect.replaceChildren();
      option(
        s.locationSelect,
        "",
        ["inventory", "warehouse-outbound"].includes(s.mode)
          ? "Tất cả vị trí"
          : "Chọn vị trí",
      );
      for (const location of locations)
        option(s.locationSelect, location.id, locationName(location));
      s.locationSelect.disabled = !locations.length;
      if (restore && s.route.query.locationId) {
        if (!locations.some((item) => item.id === s.route.query.locationId)) {
          notice(
            s.alert,
            "Vị trí trong URL không thuộc kho đã chọn hoặc không còn hoạt động.",
          );
          return;
        }
        s.locationSelect.value = s.route.query.locationId;
      }
      if (restore) for (const list of s.lists) list.restore(s.route.query);
      if (!locations.length && s.mode !== "warehouse-outbound")
        notice(
          s.alert,
          "Kho chưa có vị trí đang hoạt động. Không thể chọn vị trí nhập hoặc vị trí đích.",
          "warning",
        );
      refresh(s);
      if (s.mode === "warehouse-locations")
        window.Router.updateQuery(
          { warehouseId: s.warehouse.id, locationId: s.locationSelect.value },
          s.route,
        );
    } catch (error) {
      if (!valid(s, epoch) || error.name === "AbortError") return;
      s.locationSelect.replaceChildren();
      option(s.locationSelect, "", "Chưa tải được vị trí");
      notice(s.alert, errorMessage(error));
      s.alert.append(
        button("Tải lại vị trí", () => chooseWarehouse(s, s.warehouse.id)),
      );
      refresh(s);
    }
  }
  function showContext(s) {
    if (!s.warehouse) return;
    const location = s.locations.find(
      (item) => String(item.id) === s.locationSelect.value,
    );
    s.contextInfo.textContent =
      text(s.warehouse.branchName) +
      " · " +
      text(s.warehouse.address) +
      (location ? " · Vị trí: " + locationName(location) : "");
    if (s.mode === "warehouse-locations")
      window.Router.updateQuery(
        { warehouseId: s.warehouse.id, locationId: s.locationSelect.value },
        s.route,
      );
  }
  function showLocations(s) {
    if (!s.locationTable || !s.warehouse) return;
    s.locationTable.replaceChildren(
      table(
        ["Mã vị trí", "Khu lưu", "Kệ", "Ô", "Kho", "Bưu cục", "Thao tác"],
        s.locations.map((location) => [
          location.code,
          location.storageArea,
          location.rack,
          location.slot,
          s.warehouse.name,
          s.warehouse.branchName,
          button("Chọn vị trí", () => {
            s.locationSelect.value = location.id;
            showContext(s);
          }),
        ]),
      ),
    );
  }
  function refresh(s) {
    for (const list of s.lists) list.reload();
    showLocations(s);
  }
  function showWarehouseActionResult(s, context, result) {
    const readyForDispatch = result?.status === "WAITING_ASSIGNMENT";

    const message =
      result?.message ||
      context.successMessage ||
      (readyForDispatch
        ? "Đơn đã chuyển sang chờ phân công."
        : "Đã hoàn tất thao tác kho.");

    const details = [];

    if (result?.transactionCode) {
      details.push("Giao dịch: " + text(result.transactionCode) + ".");
    }

    if (result?.handoverId) {
      details.push(
        "Mã bàn giao: " +
          text(result.handoverCode) +
          ". Chờ shipper xác nhận nhận hàng.",
      );
    }

    notice(s.alert, [message, ...details].join(" "), "success");

    const warnings = [];

    if (typeof result?.warning === "string" && result.warning.trim()) {
      warnings.push(result.warning.trim());
    } else {
      // Dự phòng khi API chỉ trả cờ mà chưa có nội dung warning.
      if (result?.deadlineOverdue === true) {
        warnings.push(
          "Đơn đã đến hoặc quá hạn giao. Cần kiểm tra và xử lý ưu tiên.",
        );
      }

      if (result?.missingExpectedDeliveryAt === true) {
        warnings.push("Đơn chưa có hạn giao. Cần bổ sung kế hoạch giao.");
      }

      if (result?.requestedTimePassed === true) {
        warnings.push("Thời gian khách yêu cầu giao đã đến hoặc đã qua.");
      }
    }

    if (warnings.length) {
      const warningBox = el("div", "alert alert-warning mt-2");

      warningBox.setAttribute("role", "alert");

      warningBox.append(
        el("strong", "d-block mb-2", "Đã xử lý thành công — cần lưu ý"),
      );

      for (const message of new Set(warnings)) {
        warningBox.append(el("p", "mb-1", message));
      }

      s.alert.append(warningBox);
    }

    if (readyForDispatch) {
      const timeBox = el("div", "border rounded p-3 mt-2 bg-light");

      timeBox.append(
        el("strong", "d-block mb-2", "Thời gian giao hàng · Giờ Việt Nam"),
        summary([
          ["Mã đơn", result.orderCode || result.trackingNumber],
          ["Sẵn sàng phân công", date(result.readyAt)],
          ["Khách yêu cầu giao", date(result.requestedDeliveryAt)],
          ["Hạn giao", date(result.expectedDeliveryAt)],
        ]),
      );

      s.alert.append(timeBox);
    }
  }

  // Shared list implementation for warehouse inventory, order candidates, handovers and transactions.
  function createList(s, config) {
    const compact = config.compact === true;
    const state = {
      page: 1,
      pageSize: 10,
      sequence: 0,
      records: [],
      controller: null,
      timer: null,
      applied: {},
    };
    const node = el(
      "section",
      "warehouse-list" + (compact ? " inventory-list" : ""),
    );
    const heading = el("div", "warehouse-list-heading");
    heading.append(
      el("h3", "", config.title),
      button("Tải lại", () => reload()),
    );
    const form = el(
      "form",
      compact ? "inventory-filters" : "warehouse-filters row g-3",
    );
    const keyword = input("search", "", {
      maxLength: 100,
      placeholder: config.searchPlaceholder || "Mã đơn hoặc mã vận đơn",
    });
    if (compact) {
      form.append(field("Kho", s.warehouseSelect, "inventory-filter"));
      if (!config.returning)
        form.append(
          field("Vị trí lưu kho", s.locationSelect, "inventory-filter"),
        );
    }
    if (config.search && !compact)
      form.append(field("Tìm kiếm", keyword, "col-md-6"));
    const initialSize = config.routeList ? s.route.query.pageSize || 10 : 10;
    const pageSize = select(
      [...new Set([initialSize, 10, 20, 50, 100])]
        .sort((a, b) => a - b)
        .map((id) => ({ id, name: id + " dòng / trang" })),
      "Số dòng",
      initialSize,
    );
    const extra = config.filters
      ? config.filters(() => {
          state.page = 1;
          commit();
          reload();
        })
      : {};
    for (const control of extra.nodes || []) form.append(control);
    if (compact)
      form.append(
        field(
          config.outbound ? "Tìm kiếm" : "Mã đơn / mã vận đơn",
          keyword,
          "inventory-filter inventory-search",
        ),
      );
    const search = button(
      config.returning ? "Tìm kiếm" : compact ? "Lọc" : "Áp dụng",
      null,
      "btn btn-orange",
    );
    search.type = "submit";
    if (compact) {
      const actions = el("div", "inventory-filter-actions");
      actions.append(search);
      if (!config.returning)
        actions.append(
          button("Xóa bộ lọc", () => {
            keyword.value = "";
            s.locationSelect.value = "";
            extra.reset?.();
            state.page = 1;
            commit();
            reload();
          }),
        );
      if (config.returning) s.returnFilters = form;
      if (config.outbound) {
        actions.append(
          button("Làm mới", () => reload()),
          button("Tải lại danh mục kho", () => loadWarehouses(s)),
        );
        s.outboundFilters = form;
      }
      form.append(actions);
    } else form.append(field("Bộ lọc", search, "col-md-3"));
    const errorBox = el("div");
    const body = el("div");
    const pager = el("nav", "orders-pagination");
    pager.setAttribute(
      "aria-label",
      "Phân trang " + config.title.toLowerCase(),
    );
    const footer = el("div", "warehouse-list-footer");
    if (config.returning) footer.hidden = true;
    footer.append(field("Số dòng", pageSize, "warehouse-page-size"), pager);
    node.append(...(compact ? [] : [heading]), form, errorBox, body, footer);
    function commit() {
      state.applied = { ...extra.params?.() };
      if (config.search && keyword.value.trim())
        state.applied.keyword = keyword.value.trim();
    }
    form.addEventListener("submit", (event) => {
      event.preventDefault();
      if (form.reportValidity()) {
        state.page = 1;
        commit();
        reload();
      }
    });
    pageSize.addEventListener("change", () => {
      state.pageSize = Number(pageSize.value);
      state.page = 1;
      reload();
    });
    if (!compact)
      keyword.addEventListener("input", () => {
        state.page = 1;
        state.sequence++;
        state.controller?.abort();
        pager.replaceChildren();
        clearTimeout(state.timer);
        state.timer = setTimeout(() => {
          commit();
          reload();
        }, 300);
      });
    function clear() {
      state.sequence++;
      clearTimeout(state.timer);
      state.controller?.abort();
      state.records = [];
      state.page = 1;
      keyword.value = "";
      extra.reset?.();
      notice(errorBox, "");
      pager.replaceChildren();
      commit();
      if (config.returning) footer.hidden = true;
      body.setAttribute("aria-busy", "false");
      body.replaceChildren(
        el(
          "p",
          "orders-empty",
          config.returning
            ? "Chọn kho để xem yêu cầu hoàn"
            : config.outbound
              ? "Chọn kho để xem đơn chờ nhận kiện"
              : compact
                ? "Chọn kho để xem tồn kho"
                : "Chọn kho để xem dữ liệu.",
        ),
      );
    }
    async function reload() {
      if (s.dead || !s.warehouse) return;
      clearTimeout(state.timer);
      state.controller?.abort();
      state.controller = new AbortController();
      const seq = ++state.sequence,
        epoch = s.epoch;
      notice(errorBox, "");
      loading(body);
      pager.replaceChildren();
      state.records = [];
      if (config.returning) footer.hidden = true;
      config.onLoading?.();
      try {
        if (!form.reportValidity()) {
          body.replaceChildren(
            el("p", "orders-empty", "Kiểm tra bộ lọc trước khi tải dữ liệu."),
          );
          return;
        }
        if (config.routeList) {
          const values = {
            warehouseId: s.warehouse.id,
            page: state.page,
            pageSize: state.pageSize,
            ...state.applied,
          };
          if (values.orderStatus) {
            values.status = values.orderStatus;
            delete values.orderStatus;
          }
          window.Router.updateQuery(values, s.route);
        }
        const query = new URLSearchParams({
          page: state.page,
          pageSize: state.pageSize,
          ...state.applied,
        });
        const url = config.path(s.warehouse, query);
        const result = await read(s, url, state.controller.signal);
        if (!valid(s, epoch) || seq !== state.sequence) return;
        window.ApiClient.validatePage(result, url, config.idFields || []);
        config.onResult?.(result);
        const pages = Math.min(
          100000,
          Math.max(1, Math.ceil(result.totalItems / state.pageSize)),
        );
        if (state.page > pages) {
          state.page = pages;
          reload();
          return;
        }
        state.records = result.items;
        body.replaceChildren(
          result.items.length
            ? table(
                config.headers,
                result.items.map((row) => config.row(row)),
              )
            : el(
                "p",
                "orders-empty",
                config.returning
                  ? "Không có yêu cầu hoàn phù hợp tại kho này"
                  : config.outbound
                    ? "Không có đơn phù hợp tại kho này"
                    : compact
                      ? "Không có hàng phù hợp"
                      : "Không có dữ liệu.",
              ),
        );
        pagination(
          pager,
          state.page,
          state.pageSize,
          result.totalItems,
          (page) => {
            state.page = page;
            reload();
          },
        );
        if (config.returning)
          footer.hidden = result.totalItems <= state.pageSize;
      } catch (error) {
        if (
          !valid(s, epoch) ||
          seq !== state.sequence ||
          error.name === "AbortError"
        )
          return;
        notice(errorBox, errorMessage(error));
        body.replaceChildren(el("p", "orders-empty", "Chưa tải được dữ liệu."));
        (config.returning ? errorBox : pager).append(button("Thử lại", reload));
      } finally {
        if (valid(s, epoch) && seq === state.sequence)
          body.setAttribute("aria-busy", "false");
      }
    }
    const list = {
      node,
      reload,
      clear,
      restore(query) {
        if (!config.routeList) return;
        state.page = query.page || 1;
        state.pageSize = query.pageSize || 10;
        pageSize.value = state.pageSize;
        keyword.value = query.keyword || "";
        extra.restore?.(query);
        commit();
      },
      dispose() {
        state.sequence++;
        clearTimeout(state.timer);
        state.controller?.abort();
      },
    };
    s.lists.push(list);
    clear();
    return list;
  }
  function buildContent(s) {
    s.content.replaceChildren();
    if (s.mode === "warehouse-locations") {
      s.locationTable = el("div");
      s.locationTable.append(
        el("p", "orders-empty", "Chọn kho để xem vị trí."),
      );
      s.content.append(s.locationTable);
      return;
    }
    if (s.mode === "warehouse-transactions") {
      s.content.append(historyList(s).node);
      return;
    }
    if (s.mode === "inventory") {
      const guide = el("div", "alert alert-light border mb-3");
      guide.append(el("strong", "", "Xuất hàng cho tài xế ở đâu? "),
        document.createTextNode("Tài xế xác nhận nhận kiện trên app để hệ thống tự ghi xuất kho. Nút “Xem xuất kho” giúp theo dõi đơn chờ nhận; đơn đã xuất xem tại Lịch sử giao dịch."));
      s.content.append(guide);
      s.content.append(inventoryList(s).node);
      return;
    }
    if (s.mode === "warehouse-return") {
      s.content.append(returnRequestList(s).node);
      s.returnLinks = el("nav", "return-links");
      s.returnLinks.hidden = true;
      s.returnLinks.setAttribute("aria-label", "Trang kho liên quan");
      for (const [label, route] of [
        ["Xem tồn kho", "inventory"],
        ["Xuất kho", "warehouse-outbound"],
        ["Xem lịch sử giao dịch", "warehouse-transactions"],
      ]) {
        const link = el("a", "", label);
        link.dataset.route = route;
        s.returnLinks.append(link);
      }
      s.content.append(s.returnLinks);
      return;
    }
    if (s.mode === "warehouse-outbound") {
      s.content.append(handoverList(s).node);
      return;
    }
    s.content.append(inventoryList(s).node, historyList(s).node);
  }
  function inventoryList(s) {
    return createList(s, {
      title: "Tồn kho",
      search: true,
      compact: s.mode === "inventory",
      routeList: s.mode === "inventory",
      idFields: ["orderId", "warehouseId"],
      path: (warehouse, query) =>
        "/api/v1/warehouses/" + warehouse.id + "/inventory?" + query,
      filters: () => {
        if (s.mode !== "inventory") return {};
        const status = select(
          Object.entries(orderStates).map(([id, name]) => ({ id, name })),
          "Tất cả trạng thái",
        );
        status.required = false;
        return {
          nodes: [field("Trạng thái đơn", status, "inventory-filter")],
          params: () => {
            const values = {};
            if (status.value) values.orderStatus = status.value;
            if (s.locationSelect.value)
              values.locationId = s.locationSelect.value;
            return values;
          },
          reset: () => {
            status.value = "";
          },
          restore: (query) => {
            status.value = query.status || "";
          },
        };
      },
      headers: [
        "Đơn hàng",
        "Vị trí lưu kho",
        "Trạng thái đơn",
        "Trạng thái tồn kho",
        "Khối lượng",
        "Thời gian nhập kho (VN)",
        "Thao tác",
      ],
      row: (row) => {
        const actions = el("div", "order-actions");
        if (can(s, "DONHANG_XEM"))
          actions.append(
            button("Chi tiết đơn", () =>
              window.OrdersPage.showDetail(s, row.orderId),
            ),
          );
        if (can(s, "KHO_XUAT") && row.orderStatus === "ASSIGNED" &&
            ["STORED", "ALLOCATED"].includes(row.inventoryStatus)) {
          actions.append(button("Xem xuất kho", () => window.Router.navigate(
            window.Router.href("warehouse-outbound", {}, {
              warehouseId: row.warehouseId,
              keyword: row.trackingNumber || row.orderCode,
            }),
          ), "btn btn-outline-orange"));
        }
        if (
          can(s, "KHO_KIEMKE") &&
          row.locationId != null &&
          ["RECEIVED", "STORED", "ALLOCATED", "RETURNED"].includes(
            row.inventoryStatus,
          )
        )
          actions.append(
            writeButton(s, "Chuyển vị trí", () => openMove(s, row)),
          );
        if (can(s, "KHO_NHAP")) {
          const ready = writeButton(
            s,
            "Chờ phân công",
            () => openReady(s, row),
            row.orderStatus === "IN_WAREHOUSE" &&
              row.inventoryStatus === "STORED",
          );
          if (ready.disabled)
            ready.title =
              "Đơn cần ở trạng thái đã nhập kho và hàng đang lưu kho.";
          actions.append(ready);
        }
        actions.append(button("Lịch sử kho", () => openHistory(s, row)));
        return [
          orderCell(s, row),
          row.locationCode,
          badge(row.orderStatus, row.orderStatusName),
          stockBadge(row.inventoryStatus),
          weight(row.weightKg),
          date(row.receivedAt),
          actions,
        ];
      },
    });
  }
  function returnRequestList(s) {
    return createList(s, {
      title: "Yêu cầu hoàn",
      search: true,
      compact: true,
      returning: true,
      routeList: true,
      onLoading: () => {
        s.returnPermissionVerified = false;
      },
      onResult: (result) => {
        if (typeof result.canReturnIn !== "boolean")
          throw new Error("API yêu cầu hoàn thiếu thông tin quyền nhập hoàn.");
        if (result.warehouseId !== s.warehouse.id)
          throw new Error("API yêu cầu hoàn không khớp kho đã chọn.");
        s.returnPermissionVerified = result.canReturnIn;
        if (s.returnPermissionVerified && !s.permissions.known)
          notice(
            s.permissionMessage,
            "Đã xác minh quyền nhập hoàn tại kho đã chọn. Các quyền thao tác kho khác chưa được xác minh.",
            "info",
          );
      },
      idFields: ["orderId", "returnRequestId", "branchId", "returnBranchId"],
      path: (warehouse, query) =>
        "/api/v1/warehouses/" + warehouse.id + "/return-requests?" + query,
      headers: [
        "Mã đơn",
        "Mã vận đơn",
        "Yêu cầu hoàn",
        "Lý do hoàn",
        "Trạng thái hoàn",
        "Thao tác",
      ],
      row: (row) => {
        const actions = el("div", "order-actions");
        const reason = returnReason(s, row);
        const receive = writeButton(
          s,
          "Nhận hàng hoàn",
          () => openReturn(s, row),
          !reason,
        );
        if (reason) {
          receive.title = reason;
          actions.append(receive, el("small", "text-secondary", reason));
        } else actions.append(receive);
        const code = (value) => {
          const node = el("span", "return-code", text(value));
          node.title = text(value);
          return node;
        };
        return [
          code(row.orderCode),
          code(row.trackingNumber),
          "#" + row.returnRequestId,
          row.reason,
          badge(
            row.requestStatus,
            {
              IN_PROGRESS: "Đang chuyển hoàn",
              COMPLETED: "Đã nhận hàng hoàn",
              CANCELLED: "Đã hủy",
            }[row.requestStatus] || "Chờ xử lý hoàn",
          ),
          actions,
        ];
      },
    });
  }
  function returnReason(s, row) {
    if (!can(s, "KHO_NHAP") || !s.returnPermissionVerified)
      return "Bạn chưa có quyền nhập hàng hoàn tại kho này.";
    if (
      row.orderStatus !== "RETURNING" ||
      row.requestStatus !== "IN_PROGRESS" ||
      row.stockStatus !== "HANDED_OVER"
    )
      return "Đơn hoặc yêu cầu hoàn chưa đủ điều kiện nhập kho.";
    if (
      row.branchId !== s.warehouse?.branchId ||
      row.returnBranchId !== row.branchId
    )
      return "Yêu cầu hoàn không thuộc bưu cục của kho đã chọn.";
    return "";
  }
  function handoverList(s) {
    return createList(s, {
      title: "Đơn chờ tài xế nhận kiện",
      search: true,
      compact: true,
      outbound: true,
      routeList: true,
      searchPlaceholder: "Mã đơn, vận đơn, tên hoặc mã nhân viên",
      idFields: ["orderId", "assignmentId", "locationId"],
      path: (warehouse, query) =>
        "/api/v1/warehouses/" + warehouse.id + "/handover-orders?" + query,
      filters: () => {
        const status = select(
          Object.entries(assignmentStates).map(([id, name]) => ({ id, name })),
          "Tất cả trạng thái",
        );
        status.required = false;
        return {
          nodes: [field("Trạng thái phân công", status, "inventory-filter")],
          params: () => ({
            ...(status.value ? { assignmentStatus: status.value } : {}),
            ...(s.locationSelect.value
              ? { locationId: s.locationSelect.value }
              : {}),
          }),
          reset: () => {
            status.value = "";
          },
          restore: (query) => {
            status.value =
              query.assignmentStatus ||
              (query.acceptedOnly === "true" ? "ACCEPTED" : "");
          },
        };
      },
      headers: [
        "Mã đơn / mã vận đơn",
        "Vị trí hiện tại",
        "Shipper",
        "Phương tiện / biển số",
        "Trạng thái phân công",
        "Trạng thái đơn",
        "Khối lượng",
        "Thao tác",
      ],
      row: (row) => {
        const actions = el("div", "order-actions");
        if (can(s, "DONHANG_XEM"))
          actions.append(
            button("Chi tiết", () =>
              window.OrdersPage.showDetail(s, row.orderId),
            ),
          );
        if (can(s, "KHO_XUAT") && row.orderStatus === "ASSIGNED") {
          const reason = handoverReason(row);
          const outboundBtn = writeButton(
            s,
            "Xác nhận xuất kho",
            () => openOutbound(s, row),
            !reason,
          );
          if (reason) outboundBtn.title = reason;
          actions.append(outboundBtn);
        }
        if(window.PickupIssues)actions.append(button("Sự cố nhận kiện / Xử lý",()=>window.PickupIssues.show(s,row.orderId)));
        const actionCell = el("div", "outbound-actions");
        actionCell.append(actions);
        const reasonText = row.pickupBlocked ? "Đang chờ xử lý sự cố nhận kiện. Mở hồ sơ để xem ảnh và phản hồi." :
          row.pickupIssueReason ? "Đã có báo cáo nhận kiện: " + row.pickupIssueReason + ". Mở hồ sơ để xem phản hồi/kết quả xử lý." :
          row.assignmentStatus === "PENDING" ? "Chờ tài xế nhận nhiệm vụ" :
          row.orderStatus === "HANDED_OVER" ? "Kho đã xuất · Chờ tài xế ký nhận trên app" :
          (handoverReason(row) || "Thủ kho quét súng barcode đối chiếu rồi bấm Xác nhận xuất kho.");
        actionCell.append(el("p", "outbound-lock-reason", reasonText));
        return [
          orderCell(s, row),
          row.locationCode,
          text(row.shipperName) + " · " + text(row.employeeCode),
          [row.vehicleType, row.licensePlate].filter(Boolean).join(" · ") ||
            "—",
          badge(row.assignmentStatus, assignmentStates[row.assignmentStatus]),
          badge(row.orderStatus, orderStates[row.orderStatus]),
          weight(row.weightKg),
          actionCell,
        ];
      },
    });
  }
  function handoverReason(row) {
    if(row.pickupBlocked===true)return "Đơn đang chờ kho/điều phối xử lý sự cố nhận kiện.";
    if (row.assignmentStatus === "PENDING") return "Chờ shipper nhận nhiệm vụ";
    if (row.orderStatus !== "ASSIGNED")
      return "Đơn chưa ở trạng thái đã phân công.";
    if (row.assignmentStatus !== "ACCEPTED")
      return "Phân công chưa được shipper chấp nhận.";
    if (
      row.locationId == null ||
      !["STORED", "ALLOCATED"].includes(row.stockStatus)
    )
      return "Hàng không còn tồn kho hợp lệ để bàn giao.";
    if (row.canHandover !== true)
      return "Shipper, phương tiện hoặc tải hàng chưa đủ điều kiện bàn giao.";
    return "";
  }
  function historyList(s, order) {
    return createList(s, {
      title: "Lịch sử giao dịch kho",
      search: false,
      routeList: s.mode === "warehouse-transactions" && !order,
      idFields: ["id", "warehouseId"],
      path: (warehouse, query) => {
        query.set("warehouseId", warehouse.id);
        return "/api/v1/warehouse-transactions?" + query;
      },
      filters: (changed) => {
        const type = select(
          Object.entries(types).map(([id, name]) => ({ id, name })),
          "Tất cả loại giao dịch",
        );
        type.required = false;
        const orderId = input("number", order?.orderId || "", {
          min: "1",
          max: String(Number.MAX_SAFE_INTEGER),
          step: "1",
          placeholder: "ID đơn",
        });
        type.addEventListener("change", changed);
        orderId.addEventListener("change", changed);
        return {
          nodes: [
            field("Loại giao dịch", type, "col-md-6"),
            ...(order ? [] : [field("ID đơn (tùy chọn)", orderId, "col-md-6")]),
          ],
          params: () => {
            const values = {};
            if (type.value) values.type = type.value;
            if (orderId.value) values.orderId = orderId.value;
            return values;
          },
          reset: () => {
            type.value = "";
            orderId.value = order?.orderId || "";
          },
          restore: (query) => {
            type.value = query.type || "";
            orderId.value = query.orderId || "";
          },
        };
      },
      headers: [
        "Mã giao dịch",
        "Kho",
        "Loại",
        "Trạng thái giao dịch",
        "Số đơn",
        "Người thực hiện",
        "Thời gian (VN)",
        "Ghi chú",
        "Thao tác",
      ],
      row: (row) => [
        row.transactionCode,
        row.warehouseName,
        types[row.type] || row.type,
        transactionStates[row.status] || row.status,
        row.orderCount,
        row.performedByName || row.performedBy,
        date(row.performedAt),
        row.notes,
        button("Chi tiết giao dịch", () =>
          window.Router.navigate(
            window.Router.href(
              "transaction-detail",
              { id: row.id },
              {
                ...(s.route.pageId === "warehouse-transactions"
                  ? window.Router.current()?.query
                  : {}),
                warehouseId: s.warehouse?.id,
              },
            ),
          ),
        ),
      ],
    });
  }

  function openHistory(s, row) {
    const view = dialog(s, "Lịch sử kho · " + text(row.orderCode), true);
    const list = historyList(s, row);
    view.body.append(list.node);
    view.onClose(() => {
      list.dispose();
      s.lists = s.lists.filter((item) => item !== list);
    });
    list.reload();
  }

  function openReady(s, row) {
    if (
      row.orderStatus !== "IN_WAREHOUSE" ||
      row.inventoryStatus !== "STORED"
    ) {
      return;
    }

    return actionView(s, "Chuyển sang chờ phân công", "KHO_NHAP", async () => {
      const current = await findInventory(s, row);

      if (
        current.orderStatus !== "IN_WAREHOUSE" ||
        current.inventoryStatus !== "STORED"
      ) {
        throw Object.assign(
          new Error(
            "Đơn không còn đủ điều kiện chuyển sang chờ phân công. Hãy kiểm tra lại tồn kho.",
          ),
          { status: 409 },
        );
      }

      if (
        typeof current.version !== "string" ||
        !/^[A-Za-z0-9+/]{11}=$/.test(current.version)
      ) {
        throw new Error(
          "API tồn kho chưa trả phiên bản hợp lệ. Hãy cập nhật backend và tải lại.",
        );
      }

      for (const key of ["requestedDeliveryAt", "expectedDeliveryAt"]) {
        if (!Object.prototype.hasOwnProperty.call(current, key)) {
          throw new Error(
            "API tồn kho chưa trả đủ lịch giao. Hãy cập nhật backend và tải lại.",
          );
        }
      }

      // Giữ phiên bản đã hiển thị trong hộp xác nhận.
      // Không tự lấy version mới khi người dùng bấm gửi.
      const expectedVersion = current.version;

      return {
        endpoint:
          "/api/v1/orders/" +
          encodeURIComponent(current.orderId) +
          "/ready-for-dispatch",

        title: "Chờ phân công",
        noBody: false,
        hideNotes: true,
        successMessage: "Đơn đã chuyển sang chờ phân công.",

        pairs: [
          ["Đơn hàng", current.orderCode],
          ["Mã vận đơn", current.trackingNumber],
          ["Kho", s.warehouse.name],
          ["Vị trí", current.locationCode],
          ["Khách yêu cầu giao (giờ VN)", date(current.requestedDeliveryAt)],
          ["Hạn giao (giờ VN)", date(current.expectedDeliveryAt)],
        ],

        controls: [],

        values: () => ({
          expectedVersion,
        }),

        confirm: () =>
          "Chuyển đơn " +
          text(current.orderCode) +
          " sang chờ phân công theo lịch đang hiển thị? Hàng vẫn được lưu tại kho này.",
      };
    });
  }

  async function findInventory(s, row) {
    const query = new URLSearchParams({
      keyword: row.orderCode || row.trackingNumber || "",
      pageSize: 100,
    });
    // The API only supports keyword, not orderId. Match exact orderId across its result pages.
    for (let page = 1; page <= 100000; page++) {
      query.set("page", page);
      const result = await read(
        s,
        "/api/v1/warehouses/" + s.warehouse.id + "/inventory?" + query,
      );
      if (!result || !Array.isArray(result.items))
        throw new Error("Không đọc được bản tồn kho mới nhất.");
      const current = result.items.find(
        (item) => Number(item.orderId) === Number(row.orderId),
      );
      if (current) return current;
      if (page * 100 >= result.totalItems || !result.items.length) break;
    }
    throw new Error(
      "Đơn không còn trong tồn kho của kho đã chọn. Hãy tải lại tồn kho.",
    );
  }
  async function findHandover(s, row) {
    const query = new URLSearchParams({
      keyword: row.orderCode || row.trackingNumber || "",
      pageSize: 100,
      acceptedOnly: "true",
    });
    for (let page = 1; page <= 100000; page++) {
      query.set("page", page);
      const result = await read(
        s,
        "/api/v1/warehouses/" + s.warehouse.id + "/handover-orders?" + query,
      );
      if (!result || !Array.isArray(result.items))
        throw new Error("Không đọc được phân công bàn giao mới nhất.");
      const current = result.items.find(
        (item) =>
          Number(item.orderId) === Number(row.orderId) &&
          Number(item.assignmentId) === Number(row.assignmentId),
      );
      if (current) return current;
      if (page * 100 >= result.totalItems || !result.items.length) break;
    }
    throw new Error(
      "Phân công đã thay đổi hoặc không còn đủ điều kiện bàn giao. Hãy tải lại danh sách.",
    );
  }
  function locationControl(s, locations, selected) {
    return select(
      locations.map((item) => ({ id: item.id, name: locationName(item) })),
      "Chọn vị trí",
      selected || s.locationSelect.value,
    );
  }
  async function actionView(s, title, permission, prepare) {
    if (
      s.dead ||
      !s.warehouse ||
      !can(s, permission) ||
      s.pendingWrite ||
      s.dialogs.size
    )
      return;
    const view = dialog(s, title);
    const epoch = s.epoch;
    loading(view.body, "Đang kiểm tra dữ liệu hiện tại…");
    try {
      const context = await prepare();
      if (!valid(s, epoch) || !view.node.isConnected) return;
      renderAction(s, view, context, epoch, permission);
    } catch (error) {
      if (
        !valid(s, epoch) ||
        !view.node.isConnected ||
        error.name === "AbortError"
      )
        return;
      const errorBox = el("div");
      notice(errorBox, errorMessage(error));
      view.body.replaceChildren(
        errorBox,
        button("Đóng và tải lại", () => {
          view.close();
          refresh(s);
        }),
      );
      if (error.status === 409) refresh(s);
    } finally {
      view.body.setAttribute("aria-busy", "false");
    }
  }
  function openMove(s, row) {
    return actionView(
      s,
      "Chuyển vị trí · " + text(row.orderCode),
      "KHO_KIEMKE",
      async () => {
        const current = await findInventory(s, row);
        if (
          current.locationId == null ||
          !["RECEIVED", "STORED", "ALLOCATED", "RETURNED"].includes(
            current.inventoryStatus,
          )
        )
          throw new Error(
            "Đơn không có vị trí nguồn hoặc không còn trong kho để di chuyển.",
          );
        const locations = await read(
          s,
          "/api/v1/warehouses/" + s.warehouse.id + "/locations",
        );
        const target = locationControl(
          s,
          locations.filter(
            (item) =>
              Number(item.warehouseId) === Number(s.warehouse.id) &&
              Number(item.id) !== Number(current.locationId),
          ),
        );
        return {
          endpoint: "/api/v1/warehouse-transactions/move",
          title: "Chuyển vị trí",
          pairs: [
            ["Đơn", current.orderCode],
            ["Kho", s.warehouse.name],
            [
              "Vị trí nguồn mới nhất",
              current.locationCode || current.locationId,
            ],
          ],
          controls: [field("Vị trí đích trong cùng kho *", target, "mb-3")],
          values: () => ({
            orderId: current.orderId,
            fromLocationId: current.locationId,
            toLocationId: Number(target.value),
          }),
          confirm: () =>
            "Chuyển " +
            text(current.orderCode) +
            " từ " +
            text(current.locationCode || current.locationId) +
            " tới " +
            text(target.selectedOptions[0]?.textContent) +
            "?",
        };
      },
    );
  }
  function openReturn(s, row) {
    if (returnReason(s, row)) return;
    const warehouse = s.warehouse,
      epoch = s.epoch;
    return actionView(s, "Nhận hàng hoàn", "KHO_NHAP", async () => {
      const query = new URLSearchParams({
        orderId: row.orderId,
        returnRequestId: row.returnRequestId,
        page: 1,
        pageSize: 10,
      });
      const url =
        "/api/v1/warehouses/" + warehouse.id + "/return-requests?" + query;
      const result = window.ApiClient.validatePage(await read(s, url), url, [
        "orderId",
        "returnRequestId",
        "branchId",
        "returnBranchId",
      ]);
      if (!valid(s, epoch))
        throw new DOMException("Kho đã thay đổi", "AbortError");
      if (result.warehouseId !== warehouse.id || result.canReturnIn !== true)
        throw new Error("Chưa xác minh được quyền nhận hàng hoàn tại kho này.");
      const current = result.items.find(
        (item) =>
          item.orderId === row.orderId &&
          item.returnRequestId === row.returnRequestId,
      );
      if (!current || returnReason(s, current))
        throw Object.assign(
          new Error(
            "Yêu cầu hoàn không còn đủ điều kiện nhập kho. Hãy kiểm tra lại danh sách.",
          ),
          { status: 409 },
        );
      const locations = await read(
        s,
        "/api/v1/warehouses/" + warehouse.id + "/locations",
      );
      if (!valid(s, epoch))
        throw new DOMException("Kho đã thay đổi", "AbortError");
      if (
        !Array.isArray(locations) ||
        locations.some(
          (item) =>
            item.warehouseId !== warehouse.id ||
            !Number.isSafeInteger(item.id) ||
            item.id <= 0,
        )
      )
        throw new Error("API vị trí không khớp kho đã chọn.");
      s.locations = locations;
      const location = select(
        locations.map((item) => ({ id: item.id, name: locationName(item) })),
        "Chọn vị trí lưu kho",
      );
      const condition = select(
        Object.entries(conditions).map(([id, name]) => ({ id, name })),
        "Chọn tình trạng hàng",
        "NORMAL",
      );
      return {
        endpoint: "/api/v1/warehouse-transactions/return-in",
        singleStep: true,
        isReturn: true,
        dialogClass: "return-dialog",
        confirmLabel: "Xác nhận nhập hàng hoàn",
        successMessage: "Đã nhập hàng hoàn vào kho.",
        retainOnServerError: true,
        pairs: [
          ["Mã đơn", current.orderCode],
          ["Mã vận đơn", current.trackingNumber],
          ["Yêu cầu hoàn", "#" + current.returnRequestId],
          ["Lý do hoàn", current.reason],
          ["Kho đang chọn", warehouse.name],
        ],
        controls: [
          field("Vị trí lưu kho *", location, "mb-3"),
          field("Tình trạng hàng *", condition, "mb-3"),
          ...(!locations.length
            ? [
                el(
                  "p",
                  "alert alert-warning",
                  "Kho chưa có vị trí hoạt động. Cần bổ sung vị trí trước khi nhận hàng hoàn.",
                ),
              ]
            : []),
        ],
        validate(notes) {
          if (!locations.some((item) => item.id === Number(location.value)))
            throw new Error(
              "Hãy chọn vị trí lưu kho thuộc kho đang nhận hàng.",
            );
          if (!["NORMAL", "DAMAGED", "OTHER"].includes(condition.value))
            throw new Error("Tình trạng hàng không hợp lệ.");
          if (condition.value !== "NORMAL" && !notes.trim())
            throw new Error(
              "Phải ghi chú khi hàng hư hỏng hoặc có tình trạng khác.",
            );
        },
        values: () => ({
          orderId: current.orderId,
          returnRequestId: current.returnRequestId,
          warehouseId: warehouse.id,
          locationId: Number(location.value),
          condition: condition.value,
        }),
      };
    });
  }
  function openOutbound(s, row) {
    if (handoverReason(row)) return;
    return actionView(s, "Xác nhận bàn giao", "KHO_XUAT", async () => {
      const current = await findHandover(s, row);
      const reason = handoverReason(current);
      if (reason) throw new Error(reason);
      const warehouseId = s.warehouse.id;
      return {
        endpoint: "/api/v1/warehouse-transactions/outbound",
        singleStep: true,
        title: "Xuất kho",
        pairs: [
          ["Mã đơn", current.orderCode],
          ["Mã vận đơn", current.trackingNumber],
          ["Kho nguồn", s.warehouse.name],
          ["Vị trí nguồn", current.locationCode || current.locationId],
          ["Shipper", current.shipperName],
          [
            "Phương tiện / biển số",
            [current.vehicleType, current.licensePlate]
              .filter(Boolean)
              .join(" · "),
          ],
        ],
        controls: [
          el(
            "p",
            "text-secondary",
            "Sau bàn giao, shipper vẫn phải xác nhận nhận hàng trong ứng dụng shipper.",
          ),
        ],
        values: () => ({
          orderId: current.orderId,
          warehouseId,
          assignmentId: current.assignmentId,
          fromLocationId: current.locationId,
        }),
        confirm: () =>
          "Xuất " +
          text(current.orderCode) +
          " từ " +
          text(current.locationCode) +
          " để bàn giao cho " +
          text(current.shipperName) +
          "?",
      };
    });
  }
  function renderAction(s, view, context, epoch, permission) {
    if (context.dialogClass) view.node.classList.add(context.dialogClass);
    const errorBox = el("div");
    const form = el("form");
    form.noValidate = true;
    const fields = el("fieldset");
    const notes = el("textarea", "form-control");
    notes.maxLength = 500;
    notes.rows = 3;
    const confirmation = el("div", "warehouse-confirmation d-none");
    const confirmText = el("p");
    const review = button(
      context.singleStep
        ? context.confirmLabel || "Xác nhận bàn giao"
        : "Xem và xác nhận",
      null,
      "btn btn-orange",
    );
    review.type = "submit";
    const send = button("Đồng ý gửi", null, "btn btn-orange");
    const back = button("Sửa lại", () => {
      confirmation.classList.add("d-none");
      review.classList.remove("d-none");
    });
    confirmation.append(confirmText, el("div", "order-actions"));
    confirmation.lastElementChild.append(send, back);
    fields.append(
      summary(context.pairs),
      ...context.controls,
      ...(context.noBody || context.hideNotes
        ? []
        : [field("Ghi chú (tối đa 500 ký tự)", notes, "mb-3")]),
      review,
      confirmation,
    );
    form.append(fields);
    let cancel = null;
    if (context.singleStep) {
      cancel = button("Hủy", () => view.close());
      const actions = el("div", "order-actions");
      actions.append(cancel, review);
      form.append(actions);
    }
    view.body.replaceChildren(errorBox, form);
    let pending = false,
      blocked = false,
      reviewedPayload = null;
    form.addEventListener("input", () => {
      confirmation.classList.add("d-none");
      review.classList.remove("d-none");
      reviewedPayload = null;
    });
    form.addEventListener("change", () => {
      confirmation.classList.add("d-none");
      review.classList.remove("d-none");
      reviewedPayload = null;
    });
    function buildPayload() {
      if (!form.reportValidity()) {
        throw new Error("Kiểm tra các trường bắt buộc và lựa chọn vị trí.");
      }

      if (context.noBody) return {};

      context.validate?.(notes.value);

      return {
        ...context.values(),
        ...(context.hideNotes ? {} : { notes: notes.value.trim() || null }),
      };
    }
    form.addEventListener("submit", (event) => {
      event.preventDefault();
      if (pending || blocked) return;
      notice(errorBox, "");
      try {
        reviewedPayload = buildPayload();
        if (context.singleStep) {
          send.click();
          return;
        }
        confirmText.textContent =
          context.confirm() +
          (notes.value.trim() ? " Ghi chú: " + notes.value.trim() : "");
        confirmation.classList.remove("d-none");
        review.classList.add("d-none");
        send.focus();
      } catch (error) {
        notice(errorBox, error.message);
      }
    });
    send.addEventListener("click", async () => {
      if (
        pending ||
        blocked ||
        !reviewedPayload ||
        s.pendingWrite ||
        !valid(s, epoch) ||
        !can(s, permission)
      )
        return;
      let payload;
      try {
        payload = buildPayload();
      } catch (error) {
        notice(errorBox, error.message);
        return;
      }
      if (JSON.stringify(payload) !== JSON.stringify(reviewedPayload)) {
        notice(errorBox, "Dữ liệu đã thay đổi. Hãy xem và xác nhận lại.");
        return;
      }
      pending = true;
      s.pendingWrite = true;
      fields.disabled = true;
      review.disabled = true;
      if (cancel) cancel.disabled = true;
      view.setBusy(true);
      updateActions(s);
      notice(errorBox, "");
      // Mutation is sent once; changing scopes never automatically retries it.
      try {
        const result = await window.ApiClient.request(context.endpoint, {
          method: "POST",
          signal: AbortSignal.any([s.abort.signal, s.scopeAbort.signal]),
          ...(context.noBody ? {} : { body: JSON.stringify(payload) }),
        });
        if (!valid(s, epoch) || !view.node.isConnected) return;
        view.close();

        showWarehouseActionResult(s, context, result);

        refresh(s);
      } catch (error) {
        if (!valid(s, epoch) || !view.node.isConnected) return;
        notice(
          errorBox,
          error.status === 409 && context.singleStep && !context.isReturn
            ? "Dữ liệu đã thay đổi hoặc không còn đủ điều kiện bàn giao. Đã tải lại danh sách; hãy kiểm tra trước khi mở thao tác mới."
            : errorMessage(error),
        );
        if (error.status === 403) {
          s.returnPermissionVerified = false;
          s.permissions = { known: false, codes: new Set() };
          notice(
            s.permissionMessage,
            "Quyền thao tác đã bị từ chối. Hãy kiểm tra lại quyền hiện hành.",
            "warning",
          );
          s.permissionMessage.append(
            button("Kiểm tra lại quyền", () => loadPermissions(s)),
          );
        }
        if (
          [403, 404, 409].includes(error.status) ||
          !error.status ||
          (error.status >= 500 && !context.retainOnServerError)
        ) {
          blocked = true;
          errorBox.append(
            el(
              "p",
              "text-secondary",
              error.status === 409
                ? "Đã tải lại danh sách. Hãy kiểm tra dữ liệu trước khi mở thao tác mới."
                : "Kiểm tra dữ liệu và lịch sử trước khi mở thao tác mới.",
            ),
            button("Đóng và tải lại", () => {
              view.close();
              refresh(s);
            }),
          );
          refresh(s);
        }
      } finally {
        pending = false;
        s.pendingWrite = false;
        fields.disabled = blocked;
        review.disabled = blocked;
        if (cancel) cancel.disabled = false;
        view.setBusy(false);
        updateActions(s);
      }
    });
  }
  async function openTransaction(s, id) {
    const view = UI.routeView(
      s,
      "Chi tiết giao dịch kho",
      window.Router.href("warehouse-transactions", {}, s.route.query),
    );
    const epoch = s.epoch;
    async function reload() {
      loading(view.body, "Đang tải giao dịch…");
      try {
        const result = await read(
          s,
          "/api/v1/warehouse-transactions/" + encodeURIComponent(id),
        );
        if (!valid(s, epoch) || !view.node.isConnected) return;
        if (!result || !Array.isArray(result.items))
          throw new Error("API chi tiết giao dịch trả dữ liệu không hợp lệ.");
        view.body.replaceChildren(
          section(
            "Thông tin giao dịch",
            summary([
              ["Mã giao dịch", result.transactionCode],
              ["Kho", result.warehouseName],
              ["Loại", types[result.type] || result.type],
              ["Trạng thái", transactionStates[result.status] || result.status],
              ["Người thực hiện", result.performedByName || result.performedBy],
              ["Thời gian (VN)", date(result.performedAt)],
              ["Ghi chú", result.notes],
            ]),
          ),
          section(
            "Các đơn trong giao dịch",
            table(
              [
                "Mã đơn",
                "Mã vận đơn",
                "Vị trí nguồn",
                "Vị trí đích",
                "Tình trạng hàng",
                "Ghi chú",
              ],
              result.items.map((row) => [
                orderLink(s, row),
                row.trackingNumber,
                row.fromLocationCode,
                row.toLocationCode,
                conditions[row.condition] || row.condition,
                row.notes,
              ]),
            ),
          ),
        );
      } catch (error) {
        if (
          !valid(s, epoch) ||
          !view.node.isConnected ||
          error.name === "AbortError"
        )
          return;
        const box = el("div");
        notice(box, errorMessage(error));
        view.body.replaceChildren(box, button("Thử lại", reload));
      } finally {
        view.body.setAttribute("aria-busy", "false");
      }
    }
    await reload();
  }
  window.WarehousePage = Object.freeze({
    mount,
    destroy,
    reset,
    preferredWarehouse(user) {
      return remembered.account === String(user.accountId || user.username)
        ? remembered.warehouseId
        : null;
    },
    rememberWarehouse(user, warehouseId) {
      remembered = {
        account: String(user.accountId || user.username),
        warehouseId:
          Number.isSafeInteger(warehouseId) && warehouseId > 0
            ? warehouseId
            : null,
      };
    },
  });
})();
