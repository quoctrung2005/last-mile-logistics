# Kiểm tra contract kết quả SQL của đơn hàng và kho

Không tìm thấy AGENTS.md trong workspace và các thư mục cha đã kiểm tra. Bản sửa tập trung vào năm luồng ghi: sửa đơn, xác nhận đơn, chuyển vị trí, tạo đơn và nhập kho. Không thay quyền, phạm vi, expectedVersion, lịch giao, logic phí, tồn kho hoặc cơ chế xác thực.

## Contract đã đối chiếu

| Luồng | Kết quả SQL thành công | HTTP giữ nguyên |
| --- | --- | --- |
| PUT orders/{id} | Một dòng: Version binary(8), WeightKg decimal, ShippingFee decimal | 200; id, status, version Base64, weightKg, shippingFee, lịch giao, message |
| POST orders/{id}/confirm, đọc snapshot | Không có dòng nếu không tìm thấy trong phạm vi; nếu có: Version binary(8), Status text, PointsJson mảng JSON | Không tìm thấy vẫn 404; trạng thái/version không còn phù hợp vẫn 409 |
| POST orders/{id}/confirm, ghi | Một dòng: RuleId bigint dương, WeightKg decimal, CalculatedFee decimal, TotalFee decimal, Version binary(8) | 200; toàn bộ dữ liệu phí/tuyến/version hiện có |
| POST warehouse-transactions/move | Một dòng: TransactionId bigint dương, WarehouseId int dương | 201; mã giao dịch, đơn, kho, vị trí nguồn/đích, message |
| POST orders | Một dòng: OrderId bigint dương | 201; id, mã đơn/vận đơn, trạng thái, khối lượng, lịch giao, message |
| POST warehouse-transactions/inbound | Một dòng: TransactionId bigint dương | 201; giao dịch, đơn, kho, vị trí, trạng thái đơn/tồn kho, message |

SQL của các luồng ghi thực hiện COMMIT trước SELECT cuối. Không thể suy ra giao dịch thất bại chỉ từ việc không đọc được kết quả.

Đã đọc schema/procedure/trigger trong `database/QLGiaoHangChangCuoi_SQLServer_V5 .sql`. `sp_XacNhanDonHang` gọi `sp_ChuyenTrangThaiDonHang`; hai procedure chỉ thực hiện nghiệp vụ, không trả result set. Các trigger liên quan có SET NOCOUNT ON, không SELECT dữ liệu ra client. Đã đối chiếu chỉ đọc trên LocalDB Development `QLGiaoHangChangCuoi`: **2 procedure và 8 trigger khớp repository**, sau khi chuẩn hóa comment đầu batch/cú pháp CREATE mà SQL Server lưu. Kết quả tại `sql-results-database-inspection.json`.

Không cần sửa schema/migration. Các lệnh EXEC nghiệp vụ trong xác nhận đơn và nhập kho nay khai báo **WITH RESULT SETS NONE** để chặn kết quả vô tình thêm trong procedure/trigger của procedure ngay tại điểm gọi SQL. Không dùng NextResult để tìm rồi bỏ qua các result set lạ.

## Xử lý mới

`Services/SqlResult.cs` kiểm tra đúng tên/số lượng cột, đúng một dòng và một tập kết quả. Chỉ truy cập giá trị sau ReadAsync thành công; từ chối NULL/DBNull, sai kiểu SQL, ID không dương, version khác 8 byte, phí/khối lượng âm. Snapshot yêu cầu mảng JSON hợp lệ. Trường hợp không có snapshot được khai báo riêng để giữ 404. Đọc đến hết command để phát hiện dòng/tập kết quả dư và lỗi SQL xuất hiện sau dòng kết quả.

Tạo đơn và nhập kho chuyển từ ExecuteScalarAsync/Convert.ToInt64 sang đọc ID có tên cột qua cùng helper. Điều này vừa tránh null thành ID=0 vừa phát hiện SELECT dư từ trigger thay vì nhận nhầm scalar đầu tiên.

Lỗi contract trả **500**, không trả 200/201 rỗng. Nếu đã bắt đầu lệnh ghi, phản hồi:

```json
{
  "message": "Không đọc được kết quả xử lý. Hãy tải lại để kiểm tra trạng thái.",
  "code": "SQL_RESULT_UNAVAILABLE",
  "resultUnknown": true
}
```

Không tự chạy lại lệnh ghi. Các mã lỗi nghiệp vụ hiện có (quyền, không tìm thấy, validation, version/vị trí cũ) giữ nguyên. Lỗi snapshot trước bước ghi không gắn cờ kết quả ghi chưa xác định. Hủy command xác nhận khi đã bắt đầu ghi cũng dùng thông báo chưa xác định.

Log có endpoint, mã đơn/mã tạo đơn, đã bắt đầu ghi hay chưa và lý do contract. Lỗi SQL ghi number/procedure/line/state; không ghi exception message có thể chứa giá trị bản ghi, payload, JSON kết quả, token hoặc mật khẩu.

ApiClient truyền cờ `resultUnknown` của lỗi HTTP sang giao diện, giữ cơ chế 401/refresh hiện tại. Form đơn giữ nội dung và chặn gửi lại; hộp xác nhận/lịch giao yêu cầu tải lại. Kho/nhập kho giữ thông báo chưa xác định thay vì thay bằng thông báo 500 chung. Các luồng khóa gửi lại hiện có của kho tiếp tục hoạt động. Cache version các script đã đổi.

## File thay đổi

- `backend/LastMile/LastMile.Api/Services/SqlResult.cs` (mới).
- Controllers: `OrderUpdateController.cs`, `OrderConfirmController.cs`, `WarehouseMoveController.cs`, `OrderCreateController.cs`, `WarehouseInboundController.cs`.
- `frontend/js/api.js`, `orders.js`, `warehouse.js`, `inbound.js`; `frontend/index.html`.
- `backend/LastMile/LastMile.SqlResults.Tests/LastMile.SqlResults.Tests.csproj`, `Program.cs` (mới, không thêm package).
- `frontend/tests/api.test.cjs`, `order-unsaved-browser.cjs`, `README.md`.
- `tools/InspectSqlResultContracts.ps1` (chỉ SELECT metadata), tài liệu này và các báo cáo JSON: `sql-results-verification.json`, `sql-results-database-inspection.json`, `order-unsaved-verification.json`.

## Kiểm tra thực tế

- Restore project test thành công, giữ NuGet Audit. Build API và project test Release `--no-restore -warnaserror`: **0 lỗi, 0 cảnh báo**.
- `npm.cmd test`: **80/80 đạt**, gồm 5 ca mới chứng minh mỗi endpoint ghi gặp SQL result 500 chỉ gửi một lần và giữ cờ/chỉ dẫn tải lại. Các ca timeout, hủy body, refresh/401 đồng thời hiện có vẫn đạt.
- `LastMile.SqlResults.Tests`: **45 ca đạt** trên SQL Server LocalDB thật. Tự tạo database GUID `CodexSqlResults_*`, dùng schema/seed, gọi controller thật với quyền live SQL; dùng mạng đường và procedure thật để xác nhận/tính phí. Tạo/sửa/xác nhận/nhập/chuyển vị trí thành công trả đủ dữ liệu; stale version vẫn 409 và không thêm audit; stale vị trí vẫn 409, tồn kho đúng; quyền vẫn bị từ chối; snapshot không tồn tại vẫn 404.
- Fault injection chỉ trong database GUID: no result, empty row set, NULL, sai kiểu, thiếu/thừa/trùng cột, nhiều dòng, nhiều tập kết quả, rowversion sai độ dài, JSON snapshot sai. Trigger trả rỗng/thiếu/NULL/dư trong sửa đơn; NULL ID trong tạo/nhập/chuyển vị trí đều bị xử lý có kiểm soát. Procedure trả dư bị SQL 11535 tại WITH RESULT SETS NONE và toàn bộ xác nhận/đổi phí rollback. Không đưa fault hook vào API.
- Ca COMMIT rồi SELECT NULL xác nhận dữ liệu **vẫn được lưu** khi đọc kết quả thất bại; vì vậy thông báo không khẳng định chưa lưu.
- Kiểm tra log giữ endpoint/object/reason, không có nội dung payload/kết quả. Database thử được dọn ở finally.
- `node frontend/tests/order-unsaved-browser.cjs`: **39 kiểm tra đạt**, không lỗi console/unhandled rejection; form sửa gặp SQL result 500 giữ bản nhập, chặn submit và có nút kiểm tra; dialog xác nhận có chỉ dẫn tải lại và không gửi lại qua nút disabled. Bộ này dùng Edge/app/Router thật với API giả lập, không ghi đơn thật. Ba hộp thoại beforeunload native và các ca 400/409/500 trước đây vẫn đạt.

Lệnh đã dùng, từ gốc dự án:

```powershell
dotnet restore backend/LastMile/LastMile.SqlResults.Tests/LastMile.SqlResults.Tests.csproj -warnaserror
dotnet build backend/LastMile/LastMile.Api/LastMile.Api.csproj --no-restore -c Release -warnaserror --output frontend/tests/.artifacts/sql-results/build
dotnet build backend/LastMile/LastMile.SqlResults.Tests/LastMile.SqlResults.Tests.csproj --no-restore -c Release -warnaserror --output frontend/tests/.artifacts/sql-results/tests
dotnet frontend/tests/.artifacts/sql-results/tests/LastMile.SqlResults.Tests.dll .
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/InspectSqlResultContracts.ps1
node frontend/tests/order-unsaved-browser.cjs
```

Chạy `npm.cmd test` trong thư mục frontend. LocalDB/Edge cần quyền truy cập user profile của người chạy.

## Giới hạn kiểm chứng

SQL harness gọi controller trực tiếp với principal thử và kiểm tra quyền trong database; không kiểm thử HTTP/JWT middleware. Không gây mất kết nối TCP đúng thời điểm COMMIT trên database vận hành. Trường hợp đã commit nhưng mất kết quả được mô phỏng bằng SQL thật COMMIT rồi trả dữ liệu không hợp lệ. Không chạy giao diện kho end-to-end cho các lỗi SQL mới hoặc hồi quy mọi endpoint SQL ngoài năm luồng đã sửa. Database Development chỉ được đọc metadata, không ghi dữ liệu nghiệp vụ. Cần khởi động lại API đang chạy bằng bản cũ để nạp backend mới.
