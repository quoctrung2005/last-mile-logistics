# Sửa lỗi chưa lấy được GPS trên màn Lộ trình

Cập nhật 31/10/2026, theo ảnh báo “Hãy bật định vị GPS để xem đường đến kho nhận hàng”. Đây là luồng lấy vị trí trên app, riêng với lỗi vùng mạng đường đã sửa trước đó tại [báo cáo tuyến trung tâm](routing-city-coverage-fix.md).

## Các thay đổi

- Bỏ yêu cầu GPS độc lập lúc khởi tạo bản đồ vốn chạy đồng thời với yêu cầu lấy GPS để tìm tuyến. Các lượt đọc bản đồ dùng chung một yêu cầu đang chờ; luồng Trang chủ/phiếu và bản đồ chia sẻ việc xin quyền để không mở hai hộp thoại hệ điều hành.
- Dùng dịch vụ GPS riêng cho chỉ đường: chỉ nhận tọa độ hữu hạn/trong giới hạn, độ chính xác tối đa 50 m, tuổi tối đa 30 giây và không quá 5 giây trong tương lai. Vị trí cache cũ/không chính xác không chặn việc lấy vị trí mới. Các nghiệp vụ dùng `DeviceService.getCurrentPosition` vẫn giữ chính sách lấy vị trí hiện có, chỉ chia sẻ bước xin quyền.
- Trên Android, thử vị trí độ chính xác cao; nếu provider đầu không trả được fix hợp lệ thì thử LocationManager một lần, có thời hạn. Không dùng lại cache cũ vô điều kiện hoặc đổi thời gian cache để giả thành vị trí mới.
- Phân biệt rõ tắt dịch vụ vị trí, chưa cấp quyền, quyền bị chặn, vị trí cũ/không chính xác và chưa nhận được fix. Hiển thị nguyên nhân thật, không thay tất cả bằng một thông báo “bật GPS”.
- Thêm **Lấy lại GPS**, **Bật vị trí** hoặc **Cấp quyền vị trí** theo nguyên nhân. Bấm lấy vị trí thành công sẽ tải lại tuyến cho điểm đang chọn, kể cả khi mã đơn/thứ tự chưa thay đổi; xóa lỗi GPS cũ sau khi khôi phục.
- Quay lại app sau khi mở cài đặt sẽ kiểm tra lại quyền/GPS và tải lại tuyến. Phản hồi GPS sau khi rời màn hoặc sau khi đổi điểm không vẽ lại tuyến cũ.
- Có trạng thái **Đang lấy vị trí…**, khóa bấm lặp trong lúc chờ. Giữ kiểm tra GPS mới/đúng thứ tự thời gian trong lúc dẫn đường và cảnh báo khi stream quá 30 giây không cập nhật.
- Giữ giao diện thẻ hiện tại; thêm hành động **Xem lại tuyến**, nhận diện điểm đang chọn cho khả năng tiếp cận, dừng GPS trước khi chuyển sang xử lý giao. Tiêu đề/số điểm và nhãn thẻ tự xuống dòng trên màn hẹp/chữ lớn.

## Cách áp dụng

1. Stop rồi chạy lại **Flutter app** để nạp luồng GPS mới.
2. Mở Lộ trình → **Lấy lại GPS**. Khi có hộp thoại Android, cho phép vị trí khi dùng ứng dụng và bật vị trí chính xác.
3. Nếu app báo thiết bị tắt vị trí, bấm **Bật vị trí**, bật dịch vụ vị trí rồi quay lại app. Nếu quyền bị chặn, bấm **Cấp quyền vị trí**, cấp quyền trong cài đặt ứng dụng rồi quay lại.
4. Nếu máy ảo chưa phát vị trí, gửi lại tọa độ trong phần Location của máy ảo rồi lấy lại GPS. Có thể giữ điểm thử `10.7769, 106.7009` sau bản sửa dữ liệu đường trước đó. GPS đứng yên không đồng nghĩa vị trí sẽ tự cập nhật liên tục; app không tự tạo tọa độ hay thời gian quan sát.

Không có SQL/migration hoặc thay đổi backend cho bản sửa GPS này. Không cần nạp lại dữ liệu mẫu.

## Kiểm chứng

- **65/65** kiểm thử dịch vụ GPS, khôi phục quyền/cài đặt, bản đồ, dẫn đường và chuyến giao. Thêm **14 ca**: provider giả lập, quyền bị chặn, một hộp thoại khi nhiều luồng xin quyền, cache cũ, provider timeout/fallback, bật lại dịch vụ, trở về từ cài đặt, tự tính lại tuyến sau retry và rời màn khi GPS còn chờ.
- Analyzer không có vấn đề; APK Android debug x86_64 build thành công.
- Kiểm thử toàn app hiện **280 đạt / 22 chưa đạt**, ở Trang chủ, xác nhận COD, nhận/quét kiện và danh sách nhiệm vụ. Không kết luận toàn ứng dụng đã hết lỗi; nhật ký đầy đủ tại `frontend/tests/.artifacts/gps-recovery/flutter-tests.log`.
- Không điều khiển hoặc cài/chạy app trên máy ảo/điện thoại của người dùng; quyền/GPS trong kiểm thử dùng provider và vị trí giả lập. Vẫn cần người dùng cho phép vị trí/bật dịch vụ hoặc gửi fix từ máy ảo.

Kết quả và nhật ký: `frontend/tests/.artifacts/gps-recovery/verification.json`, `map-tests.log`, `analyze.log`, `android-build.log`.
