# Ghi chú dự án TVĐ Logistics

Ngày rà soát: 29/10/2026. Thư mục: `D:/DA_CN_logistics/last-mile-logistics`.

Tài liệu này lưu những kiến thức đã đối chiếu từ cấu trúc thư mục, tài liệu Markdown và các phần mã nguồn chính. Đây là nền tra cứu cho các lần làm việc tiếp theo, không phải tuyên bố đã kiểm chứng toàn bộ mã nguồn hoặc trạng thái cơ sở dữ liệu đang chạy.

## Phạm vi và nguồn dữ liệu

- Thư mục gốc chứa dự án đã giải nén và `last-mile-logistics.zip`.
- Không tìm thấy Word `.doc/.docx`, PowerPoint `.ppt/.pptx`, PDF hay Excel trong kết quả kiểm kê thư mục; kiểm tra danh mục ZIP cũng không thấy các định dạng tài liệu này.
- Có 48 tài liệu Markdown khi kiểm kê ban đầu, gồm README và các báo cáo triển khai/kiểm chứng. Một số báo cáo ghi lại những thời điểm khác nhau và có kết luận đã được bản mới thay thế.
- `CHI_MUC_DU_AN.md` lập chỉ mục cấu trúc cho 290 tệp tài liệu, mã nguồn, cấu hình dự án và kiểm thử. Chỉ mục liệt kê số dòng, khai báo lớp, tuyến API, đối tượng SQL và tiêu đề tài liệu khi phù hợp. Đây là chỉ mục tự động, không phải đánh giá đầy đủ từng tệp.
- Không tìm thấy AGENTS.md trong dự án qua tìm kiếm ban đầu. Bỏ qua thư viện bên thứ ba, file biên dịch, cache và hồ sơ trình duyệt khi lập chỉ mục.
- Lần rà soát này không chạy ứng dụng, không kết nối cơ sở dữ liệu, không chạy migration và không chạy lại bộ kiểm thử. Các kết quả kiểm thử trong `docs` thuộc những lần thực hiện trước.

## Mục đích và kiến trúc

Hệ thống quản lý giao hàng chặng cuối, thương hiệu giao diện TVĐ Logistics. Các nhóm chức năng gồm tổng quan, đơn hàng, kho, điều phối, theo dõi giao hàng, thu hộ và đối soát COD, khách hàng, nhân viên giao hàng, phương tiện, báo cáo và quản trị.

Giao diện tại `frontend`: HTML/CSS/JavaScript thuần, Bootstrap; điều hướng hash do `frontend/js/router.js` quản lý. Các màn hình nghiệp vụ nằm trong các tệp JavaScript riêng. `api.js`, `auth.js`, `write-outcome.js`, `vietnam-date.js` xử lý phần dùng chung. Leaflet được lưu cục bộ để hiển thị bản đồ.

Backend tại `backend/LastMile/LastMile.Api`: ASP.NET Core, C#, đích `net10.0`. Controller chia theo thao tác nghiệp vụ; truy cập SQL bằng Microsoft.Data.SqlClient, câu SQL tham số hóa và stored procedure. Không thấy lớp ORM trong kiến trúc chính đã đọc. `Program.cs` đăng ký xác thực, phân quyền, CORS, giới hạn tần suất, Swagger và các dịch vụ định tuyến.

SQL Server chứa dữ liệu và nhiều quy tắc nghiệp vụ trong constraint, index, trigger và stored procedure. Script chính hiện có là `database/01_KhoiTao_CoSoDuLieu_Va_CauTruc.sql`, kèm nhiều bản SQL V5, dữ liệu seed và migration; cần đối chiếu môi trường trước khi chọn script triển khai.

## Luồng nghiệp vụ đơn hàng

Luồng điển hình: tạo đơn → xác nhận/tiếp nhận → nhập kho → chờ phân công → phân công → xuất kho/bàn giao → lấy hàng → đang giao → giao thành công → hoàn tất. Không phải mọi đơn đều đi qua mọi bước; bảng chuyển trạng thái quyết định đường đi hợp lệ.

SQL seed khai báo 17 trạng thái: NEW, CONFIRMED, WAITING_INBOUND, IN_WAREHOUSE, WAITING_ASSIGNMENT, ASSIGNED, HANDED_OVER, EN_ROUTE_PICKUP, PICKED_UP, IN_DELIVERY, DELIVERED, FAILED, RETRY_WAITING, RETURNING, RETURNED, COMPLETED, CANCELLED.

Nhánh thất bại có thể chuyển sang giao lại hoặc chuyển hoàn. Hủy, đổi phân công và những bước khác có điều kiện/lý do riêng. Controller và SQL quyết định chuyển trạng thái; không suy diễn chỉ dựa trên nút giao diện.

Đơn hàng liên kết khách gửi, khách nhận, dịch vụ, địa chỉ, điểm giao nhận, hàng hóa, khoản phí, lịch sử trạng thái, lần giao và bằng chứng. Phải phân biệt ID địa chỉ khách hàng với ID điểm giao nhận. Chi tiết lưu snapshot để bảo toàn thông tin lịch sử.

Mã nguồn hiện tại của OrdersController có senderId, serviceId và requiresAddressSelection. Tài liệu `orders-api-gaps.md` có phần cập nhật nói luồng sửa đã được bổ sung; nhận định cũ rằng toàn bộ form sửa bị khóa không còn đủ để mô tả bản hiện tại.

## Kho

Các màn hình: tồn kho, nhập kho, xuất/bàn giao, nhập hoàn, vị trí lưu kho, lịch sử giao dịch. Mã nguồn liên quan: warehouse.js, inbound.js, locations.js, transactions.js và nhóm Warehouse controller.

Nhập kho kiểm tra trạng thái đơn và phạm vi bưu cục/kho/vị trí. Xuất kho gắn với phân công và điều kiện nhận nhiệm vụ, tải trọng/thể tích. Nhập hoàn dựa trên yêu cầu hoàn đủ điều kiện; không nhập tùy ý ID để vượt nghiệp vụ.

Phải phân biệt trạng thái đơn với trạng thái tồn kho. Danh sách rỗng phải trả items: []; tài liệu đã ghi nhận lỗi FOR JSON bỏ trường items khi SQL trả NULL và cách xử lý COALESCE.

`OrderReadyForDispatchController` hiện tồn tại. Báo cáo cũ nói thiếu endpoint ready-for-dispatch là lịch sử và đã được tài liệu cập nhật sau đó thay thế.

## Điều phối và thuật toán

Các tệp quan trọng: Services/Routing/RoadGraph.cs, VrpPlanner.cs, RoutingModels.cs, DispatchData.cs, DispatchPlanningService.cs; phía giao diện là dispatch.js.

RoadGraph nạp đồ thị OSM có hướng. Dijkstra dùng PriorityQueue để tối thiểu tổng chiều dài cạnh; thời gian được tính theo đường đã chọn và tốc độ giả định/thông tin OSM. Haversine phục vụ khoảng cách hình học như tìm nút gần địa chỉ, không thay ma trận đường bộ giữa các đơn.

Có profile motorcycle và hgv. VRP xây dựng nghiệm bằng cheapest feasible insertion theo ưu tiên/hạn giao, cải thiện bằng 2-opt trong tuyến và relocation giữa tuyến. Đây là heuristic, không bảo đảm nghiệm tối ưu toàn cục.

Theo tài liệu điều phối: tối đa 60 đơn và 15 shipper, giới hạn tính 20 giây; cải thiện có ngân sách riêng 2,5 giây/8 lượt. Cần xem lại giới hạn trong code khi thay đổi quy mô.

Ràng buộc gồm tải trọng, thể tích khi biết đủ kích thước, phạm vi khu vực, xe/shipper đủ điều kiện, giấy phép, thời điểm sẵn sàng và cửa sổ giao. RequestedDeliveryAt là giờ sớm nhất bắt đầu phục vụ; Deadline là giờ muộn nhất bắt đầu. Đến sớm phải chờ rồi cộng thời gian phục vụ.

Đề xuất được lưu riêng, hết hạn sau 15 phút theo tài liệu. Xác nhận đọc lại dữ liệu/quyền/phiên bản đồ thị, kiểm tra lại tuyến trong giao dịch và chống tạo trùng theo plan ID. Xác nhận tạo chuyến/phân công; các bước shipper nhận nhiệm vụ, kho bàn giao và bắt đầu giao vẫn là thao tác riêng.

Snapshot mạng đường nằm tại Data/roads.osm.gz và metadata cùng thư mục, phạm vi tập trung Bình Tân–Tân Phú–Quận 6. Không mặc định phủ toàn TP.HCM; không có giao thông trực tiếp. Các hạn chế rẽ/điều kiện chưa hỗ trợ được xử lý bảo thủ theo tài liệu và importer.

Tọa độ xuất phát lấy từ Kho theo MaKho. Không tự thay bằng tọa độ BuuCuc. Báo cáo `warehouse-depot.md` ngày 19/10 ghi nhận một số kho còn NULL; đây là trạng thái lịch sử, chưa được kiểm tra lại trong lần rà soát này.

## COD và báo cáo

Luồng COD: giao thành công tạo khoản thu → lập phiếu nộp PENDING giữ phần tiền phân bổ → xác nhận nhận tiền → lập/xác nhận kỳ đối soát theo shipper và bưu cục. Có thể có DIFFERENCE khi chênh lệch. Hệ thống trong tài liệu đang đối soát với shipper/bưu cục, chưa có nghiệp vụ thanh toán COD cho khách hàng.

Không coi COD hoặc phiếu chưa xác nhận là doanh thu. Báo cáo có nhóm đơn hàng, hiệu suất giao hàng, cước phí và COD; phân trang/tổng hợp ở backend, xuất CSV theo toàn bộ bộ lọc. Cần giữ đúng định nghĩa chỉ số: đơn tạo trong kỳ và hiện giao thành công khác số lần giao thành công phát sinh trong kỳ.

## Xác thực và tính nhất quán

JWT kèm session ID; Program.cs kiểm tra phiên còn hiệu lực, tài khoản/vai trò hoạt động và trạng thái khóa qua SQL khi token được xác thực. Có refresh token, thu hồi phiên, đổi/khôi phục mật khẩu và giới hạn tần suất đăng nhập.

Quyền thực tế đọc từ database; frontend có `/api/v1/auth/permissions` để quyết định hiển thị thao tác. Backend phải kiểm tra lại quyền và phạm vi bưu cục khi thực hiện.

Một số hồ sơ dùng ROWVERSION/ExpectedVersion để chống ghi đè dữ liệu cũ. `version-schema-runtime.md` ghi nhận thiếu PhienBan ở bảng shipper/xe tại lần chẩn đoán trước và migration tương ứng ngày 19/10. Không kết luận cơ sở dữ liệu hiện tại vẫn thiếu cột nếu chưa kiểm tra lại.

Khi phản hồi ghi bị mất, có thể không biết chắc giao dịch đã hoàn tất. `write-outcome.js` khóa phát lại thao tác và cho đọc đối chiếu. GET thành công không tự chứng minh request trước đã thất bại. Đây vẫn có giới hạn vì chưa có hợp đồng tra cứu kết quả theo mã lần ghi cho mọi nghiệp vụ.

Ngày giờ SQL chủ yếu UTC, giao diện hiển thị Asia/Ho_Chi_Minh. Ngày hết hạn bằng lái so theo ngày Việt Nam; tránh cộng múi giờ hai lần hoặc so ngày UTC sai nghiệp vụ.

## Kiểm thử và chạy cục bộ

Backend có các dự án kiểm thử Calendar, DeliveryFailure, Evidence, Routing và SqlResults. Frontend có kiểm thử đơn vị và các bộ kiểm chứng trình duyệt/SQL riêng; có nhiều fixture tạo database GUID cách ly. Đọc kỹ từng fixture trước khi chạy vì có thao tác chuẩn bị/xóa dữ liệu thử.

Chạy backend từ gốc dự án: `dotnet run --project backend/LastMile/LastMile.Api --launch-profile http`.

Chạy frontend: `node frontend/dev-server.cjs`. Theo README, frontend ở localhost:5500, proxy API đến localhost:5038. Thông số thực tế có thể bị cấu hình môi trường ghi đè.

Không cần npm dependency để chạy giao diện cơ bản. Lệnh kiểm thử nằm trong frontend/package.json. Kết quả pass được ghi trong docs là bằng chứng lịch sử; cần chạy kiểm tra phù hợp sau các thay đổi mới.

## Cách sử dụng ghi chú

Đọc tài liệu này để lấy bối cảnh; dùng CHI_MUC_DU_AN.md để tìm đúng tệp và khai báo, rồi đọc lại hàm/controller/SQL liên quan trước khi sửa. Khi tài liệu và code khác nhau, đối chiếu code hiện tại và trạng thái môi trường; không trộn các kết quả kiểm chứng ở nhiều thời điểm thành một kết luận hiện tại.

Chưa đọc nội dung hình ảnh báo cáo, mọi bản ghi seed, mọi nhánh code và dữ liệu nhị phân theo nghĩa kiểm chứng chi tiết. Chưa có tài liệu Word/PowerPoint để đọc. Những phần này cần được mở rộng khi có nguồn hoặc yêu cầu cụ thể.
