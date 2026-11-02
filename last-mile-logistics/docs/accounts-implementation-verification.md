# Trang Tài khoản — triển khai và kiểm chứng

Ngày kiểm tra: 10/10/2026. Route danh sách `#/admin/accounts`; chi tiết `#/admin/accounts/:id` giữ bộ lọc và trang trong URL, tải lại trực tiếp được.

## File sửa/bổ sung

- `frontend/js/accounts.js`: trang danh sách, bộ lọc, phân trang backend, chi tiết, modal tạo/sửa, xác nhận trạng thái, reset quản trị, xử lý lỗi và hủy request khi rời trang.
- `frontend/js/router.js`: quyền `TAIKHOAN_XEM`, query tài khoản và route chi tiết. Người có quyền xem tài khoản được mở route theo phạm vi backend, kể cả ngoài vai trò ADMIN. Route Vai trò & quyền yêu cầu `PHANQUYEN_QUANLY`.
- `frontend/js/app.js`, `frontend/index.html`: mount/destroy trang và tải script; giữ shell/sidebar/header hiện có.
- `frontend/assets/css/styles.css`: bố cục trắng cam, bảng cuộn ngang, cột thao tác đầy đủ, modal cuộn trên mobile.
- `backend/LastMile/LastMile.Api/Controllers/AccountsController.cs`: bổ sung tên vai trò và khóa tạm trong danh sách; ID nhân viên liên kết trong chi tiết. Không trả hash.
- `backend/LastMile/LastMile.Api/Controllers/RolesController.cs`: thêm chế độ lookup tối thiểu cho trang tài khoản; quyền đọc, điều kiện bưu cục và khả năng cấp vai trò lấy từ backend.
- `backend/LastMile/LastMile.Api/Controllers/AccountActionsController.cs`: thêm reset mật khẩu quản trị, DTO, kiểm tra quyền/version, BCrypt và nhật ký không chứa mật khẩu/hash/token.
- `frontend/tests/router.test.cjs`, `frontend/tests/accounts-fixture.ps1`, `frontend/tests/accounts-browser.cjs`, `frontend/package.json`: regression và lệnh chạy lại.
- `docs/accounts-verification.json`, tài liệu này: bằng chứng và giới hạn.

## API sử dụng

| API | Nội dung |
| --- | --- |
| `GET /api/v1/accounts` | `page`, `pageSize`, `keyword`, `roleId`, `branchId`, `status`; phân trang trước khi trả dữ liệu, tổng kết quả do backend tính |
| `GET /api/v1/accounts?id={id}` | Chi tiết đầy đủ và version trước khi sửa/thực hiện thao tác |
| `POST /api/v1/accounts` | DTO có username/password/fullName/phone/email/roleId/branchId; mặc định ACTIVE; backend kiểm tra unique và băm BCrypt work factor 12 |
| `PUT /api/v1/accounts/{id}` | fullName/phone/email/roleId/branchId/expectedVersion; không gửi username, password hay trạng thái |
| `POST /api/v1/accounts/{id}/actions` | LOCK/UNLOCK/DEACTIVATE/ACTIVATE, reason và expectedVersion; dùng nguyên quy tắc nghiệp vụ hiện có |
| `GET /api/v1/roles?lookupOnly=true` | **Bổ sung tham số** vào controller hiện có. Yêu cầu TAIKHOAN_XEM; trả id/code/name/isActive/requiresBranch/canAssign. Không trả toàn bộ danh mục quyền; API quản lý vai trò mặc định giữ chính sách cũ |
| `GET /api/v1/catalogs?type=BRANCHES` | Danh mục bưu cục thật, có phạm vi theo tài khoản đọc và trạng thái hoạt động |
| `POST /api/v1/accounts/{id}/reset-password` | **Bổ sung** vào AccountActionsController. Chỉ ADMIN đang hoạt động với TAIKHOAN_QUANLY; không thao tác chính mình. DTO newPassword/reason/expectedVersion. Xác nhận mật khẩu ở frontend |
| `GET /api/v1/auth/permissions` | Quyền thao tác thực từ DB qua Auth/API client chung; không tạo hệ thống phân quyền khác |

TaiKhoan có ba enum thực: ACTIVE = Đang hoạt động, LOCKED = Bị khóa, INACTIVE = Ngừng hoạt động. Khóa tạm `KhoaDenLuc` hiển thị riêng; UNLOCK xóa khóa tạm và đặt số lần đăng nhập sai về 0. Tài khoản ADMIN có branchId null hiển thị Toàn hệ thống, không bị loại khỏi danh sách.

Backend hiện có bảo vệ việc tự đổi vai trò/bưu cục, thao tác trạng thái chính mình, admin hoạt động cuối cùng, quyền vượt quá người quản lý, liên kết shipper, nhiệm vụ/chuyến/hoàn hàng/phân công xe. Frontend thông báo và giữ dữ liệu form khi bị từ chối. HTTP 409 khi sửa/thao tác có nút tải lại version; việc tải lại là lựa chọn rõ ràng của người dùng. Response danh sách cũ không ghi đè bộ lọc mới.

## Kiểm tra đã chạy

- `npm.cmd test`: **29/29 đạt** (router và auth/API client).
- `npm.cmd run test:accounts`: build .NET **0 lỗi, 0 cảnh báo**; **36 kiểm tra API/Edge đạt**, không lỗi JavaScript hoặc unhandled rejection. Danh sách cụ thể trong `accounts-verification.json`.
- Dùng LocalDB riêng `CodexAccounts_<GUID>`, schema và seed SQL của dự án, ASP.NET thật, proxy thật và Edge headless với profile riêng. Database/profile thử được xóa sau khi chạy. Không sửa dữ liệu vận hành và không dừng server người dùng. Lần chạy trong sandbox không mở được LocalDB; chạy lại với quyền thực thi được chấp thuận đã hoàn thành.
- Kiểm tra HTTP thật: danh sách, tìm theo tên đăng nhập/họ tên/điện thoại, vai trò/bưu cục/trạng thái, trang khác nhau và tổng, kết quả rỗng, thêm tài khoản và ADMIN toàn hệ thống, trùng tên (409), mật khẩu ngắn/quá 72 byte (400), thiếu bưu cục (422), sửa/version cũ, khóa/mở khóa/ngừng/kích hoạt, reset, đăng nhập và refresh bằng tài khoản vừa tạo.
- Kiểm tra quyền thật: người thiếu quyền xem/quản lý, phạm vi bưu cục, cấp vai trò ADMIN, cấp vai trò có quyền vượt quá mình, tự đổi vai trò/bưu cục, tự khóa/reset. Quản lý được cấp TAIKHOAN_QUANLY trong fixture chỉ cấp được vai trò có tập quyền nằm trong quyền của mình. Không thay quyền ở database vận hành.
- Hai ADMIN đồng thời ngừng hoạt động nhau: chỉ một thao tác thành công, DB giữ một ADMIN hoạt động. ADMIN cuối cùng tự khóa/ngừng/hạ vai trò bị từ chối. Liên kết nhân viên còn công việc bị từ chối đổi vai trò/bưu cục/ngừng hoạt động.
- Browser thật: tạo/sửa, duplicate giữ form, xác nhận mật khẩu, nút hiện/ẩn, khóa/mở khóa, reset, URL chi tiết/reload/quay về, phân trang/search, nút theo quyền, modal được dọn khi rời trang, khóa nút khi gửi theo triển khai và lỗi không làm mất phiên.
- HTTP 409 và 500 ở form sửa và response GET cũ bị trễ dùng lỗi/thời gian được kiểm soát trong harness để kiểm tra frontend; thao tác thành công đều gọi backend thật. 400/403/409/500 giữ phiên còn được kiểm tra trong bộ auth/API client. Không gây lỗi server vào dữ liệu vận hành.
- Đã xem ảnh chụp 1440 × 1000, 390 × 844 và modal 390; kiểm tra kích thước/overflow bằng browser ở cả 768 × 1024. Ảnh nằm trong `docs/accounts/accounts-*.png`. Bảng cuộn ngang trong vùng bảng, thao tác không tràn ô; modal dài có cuộn riêng và nhãn đầy đủ.
- Nhật ký tạo/sửa/hành động/reset có dữ liệu thay đổi; không chứa mật khẩu, MatKhauBam hoặc refresh token thử.

## Giới hạn còn lại

- Reset thu hồi **refresh token**, không vô hiệu hóa access token đã cấp ngay lập tức; test xác nhận access token cũ vẫn gọi auth/me được. Giao diện và phản hồi API nói rõ điều này. Reset giữ trạng thái tài khoản, khóa tạm và số lần sai; mở khóa dùng thao tác riêng.
- Schema V5 trong repo không tạo `TokenKhoiPhucMatKhau`, dù controller email recovery tham chiếu bảng đó. Reset quản trị không phụ thuộc bảng này: nếu module/bảng tồn tại thì đánh dấu mã chưa dùng là đã dùng; nếu chưa tồn tại thì không có mã lưu để thu hồi. Chưa chạy email recovery/SMTP hay kiểm tra thu hồi mã trên bảng recovery đã cài đặt.
- AuthController hiện không tăng SoLanDangNhapSai/tạo KhoaDenLuc khi mật khẩu sai. Trang này quản lý và hiển thị các giá trị backend cung cấp; chưa tự đặt một chính sách khóa tự động mới. Test UNLOCK khóa tạm dùng trạng thái khóa được đặt trong database thử, không tuyên bố đã kiểm tra chuỗi đăng nhập sai tự tạo khóa.
- Trang Vai trò & quyền hiện vẫn là placeholder của dự án; trang Tài khoản có liên kết đúng router và không tạo cơ chế cấp quyền riêng.
- Chưa kiểm tra trên phiên trình duyệt/database vận hành của người dùng. Seed gốc chứa hash mẫu; đăng nhập thật đã kiểm tra bằng các tài khoản tạo qua API trong DB thử.
