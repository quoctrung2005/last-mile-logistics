# Mã kiểm tra và dữ liệu tạm

Khung giờ bắt đầu giao VRP được kiểm tra trong `LastMile.Routing.Tests` bằng thời gian/đồ thị cố định và `dispatch-window-checks.cjs` bằng HTTP/JWT/SQL thật trong GUID fixture. Module được gọi bởi `dispatch-checks.cjs`; `dispatch-browser.cjs` kiểm tra các mốc giờ Việt Nam và tương thích proposal cũ. Không thay database đang dùng. Xem `../../docs/vrp-delivery-windows.md` cho lệnh, kết quả và giới hạn.

Kiểm tra contract kết quả SQL của sửa/xác nhận đơn, chuyển vị trí, tạo đơn và nhập kho nằm ở `backend/LastMile/LastMile.SqlResults.Tests`, dùng LocalDB GUID thật và tự dọn. `api.test.cjs` kiểm tra HTTP 500 chưa xác định không tự gửi lại; `order-unsaved-browser.cjs` kiểm tra giữ form/chặn gửi lại và dialog xác nhận. Lệnh chạy, contract và giới hạn tại `../../docs/sql-results.md`; `tools/InspectSqlResultContracts.ps1` chỉ đọc metadata database đã cấu hình.

`vehicle-picker-browser.cjs` được gọi trong hồi quy shipper: kiểm tra tự tải theo đúng shipper/bưu cục, xe đang gắn với chính shipper, nút Chọn khóa kèm lý do từ backend, bộ lọc loại, tìm mã/biển số, phân trang/giữ lựa chọn, rỗng/lỗi, gán xe đồng thời, lối mở từ trang Phương tiện và bố cục Edge 1440/390 px. Hồi quy cũng kiểm tra payload ID xe thật và reload sau lưu. Dùng LocalDB/profile GUID riêng, không đổi trạng thái xe để làm xe xuất hiện. Các response giả lập được ghi rõ trong báo cáo; lệnh build và chạy ở `../../docs/vehicle-picker.md`.

`npm.cmd run test:license-date` kiểm tra ngày Việt Nam trong C# và SQL thật bằng thời gian cố định, chỉ SELECT trên LocalDB master. `vietnam-date.test.cjs` nằm trong `npm.cmd test`; `shipper-license-browser.cjs` được chạy bởi harness shipper với form Edge thật. Xem `../../docs/license-vietnam-date.md` cho lệnh build, chạy hồi quy và giới hạn kiểm chứng.

`npm.cmd run test:evidence` build Release API, kiểm tra decoder bằng project `LastMile.Evidence.Tests`, rồi kiểm tra upload/download qua JWT/HTTP/SQL và file thật trên LocalDB GUID và content root riêng. Xem `../../docs/evidence-image-validation.md`. Cập nhật dependency Pkcs và audit được ghi riêng tại `../../docs/nuget-pkcs-update.md`.

`npm.cmd run test:order-unsaved` chạy app/form đơn hàng và Router thật trên Edge headless với API giả lập cô lập, không dùng database hoặc ghi đơn thật. Kiểm tra dữ liệu chưa lưu, Back/Forward, kết quả lưu và hộp thoại native `beforeunload`; xem `../../docs/order-unsaved.md` và `../../docs/order-unsaved-verification.json`.

Giữ các script `.test.cjs`, `*-browser.cjs`, fixture và script SQL/PowerShell trong thư mục này. `npm.cmd test` chạy test router và API client. Browser/SQL harness có yêu cầu môi trường riêng; xem báo cáo tương ứng trong `../../docs` trước khi chạy.

`npm.cmd run test:customers` build API riêng và chạy hồi quy khách hàng/địa chỉ trên database GUID cách ly với SQL/HTTP/Edge thật. `customer-version-checks.cjs` kiểm tra version, stale 409, audit và default đồng thời; `customer-version-browser.cjs` dùng hai tab thật để kiểm tra giữ form/chặn submit/tải lại có cảnh báo. Xem migration và kết quả ở `../../docs/customer-versions.md`.

`npm.cmd run test:auth-login` build API riêng và kiểm tra đếm sai/khóa tạm, race BCrypt với trạng thái/hash và rate limit IP bằng HTTP/LocalDB thật. Chỉ thay tài khoản `qa.login.*` trong database GUID cách ly rồi tự dọn. Xem cấu hình, kết quả và bước kiểm tra giao diện ở `../../docs/login-lockout.md`.

`npm.cmd run test:auth-sessions` build API riêng và kiểm chứng thu hồi access/refresh token qua HTTP thật trên LocalDB GUID cách ly, gồm nhiều phiên, ba luồng mật khẩu, migration lặp và request đồng thời. Xem `../../docs/auth-session-revocation.md`. JWT tổng hợp trong browser harness cũng phải có `sid` gắn với phiên thật của fixture; bộ `test:accounts` đã được cập nhật.

`npm.cmd run test:cod` build vào `.artifacts/cod/build`, dùng `cod-fixture.ps1`, `cod-checks.cjs`, Edge và database GUID riêng để kiểm tra thu/nộp/đối soát, quyền, đồng thời, decimal, lỗi/giữ form và đối chiếu Báo cáo. Chế độ `PrepareUi` chỉ thay đổi/cấp quyền trong database cách ly để mở các ca thao tác; không gọi trên dữ liệu vận hành. Kết quả/ảnh ở `../../docs/cod/`, mô tả tại `../../docs/cod-implementation-verification.md`.

`npm.cmd run test:reports` build vào `.artifacts/reports/build`, dùng `reports-fixture.ps1`/`.sql` và Edge để kiểm tra ba tab báo cáo trên LocalDB GUID riêng. Fixture tái sử dụng bộ khởi tạo schema/seed của `admin-fixture.ps1`, không ghi dữ liệu vận hành. Ảnh và kết quả ở `../../docs/reports/`; định nghĩa và giới hạn ở `../../docs/reports-implementation-verification.md`.

Giao diện thu gọn hiện được kiểm tra thêm qua `reports-ui-checks.cjs`, gồm bảng 3 dòng/28 kết quả, 1366/1920/390 px và zoom 100%. Ảnh toàn trang/kết quả mới ở `../../docs/reports/compact/`; báo cáo tại `../../docs/reports-ui-refinement-verification.md`. Các ảnh cũ được giữ để đối chiếu.

`npm.cmd run test:admin` build vào `.artifacts/admin/build`, rồi kiểm tra lần lượt Vai trò, Danh mục, Bảng giá, Nhật ký và hồi quy tạo đơn/nhập kho/API Điều phối trên database LocalDB GUID riêng. Không chạy trên dữ liệu vận hành. Báo cáo/ảnh và các giới hạn ở `../../docs/admin-implementation-verification.md` và `../../docs/admin/`.

Profile Edge của các browser harness được tạo dưới `.artifacts/<module>/`, dùng tên GUID riêng khi kiểm tra với database cách ly. Build riêng của `npm.cmd run test:accounts` nằm trong `.artifacts/accounts/build`. Thư mục `.artifacts` được ignore; không chứa mã nguồn cần lưu. Báo cáo và ảnh đã lưu trong `../../docs` được giữ lại; ảnh tài khoản nằm trong `../../docs/accounts`.

## Dọn thư mục kiểm tra ngày 10/10/2026

| Thư mục ở gốc dự án | Mục đích và tình trạng khi kiểm tra |
| --- | --- |
| `.auth-check` | Còn 6 file `obj` của project kiểm tra `Fixture`: assembly metadata, global usings và cache do MSBuild sinh. Không còn project hay mã kiểm tra gốc; test xác thực cần thiết nằm ở `auth.test.cjs` |
| `.customer-detail-check` | Còn 46 file `bin`: bản build API kiểm chứng SQL chi tiết khách hàng, thư viện phụ thuộc và bản sao cấu hình lúc build. Không có project/script đang gọi thư mục này; giữ `customer-detail-sql.ps1`, `read-order-detail.ps1`, `order-detail-browser.cjs` và các test khách hàng |
| `.inventory-check` | Còn 4 file `obj` của project kiểm tra `Hash`: metadata/cache tự sinh. Không còn mã kiểm tra gốc và không có tham chiếu trong project/script hiện tại; giữ mã Kho và báo cáo kiểm chứng tồn kho |
| `.locations-check` | Còn 46 file `bin` của API build thử riêng. Browser harness chỉ dùng tên thư mục để tạo profile, không dùng binary trong đó; đã chuyển profile vào `.artifacts/locations` |
| `.order-edit-check` | Còn 46 file `bin` của API build thử riêng. Browser harness chỉ dùng tên thư mục để tạo profile, không dùng binary trong đó; đã chuyển profile vào `.artifacts/order-edit` |

Đã xóa đúng năm thư mục trên: 148 file, khoảng 36,5 MiB. Không cần chuyển mã nguồn ra khỏi chúng vì tất cả file còn lại đều là đầu ra build; mã kiểm tra hiện có đã nằm trong `frontend/tests`. Các tham chiếu trong tài liệu `docs` mô tả lần build trước được giữ làm lịch sử kiểm chứng.

Không có tham chiếu từ `.csproj`/`.slnx` đến năm thư mục và không có tiến trình chạy từ chúng tại thời điểm kiểm tra. Mã nguồn backend/frontend, cấu hình gốc của API, SQL/database, báo cáo, thiết kế và các thư mục kiểm tra khác được giữ nguyên.

`.gitignore` ở gốc dự án bỏ qua `/.*-check/`, `.artifacts`, `bin`, `obj`, `.vs` và `node_modules`; không bỏ qua mã test, `docs` hoặc `database`. Các browser harness hiện dùng `.artifacts` thay vì tạo thư mục `.*-check` ở gốc dự án. Không có Git metadata ở workspace hiện tại; ignore rules sẽ áp dụng khi dự án được quản lý bằng Git.

Sau khi dọn: 195 file nguồn/cấu hình/dữ liệu/tài liệu đã lấy hash trước thao tác xóa vẫn nguyên vẹn; `node --check` đạt cho hai browser script đã đổi đường dẫn; `npm.cmd test` đạt 29/29. Đã kiểm tra ignore bằng Git với metadata tạm riêng: 12 đường dẫn build/profile được ignore, 12 đường dẫn nguồn/test/cấu hình/SQL/tài liệu được giữ. Metadata kiểm chứng được dọn; không khởi tạo `.git` trong dự án. Chưa chạy lại hai browser/SQL harness trong lần dọn thư mục này.

## Dọn bảy thư mục còn lại

- `.accounts-check`: bản build API riêng và bốn ảnh kiểm chứng. Chuyển ảnh nguyên vẹn sang `docs/accounts`; cập nhật package script và harness để build/profile dùng `.artifacts/accounts`.
- `.outbound-check`, `.transactions-check`: chỉ còn binary/thư viện/cấu hình sao chép khi build và metadata tự sinh; browser harness chuyển profile sang `.artifacts/outbound` và `.artifacts/transactions`.
- `.warehouse-fix-check`: chỉ còn sáu file metadata/cache `obj` của project kiểm tra `Check`; không có mã nguồn hay project còn tham chiếu.
- `.return-check`, `.shippers-check`, `.vehicles-check`: thư mục rỗng còn lại sau kiểm thử; profile chuyển sang `.artifacts/returns`, `.artifacts/shippers`, `.artifacts/vehicles`.
- Cập nhật cả profile test khách hàng và chi tiết đơn sang `.artifacts/customers` và `.artifacts/order-detail`, để chúng không tạo thêm thư mục kiểm tra ở gốc dự án.

Không có project chính hoặc tiến trình đang chạy từ bảy thư mục này tại thời điểm kiểm tra. Giữ toàn bộ script/fixture cần thiết trong `frontend/tests`, cấu hình gốc, SQL/dữ liệu và báo cáo. Các nhắc đến output build cũ trong tài liệu kiểm chứng khác vẫn là lịch sử của lần chạy trước.

Đã dọn bảy thư mục, gồm 151 file trong cây output cũ (36,93 MiB); bốn ảnh được sao chép và đối chiếu hash trước khi xóa bản cũ. Sau thao tác xóa, 199 file nguồn/cấu hình/dữ liệu/tài liệu/ảnh được đối chiếu hash vẫn nguyên vẹn; không còn thư mục `.*-check` ở gốc. Tám browser script đổi đường dẫn đạt `node --check`, build ở đường dẫn `.artifacts/accounts/build` đạt 0 lỗi/0 cảnh báo, `npm.cmd test` đạt 29/29. Build thử mới nằm trong `.artifacts` đã được ignore. Không chạy lại browser/SQL harness trong lần dọn này.
