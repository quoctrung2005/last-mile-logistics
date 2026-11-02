"use strict";

(function () {
  // Code39 Standard Barcode Symbol Encoding Map
  const CODE39 = {
    '0': '000110100', '1': '100100001', '2': '001100001', '3': '101100000',
    '4': '000110001', '5': '100110000', '6': '001110000', '7': '000100101',
    '8': '100100100', '9': '001100100', 'A': '100001001', 'B': '001001001',
    'C': '101001000', 'D': '000011001', 'E': '100011000', 'F': '001011000',
    'G': '000001101', 'H': '100001100', 'I': '001001100', 'J': '000011100',
    'K': '100000011', 'L': '001000011', 'M': '101000010', 'N': '000010011',
    'O': '100010010', 'P': '001010010', 'Q': '000000111', 'R': '100000110',
    'S': '001000110', 'T': '000010110', 'U': '110000001', 'V': '011000001',
    'W': '111000000', 'X': '010010001', 'Y': '110010000', 'Z': '011010000',
    '-': '010000101', '.': '110000100', ' ': '011000100', '$': '010101000',
    '/': '010100010', '+': '010001010', '%': '000101010', '*': '010010100'
  };

  function generateBarcodeSvg(rawText, height = 48) {
    if (!rawText) return "";
    const clean = ('*' + String(rawText).toUpperCase().replace(/[^0-9A-Z\-\. \$\/\+\%]/g, '') + '*');
    let bits = '';
    for (let i = 0; i < clean.length; i++) {
      const pattern = CODE39[clean[i]] || CODE39[' '];
      for (let j = 0; j < 9; j++) {
        const isBar = (j % 2 === 0);
        const isWide = pattern[j] === '1';
        const width = isWide ? 3 : 1;
        bits += isBar ? '1'.repeat(width) : '0'.repeat(width);
      }
      bits += '0'; // inter-character space
    }

    let rects = '';
    let x = 0;
    for (let i = 0; i < bits.length; i++) {
      if (bits[i] === '1') {
        rects += `<rect x="${x}" y="0" width="1" height="${height}" fill="#000" />`;
      }
      x++;
    }

    return `<svg viewBox="0 0 ${x} ${height}" preserveAspectRatio="none" style="width: 100%; height: ${height}px; display: block;">${rects}</svg>`;
  }

  function formatMoney(amount) {
    if (amount == null || isNaN(Number(amount))) return "0 ₫";
    return new Intl.NumberFormat("vi-VN").format(Number(amount)) + " ₫";
  }

  function formatDate(d) {
    if (!d) return "—";
    try {
      const parsed = new Date(String(d) + (/(?:Z|[+-]\d\d:\d\d)$/i.test(String(d)) ? "" : "Z"));
      if (isNaN(parsed.getTime())) return String(d);
      return new Intl.DateTimeFormat("vi-VN", {
        timeZone: "Asia/Ho_Chi_Minh",
        dateStyle: "short",
        timeStyle: "short"
      }).format(parsed);
    } catch {
      return String(d);
    }
  }

  function buildWaybillHtml(order) {
    const tracking = order.trackingNumber || order.orderCode || "TVD-000000";
    const barcodeSvg = generateBarcodeSvg(tracking);

    const itemsSummary = Array.isArray(order.items) && order.items.length
      ? order.items.map(it => `${it.name || "Kiện hàng"} (SL: ${it.quantity || 1})`).join(", ")
      : (order.notes || "Hàng hóa tiêu chuẩn");

    return `
      <div class="waybill-card">
        <!-- HEADER -->
        <div class="wb-header">
          <div class="wb-logo-group">
            <div class="wb-brand">TVĐ LOGISTICS</div>
            <div class="wb-slogan">Dịch vụ chuyển phát chặng cuối</div>
            <div class="wb-contact">Hotline: 1900 6868 · www.tvdlogistics.vn</div>
          </div>
          <div class="wb-branch-box">
            <div class="wb-branch-name">${order.branchName || "Bưu cục trung tâm"}</div>
            <div class="wb-routing">HUB: SGN · Tuyến: NỘI THÀNH</div>
            <div class="wb-created">Tạo: ${formatDate(order.createdAt)}</div>
          </div>
        </div>

        <!-- BARCODE & TRACKING -->
        <div class="wb-barcode-section">
          ${barcodeSvg}
          <div class="wb-tracking-text">${tracking}</div>
          <div class="wb-order-code">Mã đơn: <strong>${order.orderCode || tracking}</strong></div>
        </div>

        <!-- FROM - TO -->
        <div class="wb-address-grid">
          <div class="wb-addr-col">
            <div class="wb-addr-title">TỪ (NGƯỜI GỬI):</div>
            <div class="wb-person-name">${order.senderName || "Kho hàng bưu cục"}</div>
            <div class="wb-phone">ĐT: ${order.senderPhone || "—"}</div>
            <div class="wb-address">${order.pickupAddress || "Gửi tại bưu cục"}</div>
          </div>
          <div class="wb-addr-col to-col">
            <div class="wb-addr-title">ĐẾN (NGƯỜI NHẬN):</div>
            <div class="wb-person-name">${order.receiverName || "Khách nhận hàng"}</div>
            <div class="wb-phone">ĐT: ${order.receiverPhone || "—"}</div>
            <div class="wb-address">${order.deliveryAddress || "—"}</div>
          </div>
        </div>

        <!-- PACKAGE DETAILS -->
        <div class="wb-info-grid">
          <div><strong>Trọng lượng:</strong> ${(order.weightKg || 0).toFixed(2)} kg</div>
          <div><strong>Số kiện:</strong> ${order.items?.length || 1} kiện</div>
          <div><strong>Hạn phát:</strong> ${formatDate(order.expectedDeliveryAt)}</div>
          <div><strong>Phí cước:</strong> ${formatMoney(order.shippingFee)}</div>
        </div>

        <div class="wb-goods-row">
          <strong>Nội dung hàng:</strong> ${itemsSummary}
        </div>

        <div class="wb-notes-row">
          <strong>Chỉ dẫn giao hàng:</strong> ${order.notes || "Cho xem hàng, không cho thử · Giao giờ hành chính"}
        </div>

        <!-- COD HIGHLIGHT BOX -->
        <div class="wb-cod-box">
          <div class="wb-cod-lbl">TIỀN THU NGƯỜI NHẬN (COD):</div>
          <div class="wb-cod-amt">${formatMoney(order.codAmount || 0)}</div>
          <div class="wb-cod-sub">Tài xế thu đúng số tiền trên phiếu trước khi bàn giao kiện</div>
        </div>

        <!-- SIGNATURES -->
        <div class="wb-sign-grid">
          <div class="wb-sign-col">
            <div class="wb-sign-lbl">Chữ ký người gửi</div>
            <div class="wb-sign-note">(Ký & ghi rõ họ tên)</div>
            <div class="wb-sign-space"></div>
          </div>
          <div class="wb-sign-col">
            <div class="wb-sign-lbl">Xác nhận người nhận</div>
            <div class="wb-sign-note">(Hàng nguyên vẹn, không móp rách)</div>
            <div class="wb-sign-space"></div>
          </div>
        </div>
      </div>
    `;
  }

  function printWaybills(orders) {
    if (!orders || !orders.length) return;

    const list = Array.isArray(orders) ? orders : [orders];

    const printWin = window.open("", "_blank", "width=850,height=950,menubar=no,toolbar=no,location=no,status=no");
    if (!printWin) {
      alert("Trình duyệt đã chặn cửa sổ bật lên (popup). Vui lòng cấp quyền mở popup để in tem vận đơn.");
      return;
    }

    const cardsHtml = list.map(o => buildWaybillHtml(o)).join("\n");

    const fullHtml = `<!DOCTYPE html>
<html lang="vi">
<head>
  <meta charset="UTF-8">
  <title>In Phiếu Gửi - TVĐ Logistics (${list.length} đơn)</title>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      background: #F1F5F9;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Arial, sans-serif;
      padding: 20px;
      display: flex;
      flex-direction: column;
      align-items: center;
      gap: 20px;
    }
    .print-bar {
      position: sticky;
      top: 0;
      background: white;
      padding: 10px 20px;
      border-radius: 12px;
      box-shadow: 0 4px 12px rgba(0,0,0,0.15);
      display: flex;
      gap: 15px;
      align-items: center;
      z-index: 1000;
    }
    .btn-print {
      background: #FA5A00;
      color: white;
      border: none;
      padding: 10px 20px;
      border-radius: 8px;
      font-size: 14px;
      font-weight: 700;
      cursor: pointer;
    }
    .btn-close {
      background: #E2E8F0;
      color: #334155;
      border: none;
      padding: 10px 16px;
      border-radius: 8px;
      font-size: 14px;
      font-weight: 600;
      cursor: pointer;
    }
    
    /* WAYBILL A6 DIMENSIONS */
    .waybill-card {
      width: 105mm;
      min-height: 148mm;
      background: white;
      border: 1.5px solid #0F172A;
      padding: 5mm;
      display: flex;
      flex-direction: column;
      gap: 2mm;
      box-shadow: 0 4px 14px rgba(0,0,0,0.08);
      font-size: 11px;
      line-height: 1.3;
      color: #0F172A;
    }

    .wb-header {
      display: flex;
      justify-content: space-between;
      border-bottom: 1.5px solid #000;
      padding-bottom: 2mm;
    }
    .wb-brand {
      font-size: 15px;
      font-weight: 900;
      letter-spacing: -0.3px;
      color: #000;
    }
    .wb-slogan { font-size: 9.5px; font-weight: 600; color: #475569; }
    .wb-contact { font-size: 8.5px; color: #64748B; margin-top: 1px; }
    .wb-branch-box { text-align: right; }
    .wb-branch-name { font-size: 11px; font-weight: 800; }
    .wb-routing { font-size: 9px; font-weight: 700; color: #2563EB; }
    .wb-created { font-size: 8.5px; color: #64748B; }

    .wb-barcode-section {
      text-align: center;
      padding: 2mm 0;
      border-bottom: 1px dashed #94A3B8;
    }
    .wb-tracking-text {
      font-family: monospace;
      font-size: 15px;
      font-weight: 900;
      letter-spacing: 2px;
      margin-top: 2px;
    }
    .wb-order-code { font-size: 10px; color: #475569; }

    .wb-address-grid {
      display: grid;
      grid-template-columns: 1fr 1fr;
      gap: 3mm;
      border-bottom: 1px solid #000;
      padding-bottom: 2mm;
    }
    .wb-addr-col {
      display: flex;
      flex-direction: column;
      gap: 1px;
    }
    .to-col {
      border-left: 1px dashed #CBD5E1;
      padding-left: 2mm;
    }
    .wb-addr-title { font-size: 9px; font-weight: 800; color: #64748B; }
    .wb-person-name { font-size: 11.5px; font-weight: 800; }
    .wb-phone { font-size: 11px; font-weight: 700; }
    .wb-address { font-size: 10px; color: #1E293B; line-height: 1.25; }

    .wb-info-grid {
      display: grid;
      grid-template-columns: repeat(2, 1fr);
      gap: 1.5mm;
      background: #F8FAFC;
      padding: 1.5mm 2mm;
      border-radius: 3px;
      border: 1px solid #E2E8F0;
      font-size: 10px;
    }
    .wb-goods-row, .wb-notes-row {
      font-size: 10px;
      padding: 1mm 0;
      border-bottom: 1px dashed #E2E8F0;
    }

    .wb-cod-box {
      border: 2px solid #000;
      background: #FFF7ED;
      padding: 2mm;
      text-align: center;
      margin: 1mm 0;
    }
    .wb-cod-lbl { font-size: 10px; font-weight: 800; color: #C2410C; }
    .wb-cod-amt { font-size: 20px; font-weight: 900; color: #EA580C; margin: 1px 0; }
    .wb-cod-sub { font-size: 8.5px; font-weight: 600; color: #475569; }

    .wb-sign-grid {
      display: grid;
      grid-template-columns: 1fr 1fr;
      gap: 4mm;
      margin-top: 1mm;
      text-align: center;
    }
    .wb-sign-lbl { font-size: 9.5px; font-weight: 800; }
    .wb-sign-note { font-size: 8px; color: #64748B; font-style: italic; }
    .wb-sign-space { height: 12mm; }

    /* PRINT SPECIFIC STYLES */
    @media print {
      body { background: white; padding: 0; gap: 0; }
      .print-bar { display: none !important; }
      .waybill-card {
        border: 1.5px solid #000;
        box-shadow: none;
        page-break-after: always;
        break-after: page;
        margin: 0 auto;
      }
      @page {
        size: A6 portrait;
        margin: 3mm;
      }
    }
  </style>
</head>
<body>
  <div class="print-bar">
    <span>Sẵn sàng in <strong>${list.length}</strong> phiếu gửi (Khổ A6)</span>
    <button class="btn-print" onclick="window.print()">🖨️ Tiến hành in ngay</button>
    <button class="btn-close" onclick="window.close()">Đóng cửa sổ</button>
  </div>

  ${cardsHtml}

  <script>
    window.addEventListener('load', () => {
      // Small timeout to ensure font and SVG are fully rendered before print dialog
      setTimeout(() => {
        window.print();
      }, 400);
    });
  </script>
</body>
</html>`;

    printWin.document.open();
    printWin.document.write(fullHtml);
    printWin.document.close();
  }

  window.WaybillPrinter = Object.freeze({
    print: printWaybills,
    generateBarcodeSvg
  });
})();
