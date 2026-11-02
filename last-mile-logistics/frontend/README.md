# TVĐ Logistics frontend

HTML/CSS/JavaScript thuần + Bootstrap 5, giữ sidebar/header và xác thực hiện có. Màn hình **Đơn hàng** dùng API thật, không có dữ liệu mẫu trong ứng dụng.

Hai trang **Thu hộ COD** (`#/cod/collections`) và **Đối soát COD** (`#/cod/reconciliation`) dùng API thật: khoản thu, phiếu nộp, xác nhận nhận tiền và phiên đối chiếu với shipper. Nút lập phiếu phụ thuộc `COD_NOPTIEN`; backoffice dùng `COD_DOISOAT`. Xem [API, luồng tiền và kiểm chứng COD](../docs/cod-implementation-verification.md). Chạy `npm.cmd run test:cod` để build và kiểm tra trên LocalDB GUID riêng + Edge.

Trang **Báo cáo** tại `#/reports` gồm Đơn hàng, Hiệu suất giao hàng và Cước phí & COD; lọc ngày Việt Nam/bưu cục, lưu bộ lọc vào URL, tổng hợp/phân trang ở backend và xuất toàn bộ bảng CSV. Dùng quyền `BAOCAO_XEM` và mở rộng endpoint báo cáo hiện có. Định nghĩa chỉ số, API, kiểm tra và giới hạn tại [reports-implementation-verification.md](../docs/reports-implementation-verification.md). Chạy `npm.cmd run test:reports` để build và kiểm tra trên LocalDB GUID riêng + Edge.

## Điều hướng hash

`js/router.js` là nơi khai báo menu, route, quyền và query. Link menu dùng URL riêng; router render qua `hashchange`, không dùng cơ chế `renderPage`/`warehouse:navigate` cũ. Chi tiết đơn, tạo/sửa đơn và chi tiết giao dịch có view riêng; báo giá/xác nhận/hủy/nhập/xuất/chuyển vị trí vẫn là modal thao tác.

- Ví dụ mở trực tiếp: `http://localhost:5500/#/orders/14`, `#/orders/create`, `#/warehouse/inventory?warehouseId=1&status=IN_WAREHOUSE`, `#/warehouse/transactions/8` (ID phải tồn tại và nằm trong phạm vi tài khoản).
- Hash rỗng chọn `#/dashboard` khi có phiên, `#/login` khi chưa có phiên. F5 và Back/Forward đọc cùng route. Không tìm thấy route hiển thị trang Không tìm thấy.
- Chưa đăng nhập thì lưu route nội bộ trong `tvd.returnRoute`, chuyển Login và quay lại sau login. Chặn URL ngoài, `//`, backslash, ID không phải số nguyên dương an toàn và query sai/trùng. Thiếu quyền hiển thị Không có quyền, không xóa phiên; backend tiếp tục kiểm tra mọi API.
- Đơn hàng hỗ trợ `page` (1–100000), `pageSize` (1–100), `keyword` (≤100), `status`. Kho hỗ trợ bộ lọc theo từng màn hình: `warehouseId`, `locationId`, `page`, `pageSize`, `keyword`, `status`, `acceptedOnly`, `type`, `orderId`. Không gửi query không hợp lệ lên API. Kho/vị trí còn phải có trong danh sách scope do API trả.
- Thay bộ lọc cập nhật history entry hiện tại, không remount trang hoặc gọi API lần thứ hai từ router. Khi mở chi tiết rồi Back, danh sách lấy lại bộ lọc đã lưu. Request/timer/modal được hủy/dọn khi rời route. Các nút chuyển trang dùng `Router.navigate(Router.href(...))`; nút mở modal không đổi hash.

Danh sách đầy đủ và bằng chứng kiểm thử tại [hash-routing-verification.md](../docs/hash-routing-verification.md). Các menu placeholder giữ nội dung hiện tại; cấp URL riêng không có nghĩa đã triển khai nghiệp vụ của chúng. Sửa đơn vẫn giữ điều kiện NEW/scope/quyền và giới hạn contract backend hiện có.

## Chạy local

Từ repository, mở hai terminal:

```powershell
dotnet run --project backend/LastMile/LastMile.Api --launch-profile http
```

```powershell
node frontend/dev-server.cjs
```

Mở `http://localhost:5500`, đăng nhập và chọn **Đơn hàng**. Không cần npm để chạy frontend. Server chỉ lắng nghe loopback và proxy `/api/*` tới `http://localhost:5038`, không log body/mật khẩu/token. Không hosting.

Backend khác URL/cổng:

```powershell
$env:LASTMILE_API_URL = 'http://localhost:5038'
$env:FRONTEND_PORT = '5500'
node frontend/dev-server.cjs
```

`js/config.js` dùng `API_BASE_URL: ""` để mọi trang gọi proxy cùng origin. Trong Development, backend phục vụ HTTP loopback trực tiếp, không redirect API sang HTTPS; môi trường khác vẫn dùng HTTPS redirection. Proxy giữ Authorization và body, chặn redirect của upstream bằng lỗi 502 thay vì chuyển trình duyệt sang origin khác. Nếu đặt `LASTMILE_API_URL` tới HTTPS, cần chứng chỉ được Node tin cậy (có thể dùng `NODE_EXTRA_CA_CERTS` với CA phát hành chứng chỉ); không tắt kiểm tra TLS. Backend hiện có CORS cho `http://localhost:5500` và `http://127.0.0.1:5500`. Tránh chạy thêm Live Server trên cổng 5500; dùng server Node trên đây.

## Chức năng và API

- Danh sách: `GET /api/v1/orders`, query `keyword`, `status`, `page`, `pageSize`. Tìm mã đơn/mã vận đơn, debounce 300 ms; đổi bộ lọc về trang 1. `page` 1–100000, `pageSize` 1–100. Chặn phản hồi cũ ghi đè kết quả mới.
- Form: `GET /api/v1/order-form/options`, `GET /api/v1/customers?keyword=…&page=…&pageSize=20`, `GET /api/v1/customers/{id}/addresses`. Khách hàng có tìm kiếm/phân trang riêng, đổi khách hàng xóa địa chỉ cũ ngay; chọn địa chỉ mặc định theo API. Liên hệ/điện thoại/địa chỉ lấy từ lựa chọn vì payload tạo chỉ nhận ID, không nhận thông tin liên hệ tự do.
- Tạo: `POST /api/v1/orders`. Mã đơn/mã vận đơn do backend sinh. Chặn gửi hai lần, tải danh sách và mở chi tiết khi thành công.
- Chi tiết: `GET /api/v1/orders/{id}`; thông tin, điểm lấy/giao, hàng, phí, lịch sử, vùng thông tin nội bộ. API được render bằng DOM/textContent, không đưa vào `innerHTML`.
- Sửa: `PUT /api/v1/orders/{id}`, payload tạo cộng `expectedVersion`. Chỉ ở `NEW`, đúng scope/quyền. **Hiện khóa vì API chi tiết thiếu dữ liệu cần thiết**. Đường sửa đầy đủ và xử lý 409 đã triển khai cho contract bổ sung đề xuất: giữ bản nhập, khóa gửi lại, cho tải bản mới; không tự ghi đè. Không có ô nhập version.
- Báo giá: `POST /api/v1/shipping-fees/quote`, `{branchId, serviceId, distanceKm, weightKg}`. Có ở form/chi tiết; chi tiết thiếu serviceId nên phải chọn dịch vụ báo giá rõ ràng, không suy từ tên. Kết quả chỉ tham khảo.
- Xác nhận: `POST /api/v1/orders/{id}/confirm`, `{distanceKm}`; hộp thoại đồng ý, chỉ `NEW`. Phí chính thức lấy `shippingFee` backend trả và tải lại đơn.
- Hủy: `POST /api/v1/orders/{id}/cancel`, `{reason}`; hộp thoại đồng ý, lý do không trắng, tối đa 500 ký tự. Trạng thái theo các chuyển sang CANCELLED đã đọc từ SQL seed; backend kiểm tra DB hiện hành.

Payload tạo:

```json
{
  "branchId": 1,
  "senderId": 1,
  "receiverId": 2,
  "pickupAddressId": 10,
  "deliveryAddressId": 20,
  "serviceId": 1,
  "priority": 3,
  "codAmount": 0,
  "declaredValue": 0,
  "notes": null,
  "items": [
    {
      "name": "Hàng",
      "type": null,
      "quantity": 1,
      "unitWeightKg": 1,
      "value": 0,
      "fragile": false,
      "notes": null
    }
  ]
}
```

ID trên chỉ minh họa cấu trúc; thao tác thật dùng ID API trả về. Sửa lấy `expectedVersion` từ `version` của API chi tiết hiện tại.

Validation theo controller: 1–100 hàng; tên ≤200, loại ≤100, ghi chú hàng ≤500; số lượng nguyên 1–100000; kg/đơn vị 0.001–1000000 (3 số lẻ); giá trị/COD/khai báo 0–10¹² (2 số lẻ); ưu tiên nguyên 1–5; ghi chú đơn ≤1000. Tổng khối lượng ≤999999999.999 kg; quote chỉ ≤1000000 kg. Khoảng cách thủ công 0–1000000 km (2 số lẻ); chưa tính đường đi. Trường giá trị hàng gửi nguyên `value`, không tự nhân theo số lượng.

API client đọc JSON/ProblemDetails và lỗi `errors`, hiển thị 400/403/404/409/422/lỗi mạng. Refresh token xoay vòng, gộp refresh đồng thời; refresh lỗi mạng không xóa phiên, refresh hết hạn trở về login và dọn dữ liệu đơn. Chỉ thử lại sau 401 được refresh thành công, không tự gửi lại 409/lỗi mạng. Khi thao tác ghi lỗi mạng, kiểm tra danh sách trước khi thử lại vì backend có thể đã ghi.

Phiên dùng một bản ghi `sessionStorage["tvd.session"]`: `accessToken`, `refreshToken`, `expiresAt` (ISO UTC), `user`. Bản cũ với hai key token được chuyển một lần; token luôn được đọc mới khi gửi request, Authorization chỉ có một tiền tố Bearer. Refresh thành công lưu cả hai token mới. Request 401 đến muộn dùng token vừa được refresh, không xoay thêm lần nữa; mỗi request chỉ được thử lại một lần. 401 sau lần thử lại, 403, lỗi mạng hoặc 5xx không tự xóa phiên. Chỉ refresh trả 401 hoặc lỗi DTO xác nhận refreshToken không hợp lệ mới phát `auth:expired`. JWT `exp` tính bằng giây; khi cần chuyển sang thời gian JavaScript dùng `exp * 1000`, không cộng múi giờ. Lỗi API giữ `url`, `status`, `data` để kiểm tra trong debugger, không log mật khẩu/token.

Chạy regression không dependency: `node --test frontend/tests/auth.test.cjs` hoặc `npm test` trong `frontend`. Kết quả kiểm thử API/SQL Server/Edge headless ngày 09/10/2026 tại [auth-session-verification.md](../docs/auth-session-verification.md).

Quyền hiển thị của màn hình đơn hàng dựa trên grant đã đọc từ SQL seed: tạo/báo giá ADMIN, DISPATCHER; sửa/xác nhận ADMIN, BRANCH_MANAGER, DISPATCHER; hủy ADMIN, BRANCH_MANAGER. `/auth/me` chưa trả quyền hiện hành, nên đây chỉ là gợi ý UI, không thay backend kiểm tra DB/quyền/bưu cục. Quyền tùy chỉnh cần API bổ sung. Màn hình kho dùng cơ chế quyền thực tế được mô tả bên dưới.

SQL xác định thời gian UTC bằng `SYSUTCDATETIME()`. Chuỗi DATETIME2 qua FOR JSON không offset được hiểu UTC một lần; chuỗi có Z/offset giữ nguyên. Hiển thị `vi-VN`, `Asia/Ho_Chi_Minh`, không cộng 7 giờ lần nữa.

Có công cụ Figma nhưng chưa có URL/fileKey/frame trong yêu cầu hay repository; chưa đọc/đối chiếu Figma. Giữ phong cách trắng–cam hiện tại. Không làm điều phối tự động/thuật toán/hosting.

Theo yêu cầu, đã bỏ bộ test Playwright, phụ thuộc và ảnh kết quả; không cần cài công cụ test để chạy web.

Các giới hạn API vẫn được ghi tại [orders-api-gaps.md](../docs/orders-api-gaps.md). Luồng sửa còn cần backend bổ sung dữ liệu chi tiết; chưa kiểm thử luồng ghi/backend có token bằng tài khoản thử.

## Quản lý kho

### Nhập kho

Route `#/warehouse/inbound` dùng `js/inbound.js`: một tiêu đề/một bảng, bộ lọc Kho/Vị trí/Mã đơn hoặc mã vận đơn/Trạng thái. **Làm mới kho** chỉ đọc lại danh mục kho/vị trí và giữ lựa chọn còn hợp lệ; **Làm mới danh sách** đọc lại đơn theo các trường lọc hiện tại. **Lọc**, Enter và **Xóa bộ lọc** đưa về trang 1; Xóa giữ kho/vị trí và số dòng, mặc định hiển thị cả CONFIRMED + WAITING_INBOUND. Kho được nhớ chung với các màn hình kho khác theo tài khoản; URL giữ thêm locationId/bộ lọc cho F5/Back.

API danh sách vẫn là `GET /api/v1/orders`, bổ sung tùy chọn `warehouseId` và `inboundOnly=true`. Khi nhập kho, SQL lọc đúng bưu cục của kho, chỉ hai trạng thái hợp lệ, `MaKhoHienTai IS NULL` và chưa có dòng TonKhoDonHang; áp dụng trước COUNT/OFFSET/FETCH. Request cũ không gửi hai tham số này giữ hành vi cũ. `warehouseId` phải hoạt động và thuộc scope tài khoản; `inboundOnly` cần warehouseId. Kho/vị trí rỗng trả `[]` đúng contract thay vì lỗi cast DBNull.

Chưa chọn vị trí hợp lệ hoặc thiếu KHO_NHAP thì nút Nhập kho bị khóa. Mở thao tác đọc lại đơn/quyền/vị trí đang hoạt động, có ghi chú ≤500 ký tự và bước Xem và xác nhận → Xác nhận nhập kho. Dùng ID API thật, khóa từ bước chuẩn bị modal đến lúc gửi để chặn click liên tiếp. POST inbound hiện hữu không thay route/DTO. 201 đóng modal và tải lại một danh sách; 409 khóa bản xác nhận và tải lại, không gửi lại; 403 giữ phiên. Lỗi mạng/5xx khóa bản cũ, có **Kiểm tra trạng thái đơn** trước khi mở thao tác mới. 400 hiển thị validation trong form và yêu cầu xác nhận lại.

Bằng chứng API/SQL Server/Edge desktop + 390px: [inbound-ui-verification.md](../docs/inbound-ui-verification.md). Build và khởi động lại backend hiện có để nhận các query mới, rồi tải lại frontend; không cần framework/npm dependency mới.

Sidebar **Kho** gồm Tồn kho, Nhập kho, Xuất kho / bàn giao, Nhập hàng hoàn, Vị trí lưu kho và Lịch sử giao dịch. Chọn kho từ API trong phạm vi tài khoản; vị trí lấy theo kho. Đổi kho xóa dữ liệu/bộ lọc/vị trí cũ, đóng modal và bỏ phản hồi cũ. Kho đang chọn được nhớ trong bộ nhớ khi chuyển màn hình, xóa khi đăng xuất.

| Chức năng                 | API                                                            | Quyền backend          |
| ------------------------- | -------------------------------------------------------------- | ---------------------- |
| Kho / vị trí / tồn kho    | `GET /api/v1/warehouses`, `/{id}/locations`, `/{id}/inventory` | `KHO_XEM`              |
| Nhập kho                  | `POST /api/v1/warehouse-transactions/inbound`                  | `KHO_NHAP`             |
| Chuyển vị trí             | `POST /api/v1/warehouse-transactions/move`                     | `KHO_KIEMKE`           |
| Chờ phân công             | `POST /api/v1/orders/{id}/ready-for-dispatch` (không body)     | `KHO_NHAP`             |
| Quyền tài khoản hiện tại  | `GET /api/v1/auth/permissions`                                 | Đã đăng nhập           |
| Danh sách bàn giao        | `GET /api/v1/warehouses/{id}/handover-orders`                  | `KHO_XEM`              |
| Xuất / bàn giao từng đơn  | `POST /api/v1/warehouse-transactions/outbound`                 | `KHO_XUAT`             |
| Nhập hàng hoàn            | `POST /api/v1/warehouse-transactions/return-in`                | `KHO_NHAP`             |
| Yêu cầu hoàn đủ điều kiện | `GET /api/v1/warehouses/{id}/return-requests`                  | `KHO_XEM` + `KHO_NHAP` |
| Lịch sử / chi tiết        | `GET /api/v1/warehouse-transactions`, `/{id}`                  | `KHO_XEM`              |

Các API còn kiểm tra tài khoản, bưu cục, kho/vị trí hoạt động và điều kiện đơn. UI đọc quyền DB hiện hành cho mọi tài khoản từ `GET /api/v1/auth/permissions`, response `{accountId, permissions: ["KHO_XEM", ...]}`. Endpoint chỉ trả quyền của chính tài khoản đang đăng nhập. Các nút ghi ẩn khi chưa xác minh quyền hoặc thiếu quyền; không suy quyền từ seed/tên vai trò. Backend kiểm tra lại quyền khi POST.

Tồn kho lọc bằng `keyword` (mã đơn/mã vận đơn), `locationId`, `orderStatus`, phân trang `page`/`pageSize`. Controller áp dụng các bộ lọc trước khi đếm và phân trang. Nút Lọc áp dụng các lựa chọn; Xóa bộ lọc giữ kho và số dòng, xóa vị trí/trạng thái/từ khóa và về trang 1. Đổi kho xóa bộ lọc, tải vị trí mới và bỏ response cũ. Số dòng nằm cạnh phân trang cuối bảng. Mã đơn/mã vận đơn chung một ô, rút gọn bằng ellipsis, có title/mã đầy đủ trong chi tiết và hai nút sao chép. Thời gian DATETIME2 được xác minh là UTC từ schema và controller nhập kho; UI đổi sang Asia/Ho_Chi_Minh. Trạng thái tồn kho hiển thị riêng với trạng thái đơn. Mở đơn bằng component chi tiết hiện có ở chế độ xem khi có DONHANG_XEM; sửa đơn vẫn thuộc trang Đơn hàng và điều kiện nghiệp vụ hiện hữu. Lịch sử mỗi dòng tái sử dụng danh sách giao dịch, cố định kho + orderId và mở chi tiết giao dịch hiện có. Backend không hỗ trợ keyword cho lịch sử. Nhãn Việt hóa vẫn gửi nguyên INBOUND/MOVE/OUTBOUND/RETURN_IN.

Nhập kho chỉ chọn đơn CONFIRMED/WAITING_INBOUND ở bưu cục của kho, đọc lại chi tiết trước mở form. Chuyển vị trí đọc lại tồn kho, khớp chính xác orderId, lấy fromLocationId mới nhất, chọn đích khác nguồn trong cùng kho. Xuất lấy assignmentId và nguồn từ handover-orders vừa tải, chỉ cho thao tác khi canHandover=true và nhiệm vụ ACCEPTED. Đây là xuất từng đơn, không giả lập shipper nhận nhiệm vụ/nhận hàng.

Mỗi form ghi có bước **Xem và xác nhận → Đồng ý gửi** và chặn gửi trùng. Sau thành công tải lại tồn kho, giao dịch và danh sách liên quan. Khi 409 tải lại danh sách nhưng khóa bản thao tác cũ, không thay source rồi tự gửi lại. Lỗi mạng/5xx cũng khóa gửi lại bản cũ để kiểm tra lịch sử trước khi mở thao tác mới. Ghi chú tối đa 500 ký tự.

Các điều kiện cần lưu ý:

- **Chờ phân công:** controller OrderReadyForDispatchController đã có route POST ready-for-dispatch, không body. UI hiện theo KHO_NHAP, chỉ bật cho IN_WAREHOUSE + STORED, đọc lại tồn kho trước modal xác nhận. Backend quyết định điều kiện cuối cùng. Thành công tải lại danh sách; 409 thông báo, tải lại và khóa yêu cầu cũ; không tự gửi lại. Nút ghi khóa trong lúc gửi để tránh trùng thao tác.
- **Nhận hoàn:** chọn yêu cầu từ `GET /api/v1/warehouses/{id}/return-requests`, không nhập ID thủ công. Danh sách chỉ gồm RETURN/IN_PROGRESS, đơn RETURNING chưa có kho hiện tại, hoàn về bưu cục gốc, tồn cũ HANDED_OVER, không còn phân công đang hoạt động. Form đọc lại yêu cầu đã chọn trước khi gửi return-in. Condition NORMAL/DAMAGED/OTHER, ghi chú bắt buộc với DAMAGED/OTHER.

Kiểm tra cũ trước ngày 07/10 dùng response mô phỏng trong bộ nhớ và đã bỏ sót lỗi items rỗng. Các lần kiểm tra mới dưới đây dùng API/SQL Server thật trên database riêng; dữ liệu chạy bình thường luôn lấy từ API thật.

Đã sửa lỗi response rỗng thiếu `items`: OrdersController, WarehousesController và WarehouseHandoverOrdersController dùng `JSON_QUERY(COALESCE((...FOR JSON PATH), N'[]'))`. Frontend không bỏ validation hay tự thay items thiếu thành mảng rỗng; kiểm tra cả page/pageSize/totalItems/items và ID bắt buộc. Tồn kho rỗng hợp lệ hiển thị **Không có hàng phù hợp**; các danh sách khác hiển thị **Không có dữ liệu.** API client giữ validation; giao diện kho dùng thông báo dễ hiểu, không lộ endpoint/Content-Type hoặc lỗi kỹ thuật.

Kiểm tra Tồn kho ngày 08/10/2026: build backend 0 warning/error, cú pháp JS đạt; HTTP/Edge headless với backend + SQL Server thật trên database thử riêng. Đã thử desktop 1440px và màn hình 390px, lọc/xóa/phân trang, dữ liệu/rỗng, chi tiết/move/lịch sử, ready thành công/409, thu hồi quyền 403, refresh token và hết phiên 401, nhập/xuất qua modal thật. Lỗi 500 được tiêm có kiểm soát chỉ để kiểm tra thông báo/thử lại; không thay response dữ liệu thành dữ liệu giả. Chi tiết và giới hạn tại [inventory-ui-verification.md](../docs/inventory-ui-verification.md). Báo cáo cũ ngày 07/10 tại [warehouse-list-response-fix.md](../docs/warehouse-list-response-fix.md).

Chi tiết đơn dùng chung route `#/orders/:id`, một renderer thay nội dung cũ và hủy request khi rời trang/làm mới. Mở từ Kho mang query `returnTo` chứa route danh sách nội bộ đã kiểm tra; Quay lại giữ kho, trang và bộ lọc. Đường từ chi tiết giao dịch kho quay về danh sách giao dịch tương ứng. Không chấp nhận URL bên ngoài hoặc returnTo lồng nhau. API/JWT và xử lý thời gian UTC hiện hữu giữ nguyên.

Layout desktop dùng sidebar 256px và main grid chiếm phần còn lại. Header sticky nằm trong luồng; chỉ menu sidebar cuộn, footer tài khoản/đăng xuất cố định trong sidebar. Dưới 992px dùng menu đóng/mở, Escape/backdrop/đổi route/resize đều dọn trạng thái cuộn và inert. Chi tiết gồm thông tin chung, Phí/COD, người gửi/nhận, bảng hàng hóa, lịch sử và dữ liệu kỹ thuật mở rộng; tên phí Việt hóa chỉ khi trình bày.

Kiểm tra layout ngày 09/10/2026: **19 test auth/proxy/router** và **37 kiểm tra Edge** ở 1366×768, 1920×1080, 768×1024, 390×844 đạt. Dữ liệu của đúng hai đơn hiện có #1/#2 được đọc bằng SQL của controller theo phạm vi người dùng cho phép, chỉ giữ trong bộ nhớ; auth/transport trong browser QA là adapter riêng, không phải kiểm thử API đăng nhập thật. Không tạo hoặc sửa dữ liệu. Báo cáo, ảnh và giới hạn: [order-detail-ui-verification.md](../docs/order-detail-ui-verification.md).

Chạy regression: `node --test frontend/tests/auth.test.cjs frontend/tests/router.test.cjs` từ thư mục dự án. QA layout đọc hai đơn thực là thao tác chạy riêng: `node frontend/tests/order-detail-browser.cjs`, yêu cầu Windows/Edge/LocalDB và quyền đọc hai đơn #1/#2; dùng cổng OS cấp, không mở thêm server ở 5500/5038/7255. Script chỉ lưu ảnh/metrics, tự xóa profile thử, không lưu payload/JWT.

Biên nhận nhận kiện (STT 13): mở từ chi tiết đơn hoặc nút cạnh mã đơn trong danh sách tồn/nhập kho. Xem giờ/tình trạng/GPS và ảnh lúc tài xế nhận, theo quyền xem đơn/kho và bưu cục. Chưa có dữ liệu cũ không tự đánh dấu Nguyên vẹn. Cần [migration và hướng dẫn](../docs/shipper-pickup-condition.md).

Mục 15 — **Sự cố nhận kiện / Xử lý** trong Xuất kho hoặc chi tiết đơn: xem ảnh/lịch sử, yêu cầu tài xế bổ sung và đóng hồ sơ có hướng dẫn; kiểm tra quyền xem/xử lý và phiên bản hiện tại trên API. Xem [SQL mới, luồng xử lý và kiểm chứng](../docs/shipper-pickup-issues.md).
