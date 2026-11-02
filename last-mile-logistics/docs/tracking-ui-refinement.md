# Cập nhật giao diện Theo dõi giao hàng — 17/10/2026

## Thay đổi

- Giữ Bootstrap, tông trắng/cam, toàn bộ API, quyền và cách tính dữ liệu hiện có. Không sửa backend.
- Desktop: danh sách rộng 340–380px, chi tiết dùng phần còn lại. Các phần tử grid có `min-width: 0`; không dùng overflow để giấu lỗi bố cục. `overflow: hidden` trên địa chỉ card chỉ phục vụ giới hạn hai dòng.
- Màn hình dưới 1100px dùng danh sách hoặc chi tiết, có nút quay lại; sidebar tiếp tục dùng breakpoint và lifecycle hiện có của ứng dụng.
- Card bỏ ngày cập nhật lặp lại. Chi tiết chia Người nhận, Người giao và thời gian; nút Chi tiết đơn nằm trên đầu.
- Bản đồ cao 400px trên desktop, 280–400px trên màn hình nhỏ. Có Xem tất cả điểm / Vị trí shipper, kèm trạng thái vô hiệu hóa và lý do đọc được khi thiếu tọa độ.
- Tái sử dụng Bootstrap Icons: kiện hàng, ghim giao hàng, người giao hàng. Popup chứa dữ liệu liên hệ/địa chỉ có trong API và thời điểm GPS. Popup giới hạn chiều cao, cuộn khi nội dung dài; chỉ căn vào popup khi người dùng mở nó.
- Các điểm có tọa độ bằng nhau được dàn biểu tượng cạnh nhau bằng `iconAnchor`, giữ nguyên latitude/longitude. Popup giải thích các điểm cùng tọa độ; từng biểu tượng có nhãn, focus và hỗ trợ Enter/Space.
- GPS cũ giữ ngưỡng hơn 5 phút. Thông báo ngắn, thời gian riêng, tooltip giải thích ngưỡng; biểu tượng có viền nét đứt và đồng hồ. Không suy diễn trạng thái trực tuyến.
- Giữ timeline và các lần giao có thật từ API. Không vẽ tuyến đường hoặc thêm sự kiện/tọa độ giả.
- Polling cập nhật marker theo khóa, giữ instance bản đồ và marker không đổi, không fit lại camera. Chỉ invalidateSize khi kích thước thực sự đổi; ResizeObserver được dọn cùng map, request và timer khi rời trang.

## Kiểm tra thực tế

Lệnh: `npm.cmd test --prefix frontend` và `npm.cmd run test:tracking --prefix frontend`.

Unit test: **43/43 đạt**. Tích hợp: **70 kiểm tra đạt, 0 lỗi JavaScript**. Build phục vụ tích hợp: **0 lỗi, 0 cảnh báo**.

Kiểm tra trình duyệt dùng Edge headless, zoom 100%, API ASP.NET thật và database LocalDB GUID riêng. Database kiểm thử tự xóa sau mỗi lượt; không ghi dữ liệu vận hành. GPS thiếu/cũ dùng fixture trong database riêng. Tọa độ trùng, tọa độ ngoài miền hợp lệ và chuỗi rất dài được sửa trên response chỉ trong trình duyệt kiểm thử, không sửa API hoặc database vận hành.

Các trường hợp đã chạy: 1366/1920/390px; chọn đơn và quay lại; mở/đóng sidebar mobile; lọc và phân trang; tab bản đồ/lịch sử; lịch sử nhiều lần giao; GPS thiếu/cũ; marker trùng và từng popup; bàn phím Space; tên/địa chỉ dài; địa chỉ card hai dòng; nút căn tất cả/shipper; không có tọa độ hợp lệ rồi có lại; giữ camera/zoom/marker khi làm mới; polling thật 30 giây; ẩn tab; tắt polling; response cũ; hủy tải và dọn bản đồ khi rời trang.

Leaflet làm tròn tọa độ khi đổi zoom/kích thước: kiểm tra giữ tâm cho phép sai số tối đa **1 pixel bản đồ**, zoom và DOM marker phải giữ nguyên. Bản đồ nền vẫn cần mạng OpenStreetMap; attribution được giữ lại.

Kết quả máy đọc: [tracking-verification.json](tracking/tracking-verification.json).

Ảnh sau chỉnh sửa:

- [Desktop 1366px](tracking/tracking-list-1366.png)
- [Desktop 1920px](tracking/tracking-list-1920.png)
- [Danh sách mobile 390px](tracking/tracking-list-390.png)
- [Chi tiết mobile 390px](tracking/tracking-mobile-detail-390.png)
- [Lịch sử](tracking/tracking-history-1366.png)
- [Thiếu GPS](tracking/tracking-no-gps-1366.png)
- [GPS cũ](tracking/tracking-old-gps-1920.png)
- [Marker trùng, nội dung dài — desktop](tracking/tracking-overlap-long-1366.png)
- [Marker trùng, nội dung dài — mobile](tracking/tracking-overlap-long-390.png)
