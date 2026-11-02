# Mục 14 — Quét mã kiện

Đã triển khai **STT 14 của bảng 40**. Phần **STT 15 — Báo sự cố lấy hàng** đã triển khai tiếp, xem [hồ sơ và phản hồi](shipper-pickup-issues.md). Mục kế tiếp hiện là **STT 16 — Chuyến giao, thứ tự giao**. Mục 14 không thêm một bước duyệt bàn giao của kho.

## Cách dùng

1. Mở nhiệm vụ **Nhận tại kho** → đến kho trên bản đồ → **Đã nhận kiện hàng** → **Quét mã kiện**.
2. Cấp quyền camera, đưa một mã vận đơn trên nhãn vào camera. Có nút bật/tắt đèn khi thiết bị hỗ trợ.
3. App đối chiếu toàn bộ nội dung mã vừa đọc với **mã vận đơn hoặc mã đơn** của đúng nhiệm vụ. Sai mã báo không khớp; thấy nhiều mã khác nhau yêu cầu đưa riêng một mã vào camera. Không chọn ngầm một kiện trong nhiều mã.
4. Đúng mã: camera dừng, hiện **Đã khớp mã kiện**. Bấm **Dùng mã này** để điền mã vào phiếu nhận, hoặc **Quét lại**.
5. App tải lại nhiệm vụ sau khi đóng camera. Nếu bị thu hồi/đổi phân công, đổi kho hoặc mã nhãn thì không dùng kết quả cũ. Tài xế vẫn kiểm tra nhãn, xác nhận đủ kiện, khai tình trạng/ảnh theo mục 13 rồi bấm **Đã nhận kiện hàng**. Chỉ lúc này mới gửi lệnh xuất kho/nhận kiện.

Không dùng được camera hoặc không có quyền: chọn **Nhập mã thủ công**. Nhập tay cũng phải khớp mã nhiệm vụ; sửa mã sẽ xóa hai xác nhận kiểm tra cũ. Mã có số 0 đầu được giữ nguyên; không tự bỏ tiền tố/dấu gạch hay lấy một đoạn mã trong URL/JSON.

## Đồng bộ và camera

- Dùng dữ liệu nhiệm vụ từ API hiện có, kiểm tra quyền và nhãn lại trên máy chủ tại lúc nhận. Quét/chọn mã không tạo giao dịch kho, không tự chấp nhận nhiệm vụ và không thay đổi lộ trình admin.
- Giữ các quy tắc nhận kiện, ảnh hư hại sẵn, biên nhận và chống gửi trùng của mục 12–13. Quét đúng mã chưa xác nhận số lượng/tình trạng kiện.
- Camera chỉ chạy trên màn quét khi app đang ở trước màn hình và chưa chốt mã. Dừng khi chuyển nền, khớp mã hoặc rời màn; chờ xử lý camera đang khởi tạo trước khi giải phóng. Quyền bị từ chối không tự lặp hộp xin quyền khi app trở lại; có nút thử lại và nhập tay.
- Không trả/lưu/upload khung hình quét (`returnImage: false`). Ảnh bằng chứng lúc nhận kiện vẫn chụp/chọn riêng theo mục 13.
- Thêm thư viện **mobile_scanner 7.4.2**, khóa đúng phiên bản trong pubspec/lockfile. Android khai báo quyền camera, camera không bắt buộc để vẫn nhập tay trên thiết bị không có camera. iOS bổ sung nội dung giải thích quyền camera. Tham khảo [tài liệu của thư viện](https://pub.dev/packages/mobile_scanner/versions/7.4.2).

## Áp dụng

Stop app và chạy lại hoàn toàn từ Android Studio để nạp plugin mới; hot reload không đủ cho thay đổi plugin/quyền native. Phụ thuộc Flutter đã được tải trong lần triển khai này. Mục 14 không có migration hoặc API mới và không cần chạy lại backend chỉ vì phần quét.

File [SQL biên nhận mục 13](../database/migrations/20261030_shipper_pickup_receipts.sql) được sửa riêng theo lỗi chỉ mục đã tồn tại: kiểm tra `sys.indexes` trước khi tạo index, đồng thời bổ sung được index còn thiếu trên bảng đã có. Khi cần áp dụng, mở lại file cập nhật và chạy toàn bộ trên đúng database; không chạy riêng lệnh tạo index cũ. Chưa áp dụng thay đổi vào database vận hành.

## Kiểm chứng ngày 30/10/2026

- Flutter analyze: không có vấn đề. Toàn bộ **224/224 bài kiểm tra Flutter** đạt.
- Hai bộ mới `parcel_scanner_test.dart` và `parcel_scan_receipt_test.dart`: **19 bài**, gồm sai/nhiều mã, giữ số 0 đầu, không trích mã từ URL/JSON, đèn, quyền bị từ chối, camera trả kết quả muộn khi chuyển nền/rời màn, tải lại nhiệm vụ, đổi kho/mã nhãn, nhập tay, hủy quét và chỉ gửi nhận kiện sau kiểm tra thực tế.
- **40 nhóm HTTP/JWT/SQL/SignalR** đạt trên database GUID riêng, gồm nhận kiện và hồi quy giao/hoàn/COD; migration chạy lặp khi có/thiếu index vẫn giữ nguyên biên nhận thật.
- Build APK Android debug **x86_64** với cấu hình Gradle hiện tại thành công. Các cảnh báo Java native access hiện có không làm build thất bại.
- Không mở máy ảo, không cài app, không chạy camera điện thoại hoặc build iOS trong lần này. Các bài kiểm tra camera dùng lớp nền tảng giả lập để kiểm chứng điều khiển/lifecycle; không thay thế việc thử đọc nhãn thật trên thiết bị. Chưa xác minh camera trình duyệt trực tiếp.
