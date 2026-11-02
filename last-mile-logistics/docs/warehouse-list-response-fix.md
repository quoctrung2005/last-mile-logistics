# Sửa response danh sách Kho — 07/10/2026

## Nguyên nhân đã tái hiện

Thông báo ban đầu được ném ở `frontend/js/warehouse.js` trong createList/reload, khi `items` không phải array hoặc totalItems không phải số. Màn hình đơn có kiểm tra tương tự trong orders.js. Nay dùng chung `ApiClient.validatePage`, vẫn bắt buộc schema và ID; lỗi chỉ rõ endpoint và trường sai.

Đã thực thi SQL của controller trên database vận hành theo chế độ đọc. Với CONFIRMED/RETURNING và handover-orders rỗng, SQL trả:

```json
{"page":1,"pageSize":10,"totalItems":0}
```

Không phải lỗi HTTP 403 hay dữ liệu số bị biến thành chuỗi. Scalar subquery `(...FOR JSON PATH)` không có dòng trả SQL NULL. JSON_QUERY nhận NULL và FOR JSON ngoài không có INCLUDE_NULL_VALUES nên bỏ cả field items. Tồn kho có cùng lỗi. Kiểm tra mô phỏng trước đây luôn dựng items:[], nên chưa phát hiện lỗi này.

Sửa OrdersController, WarehousesController và WarehouseHandoverOrdersController:

```sql
JSON_QUERY(COALESCE(( ... FOR JSON PATH, INCLUDE_NULL_VALUES ), N'[]')) AS items
```

Response sau sửa:

```json
{"page":1,"pageSize":10,"totalItems":0,"items":[]}
```

Frontend giữ validation. Không tự đổi items thiếu thành [] và không chuyển mọi lỗi API thành danh sách rỗng. List rỗng hợp lệ hiển thị “Không có dữ liệu.” API client báo riêng HTTP/Content-Type nếu success response không phải JSON hợp lệ, vẫn xử lý ProblemDetails khi lỗi nghiệp vụ.

## Nhập hoàn

Không có GET yêu cầu hoàn phù hợp cho nhân viên kho trong source/Swagger trước sửa; `/my/tasks` chỉ cho SHIPPER. Đã thêm một route đọc duy nhất:

`GET /api/v1/warehouses/{id}/return-requests`

- Quyền thực tế KHO_XEM + KHO_NHAP, tài khoản/vai trò hoạt động, không khóa; non-admin chỉ kho trong bưu cục tài khoản.
- Kho/bưu cục hoạt động; RETURN/IN_PROGRESS; đơn RETURNING, warehouseId hiện tại null; tồn cũ HANDED_OVER; về bưu cục gốc; không có phân công chưa kết thúc.
- Query keyword, orderId, returnRequestId, page, pageSize có validation.
- Response pagination luôn có items array, canReturnIn boolean sau kiểm tra quyền.
- UI chọn request từ API, kiểm tra lại requestId/orderId trước mở form, giữ validation condition/notes và POST return-in hiện hữu. Nhân viên kho dùng capability, không suy quyền từ role và không cần đọc roles admin.

## ready-for-dispatch

Đã tìm toàn bộ source và Swagger của backend đang chạy/bản build kiểm tra: không có `POST /api/v1/orders/{id}/ready-for-dispatch`. Không tạo route mới/trùng hoặc dùng route đoán; không đổi trạng thái client. Nút và thông báo thiếu hỗ trợ được giữ vì chưa có hoạt động thật để xác minh. Chuỗi nhập → move → chờ phân công chưa thể hoàn tất.

## Kiểm tra đã thực hiện

Backend build 0 warning / 0 error; JavaScript thay đổi qua node --check.

Các SQL truy vấn trên database vận hành được đọc lại sau sửa: danh sách tổng có 14 đơn; các lọc rỗng đã có items:[].

HTTP regression chạy **API ASP.NET Core thật, SQL Server thật, JWT cấp qua auth/login bình thường** trên database tạm mới riêng `CodexWarehouseFix_<GUID>`. Schema/dataset của repository chỉ được chạy vào database này; fixture đủ điều kiện được chuẩn bị tại đây, không sửa đơn/tài khoản/COD vận hành. Không mock JSON HTTP. Database và tài khoản thử được xóa sau kiểm tra; không log mật khẩu/token.

| Request | Kết quả có dữ liệu | Kết quả lọc rỗng |
| --- | --- | --- |
| orders?status=CONFIRMED | 200 application/json, 1 item | 200 application/json, items:[] |
| orders?status=RETURNING | 200 application/json, 1 item | 200 application/json, items:[] |
| warehouses/{id}/handover-orders | 200 application/json, 1 item | 200 application/json, items:[] |
| warehouses/{id}/inventory | 200 application/json, 2 items | 200 application/json, items:[] |
| warehouses/{id}/return-requests | 200 application/json, 1 item | 200 application/json, items:[] |

Đã kiểm tra số nguyên page/pageSize/totalItems, items array, các ID bắt buộc, lọc lại đúng requestId/orderId. API yêu cầu hoàn với page=0 trả 400 application/problem+json; chưa đăng nhập 401; thiếu quyền 403 application/json; kho không tồn tại/ngoài bưu cục 404 application/json. Nhân viên kho xem được kho của mình và yêu cầu đủ điều kiện.

Edge headless dùng frontend hiện tại qua proxy tới API thử, **không intercept/mock API**: bốn màn hình Tồn kho/Nhập kho/Xuất kho/Nhập hoàn đều hiển thị đúng có dữ liệu/rỗng, không còn lỗi schema. Admin và nhân viên kho đều chọn yêu cầu hoàn, form không còn input request ID thủ công. Hàm validation vẫn từ chối response thiếu items. Không có lỗi JavaScript.

Checksum trạng thái/version/kho/COD/phí các đơn trong database vận hành trước và sau kiểm tra bằng nhau. Database thử và công cụ kiểm tra tạm được dọn; không thêm bộ test hay sửa node_modules.

Giới hạn: chưa xác minh bằng phiên đăng nhập hiện tại của người dùng vào database vận hành vì chưa nhận tài khoản/token thử; chưa thử POST return-in hoàn tất trên database vận hành và không gọi thao tác ghi lên đơn vận hành. ready-for-dispatch vẫn thiếu endpoint. Các kiểm tra HTTP có dữ liệu nêu trên thuộc database thử riêng, không phải dữ liệu hiển thị giả trong ứng dụng.
