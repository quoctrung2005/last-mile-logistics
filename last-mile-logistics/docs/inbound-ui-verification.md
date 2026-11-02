# Nhập kho — kiểm tra ngày 09/10/2026

## Đối chiếu và thay đổi

Đã đọc frontend (warehouse/orders/router/app/api/auth, CSS, index, proxy), WarehouseInboundController, OrdersController và WarehousesController trước sửa. Không có AGENTS.md trong dự án/thư mục cha đã kiểm tra; hướng dẫn toàn cục trống. Giữ JavaScript/HTML/CSS thuần + Bootstrap, trắng cam, API client/JWT/refresh hiện hữu, không sửa node_modules hay thời hạn token.

Màn hình `#/warehouse/inbound` dùng module InboundPage riêng, thay nhánh candidateList cũ. app chỉ mount một module; WarehousePage cũng chuyển tiếp mode nhập kho tới cùng module nếu được gọi trực tiếp. Bỏ candidateList cũ. Các màn hình nhập hoàn/xuất/tồn kho khác giữ module kho hiện hữu.

`GET /api/v1/orders` bổ sung query tùy chọn `warehouseId`, `inboundOnly` (mặc định false): kiểm tra kho/bưu cục hoạt động, scope tài khoản; khi inboundOnly cần kho, chỉ CONFIRMED/WAITING_INBOUND, không kho hiện tại và không có dòng TonKhoDonHang. Cùng predicate áp dụng trước đếm tổng và phân trang; không lọc riêng một page tại frontend. Không thêm endpoint trùng. Request API cũ không có query mới giữ hành vi cũ. Frontend kiểm tra schema, ID, branch, trạng thái, page/pageSize/totalItems và ID trùng, không tự thay dữ liệu lỗi bằng mảng rỗng.

GET warehouses/locations dùng COALESCE cho kết quả FOR JSON PATH rỗng: trả `[]` thật khi không có dòng, sửa lỗi scalar DBNull → string đã từng thấy. POST `/api/v1/warehouse-transactions/inbound` và DTO không thay đổi; controller hiện hữu vẫn kiểm tra KHO_NHAP, tài khoản/vai trò hoạt động, scope, trạng thái, tồn kho, kho/vị trí hoạt động và khóa giao dịch SQL. Payload dùng `orderId`, `warehouseId`, `locationId`, `notes`.

## Bảng kiểm tra

| Nút/chức năng | Lỗi đã xác minh | Cách sửa | Kết quả kiểm tra |
| --- | --- | --- | --- |
| Bố cục | H1 Nhập kho lặp H2, mô tả chung; ba bảng/khung lồng làm đơn xuất hiện muộn | Một H1, mô tả yêu cầu, một card/một bảng, filter gọn | Đạt DOM và QA ảnh desktop/390px |
| Làm mới kho | loadWarehouses gọi clearScope làm mất vị trí, reset bộ lọc/trang, tải lại nhiều bảng | Chỉ đọc danh mục kho/vị trí; giữ ID/selection/page/filter còn hợp lệ | Đạt: đúng 1 GET warehouses + 1 GET locations, không GET orders |
| Làm mới danh sách | Nút tải lại rải trên từng bảng, không phân biệt với tải danh mục | Nút riêng, lấy trường lọc hiện tại; giữ trang nếu filter không đổi | Đạt: đúng 1 GET orders, không GET danh mục |
| Chọn/đổi kho | Candidate query không gửi kho/bưu cục; ADMIN thấy đơn bưu cục khác | warehouseId + inboundOnly lọc tại SQL; đổi kho xóa vị trí và về trang 1 | Đạt dữ liệu/scope thật; đổi nhanh với response cũ trì hoãn |
| Chọn vị trí | Nút Chọn nhập kho vẫn mở khi chưa chọn vị trí ở trang; catalog refresh mất lựa chọn | Khóa nhập khi vị trí chưa hợp lệ; reread active positions khi mở modal, kiểm tra membership | Đạt: vị trí trống và vị trí bị thu hồi không gửi POST |
| Lọc và Enter | Submit/keyword/status đã được hỗ trợ nhưng chưa gắn đúng scope/eligibility | Dùng một submit cho Lọc/Enter; gửi mã tiếng Anh, hiển thị tiếng Việt | Đạt: mã đơn, mã vận đơn, trạng thái; mỗi thao tác một GET |
| Xóa bộ lọc | Nhánh nhập cũ không có nút này | Giữ kho/vị trí/pageSize; keyword trống, status mặc định cả hai trạng thái, page 1 | Đạt; API chỉ trả đơn đủ điều kiện |
| Phân trang/đơn đủ điều kiện | API cũ không loại dữ liệu tồn kho trong truy vấn candidate; count/page toàn scope rộng | SQL lọc trước COUNT/OFFSET/FETCH; validate metadata/IDs ở client | Đạt tổng/2 page không trùng; fixture stock với status CONFIRMED bị loại |
| Chi tiết đơn | Code cũ đã dùng đúng row.id | Duy trì helper router, route order-detail theo ID | Đạt ID thật và Back phục hồi scope/filter |
| Mở modal/click liên tiếp | Chỉ khóa khi gửi; nhiều click trước prepare hoàn tất có thể tạo nhiều modal/read | Khóa ngay khi tạo modal; một controller/modal và guard pending/review/scope | Đạt: một modal, một GET detail; hai click send chỉ một POST |
| Ghi chú/validation | 400 đã có thông báo, nhưng bản xác nhận cũ chưa được bỏ và cần kiểm tra length/membership rõ ràng | ≤500 kiểm tra JS + HTML; lỗi backend trong form, reset review và customValidity | Đạt native thiếu vị trí/501 ký tự; HTTP 400 validation thật xuất hiện trong form |
| Đóng modal | Cleanup chung phụ thuộc event close bất đồng bộ; có thể chậm dọn state/request | dispose idempotent đồng bộ, onClose callback; dùng cho cleanup modal nhập/lịch sử | Đạt: đóng sau 400 mở thao tác mới được; không modal/listener còn sót |
| Nhập kho 201 | Cần chứng minh IDs/commit/danh sách thật, không chỉ thông báo UI | Payload ID thật; 201 validate response, đóng modal, feedback và reload một danh sách | Đạt: SQL đúng một giao dịch INBOUND/một stock, IN_WAREHOUSE, đơn rời candidate |
| Sai trạng thái/409 | Cũ có xử lý 409 nhưng cần xác minh trước/sau prepare và chống resend | Reread detail trước mở; 409 khóa bản cũ, reload danh sách, không retry POST | Đạt preflight không POST; concurrent import gây 409 thật, không giao dịch trùng |
| Thiếu quyền/403 | API client đã phân biệt 403; phải duy trì và kiểm tra grant hiện hành | Live KHO_NHAP khi chuẩn bị, backend kiểm tra lại; 403 trong form/giữ phiên | Đạt SQL thu hồi grant sau review: POST 403, không ghi/không logout |
| Mạng/500 sau gửi | Cũ chỉ hướng dẫn tải lại dữ liệu/lịch sử, chưa có nút xác minh trạng thái riêng | Khóa bản cũ, nhớ attempt chưa xác nhận, GET kiểm tra trước thao tác mới; không tự gửi lại | Đạt loss-response sau commit thật; một POST, GET xác nhận nhập thành công |
| Danh sách rỗng/lỗi/thử lại | Nhãn Không có dữ liệu chung, chưa riêng nhập kho | Nhãn yêu cầu, loading, lỗi và retry theo scope/filter | Đạt empty thật; 500 có kiểm soát giữ JWT, retry dữ liệu thật |

## Môi trường và bằng chứng

Backend build **0 warning/0 error** vào output thử riêng, không ghi đè server đang chạy. Toàn bộ JS kiểm tra syntax; **18/18 regression Node hiện hữu** (10 auth/proxy, 8 router) đạt.

Regression API/UI dùng ASP.NET Core thật + LocalDB SQL Server thật trên database riêng `CodexInbound_<GUID>`, schema/seed gốc, không tắt trigger/constraint. Tài khoản BCrypt admin/reader thử riêng; đơn được tạo/confirm qua API thật, chuyển WAITING_INBOUND qua stored procedure chuẩn. Fixture tồn kho bất nhất được tạo có kiểm soát bằng SQL hợp lệ để kiểm tra NOT EXISTS; không thay response dữ liệu bằng mock. Mọi ghi/thu hồi quyền/vị trí chỉ trong database thử.

Backend và proxy thử đều dùng cổng OS cấp (0), không mở trùng 5500/5038/7255, không dừng tiến trình người dùng. Proxy và API client sản phẩm được dùng nguyên bản. POST 201/403/409 thật chứng minh Authorization/body tới backend; regression proxy xác nhận header/body giữ nguyên và redirect bị chặn 502. Không tắt TLS toàn cục, không đổi API_BASE_URL, token hoặc CORS.

Desktop: ảnh 1440×1000, viewport CSS 1414px do cửa sổ Edge. Mobile: viewport thật **390×844** đặt qua DevTools trên profile Edge thử; không dùng ảnh bị crop của CLI window-size (CLI trên Windows áp min width 496). Cả hai chạy 15 nhóm kiểm tra nút/flow, `error`/`unhandledrejection` rỗng, không tràn trang; bảng cuộn trong khung. Đã xem ảnh QA.

API trước browser kiểm tra thêm: query orders cũ vẫn đọc được nhiều trạng thái/bưu cục; query mới đúng scope/eligibility, tổng confirmed + waiting bằng tổng candidate; hai page size 5 không trùng; query inbound thiếu kho/status NEW trả 400; kho/vị trí hoàn toàn không có active row trả `[]`.

Giao dịch kiểm thử đọc lại SQL COUNT trên GiaoDichKho/ChiTietGiaoDichKho và TonKhoDonHang, trạng thái/warehouse/location của DonHang, không chỉ dựa trên thông báo thành công. Concurrent change được tạo bằng một POST inbound khác trước khi xác nhận UI; POST UI sau đó thực sự trả 409, vẫn chỉ một giao dịch. Thu hồi KHO_NHAP bằng SQL sau khi modal đã review tạo 403 thật; reader không có KHO_NHAP cũng bị POST 403 và không đọc được warehouse ngoài scope (404).

Artifacts: [kết quả có cấu trúc](inbound-browser-verification.json), [desktop](inbound-desktop.png), [mobile 390px](inbound-mobile.png).

## Phần chưa kiểm thử thực tế

- **Không làm rớt kết nối mạng vật lý**: browser wrapper bỏ phản hồi sau khi POST thật đã trả 201 và đã commit, rồi kiểm tra UI + GET/SQL. Đây là test có kiểm soát cho trạng thái commit thành công nhưng client không nhận phản hồi, không phải lỗi mạng hạ tầng thật.
- **Không gây sự cố SQL/500 thật**: response 500 được tiêm một lần vào GET danh sách ở harness; sau retry dữ liệu luôn từ backend thật. Mục đích kiểm tra thông báo/giữ phiên, không che lỗi dữ liệu.
- Backend 400 validation notes được tạo bằng thay payload thành 501 ký tự ở ranh giới request của harness; frontend bình thường chặn 501 trước POST. Response là validation thật của controller, không mock.
- Không kiểm thử thủ công trên phiên người dùng/database vận hành, không benchmark tải cao/deadlock giữa nhiều nhân viên, không kiểm thử hạ tầng TLS production. Không kiểm thử đầy đủ các nghiệp vụ nhập hoàn/xuất kho trong đợt này.

Đã dọn database, harness/profile/SDK output/key/token thử và tiến trình thử; chỉ giữ code sản phẩm và artifacts ở docs. Cần build/chạy lại backend hiện có để nhận query bổ sung, rồi tải lại frontend.

File sửa/bổ sung: frontend/js/inbound.js, orders.js, warehouse.js, router.js, app.js; frontend/index.html, assets/css/styles.css, README.md; backend/LastMile/LastMile.Api/Controllers/OrdersController.cs, WarehousesController.cs; docs/inbound-ui-verification.md, inbound-browser-verification.json, inbound-desktop.png, inbound-mobile.png.
