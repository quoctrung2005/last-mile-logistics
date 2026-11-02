# Cảnh báo nội dung đơn hàng chưa lưu

Áp dụng cho form tạo và sửa đơn trong `frontend/js/orders.js`. Không có thay đổi backend hoặc migration.

## Hành vi

- Chụp giá trị ban đầu sau khi tải options, điền khách hàng, địa chỉ, lịch giao và hàng hóa xong. Chỉ so sánh dữ liệu nhập, lựa chọn và các dòng hàng; kết quả báo giá, ô tìm khách hàng và DOM hiển thị không làm form bị đánh dấu đã sửa.
- Thay đổi thông tin chung, lịch giao, khách hàng, địa chỉ hoặc thêm/xóa/sửa hàng sẽ kích hoạt cảnh báo. Khôi phục toàn bộ giá trị ban đầu làm form trở lại trạng thái sạch.
- Quay lại, Đóng, menu, Back/Forward dùng `Router.setLeaveGuard`. Chọn ở lại giữ nguyên DOM và nội dung; Router phục hồi đúng vị trí history khi từ chối Back/Forward.
- Reload/đóng tab dùng `beforeunload` của trình duyệt. Nội dung và việc trình duyệt có hiển thị hộp thoại hay không do trình duyệt quyết định, thường cần người dùng tương tác trước đó.
- Trong lúc lưu, chặn điều hướng nội bộ với thông báo chờ kết quả, khóa gửi lặp và vẫn bảo vệ reload/đóng tab. Thành công tháo guard trước khi mở chi tiết đơn.
- Lỗi 400/409/500 giữ nội dung và trạng thái chưa lưu. Xung đột 409 khi sửa tiếp tục chặn gửi version cũ như trước. Lỗi có `resultUnknown` giữ bản nhập, chặn gửi lại và đưa nút kiểm tra danh sách đơn; không tự gửi lại request ghi.
- Đăng xuất vẫn đi qua kiểm tra rời trang hiện có; hết phiên vẫn đi thẳng đến đăng nhập theo luồng xác thực. Khi hủy màn hình, tháo listener riêng và disposer của guard; disposer cũ không xóa guard được màn hình mới đăng ký.

Hai script trong `frontend/index.html` được đổi query version để trình duyệt tải mã mới. Không cần thay đổi cấu hình.

## Kiểm tra đã chạy ngày 19/10/2026

Chạy trong thư mục `frontend`:

```powershell
npm.cmd test
npm.cmd run test:order-unsaved
```

- Bộ test frontend: **69/69 đạt**, gồm kiểm tra API, refresh/401 đồng thời, timeout và Router. Bổ sung kiểm tra từ chối Back/Forward giữ lịch sử, disposer cũ không xóa guard mới và luồng hết phiên bỏ qua guard cũ.
- Harness mới `tests/order-unsaved-browser.cjs`: **35 kiểm tra đạt**, không có lỗi console hoặc unhandled rejection. Chạy mã app/form/Router thật trong Edge headless với API giả lập cô lập, không kết nối database và không ghi đơn thật. Danh sách từng kiểm tra nằm trong `order-unsaved-verification.json`.
- Bao gồm form sạch sau tải, tìm khách/báo giá, các nhóm dữ liệu, thêm/xóa hàng, hủy/chấp nhận rời trang, Back/Forward, tạo/sửa thành công, lỗi 400/409/500, đang lưu, kết quả chưa xác định, đăng xuất/hết phiên và không còn cảnh báo dư.
- Có **3 hộp thoại beforeunload thật** qua giao thức DevTools: hủy reload giữ bản nhập, đồng ý reload trở lại form sạch, hủy đóng tab giữ tab. Các lần tương tác bàn phím/chuột dùng API Input của trình duyệt để kích hoạt cảnh báo native.

## Cách kiểm tra bằng giao diện

1. Mở Tạo đơn hoặc Sửa đơn, chờ tải xong rồi Quay lại: không hỏi bỏ dữ liệu.
2. Mở lại, sửa ghi chú/lịch giao, chọn khách/địa chỉ hoặc thêm/xóa/sửa hàng. Bấm Đóng, Quay lại, menu hoặc Back/Forward: chọn ở lại phải giữ nguyên bản nhập; đồng ý rời đi phải đến trang đã chọn.
3. Sửa dữ liệu rồi reload hoặc đóng tab sau khi đã tương tác với form: trình duyệt hỏi rời trang. Hủy phải giữ form; đồng ý reload phải bỏ bản nhập.
4. Lưu hợp lệ: mở chi tiết đơn mà không hỏi bỏ dữ liệu. Khi có lỗi lưu, nội dung vẫn ở form; 409 yêu cầu kiểm tra/tải dữ liệu mới. Khi đang lưu, chờ kết quả trước khi rời trang.
5. Rời form, mở màn hình khác rồi điều hướng/reload: không còn cảnh báo từ form cũ.

## Giới hạn kiểm chứng

Chưa thử luồng lưu với backend/database thật trong lần thay đổi này, chưa chạy lại build backend hoặc các harness SQL. Kết quả HTTP và trạng thái lỗi trong harness được giả lập; test client API hiện có chạy riêng bằng `npm.cmd test`. Chưa thử Chrome/Firefox/Safari, thiết bị di động hoặc đồng ý đóng tab thật; hành vi native thực tế đã kiểm tra trên Edge headless như mô tả ở trên.
