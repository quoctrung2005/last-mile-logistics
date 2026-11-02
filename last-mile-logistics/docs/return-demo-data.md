# Dữ liệu mẫu nhập hàng hoàn

Ngày cập nhật: 29/10/2026.

Đã thêm database/04_BoSung_DuLieu_HoanHang.sql và tích hợp cùng nội dung ở cuối file 02_Nap_DuLieu_ThucTe.sql. Database hiện có chỉ cần chạy 04; không chạy lại 02 để bổ sung vì phần đầu 02 xóa dữ liệu cơ sở.

Script tạo 2 đơn mới cho mỗi bưu cục đang có kho hoạt động. Với dữ liệu hiện tại là 6 đơn, mã DH-HOAN-<mã kho nguồn>-1/2. Kho nguồn được tìm theo ID nhỏ nhất trong mỗi bưu cục, không gắn cứng ID môi trường. Các kho cùng bưu cục xem chung yêu cầu hoàn theo contract hiện có; không nhân đôi yêu cầu riêng cho kho hàng hoàn Bình Tân. Nhận vào một kho sẽ loại yêu cầu khỏi danh sách chờ nhận của các kho cùng bưu cục.

Mỗi đơn có điểm lấy/giao, hàng đủ cân nặng/kích thước, phí, lịch sử nhập kho và xuất/bàn giao đã xác nhận. Đơn đi qua các bước trạng thái hợp lệ; giao thất bại được ghi bằng sp_XacNhanGiaoHangThatBai với lý do không bắt buộc ảnh. Sau đó tạo yêu cầu RETURN/IN_PROGRESS và chuyển RETURNING bằng stored procedure; phân công được kết thúc. Tồn cũ là HANDED_OVER, kho hiện tại NULL, đáp ứng điều kiện nhập hoàn. Không vô hiệu hóa trigger, không sửa đơn cũ hoặc đặt đường dẫn ảnh giả. Chạy lại bỏ qua mã đã có, không đưa đơn đã nhập hoàn trở lại hàng chờ.

## Kiểm chứng

- Tạo database LocalDB thử riêng từ schema 01, chạy toàn bộ 02 đã tích hợp cả xuất kho và hoàn hàng: thành công.
- Dùng nguyên SQL WarehouseReturnRequestsController: cả 4 kho thấy 2 đơn hoàn mẫu mới phù hợp bưu cục.
- Dùng nguyên SQL WarehouseReturnInController: mỗi kho nhận thử một đơn thành RETURNED, rồi rollback giao dịch ngoài. Chỉ thử ghi trên database thử.
- Áp dụng riêng 04 lên QLGiaoHangChangCuoi đang dùng: tạo 6 đơn, tổng 174 → 180. Số lượng và CHECKSUM_AGG/BINARY_CHECKSUM toàn bộ cột của 174 đơn trước đó không đổi.
- Đọc lại SQL danh sách trên database đang dùng: Bình Tân phân loại 2, Bình Tân hàng hoàn 2 (cùng hai yêu cầu), Tân Phú 3 (gồm một yêu cầu cũ), Quận 6 2.
- Chạy lại 04 tạo 0 đơn; đã xóa database thử sau kiểm tra.

Kiểm tra ở SQL Server/câu SQL từ controller, chưa qua HTTP/JWT hoặc trình duyệt. Không nhận hoàn thử trên database đang dùng.

## Ảnh

Form Nhập hàng hoàn hiện chỉ gửi orderId, returnRequestId, warehouseId, locationId, condition và notes; chưa có tải hoặc xem ảnh trong form này. Hệ thống có bằng chứng ảnh theo lần giao tại BangChungGiaoHang, được xem trong trang Theo dõi giao hàng nếu tệp tồn tại và người dùng có quyền. Sáu đơn mới không có ảnh. Việc thêm ảnh vào lúc tiếp nhận hàng hoàn sẽ cần bổ sung chức năng riêng, không chỉ dữ liệu SQL.
