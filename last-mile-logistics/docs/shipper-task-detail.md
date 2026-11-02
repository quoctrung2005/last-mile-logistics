# Chức năng 8 — Chi tiết nhiệm vụ

Cập nhật 30/10/2026. App_shipper dùng backend chính và dữ liệu phân công chung với admin.

## Cách dùng

Vào **Nhiệm vụ**, chọn một tab rồi bấm **Xem chi tiết nhiệm vụ** trên thẻ đơn. Nút có ở cả nhiệm vụ đang thực hiện và Hoàn tất. Màn chi tiết đọc lại từ máy chủ theo ID phân công, không lấy bản cũ trên thẻ làm nguồn dữ liệu.

Màn hiển thị:

- Mã đơn/vận đơn, trạng thái nhiệm vụ và trạng thái đơn hiện tại trên quản lý, bưu cục, chuyến/thứ tự điểm nếu có.
- Kho lấy kiện và địa chỉ, người nhận/điện thoại/địa chỉ giao, xe được phân công và ghi chú.
- COD cần thu hộ và phí vận chuyển của đơn. Ghi rõ phí vận chuyển **chưa phải tiền công tài xế**, không tự tính thu nhập từ khoản này.
- Thời điểm phân công, chấp nhận, **nhận kiện thực tế**, hạn giao và kết thúc phân công. Mốc chưa có ghi Chưa ghi nhận, không suy đoán từ trạng thái.
- Hàng trong kiện: tên, số lượng, khối lượng đơn vị, hàng dễ vỡ và ghi chú.
- Từng lần giao thuộc đúng phân công: kết quả, thời gian, lý do thất bại, ghi chú, lịch giao lại, bằng chứng và người nhận nếu đã ghi nhận.
- Yêu cầu giao lại/thu hồi/hoàn trong khoảng phân công: lý do, trạng thái, bưu cục nhận hoàn và thời gian hoàn tất.
- Lịch sử chuyển trạng thái trong khoảng phân công. Với phân công giao thất bại cuối cùng còn trách nhiệm hoàn, vẫn gồm mốc RETURNING/RETURNED sau khi phân công đóng để thấy kho đã nhận.

Lịch sử được sắp mới nhất trước, lấy thời gian SQL UTC và hiển thị theo giờ thiết bị. Cột thời gian SQL hiện có độ chính xác tới giây; không tạo thời gian giả để tách các sự kiện cùng giây.

## Xem ảnh và thao tác

Ảnh được tải khi bấm **Xem ảnh bằng chứng**, mở ngay trong app và có phóng to/thu nhỏ. Không tự tải tất cả ảnh khi mở chi tiết. Chỉ loại PHOTO/SIGNATURE có nút xem ảnh; xác nhận không có file ảnh vẫn hiển thị thông tin mà không tạo ảnh giả. Ảnh lỗi/không còn được phép xem có thông báo riêng và giữ màn chi tiết.

App gọi endpoint file cố định theo orderId/evidenceId bằng phiên đăng nhập. Không mở URL tùy ý từ dữ liệu bằng chứng, không đưa token vào URL và không lưu ảnh xuống máy. API trả private, no-store, nosniff; kiểm tra người sở hữu lần giao, hồ sơ hoạt động, bưu cục hiện tại khớp đơn và bưu cục còn hoạt động. Tài xế khác/đã chuyển bưu cục/hồ sơ ngừng không được tải ảnh. Quyền xem của nhân viên quản lý vẫn theo endpoint hiện có.

Nhiệm vụ hiện hành có nút gọi khách và mở bản đồ tương ứng khi phù hợp. Nhiệm vụ kết thúc chỉ xem lịch sử, không có nút gọi hoặc mở tuyến thực hiện. Mở bản đồ từ chi tiết rồi xác nhận nhận kiện vẫn trả về **Đi giao** trên danh sách. Không thêm thao tác giao thành công/từ chối trùng lặp trên màn chi tiết; các thao tác nghiệp vụ vẫn theo luồng đã có.

## Dữ liệu và làm mới

GET /api/v1/my/tasks/{id} thêm parcelReceivedAt và statusHistory. Thời điểm nhận và kho nguồn lấy từ BanGiaoHang CONFIRMED của đúng đơn/tài xế trong khoảng phân công đã chấp nhận; kho nguồn còn hiển thị sau khi xuất kho xóa MaKhoHienTai. Nếu không có xác nhận thì không đặt thời gian nhận bằng thời gian chấp nhận. Thay đổi này chỉ đọc, không sinh phiếu bàn giao mới hoặc thêm bước kho bắt buộc xác nhận trước luồng nhận kiện trực tiếp.

deliveryPoints, items, deliveryAttempts, evidence của từng lần giao, requests và statusHistory luôn là mảng kể cả rỗng. App kiểm tra kiểu, ID, số tiền, thời gian và các tập lồng nhau; dữ liệu thiếu/sai không được đổi thành kết quả thành công giả. API chung vẫn kiểm tra đúng tài xế và bưu cục hiện tại trước khi đọc chi tiết.

Làm mới bằng nút, kéo xuống, quay lại app hoặc tín hiệu thay đổi kiện. Phản hồi đọc đến muộn không ghi đè lượt mới. Khi tải lại thất bại, dữ liệu riêng trước đó được xóa khỏi màn và có Thử lại; không cho gọi/mở tuyến từ dữ liệu chưa kiểm tra lại. Đăng xuất/thu hồi phiên vẫn dùng cơ chế phiên chung, đóng các màn công việc.

## Kiểm chứng và áp dụng

- Backend build 0 lỗi/0 cảnh báo; Flutter analyze không có vấn đề.
- Toàn bộ Flutter **148/148** đạt, thêm **15 ca** về mốc nhận riêng, hàng/lịch sử/hoàn, hợp đồng mảng, dữ liệu sai, API chỉ đọc, ảnh xác thực, mất quyền/lỗi tải, phản hồi chậm, xem/đóng ảnh và bố cục 320px với chữ lớn.
- **27 nhóm HTTP/SQL/SignalR** đạt với LocalDB GUID riêng. Bổ sung kiểm tra GET không ghi nhật ký, nhận nhiệm vụ chưa có thời gian nhận kiện, sau nhận vẫn giữ kho nguồn, lần giao thành công/thất bại đúng phân công, ảnh xem được từ tài xế sở hữu nhưng bị chặn khi đổi/ngừng bưu cục hoặc hồ sơ, và chi tiết hoàn có mốc kho nhận sau khi phân công đóng. Giữ hồi quy toàn bộ luồng phân công, giao/COD, nhập hoàn và lộ trình.
- Database và API thử đã dọn; không đổi dữ liệu vận hành. Không chạy ứng dụng/thiết bị của người dùng; chưa kiểm tra camera hoặc GPS trên điện thoại thật trong bước này.

Không cần migration hoặc nạp lại SQL. Dừng/chạy lại backend trong Visual Studio bằng profile **http** và chạy lại Flutter.
