/* =====================================================================
   Customer Outstanding & Aging  -  Database objects
   Serves two pages:
     @Kind = 'CHICK'   : AreaDMData (sales)            + AreaTrData (payments)
     @Kind = 'POULTRY' : AreaDMPoultry + AreaDMPoultry_det (sales) + AreaTrPoultry (payments)

   How outstanding is worked out (FIFO):
     For each customer, all payments received are adjusted against that
     customer's supplies (DMs) oldest first. Whatever is left unpaid on a
     DM is the outstanding of that supply.
   Age date of a supply:
     CHICK   : HatchDate (falls back to DMDate when HatchDate is empty).
               A DM whose lines have different hatch dates becomes one
               supply per hatch date, each aged separately.
     POULTRY : DMDate (poultry products have no hatch date).
   Age = days from the age date to the "as on" date; supplies dated after
   the "as on" date are not counted yet.
   Aging buckets : 0-30, 31-60, 61-90, 91-180, 180+ days.

   Requires SQL Server 2012 or later. Safe to re-run.
   ===================================================================== */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/* ---------------------------------------------------------------------
   1. Indexes
   --------------------------------------------------------------------- */
/* includes HatchDate (chick aging is by hatch date); rebuilt if an older version exists */
IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_AreaDMData_Code' AND object_id = OBJECT_ID('dbo.AreaDMData'))
    CREATE NONCLUSTERED INDEX IX_AreaDMData_Code ON dbo.AreaDMData (Code, DMDate)
        INCLUDE ([session], AreaCode, Area, DMNo, CName, Chick_type, Rate, TotalChicks, Mortality, HatchDate, Hatchries, Remarks)
        WITH (DROP_EXISTING = ON);
ELSE
    CREATE NONCLUSTERED INDEX IX_AreaDMData_Code ON dbo.AreaDMData (Code, DMDate)
        INCLUDE ([session], AreaCode, Area, DMNo, CName, Chick_type, Rate, TotalChicks, Mortality, HatchDate, Hatchries, Remarks);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_AreaTrData_Code' AND object_id = OBJECT_ID('dbo.AreaTrData'))
    CREATE NONCLUSTERED INDEX IX_AreaTrData_Code ON dbo.AreaTrData (Code, TrDate)
        INCLUDE ([session], AreaCode, Area, TRNo, CName, TrAmount, isAuth, Pay_mode, Pay_type);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_AreaDMPoultry_Code' AND object_id = OBJECT_ID('dbo.AreaDMPoultry'))
    CREATE NONCLUSTERED INDEX IX_AreaDMPoultry_Code ON dbo.AreaDMPoultry (Code, DMDate)
        INCLUDE ([session], AreaCode, Area, DMNo, CName, Insurace, Tcs_Amt);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_AreaDMPoultry_det_DM' AND object_id = OBJECT_ID('dbo.AreaDMPoultry_det'))
    CREATE NONCLUSTERED INDEX IX_AreaDMPoultry_det_DM ON dbo.AreaDMPoultry_det (DMNo, [Session], AreaCode)
        INCLUDE (Product, QtyNos, QtyKg, Rate, Amount, HsnCode, TaxType, TaxPer, TaxValue);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_AreaTrPoultry_Code' AND object_id = OBJECT_ID('dbo.AreaTrPoultry'))
    CREATE NONCLUSTERED INDEX IX_AreaTrPoultry_Code ON dbo.AreaTrPoultry (Code, TrDate)
        INCLUDE ([session], AreaCode, Area, TRNo, CName, TrAmount, isAuth, Pay_mode, Pay_type);
GO

/* Drop in dependency order */
IF OBJECT_ID('dbo.usp_CustOS_Products', 'P')  IS NOT NULL DROP PROCEDURE dbo.usp_CustOS_Products;
IF OBJECT_ID('dbo.usp_CustOS_Customer', 'P')  IS NOT NULL DROP PROCEDURE dbo.usp_CustOS_Customer;
IF OBJECT_ID('dbo.usp_CustOS_Summary', 'P')   IS NOT NULL DROP PROCEDURE dbo.usp_CustOS_Summary;
IF OBJECT_ID('dbo.usp_CustOS_Filters', 'P')   IS NOT NULL DROP PROCEDURE dbo.usp_CustOS_Filters;
IF OBJECT_ID('dbo.fn_CustOS_Allocated', 'IF') IS NOT NULL DROP FUNCTION dbo.fn_CustOS_Allocated;
IF OBJECT_ID('dbo.fn_CustOS_Lines', 'IF')     IS NOT NULL DROP FUNCTION dbo.fn_CustOS_Lines;
IF OBJECT_ID('dbo.fn_CustOS_Payments', 'IF')  IS NOT NULL DROP FUNCTION dbo.fn_CustOS_Payments;
IF OBJECT_ID('dbo.fn_CustOS_Bills', 'IF')     IS NOT NULL DROP FUNCTION dbo.fn_CustOS_Bills;
GO

/* ---------------------------------------------------------------------
   2. Bills (one row per supply / DM)
      Customer key = Code; if Code is blank, '#' + customer name.
   --------------------------------------------------------------------- */
CREATE FUNCTION dbo.fn_CustOS_Bills
(
    @Kind varchar(10), @Session varchar(50), @AreaCode varchar(50), @AsOf date
)
RETURNS TABLE
AS
RETURN
    /* ---- Chicks : AreaDMData (one row per chick type line; grouped into a DM) ---- */
    SELECT  BillKey    = CAST('C|' + ISNULL(d.[session], '') + '|' + ISNULL(d.AreaCode, '') + '|' + ISNULL(d.DMNo, '') + '|' + ISNULL(CONVERT(char(8), ad.AgeDate, 112), '') AS varchar(200)),
            DMNo       = ISNULL(d.DMNo, ''),
            BillDate   = CAST(ad.AgeDate AS datetime),          -- hatch date (or DM date if no hatch date)
            DMDate     = MIN(d.DMDate),
            [Session]  = ISNULL(d.[session], ''),
            AreaCode   = ISNULL(d.AreaCode, ''),
            Area       = MAX(ISNULL(d.Area, '')),
            k.CustKey,
            Code       = MAX(ISNULL(d.Code, '')),
            CName      = CAST(MAX(ISNULL(d.CName, '')) AS varchar(180)),
            Taxable    = CAST(SUM((ISNULL(d.TotalChicks, 0) - ISNULL(d.Mortality, 0)) * ISNULL(d.Rate, 0)) AS decimal(18, 2)),
            Tax        = CAST(0 AS decimal(18, 2)),
            Insurance  = CAST(0 AS decimal(18, 2)),
            Tcs        = CAST(0 AS decimal(18, 2)),
            /* Bill value billed on net chicks (Total - Mortality), same as the sales dashboard */
            Amount     = CAST(SUM((ISNULL(d.TotalChicks, 0) - ISNULL(d.Mortality, 0)) * ISNULL(d.Rate, 0)) AS decimal(18, 2)),
            QtyNos     = CAST(SUM(ISNULL(d.TotalChicks, 0) - ISNULL(d.Mortality, 0)) AS decimal(18, 2)),
            QtyKg      = CAST(0 AS decimal(18, 2)),
            VehNo      = CAST('' AS varchar(50)),
            DriverName = CAST('' AS varchar(50)),
            Remarks    = CAST(MAX(ISNULL(d.Remarks, '')) AS varchar(150))
    FROM    dbo.AreaDMData d
    CROSS APPLY (SELECT CustKey = CAST(ISNULL(NULLIF(LTRIM(RTRIM(d.Code)), ''), '#' + ISNULL(d.CName, '')) AS varchar(200))) k
    CROSS APPLY (SELECT AgeDate = CAST(COALESCE(d.HatchDate, d.DMDate) AS date)) ad
    WHERE   @Kind = 'CHICK'
      AND  (@Session  IS NULL OR d.[session] = @Session)
      AND  (@AreaCode IS NULL OR d.AreaCode  = @AreaCode)
      AND  (ad.AgeDate IS NULL OR ad.AgeDate <= @AsOf)
    GROUP BY d.[session], d.AreaCode, d.DMNo, k.CustKey, ad.AgeDate

    UNION ALL

    /* ---- Poultry products : AreaDMPoultry header + AreaDMPoultry_det lines ---- */
    SELECT  BillKey    = CAST('P|' + CAST(h.id AS varchar(20)) AS varchar(200)),
            DMNo       = ISNULL(h.DMNo, ''),
            BillDate   = h.DMDate,
            DMDate     = h.DMDate,
            [Session]  = ISNULL(h.[session], ''),
            AreaCode   = ISNULL(h.AreaCode, ''),
            Area       = ISNULL(h.Area, ''),
            k.CustKey,
            Code       = ISNULL(h.Code, ''),
            CName      = CAST(ISNULL(h.CName, '') AS varchar(180)),
            Taxable    = CAST(ISNULL(l.Taxable, 0) AS decimal(18, 2)),
            Tax        = CAST(ISNULL(l.Tax, 0) AS decimal(18, 2)),
            Insurance  = CAST(ISNULL(h.Insurace, 0) AS decimal(18, 2)),
            Tcs        = CAST(ISNULL(h.Tcs_Amt, 0) AS decimal(18, 2)),
            /* Bill value = line amounts + line tax + insurance + TCS.
               If AreaDMPoultry_det.Amount already INCLUDES tax, remove "+ ISNULL(l.Tax, 0)". */
            Amount     = CAST(ISNULL(l.Taxable, 0) + ISNULL(l.Tax, 0) + ISNULL(h.Insurace, 0) + ISNULL(h.Tcs_Amt, 0) AS decimal(18, 2)),
            QtyNos     = CAST(ISNULL(l.QtyNos, 0) AS decimal(18, 2)),
            QtyKg      = CAST(ISNULL(l.QtyKg, 0) AS decimal(18, 2)),
            VehNo      = CAST(ISNULL(h.VehNo, '') AS varchar(50)),
            DriverName = CAST(ISNULL(h.DriverName, '') AS varchar(50)),
            Remarks    = CAST(ISNULL(h.Remarks, '') AS varchar(150))
    FROM    dbo.AreaDMPoultry h
    CROSS APPLY (SELECT CustKey = CAST(ISNULL(NULLIF(LTRIM(RTRIM(h.Code)), ''), '#' + ISNULL(h.CName, '')) AS varchar(200))) k
    OUTER APPLY (
            SELECT  Taxable = SUM(ISNULL(x.Amount, 0)),
                    Tax     = SUM(ISNULL(x.TaxValue, 0)),
                    QtyNos  = SUM(ISNULL(x.QtyNos, 0)),
                    QtyKg   = SUM(ISNULL(x.QtyKg, 0))
            FROM    dbo.AreaDMPoultry_det x
            WHERE   x.DMNo = h.DMNo AND x.[Session] = h.[session] AND x.AreaCode = h.AreaCode
         ) l
    WHERE   @Kind = 'POULTRY'
      AND  (@Session  IS NULL OR h.[session] = @Session)
      AND  (@AreaCode IS NULL OR h.AreaCode  = @AreaCode)
      AND  (h.DMDate IS NULL OR h.DMDate < DATEADD(DAY, 1, CAST(@AsOf AS datetime)));
GO

/* ---------------------------------------------------------------------
   3. Payments received
   --------------------------------------------------------------------- */
CREATE FUNCTION dbo.fn_CustOS_Payments
(
    @Kind varchar(10), @Session varchar(50), @AreaCode varchar(50), @AsOf date, @AuthOnly bit
)
RETURNS TABLE
AS
RETURN
    SELECT  PayKey   = CAST('C|' + CAST(t.id AS varchar(20)) AS varchar(30)),
            TRNo     = ISNULL(t.TRNo, ''), t.TrDate,
            [Session]= ISNULL(t.[session], ''), AreaCode = ISNULL(t.AreaCode, ''), Area = ISNULL(t.Area, ''),
            k.CustKey, Code = ISNULL(t.Code, ''), CName = CAST(ISNULL(t.CName, '') AS varchar(180)),
            PayMode  = ISNULL(NULLIF(LTRIM(RTRIM(t.Pay_mode)), ''), '-'),
            PayType  = ISNULL(NULLIF(LTRIM(RTRIM(t.Pay_type)), ''), '-'),
            DD_No    = ISNULL(t.DD_No, ''), Bank_det = ISNULL(t.Bank_det, ''), BankDate = t.bankdate,
            Amount   = CAST(ISNULL(t.TrAmount, 0) AS decimal(18, 2)),
            IsAuth   = CASE WHEN t.isAuth = 1 THEN 1 ELSE 0 END,
            Remarks  = CAST(ISNULL(t.Remarks, '') AS varchar(350))
    FROM    dbo.AreaTrData t
    CROSS APPLY (SELECT CustKey = CAST(ISNULL(NULLIF(LTRIM(RTRIM(t.Code)), ''), '#' + ISNULL(t.CName, '')) AS varchar(200))) k
    WHERE   @Kind = 'CHICK'
      AND  (@Session  IS NULL OR t.[session] = @Session)
      AND  (@AreaCode IS NULL OR t.AreaCode  = @AreaCode)
      AND  (t.TrDate IS NULL OR t.TrDate < DATEADD(DAY, 1, CAST(@AsOf AS datetime)))
      AND  (@AuthOnly = 0 OR t.isAuth = 1)

    UNION ALL

    SELECT  PayKey   = CAST('P|' + CAST(t.id AS varchar(20)) AS varchar(30)),
            TRNo     = ISNULL(t.TRNo, ''), t.TrDate,
            [Session]= ISNULL(t.[session], ''), AreaCode = ISNULL(t.AreaCode, ''), Area = ISNULL(t.Area, ''),
            k.CustKey, Code = ISNULL(t.Code, ''), CName = CAST(ISNULL(t.CName, '') AS varchar(180)),
            PayMode  = ISNULL(NULLIF(LTRIM(RTRIM(t.Pay_mode)), ''), '-'),
            PayType  = ISNULL(NULLIF(LTRIM(RTRIM(t.Pay_type)), ''), '-'),
            DD_No    = ISNULL(t.DD_No, ''), Bank_det = ISNULL(t.Bank_det, ''), BankDate = t.bankdate,
            Amount   = CAST(ISNULL(t.TrAmount, 0) AS decimal(18, 2)),
            IsAuth   = CASE WHEN t.isAuth = 1 THEN 1 ELSE 0 END,
            Remarks  = CAST(ISNULL(t.Remarks, '') AS varchar(350))
    FROM    dbo.AreaTrPoultry t
    CROSS APPLY (SELECT CustKey = CAST(ISNULL(NULLIF(LTRIM(RTRIM(t.Code)), ''), '#' + ISNULL(t.CName, '')) AS varchar(200))) k
    WHERE   @Kind = 'POULTRY'
      AND  (@Session  IS NULL OR t.[session] = @Session)
      AND  (@AreaCode IS NULL OR t.AreaCode  = @AreaCode)
      AND  (t.TrDate IS NULL OR t.TrDate < DATEADD(DAY, 1, CAST(@AsOf AS datetime)))
      AND  (@AuthOnly = 0 OR t.isAuth = 1);
GO

/* ---------------------------------------------------------------------
   4. Supply lines (particulars, quantity, rate, amount) - one customer, or all when @CustKey IS NULL
   --------------------------------------------------------------------- */
CREATE FUNCTION dbo.fn_CustOS_Lines
(
    @Kind varchar(10), @Session varchar(50), @AreaCode varchar(50), @AsOf date, @CustKey varchar(200)
)
RETURNS TABLE
AS
RETURN
    SELECT  BillKey     = CAST('C|' + ISNULL(d.[session], '') + '|' + ISNULL(d.AreaCode, '') + '|' + ISNULL(d.DMNo, '') + '|' + ISNULL(CONVERT(char(8), ad.AgeDate, 112), '') AS varchar(200)),
            LineId      = CAST(d.id AS bigint),
            Particulars = CAST(ISNULL(NULLIF(LTRIM(RTRIM(d.Chick_type)), ''), 'Chicks') AS varchar(200)),
            HsnCode     = CAST('' AS varchar(50)),
            QtyNos      = CAST(ISNULL(d.TotalChicks, 0) AS decimal(18, 2)),
            Mortality   = CAST(ISNULL(d.Mortality, 0) AS decimal(18, 2)),
            NetQty      = CAST(ISNULL(d.TotalChicks, 0) - ISNULL(d.Mortality, 0) AS decimal(18, 2)),
            QtyKg       = CAST(0 AS decimal(18, 2)),
            Rate        = CAST(ISNULL(d.Rate, 0) AS decimal(18, 2)),
            Amount      = CAST((ISNULL(d.TotalChicks, 0) - ISNULL(d.Mortality, 0)) * ISNULL(d.Rate, 0) AS decimal(18, 2)),
            TaxType     = CAST('' AS varchar(10)),
            TaxPer      = CAST(0 AS decimal(6, 2)),
            TaxValue    = CAST(0 AS decimal(18, 2)),
            HatchDate   = d.HatchDate,
            Hatchery    = CAST(ISNULL(d.Hatchries, '') AS varchar(50))
    FROM    dbo.AreaDMData d
    CROSS APPLY (SELECT AgeDate = CAST(COALESCE(d.HatchDate, d.DMDate) AS date)) ad
    WHERE   @Kind = 'CHICK'
      AND  (@CustKey IS NULL OR ISNULL(NULLIF(LTRIM(RTRIM(d.Code)), ''), '#' + ISNULL(d.CName, '')) = @CustKey)
      AND  (@Session  IS NULL OR d.[session] = @Session)
      AND  (@AreaCode IS NULL OR d.AreaCode  = @AreaCode)
      AND  (ad.AgeDate IS NULL OR ad.AgeDate <= @AsOf)

    UNION ALL

    SELECT  BillKey     = CAST('P|' + CAST(h.id AS varchar(20)) AS varchar(200)),
            LineId      = CAST(x.id AS bigint),
            Particulars = CAST(ISNULL(x.Product, '') AS varchar(200)),
            HsnCode     = CAST(ISNULL(x.HsnCode, '') AS varchar(50)),
            QtyNos      = CAST(ISNULL(x.QtyNos, 0) AS decimal(18, 2)),
            Mortality   = CAST(0 AS decimal(18, 2)),
            NetQty      = CAST(ISNULL(x.QtyNos, 0) AS decimal(18, 2)),
            QtyKg       = CAST(ISNULL(x.QtyKg, 0) AS decimal(18, 2)),
            Rate        = CAST(ISNULL(x.Rate, 0) AS decimal(18, 2)),
            Amount      = CAST(ISNULL(x.Amount, 0) AS decimal(18, 2)),
            TaxType     = CAST(ISNULL(x.TaxType, '') AS varchar(10)),
            TaxPer      = CAST(ISNULL(x.TaxPer, 0) AS decimal(6, 2)),
            TaxValue    = CAST(ISNULL(x.TaxValue, 0) AS decimal(18, 2)),
            HatchDate   = CAST(NULL AS datetime),
            Hatchery    = CAST('' AS varchar(50))
    FROM    dbo.AreaDMPoultry h
    JOIN    dbo.AreaDMPoultry_det x
            ON x.DMNo = h.DMNo AND x.[Session] = h.[session] AND x.AreaCode = h.AreaCode
    WHERE   @Kind = 'POULTRY'
      AND  (@CustKey IS NULL OR ISNULL(NULLIF(LTRIM(RTRIM(h.Code)), ''), '#' + ISNULL(h.CName, '')) = @CustKey)
      AND  (@Session  IS NULL OR h.[session] = @Session)
      AND  (@AreaCode IS NULL OR h.AreaCode  = @AreaCode)
      AND  (h.DMDate IS NULL OR h.DMDate < DATEADD(DAY, 1, CAST(@AsOf AS datetime)));
GO

/* ---------------------------------------------------------------------
   5. FIFO allocation : payments adjusted against oldest bills first
   --------------------------------------------------------------------- */
CREATE FUNCTION dbo.fn_CustOS_Allocated
(
    @Kind varchar(10), @Session varchar(50), @AreaCode varchar(50), @AsOf date, @AuthOnly bit
)
RETURNS TABLE
AS
RETURN
    WITH P AS (
        SELECT CustKey, Paid = SUM(Amount)
        FROM dbo.fn_CustOS_Payments(@Kind, @Session, @AreaCode, @AsOf, @AuthOnly)
        GROUP BY CustKey
    ),
    C AS (
        SELECT b.*,
               Cum = SUM(b.Amount) OVER (PARTITION BY b.CustKey ORDER BY b.BillDate, b.BillKey ROWS UNBOUNDED PRECEDING)
        FROM dbo.fn_CustOS_Bills(@Kind, @Session, @AreaCode, @AsOf) b
    )
    SELECT  C.BillKey, C.DMNo, C.BillDate, C.DMDate, C.[Session], C.AreaCode, C.Area, C.CustKey, C.Code, C.CName,
            C.Taxable, C.Tax, C.Insurance, C.Tcs, C.Amount, C.QtyNos, C.QtyKg, C.VehNo, C.DriverName, C.Remarks,
            a.Adjusted,
            Outstanding = C.Amount - a.Adjusted,
            d.Days,
            Bucket = CASE WHEN d.Days <= 30  THEN 0
                          WHEN d.Days <= 60  THEN 1
                          WHEN d.Days <= 90  THEN 2
                          WHEN d.Days <= 180 THEN 3
                          ELSE 4 END
    FROM C
    LEFT JOIN P ON P.CustKey = C.CustKey
    CROSS APPLY (SELECT Paid = ISNULL(P.Paid, 0)) pp
    CROSS APPLY (SELECT Adjusted = CAST(CASE WHEN pp.Paid >= C.Cum             THEN C.Amount
                                             WHEN pp.Paid <= C.Cum - C.Amount  THEN 0
                                             ELSE pp.Paid - (C.Cum - C.Amount) END AS decimal(18, 2))) a
    CROSS APPLY (SELECT Days = CASE WHEN C.BillDate IS NULL THEN 0
                                    ELSE DATEDIFF(DAY, C.BillDate, @AsOf) END) d;
GO

/* ---------------------------------------------------------------------
   6. Filter lists
   --------------------------------------------------------------------- */
CREATE PROCEDURE dbo.usp_CustOS_Filters
    @Kind varchar(10)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Today date = CAST(GETDATE() AS date);

    /* sessions, latest first */
    SELECT [Session] FROM (
        SELECT [Session], BillDate AS dt FROM dbo.fn_CustOS_Bills(@Kind, NULL, NULL, '9999-12-30')
        UNION ALL
        SELECT [Session], TrDate FROM dbo.fn_CustOS_Payments(@Kind, NULL, NULL, '9999-12-30', 0)
    ) s
    WHERE [Session] <> ''
    GROUP BY [Session]
    ORDER BY MAX(dt) DESC, [Session] DESC;

    /* areas */
    SELECT AreaCode, Area = MAX(Area) FROM (
        SELECT AreaCode, Area FROM dbo.fn_CustOS_Bills(@Kind, NULL, NULL, '9999-12-30')
        UNION ALL
        SELECT AreaCode, Area FROM dbo.fn_CustOS_Payments(@Kind, NULL, NULL, '9999-12-30', 0)
    ) a
    WHERE AreaCode <> ''
    GROUP BY AreaCode
    ORDER BY MAX(Area), AreaCode;

    SELECT Today = @Today;
END
GO

/* ---------------------------------------------------------------------
   7. Summary : KPIs, customer-wise aging, area-wise aging
   --------------------------------------------------------------------- */
CREATE PROCEDURE dbo.usp_CustOS_Summary
    @Kind     varchar(10),
    @Session  varchar(50) = NULL,
    @AreaCode varchar(50) = NULL,
    @AsOf     date        = NULL,
    @AuthOnly bit         = 0
AS
BEGIN
    SET NOCOUNT ON;
    SET @Session  = NULLIF(LTRIM(RTRIM(@Session)),  '');
    SET @AreaCode = NULLIF(LTRIM(RTRIM(@AreaCode)), '');
    SET @AsOf     = ISNULL(@AsOf, CAST(GETDATE() AS date));
    SET @AuthOnly = ISNULL(@AuthOnly, 0);

    SELECT * INTO #a   FROM dbo.fn_CustOS_Allocated(@Kind, @Session, @AreaCode, @AsOf, @AuthOnly);
    SELECT * INTO #pay FROM dbo.fn_CustOS_Payments(@Kind, @Session, @AreaCode, @AsOf, @AuthOnly);

    ;WITH R AS (SELECT *, rn = ROW_NUMBER() OVER (PARTITION BY CustKey ORDER BY TrDate DESC, PayKey DESC) FROM #pay)
    SELECT  CustKey,
            Code      = MAX(Code), CName = MAX(CName), Area = MAX(Area), AreaCode = MAX(AreaCode),
            Paid      = SUM(Amount),
            PayCount  = COUNT(*),
            LastPayDate = MAX(CASE WHEN rn = 1 THEN TrDate END),
            LastPayAmt  = MAX(CASE WHEN rn = 1 THEN Amount END)
    INTO    #p
    FROM    R
    GROUP BY CustKey;

    ;WITH B AS (
        SELECT  CustKey,
                Code = MAX(Code), CName = MAX(CName), Area = MAX(Area), AreaCode = MAX(AreaCode),
                Bills       = COUNT(*),
                Billed      = SUM(Amount),
                Outstanding = SUM(Outstanding),
                B0 = SUM(CASE WHEN Bucket = 0 THEN Outstanding ELSE 0 END),
                B1 = SUM(CASE WHEN Bucket = 1 THEN Outstanding ELSE 0 END),
                B2 = SUM(CASE WHEN Bucket = 2 THEN Outstanding ELSE 0 END),
                B3 = SUM(CASE WHEN Bucket = 3 THEN Outstanding ELSE 0 END),
                B4 = SUM(CASE WHEN Bucket = 4 THEN Outstanding ELSE 0 END),
                OpenBills   = SUM(CASE WHEN Outstanding > 0 THEN 1 ELSE 0 END),
                OldestDue   = MIN(CASE WHEN Outstanding > 0 THEN BillDate END),
                MaxDays     = MAX(CASE WHEN Outstanding > 0 THEN Days END),
                LastBillDate = MAX(BillDate),
                DueDays     = SUM(CASE WHEN Outstanding > 0 THEN Outstanding * Days ELSE 0 END)
        FROM #a
        GROUP BY CustKey
    )
    SELECT  CustKey     = COALESCE(B.CustKey, P.CustKey),
            Code        = COALESCE(NULLIF(B.Code, ''), P.Code, ''),
            CName       = COALESCE(NULLIF(B.CName, ''), P.CName, ''),
            Area        = COALESCE(NULLIF(B.Area, ''), P.Area, ''),
            AreaCode    = COALESCE(NULLIF(B.AreaCode, ''), P.AreaCode, ''),
            Bills       = ISNULL(B.Bills, 0),
            Billed      = ISNULL(B.Billed, 0),
            Received    = ISNULL(P.Paid, 0),
            Outstanding = ISNULL(B.Outstanding, 0),
            Advance     = CASE WHEN ISNULL(P.Paid, 0) > ISNULL(B.Billed, 0) THEN P.Paid - ISNULL(B.Billed, 0) ELSE 0 END,
            NetBalance  = ISNULL(B.Billed, 0) - ISNULL(P.Paid, 0),
            B0 = ISNULL(B.B0, 0), B1 = ISNULL(B.B1, 0), B2 = ISNULL(B.B2, 0), B3 = ISNULL(B.B3, 0), B4 = ISNULL(B.B4, 0),
            OpenBills   = ISNULL(B.OpenBills, 0),
            OldestDue   = B.OldestDue,
            MaxDays     = ISNULL(B.MaxDays, 0),
            AvgDays     = CASE WHEN ISNULL(B.Outstanding, 0) > 0 THEN B.DueDays / B.Outstanding ELSE 0 END,
            DueDays     = ISNULL(B.DueDays, 0),
            LastBillDate = B.LastBillDate,
            LastPayDate = P.LastPayDate,
            LastPayAmt  = ISNULL(P.LastPayAmt, 0)
    INTO    #c
    FROM    B FULL OUTER JOIN #p P ON P.CustKey = B.CustKey;

    /* ===== Result 1 : KPIs ===== */
    SELECT  Billed       = ISNULL(SUM(Billed), 0),
            Received     = ISNULL(SUM(Received), 0),
            Outstanding  = ISNULL(SUM(Outstanding), 0),
            Advance      = ISNULL(SUM(Advance), 0),
            NetReceivable = ISNULL(SUM(Outstanding), 0) - ISNULL(SUM(Advance), 0),
            B0 = ISNULL(SUM(B0), 0), B1 = ISNULL(SUM(B1), 0), B2 = ISNULL(SUM(B2), 0),
            B3 = ISNULL(SUM(B3), 0), B4 = ISNULL(SUM(B4), 0),
            C0 = SUM(CASE WHEN B0 > 0 THEN 1 ELSE 0 END), C1 = SUM(CASE WHEN B1 > 0 THEN 1 ELSE 0 END),
            C2 = SUM(CASE WHEN B2 > 0 THEN 1 ELSE 0 END), C3 = SUM(CASE WHEN B3 > 0 THEN 1 ELSE 0 END),
            C4 = SUM(CASE WHEN B4 > 0 THEN 1 ELSE 0 END),
            Customers        = COUNT(*),
            CustomersWithDue = SUM(CASE WHEN Outstanding > 0 THEN 1 ELSE 0 END),
            CustomersWithAdv = SUM(CASE WHEN Advance > 0 THEN 1 ELSE 0 END),
            OpenBills    = ISNULL(SUM(OpenBills), 0),
            AvgDays      = CASE WHEN SUM(Outstanding) > 0 THEN SUM(DueDays) / SUM(Outstanding) ELSE 0 END,
            CollectionPct = CASE WHEN SUM(Billed) > 0 THEN SUM(Received) * 100.0 / SUM(Billed) ELSE 0 END,
            AsOf         = @AsOf,
            ServerTime   = GETDATE()
    FROM #c;

    /* ===== Result 2 : customers ===== */
    SELECT CustKey, Code, CName, Area, AreaCode, Bills, Billed, Received, Outstanding, Advance, NetBalance,
           B0, B1, B2, B3, B4, OpenBills, OldestDue, MaxDays, AvgDays, LastBillDate, LastPayDate, LastPayAmt
    FROM #c
    ORDER BY Outstanding DESC, Advance DESC, CName;

    /* ===== Result 3 : area-wise aging ===== */
    SELECT  AreaCode = ISNULL(NULLIF(AreaCode, ''), '-'),
            Area     = MAX(Area),
            Customers   = COUNT(*),
            WithDue     = SUM(CASE WHEN Outstanding > 0 THEN 1 ELSE 0 END),
            Billed      = SUM(Billed),
            Received    = SUM(Received),
            Outstanding = SUM(Outstanding),
            Advance     = SUM(Advance),
            B0 = SUM(B0), B1 = SUM(B1), B2 = SUM(B2), B3 = SUM(B3), B4 = SUM(B4)
    FROM #c
    GROUP BY ISNULL(NULLIF(AreaCode, ''), '-')
    ORDER BY SUM(Outstanding) DESC;
END
GO

/* ---------------------------------------------------------------------
   8. One customer : supplies with outstanding, their lines, payments
   --------------------------------------------------------------------- */
CREATE PROCEDURE dbo.usp_CustOS_Customer
    @Kind     varchar(10),
    @CustKey  varchar(200),
    @Session  varchar(50) = NULL,
    @AreaCode varchar(50) = NULL,
    @AsOf     date        = NULL,
    @AuthOnly bit         = 0
AS
BEGIN
    SET NOCOUNT ON;
    SET @Session  = NULLIF(LTRIM(RTRIM(@Session)),  '');
    SET @AreaCode = NULLIF(LTRIM(RTRIM(@AreaCode)), '');
    SET @AsOf     = ISNULL(@AsOf, CAST(GETDATE() AS date));
    SET @AuthOnly = ISNULL(@AuthOnly, 0);

    /* ===== Result 1 : supplies (bills) with FIFO adjustment ===== */
    SELECT  BillKey, DMNo, BillDate, DMDate, [Session], AreaCode, Area, Code, CName,
            Taxable, Tax, Insurance, Tcs, Amount, QtyNos, QtyKg, VehNo, DriverName, Remarks,
            Adjusted, Outstanding, Days, Bucket
    FROM    dbo.fn_CustOS_Allocated(@Kind, @Session, @AreaCode, @AsOf, @AuthOnly)
    WHERE   CustKey = @CustKey
    ORDER BY BillDate DESC, BillKey DESC
    OPTION (RECOMPILE);

    /* ===== Result 2 : supply lines ===== */
    SELECT  BillKey, LineId, Particulars, HsnCode, QtyNos, Mortality, NetQty, QtyKg, Rate, Amount,
            TaxType, TaxPer, TaxValue, HatchDate, Hatchery
    FROM    dbo.fn_CustOS_Lines(@Kind, @Session, @AreaCode, @AsOf, @CustKey)
    ORDER BY BillKey, LineId
    OPTION (RECOMPILE);

    /* ===== Result 3 : payments ===== */
    SELECT  PayKey, TRNo, TrDate, [Session], AreaCode, Area, PayMode, PayType, DD_No, Bank_det, BankDate,
            Amount, IsAuth, Remarks
    FROM    dbo.fn_CustOS_Payments(@Kind, @Session, @AreaCode, @AsOf, @AuthOnly)
    WHERE   CustKey = @CustKey
    ORDER BY TrDate DESC, PayKey DESC
    OPTION (RECOMPILE);
END
GO

/* ---------------------------------------------------------------------
   9. Product-wise : sales, quantity and outstanding per product
      A supply's outstanding is shared among its products in proportion
      to each line's value (line amount + line tax) on that supply.
      Insurance / TCS on the bill is shown as its own "product" row, so the
      product rows always add up to the total outstanding.
   --------------------------------------------------------------------- */
CREATE PROCEDURE dbo.usp_CustOS_Products
    @Kind     varchar(10),
    @Session  varchar(50) = NULL,
    @AreaCode varchar(50) = NULL,
    @AsOf     date        = NULL,
    @AuthOnly bit         = 0
AS
BEGIN
    SET NOCOUNT ON;
    SET @Session  = NULLIF(LTRIM(RTRIM(@Session)),  '');
    SET @AreaCode = NULLIF(LTRIM(RTRIM(@AreaCode)), '');
    SET @AsOf     = ISNULL(@AsOf, CAST(GETDATE() AS date));
    SET @AuthOnly = ISNULL(@AuthOnly, 0);

    SELECT * INTO #a FROM dbo.fn_CustOS_Allocated(@Kind, @Session, @AreaCode, @AsOf, @AuthOnly);
    SELECT * INTO #l FROM dbo.fn_CustOS_Lines(@Kind, @Session, @AreaCode, @AsOf, NULL);

    ;WITH L0 AS (
        SELECT  BillKey,
                Product   = ISNULL(NULLIF(LTRIM(RTRIM(Particulars)), ''), '(blank)'),
                NetQty, QtyKg, Amount,
                LineTotal = Amount + TaxValue     -- if det.Amount already includes tax, use just Amount here too
        FROM #l
    ),
    BT AS (SELECT BillKey, LinesTotal = SUM(LineTotal) FROM L0 GROUP BY BillKey),
    L AS (
        SELECT BillKey, Product, NetQty, QtyKg, Amount, LineTotal FROM L0
        UNION ALL
        /* insurance, TCS and anything else on the bill that is not a product line */
        SELECT  a.BillKey, 'Insurance, TCS & other charges', 0, 0, 0, a.Amount - ISNULL(BT.LinesTotal, 0)
        FROM    #a a LEFT JOIN BT ON BT.BillKey = a.BillKey
        WHERE   a.Amount - ISNULL(BT.LinesTotal, 0) <> 0
    )
    SELECT  L.Product, a.CustKey, a.Code, a.CName, a.Area, a.BillKey, a.Bucket, a.Days, a.BillDate,
            L.NetQty, L.QtyKg, L.Amount, L.LineTotal,
            OsShare = CAST(CASE WHEN a.Amount <> 0 THEN a.Outstanding * L.LineTotal / a.Amount ELSE 0 END AS decimal(18, 2))
    INTO    #x
    FROM    L
    JOIN    BT ON BT.BillKey = L.BillKey
    JOIN    #a a ON a.BillKey = L.BillKey;

    /* ===== Result 1 : product-wise ===== */
    SELECT  Product,
            Customers   = COUNT(DISTINCT CustKey),
            WithDue     = COUNT(DISTINCT CASE WHEN OsShare > 0 THEN CustKey END),
            Bills       = COUNT(DISTINCT BillKey),
            Qty         = SUM(NetQty),
            QtyKg       = SUM(QtyKg),
            Sales       = SUM(LineTotal),
            AvgRate     = CASE WHEN SUM(CASE WHEN QtyKg > 0 THEN QtyKg ELSE NetQty END) > 0
                               THEN SUM(Amount) / SUM(CASE WHEN QtyKg > 0 THEN QtyKg ELSE NetQty END) ELSE 0 END,
            Outstanding = SUM(OsShare),
            B0 = SUM(CASE WHEN Bucket = 0 THEN OsShare ELSE 0 END),
            B1 = SUM(CASE WHEN Bucket = 1 THEN OsShare ELSE 0 END),
            B2 = SUM(CASE WHEN Bucket = 2 THEN OsShare ELSE 0 END),
            B3 = SUM(CASE WHEN Bucket = 3 THEN OsShare ELSE 0 END),
            B4 = SUM(CASE WHEN Bucket = 4 THEN OsShare ELSE 0 END),
            LastSaleDate = MAX(BillDate)
    FROM #x
    GROUP BY Product
    ORDER BY SUM(OsShare) DESC, SUM(LineTotal) DESC;

    /* ===== Result 2 : product x customer (only where something is due) ===== */
    SELECT  Product, CustKey,
            Code = MAX(Code), CName = MAX(CName), Area = MAX(Area),
            Qty  = SUM(NetQty), QtyKg = SUM(QtyKg),
            Sales = SUM(LineTotal),
            Outstanding = SUM(OsShare),
            B0 = SUM(CASE WHEN Bucket = 0 THEN OsShare ELSE 0 END),
            B1 = SUM(CASE WHEN Bucket = 1 THEN OsShare ELSE 0 END),
            B2 = SUM(CASE WHEN Bucket = 2 THEN OsShare ELSE 0 END),
            B3 = SUM(CASE WHEN Bucket = 3 THEN OsShare ELSE 0 END),
            B4 = SUM(CASE WHEN Bucket = 4 THEN OsShare ELSE 0 END),
            MaxDays   = MAX(CASE WHEN OsShare > 0 THEN Days END),
            OldestDue = MIN(CASE WHEN OsShare > 0 THEN BillDate END)
    FROM #x
    GROUP BY Product, CustKey
    HAVING SUM(OsShare) > 0
    ORDER BY Product, SUM(OsShare) DESC;
END
GO
