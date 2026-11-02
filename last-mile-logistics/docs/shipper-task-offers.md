# Chức năng 6 — Xem và phản hồi nhiệm vụ được phân công

Cập nhật 30/10/2026. Dùng app_shipper và backend chính, cùng dữ liệu phân công của admin. Không có lựa chọn Tạm nghỉ; không bổ sung bước kho phải bàn giao trước khi shipper nhận kiện.

## Cách sử dụng

1. Điều phối phân công đơn. App nhận thông báo khi đang kết nối; mất thông báo vẫn xem được tại Nhiệm vụ → Chờ nhận qua danh sách API.
2. Mở thông báo hoặc chọn **Xem và phản hồi nhiệm vụ**. App tải lại đúng nhiệm vụ từ máy chủ để hiển thị kho/địa chỉ lấy, người nhận/địa chỉ giao, xe được phân công, khối lượng, COD, thời điểm phân công, hạn giao và ghi chú có trong dữ liệu. Nội dung thông báo không thay thế lần đọc này.
3. Chọn **Nhận nhiệm vụ và đến kho**. Chỉ mở bản đồ sau khi máy chủ xác nhận nhận nhiệm vụ. Tới kho, kiểm tra đúng kiện và bấm **Đã nhận kiện hàng** theo luồng xác nhận mã vận đơn đã có; hệ thống xuất kho và chuyển sang Đi giao theo thứ tự điều phối.
4. Với đơn lẻ chưa nhận: chọn **Từ chối nhiệm vụ**, nhập lý do tối đa 500 ký tự, chọn **Gửi từ chối**. Máy chủ đóng phân công REJECTED và đưa đơn về WAITING_ASSIGNMENT để điều phối lại; kiện vẫn trong kho. Lý do lưu trong nhật ký và lịch sử trạng thái đơn.
5. **Để sau** chỉ đóng hộp xem, không từ chối hay thay đổi đơn. Xem lại trạng thái ở mục Chờ nhận vì admin có thể đã đổi/hủy phân công.

Nhận nhiệm vụ chỉ ghi nhận chấp nhận và thời gian máy chủ. Không xem hành động này là đã cầm kiện, không xuất tồn kho hay bắt đầu giao. Chỉ nhiệm vụ PENDING/ASSIGNED chưa nhận, chưa kết thúc và còn hiện hành mới có thao tác phản hồi. Nếu đã nhận, đổi tài xế hoặc kết thúc thì hộp hiển thị tình trạng thay vì nút phản hồi cũ.

## Đồng bộ admin và giới hạn chuyến

- API GET /api/v1/my/tasks/{id} bổ sung thông tin kho, người nhận/điểm giao và thứ tự điểm giống danh sách; trả acceptedAt, endedAt, isCurrentTask, isAssignmentActive. App kiểm tra đúng ID và tài xế, không nhận ID tài xế tùy ý từ thông báo.
- Danh sách, chi tiết, nhận và từ chối đều kiểm tra bưu cục hiện tại còn hoạt động. Tài xế đã chuyển bưu cục không xem/phản hồi đơn của bưu cục cũ. Chi tiết không còn trong phạm vi trả 404, xử lý SQL NULL đúng để không thành lỗi 500.
- Nhận/từ chối dùng transaction và khóa nghiệp vụ sẵn có của backend. Nhấn đồng thời chỉ một lệnh thành công; lệnh còn lại nhận 409, không tạo nhiều dấu thời gian/nhật ký. Từ chối sau khi đã nhận hoặc hàng đã xuất bị chặn.
- **Nhiệm vụ thuộc chuyến:** vẫn cho nhận theo luồng hiện có, giữ thứ tự admin. Không cung cấp nút từ chối riêng một đơn vì API hiện hành chặn tách chuyến; hộp giải thích liên hệ điều phối để xử lý cả chuyến. Chưa bổ sung tính năng tài xế từ chối cả chuyến trong bước này.
- Thông báo lặp cùng ID chỉ xếp một lần trong phiên. Khi đang ở màn nhiệm vụ, bản đồ hoặc màn phụ, hộp mới được giữ lại để mở khi quay về Trang chủ; không phủ lên thao tác đang thực hiện. Thông báo chờ trong bộ nhớ không phải hàng đợi bền vững: danh sách máy chủ là nguồn khôi phục sau khi mở lại app.

## Xử lý mất kết nối

Khóa nút và thao tác đóng trong lúc gửi. Chỉ nhận JSON xác nhận đúng nhiệm vụ, đúng tài xế, trạng thái và dấu thời gian máy chủ; HTTP 200 với nội dung trống/sai không được xem là thành công.

Lỗi mạng hoặc xung đột không tự gửi lại lệnh. Hộp đọc lại nhiệm vụ: nếu đã được nhận/từ chối đúng thì dùng kết quả hiện tại; nếu vẫn PENDING cho người dùng chủ động thử lại; nếu đã đổi phân công thì không có thao tác cũ. Nếu đọc cũng thất bại, khóa thao tác gửi, hiện **Kiểm tra trạng thái**; người dùng vẫn có thể chọn Để sau khi lần xử lý kết thúc. Lý do đang nhập được giữ khi yêu cầu bị từ chối.

## Kiểm chứng

- Backend build 0 lỗi/0 cảnh báo, Flutter analyze không có vấn đề.
- Toàn bộ Flutter **122/122** đạt, gồm **14 ca mới** về điều kiện phản hồi, dữ liệu thật thay nội dung thông báo, thông tin thời gian/xe, phản hồi sai ID/tài xế, lý do bắt buộc, không gửi lặp, trạng thái chưa rõ, phân công cũ, quy tắc chuyến và Để sau.
- **21 nhóm API/SQL/SignalR** trong frontend/tests/shipper-sync-api.cjs đạt. Kiểm tra thật thông tin kho/điểm giao, quyền, đổi/ngừng bưu cục, đồng thời nhận/từ chối, timestamp không bị ghi lại, tồn kho không xuất khi nhận nhiệm vụ, từ chối về hàng đợi và lý do trong nhật ký; giữ hồi quy nhận kiện, giao/COD, ảnh thất bại, hoàn kho và lộ trình admin.
- Database GUID thử và API thử đã được dọn; không đổi dữ liệu vận hành. Không chạy app, máy ảo hay điện thoại của người dùng. Chưa kiểm tra giao diện bằng thiết bị thật.

Không cần migration/seed. Dừng/chạy lại backend trong Visual Studio bằng profile **http**, sau đó dừng/chạy lại Flutter.
