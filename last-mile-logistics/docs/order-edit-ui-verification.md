# Cập nhật API sửa từ chi tiết đơn — 09/10/2026

## Contract hiện tại

`GET /api/v1/orders/{id}` trong OrdersController đã trả version Base64 và branchId/senderId/receiverId/serviceId. pickupAddressId/deliveryAddressId có thể null; requiresAddressSelection báo cần chọn lại địa chỉ. Không lấy deliveryPoints[].id làm ID địa chỉ khách hàng.

`PUT /api/v1/orders/{id}` trong OrderUpdateController vẫn yêu cầu đầy đủ CreateOrderRequest cộng expectedVersion. Response thành công trả id, status, version, weightKg, shippingFee, message. Chỉ NEW, có DONHANG_CAPNHAT, đúng bưu cục và version hiện tại mới được sửa.

## File sửa

- frontend/js/orders.js: không coi thiếu ID địa chỉ là thiếu toàn bộ dữ liệu sửa; NEW có quyền mở form. Thông báo cần chọn lại nếu API không xác định địa chỉ. Khách hàng/dịch vụ/bưu cục, hàng hóa và các trường đang lưu được điền từ response. Hiển thị snapshot địa chỉ hiện tại để đối chiếu; không tự chọn địa chỉ mặc định khi địa chỉ cũ chưa xác định. ID hợp lệ được chọn đúng; địa chỉ cũ không còn hoạt động yêu cầu chọn khác. Form khóa trong thời gian tải dữ liệu khách hàng. Giữ PUT/expectedVersion, chống bấm hai lần, quay về đúng chi tiết sau thành công và chặn gửi lại sau 409. Không hiển thị báo giá yêu cầu quyền tạo đối với người chỉ có quyền cập nhật.
- backend/LastMile/LastMile.Api/Controllers/OrderFormController.cs: sửa quyền đọc dữ liệu form từ chỉ DONHANG_TAO thành DONHANG_TAO hoặc DONHANG_CAPNHAT, giữ kiểm tra tài khoản và scope bưu cục. Không tạo route trùng, không sửa điều kiện NEW/version hay quyền PUT.
- frontend/tests/order-edit-browser.cjs: test headless cô lập trên server frontend có sẵn; không PUT tới API thật.
- docs/orders-api-gaps.md: ghi cập nhật, giữ nội dung cũ như lịch sử.

OrdersController do người dùng vừa sửa được giữ nguyên.

## Kiểm tra

- node --check frontend/js/orders.js: đạt.
- npm.cmd test --prefix frontend: 20 test xác thực/router đạt.
- Build backend vào .order-edit-check/bin: 0 warning/error, không ghi đè binary hoặc khởi động server trùng cổng.
- Đọc SQL GET detail mới trên LocalDB với ID 1/2: có các ID khách hàng/dịch vụ, version hợp lệ, pickupAddressId=null, requiresAddressSelection=true. Hai đơn đều COMPLETED; UI vẫn không cho sửa các trạng thái này.
- 18 kiểm tra browser đạt: NEW thiếu địa chỉ vẫn mở form, khóa khi tải, người có quyền cập nhật nhưng không có quyền tạo, giữ snapshot, không tự chọn mặc định, thiếu địa chỉ chặn PUT, địa chỉ xác định được điền đúng, payload PUT đủ field/expectedVersion và gửi một lần, thành công về đúng chi tiết, 409 giữ form và không retry, COMPLETED không sửa, thiếu version vẫn khóa, form vừa viewport 1366/390 px. Không có error/unhandledrejection/DevTools exception.

[Kết quả browser](order-edit-browser-verification.json). Browser dùng dữ liệu chi tiết đọc thật để tạo fixture NEW chỉ trong tab kiểm thử; response PUT được mô phỏng. Không thay đổi trạng thái hay dữ liệu đơn thật.

Chưa kiểm thử PUT bằng JWT thật, quyền BRANCH_MANAGER qua HTTP thật hoặc 409 transaction thực tế. Backend đang chạy không được restart; cần chạy lại backend để nhận thay đổi quyền đọc dữ liệu form. Không tìm thấy AGENTS.md trong workspace.

## Đối chiếu ảnh lỗi của đơn 16

Đã đọc đúng mã đơn trong ảnh bằng truy vấn GetOrder hiện tại: ID 16, NEW, branchId=1, senderId=1, receiverId=10, serviceId=2, version Base64 hợp lệ. pickupAddressId=null, deliveryAddressId=10, requiresAddressSelection=true. Những trường bắt buộc để mở sửa đã đủ; vị trí địa chỉ lấy cần người dùng chọn lại.

Frontend tại http://localhost:5500 phục vụ guard mới. DLL backend hiện có chứa các field chi tiết mới. Không truy cập được phiên browser người dùng do công cụ UI lỗi sandbox, nên chưa đọc HTTP response trong phiên đăng nhập của ảnh. Không kết luận chắc chắn response phiên đó giống truy vấn SQL.

Đã thêm query phiên bản cho orders.js trong index.html, thay cảnh báo chung bằng tên dữ liệu còn thiếu và nút Tải lại chi tiết. Chạy lại 18 kiểm tra browser tại localhost:5500 với dữ liệu đọc của đơn 16 và PUT mô phỏng cô lập: đạt, không lỗi JavaScript. Báo cáo JSON hiện phản ánh lần chạy này. Cần tải lại trang bằng Ctrl+F5 để trang đang mở nhận script mới.

read-order-detail.ps1 hỗ trợ tham số OrderCode/OrderIds cho lần đọc chính xác; mặc định vẫn đọc ID 1/2. Không thay đổi đơn 16 hoặc token của người dùng.
