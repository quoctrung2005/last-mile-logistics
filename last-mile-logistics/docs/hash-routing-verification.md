# Hash routing — kiểm tra ngày 09/10/2026

## Hướng dẫn và phạm vi

Đã kiểm tra AGENTS.md ở D:\, D:\DA_CN_logistics, thư mục dự án và các thư mục frontend: không có file. AGENTS.md toàn cục C:\Users\trung\.codex trống. Đã đọc index.html, app.js, api.js, auth.js, orders.js, warehouse.js, cấu trúc frontend, các route/quyền backend liên quan và ghi chú contract sửa đơn.

Giữ HTML/CSS/JavaScript thuần + Bootstrap. Không thêm framework/dependency, không đổi config.js, địa chỉ API, dev-server, middleware backend, token hoặc thời hạn JWT. Router tập trung khai báo menu/route/query/quyền; bỏ renderPage và event warehouse:navigate. Menu dùng href thật, chỉ hashchange thực hiện chuyển trang. History replace dùng cho redirect/filter và chủ động gọi transition một lần; filter updates không remount.

Router kiểm tra policy vai trò của shell hiện có; các màn hình Đơn hàng/Kho còn kiểm tra quyền DB hiện hành từ Auth.getPermissions trước mount. Kho dùng lại kết quả này, không gọi permissions hoặc refresh danh sách thêm lần nữa khi khởi tạo. Thiếu quyền có trang riêng, không phát auth:expired. Backend vẫn kiểm tra grant/scope khi đọc hoặc ghi.

Chi tiết đơn, form tạo/sửa và chi tiết giao dịch được tái sử dụng trong view route riêng, không mount danh sách nền. Các modal báo giá, xác nhận/hủy, nhập/xuất/chuyển vị trí và lịch sử theo dòng giữ cơ chế thao tác hiện có. Khi rời route, trang cũ destroy: abort request, dọn debounce/timer, đóng/xóa modal, bỏ phản hồi cũ. Router có generation/AbortController cho bước kiểm tra quyền. Restore user cũ không được ghi đè login/logout mới; logout dọn thông tin shell.

## Danh sách màn hình

URL đầy đủ lấy `http://localhost:5500/` cộng hash dưới đây. ID động phải là số nguyên dương an toàn và dữ liệu thuộc scope API.

| Màn hình | URL mới | Kết quả kiểm tra |
| --- | --- | --- |
| Đăng nhập | `#/login` | Đạt: deep link → login → trở lại chi tiết; logout về Login |
| Tổng quan | `#/dashboard` | Đạt; giữ placeholder |
| Đơn hàng | `#/orders` | Đạt API thật, bộ lọc, active menu |
| Tạo đơn | `#/orders/create` | Đạt form/options/customer API; không submit ghi |
| Chi tiết đơn | `#/orders/:id` | Đạt với ID 1; một GET chi tiết, không GET danh sách; F5 giữ URL |
| Sửa đơn | `#/orders/:id/edit` | Đạt route và kiểm tra điều kiện; ID 1 không NEW nên giữ thông báo không thể sửa |
| Tồn kho | `#/warehouse/inventory` | Đạt API thật; F5 giữ warehouseId/status/keyword, một inventory GET |
| Nhập kho | `#/warehouse/inbound` | Đạt route/scope/danh sách API thật |
| Xuất kho / bàn giao | `#/warehouse/outbound` | Đạt route/scope/danh sách API thật |
| Nhập hàng hoàn | `#/warehouse/returns` | Đạt route/scope/danh sách API thật |
| Vị trí lưu kho | `#/warehouse/locations` | Đạt API thật |
| Lịch sử giao dịch | `#/warehouse/transactions` | Đạt API thật |
| Chi tiết giao dịch | `#/warehouse/transactions/:id` | Đạt với ID 5; một GET chi tiết, không tải danh sách kho nền |
| Hàng chờ điều phối | `#/dispatch/orders` | Đạt điều hướng; giữ placeholder |
| Phân công | `#/dispatch/assignments` | Đạt điều hướng; giữ placeholder |
| Chuyến giao | `#/dispatch/trips` | Đạt điều hướng; giữ placeholder |
| Tối ưu tuyến | `#/dispatch/optimization` | Đạt điều hướng; giữ placeholder |
| Theo dõi giao hàng | `#/tracking` | Đạt điều hướng; giữ placeholder |
| Thu hộ COD | `#/cod/collections` | Đạt điều hướng; giữ placeholder |
| Đối soát COD | `#/cod/reconciliation` | Đạt điều hướng; giữ placeholder |
| Khách hàng | `#/customers` | Đạt điều hướng; giữ placeholder |
| Nhân viên giao hàng | `#/fleet/couriers` | Đạt điều hướng; giữ placeholder |
| Phương tiện | `#/fleet/vehicles` | Đạt điều hướng; giữ placeholder |
| Báo cáo | `#/reports` | Đạt điều hướng; giữ placeholder |
| Tài khoản | `#/admin/accounts` | Đạt; ADMIN mở placeholder, ACCOUNTANT thấy Không có quyền |
| Vai trò & quyền | `#/admin/roles` | Đạt điều hướng; giữ placeholder |
| Danh mục | `#/admin/catalogs` | Đạt điều hướng; giữ placeholder |
| Bảng giá | `#/admin/pricing` | Đạt điều hướng; giữ placeholder |
| Nhật ký hệ thống | `#/admin/audit-logs` | Đạt điều hướng; giữ placeholder |
| Không tìm thấy | Hash không khớp route | Đạt trang Không tìm thấy, không tự về Dashboard |

## Query và lịch sử

Query được parse bằng URLSearchParams, kiểm tra trước cả bước đọc quyền/API màn hình: page 1–100000, pageSize 1–100, ID nguyên dương an toàn (warehouseId tối đa int32), keyword ≤100, status/type/acceptedOnly thuộc danh mục, chặn key không hỗ trợ hoặc lặp. Nhập kho chỉ nhận CONFIRMED/WAITING_INBOUND. Query không nằm trong màn hình tương ứng bị từ chối. Ví dụ:

- `#/orders?page=2&status=NEW&keyword=LM`
- `#/warehouse/inventory?warehouseId=1&status=IN_WAREHOUSE&keyword=LM`
- `#/warehouse/transactions?warehouseId=1&type=INBOUND&orderId=1`

Filter changes replace entry hiện tại, giữ focus; mở chi tiết push entry mới. Back/Forward remount từ query được kiểm tra. Trang vượt tổng trang thực trả về từ API được clamp về trang cuối theo hành vi danh sách cũ, có thể cần một request bổ sung với page đã sửa; đây không phải mount/router trùng.

Hash rỗng chọn Login/Dashboard theo phiên. Route chưa đăng nhập được lưu vào tvd.returnRoute và trở lại sau login; role/grant kiểm tra trước render, thiếu quyền thì hiển thị Không có quyền. Không nhận return URL ngoài; dữ liệu returnRoute sai hoặc route không tồn tại được bỏ. JWT/refresh tiếp tục dùng API client hiện có.

## Kiểm thử

`node --test frontend/tests/*.test.cjs`: **18/18 đạt**, gồm 8 test router và 10 test xác thực/proxy. Không cài dependency. Router tests kiểm tra tất cả menu URL không trùng, ID động, query sai/trùng, hash rỗng, return URL an toàn, Back/Forward, reload từ hash, permissions/role, route đang chờ bị abort và kết quả đến muộn không ghi đè, logout/Back và Not Found.

Edge headless dùng frontend hiện tại, ASP.NET Core/LocalDB thật, database thử CodexRouting_<GUID> được tạo riêng từ schema/seed dự án. Tài khoản BCrypt thử riêng. Backend/proxy thử đều dùng cổng 0 được OS cấp, profile Edge riêng; không mở server trùng 5500/5038/7255, không dừng server người dùng, không ghi vào database vận hành.

- Click mọi link menu: đúng hash, title, active link và nhánh sidebar mở. Các GET cần thiết của màn hình thực trả 200 và không hiện lỗi dữ liệu; các placeholder không bịa API/dữ liệu.
- Mở `#/orders/1` chưa có phiên → Login → đúng chi tiết sau login, một GET chi tiết và không GET danh sách.
- Đơn hàng: query khôi phục control/API; chi tiết → Back phục hồi query; Forward trở lại chi tiết. Trường hợp page vượt tổng được sửa theo hành vi hiện có.
- Tạo đơn: form/options/customer API thật, một GET options, không tải danh sách nền. Hai picker người gửi/người nhận có request customer riêng theo thiết kế hiện có.
- Sửa đơn: route ID 1, đọc đúng chi tiết, thông báo điều kiện không NEW. Không bỏ khóa sửa khi contract backend thiếu ID/version.
- Chi tiết giao dịch ID 5: một GET chi tiết, không tải danh sách kho nền.
- F5 dùng location.reload trên trình duyệt thật: chi tiết vẫn đúng URL/ID; tồn kho giữ warehouseId=1, status=IN_WAREHOUSE, keyword=LM, control và API filter khớp, chỉ một inventory GET.
- Đang debounce tìm đơn rồi rời Dashboard: sau 500 ms không có GET danh sách muộn. Mở modal báo giá giữ hash; rời route xóa modal.
- Logout xóa token; mở route admin rồi login ACCOUNTANT: Không có quyền, không xóa phiên; route tạo đơn thiếu DONHANG_TAO cũng giữ phiên.
- Query page=-1 hiển thị URL không hợp lệ; hash không tồn tại hiển thị Không tìm thấy. Không có lỗi JavaScript error/unhandledrejection trong Edge, không có exception trong log backend thử.

Kết quả browser có cấu trúc tại [routing-browser-verification.json](routing-browser-verification.json). Harness, profile, JWT/key thử, database và tiến trình thử được dọn sau kiểm thử.

## Giới hạn

Không submit tạo/sửa đơn hoặc nhập/xuất/chuyển vị trí trong đợt routing này. Form sửa vẫn phụ thuộc contract backend hiện hành thiếu các ID/version (xem orders-api-gaps.md); không thay backend để bỏ giới hạn này. Các menu placeholder chỉ được kiểm tra điều hướng và quyền shell, chưa triển khai chức năng nghiệp vụ. Chưa kiểm tra thủ công trên phiên trình duyệt cũ của người dùng.

Tải lại trang đang mở để nạp router.js và app.js mới. Không cần mở server mới hoặc đổi API/config.

File sửa/bổ sung: frontend/js/router.js, app.js, orders.js, warehouse.js; frontend/index.html, README.md; frontend/tests/router.test.cjs; docs/hash-routing-verification.md, routing-browser-verification.json.
