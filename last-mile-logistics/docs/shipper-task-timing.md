# Bảng bổ sung — Mục 1: Thời gian nhiệm vụ và hạn đến kho

Cập nhật 30/10/2026, thực hiện sau bước 11 Giao thành công/bằng chứng/COD. Lựa chọn đã chốt: **điều phối đặt hạn riêng khi phân công; chưa đặt thì không báo trễ**.

## Trên admin

- Điều phối → Hàng chờ → Phân công đơn: có ô Hạn đến kho lấy hàng, giờ Việt Nam, có thể để trống.
- Điều phối → Phân công: hiển thị hạn; nút Đặt hạn lấy hàng cho phân công PENDING/ACCEPTED, đơn ASSIGNED. Dùng được cả phân công thuộc chuyến sau khi lập tuyến.
- Có thể đặt, sửa hoặc bỏ hạn trước khi nhận kiện; thay đổi từ danh sách phải nhập lý do và lưu nhật ký giá trị trước/sau.
- Đổi người giao tạo phân công mới không tự lấy hạn của người cũ. Điều phối đặt lại cho phân công mới nếu cần.
- Hạn phải trong tương lai và không sau hạn giao nếu đơn có hạn giao. Hai cửa sổ sửa cùng lúc không ghi đè: giá trị đã thay đổi thì trả 409 để tải lại. Tài xế không sửa hạn.
- Sau khi nhận kiện/đơn không còn ở bước chờ lấy hàng, không sửa lịch để thay đổi lịch sử đúng/trễ hạn.

Không tự coi giờ xuất phát chuyến là hạn đến kho, không đặt một số phút mặc định khi người dùng chưa cấu hình, không tự hủy/chuyển hoàn đơn quá hạn.

## Trên app

Thông báo nhiệm vụ, thẻ chờ nhận/nhận tại kho, bản đồ đến kho khi có hạn và chi tiết nhiệm vụ hiển thị hạn cùng giờ địa phương. Chi tiết tách rõ:

| Mốc | Nguồn |
| --- | --- |
| Được phân công | Thời gian phân công máy chủ |
| Chấp nhận nhiệm vụ | Thời gian nhận nhiệm vụ máy chủ |
| Hạn đến lấy hàng | Hạn riêng điều phối đã đặt; không có thì Chưa đặt hạn |
| Nhận kiện thực tế | Phiếu nhận kiện đã xác nhận; không dùng giờ chấp nhận nhiệm vụ |
| Hạn giao | Hạn hiện có của đơn |
| Giao thành công | Lần giao SUCCESS của phân công |
| Yêu cầu hoàn / Chờ trả kho từ | Yêu cầu RETURN / lịch sử RETURNING |
| Kho nhận hoàn | Thời gian yêu cầu RETURN được kho hoàn tất; không dùng giờ kết thúc phân công |
| Kết thúc phân công | Mốc kết thúc công việc giao; khác với kho nhận kiện hoàn |

Đúng/trễ hạn lấy kiện tính bằng giờ nhận kiện thực tế khi đã có. Khi còn chờ lấy kiện, chỉ báo quá hạn sau hạn đã đặt. Chưa đặt hạn không báo trễ; phân công đã đóng hoặc đơn đã đi giao mà thiếu giờ nhận thực tế không tự tiếp tục tăng trễ. Đến trễ vẫn có thể xác nhận nhận kiện hợp lệ; không thay quy trình vận hành thành một khóa cứng.

## Dữ liệu và API

- Thêm một cột nullable `dbo.PhanCongGiaoHang.HanDenLayHang DATETIME2(0)`. Không điền hạn cho bản ghi cũ.
- POST phân công nhận pickupDueAt tùy chọn.
- PATCH `/api/v1/dispatch/assignments/{id}/pickup-deadline`: pickupDueAt nullable, expectedPickupDueAt nullable và reason bắt buộc. Kiểm tra quyền DIEUPHOI_PHANCONG, bưu cục, trạng thái, giá trị trước và khóa khi ghi; gửi cập nhật nhiệm vụ sau commit.
- Danh sách/chi tiết nhiệm vụ và phân công trả pickupDueAt. Đọc database chưa có cột vẫn trả null để không làm hỏng luồng cũ. Ghi hạn khi chưa chạy migration trả 503 và rollback phân công, không âm thầm bỏ hạn người dùng đã nhập.
- UTC lưu trên máy chủ; giao diện Việt Nam đổi múi giờ khi nhập/xem. Không dùng giờ đồng hồ điện thoại để ghi nhận sự kiện nhận/giao hàng.

## Áp dụng

Chạy duy nhất [migration bổ sung](../database/migrations/20261030_assignment_pickup_deadline.sql) trong database `QLGiaoHangChangCuoi` đang dùng. Script thêm một cột, chạy lại được, không xóa/nạp lại dữ liệu. Không chạy lại file khởi tạo hoặc dữ liệu mẫu để thêm cột này.

Sau đó Stop/chạy lại backend Visual Studio profile **http**, chạy lại Flutter và làm mới web. Chưa chạy migration vẫn sử dụng được bước giao thành công/ảnh/COD và đọc nhiệm vụ cũ, nhưng chưa lưu được hạn lấy hàng.

## Kiểm chứng

- Backend build 0 lỗi/0 cảnh báo; Flutter analyze không có vấn đề.
- Toàn bộ Flutter **196/196**, gồm 13 ca bước 11 và 6 ca về thời gian/hạn nhận/lịch sử kho nhận.
- **36 nhóm HTTP/SQL/SignalR**: đặt/sửa/bỏ hạn, đồng bộ list/detail, chặn tài xế sửa, từ chối giá trị cũ/quá khứ, không sửa sau nhận thực tế; nhận kiện trễ vẫn hợp lệ. Database thiếu cột vẫn đọc được; lệnh đặt hạn thiếu migration bị rollback. Migration chạy lặp trong fixture.
- **81 kiểm tra web** về điều phối/router/depot: gồm hai ca thao tác đặt/bỏ hạn, đổi giờ Việt Nam sang UTC và gửi giá trị cũ để chống ghi đè.
- **319 kiểm tra lỗi giao dịch/ảnh** của bước 11 tiếp tục là báo cáo riêng; không thay bằng bộ đếm các nhóm API.

API/database thử là GUID riêng và đã dọn. Không khởi động app/máy ảo, không chạy migration trên database vận hành thay người dùng.
