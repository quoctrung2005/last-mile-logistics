# Xác nhận với khách trước khi xử lý đơn quá hạn

Ngày cập nhật: 29/10/2026. Quy trình theo yêu cầu cuối cùng của người dùng: không ẩn đơn quá hạn và không tự chuyển hoàn/hủy khi chưa có xác nhận của khách.

## Quy trình trên giao diện

Hàng chờ Điều phối giữ các đơn quá hạn và đánh dấu Quá hạn · Chờ CSKH. Không cho chọn vào tuyến mới hoặc phân công trực tiếp. Tài khoản có quyền sẽ thấy Xử lý quá hạn, mở hộp thoại có số điện thoại, kết quả khách xác nhận và nội dung xác nhận bắt buộc.

- Khách vẫn nhận: bắt buộc chọn hạn giao mới trong tương lai; đơn tiếp tục WAITING_ASSIGNMENT, ưu tiên 1, bắt đầu giao sớm nhất từ thời điểm xử lý.
- Khách hủy: cần DONHANG_HUY và KHO_KIEMKE; chọn một vị trí khác nguồn trong cùng kho. Hệ thống tạo phiếu MOVE và chi tiết nguồn/đích, giữ tồn STORED, chuyển đơn CANCELLED qua stored procedure và ghi nhật ký RESOLVE_OVERDUE. Hàng có thể xem trong Tồn kho theo trạng thái đơn đã hủy, vị trí CHO-XU-LY nếu chọn vị trí mẫu này. Đây là hàng chưa xuất khỏi kho; không giả lập xuất/giao thất bại/shipper hoàn về để đưa vào màn Nhập hàng hoàn.
- Chưa liên hệ được khách: đóng hộp thoại, đơn vẫn hiện để CSKH theo dõi. Không ghi nhận giả cuộc gọi hoặc tự chọn kết quả.

## Backend và dữ liệu

POST /api/v1/dispatch/orders/{id}/resolve-overdue dùng transaction Serializable và khóa đơn/tồn, kiểm tra quyền/phạm vi hiện hành, chỉ WAITING_ASSIGNMENT đã quá hạn còn STORED trong kho, không có nhiệm vụ/chuyến đang hoạt động. Hạn và vị trí được kiểm tra lại ở server. Thao tác thành công làm request cũ không còn thỏa điều kiện; gửi lại trả 409 và không tạo thêm phiếu. Lỗi kỹ thuật sau khi bắt đầu xử lý trả resultUnknown để chặn gửi lại khi chưa kiểm tra.

File 06 kéo dài hạn các đơn mẫu chưa quá hạn còn chờ lên 7 ngày; bỏ qua đơn đã quá hạn, đơn đã phân công/chuyến mở và dữ liệu không thuộc mã mẫu. Đã áp dụng lên 24 đơn đang dùng, không tự tạo quyết định khách đối với đơn quá hạn. File 07 thêm vị trí CHO-XU-LY cho từng kho, không tự di chuyển hàng. Cả hai file được tích hợp cuối file 02; chạy riêng để bổ sung database hiện có, không chạy lại 02 vì phần đầu có xóa dữ liệu mẫu cũ.

## Kiểm tra

- Build API Release, 0 lỗi/cảnh báo.
- 78 kiểm tra frontend về điều phối, deadline UTC và kết quả ghi chưa xác định đạt.
- 7 nhóm kiểm tra HTTP/API thật trên LocalDB GUID riêng đạt: thiếu quyền, thiếu ghi nhận CSKH, hạn mới sai, không nhận xử lý đơn chưa quá hạn, đơn quá hạn vẫn xuất hiện, khách vẫn nhận có ưu tiên/hạn mới, khách hủy có một phiếu MOVE và tồn đúng vị trí, gửi lại không tạo trùng. Database thử tự dọn.
- Nạp trọn bộ 02 mới vào database thử thành công.
- Các quyết định khách trong kiểm thử chỉ thuộc database thử; không hủy hoặc ghi nhận khách vẫn nhận trên dữ liệu đang dùng.
- Đã mở trực tiếp đơn LM261023BULK000120 trên trang thật: vẫn thấy hạn cũ và nhãn Quá hạn · Chờ CSKH; kiểm tra cả hai lựa chọn trong hộp thoại, có hạn giao mới và vị trí CHO-XU-LY. Không bấm lưu quyết định khách trên dữ liệu đang dùng.
