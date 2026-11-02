# Hạn bằng lái theo ngày Việt Nam

Đã kiểm tra schema, các controller shipper, phân công/nhận nhiệm vụ, chuyến, lập tuyến, bàn giao và luồng hoàn hàng. Không tìm thấy AGENTS.md trong workspace hoặc các thư mục cha đã kiểm tra. Không cần migration.

## Quy tắc và triển khai

`NhanVienGiaoHang.NgayHetHanBangLai` vẫn là `DATE NULL`; DTO vẫn dùng `DateOnly?`, tham số SQL vẫn `SqlDbType.Date`. Ngày hết hạn không chuyển thành UTC hoặc một thời điểm nửa đêm. Bằng lái hết hạn khi và chỉ khi ngày hết hạn **nhỏ hơn** ngày Việt Nam tại thời điểm kiểm tra. `null` tiếp tục không bị loại vì hạn bằng lái, giống quy tắc cũ; các điều kiện hoạt động, quyền, phương tiện và nhiệm vụ vẫn áp dụng.

Backend dùng `Services/VietnamDate.cs`:

- `FromInstant` chuyển thời điểm có offset thành ngày UTC+07 theo quy ước Việt Nam, độc lập múi giờ máy chủ.
- `IsLicenseExpired` dùng trong kiểm tra tạo/sửa, có overload nhận thời điểm để kiểm thử.
- `SqlDate` sinh cùng biểu thức `CONVERT(DATE, DATEADD(MINUTE, 420, <biểu thức UTC>))`. Tất cả 18 phép so sánh hạn bằng lái trong SQL C# dùng helper này. Các đối số SQL là hằng do lập trình viên viết, không nhận từ request.

Frontend dùng `js/vietnam-date.js`, với `Intl.DateTimeFormat` chỉ định `Asia/Ho_Chi_Minh`; so sánh ngày `YYYY-MM-DD` trực tiếp. `shippers.js` dùng helper lúc gửi form, không dùng ngày UTC từ `toISOString()`. Script mới được tải trước các màn hình và đổi cache version cho shipper.

Lập tuyến vẫn kiểm tra hạn bằng lái theo **ngày xuất phát** tại Việt Nam, để không chọn bằng lái hết hạn trước ngày dự kiến chạy. Cả truy vấn options hiện tại và truy vấn lập/xác nhận phương án dùng helper chung. Timestamp UTC của tạo/cập nhật, khóa tài khoản, GPS, lịch sử và lịch trình được giữ nguyên; chỉ chuyển đồng hồ dùng trong so sánh hạn bằng lái.

## File đã sửa

Các đường dẫn backend dưới `backend/LastMile/LastMile.Api/`:

| File | Phạm vi |
| --- | --- |
| `Services/VietnamDate.cs` | Helper C# và biểu thức SQL chung |
| `Controllers/ShipperCreateController.cs`, `ShipperUpdateController.cs` | Kiểm tra sớm C# và kiểm tra lại trong transaction |
| `Controllers/DispatchShippersController.cs` | Lọc ứng viên và lý do không đủ điều kiện |
| `Controllers/DispatchAssignmentsController.cs` | Phân công đơn và điều kiện phân công chuyến |
| `Controllers/MyTasksController.cs` | Nhận nhiệm vụ và nhận giao lại |
| `Controllers/MyHandoversController.cs` | Xác nhận và kiểm tra điều kiện nhận bàn giao |
| `Controllers/WarehouseHandoverOrdersController.cs`, `WarehouseOutboundController.cs` | Danh sách có thể bàn giao và thao tác xuất kho |
| `Controllers/TripsController.cs`, `TripActionsController.cs` | Phân công và thao tác chuyến |
| `Controllers/ShipperVehicleController.cs` | Gắn phương tiện cho shipper hợp lệ |
| `Controllers/OrderReturnStartController.cs` | Điều kiện shipper bắt đầu hoàn |
| `Services/Routing/DispatchData.cs` | Ứng viên lập tuyến và hạn theo ngày xuất phát |

Frontend và kiểm tra:

- `frontend/js/vietnam-date.js`, `frontend/js/shippers.js`, `frontend/index.html`.
- `backend/LastMile/LastMile.Calendar.Tests/LastMile.Calendar.Tests.csproj`, `Program.cs`: kiểm tra C# và biểu thức SQL thật với thời gian cố định.
- `frontend/tests/vietnam-date.test.cjs`: đồng hồ giả lập, múi giờ trình duyệt khác nhau và mốc cuối tháng/năm nhuận.
- `frontend/tests/shipper-license-browser.cjs`: submit form thật trên Edge tại các mốc giờ yêu cầu.
- `frontend/tests/shippers-browser.cjs`, `shippers-fixture.ps1`: chạy thêm các probe ngày; fixture JWT có `sid`/migration phiên theo bản xác thực hiện tại, assertion mạng khớp bản sửa timeout.
- `frontend/package.json`, `frontend/tests/README.md`: lệnh chạy và tài liệu.
- Tài liệu này, `docs/license-date-verification.json`, `docs/shippers-verification.json`; harness shipper cập nhật ảnh `docs/shippers-1440.png`, `shippers-390.png`, `shippers-modal-390.png`.

## Kết quả kiểm chứng thực tế

Ngày kiểm tra: 19/10/2026. Không đổi giờ hệ điều hành.

| Giờ Việt Nam được kiểm soát | Hạn 19/10/2026 | Hạn 20/10/2026 |
| --- | --- | --- |
| 19/10 23:59 | Còn hiệu lực | Còn hiệu lực |
| 20/10 00:00 | Hết hiệu lực | Còn hiệu lực |
| 20/10 06:59 | Hết hiệu lực | Còn hiệu lực |
| 20/10 23:59:59 | Hết hiệu lực | Còn hiệu lực |

- Build Release API và Calendar.Tests với `--no-restore -warnaserror`: **0 lỗi, 0 cảnh báo**. Restore Calendar.Tests với NuGet Audit hoạt động đạt, không cảnh báo.
- `npm.cmd test`: **75/75 đạt**, bao gồm 6 test mới cho ngày Việt Nam, chạy thêm process với `TZ=UTC`, `America/Los_Angeles`, `Asia/Tokyo`, `Asia/Ho_Chi_Minh`. Các test API, auth, timeout và Router hiện có vẫn đạt.
- `npm.cmd run test:license-date`: **20 trường hợp C#/SQL đạt**, thêm kiểm tra hạn theo ngày xuất phát tương lai. SQL thật chỉ `SELECT` trên LocalDB `master`, dùng tham số UTC cố định; không ghi database vận hành. Kiểm tra cả dạng phát hiện hết hạn (`<`) và dạng lọc đủ điều kiện (`IS NULL OR >=`), cùng null và năm nhuận. Chi tiết tại [license-date-verification.json](license-date-verification.json).
- Hồi quy shipper với API/JWT/SQL/Edge thật: **55 kiểm tra đạt**, không có lỗi console. Bao gồm 5 probe form với thời gian cố định, thêm/sửa hồ sơ thật, phân quyền/phạm vi bưu cục, phương tiện, trạng thái, giữ form khi lỗi và API ứng viên phân công. Chi tiết tại [shippers-verification.json](shippers-verification.json). Database GUID và profile thử đã dọn.
- Các probe form giữ nguyên chuỗi ngày người dùng nhập. Chỉ chặn POST ở các trường hợp hết hạn. Đối với probe hợp lệ, request được trả lỗi thử có kiểm soát để không ghi dữ liệu ngày giả vào SQL; những bước tạo/sửa thông thường trong harness vẫn gọi API thật.
- Rà soát nguồn sau sửa xác nhận toàn bộ **18** nơi so sánh SQL dùng `VietnamDate.SqlDate`. Trong hai file SQL schema/seed, hạn bằng lái chỉ có khai báo DATE và dữ liệu seed; không có phép kiểm tra hạn riêng cần migration.

Chạy lại từ `frontend`:

```powershell
npm.cmd test
npm.cmd run test:license-date
```

Để chạy harness shipper, build API ra thư mục thử rồi chỉ rõ DLL (chạy từ gốc dự án):

```powershell
dotnet build backend/LastMile/LastMile.Api/LastMile.Api.csproj --no-restore -c Release -warnaserror --output frontend/tests/.artifacts/license/build
$env:SHIPPERS_QA_DLL = (Resolve-Path frontend/tests/.artifacts/license/build/LastMile.Api.dll).Path
node frontend/tests/shippers-browser.cjs
```

## Giới hạn

Chưa chạy lại toàn bộ luồng phân công → nhận nhiệm vụ → xuất kho → nhận bàn giao hoặc lập/xác nhận tuyến qua HTTP tại các thời điểm giả lập. Các truy vấn đó đã đổi helper và build đạt; quy tắc SQL chung đã được thực thi với giờ cố định, API ứng viên phân công và quản lý shipper được kiểm chứng thật như trên. Chưa thử triển khai Linux, Chrome/Firefox/Safari hoặc đồng hồ máy chủ/trình duyệt bị sai giờ; helper không phụ thuộc múi giờ cục bộ nhưng vẫn cần đồng hồ UTC của hệ thống đúng.
