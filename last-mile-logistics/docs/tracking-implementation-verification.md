# Theo dõi giao hàng — 17/10/2026

Đã triển khai `#/tracking` bằng HTML/CSS/JavaScript thuần và Bootstrap, thay placeholder. Trang chỉ đọc dữ liệu: không nhận nhiệm vụ, xác nhận lấy hàng/giao hàng, phân công, tạo chuyến hoặc cập nhật trạng thái.

## API và phạm vi quyền

Đọc trước khi triển khai: router, API client, `OrdersController`, `DispatchOrdersController`, `DispatchAssignmentsController`, `DispatchShippersController`, `TripsController`, `ShippersController`, `MyShipperStatusController`, controller giao thất bại/thành công và đọc bằng chứng, schema phân công/lần giao/lịch sử trạng thái.

- **Tái sử dụng `GET /api/v1/orders`**: tìm mã đơn/vận đơn, tổng số kết quả và phân trang phía server. Bổ sung tùy chọn `branchId`, `shipperId`, `statusGroup`, `fromDate`, `toDate`; thêm địa chỉ giao, shipper của phân công hiện tại và `updatedAt` vào mỗi dòng. Giữ cách sắp xếp cũ cho các lời gọi hiện hữu không dùng nhóm trạng thái.
- **Tái sử dụng `GET /api/v1/orders/{id}`**: thông tin đơn, điểm nhận/giao và toàn bộ `statusHistory` hiện có. Với `tracking=true`, bổ sung `tracking.currentAssignment` (phân công còn hiệu lực, xe, chuyến, tọa độ gần nhất/thời điểm GPS) và `tracking.attempts` (từng lần giao, kết quả, người ghi nhận, lý do, ghi chú, dự kiến giao lại).
- **Bổ sung duy nhất `GET /api/v1/orders/tracking-options`**: tên bưu cục/shipper/trạng thái cần cho bộ lọc theo dõi; không phụ thuộc quyền quản lý danh mục hoặc tài khoản. Không tạo API danh sách/chi tiết tracking trùng với Orders. `order-form/options` phục vụ tạo/cập nhật đơn, không có shipper/trạng thái theo dõi; `dispatch/shippers` là danh sách ứng viên cho một đơn, không phù hợp làm bộ lọc lịch sử.
- **Tái sử dụng `GET /api/v1/orders/{id}/evidence`**: metadata bằng chứng có phân trang. Ảnh tải qua `/evidence/{evidenceId}/file` bằng API client có xác thực, hỗ trợ refresh token, lỗi JSON và hủy tải khi rời trang. Không đưa token vào URL hoặc dùng đường dẫn lưu trữ trực tiếp.

Route và dữ liệu theo dõi chi tiết/options yêu cầu hai quyền đang có: `DONHANG_XEM` và `DIEUPHOI_GIAMSAT`. API kiểm tra tài khoản/vai trò đang hoạt động và quyền trong database. Orders luôn kiểm tra `DONHANG_XEM`; tài khoản ngoài Admin chỉ đọc đơn thuộc bưu cục của mình. Truy vấn sai bưu cục bị từ chối; ID ngoài phạm vi trả 404. Không gọi API tra cứu công khai, không sửa quyền hoặc schema.

Shipper lọc theo **phân công hiện tại còn hiệu lực**, không phải tất cả shipper đã giao đơn trong quá khứ. Bộ lọc ngày dùng lần cập nhật đơn gần nhất (`COALESCE(updatedAt, createdAt)`), gồm cả ngày đầu/cuối theo UTC+7. GPS có thời điểm riêng, không thay thế ngày cập nhật đơn.

Nhóm trạng thái ánh xạ tại server:

| Nhóm | Mã backend |
|---|---|
| Đang thực hiện | `ASSIGNED`, `HANDED_OVER`, `EN_ROUTE_PICKUP`, `PICKED_UP`, `IN_DELIVERY` |
| Cần xử lý | `FAILED`, `RETRY_WAITING`, `RETURNING` |
| Đã kết thúc | `DELIVERED`, `COMPLETED`, `RETURNED`, `CANCELLED` |

Mọi trạng thái bỏ điều kiện nhóm; từng trạng thái cũng có thể được chọn riêng từ danh mục backend. Không lọc một trang ở frontend rồi coi đó là toàn bộ tập kết quả.

## Giao diện và cập nhật

- Desktop 38% danh sách / 62% chi tiết; mobile danh sách trước, chọn đơn mở chi tiết và có nút quay lại. Không có bảng thống kê hoặc panel placeholder lớn.
- Mã vận đơn, người nhận/địa chỉ, shipper hiện tại, trạng thái có chữ và lần cập nhật. Bộ lọc áp dụng khi tìm kiếm; bản nháp không đổi nhãn kết quả khi làm mới.
- Chi tiết có thông tin người nhận theo quyền xem đơn, phân công/xe/chuyến hiện tại, “Dự kiến giao theo đơn”, liên kết router sang chi tiết đơn và đường quay lại giữ bộ lọc/đơn/tab.
- Timeline dùng chính lịch sử trạng thái; các lần giao là bản ghi riêng, giữ cả thất bại trước. Không suy ra bước hoàn thành.
- Thời gian SQL DATETIME2 được hiểu là UTC; chuỗi đã có timezone giữ nguyên offset trước khi định dạng sang giờ Việt Nam. Không cộng 7 giờ hai lần.
- Chưa có realtime trong dự án. Dùng timer 30 giây sau khi hoàn tất lượt tải trước, nút bật/tắt và thời điểm tải gần nhất. Tạm dừng khi ẩn tab; abort controller/epoch chặn response cũ; giữ đơn đã chọn kể cả nó không còn trên trang danh sách đang xem. Giữ instance bản đồ và vị trí cuộn; dọn timer, listener, request, blob URL và bản đồ khi rời trang.

## Bản đồ

Không tìm thấy thư viện bản đồ sẵn trong frontend. Bổ sung [Leaflet 1.9.4 theo tài liệu chính thức](https://leafletjs.com/examples/quick-start/), lưu JS/CSS/LICENSE tại `frontend/assets/vendor/leaflet` và kiểm tra SHA-256 khớp các mã SRI công bố. Không phụ thuộc CDN để tải thư viện.

Hiển thị tọa độ nhận/giao hợp lệ và vị trí shipper của phân công hiện tại; chú giải màu có chữ, tooltip và attribution Leaflet/OpenStreetMap. Nền bản đồ lấy từ OpenStreetMap, cần kết nối mạng. Thiếu thư viện/nền bản đồ/tọa độ không làm mất trạng thái hoặc lịch sử. Không tạo tọa độ mặc định cho đơn thiếu dữ liệu.

Vị trí shipper là “gần nhất”, có thời điểm cập nhật; quá 5 phút được đánh dấu cũ. Thiếu thời điểm hoặc timestamp bất thường được nêu rõ. Không vẽ đường đi thực tế, marker chuyển động giả, tuyến đề xuất hoặc thuật toán định tuyến/VRP/Dijkstra. `expectedDeliveryAt` là dự kiến trên đơn, không phải ETA tính theo đường giao thông.

## Tệp thay đổi

- `frontend/js/tracking.js`, `frontend/assets/css/tracking.css`: trang theo dõi và CSS riêng dưới `.tracking-page`/`.tracking-workspace`.
- `frontend/js/router.js`, `frontend/js/app.js`, `frontend/index.html`: route/quyền, lifecycle, mô tả, stylesheet/script.
- `frontend/js/api.js`: đọc blob ảnh qua luồng xác thực và hủy request hiện có.
- `frontend/assets/vendor/leaflet/{leaflet.js,leaflet.css,LICENSE}`.
- `backend/LastMile/LastMile.Api/Controllers/OrdersController.cs`, `OrdersTracking.cs`: các phần đọc dữ liệu tối thiểu nêu trên.
- `frontend/package.json`, `frontend/tests/tracking-browser.cjs`, `tracking-checks.cjs`, `tracking-fixture.ps1`, `tracking.test.cjs`, `router.test.cjs`, `auth.test.cjs`: lệnh chạy và kiểm thử.

## Kiểm tra

`npm.cmd test --prefix frontend`: **43 bài đạt**, bao gồm kiểm tra múi giờ/GPS, URL/quyền tracking, refresh token khi đọc ảnh và hủy tải ảnh sau khi đã nhận header.

`npm.cmd run test:tracking --prefix frontend`: **48 kiểm tra đạt, 0 lỗi JavaScript**. Build backend phục vụ kiểm thử đạt, 0 cảnh báo/0 lỗi. Đã kiểm tra tìm mã, lọc bưu cục/shipper/trạng thái, phân trang, chọn đơn, Back từ chi tiết đơn, nhiều lần giao, thiếu/cũ GPS, 30 giây polling, bật/tắt tự cập nhật, bảo toàn map/scroll và hủy response cũ. Tình huống ẩn tab được kiểm tra bằng cách phát `visibilitychange` với `document.hidden` giả lập, chờ 31 giây và xác nhận không có request.

Bộ tích hợp dùng LocalDB GUID riêng, schema/seed thật, API ASP.NET thật, proxy và Edge headless. Ảnh tại `docs/tracking`, zoom 100%, độ rộng 1366/1920/390px. Fixture chỉ thêm lần giao thất bại và thay GPS trong database kiểm thử; không sửa dữ liệu vận hành. Database kiểm thử được xóa sau mỗi lượt chạy.

Có **9 ảnh**: [Desktop 1366px](tracking/tracking-list-1366.png), [Desktop 1920px](tracking/tracking-list-1920.png), [Danh sách mobile](tracking/tracking-list-390.png), [Chi tiết mobile](tracking/tracking-mobile-detail-390.png), [Lịch sử nhiều lần giao](tracking/tracking-history-1366.png), [Thiếu GPS](tracking/tracking-no-gps-1366.png), [GPS cũ](tracking/tracking-old-gps-1920.png), [Tài khoản bưu cục](tracking/tracking-branch-account-1366.png). [Danh sách 48 kiểm tra](tracking/tracking-verification.json).

## Giới hạn hiện có

Backend chưa có realtime hoặc API ETA/định tuyến giao thông. Trang dùng polling và các tọa độ được lưu, không mô tả thành dữ liệu trực tiếp. Đã kiểm tra API metadata bằng chứng/phạm vi quyền và unit test blob/refresh/hủy tải; chưa kiểm tra một tệp ảnh vận hành thực tế. Ảnh bằng chứng chỉ hiển thị nếu API có quyền và tệp tương ứng còn tồn tại; lỗi tải tệp được báo riêng. Không bổ sung màn hình xử lý giao lại/hoàn hàng chưa được triển khai.
