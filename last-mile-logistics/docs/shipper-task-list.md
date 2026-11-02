# Chức năng 7 — Danh sách, tìm kiếm và phân nhóm nhiệm vụ

Cập nhật 30/10/2026. Dùng app_shipper và backend chính, dữ liệu phân công chung với admin.

## Cách sử dụng

Mở **Nhiệm vụ**, chọn một trong năm tab, nhập mã đơn/vận đơn, tên hoặc số điện thoại người nhận. Tìm kiếm sau khi dừng gõ khoảng 350 ms hoặc nhấn Enter; nút X xóa tìm kiếm. Bộ lọc được giữ khi đổi tab. Hiển thị số nhiệm vụ đã tải/tổng của tab và từ khóa hiện tại.

| Tab | Nội dung |
| --- | --- |
| Chờ nhận | Phân công hiện hành PENDING, đơn ASSIGNED |
| Nhận tại kho | Phân công đã nhận, chưa chuyển sang giao hoặc xử lý sự cố |
| Đi giao | IN_PROGRESS với đơn PICKED_UP/IN_DELIVERY; thứ tự chuyến và điểm theo admin |
| Giao lại / hoàn | Nhiệm vụ còn trách nhiệm xử lý giao thất bại, chờ giao lại hoặc đang chuyển hoàn, kể cả phân công đã đóng nhưng đang mang hàng hoàn |
| Hoàn tất | Phân công COMPLETED và kiện RETURNED thuộc phân công ATTEMPT_FAILED cuối cùng của đơn |

Không tính phân công bị từ chối/đổi tài xế/hủy vào Hoàn tất. Không tính mọi tài xế từng giao thất bại là người hoàn tất trả cùng một kiện. Quá hạn không tự ẩn, không tự chuyển hoàn.

Mỗi lần lấy tối đa 20 nhiệm vụ. Chọn **Tải thêm nhiệm vụ** để lấy trang sau; không cần tải toàn bộ lịch sử trước khi hiển thị. Thứ tự Đi giao được máy chủ xếp trước khi chia trang để không đổi lộ trình khi tải tiếp. Lỗi tải trang sau giữ những trang đã tải và cho thử lại, không tự tăng số trang khi thất bại.

## Đồng bộ và lỗi

- Đổi tab/tìm kiếm mới xóa kết quả thuộc bộ lọc trước. Phản hồi đọc cũ không ghi đè hoặc nối vào tab mới. Không dùng dữ liệu không tải được để báo danh sách rỗng.
- Khi cập nhật nền thất bại, dữ liệu cũ có thông báo chưa cập nhật và không có thao tác ghi cho đến khi tải thành công. Tải thêm thất bại chỉ báo ở cuối danh sách và giữ kết quả đã tải.
- Làm mới bằng nút trên đầu trang hoặc kéo danh sách khi cuộn được. Quay lại app sẽ tải lại; tín hiệu nhiệm vụ/thay đổi kiện tải lại trang đầu. Chu kỳ 30 giây chỉ chạy khi đang xem màn này, không đang thao tác/tìm kiếm/tải và chưa mở quá trang đầu, tránh định kỳ kéo người dùng từ cuối lịch sử về đầu.
- Danh sách rỗng, không có kết quả tìm kiếm và lỗi mạng có nội dung riêng. Ô tìm kiếm tối đa 100 ký tự. Ký tự % được tìm như văn bản, không phải ký tự đại diện SQL.
- Giữ nguyên luồng nhận/từ chối, nhận kiện và giao hàng của bước 6; không thêm Tạm nghỉ hoặc bước kho bắt buộc bàn giao trước nhận kiện trực tiếp.

## API

GET /api/v1/my/tasks thêm taskGroup: OFFERS, WAREHOUSE, DELIVERING, ISSUES, DONE. Nhóm không hợp lệ trả 400. DONE tự bao gồm phân công đã kết thúc; không cần caller ghi nhớ activeOnly=false. Khi không gửi taskGroup, bộ lọc assignmentStatus/activeOnly hiện có vẫn hoạt động.

Response trả shipperId, page, pageSize, totalItems, taskGroup và items luôn là mảng. Mỗi item có taskGroup. Máy chủ phân nhóm từ trạng thái đơn, phân công, trách nhiệm hoàn hiện hành và phân công mới hơn; không dựa vào lọc giao diện để kiểm soát quyền. Phạm vi tài xế/bưu cục vẫn kiểm tra trên máy chủ.

App kiểm tra metadata phân trang, ID, nhóm và chủ danh sách. Thiếu items, sai kiểu, sai trang/nhóm hoặc ID trùng trong một trang là lỗi dữ liệu, không được ngầm đổi thành items rỗng. Tải thêm gộp theo ID phân công để không vẽ hai thẻ cùng một nhiệm vụ nếu dữ liệu thay đổi giữa các lần đọc. Đây là các lần đọc dữ liệu hiện tại, không phải ảnh chụp lịch sử bất biến; làm mới để lấy lại từ đầu khi admin thay đổi phân công/lộ trình.

## Kiểm chứng và áp dụng

- Backend build 0 lỗi/0 cảnh báo; Flutter analyze không có vấn đề.
- Toàn bộ Flutter **133/133** đạt, gồm **11 ca mới** về hợp đồng danh sách, phân trang, quyền chủ dữ liệu, bộ lọc, đổi tab thất bại, phản hồi chậm, tải thêm/thử lại, cập nhật nền và kết quả rỗng.
- **24 nhóm API/SQL/SignalR** đạt trên LocalDB GUID tạm. Bổ sung tìm theo mã/tên/điện thoại và %, phân nhóm qua các bước nhận/giao/hoàn, kiện RETURNED hiện ở DONE dù phân công ATTEMPT_FAILED, chuyến hai điểm thật từ API điều phối giữ nguyên thứ tự giữa trang 1 và 2; trang ngoài phạm vi trả mảng rỗng. Giữ hồi quy phiên, phân công, từ chối, nhận kiện, giao/COD, ảnh thất bại và hoàn kho.
- Database/API thử đã dọn; không sửa dữ liệu vận hành, không chạy app hoặc thiết bị của người dùng. Chưa kiểm tra giao diện trên điện thoại thật.

Không cần migration hoặc nạp lại SQL. Chạy lại backend profile **http** trong Visual Studio và chạy lại Flutter.
