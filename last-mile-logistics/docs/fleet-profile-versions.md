# Phiên bản hồ sơ shipper và phương tiện

Chẩn đoán runtime tiếp theo đã xác nhận database `QLGiaoHangChangCuoi` đang thiếu `PhienBan` ở cả hai bảng shipper/phương tiện. Xem [nguyên nhân, controller/câu SQL và bước chạy migration thủ công](version-schema-runtime.md), cùng [báo cáo schema thực tế](version-schema-diagnostic.json). Phần kiểm tra mock dưới đây là kết quả của bước triển khai ExpectedVersion ban đầu; migration vẫn chưa được tự chạy.

## Migration bắt buộc trước khi triển khai

Schema trong `database/QLGiaoHangChangCuoi_SQLServer_V5 .sql` chưa có cột phiên bản ở `dbo.NhanVienGiaoHang` và `dbo.PhuongTien`; các migration cũ cũng chưa bổ sung cho hai bảng này. Không truy vấn hoặc thay đổi schema database vận hành trong lần sửa này.

**Cần chạy riêng `database/migrations/20261019_shipper_vehicle_versions.sql` trên database đích trước khi dùng API mới.** Script thêm `PhienBan ROWVERSION NOT NULL` nếu chưa có, kiểm tra bảng/cột và kiểu 8 byte, chạy trong transaction và rollback khi lỗi. Có thể chạy lại khi cột đã đúng. Script không được ứng dụng tự chạy; chưa chạy script trên bất kỳ database nào trong lần sửa này. Giữ nguyên script tạo schema gốc; database mới cũng cần migration này.

## Hợp đồng API

- GET `/api/v1/shippers?id=...` và `/api/v1/vehicles?id=...` trả `version` là Base64 của 8 byte. Danh sách cũng trả version.
- PUT `/api/v1/shippers/{id}` bắt buộc `expectedVersion`.
- POST `/api/v1/vehicles` có `id` là cập nhật và bắt buộc `expectedVersion`; tạo mới (`id` null/không có) không yêu cầu trường này.
- Phiên bản thiếu, Base64 lỗi hoặc giải mã khác 8 byte trả 400. Phiên bản đúng định dạng nhưng cũ trả 409 với `code: "VERSION_CONFLICT"`.
- Lưu thành công trả `version` mới; tạo phương tiện cũng trả version.

Tái sử dụng cơ chế Base64/BINARY(8)/ROWVERSION như khách hàng và đơn hàng. Transaction kiểm tra quyền/phạm vi rồi đọc phiên bản hiện tại dưới `UPDLOCK, HOLDLOCK`, so với `@ExpectedVersion`; UPDATE vẫn có điều kiện `PhienBan = @ExpectedVersion` và kiểm tra `@@ROWCOUNT`. Mismatch được THROW/ROLLBACK trước thay đổi khu vực hoặc nhật ký thành công. Không chuyển sang lấy phiên bản mới rồi tự gửi lại request cũ.

Quy tắc quyền, tài khoản/bưu cục, nhiệm vụ đang mở, chuyến, hoàn hàng, liên kết xe, tải trọng/sức chứa và bằng lái lịch sử giữ nguyên. Rowversion thay đổi khi bất kỳ UPDATE nào trên hàng xảy ra, kể cả nghiệp vụ khác cập nhật trạng thái/vị trí shipper; khi đó form cũ phải đối chiếu lại.

## Form và xử lý xung đột

Form sửa và đổi trạng thái giữ cố định version nhận lúc mở, gửi `expectedVersion` cùng dữ liệu. Khi nhận `VERSION_CONFLICT`, nội dung nhập được giữ, thao tác gửi bị khóa ngay cả nếu nút được bật lại bên ngoài. Người dùng có thể bấm **Tải bản mới để đối chiếu**: chỉ GET hồ sơ hiện tại và hiển thị cạnh nội dung nhập. GET thành công/thất bại đều không đổi version của form và không gửi lại request ghi. Sau khi đối chiếu, đóng rồi mở lại biểu mẫu để sửa có chủ đích từ bản mới.

Validation và 409 nghiệp vụ khác (nhiệm vụ còn mở, CCCD/biển số trùng) vẫn cho sửa. Form phương tiện cũng giữ khóa kết quả ghi chưa xác định qua `WriteOutcome`; bổ sung đường GET phương tiện hiện có cho việc kiểm tra này.

## Kiểm tra đã chạy

Từ thư mục gốc:

```powershell
dotnet build backend/LastMile/LastMile.Calendar.Tests/LastMile.Calendar.Tests.csproj --no-restore -c Release -warnaserror --output frontend/tests/.artifacts/fleet-version/release
dotnet frontend/tests/.artifacts/fleet-version/release/LastMile.Calendar.Tests.dll --fleet-version .
dotnet frontend/tests/.artifacts/fleet-version/release/LastMile.Calendar.Tests.dll --shipper-update .
node --test frontend/tests/fleet-version.test.cjs frontend/tests/shipper-license-update.test.cjs frontend/tests/write-outcome.test.cjs
```

- Build API/bộ kiểm tra: 0 warning, 0 error.
- Phiên bản backend: 54 kiểm tra đạt qua controller thật và `DbConnection` giả lập. A/B cùng version, A nhận version mới, B 409 không sửa dữ liệu/nhật ký, mở lại sửa thành công; kiểm tra cả bật/tắt, version thiếu/sai định dạng/7 byte/9 byte và tạo phương tiện không cần version.
- Hồi quy bằng lái backend: 36 tình huống, 203 kiểm tra đạt; bổ sung ExpectedVersion hợp lệ vào fixture.
- Frontend tập trung: 57/57 kiểm tra đạt. Hai form cùng bản ghi, giữ draft, GET đối chiếu không tự gửi, GET lỗi, sửa lại có chủ đích, validation/409 nghiệp vụ và khóa kết quả ghi chưa xác định.
- Toàn bộ frontend: `npm.cmd test` trong `frontend`, **199/199 kiểm tra đạt**, bao gồm proxy HTTP giả lập, quản lý timeout/hủy, điều phối và các form ghi.

Không chạy SQL Server, migration hoặc ghi database thật. Fake command mô phỏng bộ nhớ lưu trữ, kiểm tra SQL/tham số tại ranh giới và trả lỗi SqlClient; chưa chứng minh thực thi SQL, Base64 do SQL FOR JSON sinh ra hoặc khóa đồng thời trên SQL Server thật. Các bộ kiểm tra HTTP/browser dùng database riêng cần áp dụng migration và gửi expectedVersion cho các request cập nhật trực tiếp trước khi chạy; không chạy các bộ đó trong lần sửa này.

## File thay đổi

- Backend: `ShipperUpdateController.cs`, `VehicleSaveController.cs`, `ShippersController.cs`, `VehiclesController.cs`.
- Frontend: `shippers.js`, `vehicles.js`, `write-outcome.js`.
- Migration: `20261019_shipper_vehicle_versions.sql`.
- Kiểm tra: `LastMile.Calendar.Tests/Program.cs`, `ShipperUpdateChecks.cs`, `FleetVersionChecks.cs`, `frontend/tests/fleet-version.test.cjs`.
