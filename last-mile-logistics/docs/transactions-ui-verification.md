# Lịch sử giao dịch kho — cập nhật 09/10/2026

## File đã sửa

- `frontend/js/transactions.js` mới: trang tra cứu chỉ đọc, bộ lọc kho/loại/keyword/từ ngày/đến ngày, Tìm kiếm/Xóa bộ lọc, phân trang/số dòng/tổng giao dịch và modal chi tiết. Mặc định xem tất cả kho trong phạm vi. Không có dropdown vị trí hoặc ô ID đơn; URL orderId cũ vẫn được hỗ trợ và có thông báo đang xem lịch sử của đơn được chọn.
- `frontend/js/warehouse.js`: chuyển route lịch sử/chi tiết giao dịch sang module mới; dọn module/modal khi rời trang. Giữ các API nghiệp vụ kho và lịch sử của từng đơn trong các màn hình khác.
- `frontend/js/app.js`, `frontend/assets/css/styles.css`, `frontend/index.html`: một tiêu đề/mô tả/Làm mới, filter gọn, CSS riêng transactions-workspace/card/dialog, bảng 8 cột, thao tác bám mép phải, mobile cuộn ngang, modal tối đa 1000px và cuộn nội dung dài. Asset có phiên bản mới.
- `frontend/js/router.js`: thêm keyword/fromDate/toDate cho route lịch sử và route chi tiết cũ, kiểm tra ngày ISO hợp lệ và thứ tự khoảng ngày, giữ các query cũ và đường quay lại từ chi tiết đơn.
- `backend/LastMile/LastMile.Api/Controllers/WarehouseTransactionsController.cs`: mở rộng danh sách hiện có, thêm branchName vào chi tiết; không thêm endpoint hoặc thao tác ghi.
- Test: `frontend/tests/read-transaction-data.ps1`, `transactions-browser.cjs` mới và bổ sung `router.test.cjs`.

## API

```text
GET /api/v1/warehouse-transactions
  warehouseId?, type?, orderId?, page=1, pageSize=10,
  keyword? (<=100), fromDate? (yyyy-MM-dd), toDate? (yyyy-MM-dd)
GET /api/v1/warehouse-transactions/{id}
```

Giữ warehouseId/type/orderId/page/pageSize cũ. Không chọn warehouseId vẫn xem được tất cả kho trong scope tài khoản, bao gồm lịch sử các kho đã ngừng hoạt động. Dropdown danh mục kho vẫn dùng GET warehouses hiện có (kho hoạt động); liên kết lịch sử có warehouseId cũ vẫn được giữ và kiểm tra scope bởi API giao dịch.

Keyword tìm literal trong mã giao dịch hoặc EXISTS chi tiết giao dịch nối DonHang để tìm mã đơn/vận đơn. EXISTS tránh nhân bản giao dịch nhiều đơn. Kho, loại, orderId, keyword và khoảng thời gian đều lọc trước COUNT/OFFSET/FETCH; ORDER BY performedAt DESC, id DESC. GET chi tiết có id, mã/loại/trạng thái, kho/bưu cục (branchName mới), người/thời gian/ghi chú và items theo response thực tế. UI dùng đúng items[].orderId để mở đơn, không dùng transaction id.

Backend giữ quyền KHO_XEM, tài khoản/vai trò hoạt động và scope bưu cục. Thiếu DONHANG_XEM thì modal vẫn đọc giao dịch nhưng mã đơn không có nút mở trang đơn. Không thêm nút sửa/xóa/hủy/đảo giao dịch và không thay đổi tồn kho/trạng thái đơn khi tra cứu.

## Thời gian

Schema GiaoDichKho.ThoiGianThucHien là DATETIME2 và lưu UTC bằng SYSUTCDATETIME. FOR JSON trả thời gian không có offset; response này được giữ nguyên để tương thích. UI dùng LogisticsUI.date hiện có: chỉ thêm Z khi chưa có offset, sau đó Intl.DateTimeFormat với Asia/Ho_Chi_Minh.

fromDate/toDate là ngày Việt Nam. Backend chuyển đầu ngày sang UTC bằng trừ 7 giờ, lọc >= đầu từ ngày và < đầu ngày tiếp sau đến ngày. Đến ngày bao gồm cả ngày. Không cộng thêm múi giờ ở frontend. Khoảng ngày đảo ngược bị chặn frontend/router và trả 400 ở backend; ngày vượt phạm vi DateTime trả 400.

## Kiểm tra đã chạy

- node --check module JS sửa: đạt. Build backend ra .transactions-check/bin: 0 warning/error, không ghi đè binary đang chạy.
- 22 test xác thực/router đạt, gồm query lịch sử mới, ngày không hợp lệ/đảo ngược, tham số cũ và đường quay lại từ đơn. Giữ nguyên ApiClient/JWT/refresh token.
- **18 kiểm tra SQL chỉ đọc trên LocalDB**: 9 giao dịch hiện có; thứ tự mới nhất, chi tiết và số đơn khớp; INBOUND=4, MOVE=2, OUTBOUND=3, RETURN_IN=0; tìm theo mã giao dịch/đơn/vận đơn; COUNT đúng với pageSize=1; khoảng ngày Việt Nam và hai biên inclusive/exclusive; orderId cũ; trang 2; tìm không khớp trả items=[]; scope bưu cục; không đọc được chi tiết ngoài bưu cục; tài khoản không hợp lệ hoặc không có KHO_XEM không có scope đọc.
- **43 kiểm tra browser**: một title/refresh; tất cả kho; đúng 8 cột; giờ UTC/offset không chuyển hai lần; 3 kiểu tìm kiếm; Enter; trạng thái rỗng gọn/ẩn phân trang; xóa bộ lọc tải lại; 4 loại; ngày; chặn ngày đảo; pageSize=1/trang 2 đúng bản ghi; reset page khi đổi bộ lọc; một modal/đúng transaction id/bưu cục/nguồn-đích không áp dụng là —; không có thao tác ghi; mở đúng orderId và giữ đường quay lại; retry lỗi chi tiết; link transaction-detail cũ; response cũ không ghi đè; 401/403/400/409/500/mạng không bị đồng nhất với hết phiên; thiếu quyền xem lịch sử/mở đơn; toolbar/listener dọn sau route; modal dài cuộn và Escape đóng sạch.
- 1366/768/390px không tràn ngang toàn trang. Bảng bắt đầu khoảng y=333px trên desktop, 347px tablet, 565px mobile. Cột thao tác nằm trong khung khi cuộn. Modal nhiều đơn được kiểm tra ở 390x600px và cuộn trong viewport. Đã xem ảnh để kiểm tra bố cục.
- Hồi quy: 34 kiểm tra vị trí lưu kho, 42 kiểm tra nhập hàng hoàn và 37 kiểm tra xuất kho đều đạt sau thay đổi vòng đời module/router/CSS.

Ảnh từ **bản ghi thật**: [desktop](transactions-1366.png), [tablet](transactions-768.png), [mobile](transactions-390.png), [modal nhiều đơn](transactions-detail-390.png). [Metrics/checks](transactions-browser-verification.json).

## Giới hạn

Không tạo dữ liệu giả hay sửa database. Mọi record bảng/chi tiết/đơn trong browser QA lấy từ truy vấn controller thật qua LocalDB và chỉ chuyển trong bộ nhớ; không lưu payload đơn/token/connection string vào báo cáo. Browser dùng transport/xác thực/lỗi mô phỏng cô lập để kiểm tra UI, không gửi thao tác ghi. Chưa kiểm tra HTTP đã rebuild bằng JWT của phiên người dùng; quyền và scope đã kiểm tra bằng SQL thật và UI thiếu quyền.

Dữ liệu hiện tại chưa có RETURN_IN, nên đã kiểm tra bộ lọc này trả rỗng đúng, chưa kiểm tra chi tiết một giao dịch nhập hàng hoàn thật. Backend đang chạy không được restart và không có server trùng cổng. Cần chạy lại backend để nạp keyword/fromDate/toDate/branchName mới, rồi Ctrl+F5 frontend. Không tìm thấy AGENTS.md trong workspace/thư mục cha đã kiểm tra.
