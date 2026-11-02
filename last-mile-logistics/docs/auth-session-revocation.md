# Thu hồi phiên đăng nhập

## Cơ chế

`dbo.PhienDangNhap` giữ trạng thái của từng phiên, độc lập với trạng thái xoay
refresh token. Mỗi lần login tạo một `MaPhien` ngẫu nhiên và claim JWT `sid`.
`TokenLamMoi.MaPhien` liên kết cả chuỗi refresh với phiên đó. Khóa ngoại ghép
`(MaPhien, MaTaiKhoan)` bảo đảm token không thuộc phiên của tài khoản khác.

Refresh giữ nguyên `sid`, thu hồi refresh token cũ và cấp token mới như trước.
Thời hạn phiên được gia hạn cùng refresh token. Access token đã cấp trước một
lần refresh bình thường vẫn hoạt động đến hạn JWT, trừ khi phiên bị thu hồi.

`Program.cs/OnTokenValidated` kiểm tra cả phiên còn hạn/chưa bị thu hồi, chủ sở
hữu phiên, tài khoản ACTIVE, thời điểm khóa và vai trò đang hoạt động. Các
controller tiếp tục kiểm tra quyền và phạm vi bưu cục hiện có. Không cache trạng
thái phiên nên request xác thực sau khi transaction thu hồi commit nhận 401.
Request đã qua xác thực trước khi thu hồi có thể đang tiếp tục xử lý.

Logout phiên hiện tại thu hồi phiên và các refresh token thuộc phiên đó.
Logout mọi phiên thu hồi tất cả phiên của tài khoản. Endpoint/DTO logout và
thông báo thành công được giữ nguyên, kể cả khi token không được nhận diện.
Một refresh token tiền nhiệm còn hạn, đã được xoay hợp lệ, vẫn có thể nhận diện
phiên để logout. Điều này xử lý trường hợp refresh vừa thắng khóa tài khoản;
không suy ra trạng thái phiên từ việc token tiền nhiệm đã bị thu hồi.
Token của một phiên đã thu hồi không thể logout các phiên đăng nhập mới.

Đổi mật khẩu, recovery reset và admin reset thu hồi toàn bộ phiên trong cùng
transaction đổi hash. Khóa/ngừng tài khoản và đổi vai trò/bưu cục cũng thu hồi
phiên, để quyền cũ không sống lại khi tài khoản được mở khóa. Admin reset giữ
nguyên các trường response; `accessTokensRevoked` nay là `true`.

## Đồng thời

Các luồng login/refresh/logout và mật khẩu giữ khóa `UPDLOCK, HOLDLOCK` trên
tài khoản đến khi commit. Sau đó mới khóa/cập nhật phiên và refresh token.
Lookup refresh token trước khi khóa tài khoản chỉ đọc ID; không giữ khóa token
trong lúc chờ khóa tài khoản. Trạng thái được kiểm tra lại sau khi có khóa.
Admin reset khóa hai tài khoản theo ID tăng dần trước khi khóa phiên/token.
Recovery code cũng được kiểm tra và sử dụng dưới khóa tài khoản.

Vì mọi luồng thu hồi/cấp token cùng tài khoản phải qua khóa này, refresh thắng
trước thì token mới vẫn bị thao tác thu hồi tiếp theo thu hồi; thao tác thu hồi
thắng trước thì refresh bị từ chối. Token cũ chỉ được refresh một lần.

## Áp dụng

1. Dừng các instance API cũ để không còn instance xác thực chỉ theo tài khoản.
2. Chạy `database/migrations/20261019_auth_sessions.sql` trên đúng database
   ứng dụng (SSMS hoặc công cụ triển khai SQL hiện có). Script dùng transaction,
   chạy lại an toàn, không xóa dữ liệu tài khoản/token và không thu hồi phiên mới
   trong lần chạy lại. Cài mới từ schema V5 cũng cần chạy migration này.
3. Build/deploy API mới và khởi động lại tất cả instance, cập nhật frontend.
4. Người dùng đăng nhập lại. JWT cũ không có `sid` nhận 401; refresh token cũ có
   `MaPhien IS NULL` nhận 401. Không tự chuyển token cũ thành phiên mới vì chúng
   không đủ thông tin để xác định phiên ổn định qua những lần xoay trước đó.

Chưa áp dụng migration lên database vận hành trong lần sửa này. Không thay đổi
khóa JWT và không ghi token/mật khẩu vào tài liệu hay output kiểm thử.

## Kiểm chứng

Chạy trong `frontend`:

```powershell
npm.cmd test
npm.cmd run test:auth-sessions
npm.cmd run test:accounts
```

`test:auth-sessions` build riêng dưới `tests/.artifacts/auth/build`, tạo database
LocalDB `CodexAccounts_<GUID>`, chạy API HTTP thật và tự dọn database. Một JWT
bootstrap kiểm thử có bản ghi phiên thật chỉ dùng để tạo tài khoản QA; các ca
kiểm chứng dùng login và refresh thật. Key, mật khẩu và token QA sinh ngẫu nhiên,
không được in ra. Recovery code được chèn vào database cách ly để kiểm tra
endpoint RESET; không gửi email.

Các ca gồm logout, nhiều phiên độc lập, logout mọi phiên, ba luồng mật khẩu,
refresh giữ `sid`, logout bằng token tiền nhiệm, migration lặp, từ chối token
legacy/sai phiên/sai chủ sở hữu, 8 cuộc đua refresh/logout, double-refresh,
8 request 401 đồng thời qua ApiClient thật và refresh đồng thời với từng luồng
mật khẩu. `test:accounts` dùng fixture phiên hợp lệ và kiểm tra lại admin reset
trong bộ hồi quy quyền/phạm vi và giao diện tài khoản hiện có.

Chưa kiểm thử SMTP gửi mã recovery, nhiều instance API dưới tải lớn hoặc các
browser harness nghiệp vụ khác. Các harness tạo JWT tổng hợp cần có claim `sid`
và bản ghi phiên trong database cách ly; JWT không có phiên không được đặc cách.

Kết quả thực chạy ngày 19/10/2026:

- Build API ở output riêng: 0 lỗi, 0 cảnh báo. Output `bin` mặc định bị API đang
  chạy giữ file, nên không dừng tiến trình đó để build đè.
- `npm.cmd test`: 66/66 đạt, gồm refresh đồng thời và giới hạn retry hiện có.
- `npm.cmd run test:auth-sessions`: 14/14 ca tích hợp đạt; database cách ly đã dọn.
- `npm.cmd run test:accounts`: 36 kiểm tra đạt, không lỗi JavaScript; đã kiểm tra
  1440/768/390 px và cập nhật báo cáo/ảnh trong `docs/accounts*`. Database và
  profile trình duyệt cách ly đã dọn.
