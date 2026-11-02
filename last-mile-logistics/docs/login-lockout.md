# Chống đăng nhập sai liên tục

## Cấu hình

Trong `backend/LastMile/LastMile.Api/appsettings.json`:

```json
"LoginSecurity": {
  "MaxFailedAttempts": 5,
  "LockoutMinutes": 15,
  "IpPermitLimit": 20,
  "IpWindowSeconds": 60
}
```

Có thể ghi đè bằng biến môi trường tương ứng, ví dụ
`LoginSecurity__MaxFailedAttempts` và `LoginSecurity__LockoutMinutes`.
Giá trị mặc định cũng nằm trong `LoginSecurityOptions`. Cấu hình được kiểm tra
khi khởi động: ngưỡng 1–100, khóa 1–1440 phút, giới hạn IP 1–10000 request và
cửa sổ IP 1–3600 giây. Thay cấu hình rồi khởi động lại API.

Không cần migration mới: dùng các cột sẵn có `SoLanDangNhapSai`, `KhoaDenLuc`
và `DangNhapCuoiLuc`; không đổi `TrangThaiTaiKhoan`. Cơ chế phiên `sid` và
migration phiên của lần sửa trước vẫn là điều kiện triển khai của API.

## Luồng xử lý

Controller đọc trạng thái/hash, đóng kết nối rồi xác minh BCrypt ngoài SQL
transaction. Khi sai, `LoginAttemptService` mở transaction, khóa tài khoản
`UPDLOCK, HOLDLOCK`, kiểm tra lại ACTIVE, vai trò hoạt động, hash và thời hạn
khóa. Kết quả xác minh của hash cũ sau reset mật khẩu không làm tăng bộ đếm.

Lượt sai hợp lệ tăng nguyên tử. Đạt ngưỡng thì đặt mốc khóa theo giờ SQL UTC.
Trong khi khóa, không tăng đếm, không kéo dài thời gian khóa và không cấp
token. Sau khi mốc khóa đã hết hạn, lượt sai đầu tiên bắt đầu ở 1. Bộ đếm được
giữ ở ngưỡng trong thời gian khóa, kể cả nhiều request đồng thời.

Khi đúng, `AuthTokenService` kiểm tra lại trạng thái, hash và mốc khóa dưới khóa
tài khoản hiện có. Việc cấp phiên/token, cập nhật `DangNhapCuoiLuc`, đưa bộ đếm
về 0 và xóa mốc khóa tạm hết hạn cùng commit trong một transaction. Không có
khoảng trống giữa reset bộ đếm và cấp token. Refresh không reset bộ đếm.
Luồng khóa/ngừng hoạt động của quản trị viên được giữ nguyên; login không tự
chuyển `LOCKED` hoặc `INACTIVE` sang `ACTIVE`.

Không tồn tại tên đăng nhập, sai mật khẩu, tài khoản bị khóa hoặc ngừng hoạt
động đều nhận HTTP 401 với cùng thông báo `Thông tin đăng nhập không hợp lệ.`
Giao diện tiếp tục hiện thông báo chung hiện có. Đầu vào mật khẩu tối đa 72
ký tự và 72 byte UTF-8 để tránh BCrypt cắt ngầm. Không áp dụng tối thiểu 8 ký tự
cho login nhằm giữ khả năng đăng nhập của tài khoản cũ; tạo/đổi mật khẩu vẫn
giữ quy định hiện có. Đầu vào vượt giới hạn bị từ chối trước BCrypt, không tăng
đếm: quá 72 ký tự nhận 400 validation; quá 72 byte nhận 401 chung.

Endpoint login áp dụng fixed-window rate limit theo `RemoteIpAddress`, không
theo username; mặc định request thứ 21 trong cửa sổ 60 giây nhận JSON HTTP 429.
Request bị chặn không tới BCrypt/SQL và không tăng đếm tài khoản. Header
`X-Forwarded-For` tự gửi không thay đổi IP. Khi triển khai sau reverse proxy,
cần cấu hình forwarded headers cho proxy tin cậy để nhận đúng IP khách.
Bộ đếm IP nằm trong từng instance API; bộ đếm tài khoản nằm trong SQL nên vẫn
được tuần tự hóa giữa các instance. Chưa triển khai rate limit IP phân tán.

Không thêm nhật ký mật khẩu, token hay nội dung request. Không thay contract
đăng nhập thành công hoặc cơ chế refresh/logout/thu hồi phiên.

## Kiểm chứng thực tế ngày 19/10/2026

- `npm.cmd run test:auth-login`: build riêng 0 lỗi/0 cảnh báo; 14/14 kiểm tra
  HTTP/LocalDB đạt. Bao gồm đếm dưới ngưỡng, khóa 15 phút, từ chối mật khẩu
  đúng trong lúc khóa, hết khóa rồi đúng/sai, reset sau thành công, request sai
  đồng thời, LOCKED/INACTIVE, khóa/hash đổi khi login đang xử lý, giới hạn đầu
  vào, cấu hình 3 lần/2 phút, IP mặc định trả 429 và cửa sổ IP được cấp lại.
- Hai ca kiểm tra kết quả BCrypt dùng transaction fixture giữ khóa tài khoản,
  cho HTTP request bắt đầu rồi commit khóa tạm hoặc hash thay thế. Không có
  token được cấp từ kết quả cũ và không tăng sai cho hash mới.
- `node tests/auth-sessions.cjs`: 14/14 kiểm tra thu hồi phiên/refresh/logout
  đạt với binary vừa build, gồm 401 đồng thời và refresh chạy cùng reset.
  Host kiểm thử này tăng riêng IP budget lên 1000 để không trộn hai lớp test.
- `npm.cmd test`: 66/66 test frontend đạt.

Chỉ dùng database LocalDB GUID cách ly và tài khoản `qa.login.*`; database đã
dọn sau kiểm thử. Không thử khóa tài khoản quản trị vận hành. Để kiểm tra hết
khóa nhanh, fixture chỉ đưa mốc thời gian của tài khoản thử về quá khứ; đã xác
nhận khoảng thời gian khóa được tạo là 15 phút, không ngồi chờ đủ 15 phút.

Chưa chạy thao tác đăng nhập qua trình duyệt trong lần sửa này; chưa kiểm thử
tải lớn nhiều instance, cấu hình reverse proxy thực tế hoặc rate limit phân tán.

## Kiểm tra trên giao diện

1. Dùng môi trường thử, tạo tài khoản ACTIVE riêng. Giữ một cửa sổ quản trị
   khác để mở **Tài khoản → Chi tiết** của tài khoản thử.
2. Trong cửa sổ ẩn danh, nhập sai 1–4 lần. Tải lại chi tiết tài khoản để xem
   **Số lần đăng nhập sai** tăng tương ứng, chưa có khóa tạm.
3. Nhập sai lần 5, tải lại chi tiết: vẫn ACTIVE nhưng có **Khóa tạm thời đến**.
   Nhập đúng ngay sau đó vẫn thất bại với thông báo chung và không vào ứng dụng.
4. Chờ hết 15 phút, nhập đúng: đăng nhập thành công, bộ đếm về 0, mốc khóa rỗng
   và **Đăng nhập gần nhất** được cập nhật. Có thể đặt 1 phút ở môi trường thử
   rồi khởi động lại API để kiểm tra nhanh.
5. Quản trị viên khóa tài khoản thử bằng thao tác **Khóa**: đăng nhập đúng vẫn
   thất bại đến khi được mở khóa, bất kể thời hạn khóa tạm.
6. Gửi hơn 20 lần đăng nhập trong 60 giây từ cùng IP (có thể đổi username):
   DevTools Network hiện 429 và giao diện báo quá nhiều yêu cầu đăng nhập.
   Dùng username không tồn tại cho bước này để tách kiểm tra IP khỏi khóa tài khoản.

Chạy lại test trong `frontend`: `npm.cmd run test:auth-login`,
`npm.cmd run test:auth-sessions`, `npm.cmd test`.
