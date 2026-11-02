# CustomerDetailController — lỗi SQL ngày 09/10/2026

Lỗi tại ExecuteScalarAsync khi form sửa đơn tải người gửi/nhận: SQL 156, "Incorrect syntax near the keyword 'statistics'", kèm "Incorrect syntax near the keyword 'ORDER'".

Đã tái hiện đúng hai thông báo bằng truy vấn SQL lấy từ CustomerDetailController trên LocalDB hiện có. Nguyên nhân là `AS statistics` chưa escape tên alias. Đã đổi thành `AS [statistics]`; tên JSON `statistics`, route, tham số, quyền và phạm vi bưu cục giữ nguyên. Sau sửa cả hai lỗi cú pháp đều hết, không cần sửa ORDER BY.

File sửa: `backend/LastMile/LastMile.Api/Controllers/CustomerDetailController.cs`.

Test hồi quy: `frontend/tests/customer-detail-sql.ps1`. Script lấy nguyên SQL của controller, chạy trên LocalDB bằng các ID tài khoản hiện có để kiểm tra các điều kiện quyền; không tạo JWT, không sửa dữ liệu database, không in thông tin khách hàng hoặc connection string. Chỉ bảng tạm trong SQL của controller được tạo trong phiên kết nối.

10 kiểm tra đạt:

- Khách hàng 1/10, ADMIN/BRANCH_MANAGER, includeInactiveAddresses false/true: 8 trường hợp. Response có đúng id, addresses, statistics và recentOrders; tổng số đơn khớp truy vấn kiểm chứng, scope đúng, đơn gần đây thuộc bưu cục người đọc và không vượt quá 10. Số địa chỉ khớp query kiểm chứng. Dữ liệu khách hàng hiện có đều có địa chỉ hoạt động, chưa chứng minh trường hợp địa chỉ ngừng hoạt động bằng một record thật.
- Tài khoản không hợp lệ vẫn bị từ chối với SQL 54601; khách hàng không tồn tại với SQL 54603: 2 trường hợp.

Chạy:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File frontend/tests/customer-detail-sql.ps1
```

Tái hiện SQL cũ có kiểm soát, chỉ trong script:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File frontend/tests/customer-detail-sql.ps1 -ReproduceOldSyntax
```

Build backend vào `.customer-detail-check/bin/`: thành công, 0 warning/error. Không khởi động server hoặc dừng phiên debugger đang chạy. Cần Stop Debug và chạy lại dự án trong Visual Studio để HTTP API sử dụng SQL mới. Chưa gọi endpoint bằng JWT trong phiên browser của người dùng, chưa PUT sửa đơn thật.

Kiểm thử browser trước đó dùng customer API mô phỏng nên không phát hiện lỗi cú pháp này; kiểm tra lần này thực thi SQL thật. Không tìm thấy AGENTS.md trong workspace.
