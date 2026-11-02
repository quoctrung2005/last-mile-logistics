# Sửa tuyến đi vòng trong bản đồ

Bổ sung 31/10/2026: đã mở rộng snapshot và sửa lỗi với GPS `10.7769, 106.7009`, bộ lọc điều kiện và nhánh cụt. Vùng dữ liệu/thông tin kiểm tra hiện tại xem [bản sửa vùng trung tâm](routing-city-coverage-fix.md). Số liệu/vùng ở dưới là kết quả trước lần mở rộng này.

Cập nhật 30/10/2026, tiếp nối chức năng 10. Đây là sửa bộ tính đường và cách app đọc tuyến; không thêm bước vào quy trình nhận/giao hàng.

## Nguyên nhân và thay đổi

| Nguyên nhân tìm được | Cách sửa |
| --- | --- |
| Bộ nhập OSM loại toàn bộ các đường tham gia quan hệ cấm rẽ, kể cả quan hệ miễn xe máy. Đường lớn bị cắt khỏi mạng nên thuật toán phải đi vòng. | Với quy tắc cố định qua một nút giao được hỗ trợ, giữ đường và chỉ chặn chuyển hướng bị cấm. Áp dụng ngoại lệ và loại xe; lưu cả hướng đi vào giao lộ khi tìm đường. |
| Điểm GPS ghép vào đỉnh đường gần nhất, làm lệch điểm đầu/cuối; hai điểm gần nhau có thể thành cùng một đỉnh và trả 0 m. | Dẫn đường ghép vào vị trí chiếu trên đoạn đường thật, tính đúng phần đoạn đã đi, giữ chiều lưu thông. Không tạo đường nối tắt qua khu vực không có mạng đường. |
| Màn xem tuyến có GPS vẫn ưu tiên chặng đã lưu từ điểm trước của admin. | Khi có GPS, màn xem cũng gọi tuyến từ vị trí hiện tại đến điểm đang chọn. Giữ nguyên thứ tự chuyến admin, không gửi yêu cầu sắp xếp lại đơn. |
| Tuyến đã lưu không được kiểm tra phiên bản quy tắc/mạng đường. | Phiên bản SHA-256 gồm dữ liệu và chính sách tính đường. Tuyến cũ không được dùng lại; cần GPS để tính chặng mới. Không ghi đè hình học hoặc thứ tự chuyến đã lưu. |
| Nút có rào cản bị loại dù có quyền xe máy rõ ràng. | Xét quyền theo loại xe, chỉ mở cho loại xe được cho phép. |

Quy tắc cấm rẽ và ngoại lệ theo loại xe được đối chiếu với [tài liệu OSM](https://wiki.openstreetmap.org/wiki/Relation:restriction); quyền qua rào cản theo [tài liệu barrier](https://wiki.openstreetmap.org/wiki/Key:barrier).

## Kiểm chứng

- Backend build: 0 lỗi, 0 cảnh báo.
- Bộ định tuyến/lập kế hoạch: **48/48**, gồm cấm rẽ, hướng bắt buộc, miễn xe máy, đi lại một nút giao qua hướng khác hợp lệ, đường một chiều, hai điểm trên cùng đoạn, ghép đoạn đầu/cuối, quyền qua rào và điểm ngoài vùng phủ.
- Flutter analyze: không có vấn đề; toàn bộ **175/175** kiểm tra đạt. Ca mới kiểm tra màn xem ban đầu gửi GPS và yêu cầu tuyến hiện tại, giữ điểm admin đang chọn.
- **31 nhóm HTTP/SQL/SignalR** đạt trên API và LocalDB GUID thử. Ca mới đổi phiên bản tuyến lưu sang phiên bản cũ, xác nhận API không dùng lại; tính chặng mới giữ stopSequence và RouteJson không đổi; khôi phục phiên bản đọc được tổng quan admin.
- API và database thử đã dọn. Không chạy app/emulator hoặc thay GPS; không sửa database vận hành.

Tuyến chẩn đoán sẵn trong dự án: **(10.80692, 106.62868) → (10.8105, 106.6048)**, Đại học Công Thương → kho mẫu. Bản cũ ghép đỉnh cho **3.997,79 m**; bản sửa ghép đoạn cho **3.517,37 m**, khoảng **12% ngắn hơn**, thời gian ước tính **488,80 giây**. So sánh đầu-cuối là cùng tọa độ, cách ghép mạng đã thay đổi. Đây là tuyến thử nội bộ, chưa phải đối chiếu tuyến cụ thể người dùng phản ánh với Google Maps.

Báo cáo máy: `frontend/tests/.artifacts/routing-fix/before.json`, `after.json`; kiểm tra tích hợp tại `frontend/tests/.artifacts/shipper-sync/results.json`.

## Áp dụng và giới hạn

1. Người dùng Stop rồi chạy lại backend trong Visual Studio, profile **http**, để nạp bộ tính đường mới và bỏ mạng đường đang giữ trong bộ nhớ.
2. Stop rồi chạy lại Flutter; mở Lộ trình, cho phép vị trí và làm mới. Thứ tự điểm giao vẫn theo admin.
3. Với phương án chưa xác nhận được tạo trước bản sửa, admin cần tính lại phương án. Chuyến đang giao giữ thứ tự; app tính lại chặng tới điểm được chọn từ GPS.

Không cần migration/nạp lại dữ liệu mẫu. Dữ liệu mạng đường hiện tại là snapshot OSM ngày **17/10/2026**, bbox vĩ độ **10.70–10.85**, kinh độ **106.56–106.69**; không phủ toàn TP.HCM. Những hạn chế giờ/đi qua nhiều đoạn chưa được bộ máy hiểu đầy đủ vẫn được xử lý thận trọng theo loại xe, có thể còn gây đi vòng. Chưa có giao thông trực tiếp, giọng nói hay Google Navigation SDK. Bản đồ nền hiển thị được một con đường không đồng nghĩa bộ tính đường hiện tại đã có đầy đủ dữ liệu/quy tắc cho đường đó.

Vẫn cần tọa độ/địa chỉ đầu-cuối hoặc mã đơn đang đi vòng để đối chiếu riêng tuyến người dùng phản ánh; chưa kết luận mọi tuyến đã tương đương Google Maps.
