# Vị trí lưu kho — cập nhật 09/10/2026

## File thay đổi

- `frontend/js/locations.js` (mới): module quản lý vị trí dùng LogisticsUI và ApiClient hiện có. Một tiêu đề ở shell, toolbar Thêm vị trí/Làm mới, kho/search/trạng thái. Không có dropdown chọn vị trí hoặc cột kho/bưu cục lặp. Không chọn kho thì không gọi API vị trí. Đổi kho reset filter, đóng modal, abort request và dùng epoch/sequence chống ghi đè. Danh sách nhận toàn bộ mảng vị trí đã được backend lọc.
- `frontend/js/warehouse.js`: chuyển route warehouse-locations sang module mới và dọn module khi rời trang. Các trang kho khác giữ luồng hiện có.
- `frontend/js/app.js`, `frontend/assets/css/styles.css`, `frontend/index.html`: mô tả đúng yêu cầu, CSS riêng locations-workspace/locations-card/locations-dialog, cột thao tác đủ rộng, mobile cuộn bảng bên trong card; tải module/asset phiên bản mới.
- `frontend/js/router.js`: hỗ trợ keyword/status ACTIVE|INACTIVE|ALL của route quản lý vị trí, giữ locationId URL cũ cho tương thích; không đổi validation trạng thái đơn.
- `backend/LastMile/LastMile.Api/Controllers/WarehousesController.cs`: mở rộng GET locations hiện có với keyword/status, thêm isActive vào mảng response, giữ mặc định ACTIVE.
- `backend/LastMile/LastMile.Api/Controllers/CatalogSaveController.cs`: lỗi trùng 2601/2627 của LOCATIONS trả field=code và message riêng để frontend gắn lỗi vào ô mã. Giữ toàn bộ điều kiện quản lý/lưu trước đây.
- Kiểm tra: `frontend/tests/read-location-data.ps1`, `location-catalog-sql.ps1`, `locations-browser.cjs` (mới), `router.test.cjs`. Các reader outbound/return thêm tham số query SQL mới; các browser adapter outbound/return/order-edit/order-detail hỗ trợ URL router.js có phiên bản.

## API sử dụng/bổ sung

| API | Hành vi |
| --- | --- |
| GET /api/v1/warehouses | Kho hoạt động trong phạm vi tài khoản; không tạo API mới |
| GET /api/v1/warehouses/{id}/locations?status=ACTIVE\|INACTIVE\|ALL&keyword= | Route cũ, mở rộng trạng thái và tìm theo code/storageArea/rack/slot. Không truyền status vẫn ACTIVE cho form nhập/chuyển/nhận hoàn |
| POST /api/v1/catalogs | Cơ chế lưu cũ với type=LOCATIONS; thêm/sửa và đổi isActive, không DELETE |
| GET /api/v1/warehouses/{id}/inventory?locationId=&page=&pageSize= | API tồn kho đã hỗ trợ locationId trước COUNT/OFFSET/FETCH. Modal Xem hàng gửi đúng kho/vị trí và dùng totalItems của server, không lọc riêng một trang |

JSON vị trí: id, warehouseId, code, storageArea, rack, slot, isActive. Ánh xạ schema MaViTriLuuKho, MaKho, KyHieuViTri, TenKhuLuu, MaKe, MaO, DangHoatDong.

Payload lưu:

```text
{ type: "LOCATIONS", id: null | number, warehouseId: number,
  code: string, storageArea: string | null, rack: string | null,
  slot: string | null, isActive: boolean }
```

Giới hạn DTO/schema: code 50 ký tự, pattern `^[A-Z0-9][A-Z0-9_-]*$`; storageArea 100; rack/slot 50, pattern `^[A-Za-z0-9 ._-]+$` nếu có giá trị. Frontend giữ nguyên mã người dùng nhập, không đổi chữ hoa hay tự tạo mã. UQ_ViTriLuuKho là `(MaKho, KyHieuViTri)`, áp dụng cả vị trí ngừng sử dụng. Lỗi trùng do database kiểm tra nguyên tử, trả vào ô mã; DTO validation gắn vào field liên quan.

## Quyền và nghiệp vụ

GET warehouses/locations/inventory giữ quyền KHO_XEM và scope kho/bưu cục. POST catalogs hiện yêu cầu ADMIN + BUUCUC_QUANLY; frontend dùng quyền từ Auth.getPermissions qua router context và role thực tế, không suy quyền theo tên vai trò đơn thuần. Người không đủ quyền vẫn Xem hàng nhưng không thấy Thêm/Sửa/đổi trạng thái. 403 không xóa phiên, 500/mạng không báo hết phiên.

Backend không cho đổi code hoặc warehouseId của vị trí đã tạo, nên form sửa giữ hai trường này cố định; chỉ sửa khu/kệ/ô. Ngừng sử dụng/kích hoạt lại có modal xác nhận với mã cụ thể, đọc lại vị trí mới nhất, gửi POST catalog với isActive. Backend kiểm tra TonKhoDonHang RECEIVED/STORED/ALLOCATED/RETURNED dưới transaction lock trước ngừng sử dụng. Không xóa vị trí hoặc lịch sử. Nút lưu/confirm/đóng/Hủy khóa khi gửi, chống bấm hai lần; modal chỉ đóng khi phản hồi thành công hợp lệ. Validation/500 giữ nội dung; mạng hoặc phản hồi không xác định khóa gửi lại để kiểm tra danh sách.

## Kiểm tra đã chạy

- node --check các module JS sửa: đạt.
- npm.cmd test --prefix frontend: 21 test xác thực/router đạt.
- Build backend --no-restore, output riêng .locations-check/bin: thành công, 0 warning/error, không ghi đè binary đang chạy.
- 29 kiểm tra SQL danh sách trên LocalDB: 4 kho, ACTIVE/INACTIVE/ALL, tìm code/khu/kệ/ô, mảng rỗng khi keyword không khớp, kho ngoài bưu cục bị từ chối. Dữ liệu hiện tại có 3/2/4/4 vị trí hoạt động ở 4 kho, chưa có vị trí inactive lưu lâu dài. SQL inventory locationId cũng được chạy và kiểm tra hàng thuộc đúng vị trí.
- 11 kiểm tra **SQL CatalogSave thật**, không mock: tạo, mã trùng cùng kho (2627), sửa khu/kệ/ô, đổi code bị chặn (56504), đổi kho bị chặn (56504), vị trí có hàng không được ngừng (56504), vị trí trống được ngừng, kích hoạt lại, vị trí inactive không hiện ở ACTIVE nhưng hiện ở INACTIVE/ALL, non-admin bị từ chối (56502), tài khoản không hợp lệ bị từ chối (56501).
- Các kiểm tra ghi SQL luôn nằm trong transaction ngoài; COMMIT của controller chỉ kết thúc transaction lồng, script luôn ROLLBACK transaction ngoài. Record thử và thay đổi metadata/trạng thái không được lưu; số vị trí và nhật ký trước/sau không đổi. Không thay đổi schema hay quyền.
- 34 kiểm tra browser đạt: một title/mô tả, không tải trước chọn kho, đúng 6 cột, tìm kiếm/trạng thái rỗng, không tự đổi mã, trùng mã inline, POST mapping đúng và chống gửi hai lần, sửa giữ code/kho, DTO error đúng field, 500 giữ form/session, xác nhận cụ thể, lý do backend khi còn hàng, ngừng/kích hoạt lại không DELETE, Xem hàng theo kho/locationId và trang 2, chống response cũ, thiếu permission và non-admin đều read-only, 403 không hết phiên, retry khi lỗi, toolbar/listener dọn sau route. Không error/unhandledrejection/DevTools exception.
- 1366/768/390px: pageWidth bằng viewportWidth, cột thao tác >=345px, bảng cuộn ngang trên mobile. Đã xem [desktop](locations-1366.png), [tablet](locations-768.png), [mobile](locations-390.png); ảnh dùng dữ liệu vị trí đọc thật.
- Hồi quy: 42 kiểm tra nhập hàng hoàn và 37 kiểm tra xuất kho đạt với API vị trí mặc định mới.

[Metrics và checks browser](locations-browser-verification.json).

## Giới hạn và nạp thay đổi

Browser chạy headless trên server 5500 hiện có; xác thực và HTTP POST được adapter cô lập, không gửi ghi API thật. SQL thực đã kiểm tra kể cả nhánh ghi bằng rollback, nhưng chưa kiểm thử HTTP POST bằng JWT người dùng, transaction đồng thời thật hoặc thao tác lưu lâu dài trong phiên UI hiện tại.

Cần Stop Debug và chạy lại backend để GET locations trả isActive/status/keyword mới; sau đó Ctrl+F5 frontend. Không khởi động server trùng cổng. Không tìm thấy AGENTS.md trong workspace hoặc thư mục cha đã kiểm tra; dự án không có Git repository tại đường dẫn hiện tại.
