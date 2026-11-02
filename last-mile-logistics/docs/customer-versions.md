# Phiên bản khách hàng và địa chỉ

## Hành vi

`KhachHang.PhienBan` và `DiaChiKhachHang.PhienBan` là hai cột ROWVERSION độc
lập. Các API danh sách/chi tiết khách hàng và địa chỉ trả `version` Base64 từ
8 byte này; response tạo mới và sửa cũng trả version hiện tại.

Hai API PUT yêu cầu `expectedVersion`. Thiếu/rỗng, Base64 không hợp lệ hoặc
giải mã không đúng 8 byte trả 400. Các kiểm tra quyền, tài khoản, bưu cục, số
điện thoại, tọa độ, khu vực và trạng thái hoạt động được giữ nguyên.

Sau kiểm tra quyền, transaction khóa khách hàng trước, rồi địa chỉ nếu có,
bằng UPDLOCK/HOLDLOCK. Version cũ trả 409 trước khi có thao tác ghi. UPDATE
cũng có điều kiện version; dữ liệu trước/sau và nhật ký thành công cùng commit
trong transaction. Request stale không thay dữ liệu và không thêm nhật ký thành công.

Khi đổi địa chỉ mặc định, vẫn giữ quy tắc có đúng một mặc định nếu còn địa chỉ
hoạt động, và không có mặc định hoạt động nếu không còn địa chỉ hoạt động.
Khóa bản ghi khách hàng tuần tự hóa các thao tác tạo/sửa địa chỉ và thay mặc
định; unique filtered index hiện có tiếp tục bảo vệ tính duy nhất.

Mỗi địa chỉ bị bỏ/chọn mặc định đều tự tăng ROWVERSION. Sửa địa chỉ không cập
nhật version khách hàng. Hai request đổi mặc định trên hai địa chỉ khác nhau
có thể lần lượt thành công nếu version riêng của chúng vẫn hợp lệ; trạng thái
cuối vẫn chỉ có một mặc định. Form cũ của địa chỉ bị đổi mặc định theo sẽ nhận 409.

Address PUT trả thêm `affectedAddresses` gồm id, version, isDefault, isActive
của các địa chỉ bị cập nhật. Nhật ký trước/sau giữ cả metadata này để phản ánh
việc đổi mặc định gián tiếp. Response version được đọc sau khi trigger đồng bộ
tọa độ chạy xong, tránh trả version trung gian trước trigger.

Frontend giữ version từ lần đọc mở form trong closure. Submit không GET lại
để lấy version mới. Sau 409, nội dung vẫn xem/sửa/sao chép được nhưng nút Lưu
và handler submit đều bị chặn. Nút **Tải dữ liệu mới** thông báo và xác nhận
rõ việc bỏ toàn bộ nội dung chưa lưu. Hủy xác nhận không đọc lại. Nếu GET thất
bại, form cũ và nội dung vẫn được giữ, Lưu vẫn bị chặn. GET thành công mở form
mới với dữ liệu/version mới; người dùng xem lại trước khi lưu.

## Migration và triển khai

Chạy `database/migrations/20261019_customer_versions.sql` trên database ứng
dụng trước khi khởi động API mới. Migration thêm cột khi thiếu, kiểm tra đúng
kiểu ROWVERSION 8 byte và chạy lại an toàn. Không chuyển đổi/xóa dữ liệu cũ;
lần chạy lại không tự tăng version đã có. Schema V5 dùng cho cài mới cũng cần
chạy migration này cùng các migration hiện hành.

Đã áp dụng trên database Development `QLGiaoHangChangCuoi`, server
`(localdb)\MSSQLLocalDB`, ngày 19/10/2026, sau khi đối chiếu cấu hình hiệu lực.
Script kiểm tra toàn bộ dữ liệu nghiệp vụ trước/sau, gồm tọa độ, và xác nhận
12 khách hàng/13 địa chỉ giữ nguyên. Chạy lần hai không đổi version.

Công cụ hỗ trợ Development chỉ cho phép LocalDB Windows-auth, không in dữ
liệu khách hàng hay connection string:

```powershell
# Chỉ kiểm tra database/schema hiệu lực:
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/apply_customer_version_migration.ps1
# Chỉ áp dụng khi đúng database đã kiểm tra:
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/apply_customer_version_migration.ps1 -Apply -ExpectedDatabase QLGiaoHangChangCuoi
```

Với môi trường khác, chạy SQL bằng quy trình triển khai database của môi trường.
Triển khai API và frontend cùng nhau; client cũ thiếu expectedVersion sẽ nhận
400. Khởi động lại API để nạp binary mới và tải lại frontend. Không cần đổi
khóa JWT hoặc thu hồi các phiên hiện hành vì thay đổi khách hàng này.

## Kết quả kiểm chứng

- Build API vào output riêng: 0 lỗi, 0 cảnh báo.
- `npm.cmd test`: 66/66 đạt, gồm timeout/body/abort và refresh 401 đồng thời.
- `npm.cmd run test:customers`: 58 kiểm tra đạt trên HTTP/SQL và Edge thật,
  database LocalDB GUID cách ly. Không có lỗi console ở hai tab. Viewport
  1366 px và 390 px đạt; báo cáo tại `docs/customers-verification.json`.
- Hai tab thực cùng mở khách hàng: A lưu; B gửi version cũ nhận 409, giữ nội
  dung, không GET version mới khi submit và không gửi lại được. Hủy/tải lại lỗi
  không mất nội dung; tải lại thành công mới lưu được với version mới.
- Hai tab thực cùng mở địa chỉ có cùng kết quả. API stale được đối chiếu cả
  dữ liệu thắng và số nhật ký không đổi. Nhật ký thành công có version trước/sau.
- Hai request đổi mặc định đồng thời: đúng một mặc định cuối cùng, version của
  địa chỉ bị bỏ mặc định tăng và request dùng bản cũ nhận 409.
- Thiếu/null/rỗng/Base64 sai/7 byte/9 byte đều 400 cho cả hai API; PUT với version
  hợp lệ vẫn trả 403 khi thiếu quyền. Địa chỉ sai chủ sở hữu vẫn 404.
- Các ca cũ về điện thoại, tọa độ, khu vực, trạng thái, chọn mặc định thay thế,
  tạo đơn và dữ liệu điểm giao nhận lịch sử vẫn đạt.
- Hồi quy phiên đã chạy `node tests/auth-sessions.cjs`: 15/15 đạt với binary auth
  hiện có; các file xác thực không bị sửa trong tác vụ này.

Database GUID và profile Edge kiểm thử đã được dọn. Chưa chạy kiểm thử tải lớn,
nhiều instance hoặc toàn bộ browser harness của các phân hệ khác. Không thử
sửa khách hàng nghiệp vụ thật để tạo xung đột.

## File thay đổi

- Backend: `CustomerUpdateController.cs`, `CustomerAddressUpdateController.cs`,
  `CustomerDetailController.cs`, `OrderFormController.cs`,
  `CustomerCreateController.cs`, `CustomerAddressCreateController.cs`.
- Frontend: `frontend/js/customers.js`, `frontend/package.json`.
- Migration/công cụ: `20261019_customer_versions.sql`,
  `tools/apply_customer_version_migration.ps1`.
- Test: `customers-fixture.ps1`, `customers-browser.cjs`,
  `customer-version-checks.cjs`, `customer-version-browser.cjs`, `tests/README.md`.
- Tài liệu/kết quả: tài liệu này, `docs/customers-verification.json`,
  `docs/customers-1366.png`, `docs/customers-390.png`,
  `docs/customers-modal-390.png`, `docs/customers-address-modal-390.png`.
