# Mục 15 — Báo sự cố lấy hàng và phản hồi kho

Đã triển khai **STT 15 của bảng 40**. Mục tiếp theo khi người dùng yêu cầu “tiếp” là **STT 16 — Chuyến giao, thứ tự giao**, tiếp tục hoàn thiện tổng quan chuyến trên nền lộ trình hiện có.

## Tài xế

- Tại màn lộ trình đến kho, chọn **Sự cố nhận kiện / Phản hồi kho**; hoặc trong phiếu kiểm tra nhận kiện chọn **Báo sự cố**. Chi tiết nhiệm vụ cũng có nút xem hồ sơ/phản hồi, kể cả khi phân công đã kết thúc và vẫn thuộc phạm vi được phép xem.
- Chọn **Thiếu/chưa tìm thấy kiện**, **Sai nhãn/mã kiện**, **Kiện hư hại**, **Không thể nhận tại kho** hoặc **Sự cố khác**; nhập mô tả 3–500 ký tự.
- Báo hàng hỏng/sai nhãn lần đầu bắt buộc có ảnh. Những trường hợp không thể chụp kiện như chưa tìm thấy kiện có thể gửi mô tả trước. Chụp/chọn một ảnh JPEG/PNG tối đa 5 MB mỗi lần gửi; bộ giải mã kiểm tra nội dung ảnh trên máy chủ.
- Sau khi gửi, xem giờ máy chủ ghi nhận, lịch sử ghi chú/ảnh và hướng dẫn của kho. Trạng thái **Cần bổ sung minh chứng** mở form bổ sung ghi chú/ảnh; bổ sung được lưu thành lượt mới, không thay ảnh/lời khai ban đầu.
- Có thông báo SignalR khi hồ sơ thay đổi, tải lại định kỳ khi đang mở hoặc nút **Kiểm tra / làm mới**. Không khẳng định gửi thành công trước khi có biên nhận máy chủ.

## Kho / điều phối

Mở **Kho → Xuất kho → Sự cố nhận kiện / Xử lý**, hoặc **Chi tiết đơn → Sự cố nhận kiện / Xử lý**. Hồ sơ gồm tài xế, phân công, kho, loại sự cố và toàn bộ lượt gửi/phản hồi; ảnh chỉ tải khi bấm xem.

Người có quyền `KHO_XUAT` hoặc `DIEUPHOI_PHANCONG` trong phạm vi bưu cục có thể:

1. **Yêu cầu tài xế bổ sung**: ghi cụ thể thông tin/ảnh cần thêm.
2. **Đã kiểm tra và đóng hồ sơ**: ghi kết quả kiểm tra và hướng dẫn thực tế, chẳng hạn đã tìm đủ kiện hoặc đã thay nhãn; tài xế vẫn kiểm tra lại trước khi nhận.

Quyền xem dùng quyền xem kho/đơn/giám sát điều phối. Người chỉ có quyền xem không được gửi hướng xử lý. Admin có phạm vi toàn hệ thống; nhân viên theo bưu cục. Phản hồi kiểm tra phiên bản hồ sơ: nếu người khác đã cập nhật thì trả xung đột và tải lại, giữ nội dung đang nhập trên web.

## Trạng thái và ảnh hưởng nghiệp vụ

`OPEN — Chờ xử lý` → `NEED_MORE — Cần bổ sung` → tài xế bổ sung → `OPEN` → kho/điều phối kiểm tra → `RESOLVED — Đã xử lý`. Kho có thể đóng trực tiếp hồ sơ đang mở sau khi đã kiểm tra, không bắt buộc yêu cầu bổ sung.

- Mỗi đơn có tối đa một hồ sơ đang mở, kể cả khi đổi tài xế. Hồ sơ giữ theo phân công đã báo; tài xế thay thế thấy đơn bị chặn, không thấy lịch sử/ảnh riêng của tài xế trước. Phản hồi kho thông báo đến nhiệm vụ hiện tại của đơn.
- Hồ sơ mở chặn nhận kiện trực tiếp, xuất kho qua quản lý và xác nhận bàn giao theo luồng cũ. Giao diện phiếu nhận vô hiệu hóa xác nhận nhận kiện; API kiểm tra lại trong giao dịch, không chỉ khóa nút.
- Báo sự cố không xuất kho; đóng hồ sơ cũng không xuất kho. Khoản thu hộ, kết quả giao, hàng hoàn và trách nhiệm bồi thường không được thay đổi bởi thao tác hồ sơ này. Kho/điều phối dùng các chức năng quản lý hiện có nếu cần thu hồi/đổi phân công hoặc xử lý đơn.
- Ảnh, thời gian và ghi chú của từng lượt được giữ nguyên. Người xử lý không tự đánh dấu tài xế đã nhận kiện hoặc quy trách nhiệm mất/hỏng hàng. Hồ sơ này xử lý sự cố **trước khi nhận tại kho**, không thay hồ sơ mất/hư trong quá trình vận chuyển thuộc các mục bổ sung khác.
- Báo cáo cũ chỉ ghi `SHIPPER_PICKUP_ISSUE` trong nhật ký vẫn tra được ở nhật ký quản trị. Không tự chuyển lịch sử cũ thành hồ sơ đang mở vì chưa xác định được kết quả xử lý cũ.

## Chống trùng và quyền truy cập

Mỗi lần báo/bổ sung/phản hồi có UUID riêng, lưu cùng lượt xử lý và mã phiên bản. Gửi lại cùng yêu cầu trả biên nhận cũ, không ghi đè nội dung hoặc thêm lượt/ảnh. Khi mất phản hồi, app/web đọc lại lịch sử theo mã yêu cầu; nếu chưa xác định được kết quả chỉ cho phép người dùng kiểm tra hoặc gửi lại **đúng yêu cầu đó**, không tự gửi lặp. Ảnh của giao dịch chưa xác định commit được giữ để đối chiếu; file của giao dịch chắc chắn chưa commit hoặc upload trùng sau commit được dọn.

Ảnh ở `App_Data/PickupIssueEvidence` ngoài thư mục công khai. Metadata không chứa đường dẫn file. API ảnh kiểm tra tài khoản/quyền hiện tại, đơn, hồ sơ, lượt gửi và phạm vi bưu cục; tài xế chỉ xem phân công của mình, cần hồ sơ tài xế và bưu cục hoạt động. Ảnh trả `no-store`. Đổi trang/đóng hồ sơ hoặc mất quyền khi tải lại sẽ dọn ảnh; ảnh tải muộn từ nội dung cũ bị bỏ qua.

## SQL và áp dụng

Mở [20261030_shipper_pickup_issues.sql](../database/migrations/20261030_shipper_pickup_issues.sql) trong SSMS, chọn đúng database `QLGiaoHangChangCuoi` của API rồi chạy toàn bộ. Migration bổ sung `ShipperPickupIssue`, `ShipperPickupIssueEvent`, khóa ngoại và chỉ mục kiểm soát một hồ sơ mở/đơn, UUID yêu cầu và thứ tự lượt xử lý. Có kiểm tra tồn tại để chạy lại; không xóa dữ liệu hoặc nạp lại đơn mẫu.

Sau đó **Stop và chạy lại backend trong Visual Studio với profile `http`**, tải lại web và chạy lại app Flutter. Khi thiếu migration, đọc danh sách trả `available: false` và `items: []`; ghi báo cáo trả HTTP 503, không giả báo thành công. Database có hồ sơ cũ theo mục 13 không tự có hai bảng mới này.

Trong lần triển khai này chỉ áp dụng migration vào database GUID kiểm thử. Chưa chạy SQL vào dữ liệu vận hành, chưa mở/cài app trên thiết bị.

## Kiểm chứng

- Flutter analyze và toàn bộ Flutter tests, gồm hồi quy nhận kiện/quét mã/lộ trình/COD. Bộ mới `pickup_issue_test.dart` kiểm tra contract, ảnh, phản hồi, bổ sung theo phiên bản, chưa có SQL, khóa nhận khi còn sự cố, phục hồi bằng đọc lại biên nhận và gửi lại có chủ đích với cùng UUID.
- `frontend/tests/pickup-issues.test.cjs`: quyền xem, form phản hồi, khóa gửi trùng, giữ ghi chú khi xung đột, phục hồi mất phản hồi, URL ảnh riêng và ảnh trả về muộn sau tải lại/đóng hộp thoại.
- `frontend/tests/shipper-sync-api.cjs`: API/JWT/SQL/SignalR thật, database GUID riêng; kiểm tra `items: []`, thiếu migration, chặn xuất kho, ảnh, phản hồi, UUID lặp/đồng thời, đổi tài xế mà không bỏ chặn, phạm vi minh chứng, phiên bản cũ và bảo toàn dữ liệu khi chạy lại SQL. Hồi quy giao thành công/COD/giao thất bại/hoàn cuối ca và thứ tự tuyến vẫn được chạy.
- `LastMile.PickupIssue.Tests`: kết nối giả lập, lỗi giải mã/đọc kết quả/commit/rollback/hủy, mất phản hồi, dọn file/dispose, thu hồi quyền sau giải mã, replay trước khi đọc ảnh và lỗi thông báo sau commit. Bộ ảnh thử dùng `LastMile.Evidence.Tests` để tạo trước.

Kết quả lần chạy cuối được ghi trong [tiến độ](shipper-progress.md). Kiểm thử giao diện dùng widget/DOM và lớp dịch vụ có kiểm soát, không thay thế thử camera/lấy hàng thực tế.

Kết quả cuối: **239/239 Flutter**, analyze không lỗi; **43 nhóm tích hợp**, **223/223 web**, **332 kiểm tra lỗi giao dịch/ảnh**; build API 0 cảnh báo/lỗi, APK debug Android x86_64 đạt. Các cảnh báo Java native access hiện có không làm build APK thất bại.
