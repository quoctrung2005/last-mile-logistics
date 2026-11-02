"use strict";

(function () {
  const menus = [
    { id: "overview", path: "/dashboard", label: "Tổng quan", icon: "bi-grid" },
    { id: "orders", path: "/orders", label: "Đơn hàng", icon: "bi-box-seam", permissions: ["DONHANG_XEM"] },
    { id: "warehouse", label: "Kho", icon: "bi-boxes", children: [
      { id: "inventory", path: "/warehouse/inventory", label: "Tồn kho", icon: "bi-clipboard-data" },
      { id: "inbound-outbound", path: "/warehouse/inbound", label: "Nhập kho", icon: "bi-box-arrow-in-down" },
      { id: "warehouse-outbound", path: "/warehouse/outbound", label: "Xuất kho", icon: "bi-box-arrow-up" },
      { id: "warehouse-return", path: "/warehouse/returns", label: "Nhập hàng hoàn", icon: "bi-arrow-return-left" },
      { id: "warehouse-locations", path: "/warehouse/locations", label: "Vị trí lưu kho", icon: "bi-geo" },
      { id: "warehouse-transactions", path: "/warehouse/transactions", label: "Lịch sử giao dịch", icon: "bi-clock-history" }
    ] },
    { id: "dispatch", label: "Điều phối", icon: "bi-signpost-split", children: [
      { id: "dispatch-queue", path: "/dispatch/orders", label: "Hàng chờ điều phối", icon: "bi-hourglass-split", permissions: ["DIEUPHOI_GOMDON"] },
      { id: "assignments", path: "/dispatch/assignments", label: "Phân công", icon: "bi-person-check", permissions: ["DIEUPHOI_GIAMSAT"] },
      { id: "delivery-trips", path: "/dispatch/trips", label: "Chuyến giao", icon: "bi-truck", permissions: ["DIEUPHOI_GIAMSAT"] },
      { id: "incident-chat", path: "/dispatch/incidents", label: "Sự cố & Chat hỗ trợ", icon: "bi-chat-dots-fill", permissions: ["DIEUPHOI_GIAMSAT"] },
      { id: "route-optimization", path: "/dispatch/optimization", label: "Tối ưu tuyến", icon: "bi-map", permissions: ["DIEUPHOI_GOMDON", "DIEUPHOI_TOIUUTUYEN"] }
    ] },
    { id: "tracking", path: "/tracking", label: "Theo dõi giao hàng", icon: "bi-geo-alt", permissions: ["DONHANG_XEM", "DIEUPHOI_GIAMSAT"] },
    { id: "cod", label: "COD và đối soát", icon: "bi-cash-coin", children: [
      { id: "cod-collections", path: "/cod/collections", label: "Thu hộ COD", icon: "bi-wallet2", permissions: ["COD_DOISOAT"] },
      { id: "cod-reconciliation", path: "/cod/reconciliation", label: "Đối soát COD", icon: "bi-journal-check" }
    ] },
    { id: "customers", path: "/customers", label: "Khách hàng", icon: "bi-people", permissions: ["DONHANG_XEM"] },
    { id: "fleet", label: "Nhân viên & phương tiện", icon: "bi-person-badge", children: [
      { id: "couriers", path: "/fleet/couriers", label: "Nhân viên giao hàng", icon: "bi-person-walking", permissions: ["TAIKHOAN_XEM"] },
      { id: "driver-registrations", path: "/fleet/registrations", label: "Hồ sơ đăng ký tài xế", icon: "bi-person-vcard", permissions: ["TAIKHOAN_XEM"] },
      { id: "driver-earnings", path: "/fleet/driver-earnings", label: "Thù lao tài xế", icon: "bi-cash-stack", permissions: ["TAIKHOAN_XEM"] },
      { id: "vehicles", path: "/fleet/vehicles", label: "Phương tiện", icon: "bi-truck-front", permissions: ["DIEUPHOI_GIAMSAT"] }
    ] },
    { id: "reports", path: "/reports", label: "Báo cáo", icon: "bi-bar-chart", permissions: ["BAOCAO_XEM"] },
    { id: "admin", label: "Quản trị", icon: "bi-sliders", children: [
      { id: "accounts", path: "/admin/accounts", label: "Tài khoản", icon: "bi-person-gear", permissions: ["TAIKHOAN_XEM"] },
      { id: "roles", path: "/admin/roles", label: "Vai trò & quyền", icon: "bi-shield-lock", permissions: ["PHANQUYEN_QUANLY"] },
      { id: "catalogs", path: "/admin/catalogs", label: "Danh mục", icon: "bi-list-ul", permissions: ["BUUCUC_QUANLY"] },
      { id: "pricing", path: "/admin/pricing", label: "Bảng giá", icon: "bi-tag", permissions: ["BANGGIA_QUANLY"] },
      { id: "audit-logs", path: "/admin/audit-logs", label: "Nhật ký hệ thống", icon: "bi-clock-history", permissions: ["NHATKY_XEM"] }
    ] }
  ];
  // Keep the existing shell's role policy for menus that are still placeholders.
  // Implemented Orders/Warehouse screens also require live DB permissions below.
  const roleMenus = {
    ADMIN: menus.map(menu => menu.id),
    BRANCH_MANAGER: ["overview", "orders", "warehouse", "tracking", "cod", "customers", "fleet", "reports"],
    DISPATCHER: ["overview", "orders", "warehouse", "dispatch", "tracking", "customers"],
    WAREHOUSE_STAFF: ["overview", "orders", "warehouse"],
    ACCOUNTANT: ["overview", "orders", "cod", "fleet", "reports"]
  };
  const orderStatuses = new Set(["NEW", "CONFIRMED", "WAITING_INBOUND", "IN_WAREHOUSE", "WAITING_ASSIGNMENT", "ASSIGNED", "HANDED_OVER", "EN_ROUTE_PICKUP", "PICKED_UP", "IN_DELIVERY", "DELIVERED", "FAILED", "RETRY_WAITING", "RETURNING", "RETURNED", "COMPLETED", "CANCELLED"]);
  const codQuery = ["from", "to", "branchId", "shipperId", "tab", "status", "keyword", "page", "pageSize"];
  const orderQuery = ["page", "pageSize", "keyword", "status", "branchId", "operationalGroup"];
  const customerQuery = ["page", "pageSize", "keyword", "type", "status"];
  const shipperQuery = ["page", "pageSize", "keyword", "branchId", "isActive", "availability"];
  const vehicleQuery = ["page", "pageSize", "keyword", "vehicleType", "branchId", "status"];
  const accountQuery = ["page", "pageSize", "keyword", "roleId", "branchId", "status"];
  const roleQuery = ["keyword", "isActive"];
  const catalogQuery = ["type", "keyword", "isActive", "branchId", "warehouseId", "status"];
  const pricingQuery = ["page", "pageSize", "serviceId", "areaId", "globalOnly", "isActive"];
  const earningsQuery = ["page", "pageSize", "shipperId", "type", "status", "from", "to"];
  const auditQuery = ["page", "pageSize", "from", "to", "accountId", "action", "objectType", "objectId", "keyword"];
  const dispatchQuery = ["keyword", "branchId", "warehouseId", "areaId", "priority", "deadlineDate", "shipperId", "status", "fromDate", "toDate", "page", "pageSize", "tripId", "planId", "step"];
  const routes = [{ name: "login", path: "/login", pageId: "login", label: "Đăng nhập", public: true, queryKeys: [] }];
  for (const menu of menus) {
    for (const page of menu.children || [menu]) {
      routes.push({ ...page, name: page.id, pageId: page.id, group: menu.children ? menu.id : null,
        menuId: menu.id, permissions: menu.id === "warehouse" ? (page.id === "inbound-outbound" ? ["KHO_XEM", "DONHANG_XEM"] : ["KHO_XEM"]) : page.permissions || [],
        queryKeys: page.id === "driver-earnings" ? earningsQuery : page.id === "driver-registrations" ? ["page","pageSize","status","keyword"] : page.id === "overview" ? ["branchId"] : menu.id === "dispatch" ? dispatchQuery : page.id === "tracking" ? ["keyword", "branchId", "shipperId", "status", "statusGroup", "fromDate", "toDate", "page", "pageSize", "orderId", "view", "auto"] : menu.id === "cod" ? codQuery : page.id === "reports" ? ["from", "to", "branchId", "tab", "page", "pageSize"] : page.id === "audit-logs" ? auditQuery : page.id === "pricing" ? pricingQuery : page.id === "catalogs" ? catalogQuery : page.id === "roles" ? roleQuery : page.id === "accounts" ? accountQuery : page.id === "vehicles" ? vehicleQuery : page.id === "couriers" ? shipperQuery : menu.id === "customers" ? customerQuery : menu.id === "orders" ? orderQuery : menu.id === "warehouse" ? ({
          inventory: ["warehouseId", "locationId", "page", "pageSize", "keyword", "status"],
          "inbound-outbound": ["warehouseId", "locationId", "page", "pageSize", "keyword", "status"],
          "warehouse-outbound": ["warehouseId", "locationId", "page", "pageSize", "keyword", "assignmentStatus", "acceptedOnly"],
          "warehouse-return": ["warehouseId", "page", "pageSize", "keyword"],
          "warehouse-locations": ["warehouseId", "locationId", "keyword", "status"],
          "warehouse-transactions": ["warehouseId", "page", "pageSize", "orderId", "type", "keyword", "fromDate", "toDate"]
        }[page.id]) : [] });
    }
  }
  routes.push(
    { name: "cod-collection-detail", path: "/cod/collections/:id", pageId: "cod-collections", mode: "collection", label: "Thu hộ COD", menuId: "cod", group: "cod", permissions: ["COD_DOISOAT"], queryKeys: codQuery },
    { name: "cod-deposit-detail", path: "/cod/deposits/:id", pageId: "cod-collections", mode: "deposit", label: "Thu hộ COD", menuId: "cod", group: "cod", permissions: ["COD_DOISOAT"], queryKeys: codQuery },
    { name: "cod-reconciliation-detail", path: "/cod/reconciliation/:id", pageId: "cod-reconciliation", mode: "detail", label: "Đối soát COD", menuId: "cod", group: "cod", permissions: ["COD_DOISOAT"], queryKeys: codQuery },
    { name: "audit-detail", path: "/admin/audit-logs/:id", pageId: "audit-logs", mode: "detail", label: "Nhật ký hệ thống", menuId: "admin", group: "admin", permissions: ["NHATKY_XEM"], queryKeys: auditQuery },
    { name: "role-detail", path: "/admin/roles/:id", pageId: "roles", mode: "detail", label: "Vai trò & quyền", menuId: "admin", group: "admin", permissions: ["PHANQUYEN_QUANLY"], queryKeys: roleQuery },
    { name: "account-detail", path: "/admin/accounts/:id", pageId: "accounts", mode: "detail", label: "Chi tiết tài khoản", menuId: "admin", group: "admin", permissions: ["TAIKHOAN_XEM"], queryKeys: accountQuery },
    { name: "vehicle-detail", path: "/fleet/vehicles/:id", pageId: "vehicles", mode: "detail", label: "Chi tiết phương tiện", menuId: "fleet", group: "fleet", permissions: ["DIEUPHOI_GIAMSAT"], queryKeys: vehicleQuery },
    { name: "shipper-detail", path: "/fleet/couriers/:id", pageId: "couriers", mode: "detail", label: "Chi tiết nhân viên giao hàng", menuId: "fleet", group: "fleet", permissions: ["TAIKHOAN_XEM"], queryKeys: shipperQuery },
    { name: "customer-detail", path: "/customers/:id", pageId: "customers", mode: "detail", label: "Chi tiết khách hàng", menuId: "customers", permissions: ["DONHANG_XEM"], queryKeys: customerQuery },
    { name: "order-create", path: "/orders/create", pageId: "orders", mode: "create", label: "Tạo đơn hàng", menuId: "orders", permissions: ["DONHANG_TAO"], queryKeys: orderQuery },
    { name: "order-detail", path: "/orders/:id", pageId: "orders", mode: "detail", label: "Chi tiết đơn hàng", menuId: "orders", permissions: ["DONHANG_XEM"], queryKeys: [...orderQuery, "returnTo"] },
    { name: "order-edit", path: "/orders/:id/edit", pageId: "orders", mode: "edit", label: "Sửa đơn hàng", menuId: "orders", permissions: ["DONHANG_XEM", "DONHANG_CAPNHAT"], queryKeys: [...orderQuery, "returnTo"] },
    { name: "transaction-detail", path: "/warehouse/transactions/:id", pageId: "warehouse-transactions", mode: "detail", label: "Chi tiết giao dịch kho", menuId: "warehouse", group: "warehouse", permissions: ["KHO_XEM"], queryKeys: ["warehouseId", "page", "pageSize", "orderId", "type", "keyword", "fromDate", "toDate"] }
  );
  for (const route of routes) route.pattern = new RegExp("^" + route.path.replace(":id", "([1-9]\\d*)") + "$");

  const RETURN_KEY = "tvd.returnRoute";
  let hooks = null, current = null, lastHash = null, generation = 0, controller = null, leaveGuard = null;
  const HISTORY_POSITION = "tvd.router.position";
  let historyPosition = 0, restoringHash = null, guardOwner = null;
  function entryPosition() {
    const value = window.history.state?.[HISTORY_POSITION];
    return Number.isSafeInteger(value) ? value : null;
  }
  function stampHistory(position, hash = window.location.hash) {
    window.history.replaceState({ ...window.history.state, [HISTORY_POSITION]: position }, "", hash);
  }
  function setLeaveGuard(guard) {
    const owner = guardOwner = {};
    leaveGuard = guard;
    // An old page's async cleanup must not remove a newer page's guard.
    return () => { if (guardOwner === owner) { leaveGuard = null; guardOwner = null; } };
  }

  function internalHash(value) {
    if (typeof value !== "string" || value.length > 2000) return null;
    const hash = value.startsWith("#") ? value : "#" + value;
    if (!hash.startsWith("#/") || hash.startsWith("#//") || /[\\\u0000-\u001f#]/.test(hash.slice(1))) return null;
    try {
      const decoded = decodeURIComponent(hash.slice(1));
      if (decoded.startsWith("//") || /[\\\u0000-\u001f]/.test(decoded)) return null;
    } catch (_) { return null; }
    return hash;
  }
  function positive(value, max = Number.MAX_SAFE_INTEGER) {
    return /^[1-9]\d*$/.test(value) && Number.isSafeInteger(Number(value)) && Number(value) <= max;
  }
  function parse(hash) {
    const safe = internalHash(hash);
    if (!safe) return { name: "not-found", pageId: "not-found", label: "Không tìm thấy", hash, params: {}, query: {} };
    const [rawPath, ...search] = safe.slice(1).split("?");
    const pathname = rawPath.length > 1 ? rawPath.replace(/\/$/, "") : rawPath;
    const route = routes.find(item => item.pattern.test(pathname));
    if (!route) return { name: "not-found", pageId: "not-found", label: "Không tìm thấy", hash: safe, params: {}, query: {} };
    const match = pathname.match(route.pattern), params = {};
    if (route.path.includes(":id")) {
      if (!positive(match[1])) return { name: "not-found", pageId: "not-found", label: "Không tìm thấy", hash: safe, params: {}, query: {} };
      params.id = Number(match[1]);
    }
    const query = {}, seen = new Set(), searchParams = new URLSearchParams(search.join("?"));
    let error = null;
    for (const [key, value] of searchParams) {
      if (!route.queryKeys.includes(key) || seen.has(key)) { error = "Tham số URL không được hỗ trợ hoặc bị lặp: " + key; break; }
      seen.add(key);
      if (!value) continue;
      if (["page", "pageSize", "warehouseId", "locationId", "orderId", "branchId", "shipperId", "roleId", "serviceId", "areaId", "accountId", "tripId"].includes(key)) {
        const max = key === "page" ? 100000 : key === "pageSize" ? 100 : ["warehouseId", "branchId", "roleId", "serviceId", "areaId"].includes(key) ? 2147483647 : Number.MAX_SAFE_INTEGER;
        if (!positive(value, max)) { error = "Tham số " + key + " không hợp lệ."; break; }
        query[key] = Number(value);
      } else if (key === "planId") {
        if (!/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i.test(value)) { error = "Mã phương án không hợp lệ."; break; }
        query[key] = value;
      } else if (key === "step") {
        if (!["1", "2", "3"].includes(value)) { error = "Bước lập phương án không hợp lệ."; break; }
        query[key] = Number(value);
      } else if (key === "priority") {
        if (!/^[1-5]$/.test(value)) { error = "Mức ưu tiên không hợp lệ."; break; }
        query[key] = Number(value);
      } else if (key === "operationalGroup") {
        if (!["waitingInbound", "inWarehouse", "waitingAssignment", "waitingHandover", "inDelivery", "failedNeedsAction", "overdue"].includes(value)) { error = "Nhóm công việc tổng quan không hợp lệ."; break; }
        query[key] = value;
      } else if (key === "statusGroup") {
        if (!["PROGRESS", "ATTENTION", "DONE", "ALL"].includes(value)) { error = "Nhóm trạng thái không hợp lệ."; break; }
        query[key] = value;
      } else if (key === "view") {
        if (!["map", "history"].includes(value)) { error = "Tab theo dõi không hợp lệ."; break; }
        query[key] = value;
      } else if (key === "auto") {
        if (!["true", "false"].includes(value)) { error = "Tự cập nhật không hợp lệ."; break; }
        query[key] = value;
      } else if (key === "tab") {
        if (!(route.menuId === "cod" ? ["collections", "deposits"] : ["orders", "delivery", "finance"]).includes(value)) { error = "Tab báo cáo không hợp lệ."; break; }
        query[key] = value;
      } else if (key === "returnTo") {
        // Store only an internal list route. Never allow nested return URLs or detail/login targets.
        const safeReturn = internalHash(value);
        if (!safeReturn || new URLSearchParams(safeReturn.split("?").slice(1).join("?")).has("returnTo")) {
          error = "Đường quay lại không hợp lệ."; break;
        }
        const destination = parse(safeReturn);
        if (destination.error || (destination.mode && destination.name !== "customer-detail") || !(destination.name === "overview" || destination.name === "tracking" || destination.name === "orders" || destination.pageId === "customers" || destination.group === "warehouse" || destination.group === "cod" || destination.group === "dispatch")) {
          error = "Đường quay lại phải là Đơn hàng, Khách hàng hoặc Kho."; break;
        }
        query[key] = destination.hash;
      } else if (key === "keyword") {
        if (value.length > (["couriers", "accounts"].includes(route.pageId) ? 150 : 100) || /[\u0000-\u001f]/.test(value)) { error = "Từ khóa trong URL không hợp lệ."; break; }
        query[key] = value.trim();
      } else if (key === "status") {
        if (route.pageId === "driver-registrations") {
          if (!["PENDING","NEEDS_INFO","APPROVED","REJECTED"].includes(value)) { error = "Trạng thái hồ sơ không hợp lệ."; break; }
          query[key] = value; continue;
        }
        if (route.group === "dispatch") {
          const values = route.pageId === "assignments" ? ["PENDING","ACCEPTED","IN_PROGRESS","COMPLETED","ATTEMPT_FAILED","REJECTED","CANCELLED","REASSIGNED"] : ["PLANNED","ASSIGNED","ACCEPTED","IN_PROGRESS","COMPLETED","CANCELLED"];
          if (!values.includes(value)) { error = "Trạng thái điều phối không hợp lệ."; break; }
          query[key] = value; continue;
        }
        if (route.menuId === "cod") {
          const statuses = route.pageId === "cod-reconciliation" ? ["DRAFT","REVIEW","CONFIRMED","DIFFERENCE","LOCKED","CANCELLED"] : ["COLLECTED","PARTIAL","PENDING","CONFIRMED","REJECTED","CANCELLED"];
          if (!statuses.includes(value)) { error = "Trạng thái COD không hợp lệ."; break; }
          query[key] = value; continue;
        }
        if (route.pageId === "accounts") {
          if (!["ACTIVE", "LOCKED", "INACTIVE"].includes(value)) { error = "Trạng thái tài khoản không hợp lệ."; break; }
          query[key] = value; continue;
        }
        if (route.pageId === "vehicles") {
          if (!["AVAILABLE", "IN_USE", "MAINTENANCE", "INACTIVE"].includes(value)) { error = "Trạng thái phương tiện không hợp lệ."; break; }
          query[key] = value; continue;
        }
        if (route.name === "warehouse-locations" || route.pageId === "customers" || route.pageId === "catalogs") {
          if (!["ACTIVE", "INACTIVE", "ALL"].includes(value)) { error = "Trạng thái vị trí không hợp lệ."; break; }
          query[key] = value; continue;
        }
        if (!orderStatuses.has(value) || (route.name === "inbound-outbound" && !["CONFIRMED", "WAITING_INBOUND"].includes(value))) { error = "Trạng thái trong URL không hợp lệ."; break; }
        query[key] = value;
      } else if (["fromDate", "toDate", "from", "to", "deadlineDate"].includes(key)) {
        const parsed = /^\d{4}-\d{2}-\d{2}$/.test(value) && new Date(value + "T00:00:00Z");
        if (!parsed || Number.isNaN(parsed.getTime()) || parsed.toISOString().slice(0, 10) !== value || value.startsWith("0000")) { error = "Ngày trong URL không hợp lệ."; break; }
        query[key] = value;
      } else if (key === "type") {
        if (route.pageId === "catalogs") {
          if (!["AREAS", "SERVICES", "BRANCHES", "WAREHOUSES", "LOCATIONS"].includes(value)) { error = "Loại danh mục không hợp lệ."; break; }
          query[key] = value; continue;
        }
        if (route.pageId === "customers") {
          if (!["INDIVIDUAL", "BUSINESS"].includes(value)) { error = "Loại khách hàng không hợp lệ."; break; }
          query[key] = value; continue;
        }
        if (!["INBOUND", "MOVE", "OUTBOUND", "RETURN_IN"].includes(value)) { error = "Loại giao dịch trong URL không hợp lệ."; break; }
        query[key] = value;
      } else if (key === "assignmentStatus") {
        if (!["PENDING", "ACCEPTED"].includes(value)) { error = "Trạng thái phân công không hợp lệ."; break; }
        query[key] = value;
      } else if (key === "acceptedOnly") {
        if (!["true", "false"].includes(value)) { error = "Bộ lọc phân công không hợp lệ."; break; }
        query[key] = value;
      } else if (key === "isActive" || key === "globalOnly") {
        if (!["true", "false"].includes(value)) { error = "Trạng thái nhân viên không hợp lệ."; break; }
        query[key] = value;
      } else if (key === "availability") {
        if (!["AVAILABLE", "DELIVERING", "BREAK", "OFFLINE"].includes(value)) { error = "Trạng thái làm việc không hợp lệ."; break; }
        query[key] = value;
      } else if (key === "vehicleType") {
        if (value.length > 30 || /[\u0000-\u001f]/.test(value)) { error = "Loại phương tiện không hợp lệ."; break; }
        query[key] = value.trim();
      } else if (["action", "objectType", "objectId"].includes(key)) {
        if (value.length > (key === "action" ? 50 : 100) || /[\u0000-\u001f]/.test(value)) { error = "Bộ lọc nhật ký không hợp lệ."; break; }
        query[key] = value.trim();
      }
    }
    if (!error && query.fromDate && query.toDate && query.fromDate > query.toDate) error = "Từ ngày không được sau đến ngày.";
    if (!error && query.from && query.to && query.from > query.to) error = "Từ ngày không được sau đến ngày.";
    return { ...route, hash: safe, params, query, error };
  }
  function href(name, params = {}, query = {}) {
    const route = routes.find(item => item.name === name);
    if (!route) throw new Error("Route không tồn tại: " + name);
    let pathname = route.path;
    if (pathname.includes(":id")) {
      if (!positive(String(params.id))) throw new Error("ID route không hợp lệ.");
      pathname = pathname.replace(":id", String(params.id));
    }
    const search = new URLSearchParams();
    for (const key of route.queryKeys) if (query[key] != null && query[key] !== "") search.set(key, String(query[key]));
    const hash = "#" + pathname + (search.size ? "?" + search : "");
    if (parse(hash).error) throw new Error(parse(hash).error);
    return hash;
  }
  function visibleMenus(user, permissions) {
    if (user && permissions?.known) return menus.map(menu => {
      if (!menu.children) return allowed(routes.find(r => r.name === menu.id), user, permissions) ? menu : null;
      const children = menu.children.filter(page => allowed(routes.find(r => r.name === page.id), user, permissions));
      return children.length ? {...menu, children} : null;
    }).filter(Boolean);
    const result = menus.filter(menu => (roleMenus[user?.role] || []).includes(menu.id)).map(menu => menu.children
      ? {...menu,children:menu.children.filter(page=>page.id!=="driver-registrations"||user?.role==="ADMIN")} : menu);
    // Account access uses live DB permissions and the backend branch scope.
    if (user && !result.some(menu => menu.id === "admin")) result.push({ ...menus.find(menu => menu.id === "admin"), children: [menus.find(menu => menu.id === "admin").children[0]] });
    return result;
  }
  function roleAccess(route, user) {
    if (route.pageId === "driver-registrations") return user?.role === "ADMIN";
    if (route.pageId === "accounts" || route.pageId === "overview") return true;
    if (route.menuId === "admin") return user?.role === "ADMIN";
    // Implemented screens use the same live permission codes as their APIs.
    // Keep role-only policy for the remaining placeholder screens.
    return route.permissions.length > 0 || (roleMenus[user?.role] || []).includes(route.menuId);
  }
  function allowed(route, user, permissions) {
    if (route.public) return true;
    if (!roleAccess(route,user)) return false;
    return (route.permissions || []).every(code => permissions?.known && permissions.codes.has(code));
  }
  function remember(hash) {
    const route = parse(hash);
    if (route.name !== "not-found" && !route.public && !route.error) sessionStorage.setItem(RETURN_KEY, route.hash);
  }
  function navigate(target, options = {}) {
    const safe = internalHash(target);
    if (!safe) throw new Error("Chỉ được điều hướng tới route nội bộ.");
    if (window.location.hash === safe) { if (options.force) transition(true); return; }
    if (options.replace) {
      stampHistory(historyPosition, safe);
      transition();
    } else window.location.hash = safe; // Only hashchange renders; never render a second time here.
  }
  // Filter changes update this history entry without remounting/fetching or stealing input focus.
  // Back from a child page will restore these validated filters through the normal router.
  function updateQuery(query, expected = current) {
    if (!current || !expected || current.name !== expected.name || current.params.id !== expected.params.id) return;
    const hash = href(current.name, current.params, query);
    stampHistory(historyPosition, hash);
    current = parse(hash); lastHash = hash;
  }
  async function transition(force = false) {
    if (!hooks) return;
    const hash = window.location.hash;
    if (restoringHash) {
      if (hash === restoringHash) restoringHash = null;
      return;
    }
    if (!force && hash === lastHash) return;
    if (leaveGuard && !leaveGuard()) {
      const targetPosition = entryPosition();
      if (current && hash !== current.hash && targetPosition !== historyPosition && window.history.go) {
        restoringHash = current.hash;
        window.history.go(targetPosition === null ? -1 : historyPosition - targetPosition);
      } else if (current) stampHistory(historyPosition, current.hash);
      return;
    }
    historyPosition = entryPosition() ?? historyPosition + 1;
    stampHistory(historyPosition, hash);
    lastHash = hash;
    const epoch = ++generation;
    controller?.abort(); controller = new AbortController();
    const signal = controller.signal;
    hooks.onLeave();
    if (!hash || hash === "#") { navigate(href(hooks.getUser() ? "overview" : "login"), { replace: true }); return; }
    const route = parse(hash); current = route;
    if (route.name === "not-found") { hooks.onError(route, "Không tìm thấy", "Trang bạn yêu cầu không tồn tại."); return; }
    const user = hooks.getUser();
    if (!route.public && !user) { remember(route.hash); navigate(href("login"), { replace: true }); return; }
    if (route.name === "login" && user) { navigate(href("overview"), { replace: true }); return; }
    if (route.error) { hooks.onError(route, "URL không hợp lệ", route.error); return; }
    if (route.public) { hooks.onRoute(route, { signal, user }); return; }
    if (!roleAccess(route,user)) { hooks.onError(route, "Không có quyền", "Bạn không có quyền mở màn hình này."); return; }
    hooks.onLoading(route);
    let permissions = { known: false, codes: new Set() };
    try {
      permissions = await window.Auth.getPermissions(user, signal);
      if (epoch !== generation || signal.aborted) return;
      if (!allowed(route, user, permissions)) { hooks.onError(route, "Không có quyền", "Bạn không có quyền mở màn hình này."); return; }
      hooks.onRoute(route, { signal, user, permissions });
    } catch (error) {
      if (epoch !== generation || signal.aborted || error.name === "AbortError" || error.sessionExpired) return;
      hooks.onError(route, error.status === 403 ? "Không có quyền" : "Chưa thể mở trang", error.message, true);
    }
  }
  function completeLogin() {
    const saved = sessionStorage.getItem(RETURN_KEY); sessionStorage.removeItem(RETURN_KEY);
    const route = parse(saved);
    navigate(route.name !== "not-found" && !route.public && !route.error ? route.hash : href("overview"), { replace: true, force: true });
  }
  function goLogin(preserve = false) {
    setLeaveGuard(null); // Confirmed session expiry/logout must still reach Login.
    restoringHash = null;
    if (preserve) remember(window.location.hash);
    else sessionStorage.removeItem(RETURN_KEY);
    navigate(href("login"), { replace: true, force: true });
  }
  function start(settings) {
    if (hooks) throw new Error("Router đã được khởi tạo.");
    hooks = settings;
    historyPosition = entryPosition() ?? 0; stampHistory(historyPosition);
    window.addEventListener("hashchange", transitionEvent); transition();
  }
  function transitionEvent() { transition(); }
  function stop() {
    window.removeEventListener("hashchange", transitionEvent); controller?.abort(); generation++;
    hooks?.onLeave(); hooks = null; current = null; lastHash = null; restoringHash = null; setLeaveGuard(null);
  }
  window.Router = Object.freeze({ routes: Object.freeze(routes), visibleMenus, parse, href, allowed,
    navigate, updateQuery, current: () => current, start, stop, completeLogin, goLogin, canLeave: () => !leaveGuard || leaveGuard(), setLeaveGuard, reload: () => transition(true) });
}());
