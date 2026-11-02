namespace LastMile.Api.Services;

internal static class PickupIssueSql
{
    public const string Schema = """
        IF OBJECT_ID(N'dbo.ShipperPickupIssue',N'U') IS NULL OR OBJECT_ID(N'dbo.ShipperPickupIssueEvent',N'U') IS NULL
            THROW 55900,N'Chưa áp dụng migration 20261030_shipper_pickup_issues.sql.',1;
        """;
    public const string Actor = """
        SET NOCOUNT ON; SET XACT_ABORT ON;
        DECLARE @Now DATETIME2(0)=SYSUTCDATETIME(),@Role VARCHAR(50),@RoleId INT,@Branch INT,@CanReview BIT=0,
            @OwnerAccount BIGINT,@OwnerActive BIT,@ShipperId BIGINT,@TaskStatus VARCHAR(20),@TaskEnded DATETIME2(0),
            @OrderStatus VARCHAR(40),@WarehouseId INT,@OrderBranch INT,@CurrentPending BIT=0,
            @EventId BIGINT,@NewIssueId BIGINT=@IssueId,@CurrentRevision INT,@CurrentStatus VARCHAR(20),
            @Already BIT=0,@Result NVARCHAR(MAX);
        SELECT @Role=v.KyHieuVaiTro,@RoleId=t.MaVaiTro,@Branch=t.MaBuuCuc
        FROM dbo.TaiKhoan t JOIN dbo.VaiTro v ON v.MaVaiTro=t.MaVaiTro
        WHERE t.MaTaiKhoan=@AccountId AND t.TrangThaiTaiKhoan='ACTIVE' AND v.DangHoatDong=1
          AND (t.KhoaDenLuc IS NULL OR t.KhoaDenLuc<=@Now);
        IF @Role IS NULL THROW 55901,N'Tài khoản không còn hoạt động.',1;
        IF NOT EXISTS(SELECT 1 FROM dbo.VaiTroQuyen vq JOIN dbo.Quyen q ON q.MaQuyen=vq.MaQuyen
          WHERE vq.MaVaiTro=@RoleId AND ((@Role='SHIPPER' AND q.KyHieuQuyen=CASE WHEN @Mode='READ' THEN 'NHIEMVU_XEM' ELSE 'NHIEMVU_CAPNHAT' END)
            OR (@Role<>'SHIPPER' AND ((@Mode='READ' AND q.KyHieuQuyen IN('KHO_XEM','DONHANG_XEM','DIEUPHOI_GIAMSAT'))
               OR (@Mode<>'READ' AND q.KyHieuQuyen IN('KHO_XUAT','DIEUPHOI_PHANCONG'))))))
            THROW 55902,N'Bạn không có quyền thực hiện thao tác hồ sơ nhận kiện.',1;
        IF (@Mode IN('REPORT','SUPPLEMENT') AND @Role<>'SHIPPER') OR (@Mode IN('REQUEST_INFO','RESOLVE') AND @Role='SHIPPER')
            THROW 55902,N'Vai trò không được thực hiện thao tác này.',1;
        IF @Role<>'SHIPPER' AND EXISTS(SELECT 1 FROM dbo.VaiTroQuyen vq JOIN dbo.Quyen q ON q.MaQuyen=vq.MaQuyen
            WHERE vq.MaVaiTro=@RoleId AND q.KyHieuQuyen IN('KHO_XUAT','DIEUPHOI_PHANCONG')) SET @CanReview=1;
        """;
    // Lock order matches direct pickup: order, assignment, issue. Replays still
    // check live identity/rights, but may read the original receipt after closure.
    public const string TaskScope = """
        IF @AssignmentId IS NOT NULL
        BEGIN
            SELECT @OrderId=p.MaDonHang FROM dbo.PhanCongGiaoHang p WHERE p.MaPhanCongGiaoHang=@AssignmentId;
        END;
        IF @OrderId IS NULL THROW 55903,N'Không tìm thấy nhiệm vụ.',1;
        SELECT @WarehouseId=d.MaKhoHienTai,@OrderBranch=d.MaBuuCuc,@OrderStatus=s.KyHieuTrangThai
        FROM dbo.DonHang d WITH(UPDLOCK,HOLDLOCK) JOIN dbo.TrangThaiDonHang s ON s.MaTrangThaiDonHang=d.MaTrangThaiHienTai
        WHERE d.MaDonHang=@OrderId;
        IF @OrderBranch IS NULL OR (@Role<>'ADMIN' AND @OrderBranch<>ISNULL(@Branch,-1))
            THROW 55904,N'Đơn không còn trong bưu cục của bạn. Hãy tải lại.',1;
        IF @Role<>'ADMIN' AND NOT EXISTS(SELECT 1 FROM dbo.BuuCuc WHERE MaBuuCuc=@Branch AND DangHoatDong=1)
            THROW 55904,N'Bưu cục không còn hoạt động.',1;
        IF @AssignmentId IS NOT NULL
        BEGIN
            SELECT @ShipperId=p.MaNhanVienGiaoHang,@TaskStatus=p.TrangThaiPhanCong,@TaskEnded=p.ThoiGianKetThuc,
              @OwnerAccount=n.MaTaiKhoan,@OwnerActive=n.DangHoatDong
            FROM dbo.PhanCongGiaoHang p WITH(UPDLOCK,HOLDLOCK) JOIN dbo.NhanVienGiaoHang n ON n.MaNhanVienGiaoHang=p.MaNhanVienGiaoHang
            WHERE p.MaPhanCongGiaoHang=@AssignmentId AND p.MaDonHang=@OrderId;
            IF @OwnerAccount IS NULL OR (@Role='SHIPPER' AND (@OwnerAccount<>@AccountId OR @OwnerActive<>1))
                THROW 55903,N'Không tìm thấy nhiệm vụ của bạn.',1;
            IF @TaskEnded IS NULL AND @TaskStatus='ACCEPTED' AND @OrderStatus='ASSIGNED'
              AND EXISTS(SELECT 1 FROM dbo.Kho WHERE MaKho=@WarehouseId AND DangHoatDong=1 AND MaBuuCuc=@OrderBranch)
              AND EXISTS(SELECT 1 FROM dbo.TonKhoDonHang WHERE MaDonHang=@OrderId AND MaKho=@WarehouseId AND TrangThaiTonKho IN('STORED','ALLOCATED'))
                SET @CurrentPending=1;
        END
        ELSE IF @Role='SHIPPER' THROW 55902,N'Tài xế phải chọn nhiệm vụ của mình.',1;
        """;
    public const string Ack = """
        SET @Result=(SELECT i.IssueId issueId,i.AssignmentId assignmentId,i.OrderId orderId,i.ShipperId shipperId,
            i.Kind kind,e.EventId eventId,e.RequestId requestId,e.EventType eventType,e.Notes reason,
            e.ResultStatus status,e.Revision revision,e.RecordedAt recordedAt,
            CONVERT(BIT,CASE WHEN e.EvidencePath IS NULL THEN 0 ELSE 1 END) hasEvidence,@Already alreadyRecorded
          FROM dbo.ShipperPickupIssueEvent e JOIN dbo.ShipperPickupIssue i ON i.IssueId=e.IssueId
          WHERE e.EventId=@EventId FOR JSON PATH,INCLUDE_NULL_VALUES,WITHOUT_ARRAY_WRAPPER);
        """;
    public static string Replay => $$"""
        SELECT @EventId=e.EventId FROM dbo.ShipperPickupIssueEvent e WITH(UPDLOCK,HOLDLOCK)
        JOIN dbo.ShipperPickupIssue i ON i.IssueId=e.IssueId
        WHERE e.RequestId=@RequestId AND e.AuthorAccountId=@AccountId AND e.EventType=@Mode
          AND i.AssignmentId=@AssignmentId AND (@Role='ADMIN' OR i.BranchId=@Branch) AND (@Mode='REPORT' OR i.IssueId=@IssueId);
        IF @EventId IS NOT NULL BEGIN SET @Already=1; {{Ack}} END;
        IF @EventId IS NULL AND EXISTS(SELECT 1 FROM dbo.ShipperPickupIssueEvent WHERE RequestId=@RequestId)
            THROW 55904,N'Mã yêu cầu đã được dùng cho thao tác khác.',1;
        """;
    public const string GuardNew = """
        IF @Mode IN('REPORT','SUPPLEMENT') AND @CurrentPending<>1
            THROW 55904,N'Nhiệm vụ không còn chờ bạn nhận kiện. Hãy tải lại.',1;
        IF @Mode='REPORT' AND EXISTS(SELECT 1 FROM dbo.ShipperPickupIssue WITH(UPDLOCK,HOLDLOCK) WHERE OrderId=@OrderId AND ClosedAt IS NULL)
            THROW 55904,N'Đơn đang có hồ sơ nhận kiện chưa đóng. Hãy xem hồ sơ và phản hồi của kho.',1;
        IF @Mode<>'REPORT'
        BEGIN
            SELECT @CurrentRevision=Revision,@CurrentStatus=Status FROM dbo.ShipperPickupIssue WITH(UPDLOCK,HOLDLOCK)
            WHERE IssueId=@IssueId AND AssignmentId=@AssignmentId AND OrderId=@OrderId
              AND (@Role='ADMIN' OR BranchId=@Branch);
            IF @CurrentRevision IS NULL THROW 55903,N'Không tìm thấy hồ sơ sự cố.',1;
            IF @CurrentRevision<>@ExpectedRevision THROW 55905,N'Hồ sơ đã thay đổi. Hãy tải lại trước khi gửi.',1;
            IF @CurrentStatus='RESOLVED' THROW 55904,N'Hồ sơ đã được xử lý.',1;
            IF @Mode='SUPPLEMENT' AND @CurrentStatus<>'NEED_MORE'
                THROW 55904,N'Chỉ bổ sung khi kho/điều phối yêu cầu thêm thông tin.',1;
        END;
        """;
    public const string ResolveAssignment = """
        IF @Mode IN('REQUEST_INFO','RESOLVE')
            SELECT @AssignmentId=AssignmentId FROM dbo.ShipperPickupIssue WHERE IssueId=@IssueId AND OrderId=@OrderId;
        """;
    public static string Preflight => Actor + Schema + ResolveAssignment + TaskScope + Replay + "IF @Result IS NOT NULL SELECT @Result; ELSE BEGIN " + GuardNew + " SELECT 1; END;";
    public static string Write => Actor + Schema + ResolveAssignment + TaskScope + Replay + $$"""
        IF @Result IS NOT NULL BEGIN SELECT @Result AS Result; RETURN; END;
        {{GuardNew}}
        IF @Mode='REPORT'
        BEGIN
            INSERT dbo.ShipperPickupIssue(AssignmentId,OrderId,ShipperId,WarehouseId,BranchId,Kind,Status,Revision,ReportedAt)
            VALUES(@AssignmentId,@OrderId,@ShipperId,@WarehouseId,@OrderBranch,@Kind,'OPEN',1,@Now);
            SET @NewIssueId=SCOPE_IDENTITY();SET @CurrentRevision=1;SET @CurrentStatus='OPEN';
        END
        ELSE
        BEGIN
            SET @CurrentRevision=@CurrentRevision+1;
            SET @CurrentStatus=CASE @Mode WHEN 'REQUEST_INFO' THEN 'NEED_MORE' WHEN 'RESOLVE' THEN 'RESOLVED' ELSE 'OPEN' END;
            UPDATE dbo.ShipperPickupIssue SET Status=@CurrentStatus,Revision=@CurrentRevision,
              ClosedAt=CASE WHEN @CurrentStatus='RESOLVED' THEN @Now ELSE NULL END WHERE IssueId=@IssueId;
        END;
        INSERT dbo.ShipperPickupIssueEvent(IssueId,RequestId,EventType,AuthorAccountId,Notes,EvidencePath,ResultStatus,Revision,RecordedAt)
        VALUES(@NewIssueId,@RequestId,@Mode,@AccountId,@Reason,@EvidencePath,@CurrentStatus,@CurrentRevision,@Now);
        SET @EventId=SCOPE_IDENTITY();
        {{Ack}}
        INSERT dbo.NhatKyHoatDong(MaTaiKhoan,LoaiThaoTac,TenDoiTuong,MaDoiTuong,DuLieuMoiJson)
        VALUES(@AccountId,CASE @Mode WHEN 'REPORT' THEN 'SHIPPER_PICKUP_ISSUE' WHEN 'SUPPLEMENT' THEN 'PICKUP_ISSUE_SUPPLEMENT' ELSE 'PICKUP_ISSUE_RESPONSE' END,
          'DonHang',CONVERT(VARCHAR(100),@OrderId),@Result);
        SELECT @Result AS Result;
        """;
    public const string Rows = """
        SELECT i.IssueId id,i.AssignmentId assignmentId,i.OrderId orderId,i.ShipperId shipperId,i.WarehouseId warehouseId,
          k.TenKho warehouseName,t.HoTen shipperName,i.Kind kind,i.Status status,i.Revision revision,i.ReportedAt reportedAt,i.ClosedAt closedAt,
          CONVERT(BIT,CASE WHEN @Role='SHIPPER' AND @CurrentPending=1 AND i.AssignmentId=@AssignmentId AND i.Status='NEED_MORE' AND EXISTS(SELECT 1 FROM dbo.VaiTroQuyen vq JOIN dbo.Quyen q ON q.MaQuyen=vq.MaQuyen WHERE vq.MaVaiTro=@RoleId AND q.KyHieuQuyen='NHIEMVU_CAPNHAT') THEN 1 ELSE 0 END) canSupplement,
          CONVERT(BIT,CASE WHEN @CanReview=1 AND i.ClosedAt IS NULL THEN 1 ELSE 0 END) canReview,
          JSON_QUERY((SELECT e.EventId id,e.RequestId requestId,e.EventType eventType,e.AuthorAccountId authorAccountId,a.HoTen authorName,
            e.Notes notes,CONVERT(BIT,CASE WHEN e.EvidencePath IS NULL THEN 0 ELSE 1 END) hasEvidence,
            e.ResultStatus status,e.Revision revision,e.RecordedAt recordedAt
            FROM dbo.ShipperPickupIssueEvent e JOIN dbo.TaiKhoan a ON a.MaTaiKhoan=e.AuthorAccountId
            WHERE e.IssueId=i.IssueId ORDER BY e.Revision FOR JSON PATH,INCLUDE_NULL_VALUES)) events
        FROM dbo.ShipperPickupIssue i JOIN dbo.Kho k ON k.MaKho=i.WarehouseId
        JOIN dbo.NhanVienGiaoHang n ON n.MaNhanVienGiaoHang=i.ShipperId JOIN dbo.TaiKhoan t ON t.MaTaiKhoan=n.MaTaiKhoan
        WHERE i.OrderId=@OrderId AND (@AssignmentId IS NULL OR i.AssignmentId=@AssignmentId)
          AND (@Role='ADMIN' OR i.BranchId=@Branch)
        ORDER BY i.IssueId DESC FOR JSON PATH,INCLUDE_NULL_VALUES;
        """;
    public static string LoadBlocked => """
        DECLARE @PickupBlocked BIT=0;
        IF OBJECT_ID(N'dbo.ShipperPickupIssue',N'U') IS NOT NULL
            EXEC sp_executesql N'SELECT @blocked=CONVERT(BIT,CASE WHEN EXISTS(SELECT 1 FROM dbo.ShipperPickupIssue WHERE OrderId=@order AND ClosedAt IS NULL) THEN 1 ELSE 0 END);',
              N'@order BIGINT,@blocked BIT OUTPUT',@OrderId,@PickupBlocked OUTPUT;
        """;
    public static string AssertClear(string orderExpression = "@OrderId", int error = 51504) => $$"""
        IF OBJECT_ID(N'dbo.ShipperPickupIssue',N'U') IS NOT NULL
            EXEC sp_executesql N'IF EXISTS(SELECT 1 FROM dbo.ShipperPickupIssue WITH(UPDLOCK,HOLDLOCK) WHERE OrderId=@order AND ClosedAt IS NULL)
              THROW {{error}},N''Đơn đang có sự cố nhận kiện chưa được kho/điều phối xử lý.'',1;',N'@order BIGINT',{{orderExpression}};
        """;
}
