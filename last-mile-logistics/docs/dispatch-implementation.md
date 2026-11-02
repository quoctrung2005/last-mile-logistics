# Điều phối TVĐ Logistics — 17/10/2026

## Kết quả triển khai

Bốn trang HTML/CSS/JavaScript và Bootstrap đã được nối với API thật: Hàng chờ, Phân công, Chuyến giao, Tối ưu tuyến. Giữ sidebar cây, trắng/cam và các thay đổi trước đó của trang Theo dõi. Route dùng quyền đang có trong database; Tổng quan chỉ active khi đúng route Tổng quan.

Hàng chờ chọn tối đa 60 đơn **trên trang đang xem**, checkbox đầu bảng có trạng thái chọn một phần. Đổi bộ lọc hoặc trang sẽ bỏ lựa chọn và thông báo rõ; Làm mới giữ bộ lọc đã áp dụng, chỉ giữ các đơn còn đủ điều kiện trên trang và cập nhật lại khối lượng từ API. Chuyển thẳng sang bước chọn shipper/xe và tải lại bước này vẫn giữ các ID đã chọn. Không lưu thông tin người nhận vào sessionStorage. Phân công đơn lẻ, đổi/hủy phân công, tạo/sửa/hủy chuyến gọi lại API cũ. Phân công gắn chuyến chỉ có liên kết Mở chuyến, không chỉnh riêng. Các nút nhận/bắt đầu/hoàn tất chuyến không xuất hiện cho nhân viên văn phòng; backend vẫn dành các action này cho shipper và giữ điều kiện kho bàn giao.

Bảng hàng chờ dùng colgroup và table-layout cố định. Nhấn mã vận đơn để xem đầy đủ/sao chép mã và địa chỉ trong modal; chuỗi thực khi gọi API không đổi. Bộ lọc chính gồm mã, bưu cục, kho, Tìm kiếm, Làm mới; các bộ lọc còn lại nằm trong “Bộ lọc thêm”. Đổi bưu cục tải lại danh mục kho từ API và xóa kho không còn phù hợp. API options luôn trả mảng, kể cả khi phạm vi không có kho. Modal phân công tách shipper/phương tiện, hiển thị tải trọng còn lại và lý do loại từ API; lỗi 409 giữ ghi chú và yêu cầu cập nhật dữ liệu trước khi xác nhận lại.

Tối ưu tuyến có ba bước, xem đề xuất trước khi xác nhận. Danh sách tuyến dùng chữ A/B/... và màu; bản đồ vẽ hình học cạnh đường OSM, điểm giao có chữ tuyến và số thứ tự. Các điểm trùng tọa độ được dàn biểu tượng cạnh nhau, không sửa tọa độ. Có lý do chưa xếp được, cảnh báo dữ liệu, mục Cách tính và tùy chọn nâng cao. Chỉnh thứ tự/chuyển đơn làm phương án mất trạng thái hợp lệ và khóa xác nhận cho đến khi backend kiểm tra lại.

## Những phần đã kiểm tra trước khi thay đổi

- `DispatchOrdersController`, `DispatchAssignmentsController`, `DispatchShippersController`, `TripsController`, `TripActionsController`, `TripOptimizationController`.
- Nhiệm vụ shipper, nhận chuyến, kho xuất/bàn giao, nhân viên, phương tiện, phân xe, khu vực phục vụ và danh mục loại xe.
- Schema V5, trigger trạng thái/tổng khối lượng/tải trọng/một chuyến hoạt động, unique index một phân công hiện hành; `sp_ChuyenTrangThaiDonHang` và các stored procedure giao thành công/thất bại.
- Ban đầu frontend Điều phối là placeholder. Endpoint tối ưu dùng nearest-neighbor với `geography.STDistance`, không có đồ thị đường hoặc VRP nhiều xe. Giá trị `NEAREST_NEIGHBOR` mà endpoint cũ định lưu còn không thuộc CHECK constraint phương pháp của schema V5. Phần này đã được thay bằng service định tuyến/VRP thực sự.

## Thuật toán và nguồn mạng đường

Mã C# thực hiện **Dijkstra** với priority queue trên đồ thị có hướng, trọng số chiều dài không âm. Cạnh là hai nút liên tiếp của một OSM way; chiều dài hình học của từng cạnh được cộng dọc đường đi. Không dùng khoảng cách trực tiếp giữa đơn làm ma trận đường bộ, không gọi một dịch vụ định tuyến để thay cho thuật toán trong dự án.

Ma trận theo từng profile `motorcycle` / `hgv` lấy từ Dijkstra. Cùng nút nguồn và cùng profile được tái sử dụng trong một lần tính. Đồ thị được nạp một lần, khóa phiên bản bằng SHA-256; thay file cần khởi động lại API. Mọi preview sau khởi động lại phải dùng đúng phiên bản đồ thị khi xác nhận.

VRP dùng **priority/deadline ordered cheapest feasible insertion**, cải thiện **2-opt** trong tuyến và **relocation** giữa tuyến. Đây là heuristic, không bảo đảm tối ưu toàn cục, không bảo đảm tìm được mọi nghiệm khả thi. Tối đa 60 đơn, 15 shipper; tính tối đa 20 giây, cải thiện tối đa 2,5 giây/8 lượt, giữ phương án khả thi gần nhất khi hết giai đoạn cải thiện. Ma trận không dùng khoảng cách chim bay giữa địa chỉ.

Snapshot kèm mã nguồn:

- `backend/LastMile/LastMile.Api/Data/roads.osm.gz` (~3,8 MB).
- [Metadata và truy vấn nguồn](../backend/LastMile/LastMile.Api/Data/roads.osm.metadata.json).
- Nguồn: OpenStreetMap qua Overpass API; dữ liệu gốc có attribution **© OpenStreetMap contributors**, [ODbL/copyright](https://www.openstreetmap.org/copyright).
- Bbox truy vấn: nam `10.70`, tây `106.56`, bắc `10.85`, đông `106.69`, chọn vùng Bình Tân–Tân Phú–Quận 6. Way và thành viên relation được tải đầy đủ nên một số nút nằm ngoài bbox truy vấn; không tuyên bố phủ toàn TP.HCM.
- Thời điểm dữ liệu OSM: `2026-10-17T08:52:51Z`.
- SHA-256 gzip: `01bf08232f96ea56deafa3c8f3c216ac55f15884787c73d308c552fda19ba419`.
- 185.484 nút; 699.837 cạnh tổng của hai profile sau lọc. Số cạnh này không phải số tuyến đường duy nhất.

Chuẩn bị lại từ dữ liệu công khai:

```powershell
python tools/prepare_roads.py --download
# Hoặc cùng định dạng dữ liệu được cung cấp độc lập:
python tools/prepare_roads.py --input D:/maps/verified-area.osm
```

Truy vấn, thời điểm OSM và hash được lưu cùng snapshot. Tải lại sau này có thể có dữ liệu mới; dùng file có hash ở trên để tái lập chính xác kết quả của bản bàn giao. Script chỉ tải mạng đường công khai, không gửi địa chỉ/đơn/shipper ra dịch vụ ngoài.

Quy tắc import theo [OSM XML](https://wiki.openstreetmap.org/wiki/OSM_XML), [oneway](https://wiki.openstreetmap.org/wiki/Key:oneway) và [access](https://wiki.openstreetmap.org/wiki/Key:access):

- Xét chiều way, `oneway=yes/-1/no`, vòng xuyến, `oneway:<profile>` và quyền `access/vehicle/motor_vehicle/motorcycle/hgv` được gắn trong dữ liệu.
- Loại đường không dành cho cơ giới, hạn chế tiếp cận không rõ, nút barrier hạn chế. Xe máy không mặc định đi motorway. Loại xe chưa ánh xạ profile không được giả lập đường đi.
- **Giới hạn có chủ ý:** chưa triển khai turn-state routing đầy đủ. Way tham gia relation cấm rẽ và way có điều kiện thời gian chưa hỗ trợ được loại bảo thủ, thay vì cho phép lượt rẽ sai. Snapshot hiện loại 1.501 way vì nhóm quy tắc này. Xe tải cũng loại đoạn có hạn chế kích thước/trọng lượng khi chưa có thông số xe cần để chứng minh đi được. Không phải hệ thống dẫn đường đủ điều kiện giao thông thực tế.
- Snap vào nút có cạnh đi được trong tối đa 200m (`Routing:MaxSnapMeters`, giới hạn cấu hình 10–500m). Kho/điểm ngoài phạm vi hoặc không có đường có hướng tới nhau được báo rõ. Không thêm đường nối giả. Popup và kết quả có khoảng cách snap; km/phút **không gồm đoạn tiếp cận** từ địa chỉ tới nút đường.
- Dijkstra tối thiểu hóa chiều dài, thời gian tính trên đường được chọn. Dùng `maxspeed` khi đọc được, giới hạn bởi tốc độ giả định: đường service/living_street 12 km/h, residential 20, còn lại xe máy 30/xe tải 25. Không có giao thông trực tiếp. Mỗi chặng làm tròn lên phút để thống nhất với cột phút của schema hiện có.

## Ràng buộc và xác nhận

Khối lượng và thể tích đọc lại từ SQL. Thể tích thiếu kích thước hoặc thiếu chi tiết được giữ là **không biết**, không quy về 0. Xe có giới hạn m³ không nhận đơn thiếu kích thước; xe chưa có giới hạn m³ có cảnh báo không kết luận đủ thể tích. Kiểm tra nhân viên/tài khoản/vai trò/xe đang hoạt động, giấy phép theo ngày xuất phát, quan hệ phân xe hiện hành, khu vực shipper và khu vực bưu cục đang hoạt động.

Không có lịch kết thúc nhiệm vụ chắc chắn trong dữ liệu hiện có, nên shipper/xe có nhiệm vụ hoặc chuyến chưa kết thúc bị loại bảo thủ khỏi kế hoạch mới, kể cả khi xuất phát trong tương lai. Không giả định nhiệm vụ hiện tại sẽ tự kết thúc. `ThoiGianSanSang` phải không muộn hơn xuất phát. Theo quy tắc cập nhật 19/10/2026, `ThoiGianYeuCauGiao` là giờ sớm nhất bắt đầu giao và `ThoiGianDuKienGiao` là giờ muộn nhất bắt đầu giao. Đến sớm thì chờ, rồi cộng phục vụ và dùng giờ rời để tính điểm tiếp theo. Giờ trống không được tự tạo; giờ sẵn sàng ở kho không phải cửa sổ giao. Cùng evaluator kiểm tra cheapest insertion, 2-opt, relocation, tuyến thủ công và xác nhận. Xem [khung giờ VRP và kiểm chứng](vrp-delivery-windows.md).

Preview chỉ lưu bản đề xuất riêng trong `DispatchRoutePlan`, hết hạn sau 15 phút; không đổi trạng thái đơn, không tạo chuyến/phân công. Confirm chỉ nhận plan ID. Backend dùng dữ liệu đề xuất đã lưu, đọc và kiểm tra lại dữ liệu/rowversion/quyền/mạng đường, rồi kiểm tra lại thứ tự và tổng bằng cùng engine. Không tin tổng kg, km hoặc thứ tự trong body tự gửi.

Xác nhận dùng serializable transaction, application lock, khóa đơn/tồn kho/xe/phân xe/nhân viên và unique index hiện có. Phương án cạnh tranh hoặc dữ liệu thay đổi trả **409**. Retry cùng plan ID trả lại kết quả đã xác nhận, không tạo trùng. Tạo chuyến `ASSIGNED`, phân công `PENDING`, gọi stored procedure chuyển trạng thái; không tự nhận nhiệm vụ, không bàn giao kho, không bắt đầu giao. Lưu geometry đúng phiên bản để xem lại chuyến. Chỉ chuyến `PLANNED` chưa có lịch sử phân công được tính lại/cập nhật qua luồng tối ưu; không ghi đè tuyến của chuyến đã nhận/đang đi.

## API

Tái sử dụng:

| API | Vai trò |
| --- | --- |
| `GET /api/v1/dispatch/orders` | Hàng chờ đủ điều kiện; thêm areaId, priority, deadlineDate và ids (tối đa 60 ID để khôi phục lựa chọn) |
| `GET /api/v1/dispatch/shippers` | Ứng viên phân công; thêm assignmentId để đổi phân công đơn lẻ hợp lệ, trừ tải của phân công đang đổi |
| `GET/POST /api/v1/dispatch/assignments` | Danh sách/tạo phân công đơn lẻ |
| `POST /api/v1/dispatch/assignments/{id}/cancel,reassign` | Hủy/đổi theo nghiệp vụ cũ |
| `GET/POST /api/v1/trips`, `PUT /api/v1/trips/{id}` | Đọc/tạo/sửa chuyến; GET thêm fromDate/toDate theo ngày Việt Nam của giờ dự kiến, fallback ngày tạo |
| `POST /api/v1/trips/{id}/actions` | Giữ nguyên quyền và điều kiện nhận/bắt đầu/hoàn tất/hủy |
| `POST /api/v1/trips/{id}/optimize` | **Đổi hành vi cũ:** tạo preview Dijkstra/VRP của chuyến nháp; không ghi trực tiếp. Nhận shipperIds (đúng một), departureAt, serviceMinutesPerStop, returnToBranch; xác nhận qua plan ID |

API bổ sung cho chức năng trước đây chưa có:

| API | Vai trò |
| --- | --- |
| `GET /api/v1/dispatch/options` | Tên bưu cục/kho/khu vực/shipper/xe và lý do loại, trạng thái mạng đường; theo quyền/phạm vi; branchId tùy chọn để tải kho phù hợp |
| `POST /api/v1/dispatch/plans` | Preview nhiều xe hoặc đánh giá lại ManualRoutes |
| `GET /api/v1/dispatch/plans/{guid}` | Khôi phục đề xuất của chính người lập |
| `POST /api/v1/dispatch/plans/{guid}/confirm` | Kiểm tra lại và lưu transaction/idempotent |
| `GET /api/v1/trips/{id}/route` | Object `{route: ...}` theo quyền xem chuyến; `route: null` nếu chuyến chỉ có thứ tự thủ công, tương thích yêu cầu object của API client |

Preview cần `DIEUPHOI_GOMDON` + `DIEUPHOI_TOIUUTUYEN`; confirm thêm `DIEUPHOI_PHANCONG`. Không cấp thêm quyền/vai trò trong migration. Các endpoint cũ tiếp tục kiểm tra quyền riêng của chúng.

## Cài đặt trên database hiện có

**Đã áp dụng migration vào database Development `QLGiaoHangChangCuoi` trên `(localdb)\MSSQLLocalDB` ngày 17/10/2026.** Đã kiểm tra đủ schema và chạy lại migration thành công; số bản ghi tài khoản/kho/đơn/chuyến trước và sau lần lượt giữ nguyên 16/4/16/3. Chưa điền tọa độ kho: cả 4 kho còn thiếu tọa độ. [Kết quả kiểm tra database](dispatch/migration-verification.json). Các kiểm thử tích hợp bên dưới vẫn chỉ dùng database GUID riêng và tự xóa.

Nếu Visual Studio đang dừng tại exception cũ trong `EnsureSchema`, bấm **F5 / Continue**, sau đó tải lại trang Điều phối để gửi yêu cầu mới. Không cần bỏ kiểm tra schema hoặc thay quyền tài khoản. Khi triển khai trên database khác:

1. Chạy [migration bổ sung](../database/migrations/20261017_dispatch_planning.sql) trên đúng database. Script idempotent, không xóa dữ liệu cũ: thêm tọa độ/nguồn tọa độ vào Kho và hai bảng đề xuất/geometry. Không đổi enum hoặc bỏ CHECK/trigger/index hiện có.
2. Điền **tọa độ kho đã xác minh** cùng nguồn theo [mẫu cấu hình](../database/configure_warehouse_depot.sql). Kho hiện chưa có tọa độ sẽ bị chặn tính tuyến; không tự lấy tọa độ bưu cục. Dữ liệu seed ghi kho trong trụ sở bưu cục được dùng như giả định riêng của fixture kiểm thử, không tự áp dụng sang vận hành.
3. Snapshot đường đã kèm sẵn; mặc định API đọc `Data/roads.osm.gz`. Có thể đặt `Routing__GraphPath` tới tệp OSM/XML hoặc `.gz` khác. Khởi động lại API khi đổi tệp. Điểm ngoài snapshot cần chuẩn bị mạng đường phù hợp.

Ví dụ chạy migration (thay đúng SQL Server):

```powershell
sqlcmd -S "<SQL_SERVER>" -d QLGiaoHangChangCuoi -E -b -f 65001 -i database/migrations/20261017_dispatch_planning.sql
```

Hoặc từ thư mục gốc, dùng script đọc `DefaultConnection` từ appsettings, Development user secrets và biến môi trường theo thứ tự ưu tiên (không in chuỗi kết nối). Script chỉ bổ sung schema, kiểm tra số bản ghi nghiệp vụ và chạy lại để xác minh tính idempotent:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/apply_dispatch_migration.ps1 -ReportPath docs/dispatch/migration-verification.json
```

Chạy ứng dụng từ thư mục gốc:

```powershell
dotnet run --project backend/LastMile/LastMile.Api --no-restore --urls http://127.0.0.1:5038
# Terminal khác:
npm.cmd start --prefix frontend
```

Frontend tại `http://localhost:5500`; proxy giữ luồng xác thực hiện có. Không cần khóa của dịch vụ định tuyến. OpenStreetMap tiles vẫn cần mạng để hiện nền, trong khi định tuyến chạy offline trên snapshot; khi tiles lỗi vẫn giữ điểm và hình học tuyến, attribution vẫn có.

Kịch bản demo: **Hàng chờ → lọc kho → chọn các đơn → Lập phương án giao → kiểm tra kho → chọn shipper/xe và giờ Việt Nam → Tính đề xuất → chọn tuyến xem tải/thứ tự/map và lý do chưa xếp → Xác nhận tạo chuyến → Mở chuyến**. Shipper nhận nhiệm vụ và kho bàn giao ở luồng nghiệp vụ hiện có. Muốn so sánh thủ công: chỉnh thứ tự/chuyển tuyến, xác nhận đang bị khóa, bấm kiểm tra lại rồi mới xác nhận phương án hợp lệ.

## Tệp thay đổi

- Frontend: `frontend/js/dispatch.js`, `frontend/assets/css/dispatch.css`, `frontend/js/router.js`, `frontend/js/app.js`, `frontend/index.html`, `frontend/package.json`.
- Backend mới: `Services/Routing/{RoutingModels,RoadGraph,VrpPlanner,DispatchData,DispatchPlanningService}.cs`, `Controllers/DispatchPlanningController.cs`.
- Backend sửa: `TripOptimizationController.cs`, `DispatchOrdersController.cs`, `DispatchShippersController.cs`, `TripsController.cs`, `Program.cs`, `.csproj`.
- Dữ liệu/cấu hình: migration, mẫu cấu hình tọa độ kho, `tools/prepare_roads.py`, snapshot và metadata trong `Data`.
- Kiểm thử: project C# `LastMile.Routing.Tests` liên kết trực tiếp các file thuật toán thật, không cần thư viện test bên ngoài; `dispatch-fixture.ps1`, `dispatch-browser.cjs`, `dispatch-checks.cjs`, bổ sung test router.

## Kiểm tra và bằng chứng

Lượt sửa Hàng chờ ngày 17/10/2026: **45/45 unit test frontend**, **110 kiểm tra API/giao diện Điều phối** đạt; backend build **0 lỗi, 0 cảnh báo**, trình duyệt không có lỗi JavaScript và log backend không có lỗi ứng dụng ngoài dự kiến. Đã thử 409/503 thật và kiểm tra thông báo tương ứng. Database thử đã tự xóa. Xem [báo cáo từng nút và giới hạn kiểm thử](dispatch-queue-verification.md).

Các lượt triển khai trước đã đạt **20/20 kiểm tra C# thuật toán** và **70 kiểm tra hồi quy Theo dõi**; hai bộ này không chạy lại trong lượt sửa Hàng chờ này. Không có cảnh báo lỗi API trên các ảnh giao diện thông thường; ảnh thử 409 cố ý hiển thị lỗi xung đột.

Các trường hợp gồm: đường ngắn nhất biết trước, đường có hướng/không tới được, một/nhiều xe, tải trọng khác nhau, đơn vượt tải, thiếu xe, khu vực, deadline không đáp ứng, giờ sẵn sàng, thiếu tọa độ/thể tích, đơn không lặp, tổng tải và thời gian khớp thứ tự, phương án thủ công trên cùng ma trận, đổi rowversion, hai xác nhận cạnh tranh, retry idempotent, hộp thoại phân công/đổi/hủy, tạo/sửa/hủy chuyến, sidebar, ba bước, chỉnh thứ tự phải kiểm tra lại, tải lại/Back, attribution, marker trùng và dọn request/map khi rời trang. Kiểm tra 1366/1920/390px ở zoom 100% phát hiện và đã sửa lỗi tràn do mã chuyến dài; trường hợp hàng chờ hết đơn trả đúng `items: []`; chuyến thủ công chưa có geometry trả object `{route:null}` tương thích API client và không báo lỗi giả.

```powershell
npm.cmd test --prefix frontend
# Một lần ở môi trường chưa restore project test (không thêm package ngoài):
dotnet restore backend/LastMile/LastMile.Routing.Tests --configfile backend/LastMile/LastMile.Routing.Tests/NuGet.Config
npm.cmd run test:routing --prefix frontend
npm.cmd run test:dispatch --prefix frontend
```

[Kết quả thuật toán](dispatch/algorithm-verification.json), [kết quả API/trình duyệt](dispatch/dispatch-verification.json). API/browser dùng schema/seed/trigger thật trong LocalDB `CodexAdmin_<GUID>`, ASP.NET thật, proxy thật và Edge headless, zoom 100%. Đơn/shipper bổ sung để kiểm thử chỉ có trong database này, không xuất hiện trong ứng dụng vận hành. Không mock response định tuyến hoặc thao tác xác nhận trong kiểm tra tích hợp.

Ảnh: [Hàng chờ 1366](dispatch/dispatch-queue-1366.png), [1920](dispatch/dispatch-queue-1920.png), [390](dispatch/dispatch-queue-390.png), [chọn shipper](dispatch/dispatch-shippers-1366.png), [đề xuất 1366](dispatch/dispatch-proposal-1366.png), [1920](dispatch/dispatch-proposal-1920.png), [390](dispatch/dispatch-proposal-390.png), [chi tiết chuyến](dispatch/dispatch-trip-detail-1366.png), [phân công](dispatch/dispatch-assignments-1366.png), [hộp thoại phân công](dispatch/dispatch-manual-assignment-1366.png), [sửa chuyến trên mobile](dispatch/dispatch-edit-trip-390.png).
