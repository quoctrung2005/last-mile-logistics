# Chức năng 5 — Trạng thái làm việc tài xế

Cập nhật 30/10/2026. App và web dùng backend chính, cùng dữ liệu tài xế hiện có. Theo lựa chọn của người dùng, **không có lựa chọn Tạm nghỉ** trên app.

## Cách dùng

Trang chủ có hai lựa chọn **Sẵn sàng** và **Ngoại tuyến**. Chuyển ngoại tuyến cần xác nhận. **Đang giao** được cập nhật từ luồng nhận kiện/bắt đầu giao, tài xế không tự chọn trạng thái này. Nếu trạng thái vẫn là Đang giao nhưng đã hết công việc, app cho chọn trạng thái tiếp theo; không khóa công tắc vĩnh viễn như trước.

| Điều kiện | Sẵn sàng | Ngoại tuyến |
| --- | --- | --- |
| Không còn công việc, giấy phép và xe phù hợp | Cho phép | Cho phép |
| Còn phân công chưa kết thúc hoặc chuyến ASSIGNED/ACCEPTED | Cho phép nếu chưa có hàng đang giao/hoàn và đủ điều kiện | Chặn, hiện lý do |
| Hàng đang giao, giao thất bại/chờ giao lại hoặc chuyến chưa xử lý xong | Chặn, tiếp tục xử lý nhiệm vụ | Chặn, hoàn tất hoặc liên hệ điều phối |
| Chỉ còn kiện hoàn đã chốt, chờ trả kho cuối ca | Cho phép; có thể nhận chuyến mới khi đủ tải | Chặn đến khi kho xác nhận nhận đủ |
| Bằng lái đã hết hạn, chưa có xe được phân công hoặc xe không hoạt động/đang bảo trì | Chặn, hướng dẫn liên hệ quản lý | Cho phép nếu hết công việc |
| Không có quyền cập nhật hoặc chưa tải được trạng thái | Không cho đổi | Không cho đổi |

Giấy phép còn hợp lệ suốt ngày hết hạn theo ngày Việt Nam; giấy phép không có ngày hết hạn giữ quy tắc tùy chọn hiện hành của admin. Xe phải có phân công chưa kết thúc, đang hoạt động và AVAILABLE/IN_USE. Hàng RETURNING kiểm tra người được phân công gần nhất, kể cả phân công đã đóng; chỉ kho nhận hàng hoặc thay đổi nghiệp vụ hợp lệ mới giải phóng trách nhiệm này.

Ngoại tuyến không đăng xuất và không xóa nhiệm vụ/COD. Admin không phân công đơn mới cho tài xế ngoại tuyến; trang Nhân viên giao hàng/Làm mới đọc cùng trạng thái đã lưu. Đổi trạng thái ghi nhật ký máy chủ khi giá trị thực sự đổi.

Điều chỉnh sau bước 10: [kiện hoàn chờ trả kho cuối ca](shipper-deferred-returns.md) không làm hasDeliveryWork=true, không giữ khóa Sẵn sàng/chuyến giao. pendingReturnCount theo dõi trách nhiệm còn giữ; tải trọng/thể tích vẫn tính khi nhận công việc mới.

## Đồng bộ và lỗi mạng

- GET /api/v1/my/shipper-status vẫn chỉ đọc, xác định tài xế từ phiên. Bổ sung hasActiveWork, hasDeliveryWork, canSetAvailable, canSetOffline, availableBlockedReason, stopBlockedReason. Điều kiện hiển thị và điều kiện ghi dùng cùng quy tắc SQL; máy chủ khóa và kiểm tra lại khi ghi.
- PATCH cùng endpoint nhận availability AVAILABLE/OFFLINE và expectedAvailability mà app vừa đọc. Trạng thái đã khác trả 409 để tải lại; hai lệnh đồng thời dựa trên cùng trạng thái cũ không ghi đè lẫn nhau. DELIVERING/BREAK không phải lệnh tài xế được gửi. Bản ghi BREAK cũ vẫn đọc được để người dùng chuyển sang một trong hai lựa chọn mới; không tự sửa hàng loạt dữ liệu lịch sử.
- App khóa thao tác lúc đang gửi, dùng giá trị máy chủ trả về thay vì tự gán giá trị yêu cầu. Lỗi mạng/xung đột/response không hợp lệ sẽ đọc lại trạng thái; không tự gửi lại lệnh ghi. Nếu đọc lại cũng thất bại, hiện nút tải lại và khóa lựa chọn. Phản hồi đến sau đăng xuất không được áp dụng.
- Tải lại khi về Trang chủ, quay lại app hoặc theo chu kỳ khi đang xem Trang chủ. Phản hồi đọc cũ không đè kết quả đổi trạng thái mới.
- Khi bật Sẵn sàng, thử lấy GPS hiện tại; tọa độ làm tròn 6 chữ số, độ chính xác 2 chữ số phù hợp schema. Không lấy được GPS vẫn cho đổi nếu đủ điều kiện và thông báo rõ vị trí chưa được cập nhật. Không tự tạo tọa độ, không theo dõi nền trong chức năng này.

## Kiểm tra và áp dụng

- Backend build đạt, 0 cảnh báo/0 lỗi; Flutter analyze không có vấn đề.
- Toàn bộ Flutter **108/108** đạt, thêm 12 ca về dữ liệu trạng thái, GPS, phiên, lỗi ghi, hai lựa chọn, xác nhận ngoại tuyến, điều kiện khóa và làm mới. Giao diện kiểm tra ở 320px; bộ kiểm tra dashboard có cả chữ lớn.
- **18 nhóm HTTP/SQL/SignalR đạt** bằng shipper-sync-api.cjs trên LocalDB GUID tạm: trạng thái khớp API admin; ngoại tuyến chặn phân công; giấy phép hôm qua/hôm nay; xe bảo trì/hết phân công; quyền trực tiếp; hai lệnh đồng thời; nhiệm vụ chờ, nhận kiện, giao thành công, hoàn hàng và chuyến VRP. Cơ sở dữ liệu thử đã được xóa; không đổi dữ liệu vận hành.
- Không cần migration hoặc nạp lại dữ liệu. Dừng/chạy lại backend trong Visual Studio với profile **http**, rồi chạy lại Flutter để tải giao diện mới.
- Chưa kiểm tra GPS/điện thoại/máy ảo vật lý; không khởi động ứng dụng hay thiết bị của người dùng trong lần sửa này.
