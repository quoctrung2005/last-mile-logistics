# Tổng quan TVD Logistics — bố cục thẻ chỉ số

Đã khôi phục bố cục Tổng quan dạng 4 thẻ theo yêu cầu, thay sơ đồ luồng và các đường nối SVG. Giữ giao diện trắng cam, Bootstrap, API, quyền và dữ liệu hiện có.

## Giao diện hiện tại

- Bốn thẻ: Chờ nhập kho, Chờ phân công, Đang giao, Giao thất bại cần xử lý. Mỗi thẻ có icon, số lượng, giải thích và liên kết Xem danh sách.
- Desktop 4 cột; màn hình nhỏ 2 cột. Tên/mã dài xuống dòng hoặc ellipsis phù hợp, không cuộn ngang toàn trang.
- Giữ phần Cần xử lý, Kết quả giao hàng hôm nay, Xem báo cáo, nút Làm mới và bộ chọn bưu cục duy nhất ở header.
- Giữ khoảng chừa header đã sửa; một tiêu đề Tổng quan, phạm vi và thời điểm cập nhật.
- Thiếu quyền không hiển thị số 0 hoặc liên kết trái phép. Lỗi từng phần có Thử lại và không đăng xuất tùy tiện.
- Không còn ResizeObserver, RAF hoặc SVG của sơ đồ. Request và listener header tiếp tục được dọn khi rời trang.

## Số liệu và API

| Thẻ | Điều kiện |
| --- | --- |
| Chờ nhập kho | CONFIRMED/WAITING_INBOUND, chưa có kho hiện tại và chưa có bản ghi tồn kho. |
| Chờ phân công | WAITING_ASSIGNMENT. |
| Đang giao | IN_DELIVERY. |
| Giao thất bại cần xử lý | FAILED với lượt mới nhất thất bại và chưa có yêu cầu xử lý đang thực hiện/đã hoàn tất cho lượt đó, theo OperationalOrderQuery hiện có. |

Không giới hạn ngày tạo đơn. Thẻ mở danh sách Đơn hàng với đúng operationalGroup và branchId. Tổng và danh sách dùng chung điều kiện backend.

Giữ nguyên GET /api/v1/dashboard/context, /operations, /delivery-today và bộ lọc /api/v1/orders. Các trường inWarehouse, waitingHandover, overdue đã bổ sung ở backend vẫn tương thích, không hiển thị thành node trên giao diện. Không sửa backend, migration hoặc database vận hành trong lần khôi phục này.

Kết quả hôm nay tiếp tục đếm lượt giao theo thời điểm thực hiện trong ngày Việt Nam; mẫu số 0 hiển thị — và “Hôm nay chưa có lượt giao”. Công việc giữ tối đa 5 mục, link chỉ mở chi tiết; không phân công hoặc thay đổi trạng thái tự động.

## File khôi phục và kiểm tra

- frontend/js/dashboard.js: trở lại 4 thẻ, bỏ logic sơ đồ.
- frontend/assets/css/dashboard.css: bố cục thẻ và responsive.
- frontend/index.html: tăng phiên bản CSS/JS để bỏ cache cũ.
- frontend/tests/dashboard-checks.cjs: kiểm tra bố cục thẻ và liên kết tương ứng.
- Tài liệu này và ảnh/JSON kiểm tra trong docs/dashboard/.

Lệnh: npm.cmd test --prefix frontend; npm.cmd run test:dashboard --prefix frontend.

Kiểm tra tích hợp dùng API ASP.NET và Edge thật với database LocalDB GUID riêng; không ghi dữ liệu vận hành. Database thử tự dọn khi kết thúc. Có một lỗi SQL/503 cố ý để kiểm tra lỗi một phần và khả năng Thử lại.

Đã đạt 72 kiểm tra tích hợp, 46/46 unit test; build backend 0 lỗi và 0 cảnh báo. Đã kiểm tra 1366px, 1920px, 1024px và mobile 390px. Kết quả lần chạy cuối: [JSON](dashboard/dashboard-verification.json). Ảnh: [1366px](dashboard/dashboard-1366.png), [1920px](dashboard/dashboard-1920.png), [1024px](dashboard/dashboard-1024.png), [390px](dashboard/dashboard-390.png).