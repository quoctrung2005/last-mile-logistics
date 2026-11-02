# Kiểm tra ảnh bằng chứng giao hàng

Đã đọc controller upload, đọc danh sách, đọc file và xóa bằng chứng. Không tìm thấy AGENTS.md trong workspace hoặc các thư mục cha đã kiểm tra. Không cần migration.

## Thay đổi

`DeliveryEvidenceUploadController` gọi chung phép kiểm tra tài khoản/quyền/lần giao trước khi xử lý ảnh, rồi kiểm tra lại trong transaction với các khóa SQL cũ trước khi lưu file, bản ghi và nhật ký. Đọc stream, ping và giải mã ảnh diễn ra ngoài transaction SQL. Quyền `BANGCHUNG_TAO`, vai trò SHIPPER, chủ lần giao, kiểm tra tọa độ và đường dẫn tên GUID do server tạo được giữ nguyên.

`Services/DeliveryEvidenceImage.cs` thực hiện đọc stream có giới hạn, chọn decoder theo nội dung, kiểm tra container đầy đủ, ping kích thước rồi mới giải mã toàn bộ. Cả lỗi và cảnh báo decoder đều bị từ chối: libjpeg có thể phục hồi một JPEG thiếu dữ liệu và chỉ phát warning; chỉ kiểm tra rằng hàm decode trả image là chưa đủ. Lưu bytes gốc chỉ khi các bước kiểm tra đã đạt.

Dependency cuối cùng: **[Magick.NET-Q8-AnyCPU 15.0.0](https://www.nuget.org/packages/Magick.NET-Q8-AnyCPU/15.0.0)**, giấy phép Apache 2.0, chứa native assets Windows/Linux/macOS. Không còn reference ImageSharp hoặc SkiaSharp; các bản đó chỉ được thử trong lúc chọn decoder. Hai lý do chọn Magick.NET là bản ImageSharp thử yêu cầu license khi build Release và SkiaSharp vẫn nhận JPEG bị mất dữ liệu entropy dù có SOI/EOI. Gói publish phải giữ native assets cho runtime đích; không cần GDI/System.Drawing hoặc executable ImageMagick cài riêng.

Giới hạn:

- File: lớn hơn 0 và tối đa **5 × 1024 × 1024 byte**; kiểm tra cả độ dài khai báo và số byte thật đọc được.
- Kích thước: tối đa **8.192 pixel mỗi chiều**, **16.000.000 pixel tổng**, kiểm tra trước full decode.
- Chỉ PNG/JPEG tĩnh; APNG bị từ chối. Không tin tên file hoặc Content-Type. Decoder được chỉ định PNG/JPEG rõ ràng, không mở các coder/delegate định dạng khác.
- Tối đa **2** tác vụ đọc/giải mã ảnh đồng thời mỗi process. Native pixel cache **256 MiB**, giới hạn allocation request **128 MiB**, profile tối đa **5 MiB**, 2 native threads; không spill pixel cache ra disk.
- File sai định dạng: 415. Nội dung hỏng/cắt cụt/quá kích thước: 400, thông báo tiếng Việt. Không tạo file hoặc bản ghi trước khi kiểm tra ảnh xong.

Giữ quy tắc commit chưa xác định: nếu lỗi trước khi bắt đầu commit thì rollback và xóa file; nếu đã gọi commit mà chưa biết kết quả, giữ file để tránh xóa ảnh có thể đã được database ghi nhận. Không tự retry thao tác ghi.

## File đã thay đổi

- `backend/LastMile/LastMile.Api/Controllers/DeliveryEvidenceUploadController.cs`: preflight, kiểm tra ảnh ngoài transaction và kiểm tra lại trước ghi.
- `backend/LastMile/LastMile.Api/Services/DeliveryEvidenceImage.cs`: decoder, kiểm tra container, dung lượng và tài nguyên.
- `backend/LastMile/LastMile.Api/LastMile.Api.csproj`: dependency ảnh; bản vá Pkcs và audit được mô tả trong tài liệu riêng.
- `backend/LastMile/LastMile.Evidence.Tests/LastMile.Evidence.Tests.csproj` và `Program.cs`: fixture/kiểm tra decoder và báo exception đầy đủ.
- `frontend/tests/evidence-fixture.ps1`, `frontend/tests/evidence-upload.cjs`: fixture SQL cô lập và kiểm tra HTTP/file thật.
- `frontend/package.json`, `frontend/tests/README.md`: lệnh chạy và mô tả kiểm tra.
- Tài liệu này và `docs/evidence-upload-verification.json`: kết quả thực tế.

## Lệnh kiểm tra

Từ `frontend`, sau khi restore các project:

```powershell
npm.cmd run test:evidence
```

Script build Release API, chạy console test decoder, rồi chạy JWT/HTTP/SQL và file thật trên LocalDB GUID riêng với thư mục content root GUID dưới `.artifacts/evidence`. Tự dọn database và thư mục file thử; không ghi database vận hành.

Kết quả ngày 19/10/2026:

- **20 kiểm tra decoder đạt**: PNG/JPEG, văn bản đổi đuôi, chỉ chữ ký, cắt cụt giữa file, mất marker cuối, IDAT hỏng, JPEG mất entropy nhưng giữ đầu/cuối, GIF không hỗ trợ, APNG, hơn 5 MB, đúng 5 MB hợp lệ, chiều rộng quá 8.192 và ảnh nén nhỏ nhưng hơn 16 triệu pixel. Thêm stream khai báo sai Length, hủy trước khi đọc và khả năng xử lý tiếp sau lỗi/hủy/đồng thời.
- **24 kiểm tra HTTP/SQL đạt**: các file không hợp lệ nhận 4xx, không có file rác, bản ghi bằng chứng và audit thành công không đổi; thiếu quyền bị chặn trước decode; sai vai trò/lần giao/tọa độ vẫn bị từ chối.
- PNG, JPEG và PNG đúng 5 MB upload 201 rồi tải lại 200 với MIME đúng, `nosniff`, bytes khớp file đã giải mã. Tên `../../misleading.txt` và MIME khai báo sai không ảnh hưởng định dạng/đường dẫn lưu.
- Mỗi upload thành công chỉ tạo một file, một bản ghi và một audit. Trigger lỗi SQL thử trước commit rollback bản ghi/audit và xóa file đã ghi.
- Chi tiết các kiểm tra HTTP: [evidence-upload-verification.json](evidence-upload-verification.json). Lỗi ListLength của test exe được phân tích riêng trong [nuget-pkcs-update.md](nuget-pkcs-update.md).

Chưa kiểm chứng runtime Linux/macOS, hiển thị ảnh qua giao diện, benchmark tải lớn hoặc fault injection ngay trong commit để tái hiện kết quả chưa xác định. Chưa chạy race chủ lần giao/quyền đổi đúng trong khi decoder đang xử lý; kiểm tra lại trong transaction đã giữ trong mã. Bộ kiểm tra tọa độ qua HTTP dùng số nguyên để độc lập với thiết lập decimal separator của Windows; các kiểm tra số lẻ trong controller được giữ nguyên.
