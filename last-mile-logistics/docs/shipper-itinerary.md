# Chức năng 10 — Lộ trình điều phối trong app

Cập nhật 30/10/2026. Tiếp nối xác nhận nhận kiện, dùng thứ tự chuyến và tuyến từ backend chính của admin.

## Cách sử dụng

Mở tab **Lộ trình**, hoặc mở bản đồ từ nhiệm vụ/chi tiết đơn. Màn hình hiển thị số đơn đang chờ lấy/đi giao, từng **Chuyến #… · Điểm …** theo số thật trên quản lý và dấu **Điểm đang xem**. Không đánh lại số điểm còn lại bắt đầu từ 1; nếu điểm 2 đã kết thúc thì vẫn thấy điểm 1/3 theo dữ liệu admin. Đơn không có chuyến được ghi Đơn lẻ, không tuyên bố đã tối ưu.

Mở từ một đơn thuộc chuyến sẽ giữ các nhiệm vụ lấy/giao còn lại của cùng chuyến. Đơn lẻ chỉ mở phạm vi chính đơn đó. Mở một ID không còn trong danh sách mà chưa biết chuyến không tự chuyển sang chuyến khác.

Chọn **Xem tuyến đến kho**, **Xem tuyến giao đã xếp** hoặc chạm điểm trên bản đồ để chọn điểm xem. Thẻ được đánh dấu và tuyến chuyển sang đúng điểm đó. Danh sách giữ nguyên thứ tự admin, chọn điểm xem/chỉ đường không ghi lại thứ tự chuyến hay gửi yêu cầu tối ưu VRP.

Làm mới giữ điểm đang chọn nếu nhiệm vụ còn hợp lệ. Sau khi nhiệm vụ đang chọn kết thúc/không còn ở bước lấy/giao, lần tải mới chọn điểm còn lại đầu tiên trong phạm vi chuyến; không mang thứ tự cũ sang chuyến khác. Dừng GPS của tuyến cũ khi đổi mục tiêu; người dùng chủ động bắt đầu lại chỉ đường cho điểm mới.

Chỉ hiện các phân công hiện hành, chưa kết thúc và đang ở bước đã nhận nhiệm vụ/lấy/giao. Nhiệm vụ chờ chấp nhận, giao thất bại/chờ giao lại/hoàn hoặc kết thúc vẫn xử lý ở các tab Nhiệm vụ tương ứng, không biến thành điểm giao thông thường trên màn này.

## Tuyến, GPS và lỗi

- Khi có GPS, xem tuyến và dẫn đường đều dùng vị trí hiện tại đến đúng điểm được chọn. Nếu không có GPS, chỉ dùng hình học admin đã lưu khi khớp orderId/stopSequence và phiên bản mạng đường. Không ghi đè tuyến/chuyến admin. Xem [bản sửa đi vòng](routing-detour-fix.md).
- API và app kiểm tra đúng assignmentId, orderId, loại bước, nguồn tuyến, số điểm, hình học, khoảng cách/thời gian hữu hạn và không âm. Thứ tự/đơn không khớp là lỗi cần tải lại, không vẽ tuyến của đơn khác hoặc tự đặt số liệu 0.
- Phản hồi tuyến cũ đến muộn không ghi đè tuyến mới. Khi tải lại nhiệm vụ lỗi, xóa đường/hướng dẫn cũ, dừng GPS và khóa nút chỉ đường/cập nhật kết quả từ dữ liệu chưa kiểm tra lại. Các điểm cũ còn trên màn được kèm lỗi tải, cần làm mới để tiếp tục.
- Làm mới theo chu kỳ 30 giây khi đang xem màn và app ở foreground; tín hiệu cập nhật không tính lại tuyến khi màn đang bị màn khác che. Quay lại app/màn cập nhật kết quả sẽ đọc lại nhiệm vụ. Mở màn cập nhật kết quả hoặc phiếu bàn giao cũ dừng GPS trước khi chuyển màn.
- Giữ các nút bắt đầu/dừng chỉ đường, theo vị trí và kiểm tra lệch tuyến đã có. Không tự xác nhận nhận kiện/giao thành công khi GPS tới nơi. Không thêm theo dõi nền, giọng nói, giao thông trực tiếp hoặc Navigation SDK trong bước này.

Chọn điểm xem không phải phê duyệt thay đổi thứ tự giao. Bước này không thêm quy tắc mới khóa API ghi nhận kết quả theo điểm trước/sau; quy trình kết quả và ngoại lệ điều phối tiếp tục dùng các chức năng hiện có.

## Phạm vi API

GET /api/v1/my/tasks/{id}/route vẫn chỉ đọc. Bổ sung kiểm tra quyền NHIEMVU_XEM hiện tại, bưu cục đang hoạt động và chuyến phải còn mở/khớp tài xế, xe nếu nhiệm vụ có tripId. Chuyến CANCELLED/COMPLETED hoặc đã đổi người không được rơi về tính đường mới như đơn lẻ. Không đủ phạm vi trả 404 như nhiệm vụ không còn khả dụng.

Không thay đổi schema, thứ tự ChiTietChuyenGiao hoặc TripRouteGeometry. Quyền sử dụng app, hồ sơ và phiên tiếp tục kiểm tra qua cơ chế chung.

## Kiểm chứng và áp dụng

- Backend build 0 lỗi/0 cảnh báo, Flutter analyze không có vấn đề.
- Toàn bộ Flutter **174/174** đạt; thêm **14 ca** về phạm vi chuyến, số điểm thật, phân công đã đóng/đơn lẻ, giữ/chuyển điểm khi cập nhật, GET tuyến và dữ liệu sai, chọn điểm, phản hồi hình học đến muộn, lỗi cập nhật dừng GPS, chuyển sang màn kết quả giải phóng stream và ID đã mất không mở nhầm chuyến.
- **30 nhóm HTTP/SQL/SignalR** đạt trên LocalDB GUID thử. Bổ sung thu hồi quyền xem, bưu cục ngừng và chuyến hủy chặn đọc tuyến, khôi phục hợp lệ đọc lại được tuyến admin, tọa độ thiếu trả 400 và hình học lưu không bị thay đổi. Giữ hồi quy chuyến hai điểm đúng thứ tự, nhận kiện, COD, bằng chứng và hoàn kho.
- Kiểm thử bản đồ/GPS dùng ảnh bản đồ trong bộ nhớ và stream vị trí giả lập; không điều khiển app, máy ảo hoặc điện thoại. Database/API thử đã dọn; không đổi dữ liệu vận hành.

Chạy lại backend Visual Studio profile **http** và Flutter. Không cần migration/nạp lại dữ liệu. Vẫn cần thử GPS/di chuyển thực tế trên thiết bị khi người dùng chạy app.
