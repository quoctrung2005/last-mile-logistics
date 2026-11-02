# App shipper — dùng chung backend với web quản lý

Ứng dụng Flutter nằm trong `lib`. Backend dùng chung là **`../backend/LastMile/LastMile.Api`**, không phải bản backend nhập kèm trong thư mục này.

## Khởi động

Từ thư mục `last-mile-logistics`:

```powershell
.\tools\start-shared-api.ps1
```

Web quản lý dùng `frontend/dev-server.cjs` ở cổng 5500. Cả web và app gọi API cổng 5038, cùng database cấu hình tại backend chính. Không cần nạp lại SQL để đồng bộ.

Từ thư mục `app_shipper`, sau khi cài Flutter và Android SDK:

```powershell
flutter pub get
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:5038
```

Lệnh trên dành cho Android Emulator; chọn thiết bị Android khi Flutter hỏi. Điện thoại thật cùng Wi-Fi dùng IPv4 máy chạy API ở màn đăng nhập và chạy API bằng `tools/start-shared-api.ps1 -BindAddress 0.0.0.0`. Địa chỉ máy chủ được lưu khi mở lại app. Dùng tài khoản có vai trò SHIPPER.

`android/local.properties` đã cấu hình Flutter tại `D:\flutter` và Android SDK tại `D:\AndroidSDK`. Chưa có thư mục nền tảng Windows để dùng `flutter run -d windows`.

Các thư mục `backend`, `frontend`, `database` trong `app_shipper` giữ làm tài liệu tham khảo của bản nhập. Không chạy thêm backend hoặc dùng script nạp dữ liệu của các bản này lên database chung.

## Luồng hiện có

Nhận nhiệm vụ → đến kho → xác nhận đã nhận kiện (hệ thống xuất kho) → tự chuyển sang đi giao → giao thành công/COD hoặc thất bại/giao lại/chuyển hoàn. Thứ tự giao trong chuyến theo admin. Thông báo nhiệm vụ dùng SignalR; danh sách có cơ chế tải lại.

Ảnh bằng chứng có tại lúc nhận kiện, giao thành công và giao thất bại; yêu cầu hoàn riêng chưa có ảnh. Giao thành công phải nhập người nhận thực tế, đối chiếu COD thực thu và nhận biên nhận máy chủ; mất phản hồi dùng kiểm tra lại, không tự gửi lặp. Xem [bước 11](../docs/shipper-delivery-success.md). Đăng ký tài xế đã gửi hồ sơ/ảnh lên admin xét duyệt thủ công; chưa có xác minh eKYC tự động. Bản đồ và chỉ đường hiển thị trong app, có GPS khi đang mở màn lộ trình; chưa có giọng nói hoặc giao thông trực tiếp.

Đổi mật khẩu: Trang chủ → biểu tượng tài khoản → **Đổi mật khẩu**. Khôi phục: màn đăng nhập → **Quên mật khẩu?** → email → mã khôi phục trong email → mật khẩu mới. Đổi/đặt lại thành công yêu cầu đăng nhập lại. Gửi mã thật cần cấu hình email phía backend; app không tự cấp mã giả. Xem [shipper-password.md](../docs/shipper-password.md).

Hồ sơ tài xế: Trang chủ → biểu tượng tài khoản → **Hồ sơ tài xế**. Xem thông tin cá nhân, bưu cục, giấy phép, phương tiện hiện được phân công và khu vực phụ trách. Dữ liệu do admin quản lý; kéo xuống hoặc bấm làm mới để tải thay đổi. Xem [shipper-profile.md](../docs/shipper-profile.md).

Đăng ký: trang chào mừng → **Đăng ký tài xế**. Gửi thông tin, ảnh CCCD hai mặt, giấy phép, chân dung và bưu cục/khu vực muốn hoạt động. Admin vào **Nhân viên & phương tiện → Hồ sơ đăng ký tài xế** để xem ảnh, yêu cầu bổ sung, từ chối hoặc duyệt tạo tài khoản. Người đăng ký xem kết quả bằng **Theo dõi hồ sơ đăng ký** trên thiết bị đã gửi. Xem [shipper-registration.md](../docs/shipper-registration.md).

Trạng thái làm việc: Trang chủ → **Sẵn sàng** hoặc **Ngoại tuyến** (không có Tạm nghỉ). Đang giao do hệ thống cập nhật. Máy chủ chặn ngoại tuyến khi còn nhiệm vụ/chuyến/hàng hoàn và hiển thị lý do; kiểm tra bằng lái, xe được phân công trước khi bật sẵn sàng. Xem [shipper-availability.md](../docs/shipper-availability.md).

Phản hồi phân công: **Nhiệm vụ → Chờ nhận → Xem và phản hồi nhiệm vụ**, hoặc hộp thông báo trên Trang chủ. App tải thông tin hiện tại trước khi cho nhận/từ chối; nhận thành công mở bản đồ đến kho. Từ chối đơn lẻ cần lý do, đưa đơn về hàng đợi điều phối. Đơn thuộc chuyến không tách từ chối riêng. Xem [shipper-task-offers.md](../docs/shipper-task-offers.md) và [tiến độ từng bước](../docs/shipper-progress.md).

Danh sách nhiệm vụ: phân nhóm trên máy chủ, tìm theo mã/vận đơn/tên/số điện thoại, hiển thị tổng và **Tải thêm nhiệm vụ**. Hoàn tất gồm cả kiện đã nhập hoàn; Đi giao giữ thứ tự tuyến admin trước khi chia trang. Xem [shipper-task-list.md](../docs/shipper-task-list.md).

Chuyến giao: **Nhiệm vụ → biểu tượng xe tải “Chuyến giao của tôi”**, hoặc **Xem chuyến / thứ tự giao** trong chi tiết nhiệm vụ. Xem chuyến đang làm/lịch sử, tiến độ và các điểm theo thứ tự admin; mở bản đồ đúng chuyến. Giao thành công thống kê riêng, hàng chờ trả cuối ca vẫn hiển thị dù chuyến giao đã kết thúc. Mục 16 không cần SQL mới. Xem [hướng dẫn chuyến giao](../docs/shipper-trip-overview.md).

Chi tiết nhiệm vụ: bấm **Xem chi tiết nhiệm vụ** trên thẻ ở bất kỳ tab nào. Xem hàng trong kiện, COD/phí đơn, mốc nhận kiện thực tế, từng lần giao và yêu cầu giao lại/hoàn, lịch sử trạng thái; ảnh bằng chứng mở trong app bằng quyền xem riêng. Xem [shipper-task-detail.md](../docs/shipper-task-detail.md).

Nhận kiện tại kho: **Đã nhận kiện hàng** → đối chiếu mã trên nhãn, xác nhận đủ kiện/bao bì và ghi chú nếu có. Sai/thiếu/hỏng chọn **Báo sự cố** để kho xử lý. Chỉ chuyển Đi giao sau xác nhận nhận thực tế; lỗi mạng kiểm tra lại phiếu thay vì tự gửi lặp. Xem [shipper-pickup-receipt.md](../docs/shipper-pickup-receipt.md).

Lộ trình: mở từ một đơn vẫn xem các điểm lấy/giao còn lại cùng chuyến, giữ số điểm admin. Chọn thẻ/điểm để xem tuyến, giữ lựa chọn khi làm mới và chuyển sang điểm còn lại khi nhiệm vụ kết thúc. GPS dừng khi rời sang màn cập nhật kết quả hoặc dữ liệu nhiệm vụ không tải được. Xem [shipper-itinerary.md](../docs/shipper-itinerary.md).

Mục 17 — **Bắt đầu chỉ đường**: bảng hướng dẫn riêng phía trên bản đồ, hướng rẽ ước lượng theo hình tuyến, khoảng cách tới hướng rẽ và còn lại; cảnh báo GPS cũ/lệch tuyến, thử lại từ vị trí hiện tại khi tải đường lỗi. Dừng GPS khi mở phiếu hoặc rời app; giữ nguyên thứ tự admin. Chưa có tên đường/giọng nói/giao thông trực tiếp. Chạy lại app, không cần SQL mới. Xem [chỉ đường trong app](../docs/shipper-navigation.md).

Khôi phục GPS: màn Lộ trình có **Lấy lại GPS**, **Bật vị trí** và **Cấp quyền vị trí** theo nguyên nhân. Có vị trí trở lại sẽ tải lại tuyến đang chọn; GPS cũ hoặc không chính xác không được coi là vị trí mới. Stop/chạy lại app để nạp bản sửa, xem [hướng dẫn GPS](../docs/shipper-gps-recovery.md).

Sửa lỗi 31/10 — GPS `10.7769, 106.7009`: mở rộng dữ liệu đường, sửa lọc lịch đóng/loại xe và xử lý nhánh cụt. **Shift+F5 rồi chạy lại backend profile http**, và chạy lại app; không cần SQL. Khi GPS chưa nằm trên đường, app báo khoảng cách tới đầu tuyến. Xem [kết quả kiểm tra và giới hạn hiện tại](../docs/routing-city-coverage-fix.md).

Xem báo cáo kiểm tra và cách chạy kiểm thử tại [shipper-web-sync.md](../docs/shipper-web-sync.md).

Bảng bổ sung mục 1 — hạn đến kho: điều phối đặt riêng khi phân công hoặc trên danh sách phân công, có thể để trống/sửa/bỏ trước khi nhận kiện. App phân biệt nhận nhiệm vụ và nhận kiện thực tế, chỉ báo trễ khi có hạn. Xem [mốc thời gian và migration cần áp dụng](../docs/shipper-task-timing.md), [tiến độ bảng bổ sung](../docs/shipper-additional-features.md).

Mục 13 bảng 40 — nhận kiện: chọn tình trạng, chụp/chọn ảnh, ghi GPS nếu lấy được. Hư hại sẵn cần ảnh và mô tả; app/admin/kho xem lại biên nhận theo quyền. Cần migration bổ sung `20261030_shipper_pickup_receipts.sql`, sau đó chạy lại backend/app. Xem [cách áp dụng và kiểm chứng](../docs/shipper-pickup-condition.md).

Mục 14 bảng 40 — **Quét mã kiện** trong phiếu nhận kiện: camera kiểm tra mã đơn/vận đơn, chặn sai/nhiều mã, có nhập tay. Quét chưa xuất kho; vẫn kiểm tra nhãn/đủ kiện và xác nhận nhận. Cần Stop và chạy lại app hoàn toàn để nạp plugin camera mới. Xem [hướng dẫn và giới hạn kiểm chứng](../docs/shipper-parcel-scanning.md).

Mục 15 bảng 40 — **Sự cố nhận kiện / Phản hồi kho**: tài xế gửi loại sự cố, mô tả/ảnh; kho yêu cầu bổ sung hoặc ghi hướng xử lý; hồ sơ mở chặn nhận/xuất đúng đơn. Mất phản hồi dùng kiểm tra biên nhận, không tự lặp lệnh ghi. Cần migration `20261030_shipper_pickup_issues.sql` và chạy lại backend/app. Xem [hướng dẫn áp dụng](../docs/shipper-pickup-issues.md).
