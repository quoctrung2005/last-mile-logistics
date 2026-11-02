# Chọn phương tiện để gán/đổi xe cho shipper

Đã kiểm tra form dùng chung trong `shippers.js`, lối mở từ `vehicles.js`, API tìm/lưu xe, danh mục loại xe và schema. Không tìm thấy AGENTS.md trong workspace hoặc các thư mục cha đã kiểm tra. Không cần migration hoặc dependency mới.

## Hành vi mới

- Mở form hoặc tiếp tục sau khi chọn shipper tự tải trang đầu, từ khóa trống; gửi `forShipperId`, `branchId` thực tế, `assignableOnly=true` và `includeUnavailable=true`. Lấy danh mục từ `GET /api/v1/vehicles/types`, hiển thị tên tiếng Việt theo cấu hình: Tất cả, Xe máy, Xe tải, Xe tải 1 tấn.
- Ô tìm ghi rõ **Nhập biển số hoặc mã phương tiện**, độc lập với bộ lọc loại xe. API vẫn chỉ tìm theo mã/biển số; người dùng chọn Xe máy trong dropdown thay vì phải nhập `MOTORBIKE` hoặc đoán cách viết `Motobike`.
- Kết quả là danh sách có nút Chọn, hiển thị mã, biển số, loại xe, tải trọng thực tế, tình trạng và khả năng sử dụng. Phân trang 10 kết quả do server thực hiện sau lọc. Xe không hợp lệ vẫn hiển thị với lý do từ backend, nút Chọn bị khóa. Phân biệt xe đang gắn với chính shipper và xe của shipper khác. Mã hiển thị là `KyHieuPhuongTien`; `vehicleId` gửi lên là `MaPhuongTien` (API `id`) của chính bản ghi đã chọn, không sinh mã hay suy ID từ biển số.
- Xe đã chọn xuất hiện trong vùng nền cam nhạt với nút Đổi lựa chọn. Giữ lựa chọn khi đổi trang, tìm lại hoặc xóa bộ lọc. Đổi lựa chọn xóa lựa chọn cũ; mở cho shipper khác khởi tạo phạm vi mới. Nếu API báo bưu cục/shipper khác bản form đang mở, xóa lựa chọn và yêu cầu đóng/mở lại.
- Phân biệt không có phương tiện trong phạm vi/nguồn xe chung; có phương tiện nhưng không có xe đủ điều kiện; không có xe khớp bộ lọc; và lỗi tải dữ liệu. Có Thử lại khi phù hợp. Bưu cục không còn khớp trả 409, xóa lựa chọn và yêu cầu mở lại form.
- Khi server trả 409/422 lúc lưu, giữ ghi chú, xóa xe đã chọn và tải lại danh sách để người dùng kiểm tra/chọn lại. Không tự gửi lại PUT. Kết quả danh sách đến trong lúc lưu được tải lại sau khi form hết bận, tránh để màn hình kẹt ở Đang tải.
- Lối mở từ trang Phương tiện xác minh xe được chuyển sang trước khi chọn sẵn; danh sách vẫn tải từ khóa trống.

## API và phạm vi bưu cục

`GET /api/v1/vehicles` giữ các filter/response hiện có, bổ sung:

- `forShipperId`: chỉ dùng cùng `assignableOnly=true`; kiểm tra shipper tồn tại, bưu cục đích và quyền quản lý trực tiếp từ database. Giữ quy tắc form gán xe hiện tại: ADMIN có `DIEUPHOI_GIAMSAT`, `TAIKHOAN_XEM`, `TAIKHOAN_QUANLY`.
- `includeUnavailable=true`: chỉ dùng trong ngữ cảnh chọn cho shipper; trả cả xe không thể chọn cùng `canSelect`, `unavailableReason`, `isCurrentVehicle`. Không làm thay đổi trạng thái hoặc phân công. Bỏ tham số này vẫn giữ contract danh sách chỉ gồm xe đủ điều kiện.
- `selectionShipperId`, `selectionBranchId`, `selectionBranchName`: phạm vi đã kiểm tra để frontend phát hiện context thay đổi.
- `scopedTotalItems`: tổng xe trong phạm vi trước lọc; `eligibleTotalItems`: số xe có thể chọn trước lọc. `totalItems` là số sau lọc, dùng phân trang server.

Schema hiện tại không có bưu cục sở hữu trên `PhuongTien`. Danh sách chọn gồm xe đang gán cho nhân viên tại bưu cục đích và xe chưa gán thuộc nguồn chung do ADMIN quản lý. Xe đã gán ở bưu cục khác không xuất hiện. Không dùng `tk.MaBuuCuc=@branchId` để lọc bỏ toàn bộ xe chưa gán (không có tài khoản liên kết nên cột này NULL). API đối chiếu branchId gửi lên với bưu cục thật của shipper; lệch trả 409. Các quy tắc phạm vi của API xem xe thông thường giữ nguyên. Không bổ sung mô hình bưu cục sở hữu xe riêng.

Điều kiện xe hoạt động, AVAILABLE, không có phân công hiện hành, phân công giao hàng, chuyến chưa kết thúc hoặc nhiệm vụ hoàn đang mở được xét trước phân trang. Trạng thái hợp lệ của shipper, tài khoản, bưu cục, bằng lái và nhiệm vụ trên shipper/xe cũ cũng được xét. `ShipperVehicleController` tiếp tục kiểm tra lại dưới transaction/khóa SQL và so `expectedAssignmentId` từ lúc mở form; không lấy phiên bản mới ngay trước PUT để vượt xung đột. Kiểm tra bằng lái theo ngày Việt Nam và các bản sửa xác thực/timeout được giữ.

## Nguyên nhân thực tế của danh sách rỗng

Đã chạy kiểm tra chỉ đọc theo cấu hình Development (appsettings, user secrets, environment) trên `(localdb)\MSSQLLocalDB`, database `QLGiaoHangChangCuoi`. Có 5 xe: 2 xe AVAILABLE nhưng đã có phân công phương tiện hiện hành, 2 xe IN_USE, 1 xe ngừng hoạt động. Không có xe tự do đủ điều kiện gán mới. API cũ loại bỏ tất cả các xe này, kể cả xe của chính shipper, nên form không giải thích được vì sao danh sách trống. Không phải do thiếu lời gọi tự tải; kiểm thử trình duyệt đã xác nhận lời gọi chạy khi mở form với từ khóa trống.

Controller mới đã chạy chỉ đọc trên database này cho cả 5 shipper: mỗi phạm vi trả 2–3 xe, `eligibleTotalItems=0`; các xe của bưu cục khác được loại đúng, xe của chính shipper được gắn cờ và mọi xe bị khóa đều có lý do. Không thay đổi dữ liệu hoặc trạng thái xe. Chi tiết: [vehicle-picker-database-diagnostic.json](vehicle-picker-database-diagnostic.json).

## File đã sửa

- `backend/LastMile/LastMile.Api/Controllers/VehiclesController.cs`: phạm vi shipper đích, số xe đủ điều kiện trước lọc và metadata bổ sung.
- `frontend/js/shippers.js`: bộ chọn xe riêng, lựa chọn bền qua phân trang, xử lý bất đồng bộ/lỗi lưu; tái sử dụng ở cả trang Shipper và Phương tiện.
- `frontend/assets/css/styles.css`, `frontend/index.html`: bố cục trắng–cam thích ứng điện thoại và cache version.
- `frontend/tests/vehicle-picker-browser.cjs`, `frontend/tests/shippers-browser.cjs`: các ca mới và cập nhật thao tác chọn xe trong hồi quy cũ.
- `frontend/tests/README.md`, tài liệu này và `docs/vehicle-picker-verification.json`.
- `tools/VehicleSelectionDiagnostics/VehicleSelectionDiagnostics.csproj`, `Program.cs`: công cụ chỉ đọc schema/dữ liệu và gọi controller mới trên database đã cấu hình; `docs/vehicle-picker-database-diagnostic.json`: kết quả. Công cụ không tạo JWT hoặc in connection string/mật khẩu/token.
- Ảnh `docs/vehicle-picker-1440.png`, `docs/vehicle-picker-390.png`; harness cũng cập nhật báo cáo/ảnh hồi quy shipper hiện có.

## Kiểm tra thực tế ngày 19/10/2026

- Build API Release với `--no-restore -warnaserror`: **0 lỗi, 0 cảnh báo**.
- `npm.cmd test`: **75/75 đạt**, gồm API client, auth, timeout, Router và ngày Việt Nam.
- Harness Shipper mở rộng: **86 kiểm tra đạt**, trong đó **29 ca riêng cho bộ chọn xe**, dùng API/JWT/SQL và Edge thật trên LocalDB GUID/profile riêng. Database/profile thử đã dọn; không ghi database vận hành.
- Đã chạy: mở không có từ khóa; lọc cả 3 loại trong danh mục; tìm theo mã và biển số; phân trang không trùng; chọn/đổi lựa chọn/giữ lựa chọn qua trang và xóa lọc; ba trạng thái rỗng/lỗi; đổi shipper/bưu cục; lối mở từ trang Phương tiện; request danh sách đến trong lúc lưu.
- Ca xung đột dùng thao tác SQL thật: mở form và chọn xe, shipper thứ hai được gán chính xe đó bằng API, form thứ nhất gửi PUT nhận **409**, shipper thứ nhất vẫn chưa có xe và giữ ghi chú. Sau đó gỡ phân công thử để hồi quy tiếp.
- Ca không có xe đủ điều kiện dùng shipper còn nhiệm vụ trên SQL thật: vẫn hiển thị các xe với nút Chọn khóa và lý do. Không đổi trạng thái xe để tạo ca thử. Ca không khớp bộ lọc vẫn còn xe đủ điều kiện và trả `totalItems=0` riêng biệt.
- Đã xác minh payload PUT chứa đúng ID xe từ database, gán thành công, gọi GET lại và reload trình duyệt vẫn thấy đúng xe; gán/đổi/gỡ và xung đột chạy qua API/SQL thật trên database thử cô lập.
- Các response có kiểm soát: danh sách phạm vi không có bản ghi; list 500; list 409 do bưu cục thay đổi; list chậm kết hợp save 400. Không ghi các ca này là thao tác SQL thật.
- Đã chụp và xem ảnh ở **1440 px** và **390 px**; kiểm tra hình học không có tràn ngang trong dialog, kết quả bố cục dạng thẻ trên điện thoại. Không có lỗi console/unhandled rejection.

Kết quả từng ca: [vehicle-picker-verification.json](vehicle-picker-verification.json). Toàn bộ hồi quy: [shippers-verification.json](shippers-verification.json).

Chạy lại từ gốc dự án:

```powershell
dotnet build backend/LastMile/LastMile.Api/LastMile.Api.csproj --no-restore -c Release -warnaserror --output frontend/tests/.artifacts/vehicle-picker/build
$env:SHIPPERS_QA_DLL = (Resolve-Path frontend/tests/.artifacts/vehicle-picker/build/LastMile.Api.dll).Path
node frontend/tests/shippers-browser.cjs
```

Chưa kiểm chứng Chrome/Firefox/Safari hoặc thiết bị điện thoại vật lý. Ca đổi phạm vi kiểm tra bằng mở shipper khác/bưu cục khác, gửi branchId lệch thật và chèn list 409 để kiểm tra giao diện; chưa đổi bưu cục đồng thời qua một request ngoài trong lúc form mở. Không thực hiện gán/đổi xe trên database đang sử dụng vì hiện không có xe đủ điều kiện; luồng ghi hoàn chỉnh đã chạy trên SQL thử cô lập. API đang chạy bằng bản build cũ cần khởi động lại để nạp backend mới; cache version frontend đã được tăng. Không cần migration.
