# Xác thực và refresh — kiểm tra ngày 09/10/2026

## Bằng chứng và nguyên nhân trong mã

- Thông báo hết phiên xuất phát từ `frontend/js/api.js`, event `auth:expired` và `restoreSession` trong `app.js`, cùng nhánh mọi 401 trong `warehouse.js`.
- API client cũ xóa token sau mọi 401 của request đã thử lại, dù refresh vừa thành công. Refresh 400/403 cũng bị coi là không hợp lệ mà không đối chiếu response. UI khôi phục phiên và Kho gọi mọi 401 là hết phiên. Các lỗi này đã được sửa: chỉ phản hồi refresh xác nhận token không hợp lệ/hết hạn mới kết thúc phiên.
- Proxy cũ mặc định gọi `http://localhost:5038`, backend gọi `UseHttpsRedirection()` cả trong Development. Proxy chuyển nguyên status/Location 3xx ra trình duyệt; comment “Do not follow API redirects” không ngăn fetch đi sang origin khác. Chuyển origin có thể làm mất Authorization. Test HTTP thực xác nhận upstream 307 tới `https://localhost:7255/...` hiện bị proxy chặn thành 502, không trả Location.
- API client cũ đã đọc access token từ sessionStorage ở mỗi request, và route/DTO login/refresh đã đúng. Không tìm thấy bằng chứng biến token khởi tạo trước login bị giữ lại hoặc DTO bị đọc nhầm trong mã cũ. Tuy nhiên bộ lưu cũ chỉ kiểm tra typeof string, bỏ expiresAt/user; chưa chặn chuỗi undefined/null hoặc token rỗng. Nay lưu phiên nguyên tử, kiểm tra định dạng token và user/time, chuẩn hóa Bearer một lần.
- Gộp refresh cũ chỉ hiệu lực khi promise còn đang chạy. 401 của token cũ đến sau khi promise hoàn tất có thể refresh thêm lần nữa. Nay so sánh token đã gửi với token hiện tại trước khi refresh; generation bảo vệ login/logout mới khỏi kết quả refresh của phiên cũ.

HTTP ban đầu, không có backend lắng nghe 5038/7255:

| URL | HTTP | Response |
| --- | --- | --- |
| `http://localhost:5500/api/v1/orders` | 502 | `{"message":"Không thể kết nối backend. Hãy khởi chạy API hoặc kiểm tra LASTMILE_API_URL."}` |
| `http://127.0.0.1:5500/api/v1/orders` | 502 | Như trên |
| `http://localhost:5038/api/v1/auth/me` | Không kết nối | curl connection refused |

Sau đó backend người dùng xuất hiện trên 5038/7255. Request không token tới `http://localhost:5500/api/v1/orders` trả 401, body rỗng, `WWW-Authenticate: Bearer`, không redirect. Đây là phản hồi bình thường cho request chưa xác thực. Không có tài khoản/phiên cũ của người dùng để xác nhận request sau login ban đầu, nên không khẳng định lỗi trong phiên cũ chỉ do redirect hoặc token sai.

## Thay đổi

- `frontend/js/api.js`: một bản ghi `tvd.session`, migrate key cũ; giữ cả accessToken/refreshToken/expiresAt/user; đọc token mới mỗi request; loại header tự truyền và đặt `Bearer <accessToken>` một lần. ExpiresAt dùng Date.parse với timezone ISO, legacy JWT exp dùng giây nhân 1000. Client không tự kết luận hết phiên bằng đồng hồ máy khách.
- Request 401 refresh một lần, gộp cùng promise, xử lý 401 đến muộn; retry tối đa một lần. Login/refresh/logout không vào luồng refresh. Refresh mới lưu cả hai token; kết quả của generation cũ không ghi/xóa phiên mới.
- Refresh 401 hoặc 400 có lỗi DTO riêng `RefreshToken` mới xóa phiên. Generic 400/403/409/429/5xx, lỗi mạng và response refresh sai contract giữ phiên. 401 sau retry giữ phiên và báo bị từ chối xác thực. Lỗi giữ URL/status/response trong object cho debugger; không log token/password.
- `frontend/js/app.js`, `warehouse.js`: dùng cờ sessionExpired thay vì coi mọi 401 là hết hạn. Khi restore bị lỗi tạm thời, user đã lưu được dùng để giữ shell và hiện lỗi/nút thử lại; quyền thao tác vẫn do API backend kiểm tra.
- `frontend/dev-server.cjs`: giữ Authorization/body, chặn upstream 3xx thành JSON 502. Có createServer export để test HTTP trên cổng 0; chạy thường vẫn cổng 5500.
- `backend/LastMile/LastMile.Api/Program.cs`: Development không redirect HTTP API loopback; môi trường khác giữ HTTPS redirection. Không đổi xác thực, Jwt:ExpireMinutes, ClockSkew, issuer/audience/key hoặc CORS. HTTPS proxy vẫn kiểm tra chứng chỉ bình thường.
- `frontend/package.json`, `frontend/tests/auth.test.cjs`, `frontend/README.md`: lệnh test không dependency, regression và hướng dẫn cấu hình local.

## Kết quả

Backend build: **0 warning, 0 error** trước khi backend người dùng được khởi chạy. Fixture thử dùng DLL đã build để tránh rebuild file exe đang được tiến trình người dùng giữ. Cú pháp JS và **10 test Node đạt**. Unit test mô phỏng response trong bộ nhớ; test proxy sử dụng HTTP upstream/proxy thật trên các cổng tự cấp phát.

Regression API dùng ASP.NET Core và LocalDB thật, database riêng `CodexAuth_<GUID>`, schema/seed của dự án, tài khoản BCrypt riêng và JWT ký đúng key thử. Không sửa database vận hành. API thử dùng cổng 0, proxy thử dùng cổng 0; không khởi chạy trùng 5500/5038/7255, không dừng server người dùng. Không log token/mật khẩu; không tăng thời hạn JWT.

| Kiểm tra | Kết quả |
| --- | --- |
| Login mới | 200, đúng accessToken/refreshToken/expiresAt/user; ISO UTC và JWT exp khớp; issuer/audience khớp cấu hình xác thực |
| Auth/me, Đơn hàng, Kho, permissions, Điều phối | HTTP 200 thật qua proxy cùng origin, không redirect |
| Tải lại client | Giữ phiên; auth/me 200 |
| JWT đã hết hạn được ký đúng | Bốn request đồng thời thực sự trả 401; đúng một POST refresh 200; bốn retry trả 200, cả hai token được đổi |
| Token mới bị 401 tiếp | Test kiểm soát: retry đúng một lần, không refresh đệ quy hoặc xóa phiên |
| 401 đến sau refresh hoàn tất | Test kiểm soát: tám request đồng thời và một request đến muộn, chỉ một refresh |
| 403 thiếu KHO_XEM | HTTP 403 thật, không xóa phiên; auth/me tiếp tục 200 |
| 400 query page=0 | HTTP 400 thật, giữ phiên |
| Refresh sai | Refresh HTTP 401 thật, xóa đúng phiên thử và phát auth:expired một lần |
| Generic refresh 400/403/409/429/500, lỗi mạng, response sai | Test kiểm soát: giữ phiên |
| API 400/403/404/409/429/500/502 và lỗi mạng | Test kiểm soát: giữ phiên, giữ status/URL/response trong error |
| Login/refresh có hoặc không slash cuối | Test kiểm soát: không tự refresh đệ quy |
| Login mới trong khi refresh cũ đang chạy | Test kiểm soát: success/failure cũ không ghi đè hoặc xóa phiên mới |
| HTTP proxy Authorization/body | Giữ đúng Bearer, method POST và body JSON |
| HTTP proxy redirect 307 | 502 JSON, không Location, không chuyển origin |
| Edge headless | Submit login, mở Đơn hàng có dữ liệu seed, mở Kho có danh sách thật, mở Hàng chờ điều phối, gọi API Điều phối và reload; vẫn trong shell với token hợp lệ |

## Giới hạn và lỗi độc lập

Browser-use không khởi tạo được do lỗi Windows sandbox (`setup refresh had errors`). Kiểm thử trình duyệt thực được hoàn thành bằng Edge headless với profile thử riêng. Chưa kiểm thử thủ công trên phiên trình duyệt cũ của người dùng.

Điều phối hiện là placeholder trong frontend, chưa có màn hình nghiệp vụ. Đã test điều hướng và API `GET /api/v1/dispatch/orders` thật, không tuyên bố hoàn thành UI Điều phối.

Trước khi nạp seed, `GET /api/v1/warehouses` trên database hoàn toàn không có kho trả **500**: `InvalidCastException: System.DBNull -> System.String` ở `WarehousesController.GetWarehouses`, dòng 154. Đây là lỗi danh sách trống độc lập, không phải hết phiên; không mở rộng sửa controller Kho trong yêu cầu xác thực này. Sau nạp seed, endpoint trả 200. Không gây lỗi 429/500/mất mạng vào database vận hành; các tình huống này dùng regression kiểm soát.

Database, profile Edge, JWT/key thử, harness tạm và tiến trình thử đã được dọn sau kiểm thử. Giữ bộ regression Node trong frontend và báo cáo này. Server Node đang chạy trước sửa cần khởi động lại để nạp dev-server.cjs mới; browser cần tải lại JS. Không mở thêm server trên cổng đã chiếm.
