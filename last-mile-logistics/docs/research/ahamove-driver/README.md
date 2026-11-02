# Tham khảo giao diện Tài xế Aha cho app shipper

Ngày xem: 29/10/2026. Phạm vi: nghiên cứu ảnh giao diện công khai và tài liệu chính thức; chưa sửa giao diện app shipper.

## Nguồn và giới hạn

- [Tài xế Aha trên Google Play](https://play.google.com/store/apps/details?hl=vi&id=com.ahamove.supplier): đã tải và xem trực tiếp 6 ảnh giới thiệu. Đây là ảnh quảng bá có chèn màn hình ứng dụng, không phải bản chụp đầy đủ mọi màn hình.
- [Hướng dẫn thao tác ứng dụng tài xế Ahamove](https://ahamove.com/huong-dan-thao-tac-tren-ung-dung-tai-xe-ahamove): xác nhận có hướng dẫn giao diện, nạp/rút tiền và ký quỹ. Video Canva nhúng chưa xem được; không dùng nó làm bằng chứng đã quan sát giao diện.
- [Tự động nhận đơn 2.0](https://ahamove.com/tu-dong-nhan-don-2-0): tham khảo cách mô tả nhận đơn, trạng thái hoạt động và thông báo. Không coi các điều kiện trong bài này là quy định hiện hành cho mọi tài xế.
- [Ứng dụng tài xế OnWheel](https://developers.ahamove.com/onwheel/driver-application): tài liệu về sản phẩm dành cho đội tài xế nội bộ, riêng với Tài xế Aha. Chỉ dùng đối chiếu quy trình online → nhận nhiệm vụ → giao hàng và thông tin thẻ đơn.

Không đăng nhập app Ahamove, không thao tác tài khoản tài xế, không khẳng định đã xem mọi màn hình bản mới nhất.

## Quan sát trực tiếp từ sáu ảnh

| Ảnh lưu | Nội dung thấy được | Bài học bố trí |
|---|---|---|
| [store-1.png](store-1.png) | Bản đồ nhiều điểm; điểm lấy và giao phân biệt màu; các điểm có số thứ tự | Thứ tự điểm dừng cần nhìn rõ trên bản đồ và khớp danh sách tuyến |
| [store-2.png](store-2.png) | Chọn hình thức làm việc bằng thẻ lớn, có mô tả và trạng thái nổi bật | Các lựa chọn cần tên ngắn và giải thích ngay tại chỗ |
| [store-3.png](store-3.png) | Thẻ đơn có nhãn dịch vụ, giá cước màu cam, quãng đường màu xanh, khoảng cách tới điểm lấy | Phân cấp thông tin để người lái đọc nhanh trước khi quyết định |
| [store-4.png](store-4.png) | Bản đồ phía sau; chuyển Tổng quan/Chi tiết điểm; bảng kéo chứa hạn lấy, địa chỉ, ghi chú, hàng hóa và yêu cầu có thể thu gọn | Kết hợp điều hướng với thông tin điểm hiện tại; mở rộng chi tiết khi cần |
| [store-5.png](store-5.png) | Hỗ trợ dạng hội thoại với các lựa chọn gợi ý | Lối vào hỗ trợ dễ thấy và câu hỏi ngắn; không suy ra backend hiện có khả năng AI |
| [store-6.png](store-6.png) | Thẻ điểm chất lượng, nhóm tiêu chí, thanh tiến độ và mức phân loại | Số liệu cần có nhãn, thời điểm cập nhật và giải thích nguồn tính |

Màu trong phần giao diện được quan sát: nền trắng/xám nhạt, chữ tối, cam để nhấn mạnh, xanh hỗ trợ thông tin bản đồ. Nền cam đen, hiệu ứng sáng và hình 3D bao quanh điện thoại thuộc ảnh quảng bá; không dùng chúng như nền mặc định của màn thao tác.

## Đối chiếu app shipper hiện tại

Đây là đề xuất cho dự án, không phải mô tả các chức năng Ahamove đã được kiểm tra trực tiếp.

| Phần app hiện tại | Hướng áp dụng phù hợp |
|---|---|
| `b1_home_screen.dart` | Giảm diện tích thẻ hồ sơ; ưu tiên trạng thái sẵn sàng, việc cần làm tiếp theo và các nhiệm vụ đang thực hiện |
| `b2_new_task_popup_dialog.dart` | Làm rõ kho nhận hàng, điểm giao, COD và nút nhận nhiệm vụ; dữ liệu thiếu cần có trạng thái giải thích |
| `b3_order_management_screen.dart` | Thẻ đơn gọn, địa chỉ dễ đọc; nút hành động thay đổi theo trạng thái đã được API xác nhận |
| `b4_map_route_screen.dart` | Có thể phát triển bản đồ và bảng điểm dừng; cần lấy đúng thứ tự, hình học tuyến từ backend. Hiện màn này mở Google Maps bên ngoài |
| `b5_delivery_success_screen.dart`, `b6_delivery_failed_screen.dart` | Tách người nhận/tiền thu/bằng chứng; xác nhận rõ trước khi gửi kết quả. Ảnh thành công là phần còn cần phát triển |
| `b7_cod_wallet_screen.dart` | Hiển thị rõ COD đang giữ, đang chờ xác nhận nộp và đã nộp. Không đổi phí vận chuyển thành thu nhập tài xế khi chưa có quy tắc/API tương ứng |
| `b8_handover_screen.dart`, `c1/c2` | Giữ luồng nhận hàng từ kho, giao lại và hoàn hàng; thể hiện trạng thái chờ kho/chờ xử lý rõ ràng |

## Nguyên tắc cho lần thiết kế sau

1. Chỉ hiện nút có thể thực hiện ở trạng thái hiện tại, lấy backend làm nguồn quyết định.
2. App của dự án nhận nhiệm vụ được điều phối; không biến thành sàn tự chọn mọi đơn hoặc tự chấp nhận nhiệm vụ chỉ vì có tính năng tương tự ở Ahamove.
3. Nút thao tác chính lớn, nằm ở vị trí dễ chạm; thông tin phụ có thể mở rộng. Đây là định hướng thiết kế đề xuất.
4. Tách COD, phí dịch vụ và thu nhập. Không thêm số liệu, điểm chất lượng, bộ đếm hoặc tính năng AI giả để trang trí.
5. Dùng bộ nhận diện riêng của dự án; tham khảo cách tổ chức thông tin và tương tác.
6. Khi triển khai cần kiểm tra trên màn nhỏ, trạng thái rỗng, mất mạng, đang gửi, lỗi API và kết quả thao tác chưa xác định.

Chưa thực hiện: sửa mã Flutter, chạy ứng dụng, đổi nghiệp vụ, hoặc tích hợp bản đồ/AI/thu nhập mới.
