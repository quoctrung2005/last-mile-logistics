"use strict";
(function () {
  const U = window.AdminUI, R = window.Router, { el, button } = U;
  const tabs = { orders: "Đơn hàng", delivery: "Giao hàng", finance: "Cước phí & COD" };
  const columns = {
    orders: [["branchName", "Bưu cục"], ["createdCount", "Tổng đơn"], ["successfulCount", "Thành công"], ["failedCount", "Thất bại"], ["cancelledReturnedCount", "Hủy/hoàn"]],
    delivery: [["shipperName", "Nhân viên"], ["branchName", "Bưu cục"], ["assignmentCount", "Phân công"], ["attemptCount", "Lượt giao"], ["successfulCount", "Thành công"], ["failedCount", "Thất bại"], ["successRatePercent", "Tỷ lệ thành công"]],
    finance: [["branchName", "Bưu cục"], ["shippingFees", "Tổng cước phí trên đơn"], ["openingBalance", "Số dư đầu kỳ"], ["collectedAmount", "COD đã thu trong kỳ"], ["confirmedDepositAmount", "Nộp được xác nhận trong kỳ"], ["closingBalance", "Số dư cuối kỳ"], ["outstandingAmount", "Còn phải nộp cuối kỳ"], ["pendingDepositAmount", "Phiếu hiện chờ xác nhận đến cuối kỳ"], ["availableToDepositAmount", "Còn có thể lập phiếu"]]
  };
  const number = n => new Intl.NumberFormat("vi-VN", { maximumFractionDigits: 2 }).format(n);
  const money = n => number(n) + " VNĐ";
  const rate = n => n == null ? "—" : number(n) + "%";
  const dayLabel = d => d.split("-").reverse().join("/");
  const financeNote = "Dữ liệu theo trạng thái hiện tại của bản ghi; hệ thống chưa lưu lịch sử thời điểm đảo thu/chuyển trạng thái phiếu. Phiếu chờ là trạng thái hiện tại, có ngày nộp trước hết kỳ; không phải ảnh chụp trạng thái quá khứ. Chưa có sổ doanh thu thực thu hoặc số tiền thực trả khách hàng. Số dư có thể thay đổi khi bản ghi được đảo/hủy.";
  const hints = {
    assignmentCount: "Số bản ghi phân công có ngày phân công trong kỳ; gồm mọi trạng thái. Một đơn có thể có nhiều phân công.",
    attemptCount: "Số lượt giao thực hiện trong kỳ. Một đơn có thể có nhiều lượt giao.",
    successfulCount: "Số lượt giao trong kỳ có kết quả SUCCESS.",
    failedCount: "Số lượt giao trong kỳ có kết quả FAILED.",
    branchName: "Bưu cục của đơn hàng, không nhất thiết là bưu cục hiện tại của nhân viên."
  };
  let active = null;

  function todayVN() { return new Intl.DateTimeFormat("en-CA", { timeZone: "Asia/Ho_Chi_Minh", year: "numeric", month: "2-digit", day: "2-digit" }).format(new Date()); }
  function shiftDay(day, delta) { const date = new Date(day + "T00:00:00Z"); date.setUTCDate(date.getUTCDate() + delta); return date.toISOString().slice(0, 10); }
  function validateDates(from, to) {
    for (const value of [from, to]) {
      const date = /^\d{4}-\d{2}-\d{2}$/.test(value) && new Date(value + "T00:00:00Z");
      if (!date || !Number.isFinite(date.getTime()) || date.toISOString().slice(0, 10) !== value || value < "1900-01-01" || value > "9999-12-30") return "Hãy chọn ngày hợp lệ từ 01/01/1900 đến 30/12/9999.";
    }
    if (from > to) return "Từ ngày không được sau đến ngày.";
    if ((Date.parse(to + "T00:00:00Z") - Date.parse(from + "T00:00:00Z")) / 86400000 > 365) return "Mỗi lần xem báo cáo tối đa 366 ngày.";
    return "";
  }
  // Text cells get a leading apostrophe when spreadsheet programs could evaluate them.
  function csvCell(value) {
    let text = value == null ? "" : String(value);
    if (typeof value === "string" && /^[\s\u0000-\u001f]*[=+\-@]/.test(text)) text = "'" + text;
    return '"' + text.replace(/"/g, '""') + '"';
  }
  function csvRows(rows) { return "\uFEFF" + rows.map(row => row.map(csvCell).join(",")).join("\r\n") + "\r\n"; }
  function definition(tab, to) {
    if (tab === "orders") return "Đơn tạo trong khoảng thời gian đã chọn — trạng thái tại thời điểm xem. Thành công: DELIVERED hoặc COMPLETED; thất bại: FAILED; hủy/hoàn: CANCELLED, RETURNING hoặc RETURNED. Mỗi đơn đếm một lần.";
    if (tab === "delivery") return "Đếm bản ghi phân công theo ngày phân công và lần giao theo ngày thực hiện trong kỳ (hai tập độc lập). Một đơn có thể có nhiều phân công/lần giao. Kết quả thuộc nhân viên của phân công gắn với chính lần giao, không phải shipper hiện tại. Tỷ lệ = lần thành công / tổng lần giao × 100%.";
    return "Cước phí: toàn bộ đơn tạo trong kỳ, kể cả đơn hủy; chưa phải doanh thu thực thu. COD thu theo ngày thu, nộp theo ngày xác nhận và phân bổ của từng đơn. Số dư đến cuối ngày " + dayLabel(to) + " = số dư đầu kỳ + thu trong kỳ − nộp được xác nhận trong kỳ. Còn phải nộp = tổng phần số dư dương từng đơn; còn có thể lập phiếu trừ thêm phân bổ hiện chờ xác nhận. COD không phải doanh thu.";
  }
  function validateReport(data, tab) {
    window.ApiClient.validatePage(data, "/api/v1/reports/dashboard", []);
    if (data.report !== tab || !data.summary || !Array.isArray(data.branches) || !Array.isArray(data.dailyOrders) || !Array.isArray(data.ordersByStatus)) throw new Error("API báo cáo trả dữ liệu không hợp lệ.");
    const metrics = columns[tab].filter(([key]) => !["branchName", "shipperName"].includes(key)).map(([key]) => key);
    for (const row of [data.summary, ...data.items]) for (const key of metrics) {
      if (key === "successRatePercent" && row[key] === null) continue;
      if (typeof row[key] !== "number" || !Number.isFinite(row[key])) throw new Error("API báo cáo thiếu chỉ số hợp lệ: " + key);
    }
    if (data.dailyOrders.some(row => !/^\d{4}-\d{2}-\d{2}$/.test(row.date) || !Number.isSafeInteger(row.createdOrderCount) || row.createdOrderCount < 0)
      || data.ordersByStatus.some(row => typeof row.statusName !== "string" || !Number.isSafeInteger(row.orderCount))) throw new Error("API trả chuỗi biểu đồ không hợp lệ.");
    return data;
  }
  function cell(key, value, tab) { return key === "successRatePercent" ? rate(value) : /Name$/.test(key) ? value : tab === "finance" ? money(value) : number(value); }
  function dataTable(headers, rows, caption, keys = [], tooltips = {}) {
    const wrap = el("div", "report-table-wrap"), table = el("table", "table report-table align-middle");
    table.append(el("caption", "visually-hidden", caption));
    const head = el("thead"), heading = el("tr"), body = el("tbody");
    headers.forEach((label, index) => {
      const th = el("th", "", label); th.scope = "col";
      if (keys[index] && !/Name$/.test(keys[index])) th.className = "report-number";
      if (keys[index] && tooltips[keys[index]]) th.title = tooltips[keys[index]];
      heading.append(th);
    });
    for (const row of rows) {
      const tr = el("tr"); row.forEach((value, index) => {
        const td = el("td", keys[index] && !/Name$/.test(keys[index]) ? "report-number" : "");
        td.append(value instanceof Node ? value : document.createTextNode(value == null ? "—" : String(value))); tr.append(td);
      }); body.append(tr);
    }
    head.append(heading); table.append(head, body); wrap.append(table);
    wrap.tabIndex = 0; wrap.setAttribute("role", "region"); wrap.setAttribute("aria-label", caption);
    return wrap;
  }
  function card(title, content) {
    const section = el("section", "report-panel"); section.append(el("h2", "h6", title), content); return section;
  }
  function chart(s, rows) {
    const box = el("div", "report-chart"), plot = el("div", "report-plot");
    const details = el("details"), summary = el("summary", "", "Xem bảng số đơn theo ngày");
    details.append(summary, dataTable(["Ngày (VN)", "Số đơn tạo"], rows.map(r => [dayLabel(r.date), number(r.createdOrderCount)]), "Dữ liệu biểu đồ số đơn theo ngày", ["date", "createdOrderCount"]));
    box.append(el("p", "report-chart-legend", "Đơn tạo theo ngày · Đơn vị: đơn"), plot, details);

    if (window.Chart) {
      plot.style.height = "260px";
      plot.style.position = "relative";
      const canvas = el("canvas");
      plot.replaceChildren(canvas);
      try {
        const cInstance = new window.Chart(canvas.getContext("2d"), {
          type: "line",
          data: {
            labels: rows.map(r => dayLabel(r.date)),
            datasets: [{
              label: "Số đơn tạo",
              data: rows.map(r => r.createdOrderCount),
              borderColor: "#FA5A00",
              backgroundColor: "rgba(250, 90, 0, 0.15)",
              borderWidth: 2.5,
              tension: 0.3,
              fill: true,
              pointRadius: rows.length > 30 ? 1 : 3
            }]
          },
          options: {
            responsive: true,
            maintainAspectRatio: false,
            plugins: { legend: { display: false } },
            scales: {
              y: { beginAtZero: true, title: { display: true, text: "Số đơn" } },
              x: { ticks: { maxRotation: 45, minRotation: 0 } }
            }
          }
        });
        s.disposeChart = () => { try { cInstance.destroy(); } catch {} };
        return box;
      } catch (err) {
        console.warn("Chart.js failed, falling back to SVG:", err);
      }
    }

    let failed = false;
    function draw(width) {
      if (failed || !s.alive()) return;
      try {
        const w = Math.max(260, Math.round(width)), left = 44, right = w - 16;
        const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
        svg.setAttribute("viewBox", "0 0 " + w + " 260"); svg.setAttribute("role", "img"); svg.setAttribute("aria-label", "Số đơn tạo theo ngày. Trục ngang: ngày Việt Nam; trục dọc: số đơn. Đường màu cam là số đơn tạo.");
        const add = (type, attrs, text) => { const n = document.createElementNS(svg.namespaceURI, type); for (const [key, value] of Object.entries(attrs)) n.setAttribute(key, value); if (text != null) n.textContent = text; svg.append(n); return n; };
        const max = Math.max(4, Math.ceil(Math.max(0, ...rows.map(r => r.createdOrderCount)) / 4) * 4);
        for (let i = 0; i <= 4; i++) { const y = 218 - i * 48; add("line", { x1: left, x2: right, y1: y, y2: y, stroke: "#e8edf3" }); add("text", { x: left - 8, y: y + 4, "text-anchor": "end", fill: "#667085" }, number(max * i / 4)); }
        const x = i => rows.length === 1 ? (left + right) / 2 : left + i * (right - left) / Math.max(1, rows.length - 1), y = count => 218 - count * 192 / max;
        add("polyline", { points: rows.map((r, i) => x(i) + "," + y(r.createdOrderCount)).join(" "), fill: "none", stroke: "#ed6a22", "stroke-width": 2.5 });
        rows.forEach((r, i) => { const point = add("circle", { cx: x(i), cy: y(r.createdOrderCount), r: rows.length > 60 ? 1.25 : 3, fill: "#ed6a22" }); const title = document.createElementNS(svg.namespaceURI, "title"); title.textContent = dayLabel(r.date) + ": " + number(r.createdOrderCount) + " đơn"; point.append(title); });
        [...new Set([0, Math.floor((rows.length - 1) / 2), rows.length - 1])].filter(i => i >= 0).forEach(i => add("text", { x: x(i), y: 244, "text-anchor": rows.length === 1 ? "middle" : i === 0 ? "start" : i === rows.length - 1 ? "end" : "middle", fill: "#667085" }, dayLabel(rows[i].date).slice(0, 5)));
        plot.replaceChildren(svg);
      } catch (_) {
        failed = true; plot.classList.add("report-chart-error"); plot.replaceChildren(el("p", "", "Không thể hiển thị biểu đồ. Bạn có thể xem bảng số liệu bên dưới.")); details.open = true;
      }
    }
    draw(600);
    if (window.ResizeObserver) { const observer = new ResizeObserver(entries => draw(entries[0].contentRect.width)); observer.observe(plot); s.disposeChart = () => observer.disconnect(); }
    return box;
  }
  function destroy() { active?.destroy(); active = null; }
  function path(filters, exporting = false) { return "/api/v1/reports/dashboard?" + U.query({ from: filters.from, to: filters.to, branchId: filters.branchId, report: filters.tab, page: filters.page, pageSize: filters.pageSize, ...(exporting ? { export: true } : {}) }); }
  function updateURL(s) { R.updateQuery(s.filters, s.route); s.route = R.current() || s.route; }
  function hasDraft(s) {
    const applied = s.confirmedFilters || s.filters;
    return ["from", "to", "branchId"].some(key => String(s.fields[key].control.value) !== String(applied[key] ?? ""));
  }
  function updateQuick(s) {
    const from = s.fields.from.control.value, to = s.fields.to.control.value, today = todayVN();
    for (const [key, b] of Object.entries(s.quickButtons)) {
      const start = key === "today" ? today : key === "week" ? shiftDay(today, -6) : today.slice(0, 7) + "-01";
      b.setAttribute("aria-pressed", String(from === start && to === today));
    }
  }
  function draftNotice(s) {
    s.feedback.replaceChildren();
    if (hasDraft(s)) s.feedback.append(el("p", "report-draft", "Bộ lọc đã thay đổi. Chọn Áp dụng để xem kết quả mới."));
  }
  function switchTab(s, tab) {
    s.filters = { ...(s.confirmedFilters || s.filters), tab, page: 1 }; load(s);
  }
  function apply(s, tab = s.filters.tab, reset = false) {
    const from = s.fields.from.control.value, to = s.fields.to.control.value;
    const error = validateDates(from, to);
    U.notice(s.feedback, error);
    if (error) return;
    s.filters = { ...s.filters, from, to, branchId: s.fields.branchId.control.value, tab, page: reset ? 1 : s.filters.page };
    load(s);
  }
  function shell(s) {
    const form = el("form", "report-filters"), main = el("div", "report-filter-main"), fields = {}; s.fields = fields;
    U.field(main, fields, "from", "Từ ngày", s.filters.from, { type: "date", min: "1900-01-01", max: "9999-12-30", required: true });
    U.field(main, fields, "to", "Đến ngày", s.filters.to, { type: "date", min: "1900-01-01", max: "9999-12-30", required: true });
    const branches = s.branches || (s.user.role === "ADMIN" ? [] : [{ id: s.user.branchId, name: "Bưu cục #" + s.user.branchId }]);
    U.field(main, fields, "branchId", "Bưu cục", s.filters.branchId, { items: [...(s.user.role === "ADMIN" ? [["", "Toàn hệ thống"]] : []), ...branches.map(b => [b.id, b.name])] });
    const actions = el("div", "report-filter-actions"), submit = button("Áp dụng", null, "btn btn-orange"); submit.type = "submit";
    const refresh = button("", () => { s.filters = { ...(s.confirmedFilters || s.filters) }; load(s); }, "btn btn-outline-secondary report-refresh");
    refresh.title = "Làm mới báo cáo theo bộ lọc đã áp dụng"; refresh.setAttribute("aria-label", "Làm mới");
    const refreshIcon = el("i", "bi bi-arrow-clockwise"); refreshIcon.setAttribute("aria-hidden", "true"); refresh.replaceChildren(refreshIcon, el("span", "visually-hidden", "Làm mới"));
    actions.append(submit, refresh); main.append(actions);
    const meta = el("div", "report-filter-meta"), quick = el("div", "report-quick"); s.quickButtons = {};
    quick.setAttribute("role", "group"); quick.setAttribute("aria-label", "Chọn nhanh khoảng ngày");
    for (const [key, label] of [["today", "Hôm nay"], ["week", "7 ngày"], ["month", "Tháng này"]]) {
      const b = button(label, () => { const today = todayVN(); fields.from.control.value = key === "today" ? today : key === "week" ? shiftDay(today, -6) : today.slice(0, 7) + "-01"; fields.to.control.value = today; markDraft(); }, "btn btn-sm");
      s.quickButtons[key] = b; quick.append(b);
    }
    const timezone = el("small", "report-timezone", "Múi giờ Việt Nam"); timezone.id = "report-timezone";
    for (const key of ["from", "to"]) fields[key].control.setAttribute("aria-describedby", "report-timezone");
    meta.append(quick, timezone); form.append(main, meta); form.addEventListener("submit", e => { e.preventDefault(); apply(s, s.filters.tab, true); });
    s.feedback = el("div", "report-feedback");
    const nav = el("div", "report-tabs"); nav.setAttribute("role", "tablist"); nav.setAttribute("aria-label", "Loại báo cáo"); s.tabButtons = {};
    for (const [key, label] of Object.entries(tabs)) { const b = button(label, () => switchTab(s, key), "report-tab"); b.setAttribute("role", "tab"); b.id = "report-tab-" + key; b.setAttribute("aria-controls", "report-results"); s.tabButtons[key] = b; nav.append(b); }
    nav.addEventListener("keydown", event => {
      const keys = Object.keys(tabs), index = keys.indexOf(s.filters.tab);
      const next = event.key === "ArrowRight" ? (index + 1) % keys.length : event.key === "ArrowLeft" ? (index + keys.length - 1) % keys.length : event.key === "Home" ? 0 : event.key === "End" ? keys.length - 1 : -1;
      if (next < 0) return; event.preventDefault(); s.tabButtons[keys[next]].focus(); switchTab(s, keys[next]);
    });
    s.results = el("div", "report-results"); s.results.id = "report-results"; s.results.setAttribute("role", "tabpanel"); s.results.tabIndex = 0;
    function markDraft() { s.draftVersion++; if (s.exportButton) s.exportButton.disabled = hasDraft(s) || s.exporting; draftNotice(s); updateQuick(s); }
    form.addEventListener("input", markDraft); form.addEventListener("change", markDraft);
    s.root.replaceChildren(form, s.feedback, nav, s.results); updateQuick(s);
  }
  function totals(s, data) {
    const strip = el("div", "report-stats"), tab = s.filters.tab, total = data.summary;
    if (tab === "finance") strip.classList.add("report-stats-finance");
    const metrics = tab === "orders" ? [["createdCount", "Tổng đơn"], ["successfulCount", "Thành công"], ["failedCount", "Thất bại"], ["cancelledReturnedCount", "Hủy/hoàn"]]
      : tab === "delivery" ? [["assignmentCount", "Phân công trong kỳ"], ["attemptCount", "Lượt giao"], ["successfulCount", "Giao thành công"], ["successRatePercent", "Tỷ lệ thành công"]]
      : columns.finance.slice(1, 9);
    const icons = { createdCount: "bi-box-seam", successfulCount: "bi-check2-circle", failedCount: "bi-exclamation-circle", cancelledReturnedCount: "bi-arrow-return-left", assignmentCount: "bi-person-check", attemptCount: "bi-truck", successRatePercent: "bi-percent" };
    for (const [key, label] of metrics) {
      const n = el("div", "report-stat"), top = el("div", "report-stat-label"), icon = el("i", "bi " + (icons[key] || "bi-wallet2"));
      icon.setAttribute("aria-hidden", "true"); top.append(el("span", "", label), icon); n.append(top, el("strong", "", cell(key, total[key], tab)));
      if (key === "successRatePercent") { n.title = "Số lượt giao thành công / tổng lượt giao × 100%. Mẫu số: " + number(total.attemptCount) + " lượt giao. Không có lượt giao: —."; n.tabIndex = 0; }
      strip.append(n);
    }
    return strip;
  }
  async function exportCSV(s) {
    if (!s.alive() || s.exportButton.disabled) return;
    const epoch = s.epoch, draftVersion = s.draftVersion, filters = { ...s.confirmedFilters }, b = s.exportButton; s.exporting = true; b.disabled = true; b.textContent = "Đang xuất…";
    s.exportAbort?.abort(); s.exportAbort = new AbortController();
    try {
      const data = validateReport(await s.read(path(filters, true), AbortSignal.any([s.abort.signal, s.exportAbort.signal])), filters.tab);
      if (!s.alive() || epoch !== s.epoch || draftVersion !== s.draftVersion) return;
      const scope = data.branchId == null ? "Toàn hệ thống" : data.branches.find(branch => branch.id === data.branchId)?.name || "Bưu cục #" + data.branchId;
      const cols = columns[filters.tab], rows = [["Báo cáo", tabs[filters.tab]], ["Từ ngày (VN)", data.from, "Đến ngày (VN)", data.to], ["Phạm vi", scope], ["Đơn vị tiền", "VNĐ"], ["Định nghĩa", definition(filters.tab, data.to)], ["Tạo lúc (UTC)", data.generatedAtUtc], [], cols.map(([, title]) => title),
        ...data.items.map(row => cols.map(([key]) => key === "successRatePercent" ? rate(row[key]) : row[key])),
        cols.map(([key], i) => i === 0 ? "Tổng cộng" : /Name$/.test(key) ? "" : key === "successRatePercent" ? rate(data.summary[key]) : data.summary[key])];
      if (filters.tab === "orders") rows.push([], ["Phân bố trạng thái hiện tại", "Số đơn"], ...data.ordersByStatus.map(r => [r.statusName, r.orderCount]), [], ["Ngày tạo (VN)", "Số đơn"], ...data.dailyOrders.map(r => [r.date, r.createdOrderCount]));
      const url = URL.createObjectURL(new Blob([csvRows(rows)], { type: "text/csv;charset=utf-8" })), link = el("a"); link.href = url; link.download = "bao-cao-" + filters.tab + "-" + data.from + "-" + data.to + ".csv"; link.click(); URL.revokeObjectURL(url);
      U.notice(s.feedback, "Đã xuất toàn bộ " + number(data.totalItems) + " dòng tổng hợp theo bộ lọc.", "success");
    } catch (error) { if (s.alive() && epoch === s.epoch && !s.exportAbort.signal.aborted) U.failure(s, s.feedback, error); }
    finally { if (s.alive() && epoch === s.epoch) { s.exporting = false; b.disabled = hasDraft(s); b.textContent = "Xuất CSV"; } }
  }
  function dateRange(from, to) {
    return from.slice(0, 4) === to.slice(0, 4) ? dayLabel(from).slice(0, 5) + "–" + dayLabel(to) : dayLabel(from) + "–" + dayLabel(to);
  }
  function explanation(tab, to) {
    const box = el("div", "report-explanation"), line = el("div", "report-explanation-line");
    const brief = tab === "orders" ? "Đơn tạo trong kỳ, theo trạng thái hiện tại." : tab === "delivery" ? "Thống kê theo lượt giao phát sinh trong thời gian đã chọn." : "Cước phí trên đơn và tiền thu hộ COD được theo dõi riêng.";
    const detail = el("div", "report-method"), toggle = button("Cách tính số liệu", () => { detail.hidden = !detail.hidden; toggle.setAttribute("aria-expanded", String(!detail.hidden)); }, "report-method-toggle");
    detail.id = "report-method-" + tab; detail.hidden = true; toggle.setAttribute("aria-expanded", "false"); toggle.setAttribute("aria-controls", detail.id);
    detail.append(el("p", "", definition(tab, to)));
    if (tab === "finance") detail.append(el("p", "", financeNote));
    if (tab === "delivery") detail.append(el("p", "", "Phân công bao gồm mọi trạng thái, kể cả từ chối, hủy hoặc thay thế. Mẫu số tỷ lệ là tổng lượt giao, không phải số phân công hoặc số đơn."));
    line.append(el("p", "", brief), toggle); box.append(line, detail); return box;
  }
  function statusList(data) {
    if (!data.ordersByStatus.length) return el("p", "report-muted", "Chưa có đơn trong kỳ.");
    const list = el("ul", "report-status-list"), total = data.summary.createdCount;
    for (const row of data.ordersByStatus) {
      const item = el("li"), line = el("div", "report-status-label"), track = el("div", "report-status-track"), fill = el("span");
      line.append(el("span", "", row.statusName), el("strong", "", number(row.orderCount)));
      fill.style.width = (total ? 100 * row.orderCount / total : 0) + "%"; track.setAttribute("aria-hidden", "true"); track.append(fill); item.append(line, track); list.append(item);
    }
    return list;
  }
  function pager(s, data) {
    const box = el("div", "report-pagination"), controls = el("div", "report-page-controls"), pages = Math.max(1, Math.ceil(data.totalItems / data.pageSize));
    const start = (data.page - 1) * data.pageSize + 1, end = Math.min(data.totalItems, data.page * data.pageSize);
    box.append(el("span", "report-page-summary", "Hiển thị " + number(start) + "–" + number(end) + " trong " + number(data.totalItems) + " kết quả"));
    const size = U.select([...new Set([10, 20, 50, 100, data.pageSize])].sort((a,b) => a-b).map(n => [n, n + " dòng"]), data.pageSize);
    size.setAttribute("aria-label", "Số dòng mỗi trang"); size.addEventListener("change", () => { s.filters = { ...s.confirmedFilters, page: 1, pageSize: Number(size.value) }; load(s); }); controls.append(size);
    if (pages > 1) {
      const prev = button("‹ Trước", () => { s.filters = { ...s.confirmedFilters, page: data.page - 1 }; load(s); }, "btn btn-outline-secondary btn-sm");
      const next = button("Sau ›", () => { s.filters = { ...s.confirmedFilters, page: data.page + 1 }; load(s); }, "btn btn-outline-secondary btn-sm");
      prev.disabled = data.page <= 1; next.disabled = data.page >= pages;
      controls.append(prev, el("span", "report-page-index", data.page + " / " + pages), next);
    }
    box.append(controls); return box;
  }
  function render(s, data) {
    const tab = data.report, scope = data.branchId == null ? "Toàn hệ thống" : data.branches.find(b => b.id === data.branchId)?.name || "Bưu cục #" + data.branchId;
    const head = el("div", "report-result-heading"), copy = el("div", "report-result-meta"), period = el("p", "report-period", dateRange(data.from, data.to) + " · " + scope);
    const updated = el("small", "report-updated", "Cập nhật " + U.date(data.generatedAtUtc)); updated.title = "Lần cập nhật dữ liệu thành công gần nhất, theo giờ Việt Nam";
    copy.append(period, updated);
    s.exportButton = button("Xuất CSV", () => exportCSV(s), "btn btn-outline-orange btn-sm"); head.append(copy, s.exportButton);
    s.results.replaceChildren(head, explanation(tab, data.to), totals(s, data));
    if (!data.totalItems) s.results.append(el("p", "report-empty", "Không có dữ liệu phù hợp với khoảng ngày và phạm vi đã chọn."));
    if (tab === "orders") {
      const grid = el("div", "report-order-grid");
      grid.append(card("Số đơn tạo theo ngày", chart(s, data.dailyOrders)), card("Phân bố trạng thái", statusList(data)));
      s.results.append(grid);
    }
    if (data.items.length && (tab !== "orders" || data.branches.length > 1)) {
      const cols = columns[tab], rows = data.items.map(row => cols.map(([key]) => {
        if (key !== "successRatePercent") return cell(key, row[key], tab);
        const n = el("span", "report-rate", rate(row[key])); n.title = "Số lượt giao thành công / tổng lượt giao × 100%. Mẫu số: " + number(row.attemptCount) + " lượt giao."; n.tabIndex = 0; return n;
      }));
      const tooltips = tab === "delivery" ? { ...hints, successRatePercent: "Số lượt giao thành công / tổng lượt giao × 100%." } : {};
      const panel = card(tab === "delivery" ? "Kết quả theo nhân viên" : "Tổng hợp theo bưu cục", dataTable(cols.map(([, label]) => label), rows, tabs[tab] + " theo bộ lọc đang áp dụng", cols.map(([key]) => key), tooltips));
      if (tab === "orders") { const note = el("p", "report-table-note", "Đơn tạo trong kỳ · Trạng thái tại thời điểm xem"); panel.insertBefore(note, panel.children[1]); }
      panel.append(pager(s, data)); s.results.append(panel);
    }
  }
  async function load(s) {
    const pending = U.request(s), draftVersion = s.draftVersion, requested = { ...s.filters }, branchWasDraft = hasDraft(s) && s.fields.branchId.control.value !== String((s.confirmedFilters || s.filters).branchId ?? "");
    s.exportAbort?.abort(); s.exporting = false; s.exportButton = null; s.disposeChart?.(); s.disposeChart = null;
    for (const [key, b] of Object.entries(s.tabButtons)) { const selected = key === s.filters.tab; b.setAttribute("aria-selected", String(selected)); b.tabIndex = selected ? 0 : -1; }
    s.results.setAttribute("aria-labelledby", "report-tab-" + s.filters.tab); s.results.setAttribute("aria-busy", "true"); s.results.replaceChildren(el("p", "report-empty", "Đang tải báo cáo…"));
    try {
      const data = validateReport(await s.read(path(requested), pending.signal), requested.tab);
      if (!s.alive() || pending.signal.aborted || pending.epoch !== s.epoch) return;
      const pages = Math.max(1, Math.ceil(data.totalItems / data.pageSize));
      if (data.page > pages) { s.filters.page = pages; return load(s); }
      s.branches = data.branches; s.filters = { ...requested, from: data.from, to: data.to, branchId: data.branchId ?? "", page: data.page, pageSize: data.pageSize }; s.confirmedFilters = { ...s.filters }; updateURL(s);
      const select = s.fields.branchId.control, branchDraft = select.value; select.replaceChildren();
      for (const [value, label] of [...(s.user.role === "ADMIN" ? [["", "Toàn hệ thống"]] : []), ...data.branches.map(b => [b.id, b.name])]) { const option = el("option", "", label); option.value = value; select.append(option); } select.value = draftVersion === s.draftVersion && !branchWasDraft ? s.filters.branchId : branchDraft;
      draftNotice(s); updateQuick(s); render(s, data); s.exportButton.disabled = hasDraft(s);
    } catch (error) { if (pending.epoch === s.epoch && !pending.signal.aborted) U.failure(s, s.results, error, () => load(s)); }
    finally { if (s.alive() && pending.epoch === s.epoch) s.results.setAttribute("aria-busy", "false"); }
  }
  function mount(container, user, route, context) {
    destroy(); const s = active = U.state(container, user, route, context); s.root.className = "reports-page"; s.draftVersion = 0;
    const to = route.query.to || todayVN();
    s.filters = { from: route.query.from || to.slice(0, 7) + "-01", to, branchId: route.query.branchId || "", tab: route.query.tab || "orders", page: route.query.page || 1, pageSize: route.query.pageSize || 10 };
    const cleanup = s.destroy; s.destroy = () => { s.exportAbort?.abort(); s.disposeChart?.(); s.disposeChart = null; cleanup(); };
    shell(s); const error = validateDates(s.filters.from, s.filters.to); if (error) U.notice(s.feedback, error); else load(s);
  }
  window.ReportsPage = Object.freeze({ mount, destroy, validateDates, csvRows, validateReport });
}());
