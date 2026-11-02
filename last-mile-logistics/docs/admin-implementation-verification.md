# Bốn trang quản trị — triển khai và kiểm chứng

Ngày thực hiện: 10/10/2026. Các trang dùng HTML/CSS/JavaScript thuần, Bootstrap và shell/sidebar cây hiện có. Không dùng fixture trong ứng dụng; tất cả dữ liệu và thao tác của trang gọi API thật.

## Vai trò & quyền

**File:** `frontend/js/roles.js`, `Controllers/RolesController.cs`, `Controllers/RolePermissionsController.cs`.

**API:** `GET /api/v1/roles` và `?id=`, `POST /api/v1/roles`, `PUT /api/v1/roles/{id}/permissions`, `GET /api/v1/auth/permissions`. Không tạo endpoint phân quyền khác. Sửa các mảng permissions/items rỗng để luôn trả `[]`.

Danh sách có tìm mã/tên, lọc trạng thái, tạo/sửa và URL `/admin/roles/:id` để chỉnh quyền. Dùng ID/mã/tên quyền và đầy đủ tập quyền của backend; nhóm theo tiền tố mã thực tế. Mọi quyền trong availablePermissions hoặc permissions đều được giữ trong tập chọn, kể cả quyền chưa có nhóm chuyên biệt. Không thêm mã quyền riêng cho Khách hàng/Phương tiện: các màn hình đó dùng mã Đơn hàng/Điều phối/Tài khoản hiện có; giao diện giải thích quan hệ này.

Checkbox nhóm có chọn tất cả/indeterminate. Chỉ PUT khi Lưu quyền, gửi `permissionIds`, `expectedPermissionIds`, `reason`. Hủy thay đổi khôi phục tập ban đầu. Có cảnh báo khi chuyển URL, Back/Forward, tải lại/đóng tab và đăng xuất; lỗi giữ lựa chọn, 409 có tải lại quyền. Sau lưu GET lại chi tiết và quyền hiện hành, cập nhật sidebar. Backend giữ mã vai trò cố định, chặn tắt ADMIN và tắt vai trò còn tài khoản ACTIVE/LOCKED, bắt buộc ADMIN giữ PHANQUYEN_QUANLY/TAIKHOAN_QUANLY/TAIKHOAN_XEM.

Các API quản trị này kiểm tra quyền từ DB ở mỗi request; JWT hiện tại đọc được tập quyền mới qua auth/permissions. Đổi quyền thu hồi refresh token của vai trò, **không thu hồi access token ngay**. Role/branch claims của JWT không được tuyên bố đã thay đổi; cần đăng nhập lại khi thay đổi liên kết vai trò/bưu cục của tài khoản.

**Kiểm tra:** báo cáo `docs/admin/roles-verification.json`: tạo/sửa qua API và UI, mã trùng, mã bất biến, bảo vệ ADMIN/quyền cốt lõi, tập quyền thay thế/expected set cũ 409, đủ 27 quyền seed xuất hiện đúng một lần, indeterminate, rời trang chưa lưu, hủy/sau lưu/reload, quyền API, đăng nhập vai trò mới, quyền theo bưu cục và refresh token thật bị thu hồi trong khi access token cũ vẫn hợp lệ.

**Giới hạn:** bảng vai trò chưa có phân trang backend; API hiện trả đầy đủ danh sách, lọc ACTIVE bằng API và INACTIVE từ danh sách thật. Không thêm cơ chế version cho tên/mô tả vai trò vì DTO lưu hiện tại không có; expected set áp dụng cho quyền.

## Danh mục

**File:** `frontend/js/catalogs.js`, `frontend/js/locations.js`, `Controllers/CatalogsController.cs`. `CatalogSaveController` được tái sử dụng, không tạo luồng lưu mới.

**API:** `GET /api/v1/catalogs` và `?type=AREAS|SERVICES|BRANCHES|WAREHOUSES|LOCATIONS`, `POST /api/v1/catalogs`. Tab vị trí dùng nguyên `LocationsPage` và các form/validation/xác nhận/POST đã có. Màn hình kho cũ vẫn dùng `GET /api/v1/warehouses/{id}/locations`; chế độ quản lý danh mục dùng catalog API để xem cả kho/vị trí ngừng hoạt động.

Năm tab đúng enum backend, bộ lọc/tìm kiếm và modal riêng cho bốn danh mục đầu. Quan hệ khu vực cha, khu vực của bưu cục, bưu cục của kho theo schema. Mã danh mục và bưu cục của kho đã tạo không đổi; backend kiểm tra cha/vòng lặp, trạng thái quan hệ, tọa độ, mã trùng, công việc/đơn/tồn kho còn hoạt động. Không DELETE vật lý. Nút lưu dịch vụ yêu cầu BANGGIA_QUANLY; danh mục khác yêu cầu BUUCUC_QUANLY và ADMIN như controller.

Bổ sung trường đọc đã có trong schema nhưng API thiếu: code/address/phone/email của bưu cục, address của kho, storageArea/rack/slot của vị trí. Mảng rỗng luôn `[]`. Gom JSON gốc vào NVARCHAR(MAX) trước ExecuteScalar để danh sách ALL không bị cắt thành phần đầu của kết quả FOR JSON. Cho ADMIN có BANGGIA_QUANLY đọc danh mục dịch vụ/khu vực/bưu cục dùng để quản lý và thử phí, giữ giới hạn ghi cũ.

**Kiểm tra:** `docs/admin/catalogs-verification.json`: tạo năm loại, sửa dịch vụ/trạng thái và sửa khu vực bằng UI, mã trùng, tự làm cha/cha không tồn tại, tọa độ sai, không đổi bưu cục của kho, không tắt cha/bưu cục có tham chiếu hoạt động, form vị trí cũ tạo qua HTTP thật, xem vị trí của kho ngừng hoạt động, dịch vụ/kho ngừng hoạt động bị loại khỏi picker tạo đơn/kho.

**Giới hạn:** API không có tìm kiếm/phân trang tổng quát cho catalog; bốn tab đầu lọc danh sách thật từ API trong frontend. Tab vị trí quản lý kho inactive hỗ trợ xem/sửa/ngừng/kích hoạt theo ràng buộc backend; không bổ sung nghiệp vụ chuyển vị trí sang kho khác.

## Bảng giá

**File:** `frontend/js/pricing.js`, `Controllers/ShippingFeeRulesReadController.cs`, `Controllers/ShippingFeesController.cs`; dùng `ShippingFeeRulesController` hiện có để lưu.

**API:** `GET /api/v1/shipping-fees/rules` và `?id=`, `POST /api/v1/shipping-fees/rules`, `POST /api/v1/shipping-fees/quote`. Bộ lọc dịch vụ, khu vực/phạm vi toàn hệ thống, trạng thái và phân trang tại backend. Bổ sung `isActive`, `globalOnly` vào API đọc để lọc đúng trước phân trang, vẫn hỗ trợ `activeOnly` cũ. Mảng items rỗng trả `[]`.

Hiển thị dịch vụ, khu vực, km/kg (hai đầu bao gồm), phí cơ bản/phí mỗi km/phí mỗi kg, thời gian hiệu lực và trạng thái. Phạm vi là **khu vực hoặc null toàn hệ thống**, không tạo trường bưu cục/độ ưu tiên cho quy tắc khi schema không có. Thời gian nhập theo Việt Nam, gửi offset +07:00; backend lưu UTC giây. Khoảng hiệu lực bao gồm thời điểm bắt đầu và loại thời điểm kết thúc. Backend kiểm tra phí không âm, độ chính xác, thứ tự khoảng, ngày và chồng lấn cùng dịch vụ/phạm vi đang hoạt động. Toàn hệ thống và khu vực cụ thể được cùng tồn tại theo thuật toán hiện có.

Thử phí gọi API thật với branchId/serviceId/distanceKm/weightKg, không tạo đơn/giao dịch, không nhân/tính tổng cước ở frontend. Công thức backend giữ nguyên: baseFee + distanceKm × feePerKm + weightKg × feePerKg, làm tròn 0 chữ số theo AwayFromZero. Ưu tiên khu vực của bưu cục, sau đó global, hiệu lực mới nhất, rồi ID quy tắc. Cho ADMIN có BANGGIA_QUANLY thử phí ngay cả khi thiếu DONHANG_TAO; người dùng thường vẫn theo DONHANG_TAO/phạm vi cũ.

Thêm các trường đọc `baseFeeExact`, `feePerKmExact`, `feePerKgExact` và các phần phí `*Exact` trong quote dưới dạng chuỗi thập phân để giữ chính xác DECIMAL lớn; trường numeric cũ giữ nguyên cho tương thích. Form tiền gửi chuỗi thập phân được DTO ASP.NET hiện có chấp nhận; không chuyển tiền lớn sang Number. Định dạng tiền chỉ định dạng chuỗi, không tính cước riêng.

**Kiểm tra:** `docs/admin/pricing-verification.json`: quyền API, phí âm, khoảng/ngày sai, chồng lấn 409, tạo/sửa/ngừng bằng API, tạo/sửa qua UI, lọc trạng thái/phạm vi/empty/pagination, global so với area ưu tiên đúng, quote HTTP thật 14.000/19.000/15.000 VNĐ, số tiền `90071992547409.91` được sửa và đọc lại chính xác, không tạo POST orders khi thử và hai đơn cũ giữ nguyên dữ liệu/phí trong hồi quy.

**Giới hạn:** DTO lưu quy tắc không có version; không tự thêm optimistic version. Không có trạng thái phí hay khoảng bưu cục khác với schema hiện có. Chưa thử chính sách vận hành chồng lấn ngoài ràng buộc/thuật toán controller hiện có.

## Nhật ký hệ thống

**File:** `frontend/js/audit.js`, `Controllers/AuditLogsController.cs`, `Services/AuditDataSanitizer.cs`.

**API:** `GET /api/v1/audit-logs` và `?id=`. Bổ sung keyword trên metadata người thực hiện/thao tác/đối tượng; giữ accountId/action/objectType/objectId/from/to và phân trang. Người thực hiện nhập mã tài khoản, không phụ thuộc thêm quyền TAIKHOAN_XEM để tải bộ lọc. Sort createdAtUtc DESC/id DESC. Bộ lọc ngày do backend đổi từ ngày Việt Nam sang UTC; giao diện hiển thị UTC có/không Z bằng formatter Việt Nam chung, không cộng 7 giờ lần nữa.

Modal dữ liệu trước/sau dùng đúng DuLieuCuJson/DuLieuMoiJson. URL `/admin/audit-logs/:id` tải lại được, đóng về danh sách giữ bộ lọc, hỗ trợ Back/Forward. JSON bằng textContent/pre, có cuộn, null và không hợp lệ được thông báo. Không có thêm/sửa/xóa log.

Backend lọc trường chứa password/MatKhau/token/secret/credentials/authorization/API key/private key/connection string/cookie/JWT đệ quy, ẩn chuỗi JWT/refresh token/BCrypt có thể nhận diện và giá trị bí mật gắn nhãn trong văn bản. Không trả JSON lỗi thô từ lịch sử; SQL kiểm tra ISJSON và báo cờ invalid. Lý do lưu quyền đi qua bộ lọc chuỗi trước khi ghi log. Không sửa/xóa dữ liệu nhật ký vận hành đã lưu.

**Kiểm tra:** `docs/admin/audit-verification.json`: tạo log thật từ 12 POST vai trò trên DB thử, sort/pagination/metadata/date/keyword/empty/403/400, đọc trước/sau của log thử chứa bí mật lồng nhau, token string bị che; nội dung img/onerror giữ dưới dạng text và không thực thi; null/JSON lỗi ở formatter, URL modal/reload/đóng giữ bộ lọc, request nhật ký chỉ GET, desktop/mobile.

**Giới hạn:** schema V5 chặn JSON không hợp lệ bằng CHECK, nên không phá constraint DB để tạo log lỗi; formatter được kiểm tra với chuỗi lỗi và SQL có nhánh phòng ngừa cho dữ liệu lịch sử. Tìm từ khóa chỉ trên metadata, không tìm nội dung JSON/bí mật. Bộ lọc 366 ngày tối đa theo cơ chế controller. Bộ lọc bí mật bảo vệ trường/tokens/nhãn có thể nhận diện, không suy đoán ý nghĩa của văn bản tự do không có dấu hiệu bí mật.

## File dùng chung, kiểm tra và ảnh

- `frontend/js/admin-ui.js`: form/modal, khóa nút/giữ form, lỗi/thử lại, abort/epoch, phân trang và cleanup dùng chung.
- `frontend/js/router.js`: các URL/query/permission thật, leave guard, và quyền DB cho các màn hình đã triển khai để vai trò mới dùng được; admin management giữ điều kiện ADMIN, các placeholder còn lại giữ chính sách role cũ.
- `frontend/js/app.js`, `frontend/index.html`: mount/destroy, script/cache version, menu từ quyền hiện hành và cảnh báo logout; giữ shell.
- `frontend/assets/css/styles.css`: selector `.admin-page`/các trang quản trị và chế độ nhúng locations, không đổi style trang đã hoàn thành. Tab đang chọn đã sửa tương phản chữ/nền sau khi rà ảnh.
- `frontend/package.json`: `npm.cmd test`, `npm.cmd run test:admin` (build riêng rồi chạy lần lượt roles/catalogs/pricing/audit/regression).
- `frontend/tests/admin-fixture.ps1`, `admin-browser.cjs`, `admin-roles.cjs`, `admin-catalogs.cjs`, `admin-pricing.cjs`, `admin-audit.cjs`, `admin-regression.cjs`, `router.test.cjs`: test/fixture được giữ trong tests. Build/profile dưới `.artifacts/admin`, đã có .gitignore; không tạo thư mục check ở gốc.

Kiểm tra chạy bằng ASP.NET, LocalDB và Edge thật, database `CodexAdmin_<GUID>`/profile riêng, cổng OS cấp. Mỗi phase tự dọn database/profile, không thay database vận hành hoặc dừng server debugger của người dùng. Các actor seed dùng JWT ký đúng key thử riêng; login/refresh còn được kiểm tra bằng tài khoản mới tạo và mật khẩu BCrypt thật. Log chứa bí mật/HTML chỉ được chèn trong database thử để kiểm chứng redaction/XSS, không phải dữ liệu giả của trang.

Các báo cáo máy đọc và ảnh 1440/390px trong `docs/admin`. Build cuối 0 lỗi/0 cảnh báo; unit router/auth **32/32 đạt**. Báo cáo JSON mới nhất: **Vai trò 18, Danh mục 10, Bảng giá 13, Nhật ký 11, hồi quy 20**; tổng **72 kiểm tra API/Edge đạt**, không lỗi JavaScript. Một lượt hồi quy tổng hợp gặp lỗi kết nối khi điều hướng; harness hỗ trợ kiểm tra giữ phiên/nút Thử lại trên lỗi thật, không thay response thành dữ liệu giả; lượt hồi quy cuối hoàn thành 20 kiểm tra. Các lỗi SQL mảng rỗng/JSON danh mục cắt đoạn và lỗi harness trong các lượt đầu đã được sửa và chạy lại; không dùng kết quả lỗi làm bằng chứng thành công.

`regression-verification.json` kiểm tra form tạo đơn thực với khách hàng/địa chỉ/dịch vụ thật → confirm → modal nhập kho thực → IN_WAREHOUSE → ready-for-dispatch → API hàng chờ/ứng viên điều phối, cùng bố cục của bốn trang. **UI Điều phối vốn vẫn là placeholder ngoài yêu cầu này**: đã kiểm tra API queue/candidate, không tuyên bố có form phân công UI mới hoặc đã thử phân công thực. Chưa kiểm tra trên phiên/database vận hành.
