# Chức năng 3 — Hồ sơ tài xế

Ngày cập nhật: 30/10/2026. Backend chính: backend/LastMile/LastMile.Api; app: app_shipper.

## Sử dụng

Trang chủ → biểu tượng tài khoản góc trên → **Hồ sơ tài xế**.

- Thông tin cá nhân: họ tên, mã nhân viên, tên đăng nhập, điện thoại, email và CCCD. CCCD mặc định che một phần, có nút hiện/ẩn.
- Giấy phép lái xe: số giấy phép, ngày hết hạn, còn hạn/sắp hết hạn/đã hết hạn. Cảnh báo sắp hết hạn trong 30 ngày; hạn trong ngày hôm nay còn hiệu lực hết ngày theo lịch Việt Nam UTC+07. Thông tin giấy phép chưa khai báo được hiển thị rõ, không tự suy ra đã hết hạn.
- Bưu cục quản lý: tên, mã, địa chỉ, điện thoại và email. Có nút mở cuộc gọi nếu bưu cục có số điện thoại.
- Phương tiện đang được phân công: biển số, mã xe, loại xe, tải trọng/thể tích tối đa, thời gian phân công và trạng thái. Xe bảo dưỡng hoặc ngừng hoạt động vẫn hiện đúng trạng thái. Không dùng xe của đơn hàng cũ thay cho phân công hiện hành.
- Khu vực phụ trách: tên/mã, khu vực chính và trạng thái hoạt động.
- Nút đổi mật khẩu mở chức năng 2.

Thông tin hồ sơ do admin quản lý; không bổ sung sửa hồ sơ hoặc tự đổi xe trên app. Thiếu trường tùy chọn hiển thị Chưa cập nhật. Không có phân công xe/khu vực có trạng thái trống riêng. Kéo xuống hoặc bấm Làm mới hồ sơ để đọc lại máy chủ; quay lại app từ nền khi đang ở màn hồ sơ cũng tải lại. Nếu tải lại thất bại, dữ liệu trước đó được gắn nhãn lần tải trước, có nút Thử lại.

## API

`GET /api/v1/my/profile` có Bearer token và chỉ đọc. Lấy accountId từ phiên xác thực, không nhận ID tài xế để chọn đối tượng. Kiểm tra tài khoản/vai trò hoạt động, quyền NHIEMVU_XEM, bưu cục và hồ sơ tài xế hoạt động. Admin hoặc vai trò khác không dùng endpoint này để xem hồ sơ người khác.

Trả accountId, shipperId, employeeCode, username, fullName, phone, email, availability, identityNumber, licenseNumber, licenseExpiresAt, licenseStatus, licenseDaysRemaining, serverDate, branch, currentVehicle và areas. currentVehicle là phân công có ThoiGianKetThuc IS NULL; không có xe trả null, không có khu vực trả []. Không trả mật khẩu/hash/token. Không thay đổi trạng thái tài xế, giấy phép, đơn hay xe và không tạo nhật ký ghi dữ liệu cho thao tác đọc.

App kiểm tra dữ liệu và accountId khớp phiên trước khi cập nhật tên/mã nhân viên đã lưu để trang chủ phản ánh thay đổi từ admin. API dùng kiểm tra phiên/refresh của chức năng 1. 403 do mất điều kiện sử dụng hồ sơ sẽ kết thúc phiên; endpoint chưa có/không truy cập được hiển thị lỗi thay vì tạo dữ liệu mẫu.

Không yêu cầu migration mới cho chức năng này. Bộ fixture cũ được bổ sung migration rowversion đã có để kiểm thử đối chiếu với API admin; chỉ chạy bản migration đã gắn đúng tên database GUID tạm. Không áp dụng migration lên database vận hành trong lần sửa này.

## Kiểm chứng

- Backend build output riêng frontend/tests/.artifacts/shipper-profile/build: đạt, 0 cảnh báo, 0 lỗi.
- Flutter analyze: không có vấn đề.
- Toàn bộ Flutter: **81/81** kiểm thử đạt, gồm **13** ca mới cho dữ liệu/API client và giao diện hồ sơ. Kiểm tra CCCD ẩn/hiện, thiếu dữ liệu, giấy phép, xe bảo dưỡng, lỗi tải/tải lại, tên dài/cỡ chữ lớn và mở đổi mật khẩu.
- Kiểm thử HTTP/SQL/SignalR: **15 nhóm đạt** trên LocalDB tạm. Hồ sơ khớp API admin; giả mạo ID qua query vẫn chỉ trả đúng tài xế; kiểm tra 401/403, thu hồi phiên, cập nhật hồ sơ, xe kết thúc phân công, khu vực trống và các mốc hạn giấy phép -1/0/30/31 ngày theo lịch Việt Nam. Các luồng nhận kiện/giao/COD/hoàn/tuyến hiện có vẫn đạt. Database tạm đã được dọn.
- Chạy lại kiểm thử API bằng npm.cmd run test:shipper-profile trong frontend.
- Không mở app, máy ảo/điện thoại hoặc chỉnh dữ liệu vận hành. Cần kiểm tra thủ công trên thiết bị sau khi chạy lại backend và Flutter.

## Nạp thay đổi

Trong Visual Studio dừng/chạy lại backend LastMile.Api với profile http để có GET mới. Dừng/chạy lại Flutter; vào menu tài khoản → Hồ sơ tài xế. Sau khi admin cập nhật thông tin hoặc phân công xe, bấm làm mới để đối chiếu.
