# Chức năng 1 — Đăng nhập, duy trì phiên và đăng xuất

Ngày cập nhật: 30/10/2026. Phạm vi: app_shipper và backend/LastMile/LastMile.Api ở thư mục gốc dự án.

## Hành vi

- Chỉ cho vào màn công việc sau khi đăng nhập đúng tài khoản SHIPPER và máy chủ xác nhận hồ sơ tài xế, bưu cục đang hoạt động, có quyền NHIEMVU_XEM. Tài khoản admin bị từ chối; app cố thu hồi phiên vừa cấp mà không lưu phiên đó.
- Kiểm tra dữ liệu đăng nhập trước khi lưu. Token nằm trong bộ lưu trữ bảo mật; thông tin hiển thị lưu trong SharedPreferences. Token kiểu lưu cũ được chuyển sang bộ lưu trữ bảo mật khi đọc.
- Mở lại app phải kiểm tra phiên với máy chủ, không chỉ dựa vào token còn trên thiết bị. Lỗi mạng/máy chủ hiển thị Thử lại / Đăng nhập lại và giữ phiên để có thể thử lại. Khi quay lại app từ nền, kiểm tra lại phiên.
- Token sắp hết hạn được làm mới qua một yêu cầu dùng chung. Khi máy chủ trả 401, làm mới rồi thử lại yêu cầu đúng một lần. 401 tiếp theo hoặc refresh bị từ chối sẽ xóa phiên, đóng toàn bộ màn công việc, ngắt kết nối cập nhật và đưa về đăng nhập có giải thích.
- Không tự gửi lại thao tác nhận kiện/giao hàng/COD khi lỗi mạng, timeout hoặc lỗi nghiệp vụ. Gửi ảnh thất bại cũng đi qua cơ chế phiên chung. 403 của một thao tác nghiệp vụ không tự đăng xuất toàn bộ app; 403/404 của API kiểm tra hồ sơ được xử lý là không đủ điều kiện sử dụng app.
- Đăng xuất xóa dữ liệu phiên cục bộ và tăng phiên bản phiên trước khi đợi thu hồi từ máy chủ. Yêu cầu cũ hoặc refresh đến muộn không được khôi phục token hay ghi dữ liệu sang tài khoản đăng nhập sau. Thông báo rõ nếu đã đăng xuất cục bộ nhưng chưa xác nhận thu hồi với máy chủ.
- Khóa màn thao tác trong lúc đăng xuất; không thay đổi trạng thái hàng, phân công hay tự chuyển tài xế OFFLINE khi còn giữ hàng.
- Nút đăng nhập không nhận bấm lặp trong lúc đang gửi; kiểm tra ô trống, xóa mật khẩu sau lần đăng nhập thất bại. Khi vào màn công việc, xóa các màn đăng nhập khỏi lịch sử quay lại.

## API bổ sung

`GET /api/v1/my/shipper-status` là thao tác chỉ đọc. Lấy accountId từ phiên đã xác thực, không nhận ID tài xế từ client. Kiểm tra tài khoản/vai trò hoạt động, NHIEMVU_XEM, bưu cục hoạt động và hồ sơ tài xế hoạt động. Trả shipperId, employeeCode, accountId, branchId, fullName, availability, vị trí gần nhất và thời gian ghi nhận. 401 cho phiên/tài khoản không hợp lệ; 403 cho vai trò/quyền/hồ sơ/bưu cục không phù hợp. Không cần thay đổi schema.

Phân quyền nhiệm vụ tiếp tục do API kiểm tra người được phân công và bưu cục; app không dùng lọc giao diện để thay thế kiểm tra quyền ở máy chủ.

## Kiểm chứng

- Backend build output riêng `frontend/tests/.artifacts/shipper-auth/build`: đạt, 0 cảnh báo, 0 lỗi.
- Toàn bộ Flutter: **50/50** kiểm thử đạt, gồm **23** ca bổ sung cho phiên và giao diện đăng nhập. Kiểm tra phiên hết hạn, 401 đồng thời, refresh đến muộn sau đăng xuất, phản hồi tài khoản cũ, ảnh multipart, lỗi mạng và xóa lịch sử màn công việc.
- Kiểm thử HTTP/SQL/SignalR `frontend/tests/shipper-sync-api.cjs`: **12 nhóm đạt** trên cơ sở dữ liệu LocalDB tạm `CodexAdmin_<GUID>`. Đã xác nhận API hồ sơ từ chối anonymous/admin/hồ sơ tắt/bưu cục tắt, trả đúng tài xế hiện tại; tài xế khác không xem/nhận nhiệm vụ; phiên bị thu hồi nhận 401. Các luồng nhận kiện, giao thành công, COD, ảnh thất bại, hoàn kho và tuyến điều phối vẫn đạt. Cơ sở dữ liệu tạm đã được xóa.
- Không mở/chạy app hoặc điều khiển máy ảo/điện thoại. Cần kiểm tra thủ công trên thiết bị sau khi chạy lại backend và Flutter.

## Áp dụng và kiểm tra thủ công

1. Trong Visual Studio, dừng và chạy lại LastMile.Api với profile http để nạp API GET mới; dừng/chạy lại Flutter.
2. Đăng nhập tài xế hợp lệ, đóng rồi mở lại app: máy chủ xác nhận phiên trước khi hiện công việc.
3. Thử sai mật khẩu và tài khoản admin: không vào màn công việc.
4. Thu hồi/khóa tài khoản từ admin rồi làm mới nhiệm vụ hoặc quay lại app: yêu cầu đăng nhập lại, không quay lại màn cũ bằng Back.
5. Đăng xuất, mở lại app: ở màn đăng nhập/chào mừng. Tắt kết nối khi đăng xuất: vẫn thoát trên thiết bị và có thông báo chưa xác nhận thu hồi phía máy chủ.

Đổi/khôi phục mật khẩu là chức năng 2, được bổ sung sau trong [shipper-password.md](shipper-password.md).
