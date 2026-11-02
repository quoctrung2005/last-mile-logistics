# Chức năng 4 — Đăng ký tài xế và xét duyệt

Ngày cập nhật: 30/10/2026. Luồng dùng backend chính và LocalDB chung với web quản lý.

## App

Trang chào mừng có Đăng ký tài xế và Theo dõi hồ sơ đăng ký. Đăng ký gồm bốn bước:

1. Họ tên, điện thoại, email, CCCD 12 số, ngày sinh tùy chọn, tên đăng nhập, mật khẩu và xác nhận.
2. Chụp/chọn ảnh CCCD mặt trước, mặt sau, giấy phép lái xe, chân dung; nhập số giấy phép và hạn giấy phép. Ảnh do admin kiểm tra thủ công, không có kết quả nhận diện eKYC/khuôn mặt tự động. Các entry point A2/A3/A4 cũ đã chuyển sang luồng thật; A5 chuyển sang theo dõi trạng thái.
3. Loại xe/biển số đề xuất, bưu cục và khu vực chính. Danh sách bưu cục/khu vực lấy từ dữ liệu hoạt động thật, khu vực phải thuộc phạm vi bưu cục.
4. Kiểm tra và xác nhận gửi hồ sơ. Chỉ hiện máy chủ đã nhận sau phản hồi thành công hoặc truy vấn lại xác nhận hồ sơ đã tồn tại.

Mỗi ảnh tối đa 5 MB, JPEG/PNG; backend kiểm tra dữ liệu ảnh thật, kích thước/pixel và định dạng tĩnh bằng bộ kiểm tra bằng chứng hiện có. Bốn ảnh được lưu trong database riêng của hồ sơ; không có URL công khai.

Trước khi gửi, app giữ ID ngẫu nhiên và secret theo dõi trong FlutterSecureStorage, gắn với đúng máy chủ. Không lưu mật khẩu/ảnh vào SharedPreferences. Secret không nằm trong URL hay màn hình. Nếu timeout, app kiểm tra lại bằng ID/secret trước khi kết luận kết quả; gửi lại cùng ID không tạo hồ sơ trùng. Đăng xuất thông thường không xóa mã theo dõi. Mất dữ liệu ứng dụng/chuyển thiết bị cần liên hệ admin; không có tra cứu công khai bằng số điện thoại.

## Trạng thái và admin

Web: Nhân viên & phương tiện → Hồ sơ đăng ký tài xế. Chỉ ADMIN có quyền xem tài khoản được đọc hồ sơ/ảnh; quyết định cần thêm quyền quản lý tài khoản. Trang có tìm kiếm, lọc, phân trang, xem ảnh và lịch sử.

| Trạng thái | Xử lý |
| --- | --- |
| PENDING | Admin kiểm tra thông tin/ảnh. Chưa có tài khoản hoạt động để nhận nhiệm vụ. |
| NEEDS_INFO | Bắt buộc có lý do hiển thị trên app. Người đăng ký mở bổ sung, kiểm tra lại thông tin, nhập mật khẩu và chọn đủ bốn ảnh; gửi lại cùng ID/secret với phiên bản hiện hành để quay về PENDING. |
| APPROVED | Tạo tài khoản vai trò SHIPPER, hồ sơ nhân viên OFFLINE và khu vực chính trong một giao dịch. App cho đăng nhập bằng mật khẩu đã đăng ký. |
| REJECTED | Có lý do; không tạo tài khoản. Không ghi đè hồ sơ bị từ chối bằng PUT; có thể đăng ký hồ sơ mới nếu thông tin chưa thuộc tài khoản thật. |

Xe khai báo là đề xuất; không tự tạo/chiếm xe có biển số đó hoặc tự khai tải trọng. Sau duyệt, admin kiểm tra và phân công phương tiện bằng chức năng nhân viên/phương tiện hiện có. Hồ sơ tài xế trên app phản ánh phân công sau đó.

Khi duyệt, backend kiểm tra lại giấy phép còn hạn theo ngày Việt Nam, bưu cục/khu vực hoạt động, vai trò/quyền SHIPPER, đủ bốn ảnh và trùng username/email/điện thoại/CCCD. Kiểm soát phiên bản và command ID bảo đảm hai lần duyệt đồng thời hoặc gửi lại không tạo nhiều tài khoản. Hash mật khẩu của hồ sơ được xóa khi duyệt/từ chối; tài khoản được duyệt giữ hash trong bảng tài khoản như quy trình hiện có. Không đưa mật khẩu/hash/secret vào JSON hoặc nhật ký xử lý.

## API

- GET /api/v1/shipper-registrations/catalogs: bưu cục/khu vực hoạt động.
- POST /api/v1/shipper-registrations: multipart thông tin và bốn ảnh; X-Application-Token là secret theo dõi.
- GET /api/v1/shipper-registrations/{guid}/status: cần đúng secret trong header, không dùng token đăng nhập.
- PUT /api/v1/shipper-registrations/{guid}: bổ sung trọn bộ hồ sơ/ảnh khi NEEDS_INFO, kèm ExpectedVersion.
- GET /api/v1/admin/shipper-registrations và /{guid}: danh sách/chi tiết, kiểm tra ADMIN và quyền thực tế.
- GET /api/v1/admin/shipper-registrations/{guid}/documents/{kind}: ảnh riêng tư, no-store và nosniff.
- POST /api/v1/admin/shipper-registrations/{guid}/review: action APPROVE/NEEDS_INFO/REJECT, reason, expectedVersion, commandId.

Các API public được giới hạn số yêu cầu theo IP. API hoạt động xét duyệt vẫn kiểm tra quyền máy chủ; menu ẩn không thay thế kiểm tra quyền.

## Schema và áp dụng

Migration database/migrations/20261030_shipper_registrations.sql thêm ShipperRegistration, ShipperRegistrationDocument và ShipperRegistrationEvent. Có giao dịch, kiểm tra đúng database QLGiaoHangChangCuoi, chạy lại an toàn; không cập nhật/xóa dữ liệu vận hành hiện có.

**Đã áp dụng migration trên LocalDB QLGiaoHangChangCuoi của dự án** bằng cấu hình Development thực tế (JSON, User Secrets nếu có và biến môi trường), xác nhận Windows authentication và đúng LocalDB trước khi thực hiện. Sau migration đã kiểm tra giữ nguyên số dòng tài khoản, token, đơn hàng và tồn kho. Không tạo tài khoản đăng ký mẫu trong database vận hành.

Công cụ tools/AuthSessionDiagnostics có chế độ apply-registration với tên database tường minh; dừng sau khi kiểm tra schema, không khởi động API hay đổi phiên đăng nhập.

Để dùng giao diện mới: dừng/chạy lại LastMile.Api trong Visual Studio, profile http; dừng/chạy lại Flutter; Ctrl+F5 trên web quản lý. Không cần nạp lại seed SQL.

## Kiểm chứng

- Backend và công cụ schema build: 0 cảnh báo, 0 lỗi. Flutter analyze không có vấn đề.
- Flutter **96/96** kiểm thử đạt, gồm **15** ca mới cho receipt, multipart/secret, dữ liệu thiếu, lỗi gửi, bước biểu mẫu, ảnh, bổ sung và chuyển đến đăng nhập sau duyệt.
- Web **205/205** kiểm thử đạt, gồm route xét duyệt chỉ ADMIN và kiểm tra bộ lọc trạng thái.
- Tích hợp **7 nhóm đạt** với database GUID cách ly, API thật và Edge chạy ẩn: ảnh riêng tư, thiếu/ảnh sai bị từ chối, pending không đăng nhập, idempotency, bổ sung và phiên bản, hai yêu cầu duyệt đồng thời, tài khoản SHIPPER thật đăng nhập sau duyệt, từ chối, migration chạy lại; trang admin thực sự xem bốn ảnh, kiểm tra lý do và gửi NEEDS_INFO một lần, không có lỗi JS và không tràn ngang ở 390px. Database tạm đã được dọn.
- Chạy lại qua npm.cmd run test:shipper-registration trong frontend. Ảnh kiểm tra giao diện là ảnh QA giả lập, giữ trong frontend/tests/.artifacts/shipper-registration.
- Không chạy app trên máy ảo/điện thoại hay điều khiển thiết bị; chưa kiểm thử camera vật lý hoặc dịch vụ eKYC bên ngoài.
