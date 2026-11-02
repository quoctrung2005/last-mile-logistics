# Triển khai trang Khách hàng — 10/10/2026

Trang `#/customers` thay nội dung chưa triển khai. Route `#/customers/:id` mở chi tiết, tải lại trực tiếp được, mang theo `page/pageSize/keyword/type/status` để quay về danh sách. Header/sidebar và Bootstrap hiện có được giữ nguyên; CSS mới nằm dưới `.customers-page`.

## File sản phẩm

- `frontend/js/customers.js`: danh sách, lọc/phân trang server, modal tạo/sửa/trạng thái khách hàng, chi tiết, địa chỉ và tab đơn hàng.
- `frontend/js/router.js`: route chi tiết, query khách hàng, quyền đọc, menu cho dispatcher và returnTo từ đơn về khách hàng.
- `frontend/js/app.js`: mount/destroy trang; dọn modal và hủy request khi chuyển trang.
- `frontend/index.html`: tải module và cập nhật cache version.
- `frontend/assets/css/styles.css`: giao diện khách hàng, bảng cuộn trong khung, modal cuộn trên điện thoại.
- `backend/LastMile/LastMile.Api/Controllers/OrderFormController.cs`: mở rộng API danh sách hiện có bằng type/status/isActive, cho tài khoản có DONHANG_XEM đọc danh sách; trả mảng [] khi rỗng.
- `backend/LastMile/LastMile.Api/Controllers/CustomerDetailController.cs`: bảo đảm addresses/recentOrders là [] khi rỗng.
- `backend/LastMile/LastMile.Api/Controllers/CustomerCreateController.cs`: bảo đảm addresses là [] khi không tạo địa chỉ ban đầu; kiểm tra tài khoản ngoài ADMIN phải có bưu cục.
- `backend/LastMile/LastMile.Api/Controllers/CustomerUpdateController.cs`, `CustomerAddressCreateController.cs`, `CustomerAddressUpdateController.cs`: bổ sung kiểm tra bưu cục cho tài khoản ngoài ADMIN; trả 403 khi thiếu phạm vi, giữ nghiệp vụ/DTO/log/transaction sẵn có.

## API sử dụng

Không tạo endpoint mới hoặc trùng endpoint.

| API | Sử dụng / mở rộng |
| --- | --- |
| GET /api/v1/auth/permissions | Quyền hiện hành của tài khoản; không suy quyền ghi từ vai trò |
| GET /api/v1/customers | keyword/page/pageSize hiện có; thêm type=INDIVIDUAL hoặc BUSINESS, status=ACTIVE/INACTIVE/ALL và isActive từng item |
| GET /api/v1/customers/{id}?includeInactiveAddresses=true | Thông tin đầy đủ để sửa, địa chỉ kể cả ngừng dùng, statistics và recentOrders |
| POST /api/v1/customers | fullName/phone/email/type; mã KH được backend sinh |
| PUT /api/v1/customers/{id} | fullName/phone/email/type/isActive, gồm ngừng/kích hoạt lại |
| POST /api/v1/customers/{customerId}/addresses | DTO địa chỉ hiện có |
| PUT /api/v1/customers/{customerId}/addresses/{addressId} | Sửa, đổi mặc định và ngừng/kích hoạt lại bằng DTO hiện có |
| GET /api/v1/order-form/options | Khu vực đang hoạt động từ danh mục thật |
| GET /api/v1/customers/{id}/addresses | Form đơn hiện có vẫn chỉ nhận địa chỉ hoạt động của khách hàng hoạt động |

Danh sách không truyền status vẫn mặc định ACTIVE, giữ tương thích form đơn. COUNT và các dòng cùng dùng bộ lọc trong SQL trước OFFSET/FETCH. Không lọc cục bộ từng trang.

Quyền nghiệp vụ hiện có: DONHANG_XEM đọc, DONHANG_TAO tạo khách hàng, DONHANG_CAPNHAT sửa khách hàng và quản lý địa chỉ. KhachHang không có MaBuuCuc trong schema: danh bạ dùng chung theo thiết kế hiện hữu; dữ liệu đơn trong chi tiết được backend giới hạn ADMIN toàn hệ thống, tài khoản khác theo bưu cục. Không tự suy ra phạm vi danh bạ từ tên/đơn hàng.

DTO khách hàng/địa chỉ không có version; frontend tải dữ liệu đầy đủ trước PUT, không tự thêm version. Schema chỉ đặt unique cho mã khách hàng; điện thoại/email khách hàng không unique, nên không áp quy tắc trùng khác. Không dùng DELETE. Quy tắc một địa chỉ mặc định và chọn thay thế khi ngừng mặc định do transaction/unique index hiện có bảo đảm. Không cập nhật DiemGiaoNhan của đơn cũ khi sửa danh bạ.

## Kiểm tra đã chạy

- `dotnet build --no-restore`: đạt, 0 warning / 0 error.
- `npm.cmd test`: 24/24 đạt, gồm auth/proxy/router hiện có và route/query/quyền khách hàng mới.
- `frontend/tests/customer-detail-sql.ps1`: 10/10 đạt trên LocalDB hiện có, chỉ đọc; gồm ADMIN/BRANCH_MANAGER, địa chỉ, thống kê/đơn đúng bưu cục, account không hợp lệ và customer không tồn tại.
- `frontend/tests/customers-browser.cjs`: 48 kiểm tra API/trình duyệt đạt, sử dụng database thử riêng CodexCustomers_<GUID>, schema/seed gốc, ASP.NET thật, proxy/API client thật và Edge headless. Database, server thử và browser profile được dọn sau chạy. Database vận hành không bị ghi.

Harness tự ký JWT bằng khóa ngẫu nhiên chỉ cho API thử và tài khoản seed trong database thử; không dùng session/token của người dùng. Không kiểm thử login bằng mật khẩu trong harness này.

Các luồng đã thực thi với HTTP/SQL thật: danh sách, tìm mã/tên/điện thoại, phân trang không trùng, lọc loại/trạng thái, mảng rỗng, tạo/sửa/trạng thái khách hàng, tạo địa chỉ không tọa độ, sửa đúng cặp customerId/addressId, đổi mặc định, ngừng mặc định và chọn thay thế, kích hoạt lại, loại địa chỉ/khách hàng ngừng dùng khỏi API form đơn, từ chối addressId của khách hàng khác, chi tiết tải lại/quay về giữ query, tab đơn theo ID/phạm vi, chọn khách hàng và tải địa chỉ trong form tạo đơn. Một sửa địa chỉ khách hàng thật được đối chiếu toàn bộ bản ghi DiemGiaoNhan trước/sau: không đổi.

Quyền: thu hồi grant ghi của BRANCH_MANAGER trong database thử; danh sách vẫn đọc được, UI không có nút ghi, PUT khách hàng và POST địa chỉ trả 403 thật. Tài khoản dispatcher hợp lệ nhưng thiếu bưu cục bị POST khách hàng 403. Route không có quyền và khách hàng không tồn tại hiển thị trạng thái riêng.

Lỗi được tiêm có kiểm soát ở harness (không phải sự cố hạ tầng thật): TypeError mạng và 500 trên GET; 400 có errors.FullName và 500 trên PUT; trì hoãn POST để kiểm tra khóa nút/form. Đã kiểm tra retry, lỗi theo trường và giữ dữ liệu/phiên. Các thao tác thành công luôn đi tới backend thật.

Viewport 1366px và 390px: không tràn ngang toàn trang; cột thao tác rộng hơn 210px trong khung bảng cuộn; modal khách hàng vừa màn hình, modal địa chỉ dài cuộn bên trong; chuyển route dọn modal. Đã mở ảnh QA để xem bố cục. Không có JavaScript exception hoặc unhandled rejection.

Bằng chứng: `customers-verification.json`, `customers-1366.png`, `customers-390.png`, `customers-modal-390.png`, `customers-address-modal-390.png` trong thư mục docs.

## Giới hạn còn lại

- API chi tiết hiện chỉ có tối đa 10 đơn gần nhất và tổng thống kê; tab ghi rõ giới hạn, chưa có API danh sách đơn đầy đủ phân trang theo customerId.
- Chưa kiểm thử tải/concurrency lớn, deadlock hoặc hạ tầng production/TLS; không tạo đơn mới thật trong đợt này, chỉ kiểm tra khả năng chọn khách hàng/địa chỉ trong form tạo đơn.
- Nếu backend đang chạy trong IDE, cần khởi động lại để nhận thay đổi controller; tải lại frontend để nhận module mới.

Chạy lại harness:

```powershell
# Từ backend/LastMile/LastMile.Api
dotnet build --no-restore
# Từ thư mục last-mile-logistics
node frontend/tests/customers-browser.cjs
```

LocalDB/Edge phải khả dụng; test cần quyền truy cập LocalDB và tự tạo/xóa database thử có GUID. `CUSTOMERS_QA_DLL` có thể chỉ tới bản build thử riêng. Fixture từ chối mọi database không đúng tiền tố/GUID và mọi SQL Server ngoài LocalDB.
