# Mục 16 — Chuyến giao, thứ tự giao

Hoàn thiện mục 16 của [bảng chính 40 chức năng](shipper-functions-40.md), trên nền lộ trình đang có. Chức năng đọc dữ liệu chuyến do admin lập; không lập lại thứ tự hoặc thay đổi trạng thái chuyến khi mở màn.

## Cách sử dụng

1. Vào **Nhiệm vụ → biểu tượng xe tải “Chuyến giao của tôi”** trên thanh tiêu đề.
2. Chọn **Đang thực hiện** hoặc **Lịch sử**; tìm theo mã chuyến, kho hoặc biển số. Danh sách có tổng số chuyến và phân trang 10 chuyến.
3. Mở chuyến để xem kho, xe, trạng thái, thời gian dự kiến/thực tế, tổng điểm và tiến độ. Quãng đường/thời gian kế hoạch lấy từ admin; chưa có dữ liệu thì hiển thị rõ, không tự tạo số.
4. Danh sách điểm giữ nguyên `ThuTuDuKien`, kể cả khi số thứ tự có khoảng trống. Mỗi điểm có trạng thái, giờ đến dự kiến nếu có và kết quả lần giao gần nhất. Bấm **Xem nhiệm vụ** để xem hồ sơ; **Xem tuyến đến điểm này** mở bản đồ trong đúng chuyến.
5. Nút **Xem lộ trình chuyến** mở điểm khả dụng đầu tiên theo thứ tự admin. Chọn xem điểm khác không tự sắp lại chuyến. Nhận kiện thành công vẫn đưa về tab **Đi giao** như luồng đã chốt.

Cũng có thể mở **Xem chuyến / thứ tự giao** từ chi tiết nhiệm vụ đã gắn chuyến. Nhiệm vụ đơn lẻ vẫn nằm trong danh sách nhiệm vụ; màn chuyến hiển thị số nhiệm vụ chưa gắn chuyến để tránh hiểu nhầm là không còn việc.

## Quy tắc tiến độ và đồng bộ

| Nội dung | Cách hiển thị/xử lý |
| --- | --- |
| Tiến độ xử lý điểm | Đã giao, kho đã nhận hoàn, chờ trả kho sau khi bắt đầu hoàn hoặc điểm đã thu hồi được tính đã xử lý phần chuyến. Đây không phải số giao thành công. |
| Giao thành công | Chỉ tính khi phân công hoàn thành và có lần giao SUCCESS tương ứng. |
| Hàng chờ trả cuối ca | Vẫn hiện nghĩa vụ trả kho và số kiện đang giữ, kể cả chuyến giao đã kết thúc. Chưa tính là kho đã nhận hoàn; không thêm điều kiện chặn chuyến mới. |
| Chờ nhận nhiệm vụ / nhận kiện / đi giao | Thống kê riêng theo trạng thái hiện hành của phân công và đơn hàng. |
| Điểm cần xử lý | Giao thất bại, giao lại, chưa có nhiệm vụ hoặc sự cố nhận kiện còn mở. Hồ sơ sự cố mở không được mở tuyến lấy kiện. |
| Thu hồi / đổi tài xế | Giữ dấu vết điểm và số thứ tự gốc; ẩn nhiệm vụ, thông tin liên hệ và lần giao khi tài xế không còn quyền. Không mở tuyến và không tính giao thành công. |
| Lịch sử chuyến | Chuyến COMPLETED/CANCELLED vẫn xem được theo quyền, không có nút mở tuyến. |
| Thay đổi từ admin | Làm mới qua SignalR, khi trở lại màn/ứng dụng, kéo xuống và chu kỳ 30 giây khi màn đang mở. Phản hồi cũ không ghi đè bộ lọc mới. |
| Mất quyền / lỗi tải | Xóa chi tiết đã tải và khóa thao tác trên dữ liệu cũ. Không báo danh sách rỗng như tải thành công. |

Không thêm bước kho duyệt bàn giao. Không thay đổi cách tối ưu đường, chính sách thứ tự xác nhận giao, COD, tiền công hoặc quy trình kết thúc chuyến trong mục này.

## API và phạm vi dữ liệu

- `GET /api/v1/my/trips?group=ACTIVE|HISTORY&keyword=&page=1&pageSize=10`: danh sách, tổng số, số nhiệm vụ chưa gắn chuyến và hàng chờ trả kho.
- `GET /api/v1/my/trips/{id}`: toàn bộ điểm của chuyến theo thứ tự lưu, không phân trang danh sách điểm.

Hai API chỉ đọc, không ghi nhật ký nghiệp vụ hoặc thực hiện thao tác chuyến. Kiểm tra phiên/tài khoản đang hoạt động, vai trò SHIPPER, quyền `NHIEMVU_XEM`, hồ sơ hoạt động, bưu cục hiện tại và tài xế của chuyến. Truyền mã tài xế qua query không thay đổi phạm vi. Admin dùng API quản lý chuyến hiện có.

Các mảng luôn là `[]` khi rỗng; app kiểm tra chủ sở hữu, mã chuyến, thứ tự, số lượng và phiên đăng nhập trước khi hiển thị. Bản đồ mở từ chuyến giữ phạm vi chuyến; nhiệm vụ đã đổi chuyến yêu cầu mở lại từ danh sách.

## Áp dụng và kiểm chứng

**Không có SQL/migration mới cho mục 16.** Dùng database hiện tại đã có các phần trước; Stop rồi chạy lại backend chính trong Visual Studio với profile **http**, và chạy lại app để nhận màn/API mới. Không chạy backend bản sao trong `app_shipper`.

Kết quả kiểm tra ngày 30/10/2026:

- **254/254 Flutter**; analyze không có vấn đề. Bao gồm hợp đồng dữ liệu, quyền/đổi phiên, phản hồi đến muộn, mở đúng chuyến/điểm, hàng hoàn và giao diện hẹp/chữ lớn.
- **48 nhóm API/SQL/SignalR**: chuyến thật hai điểm từ VRP/admin, phân trang, chỉ đọc, thu hồi/ẩn liên hệ, thu hồi quyền/bưu cục, giao thành công cập nhật đúng điểm và chuyến kết thúc vẫn còn hàng chờ trả kho.
- Backend build thành công, 0 cảnh báo/lỗi; APK Android debug x86_64 biên dịch đạt.
- API dùng database GUID riêng, tự xóa sau kiểm tra. Không cập nhật database vận hành, không cài/chạy app trên máy ảo hoặc điện thoại trong lần sửa. Chưa kiểm thử thao tác thực tế trên thiết bị.

Mục 17 đã được bổ sung trong lần triển khai kế tiếp: [Bản đồ, chỉ đường trong app](shipper-navigation.md). Tiến độ hiện tại theo [bảng tiến độ](shipper-progress.md).
