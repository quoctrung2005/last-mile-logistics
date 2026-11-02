# Quản lý kho — contract, thiếu sót và kiểm tra (cập nhật 08/10/2026)

Giữ HTML/CSS/JavaScript + Bootstrap và kiến trúc hiện tại. Không thay đổi đơn/COD trong database vận hành hoặc node_modules. Báo cáo mới: [inventory-ui-verification.md](inventory-ui-verification.md); lịch sử sửa response rỗng ngày 07/10: [warehouse-list-response-fix.md](warehouse-list-response-fix.md).

## Contract đã đối chiếu controller

`WarehousesController`:

- `GET /api/v1/warehouses` trả **array**, không phải `{items}`: id, code, name, branchId, branchName, address, activeLocationCount. Quyền KHO_XEM, kho/bưu cục đang hoạt động, scope theo tài khoản.
- `GET /api/v1/warehouses/{id}/locations` trả **array**: id, warehouseId, code, storageArea, rack, slot, isActive. Mặc định chỉ vị trí hoạt động. Cập nhật quản lý 09/10/2026: hỗ trợ `status=ACTIVE|INACTIVE|ALL`, `keyword` tìm mã/khu/kệ/ô; form nhập/chuyển/nhận hoàn giữ request mặc định ACTIVE. Xem [locations-ui-verification.md](locations-ui-verification.md).
- `GET /api/v1/warehouses/{id}/inventory?keyword=&locationId=&orderStatus=&page=1&pageSize=10` trả warehouseId, page, pageSize, totalItems, items. Item: orderId, orderCode, trackingNumber, warehouseId, locationId, locationCode, inventoryStatus, orderStatus, orderStatusName, weightKg, receivedAt, lastMovedAt. Chỉ tồn RECEIVED/STORED/ALLOCATED/RETURNED có kho trùng kho hiện tại đơn. Không có query orderId/status; dùng orderStatus chính xác.

`WarehouseInboundController`:

```text
POST /api/v1/warehouse-transactions/inbound
{orderId, warehouseId, locationId, notes}
```

Quyền KHO_NHAP. Đơn CONFIRMED/WAITING_INBOUND, chưa có kho hiện tại và chưa có bất kỳ bản ghi tồn kho; kho thuộc bưu cục đơn, vị trí hoạt động thuộc kho. Backend tự chuyển trạng thái và tạo giao dịch. Response 201: transactionId, transactionCode, orderId, warehouseId, locationId, orderStatus, inventoryStatus, message.

`WarehouseMoveController`:

```text
POST /api/v1/warehouse-transactions/move
{orderId, fromLocationId, toLocationId, notes}
```

Quyền KHO_KIEMKE. Tồn hiện tại RECEIVED/STORED/ALLOCATED/RETURNED, kho tồn trùng kho đơn; source khớp bản DB, đích hoạt động cùng kho và khác nguồn. Source mismatch → 409. Response 201: transactionId, transactionCode, orderId, warehouseId, fromLocationId, toLocationId, message. UI đọc tồn kho mới nhất, khớp orderId qua các trang tìm kiếm; không suy nguồn từ vị trí đang chọn ở header.

`WarehouseHandoverOrdersController`:

```text
GET /api/v1/warehouses/{id}/handover-orders
query: keyword, shipperId?, acceptedOnly=false, locationId?, assignmentStatus=PENDING|ACCEPTED, page=1, pageSize=10
```

Quyền KHO_XEM. Response warehouseId, warehouseName, page, pageSize, totalItems, items. Items gồm orderId, version, orderCode, trackingNumber, branchId, orderStatus, weightKg, codAmount, stockStatus, locationId, locationCode, receiverName/Phone, deliveryAddress, assignmentId/Status, shipperId/Name/Phone, employeeCode, vehicleId, vehicleType, licensePlate, tripId, assignedAt, acceptedAt, canHandover. Danh sách chỉ ASSIGNED, tồn STORED/ALLOCATED, vị trí hoạt động, phân công PENDING/ACCEPTED chưa kết thúc. Cập nhật 09/10/2026: `canHandover` kiểm tra ACCEPTED, shipper/xe và tải trọng/thể tích theo các điều kiện của POST outbound. POST vẫn kiểm tra lại trong transaction. UI gửi keyword/locationId/assignmentStatus lên server trước phân trang; acceptedOnly được giữ cho tương thích URL cũ. Kết quả kiểm tra mới: [outbound-ui-verification.md](outbound-ui-verification.md).

`WarehouseOutboundController`:

```text
POST /api/v1/warehouse-transactions/outbound
{orderId, warehouseId, assignmentId, fromLocationId, notes}
```

Quyền KHO_XUAT. ASSIGNED, đúng kho/nguồn/tồn; assignment thuộc đúng order, ACCEPTED và chưa kết thúc; shipper/xe đủ điều kiện, tải trọng/thể tích hợp lệ. Response 201: transactionId/Code, handoverId/Code, orderId, warehouseId, assignmentId, shipperId, vehicleId, orderStatus=HANDED_OVER, handoverStatus=PENDING, handedOverAt, message. Ba ID orderId/assignmentId/handoverId không hoán đổi. Một request xử lý một đơn. UI không gọi `/my/handovers/{id}/confirm` hay `/my/tasks/{id}/accept` bằng token quản lý.

`WarehouseReturnInController`:

```text
POST /api/v1/warehouse-transactions/return-in
{orderId, returnRequestId, warehouseId, locationId, condition, notes}
```

Quyền KHO_NHAP. Condition NORMAL/DAMAGED/OTHER; ghi chú ≤500 ký tự, bắt buộc với DAMAGED/OTHER. Đơn RETURNING, chưa có kho hiện tại; yêu cầu đúng đơn, loại RETURN, IN_PROGRESS, bưu cục hoàn trùng bưu cục gốc; kho/vị trí hợp lệ tại bưu cục đó; tồn cũ HANDED_OVER; không còn phân công đang hoạt động. Response 201: transactionId/Code, orderId, returnRequestId, warehouseId/Name, locationId/Code, orderStatus, stockStatus=RETURNED, requestStatus=COMPLETED, condition, receivedAt, version, message.

`WarehouseTransactionsController`:

- `GET /api/v1/warehouse-transactions?warehouseId=&type=&orderId=&page=&pageSize=&keyword=&fromDate=&toDate=`; type INBOUND/MOVE/OUTBOUND/RETURN_IN. Cập nhật 09/10: keyword tìm mã giao dịch/đơn/vận đơn; fromDate/toDate là ngày Việt Nam, lọc tại server trước phân trang. Response page/pageSize/totalItems/items; item id, transactionCode, warehouseId/Name, branchId, type, status, performedBy/Name, performedAt, notes, orderCount.
- `GET /api/v1/warehouse-transactions/{id}`: các trường thông tin giao dịch (thêm branchName) cộng items: orderId, orderCode, trackingNumber, fromLocationId/Code, toLocationId/Code, condition, notes.
- Quyền KHO_XEM, scope theo bưu cục. Trang lịch sử mặc định tất cả kho trong scope, filter loại/mã/ngày; tham số orderId cũ vẫn dùng được. Chi tiết mở modal chỉ đọc. [transactions-ui-verification.md](transactions-ui-verification.md).

Các ID phải lớn hơn 0; page 1–100000; pageSize 1–100; keyword ≤100. UI giới hạn ID nhập tay tới Number.MAX_SAFE_INTEGER để không làm tròn ID BIGINT trong JavaScript. API có thể hỗ trợ BIGINT lớn hơn; nếu cần miền này, nên đổi contract ID thành chuỗi.

## 1. ready-for-dispatch đã nối ngày 08/10/2026

OrderReadyForDispatchController đã có `POST /api/v1/orders/{id}/ready-for-dispatch`, không body, quyền KHO_NHAP. Controller kiểm tra DB hiện hành, bưu cục, IN_WAREHOUSE + STORED, kho/vị trí hoạt động, không có phân công/chuyến chưa kết thúc; thực hiện trong giao dịch và trả trạng thái/version mới.

UI đã nối route này, xác nhận trước khi gửi và tải lại tồn kho sau thành công/409. Đã kiểm tra success, request trùng trả 409 và thiếu/thu hồi quyền trả 403 trên database thử thật. Xem [báo cáo mới](inventory-ui-verification.md).

## 2. Danh sách yêu cầu hoàn đã bổ sung

Đã thêm `GET /api/v1/warehouses/{id}/return-requests`, kiểm tra tài khoản hoạt động, KHO_XEM + KHO_NHAP, kho/bưu cục hoạt động và phạm vi tài khoản. Chỉ RETURN/IN_PROGRESS, đơn RETURNING chưa có kho hiện tại, tồn HANDED_OVER, bưu cục nhận hoàn trùng bưu cục gốc/kho đã chọn, không còn phân công đang hoạt động. Query keyword/orderId/returnRequestId/page/pageSize; response warehouseId/Name, canReturnIn, page/pageSize/totalItems/items. Items có returnRequestId, orderId/orderCode/trackingNumber, branchId/Name, returnBranchId, orderStatus/Name, requestStatus, reason, requestedAt, weightKg, previousWarehouseId, stockStatus.

UI chọn yêu cầu từ danh sách, đọc lại đúng requestId/orderId trước mở form; đã bỏ ô nhập ID thủ công. Return-in vẫn kiểm tra toàn bộ điều kiện/quyền trong giao dịch khi ghi. Không dùng API shipper để giả lập bắt đầu hoàn hay nhận hàng.

API trả canReturnIn sau khi xác minh quyền KHO_XEM/KHO_NHAP. Capability chỉ phục vụ hiển thị; POST tiếp tục quyết định quyền và điều kiện hiện tại.

## 3. API quyền cá nhân đã bổ sung ngày 08/10/2026

`GET /api/v1/auth/permissions` dùng accountId từ JWT, trả `{accountId, permissions: string[]}` từ TaiKhoan/VaiTro/VaiTroQuyen/Quyen hiện hành. Không nhận ID tài khoản/vai trò khác; `/roles` tiếp tục giữ quyền quản trị riêng. Frontend dùng API mới để ẩn/hiện thao tác cho cả admin và nhân viên kho; backend POST vẫn quyết định quyền và scope.

API tồn kho hiện hỗ trợ thêm locationId (BIGINT > 0) và orderStatus (VARCHAR ≤40), áp dụng cả hai trước COUNT/OFFSET/FETCH. Các tham số được truyền qua SqlParameter. Contract pagination và items:[] khi rỗng được giữ.

UI có kiểm tra lại quyền khi lỗi đọc quyền/403 thao tác; refresh token không thay đổi.

## 4. Điều kiện outbound và kích thước hàng

`canHandover=true` chưa kiểm tra đầy đủ tải trọng/thể tích. POST outbound có thể trả 409 nếu xe yêu cầu thể tích nhưng hàng thiếu lengthCm/widthCm/heightCm. Form tạo/sửa đơn hiện tại và CreateOrderRequest không nhận các kích thước này, mặc dù chi tiết đơn hiển thị chúng. Không tự thêm field payload mà controller chưa hỗ trợ.

Đề xuất thống nhất DTO tạo/cập nhật hàng hóa và dữ liệu kích thước với kiểm tra outbound, hoặc làm rõ quy tắc nghiệp vụ cho hàng không có kích thước. Chưa chứng minh có lỗi 409 này trên dữ liệu thật; đây là điều kiện được đọc từ source. UI hiển thị message backend và không tự sửa dữ liệu để vượt kiểm tra.

## Lịch sử kiểm tra trước cập nhật 08/10/2026

- Đã đọc login/orders và tái sử dụng chi tiết đơn ở chế độ xem. Trước đây component không mở độc lập được từ kho; đã bổ sung API showDetail với vòng đời modal gắn màn hình kho. Khi đổi trang/kho/hết phiên, đóng modal và bỏ phản hồi cũ. Đăng xuất dọn màn hình kho ngay.
- Shared DOM/format tiền, ngày UTC → giờ VN, modal, thông báo, bảng và phân trang được tái sử dụng từ component đơn hàng. Không đưa API vào innerHTML, không log mật khẩu/token.
- `node --check` đã kiểm tra các JavaScript thay đổi. Không cài test/framework hoặc sửa node_modules.
- Edge headless kiểm tra bằng phản hồi API mô phỏng **riêng trong bộ nhớ**, chặn toàn bộ request API của trình duyệt kiểm tra: kho/vị trí/reset, tìm/phân trang, inbound, move với nguồn vừa tải và 409 không tự gửi lại, gửi trùng, outbound assignmentId khác orderId/handoverId, nhận hoàn/ghi chú condition, lịch sử/chi tiết, lỗi 400/403/404/409/422/kết nối, quyền chưa xác minh, refresh đồng thời/hết phiên. 5 thao tác POST mô phỏng, không gửi DB; không có lỗi JavaScript. Đã xem responsive 1440/820/390 px. Dữ liệu chạy bình thường luôn từ API thật. Công cụ mở browser ban đầu bị lỗi môi trường; sử dụng Edge headless thay thế. Công cụ kiểm tra và ảnh tạm được dọn, không để lại bộ test.
- Backend khởi động profile http ở 5038, frontend proxy ở 5500; `GET /api/database/check` qua proxy HTTP 200, đọc được 14 đơn. GET warehouses/warehouse-transactions/handover-orders không token HTTP 401.
- Ở lần triển khai trước chưa kiểm thử HTTP có token, nên bỏ sót response danh sách rỗng thiếu items. Lần sửa này đã dùng API và SQL Server thật trên database thử riêng để kiểm tra cả có dữ liệu/rỗng, quyền/phạm vi, bốn màn hình trên Edge, chọn yêu cầu hoàn bằng admin/nhân viên kho. Database thử đã xóa, đơn/COD vận hành không đổi. Xem `warehouse-list-response-fix.md`.
- Tại thời điểm kiểm tra cũ chưa có endpoint ready-for-dispatch/API quyền cá nhân. Cả hai đã được xác minh/nối trong cập nhật 08/10/2026 ở trên.
- Không Dijkstra/VRP, điều phối tự động hoặc hosting.
