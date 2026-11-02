# Tinh chỉnh giao diện COD — 17/10/2026

Phạm vi: `#/cod/collections` và `#/cod/reconciliation`. Giữ Bootstrap, giao diện trắng/cam, route, URL bộ lọc, API, quyền và công thức tiền hiện có. Không sửa backend hoặc dữ liệu vận hành.

## Các thay đổi

- Khung sidebar và cột nội dung tiếp tục dùng chung `--sidebar-width`. Thêm `min-width: 0` đúng phạm vi COD. Bảng cũ có nhiều cột và `nowrap` trên mọi ô; thay bằng cột có độ rộng xác định, nội dung mã/tên được xuống dòng. Không thêm `100vw` hoặc che tràn toàn trang bằng `overflow: hidden`.
- Bộ lọc ngày/bưu cục/Áp dụng/icon làm mới nằm cùng hàng desktop, điều khiển cao 38px; ngày giới hạn 170px. Bộ lọc thêm có số lượng, chip theo kết quả đã áp dụng và nút xóa. Làm mới giữ bộ lọc đã áp dụng; bản nháp chưa áp dụng không đổi nhãn kỳ hoặc số liệu.
- Mỗi trang có một tiêu đề và mô tả ngắn. Nút tạo phiên ở khu vực tiêu đề, theo quyền API. CSV là thao tác phụ.
- Thẻ tiền dùng ký hiệu ₫, 3–4 thẻ, có giải thích phạm vi. Chỉ số cần chú ý có giá trị dương mới được nhấn cam. Mọi tổng hợp tiếp tục lấy từ API; lỗi không trở thành số 0.
- Khoản thu có 7 cột; mã đơn/vận đơn chung một ô, nút sao chép có nhãn truy cập. Phiếu nộp có 6 cột; thông tin người xác nhận ở chi tiết.
- Đối soát có 7 cột. Ô tiền ghi riêng “Đã thu” và “Đã nộp”, không tạo chỉ số tổng hợp mới. Kỳ tối đa hai dòng; tooltip giải thích mốc kết thúc không bao gồm. Hiển thị thời gian Việt Nam `dd/MM/yyyy, HH:mm`; khoảng thời gian gửi API giữ nguyên.
- Chi tiết chia thông tin chung, tóm tắt tiền, thông tin xác nhận thực có và danh sách liên quan. Nhãn/giá trị thẳng hàng, tiền căn phải, có nút Đóng ở footer. Giữ xác nhận rõ số tiền/người nộp hoặc toàn bộ kỳ trước thao tác ghi tiền.
- CSS chỉ áp dụng dưới `.cod-page` hoặc `.cod-workspace`. Hàng thông thường khoảng 50px, mã/tên dài được xuống dòng. Bảng trên mobile có thể kéo ngang; toàn trang không kéo ngang. Bảng ngắn không có vùng cuộn dọc riêng.

## Tệp thay đổi

- `frontend/js/cod.js`: thành phần, bảng, bộ lọc, định dạng hiển thị, chi tiết và thao tác tiêu đề.
- `frontend/js/app.js`: mô tả và lớp phạm vi COD.
- `frontend/assets/css/styles.css`: CSS COD.
- `frontend/index.html`: phiên bản cache CSS/JS.
- `frontend/tests/cod-browser.cjs`, `frontend/tests/cod-checks.cjs`: kiểm tra UI và ảnh tại 1366/1920/390px, zoom 100%.

## Kiểm chứng

`npm.cmd test --prefix frontend`: **38/38 đạt**.

`npm.cmd run test:cod --prefix frontend`: **101 kiểm tra đạt, không có lỗi JavaScript**. Build backend phục vụ kiểm thử thành công, 0 cảnh báo/0 lỗi. Đã xác minh clipboard thật, menu mobile, và mã/tên dài ở 1366/1920/390px, zoom 100%.

Bộ tích hợp dùng SQL LocalDB GUID riêng, schema/seed của dự án, ASP.NET API thật và Edge headless. Kiểm tra cả đọc/ghi tiền, quyền/phạm vi bưu cục, số thập phân, chống nhấn trùng, xung đột 409, ngày Việt Nam, CSV, tab, phân trang, chi tiết/F5/Back, lỗi 403/500, trạng thái trống và hủy phản hồi cũ. Database kiểm thử được xóa sau chạy.

23 ảnh và [danh sách kết quả](cod/compact/cod-verification.json) nằm tại `docs/cod/compact`. Ví dụ: [Khoản thu 1366px](cod/compact/collections-1366.png), [Đối soát 1920px](cod/compact/reconciliations-1920.png), [Chi tiết mobile](cod/compact/reconciliation-detail-390.png), [Tên/mã dài 1366px](cod/compact/reconciliations-long-1366.png). Các ảnh `*-long-*` chỉ thay trường văn bản của phản hồi trong trình duyệt để kiểm tra mã/tên dài, không thay số tiền/trạng thái và không ghi vào dữ liệu vận hành.

API không cung cấp lịch sử sự kiện xác nhận đầy đủ; giao diện hiển thị người/thời điểm xác nhận và thời điểm khóa khi có, không tự dựng lịch sử.
