# Thu hộ COD và Đối soát COD — 17/10/2026

Đã triển khai trực tiếp `#/cod/collections` và `#/cod/reconciliation`, thay placeholder. HTML/CSS/JavaScript thuần, Bootstrap và giao diện trắng cam; giữ header, sidebar, API client và đăng nhập hiện có. Không sửa schema hoặc dữ liệu vận hành.

## Luồng tiền thực tế

Hệ thống **đối chiếu tiền với shipper/bưu cục**, chưa có nghiệp vụ thanh toán COD cho khách hàng.

1. Shipper có phân công hiện hành báo giao thành công qua API giao hàng. Backend tạo lần giao, bằng chứng, khoản thu COD và chuyển trạng thái trong transaction. Đơn không COD không tạo khoản thu. Hai trang mới không gọi API giao thành công hoặc tạo khoản thu lần nữa.
2. Khoản thu ghi `SoTienPhaiThu` và `SoTienThucThu` tại lần giao. COD hiện trên đơn được trình bày riêng trong chi tiết, không thay thế số tiền lịch sử của khoản thu.
3. Tài khoản có `COD_NOPTIEN` lập phiếu `PENDING`, chọn các khoản thu và số tiền phân bổ. Nếu là shipper, API chỉ cho đúng hồ sơ shipper của tài khoản. `PENDING` giữ phần tiền phân bổ, chưa phải tiền bưu cục đã xác nhận nhận.
4. Tài khoản có `COD_DOISOAT` thuộc phạm vi bưu cục xác nhận phiếu. UI yêu cầu tích xác nhận rõ số tiền, người nộp và mã phiếu. Backend khóa và kiểm tra lại chi tiết/tổng tiền trước khi chuyển `CONFIRMED`.
5. Phiên đối soát được tạo cho **toàn bộ khoản `COLLECTED`/`PARTIAL` của một shipper, một bưu cục trong kỳ thu**, theo API sẵn có. Không có lựa chọn tùy ý vài dòng trong phiên. UI xem trước toàn bộ số khoản/tổng tiền, phân trang chi tiết và yêu cầu đồng ý rõ phạm vi gồm cả trang chưa mở.
6. Nếu một khoản đã thuộc phiên khác chưa hủy, preview báo mã phiên và số khoản bị chặn; backend từ chối tạo trùng. Khi xác nhận, server tính lại tiền thu/nộp: đủ khớp thành `CONFIRMED`, có chênh lệch thành `DIFFERENCE`. `DIFFERENCE` được kiểm tra lại sau khi bổ sung nộp tiền. Đây không phải trạng thái đã thanh toán cho khách hàng.

Không coi COD hoặc tiền trên phiếu chưa xác nhận là doanh thu. Không tự thêm thao tác chuyển tiền ngân hàng, thanh toán, từ chối, hủy, sửa hoặc xóa chứng từ đã xác nhận.

## Trang và quyền

### Thu hộ COD

- Tab **Khoản thu**: mã đơn/vận đơn, shipper, COD phải thu đã ghi, thực thu, ngày thu, badge trạng thái; chi tiết có phân bổ nộp tiền và liên kết đến đơn khi có `DONHANG_XEM`.
- API khoản thu hiện phục vụ `COLLECTED`/`PARTIAL` có thực thu dương. Không đưa đơn chưa thu, đơn không COD, bản ghi `WAIVED`/`REVERSED` thành khoản đã thu.
- Bốn thẻ: thực thu, nộp đã xác nhận, phân bổ chờ xác nhận, còn phải nộp **của các khoản đang lọc**. Tổng do backend tính trên toàn bộ kết quả.
- Tab **Phiếu nộp tiền**: mã phiếu, shipper, tiền, ngày lập/nộp, trạng thái, người xác nhận, chi tiết và xác nhận khi được phép.
- Lập phiếu: chọn bưu cục/shipper theo tên; lọc khoản thu; chỉ các khoản đã tích chọn được đưa vào phiếu. Giữ lựa chọn qua các trang và hiển thị tổng số khoản/tiền đã chọn; đổi điều kiện tìm sẽ xóa lựa chọn với thông báo rõ. Tối đa 100 khoản theo DTO hiện có. Có bước xem lại và xác nhận trước khi gửi.
- Số tiền phân bổ được kiểm tra bằng đơn vị phần trăm VNĐ (`BigInt`), không cộng số tiền form bằng float. JSON gửi số decimal chuẩn, giữ nguyên hai chữ số, kể cả khi input vượt độ chính xác integer của JavaScript.

### Đối soát COD

- Danh sách phiên có mã, shipper, kỳ thu, số khoản, tiền phải thu/đã thu/đã nộp, trạng thái và ngày xác nhận.
- Tạo phiên có preview do backend cung cấp, chỉ cho lưu sau khi xem lại, có khoản và không bị phiên khác giữ.
- Chi tiết có khoản/đơn, số tiền, chênh lệch `thu − phải thu`, `nộp − thu`, chênh lệch chung, người/ngày xác nhận, ngày khóa và ghi chú.
- Chỉ hiện xác nhận cho `DRAFT`, `REVIEW`, `DIFFERENCE` và người có quyền; không gắn nhãn “Đã thanh toán”. Không tự tạo trường người tạo/ngày tạo khi API/schema chưa có.

Hai route backoffice yêu cầu quyền DB đang có hiệu lực `COD_DOISOAT`. API tiếp tục kiểm tra tài khoản/vai trò/quyền/phạm vi cho từng yêu cầu. Không tự cấp quyền mới.

**ADMIN mặc định không có `COD_NOPTIEN` trong seed hiện tại**: được xem/xác nhận, không thấy nút lập phiếu. Nút lập phiếu xuất hiện khi tài khoản thật sự được cấp quyền đó và đủ quyền mở trang COD. Shipper vẫn dùng ứng dụng/mobile theo chính sách đăng nhập sẵn có; các API dành cho shipper được kiểm tra trực tiếp bằng tài khoản shipper cách ly, không mở giả vai trò shipper trong backoffice.

## API sử dụng và phần bổ sung

| API | Tình trạng / mục đích |
| --- | --- |
| `GET /api/v1/cod/collections` | Tái sử dụng; thêm `id`, `status=COLLECTED\|PARTIAL`, `export=true`, tổng phải thu và COD hiện trên đơn trong chi tiết |
| `GET /api/v1/cod/deposits` | Tái sử dụng; thêm lọc ngày nộp `from/to`, tổng hợp toàn bộ kết quả và `export=true` |
| `GET /api/v1/cod/deposits/{id}` | Tái sử dụng chi tiết và các phân bổ |
| `POST /api/v1/cod/deposits` | Tái sử dụng; không đổi quyền, DTO hoặc transaction/khóa/nhật ký của nghiệp vụ lập phiếu |
| `POST /api/v1/cod/deposits/{id}/confirm` | Tái sử dụng; xác nhận nhận tiền với kiểm tra trạng thái/khóa hiện có |
| `GET /api/v1/cod/reconciliations` | Tái sử dụng; thêm `from/to` lọc giao khoảng kỳ, summary và `export=true`; chi tiết vẫn dùng `?id=...` |
| `POST /api/v1/cod/reconciliations` | Tái sử dụng toàn bộ cohort; sửa alias SQL `[from]` và kiểm tra khoảng thời gian hợp lệ |
| `POST /api/v1/cod/reconciliations/{id}/confirm` | Tái sử dụng procedure tính lại và xác nhận |
| `GET /api/v1/cod/options` | **Bổ sung** danh mục bưu cục/tên shipper và khả năng thao tác theo quyền COD. Kế toán không phải xin thêm quyền đọc tài khoản/danh mục quản trị |
| `GET /api/v1/cod/reconciliations/preview` | **Bổ sung** preview đúng tập khoản của API tạo phiên, tổng hợp toàn kỳ, số khoản đang bị phiên khác giữ và phân trang chi tiết |
| `GET /api/v1/orders/{id}` | Liên kết đơn, giữ `returnTo` trở về đúng bộ lọc COD |
| `GET /api/v1/reports/dashboard` | Kiểm tra đối chiếu với Báo cáo, không tạo endpoint báo cáo trùng |

Hai API đọc mới dùng chung kiểm tra quyền/phạm vi trong `CodQuerySupport`. Các GET cũ giữ tham số/cấu trúc sẵn có; trường mới bổ sung vào JSON. Các mảng danh sách rỗng được chuẩn hóa `[]`. Không thêm migration hoặc procedure mới.

## Ngày, số tiền và phạm vi tổng hợp

- UI chọn ngày Việt Nam, API nhận timestamp có offset `+07:00`, truy vấn lưu UTC dùng `.UtcDateTime` đúng một lần. Bao gồm toàn bộ ngày cuối qua mốc `< 00:00 ngày kế tiếp`. Khoảng có đủ hai đầu phải tăng dần và không quá 366 ngày.
- **Khoản thu** lọc theo ngày thu. `totalCollected`, `totalDeposited`, `totalPendingDeposit`, `totalRemaining` cùng tập khoản thu. Phân bổ nộp tiền tính theo trạng thái **hiện tại của chính những đơn này**, không giới hạn ngày nộp cùng ngày thu. Vì vậy không lấy hai dòng tiền khác kỳ trừ nhau và gọi là số dư.
- **Phiếu nộp** lọc theo ngày lập/nộp phiếu. “Tiền trên phiếu” cộng mọi trạng thái đang lọc; chỉ `CONFIRMED` tính là tiền đã được xác nhận nhận.
- **Phiên đối soát** lọc theo kỳ giao với khoảng được chọn vì schema không có ngày tạo phiên. Các tổng trên thẻ là tổng snapshot **trên các phiên đang lọc**, không phải khoản thu duy nhất hay số dư hệ thống; lịch sử phiên đã hủy có thể trùng tập khoản với phiên mới.
- Báo cáo số dư cuối kỳ khác với tra cứu khoản thu đang lọc tại thời điểm hiện tại khi có phiếu nộp sau kỳ. So sánh phải cùng cohort/cutoff. Kiểm tra đã xác nhận đúng số dư đầu kỳ, tiền thu kỳ trước/nộp kỳ sau và các số tiền hiện tại sau thao tác UI.
- Các phép tổng hợp/phân trang ở SQL, tiền dùng `DECIMAL`. Tổng phân bổ được chuyển về `DECIMAL(28,2)` trước phép trừ để không mất phần thập phân vì quy tắc scale của SQL Server.
- CSV dùng toàn bộ kết quả `export=true` theo bộ lọc đã áp dụng, kèm phạm vi/ngày/shipper/trạng thái/từ khóa/đơn vị/cách tính. UTF-8 BOM, escape dấu phẩy/nháy/xuống dòng và chống công thức văn bản theo helper đã dùng ở Báo cáo.

## An toàn thao tác và giao diện

- Lưu/xác nhận khóa các nút và control trong khi gửi, có bước xác nhận rõ; không tự retry POST khi có lỗi.
- Giữ form/lựa chọn khi POST lỗi. Với 409, hiển thị message và nút **Tải lại dữ liệu** để kiểm tra lại điều kiện, không tự gửi lại tiền cũ.
- Backend hiện có `UPDLOCK/HOLDLOCK`, khóa shipper/khoản thu/chứng từ và transaction; kiểm tra tổng phân bổ, cùng shipper/bưu cục, số đã nộp/chờ, trạng thái và trùng khoản trong phiên. Nhật ký ghi qua các controller hiện có.
- Không sửa/xóa tiền lịch sử hoặc chứng từ đã xác nhận. Việc cập nhật thông tin đơn vẫn đi qua API đơn hàng riêng; hai trang mới không ghi ngược vào khoản thu.
- Chỉ một vùng cuộn dọc nội dung chính; bảng chỉ cuộn ngang khi thiếu chiều rộng. Modal có body cuộn, header đóng và footer lưu/xác nhận vẫn nhìn thấy. CSS giới hạn `.cod-page`.
- Route chi tiết: `#/cod/collections/:id`, `#/cod/deposits/:id`, `#/cod/reconciliation/:id`; F5/Back/Forward dùng router hiện có. Bộ lọc nằm trong URL; link đơn hàng có đường quay lại COD hợp lệ.
- Loading/rỗng/403/lỗi API/409 riêng biệt; không đổi lỗi thành số 0, không gán mọi lỗi thành hết phiên. Abort và generation ngăn response cũ ghi đè; request xem/xuất/preview được hủy theo lifecycle trang/modal.

## Tệp đã sửa

- Backend: `CodCollectionsController.cs`, `CodDepositsController.cs`, `CodReconciliationsController.cs`; thêm `CodQuerySupport.cs`, `CodFormController.cs` trong `backend/LastMile/LastMile.Api/Controllers/`.
- Frontend: thêm `frontend/js/cod.js`; sửa `router.js`, `app.js`, `frontend/index.html`, `frontend/assets/css/styles.css`.
- Kiểm tra: thêm `frontend/tests/cod.test.cjs`, `cod-browser.cjs`, `cod-checks.cjs`, `cod-fixture.ps1`; sửa test router và `frontend/package.json` để có `test:cod`.
- Tài liệu: báo cáo này và README frontend/tests.

## Kết quả chạy thực tế

- `dotnet build ... --no-restore --output frontend/tests/.artifacts/cod/build`: **0 lỗi / 0 cảnh báo**.
- `npm.cmd test --prefix frontend`: **38/38** test đạt; bao gồm router/quyền/returnTo, ngày UTC+7, decimal JSON chính xác và hồi quy đăng nhập/API client.
- `node frontend/tests/cod-browser.cjs`: **51 kiểm tra tích hợp đạt**, không có lỗi JavaScript. API ASP.NET, SQL và Edge/proxy thật trên database LocalDB GUID cách ly; JWT test dùng signing key riêng. Không ghi dữ liệu vận hành, database/profile đã dọn.
- Đã chạy giao hàng thật qua API cho đơn có COD và không COD; sai shipper/admin bị từ chối; lặp giao bị chặn; chỉ đơn có COD tạo khoản thu.
- Đã gửi **hai yêu cầu đồng thời** lập phiếu, tạo phiên, xác nhận phiếu và xác nhận phiên khớp: mỗi cặp một thành công, một 409. Không trùng chi tiết hoặc tiền; `DIFFERENCE` được tính lại đúng sau khi xác nhận nộp.
- Đã kiểm tra tài khoản shipper/admin/kế toán/bưu cục/không quyền; danh mục theo COD, chặn ID/phạm vi ngoài quyền, khoản đã đối soát, danh sách rỗng, khoảng sai, tìm kiếm, phân trang backend, xuất toàn bộ CSV, chi tiết/F5/Back từ đơn.
- Thao tác UI tạo/xác nhận **100.000,25 VNĐ**, giữ form khi phát sinh 409 do phân bổ đã bị yêu cầu khác giữ, tải lại eligibility; kiểm tra nhật ký đầy đủ.
- Tiền thu 30/09, nộp 17/10: Báo cáo 30/09 còn 310.000 VNĐ; tháng 10 có đầu kỳ 310.000 VNĐ và hết số dư sau khi nộp đủ. Sau thao tác UI nộp một phần, khoản thu/phiên hiện hành/Báo cáo cùng ghi tiền nộp 100.000,25 VNĐ, còn 209.999,75 VNĐ; phiếu PENDING không được coi là đã nhận.
- Đã chụp desktop **1366 px** và mobile **390 px**, zoom 100%; kiểm tra không tràn ngang trang và không có cuộn dọc riêng trong bảng. Có lỗi 403/500 giả lập chỉ trong browser test để kiểm tra trạng thái; số liệu nghiệp vụ vẫn đi qua API/SQL thật.

[Kết quả máy đọc](cod/cod-verification.json)

| Màn hình | Desktop | Mobile |
| --- | --- | --- |
| Khoản thu | [Ảnh](cod/collections-1366.png) | [Ảnh](cod/collections-390.png) |
| Phiếu nộp | [Ảnh](cod/deposits-1366.png) | [Ảnh](cod/deposits-390.png) |
| Phiên đối soát | [Ảnh](cod/reconciliations-1366.png) | [Ảnh](cod/reconciliations-390.png) |
| Chi tiết khoản thu | — | [Ảnh](cod/collection-detail-390.png) |
| Xem lại phiếu nộp | — | [Ảnh](cod/deposit-review-390.png) |
| Xem lại phiên | — | [Ảnh](cod/reconciliation-review-390.png) |
| Chi tiết phiên | — | [Ảnh](cod/reconciliation-detail-390.png) |

Chạy lại từ `frontend`:

```powershell
npm.cmd test
npm.cmd run test:cod
```

## Phần chưa có trong nghiệp vụ hiện tại

- Chưa có thanh toán/trả COD cho khách hàng, cổng thanh toán/chuyển tiền ngân hàng. Không suy ra đã thanh toán từ `CONFIRMED`.
- Chưa có API từ chối/hủy/điều chỉnh phiếu hoặc phiên; chỉ xem các trạng thái lịch sử đã có. Không dựng nút thao tác không tồn tại.
- Chưa có phương thức thu trên `ThuTienCOD`, người/ngày tạo phiên riêng hoặc row version cho chứng từ COD. Không tự tạo giá trị; đồng thời được bảo vệ bằng transaction/khóa và trạng thái hiện có.
- Không thay đổi chính sách shipper chỉ dùng Mobile, không tự cấp `COD_NOPTIEN` cho admin. Fixture chỉ cấp quyền đó trong database test để kiểm tra thao tác UI đúng quyền.
- Kiểm tra dùng fixture cách ly; chưa xác nhận số dư vận hành, tải lớn, lựa chọn hàng trăm khoản trên dữ liệu thật hoặc điện thoại vật lý.

Một lần kiểm tra ban đầu dừng do điều kiện chờ modal trong test còn khớp màn hình xem lại cũ; một lần dừng ở fixture đọc nhật ký JSON bị chia chunk. Đã sửa điều kiện chờ và bọc JSON SQL thành scalar đầy đủ. Các lần chưa hoàn tất không tính là đạt; lần cuối hoàn tất 51 mục.
