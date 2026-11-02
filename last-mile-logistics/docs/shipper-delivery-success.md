# Chức năng 11 — Giao thành công, bằng chứng và COD

Cập nhật 30/10/2026, tiếp nối bước 10 Lộ trình. Các mục bổ sung về thời gian, tiền công, đền bù và ví thu nhập được theo dõi riêng, không đổi số của 11 bước hiện tại.

## Sử dụng

Nhiệm vụ → Đi giao → Giao thành công. Màn đọc lại nhiệm vụ hiện hành từ máy chủ, không dùng tên/COD cũ của thẻ làm kết quả giao.

1. Nhập tên người nhận thực tế; không tự lấy tên khách khi bỏ trống.
2. Đơn có COD: nhập số thực tế đã thu, xác nhận đã thu đủ. Thiếu/thừa tiền chưa được xác nhận thành công. Đơn không COD gửi 0 và không tạo khoản thu.
3. Xác nhận đã giao đủ kiện. Có thể chụp hoặc chọn ảnh JPEG/PNG tối đa 5 MB; ảnh được khuyến khích, không bắt buộc thêm ngoài quy tắc hiện có cho mọi đơn. Không có ảnh vẫn lưu xác nhận người nhận thực tế.
4. Ghi chú, rồi gửi. GPS nếu lấy được tọa độ đủ chính xác được làm tròn 6 số thập phân; không lấy được vẫn gửi nhưng không tự tạo vị trí.
5. Chỉ hiện hoàn tất sau khi đọc được biên nhận hợp lệ: đúng nhiệm vụ/đơn/tài xế, người nhận, số tiền, thời điểm máy chủ và bằng chứng. Có nút về danh sách hoặc xem COD cần nộp. Biên nhận đã xong không còn nút gửi lần nữa.

COD là tiền thu hộ phải nộp; không dùng khoản này làm thu nhập hay tiền công tài xế.

## Đồng bộ, quyền và mất kết nối

- JSON cũ vẫn được hỗ trợ; multipart cùng endpoint nhận ảnh. App luôn gửi assignmentId. Máy chủ kiểm tra quyền hiện tại, tài khoản/tài xế/bưu cục hoạt động và phân công mới nhất; không cho phân công cũ ghi vào nhiệm vụ khác.
- Lần giao, bằng chứng, COD, trạng thái và nhật ký lưu trong cùng giao dịch. Giữ quy tắc kết thúc phần giao của chuyến, hàng chờ trả kho cuối ca vẫn theo dõi riêng.
- Với assignmentId đã giao thành công, gửi lại trả biên nhận gốc; không tạo thêm lần giao/COD, không sửa người nhận hay thay ảnh. Gửi đồng thời cũng chỉ có một bộ dữ liệu. JSON cũ không có assignmentId vẫn giữ phản hồi xung đột khi gửi lặp để tương thích client cũ.
- GET `/api/v1/my/tasks/{assignmentId}/delivery-receipt` chỉ đọc, dùng để kiểm tra kết quả sau mất phản hồi. Không tự gửi lại lệnh ghi. Nếu kiểm tra cũng lỗi, khóa gửi và cho kiểm tra lại biên nhận. Chỉ khi máy chủ đọc lại được và đơn vẫn đang giao mới cho người dùng đối chiếu/gửi lại chủ động.
- Ảnh lưu riêng ngoài wwwroot, kiểm tra bằng bộ giải mã JPEG/PNG hiện có. Ảnh gắn đúng lần giao và mở qua API bằng chứng được phân quyền; admin xem được trên hồ sơ bằng chứng hiện có, tài xế khác không xem được.
- Lỗi trước commit và đã xác nhận rollback: dọn ảnh. Không xác định commit/rollback: giữ ảnh và trả kết quả chưa rõ, không xóa bằng chứng có thể đã được lưu. Upload thừa của một lần gửi trùng được dọn sau khi biết chắc kết quả.
- Số tiền và GPS multipart dùng định dạng dấu chấm bất kể máy chủ dùng vi-VN, tránh hiểu tọa độ thập phân thành số hàng nghìn.

## Kiểm chứng

- 13 kiểm tra mới của Flutter về biên nhận, COD thực thu, dữ liệu cũ, ảnh multipart, phiên/quyền sở hữu, đơn không COD, mất phản hồi, kiểm tra lại thất bại và bấm hai lần.
- 319 kiểm tra backend dùng kết nối giả lập: ảnh hợp lệ/hỏng/vượt giới hạn, lỗi trước commit/commit đã xong mất phản hồi, rollback chưa rõ, hủy, đọc hết kết quả trước commit, lỗi dọn file/dispose và upload trùng.
- 35 nhóm HTTP/SQL/SignalR trên API và database GUID thử: hai POST ảnh đồng thời tạo đúng một lần giao, ảnh, COD, nhật ký; số COD sai và ảnh không hợp lệ không lưu kết quả; admin/tài xế sở hữu tải được ảnh, tài xế khác bị chặn; bưu cục ngừng không ghi hoặc đọc lại biên nhận được. Các luồng kho, hoàn cuối ca và lộ trình giữ hồi quy.

Không cần migration cho riêng bước 11. Chạy lại backend Visual Studio profile http và Flutter để dùng bản mới. Kiểm thử không khởi động app/emulator hoặc sửa dữ liệu vận hành.
