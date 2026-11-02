# Dữ liệu mẫu xuất kho cho mọi kho

Ngày cập nhật: 29/10/2026.

Nguyên nhân danh sách trống: tập dữ liệu cơ sở có đơn IN_WAREHOUSE/WAITING_ASSIGNMENT nhưng không có đơn ASSIGNED còn trong kho cùng phân công PENDING/ACCEPTED hiện hành. Các phân công mẫu trước đó đã kết thúc hoặc hàng đã rời kho.

Đã thêm `database/03_BoSung_DuLieu_XuatKho.sql` và tích hợp cùng nội dung ở cuối `database/02_Nap_DuLieu_ThucTe.sql`. Khi nạp mới, chạy 01 rồi 02 là đủ. Database đã có dữ liệu chỉ cần chạy 03; không chạy lại 02 để bổ sung vì phần đầu 02 xóa dữ liệu cơ sở.

Mỗi kho hoạt động được tạo 3 đơn mới có mã `DH-XK-<mã kho>-1/2/3`: hai phân công ACCEPTED với tồn ALLOCATED và một phân công PENDING với tồn STORED. Tất cả đơn ở ASSIGNED; có điểm lấy/giao, hàng có cân nặng và ba kích thước, phí vận chuyển, giao dịch nhập, chi tiết nhập, tồn kho, lịch sử trạng thái và liên kết shipper/xe trong cùng bưu cục. Đơn thứ hai có COD 150.000 đồng; hai đơn còn lại không COD. Kho hàng hoàn có một lô gửi lại mẫu riêng, không sửa các đơn hoàn cũ.

Script tìm ID theo dữ liệu thực tế, không gắn cứng warehouseId=1016. Chọn shipper/xe đang hoạt động, bằng lái còn hạn theo ngày Việt Nam, địa chỉ giao trong khu vực shipper. Kiểm tra tổng tải và thể tích của mọi phân công hiện hành. Nếu một kho thiếu điều kiện, hủy toàn bộ lần bổ sung. Giữ nguyên trigger/constraint và chuyển trạng thái qua stored procedure. Khóa lần chạy bằng application lock; mã đơn cố định khiến chạy lại không tạo trùng hoặc đưa đơn đã xuất trở lại kho.

## Kiểm chứng

- Tạo database SQL LocalDB riêng với toàn bộ schema 01 và dữ liệu 02.
- Chạy 03 lần đầu tạo 12 đơn; chạy lại tạo 0 đơn.
- Dùng nguyên SQL từ WarehouseHandoverOrdersController (thay helper ngày Việt Nam bằng biểu thức SQL tương ứng): cả 4 kho trả 3 dòng, 2 canHandover=true và 1 PENDING.
- Dùng nguyên SQL từ WarehouseOutboundController: xuất thành công một đơn ACCEPTED tại từng kho, trả HANDED_OVER. Mỗi lần được bọc trong giao dịch ngoài và rollback, chỉ thực hiện trên database thử.
- Chạy lại toàn bộ 02 đã tích hợp: thành công.
- Đã áp dụng riêng 03 lên database QLGiaoHangChangCuoi đang dùng: tổng đơn 162 → 174. Số lượng và CHECKSUM_AGG/BINARY_CHECKSUM toàn bộ cột của 162 đơn cũ trước/sau bằng nhau.
- Đọc lại SQL danh sách trên database đang dùng: Bình Tân phân loại, Bình Tân hàng hoàn, Tân Phú, Quận 6 đều có 3 dòng, 2 đủ điều kiện bàn giao. Không xuất thử trên database đang dùng.
- Đã xóa database thử sau khi hoàn tất.

Phạm vi kiểm tra là SQL Server và câu SQL nghiệp vụ từ controller, chưa kiểm thử qua HTTP/JWT hay trình duyệt trong lần thay đổi này. Không sửa giao diện hoặc nới điều kiện xuất kho.
