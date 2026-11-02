# Trang Nhân viên giao hàng — 10/10/2026

Đã thay placeholder tại `#/fleet/couriers`, thêm chi tiết `#/fleet/couriers/:id`. Sử dụng JavaScript/HTML/CSS thuần và Bootstrap hiện có. Giữ shell/header/sidebar TVD Logistics; CSS mới giới hạn dưới `.shippers-page`.

## File sản phẩm sửa/bổ sung

- `frontend/js/shippers.js` (mới): danh sách/lọc/phân trang, chi tiết, modal tạo/sửa, xác nhận trạng thái và quản lý phương tiện. Hủy request, chặn response cũ, dọn modal khi chuyển route.
- `frontend/js/router.js`: route, query `page/pageSize/keyword/branchId/isActive/availability`, quyền `TAIKHOAN_XEM` và URL chi tiết tải lại được.
- `frontend/js/app.js`: mount/destroy trang.
- `frontend/index.html`: tải module; cache version cho router/app/CSS.
- `frontend/assets/css/styles.css`: bảng cuộn ngang, cột thao tác cố định trên desktop, modal giới hạn chiều cao/cuộn và bố cục mobile.
- `backend/LastMile/LastMile.Api/Controllers/ShippersController.cs`: thêm lọc isActive, currentVehicle trên danh sách và assignmentId trong phương tiện; bảo đảm mảng items/areas rỗng là []. Giữ activeOnly hiện hữu và phạm vi tài khoản theo bưu cục.
- `AccountsController.cs`: thêm eligibleForShipper, kiểm tra trước COUNT/OFFSET: vai trò SHIPPER hoạt động, tài khoản ACTIVE không bị khóa tạm thời, có bưu cục hoạt động, chưa có hồ sơ shipper. Không thêm dữ liệu mật khẩu vào response.
- `VehiclesController.cs`: thêm assignableOnly trước COUNT/OFFSET: xe hoạt động, AVAILABLE, chưa được liên kết, không có phân công giao hàng/chuyến đang mở hoặc nhiệm vụ hoàn hàng. Giữ phạm vi hiện hữu; trả items=[] khi rỗng.
- `CatalogsController.cs`: cho người có TAIKHOAN_XEM đọc riêng AREAS/BRANCHES; ngoài ADMIN chỉ bưu cục của mình, từ chối branchId khác và thiếu bưu cục. ALL/WAREHOUSES/LOCATIONS/SERVICES vẫn dùng policy quản trị hiện có; không đổi quyền ghi danh mục. Chuẩn hóa mảng rỗng cho hai lookup.
- `ShipperCreateController.cs`, `ShipperUpdateController.cs`: giữ DTO/SQL nghiệp vụ; chỉ bảo đảm areas=[] khi rỗng.
- `DispatchAssignmentsController.cs`, `TripsController.cs`, `DispatchShippersController.cs`: giữ route/DTO/quyền/nghiệp vụ; chỉ sửa items=[] khi không có kết quả.

Không sửa AccountCreate/AccountUpdate/ShipperVehicle/VehicleSave và không thêm endpoint mới.

## API dùng

| API hiện có | Cách dùng |
| --- | --- |
| GET /api/v1/auth/permissions | Quyền hiện hành; không mặc định ADMIN hoặc mọi tài khoản đều được ghi |
| GET /api/v1/shippers | keyword/branchId/availability/page/pageSize; bổ sung isActive để lọc hoạt động hồ sơ riêng với accountStatus và availability |
| GET /api/v1/shippers?id={shipperId} | Tải đầy đủ trước sửa/đổi xe/xác nhận trạng thái; chi tiết lấy bằng ID |
| POST /api/v1/shippers | Liên kết AccountId của tài khoản SHIPPER có sẵn; IdentityNumber/LicenseNumber/LicenseExpiresAt/Areas theo DTO |
| PUT /api/v1/shippers/{id} | Sửa hồ sơ hoặc xác nhận IsActive, giữ Areas đầy đủ; không sửa tài khoản/bưu cục/trạng thái làm việc tùy ý |
| GET /api/v1/accounts?eligibleForShipper=true | Tìm/chọn tài khoản đủ điều kiện theo phạm vi, có phân trang thật |
| GET /api/v1/catalogs?type=BRANCHES | Bưu cục trong phạm vi; lọc danh sách gồm cả bưu cục ngừng hoạt động |
| GET /api/v1/catalogs?type=AREAS&activeOnly=true | Khu vực phụ trách thật từ danh mục |
| GET /api/v1/vehicles?assignableOnly=true | Chọn xe đủ điều kiện, có tìm kiếm/phân trang thật |
| PUT /api/v1/shippers/{id}/vehicle | VehicleId (null khi gỡ), ExpectedAssignmentId từ chi tiết mới tải và Notes bắt buộc |
| GET /api/v1/dispatch/assignments?shipperId={id}&activeOnly=true | Phân công đang mở, có phân trang; chỉ tải nếu có DIEUPHOI_GIAMSAT |
| GET /api/v1/trips?shipperId={id}&status=IN_PROGRESS | Chuyến theo shipperId, cho chọn enum trạng thái hiện có và phân trang; chỉ tải nếu có DIEUPHOI_GIAMSAT |
| GET /api/v1/dispatch/shippers?orderId={id} | Kiểm tra tương thích danh sách chọn shipper cho điều phối; không đổi nghiệp vụ chọn |

Quyền: đọc TAIKHOAN_XEM; tạo/sửa/trạng thái TAIKHOAN_QUANLY; đổi/gỡ xe còn yêu cầu ADMIN theo ShipperVehicleController, và frontend yêu cầu DIEUPHOI_GIAMSAT để đọc danh sách xe. Backend quyết định lại quyền/phạm vi mỗi thao tác.

ShipperCreate chỉ liên kết tài khoản đã có, không tạo tài khoản và không đặt mật khẩu mới. Họ tên/điện thoại/bưu cục lấy từ tài khoản; không gửi các trường đó trong DTO shipper. Có liên kết sang trang Tài khoản/Phương tiện hiện hữu. Nhân viên không được thay liên kết tài khoản hoặc bưu cục trong modal này. AccountUpdate hiện có chặn chuyển bưu cục khi có nhiệm vụ/chuyến/phân công xe.

Khác biệt trạng thái được trình bày thành ba cột/nhóm: accountStatus (ACTIVE/LOCKED/INACTIVE), isActive của hồ sơ, availability (AVAILABLE/DELIVERING/BREAK/OFFLINE). Ngừng hồ sơ qua API hiện có chuyển availability về OFFLINE, giữ trạng thái tài khoản. Kích hoạt lại phải thỏa điều kiện tài khoản SHIPPER và bưu cục hoạt động. Backend từ chối sửa/ngừng khi còn phân công, chuyến chưa kết thúc hoặc nhiệm vụ hoàn hàng; không tự hủy dữ liệu.

DTO hồ sơ không có version. Đổi xe có ExpectedAssignmentId và frontend gửi đúng giá trị từ GET mới tải. Validation theo DTO: CCCD tùy chọn nhưng khi nhập phải 12 chữ số, unique theo schema; bằng lái tối đa 50 ký tự với regex hiện có; ngày hết hạn cần số bằng lái và không trong quá khứ theo ngày UTC của backend; tối đa 100 khu vực, không trùng, tối đa một khu vực chính. Không xóa vật lý hồ sơ.

Không gọi API shipper nhận nhiệm vụ/lấy hàng/giao thành công bằng tài khoản quản trị; không sửa availability từ trang quản lý. Mọi phân công/chuyến tra bằng shipperId trên backend, không tải tất cả đơn để lọc theo tên.

## Kiểm tra đã chạy

- `dotnet build --no-restore`: đạt, 0 warning / 0 error.
- `npm.cmd test`: 26/26 đạt, gồm test auth/proxy/router cũ và route/query/quyền courier mới.
- `node frontend/tests/shippers-browser.cjs`: 49 kiểm tra đạt. Database thử CodexShippers_<GUID>, schema/seed gốc, ASP.NET API thật, proxy/API client thật, Edge headless. JWT thử dùng khóa ngẫu nhiên riêng; không dùng session/token/mật khẩu người dùng. Mọi ghi nằm trong database thử đã được xóa sau chạy; browser/API/profile thử cũng được dọn.

Đã chạy HTTP/SQL thật cho danh sách, tìm mã/tên/điện thoại, phân trang, bưu cục, availability, isActive/activeOnly; mảng rỗng; danh sách tài khoản đủ điều kiện; liên kết trùng bị 409; thêm hồ sơ/CCCD/khu vực chính; sửa hồ sơ; CCCD trùng tại trường; gán/đổi/gỡ xe; ExpectedAssignmentId cũ bị 409; ngừng/kích hoạt lại; nhân viên còn nhiệm vụ bị từ chối ngừng/gỡ xe; đọc ngoài bưu cục bị 403/404.

Browser kiểm tra tạo/sửa, dữ liệu đầy đủ khi sửa, account/branch không chỉnh tùy ý, bộ lọc đặt page=1, chi tiết tải lại thật và quay về giữ page/pageSize, truy vấn phân công/chuyến theo shipperId, xác nhận đúng mã/tên/tài khoản nhân viên, dọn modal. Người chỉ đọc không có nút ghi. Thu hồi TAIKHOAN_QUANLY của ADMIN trong database thử sau khi modal đã mở: PUT trả 403 thật, giữ form/phiên; reload route ẩn mọi nút ghi dù vẫn là ADMIN.

So sánh trạng thái/version tài khoản trước/sau ngừng hồ sơ: không đổi. So sánh số phân công/chuyến và toàn bộ điểm giao nhận của đơn trước/sau: không đổi. API chọn shipper điều phối vẫn trả ít nhất một ứng viên, ID shipper/xe hợp lệ, đúng bưu cục và totalItems khớp items. Không thực hiện phân công/giao nhận thay nhân viên.

Các lỗi/độ trễ tiêm có kiểm soát ở harness: PUT 400 có errors.IdentityNumber, PUT 500, lỗi mạng GET, trì hoãn POST để kiểm tra khóa nút và trì hoãn một GET thật bỏ qua abort để xác minh response cũ không ghi đè dữ liệu mới. Đây không phải sự cố hạ tầng thật; các thao tác thành công đều tới backend thật.

Viewport 1440px và 390px: không tràn ngang toàn trang; bảng cuộn trong khung, cột thao tác rộng hơn 230px; desktop cố định cột thao tác bên phải. Modal nằm trong viewport và có max-height/overflow khi dài. Đã mở ảnh QA để xem bố cục. Không có JavaScript exception hoặc unhandled rejection.

Bằng chứng: `shippers-verification.json`, `shippers-1440.png`, `shippers-390.png`, `shippers-modal-390.png`.

## Phần chưa thực hiện/kiểm tra

- Màn hình điều phối hiện vẫn là placeholder, không có form chọn shipper trong frontend. Đã kiểm tra API ứng viên thật, chưa thể kiểm thử chọn shipper trên giao diện điều phối. Không tuyên bố đã triển khai màn hình điều phối.
- Trang Tài khoản và Phương tiện hiện cũng là placeholder; liên kết dùng route hiện có. Đợt này không triển khai các trang đó hoặc tạo luồng mật khẩu riêng.
- Chưa kiểm thử hạ tầng production/TLS, tải lớn, deadlock/concurrency nhiều nhân viên, hoặc gây mất kết nối vật lý. Không kiểm thử đăng nhập bằng mật khẩu trong harness này.

## Chạy lại

```powershell
# Từ backend/LastMile/LastMile.Api
dotnet build --no-restore
# Từ thư mục last-mile-logistics
node frontend/tests/shippers-browser.cjs
# Từ frontend
npm.cmd test
```

Cần LocalDB/Edge khả dụng và quyền tạo/xóa database thử. Fixture chỉ chấp nhận LocalDB và tên CodexShippers_<GUID>. Có thể dùng SHIPPERS_QA_DLL để chỉ tới bản build khác. Khởi động lại backend đang chạy trong IDE và tải lại frontend để nhận thay đổi.
