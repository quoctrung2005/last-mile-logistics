# Đọc tọa độ xuất phát theo kho được chọn

## Dữ liệu đã đối chiếu (19/10/2026)

API đang chạy ở `localhost:5038/api/database/check` báo database
`QLGiaoHangChangCuoi`. Công cụ SELECT dùng cấu hình Development hiện tại của
LastMile.Api kết nối `(localdb)\MSSQLLocalDB / QLGiaoHangChangCuoi`.
Đã duyệt các cột tọa độ của bảng/view trong schema, không chỉ đọc file SQL mẫu.

| Bản ghi | Kho.ViDo | Kho.KinhDo | BuuCuc.ViDo | BuuCuc.KinhDo |
|---|---|---|---|---|
| MaKho=3, KHO-TP-PL, MaBuuCuc=2 | NULL | NULL | 10.802900 | 106.617900 |
| MaKho=1, KHO-BT-PL, MaBuuCuc=1 | NULL | NULL | 10.810500 | 106.604800 |

Nguồn riêng của kho trong schema hiện tại là **dbo.Kho.ViDo DECIMAL(9,6)** và
**dbo.Kho.KinhDo DECIMAL(10,6)**, liên kết bằng **MaKho**. `NguonToaDo` chỉ là
metadata, không còn là điều kiện để thuật toán chấp nhận tọa độ hợp lệ.
Không có cột tọa độ khác hoặc cột geography riêng của Kho trong schema đã đọc.
`BuuCuc.ViDo/KinhDo/ToaDoDiaLy` là dữ liệu của bưu cục, không tự chuyển thành
vị trí của kho khi chưa xác nhận cùng địa điểm.

Kết quả đọc hiện tại chưa khớp nhận định "Kho đã có tọa độ": hai bản ghi Kho
đều NULL; giá trị có sẵn nằm tại BuuCuc. Đã hỏi lại bảng/database người dùng đang
xem. Chưa có xác nhận dùng chung vị trí kho và bưu cục, nên không thêm fallback.
Không khẳng định có lỗi đảo latitude/longitude trong SQL cũ: phép gán hai tên
trường đó vốn đúng. Lỗi đã sửa là chặn tọa độ hợp lệ do thiếu metadata nguồn,
phụ thuộc options cũ, và thiếu một vòng đời request riêng cho kho được chọn.

Bằng chứng đọc thực tế: [warehouse-depot-diagnostic.json](warehouse-depot-diagnostic.json).
Công cụ gọi đường đọc service với quyền đang lưu trong database và rollback
transaction; không giả là đã gọi HTTP bằng phiên đăng nhập thật của người dùng.

## Luồng sau sửa

1. Frontend lấy `warehouseId` từ lựa chọn/danh sách đơn. Kho chỉ định trong URL
   được ưu tiên khi mở màn hình thay vì bị lựa chọn cũ trong sessionStorage che.
2. Mỗi lần chọn/đổi kho hoặc mở bước chọn shipper, tự GET
   `/api/v1/warehouses/{warehouseId}/depot`. Trong lúc tải, nút tính tuyến bị khóa.
3. Backend kiểm tra quyền thực tế, phạm vi bưu cục, kho/bưu cục hoạt động;
   truy vấn `WHERE k.MaKho=@id` rồi trả JSON số `latitude`, `longitude`.
   Frontend xác nhận cả `id` lẫn `branchId`, phân biệt thiếu trường, null và sai kiểu.
4. Khi đổi kho/rời bước/rời màn hình, abort request trước; kiểm tra thêm sequence,
   kho hiện tại và node còn gắn vào DOM. Phản hồi cũ không được cập nhật điểm xuất phát.
5. API xem phương án nhận ID kho, tự đọc SQL. API xác nhận đọc lại cùng nguồn trong
   transaction, so fingerprint và kiểm tra lại thuật toán. Không nhận tọa độ do
   frontend tự gửi. Thay đổi điểm xuất phát làm phương án cũ bị từ chối 409.
6. Tọa độ hợp lệ không cần nhập lại và không cần `NguonToaDo`. Bản ghi thiếu/sai
   có thông báo ngắn. Không nối được OSM có lý do mạng đường riêng.

Đã bỏ khung **Tọa độ kho**, nút **Tải lại tọa độ kho**, nút/form **Nhập / cập nhật
 tọa độ kho đã xác minh** khỏi màn hình tối ưu. Màn hình chỉ đọc API tọa độ.
Không thay trạng thái shipper; GH-TP-001 trên dữ liệu thật vẫn DELIVERING với
1 nhiệm vụ hiện hành và 1 chuyến chưa kết thúc.

## File sửa trong lần này

- `frontend/js/dispatch.js`: bỏ UI nhập; tự tải và hủy request; kiểm tra đúng kho,
  số/null/kiểu; giữ các tùy chọn khi chuyển bước.
- `frontend/assets/css/dispatch.css`: bỏ CSS khung tọa độ đã loại bỏ.
- `frontend/index.html`: tăng phiên bản asset.
- `backend/LastMile/LastMile.Api/Services/Routing/DispatchData.cs`: dùng một
  `DepotColumns` cho options, đọc depot, xem và xác nhận phương án; bỏ điều kiện
  nguồn xác minh; giữ null từng tọa độ khi ánh xạ. Contract SQL `vehicles` rỗng
  trả mảng `[]` để lựa chọn không có xe không gây lỗi đọc JSON.
- `backend/LastMile/LastMile.Api/Services/Routing/DepotCoordinates.cs`: thông báo ngắn.
- `backend/LastMile/LastMile.Api/Controllers/WarehouseDepotController.cs`: GET dùng
  cùng projection tọa độ và không bắt buộc metadata nguồn. Endpoint quản lý PUT
  có sẵn giữ kiểm tra quyền; frontend tối ưu không gọi nó.
- `tools/DepotDiagnostics/Program.cs`: kiểm tra metadata toàn schema, đọc hai kho,
  đi qua DispatchData.Load và VrpPlanner bằng lựa chọn chẩn đoán rỗng, không ghi.
- `frontend/tests/dispatch-depot.test.cjs`: kiểm tra dữ liệu/kiểu/null, metadata nguồn.
- `frontend/tests/dispatch-depot-checks.cjs`: SQL/API/Edge, hai kho, abort/phản hồi
  chậm, source NULL, Depot, 409, lỗi mạng đường và UI không có form nhập.
- `frontend/tests/dispatch-fixture.ps1`: thêm tình huống và phép đọc tọa độ chỉ cho
  database GUID thử. Toàn bộ thay đổi dữ liệu thử đều được giới hạn ở database đó.
- Báo cáo này và các JSON/ảnh kiểm chứng trong `docs/dispatch`.

Không thêm/sửa migration, bảng hoặc cột trong lần này. Không chạy script cấu hình
hoặc cập nhật dữ liệu/schema của database hiện tại. Không khởi động lại API đang
được người dùng chạy; cần chạy code mới để nhận thay đổi backend/asset.

## Kiểm chứng

- Build API Release và DepotDiagnostics: thành công, 0 warning/error.
- Frontend: 82/82 đạt.
- Routing tests với đồ thị kiểm soát và snapshot OSM: 35/35 đạt.
- Tích hợp: 140/140 đạt, không lỗi JavaScript hoặc lỗi backend ngoài dự kiến;
  [dispatch-verification.json](dispatch/dispatch-verification.json).
  Chạy API thật, SQL LocalDB và Edge. Database ghi thử là GUID riêng, được dọn sau chạy.
- Với KHO-TP-PL và KHO-BT-PL trong database thử: đối chiếu SELECT trực tiếp với
  HTTP options/depot, kiểm tra JSON number và đúng thứ tự. Đi qua DispatchData.Load
  và VrpPlanner với hai tọa độ riêng, cùng Depot ở đầu vào/đầu ra; không tạo chuyến
  trong phép chẩn đoán rỗng. Bằng chứng: [warehouse-depot-isolated.json](dispatch/warehouse-depot-isolated.json).
- Kiểm tra request chậm: đổi từ kho A sang B, signal cũ đã abort, trả cố ý dữ liệu
  thiếu của A sau khi B tải xong; UI giữ B và không hiện cảnh báo sai.
- Preview bằng đơn/xe thật trong database thử nhận đúng Depot; thay tọa độ rồi
  xác nhận phương án cũ nhận 409. Bộ hồi quy giữ kiểm tra lịch giao và nghiệp vụ.
- Có ảnh desktop 1366 và điện thoại 390: `dispatch-depot-auto-*`.

Chưa thể xác nhận cảnh báo hết trên KHO-TP-PL của database hiện tại, vì chính bản
Kho đọc được đang NULL. Đường đọc hiện tại từ chối cả KHO-TP-PL và KHO-BT-PL với
409 đúng nguyên nhân, không tự lấy tọa độ bưu cục. Nếu dữ liệu người dùng xem nằm
ở connection/database khác, cần đối chiếu đúng nơi đó; không tự thay connection.
