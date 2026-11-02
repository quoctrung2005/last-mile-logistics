# Giao diện app tài xế theo nghiệp vụ TVD Logistics

Đợt chỉnh đầu tiên, ngày 29/10/2026. Rà chức năng từ menu/route, mã giao diện web và các API đã có; không khẳng định đã kiểm thử lại toàn bộ trang quản lý trong đợt này.

## Chức năng web đã đối chiếu

| Nhóm trên web quản lý | Liên quan tới giao diện tài xế |
|---|---|
| Tổng quan | Không đưa dashboard quản trị vào app; chỉ thống kê nhiệm vụ của tài xế đăng nhập |
| Đơn hàng | Mã đơn, người nhận, địa chỉ, hạn giao, ghi chú và COD |
| Kho: tồn kho, nhập kho, xuất kho/bàn giao, nhập hoàn, vị trí, lịch sử | Tài xế nhận phiếu bàn giao và xác nhận nhận kiện; kho xử lý xuất/nhập hàng trên web |
| Điều phối: hàng chờ, phân công, chuyến giao, tối ưu tuyến | App nhận nhiệm vụ được phân công; không tạo sàn tự nhận tất cả đơn |
| Theo dõi giao hàng | Tài xế cập nhật tiến trình, kết quả giao và sự cố |
| COD và đối soát | App theo dõi COD, lập phiếu nộp; nhân viên bưu cục xác nhận và đối soát |
| Khách hàng | Chỉ thông tin người nhận cần thiết cho việc giao |
| Nhân viên và phương tiện | Hồ sơ, trạng thái sẵn sàng và phương tiện của tài xế |
| Báo cáo | Không dùng số liệu quản trị làm thu nhập cá nhân |
| Quản trị: tài khoản, vai trò/quyền, danh mục, bảng giá, nhật ký | Tài khoản tài xế do quản trị cấp; app không hiển thị các chức năng quản trị |

## Các thay đổi đã thực hiện

- Trang chào và đăng nhập dùng nhận diện TVD Logistics; trang chào mô tả đúng quy trình, không hứa thu nhập hoặc đưa người dùng vào đăng ký mô phỏng.
- Trang chủ ưu tiên công việc tiếp theo: phiếu kho đã bàn giao → nhiệm vụ chờ nhận → đi giao → giao lại/hoàn → chờ kho. Số đếm lấy từ API nhiệm vụ, phiếu bàn giao và COD.
- COD chờ lập phiếu nộp và COD đang chờ bưu cục xác nhận được trình bày riêng. API lỗi/đang tải hiển thị chưa có dữ liệu; không biến thành số 0.
- Thanh điều hướng Trang chủ/Nhiệm vụ/Lộ trình/COD nằm trên cùng một khung và giữ lựa chọn hiện tại, không mở thêm một tầng trang chỉ để đổi tab.
- Thẻ nhiệm vụ ưu tiên địa chỉ, người nhận, hạn giao, COD, nút gọi và chỉ đường. Bỏ nút chat chưa có chức năng.
- COD bằng 0 ghi “Không thu COD”, không suy ra “Đã thanh toán trước”.
- Nhãn rõ theo từng bước: Chờ kho bàn giao / Chờ xác nhận nhận kiện / Sẵn sàng đi giao / Đang giao / Giao thất bại / Chờ giao lại / Đang chuyển hoàn.
- Tab “Nhận tại kho” giữ các nhiệm vụ đã chấp nhận. Nút xác nhận nhận kiện chỉ mở khi kho đã xuất. Nút bắt đầu giao chỉ dành cho nhiệm vụ IN_PROGRESS và đơn PICKED_UP. Các nhiệm vụ đã kết thúc/hủy không hiện thao tác giao.
- Hạn giao và thời gian API dạng UTC không kèm múi giờ được đọc theo UTC rồi hiển thị giờ địa phương.
- Các danh sách COD đọc đủ trang để thống kê không dừng ở 100 dòng đầu.
- Danh sách nhiệm vụ tải lại khi quay về từ màn nhận kiện; thông báo nhiệm vụ tới liên tiếp được xếp chờ thay vì bỏ khi đang mở một thông báo khác.

## Làm rõ thao tác ở web kho

Tồn kho dùng để xem hàng; Nhập hàng hoàn dùng để nhận hàng trả về. Xuất kiện cho tài xế nằm ở **Kho → Xuất kho / bàn giao**.

Đã thêm hướng dẫn ở trang Tồn kho và nút **Mở bàn giao** trên dòng đơn ASSIGNED còn tồn STORED/ALLOCATED, khi người dùng có quyền KHO_XUAT. Nút chỉ điều hướng tới đúng kho và lọc theo mã vận đơn; không tự ghi nhận xuất hàng. Trang nhập hoàn có thêm liên kết sang trang xuất kho/bàn giao.

Luồng tiếp theo vẫn là: tài xế nhận nhiệm vụ → nhân viên kho xác nhận bàn giao trên web → tài xế xác nhận nhận kiện trên app → bắt đầu giao.

## Ảnh xem trước

Ảnh được dựng từ widget Flutter bằng dữ liệu kiểm tra tổng hợp, không phải ảnh chụp tài khoản/đơn đang chạy. Font xem trước dùng font hệ thống Windows; thiết bị có thể thể hiện chữ khác nhẹ. Ảnh trang chủ là phần nội dung kéo dài, không bao gồm khung thanh điều hướng của màn chính.

- [Trang chủ](dashboard-390.png)
- [Thẻ nhiệm vụ chờ kho bàn giao](task-card-390.png)
- [Trang chào](welcome-390.png)

## Kiểm tra

- Flutter analyze: không có lỗi/cảnh báo.
- 14 kiểm tra Flutter đạt: phân loại trạng thái, chống hiển thị thao tác sai, số liệu chưa tải/rỗng, tách hai khoản COD, múi giờ, bố cục 320/390 px, chữ phóng to 150%, nút gọi/chỉ đường và điều hướng thẻ công việc.
- 49 kiểm tra web về router và danh sách điều phối đạt; cú pháp `warehouse.js` hợp lệ.
- Đã mở kiểm tra trực quan cả ba ảnh xem trước và sửa nền trong suốt/font ảnh thử.

Lệnh kiểm tra từ `app_shipper`:

```powershell
D:\flutter\bin\flutter.bat analyze --no-pub
D:\flutter\bin\flutter.bat test --no-pub --dart-define=EXPORT_UI_PREVIEWS=true --reporter expanded
```

Không khởi chạy app, máy ảo hoặc backend thay người dùng trong đợt này. Không ghi nhận bàn giao hay đổi trạng thái đơn thật. Việc đọc lại LocalDB để đối chiếu các đơn trong ảnh bị timeout; chưa xác minh lại dữ liệu thực tế của các đơn đó.

## Xem thay đổi

Trong Android Studio, người dùng tự Hot Restart app để tạo lại trang chủ và lấy dữ liệu. Web quản lý tải lại bằng Ctrl+F5. Backend dùng bản chính đang chạy như trước.

Bản đồ nhúng, thu nhập tài xế, chấm điểm chất lượng, trợ lý AI và ảnh giao thành công không được thêm trong đợt chỉnh này. Màn Lộ trình vẫn mở chỉ đường bằng Google Maps.
