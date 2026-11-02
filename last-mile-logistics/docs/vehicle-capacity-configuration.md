# Thông số phương tiện tự hiển thị theo loại — 10/10/2026

Theo yêu cầu mới nhất, form không nhập thủ công tải trọng và sức chứa. Cả hai ô chỉ đọc, tự hiển thị khi chọn loại xe và lấy cùng cấu hình backend dùng khi lưu.

Nguồn duy nhất: `backend/LastMile/LastMile.Api/appsettings.json`, mục `VehicleTypeCatalog.Types`; có thể chỉnh qua configuration provider của ASP.NET Core. JavaScript không có bảng thông số riêng.

| Mã | Loại | Tải trọng hàng kg | Sức chứa m³ | Trạng thái |
| --- | --- | --- | --- | --- |
| MOTORBIKE | Xe máy | 100 | 0,38 | Tham chiếu dữ liệu khởi tạo; cần xác nhận vận hành |
| TRUCK | Xe tải | 2.000 | 8 | Giá trị nghiệp vụ tạm; cần xác nhận vận hành |
| TRUCK_1_TON | Xe tải 1 tấn | 1.000 | 5 | Cần xác nhận với hồ sơ xe/vận hành |

100 kg/0,38 m³ tham chiếu mức lớn nhất của xe máy trong dữ liệu khởi tạo. Trước khi bổ sung xe tải đã đọc mã loại trong database vận hành: chỉ có MOTORBIKE với 5 xe. Hai loại xe tải được thêm theo yêu cầu người dùng. Mức 2.000 kg của TRUCK, 8 m³ và 5 m³ là cấu hình nghiệp vụ tạm; mức 1.000 kg theo tên loại xe tải 1 tấn được yêu cầu. Các mức không phải giới hạn pháp luật. Thể tích được cấu hình độc lập, không suy ra từ kg. Người phụ trách vận hành cần xác nhận trước khi dùng các mức tạm làm thông số thực tế. RequiresConfirmation/Source trong cấu hình và API ghi rõ điều này; form hiển thị ghi chú.

## Form thêm/sửa

- Thêm xe: chọn loại tự điền kg và m³; xóa lựa chọn xóa cả hai giá trị; bàn phím không sửa được hai ô.
- Sửa xe: tải và hiển thị thông số đã lưu. Khi chọn loại xe, áp dụng thông số cấu hình của loại được chọn. Chỉ sửa biển số/trạng thái mà không chọn lại loại sẽ giữ thông số cũ, tránh âm thầm đổi tải trọng đã lưu.
- Đổi loại/thông số vẫn bị backend từ chối khi xe còn phân công, chuyến chưa kết thúc hoặc nhiệm vụ hoàn hàng. Không sửa phương tiện trên phân công cũ và không hủy nhiệm vụ.
- Lỗi giữ modal, lựa chọn và thông số hiển thị; khóa nút lưu khi gửi. Modal được dọn khi chuyển trang; CSS giới hạn trong trang phương tiện.

## API

- GET `/api/v1/vehicles/types`: ba mã, nhãn tiếng Việt, thông số, nguồn/cờ xác nhận. Dùng quyền đọc/phạm vi thật của controller phương tiện.
- POST `/api/v1/vehicles`: thêm `useTypeCapacity` tùy chọn, mặc định false để tương thích caller cũ. Khi true, backend lấy kg/m³ từ cấu hình, cho phép bỏ hai trường số khỏi body và bỏ qua số giả mạo do client gửi. Loại không hợp lệ trả HTTP400 với `errors.VehicleType`. Khi false, giữ luồng thông số đã lưu hoặc riêng của caller cũ: phạm vi DECIMAL, độ chính xác, >0, giới hạn theo loại và lỗi theo trường vẫn kiểm tra.
- Dữ liệu legacy chưa có loại trong danh mục/vượt cấu hình được giữ nếu cả loại/kg/m³ không đổi; so sánh dưới khóa save. Chuyển sang loại hợp lệ với `useTypeCapacity=true` áp dụng thông số của loại đó, không đổi hàng loạt dữ liệu.
- GET `/api/v1/dispatch/shippers`: `vehicleId`, `excludedVehicles`/`eligibilityReason`; `items`/`totalItems` tiếp tục chỉ gồm ứng viên đủ điều kiện. Panel kiểm tra tải trên chi tiết xe dùng đơn chờ điều phối có phân trang và API này.

Điều phối vẫn dùng tải trọng/thể tích thực tế đã lưu, cộng tất cả đơn chưa kết thúc với đơn mới. Tái sử dụng UPDLOCK/HOLDLOCK trong transaction của DispatchAssignmentsController và kiểm tra lại trước khi lưu. Route Điều phối riêng vẫn là placeholder; không tuyên bố đã kiểm tra UI phân công tại route đó.

## Kết quả thực chạy

- Backend build: 0 lỗi, 0 cảnh báo.
- 78 kiểm tra phương tiện API/Edge đạt, 0 lỗi console. Có tự điền cả ba loại, ô chỉ đọc với bàn phím native, đổi/xóa loại, thêm/sửa lưu đúng preset, API bỏ trường số/giả mạo số, legacy, xe đang có nhiệm vụ, quyền và hai phân công đồng thời.
- 28 kiểm tra Node auth/router đạt.
- Kiểm tra desktop 1440px/mobile 390px; ảnh modal mobile ghi lại Xe tải 1 tấn với 1.000 kg/5 m³.

Script `frontend/tests/vehicles-browser.cjs` dùng Edge, API thật và LocalDB schema/seed trong database GUID riêng. Lượt này dùng cấu hình sản phẩm, không override m³. Có mô phỏng POST 400/500, lỗi mạng và độ trễ; validation, lưu thành công và đồng thời dùng API thật. API trực tiếp qua HTTP, không thao tác Swagger UI. Database/profile kiểm tra và build tạm được dọn, không ghi database vận hành và không dừng API đang mở trong IDE. Kết quả: `docs/vehicle-limits-verification.json`.

## File sửa trong lượt này

- `frontend/js/vehicles.js`: hai ô chỉ đọc, tự hiển thị theo lựa chọn, giữ thông số xe cũ, yêu cầu backend tính thông số theo loại.
- `frontend/assets/css/styles.css`: nền ô chỉ đọc, giới hạn trong modal phương tiện.
- `frontend/index.html`: phiên bản cache mới của module phương tiện.
- `backend/LastMile/LastMile.Api/appsettings.json`: cấu hình kg/m³ của ba loại.
- `backend/LastMile/LastMile.Api/Controllers/VehicleSaveController.cs`: UseTypeCapacity, tính thông số từ backend; giữ validation/caller cũ và kiểm tra nhiệm vụ.
- `frontend/tests/vehicles-browser.cjs`: kiểm tra tự hiển thị, API preset, tương thích và hồi quy.
- Tài liệu này, `docs/vehicle-limits-verification.json`, `docs/vehicles-*.png`: kết quả/ảnh thực chạy.
