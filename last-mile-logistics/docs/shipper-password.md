# Chức năng 2 — Đổi và khôi phục mật khẩu

Ngày cập nhật: 30/10/2026. Thực hiện trên app_shipper; dùng API của backend/LastMile/LastMile.Api ở gốc dự án.

## Cách sử dụng

- Đổi mật khẩu: Trang chủ → biểu tượng tài khoản ở góc trên → **Đổi mật khẩu**. Nhập mật khẩu hiện tại, mật khẩu mới và xác nhận. Sai mật khẩu hiện tại giữ nguyên màn và phiên; thành công xóa thông tin phiên trên thiết bị, ngắt cập nhật nhiệm vụ, đóng lịch sử màn công việc và về đăng nhập với thông báo thành công.
- Quên mật khẩu: màn đăng nhập → **Quên mật khẩu?**. Địa chỉ máy chủ đang nhập được lưu trước khi mở khôi phục. Nhập email đã đăng ký; nếu API xác nhận yêu cầu, chuyển sang nhập mã. Phản hồi trung lập không xác nhận email có tài khoản hay không.
- Mã khôi phục là chuỗi đầy đủ 43 ký tự trong email, không phải OTP 6 số. Có nút **Tôi đã có mã khôi phục** để vào thẳng bước đặt lại. Mã hiệu lực 15 phút và chỉ dùng một lần theo backend.
- Nhập mã, mật khẩu mới và xác nhận; thành công về đăng nhập. Mã sai/hết hạn/đã dùng hiển thị lỗi, cho sửa mã hoặc quay lại yêu cầu mã mới. Giới hạn gửi lại trên app là 60 giây, phù hợp cơ chế một mã mới/phút/tài khoản của backend.
- Mật khẩu mới ít nhất 8 ký tự, không chỉ khoảng trắng, không vượt giới hạn 72 byte UTF-8 của backend. Đổi mật khẩu yêu cầu khác mật khẩu hiện tại; xác nhận so sánh chính xác, không tự cắt khoảng trắng của mật khẩu.
- Có nút hiện/ẩn mật khẩu, khóa bấm lặp và quay lại khi đang gửi. Mật khẩu/mã chỉ nằm trong biểu mẫu đang mở, không lưu vào SharedPreferences, không ghi log.

## API và phiên

1. `POST /api/v1/auth/change-password` với currentPassword, newPassword, confirmPassword; có Bearer token. Sử dụng cơ chế refresh/401 của chức năng 1. Lỗi mật khẩu hiện tại là 400, không tự đăng xuất.
2. `POST /api/v1/auth/password-recovery` với action=REQUEST, email; không gửi Bearer token.
3. Cùng endpoint với action=RESET, recoveryToken, newPassword, confirmPassword; không gửi Bearer token. 401 ở đây là mã khôi phục không hợp lệ, không kích hoạt refresh hoặc đăng xuất một phiên khác.

Backend hiện có cập nhật mật khẩu và thu hồi toàn bộ phiên/refresh token trong cùng giao dịch. RESET dùng token một lần, lưu hash token, không tự mở khóa tài khoản do admin khóa. Không cần sửa backend hoặc schema trong lần nối giao diện này. Dùng schema hiện hành có dbo.TokenKhoiPhucMatKhau; không chạy script seed/xóa dữ liệu để cài tính năng.

Phản hồi cũ không được xóa phiên mới nếu tài khoản đã đăng nhập lại trong lúc chờ RESET. Hàng đợi ghi/xóa phiên được giải phóng khi rảnh, vẫn giữ tuần tự và kiểm tra thế hệ phiên để tránh refresh đến muộn.

## Điều kiện nhận email thật

Các tệp appsettings dự án hiện chưa có cấu hình Email. Cần cấu hình dịch vụ gửi email trên máy chủ trước khi nhận mã thật; có thể dùng cấu hình riêng của Visual Studio (nhấp phải project LastMile.Api → Manage User Secrets), giữ thông tin SMTP ngoài mã nguồn. Các khóa backend đọc:

| Khóa | Nội dung |
| --- | --- |
| Email:Host | Máy chủ SMTP của dịch vụ email đang sử dụng |
| Email:Port | Cổng SMTP, mặc định 587 |
| Email:EnableSsl | true cho kết nối TLS thông thường |
| Email:From | Địa chỉ người gửi hợp lệ |
| Email:Username | Tài khoản SMTP |
| Email:Password | Thông tin xác thực SMTP do dịch vụ email cấp |

Email tài xế phải được khai báo trên tài khoản trong admin. Không đưa mật khẩu SMTP vào chat hoặc tệp mã nguồn. Thiếu cấu hình trả 503: app giữ bước email và hiển thị lý do, không thông báo đã gửi mã. Nếu chưa có email hoặc không còn truy cập được email, liên hệ quản trị viên để xử lý tài khoản theo quyền hiện có.

Sau khi cấu hình, chạy lại backend trong Visual Studio với profile http và dừng/chạy lại Flutter để có giao diện mới.

## Kiểm chứng

- Toàn bộ Flutter: **68/68** kiểm thử đạt. Flutter analyze: không có lỗi/cảnh báo.
- 12 kiểm thử API client/quy tắc mật khẩu và 6 kiểm thử giao diện mới: đạt. Kiểm tra dữ liệu gửi thực tế, thông báo lỗi, thao tác trùng, cooldown, mã hết hạn, chuyển về đăng nhập và phản hồi đến muộn.
- Kiểm thử SQL/HTTP/SMTP trong `frontend/tests/shipper-password-api.cjs`: **7 nhóm đạt**. Tạo tài khoản SHIPPER và database LocalDB tạm; nhận email qua SMTP trên 127.0.0.1; lấy mã từ nội dung email thật; kiểm tra lưu hash, gửi lại, mã sai/hết hạn/đã dùng, thu hồi tất cả phiên, đăng nhập bằng mật khẩu mới và tài khoản bị khóa. Database tạm đã được dọn. Không gửi email ra ngoài hoặc sửa database vận hành.
- Chạy lại kiểm thử tích hợp bằng `npm.cmd run test:shipper-password` trong frontend. Mọi mật khẩu/token QA tạo ngẫu nhiên, không in ra output.
- Không điều khiển máy ảo/điện thoại hoặc khởi chạy app của người dùng. Chưa thử giao nhận email với dịch vụ SMTP bên ngoài.
