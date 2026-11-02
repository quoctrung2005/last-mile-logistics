# Vá dependency Pkcs — 19/10/2026

## Truy vết và quyết định

`dotnet nuget why backend/LastMile/LastMile.Api/LastMile.Api.csproj System.Security.Cryptography.Pkcs` xác định:

```text
LastMile.Api (net10.0)
  Microsoft.Data.SqlClient 7.1.1
    System.Security.Cryptography.Pkcs 9.0.18
```

Đã kiểm tra [NuGet của Microsoft.Data.SqlClient](https://www.nuget.org/packages/Microsoft.Data.SqlClient/): 7.1.1 là bản ổn định mới nhất tại thời điểm kiểm tra; nhóm asset net9.0 được .NET 10 chọn vẫn phụ thuộc `Pkcs >= 9.0.18`. Chưa có bản cha mới hơn đã nâng dependency này. Giữ SqlClient 7.1.1, thêm reference trực tiếp Pkcs **9.0.21**, là bản vá cùng nhánh 9.x và thỏa điều kiện của SqlClient. Không đổi cách kết nối SQL, transaction, xác thực hay native decoder ảnh.

| Package | Trước | Sau |
| --- | --- | --- |
| Microsoft.Data.SqlClient | 7.1.1 | 7.1.1 |
| System.Security.Cryptography.Pkcs | 9.0.18, gián tiếp | 9.0.21, reference trực tiếp và dependency được resolve |

Reference có comment nêu lý do và hai mã GHSA trong `LastMile.Api.csproj`. Có thể bỏ reference này khi bản SqlClient tương lai tự yêu cầu bản Pkcs đã vá, sau khi chạy lại audit và hồi quy.

## Advisory đã đọc

- [GHSA-2fmv-rv2c-59x7 / CVE-2026-70162](https://github.com/advisories/GHSA-2fmv-rv2c-59x7): mức Moderate, `EnvelopedCms.Decode` trên Windows có thể tiêu thụ CPU quá mức với dữ liệu CMS/PKCS#7 do bên tấn công cung cấp.
- [GHSA-846f-f764-76mx / CVE-2026-84008](https://github.com/advisories/GHSA-846f-f764-76mx): mức High, `SignedCms.CheckSignature` có thể lặp xử lý dữ liệu X.509 gây cạn CPU trên Windows/Linux/macOS.

Cả hai advisory ghi cùng các nhánh ảnh hưởng và bản vá:

| Nhánh bị ảnh hưởng | Bản đầu tiên đã vá |
| --- | --- |
| 8.0.0–8.0.1 | 8.0.2 |
| 9.0.0–9.0.20 | 9.0.21 |
| 10.0.0–10.0.12 | 10.0.13 |
| 11.0.0-preview.1–11.0.0-rc.1 | 11.0.0-rc.2 |

## Kiểm chứng thực tế

- Restore API và project Evidence.Tests với `--force-evaluate -warnaserror`: đạt. Không có NU1605 (downgrade), NU1608 (vượt ràng buộc) hoặc NU190x.
- Build Release API và Evidence.Tests với `--no-restore -warnaserror`: đạt, **0 lỗi, 0 cảnh báo**. Build API của harness xác thực cũng đạt 0 lỗi/0 cảnh báo.
- `dotnet nuget why` sau restore: cả cạnh từ SqlClient và reference trực tiếp đều resolve **9.0.21**.
- `dotnet list ... package --include-transitive --vulnerable --format json --no-restore`: không có package vulnerable trong LastMile.Api. Output thật lưu tại [nuget-pkcs-audit.json](nuget-pkcs-audit.json).
- Giá trị MSBuild thực tế: `NuGetAudit = true`, `NuGetAuditMode = all`. Hai giá trị được khai báo rõ trong project; không thêm suppress, `NoWarn` hoặc tắt nguồn audit.
- `npm.cmd run test:auth-sessions`: **15/15 đạt** trên LocalDB GUID/HTTP thật, gồm login, refresh xoay token, logout một/mọi phiên, ba luồng mật khẩu, race và 401 đồng thời. Fixture đã dọn; không ghi database vận hành.
- `npm.cmd test`: **69/69 đạt**, gồm API client, auth, timeout và Router.
- Decoder ảnh: **20 kiểm tra đạt** sau khi resolve Pkcs mới. Upload/download JWT/HTTP/SQL thật: **24 kiểm tra đạt**, xem [evidence-image-validation.md](evidence-image-validation.md).

## Evidence.Tests được điều tra riêng

Không có bằng chứng gán lỗi chạy test cho Pkcs. Exception thực tế và InnerException đã đọc là:

```text
System.Exception: Valid fixture failed: valid.png: list length exceeds limit
  ---> LastMile.Api.Services.EvidenceImageException: Ảnh vượt giới hạn xử lý...
    ---> ImageMagick.MagickResourceLimitErrorException:
          list length exceeds limit ... error/cache.c/OpenPixelCache/3824
      at ImageMagick.NativeInstance.CheckException(...)
      at ImageMagick.MagickImage.NativeMagickImage.ReadBlob(...)
      at ImageMagick.MagickImage.Read(...)
      at LastMile.Api.Services.DeliveryEvidenceImage.ReadAsync(...)
  at Program.<Main>$(String[] args)
```

Tại lần lỗi, cấu hình native `ResourceLimits.ListLength = 1` ngăn bước `Read` thay thế image/cache sau `Ping`. Đã chỉnh thành 4 để cho phép cấu trúc tạm nội bộ; API vẫn chỉ đọc một khung hình và chặn APNG trước khi gọi native decoder. Bộ 20 kiểm tra đã đạt **ngay khi vẫn dùng Pkcs 9.0.18**, và tiếp tục đạt với 9.0.21. Không có frame `Pkcs` trong stack trace này.

Harness hiện bắt exception ở entry point, in đầy đủ exception/inner stack và trả exit code 1, tránh hộp thoại lỗi unhandled của Windows giữ process/file build khi một assertion thất bại. Không che exception trong API hoặc đổi lỗi SQL thành 401.

## Áp dụng và giới hạn

Chạy `dotnet restore` rồi build/publish lại API để đưa DLL đã vá vào gói triển khai; khởi động lại instance khi triển khai. Không có migration hoặc thay đổi dữ liệu.

Đã kiểm chứng trên Windows/.NET 10/LocalDB. Chưa chạy workload PKCS#7 gây DoS, triển khai production, xác thực SQL bằng certificate/enclave/Azure AD hoặc runtime Linux. NuGet Audit là kết quả theo nguồn advisory tại thời điểm chạy; không thay thế việc cập nhật runtime/SDK và audit tiếp trong các lần restore sau.
