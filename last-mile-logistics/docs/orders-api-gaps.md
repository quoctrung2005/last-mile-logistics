# Quản lý đơn hàng — thiếu sót API và kiểm thử (07/10/2026)

> Cập nhật 09/10/2026: các nhận định dưới đây là lịch sử ngày 07/10. OrdersController hiện đã trả `version`, `senderId`, `receiverId`, `serviceId`, `pickupAddressId`, `deliveryAddressId` và `requiresAddressSelection`. Frontend đã cập nhật luồng sửa: địa chỉ không xác định được phải chọn lại, không khóa toàn bộ form hoặc đoán ID. Các GET của OrderFormController cho phép DONHANG_TAO hoặc DONHANG_CAPNHAT, giữ nguyên scope. Kết quả mới: [order-edit-ui-verification.md](order-edit-ui-verification.md).

Không sửa backend hoặc database trong lần triển khai này.

## Chi tiết thiếu version và ID phục vụ sửa

Endpoint `GET /api/v1/orders/{id}`, `OrdersController.GetOrder`, trả tên người gửi/nhận/dịch vụ và điểm giao nhận dạng snapshot nhưng không có `senderId`, `receiverId`, `serviceId`, `pickupAddressId`, `deliveryAddressId`, `version`. `deliveryPoints[].id` là ID **DiemGiaoNhan**, không phải ID địa chỉ khách hàng. Danh sách có version nhưng thiếu các ID khác. Không suy ID từ tên/chuỗi địa chỉ vì có thể trùng.

`PUT /api/v1/orders/{id}` yêu cầu toàn bộ CreateOrderRequest cộng `expectedVersion` Base64 của rowversion 8 byte. Hiện không thể điền đúng bản đang lưu hoặc gửi PUT hợp lệ. UI khóa sửa, ghi rõ thiếu dữ liệu. Không gửi PUT thật và không tuyên bố đã thấy 409 backend thật.

Đề xuất bổ sung vào response chi tiết, **tên field đề xuất** khớp payload hiện hữu:

```json
{
  "senderId": 1, "receiverId": 2, "serviceId": 1,
  "pickupAddressId": 10, "deliveryAddressId": 20,
  "version": "AAAAAAAAAAE="
}
```

Version lấy từ `DonHang.PhienBan` tại cùng lần đọc chi tiết, Base64 như response PUT; không tạo ở frontend. Cần lưu liên kết địa chỉ gốc với đơn/điểm giao nhận khi tạo, hoặc endpoint edit-context tương đương. Không JOIN lại theo chuỗi địa chỉ hay người liên hệ để đoán địa chỉ gốc; giữ snapshot và quan hệ gốc riêng. UI đã có đường sửa khi API trả đầy đủ contract này.

Thiếu serviceId ảnh hưởng báo giá đơn đã lưu. UI cho chọn dịch vụ muốn báo giá thủ công, hiển thị tên dịch vụ đơn; không coi lựa chọn này là cập nhật dịch vụ của đơn. Xác nhận luôn dùng dịch vụ lưu DB và phí backend. Bổ sung serviceId giúp quote dịch vụ hiện hành mà không chọn lại.

## Quyền đọc form không khớp quyền sửa

`GET /api/v1/order-form/options`, `GET /api/v1/customers`, `GET /api/v1/customers/{id}/addresses` đều kiểm tra `DONHANG_TAO`; PUT và confirm kiểm tra `DONHANG_CAPNHAT`. Seed BRANCH_MANAGER có quyền cập nhật nhưng không có quyền tạo. Do đó các GET form dự kiến trả 403 dù có quyền sửa. Kết luận từ source/seed, chưa gọi bằng tài khoản BRANCH_MANAGER thật.

Đề xuất cho phép quyền tạo **hoặc** cập nhật đọc các dữ liệu form; giữ scope và kiểm tra quyền POST/PUT riêng.

## API quyền hiện hành còn thiếu

`GET /api/v1/auth/me` chỉ có accountId, username, fullName, role, branchId. Login/token cũng không có quyền DB hiện hành. `/api/v1/roles` dành ADMIN có PHANQUYEN_QUANLY, không dùng cho mọi tài khoản.

UI đơn hàng dùng grant seed làm gợi ý và kiểm tra trạng thái/bưu cục; backend kiểm tra quyền DB mỗi thao tác. Nếu quyền DB tùy chỉnh, UI có thể hiển thị nút dẫn đến 403 hoặc chưa hiển thị nút vừa được cấp quyền. Đề xuất bổ sung danh sách mã `permissions` vào `/auth/me` hoặc API quyền cá nhân; đây chưa phải field hiện có. Màn hình kho mới chỉ dùng quyền được đọc thực tế qua `/roles` cho ADMIN có quyền đọc vai trò; nếu không xác minh được quyền thì ẩn thao tác ghi, xem `warehouse-api-gaps.md`.

`/api/v1/catalogs` chỉ dành ADMIN BUUCUC_QUANLY, không có trạng thái đơn. UI dùng `/order-form/options` cho bưu cục/dịch vụ và trạng thái đã đọc từ SQL seed. Nếu trạng thái/chuyển trạng thái được tùy chỉnh, cần endpoint phục vụ bộ lọc/action capabilities.

## Khung đăng nhập và CORS

`Program.cs` chưa CORS hoặc phục vụ frontend. Trang 5500 gọi thẳng 5038 khác origin. Đã thêm server frontend local proxy `/api/*` tới URL backend cố định, không log body/token và chỉ nghe loopback; config dùng URL tương đối. Không sửa Program.cs/nghiệp vụ.

## Kiểm thử và giới hạn

- Khởi động backend profile http ở 5038, frontend ở 5500.
- `GET /api/database/check` qua proxy: HTTP 200, đọc database thành công, có 14 đơn tại thời điểm kiểm tra; không sửa dữ liệu.
- `GET /api/v1/orders` không token: HTTP 401.
- `POST /api/v1/auth/login` tên kiểm tra không tồn tại: HTTP 401, thông báo đăng nhập không hợp lệ; không log mật khẩu/token.
- Không có tài khoản thử hay LASTMILE_TEST_USERNAME/LASTMILE_TEST_PASSWORD. **Chưa kiểm thử backend thật với token**: danh sách/tìm/lọc/phân trang, tạo/sửa/quote/confirm/cancel, refresh, quyền vai trò, xung đột version.
- Trước khi bỏ bộ test, 7/7 nhóm Playwright với API mô phỏng đã pass. Kết quả này không chứng minh các thao tác ghi trên backend thật hoạt động; phần sửa chỉ dùng contract đề xuất.
- Theo yêu cầu mới, đã xóa bộ test Playwright, phụ thuộc và ảnh kết quả, không chạy thêm test.
- Không thao tác ghi trên 14 đơn hiện có. Sửa cần bổ sung backend trước.
- Chưa đối chiếu Figma vì chưa có URL/fileKey/frame. Không làm kho, điều phối, thuật toán đường đi hoặc hosting.
