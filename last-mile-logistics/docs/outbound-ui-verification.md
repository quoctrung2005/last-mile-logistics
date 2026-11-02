# Xuất kho / bàn giao — kiểm tra ngày 09/10/2026

## Thay đổi

- `frontend/js/warehouse.js`: một vùng lọc, một bảng; bỏ tiêu đề nội bộ và các bảng tồn kho/lịch sử ghép phía dưới. Vị trí mặc định “Tất cả vị trí”, Lọc/Enter, Xóa bộ lọc giữ kho, Làm mới danh sách và Tải lại danh mục kho riêng biệt. Bộ lọc gửi lên API, không lọc một trang ở client. Đổi kho reset vị trí/trang; AbortController + epoch + sequence ngăn phản hồi cũ ghi đè.
- `frontend/js/app.js`, `frontend/assets/css/styles.css`: một tiêu đề ở shell, mô tả đúng yêu cầu, giao diện trắng cam, bảng cuộn trong card; vùng rỗng không có min-height lớn.
- Bảng: mã đơn/vận đơn có ellipsis, title/aria-label chứa mã đầy đủ và nút sao chép; nếu clipboard không dùng được thì mở mã đầy đủ để sao chép thủ công. Vị trí, shipper, loại xe/biển số, badge tiếng Việt, khối lượng, Chi tiết/Bàn giao. Có số dòng và phân trang cuối bảng.
- Bàn giao bị khóa với PENDING, đơn không ASSIGNED, tồn không STORED/ALLOCATED hoặc thiếu vị trí, `canHandover=false`, thiếu quyền. Hiển thị lý do bằng chữ. Không có thao tác thay shipper nhận nhiệm vụ hoặc xác nhận nhận hàng.
- Modal đọc lại đúng orderId + assignmentId, dùng locationId tồn kho mới nhất làm fromLocationId cố định, không lấy vị trí nguồn từ bộ lọc. Gửi một lần `{orderId, assignmentId, warehouseId, fromLocationId, notes}` đến route outbound hiện có. Nút Hủy/Xác nhận; khóa form và nút đóng modal khi đang gửi. Thành công đóng, thông báo chờ shipper xác nhận và tải lại. 409 khóa thao tác, tải lại, không tự POST lại.
- `WarehouseHandoverOrdersController.cs`: thêm locationId, assignmentStatus có validation vào GET hiện có; lọc trước COUNT/OFFSET/FETCH. Thêm vehicleType. Bổ sung điều kiện tải trọng/thể tích vào canHandover giống POST, giữ nguyên quy tắc và transaction của WarehouseOutboundController.
- `frontend/js/router.js`: lưu/khôi phục bộ lọc mới và giữ đường quay lại từ chi tiết; tương thích acceptedOnly cũ. Giữ nguyên ApiClient, JWT và refresh token.

## Lỗi đã xác minh trước sửa

Tiêu đề trang, card và danh sách bị lặp; trang ghép ba bảng và có nhiều lớp khung. Vị trí hiển thị như một lựa chọn thao tác thay vì “Tất cả vị trí”, chưa gửi bộ lọc vị trí lên API bàn giao. API chưa có bộ lọc PENDING riêng; bảng thiếu khối lượng, mã dài chưa có cách sao chép. Nút bàn giao chưa tham gia khóa pendingWrite và modal có thêm bước xác nhận trung gian. Vùng rỗng kế thừa chiều cao tối thiểu lớn. Cờ canHandover ở GET chưa kiểm tra tải trọng/thể tích như POST.

## Kết quả kiểm tra

- `node --check` các file JavaScript đã sửa: đạt.
- `npm.cmd test --prefix frontend`: 20 test xác thực/router đạt, gồm query bàn giao mới và đường quay lại chi tiết. Các test ApiClient xác nhận 403, 409, 500, lỗi mạng không xóa phiên; refresh token vẫn hoạt động.
- `dotnet build ... --no-restore -p:OutputPath=.../.outbound-check/bin/ -p:UseAppHost=false`: thành công, 0 warning/error. Build ra thư mục riêng để không ghi đè binary của server đang chạy.
- `read-outbound-data.ps1`: chạy SQL lấy từ controller mới trên LocalDB hiện có, chỉ đọc. Cả 4 kho đều totalItems=0/items=[]. Đã kiểm tra bộ lọc PENDING/ACCEPTED, từng vị trí, keyword không khớp và pageSize=1; COUNT/items khớp dữ liệu hiện tại. SQL mới gồm các điều kiện capacity thực thi được.
- `outbound-browser.cjs`: dùng server 5500 có sẵn, Edge headless với profile riêng. Không khởi động API/frontend trùng cổng. Adapter xác thực/transport chỉ tồn tại trong tab kiểm thử, không sửa index.html hoặc app runtime. Không lưu JWT, mật khẩu, connection string hay payload đơn thật vào báo cáo.
- Ảnh desktop/mobile dùng dữ liệu rỗng thật từ truy vấn LocalDB; ở 1366/768/390 px, pageWidth bằng viewportWidth, vùng rỗng cao 85 px. Đã xem ảnh để kiểm tra bố cục.
- 37 kiểm tra browser đạt. Tình huống có dòng dùng fixture contract trong tab headless để kiểm tra lọc/Enter, phân trang/số dòng, sao chép dự phòng, chi tiết đúng ID (đọc đơn thật ID 1), PENDING và các lý do khóa, modal đọc nguồn tồn mới, chống mở/gửi hai lần, thành công, 409 không retry, phân công thay đổi, Hủy/Đóng/Escape, 403/500/lỗi mạng và thử lại, phản hồi cũ sau đổi kho, listener chỉ chạy một lần sau mount lại. Bảng có dòng cuộn trong card ở 1366/390 px. Không phát sinh error/unhandledrejection/DevTools exception trong các tình huống hoàn tất.

Chi tiết số kiểm tra và metrics: [outbound-browser-verification.json](outbound-browser-verification.json). Ảnh: [desktop](outbound-1366.png), [tablet](outbound-768.png), [mobile](outbound-390.png).

## Chưa kiểm thử thực tế

- Chưa POST bàn giao bằng JWT thật hoặc xác nhận nhận hàng bằng tài khoản shipper. Dữ liệu hiện tại không có đơn PENDING/ACCEPTED phù hợp, chưa có ID đơn thử nghiệm được chỉ định. Không tạo hay sửa dữ liệu để làm xuất hiện đơn.
- Chưa kiểm tra tải trọng/thể tích với đơn đủ điều kiện thực tế, transaction đồng thời hoặc 409 thật trên database. Thành công/409 và khóa nút đã kiểm tra bằng phản hồi fixture cô lập.
- Backend đang chạy không được restart. Cần nạp lại bản backend đã sửa để HTTP API hỗ trợ locationId/assignmentStatus và vehicleType; SQL mới đã kiểm tra trực tiếp, chưa kiểm tra HTTP mới bằng phiên thật.
- Chưa thử quyền clipboard thực tế trên thiết bị người dùng; đã kiểm tra hiển thị mã đầy đủ khi clipboard bị từ chối.

Không tìm thấy AGENTS.md trong workspace/dự án hoặc các thư mục cha đã kiểm tra. Không có Git repository tại đường dẫn dự án nên không có git diff/status để báo cáo.
