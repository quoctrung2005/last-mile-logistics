namespace LastMile.Api.Controllers;

// Optional tables on the existing dashboard endpoint. The original response is unchanged
// when report is omitted. Monetary aggregates stay DECIMAL in SQL Server.
internal static class ReportsQuery
{
    internal const string Sql = """
        IF @Report IS NOT NULL
        BEGIN
            DECLARE @Items NVARCHAR(MAX), @Summary NVARCHAR(MAX), @Total BIGINT;

            IF @Report = 'orders'
            BEGIN
                SELECT b.MaBuuCuc AS branchId, b.TenBuuCuc AS branchName,
                    COUNT_BIG(*) AS createdCount,
                    COUNT_BIG(CASE WHEN o.Status IN ('DELIVERED','COMPLETED') THEN 1 END) AS successfulCount,
                    COUNT_BIG(CASE WHEN o.Status = 'FAILED' THEN 1 END) AS failedCount,
                    COUNT_BIG(CASE WHEN o.Status IN ('CANCELLED','RETURNING','RETURNED') THEN 1 END) AS cancelledReturnedCount
                INTO #OrderBranchReport
                FROM #PeriodOrders o JOIN dbo.BuuCuc b ON b.MaBuuCuc = o.BranchId
                GROUP BY b.MaBuuCuc, b.TenBuuCuc;

                SELECT @Total = COUNT_BIG(*) FROM #OrderBranchReport;
                SELECT @Items = (SELECT * FROM #OrderBranchReport ORDER BY branchId
                    OFFSET CASE WHEN @Export = 1 THEN 0 ELSE @Offset END ROWS
                    FETCH NEXT CASE WHEN @Export = 1 THEN 2147483647 ELSE @PageSize END ROWS ONLY FOR JSON PATH);
                SELECT @Summary = (SELECT COALESCE(SUM(createdCount),0) AS createdCount,
                    COALESCE(SUM(successfulCount),0) AS successfulCount,
                    COALESCE(SUM(failedCount),0) AS failedCount,
                    COALESCE(SUM(cancelledReturnedCount),0) AS cancelledReturnedCount
                    FROM #OrderBranchReport FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
            END;

            IF @Report = 'delivery'
            BEGIN
                -- Count assignments and attempts independently; an assignment may have multiple attempts.
                SELECT pc.MaNhanVienGiaoHang AS shipperId, o.BranchId AS branchId,
                    COUNT_BIG(*) AS assignmentCount
                INTO #Assigned
                FROM dbo.PhanCongGiaoHang pc JOIN #ScopedOrders o ON o.OrderId = pc.MaDonHang
                WHERE pc.ThoiGianPhanCong >= @FromUtc AND pc.ThoiGianPhanCong < @ToUtcExclusive
                GROUP BY pc.MaNhanVienGiaoHang, o.BranchId;

                SELECT ShipperId AS shipperId, BranchId AS branchId, COUNT_BIG(*) AS attemptCount,
                    COUNT_BIG(CASE WHEN Result = 'SUCCESS' THEN 1 END) AS successfulCount,
                    COUNT_BIG(CASE WHEN Result = 'FAILED' THEN 1 END) AS failedCount
                INTO #Attempted FROM #PeriodAttempts GROUP BY ShipperId, BranchId;

                SELECT COALESCE(a.shipperId,t.shipperId) AS shipperId,
                    COALESCE(a.branchId,t.branchId) AS branchId, b.TenBuuCuc AS branchName,
                    tk.HoTen AS shipperName, COALESCE(a.assignmentCount,0) AS assignmentCount,
                    COALESCE(t.attemptCount,0) AS attemptCount,
                    COALESCE(t.successfulCount,0) AS successfulCount,
                    COALESCE(t.failedCount,0) AS failedCount,
                    CONVERT(DECIMAL(5,2),100.0*t.successfulCount/NULLIF(t.attemptCount,0)) AS successRatePercent
                INTO #DeliveryReport
                FROM #Assigned a FULL JOIN #Attempted t ON t.shipperId=a.shipperId AND t.branchId=a.branchId
                JOIN dbo.NhanVienGiaoHang nv ON nv.MaNhanVienGiaoHang=COALESCE(a.shipperId,t.shipperId)
                JOIN dbo.TaiKhoan tk ON tk.MaTaiKhoan=nv.MaTaiKhoan
                JOIN dbo.BuuCuc b ON b.MaBuuCuc=COALESCE(a.branchId,t.branchId);

                SELECT @Total=COUNT_BIG(*) FROM #DeliveryReport;
                SELECT @Items=(SELECT * FROM #DeliveryReport ORDER BY branchId,shipperId
                    OFFSET CASE WHEN @Export=1 THEN 0 ELSE @Offset END ROWS
                    FETCH NEXT CASE WHEN @Export=1 THEN 2147483647 ELSE @PageSize END ROWS ONLY
                    FOR JSON PATH, INCLUDE_NULL_VALUES);
                SELECT @Summary=(SELECT COALESCE(SUM(assignmentCount),0) AS assignmentCount,
                    COALESCE(SUM(attemptCount),0) AS attemptCount,
                    COALESCE(SUM(successfulCount),0) AS successfulCount,
                    COALESCE(SUM(failedCount),0) AS failedCount,
                    CONVERT(DECIMAL(5,2),100.0*SUM(successfulCount)/NULLIF(SUM(attemptCount),0)) AS successRatePercent
                    FROM #DeliveryReport FOR JSON PATH, INCLUDE_NULL_VALUES, WITHOUT_ARRAY_WRAPPER);
            END;

            IF @Report = 'finance'
            BEGIN
                -- One ledger row per order, using that order's allocated deposits only.
                -- Confirmation time, not submission time, determines the confirmed cash movement.
                SELECT o.OrderId, o.BranchId,
                    CASE WHEN o.CreatedAt>=@FromUtc AND o.CreatedAt<@ToUtcExclusive THEN o.ShippingFee ELSE 0 END AS shippingFees,
                    CASE WHEN c.ThoiGianThuTien<@FromUtc THEN c.SoTienThucThu ELSE 0 END-p.openingDeposit AS openingBalance,
                    CASE WHEN c.ThoiGianThuTien>=@FromUtc AND c.ThoiGianThuTien<@ToUtcExclusive THEN c.SoTienThucThu ELSE 0 END AS collectedAmount,
                    p.periodDeposit AS confirmedDepositAmount,
                    CASE WHEN c.ThoiGianThuTien<@ToUtcExclusive THEN c.SoTienThucThu ELSE 0 END-p.closingDeposit AS closingBalance,
                    p.pendingDeposit AS pendingDepositAmount
                INTO #MoneyByOrder
                FROM #ScopedOrders o
                LEFT JOIN dbo.ThuTienCOD c ON c.MaDonHang=o.OrderId AND c.TrangThaiThuTien IN ('COLLECTED','PARTIAL')
                OUTER APPLY (
                    -- Narrow SUM's DECIMAL(38,2) before subtraction so SQL does not
                    -- reduce the result's scale when adding the carry digit.
                    SELECT CONVERT(DECIMAL(28,2),COALESCE(SUM(CASE WHEN n.TrangThaiNop='CONFIRMED' AND n.ThoiGianXacNhan<@FromUtc THEN ct.SoTienPhanBo ELSE 0 END),0)) AS openingDeposit,
                        CONVERT(DECIMAL(28,2),COALESCE(SUM(CASE WHEN n.TrangThaiNop='CONFIRMED' AND n.ThoiGianXacNhan>=@FromUtc AND n.ThoiGianXacNhan<@ToUtcExclusive THEN ct.SoTienPhanBo ELSE 0 END),0)) AS periodDeposit,
                        CONVERT(DECIMAL(28,2),COALESCE(SUM(CASE WHEN n.TrangThaiNop='CONFIRMED' AND n.ThoiGianXacNhan<@ToUtcExclusive THEN ct.SoTienPhanBo ELSE 0 END),0)) AS closingDeposit,
                        CONVERT(DECIMAL(28,2),COALESCE(SUM(CASE WHEN n.TrangThaiNop='PENDING' AND n.ThoiGianNop<@ToUtcExclusive THEN ct.SoTienPhanBo ELSE 0 END),0)) AS pendingDeposit
                    FROM dbo.ChiTietNopTienCOD ct JOIN dbo.NopTienCOD n ON n.MaNopTienCOD=ct.MaNopTienCOD
                    WHERE ct.MaDonHang=o.OrderId
                ) p;

                SELECT m.BranchId AS branchId, b.TenBuuCuc AS branchName,
                    SUM(shippingFees) AS shippingFees, SUM(openingBalance) AS openingBalance,
                    SUM(collectedAmount) AS collectedAmount, SUM(confirmedDepositAmount) AS confirmedDepositAmount,
                    SUM(closingBalance) AS closingBalance, SUM(pendingDepositAmount) AS pendingDepositAmount,
                    SUM(CASE WHEN closingBalance>0 THEN closingBalance ELSE 0 END) AS outstandingAmount,
                    SUM(CASE WHEN closingBalance-pendingDepositAmount>0 THEN closingBalance-pendingDepositAmount ELSE 0 END) AS availableToDepositAmount
                INTO #FinanceReport
                FROM #MoneyByOrder m JOIN dbo.BuuCuc b ON b.MaBuuCuc=m.BranchId
                GROUP BY m.BranchId,b.TenBuuCuc
                HAVING SUM(ABS(shippingFees)+ABS(openingBalance)+ABS(collectedAmount)+ABS(confirmedDepositAmount)+ABS(closingBalance)+ABS(pendingDepositAmount))>0;

                SELECT @Total=COUNT_BIG(*) FROM #FinanceReport;
                SELECT @Items=(SELECT * FROM #FinanceReport ORDER BY branchId
                    OFFSET CASE WHEN @Export=1 THEN 0 ELSE @Offset END ROWS
                    FETCH NEXT CASE WHEN @Export=1 THEN 2147483647 ELSE @PageSize END ROWS ONLY FOR JSON PATH);
                SELECT @Summary=(SELECT COALESCE(SUM(shippingFees),0) AS shippingFees,
                    COALESCE(SUM(openingBalance),0) AS openingBalance,
                    COALESCE(SUM(collectedAmount),0) AS collectedAmount,
                    COALESCE(SUM(confirmedDepositAmount),0) AS confirmedDepositAmount,
                    COALESCE(SUM(closingBalance),0) AS closingBalance,
                    COALESCE(SUM(pendingDepositAmount),0) AS pendingDepositAmount,
                    COALESCE(SUM(outstandingAmount),0) AS outstandingAmount,
                    COALESCE(SUM(availableToDepositAmount),0) AS availableToDepositAmount
                    FROM #FinanceReport FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
            END;

            SELECT (SELECT @FromDate AS [from], @ToDate AS [to], 'Asia/Ho_Chi_Minh' AS timeZone,
                @ScopeBranchId AS branchId, SYSUTCDATETIME() AS generatedAtUtc, @Report AS report,
                @Page AS page, @PageSize AS pageSize, @Total AS totalItems,
                JSON_QUERY(COALESCE(@Items,N'[]')) AS items, JSON_QUERY(@Summary) AS summary,
                JSON_QUERY((SELECT MaBuuCuc AS id, TenBuuCuc AS name FROM dbo.BuuCuc
                    WHERE @ActorRole='ADMIN' OR MaBuuCuc=@ActorBranchId ORDER BY MaBuuCuc FOR JSON PATH)) AS branches,
                JSON_QUERY(COALESCE((SELECT Status AS status,StatusName AS statusName,COUNT_BIG(*) AS orderCount
                    FROM #PeriodOrders WHERE @Report='orders' GROUP BY Status,StatusName ORDER BY Status FOR JSON PATH),N'[]')) AS ordersByStatus,
                JSON_QUERY(COALESCE((SELECT CONVERT(VARCHAR(10),day.ReportDate,23) AS [date],COUNT_BIG(o.OrderId) AS createdOrderCount
                    FROM @Days day LEFT JOIN #PeriodOrders o ON CONVERT(DATE,DATEADD(HOUR,7,o.CreatedAt))=day.ReportDate
                    WHERE @Report='orders' GROUP BY day.ReportDate ORDER BY day.ReportDate FOR JSON PATH),N'[]')) AS dailyOrders
                FOR JSON PATH, INCLUDE_NULL_VALUES, WITHOUT_ARRAY_WRAPPER);
            RETURN;
        END;
        """;
}
