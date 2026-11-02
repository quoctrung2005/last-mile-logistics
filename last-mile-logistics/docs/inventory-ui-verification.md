# Tồn kho — kiểm tra ngày 08/10/2026

## Thay đổi

Giữ JavaScript/HTML/CSS thuần + Bootstrap, sidebar cây và API client/refresh token. Tồn kho chỉ giữ tiêu đề của shell, bỏ tiêu đề/khung lồng và cảnh báo backend chưa hỗ trợ. Thanh thao tác dùng trang Nhập kho và Xuất kho / bàn giao hiện có, nhớ kho trong bộ nhớ theo tài khoản. Không thêm form danh mục, nút xóa tồn kho/đơn/giao dịch hoặc hủy giao dịch nhập.

Bảng bảy cột có mã đơn/vận đơn chung ô, ellipsis, xem đầy đủ trong title/chi tiết và sao chép. Dữ liệu tạo bằng textContent/text node. Lọc kho/vị trí/trạng thái/từ khóa trước phân trang; số dòng ở footer. AbortController + epoch + sequence ngăn response cũ ghi đè. Danh sách items:[] hợp lệ hiển thị “Không có hàng phù hợp”; thiếu kho, loading, lỗi/thử lại hiển thị riêng. 401 về đăng nhập sau cơ chế refresh; 403 khóa/ẩn thao tác; 409 tải lại và khóa xác nhận cũ; 500 thông báo dễ hiểu.

Đã đọc route/DTO/SQL của Warehouses, WarehouseInbound, WarehouseMove, WarehouseOutbound, WarehouseTransactions và OrderReadyForDispatch. Endpoint ready có sẵn, không sửa controller này. Bổ sung nhỏ trong WarehousesController để nhận locationId/orderStatus; AuthController thêm GET quyền cá nhân vì API vai trò chỉ cho admin. Schema quy định UTC và inbound/move dùng SYSUTCDATETIME, nên sử dụng hàm date chung đổi sang giờ Việt Nam.

Không có AGENTS.md trong workspace/dự án hoặc D:\; AGENTS.md toàn cục tại C:\Users\trung\.codex trống. Workspace không có Git metadata, không thể cung cấp git diff/status.

## Môi trường và kết quả

Backend build net10.0: 0 warning, 0 error. node --check cho warehouse.js, app.js, auth.js đạt.

Regression dùng ASP.NET Core thật, LocalDB SQL Server thật, JWT cấp bằng auth/login, frontend qua proxy thật, Edge headless ở 1440×1000 và 390×844. Database thử CodexInventory_<GUID> được tạo riêng từ schema/seed dự án, thêm fixture đủ điểm giao nhận/hàng hóa qua đúng chuỗi trạng thái; không tắt trigger. Tất cả POST/đổi quyền/mật khẩu thử chỉ chạy vào database này. Không cài thư viện, sửa node_modules hoặc mở thêm server trùng cổng. Các server kiểm thử được dừng và database thử được xóa sau kiểm tra.

| Kiểm tra | Kết quả |
| --- | --- |
| Kho/vị trí theo scope, trạng thái + vị trí trước phân trang, keyword, page/pageSize | Đạt bằng HTTP thật và UI |
| Chưa chọn kho, 14 dòng tồn, lọc rỗng trả items:[], lọc/xóa về trang 1, số dòng giữ kho | Đạt |
| Một tiêu đề, bảy cột, mã dài rút gọn, nhập kho UTC 00:30 → VN 07:30 | Đạt; xem ảnh desktop/màn hình hẹp |
| Bộ lọc xuống hai cột, bảng cuộn ngang, trang không tràn ngang ở 390px | Đạt |
| Đổi kho nhanh, xóa vị trí cũ, bỏ response cũ | Đạt; trì hoãn response thật trong trình duyệt, không bịa dữ liệu |
| Chi tiết đơn, chuyển vị trí POST move, lịch sử đúng kho/orderId, chi tiết giao dịch | Đạt qua UI thật |
| ready không body, xác nhận, success cập nhật WAITING_ASSIGNMENT, hàng vẫn STORED | Đạt |
| Bấm gửi hai lần | Chỉ một POST |
| ready bị thay đổi đồng thời | 409 thật, reload, xác nhận cũ khóa, không gửi lại |
| Tài khoản thiếu quyền và thu hồi quyền khi modal đang mở | 403 thật, nút ghi ẩn, yêu cầu bị khóa |
| Nhân viên kho có quyền hiện hành | Có nút nhập/xuất/move/ready phù hợp, không suy từ role |
| Token access sai, refresh hợp lệ; cả hai token sai | Refresh phục hồi; hết phiên về đăng nhập |
| 500 và thử lại | Tiêm lỗi 500 có kiểm soát để xác minh UI; thông báo không lộ chi tiết kỹ thuật, retry lấy lại dữ liệu thật |
| Nhập kho và xuất/bàn giao | POST thành công qua modal hiện có; phân công và shipper accept bằng API thật/tài khoản shipper thử; đơn HANDED_OVER rời danh sách tồn kho |
| Điều hướng nhập/xuất từ Tồn kho | Giữ kho đang chọn |
| Lỗi JavaScript không bắt được | Không có trong Edge |
| Sao chép và dữ liệu chứa HTML | writeText nhận đúng mã đầy đủ và trả thành công; fixture có mã dạng img/onerror vẫn là text, không tạo img; khi tiêm lỗi clipboard, modal thủ công chứa mã đầy đủ |

## Giới hạn

Không chạy POST trên database vận hành hoặc phiên đăng nhập thực của người dùng. Không tạo sự cố SQL/500 thực, không kiểm tra mất mạng giữa lúc commit hoặc deadlock đồng thời. Clipboard API được kiểm tra lời gọi/tham số và fallback; chưa xác nhận nội dung clipboard Windows bằng thao tác dán vì readback trong Edge headless trả rỗng. Nhập hàng hoàn không thuộc thay đổi lần này và chưa chạy POST return-in trong lần kiểm tra này. Hủy giao dịch nhập sai vẫn ngoài phạm vi; không có nút giả. Chức năng sửa đơn tiếp tục dùng trang Đơn hàng hiện có và điều kiện NEW/quyền của nghiệp vụ đó.
