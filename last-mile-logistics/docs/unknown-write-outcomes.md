# Kết quả ghi chưa xác định

Các form trong customers.js, shippers.js, accounts.js, admin-ui.js, cod.js và dispatch.js dùng chung write-outcome.js. Khi `error.resultUnknown === true`:

- Hiển thị “Chưa xác định được kết quả lưu. Hãy kiểm tra dữ liệu trước khi thực hiện lại.”
- Khóa thao tác ghi ở cả nút và hàm gửi; giữ nội dung nhập, không thay form bằng dữ liệu tải lại. Trường văn bản chỉ đọc vẫn có thể chọn/sao chép.
- Nút “Tải lại để kiểm tra” chỉ gọi GET, hiển thị bản ghi và các trang kết quả trong vùng đối chiếu riêng. GET thành công, danh sách rỗng, lỗi đọc hoặc trạng thái vẫn PENDING không tự mở khóa.
- Giữ dấu vân tay của lần ghi chưa rõ kết quả trong sessionStorage theo tài khoản. Mở lại form/tải lại tab không cho gửi lại cùng request đó. Không lưu payload, ghi chú, mật khẩu hay token; trường bí mật được loại khỏi dữ liệu tạo dấu vân tay. Không gửi dấu vân tay thành header tới backend.

Validation và HTTP 409 tiếp tục đi theo luồng hiện có khi không có cờ resultUnknown. ApiClient chỉ tự refresh/replay các request đọc sau 401; POST/PATCH/PUT/DELETE không tự gửi lại và không thêm Idempotency-Key.

| Nghiệp vụ | API đọc dùng để đối chiếu |
| --- | --- |
| Khách hàng/địa chỉ | GET /api/v1/customers/{id}?includeInactiveAddresses=true; tạo mới dùng danh sách khách hàng, tìm theo điện thoại/tên, mọi trạng thái |
| Tài khoản/thao tác tài khoản | GET /api/v1/accounts?id={id}; tạo mới dùng danh sách theo username |
| Shipper/xe | GET /api/v1/shippers?id={id}; tạo mới dùng danh sách, không lọc chỉ nhân viên đang hoạt động |
| Danh mục, vai trò, quy tắc cước | GET /api/v1/catalogs?type=..., /api/v1/roles?id=... hoặc keyword=..., /api/v1/shipping-fees/rules?id=... |
| Lập phiếu nộp/tạo phiên đối soát | GET /api/v1/cod/deposits hoặc /api/v1/cod/reconciliations theo bưu cục/shipper, gồm mọi trạng thái, có phân trang |
| Xác nhận nhận tiền/đối soát | GET /api/v1/cod/deposits/{id}; GET /api/v1/cod/reconciliations?id={id} |
| Phân công/đổi người giao/hủy | GET /api/v1/dispatch/assignments theo orderId khi có; giữ cả lịch sử |
| Chuyến giao | GET /api/v1/trips?id={id}; tạo mới dùng danh sách chuyến theo bưu cục |
| Tạo đề xuất tuyến | GET /api/v1/dispatch/orders?ids=... chỉ đối chiếu trạng thái đơn; không xác minh được ID đề xuất vừa tạo |
| Xác nhận đề xuất | GET danh sách chuyến để đối chiếu; không coi việc đọc lại đề xuất là bằng chứng chưa xác nhận |

## Phần backend còn thiếu

Chưa có hợp đồng tra cứu kết quả theo một mã lần ghi để biết chắc thao tác đã hoàn tất hay đã kết thúc thất bại. Không thể suy luận thất bại từ một GET trong lúc request trước có thể còn chạy.

- POST tạo phiếu nộp, phiên đối soát, khách hàng, địa chỉ, tài khoản, shipper, chuyến: mất phản hồi có thể mất luôn ID mới. Dữ liệu giống nhau trong danh sách chỉ hỗ trợ đối chiếu, không định danh chắc chắn lần ghi đó.
- POST /dispatch/plans: hiện chỉ có GET theo ID đề xuất, không có API tìm lần tạo khi mất ID.
- GET /dispatch/plans/{id} chỉ trả ResultJson, không trả ConfirmedJson/trạng thái kết quả lần xác nhận. Không dùng nó để mở lại nút xác nhận.
- Đặt lại mật khẩu: GET tài khoản không cho biết mật khẩu mới đã được đặt bởi lần gửi nào. Không thử đăng nhập hoặc gửi lại thao tác để “kiểm tra”.

Vì vậy bản sửa không có nút tự xóa khóa hoặc coi GET là xác nhận thất bại. Cần xác minh nghiệp vụ/quản trị hoặc bổ sung hợp đồng kết quả giao dịch phía backend trước khi cho phép phát lại một lần ghi chưa rõ kết quả. Khóa ở trình duyệt không thay thế chống trùng phía backend và không bảo đảm chống lặp giữa thiết bị/tab khác.

## Kiểm tra

write-outcome.test.cjs chạy các hàm submit thật với API giả lập: khách hàng, tài khoản, shipper/xe, quản trị, tạo/xác nhận phiếu nộp, tạo/xác nhận đối soát, phân công, tạo/sửa/hủy chuyến. Kiểm tra gửi lần hai, đọc lại thành công/rỗng/lỗi, checkbox COD, dữ liệu nhập, mở lại form, HTTP 409 và validation bình thường. dispatch-validity.test.cjs kiểm tra thêm ghi đề xuất/xác nhận. auth.test.cjs kiểm tra các method ghi gặp 401 vẫn chỉ gửi một lần. Không dùng database.
