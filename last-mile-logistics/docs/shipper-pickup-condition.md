# Mục 13: tình trạng, GPS và ảnh khi nhận kiện

Đây là **STT 13 của bảng 40**, đồng thời hoàn thiện mục 2 của bảng 11 bổ sung. Phần **STT 14: Quét mã kiện** đã triển khai tiếp, xem [hướng dẫn](shipper-parcel-scanning.md); phần [STT 15 — Báo sự cố lấy hàng](shipper-pickup-issues.md) cũng đã bổ sung; mục kế tiếp hiện là **STT 16**. Phần báo sự cố lấy hàng có ảnh/phản hồi của kho được mô tả riêng tại STT 15.

## Cách dùng

1. Nhận nhiệm vụ, mở bản đồ đến kho, chọn **Đã nhận kiện hàng**.
2. Đối chiếu nhãn, xác nhận đủ kiện; chọn **Nguyên vẹn** hoặc **Có hư hại sẵn**. Đổi tình trạng sẽ xóa xác nhận đủ kiện để tài xế kiểm tra lại.
3. Có thể chụp/chọn một ảnh JPEG/PNG tối đa 5 MB. Với hư hại sẵn, bắt buộc nhập mô tả và ảnh trước khi gửi. Sai/thiếu kiện hoặc không thể nhận an toàn vẫn chọn **Báo sự cố**; không dùng xác nhận nhận kiện thay cho báo thiếu hàng.
4. Khi xác nhận, app thử lấy GPS hiện tại. Chỉ dùng vị trí có sai số không quá 100 m và mốc GPS cách hiện tại không quá 2 phút. Không lấy được, từ chối quyền hoặc GPS kém chính xác thì lưu null; không thay bằng tọa độ kho. Đây là GPS do thiết bị cung cấp, không phải cơ chế chống giả vị trí.
5. Máy chủ lưu giờ nhận UTC, kho, tài xế, mã nhãn, tình trạng, ghi chú, tọa độ/sai số và tham chiếu ảnh cùng giao dịch xuất kho. Thành công chuyển ngay sang Đi giao, giữ thứ tự admin. Không thêm bước kho duyệt bàn giao.

App xem lại tại **Chi tiết nhiệm vụ → Tiền và thời gian**, gồm nút **Xem ảnh lúc nhận kiện**. Web có nút **Biên nhận tài xế nhận kiện** trong chi tiết đơn và **Biên nhận nhận kiện** cạnh mã đơn trong danh sách tồn/nhập kho. Đây là ảnh lúc nhận kiện; ảnh giao hàng và ảnh trả kho là các dữ liệu riêng.

## Tính nhất quán và quyền xem

- Mỗi phân công có tối đa một biên nhận `dbo.ShipperPickupReceipt`. Gửi lặp khi đơn vẫn đang giao trả lại biên nhận ban đầu, không ghi đè giờ/ảnh/GPS và không xuất kho thêm. Hàng hoàn còn giữ vẫn tính vào tải xe khi nhận chuyến mới.
- Mất phản hồi: app đọc lại chi tiết và kiểm tra mốc nhận thực tế, không tự lặp lệnh ghi. Nếu máy chủ chưa xác định commit, giữ file để đối chiếu; chỉ xóa khi xác định chưa commit hoặc upload thừa của một replay đã commit.
- Ảnh ở `App_Data/PickupEvidence`, ngoài thư mục công khai. API trả metadata và ID, không trả đường dẫn file. Tải ảnh kiểm tra lại phiên, quyền hiện tại, đúng đơn/phân công và bưu cục. Tài xế chỉ xem biên nhận của mình; nhân viên kho xem theo phạm vi bưu cục; admin có quyền xem toàn hệ thống. Ảnh trả về `no-store`.
- Ảnh được kiểm tra bằng bộ giải mã JPEG/PNG đang dùng cho bằng chứng giao hàng: không tin tên file/MIME của người gửi, chặn file hỏng, quá lớn hoặc ảnh động. Nút xem không tải ảnh trước khi bấm; đóng/chuyển trang sẽ dọn ảnh đang xem. App đóng ảnh khi tải lại chi tiết hoặc mất quyền.
- Phiếu cũ không được tự điền Nguyên vẹn/GPS/ảnh. Khách API cũ vẫn gửi JSON nhận kiện như trước; biên nhận mới của khách cũ ghi tình trạng null. Nghiệp vụ bàn giao cũ chưa tạo biên nhận tình trạng sẽ hiển thị chưa có dữ liệu.

## SQL và áp dụng

Mở [20261030_shipper_pickup_receipts.sql](../database/migrations/20261030_shipper_pickup_receipts.sql) bằng SSMS, chọn đúng database `QLGiaoHangChangCuoi` mà API đang dùng rồi chạy. Đây là migration bổ sung bảng, không xóa hoặc sửa đơn/phiếu cũ; có thể chạy lại. Không chạy lại script khởi tạo hoặc nạp dữ liệu mẫu để áp dụng mục này. Cài mới cũng chạy migration sau phần cấu trúc nền.

Sau đó Stop và chạy lại backend trong Visual Studio với profile `http`, chạy lại Flutter và tải lại web. Trong lần triển khai này chỉ áp dụng migration vào database GUID kiểm thử, chưa thay database vận hành hoặc khởi động thiết bị.

Khi chưa có migration, đọc nhiệm vụ/biên nhận cũ vẫn hoạt động; API từ chối ghi tình trạng/ảnh/GPS mới bằng HTTP 503 trước khi xuất kho. App không chấp nhận thành công thiếu metadata cho yêu cầu mới.

## Kiểm chứng

- Build API; Flutter analyze và toàn bộ Flutter tests.
- `frontend/tests/shipper-sync-api.cjs`: HTTP/JWT/SQL/SignalR thật trên database GUID; chạy migration hai lần, kiểm tra schema cũ, nhận có hư hại/GPS/ảnh, nguyên vẹn không ảnh, khách cũ, quyền kho chỉ có `KHO_XEM`, sai bưu cục/tài xế, quyền bị thu hồi, file riêng, replay đồng thời, lịch sử sau giao và luồng hoàn cuối ca.
- `backend/LastMile/LastMile.PickupReceipt.Tests`: kết nối giả lập kiểm tra lỗi đọc kết quả, commit/rollback mất phản hồi, hủy, lỗi dọn file/dispose, scope đổi sau giải mã và lỗi thông báo sau commit. Không nối SQL Server. Bộ ảnh kiểm thử được tạo bởi `LastMile.Evidence.Tests` trước khi chạy harness này.
- `frontend/tests/pickup-receipts.test.cjs`: dữ liệu legacy/sai schema, xem ảnh theo ID, đóng trong lúc đang tải, MIME lỗi và dọn URL ảnh.
- `app_shipper/test/pickup_condition_test.dart`: contract biên nhận, multipart/precision GPS, metadata bị bỏ qua, ảnh riêng, hư hại thiếu bằng chứng, xác nhận một lần, GPS không có quyền và đóng ảnh khi mất quyền.

Kết quả lần chạy cuối được ghi ở [tiến độ](shipper-progress.md). Không coi các bài kiểm tra này là đã thử camera/GPS trên điện thoại thật.
