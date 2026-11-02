# Kiểm tra sửa Hàng chờ điều phối — 17/10/2026

## Lỗi gốc và thay đổi

- Mã vận đơn dùng `white-space: nowrap` nhưng không có giới hạn ô/ellipsis; bảng tự chia cột nên mã dài lấn sang người nhận và nút Phân công xuống dòng. Bảng hàng chờ hiện dùng colgroup, table-layout cố định, mã có ellipsis và mở modal xem/sao chép đầy đủ. Không cắt chuỗi dữ liệu hoặc ID gửi API.
- Bộ lọc trước đây chiếm hai hàng lớn, thiếu Làm mới và không liên kết bưu cục/kho. Đã tách bộ lọc thêm, bổ sung Làm mới và tải kho qua `dispatch/options?branchId=...`; backend vẫn áp dụng phạm vi quyền hiện có. Tìm kiếm áp dụng tại backend và đặt page=1; Enter gửi cùng form.
- Checkbox tổng thiếu trạng thái chọn một phần; lựa chọn qua phân trang không được giải thích. Hiện chỉ chọn trong trang đang xem, bỏ chọn có thông báo khi đổi trang/bộ lọc. Làm mới đối chiếu lại các đơn hiển thị và khối lượng từ API. Map theo orderId thật loại bỏ cộng trùng.
- Nút Lập phương án giao đưa về bước chọn đơn, khiến người dùng phải thao tác lại; đã chuyển trực tiếp đến step=2 với các ID đã chọn. Tạo chuyến thủ công lấy kho từ đơn đang chọn, tránh dùng kho cũ của bản nháp tối ưu.
- Modal trước đây gộp shipper/xe vào cùng ô và chỉ tìm ứng viên bằng shipperId. Hiện chọn riêng shipper và vehicleId thực tế, hiển thị tải trọng/còn lại, lý do loại từ API và nút Hủy. Điều kiện phân công thủ công được lấy từ endpoint ứng viên, không suy diễn từ điều kiện chặt hơn của tối ưu tuyến.
- Phản hồi options khi danh mục rỗng có thể thiếu trường `warehouses`, gây KeyNotFoundException/HTTP 500. SQL hiện trả các mảng rỗng rõ ràng; không chuyển lỗi SQL/migration thành dữ liệu rỗng. EnsureSchema và bộ lọc exception tiếp tục trả 503 khi thiếu migration.
- Lỗi 409 giữ form/ghi chú, khóa xác nhận cả khi đổi shipper trong danh sách cũ; nút Cập nhật dữ liệu đọc lại điều kiện. Nếu đơn đã rời hàng chờ thì có nút đóng và tải lại danh sách. Không giả lập shipper nhận nhiệm vụ.
- Chuẩn hóa width/min-width/margin của khung Điều phối và logo; sidebar desktop khớp cột workspace, sidebar mobile mở bằng cơ chế hiện có. Không dùng overflow hidden để che lỗi bố cục. Chỉ phần bảng cuộn ngang khi không đủ chiều rộng.

## Nút và thao tác đã kiểm tra

| Thao tác | Kiểm tra thực tế |
| --- | --- |
| Tìm kiếm | Bấm nút với bưu cục, kho, khu vực, ưu tiên, hạn giao; request GET hàng chờ có đúng bộ lọc, đặt page 2 về 1 và bỏ lựa chọn có thông báo. |
| Enter trong ô mã | Gửi form tới API thật; từ khóa không tồn tại trả danh sách rỗng hợp lệ. |
| Làm mới | Gọi lại API theo bộ lọc đã áp dụng; giữ đơn còn hợp lệ trên trang, không cộng lặp khối lượng. |
| Chọn từng đơn | data-order bằng orderId; tổng 1 đơn/8 kg, checkbox tổng ở trạng thái chọn một phần. |
| Chọn tất cả | Chỉ hai đơn trên trang thử, tổng 16 kg; không chọn toàn bộ bốn kết quả. |
| Bỏ chọn | Xóa checkbox từng dòng, checked/indeterminate của tổng và đưa tổng về 0. |
| Phân trang Trước/Sau | Đọc trang API tương ứng; xóa lựa chọn trang cũ, thông báo phạm vi rõ ràng. |
| Xem/sao chép mã | Modal hiển thị toàn bộ mã dài và địa chỉ; Clipboard API ghi/đọc đúng `LM-AF1CEB7CB6124AACB8FAE10C974006BB`. |
| Phân công / Hủy | Đọc shipper/xe thực; Hủy không lưu; Xác nhận tạo phân công PENDING qua API cũ, đóng modal và tải lại hàng chờ. |
| Phân công lỗi 409 | Tạo một phân công cạnh tranh thực qua API sau khi mở modal; lần xác nhận cũ trả 409, giữ ghi chú, không đăng xuất; cập nhật điều kiện phát hiện đơn đã được phân công. |
| Lý do không đủ điều kiện | Đơn 30 kg và xe 15 kg hiển thị lý do vượt tải do API trả; danh mục lý do shipper và xe tách riêng. |
| Lập phương án giao | Không chọn thì disabled và có hướng dẫn; chọn ba đơn/23 kg chuyển thẳng đến chọn shipper/xe, reload vẫn giữ ID/kho. |
| Tính đề xuất / xác nhận | Preview không tạo phân công/chuyến; xác nhận mới lưu, kiểm tra lại rowversion/tải trọng/phân công trùng; retry idempotent và cạnh tranh 200/409. |
| Tạo chuyến thủ công | Không chọn thì disabled; chọn đơn mở form thật, POST tạo chuyến PLANNED và mở chi tiết; backend từ chối danh sách rỗng bằng 400. |
| Sidebar | Desktop mở/thu nhóm menu vẫn giữ header khớp sidebar; mobile mở logo/menu đủ trong viewport, đóng/Escape khôi phục tương tác. |

## Môi trường và bằng chứng

ASP.NET thật, proxy thật, Edge headless và LocalDB `CodexAdmin_<GUID>` riêng, dùng schema/seed/trigger thật. Không mock response phân công/định tuyến, không ghi vào database vận hành. Các database thử được xóa sau khi chạy. [Báo cáo máy đọc được](dispatch/dispatch-verification.json) chứa danh sách kiểm tra và thời điểm chạy cuối.

Kết quả bản mã cuối: **110 kiểm tra tích hợp đạt**, **0 lỗi JavaScript**, **0 lỗi backend ngoài dự kiến**; build backend **0 lỗi, 0 cảnh báo**. Unit test router/API client và frontend: **45/45 đạt**. Lệnh chạy: `npm.cmd test --prefix frontend` và `npm.cmd run test:dispatch --prefix frontend`.

Đã kiểm tra 1366px, 1920px và 390px ở zoom 100%: scrollWidth trang không vượt viewport; mã không đè sang ô kế; địa chỉ hai dòng; khu vực dài xuống dòng tự nhiên; nút Phân công không ngắt dòng. Sidebar mobile có ảnh riêng. Ảnh đã xem lại: [1366](dispatch/dispatch-queue-1366.png), [1920](dispatch/dispatch-queue-1920.png), [mobile](dispatch/dispatch-queue-390.png), [sidebar](dispatch/dispatch-queue-sidebar-390.png), [modal](dispatch/dispatch-manual-assignment-1366.png), [409](dispatch/dispatch-assignment-conflict-1366.png), [vượt tải](dispatch/dispatch-assignment-exclusions-390.png).

HTTP thực được kiểm tra: 400 khi dữ liệu sai/chuyến rỗng, 401 khi thiếu xác thực, 403 khi thiếu quyền, 409 khi có phân công cạnh tranh và dữ liệu đã đổi, 503 khi tạm ẩn bảng migration trong database thử. Khôi phục bảng và Thử lại mở được hàng chờ. Unit test API client kiểm tra riêng việc chỉ xử lý làm mới xác thực với 401 và giữ phiên khi gặp 400/403/409/503.

## File sửa

- `frontend/js/dispatch.js`, `frontend/assets/css/dispatch.css`.
- `backend/LastMile/LastMile.Api/Services/Routing/DispatchData.cs`.
- `backend/LastMile/LastMile.Api/Controllers/DispatchPlanningController.cs`, `DispatchShippersController.cs`.
- `frontend/tests/dispatch-checks.cjs`, `dispatch-fixture.ps1`, `dispatch-browser.cjs`.
- Tài liệu này, `docs/dispatch-implementation.md`, báo cáo JSON và ảnh trong `docs/dispatch/`.

Đã đọc router, API client, các controller hàng chờ/phân công/chuyến và service tối ưu. Router/API client không cần đổi mã; đã kiểm tra bằng unit test và các luồng trên trình duyệt.

## Còn bị chặn trong dữ liệu vận hành

Kiểm tra chỉ đọc `QLGiaoHangChangCuoi` xác nhận schema Điều phối hiện có, nhưng cả **4 kho hoạt động còn thiếu tọa độ**. Cần cung cấp tọa độ kho đã xác minh trước khi tính tuyến ở các kho này. Không tự lấy tọa độ bưu cục hoặc tạo tọa độ giả. Phân công thủ công và tạo chuyến nháp không cần bỏ điều kiện nghiệp vụ nào.

Chưa thử ghi/phân công bằng tài khoản và dữ liệu vận hành của người dùng; các kết quả thao tác ghi ở trên thuộc database thử riêng. Cần khởi động lại backend đang chạy để nạp mã mới, sau đó tải lại frontend.
