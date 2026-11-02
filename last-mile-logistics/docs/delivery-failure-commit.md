# Ảnh giao thất bại và kết quả commit

`OrderDeliveryFailureController` quản lý transaction ngoài bằng C#, thay vì COMMIT trong batch SQL rồi mới nhận kết quả. Controller đọc và kiểm tra toàn bộ tập kết quả, đóng reader, kiểm tra hủy, đặt `commitAttempted = true` ngay trước `CommitAsync` và chỉ đánh dấu `Committed` sau khi nhận xác nhận thành công.

| Kết quả | Xử lý ảnh | Phản hồi |
| --- | --- | --- |
| SQL chưa được gửi hoặc rollback đã được xác nhận trước khi thử commit | Xóa file vừa lưu; lỗi xóa chỉ ghi cảnh báo | Giữ mapping lỗi nghiệp vụ; lỗi kỹ thuật xác định có `resultUnknown=false` |
| Commit được xác nhận thành công | Giữ ảnh | Giữ JSON thành công hiện có |
| Lỗi/hủy trong lúc commit, mất xác nhận commit, hoặc không xác nhận được rollback | Giữ ảnh | HTTP 500, `DELIVERY_FAILURE_RESULT_UNKNOWN`, `resultUnknown=true`; yêu cầu tải lại đơn và kiểm tra trước khi thực hiện lại |

Rollback thành công sau một lỗi commit không được dùng để suy luận commit trước đó thất bại. Dispose, hủy request hoặc mất kết nối cũng không được coi là bằng chứng rollback.

## Transaction lồng nhau

Đã đọc `dbo.sp_XacNhanGiaoHangThatBai` trong `database/QLGiaoHangChangCuoi_SQLServer_V5 .sql`: procedure mở một transaction và COMMIT một cấp khi thành công; với transaction ngoài đang mở, `@@TRANCOUNT` đi từ 1 → 2 → 1. COMMIT cuối cùng do C# thực hiện. CATCH của procedure có thể ROLLBACK toàn bộ transaction và dọn session context.

Nếu rollback phía SqlClient báo transaction đã hoàn tất trước khi C# từng thử commit, controller chỉ xác nhận rollback khi kết nối vẫn mở, transaction đã hoàn tất và một truy vấn đọc xác nhận cả `XACT_STATE() = 0` và `@@TRANCOUNT = 0`. Không lấy trạng thái này sau lỗi commit để kết luận ghi thất bại.

Không sửa procedure, schema hoặc dữ liệu database. SQL kiểm tra tài khoản/quyền, bưu cục, trạng thái IN_DELIVERY, phân công IN_PROGRESS, gọi procedure, cập nhật yêu cầu giao lại, kết quả và nhật ký vẫn nằm trong cùng transaction. Không thêm nhánh phát lại command/commit.

Reader, command, transaction và connection được dọn trong finally. Lỗi dispose được ghi cảnh báo, không che kết quả/lỗi gốc; lỗi xóa file IOException/UnauthorizedAccessException được xử lý tương tự.

## Kiểm tra ảnh

Controller dùng `DeliveryEvidenceImage.ReadAsync`, cùng bộ kiểm tra với upload bằng chứng. Bộ xử lý chỉ chọn decoder JPEG/PNG theo nội dung, kiểm tra container, đọc kích thước rồi giải mã đầy đủ; không dùng tên, đuôi file hoặc Content-Type của client. Giới hạn chung là 5 MB (cả độ dài khai báo và số byte thực đọc), 8.192 pixel mỗi chiều và tổng 16 triệu pixel; ảnh hỏng, cắt cụt, chỉ có đầu file hoặc PNG động bị từ chối.

Trước khi đọc ảnh, truy vấn chỉ đọc kiểm tra tài khoản/vai trò đang hoạt động, quyền `NHIEMVU_CAPNHAT`, hồ sơ shipper và phạm vi đơn theo bưu cục/phân công. Ảnh phải qua bộ xử lý trước khi tạo thư mục/file hoặc mở transaction ghi. Controller lưu đúng `Bytes` và `Extension` được bộ xử lý trả về, không mở lại/copy upload gốc. Bộ xử lý chung hiện giữ nguyên byte của ảnh đã giải mã hợp lệ, không tái mã hóa ảnh.

Transaction vẫn kiểm tra lại quyền/phạm vi đơn, trạng thái IN_DELIVERY và phân công IN_PROGRESS. Procedure tiếp tục quyết định ảnh bắt buộc theo `BatBuocMinhChung` của lý do đang hoạt động: thiếu ảnh bắt buộc vẫn trả 422, lý do không bắt buộc vẫn ghi được khi không gửi ảnh. Không sửa procedure hay chuyển quy tắc này ra khỏi transaction. Cơ chế giữ ảnh khi kết quả commit/rollback chưa xác định vẫn áp dụng như trên.

## Kiểm tra đã chạy

- Build API và bộ kiểm tra Release với `--no-restore -warnaserror`: 0 warning, 0 error.
- `LastMile.Evidence.Tests`: **22 kiểm tra đạt**, tạo fixture JPEG/PNG hợp lệ, file giả đúng đầu file, ảnh cắt cụt/hỏng, 5 MB chính xác/quá 5 MB, ảnh quá kích thước/pixel, định dạng không hỗ trợ, stream khai báo sai độ dài, hủy và giải mã đồng thời.
- `LastMile.DeliveryFailure.Tests`: **41 kịch bản, 318 kiểm tra đạt**, gọi action controller thật qua DbConnection giả lập, dùng ảnh JPEG/PNG giải mã được và các fixture lỗi từ bộ kiểm tra chung trong thư mục kiểm thử riêng.
- Bao gồm thành công, lỗi execute, mất phần cuối kết quả, kết quả rỗng, procedure rollback sẵn, rollback chưa được xác nhận, lỗi mở kết nối, lỗi trước/sau commit, commit bị hủy, hủy trước commit, ảnh không bắt buộc, file bị khóa khi xóa và lỗi dispose sau thành công/thất bại.
- Mỗi kịch bản kiểm tra không phát lại command/commit và tài nguyên đã được dispose. Sau commit mất xác nhận, trạng thái mock đã lưu bản ghi nhưng ảnh vẫn tồn tại.
- Kiểm tra ở ranh giới controller: dữ liệu/phần mở rộng lưu đúng kết quả bộ xử lý dù tên file là `untrusted.exe` và Content-Type là `application/octet-stream`; ảnh lỗi bị từ chối trước khi tạo file/transaction ghi; lỗi 401/403/404 không mở stream ảnh; phạm vi thay đổi sau giải mã bị kiểm tra lại trong transaction; lý do bắt buộc/không bắt buộc ảnh giữ cách xử lý hiện tại. Quy tắc lý do và lỗi SQL được giả lập ở ranh giới command, không chạy procedure thật.

Lệnh thực thi:

```powershell
dotnet build backend/LastMile/LastMile.Evidence.Tests/LastMile.Evidence.Tests.csproj --no-restore -c Release -warnaserror --output frontend/tests/.artifacts/evidence/release
dotnet frontend/tests/.artifacts/evidence/release/LastMile.Evidence.Tests.dll frontend/tests/.artifacts/evidence/fixtures
dotnet build backend/LastMile/LastMile.DeliveryFailure.Tests/LastMile.DeliveryFailure.Tests.csproj --no-restore -c Release -warnaserror --output frontend/tests/.artifacts/delivery-failure/release
dotnet frontend/tests/.artifacts/delivery-failure/release/LastMile.DeliveryFailure.Tests.dll frontend/tests/.artifacts/delivery-failure/mock-tests frontend/tests/.artifacts/evidence/fixtures
```

## Chưa kiểm tra

Chưa chạy SQL Server/LocalDB thật, chưa thực thi procedure/trigger thật với transaction C# và chưa gây mất TCP thật khi COMMIT. Các trường hợp này được mô phỏng ở ranh giới DbConnection/DbTransaction; quyền, lịch sử và nhật ký được giữ trong SQL nhưng chưa được kiểm chứng tích hợp với database trong lần sửa này.

Fresh NuGet restore trong sandbox bị từ chối quyền đọc cấu hình NuGet cá nhân; build và toàn bộ kiểm tra trên đã chạy thành công bằng assets/package cache hiện có với `--no-restore`. Không truy cập hay ghi vào database vận hành.
