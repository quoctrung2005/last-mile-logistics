/*
===============================================================================
DỮ LIỆU GIẢ LẬP THỰC TẾ 
===============================================================================
Mục tiêu:
- Dữ liệu có hình thức giống một hệ thống last-mile đang vận hành thực tế.
- Tên người, doanh nghiệp, số điện thoại, mã vận đơn... do ChatGPT tự tạo,
  hoàn toàn là dữ liệu giả lập; không đại diện cho người/doanh nghiệp thật.
- Địa danh/tên đường được dùng để tạo ngữ cảnh vận hành TP.HCM.
- Bao phủ đầy đủ 50 bảng: một số bảng danh mục đã được seed trong schema,
  một số bảng lịch sử/tài chính được sinh tự động qua trigger/stored procedure.

Quy mô dữ liệu:
- 10 khu vực (1 thành phố, 3 quận, 6 phường)
- 3 bưu cục, 4 kho, 12 vị trí lưu kho
- 16 tài khoản nghiệp vụ, 5 shipper, 5 phương tiện
- 12 khách hàng
- 12 đơn hàng với nhiều trạng thái khác nhau
- 3 chuyến giao thực tế
- Có giao thành công, COD, giao thất bại, giao lại, đơn đang giao,
  hàng trong kho, đơn chờ phân công, đơn chờ nhập kho và đơn hủy.
- Có nộp COD, đối soát, đánh giá, khiếu nại, cảnh báo, thông báo, audit log.

TRẠNG THÁI SAU KHI CHẠY:
  DH-HCM-261002-0001 -> COMPLETED (COD)
  DH-HCM-261002-0002 -> COMPLETED
  DH-HCM-261002-0003 -> COMPLETED (COD)
  DH-HCM-261002-0004 -> COMPLETED (COD)
  DH-HCM-261002-0005 -> RETRY_WAITING
  DH-HCM-261002-0006 -> IN_DELIVERY
  DH-HCM-261002-0007 -> IN_DELIVERY
  DH-HCM-261002-0008 -> WAITING_ASSIGNMENT
  DH-HCM-261002-0009 -> IN_WAREHOUSE
  DH-HCM-261002-0010 -> WAITING_ASSIGNMENT
  DH-HCM-261002-0011 -> WAITING_INBOUND
  DH-HCM-261002-0012 -> CANCELLED

QUY ƯỚC CÚ PHÁP:
- Luôn dùng đầy đủ từ khóa INSERT INTO khi thêm dữ liệu.
- Stored procedure gọi bằng tên tham số: @TenThamSo = GiaTri.
- Khai báo biến trước, SELECT/SET gán giá trị sau.
- Có BEGIN ... END cho các khối IF/TRY/CATCH.

CÁCH CHẠY:
1. Chạy QLGiaoHangChangCuoi_SQLServer_V5_FINAL_AUDITED.sql trước.
2. Nên dùng database sạch, chưa có bộ dữ liệu giả lập này.
3. Mở file này trong SSMS và nhấn F5.
===============================================================================
*/

USE QLGiaoHangChangCuoi;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @Now DATETIME2(0)=SYSUTCDATETIME();

DECLARE
    @KV_HCM INT, @KV_BT INT, @KV_TP INT, @KV_Q6 INT,
    @KV_BHB INT, @KV_AL INT, @KV_SK INT, @KV_TT INT, @KV_Q6P10 INT, @KV_Q6P12 INT,
    @BC_BT INT, @BC_TP INT, @BC_Q6 INT,
    @Kho_BT INT, @Kho_BT_Return INT, @Kho_TP INT, @Kho_Q6 INT,
    @VT_BT_A1 BIGINT, @VT_BT_A2 BIGINT, @VT_BT_A3 BIGINT,
    @VT_BTR_R1 BIGINT, @VT_BTR_R2 BIGINT,
    @VT_TP_A1 BIGINT, @VT_TP_A2 BIGINT, @VT_TP_A3 BIGINT,
    @VT_Q6_A1 BIGINT, @VT_Q6_A2 BIGINT, @VT_Q6_A3 BIGINT, @VT_Q6_A4 BIGINT,

    @RoleAdmin INT, @RoleManager INT, @RoleDispatcher INT,
    @RoleWarehouse INT, @RoleAccountant INT, @RoleShipper INT,

    @TK_Admin BIGINT,
    @TK_MgrBT BIGINT, @TK_MgrTP BIGINT, @TK_MgrQ6 BIGINT,
    @TK_DPBT BIGINT, @TK_DPTP BIGINT, @TK_DPQ6 BIGINT,
    @TK_KhoBT BIGINT, @TK_KhoTP BIGINT, @TK_KhoQ6 BIGINT,
    @TK_KeToan BIGINT,
    @TK_S1 BIGINT, @TK_S2 BIGINT, @TK_S3 BIGINT, @TK_S4 BIGINT, @TK_S5 BIGINT,

    @KH_ShopAnPhuc BIGINT, @KH_ShopMinhTam BIGINT, @KH_ShopNhaXinh BIGINT,
    @KH_01 BIGINT, @KH_02 BIGINT, @KH_03 BIGINT, @KH_04 BIGINT, @KH_05 BIGINT,
    @KH_06 BIGINT, @KH_07 BIGINT, @KH_08 BIGINT, @KH_09 BIGINT,

    @S1 BIGINT, @S2 BIGINT, @S3 BIGINT, @S4 BIGINT, @S5 BIGINT,
    @Xe1 BIGINT, @Xe2 BIGINT, @Xe3 BIGINT, @Xe4 BIGINT, @Xe5 BIGINT,

    @DV_STD INT, @DV_EXP INT, @TT_NEW SMALLINT,
    @LyDoNoAnswer INT,

    @Trip1 BIGINT, @Trip2 BIGINT, @Trip3 BIGINT,
    @Handover1 BIGINT, @Handover2 BIGINT, @Handover3 BIGINT,
    @WT_BT_IN BIGINT, @WT_TP_IN BIGINT, @WT_Q6_IN BIGINT,
    @WT_BT_OUT1 BIGINT, @WT_BT_OUT2 BIGINT, @WT_TP_OUT BIGINT,
    @Deposit BIGINT, @Recon BIGINT,
    @Complaint1 BIGINT, @Complaint2 BIGINT;

SELECT @RoleAdmin = MaVaiTro FROM dbo.VaiTro WHERE KyHieuVaiTro='ADMIN';
SELECT @RoleManager = MaVaiTro FROM dbo.VaiTro WHERE KyHieuVaiTro='BRANCH_MANAGER';
SELECT @RoleDispatcher = MaVaiTro FROM dbo.VaiTro WHERE KyHieuVaiTro='DISPATCHER';
SELECT @RoleWarehouse = MaVaiTro FROM dbo.VaiTro WHERE KyHieuVaiTro='WAREHOUSE_STAFF';
SELECT @RoleAccountant = MaVaiTro FROM dbo.VaiTro WHERE KyHieuVaiTro='ACCOUNTANT';
SELECT @RoleShipper = MaVaiTro FROM dbo.VaiTro WHERE KyHieuVaiTro='SHIPPER';
SELECT @DV_STD = MaLoaiDichVu FROM dbo.LoaiDichVu WHERE KyHieuDichVu='STANDARD';
SELECT @DV_EXP = MaLoaiDichVu FROM dbo.LoaiDichVu WHERE KyHieuDichVu='EXPRESS';
SELECT @TT_NEW = MaTrangThaiDonHang FROM dbo.TrangThaiDonHang WHERE KyHieuTrangThai='NEW';
SELECT @LyDoNoAnswer = MaLyDoGiaoThatBai FROM dbo.LyDoGiaoThatBai WHERE KyHieuLyDo='NO_ANSWER';

BEGIN TRY
BEGIN TRAN;

--------------------------------------------------------------------------------
-- 1. KHU VỰC THỰC TẾ HÓA
--------------------------------------------------------------------------------
PRINT N'1/15 - Khu vực, bưu cục, kho...';

INSERT INTO dbo.KhuVuc(KyHieuKhuVuc,TenKhuVuc,MaKhuVucCha,LoaiKhuVuc,DangHoatDong)
VALUES ('HCM',N'Thành phố Hồ Chí Minh',NULL,'CITY',1);
SET @KV_HCM = SCOPE_IDENTITY();

INSERT INTO dbo.KhuVuc(KyHieuKhuVuc,TenKhuVuc,MaKhuVucCha,LoaiKhuVuc,DangHoatDong)
VALUES ('HCM-BT',N'Quận Bình Tân',@KV_HCM,'DISTRICT',1);
SET @KV_BT = SCOPE_IDENTITY();

INSERT INTO dbo.KhuVuc(KyHieuKhuVuc,TenKhuVuc,MaKhuVucCha,LoaiKhuVuc,DangHoatDong)
VALUES ('HCM-TP',N'Quận Tân Phú',@KV_HCM,'DISTRICT',1);
SET @KV_TP = SCOPE_IDENTITY();

INSERT INTO dbo.KhuVuc(KyHieuKhuVuc,TenKhuVuc,MaKhuVucCha,LoaiKhuVuc,DangHoatDong)
VALUES ('HCM-Q6',N'Quận 6',@KV_HCM,'DISTRICT',1);
SET @KV_Q6 = SCOPE_IDENTITY();

INSERT INTO dbo.KhuVuc(KyHieuKhuVuc,TenKhuVuc,MaKhuVucCha,LoaiKhuVuc,DangHoatDong)
VALUES ('HCM-BT-BHB',N'Phường Bình Hưng Hòa B',@KV_BT,'WARD',1);
SET @KV_BHB = SCOPE_IDENTITY();

INSERT INTO dbo.KhuVuc(KyHieuKhuVuc,TenKhuVuc,MaKhuVucCha,LoaiKhuVuc,DangHoatDong)
VALUES ('HCM-BT-AL',N'Phường An Lạc',@KV_BT,'WARD',1);
SET @KV_AL = SCOPE_IDENTITY();

INSERT INTO dbo.KhuVuc(KyHieuKhuVuc,TenKhuVuc,MaKhuVucCha,LoaiKhuVuc,DangHoatDong)
VALUES ('HCM-TP-SK',N'Phường Sơn Kỳ',@KV_TP,'WARD',1);
SET @KV_SK = SCOPE_IDENTITY();

INSERT INTO dbo.KhuVuc(KyHieuKhuVuc,TenKhuVuc,MaKhuVucCha,LoaiKhuVuc,DangHoatDong)
VALUES ('HCM-TP-TT',N'Phường Tân Thành',@KV_TP,'WARD',1);
SET @KV_TT = SCOPE_IDENTITY();

INSERT INTO dbo.KhuVuc(KyHieuKhuVuc,TenKhuVuc,MaKhuVucCha,LoaiKhuVuc,DangHoatDong)
VALUES ('HCM-Q6-P10',N'Phường 10, Quận 6',@KV_Q6,'WARD',1);
SET @KV_Q6P10 = SCOPE_IDENTITY();

INSERT INTO dbo.KhuVuc(KyHieuKhuVuc,TenKhuVuc,MaKhuVucCha,LoaiKhuVuc,DangHoatDong)
VALUES ('HCM-Q6-P12',N'Phường 12, Quận 6',@KV_Q6,'WARD',1);
SET @KV_Q6P12 = SCOPE_IDENTITY();

INSERT INTO dbo.BuuCuc
(KyHieuBuuCuc,TenBuuCuc,MaKhuVuc,DiaChi,ViDo,KinhDo,SoDienThoai,Email,DangHoatDong)
VALUES
('HCM-BT01',N'Bưu cục Bình Tân 01',@KV_BT,
 N'621 Quốc lộ 1A, Bình Hưng Hòa B, Bình Tân, TP.HCM',
 10.810500,106.604800,'02870001001','bt01@lastmile.local',1);
SET @BC_BT = SCOPE_IDENTITY();

INSERT INTO dbo.BuuCuc
(KyHieuBuuCuc,TenBuuCuc,MaKhuVuc,DiaChi,ViDo,KinhDo,SoDienThoai,Email,DangHoatDong)
VALUES
('HCM-TP01',N'Bưu cục Tân Phú 01',@KV_TP,
 N'88 Tân Kỳ Tân Quý, Sơn Kỳ, Tân Phú, TP.HCM',
 10.802900,106.617900,'02870001002','tp01@lastmile.local',1);
SET @BC_TP = SCOPE_IDENTITY();

INSERT INTO dbo.BuuCuc
(KyHieuBuuCuc,TenBuuCuc,MaKhuVuc,DiaChi,ViDo,KinhDo,SoDienThoai,Email,DangHoatDong)
VALUES
('HCM-Q601',N'Bưu cục Quận 6 01',@KV_Q6,
 N'180 Hậu Giang, Phường 10, Quận 6, TP.HCM',
 10.746900,106.635800,'02870001003','q601@lastmile.local',1);
SET @BC_Q6 = SCOPE_IDENTITY();

INSERT INTO dbo.KhuVucPhucVuBuuCuc(MaBuuCuc,MaKhuVuc,LaChinh) VALUES
(@BC_BT,@KV_BHB,1),(@BC_BT,@KV_AL,0),
(@BC_TP,@KV_SK,1),(@BC_TP,@KV_TT,0),
(@BC_Q6,@KV_Q6P10,1),(@BC_Q6,@KV_Q6P12,0);

INSERT INTO dbo.Kho(KyHieuKho,TenKho,MaBuuCuc,DiaChi,DangHoatDong)
VALUES ('KHO-BT-PL',N'Kho phân loại Bình Tân',@BC_BT,N'Khu A - Bưu cục Bình Tân 01',1);
SET @Kho_BT = SCOPE_IDENTITY();

INSERT INTO dbo.Kho(KyHieuKho,TenKho,MaBuuCuc,DiaChi,DangHoatDong)
VALUES ('KHO-BT-HOAN',N'Kho hàng hoàn Bình Tân',@BC_BT,N'Khu B - Bưu cục Bình Tân 01',1);
SET @Kho_BT_Return = SCOPE_IDENTITY();

INSERT INTO dbo.Kho(KyHieuKho,TenKho,MaBuuCuc,DiaChi,DangHoatDong)
VALUES ('KHO-TP-PL',N'Kho phân loại Tân Phú',@BC_TP,N'Tầng trệt - Bưu cục Tân Phú 01',1);
SET @Kho_TP = SCOPE_IDENTITY();

INSERT INTO dbo.Kho(KyHieuKho,TenKho,MaBuuCuc,DiaChi,DangHoatDong)
VALUES ('KHO-Q6-PL',N'Kho phân loại Quận 6',@BC_Q6,N'Tầng trệt - Bưu cục Quận 6 01',1);
SET @Kho_Q6 = SCOPE_IDENTITY();

INSERT INTO dbo.ViTriLuuKho(MaKho,KyHieuViTri,TenKhuLuu,MaKe,MaO,DangHoatDong)
VALUES
(@Kho_BT,'BT-A1-01',N'Hàng mới nhập','A1','01',1),
(@Kho_BT,'BT-A1-02',N'Hàng mới nhập','A1','02',1),
(@Kho_BT,'BT-B1-01',N'Hàng chờ giao','B1','01',1);
SELECT @VT_BT_A1 = MaViTriLuuKho FROM dbo.ViTriLuuKho WHERE MaKho=@Kho_BT AND KyHieuViTri='BT-A1-01';
SELECT @VT_BT_A2 = MaViTriLuuKho FROM dbo.ViTriLuuKho WHERE MaKho=@Kho_BT AND KyHieuViTri='BT-A1-02';
SELECT @VT_BT_A3 = MaViTriLuuKho FROM dbo.ViTriLuuKho WHERE MaKho=@Kho_BT AND KyHieuViTri='BT-B1-01';

INSERT INTO dbo.ViTriLuuKho(MaKho,KyHieuViTri,TenKhuLuu,MaKe,MaO,DangHoatDong)
VALUES
(@Kho_BT_Return,'BTR-R1-01',N'Hàng hoàn chờ xử lý','R1','01',1),
(@Kho_BT_Return,'BTR-R1-02',N'Hàng hoàn đã kiểm','R1','02',1);
SELECT @VT_BTR_R1 = MaViTriLuuKho FROM dbo.ViTriLuuKho WHERE MaKho=@Kho_BT_Return AND KyHieuViTri='BTR-R1-01';
SELECT @VT_BTR_R2 = MaViTriLuuKho FROM dbo.ViTriLuuKho WHERE MaKho=@Kho_BT_Return AND KyHieuViTri='BTR-R1-02';

INSERT INTO dbo.ViTriLuuKho(MaKho,KyHieuViTri,TenKhuLuu,MaKe,MaO,DangHoatDong)
VALUES
(@Kho_TP,'TP-A1-01',N'Hàng mới nhập','A1','01',1),
(@Kho_TP,'TP-A1-02',N'Hàng chờ phân công','A1','02',1),
(@Kho_TP,'TP-B1-01',N'Hàng chờ giao','B1','01',1);
SELECT @VT_TP_A1 = MaViTriLuuKho FROM dbo.ViTriLuuKho WHERE MaKho=@Kho_TP AND KyHieuViTri='TP-A1-01';
SELECT @VT_TP_A2 = MaViTriLuuKho FROM dbo.ViTriLuuKho WHERE MaKho=@Kho_TP AND KyHieuViTri='TP-A1-02';
SELECT @VT_TP_A3 = MaViTriLuuKho FROM dbo.ViTriLuuKho WHERE MaKho=@Kho_TP AND KyHieuViTri='TP-B1-01';

INSERT INTO dbo.ViTriLuuKho(MaKho,KyHieuViTri,TenKhuLuu,MaKe,MaO,DangHoatDong)
VALUES
(@Kho_Q6,'Q6-A1-01',N'Hàng mới nhập','A1','01',1),
(@Kho_Q6,'Q6-A1-02',N'Hàng mới nhập','A1','02',1),
(@Kho_Q6,'Q6-B1-01',N'Hàng chờ phân công','B1','01',1),
(@Kho_Q6,'Q6-C1-01',N'Hàng ngoại lệ','C1','01',1);
SELECT @VT_Q6_A1 = MaViTriLuuKho FROM dbo.ViTriLuuKho WHERE MaKho=@Kho_Q6 AND KyHieuViTri='Q6-A1-01';
SELECT @VT_Q6_A2 = MaViTriLuuKho FROM dbo.ViTriLuuKho WHERE MaKho=@Kho_Q6 AND KyHieuViTri='Q6-A1-02';
SELECT @VT_Q6_A3 = MaViTriLuuKho FROM dbo.ViTriLuuKho WHERE MaKho=@Kho_Q6 AND KyHieuViTri='Q6-B1-01';
SELECT @VT_Q6_A4 = MaViTriLuuKho FROM dbo.ViTriLuuKho WHERE MaKho=@Kho_Q6 AND KyHieuViTri='Q6-C1-01';

--------------------------------------------------------------------------------
-- 2. TÀI KHOẢN NGHIỆP VỤ
--------------------------------------------------------------------------------
PRINT N'2/15 - Tài khoản nhân sự...';

INSERT INTO dbo.TaiKhoan(KyHieuTaiKhoan,TenDangNhap,MatKhauBam,HoTen,SoDienThoai,Email,MaVaiTro,MaBuuCuc,TrangThaiTaiKhoan)
VALUES ('NV-ADMIN-001','admin.system','$2a$10$Mje8mvWdPlIoDq2QlWIxlehGuICRRMVZwrNw8l3AYpgVVXtvBXZSi',N'Nguyễn Hoàng Minh','0900001001','admin@lastmile.local',@RoleAdmin,NULL,'ACTIVE');
SET @TK_Admin = SCOPE_IDENTITY();

INSERT INTO dbo.TaiKhoan(KyHieuTaiKhoan,TenDangNhap,MatKhauBam,HoTen,SoDienThoai,Email,MaVaiTro,MaBuuCuc,TrangThaiTaiKhoan)
VALUES ('NV-BT-QL-001','ql.binh.tan','$2a$10$Mje8mvWdPlIoDq2QlWIxlehGuICRRMVZwrNw8l3AYpgVVXtvBXZSi',N'Trần Thị Thanh Hương','0900001002','huong.tt@lastmile.local',@RoleManager,@BC_BT,'ACTIVE');
SET @TK_MgrBT = SCOPE_IDENTITY();

INSERT INTO dbo.TaiKhoan(KyHieuTaiKhoan,TenDangNhap,MatKhauBam,HoTen,SoDienThoai,Email,MaVaiTro,MaBuuCuc,TrangThaiTaiKhoan)
VALUES ('NV-TP-QL-001','ql.tan.phu','$2a$10$Mje8mvWdPlIoDq2QlWIxlehGuICRRMVZwrNw8l3AYpgVVXtvBXZSi',N'Phạm Quốc Khánh','0900001003','khanh.pq@lastmile.local',@RoleManager,@BC_TP,'ACTIVE');
SET @TK_MgrTP = SCOPE_IDENTITY();

INSERT INTO dbo.TaiKhoan(KyHieuTaiKhoan,TenDangNhap,MatKhauBam,HoTen,SoDienThoai,Email,MaVaiTro,MaBuuCuc,TrangThaiTaiKhoan)
VALUES ('NV-Q6-QL-001','ql.quan.6','$2a$10$Mje8mvWdPlIoDq2QlWIxlehGuICRRMVZwrNw8l3AYpgVVXtvBXZSi',N'Lê Ngọc Mai','0900001004','mai.ln@lastmile.local',@RoleManager,@BC_Q6,'ACTIVE');
SET @TK_MgrQ6 = SCOPE_IDENTITY();

INSERT INTO dbo.TaiKhoan(KyHieuTaiKhoan,TenDangNhap,MatKhauBam,HoTen,SoDienThoai,Email,MaVaiTro,MaBuuCuc,TrangThaiTaiKhoan)
VALUES ('NV-BT-DP-001','dp.binh.tan','$2a$10$Mje8mvWdPlIoDq2QlWIxlehGuICRRMVZwrNw8l3AYpgVVXtvBXZSi',N'Võ Minh Tân','0900001010','tan.vm@lastmile.local',@RoleDispatcher,@BC_BT,'ACTIVE');
SET @TK_DPBT = SCOPE_IDENTITY();

INSERT INTO dbo.TaiKhoan(KyHieuTaiKhoan,TenDangNhap,MatKhauBam,HoTen,SoDienThoai,Email,MaVaiTro,MaBuuCuc,TrangThaiTaiKhoan)
VALUES ('NV-TP-DP-001','dp.tan.phu','$2a$10$Mje8mvWdPlIoDq2QlWIxlehGuICRRMVZwrNw8l3AYpgVVXtvBXZSi',N'Nguyễn Thùy Linh','0900001011','linh.nt@lastmile.local',@RoleDispatcher,@BC_TP,'ACTIVE');
SET @TK_DPTP = SCOPE_IDENTITY();

INSERT INTO dbo.TaiKhoan(KyHieuTaiKhoan,TenDangNhap,MatKhauBam,HoTen,SoDienThoai,Email,MaVaiTro,MaBuuCuc,TrangThaiTaiKhoan)
VALUES ('NV-Q6-DP-001','dp.quan.6','$2a$10$Mje8mvWdPlIoDq2QlWIxlehGuICRRMVZwrNw8l3AYpgVVXtvBXZSi',N'Đặng Anh Tuấn','0900001012','tuan.da@lastmile.local',@RoleDispatcher,@BC_Q6,'ACTIVE');
SET @TK_DPQ6 = SCOPE_IDENTITY();

INSERT INTO dbo.TaiKhoan(KyHieuTaiKhoan,TenDangNhap,MatKhauBam,HoTen,SoDienThoai,Email,MaVaiTro,MaBuuCuc,TrangThaiTaiKhoan)
VALUES ('NV-BT-KHO-001','kho.binh.tan','$2a$10$Mje8mvWdPlIoDq2QlWIxlehGuICRRMVZwrNw8l3AYpgVVXtvBXZSi',N'Bùi Văn Long','0900001020','long.bv@lastmile.local',@RoleWarehouse,@BC_BT,'ACTIVE');
SET @TK_KhoBT = SCOPE_IDENTITY();

INSERT INTO dbo.TaiKhoan(KyHieuTaiKhoan,TenDangNhap,MatKhauBam,HoTen,SoDienThoai,Email,MaVaiTro,MaBuuCuc,TrangThaiTaiKhoan)
VALUES ('NV-TP-KHO-001','kho.tan.phu','$2a$10$Mje8mvWdPlIoDq2QlWIxlehGuICRRMVZwrNw8l3AYpgVVXtvBXZSi',N'Phan Thị Hạnh','0900001021','hanh.pt@lastmile.local',@RoleWarehouse,@BC_TP,'ACTIVE');
SET @TK_KhoTP = SCOPE_IDENTITY();

INSERT INTO dbo.TaiKhoan(KyHieuTaiKhoan,TenDangNhap,MatKhauBam,HoTen,SoDienThoai,Email,MaVaiTro,MaBuuCuc,TrangThaiTaiKhoan)
VALUES ('NV-Q6-KHO-001','kho.quan.6','$2a$10$Mje8mvWdPlIoDq2QlWIxlehGuICRRMVZwrNw8l3AYpgVVXtvBXZSi',N'Hoàng Minh Đức','0900001022','duc.hm@lastmile.local',@RoleWarehouse,@BC_Q6,'ACTIVE');
SET @TK_KhoQ6 = SCOPE_IDENTITY();

INSERT INTO dbo.TaiKhoan(KyHieuTaiKhoan,TenDangNhap,MatKhauBam,HoTen,SoDienThoai,Email,MaVaiTro,MaBuuCuc,TrangThaiTaiKhoan)
VALUES ('NV-KT-001','ke.toan.cod','$2a$10$Mje8mvWdPlIoDq2QlWIxlehGuICRRMVZwrNw8l3AYpgVVXtvBXZSi',N'Đỗ Thu Trang','0900001030','trang.dt@lastmile.local',@RoleAccountant,@BC_BT,'ACTIVE');
SET @TK_KeToan = SCOPE_IDENTITY();

INSERT INTO dbo.TaiKhoan(KyHieuTaiKhoan,TenDangNhap,MatKhauBam,HoTen,SoDienThoai,Email,MaVaiTro,MaBuuCuc,TrangThaiTaiKhoan)
VALUES ('NVGH-BT-001','shipper.tuan','$2a$10$Mje8mvWdPlIoDq2QlWIxlehGuICRRMVZwrNw8l3AYpgVVXtvBXZSi',N'Nguyễn Minh Tuấn','0900001101','tuan.nm@lastmile.local',@RoleShipper,@BC_BT,'ACTIVE');
SET @TK_S1 = SCOPE_IDENTITY();

INSERT INTO dbo.TaiKhoan(KyHieuTaiKhoan,TenDangNhap,MatKhauBam,HoTen,SoDienThoai,Email,MaVaiTro,MaBuuCuc,TrangThaiTaiKhoan)
VALUES ('NVGH-BT-002','shipper.bao','$2a$10$Mje8mvWdPlIoDq2QlWIxlehGuICRRMVZwrNw8l3AYpgVVXtvBXZSi',N'Trần Quốc Bảo','0900001102','bao.tq@lastmile.local',@RoleShipper,@BC_BT,'ACTIVE');
SET @TK_S2 = SCOPE_IDENTITY();

INSERT INTO dbo.TaiKhoan(KyHieuTaiKhoan,TenDangNhap,MatKhauBam,HoTen,SoDienThoai,Email,MaVaiTro,MaBuuCuc,TrangThaiTaiKhoan)
VALUES ('NVGH-TP-001','shipper.phuc','$2a$10$Mje8mvWdPlIoDq2QlWIxlehGuICRRMVZwrNw8l3AYpgVVXtvBXZSi',N'Lê Hoàng Phúc','0900001103','phuc.lh@lastmile.local',@RoleShipper,@BC_TP,'ACTIVE');
SET @TK_S3 = SCOPE_IDENTITY();

INSERT INTO dbo.TaiKhoan(KyHieuTaiKhoan,TenDangNhap,MatKhauBam,HoTen,SoDienThoai,Email,MaVaiTro,MaBuuCuc,TrangThaiTaiKhoan)
VALUES ('NVGH-Q6-001','shipper.huy','$2a$10$Mje8mvWdPlIoDq2QlWIxlehGuICRRMVZwrNw8l3AYpgVVXtvBXZSi',N'Phạm Gia Huy','0900001104','huy.pg@lastmile.local',@RoleShipper,@BC_Q6,'ACTIVE');
SET @TK_S4 = SCOPE_IDENTITY();

INSERT INTO dbo.TaiKhoan(KyHieuTaiKhoan,TenDangNhap,MatKhauBam,HoTen,SoDienThoai,Email,MaVaiTro,MaBuuCuc,TrangThaiTaiKhoan)
VALUES ('NVGH-Q6-002','shipper.dat','$2a$10$Mje8mvWdPlIoDq2QlWIxlehGuICRRMVZwrNw8l3AYpgVVXtvBXZSi',N'Võ Thành Đạt','0900001105','dat.vt@lastmile.local',@RoleShipper,@BC_Q6,'ACTIVE');
SET @TK_S5 = SCOPE_IDENTITY();

INSERT INTO dbo.TokenLamMoi(MaTaiKhoan,GiaTriBamToken,HetHanLuc,ThuHoiLuc,ThoiGianTao,DiaChiIPTao,TokenThayTheBam)
VALUES
(@TK_DPBT,'sha256:rt_dpbt_20261002',DATEADD(DAY,7,@Now),NULL,@Now,'10.10.1.15',NULL),
(@TK_DPTP,'sha256:rt_dptp_20261002',DATEADD(DAY,7,@Now),NULL,@Now,'10.20.1.15',NULL),
(@TK_S1,'sha256:rt_shipper_tuan_20261002',DATEADD(DAY,7,@Now),NULL,@Now,'10.10.2.101',NULL),
(@TK_S2,'sha256:rt_shipper_bao_20261002',DATEADD(DAY,7,@Now),NULL,@Now,'10.10.2.102',NULL),
(@TK_S3,'sha256:rt_shipper_phuc_20261002',DATEADD(DAY,7,@Now),NULL,@Now,'10.20.2.101',NULL);

--------------------------------------------------------------------------------
-- 3. KHÁCH HÀNG
--------------------------------------------------------------------------------
PRINT N'3/15 - Khách hàng và địa chỉ...';

INSERT INTO dbo.KhachHang(KyHieuKhachHang,HoTen,SoDienThoai,Email,LoaiKhachHang,DangHoatDong)
VALUES ('KH-DN-0001',N'Công ty TNHH Thương mại An Phúc','0912000001','lienhe@anphuc.example','BUSINESS',1);
SET @KH_ShopAnPhuc = SCOPE_IDENTITY();

INSERT INTO dbo.KhachHang(KyHieuKhachHang,HoTen,SoDienThoai,Email,LoaiKhachHang,DangHoatDong)
VALUES ('KH-DN-0002',N'Cửa hàng Gia Dụng Minh Tâm','0912000002','minhtam@shop.example','BUSINESS',1);
SET @KH_ShopMinhTam = SCOPE_IDENTITY();

INSERT INTO dbo.KhachHang(KyHieuKhachHang,HoTen,SoDienThoai,Email,LoaiKhachHang,DangHoatDong)
VALUES ('KH-DN-0003',N'Nội thất Nhà Xinh Online','0912000003','nhaxinh@shop.example','BUSINESS',1);
SET @KH_ShopNhaXinh = SCOPE_IDENTITY();

INSERT INTO dbo.KhachHang(KyHieuKhachHang,HoTen,SoDienThoai,Email,LoaiKhachHang,DangHoatDong)
VALUES ('KH-CN-0001',N'Nguyễn Ngọc Anh','0912000101','ngocanh@example.com','INDIVIDUAL',1);
SET @KH_01 = SCOPE_IDENTITY();

INSERT INTO dbo.KhachHang(KyHieuKhachHang,HoTen,SoDienThoai,Email,LoaiKhachHang,DangHoatDong)
VALUES ('KH-CN-0002',N'Trần Khánh Vy','0912000102','khanhvy@example.com','INDIVIDUAL',1);
SET @KH_02 = SCOPE_IDENTITY();

INSERT INTO dbo.KhachHang(KyHieuKhachHang,HoTen,SoDienThoai,Email,LoaiKhachHang,DangHoatDong)
VALUES ('KH-CN-0003',N'Lê Minh Khang','0912000103','minhkhang@example.com','INDIVIDUAL',1);
SET @KH_03 = SCOPE_IDENTITY();

INSERT INTO dbo.KhachHang(KyHieuKhachHang,HoTen,SoDienThoai,Email,LoaiKhachHang,DangHoatDong)
VALUES ('KH-CN-0004',N'Phạm Thảo Nhi','0912000104','thaonhi@example.com','INDIVIDUAL',1);
SET @KH_04 = SCOPE_IDENTITY();

INSERT INTO dbo.KhachHang(KyHieuKhachHang,HoTen,SoDienThoai,Email,LoaiKhachHang,DangHoatDong)
VALUES ('KH-CN-0005',N'Võ Quốc Huy','0912000105','quochuy@example.com','INDIVIDUAL',1);
SET @KH_05 = SCOPE_IDENTITY();

INSERT INTO dbo.KhachHang(KyHieuKhachHang,HoTen,SoDienThoai,Email,LoaiKhachHang,DangHoatDong)
VALUES ('KH-CN-0006',N'Đặng Thu Hà','0912000106','thuha@example.com','INDIVIDUAL',1);
SET @KH_06 = SCOPE_IDENTITY();

INSERT INTO dbo.KhachHang(KyHieuKhachHang,HoTen,SoDienThoai,Email,LoaiKhachHang,DangHoatDong)
VALUES ('KH-CN-0007',N'Bùi Gia Bảo','0912000107','giabao@example.com','INDIVIDUAL',1);
SET @KH_07 = SCOPE_IDENTITY();

INSERT INTO dbo.KhachHang(KyHieuKhachHang,HoTen,SoDienThoai,Email,LoaiKhachHang,DangHoatDong)
VALUES ('KH-CN-0008',N'Hoàng Mỹ Linh','0912000108','mylinh@example.com','INDIVIDUAL',1);
SET @KH_08 = SCOPE_IDENTITY();

INSERT INTO dbo.KhachHang(KyHieuKhachHang,HoTen,SoDienThoai,Email,LoaiKhachHang,DangHoatDong)
VALUES ('KH-CN-0009',N'Ngô Đức Anh','0912000109','ducanh@example.com','INDIVIDUAL',1);
SET @KH_09 = SCOPE_IDENTITY();

INSERT INTO dbo.DiaChiKhachHang
(MaKhachHang,NhanDiaChi,TenNguoiLienHe,SoDienThoaiLienHe,DiaChi,MaKhuVuc,ViDo,KinhDo,LaMacDinh,DangHoatDong)
VALUES
(@KH_ShopAnPhuc,N'Kho Bình Tân',N'Nguyễn Thị Yến','0912000001',N'42 Đường số 7, Bình Hưng Hòa B, Bình Tân, TP.HCM',@KV_BHB,10.811800,106.601500,1,1),
(@KH_ShopMinhTam,N'Cửa hàng Tân Phú',N'Trần Văn Dũng','0912000002',N'155 Tân Kỳ Tân Quý, Sơn Kỳ, Tân Phú, TP.HCM',@KV_SK,10.803400,106.618800,1,1),
(@KH_ShopNhaXinh,N'Kho Quận 6',N'Lê Thanh Bình','0912000003',N'96 Hậu Giang, Phường 10, Quận 6, TP.HCM',@KV_Q6P10,10.747800,106.634900,1,1),
(@KH_01,N'Nhà riêng',N'Nguyễn Ngọc Anh','0912000101',N'118 Đường số 5, An Lạc, Bình Tân, TP.HCM',@KV_AL,10.728900,106.615200,1,1),
(@KH_02,N'Nhà riêng',N'Trần Khánh Vy','0912000102',N'76 Đường số 18B, Bình Hưng Hòa B, Bình Tân, TP.HCM',@KV_BHB,10.816000,106.598900,1,1),
(@KH_03,N'Căn hộ',N'Lê Minh Khang','0912000103',N'25 Tân Hương, Tân Thành, Tân Phú, TP.HCM',@KV_TT,10.789900,106.628000,1,1),
(@KH_04,N'Nhà riêng',N'Phạm Thảo Nhi','0912000104',N'212 Lê Trọng Tấn, Sơn Kỳ, Tân Phú, TP.HCM',@KV_SK,10.806700,106.624600,1,1),
(@KH_05,N'Văn phòng',N'Võ Quốc Huy','0912000105',N'310 Hậu Giang, Phường 12, Quận 6, TP.HCM',@KV_Q6P12,10.744100,106.629800,1,1),
(@KH_06,N'Nhà riêng',N'Đặng Thu Hà','0912000106',N'74 Bình Phú, Phường 10, Quận 6, TP.HCM',@KV_Q6P10,10.741300,106.637900,1,1),
(@KH_07,N'Nhà riêng',N'Bùi Gia Bảo','0912000107',N'55 Đường số 1, An Lạc, Bình Tân, TP.HCM',@KV_AL,10.731800,106.611900,1,1),
(@KH_08,N'Công ty',N'Hoàng Mỹ Linh','0912000108',N'101 Tân Quý, Tân Thành, Tân Phú, TP.HCM',@KV_TT,10.795300,106.625400,1,1),
(@KH_09,N'Nhà riêng',N'Ngô Đức Anh','0912000109',N'89 Đường số 12, Bình Hưng Hòa B, Bình Tân, TP.HCM',@KV_BHB,10.814300,106.603200,1,1);

--------------------------------------------------------------------------------
-- 4. SHIPPER + PHƯƠNG TIỆN
--------------------------------------------------------------------------------
PRINT N'4/15 - Shipper, phương tiện và GPS...';

INSERT INTO dbo.NhanVienGiaoHang(MaTaiKhoan,MaNhanVien,CCCD,SoBangLai,NgayHetHanBangLai,TrangThaiSanSang,ViDoHienTai,KinhDoHienTai,ThoiGianCapNhatViTri,DangHoatDong)
VALUES (@TK_S1,'GH-BT-001','079260000001','A1-260001','2031-06-30','AVAILABLE',10.810500,106.604800,@Now,1);
SET @S1 = SCOPE_IDENTITY();

INSERT INTO dbo.NhanVienGiaoHang(MaTaiKhoan,MaNhanVien,CCCD,SoBangLai,NgayHetHanBangLai,TrangThaiSanSang,ViDoHienTai,KinhDoHienTai,ThoiGianCapNhatViTri,DangHoatDong)
VALUES (@TK_S2,'GH-BT-002','079260000002','A1-260002','2030-11-30','AVAILABLE',10.812000,106.602900,@Now,1);
SET @S2 = SCOPE_IDENTITY();

INSERT INTO dbo.NhanVienGiaoHang(MaTaiKhoan,MaNhanVien,CCCD,SoBangLai,NgayHetHanBangLai,TrangThaiSanSang,ViDoHienTai,KinhDoHienTai,ThoiGianCapNhatViTri,DangHoatDong)
VALUES (@TK_S3,'GH-TP-001','079260000003','A1-260003','2031-03-31','AVAILABLE',10.802900,106.617900,@Now,1);
SET @S3 = SCOPE_IDENTITY();

INSERT INTO dbo.NhanVienGiaoHang(MaTaiKhoan,MaNhanVien,CCCD,SoBangLai,NgayHetHanBangLai,TrangThaiSanSang,ViDoHienTai,KinhDoHienTai,ThoiGianCapNhatViTri,DangHoatDong)
VALUES (@TK_S4,'GH-Q6-001','079260000004','A1-260004','2030-08-31','AVAILABLE',10.746900,106.635800,@Now,1);
SET @S4 = SCOPE_IDENTITY();

INSERT INTO dbo.NhanVienGiaoHang(MaTaiKhoan,MaNhanVien,CCCD,SoBangLai,NgayHetHanBangLai,TrangThaiSanSang,ViDoHienTai,KinhDoHienTai,ThoiGianCapNhatViTri,DangHoatDong)
VALUES (@TK_S5,'GH-Q6-002','079260000005','A1-260005','2031-01-31','BREAK',10.748000,106.637100,@Now,1);
SET @S5 = SCOPE_IDENTITY();

INSERT INTO dbo.PhuongTien(KyHieuPhuongTien,BienSo,LoaiXe,KhoiLuongDenKg,TheTichToiDaM3,TrangThaiPhuongTien,DangHoatDong)
VALUES ('XE-BT-001',N'59H1-812.34','MOTORBIKE',85,0.32,'AVAILABLE',1);
SET @Xe1 = SCOPE_IDENTITY();

INSERT INTO dbo.PhuongTien(KyHieuPhuongTien,BienSo,LoaiXe,KhoiLuongDenKg,TheTichToiDaM3,TrangThaiPhuongTien,DangHoatDong)
VALUES ('XE-BT-002',N'59H2-463.27','MOTORBIKE',90,0.35,'AVAILABLE',1);
SET @Xe2 = SCOPE_IDENTITY();

INSERT INTO dbo.PhuongTien(KyHieuPhuongTien,BienSo,LoaiXe,KhoiLuongDenKg,TheTichToiDaM3,TrangThaiPhuongTien,DangHoatDong)
VALUES ('XE-TP-001',N'59D2-375.61','MOTORBIKE',80,0.30,'AVAILABLE',1);
SET @Xe3 = SCOPE_IDENTITY();

INSERT INTO dbo.PhuongTien(KyHieuPhuongTien,BienSo,LoaiXe,KhoiLuongDenKg,TheTichToiDaM3,TrangThaiPhuongTien,DangHoatDong)
VALUES ('XE-Q6-001',N'59K1-724.18','MOTORBIKE',100,0.38,'AVAILABLE',1);
SET @Xe4 = SCOPE_IDENTITY();

INSERT INTO dbo.PhuongTien(KyHieuPhuongTien,BienSo,LoaiXe,KhoiLuongDenKg,TheTichToiDaM3,TrangThaiPhuongTien,DangHoatDong)
VALUES ('XE-Q6-002',N'59K2-518.42','MOTORBIKE',85,0.32,'MAINTENANCE',1);
SET @Xe5 = SCOPE_IDENTITY();

INSERT INTO dbo.PhanCongPhuongTien(MaNhanVienGiaoHang,MaPhuongTien,ThoiGianPhanCong,ThoiGianKetThuc,MaTaiKhoanPhanCong,GhiChu)
VALUES
(@S1,@Xe1,DATEADD(HOUR,-8,@Now),NULL,@TK_DPBT,N'Phân xe ca sáng'),
(@S2,@Xe2,DATEADD(HOUR,-8,@Now),NULL,@TK_DPBT,N'Phân xe ca sáng'),
(@S3,@Xe3,DATEADD(HOUR,-8,@Now),NULL,@TK_DPTP,N'Phân xe ca sáng'),
(@S4,@Xe4,DATEADD(HOUR,-8,@Now),NULL,@TK_DPQ6,N'Phân xe ca sáng');

INSERT INTO dbo.KhuVucNhanVienGiaoHang(MaNhanVienGiaoHang,MaKhuVuc,LaChinh) VALUES
(@S1,@KV_BHB,1),(@S1,@KV_AL,0),
(@S2,@KV_AL,1),(@S2,@KV_BHB,0),
(@S3,@KV_SK,1),(@S3,@KV_TT,0),
(@S4,@KV_Q6P10,1),(@S4,@KV_Q6P12,0),
(@S5,@KV_Q6P12,1);

INSERT INTO dbo.LichSuViTriNhanVienGiaoHang(MaNhanVienGiaoHang,ViDo,KinhDo,DoChinhXacMet,ThoiGianGhiNhan) VALUES
(@S1,10.810500,106.604800,4.8,DATEADD(MINUTE,-45,@Now)),
(@S1,10.798200,106.608900,6.2,DATEADD(MINUTE,-30,@Now)),
(@S1,10.775900,106.612600,5.4,DATEADD(MINUTE,-15,@Now)),
(@S2,10.812000,106.602900,5.1,DATEADD(MINUTE,-40,@Now)),
(@S2,10.805500,106.607300,7.4,DATEADD(MINUTE,-20,@Now)),
(@S3,10.802900,106.617900,4.6,DATEADD(MINUTE,-35,@Now)),
(@S3,10.798700,106.622100,5.2,DATEADD(MINUTE,-15,@Now)),
(@S4,10.746900,106.635800,5.0,DATEADD(MINUTE,-25,@Now)),
(@S5,10.748000,106.637100,6.0,DATEADD(MINUTE,-25,@Now));

--------------------------------------------------------------------------------
-- 5. QUY TẮC PHÍ
--------------------------------------------------------------------------------
PRINT N'5/15 - Quy tắc tính phí...';

INSERT INTO dbo.QuyTacTinhPhi
(MaLoaiDichVu,MaKhuVuc,KhoangCachTuKm,KhoangCachDenKm,KhoiLuongTuKg,KhoiLuongDenKg,
 PhiCoBan,PhiMoiKm,PhiMoiKg,HieuLucTu,HieuLucDen,DangHoatDong)
VALUES
(@DV_STD,@KV_BT,0,25,0,20,18000,3500,2500,DATEADD(DAY,-30,@Now),NULL,1),
(@DV_EXP,@KV_BT,0,25,0,20,28000,5000,3000,DATEADD(DAY,-30,@Now),NULL,1),
(@DV_STD,@KV_TP,0,25,0,20,18000,3500,2500,DATEADD(DAY,-30,@Now),NULL,1),
(@DV_EXP,@KV_TP,0,25,0,20,28000,5000,3000,DATEADD(DAY,-30,@Now),NULL,1),
(@DV_STD,@KV_Q6,0,25,0,20,18000,3500,2500,DATEADD(DAY,-30,@Now),NULL,1),
(@DV_EXP,@KV_Q6,0,25,0,20,28000,5000,3000,DATEADD(DAY,-30,@Now),NULL,1);

--------------------------------------------------------------------------------
-- 6. TẠO 12 ĐƠN HÀNG
--------------------------------------------------------------------------------
PRINT N'6/15 - Tạo 12 đơn hàng...';

DECLARE @OrderInput TABLE(
    KyHieu VARCHAR(40) PRIMARY KEY,
    VanDon VARCHAR(50),
    MaBC INT,
    Sender BIGINT,
    Receiver BIGINT,
    ServiceId INT,
    ReadyMin INT,
    RequestMin INT,
    EtaMin INT,
    Priority TINYINT,
    Declared DECIMAL(18,2),
    COD DECIMAL(18,2),
    Shipping DECIMAL(18,2),
    Note NVARCHAR(500)
);

INSERT INTO @OrderInput
(KyHieu, VanDon, MaBC, Sender, Receiver, ServiceId, ReadyMin, RequestMin, EtaMin,
 Priority, Declared, COD, Shipping, Note)
VALUES
('DH-HCM-261002-0001','LM261002000001',@BC_BT,@KH_ShopAnPhuc,@KH_01,@DV_STD,-150,120,180,2,450000,185000,32000,N'Gọi khách trước 10 phút; hàng điện tử'),
('DH-HCM-261002-0002','LM261002000002',@BC_BT,@KH_ShopAnPhuc,@KH_02,@DV_STD,-145,130,190,3,280000,0,29000,N'Không để kiện hàng dưới mưa'),
('DH-HCM-261002-0003','LM261002000003',@BC_BT,@KH_ShopAnPhuc,@KH_07,@DV_EXP,-140,90,140,1,850000,420000,45000,N'Đơn ưu tiên, khách nhận tại nhà'),
('DH-HCM-261002-0004','LM261002000004',@BC_BT,@KH_ShopMinhTam,@KH_02,@DV_STD,-135,150,210,3,180000,75000,30000,N'Gia dụng nhỏ, đóng gói chống sốc'),
('DH-HCM-261002-0005','LM261002000005',@BC_BT,@KH_ShopAnPhuc,@KH_09,@DV_EXP,-120,80,130,2,520000,220000,43000,N'Khách thường đi làm, ưu tiên gọi trước'),
('DH-HCM-261002-0006','LM261002000006',@BC_BT,@KH_ShopMinhTam,@KH_01,@DV_STD,-115,170,230,3,390000,0,30000,N'Giao trong ngày'),
('DH-HCM-261002-0007','LM261002000007',@BC_TP,@KH_ShopMinhTam,@KH_03,@DV_EXP,-110,90,150,1,620000,310000,46000,N'Hàng dễ vỡ'),
('DH-HCM-261002-0008','LM261002000008',@BC_TP,@KH_ShopMinhTam,@KH_04,@DV_STD,-100,180,260,3,250000,0,31000,N'Chờ phân công shipper'),
('DH-HCM-261002-0009','LM261002000009',@BC_TP,@KH_ShopMinhTam,@KH_08,@DV_STD,-90,210,290,4,310000,125000,33000,N'Hàng đang lưu kho'),
('DH-HCM-261002-0010','LM261002000010',@BC_Q6,@KH_ShopNhaXinh,@KH_05,@DV_STD,-80,220,300,3,780000,350000,37000,N'Kiện hàng cồng kềnh vừa'),
('DH-HCM-261002-0011','LM261002000011',@BC_Q6,@KH_ShopNhaXinh,@KH_06,@DV_EXP,-70,150,220,2,560000,0,44000,N'Đã tiếp nhận, chờ nhập kho'),
('DH-HCM-261002-0012','LM261002000012',@BC_Q6,@KH_ShopNhaXinh,@KH_05,@DV_STD,-60,240,320,5,200000,0,30000,N'Khách yêu cầu hủy trước khi nhập kho');

DECLARE @OrderMap TABLE(KyHieu VARCHAR(40) PRIMARY KEY, MaDonHang BIGINT);

INSERT INTO dbo.DonHang
(KyHieuDonHang,MaVanDon,MaBuuCuc,MaNguoiGui,MaNguoiNhan,MaLoaiDichVu,MaTrangThaiHienTai,
 MaKhoHienTai,ThoiGianSanSang,ThoiGianYeuCauGiao,ThoiGianDuKienGiao,MucDoUuTien,
 GiaTriKhaiBao,TienCOD,PhiVanChuyen,GhiChuDacBiet,MaTaiKhoanTao,MaTaiKhoanCapNhatCuoi)
OUTPUT inserted.KyHieuDonHang,inserted.MaDonHang INTO @OrderMap
SELECT o.KyHieu,o.VanDon,o.MaBC,o.Sender,o.Receiver,o.ServiceId,@TT_NEW,NULL,
       DATEADD(MINUTE,o.ReadyMin,@Now),
       DATEADD(MINUTE,o.RequestMin,@Now),
       DATEADD(MINUTE,o.EtaMin,@Now),
       o.Priority,o.Declared,o.COD,o.Shipping,o.Note,
       CASE WHEN o.MaBC=@BC_BT THEN @TK_DPBT WHEN o.MaBC=@BC_TP THEN @TK_DPTP ELSE @TK_DPQ6 END,
       CASE WHEN o.MaBC=@BC_BT THEN @TK_DPBT WHEN o.MaBC=@BC_TP THEN @TK_DPTP ELSE @TK_DPQ6 END
FROM @OrderInput o;

DECLARE
    @O1 BIGINT, @O2 BIGINT, @O3 BIGINT, @O4 BIGINT,
    @O5 BIGINT, @O6 BIGINT, @O7 BIGINT, @O8 BIGINT,
    @O9 BIGINT, @O10 BIGINT, @O11 BIGINT, @O12 BIGINT;

SELECT @O1 = MaDonHang FROM @OrderMap WHERE KyHieu = 'DH-HCM-261002-0001';
SELECT @O2 = MaDonHang FROM @OrderMap WHERE KyHieu = 'DH-HCM-261002-0002';
SELECT @O3 = MaDonHang FROM @OrderMap WHERE KyHieu = 'DH-HCM-261002-0003';
SELECT @O4 = MaDonHang FROM @OrderMap WHERE KyHieu = 'DH-HCM-261002-0004';
SELECT @O5 = MaDonHang FROM @OrderMap WHERE KyHieu = 'DH-HCM-261002-0005';
SELECT @O6 = MaDonHang FROM @OrderMap WHERE KyHieu = 'DH-HCM-261002-0006';
SELECT @O7 = MaDonHang FROM @OrderMap WHERE KyHieu = 'DH-HCM-261002-0007';
SELECT @O8 = MaDonHang FROM @OrderMap WHERE KyHieu = 'DH-HCM-261002-0008';
SELECT @O9 = MaDonHang FROM @OrderMap WHERE KyHieu = 'DH-HCM-261002-0009';
SELECT @O10 = MaDonHang FROM @OrderMap WHERE KyHieu = 'DH-HCM-261002-0010';
SELECT @O11 = MaDonHang FROM @OrderMap WHERE KyHieu = 'DH-HCM-261002-0011';
SELECT @O12 = MaDonHang FROM @OrderMap WHERE KyHieu = 'DH-HCM-261002-0012';

-- Điểm lấy/giao.
INSERT INTO dbo.DiemGiaoNhan(MaDonHang,LoaiDiem,TenNguoiLienHe,SoDienThoaiLienHe,DiaChi,MaKhuVuc,ViDo,KinhDo,GhiChu)
VALUES
(@O1,'PICKUP',N'Nguyễn Thị Yến','0912000001',N'42 Đường số 7, Bình Hưng Hòa B, Bình Tân, TP.HCM',@KV_BHB,10.811800,106.601500,N'Kho cửa hàng'),
(@O1,'DELIVERY',N'Nguyễn Ngọc Anh','0912000101',N'118 Đường số 5, An Lạc, Bình Tân, TP.HCM',@KV_AL,10.728900,106.615200,N'Gọi trước 10 phút'),
(@O2,'PICKUP',N'Nguyễn Thị Yến','0912000001',N'42 Đường số 7, Bình Hưng Hòa B, Bình Tân, TP.HCM',@KV_BHB,10.811800,106.601500,NULL),
(@O2,'DELIVERY',N'Trần Khánh Vy','0912000102',N'76 Đường số 18B, Bình Hưng Hòa B, Bình Tân, TP.HCM',@KV_BHB,10.816000,106.598900,NULL),
(@O3,'PICKUP',N'Nguyễn Thị Yến','0912000001',N'42 Đường số 7, Bình Hưng Hòa B, Bình Tân, TP.HCM',@KV_BHB,10.811800,106.601500,NULL),
(@O3,'DELIVERY',N'Bùi Gia Bảo','0912000107',N'55 Đường số 1, An Lạc, Bình Tân, TP.HCM',@KV_AL,10.731800,106.611900,N'Khách nhận trực tiếp'),
(@O4,'PICKUP',N'Trần Văn Dũng','0912000002',N'155 Tân Kỳ Tân Quý, Sơn Kỳ, Tân Phú, TP.HCM',@KV_SK,10.803400,106.618800,N'Hàng đã chuyển về bưu cục Bình Tân'),
(@O4,'DELIVERY',N'Trần Khánh Vy','0912000102',N'76 Đường số 18B, Bình Hưng Hòa B, Bình Tân, TP.HCM',@KV_BHB,10.816000,106.598900,NULL),
(@O5,'PICKUP',N'Nguyễn Thị Yến','0912000001',N'42 Đường số 7, Bình Hưng Hòa B, Bình Tân, TP.HCM',@KV_BHB,10.811800,106.601500,NULL),
(@O5,'DELIVERY',N'Ngô Đức Anh','0912000109',N'89 Đường số 12, Bình Hưng Hòa B, Bình Tân, TP.HCM',@KV_BHB,10.814300,106.603200,N'Khách thường đi làm'),
(@O6,'PICKUP',N'Trần Văn Dũng','0912000002',N'155 Tân Kỳ Tân Quý, Sơn Kỳ, Tân Phú, TP.HCM',@KV_SK,10.803400,106.618800,NULL),
(@O6,'DELIVERY',N'Nguyễn Ngọc Anh','0912000101',N'118 Đường số 5, An Lạc, Bình Tân, TP.HCM',@KV_AL,10.728900,106.615200,NULL),
(@O7,'PICKUP',N'Trần Văn Dũng','0912000002',N'155 Tân Kỳ Tân Quý, Sơn Kỳ, Tân Phú, TP.HCM',@KV_SK,10.803400,106.618800,NULL),
(@O7,'DELIVERY',N'Lê Minh Khang','0912000103',N'25 Tân Hương, Tân Thành, Tân Phú, TP.HCM',@KV_TT,10.789900,106.628000,N'Hàng dễ vỡ'),
(@O8,'PICKUP',N'Trần Văn Dũng','0912000002',N'155 Tân Kỳ Tân Quý, Sơn Kỳ, Tân Phú, TP.HCM',@KV_SK,10.803400,106.618800,NULL),
(@O8,'DELIVERY',N'Phạm Thảo Nhi','0912000104',N'212 Lê Trọng Tấn, Sơn Kỳ, Tân Phú, TP.HCM',@KV_SK,10.806700,106.624600,NULL),
(@O9,'PICKUP',N'Trần Văn Dũng','0912000002',N'155 Tân Kỳ Tân Quý, Sơn Kỳ, Tân Phú, TP.HCM',@KV_SK,10.803400,106.618800,NULL),
(@O9,'DELIVERY',N'Hoàng Mỹ Linh','0912000108',N'101 Tân Quý, Tân Thành, Tân Phú, TP.HCM',@KV_TT,10.795300,106.625400,NULL),
(@O10,'PICKUP',N'Lê Thanh Bình','0912000003',N'96 Hậu Giang, Phường 10, Quận 6, TP.HCM',@KV_Q6P10,10.747800,106.634900,NULL),
(@O10,'DELIVERY',N'Võ Quốc Huy','0912000105',N'310 Hậu Giang, Phường 12, Quận 6, TP.HCM',@KV_Q6P12,10.744100,106.629800,NULL),
(@O11,'PICKUP',N'Lê Thanh Bình','0912000003',N'96 Hậu Giang, Phường 10, Quận 6, TP.HCM',@KV_Q6P10,10.747800,106.634900,NULL),
(@O11,'DELIVERY',N'Đặng Thu Hà','0912000106',N'74 Bình Phú, Phường 10, Quận 6, TP.HCM',@KV_Q6P10,10.741300,106.637900,NULL),
(@O12,'PICKUP',N'Lê Thanh Bình','0912000003',N'96 Hậu Giang, Phường 10, Quận 6, TP.HCM',@KV_Q6P10,10.747800,106.634900,NULL),
(@O12,'DELIVERY',N'Võ Quốc Huy','0912000105',N'310 Hậu Giang, Phường 12, Quận 6, TP.HCM',@KV_Q6P12,10.744100,106.629800,NULL);

-- Hàng hóa: mọi kiện tham gia chuyến đều có đủ kích thước để trigger kiểm thể tích.
INSERT INTO dbo.ChiTietDonHang(MaDonHang,TenHang,LoaiHang,SoLuong,KhoiLuongDonViKg,ChieuDaiCm,ChieuRongCm,ChieuCaoCm,GiaTriHang,HangDeVo,GhiChu)
VALUES
(@O1,N'Tai nghe Bluetooth',N'Điện tử',1,0.35,18,12,6,450000,1,N'Đóng hộp chống sốc'),
(@O2,N'Áo khoác unisex',N'Thời trang',1,0.60,35,28,8,280000,0,NULL),
(@O3,N'Máy xay mini',N'Gia dụng',1,1.20,28,22,24,850000,1,N'Không lật ngược'),
(@O4,N'Bộ hộp đựng thực phẩm',N'Gia dụng',1,1.60,38,28,24,180000,0,NULL),
(@O5,N'Bàn phím cơ',N'Điện tử',1,1.10,48,20,8,520000,1,N'Tránh va đập'),
(@O6,N'Bộ khăn tắm cotton',N'Gia dụng',2,0.70,32,25,10,195000,0,NULL),
(@O7,N'Bình giữ nhiệt inox',N'Gia dụng',2,0.55,28,12,12,310000,1,N'Đóng chống sốc'),
(@O8,N'Giày thể thao',N'Thời trang',1,0.95,34,22,13,250000,0,NULL),
(@O9,N'Chuột không dây',N'Điện tử',1,0.25,16,10,6,310000,1,NULL),
(@O10,N'Đèn bàn trang trí',N'Nội thất',2,1.60,36,26,24,390000,1,N'Kiện cồng kềnh vừa'),
(@O11,N'Bộ ga gối cotton',N'Nội thất',1,2.20,42,34,18,560000,0,NULL),
(@O12,N'Kệ để đồ mini',N'Nội thất',1,3.00,60,35,15,200000,0,NULL);

INSERT INTO dbo.KhoanPhiDonHang(MaDonHang,LoaiKhoanPhi,SoTien,MoTa)
VALUES
(@O1,'SHIPPING',32000,N'Phí giao tiêu chuẩn'),
(@O2,'SHIPPING',29000,N'Phí giao tiêu chuẩn'),
(@O3,'SHIPPING',45000,N'Phí giao nhanh'),
(@O3,'SURCHARGE',8000,N'Phụ phí ưu tiên'),
(@O4,'SHIPPING',30000,N'Phí giao tiêu chuẩn'),
(@O5,'SHIPPING',43000,N'Phí giao nhanh'),
(@O6,'SHIPPING',30000,N'Phí giao tiêu chuẩn'),
(@O7,'SHIPPING',46000,N'Phí giao nhanh'),
(@O7,'SURCHARGE',7000,N'Phụ phí hàng dễ vỡ'),
(@O8,'SHIPPING',31000,N'Phí giao tiêu chuẩn'),
(@O9,'SHIPPING',33000,N'Phí giao tiêu chuẩn'),
(@O10,'SHIPPING',37000,N'Phí giao tiêu chuẩn'),
(@O10,'SURCHARGE',12000,N'Phụ phí kiện cồng kềnh'),
(@O11,'SHIPPING',44000,N'Phí giao nhanh'),
(@O12,'SHIPPING',30000,N'Phí dự kiến trước khi hủy');

--------------------------------------------------------------------------------
-- 7. XÁC NHẬN / HỦY / CHỜ NHẬP KHO
--------------------------------------------------------------------------------
PRINT N'7/15 - Chuyển trạng thái đầu vòng đời...';

EXEC dbo.sp_ChuyenTrangThaiDonHang
     @MaDonHang = @O12,
     @KyHieuTrangThaiMoi = 'CANCELLED',
     @MaTaiKhoan = @TK_DPQ6,
     @LyDo = N'Khách hàng yêu cầu hủy trước khi hàng vào kho',
     @NguonCapNhat = 'WEB';

DECLARE
    @i INT,
    @oid BIGINT,
    @creator BIGINT,
    @TaiKhoanThucHien BIGINT,
    @ThoiGianGiaoLai DATETIME2(0);

SET @i = 1;
WHILE @i<=11
BEGIN
    SELECT @oid = MaDonHang,
           @creator = CASE WHEN @i<=6 THEN @TK_DPBT WHEN @i<=9 THEN @TK_DPTP ELSE @TK_DPQ6 END
    FROM @OrderMap WHERE KyHieu=CONCAT('DH-HCM-261002-',RIGHT('0000'+CONVERT(VARCHAR(4),@i),4));

    EXEC dbo.sp_XacNhanDonHang
         @MaDonHang = @oid,
         @MaTaiKhoan = @creator;

    SET @TaiKhoanThucHien =
        CASE
            WHEN @i <= 6 THEN @TK_KhoBT
            WHEN @i <= 9 THEN @TK_KhoTP
            ELSE @TK_KhoQ6
        END;

    EXEC dbo.sp_ChuyenTrangThaiDonHang
         @MaDonHang = @oid,
         @KyHieuTrangThaiMoi = 'WAITING_INBOUND',
         @MaTaiKhoan = @TaiKhoanThucHien,
         @LyDo = NULL,
         @NguonCapNhat = 'WEB';
    SET @i = @i + 1;
END;

--------------------------------------------------------------------------------
-- 8. NHẬP KHO CHO ĐƠN 1..10. ĐƠN 11 GIỮ WAITING_INBOUND
--------------------------------------------------------------------------------
PRINT N'8/15 - Nhập kho...';

INSERT INTO dbo.GiaoDichKho(KyHieuGiaoDich,MaKho,LoaiGiaoDich,TrangThaiGiaoDich,MaTaiKhoanThucHien,ThoiGianThucHien,GhiChu)
VALUES ('GD-BT-IN-261002-01',@Kho_BT,'INBOUND','COMPLETED',@TK_KhoBT,DATEADD(MINUTE,-80,@Now),N'Nhập lô hàng đầu ca');
SET @WT_BT_IN = SCOPE_IDENTITY();

INSERT INTO dbo.ChiTietGiaoDichKho(MaGiaoDichKho,MaDonHang,MaViTriNguon,MaViTriDich,TinhTrangHang,GhiChu)
VALUES
(@WT_BT_IN,@O1,NULL,@VT_BT_A1,'NORMAL',N'Bao bì nguyên vẹn'),
(@WT_BT_IN,@O2,NULL,@VT_BT_A1,'NORMAL',N'Bao bì nguyên vẹn'),
(@WT_BT_IN,@O3,NULL,@VT_BT_A2,'NORMAL',N'Đã dán tem dễ vỡ'),
(@WT_BT_IN,@O4,NULL,@VT_BT_A2,'NORMAL',N'Bao bì nguyên vẹn'),
(@WT_BT_IN,@O5,NULL,@VT_BT_A3,'NORMAL',N'Bao bì nguyên vẹn'),
(@WT_BT_IN,@O6,NULL,@VT_BT_A3,'NORMAL',N'Bao bì nguyên vẹn');

INSERT INTO dbo.GiaoDichKho(KyHieuGiaoDich,MaKho,LoaiGiaoDich,TrangThaiGiaoDich,MaTaiKhoanThucHien,ThoiGianThucHien,GhiChu)
VALUES ('GD-TP-IN-261002-01',@Kho_TP,'INBOUND','COMPLETED',@TK_KhoTP,DATEADD(MINUTE,-75,@Now),N'Nhập hàng Tân Phú');
SET @WT_TP_IN = SCOPE_IDENTITY();

INSERT INTO dbo.ChiTietGiaoDichKho(MaGiaoDichKho,MaDonHang,MaViTriNguon,MaViTriDich,TinhTrangHang,GhiChu)
VALUES
(@WT_TP_IN,@O7,NULL,@VT_TP_A1,'NORMAL',N'Đã dán tem dễ vỡ'),
(@WT_TP_IN,@O8,NULL,@VT_TP_A2,'NORMAL',N'Bao bì nguyên vẹn'),
(@WT_TP_IN,@O9,NULL,@VT_TP_A2,'NORMAL',N'Bao bì nguyên vẹn');

INSERT INTO dbo.GiaoDichKho(KyHieuGiaoDich,MaKho,LoaiGiaoDich,TrangThaiGiaoDich,MaTaiKhoanThucHien,ThoiGianThucHien,GhiChu)
VALUES ('GD-Q6-IN-261002-01',@Kho_Q6,'INBOUND','COMPLETED',@TK_KhoQ6,DATEADD(MINUTE,-70,@Now),N'Nhập hàng Quận 6');
SET @WT_Q6_IN = SCOPE_IDENTITY();

INSERT INTO dbo.ChiTietGiaoDichKho(MaGiaoDichKho,MaDonHang,MaViTriNguon,MaViTriDich,TinhTrangHang,GhiChu)
VALUES (@WT_Q6_IN,@O10,NULL,@VT_Q6_A1,'NORMAL',N'Bao bì nguyên vẹn');

INSERT INTO dbo.TonKhoDonHang(MaDonHang,MaKho,MaViTriLuuKho,TrangThaiTonKho,ThoiGianNhapKho,ThoiGianDiChuyenCuoi,MaTaiKhoanCapNhatCuoi)
VALUES
(@O1,@Kho_BT,@VT_BT_A1,'STORED',DATEADD(MINUTE,-80,@Now),DATEADD(MINUTE,-78,@Now),@TK_KhoBT),
(@O2,@Kho_BT,@VT_BT_A1,'STORED',DATEADD(MINUTE,-80,@Now),DATEADD(MINUTE,-78,@Now),@TK_KhoBT),
(@O3,@Kho_BT,@VT_BT_A2,'STORED',DATEADD(MINUTE,-80,@Now),DATEADD(MINUTE,-78,@Now),@TK_KhoBT),
(@O4,@Kho_BT,@VT_BT_A2,'STORED',DATEADD(MINUTE,-80,@Now),DATEADD(MINUTE,-78,@Now),@TK_KhoBT),
(@O5,@Kho_BT,@VT_BT_A3,'STORED',DATEADD(MINUTE,-80,@Now),DATEADD(MINUTE,-78,@Now),@TK_KhoBT),
(@O6,@Kho_BT,@VT_BT_A3,'STORED',DATEADD(MINUTE,-80,@Now),DATEADD(MINUTE,-78,@Now),@TK_KhoBT),
(@O7,@Kho_TP,@VT_TP_A1,'STORED',DATEADD(MINUTE,-75,@Now),DATEADD(MINUTE,-73,@Now),@TK_KhoTP),
(@O8,@Kho_TP,@VT_TP_A2,'STORED',DATEADD(MINUTE,-75,@Now),DATEADD(MINUTE,-73,@Now),@TK_KhoTP),
(@O9,@Kho_TP,@VT_TP_A2,'STORED',DATEADD(MINUTE,-75,@Now),DATEADD(MINUTE,-73,@Now),@TK_KhoTP),
(@O10,@Kho_Q6,@VT_Q6_A1,'STORED',DATEADD(MINUTE,-70,@Now),DATEADD(MINUTE,-68,@Now),@TK_KhoQ6);

UPDATE dbo.DonHang SET MaKhoHienTai=@Kho_BT,MaTaiKhoanCapNhatCuoi=@TK_KhoBT WHERE MaDonHang IN (@O1,@O2,@O3,@O4,@O5,@O6);
UPDATE dbo.DonHang SET MaKhoHienTai=@Kho_TP,MaTaiKhoanCapNhatCuoi=@TK_KhoTP WHERE MaDonHang IN (@O7,@O8,@O9);
UPDATE dbo.DonHang SET MaKhoHienTai=@Kho_Q6,MaTaiKhoanCapNhatCuoi=@TK_KhoQ6 WHERE MaDonHang=@O10;

SET @i = 1;
WHILE @i<=10
BEGIN
    SELECT @oid = MaDonHang FROM @OrderMap
    WHERE KyHieu=CONCAT('DH-HCM-261002-',RIGHT('0000'+CONVERT(VARCHAR(4),@i),4));

    SET @TaiKhoanThucHien =
        CASE
            WHEN @i <= 6 THEN @TK_KhoBT
            WHEN @i <= 9 THEN @TK_KhoTP
            ELSE @TK_KhoQ6
        END;

    EXEC dbo.sp_ChuyenTrangThaiDonHang
         @MaDonHang = @oid,
         @KyHieuTrangThaiMoi = 'IN_WAREHOUSE',
         @MaTaiKhoan = @TaiKhoanThucHien,
         @LyDo = NULL,
         @NguonCapNhat = 'WEB';
    SET @i = @i + 1;
END;

-- 1..8 và 10 chờ phân công; 9 cố ý giữ IN_WAREHOUSE.
SET @i = 1;
WHILE @i<=10
BEGIN
    IF @i<>9
    BEGIN
        SELECT @oid = MaDonHang FROM @OrderMap
        WHERE KyHieu=CONCAT('DH-HCM-261002-',RIGHT('0000'+CONVERT(VARCHAR(4),@i),4));

        SET @TaiKhoanThucHien =
            CASE
                WHEN @i <= 6 THEN @TK_DPBT
                WHEN @i <= 9 THEN @TK_DPTP
                ELSE @TK_DPQ6
            END;

        EXEC dbo.sp_ChuyenTrangThaiDonHang
             @MaDonHang = @oid,
             @KyHieuTrangThaiMoi = 'WAITING_ASSIGNMENT',
             @MaTaiKhoan = @TaiKhoanThucHien,
             @LyDo = NULL,
             @NguonCapNhat = 'WEB';
    END;
    SET @i = @i + 1;
END;

--------------------------------------------------------------------------------
-- 9. CHUYẾN 1: 4 ĐƠN BÌNH TÂN -> GIAO THÀNH CÔNG
--------------------------------------------------------------------------------
PRINT N'9/15 - Chuyến giao hoàn tất Bình Tân...';

INSERT INTO dbo.ChuyenGiaoHang
(KyHieuChuyenGiao,MaBuuCuc,MaKho,MaNhanVienGiaoHang,MaPhuongTien,TrangThaiChuyen,
 PhuongPhapToiUu,TongQuangDuongKm,ThoiGianDuKienPhut,ThoiGianBatDauDuKien,MaTaiKhoanTao)
VALUES ('CG-BT-261002-001',@BC_BT,@Kho_BT,@S1,@Xe1,'PLANNED','VRP',23.40,105,DATEADD(MINUTE,-55,@Now),@TK_DPBT);
SET @Trip1 = SCOPE_IDENTITY();

INSERT INTO dbo.ChiTietChuyenGiao(MaChuyenGiao,MaDonHang,ThuTuDuKien,ThoiGianDenDuKien,ThoiGianDenThucTe)
VALUES
(@Trip1,@O1,1,DATEADD(MINUTE,-25,@Now),NULL),
(@Trip1,@O3,2,DATEADD(MINUTE,-5,@Now),NULL),
(@Trip1,@O2,3,DATEADD(MINUTE,15,@Now),NULL),
(@Trip1,@O4,4,DATEADD(MINUTE,35,@Now),NULL);

DECLARE @D1 BIGINT;
SELECT @D1 = MaDiemGiaoNhan
FROM dbo.DiemGiaoNhan
WHERE MaDonHang = @O1
  AND LoaiDiem = 'DELIVERY';
DECLARE @D2 BIGINT;
SELECT @D2 = MaDiemGiaoNhan
FROM dbo.DiemGiaoNhan
WHERE MaDonHang = @O2
  AND LoaiDiem = 'DELIVERY';
DECLARE @D3 BIGINT;
SELECT @D3 = MaDiemGiaoNhan
FROM dbo.DiemGiaoNhan
WHERE MaDonHang = @O3
  AND LoaiDiem = 'DELIVERY';
DECLARE @D4 BIGINT;
SELECT @D4 = MaDiemGiaoNhan
FROM dbo.DiemGiaoNhan
WHERE MaDonHang = @O4
  AND LoaiDiem = 'DELIVERY';

INSERT INTO dbo.DiemDungTuyen(MaChuyenGiao,MaDonHang,MaDiemGiaoNhan,ThuTuDiemDung,LoaiDiem,ViDo,KinhDo,ThoiGianDenDuKien,KhoangCachTuDiemTruocKm,ThoiGianTuDiemTruocPhut)
VALUES
(@Trip1,NULL,NULL,1,'BRANCH',10.810500,106.604800,DATEADD(MINUTE,-55,@Now),NULL,NULL),
(@Trip1,@O1,@D1,2,'DELIVERY',10.728900,106.615200,DATEADD(MINUTE,-25,@Now),10.4,30),
(@Trip1,@O3,@D3,3,'DELIVERY',10.731800,106.611900,DATEADD(MINUTE,-5,@Now),2.2,15),
(@Trip1,@O2,@D2,4,'DELIVERY',10.816000,106.598900,DATEADD(MINUTE,15,@Now),11.1,25),
(@Trip1,@O4,@D4,5,'DELIVERY',10.816000,106.598900,DATEADD(MINUTE,35,@Now),0.2,5);

DECLARE @PC1 BIGINT,@PC2 BIGINT,@PC3 BIGINT,@PC4 BIGINT;
INSERT INTO dbo.PhanCongGiaoHang(MaDonHang,MaChuyenGiao,MaNhanVienGiaoHang,MaPhuongTien,MaTaiKhoanPhanCong,ThoiGianPhanCong,TrangThaiPhanCong,BoQuaQuyTacKhuVuc)
VALUES (@O1,@Trip1,@S1,@Xe1,@TK_DPBT,DATEADD(MINUTE,-52,@Now),'PENDING',0); SET @PC1 = SCOPE_IDENTITY();
INSERT INTO dbo.PhanCongGiaoHang(MaDonHang,MaChuyenGiao,MaNhanVienGiaoHang,MaPhuongTien,MaTaiKhoanPhanCong,ThoiGianPhanCong,TrangThaiPhanCong,BoQuaQuyTacKhuVuc)
VALUES (@O2,@Trip1,@S1,@Xe1,@TK_DPBT,DATEADD(MINUTE,-52,@Now),'PENDING',0); SET @PC2 = SCOPE_IDENTITY();
INSERT INTO dbo.PhanCongGiaoHang(MaDonHang,MaChuyenGiao,MaNhanVienGiaoHang,MaPhuongTien,MaTaiKhoanPhanCong,ThoiGianPhanCong,TrangThaiPhanCong,BoQuaQuyTacKhuVuc)
VALUES (@O3,@Trip1,@S1,@Xe1,@TK_DPBT,DATEADD(MINUTE,-52,@Now),'PENDING',0); SET @PC3 = SCOPE_IDENTITY();
INSERT INTO dbo.PhanCongGiaoHang(MaDonHang,MaChuyenGiao,MaNhanVienGiaoHang,MaPhuongTien,MaTaiKhoanPhanCong,ThoiGianPhanCong,TrangThaiPhanCong,BoQuaQuyTacKhuVuc)
VALUES (@O4,@Trip1,@S1,@Xe1,@TK_DPBT,DATEADD(MINUTE,-52,@Now),'PENDING',0); SET @PC4 = SCOPE_IDENTITY();

EXEC dbo.sp_ChuyenTrangThaiDonHang
     @MaDonHang = @O1,
     @KyHieuTrangThaiMoi = 'ASSIGNED',
     @MaTaiKhoan = @TK_DPBT,
     @LyDo = NULL,
     @NguonCapNhat = 'WEB';
EXEC dbo.sp_ChuyenTrangThaiDonHang
     @MaDonHang = @O2,
     @KyHieuTrangThaiMoi = 'ASSIGNED',
     @MaTaiKhoan = @TK_DPBT,
     @LyDo = NULL,
     @NguonCapNhat = 'WEB';
EXEC dbo.sp_ChuyenTrangThaiDonHang
     @MaDonHang = @O3,
     @KyHieuTrangThaiMoi = 'ASSIGNED',
     @MaTaiKhoan = @TK_DPBT,
     @LyDo = NULL,
     @NguonCapNhat = 'WEB';
EXEC dbo.sp_ChuyenTrangThaiDonHang
     @MaDonHang = @O4,
     @KyHieuTrangThaiMoi = 'ASSIGNED',
     @MaTaiKhoan = @TK_DPBT,
     @LyDo = NULL,
     @NguonCapNhat = 'WEB';

UPDATE dbo.PhanCongGiaoHang
SET TrangThaiPhanCong='ACCEPTED',ThoiGianChapNhan=DATEADD(MINUTE,-50,@Now)
WHERE MaPhanCongGiaoHang IN (@PC1,@PC2,@PC3,@PC4);

UPDATE dbo.ChuyenGiaoHang
SET TrangThaiChuyen='ACCEPTED',ThoiGianBatDauThucTe=DATEADD(MINUTE,-48,@Now)
WHERE MaChuyenGiao=@Trip1;

UPDATE dbo.TonKhoDonHang
SET TrangThaiTonKho='ALLOCATED',ThoiGianDiChuyenCuoi=DATEADD(MINUTE,-47,@Now),MaTaiKhoanCapNhatCuoi=@TK_KhoBT
WHERE MaDonHang IN (@O1,@O2,@O3,@O4);

INSERT INTO dbo.BanGiaoHang(KyHieuBanGiao,MaKho,MaNhanVienGiaoHang,MaTaiKhoanBanGiao,TrangThaiBanGiao,ThoiGianBanGiao,ThoiGianNhanVienXacNhan,GhiChu)
VALUES ('BG-BT-261002-001',@Kho_BT,@S1,@TK_KhoBT,'CONFIRMED',DATEADD(MINUTE,-46,@Now),DATEADD(MINUTE,-45,@Now),N'Bàn giao chuyến sáng Bình Tân');
SET @Handover1 = SCOPE_IDENTITY();

INSERT INTO dbo.ChiTietBanGiaoHang(MaBanGiao,MaDonHang,SoLuong,GhiChuTinhTrang)
VALUES
(@Handover1,@O1,1,N'Nguyên vẹn'),(@Handover1,@O2,1,N'Nguyên vẹn'),
(@Handover1,@O3,1,N'Đã kiểm tem dễ vỡ'),(@Handover1,@O4,1,N'Nguyên vẹn');

INSERT INTO dbo.GiaoDichKho(KyHieuGiaoDich,MaKho,LoaiGiaoDich,TrangThaiGiaoDich,MaTaiKhoanThucHien,ThoiGianThucHien,GhiChu)
VALUES ('GD-BT-OUT-261002-01',@Kho_BT,'OUTBOUND','COMPLETED',@TK_KhoBT,DATEADD(MINUTE,-44,@Now),N'Xuất chuyến CG-BT-261002-001');
SET @WT_BT_OUT1 = SCOPE_IDENTITY();

INSERT INTO dbo.ChiTietGiaoDichKho(MaGiaoDichKho,MaDonHang,MaViTriNguon,MaViTriDich,TinhTrangHang,GhiChu)
VALUES
(@WT_BT_OUT1,@O1,@VT_BT_A1,NULL,'NORMAL',N'Xuất giao'),
(@WT_BT_OUT1,@O2,@VT_BT_A1,NULL,'NORMAL',N'Xuất giao'),
(@WT_BT_OUT1,@O3,@VT_BT_A2,NULL,'NORMAL',N'Xuất giao'),
(@WT_BT_OUT1,@O4,@VT_BT_A2,NULL,'NORMAL',N'Xuất giao');

UPDATE dbo.TonKhoDonHang
SET TrangThaiTonKho='HANDED_OVER',MaViTriLuuKho=NULL,ThoiGianDiChuyenCuoi=DATEADD(MINUTE,-43,@Now),MaTaiKhoanCapNhatCuoi=@TK_KhoBT
WHERE MaDonHang IN (@O1,@O2,@O3,@O4);

EXEC dbo.sp_ChuyenTrangThaiDonHang
     @MaDonHang = @O1,
     @KyHieuTrangThaiMoi = 'HANDED_OVER',
     @MaTaiKhoan = @TK_KhoBT,
     @LyDo = NULL,
     @NguonCapNhat = 'WEB';
EXEC dbo.sp_ChuyenTrangThaiDonHang
     @MaDonHang = @O2,
     @KyHieuTrangThaiMoi = 'HANDED_OVER',
     @MaTaiKhoan = @TK_KhoBT,
     @LyDo = NULL,
     @NguonCapNhat = 'WEB';
EXEC dbo.sp_ChuyenTrangThaiDonHang
     @MaDonHang = @O3,
     @KyHieuTrangThaiMoi = 'HANDED_OVER',
     @MaTaiKhoan = @TK_KhoBT,
     @LyDo = NULL,
     @NguonCapNhat = 'WEB';
EXEC dbo.sp_ChuyenTrangThaiDonHang
     @MaDonHang = @O4,
     @KyHieuTrangThaiMoi = 'HANDED_OVER',
     @MaTaiKhoan = @TK_KhoBT,
     @LyDo = NULL,
     @NguonCapNhat = 'WEB';

EXEC dbo.sp_ChuyenTrangThaiDonHang
     @MaDonHang = @O1,
     @KyHieuTrangThaiMoi = 'PICKED_UP',
     @MaTaiKhoan = @TK_S1,
     @LyDo = NULL,
     @NguonCapNhat = 'MOBILE';
EXEC dbo.sp_ChuyenTrangThaiDonHang
     @MaDonHang = @O2,
     @KyHieuTrangThaiMoi = 'PICKED_UP',
     @MaTaiKhoan = @TK_S1,
     @LyDo = NULL,
     @NguonCapNhat = 'MOBILE';
EXEC dbo.sp_ChuyenTrangThaiDonHang
     @MaDonHang = @O3,
     @KyHieuTrangThaiMoi = 'PICKED_UP',
     @MaTaiKhoan = @TK_S1,
     @LyDo = NULL,
     @NguonCapNhat = 'MOBILE';
EXEC dbo.sp_ChuyenTrangThaiDonHang
     @MaDonHang = @O4,
     @KyHieuTrangThaiMoi = 'PICKED_UP',
     @MaTaiKhoan = @TK_S1,
     @LyDo = NULL,
     @NguonCapNhat = 'MOBILE';

UPDATE dbo.PhanCongGiaoHang SET TrangThaiPhanCong='IN_PROGRESS'
WHERE MaPhanCongGiaoHang IN (@PC1,@PC2,@PC3,@PC4);

UPDATE dbo.ChuyenGiaoHang SET TrangThaiChuyen='IN_PROGRESS' WHERE MaChuyenGiao=@Trip1;
UPDATE dbo.NhanVienGiaoHang SET TrangThaiSanSang='DELIVERING' WHERE MaNhanVienGiaoHang=@S1;
UPDATE dbo.PhuongTien SET TrangThaiPhuongTien='IN_USE' WHERE MaPhuongTien=@Xe1;

EXEC dbo.sp_ChuyenTrangThaiDonHang
     @MaDonHang = @O1,
     @KyHieuTrangThaiMoi = 'IN_DELIVERY',
     @MaTaiKhoan = @TK_S1,
     @LyDo = NULL,
     @NguonCapNhat = 'MOBILE';
EXEC dbo.sp_ChuyenTrangThaiDonHang
     @MaDonHang = @O2,
     @KyHieuTrangThaiMoi = 'IN_DELIVERY',
     @MaTaiKhoan = @TK_S1,
     @LyDo = NULL,
     @NguonCapNhat = 'MOBILE';
EXEC dbo.sp_ChuyenTrangThaiDonHang
     @MaDonHang = @O3,
     @KyHieuTrangThaiMoi = 'IN_DELIVERY',
     @MaTaiKhoan = @TK_S1,
     @LyDo = NULL,
     @NguonCapNhat = 'MOBILE';
EXEC dbo.sp_ChuyenTrangThaiDonHang
     @MaDonHang = @O4,
     @KyHieuTrangThaiMoi = 'IN_DELIVERY',
     @MaTaiKhoan = @TK_S1,
     @LyDo = NULL,
     @NguonCapNhat = 'MOBILE';

EXEC dbo.sp_XacNhanGiaoHangThanhCong
     @MaDonHang = @O1,
     @MaNhanVienGiaoHang = @S1,
     @MaTaiKhoan = @TK_S1,
     @LoaiBangChung = 'PHOTO',
     @DuongDanTep = N'/pod/2026/10/02/LM261002000001.jpg',
     @MaXacNhanBam = NULL,
     @TenNguoiNhan = NULL,
     @ViDo = 10.728900,
     @KinhDo = 106.615200,
     @SoTienThucThu = 185000,
     @GhiChuCOD = N'Thu tiền mặt đủ 185.000đ';
EXEC dbo.sp_XacNhanGiaoHangThanhCong
     @MaDonHang = @O2,
     @MaNhanVienGiaoHang = @S1,
     @MaTaiKhoan = @TK_S1,
     @LoaiBangChung = 'OTP',
     @DuongDanTep = NULL,
     @MaXacNhanBam = 'OTP_HASH_928461',
     @TenNguoiNhan = NULL,
     @ViDo = 10.816000,
     @KinhDo = 106.598900,
     @SoTienThucThu = NULL,
     @GhiChuCOD = NULL;
EXEC dbo.sp_XacNhanGiaoHangThanhCong
     @MaDonHang = @O3,
     @MaNhanVienGiaoHang = @S1,
     @MaTaiKhoan = @TK_S1,
     @LoaiBangChung = 'SIGNATURE',
     @DuongDanTep = N'/pod/2026/10/02/LM261002000003-sign.png',
     @MaXacNhanBam = NULL,
     @TenNguoiNhan = NULL,
     @ViDo = 10.731800,
     @KinhDo = 106.611900,
     @SoTienThucThu = 420000,
     @GhiChuCOD = N'Thu tiền mặt đủ 420.000đ';
EXEC dbo.sp_XacNhanGiaoHangThanhCong
     @MaDonHang = @O4,
     @MaNhanVienGiaoHang = @S1,
     @MaTaiKhoan = @TK_S1,
     @LoaiBangChung = 'RECEIVER_CONFIRMATION',
     @DuongDanTep = NULL,
     @MaXacNhanBam = NULL,
     @TenNguoiNhan = N'Trần Khánh Vy',
     @ViDo = 10.816000,
     @KinhDo = 106.598900,
     @SoTienThucThu = 75000,
     @GhiChuCOD = N'Thu tiền mặt đủ 75.000đ';

EXEC dbo.sp_ChuyenTrangThaiDonHang
     @MaDonHang = @O1,
     @KyHieuTrangThaiMoi = 'COMPLETED',
     @MaTaiKhoan = @TK_DPBT,
     @LyDo = NULL,
     @NguonCapNhat = 'SYSTEM';
EXEC dbo.sp_ChuyenTrangThaiDonHang
     @MaDonHang = @O2,
     @KyHieuTrangThaiMoi = 'COMPLETED',
     @MaTaiKhoan = @TK_DPBT,
     @LyDo = NULL,
     @NguonCapNhat = 'SYSTEM';
EXEC dbo.sp_ChuyenTrangThaiDonHang
     @MaDonHang = @O3,
     @KyHieuTrangThaiMoi = 'COMPLETED',
     @MaTaiKhoan = @TK_DPBT,
     @LyDo = NULL,
     @NguonCapNhat = 'SYSTEM';
EXEC dbo.sp_ChuyenTrangThaiDonHang
     @MaDonHang = @O4,
     @KyHieuTrangThaiMoi = 'COMPLETED',
     @MaTaiKhoan = @TK_DPBT,
     @LyDo = NULL,
     @NguonCapNhat = 'SYSTEM';

UPDATE dbo.ChuyenGiaoHang
SET TrangThaiChuyen='COMPLETED',ThoiGianKetThucThucTe=SYSUTCDATETIME()
WHERE MaChuyenGiao=@Trip1;

UPDATE dbo.NhanVienGiaoHang SET TrangThaiSanSang='AVAILABLE' WHERE MaNhanVienGiaoHang=@S1;
UPDATE dbo.PhuongTien SET TrangThaiPhuongTien='AVAILABLE' WHERE MaPhuongTien=@Xe1;

--------------------------------------------------------------------------------
-- 10. CHUYẾN 2: 1 ĐƠN THẤT BẠI CHỜ GIAO LẠI + 1 ĐƠN ĐANG GIAO
--------------------------------------------------------------------------------
PRINT N'10/15 - Chuyến Bình Tân đang hoạt động...';

INSERT INTO dbo.ChuyenGiaoHang
(KyHieuChuyenGiao,MaBuuCuc,MaKho,MaNhanVienGiaoHang,MaPhuongTien,TrangThaiChuyen,
 PhuongPhapToiUu,TongQuangDuongKm,ThoiGianDuKienPhut,ThoiGianBatDauDuKien,MaTaiKhoanTao)
VALUES ('CG-BT-261002-002',@BC_BT,@Kho_BT,@S2,@Xe2,'PLANNED','VRP',16.80,80,DATEADD(MINUTE,-35,@Now),@TK_DPBT);
SET @Trip2 = SCOPE_IDENTITY();

INSERT INTO dbo.ChiTietChuyenGiao(MaChuyenGiao,MaDonHang,ThuTuDuKien,ThoiGianDenDuKien)
VALUES (@Trip2,@O5,1,DATEADD(MINUTE,-5,@Now)),(@Trip2,@O6,2,DATEADD(MINUTE,25,@Now));

DECLARE @D5 BIGINT;
SELECT @D5 = MaDiemGiaoNhan
FROM dbo.DiemGiaoNhan
WHERE MaDonHang = @O5
  AND LoaiDiem = 'DELIVERY';
DECLARE @D6 BIGINT;
SELECT @D6 = MaDiemGiaoNhan
FROM dbo.DiemGiaoNhan
WHERE MaDonHang = @O6
  AND LoaiDiem = 'DELIVERY';

INSERT INTO dbo.DiemDungTuyen(MaChuyenGiao,MaDonHang,MaDiemGiaoNhan,ThuTuDiemDung,LoaiDiem,ViDo,KinhDo,ThoiGianDenDuKien,KhoangCachTuDiemTruocKm,ThoiGianTuDiemTruocPhut)
VALUES
(@Trip2,NULL,NULL,1,'BRANCH',10.810500,106.604800,DATEADD(MINUTE,-35,@Now),NULL,NULL),
(@Trip2,@O5,@D5,2,'DELIVERY',10.814300,106.603200,DATEADD(MINUTE,-5,@Now),3.2,15),
(@Trip2,@O6,@D6,3,'DELIVERY',10.728900,106.615200,DATEADD(MINUTE,25,@Now),10.8,30);

DECLARE @PC5 BIGINT,@PC6 BIGINT;
INSERT INTO dbo.PhanCongGiaoHang(MaDonHang,MaChuyenGiao,MaNhanVienGiaoHang,MaPhuongTien,MaTaiKhoanPhanCong,ThoiGianPhanCong,TrangThaiPhanCong,BoQuaQuyTacKhuVuc)
VALUES (@O5,@Trip2,@S2,@Xe2,@TK_DPBT,DATEADD(MINUTE,-33,@Now),'PENDING',0); SET @PC5 = SCOPE_IDENTITY();
INSERT INTO dbo.PhanCongGiaoHang(MaDonHang,MaChuyenGiao,MaNhanVienGiaoHang,MaPhuongTien,MaTaiKhoanPhanCong,ThoiGianPhanCong,TrangThaiPhanCong,BoQuaQuyTacKhuVuc)
VALUES (@O6,@Trip2,@S2,@Xe2,@TK_DPBT,DATEADD(MINUTE,-33,@Now),'PENDING',0); SET @PC6 = SCOPE_IDENTITY();

EXEC dbo.sp_ChuyenTrangThaiDonHang
     @MaDonHang = @O5,
     @KyHieuTrangThaiMoi = 'ASSIGNED',
     @MaTaiKhoan = @TK_DPBT,
     @LyDo = NULL,
     @NguonCapNhat = 'WEB';
EXEC dbo.sp_ChuyenTrangThaiDonHang
     @MaDonHang = @O6,
     @KyHieuTrangThaiMoi = 'ASSIGNED',
     @MaTaiKhoan = @TK_DPBT,
     @LyDo = NULL,
     @NguonCapNhat = 'WEB';

UPDATE dbo.PhanCongGiaoHang SET TrangThaiPhanCong='ACCEPTED',ThoiGianChapNhan=DATEADD(MINUTE,-31,@Now)
WHERE MaPhanCongGiaoHang IN (@PC5,@PC6);

UPDATE dbo.ChuyenGiaoHang SET TrangThaiChuyen='ACCEPTED',ThoiGianBatDauThucTe=DATEADD(MINUTE,-30,@Now) WHERE MaChuyenGiao=@Trip2;
UPDATE dbo.TonKhoDonHang SET TrangThaiTonKho='ALLOCATED',ThoiGianDiChuyenCuoi=DATEADD(MINUTE,-29,@Now),MaTaiKhoanCapNhatCuoi=@TK_KhoBT WHERE MaDonHang IN (@O5,@O6);

INSERT INTO dbo.BanGiaoHang(KyHieuBanGiao,MaKho,MaNhanVienGiaoHang,MaTaiKhoanBanGiao,TrangThaiBanGiao,ThoiGianBanGiao,ThoiGianNhanVienXacNhan,GhiChu)
VALUES ('BG-BT-261002-002',@Kho_BT,@S2,@TK_KhoBT,'CONFIRMED',DATEADD(MINUTE,-28,@Now),DATEADD(MINUTE,-27,@Now),N'Bàn giao chuyến đang giao');
SET @Handover2 = SCOPE_IDENTITY();

INSERT INTO dbo.ChiTietBanGiaoHang(MaBanGiao,MaDonHang,SoLuong,GhiChuTinhTrang)
VALUES (@Handover2,@O5,1,N'Nguyên vẹn'),(@Handover2,@O6,1,N'Nguyên vẹn');

INSERT INTO dbo.GiaoDichKho(KyHieuGiaoDich,MaKho,LoaiGiaoDich,TrangThaiGiaoDich,MaTaiKhoanThucHien,ThoiGianThucHien,GhiChu)
VALUES ('GD-BT-OUT-261002-02',@Kho_BT,'OUTBOUND','COMPLETED',@TK_KhoBT,DATEADD(MINUTE,-26,@Now),N'Xuất chuyến CG-BT-261002-002');
SET @WT_BT_OUT2 = SCOPE_IDENTITY();

INSERT INTO dbo.ChiTietGiaoDichKho(MaGiaoDichKho,MaDonHang,MaViTriNguon,MaViTriDich,TinhTrangHang,GhiChu)
VALUES
(@WT_BT_OUT2,@O5,@VT_BT_A3,NULL,'NORMAL',N'Xuất giao'),
(@WT_BT_OUT2,@O6,@VT_BT_A3,NULL,'NORMAL',N'Xuất giao');

UPDATE dbo.TonKhoDonHang
SET TrangThaiTonKho='HANDED_OVER',MaViTriLuuKho=NULL,ThoiGianDiChuyenCuoi=DATEADD(MINUTE,-25,@Now),MaTaiKhoanCapNhatCuoi=@TK_KhoBT
WHERE MaDonHang IN (@O5,@O6);

EXEC dbo.sp_ChuyenTrangThaiDonHang
     @MaDonHang = @O5,
     @KyHieuTrangThaiMoi = 'HANDED_OVER',
     @MaTaiKhoan = @TK_KhoBT,
     @LyDo = NULL,
     @NguonCapNhat = 'WEB';
EXEC dbo.sp_ChuyenTrangThaiDonHang
     @MaDonHang = @O6,
     @KyHieuTrangThaiMoi = 'HANDED_OVER',
     @MaTaiKhoan = @TK_KhoBT,
     @LyDo = NULL,
     @NguonCapNhat = 'WEB';
EXEC dbo.sp_ChuyenTrangThaiDonHang
     @MaDonHang = @O5,
     @KyHieuTrangThaiMoi = 'PICKED_UP',
     @MaTaiKhoan = @TK_S2,
     @LyDo = NULL,
     @NguonCapNhat = 'MOBILE';
EXEC dbo.sp_ChuyenTrangThaiDonHang
     @MaDonHang = @O6,
     @KyHieuTrangThaiMoi = 'PICKED_UP',
     @MaTaiKhoan = @TK_S2,
     @LyDo = NULL,
     @NguonCapNhat = 'MOBILE';

UPDATE dbo.PhanCongGiaoHang SET TrangThaiPhanCong='IN_PROGRESS' WHERE MaPhanCongGiaoHang IN (@PC5,@PC6);
UPDATE dbo.ChuyenGiaoHang SET TrangThaiChuyen='IN_PROGRESS' WHERE MaChuyenGiao=@Trip2;
UPDATE dbo.NhanVienGiaoHang SET TrangThaiSanSang='DELIVERING' WHERE MaNhanVienGiaoHang=@S2;
UPDATE dbo.PhuongTien SET TrangThaiPhuongTien='IN_USE' WHERE MaPhuongTien=@Xe2;

EXEC dbo.sp_ChuyenTrangThaiDonHang
     @MaDonHang = @O5,
     @KyHieuTrangThaiMoi = 'IN_DELIVERY',
     @MaTaiKhoan = @TK_S2,
     @LyDo = NULL,
     @NguonCapNhat = 'MOBILE';
EXEC dbo.sp_ChuyenTrangThaiDonHang
     @MaDonHang = @O6,
     @KyHieuTrangThaiMoi = 'IN_DELIVERY',
     @MaTaiKhoan = @TK_S2,
     @LyDo = NULL,
     @NguonCapNhat = 'MOBILE';

SET @ThoiGianGiaoLai = DATEADD(HOUR, 3, @Now);

EXEC dbo.sp_XacNhanGiaoHangThatBai
     @MaDonHang = @O5,
     @MaNhanVienGiaoHang = @S2,
     @MaTaiKhoan = @TK_S2,
     @MaLyDoGiaoThatBai = @LyDoNoAnswer,
     @GhiChu = N'Gọi 3 lần trong 15 phút nhưng khách chưa nghe máy',
     @ThoiGianGiaoLaiDuKien = @ThoiGianGiaoLai,
     @DuongDanTepMinhChung = NULL,
     @ViDo = 10.814300,
     @KinhDo = 106.603200;

INSERT INTO dbo.YeuCauGiaoLaiHoacHoan(MaDonHang,LoaiYeuCau,TrangThaiYeuCau,MaBuuCucHoan,LyDo,MaTaiKhoanYeuCau,ThoiGianYeuCau,ThoiGianHoanTat)
VALUES (@O5,'RETRY','APPROVED',NULL,N'Đã liên hệ lại; khách hẹn nhận sau 17:00',@TK_DPBT,@Now,NULL);

EXEC dbo.sp_ChuyenTrangThaiDonHang
     @MaDonHang = @O5,@KyHieuTrangThaiMoi = 'RETRY_WAITING',
     @MaTaiKhoan = @TK_DPBT,@LyDo = N'Khách hẹn giao lại sau 17:00',@NguonCapNhat = 'WEB';

INSERT INTO dbo.CanhBaoGiaoHang(MaDonHang,MaChuyenGiao,LoaiCanhBao,MucDoCanhBao,NoiDungCanhBao,TrangThaiCanhBao,ThoiGianPhatHien)
VALUES (@O5,@Trip2,'LATE_RISK','WARNING',N'Đơn giao thất bại lần 1, có nguy cơ trễ SLA.','OPEN',@Now);

--------------------------------------------------------------------------------
-- 11. CHUYẾN 3 TÂN PHÚ: ĐƠN 7 ĐANG GIAO
--------------------------------------------------------------------------------
PRINT N'11/15 - Chuyến Tân Phú đang giao...';

INSERT INTO dbo.ChuyenGiaoHang
(KyHieuChuyenGiao,MaBuuCuc,MaKho,MaNhanVienGiaoHang,MaPhuongTien,TrangThaiChuyen,
 PhuongPhapToiUu,TongQuangDuongKm,ThoiGianDuKienPhut,ThoiGianBatDauDuKien,MaTaiKhoanTao)
VALUES ('CG-TP-261002-001',@BC_TP,@Kho_TP,@S3,@Xe3,'PLANNED','ASTAR',9.60,50,DATEADD(MINUTE,-25,@Now),@TK_DPTP);
SET @Trip3 = SCOPE_IDENTITY();

INSERT INTO dbo.ChiTietChuyenGiao(MaChuyenGiao,MaDonHang,ThuTuDuKien,ThoiGianDenDuKien)
VALUES (@Trip3,@O7,1,DATEADD(MINUTE,15,@Now));

DECLARE @D7 BIGINT;
SELECT @D7 = MaDiemGiaoNhan
FROM dbo.DiemGiaoNhan
WHERE MaDonHang = @O7
  AND LoaiDiem = 'DELIVERY';
INSERT INTO dbo.DiemDungTuyen(MaChuyenGiao,MaDonHang,MaDiemGiaoNhan,ThuTuDiemDung,LoaiDiem,ViDo,KinhDo,ThoiGianDenDuKien,KhoangCachTuDiemTruocKm,ThoiGianTuDiemTruocPhut)
VALUES
(@Trip3,NULL,NULL,1,'BRANCH',10.802900,106.617900,DATEADD(MINUTE,-25,@Now),NULL,NULL),
(@Trip3,@O7,@D7,2,'DELIVERY',10.789900,106.628000,DATEADD(MINUTE,15,@Now),4.8,22);

DECLARE @PC7 BIGINT;
INSERT INTO dbo.PhanCongGiaoHang(MaDonHang,MaChuyenGiao,MaNhanVienGiaoHang,MaPhuongTien,MaTaiKhoanPhanCong,ThoiGianPhanCong,TrangThaiPhanCong,BoQuaQuyTacKhuVuc)
VALUES (@O7,@Trip3,@S3,@Xe3,@TK_DPTP,DATEADD(MINUTE,-23,@Now),'PENDING',0);
SET @PC7 = SCOPE_IDENTITY();

EXEC dbo.sp_ChuyenTrangThaiDonHang
     @MaDonHang = @O7,
     @KyHieuTrangThaiMoi = 'ASSIGNED',
     @MaTaiKhoan = @TK_DPTP,
     @LyDo = NULL,
     @NguonCapNhat = 'WEB';
UPDATE dbo.PhanCongGiaoHang SET TrangThaiPhanCong='ACCEPTED',ThoiGianChapNhan=DATEADD(MINUTE,-21,@Now) WHERE MaPhanCongGiaoHang=@PC7;
UPDATE dbo.ChuyenGiaoHang SET TrangThaiChuyen='ACCEPTED',ThoiGianBatDauThucTe=DATEADD(MINUTE,-20,@Now) WHERE MaChuyenGiao=@Trip3;
UPDATE dbo.TonKhoDonHang SET TrangThaiTonKho='ALLOCATED',ThoiGianDiChuyenCuoi=DATEADD(MINUTE,-19,@Now),MaTaiKhoanCapNhatCuoi=@TK_KhoTP WHERE MaDonHang=@O7;

INSERT INTO dbo.BanGiaoHang(KyHieuBanGiao,MaKho,MaNhanVienGiaoHang,MaTaiKhoanBanGiao,TrangThaiBanGiao,ThoiGianBanGiao,ThoiGianNhanVienXacNhan,GhiChu)
VALUES ('BG-TP-261002-001',@Kho_TP,@S3,@TK_KhoTP,'CONFIRMED',DATEADD(MINUTE,-18,@Now),DATEADD(MINUTE,-17,@Now),N'Bàn giao đơn dễ vỡ');
SET @Handover3 = SCOPE_IDENTITY();

INSERT INTO dbo.ChiTietBanGiaoHang(MaBanGiao,MaDonHang,SoLuong,GhiChuTinhTrang)
VALUES (@Handover3,@O7,1,N'Nguyên vẹn, tem dễ vỡ còn nguyên');

INSERT INTO dbo.GiaoDichKho(KyHieuGiaoDich,MaKho,LoaiGiaoDich,TrangThaiGiaoDich,MaTaiKhoanThucHien,ThoiGianThucHien,GhiChu)
VALUES ('GD-TP-OUT-261002-01',@Kho_TP,'OUTBOUND','COMPLETED',@TK_KhoTP,DATEADD(MINUTE,-16,@Now),N'Xuất chuyến CG-TP-261002-001');
SET @WT_TP_OUT = SCOPE_IDENTITY();

INSERT INTO dbo.ChiTietGiaoDichKho(MaGiaoDichKho,MaDonHang,MaViTriNguon,MaViTriDich,TinhTrangHang,GhiChu)
VALUES (@WT_TP_OUT,@O7,@VT_TP_A1,NULL,'NORMAL',N'Xuất giao');

UPDATE dbo.TonKhoDonHang
SET TrangThaiTonKho='HANDED_OVER',MaViTriLuuKho=NULL,ThoiGianDiChuyenCuoi=DATEADD(MINUTE,-15,@Now),MaTaiKhoanCapNhatCuoi=@TK_KhoTP
WHERE MaDonHang=@O7;

EXEC dbo.sp_ChuyenTrangThaiDonHang
     @MaDonHang = @O7,
     @KyHieuTrangThaiMoi = 'HANDED_OVER',
     @MaTaiKhoan = @TK_KhoTP,
     @LyDo = NULL,
     @NguonCapNhat = 'WEB';
EXEC dbo.sp_ChuyenTrangThaiDonHang
     @MaDonHang = @O7,
     @KyHieuTrangThaiMoi = 'PICKED_UP',
     @MaTaiKhoan = @TK_S3,
     @LyDo = NULL,
     @NguonCapNhat = 'MOBILE';
UPDATE dbo.PhanCongGiaoHang SET TrangThaiPhanCong='IN_PROGRESS' WHERE MaPhanCongGiaoHang=@PC7;
UPDATE dbo.ChuyenGiaoHang SET TrangThaiChuyen='IN_PROGRESS' WHERE MaChuyenGiao=@Trip3;
UPDATE dbo.NhanVienGiaoHang SET TrangThaiSanSang='DELIVERING',ViDoHienTai=10.798700,KinhDoHienTai=106.622100,ThoiGianCapNhatViTri=@Now WHERE MaNhanVienGiaoHang=@S3;
UPDATE dbo.PhuongTien SET TrangThaiPhuongTien='IN_USE' WHERE MaPhuongTien=@Xe3;
EXEC dbo.sp_ChuyenTrangThaiDonHang
     @MaDonHang = @O7,
     @KyHieuTrangThaiMoi = 'IN_DELIVERY',
     @MaTaiKhoan = @TK_S3,
     @LyDo = NULL,
     @NguonCapNhat = 'MOBILE';

--------------------------------------------------------------------------------
-- 12. COD: SHIPPER 1 NỘP 680.000 VÀ ĐỐI SOÁT KHỚP
--------------------------------------------------------------------------------
PRINT N'12/15 - Nộp COD và đối soát...';

INSERT INTO dbo.NopTienCOD
(KyHieuNopTien,MaNhanVienGiaoHang,MaBuuCuc,SoTienNop,PhuongThucNop,TrangThaiNop,ThoiGianNop,MaThamChieuNgoai,GhiChu)
VALUES ('NOP-BT-261002-001',@S1,@BC_BT,680000,'CASH','PENDING',@Now,'PHIEU-THU-BT-261002-001',N'Nộp COD sau chuyến sáng');
SET @Deposit = SCOPE_IDENTITY();

INSERT INTO dbo.ChiTietNopTienCOD(MaNopTienCOD,MaDonHang,SoTienPhanBo)
VALUES (@Deposit,@O1,185000),(@Deposit,@O3,420000),(@Deposit,@O4,75000);

EXEC dbo.sp_XacNhanNopTienCOD
     @MaNopTienCOD = @Deposit,
     @MaTaiKhoanXacNhan = @TK_KeToan;

INSERT INTO dbo.DoiSoatCOD
(KyHieuDoiSoat,MaBuuCuc,MaNhanVienGiaoHang,TuThoiGian,DenThoiGian,TongTienPhaiThu,TongTienDaThu,TongTienDaNop,TrangThaiDoiSoat,GhiChu)
VALUES ('DS-BT-261002-S1',@BC_BT,@S1,DATEADD(HOUR,-3,@Now),DATEADD(HOUR,1,@Now),0,0,0,'DRAFT',N'Đối soát COD chuyến sáng Nguyễn Minh Tuấn');
SET @Recon = SCOPE_IDENTITY();

EXEC dbo.sp_XacNhanDoiSoatCOD
     @MaDoiSoatCOD = @Recon,
     @MaTaiKhoanXacNhan = @TK_KeToan;

--------------------------------------------------------------------------------
-- 13. ĐÁNH GIÁ + KHIẾU NẠI
--------------------------------------------------------------------------------
PRINT N'13/15 - Đánh giá và khiếu nại...';

INSERT INTO dbo.DanhGia(MaDonHang,MaKhachHang,MaNhanVienGiaoHang,SoSao,NhanXet,ThoiGianTao)
VALUES
(@O1,@KH_01,@S1,5,N'Giao đúng hẹn, shipper gọi trước và hỗ trợ kiểm hàng.',@Now),
(@O2,@KH_02,@S1,4,N'Giao nhanh, kiện hàng sạch sẽ.',@Now),
(@O3,@KH_07,@S1,5,N'Shipper lịch sự, hàng dễ vỡ vẫn nguyên vẹn.',@Now);

INSERT INTO dbo.KhieuNai(KyHieuKhieuNai,MaDonHang,MaKhachHang,LoaiKhieuNai,TieuDe,NoiDung,TrangThaiKhieuNai,MucDoUuTien,MaTaiKhoanXuLy,KetQuaXuLy,ThoiGianTao,ThoiGianXuLy)
VALUES
('KN-261002-001',@O3,@KH_07,'OTHER',N'Kiểm tra tình trạng vỏ hộp',N'Khách phản ánh góc vỏ hộp bị móp nhẹ nhưng sản phẩm bên trong bình thường.','RESOLVED','NORMAL',@TK_MgrBT,N'Đã đối chiếu ảnh POD và xác nhận sản phẩm nguyên vẹn; khách đồng ý kết thúc.',DATEADD(MINUTE,-10,@Now),@Now);
SET @Complaint1 = SCOPE_IDENTITY();

INSERT INTO dbo.LichSuKhieuNai(MaKhieuNai,TrangThaiCu,TrangThaiMoi,MaTaiKhoanThucHien,ThoiGianThucHien,GhiChu)
VALUES
(@Complaint1,NULL,'OPEN',@TK_MgrBT,DATEADD(MINUTE,-10,@Now),N'Tiếp nhận phản ánh'),
(@Complaint1,'OPEN','IN_PROGRESS',@TK_MgrBT,DATEADD(MINUTE,-7,@Now),N'Kiểm tra ảnh bằng chứng'),
(@Complaint1,'IN_PROGRESS','RESOLVED',@TK_MgrBT,@Now,N'Đã phản hồi khách');

INSERT INTO dbo.KhieuNai(KyHieuKhieuNai,MaDonHang,MaKhachHang,LoaiKhieuNai,TieuDe,NoiDung,TrangThaiKhieuNai,MucDoUuTien,MaTaiKhoanXuLy,KetQuaXuLy,ThoiGianTao,ThoiGianXuLy)
VALUES
('KN-261002-002',@O5,@KH_09,'LATE',N'Đề nghị giao lại sau giờ làm',N'Khách không thể nhận trong giờ hành chính và đề nghị giao lại sau 17:00.','OPEN','NORMAL',@TK_DPBT,NULL,@Now,NULL);
SET @Complaint2 = SCOPE_IDENTITY();

INSERT INTO dbo.LichSuKhieuNai(MaKhieuNai,TrangThaiCu,TrangThaiMoi,MaTaiKhoanThucHien,ThoiGianThucHien,GhiChu)
VALUES (@Complaint2,NULL,'OPEN',@TK_DPBT,@Now,N'Ghi nhận yêu cầu thay đổi thời điểm giao');

--------------------------------------------------------------------------------
-- 14. THÔNG BÁO + AUDIT LOG
--------------------------------------------------------------------------------
PRINT N'14/15 - Thông báo và audit...';

INSERT INTO dbo.ThongBao(MaTaiKhoan,LoaiThongBao,TieuDe,NoiDung,LoaiDoiTuongThamChieu,MaDoiTuongThamChieu,DaDoc,ThoiGianTao,ThoiGianDoc)
VALUES
(@TK_S2,'DELIVERY_RETRY',N'Đơn cần giao lại',N'Đơn LM261002000005 được hẹn giao lại sau 17:00.','ORDER',@O5,0,@Now,NULL),
(@TK_DPBT,'DELIVERY_ALERT',N'Nguy cơ trễ SLA',N'Đơn LM261002000005 đã giao thất bại một lần.','ORDER',@O5,1,DATEADD(MINUTE,-2,@Now),@Now),
(@TK_KeToan,'COD_DEPOSIT',N'Phiếu nộp COD đã xác nhận',N'Phiếu NOP-BT-261002-001 trị giá 680.000đ đã được xác nhận.','COD_DEPOSIT',@Deposit,1,DATEADD(MINUTE,-2,@Now),@Now),
(@TK_DPTP,'TRIP_STARTED',N'Chuyến Tân Phú đang thực hiện',N'CG-TP-261002-001 đã xuất phát với 1 đơn hàng.','TRIP',@Trip3,0,@Now,NULL);

INSERT INTO dbo.NhatKyHoatDong(MaTaiKhoan,LoaiThaoTac,TenDoiTuong,MaDoiTuong,DuLieuCuJson,DuLieuMoiJson,DiaChiIP,ThongTinThietBi,ThoiGianTao)
VALUES
(@TK_DPBT,'CREATE_ORDER','DonHang',CONVERT(VARCHAR(100),@O1),NULL,N'{"tracking":"LM261002000001","branch":"HCM-BT01"}','10.10.1.15',N'Web Dispatcher / Windows 11',DATEADD(MINUTE,-100,@Now)),
(@TK_KhoBT,'WAREHOUSE_INBOUND','GiaoDichKho',CONVERT(VARCHAR(100),@WT_BT_IN),NULL,N'{"type":"INBOUND","orders":6}','10.10.1.25',N'Warehouse Web / Chrome',DATEADD(MINUTE,-80,@Now)),
(@TK_DPBT,'CREATE_TRIP','ChuyenGiaoHang',CONVERT(VARCHAR(100),@Trip1),NULL,N'{"method":"VRP","orders":4}','10.10.1.15',N'Web Dispatcher / Windows 11',DATEADD(MINUTE,-55,@Now)),
(@TK_S2,'DELIVERY_FAILED','DonHang',CONVERT(VARCHAR(100),@O5),N'{"status":"IN_DELIVERY"}',N'{"status":"RETRY_WAITING","reason":"NO_ANSWER"}','10.10.2.102',N'Android Mobile App',@Now),
(@TK_KeToan,'CONFIRM_COD_DEPOSIT','NopTienCOD',CONVERT(VARCHAR(100),@Deposit),N'{"status":"PENDING"}',N'{"status":"CONFIRMED","amount":680000}','10.10.1.35',N'Finance Web / Edge',@Now),
(@TK_KeToan,'CONFIRM_COD_RECON','DoiSoatCOD',CONVERT(VARCHAR(100),@Recon),N'{"status":"DRAFT"}',N'{"status":"CONFIRMED","amount":680000}','10.10.1.35',N'Finance Web / Edge',@Now);

COMMIT;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK;

    SELECT
        ERROR_NUMBER() AS MaLoi,
        ERROR_LINE() AS DongLoi,
        ERROR_MESSAGE() AS NoiDungLoi;

    THROW;
END CATCH;
GO

--------------------------------------------------------------------------------
-- 15. KIỂM TRA DỮ LIỆU SAU KHI INSERT
--------------------------------------------------------------------------------
PRINT N'15/15 - Kiểm tra kết quả';

SELECT
    d.KyHieuDonHang,
    d.MaVanDon,
    bc.TenBuuCuc,
    tt.TenTrangThai,
    dv.TenDichVu,
    d.TongKhoiLuongKg,
    d.TienCOD,
    d.PhiVanChuyen
FROM dbo.DonHang d
JOIN dbo.BuuCuc bc ON bc.MaBuuCuc=d.MaBuuCuc
JOIN dbo.TrangThaiDonHang tt ON tt.MaTrangThaiDonHang=d.MaTrangThaiHienTai
JOIN dbo.LoaiDichVu dv ON dv.MaLoaiDichVu=d.MaLoaiDichVu
WHERE d.KyHieuDonHang LIKE 'DH-HCM-261002-%'
ORDER BY d.KyHieuDonHang;

SELECT
    cg.KyHieuChuyenGiao,
    cg.TrangThaiChuyen,
    tk.HoTen AS Shipper,
    pt.BienSo,
    COUNT(ct.MaDonHang) AS SoDon,
    cg.TongQuangDuongKm,
    cg.ThoiGianDuKienPhut
FROM dbo.ChuyenGiaoHang cg
LEFT JOIN dbo.NhanVienGiaoHang nv ON nv.MaNhanVienGiaoHang=cg.MaNhanVienGiaoHang
LEFT JOIN dbo.TaiKhoan tk ON tk.MaTaiKhoan=nv.MaTaiKhoan
LEFT JOIN dbo.PhuongTien pt ON pt.MaPhuongTien=cg.MaPhuongTien
LEFT JOIN dbo.ChiTietChuyenGiao ct ON ct.MaChuyenGiao=cg.MaChuyenGiao
WHERE cg.KyHieuChuyenGiao LIKE 'CG-%-261002-%'
GROUP BY cg.KyHieuChuyenGiao,cg.TrangThaiChuyen,tk.HoTen,pt.BienSo,cg.TongQuangDuongKm,cg.ThoiGianDuKienPhut
ORDER BY cg.KyHieuChuyenGiao;

SELECT
    d.MaVanDon,
    lg.SoLanThu,
    lg.KetQua,
    ld.TenLyDo,
    lg.GhiChu,
    lg.ThoiGianGiaoLaiDuKien
FROM dbo.LanGiaoHang lg
JOIN dbo.DonHang d ON d.MaDonHang=lg.MaDonHang
LEFT JOIN dbo.LyDoGiaoThatBai ld ON ld.MaLyDoGiaoThatBai=lg.MaLyDoGiaoThatBai
WHERE d.KyHieuDonHang LIKE 'DH-HCM-261002-%'
ORDER BY d.MaVanDon,lg.SoLanThu;

SELECT
    d.MaVanDon,
    cod.SoTienPhaiThu,
    cod.SoTienThucThu,
    cod.TrangThaiThuTien,
    nop.KyHieuNopTien,
    nop.TrangThaiNop
FROM dbo.ThuTienCOD cod
JOIN dbo.DonHang d ON d.MaDonHang=cod.MaDonHang
LEFT JOIN dbo.ChiTietNopTienCOD ct ON ct.MaDonHang=d.MaDonHang
LEFT JOIN dbo.NopTienCOD nop ON nop.MaNopTienCOD=ct.MaNopTienCOD
WHERE d.KyHieuDonHang LIKE 'DH-HCM-261002-%'
ORDER BY d.MaVanDon;

SELECT KyHieuDoiSoat,TongTienPhaiThu,TongTienDaThu,TongTienDaNop,SoTienChenhLech,TrangThaiDoiSoat
FROM dbo.DoiSoatCOD
WHERE KyHieuDoiSoat='DS-BT-261002-S1';

SELECT
    tt.KyHieuTrangThai,
    tt.TenTrangThai,
    COUNT(*) AS SoLuongDon
FROM dbo.DonHang d
JOIN dbo.TrangThaiDonHang tt ON tt.MaTrangThaiDonHang=d.MaTrangThaiHienTai
WHERE d.KyHieuDonHang LIKE 'DH-HCM-261002-%'
GROUP BY tt.KyHieuTrangThai,tt.TenTrangThai
ORDER BY MIN(tt.ThuTuSapXep);
GO
