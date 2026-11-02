# Trang Báo cáo — 17/10/2026

Giao diện đã được thu gọn trong lần tiếp theo, giữ nguyên API/cách tính. Xem [thay đổi và 88 kiểm tra giao diện mới](reports-ui-refinement-verification.md); ảnh sau sửa ở `reports/compact/`.

Đã triển khai trực tiếp `#/reports` bằng HTML/CSS/JavaScript thuần và Bootstrap, dùng dữ liệu từ backend. Giữ header, sidebar, đăng nhập và API client hiện có. Không sửa schema hay dữ liệu vận hành; không thêm thư viện frontend.

## Tệp triển khai

- `frontend/js/reports.js`: bộ lọc ngày Việt Nam/bưu cục, chọn nhanh, ba tab, thẻ số liệu, SVG và bảng dữ liệu, phân trang, CSV, hủy request và chặn response cũ.
- `frontend/js/router.js`: quyền `BAOCAO_XEM`, query `from`, `to`, `branchId`, `tab`, `page`, `pageSize`.
- `frontend/js/app.js`: mount/destroy trang, tiêu đề và mô tả.
- `frontend/index.html`: nạp module, cập nhật phiên bản asset.
- `frontend/assets/css/styles.css`: bố cục trắng cam, thẻ, tab, biểu đồ và bảng responsive.
- `backend/LastMile/LastMile.Api/Controllers/ReportsDashboardController.cs`: mở rộng tham số trên endpoint hiện có, tái sử dụng xác thực/phạm vi/ngày; tránh chạy các truy vấn dashboard không cần thiết khi xem tab báo cáo.
- `backend/LastMile/LastMile.Api/Controllers/ReportsQuery.cs`: tổng hợp và phân trang SQL cho ba tab.
- `frontend/package.json`, `frontend/tests/router.test.cjs`, `reports.test.cjs`, `reports-browser.cjs`, `reports-checks.cjs`, `reports-fixture.ps1`, `reports-fixture.sql`: lệnh chạy, unit test và kiểm tra tích hợp cách ly.

## API

Tái sử dụng **GET `/api/v1/reports/dashboard`**, không tạo endpoint trùng.

Ví dụ:

```text
/api/v1/reports/dashboard?report=orders&from=2026-10-01&to=2026-10-17&page=1&pageSize=10
/api/v1/reports/dashboard?report=delivery&from=2026-10-01&to=2026-10-17&branchId=1
/api/v1/reports/dashboard?report=finance&from=2026-10-01&to=2026-10-17&export=true
```

- Không truyền `report`: giữ cấu trúc và định nghĩa dashboard trước đây. Kiểm tra hồi quy đã gọi nhánh này.
- `report=orders|delivery|finance`: trả `summary`, `items`, `totalItems`, `page`, `pageSize`, `branches`, `dailyOrders`, `ordersByStatus`, khoảng ngày, phạm vi và thời điểm tạo báo cáo UTC.
- `export=true`: backend trả **tất cả dòng tổng hợp** thuộc bộ lọc; frontend tạo CSV UTF-8 BOM. Quyền và phạm vi kiểm tra lại ở backend, kể cả khi xuất.
- Phân trang ở SQL: `page` 1–100000, `pageSize` 1–100. Các thẻ luôn lấy tổng toàn bộ kết quả, không cộng một trang.
- Backend đọc tài khoản/vai trò/quyền đang có hiệu lực từ database. `ADMIN` được xem toàn hệ thống hoặc chọn bưu cục; vai trò khác phải có `BAOCAO_XEM` và chỉ được xem bưu cục của mình. Sửa query sang bưu cục khác nhận 403.
- Ngày nhận dạng `yyyy-MM-dd`, từ 1900-01-01 đến 9999-12-30, tối đa 366 ngày tính cả hai đầu. Truy vấn UTC theo `>= 00:00 UTC+7 ngày đầu` và `< 00:00 UTC+7 ngày kế tiếp ngày cuối`.

## Định nghĩa chỉ số

### Đơn hàng

Tập dữ liệu: **đơn tạo trong kỳ, trạng thái hiện tại khi xem**. Bưu cục lấy từ đơn. Một dòng đơn gốc được tính một lần, không join lịch sử/lần giao vào tổng đơn.

| Chỉ số | Định nghĩa |
| --- | --- |
| Tổng đơn tạo | Số đơn có `ThoiGianTao` trong khoảng UTC tương ứng ngày Việt Nam đã chọn |
| Giao thành công (hiện tại) | Các đơn trong tập trên hiện có trạng thái `DELIVERED` hoặc `COMPLETED` |
| Thất bại (hiện tại) | Các đơn trong tập trên hiện có trạng thái `FAILED`; không cộng `RETRY_WAITING` hay lịch sử thất bại |
| Hủy / hoàn | Các đơn trong tập trên hiện có trạng thái `CANCELLED`, `RETURNING` hoặc `RETURNED` |
| Số đơn theo ngày | Nhóm cùng tập đơn theo ngày tạo UTC+7, ngày không có đơn điền 0 |
| Phân bố trạng thái | Nhóm cùng tập đơn theo trạng thái hiện tại; tổng các nhóm bằng tổng đơn |
| Tổng hợp bưu cục | Các chỉ số trên nhóm theo bưu cục của đơn; hiện khi tài khoản có thể xem nhiều bưu cục |

Không gọi số đơn hiện thành công là số đơn **được giao thành công trong kỳ**.

### Hiệu suất giao hàng

| Chỉ số | Định nghĩa |
| --- | --- |
| Phân công trong kỳ | Số bản ghi `PhanCongGiaoHang` có ngày phân công trong kỳ, gồm mọi trạng thái phân công; không phải số đơn duy nhất |
| Lần giao trong kỳ | Số bản ghi `LanGiaoHang` có thời điểm thử giao trong kỳ; một đơn được phép có nhiều lần |
| Lần thành công | Số lần giao trên có `KetQua=SUCCESS` |
| Lần thất bại | Số lần giao trên có `KetQua=FAILED` |
| Tỷ lệ thành công | `100 × lần SUCCESS / tổng lần giao`; mẫu số 0 trả `null`, UI/CSV hiển thị `—` |

Phân công và lần giao là hai tập sự kiện độc lập theo thời gian riêng. Kết quả lần giao gắn nhân viên qua khóa `LanGiaoHang.MaPhanCongGiaoHang` và `MaDonHang`, không lấy shipper hiện tại. Bảng nhóm theo nhân viên và bưu cục **của đơn**, sắp theo mã ổn định, không xếp hạng theo số thành công. Tooltip nêu công thức và số lần giao làm mẫu số. Không đưa tỷ lệ đúng hẹn/thời gian trung bình vì chưa có định nghĩa nghiệp vụ đủ chặt.

### Cước phí và COD

Mỗi đơn có một dòng trung gian tiền; các phân bổ nộp tiền được tổng hợp trước khi cộng theo bưu cục. Không cộng lặp toàn bộ phiếu nộp khi phiếu có nhiều đơn. Tiền tính bằng `DECIMAL` trong SQL; tổng phân bổ từng đơn chuyển về `DECIMAL(28,2)` trước phép trừ để giữ hai chữ số thập phân. UI dùng VNĐ.

| Chỉ số | Định nghĩa |
| --- | --- |
| Tổng cước phí trên đơn | Tổng `PhiVanChuyen` của **mọi đơn tạo trong kỳ, kể cả đơn hủy**. Chưa phải doanh thu thực thu |
| COD đã thu trong kỳ | Tổng `SoTienThucThu` của bản ghi hiện `COLLECTED`/`PARTIAL`, có `ThoiGianThuTien` trong kỳ |
| Nộp được xác nhận trong kỳ | Tổng `ChiTietNopTienCOD.SoTienPhanBo` theo đơn trong phạm vi, phiếu hiện `CONFIRMED`, `ThoiGianXacNhan` trong kỳ; không dùng ngày lập/nộp phiếu |
| Số dư đầu kỳ | COD thu trước đầu kỳ trừ phân bổ nộp hiện được xác nhận trước đầu kỳ |
| Số dư cuối kỳ | COD thu trước mốc kết thúc loại trừ trừ phân bổ nộp được xác nhận trước cùng mốc. Bằng đầu kỳ + thu trong kỳ − nộp được xác nhận trong kỳ |
| Còn phải nộp cuối kỳ | Tổng `max(số dư cuối kỳ từng đơn, 0)`, không bù khoản nộp thừa của đơn khác |
| Phiếu hiện chờ xác nhận đến cuối kỳ | Phân bổ từ phiếu **hiện `PENDING`**, có ngày nộp trước mốc kết thúc loại trừ; gồm phiếu từ trước kỳ |
| Còn có thể lập phiếu | Tổng `max(số dư cuối kỳ từng đơn − phân bổ hiện PENDING từng đơn, 0)` |

`REJECTED`/`CANCELLED` không tính vào tiền nộp xác nhận hoặc tiền đang chờ. `WAIVED`/`REVERSED` không tính là COD thu. COD không phải doanh thu. Không trình bày số tiền đã đối soát/trả khách hàng khi chưa có đủ dữ liệu nghiệp vụ đó.

## CSV và trạng thái giao diện

- Xuất toàn bộ bảng tổng hợp đang xem; kèm tổng cộng, khoảng ngày Việt Nam, phạm vi, đơn vị tiền, định nghĩa và thời điểm tạo. Tab đơn hàng xuất thêm phân bố trạng thái và chuỗi ngày.
- CSV có BOM UTF-8, CRLF, quote/escape dấu nháy, dấu phẩy và xuống dòng. Ô văn bản có ký tự công thức `= + - @` sau khoảng trắng/ký tự điều khiển được thêm apostrophe; số âm thực vẫn là số.
- Mỗi lần tải mới hủy request cũ, kiểm tra generation trước khi render. Rời route hủy request xem/xuất; DOM, SVG và listener thuộc trang được bỏ theo lifecycle.
- Bộ lọc chưa áp dụng có thông báo riêng và khóa xuất; chỉnh bộ lọc trong lúc request/xuất đang chạy không được xuất kết quả cũ.
- Phân biệt đang tải, không có dữ liệu, 403 và lỗi kết nối/API; không đổi lỗi thành 0 hoặc gán mọi lỗi thành hết phiên đăng nhập.

## Kiểm tra đã chạy

- Build `.NET`: **0 lỗi, 0 cảnh báo**.
- `npm.cmd test --prefix frontend`: **35/35** unit/regression tests đạt, gồm ngày không hợp lệ/năm nhuận/366 ngày, CSV tiếng Việt/chống công thức, query và quyền router, hồi quy đăng nhập/API client.
- `node frontend/tests/reports-browser.cjs`: kiểm tra API ASP.NET thật, proxy thật và Edge headless trên database LocalDB GUID riêng, import schema/seed của dự án; JWT test dùng signing key riêng. Số mục đạt và kết quả máy đọc tại [reports-verification.json](reports/reports-verification.json).
- Bao phủ đơn có dữ liệu/rỗng, thẻ/biểu đồ/bảng khớp; ranh giới UTC 17:00; phạm vi admin/bưu cục, sửa query và xuất trái quyền; nhiều phân công/lần giao, nhân viên mới không nhận thành công của người cũ; mẫu số 0; COD đầu kỳ/thu/nộp khác kỳ, phiếu PENDING/REJECTED/CANCELLED và số tiền có phần thập phân; phân trang/xuất tất cả trang; tab/F5; lỗi 500/403; response đến muộn và abort khi rời trang.
- Ảnh: [Đơn hàng 1440](reports/orders-1440.png), [768](reports/orders-768.png), [390](reports/orders-390.png), [Hiệu suất 1440](reports/delivery-1440.png), [390](reports/delivery-390.png), [COD 1440](reports/finance-1440.png), [390](reports/finance-390.png). Kiểm tra không tràn ngang trang, bảng/tab có cuộn riêng.
- Database và profile trình duyệt test được dọn sau khi chạy. Không sửa database vận hành. LocalDB/Edge cần quyền truy cập ngoài sandbox mặc định trong môi trường hiện tại.

Chạy lại từ thư mục `frontend`:

```powershell
npm.cmd test
npm.cmd run test:reports
```

## Giới hạn còn lại

- API danh sách đơn chưa hỗ trợ cùng điều kiện ngày tạo và bưu cục, nên không tạo liên kết chỉ số sang danh sách có kết quả khác. Chưa bổ sung API danh sách trùng.
- Schema chưa có lịch sử thời điểm đảo thu và mọi lần chuyển trạng thái phiếu. Các số dư được tính bằng thời điểm thu/xác nhận còn lưu và **trạng thái bản ghi hiện tại**, không đảm bảo tái lập ảnh chụp kế toán trong quá khứ nếu có đảo/hủy sau kỳ. UI nêu rõ; pending là phiếu hiện chờ có ngày nộp trước hết kỳ, không khẳng định là trạng thái chờ tại ngày quá khứ.
- Chưa có sổ doanh thu thực thu và thực trả COD cho khách hàng. Không suy ra các số này từ cước phí, COD hoặc trạng thái đối soát.
- Kiểm tra dùng dữ liệu thật qua backend trên **fixture cách ly**, không xác nhận số liệu của môi trường vận hành, tải lớn hoặc thiết bị di động vật lý.
- Chưa thêm PDF/Excel theo đúng phạm vi yêu cầu.
