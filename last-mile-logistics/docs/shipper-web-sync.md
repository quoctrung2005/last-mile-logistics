# Đồng bộ web quản lý và app shipper

Ngày kiểm tra: 29/10/2026.

## Bản dùng chung

- Backend: `backend/LastMile/LastMile.Api`, cổng 5038.
- Web: `frontend`, cổng 5500, chuyển tiếp API tới backend trên.
- App Flutter: `app_shipper/lib`, gọi cùng backend.
- Database: lấy theo cấu hình backend chính. App không mở kết nối SQL trực tiếp.
- Các thư mục `app_shipper/backend`, `app_shipper/frontend`, `app_shipper/database` là bản nhập kèm để tham khảo. Không khởi động hoặc nạp dữ liệu từ các bản này cho môi trường dùng chung.

## Các thay đổi

1. Bổ sung hub `/hubs/shipper`. Giữ xác thực JWT và kiểm tra phiên SQL của backend chính; chỉ tài khoản SHIPPER kết nối được. Nhóm nhận thông báo được xác định từ tài khoản đăng nhập, không nhận ID do client chỉ định.
2. Gửi `TaskAssigned` sau khi phân công tay, đổi shipper hoặc xác nhận phương án VRP đã commit; gửi `HandoverReady` sau khi kho xuất hàng. Lỗi gửi thông báo không đảo ngược giao dịch đã lưu. Xác nhận lại phương án đã lưu không gửi trùng.
3. Bổ sung GET `/api/v1/my/handovers`: chỉ phiếu PENDING thuộc shipper đăng nhập và bưu cục của họ.
4. Danh sách nhiệm vụ rỗng trả `items: []`; trả thêm `returnRequestStatus` để app biết yêu cầu hoàn đã duyệt.
5. Shipper dùng quyền `NHIEMVU_CAPNHAT` để tạo yêu cầu hoàn cho chính phân công IN_PROGRESS hiện hành của mình. Không cấp thêm quyền sửa đơn chung. Nhân viên quản lý vẫn dùng `DONHANG_CAPNHAT`. API hiện có duyệt yêu cầu hợp lệ ngay thành APPROVED; đây không phải quy trình chờ CSKH phê duyệt riêng.
6. App lưu địa chỉ máy chủ qua lần mở lại và đăng xuất; xóa thông tin shipper/bưu cục cũ khi đổi tài khoản. Đăng nhập bằng tài khoản quản lý không được mở dashboard shipper.
7. Làm mới token trước khi gửi ảnh multipart và kết nối SignalR. Thêm tải lại phiếu bàn giao mỗi 30 giây khi mất thông báo. Các danh sách đơn/giao lại/hoàn/bản đồ đọc đủ các trang API.
8. Bổ sung mô tả quyền camera, thư viện ảnh và vị trí trên iOS.

## Chạy đúng bản

Từ thư mục `last-mile-logistics`:

```powershell
.\tools\start-shared-api.ps1
```

Web dùng `frontend/dev-server.cjs`. Không chạy thêm backend trong `app_shipper`.

App trên Android Emulator: `http://10.0.2.2:5038`.

Điện thoại thật cùng Wi-Fi: dùng `http://<IPv4 máy chạy API>:5038` ở màn đăng nhập, khởi động API bằng `tools/start-shared-api.ps1 -BindAddress 0.0.0.0`. Cần kết nối mạng/firewall phù hợp. Chỉ thực hiện cấu hình này khi thử trên điện thoại; không tự mở cổng firewall trong thay đổi này. HTTP chỉ dành cho thử nghiệm nội bộ; bản phát hành dùng HTTPS.

## Kiểm tra đã chạy

- Build backend: đạt, không cảnh báo/lỗi.
- 10 nhóm kiểm tra API + WebSocket/SignalR thật bằng `frontend/tests/shipper-sync-api.cjs`: đạt.
- 63 kiểm tra hồi quy web về đăng nhập, điều phối và bộ lọc: đạt.
- Kiểm tra API tạo database LocalDB GUID riêng rồi xóa; ảnh thử lưu trong thư mục build kiểm tra. Không cập nhật trạng thái đơn đang dùng.

Các luồng: phân công đúng shipper, từ chối truy cập chéo, nhận nhiệm vụ, chặn giao trước nhận hàng, kho bàn giao, shipper xác nhận, bắt đầu giao, thành công/COD, giao thất bại có ảnh và nhân viên tải ảnh, chuyển hoàn về kho, đổi shipper, thông báo từ VRP, chống trùng xác nhận và từ chối phiên bị thu hồi khi kết nối lại.

Chạy lại:

```powershell
dotnet build backend/LastMile/LastMile.Api --no-restore --output frontend/tests/.artifacts/shipper-sync/build
node frontend/tests/shipper-sync-api.cjs
```

Kết quả máy đọc được: `frontend/tests/.artifacts/shipper-sync/results.json`.

## Giới hạn còn lại

- Flutter 3.47.8 / Dart 3.13.7 đã cài tại `D:\flutter`; command-line tools Android tại `D:\AndroidSDK`. Đã chạy `flutter pub get` và `flutter analyze --no-pub`: No issues found. Cache gói tại `D:\FlutterPubCache`, Gradle tại `D:\GradleCache`. Người dùng đang cài Android Studio vào `D:\AndroidStudio`; còn cần tải SDK platform/build-tools và kiểm tra thiết bị. Chưa build APK hoặc thao tác giao diện trên điện thoại.
- Đăng ký/eKYC vẫn là giao diện mô phỏng.
- Giao thành công chưa đính kèm ảnh; yêu cầu hoàn chưa có ảnh riêng. Ảnh giao thất bại đã có và kiểm chứng xem được từ API quản lý.
- Màn bản đồ mở Google Maps theo điểm giao; chưa hiển thị hình học/thứ tự tuyến VRP của backend trong app.
- Thông báo không lưu thành hàng đợi bền vững. Khi offline, danh sách API là nguồn khôi phục; tải lại sau khi mở app.
