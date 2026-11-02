# Khung giờ bắt đầu giao trong VRP — 19/10/2026

Đã kiểm tra `DispatchData`, `RoutingModels`, `VrpPlanner`, `DispatchPlanningService`, API hàng chờ/tối ưu/xác nhận/xem tuyến, frontend phương án và schema liên quan. Không tìm thấy AGENTS.md trong workspace và các thư mục cha đã kiểm tra.

## Quy tắc đã triển khai

Với mỗi điểm giao, cùng một hàm Evaluate tính:

```text
arrivalAt      = departureAt của điểm trước + thời gian di chuyển
serviceStartAt = max(arrivalAt, requestedDeliveryAt nếu có)
waitingMinutes = (serviceStartAt - arrivalAt).TotalMinutes
departureAt    = serviceStartAt + serviceMinutes
hợp lệ         = expectedDeliveryAt null hoặc serviceStartAt <= expectedDeliveryAt
```

Ví dụ cố định giờ Việt Nam: đến 13:50, requested 14:00, phục vụ 5 phút → chờ 10 phút, bắt đầu 14:00, rời 14:05. Đến 14:10 với requested 14:00 → bắt đầu 14:10, không chờ. Bắt đầu đúng hạn cuối được phép, kể cả phục vụ kết thúc sau hạn. Bắt đầu sau hạn bị loại.

Cheapest insertion, 2-opt, relocation, thứ tự thủ công và kiểm tra lại khi confirm đều gọi Evaluate này. Chặng sau dùng thời điểm rời sau chờ/phục vụ; tổng thời gian tuyến gồm di chuyển, chờ, phục vụ và quay về kho nếu được chọn. Mục tiêu tối ưu chiều dài đường và thuật toán Dijkstra, làm tròn di chuyển lên phút mỗi chặng, tải trọng, thể tích, khu vực, trạng thái kho/đơn/xe/shipper và giới hạn thời gian tính được giữ.

`requestedDeliveryAt=null` không thêm cận sớm, không chờ vì lịch. `expectedDeliveryAt=null` giữ cách xử lý thiếu hạn hiện có: không áp cận muộn, không tạo hạn giả; nếu requested vẫn có thì vẫn chờ. Khi requested > expected và cả hai có giá trị: phương án tự động báo lỗi lịch rõ tại đơn chưa xếp được; tuyến thủ công chứa đơn đó nhận 422. Lỗi này vẫn hiển thị ngay cả khi chưa chọn xe. Confirm phương án cũ sau khi lịch đổi nhận 409 và yêu cầu tính lại.

## Dữ liệu, snapshot và tương thích

- `PlanningOrder` bổ sung `RequestedDeliveryAt` tùy chọn. `Deadline` nội bộ vẫn ánh xạ cột `ThoiGianDuKienGiao`; không đổi tên trường nội bộ hiện có.
- `DispatchData.Load` đọc `ThoiGianYeuCauGiao` thành timestamp UTC có timezone, đưa vào raw snapshot dùng SHA-256. Cả requested, deadline và rowversion đều nằm trong snapshot. Hash có thêm policy `DELIVERY_START_WINDOW_V1` để phương án chưa xác nhận được tính bằng quy tắc cũ phải tính lại.
- API hàng chờ thêm `requestedDeliveryAt`, giữ `expectedDeliveryAt`. Không đổi request lập tuyến; lịch được đọc từ database, không tin lịch/tổng do client tự gửi.
- Stop response thêm `serviceStartAt`, `waitingMinutes`, `requestedDeliveryAt`, `expectedDeliveryAt`. Giữ `arrivalAt` là giờ đến nơi và `departureAt` là giờ rời sau phục vụ. Các trường mới nullable khi đọc JSON lịch sử thiếu trường; không suy serviceStartAt từ arrivalAt rồi giả là dữ liệu mới.
- Confirm đọc dữ liệu hiện tại trong transaction/khóa như trước, so fingerprint và tính lại toàn bộ thứ tự/thời gian bằng engine, không dùng thời gian đã lưu trong proposal làm kết quả tin cậy. Vẫn giữ idempotency cho phương án đã xác nhận.
- JSON phương án trong `DispatchRoutePlan.ResultJson` và JSON tuyến trong `TripRouteGeometry.RouteJson` lưu đủ các mốc thời gian mới. Request departure và các timestamp mới chuẩn hóa UTC. Cột `ThoiGianDenDuKien` của chi tiết chuyến/điểm dừng vẫn lưu **arrival**, không đổi thành giờ bắt đầu giao. Cột phút di chuyển vẫn chỉ lưu di chuyển. Tổng phút chuyến nguyên dùng ceiling của tổng phút tuyến có chờ; JSON giữ độ chính xác thời gian chờ dưới một phút.
- Frontend bảng phương án, popup bản đồ và chi tiết chuyến có giờ đến, bắt đầu giao, phút chờ, rời điểm theo `Asia/Ho_Chi_Minh`. Bản phương án cũ thiếu timing mới được ghi rõ và khóa xác nhận, có Tính lại. Chỉnh thứ tự/chuyển đơn vẫn ẩn các mốc cũ bằng “Chưa tính lại” cho tới khi backend kiểm tra.

Không cần migration mới: các cột lịch và bảng JSON cần thiết đã có. Không chạy migration hoặc ghi dữ liệu trên database đang dùng. Chỉ fixture GUID thử áp dụng các migration hiện có để tạo môi trường độc lập.

## File thay đổi

- `backend/LastMile/LastMile.Api/Services/Routing/DispatchData.cs`
- `backend/LastMile/LastMile.Api/Services/Routing/RoutingModels.cs`
- `backend/LastMile/LastMile.Api/Services/Routing/VrpPlanner.cs`
- `backend/LastMile/LastMile.Api/Services/Routing/DispatchPlanningService.cs`
- `backend/LastMile/LastMile.Api/Controllers/DispatchOrdersController.cs`
- `frontend/js/dispatch.js`, `frontend/assets/css/dispatch.css`, `frontend/index.html` (cache version mới).
- `backend/LastMile/LastMile.Routing.Tests/Program.cs`
- `frontend/tests/dispatch-window-checks.cjs` (mới), `dispatch-checks.cjs`, `dispatch-browser.cjs`, `dispatch-fixture.ps1`, `README.md`.
- Tài liệu này, `docs/dispatch-implementation.md`; báo cáo `docs/dispatch/algorithm-verification.json`, `delivery-window-verification.json`, `dispatch-verification.json` và ảnh hồi quy Điều phối.

Fixture bổ sung phiên đăng nhập thử/sid cho JWT tổng hợp để kiểm tra qua middleware thu hồi phiên hiện tại. Không nới kiểm tra JWT của ứng dụng. Các mode thay lịch/timing chỉ chạy trong database có tên GUID `CodexAdmin_*` được kiểm tra cứng trước khi mở connection.

## Kiểm tra đã chạy

- Build API Release `--no-restore -warnaserror`: 0 lỗi, 0 cảnh báo.
- `LastMile.Routing.Tests`: **33 ca đạt**, gồm 13 ca bổ sung khung giờ/tương thích. Kiểm chứng các mốc cố định 13:50, 14:00, 14:05, đến 14:10; đúng/sau hạn; chờ làm điểm sau trễ; 2-opt không đảo sang tuyến ngắn hơn nhưng sai giờ; relocation không gộp hai tuyến có giờ bắt đầu trùng thành tuyến sai; null requested/deadline; lịch đảo; chờ 10,5 phút; JSON cũ giữ trường mới là chưa biết. Các ca tải/thể tích/khu vực/xe và Dijkstra trên snapshot OSM thật vẫn đạt.
- `npm.cmd test`: **80/80 đạt**; giữ hồi quy timeout từng request, hủy body, refresh/401 đồng thời, request ghi không tự gửi lại và router.
- Harness `dispatch-browser.cjs`: **123 kiểm tra đạt**, API/HTTP/JWT/SQL/Edge thật trên database GUID riêng; không lỗi JavaScript hoặc lỗi ứng dụng backend ngoài dự kiến. Báo cáo cuối ở `docs/dispatch/dispatch-verification.json`.
- Module mới **9 kiểm tra API/SQL đạt**: đọc lịch từ SQL sang stop, lưu/đọc lại proposal, tổng thời gian có chờ, đổi requested hoặc expected làm confirm 409 không tạo chuyến/phân công, tuyến thủ công dùng cùng evaluator, confirm tính lại timing đã bị sửa trong SQL thử, lưu route UTC và giữ cột arrival, null deadline/requested, lịch sai báo rõ/422.
- UI đã kiểm tra cột giờ mới, định dạng Việt Nam từ timestamp API thật, lưu và tải lại phương án, chỉnh thứ tự phải kiểm tra lại, xác nhận/xem tuyến đã lưu; hồi quy cả bộ Điều phối ở 1366/1920/390 px. Ca JSON phương án cũ trên UI dùng response đọc có kiểm soát bỏ hai trường mới, không sửa proposal thật trong database; sau đó khôi phục response thật.
- Kiểm thử ghi chỉ trên database thử riêng, đã tự dọn; không đổi giờ hệ điều hành.

Lệnh từ gốc dự án:

```powershell
dotnet build backend/LastMile/LastMile.Api/LastMile.Api.csproj --no-restore -c Release -warnaserror --output frontend/tests/.artifacts/dispatch/build
dotnet run --no-restore -c Release --project backend/LastMile/LastMile.Routing.Tests -- backend/LastMile/LastMile.Api/Data/roads.osm.gz docs/dispatch/algorithm-verification.json
npm.cmd test --prefix frontend
node frontend/tests/dispatch-browser.cjs
```

LocalDB/Edge cần quyền truy cập user profile. Không thêm dependency, không tắt NuGet Audit.

## Phần chưa kiểm chứng

Chưa thử điện thoại vật lý hoặc Chrome/Firefox/Safari. Chưa kiểm thử tải lớn nhiều người đồng thời ngoài các ca xác nhận cạnh tranh có sẵn. Các ví dụ giờ chính xác dùng đồ thị/thời gian đầu vào cố định; tích hợp API dùng lịch tương đối tương lai để qua kiểm tra departure và chạy mạng OSM thật. Chưa chạy ghi trên database đang dùng. Giới hạn heuristic, thời gian ước tính OSM, snap và đoạn tiếp cận địa chỉ giữ như tài liệu Điều phối hiện có. API đang chạy bản cũ cần khởi động lại; các phương án chưa xác nhận tính trước bản sửa cần tính lại.
