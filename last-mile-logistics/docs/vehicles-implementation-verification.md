# Trang Phương tiện — 10/10/2026

Đã triển khai `#/fleet/vehicles` và chi tiết `#/fleet/vehicles/:id`, thay placeholder. Giữ shell/header/sidebar TVD Logistics, JavaScript/HTML/CSS thuần và Bootstrap hiện có. CSS mới giới hạn trong `.vehicles-page`.

## File sản phẩm

- `frontend/js/vehicles.js` (mới): danh sách, bộ lọc, phân trang server, chi tiết, modal tạo/sửa/đổi trạng thái, chọn nhân viên để mở editor liên kết dùng chung, trạng thái tải/trống/lỗi, dọn modal/hủy request/chặn response cũ.
- `frontend/js/shippers.js`: xuất `VehicleLink` từ editor liên kết hiện có; hỗ trợ context/lifetime/refresh của trang Phương tiện và chọn trước một xe thực đã được API xác nhận đủ điều kiện. Trang Nhân viên giao hàng tiếp tục dùng chính editor này và cùng PUT.
- `frontend/js/router.js`: quyền đọc DIEUPHOI_GIAMSAT, route chi tiết, query page/pageSize/keyword/vehicleType/branchId/status và kiểm tra enum/ID.
- `frontend/js/app.js`: mount/destroy trang.
- `frontend/index.html`: tải module, cập nhật cache version.
- `frontend/assets/css/styles.css`: bảng desktop đủ cột trạng thái và thao tác, cuộn ngang trong khung trên mobile; modal vừa viewport/cuộn khi dài. Các kiểu editor liên kết dùng chung được giới hạn riêng dưới `.vehicles-page`.
- `backend/LastMile/LastMile.Api/Controllers/VehiclesController.cs`: thêm lọc vehicleType/branchId trước COUNT/OFFSET; bổ sung metadata bộ lọc khi includeFilterOptions=true, bưu cục nhân viên liên kết, mã nhân viên; assignmentHistory=[] khi trống; đếm PLANNED trong chuyến chưa kết thúc.
- `VehicleSaveController.cs`: giữ nguyên DTO và nghiệp vụ lưu; bổ sung field=licensePlate khi SQL báo unique constraint biển số để hiển thị đúng trường. Không đổi tên response, không thêm trạng thái hoặc endpoint.
- `DispatchAssignmentsController.cs`, `TripsController.cs`: thêm tham số GET vehicleId và predicate trong SQL trước phân trang, giữ tương thích truy vấn shipperId và quyền/phạm vi hiện có.

Không sửa ShipperVehicleController và không tạo endpoint trùng.

## API sử dụng

| API hiện có | Sử dụng / bổ sung |
| --- | --- |
| GET /api/v1/auth/permissions | Quyền hiện hành; không mặc định ADMIN được ghi |
| GET /api/v1/vehicles | keyword/status/page/pageSize hiện có; thêm vehicleType, branchId, includeFilterOptions=true |
| GET /api/v1/vehicles?id={id} | Thông tin đầy đủ, currentAssignment, lịch sử liên kết, số phân công/chuyến; đọc lại trước sửa/đổi trạng thái |
| POST /api/v1/vehicles | DTO SaveVehicleRequest, Id=null tạo mới, Id có giá trị cập nhật. Không tự đổi thành PUT |
| GET /api/v1/shippers?activeOnly=true | Chọn nhân viên đang hoạt động theo phạm vi, tìm kiếm/phân trang server; điều kiện nhiệm vụ/bằng lái được kiểm tra lại khi liên kết |
| GET /api/v1/shippers?id={shipperId} | Editor dùng chung tải lại nhân viên và currentVehicle.assignmentId |
| GET /api/v1/vehicles?assignableOnly=true | Editor dùng chung chỉ chọn xe đủ điều kiện; không lọc riêng một trang tại frontend |
| PUT /api/v1/shippers/{id}/vehicle | Editor dùng chung gửi VehicleId, ExpectedAssignmentId, Notes theo DTO hiện có |
| GET /api/v1/dispatch/assignments?vehicleId={id}&activeOnly=true | Phân công đang sử dụng xe, truy vấn bằng ID và phân trang server |
| GET /api/v1/trips?vehicleId={id}&status=IN_PROGRESS | Chuyến sử dụng xe, chọn enum trạng thái thật và phân trang server |
| GET /api/v1/dispatch/shippers?orderId={id} | Kiểm tra tương thích ứng viên shipper/vehicle của điều phối |

filterOptions.vehicleTypes lấy DISTINCT từ toàn bộ dữ liệu trong phạm vi, không chỉ trang đã lọc. filterOptions.branches lấy bưu cục trong phạm vi. Mặc định includeFilterOptions=false giữ response của picker hiện hữu; các trường mới là bổ sung.

PhuongTien không có MaBuuCuc. Bộ lọc/cột bưu cục ghi rõ là bưu cục của nhân viên đang liên kết qua PhanCongPhuongTien → NhanVienGiaoHang → TaiKhoan. Xe chưa liên kết không tự có bưu cục. Form không thêm bưu cục hoặc ghi chú vào hồ sơ xe; ghi chú chỉ có trong nghiệp vụ liên kết nơi schema thực sự lưu được.

## DTO, trạng thái và quyền

Form gửi Id, LicensePlate, VehicleType, MaxWeightKg, MaxVolumeM3, Status, IsActive đúng DTO. Mã XE do backend sinh. Không có version trong DTO/schema phương tiện; không tự thêm version. Liên kết xe gửi ExpectedAssignmentId theo API riêng.

Biển số bắt buộc, tối đa 20 ký tự, backend Trim/ToUpperInvariant và unique. Không áp regex biển số không có trong DTO. Loại bắt buộc, tối đa 30 ký tự, regex ASCII hiện có; không tự tạo enum loại xe. Tải trọng tối đa là khả năng chở hàng, đơn vị kg: 0.01–99999999.99, tối đa 2 chữ số thập phân. Sức chứa m³ tùy chọn: 0.001–9999999.999, tối đa 3 chữ số thập phân. Không nhầm với trọng lượng bản thân xe.

Danh sách hiển thị AVAILABLE/Sẵn sàng, IN_USE/Đang sử dụng, MAINTENANCE/Bảo trì, INACTIVE/Ngừng sử dụng. SaveVehicleRequest chỉ nhận AVAILABLE/MAINTENANCE/INACTIVE; form không gửi IN_USE. Trạng thái Đang sử dụng do nghiệp vụ giao hàng quản lý. Khi đổi trạng thái hoặc tạo xe ở trạng thái bảo trì/ngừng dùng, phải xác nhận rõ xe/trạng thái trong modal. IsActive=false đi cùng INACTIVE, các trạng thái lưu hoạt động khác dùng true theo backend.

Backend hiện từ chối mọi sửa hồ sơ khi xe còn phân công chưa kết thúc, chuyến PLANNED/ASSIGNED/ACCEPTED/IN_PROGRESS hoặc nhiệm vụ hoàn hàng. Bảo trì/ngừng dùng còn bị chặn khi có liên kết thường xuyên chưa kết thúc. Frontend giữ form và hiển thị lý do backend; không hủy phân công/chuyến, không sửa phương tiện trên các phân công cũ và không DELETE xe.

Đọc: DIEUPHOI_GIAMSAT, ngoài ADMIN chỉ xe đang liên kết với nhân viên cùng bưu cục. Tạo/sửa: ADMIN và TAIKHOAN_QUANLY. Editor liên kết còn cần TAIKHOAN_XEM để đọc hồ sơ nhân viên và DIEUPHOI_GIAMSAT để đọc xe. Mỗi API kiểm tra lại DB/quyền/phạm vi.

VehicleLink.openForShipper là cùng một editor dùng trên cả hai trang. Xe đã liên kết mở quản lý nhân viên hiện tại để đổi/gỡ xe; xe chưa liên kết chọn nhân viên rồi mở editor đó, có thông tin phương tiện hiện tại và xác nhận. Muốn chuyển xe sang nhân viên khác, phải gỡ liên kết cũ rõ ràng rồi liên kết mới; không tự làm hai PUT nối tiếp hoặc tự chuyển xe trên nhiệm vụ đã có.

Chi tiết tách liên kết thường xuyên khỏi nhân viên sử dụng xe trong từng phân công/chuyến. Hiển thị tối đa 10 liên kết gần nhất theo API. Không tạo lịch sử bảo trì, GPS hoặc số liệu mẫu; trang này không gọi vị trí nhân viên là GPS xe.

## Kiểm tra đã chạy

- Build thông thường gặp lỗi khóa apphost vì backend của người dùng đang chạy. Không dừng tiến trình đó. `dotnet build --no-restore -o .vehicles-qa-bin` đạt: **0 warning, 0 error**; API kiểm thử dùng chính bản build riêng.
- `npm.cmd test`: **28/28 đạt**, gồm auth/proxy/router cũ và route/query/quyền Phương tiện mới.
- `frontend/tests/vehicles-browser.cjs`: **54 kiểm tra đạt** với SQL Server LocalDB, ASP.NET API thật, proxy/API client thật và Edge headless trên database CodexVehicles_<GUID> riêng.
- Hồi quy `frontend/tests/shippers-browser.cjs`: **49 kiểm tra đạt** trên database CodexShippers_<GUID> riêng sau khi thay đổi editor dùng chung và filter API.

Harness JWT dùng khóa ngẫu nhiên riêng cho API/database thử, không dùng phiên của người dùng. Mọi ghi chỉ ở database thử, đã dọn database/API/browser/profile sau chạy. Không thay đổi dữ liệu database vận hành. Test và artifacts mới: `frontend/tests/vehicles-fixture.ps1`, `vehicles-browser.cjs`, cập nhật `router.test.cjs`; `docs/vehicles-verification.json`, `vehicles-1440.png`, `vehicles-390.png`, `vehicles-modal-390.png`.

Đã thực thi: danh sách, biển số/mã, loại, bưu cục liên kết, trạng thái; tổng và các trang không trùng; mảng rỗng; tải lại chi tiết thật và quay về giữ page/pageSize; DTO đầy đủ khi sửa; POST tạo/cập nhật và chuẩn hóa biển số/mã tự sinh; biển số trùng 409 tại trường; tải trọng ngoài phạm vi/độ chính xác sai; sức chứa m³ sai độ chính xác; xác nhận bảo trì/ngừng/kích hoạt; xe còn nhiệm vụ bị từ chối giảm tải trọng hoặc ngừng; xe còn liên kết bị từ chối bảo trì; gán/gỡ bằng cùng editor, hai trang đọc cùng liên kết; GET phân công/chuyến theo vehicleId.

Quyền: BRANCH_MANAGER chỉ đọc đúng phạm vi, lọc bưu cục ngoài phạm vi trả 403, ID xe ngoài phạm vi 404, POST bị 403. Thu hồi TAIKHOAN_QUANLY của ADMIN trong database thử sau khi modal đã mở: POST 403 thật, giữ form/phiên; tải lại route ẩn nút ghi dù vẫn ADMIN. Không có quyền và không tìm thấy được phân biệt riêng.

API điều phối vẫn trả ít nhất một ứng viên và vehicleId thật. Xe bảo trì bị loại khỏi picker assignableOnly. So sánh số phân công/chuyến và toàn bộ điểm giao nhận của đơn trước/sau: không đổi. Không thực hiện phân công/giao nhận thay nhân viên.

Lỗi có kiểm soát ở harness: POST 400 có errors.LicensePlate, POST 500, lỗi mạng GET, trì hoãn POST và một GET thật bỏ qua abort. Đã kiểm tra khóa nút, giữ form/phiên, lỗi theo trường, retry và response cũ không ghi đè kết quả mới. Đây không phải sự cố mạng/SQL hạ tầng thật; các thao tác thành công luôn tới backend thật.

QA 1440px và 390px: không tràn ngang toàn trang; cột thao tác 225px, bảng cuộn trong khung; cột trạng thái desktop không bị cột thao tác che. Modal vừa viewport, CSS có cuộn khi dài. Đã mở ảnh để xem lại bố cục. Không có JavaScript exception hoặc unhandled rejection.

## Giới hạn còn lại

- Màn hình điều phối vẫn là placeholder. Đã kiểm tra API ứng viên/vehicleId thật, chưa thể kiểm thử chọn phương tiện trên giao diện điều phối và không tuyên bố đã triển khai trang đó.
- Chưa kiểm thử tải lớn, deadlock/concurrency nhiều nhân viên, mất mạng vật lý hoặc hạ tầng production/TLS. Không kiểm thử đăng nhập bằng mật khẩu trong harness này.
- Backend đang chạy cần khởi động lại/build lại trong IDE để nhận controller mới; tải lại frontend. Không dừng server của người dùng trong phiên triển khai.

## Chạy lại

```powershell
# Từ backend/LastMile/LastMile.Api, khi backend đang chạy giữ khóa bin
dotnet build --no-restore -o .vehicles-qa-bin
# Từ thư mục last-mile-logistics
$env:VEHICLES_QA_DLL = 'D:\DA_CN_logistics\last-mile-logistics\backend\LastMile\LastMile.Api\.vehicles-qa-bin\LastMile.Api.dll'
node frontend/tests/vehicles-browser.cjs
$env:SHIPPERS_QA_DLL = $env:VEHICLES_QA_DLL
node frontend/tests/shippers-browser.cjs
# Từ frontend
npm.cmd test
```

Fixture yêu cầu LocalDB/Edge và quyền tạo/xóa database thử. Chỉ chấp nhận LocalDB và tên CodexVehicles_<GUID>. Nếu backend đã dừng, có thể build bình thường và bỏ VEHICLES_QA_DLL/SHIPPERS_QA_DLL để dùng bin/Debug/net10.0. Thư mục build/profile thử của phiên này đã được dọn, cần build lại trước khi chạy harness.
