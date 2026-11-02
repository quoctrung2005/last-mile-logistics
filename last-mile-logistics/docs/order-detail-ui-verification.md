# Chi tiết đơn và layout dùng chung — 09/10/2026

## Phạm vi và nguyên nhân xác minh

Đọc frontend/index.html, styles.css, app.js, router.js, orders.js, warehouse.js, inbound.js cùng OrdersController, OrderConfirmController, OrderCancelController, ShippingFeesController và schema SQL hiện tại. Không có AGENTS.md trong dự án/đường dẫn cha; AGENTS toàn cục rỗng. Giữ HTML/CSS/JavaScript + Bootstrap và trắng/cam. Không sửa backend, URL API, JWT, CORS, thời hạn token, node_modules hoặc database.

Các vấn đề được xác minh trực tiếp từ code trước sửa:

1. `orders-route-body` không có padding; renderer chi tiết từng dùng nội dung phù hợp với modal có padding nhưng chuyển sang route không được bù khoảng cách. Header H1 của shell lại lặp H2 trong card.
2. Selector `.orders-card .orders-table { min-width: 1250px }` áp dụng cả các bảng hàng hóa/phí/lịch sử trong chi tiết. Bảng phí chỉ ba cột vẫn rất rộng. Chi tiết dùng nhãn 11px và bảng 12px, nhiều tọa độ/nguồn kỹ thuật trộn trong thông tin giao hàng.
3. Sidebar cố định dùng width/margin-left lặp 256px, đổi 226px ở media 1100px. Menu flex thiếu `min-height:0`/basis 0, brand/footer thiếu ràng buộc không co; thông tin phiên nằm cùng vùng menu cuộn. Layout tablet 768px vẫn mang sidebar desktop, thu hẹp nội dung.
4. Làm mới chi tiết không có controller/sequence riêng. Đổi route đã có guard `s.dead`, `replaceChildren` và hủy request toàn trang: **không xác minh được lỗi append nhiều màn hình**, cũng không thấy nhu cầu tăng z-index. Kho mở đúng orderId nhưng helper không mang đường quay lại, nên nút Quay lại đưa về Đơn hàng và mất bộ lọc Kho.
5. Dialog chung có cleanup đồng bộ khi bấm Đóng, nhưng destroy của các trang chỉ close/remove node; cleanup callback có thể đợi event close. Request Báo giá không hủy ngay khi đóng modal. Nút thao tác chi tiết chưa ngăn mở nhiều dialog trước khi gửi.

Header hiện hữu là sticky nằm trong luồng, không phải fixed cần cộng padding bù. Giữ đúng cơ chế này. Các mức z-index header/sidebar/backdrop giữ nguyên; modal native `dialog.showModal()` dùng top layer. Không dùng z-index mới để che nội dung.

## Thay đổi

- App grid có một biến sidebar width 256px, cột main `minmax(0,1fr)`/`min-width:0`; body cuộn nội dung chính, sidebar chỉ cuộn menu. Brand và footer không co, menu `min-height:0; flex:1 1 0`. Footer riêng có tên/vai trò/phiên/đăng xuất.
- Dưới 992px dùng drawer hiện hữu, body lock chỉ khi mở, workspace inert, sidebar inert khi đóng. Có Escape, focus vòng trong menu, backdrop, resize và leave route đều dọn lock/inert. Route mới cuộn về đầu ngay, không kế thừa smooth scroll của Bootstrap.
- Chi tiết chỉ một H1 shell, breadcrumb/Quay lại, mã đơn/tracking/status và thanh thao tác gọn. Card grid hai cột trên desktop rộng, một cột dưới 1200px; body/nhãn/bảng 13–16px, mã/địa chỉ xuống dòng.
- Nhóm Thông tin chung; Phí/COD có bảng phí Việt hóa SHIPPING/RETURN/SURCHARGE/DISCOUNT/OTHER; Người gửi/điểm lấy và Người nhận/điểm giao; Hàng hóa table-responsive; timeline lịch sử. Khoản tiền vẫn Intl VND, khối lượng kg.
- Actor sử dụng `changedByName` nếu có; response controller hiện tại chỉ có changedBy nên dùng **Tài khoản #ID**, không gán tên. Tọa độ, version/ID và nguồn lịch sử nằm trong details Dữ liệu kỹ thuật.
- Giữ helper date hiện hữu. Schema ghi rõ thời gian mặc định UTC/SYSUTCDATETIME; controller trả DATETIME2 qua FOR JSON không offset. Không đổi cách chuyển giờ hoặc cộng múi giờ thủ công.
- Nút dựa trên live DONHANG_TAO/CAPNHAT/HUY, scope và trạng thái đã đối chiếu controller/schema; backend vẫn quyết định cuối cùng. Sửa NEW tiếp tục khóa nếu DTO thiếu ID/version; không chế dữ liệu cập nhật. Hủy chỉ các chuyển trạng thái đã có trong schema.
- Route detail/edit hỗ trợ returnTo đã kiểm tra: chỉ danh sách Đơn hàng/Kho, không URL ngoài/nested/login/detail. Helper từ chi tiết giao dịch mang route danh sách giao dịch cùng bộ lọc. Quyền vẫn được router kiểm tra khi quay lại.
- GET detail có AbortController/sequence mỗi lần reload, kiểm tra ID khớp và bỏ response cũ, tối đa một renderer. Dialog có signal riêng, cleanup idempotent đồng bộ qua UI.closeDialogs; đóng/rời route hủy request. Detail actions ngăn dialog chồng nhau.

## Kiểm tra đã chạy

Regression Node: **19/19 đạt** (10 auth/proxy, 9 router, gồm returnTo giữ query và chặn đích ngoài/lồng nhau). Cú pháp tất cả frontend/js/*.js đạt. Không cần build lại backend vì không sửa backend.

Browser: Edge headless trên profile riêng; dùng DevTools Emulation để có viewport CSS đúng kích thước, không crop ảnh cửa sổ CLI. Cổng frontend QA do OS cấp, không trùng các server người dùng. Bootstrap/font thực đã tải; đã xem ảnh cả phần đầu, giao nhận/hàng hóa/lịch sử và drawer.

| Viewport | Cột chi tiết | Header/sidebar/footer | Tràn ngang toàn trang | Ảnh |
| --- | --- | --- | --- | --- |
| 1366×768 | 2 | Đạt, sidebar 256px, footer trong viewport cả khi mở các nhánh | Không, document 1351px (scrollbar 15px) | [Ảnh](order-detail-1366.png) |
| 1920×1080 | 2 | Đạt, main giới hạn chiều rộng phù hợp | Không, document 1905px (scrollbar 15px) | [Ảnh](order-detail-1920.png) |
| 768×1024 | 1 | Đạt, drawer đóng/mở, Escape/backdrop dọn inert/lock | Không, document 768px | [Ảnh](order-detail-768.png) |
| 390×844 | 1 | Đạt, drawer/menu cuộn, đăng xuất không bị cắt | Không, document 390px | [Ảnh](order-detail-390.png), [Drawer](order-detail-390-sidebar.png) |

**37 kiểm tra browser đạt**, kết quả tại [order-detail-browser-verification.json](order-detail-browser-verification.json):

- Mỗi viewport đúng width/height, một màn hình detail, phần đầu detail dưới header; header sticky đứng đầu khi cuộn; footer luôn nằm dưới vùng menu và trong viewport khi mở các nhánh. Mở Dữ liệu kỹ thuật không làm trang tràn ngang.
- Đúng nhãn Phí vận chuyển/Tài khoản #ID từ hai đơn hiện có. Desktop hai nhóm người gửi/nhận sát nhau; mobile xuống một cột. Bảng cuộn trong table-responsive. [Giao nhận/hàng hóa desktop](order-detail-1366-contacts.png), [Giao nhận mobile](order-detail-390-contacts.png), [Lịch sử mobile](order-detail-390-history.png), [Lịch sử desktop](order-detail-1366-history.png).
- Làm mới đúng một request adapter, hai reload chồng nhau chỉ render response mới nhất. Trì hoãn response đơn #2 rồi chuyển #1: response #2 không ghi đè; chuyển lại #2 thay renderer cũ.
- Button Chi tiết từ bảng Đơn hàng mở đúng ID; helper dùng cho Kho và chi tiết giao dịch mang đúng returnTo. Quay lại giữ warehouseId/page/keyword, Back/Forward và F5 phục hồi route detail/list.
- Double click Báo giá chỉ có một dialog; Đóng/rời route dọn dialog/backdrop/body lock. Cleanup shared hủy signal, callback đúng một lần và xóa ownership. Route mới về đầu trang.
- Bộ quyền viewer chỉ hiện Làm mới; thiếu DONHANG_XEM hiện Không có quyền và giữ session adapter. Không có error/unhandledrejection hoặc DevTools exception trong các ca hoàn thành.

## Dữ liệu và giới hạn kiểm thử

Bộ duyệt tự động ban đầu từ chối tạo snapshot toàn bộ dữ liệu vì vượt phạm vi QA. Không có script/payload snapshot toàn bộ nào được tạo. Người dùng sau đó cho phép **chỉ đọc hai đơn #1 và #2**, render và lưu ảnh; đã thực hiện đúng phạm vi này.

Script read-order-detail.ps1 thực thi nguyên truy vấn GetOrder của OrdersController cho đúng hai ID vào bộ nhớ. Không đọc bảng tài khoản/mật khẩu/token, không ghi payload SQL/JWT ra file/log, không tạo/sửa đơn hoặc dữ liệu giả. Hai đơn đều COMPLETED; mỗi đơn một item, một khoản phí, 11 dòng lịch sử. Ảnh chứa dữ liệu hai đơn được người dùng cho phép. Profile QA được xóa sau chạy.

Auth/quyền và transport trong browser QA là **adapter chỉ trong server thử**, đưa hai payload SQL thật vào renderer hiện hữu, có chủ ý trì hoãn response để kiểm tra race. Danh sách QA chỉ gồm hai bản ghi được phép đọc, không phải kết quả phân trang của toàn database. Adapter chặn mọi POST và không chế payload API không có sẵn. Đây là kiểm thử giao diện/router/lifecycle, **không phải end-to-end qua API đăng nhập thật**; không có adapter trong frontend/index.html hoặc code sản phẩm.

Chưa kiểm thử:

- API nghiệp vụ với phiên đăng nhập thật, quyền backend thực ở lần này. Không có credential/phiên được cung cấp; tại kiểm tra cuối backend 5038/7255 không listen, GET qua proxy 5500 trả **502**. Server frontend 21988 và Live Server 26632 vẫn hiện hữu; không dừng/restart server người dùng.
- Gửi Báo giá/Sửa/Xác nhận/Hủy với backend thật. Modal Báo giá chỉ thử mở/đóng, chống chồng và cleanup; API options chưa được nối trong adapter. Không hủy/sửa đơn vận hành để kiểm thử layout. Hai đơn được phép đọc đã COMPLETED nên không có nút Sửa/Xác nhận/Hủy.
- Click dòng dữ liệu thật của từng trang Kho qua API. Đã kiểm tra shared helper/from-route/returnTo và cùng renderer; API danh mục/tồn kho/giao dịch không được mô phỏng hoặc đọc thêm ngoài hai đơn.
- Lỗi HTTP403 backend thật, refresh JWT với backend thật, test trên trình duyệt/thiết bị vật lý khác. Regression Node auth/proxy/router hiện hữu vẫn đạt.

## File thay đổi

Frontend sản phẩm: index.html; assets/css/styles.css; js/app.js, orders.js, router.js, warehouse.js, inbound.js. Kiểm thử: tests/router.test.cjs, order-detail-browser.cjs, read-order-detail.ps1. Tài liệu: frontend/README.md và báo cáo/kết quả/ảnh order-detail-* trong docs.

Chạy regression từ root: `node --test frontend/tests/auth.test.cjs frontend/tests/router.test.cjs`.

Chạy riêng QA Windows/Edge/LocalDB, chỉ khi có quyền đọc/lưu ảnh hai đơn #1/#2: `node frontend/tests/order-detail-browser.cjs`. Script dùng cổng OS cấp, chặn mutation, giữ payload trong bộ nhớ, ghi metrics/ảnh và xóa profile thử.
