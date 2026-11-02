# Chức năng 9 — Kiểm tra và xác nhận nhận kiện tại kho

Cập nhật 30/10/2026. Hoàn thiện luồng nhận kiện trực tiếp đã chốt, dùng backend chính và dữ liệu kho chung với admin.

## Cách dùng

1. Nhận nhiệm vụ, mở bản đồ đến kho và bấm **Đã nhận kiện hàng**.
2. Hộp **Kiểm tra và nhận kiện** tải lại phân công hiện tại trước khi cho gửi. Nhập mã vận đơn hoặc mã đơn đọc trên nhãn kiện, tối đa 50 ký tự; không tự điền mã để bỏ qua đối chiếu thực tế.
3. Đánh dấu **Nhãn và mã kiện khớp nhiệm vụ**, **Đã nhận đủ kiện và bao bì nguyên vẹn**. Có thể ghi chú lúc nhận, tối đa 500 ký tự. Các dấu kiểm là xác nhận của tài xế trên giao diện, không phải kết quả hệ thống tự kiểm chứng tình trạng vật lý.
4. Chọn **Đã nhận kiện hàng**. Chỉ sau phản hồi xác nhận hợp lệ, app chuyển sang Đi giao; thứ tự giao giữ theo admin. Hệ thống xuất toàn bộ kiện của đúng một đơn, không xuất các đơn khác trong chuyến hoặc nhận từng phần trong một đơn.
5. Nếu sai mã, thiếu hoặc hỏng kiện, chọn **Báo sự cố**, nhập mô tả. Báo cáo hiện ở mục **Kho → Xuất kho / bàn giao** sau khi làm mới và có nhật ký quản trị. Báo cáo không tự xuất kho hoặc chuyển trạng thái giao; liên hệ kho/điều phối để có hướng xử lý trước khi nhận.

Không thêm bước nhân viên kho bắt buộc xác nhận bàn giao trước khi tài xế nhận kiện. Các phiếu bàn giao cũ vẫn dùng luồng cũ hiện có để hoàn tất dữ liệu lịch sử. Không thêm lựa chọn Tạm nghỉ.

Bước này ghi nhận mã, xác nhận trên giao diện và ghi chú; **chưa bổ sung quét mã bằng camera hoặc ảnh lúc nhận kiện**. Ảnh bằng chứng các lần giao đã có ở chức năng 8 là dữ liệu riêng.

## Xác nhận và mất kết nối

- Khóa thao tác gửi/đóng khi đang gửi. Không cho vào bước gửi khi dữ liệu phân công mới chưa đọc được, không còn ACCEPTED/ASSIGNED hiện hành hoặc đã kết thúc.
- API nhận kiện chỉ được xem là thành công khi trả đúng assignmentId, orderId hợp lệ, tài xế hiện tại, phiếu nhận CONFIRMED, handoverId hợp lệ, trạng thái IN_DELIVERY và thời điểm máy chủ. HTTP 200 với JSON thiếu/sai hoặc callback false không được điều hướng sang giao.
- Sau lỗi/timeout, hộp đọc lại đúng nhiệm vụ; chỉ dùng bằng chứng nhận thực tế khi có parcelReceivedAt và phân công IN_PROGRESS/IN_DELIVERY còn hiện hành. Không chỉ dựa vào nhãn trạng thái giao hoặc danh sách bản đồ cũ.
- Nếu kết quả chưa rõ và đọc lại cũng lỗi, khóa nút gửi; dùng **Kiểm tra trạng thái nhận kiện**. Không tự phát lại lệnh nhận. Nếu máy chủ xác nhận đã nhận thì tiếp tục sang Đi giao; nếu vẫn chờ nhận thì giữ mã/ghi chú để người dùng kiểm tra và chủ động gửi lại.
- Kiện đã được xác nhận trước khi mở hộp hiển thị thời gian đã lưu và nút **Tiếp tục đi giao**, không tạo yêu cầu xuất mới.
- Hủy/đóng hoặc chuyển sang báo sự cố sẽ tải lại danh sách bản đồ để phản ánh phân công đã đổi. Sau lỗi báo sự cố, hướng dẫn kiểm tra mục Xuất kho/liên hệ điều phối trước khi gửi lại. Báo sự cố chưa có mã lệnh chống lặp riêng hoặc thông báo đẩy bền vững; không tự gửi lại báo cáo khi kết nối lỗi.

## Backend và dữ liệu

POST /api/v1/my/tasks/{id}/pickup giữ transaction kiểm tra tài khoản, quyền, hồ sơ tài xế, bưu cục/kho, phân công, mã nhãn, tồn/vị trí, xe, tải trọng và lịch khởi hành chuyến. Thêm kiểm tra bưu cục hoạt động trước nhánh gửi lại yêu cầu. Notes đã có trong DTO backend được app truyền và lưu vào phiếu nhận/giao dịch kho.

Nhánh alreadyReceived trả lại handoverId, shipperId, handoverStatus và thời gian xác nhận thực tế từ phiếu gốc, không dùng giờ gọi lại và không ghi đè ghi chú. Không tạo thêm outbound hoặc nhận kiện cho phân công đã hoàn tất. Timestamp thực tế tiếp tục xem được trong Chi tiết nhiệm vụ.

POST /api/v1/my/tasks/{id}/pickup-issue bổ sung kiểm tra quyền NHIEMVU_CAPNHAT trực tiếp, đúng bưu cục hiện tại còn hoạt động, phân công đang chờ nhận. Thiếu quyền trả 403; nhiệm vụ không còn thuộc phạm vi chờ nhận trả 409. App kiểm tra phản hồi đúng assignmentId/orderId/lý do trước khi báo đã ghi nhận.

## Kiểm chứng và áp dụng

- Backend build 0 cảnh báo/0 lỗi, Flutter analyze không có vấn đề.
- Toàn bộ Flutter **160/160** đạt; bổ sung **12 ca** về mã/ghi chú, phản hồi nhận sai, lý do sự cố, hai dấu kiểm, chống bấm lặp, callback false, kết quả chưa rõ, xác nhận từ lần đọc mới, báo sự cố và phiếu đã nhận. Hai kiểm thử bản đồ cũ vẫn xác nhận nhận xong chuyển sang Đi giao; kiểm thử refresh token vẫn giữ nguyên payload khi thử lại đúng một lần sau 401.
- **29 nhóm HTTP/SQL/SignalR** đạt trên LocalDB GUID riêng. Bổ sung ghi chú lưu thật, phản hồi gửi lại khớp phiếu/thời gian gốc, không xuất trùng, không nhận lại phân công đã giao xong, không xuất đơn khác trong chuyến, quyền/bưu cục báo sự cố, dữ liệu không hợp lệ không ghi nhật ký/xuất kho. Hồi quy phiên, phân công, chi tiết/ảnh, COD, hoàn kho và lộ trình vẫn đạt.
- Database/API thử đã dọn; không thay dữ liệu vận hành hoặc chạy app/thiết bị của người dùng. Chưa kiểm tra thực địa trên điện thoại hay camera/GPS vật lý trong bước này.

Không cần migration hoặc nạp lại SQL. Chạy lại backend trong Visual Studio bằng profile **http** và chạy lại Flutter.
