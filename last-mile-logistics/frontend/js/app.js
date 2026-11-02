"use strict";
(function () {
  const Router = window.Router, UI = window.LogisticsUI;
  const loginPage = document.getElementById("login-page"), appShell = document.getElementById("app-shell");
  const loginForm = document.getElementById("login-form"), loginAlert = document.getElementById("login-alert"), loginSubmit = document.getElementById("login-submit");
  const usernameInput = document.getElementById("username"), passwordInput = document.getElementById("password"), rememberInput = document.getElementById("remember-username");
  const navigation = document.getElementById("main-navigation"), pageContent = document.getElementById("page-content");
  const roleLabels = { ADMIN: "Quản trị viên", BRANCH_MANAGER: "Quản lý bưu cục", DISPATCHER: "Điều phối viên", WAREHOUSE_STAFF: "Nhân viên kho", ACCOUNTANT: "Kế toán / Đối soát" };
  let currentUser = null, loginMessage = "", restoreWarning = "", started = false, authGeneration = 0;
  const sidebar = document.getElementById("sidebar"), workspace = document.querySelector(".workspace"), mobileMenu = document.getElementById("mobile-menu");
  const compactLayout = window.matchMedia("(max-width: 991.98px)");
  function icon(name) { const node = UI.el("i", "bi " + name); node.setAttribute("aria-hidden", "true"); return node; }
  function appendLink(container, page, nested) {
    const link = UI.el("a", "navigation-link" + (nested ? " navigation-child-link" : ""));
    link.href = Router.href(page.id); link.dataset.page = page.id;
    link.append(icon(page.icon), UI.el("span", "", page.label)); container.append(link);
  }
  function buildNavigation(permissions) {
    navigation.replaceChildren();
    for (const menu of Router.visibleMenus(currentUser, permissions)) {
      if (!menu.children) { appendLink(navigation, menu, false); continue; }
      const group = UI.el("div", "navigation-group");
      const toggle = UI.button("", null, "navigation-toggle"); toggle.dataset.group = menu.id;
      toggle.setAttribute("aria-expanded", "false"); toggle.setAttribute("aria-controls", "navigation-" + menu.id);
      const chevron = icon("bi-chevron-right"); chevron.classList.add("chevron");
      toggle.replaceChildren(icon(menu.icon), UI.el("span", "", menu.label), chevron);
      const children = UI.el("div", "navigation-children d-none"); children.id = "navigation-" + menu.id;
      for (const child of menu.children) appendLink(children, child, true);
      group.append(toggle, children); navigation.append(group);
    }
  }
  function updateNavigation(route) {
    for (const link of navigation.querySelectorAll(".navigation-link")) {
      const active = link.dataset.page === route.pageId; link.classList.toggle("is-active", active);
      if (active) link.setAttribute("aria-current", "page"); else link.removeAttribute("aria-current");
    }
    for (const toggle of navigation.querySelectorAll(".navigation-toggle")) {
      const open = toggle.dataset.group === route.group; toggle.setAttribute("aria-expanded", String(open));
      document.getElementById("navigation-" + toggle.dataset.group).classList.toggle("d-none", !open);
    }
  }
  function setupUser(user) {
    currentUser = user;
    const name = user.fullName || user.username || "Tài khoản";
    document.getElementById("profile-name").textContent = name;
    document.getElementById("profile-role").textContent = roleLabels[user.role] || "Nhân viên";
    document.getElementById("sidebar-account-name").textContent = name;
    document.getElementById("sidebar-account-role").textContent = roleLabels[user.role] || "Nhân viên";
    document.getElementById("profile-avatar").textContent = name.trim().slice(0, 2).toLocaleUpperCase("vi");
    document.getElementById("sidebar-account-avatar").textContent = name.trim().split(/\s+/).slice(-2).map(part => Array.from(part)[0] || "").join("").toLocaleUpperCase("vi");
    const branch = user.branchId ? "Bưu cục #" + user.branchId : "Toàn hệ thống";
    document.getElementById("branch-label").textContent = branch; document.getElementById("header-branch").textContent = branch;
    buildNavigation();
  }
  function forgetUser() {
    authGeneration++; currentUser = null; restoreWarning = ""; navigation.replaceChildren(); window.WarehousePage.reset();
    document.getElementById("profile-name").textContent = "Chưa đăng nhập";
    document.getElementById("profile-role").textContent = ""; document.getElementById("profile-avatar").textContent = "";
    document.getElementById("branch-label").textContent = ""; document.getElementById("header-branch").textContent = "";
    document.getElementById("sidebar-account-name").textContent = "Chưa đăng nhập";
    document.getElementById("sidebar-account-role").textContent = "";
    document.getElementById("sidebar-account-avatar").textContent = "";
  }
  function closeSidebar() {
    const restoreFocus = sidebar.contains(document.activeElement) && compactLayout.matches;
    workspace.inert = false;
    if (restoreFocus) mobileMenu.focus();
    sidebar.classList.remove("is-open"); document.getElementById("sidebar-backdrop").classList.remove("is-visible");
    mobileMenu.setAttribute("aria-expanded", "false");
    sidebar.inert = compactLayout.matches; sidebar.setAttribute("aria-hidden", String(compactLayout.matches));
    document.body.classList.remove("sidebar-open");
  }
  compactLayout.addEventListener("change", closeSidebar);
  closeSidebar();
  document.addEventListener("keydown", event => {
    if (!sidebar.classList.contains("is-open")) return;
    if (event.key === "Escape") { event.preventDefault(); closeSidebar(); }
    if (event.key === "Tab") {
      const controls = [...sidebar.querySelectorAll("a[href], button:not(:disabled)")].filter(node => node.getClientRects().length);
      const first = controls[0], last = controls.at(-1);
      if (event.shiftKey && document.activeElement === first) { event.preventDefault(); last?.focus(); }
      else if (!event.shiftKey && document.activeElement === last) { event.preventDefault(); first?.focus(); }
    }
  });
  function leavePage() { window.IncidentChatPage?.destroy(); window.DriverEarningsPage?.destroy(); window.RegistrationsPage?.destroy(); window.DashboardPage.destroy(); window.DispatchPage.destroy(); window.TrackingPage.destroy(); window.CodPage.destroy(); window.ReportsPage.destroy(); window.AuditPage.destroy(); window.PricingPage.destroy(); window.CatalogsPage.destroy(); window.RolesPage.destroy(); window.AccountsPage.destroy(); window.VehiclesPage.destroy(); window.ShippersPage.destroy(); window.CustomersPage.destroy(); window.OrdersPage.destroy(); window.WarehousePage.destroy(); window.InboundPage.destroy(); closeSidebar(); window.scrollTo({ top: 0, behavior: "instant" }); }
  function showLogin() {
    pageContent.replaceChildren(); appShell.classList.add("d-none"); loginPage.classList.remove("d-none");
    loginAlert.textContent = loginMessage; loginAlert.classList.toggle("d-none", !loginMessage);
  }
  function showShell(route) {
    loginPage.classList.add("d-none"); appShell.classList.remove("d-none");
    appShell.classList.toggle("tracking-workspace", route.pageId === "tracking");
    appShell.classList.toggle("dispatch-workspace", route.group === "dispatch");
    appShell.classList.toggle("dashboard-workspace", route.pageId === "overview");
    appShell.classList.toggle("reports-workspace", route.pageId === "reports");
    appShell.classList.toggle("cod-workspace", route.group === "cod");
    document.querySelector(".content-area").classList.toggle("inventory-workspace", route.pageId === "inventory");
    document.querySelector(".content-area").classList.toggle("inbound-workspace", route.pageId === "inbound-outbound");
    document.querySelector(".content-area").classList.toggle("outbound-workspace", route.pageId === "warehouse-outbound");
    document.querySelector(".content-area").classList.toggle("return-workspace", route.pageId === "warehouse-return");
    document.querySelector(".content-area").classList.toggle("locations-workspace", route.pageId === "warehouse-locations");
    document.querySelector(".content-area").classList.toggle("transactions-workspace", route.pageId === "warehouse-transactions");
    document.querySelector(".content-area").classList.toggle("order-detail-workspace", route.name === "order-detail");
    document.getElementById("page-title").textContent = route.pageId === "warehouse-transactions" ? "Lịch sử giao dịch kho" : route.label;
    const parent = Router.visibleMenus(currentUser).find(menu => menu.id === route.group);
    document.getElementById("page-breadcrumb").textContent = "TVĐ LOGISTICS / " + (parent?.label || "QUẢN LÝ").toLocaleUpperCase("vi");
    document.getElementById("page-description").textContent = route.pageId === "inbound-outbound" ? "Tiếp nhận hàng vào kho và ghi nhận vị trí lưu"
      : route.pageId === "warehouse-outbound" ? "Thủ kho quét súng barcode đối chiếu và bấm xác nhận xuất kho bàn giao cho tài xế"
      : route.pageId === "warehouse-return" ? "Tiếp nhận hàng hoàn từ shipper và đưa vào vị trí lưu kho."
      : route.pageId === "warehouse-locations" ? "Quản lý khu lưu, kệ và ô chứa hàng trong từng kho."
      : route.pageId === "warehouse-transactions" ? "Tra cứu các lần nhập kho, chuyển vị trí, xuất kho và nhận hàng hoàn."
      : route.group === "dispatch" ? ({"dispatch-queue":"Chọn đơn đủ điều kiện để lập phương án giao.","assignments":"Theo dõi phân công và điều chỉnh trước khi bàn giao.","delivery-trips":"Quản lý chuyến và thứ tự giao hàng.","incident-chat":"Theo dõi sự cố trên đường và chat hướng dẫn xử lý với tài xế.","route-optimization":"Chọn đơn, xem đề xuất và xác nhận chuyến giao."}[route.pageId])
      : route.pageId === "tracking" ? "Tìm đơn, xem tiến độ và vị trí shipper gần nhất."
      : route.pageId === "reports" ? "Theo dõi kết quả giao hàng và tiền thu hộ"
      : route.pageId === "cod-collections" ? "Theo dõi tiền đã thu và các phiếu nộp."
      : route.pageId === "cod-reconciliation" ? "Đối chiếu tiền thu hộ với tiền shipper đã nộp."
      : route.pageId === "driver-earnings" ? "Quản lý bảng định mức chiết khấu và duyệt thanh toán thù lao tài xế." : route.pageId === "overview" ? "Đơn cần xử lý và kết quả giao hàng trong phạm vi đang xem." : "Khu vực quản lý " + route.label.toLocaleLowerCase("vi") + ".";
    updateNavigation(route);
  }
  function showError(route, title, message, retry = false) {
    showShell(route); document.getElementById("page-title").textContent = title;
    const card = UI.el("section", "orders-card"); card.append(UI.el("h2", "", title), UI.el("p", "text-secondary", message));
    if (retry) card.append(UI.button("Thử lại", Router.reload, "btn btn-outline-orange"));
    const link = UI.el("a", "btn btn-orange ms-2", currentUser ? "Về Tổng quan" : "Đăng nhập");
    link.href = Router.href(currentUser ? "overview" : "login"); card.append(link); pageContent.replaceChildren(card);
  }
  function showLoading(route) { showShell(route); pageContent.replaceChildren(UI.el("p", "orders-empty", "Đang mở trang…")); }
  function renderRoute(route, context) {
    if (route.pageId === "login") { showLogin(); return; }
    if (context.permissions?.known) buildNavigation(context.permissions);
    showShell(route);
    if (route.pageId === "overview") window.DashboardPage.mount(pageContent, currentUser, route, context);
    else if (route.pageId === "incident-chat") window.IncidentChatPage.mount(pageContent, route);
    else if (route.group === "dispatch") window.DispatchPage.mount(pageContent, currentUser, route, context);
    else if (route.pageId === "tracking") window.TrackingPage.mount(pageContent, currentUser, route, context);
    else if (route.group === "cod") window.CodPage.mount(pageContent, currentUser, route, context);
    else if (route.pageId === "reports") window.ReportsPage.mount(pageContent, currentUser, route, context);
    else if (route.pageId === "audit-logs") window.AuditPage.mount(pageContent, currentUser, route, context);
    else if (route.pageId === "pricing") window.PricingPage.mount(pageContent, currentUser, route, context);
    else if (route.pageId === "catalogs") window.CatalogsPage.mount(pageContent, currentUser, route, context);
    else if (route.pageId === "roles") window.RolesPage.mount(pageContent, currentUser, route, context);
    else if (route.pageId === "accounts") window.AccountsPage.mount(pageContent, currentUser, route, context);
    else if (route.pageId === "orders") window.OrdersPage.mount(pageContent, currentUser, route, context);
    else if (route.pageId === "customers") window.CustomersPage.mount(pageContent, currentUser, route, context);
    else if (route.pageId === "couriers") window.ShippersPage.mount(pageContent, currentUser, route, context);
    else if (route.pageId === "driver-registrations") window.RegistrationsPage.mount(pageContent, currentUser, route, context);
    else if (route.pageId === "driver-earnings") window.DriverEarningsPage.mount(pageContent, currentUser, route, context);
    else if (route.pageId === "vehicles") window.VehiclesPage.mount(pageContent, currentUser, route, context);
    else if (route.pageId === "inbound-outbound") window.InboundPage.mount(pageContent, currentUser, route, context);
    else if (route.group === "warehouse") window.WarehousePage.mount(pageContent, currentUser, route.pageId, route, context);
    else {
      const card = UI.el("section", "placeholder-card"), content = UI.el("div", "placeholder-content"), image = UI.el("span", "placeholder-icon");
      image.append(icon(route.icon || "bi-grid"));
      content.append(image, UI.el("h2", "", "Màn hình " + route.label.toLocaleLowerCase("vi") + " chưa được triển khai"),
        UI.el("p", "", "Khu vực này sẽ hiển thị khi chức năng và API tương ứng được triển khai. Chưa có dữ liệu để trình bày."),
        UI.el("span", "status-badge", "Chưa triển khai"));
      card.append(content); pageContent.replaceChildren(card);
    }
    if (restoreWarning) {
      const alert = UI.el("div", "alert alert-warning", restoreWarning); alert.setAttribute("role", "alert");
      alert.append(UI.button("Kiểm tra lại phiên", async () => { await restoreUser(); Router.reload(); }, "btn btn-outline-orange ms-2")); pageContent.prepend(alert);
    }
  }
  function setLoading(value) {
    loginSubmit.disabled = value; loginSubmit.querySelector(".spinner-border").classList.toggle("d-none", !value);
    loginSubmit.querySelector(".button-label").classList.toggle("d-none", value);
  }
  async function acceptUser(user) {
    if (user.role === "SHIPPER") {
      try { await window.Auth.logout(); } catch (_) { /* Local session is cleared by logout. */ }
      forgetUser(); loginMessage = "Tài khoản giao hàng chỉ sử dụng ứng dụng Shipper Mobile. Hãy đăng nhập bằng tài khoản quản lý hoặc điều phối."; return false;
    }
    restoreWarning = ""; setupUser(user); return true;
  }
  loginForm.addEventListener("submit", async event => {
    event.preventDefault(); if (loginSubmit.disabled) return; loginAlert.classList.add("d-none");
    if (!usernameInput.value.trim() || !passwordInput.value) { loginMessage = "Vui lòng nhập tên đăng nhập và mật khẩu."; showLogin(); return; }
    authGeneration++; setLoading(true);
    try {
      const username = usernameInput.value.trim(); const user = await window.Auth.login(username, passwordInput.value);
      window.Auth.rememberUsername(username, rememberInput.checked); passwordInput.value = "";
      if (await acceptUser(user)) { loginMessage = ""; Router.completeLogin(); } else Router.goLogin(false);
    } catch (error) {
      loginMessage = error.status === 401 ? "Tên đăng nhập hoặc mật khẩu không đúng." : error.message || "Không thể đăng nhập. Vui lòng thử lại."; showLogin();
    } finally { setLoading(false); }
  });
  document.getElementById("password-toggle").addEventListener("click", function () {
    const reveal = passwordInput.type === "password"; passwordInput.type = reveal ? "text" : "password";
    this.setAttribute("aria-pressed", String(reveal)); this.setAttribute("aria-label", reveal ? "Ẩn mật khẩu" : "Hiện mật khẩu");
    this.replaceChildren(icon(reveal ? "bi-eye-slash" : "bi-eye"));
  });
  navigation.addEventListener("click", event => {
    const toggle = event.target.closest(".navigation-toggle");
    if (toggle) {
      const children = document.getElementById("navigation-" + toggle.dataset.group), open = toggle.getAttribute("aria-expanded") === "true";
      toggle.setAttribute("aria-expanded", String(!open)); children.classList.toggle("d-none", open);
    } else if (event.target.closest(".navigation-link")) closeSidebar();
    // Links use their real href; hashchange alone renders the destination.
  });
  mobileMenu.addEventListener("click", function () {
    if (!compactLayout.matches || sidebar.classList.contains("is-open")) { closeSidebar(); return; }
    sidebar.inert = false; sidebar.setAttribute("aria-hidden", "false"); sidebar.classList.add("is-open");
    document.getElementById("sidebar-backdrop").classList.add("is-visible"); this.setAttribute("aria-expanded", "true");
    document.body.classList.add("sidebar-open"); sidebar.querySelector("a, button")?.focus(); workspace.inert = true;
  });
  document.getElementById("sidebar-backdrop").addEventListener("click", closeSidebar);
  async function signOut() {
    if (!Router.canLeave()) return;
    forgetUser();
    loginMessage = "Đang đăng xuất…"; setLoading(true); Router.goLogin(false);
    try { await window.Auth.logout(); loginMessage = "Bạn đã đăng xuất."; }
    catch (error) { loginMessage = error.message || "Không thể thu hồi phiên. Token trên trình duyệt đã được xóa."; }
    finally { setLoading(false); if (!currentUser) showLogin(); }
  }
  document.getElementById("sidebar-signout").addEventListener("click", signOut); document.getElementById("header-signout").addEventListener("click", signOut);
  window.addEventListener("auth:expired", () => {
    forgetUser();
    loginMessage = "Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại."; if (started) Router.goLogin(true);
  });
  window.addEventListener("auth:permissions", event => { if(currentUser && event.detail?.known){buildNavigation(event.detail);updateNavigation(Router.current());} });
  usernameInput.value = window.Auth.rememberedUsername(); rememberInput.checked = usernameInput.value.length > 0;
  async function restoreUser() {
    if (!window.ApiClient.getAccessToken() && !window.ApiClient.getRefreshToken()) return;
    const epoch = authGeneration;
    try {
      const user = await window.Auth.getCurrentUser();
      if (epoch !== authGeneration || !window.ApiClient.getAccessToken()) return;
      await acceptUser(user);
    }
    catch (error) {
      if (epoch !== authGeneration) return;
      if (error.sessionExpired) { currentUser = null; loginMessage = "Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại."; }
      else {
        const saved = window.ApiClient.getSession()?.user;
        if (saved && saved.role !== "SHIPPER") { setupUser(saved); restoreWarning = error.message; } else loginMessage = error.message;
      }
    }
  }
  setLoading(true);
  restoreUser().finally(() => {
    started = true; Router.start({ getUser: () => currentUser, onLeave: leavePage, onLoading: showLoading, onRoute: renderRoute, onError: showError }); setLoading(false);
  });
}());
