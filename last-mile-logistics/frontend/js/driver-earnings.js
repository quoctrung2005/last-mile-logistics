"use strict";
(function () {
  const U = window.AdminUI, R = window.Router;
  let active = null;

  const money = v => {
    if (v == null) return "0 VNĐ";
    const num = Number(v) || 0;
    return new Intl.NumberFormat("vi-VN", { maximumFractionDigits: 0 }).format(num) + " VNĐ";
  };

  const earningTypeLabels = {
    DELIVERY_SUCCESS: "Giao hàng thành công",
    RETRY_BONUS: "Phụ cấp giao lại",
    RETURN_COMPLETED: "Chuyển hoàn kho",
    BONUS: "Thưởng bổ sung"
  };

  const statusBadges = {
    PENDING: { label: "Chờ đối soát", cls: "text-bg-warning" },
    APPROVED: { label: "Đã duyệt", cls: "text-bg-success" },
    PAID: { label: "Đã thanh toán", cls: "text-bg-primary" }
  };

  function destroy() {
    active?.destroy();
    active = null;
  }

  async function editor(s, currentRates) {
    const d = U.dialog(s, "Cập nhật bảng định mức thù lao tài xế");
    if (!d) return;

    const form = U.el("form", "row g-3"), f = {};

    form.append(U.el("p", "col-12 text-secondary small",
      "Thiết lập tỷ lệ chiết khấu trên cước đơn hàng (tính theo km) và các mức phụ cấp theo loại xe. Hệ thống sẽ tự động tính thù lao tài xế cho mọi đơn hàng giao thành công tiếp theo."
    ));

    U.field(form, f, "commissionRate", "Tỷ lệ chiết khấu cước đơn (%) *", currentRates?.commissionRate ?? 80, {
      required: true, type: "number", min: 0, max: 100, step: "0.1"
    });

    U.field(form, f, "minWage", "Thù lao sàn tối thiểu (VNĐ) *", currentRates?.minWage ?? 15000, {
      required: true, type: "number", min: 0, max: 10000000, step: "1000"
    });

    U.field(form, f, "vanAllowance", "Phụ cấp Xe Van / Ba gác (VNĐ) *", currentRates?.vanAllowance ?? 20000, {
      required: true, type: "number", min: 0, max: 10000000, step: "1000"
    });

    U.field(form, f, "truckAllowance", "Phụ cấp Xe tải (VNĐ) *", currentRates?.truckAllowance ?? 50000, {
      required: true, type: "number", min: 0, max: 10000000, step: "1000"
    });

    U.field(form, f, "retryBonusRate", "Phụ cấp giao lại thành công (VNĐ) *", currentRates?.retryBonusRate ?? 5000, {
      required: true, type: "number", min: 0, max: 10000000, step: "1000"
    });

    U.field(form, f, "returnCompletedRate", "Thù lao chuyển hoàn về kho (VNĐ) *", currentRates?.returnCompletedRate ?? 8000, {
      required: true, type: "number", min: 0, max: 10000000, step: "1000"
    });

    U.field(form, f, "deliverySuccessRate", "Định mức giao thành công cơ bản (VNĐ) *", currentRates?.deliverySuccessRate ?? 15000, {
      required: true, type: "number", min: 0, max: 10000000, step: "1000"
    });

    form.append(U.el("p", "col-12 small text-muted",
      "Công thức: Thù lao = MAX(Cước đơn hàng × Tỷ lệ chiết khấu, Sàn tối thiểu) + Phụ cấp xe. Khi bấm Lưu, cấu hình cũ được lưu trữ và bảng định mức mới lập tức có hiệu lực."
    ));

    U.save(s, d, form, f, "/api/v1/admin/driver-earnings/rates", "PUT", () => ({
      commissionRate: Number(f.commissionRate.control.value),
      minWage: Number(f.minWage.control.value),
      vanAllowance: Number(f.vanAllowance.control.value),
      truckAllowance: Number(f.truckAllowance.control.value),
      retryBonusRate: Number(f.retryBonusRate.control.value),
      returnCompletedRate: Number(f.returnCompletedRate.control.value),
      deliverySuccessRate: Number(f.deliverySuccessRate.control.value)
    }), async () => {
      s.message = "Đã cập nhật bảng định mức thù lao tài xế thành công.";
      await list(s);
    }, "Lưu định mức");

    d.body.replaceChildren(form);
  }

  async function batchPay(s, ids) {
    if (!ids || ids.length === 0) return;
    if (!window.confirm(`Xác nhận duyệt thanh toán cho ${ids.length} khoản thù lao đã chọn?`)) return;

    try {
      const res = await window.ApiClient.request("/api/v1/admin/driver-earnings/batch-pay", {
        method: "POST",
        body: JSON.stringify({ earningIds: ids }),
        signal: s.abort.signal
      });
      s.message = res.message || `Đã thanh toán thành công cho ${ids.length} khoản thù lao.`;
      await list(s);
    } catch (err) {
      alert("Lỗi thanh toán: " + err.message);
    }
  }

  function renderRatesCard(s, rates) {
    const card = U.el("div", "card mb-4 shadow-sm border-0");
    card.style.background = "linear-gradient(135deg, #0f766e 0%, #0d9488 100%)";
    card.style.color = "#ffffff";
    card.style.borderRadius = "16px";

    const body = U.el("div", "card-body p-4");

    const header = U.el("div", "d-flex justify-content-between align-items-center mb-3");
    const titleWrap = U.el("div", "");
    const title = U.el("h3", "h5 fw-bold mb-1", "Bảng định mức chiết khấu & thù lao tài xế");
    const sub = U.el("p", "small text-white-50 mb-0", "Cơ chế tính theo cước đơn hàng thực tế (km) và loại phương tiện (xe máy, xe Van, xe tải)");
    titleWrap.append(title, sub);

    const editBtn = U.button("Cập nhật định mức", () => editor(s, rates), "btn btn-light btn-sm fw-bold text-teal");
    editBtn.style.color = "#0f766e";
    header.append(titleWrap, editBtn);

    const grid = U.el("div", "row g-3");

    const items = [
      { label: "Chiết khấu cước", value: (rates?.commissionRate ?? 80) + "%", sub: "trên cước đơn hàng", bg: "rgba(255,255,255,0.15)" },
      { label: "Sàn thù lao tối thiểu", value: money(rates?.minWage ?? 15000), sub: "đơn cước thấp/ngắn", bg: "rgba(255,255,255,0.15)" },
      { label: "Phụ cấp Xe Van / Ba gác", value: "+" + money(rates?.vanAllowance ?? 20000), sub: "cộng thêm mỗi đơn", bg: "rgba(255,255,255,0.15)" },
      { label: "Phụ cấp Xe tải", value: "+" + money(rates?.truckAllowance ?? 50000), sub: "tải nhẹ & tải nặng", bg: "rgba(255,255,255,0.15)" },
      { label: "Phụ cấp giao lại", value: "+" + money(rates?.retryBonusRate ?? 5000), sub: "giao lại thành công", bg: "rgba(255,255,255,0.15)" },
      { label: "Chuyển hoàn kho", value: money(rates?.returnCompletedRate ?? 8000), sub: "trả hàng về kho", bg: "rgba(255,255,255,0.15)" }
    ];

    for (const item of items) {
      const col = U.el("div", "col-md-4 col-sm-6");
      const box = U.el("div", "p-3 rounded-3");
      box.style.background = item.bg;
      box.style.backdropFilter = "blur(4px)";
      box.append(
        U.el("div", "small text-white-50 fw-semibold", item.label),
        U.el("div", "fs-5 fw-bold my-1", item.value),
        U.el("div", "small text-white-50", item.sub)
      );
      col.append(box);
      grid.append(col);
    }

    body.append(header, grid);
    card.append(body);
    return card;
  }

  async function list(s) {
    const pending = U.request(s);
    R.updateQuery(s.filters, s.route);
    s.route = R.current() || s.route;
    s.root.replaceChildren(U.el("p", "admin-empty", "Đang tải dữ liệu thù lao tài xế…"));

    try {
      const ratesPath = "/api/v1/admin/driver-earnings/rates";
      const listPath = "/api/v1/admin/driver-earnings?" + U.query(s.filters);

      const [rates, result] = await Promise.all([
        s.read(ratesPath, pending.signal),
        s.read(listPath, pending.signal)
      ]);

      if (!s.alive() || pending.signal.aborted || pending.epoch !== s.epoch) return;

      const pages = Math.max(1, Math.ceil(result.totalCount / result.pageSize));
      if (result.page > pages && pages > 0) {
        s.filters.page = pages;
        return list(s);
      }

      // Bộ lọc
      const form = U.el("form", "row g-3 admin-filters mb-3"), f = {};

      U.field(form, f, "status", "Trạng thái thanh toán", s.filters.status, {
        items: [
          ["", "Tất cả trạng thái"],
          ["APPROVED", "Đã duyệt (chờ thanh toán)"],
          ["PENDING", "Chờ đối soát"],
          ["PAID", "Đã thanh toán"]
        ]
      });

      U.field(form, f, "type", "Loại thu nhập", s.filters.type, {
        items: [
          ["", "Tất cả loại thu nhập"],
          ["DELIVERY_SUCCESS", "Giao hàng thành công"],
          ["RETRY_BONUS", "Phụ cấp giao lại"],
          ["RETURN_COMPLETED", "Chuyển hoàn kho"]
        ]
      });

      const searchBtn = U.button("Lọc danh sách", null, "btn btn-outline-orange");
      searchBtn.type = "submit";
      form.append(U.actions(searchBtn));

      form.addEventListener("submit", e => {
        e.preventDefault();
        for (const [key, v] of Object.entries(f)) s.filters[key] = v.control.value;
        s.filters.page = 1;
        list(s);
      });

      for (const v of Object.values(f)) {
        v.control.addEventListener("change", () => form.requestSubmit());
      }

      // Toolbar & Actions
      const feedback = U.el("div");
      const selectedIds = new Set();

      const paySelectedBtn = U.button("Duyệt thanh toán hàng loạt (0)", () => {
        batchPay(s, Array.from(selectedIds));
      }, "btn btn-success disabled");

      function updateSelectedCount() {
        const count = selectedIds.size;
        paySelectedBtn.textContent = `Duyệt thanh toán (${count})`;
        paySelectedBtn.classList.toggle("disabled", count === 0);
      }

      const toolbar = U.actions(
        U.button("Làm mới", () => list(s), "btn btn-outline-orange"),
        paySelectedBtn
      );

      // Bảng dữ liệu
      let body;
      if (!result.items || result.items.length === 0) {
        body = U.el("p", "admin-empty", "Không có khoản thù lao nào phù hợp điều kiện lọc.");
      } else {
        const checkAll = U.el("input", "form-check-input");
        checkAll.type = "checkbox";
        checkAll.title = "Chọn tất cả đơn có thể thanh toán";

        checkAll.addEventListener("change", () => {
          const checkboxes = body.querySelectorAll("input.row-check");
          checkboxes.forEach(cb => {
            if (!cb.disabled) {
              cb.checked = checkAll.checked;
              const id = Number(cb.dataset.id);
              if (checkAll.checked) selectedIds.add(id); else selectedIds.delete(id);
            }
          });
          updateSelectedCount();
        });

        const rows = result.items.map(item => {
          const isPaid = item.status === "PAID";
          const rowCheck = U.el("input", "form-check-input row-check");
          rowCheck.type = "checkbox";
          rowCheck.dataset.id = item.earningId;
          rowCheck.disabled = isPaid;

          rowCheck.addEventListener("change", () => {
            const id = item.earningId;
            if (rowCheck.checked) selectedIds.add(id); else selectedIds.delete(id);
            updateSelectedCount();
          });

          const st = statusBadges[item.status] || { label: item.statusLabel || item.status, cls: "text-bg-secondary" };
          const statusBadge = U.el("span", "badge " + st.cls, st.label);

          const typeName = earningTypeLabels[item.earningType] || item.earningTypeLabel || item.earningType;
          const typeBadge = U.el("span", "badge " + (
            item.earningType === "DELIVERY_SUCCESS" ? "text-bg-success" :
            item.earningType === "RETRY_BONUS" ? "text-bg-warning" : "text-bg-info"
          ), typeName);

          const shipperText = U.el("div", "", [
            U.el("strong", "d-block", item.shipperName || "Tài xế #" + item.shipperId),
            U.el("small", "text-muted", "ID: " + item.shipperId)
          ]);

          const orderText = U.el("div", "", [
            U.el("strong", "d-block", item.orderCode || "—"),
            U.el("small", "text-muted", item.trackingNumber || "")
          ]);

          const amountCol = U.el("span", "fw-bold text-success fs-6", "+" + money(item.amount));
          const feeCol = item.shippingFee > 0 ? money(item.shippingFee) : "—";
          const rateCol = item.commissionRate != null ? (item.commissionRate + "%") : "80%";

          const action = isPaid
            ? U.el("span", "text-muted small", "Đã trả")
            : U.button("Thanh toán", () => batchPay(s, [item.earningId]), "btn btn-outline-success btn-sm");

          return [
            rowCheck,
            "#" + item.earningId,
            shipperText,
            orderText,
            typeBadge,
            feeCol,
            rateCol,
            amountCol,
            statusBadge,
            U.date(item.recordedAt),
            item.notes || "—",
            action
          ];
        });

        body = U.table([
          checkAll,
          "Mã",
          "Tài xế",
          "Đơn hàng",
          "Loại thù lao",
          "Cước đơn",
          "Chiết khấu",
          "Thù lao",
          "Trạng thái",
          "Thời gian",
          "Ghi chú",
          "Thao tác"
        ], rows);
      }

      const pager = U.el("div", "admin-pagination");
      U.pager(pager, {
        page: result.page,
        pageSize: result.pageSize,
        totalItems: result.totalCount
      }, change => {
        Object.assign(s.filters, change);
        list(s);
      });

      s.root.replaceChildren(
        renderRatesCard(s, rates),
        toolbar,
        form,
        feedback,
        body,
        pager
      );

      if (s.message) {
        U.notice(feedback, s.message, "success");
        s.message = "";
      }
    } catch (error) {
      if (!pending.signal.aborted) {
        U.failure(s, s.root, error, () => list(s));
      }
    }
  }

  function mount(container, user, route, context) {
    destroy();
    active = U.state(container, user, route, context);
    active.filters = {
      page: route.query.page || 1,
      pageSize: route.query.pageSize || 20,
      shipperId: route.query.shipperId || "",
      type: route.query.type || "",
      status: route.query.status || ""
    };
    list(active);
  }

  window.DriverEarningsPage = Object.freeze({ mount, destroy });
}());
