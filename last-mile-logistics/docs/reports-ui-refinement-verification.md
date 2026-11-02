# Giao diện Báo cáo thu gọn — 17/10/2026

Đã sửa trực tiếp `#/reports`. Giữ API, SQL, quyền truy cập, phạm vi bưu cục và cách tính các chỉ số. Các kiểm tra API cũ vẫn chạy cùng bộ kiểm tra giao diện mới.

## Tệp đã sửa

| Tệp | Nội dung |
| --- | --- |
| `frontend/js/reports.js` | Bộ lọc gọn, hành vi Áp dụng/Làm mới, tab ngắn, giải thích mở theo yêu cầu, thẻ chỉ số, SVG tự resize, danh sách trạng thái, bảng và footer phân trang riêng |
| `frontend/assets/css/styles.css` | CSS giới hạn dưới `.reports-page` hoặc `.reports-workspace`; bỏ giới hạn chiều cao bảng và sửa kích thước dropdown, căn số, khoảng cách, responsive |
| `frontend/js/app.js` | Bật/tắt lớp `.reports-workspace` theo route để các chỉnh sửa bố cục không ảnh hưởng trang khác |
| `frontend/index.html` | Cập nhật phiên bản asset CSS/JS |
| `frontend/tests/reports-checks.cjs` | Cập nhật nhãn giao diện và giữ toàn bộ kiểm tra API/phạm vi/CSV trước đây |
| `frontend/tests/reports-ui-checks.cjs` | Kiểm tra giao diện gọn, refresh/draft, biểu đồ, bảng ít/nhiều dòng và xuất CSV |
| `frontend/tests/reports-browser.cjs` | Chụp toàn trang ở 100% zoom, kiểm tra tràn và cuộn bảng, lưu ảnh vào thư mục `compact` |
| `frontend/tests/reports-fixture.ps1` | Thêm chế độ `ManyRows` tạo 24 nhân viên/phân công trong database GUID riêng để kiểm tra bảng 28 kết quả; giữ UTF-8 BOM cho PowerShell 5.1 |
| Tài liệu Báo cáo và README test | Liên kết bằng chứng mới |

Không thay đổi backend, schema, xác thực hoặc CSS dùng chung của dashboard/quản trị.

## Thay đổi người dùng nhìn thấy

- Bộ lọc desktop có ngày bắt đầu/kết thúc, bưu cục, **Áp dụng** và nút biểu tượng làm mới trên cùng hàng. Input/button cao 38 px. Nhóm Hôm nay / 7 ngày / Tháng này có trạng thái chọn; cả bộ lọc dùng một chú thích múi giờ Việt Nam.
- Chọn nhanh chỉ điền bộ lọc. **Áp dụng** tải theo phần đang nhập. **Làm mới** tải lại bộ lọc đã nhận dữ liệu thành công, không tự áp dụng hoặc đặt lại ngày đang nhập. Chuyển tab cũng dùng bộ lọc đã áp dụng.
- Nhãn khoảng ngày và dữ liệu được cập nhật cùng nhau khi phản hồi phù hợp hoàn tất. Nếu sửa input mà chưa áp dụng, dòng kết quả vẫn mang nhãn bộ lọc cũ và nút xuất bị khóa; dữ liệu không bị gán nhãn của phần đang nhập.
- Giữ ba tab **Đơn hàng / Giao hàng / Cước phí & COD**. Bỏ tiêu đề lặp trong nội dung tab. Khoảng ngày/phạm vi nằm cùng hàng với Xuất CSV; thời gian cập nhật nhỏ bên dưới.
- Thẻ chỉ số có nhãn 13 px, số 26–28 px, biểu tượng nhẹ, padding 16 px. Desktop 4 thẻ/hàng, tablet 2; mobile tự xuống hàng. Thẻ tiền trên mobile dùng cột đủ rộng để không ngắt giữa các chữ số thập phân.
- Một câu mô tả và liên kết **Cách tính số liệu** thay khối giải thích dài. Phần mở rộng giữ đầy đủ định nghĩa, nhiều lượt giao/một đơn, lịch sử shipper và giới hạn COD quá khứ. Tooltip tỷ lệ ghi công thức và mẫu số, mẫu số 0 vẫn là `—`.
- SVG có vùng vẽ 260 px và `ResizeObserver`, giữ chữ/điểm dữ liệu rõ khi resize/chuyển tab. Lỗi dựng SVG hiện thông báo ngắn và tự mở bảng dữ liệu thật; không thay bằng số liệu giả.
- Trạng thái dùng danh sách thanh ngang có số lượng, không có cuộn dọc riêng.
- Bảng bưu cục có 5 cột ngắn, nhắc trạng thái hiện tại một lần. Bảng nhân viên mang tên **Kết quả theo nhân viên**, có bưu cục riêng và tooltip giải thích các cột. Tên căn trái, số căn phải; hàng khoảng 46 px.
- Mọi bảng bỏ `max-height`, chỉ cuộn ngang khi thiếu chỗ. Bảng 3 dòng hiển thị đủ 3 dòng; bảng 10 dòng cũng cuộn cùng trang, không thêm vùng cuộn dọc trong bảng.
- Footer bên trái là **Hiển thị 1–3 trong 3 kết quả**; bên phải dropdown 104 px và phân trang. Chỉ một trang thì không hiện nút Trước/Sau. Không thay đổi tổng hoặc phân trang backend.
- Khi rời route hoặc thay kết quả: hủy request xem/xuất và disconnect observer biểu đồ. Tooltip dùng `title` gắn DOM, không tạo instance/plugin cần giữ ngoài trang.

## Kiểm tra thực tế

- `node --check` cho module và script kiểm tra: đạt.
- `npm.cmd test --prefix frontend`: **35/35** test đạt.
- Build `.NET` vào thư mục test: **0 lỗi, 0 cảnh báo**; không sửa mã backend trong lần này.
- `node frontend/tests/reports-browser.cjs`: **88 kiểm tra đạt**, không có lỗi JavaScript. Dùng API ASP.NET thật, proxy thật, SQL schema/seed của dự án trên database LocalDB GUID riêng và Edge headless. JWT test dùng khóa riêng; không ghi dữ liệu vận hành. Database/profile test đã được dọn.
- Cả 3 tab được chụp và kiểm tra ở **1366, 1920, 390 px**, `devicePixelRatio=1`, `visualViewport.scale=1` (100% zoom). Có thêm kiểm tra 768 px cho thẻ 2 cột.
- Đã kiểm tra logo/menu/nội dung nằm trong layout, header không che heading, input/button cùng hàng và cao 36–40 px, chiều cao bộ lọc desktop dưới 145 px; không tràn ngang trang, không cuộn dọc riêng trong bảng.
- Bảng ít dòng: 3 bưu cục, 4 nhân viên; bảng nhiều dòng: **28 nhân viên**, 10 dòng/trang, đi trang 2, tổng không đổi, CSV chứa cả nhân viên ngoài trang đang xem.
- Đã kiểm tra đổi tab/F5, điều kiện ngày sai/rỗng, chọn nhanh, refresh giữ khoảng áp dụng, không gán nhãn mới cho dữ liệu cũ, mở/đóng giải thích, biểu đồ thật sau chuyển tab và thông báo/bảng dự phòng khi cố ý gây lỗi dựng SVG trong trình duyệt test.
- Giữ kiểm tra quyền admin/bưu cục/từ chối, API 403/500, response đến muộn, abort khi rời trang, COD khác kỳ/decimal/trạng thái phiếu và chống công thức CSV.

Hai lần chạy trước lần đạt cuối gặp tài nguyên/kết nối trình duyệt cục bộ chưa hoàn tất khi đổi tài khoản. Harness đã tăng thời gian chờ tải trang và ghi chẩn đoán mạng. Lần chạy cuối hoàn tất đủ 88 kiểm tra; các lần chưa hoàn tất không được tính là đạt.

## Bằng chứng

[Kết quả máy đọc — 88 kiểm tra](reports/compact/reports-verification.json)

| Tab | 1366 px | 1920 px | Mobile 390 px |
| --- | --- | --- | --- |
| Đơn hàng, bảng 3 dòng | [Ảnh](reports/compact/orders-1366.png) | [Ảnh](reports/compact/orders-1920.png) | [Ảnh](reports/compact/orders-390.png) |
| Giao hàng | [Ảnh](reports/compact/delivery-1366.png) | [Ảnh](reports/compact/delivery-1920.png) | [Ảnh](reports/compact/delivery-390.png) |
| Cước phí & COD | [Ảnh](reports/compact/finance-1366.png) | [Ảnh](reports/compact/finance-1920.png) | [Ảnh](reports/compact/finance-390.png) |
| Giao hàng, 28 kết quả | [Ảnh](reports/compact/delivery-many-1366.png) | [Ảnh](reports/compact/delivery-many-1920.png) | [Ảnh](reports/compact/delivery-many-390.png) |

Ảnh cũ ở `docs/reports/` được giữ để đối chiếu, ảnh mới nằm trong `docs/reports/compact/`. Ảnh dùng dữ liệu kiểm tra cách ly, không phải số liệu vận hành. Chưa kiểm tra trên điện thoại vật lý hoặc từng trình duyệt ngoài Edge.

Chạy lại từ thư mục `frontend`:

```powershell
npm.cmd test
npm.cmd run test:reports
```
