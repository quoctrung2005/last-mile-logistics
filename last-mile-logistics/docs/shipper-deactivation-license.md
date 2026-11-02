# Ngừng hoạt động shipper và bằng lái lịch sử

`ShipperUpdateController` so sánh số bằng lái (đã trim), ngày hết hạn và trạng thái hoạt động với hồ sơ hiện tại được đọc bằng `UPDLOCK, HOLDLOCK` trong transaction. Không dùng dữ liệu cũ do trình duyệt gửi làm bằng chứng rằng bằng lái không đổi.

| Thao tác | Ngày hết hạn trước hôm nay ở Việt Nam |
| --- | --- |
| Ngừng hoạt động, giữ nguyên số và ngày hết hạn | Cho phép nếu không còn nhiệm vụ |
| Giữ trạng thái hiện tại, sửa thông tin khác và giữ nguyên bằng lái | Cho phép nếu các điều kiện cập nhật hiện có thỏa mãn |
| Nhập ngày hết hạn mới hoặc thay đổi số bằng lái | Từ chối bằng lỗi 422 |
| Kích hoạt lại hồ sơ đang ngừng hoạt động | Từ chối bằng lỗi 422; cần cập nhật bằng lái hợp lệ trước |

Ngày hết hạn là hôm nay còn hợp lệ đến hết ngày Việt Nam; ngày mai hợp lệ. Frontend dùng `window.VietnamDate.isLicenseExpired`; SQL dùng `VietnamDate.SqlDate("SYSUTCDATETIME()")`. Không chuyển ngày hết hạn thành mốc giờ UTC và không dùng ngày cục bộ của trình duyệt/máy chủ.

Form sửa hồ sơ cho phép giữ dữ liệu bằng lái lịch sử; form đổi trạng thái vẫn gửi lại nguyên ngày cũ khi ngừng hoạt động. Form kích hoạt lại chặn bằng lái hết hạn và hướng dẫn cập nhật trước. Quy tắc bằng lái tùy chọn và yêu cầu có số bằng lái khi nhập ngày hết hạn vẫn giữ nguyên.

Backend tiếp tục chặn khi có phân công chưa kết thúc, chuyến ASSIGNED/ACCEPTED/IN_PROGRESS hoặc nhiệm vụ RETURNING thuộc shipper. Khi ngừng hoạt động, `TrangThaiSanSang` chuyển OFFLINE. Các kiểm tra quyền, phạm vi bưu cục, tài khoản/bưu cục còn hoạt động khi kích hoạt, khu vực, dữ liệu cũ/mới và nhật ký vẫn nằm trong transaction. Không sửa điều kiện nhận/bắt đầu nhiệm vụ hoặc chuyến: các luồng đó vẫn yêu cầu shipper hoạt động và bằng lái đủ điều kiện theo ngày Việt Nam.

## Kiểm tra

Lệnh từ thư mục gốc dự án, không đọc cấu hình kết nối và không kết nối database:

```powershell
dotnet build backend/LastMile/LastMile.Calendar.Tests/LastMile.Calendar.Tests.csproj --no-restore -c Release -warnaserror --output frontend/tests/.artifacts/shipper-update/release
dotnet frontend/tests/.artifacts/shipper-update/release/LastMile.Calendar.Tests.dll --shipper-update .
node --test frontend/tests/shipper-license-update.test.cjs frontend/tests/vietnam-date.test.cjs
```

- Build API và bộ kiểm tra Release: 0 warning, 0 error.
- Backend: 36 tình huống controller, 203 kiểm tra đạt qua `DbConnection` giả lập. Bao gồm giữ ngày cũ/OFFLINE, các loại nhiệm vụ, kích hoạt lại, thay đổi số/ngày, khác biệt chữ hoa/chữ thường, khoảng trắng, hồ sơ hiện tại khác dữ liệu form, quyền/phạm vi, bằng lái tùy chọn và ranh giới nửa đêm Việt Nam.
- Frontend: 16 kiểm tra luồng form thật với DOM/HTTP giả lập và 6 kiểm tra helper ngày đạt. Kiểm tra request ngừng hoạt động giữ số/ngày cũ, kích hoạt bằng lái hết hạn không gửi PUT, nhập/sửa bằng lái, sửa lại validation và ngày hôm qua/hôm nay/ngày mai.
- Hồi quy frontend: chạy `npm.cmd test` trong `frontend`, **189/189 kiểm tra đạt**, gồm luồng lưu của shipper, validation thông thường và khóa thao tác có kết quả ghi chưa xác định.

Mock kiểm tra câu SQL và tham số tại ranh giới command rồi mô phỏng trạng thái được khóa và quy tắc nhiệm vụ. Chưa chạy SQL Server hoặc kiểm tra tranh chấp khóa bằng các giao dịch thật. Không chạy nhánh kiểm tra Calendar mặc định (nhánh đó dùng truy vấn LocalDB); chỉ chạy chế độ `--shipper-update` không có kết nối database.
