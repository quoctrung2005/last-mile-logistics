# Chẩn đoán runtime: Invalid column name 'PhienBan'

## Nguyên nhân đã xác nhận bằng SQL Server

Dùng chính cấu hình hiệu lực của API host ở môi trường **Development** (như `Properties/launchSettings.json`), gồm appsettings, user secrets, biến môi trường và đối số dòng lệnh. Provider quyết định DefaultConnection là **appsettings.json**. Kết nối đã mở thực tế tới **`(localdb)\MSSQLLocalDB`**, và `SELECT DB_NAME()` xác nhận database **`QLGiaoHangChangCuoi`**. Không in connection string đầy đủ, thông tin đăng nhập, token hay dữ liệu người dùng.

Metadata thực tế (`sys.tables`, `sys.columns`) xác nhận:

| Bảng | PhienBan | Rowversion tên khác |
| --- | --- | --- |
| dbo.NhanVienGiaoHang | **Thiếu** | Không có |
| dbo.PhuongTien | **Thiếu** | Không có |
| dbo.KhachHang | Có, 8 byte NOT NULL | Không có |
| dbo.DiaChiKhachHang | Có, 8 byte NOT NULL | Không có |
| dbo.TaiKhoan | Có, 8 byte NOT NULL | Không có |
| dbo.DonHang | Có, 8 byte NOT NULL | Không có |

SQL Server hiển thị tên kiểu `timestamp` cho ROWVERSION (system_type_id 189); không phải cột ngày giờ. Tài khoản kiểm tra có VIEW DEFINITION trên các bảng, nên kết luận thiếu cột không xuất phát từ metadata bị ẩn do quyền.

**Nguyên nhân là migration shipper/phương tiện chưa được áp dụng trên database này.** Schema V5 gốc không tạo cột đó. Migration khách hàng đã có hiệu lực; không cần chạy lại migration khách hàng hoặc dựng lại database. Alias hiện tại đúng bảng.

## Controller và câu SQL lỗi

| Controller/action | Vị trí trong source | Tham chiếu / bảng | Kiểm tra runtime |
| --- | --- | --- | --- |
| ShippersController.Get | cột ở dòng 137, ExecuteScalarAsync ở dòng 344 | `CONVERT(BINARY(8), nv.PhienBan) AS Version`, `dbo.NhanVienGiaoHang nv`; sau đó `s.Version` trong `#Shippers s` | **Action GET thật lỗi 207, dòng 63 của batch SQL** |
| VehiclesController.Get | cột ở dòng 206, ExecuteScalarAsync ở dòng 479 | `CONVERT(BINARY(8), pt.PhienBan) AS Version`, `dbo.PhuongTien pt`; sau đó `v.Version` trong `#Vehicles v` | **Action GET thật lỗi 207, dòng 109 của batch SQL** |
| ShipperUpdateController.Update | cột ở dòng 176, ExecuteScalarAsync ở dòng 446 | `@CurrentVersion = nv.PhienBan` từ `dbo.NhanVienGiaoHang nv`; UPDATE cùng bảng có `PhienBan = @ExpectedVersion` | Probe SELECT TOP(0) cùng bảng/alias lỗi 207; **không gọi action ghi** |
| VehicleSaveController.Save | cột ở dòng 201, ExecuteScalarAsync ở dòng 465 | `SELECT @CurrentVersion = PhienBan FROM dbo.PhuongTien`; UPDATE cùng bảng có `PhienBan = @ExpectedVersion` | Probe SELECT TOP(0) cùng bảng/cột lỗi 207; **không gọi action ghi** |

`VehiclesController.GetTypes` dùng lại `Get` để kiểm tra quyền, nên endpoint danh mục loại phương tiện cũng có thể gặp cùng lỗi. Không đổi alias hoặc bỏ ExpectedVersion để né lỗi. Các probe dùng SELECT TOP(0), không đọc dữ liệu nghiệp vụ. Chẩn đoán GET gọi trực tiếp action với tài khoản ADMIN hiện có và vẫn đi qua kiểm tra quyền trong SQL; không gọi login, không tạo session và không kiểm tra middleware JWT/HTTP.

Kết quả đầy đủ đã lọc dữ liệu nhạy cảm: `docs/version-schema-diagnostic.json`.

### Kiểm tra riêng bảng tạm và CTE

Trong SQL của `ShippersController.Get` chỉ có **một tham chiếu trực tiếp `PhienBan`**, tại dòng 137: `nv.PhienBan`. `nv` là alias bảng thật `dbo.NhanVienGiaoHang`, không phải CTE/bảng tạm. Truy vấn nguồn đã chiếu `CONVERT(BINARY(8), nv.PhienBan) AS Version` vào `#Shippers` ở dòng 165. Cả nhánh chi tiết (dòng 231) và danh sách (dòng 282) đều dùng **`s.Version AS version`**, với `s` là alias `#Shippers`. Không có `s.PhienBan`, không thiếu trường ở bảng tạm và không cần đổi alias để né lỗi.

Tương tự với phương tiện: dòng 206 lấy `pt.PhienBan` từ bảng thật `dbo.PhuongTien pt`, chiếu thành `Version` vào `#Vehicles` (dòng 217); nhánh chi tiết/danh sách dùng `v.Version` (dòng 295/412), không dùng `v.PhienBan`.

Đã kiểm tra lại cả danh sách và chi tiết với bản ghi hiện có trên SQL Server; **cả bốn lượt gọi GET vẫn lỗi 207**. Báo cáo có `checkedAtUtc` và `mode: list/detail` để phân biệt lần kiểm tra này với lần trước chỉ gọi danh sách. Không sửa cấu hình sang database khác vì cấu hình hiệu lực và `DB_NAME()` đều xác nhận đúng `QLGiaoHangChangCuoi`.

Kết quả runtime mới nhất (xem thời điểm trong báo cáo JSON):

| Trường hợp | Cột nguồn | Cột đã chiếu vào bảng tạm | Kết quả SQL Server |
| --- | --- | --- | --- |
| Danh sách shipper | `dbo.NhanVienGiaoHang.PhienBan` đang thiếu | Nguồn `AS Version`, đầu ra `s.Version` đã đúng | SQL 207, dòng batch 63 |
| Chi tiết shipper | `dbo.NhanVienGiaoHang.PhienBan` đang thiếu | Nguồn `AS Version`, đầu ra `s.Version` đã đúng | SQL 207, dòng batch 63 |
| Danh sách phương tiện | `dbo.PhuongTien.PhienBan` đang thiếu | Nguồn `AS Version`, đầu ra `v.Version` đã đúng | SQL 207, dòng batch 109 |
| Chi tiết phương tiện | `dbo.PhuongTien.PhienBan` đang thiếu | Nguồn `AS Version`, đầu ra `v.Version` đã đúng | SQL 207, dòng batch 109 |

Batch lỗi tại projection đọc bảng nguồn. Chưa thể kiểm chứng Base64 của bốn nhánh thành công trên database này khi cột nguồn chưa được thêm. Không sửa bộ lọc, quyền, phân trang hoặc điều kiện chọn phương tiện trong quá trình chẩn đoán; không thêm projection trùng hoặc rowversion thứ hai để xử lý một lỗi schema nguồn.

`ShipperUpdateController` và `VehicleSaveController` cùng tham chiếu cột ở đúng bảng thật, bind ExpectedVersion dưới dạng `BINARY(8)` và giữ điều kiện UPDATE theo phiên bản. Form sửa/đổi trạng thái gửi `openedVersion` lấy từ bản ghi khi mở; việc GET đối chiếu không đổi version của draft. Các kiểm tra này giữ nguyên, không tạo token thay thế khi database thiếu cột.

## Bước người vận hành cần thực hiện

1. Kết nối SSMS tới **`(localdb)\MSSQLLocalDB`** bằng Windows Authentication.
2. Chọn database **`QLGiaoHangChangCuoi`**.
3. Mở và chạy **`database/migrations/20261019_shipper_vehicle_versions.sql`**. Script đã bổ sung guard đúng database, kiểm tra bảng/cột, từ chối rowversion tên khác, kiểm tra kiểu 8 byte và rollback khi lỗi. Không xóa bảng, dữ liệu hay tạo lại database; chạy lại khi cột đã đúng không thêm cột nữa.
4. Kết quả metadata sau script cần có hai dòng `PhienBan`, kiểu timestamp/rowversion, `bytes = 8`, `nullable = 0`.
5. Chạy lại chẩn đoán chỉ đọc bên dưới, rồi tải lại trang/mở lại form để lấy version thật. Không dùng payload/form cũ hoặc tự thay version trong dữ liệu cũ để gửi lại.

Có thể chạy **`database/diagnostics/verify_shipper_vehicle_versions.sql`** trong SSMS trước và sau migration. Script này chỉ SELECT metadata, hiển thị cả rowversion tên khác nếu có và không phát sinh lỗi biên dịch do cột `PhienBan` chưa tồn tại. Đã chạy script kiểm tra này trên SQL Server thật: hai bảng tồn tại nhưng đều có `schemaReady = 0`, không có cột rowversion nào. **Đây là script kiểm tra, không phải script sửa schema.**

Lựa chọn dòng lệnh thay cho SSMS, chạy **thủ công** từ gốc dự án:

```powershell
sqlcmd -S "(localdb)\MSSQLLocalDB" -E -d QLGiaoHangChangCuoi -b -f 65001 -i "database\migrations\20261019_shipper_vehicle_versions.sql"
```

Không tự chạy lệnh này trong lần sửa hiện tại. Nếu triển khai trên database tên khác, phải xác nhận DefaultConnection ở môi trường đó rồi sửa `@ExpectedDatabase` trong script cho đúng; không bỏ guard.

## Công cụ và kết quả kiểm tra

Đã thêm chế độ CLI trước khi API bắt đầu chạy HTTP. Khi không bật cờ, cách chạy API hiện tại giữ nguyên. Chế độ này không tự chạy migration:

```powershell
dotnet build backend/LastMile/LastMile.Api/LastMile.Api.csproj --no-restore -c Release -warnaserror --output frontend/tests/.artifacts/version-schema/release
dotnet frontend/tests/.artifacts/version-schema/release/LastMile.Api.dll --contentRoot D:\DA_CN_logistics\last-mile-logistics\backend\LastMile\LastMile.Api --environment Development --SchemaDiagnostics:Version=true --SchemaDiagnostics:ReadControllers=true
```

Exit code `2` hiện tại là kết quả chẩn đoán **schema chưa sẵn sàng**, không phải build lỗi. `1` là lỗi cấu hình/kết nối/chẩn đoán, chỉ in loại lỗi và mã SQL, không in exception/connection string. Exit `0` nghĩa là các cột phiên bản được kiểm tra đã đúng; kiểm tra thêm mục `readControllers` để xem quyền/GET và Base64 thực tế. Công cụ không gửi request ghi để kiểm tra xung đột.

- **Build:** API và bộ kiểm tra Release đạt, 0 warning, 0 error.
- **SQL Server runtime thật:** kết nối database đích thành công; metadata xác nhận hai cột thiếu; probe SQL lỗi 207; bốn lượt gọi GET danh sách/chi tiết shipper/phương tiện thật tái hiện lỗi tại ExecuteScalarAsync. Script kiểm tra metadata cho SSMS chạy thành công và báo schema chưa sẵn sàng. Không thay đổi schema hoặc dữ liệu ứng dụng.
- **Kiểm tra tự động không kết nối database:** 32 kiểm tra chẩn đoán/không lộ bí mật, kiểm tra version JSON danh sách/chi tiết và cấu trúc migration; 54 kiểm tra ExpectedVersion qua controller với DbConnection giả lập; 203 kiểm tra bằng lái; 10 kiểm tra form frontend đều đạt.
- **Chưa kiểm tra:** thực thi/re-run migration, API đọc/lưu sau migration và xung đột ghi trên SQL Server thật. Những bước đó chưa thể xác nhận khi script chưa được người vận hành áp dụng. Build thành công không chứng minh database đã có cột.

API đọc/lưu vẫn trả version Base64 từ ROWVERSION; cập nhật vẫn bắt buộc ExpectedVersion đúng 8 byte, kiểm tra nguyên tử và trả 409 khi cũ. Không tạo version giả hoặc thêm fallback bỏ kiểm tra.

File thay đổi: `Program.cs`, `Services/VersionSchemaDiagnostics.cs`, `20261019_shipper_vehicle_versions.sql`, `database/diagnostics/verify_shipper_vehicle_versions.sql`, `LastMile.Calendar.Tests/Program.cs`, `VersionSchemaChecks.cs`, tài liệu này, báo cáo JSON và liên kết từ `fleet-profile-versions.md`.
