# Lỗi lookup refresh token ngày 19/10/2026

## Nguyên nhân thực tế

Đã gọi chính `AuthTokenService.RefreshAsync` bằng Microsoft.Data.SqlClient,
với token chẩn đoán ngẫu nhiên không thuộc tài khoản nào. Cấu hình Development
hiệu lực lấy `DefaultConnection` từ `appsettings.json`:

- Server: `(localdb)\MSSQLLocalDB`, Windows authentication.
- Database SQL thực sự kết nối: `QLGiaoHangChangCuoi`.
- Exception đầy đủ và chuỗi InnerException đã được đọc. Exception là
  `Microsoft.Data.SqlClient.SqlException`, Number 207, State 1, Class 16,
  thông báo `Invalid column name 'MaPhien'.`; không có InnerException.
- Stack chỉ tới `lookup.ExecuteReaderAsync` trong `AuthTokenService`.

Lookup gây lỗi:

```sql
SELECT MaTaiKhoan, MaPhien
FROM dbo.TokenLamMoi
WHERE GiaTriBamToken = @Hash;
```

Trước sửa database, `TokenLamMoi` có `MaTaiKhoan BIGINT` và hash VARCHAR(255),
nhưng chưa có `MaPhien`; bảng `PhienDangNhap` cũng chưa tồn tại. Đây là lỗi
thiếu migration, không phải reader còn mở hay token đã hết hạn.

## Thay đổi và migration đã áp dụng

Đã áp dụng đúng `database/migrations/20261019_auth_sessions.sql` lên database
Development nêu trên, qua tool chỉ cho phép LocalDB Windows-auth và yêu cầu tên
database khớp tên đã xác minh. Script đã chạy thành công hai lần. Số lượng
16 tài khoản và 42 refresh token trước/sau giữ nguyên; không xóa hoặc sửa hash
token/tài khoản. Sau migration:

- `TokenLamMoi.MaPhien`: `UNIQUEIDENTIFIER NULL`, 16 byte.
- `PhienDangNhap.MaPhien`: `UNIQUEIDENTIFIER NOT NULL`, có khóa chính.
- Phiên có chủ tài khoản BIGINT, thời gian UTC DATETIME2(0), mốc thu hồi nullable.
- Khóa ngoại ghép phiên/tài khoản được tạo, bật và trusted; có các index của migration.

Token cũ vẫn được giữ trong database với `MaPhien IS NULL`; refresh trả 401,
yêu cầu đăng nhập lại. Không tự chuyển token cũ thành phiên mới. Kiểm tra `sid`
và thu hồi phiên trong JWT validation tiếp tục được giữ nguyên.

`AuthTokenService.cs` nay thể hiện phạm vi reader lookup bằng khối `await using`
riêng, đóng reader trước lệnh tiếp theo trên cùng connection. Phạm vi cũ cũng
đã dispose ở cuối nhánh `if`; thay đổi này làm vòng đời rõ ràng và được kiểm
chứng với `MultipleActiveResultSets=False`.

`AuthRefreshController.cs` ghi đầy đủ SQL exception cùng mã lỗi và server/database,
rồi `throw;` giữ nguyên stack. Không ghi connection string, body, token hoặc mật
khẩu. SQL/schema lỗi tiếp tục là lỗi server, không bị chuyển thành 401. Riêng
deadlock 1205 giữ response 409 hiện có.

## Kiểm tra

- Lookup trên database Development sau migration chạy xong, token chẩn đoán
  bị từ chối theo cơ chế xác thực; không còn SQL 207.
- `npm.cmd run test:auth-sessions`: 15/15 đạt; build API riêng, 0 lỗi/0 cảnh báo; kiểm thử
  HTTP với LocalDB GUID cách ly. Ca mới tạm bỏ cột trên fixture xác nhận 500,
  log SQL 207, rồi áp dụng lại migration và nhận 401 cho token không hợp lệ.
- Bộ này chạy login thật, refresh giữ nguyên `sid` khi MARS tắt, logout và dùng
  lại access/refresh cũ, đổi mật khẩu/admin reset/recovery reset thu hồi các phiên,
  token legacy không phiên, nhiều phiên và refresh/401 đồng thời.
- `npm.cmd test` đạt 66/66.

Kiểm thử login/đổi mật khẩu dùng tài khoản ngẫu nhiên trong database cách ly,
không dùng tài khoản thật trong database Development. Không khởi động lại hoặc
đăng xuất thay người dùng; nếu API/debugger còn chạy binary cũ thì cần khởi động
lại để nạp thay đổi log và phạm vi reader, sau đó đăng nhập mới trên frontend.

## Chẩn đoán/chạy lại

Tool `tools/AuthSessionDiagnostics` đọc cấu hình theo thứ tự của API Development:
appsettings, appsettings.Development, user secrets, biến môi trường. Chỉ in nguồn
cấu hình, danh tính database, schema và exception; không in giá trị bí mật.

```powershell
dotnet build tools/AuthSessionDiagnostics/AuthSessionDiagnostics.csproj --output frontend/tests/.artifacts/auth-diagnostics/build
dotnet frontend/tests/.artifacts/auth-diagnostics/build/AuthSessionDiagnostics.dll D:/DA_CN_logistics/last-mile-logistics inspect
```

Chế độ `apply QLGiaoHangChangCuoi` thay cho `inspect` chỉ dùng sau khi đã xác minh
đúng database phát triển; nó chạy migration hai lần và đối chiếu số bản ghi.
Migration gốc không cần thay đổi cho lỗi này.
