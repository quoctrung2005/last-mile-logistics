# Danh sách bằng chứng rỗng

Ngày sửa: 29/10/2026.

Đã tái hiện bằng nguyên câu SQL của DeliveryEvidenceReadController trên đơn hoàn mẫu không có bằng chứng: JSON trả orderId, trackingNumber, page, pageSize, totalItems=0 nhưng thiếu items. Giao diện kiểm tra contract ở tracking.js từ chối phản hồi này và báo `evidence. items phải là mảng`.

Sửa projection items thành JSON_QUERY(COALESCE((... FOR JSON PATH, INCLUDE_NULL_VALUES), N'[]')). Danh sách rỗng và trang vượt cuối luôn có items: []; danh sách có dữ liệu giữ mảng object. Không đổi phân quyền, phạm vi đơn, nhánh chi tiết evidenceId hoặc nới validation frontend. Không tạo bằng chứng hay đường dẫn ảnh giả.

Kiểm chứng: build API Release với --no-restore -warnaserror, 0 lỗi/cảnh báo. Đọc SQL thật trên LocalDB cho bốn trường hợp: đơn không bằng chứng, đơn có bằng chứng, trang vượt cuối và lọc PHOTO không có kết quả; tất cả items đều là mảng đúng nội dung. Không ghi database. Chưa kiểm tra qua HTTP/JWT hoặc trình duyệt; API đang chạy cần khởi động lại từ mã đã sửa để nhận thay đổi.
