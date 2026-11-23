/* =====================================================================
   Poultry Products Sales Dashboard  -  Database objects
   Tables : dbo.AreaDMPoultry      (DM header  = sale)
            dbo.AreaDMPoultry_det  (DM lines   = products sold)
            dbo.AreaTrPoultry      (payment receipts)
   Lines are linked to the header by DMNo + Session + AreaCode.
   Requires SQL Server 2012 or later. Safe to re-run.
   Run 03_Customer_Outstanding.sql first (it creates the indexes used here).
   ===================================================================== */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_AreaDMPoultry_Session' AND object_id = OBJECT_ID('dbo.AreaDMPoultry'))
    CREATE NONCLUSTERED INDEX IX_AreaDMPoultry_Session ON dbo.AreaDMPoultry ([session], DMDate)
        INCLUDE (AreaCode, Area, DMNo, Code, CName, Insurace, Tcs_Amt, VehNo, DriverName);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_AreaTrPoultry_Session' AND object_id = OBJECT_ID('dbo.AreaTrPoultry'))
    CREATE NONCLUSTERED INDEX IX_AreaTrPoultry_Session ON dbo.AreaTrPoultry ([session], TrDate)
        INCLUDE (AreaCode, Area, TRNo, Code, CName, Pay_mode, Pay_type, DD_No, Bank_det, TrAmount, isAuth, AuthBy);
GO

IF OBJECT_ID('dbo.usp_PoultryDash_Filters', 'P') IS NOT NULL DROP PROCEDURE dbo.usp_PoultryDash_Filters;
IF OBJECT_ID('dbo.usp_PoultryDash_Data', 'P')    IS NOT NULL DROP PROCEDURE dbo.usp_PoultryDash_Data;
GO

/* ---------------------------------------------------------------------
   1. Filters : sessions (latest first), areas and products of a session
   --------------------------------------------------------------------- */
CREATE PROCEDURE dbo.usp_PoultryDash_Filters
    @Session varchar(50) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT s.[session] AS [Session], MAX(s.dt) AS LastDate
    INTO   #s
    FROM ( SELECT [session], DMDate AS dt FROM dbo.AreaDMPoultry WHERE ISNULL([session], '') <> ''
           UNION ALL
           SELECT [session], TrDate FROM dbo.AreaTrPoultry WHERE ISNULL([session], '') <> '' ) s
    GROUP BY s.[session];

    SELECT [Session] FROM #s ORDER BY LastDate DESC, [Session] DESC;

    IF NULLIF(LTRIM(RTRIM(@Session)), '') IS NULL
        SELECT TOP (1) @Session = [Session] FROM #s ORDER BY LastDate DESC, [Session] DESC;

    SELECT a.AreaCode, MAX(ISNULL(a.Area, '')) AS Area
    FROM ( SELECT AreaCode, Area FROM dbo.AreaDMPoultry WHERE [session] = @Session
           UNION ALL
           SELECT AreaCode, Area FROM dbo.AreaTrPoultry WHERE [session] = @Session ) a
    WHERE ISNULL(a.AreaCode, '') <> ''
    GROUP BY a.AreaCode
    ORDER BY MAX(ISNULL(a.Area, '')), a.AreaCode;

    SELECT Product = ISNULL(NULLIF(LTRIM(RTRIM(d.Product)), ''), '(blank)'), Sales = SUM(ISNULL(d.Amount, 0) + ISNULL(d.TaxValue, 0))
    FROM   dbo.AreaDMPoultry_det d
    WHERE  d.[Session] = @Session
    GROUP BY ISNULL(NULLIF(LTRIM(RTRIM(d.Product)), ''), '(blank)')
    ORDER BY ISNULL(NULLIF(LTRIM(RTRIM(d.Product)), ''), '(blank)');

    SELECT @Session AS CurrentSession;
END
GO

/* ---------------------------------------------------------------------
   2. Dashboard data - 11 result sets in one round trip
      @Product : one product name, or NULL for all products.
      With a product selected, sales figures are that product's lines only
      (insurance / TCS are bill-level, so they are left out), while payment
      figures stay for all products (receipts are not recorded per product).
   --------------------------------------------------------------------- */
CREATE PROCEDURE dbo.usp_PoultryDash_Data
    @Session  varchar(50),
    @AreaCode varchar(50)  = NULL,
    @Product  varchar(200) = NULL,
    @FromDate date         = NULL,
    @ToDate   date         = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET @AreaCode = NULLIF(LTRIM(RTRIM(@AreaCode)), '');
    SET @Product  = NULLIF(LTRIM(RTRIM(@Product)),  '');

    DECLARE @From   datetime = CAST(@FromDate AS datetime);
    DECLARE @ToNext datetime = CASE WHEN @ToDate IS NULL THEN NULL ELSE DATEADD(DAY, 1, CAST(@ToDate AS datetime)) END;

    /* ---------- DM headers ---------- */
    SELECT  h.id, DMNo = ISNULL(h.DMNo, ''), h.DMDate, Sess = h.[session], h.AreaCode AS AreaKey,
            AreaCode = ISNULL(h.AreaCode, ''), Area = ISNULL(h.Area, ''),
            CustKey  = CAST(ISNULL(NULLIF(LTRIM(RTRIM(h.Code)), ''), '#' + ISNULL(h.CName, '')) AS varchar(200)),
            Code = ISNULL(h.Code, ''), CName = ISNULL(h.CName, ''),
            Insurance = ISNULL(h.Insurace, 0), Tcs = CAST(ISNULL(h.Tcs_Amt, 0) AS decimal(18, 2)),
            VehNo = ISNULL(h.VehNo, ''), DriverName = ISNULL(h.DriverName, ''), Remarks = ISNULL(h.Remarks, '')
    INTO    #h
    FROM    dbo.AreaDMPoultry h
    WHERE   h.[session] = @Session
      AND  (@AreaCode IS NULL OR h.AreaCode = @AreaCode)
      AND  (@From     IS NULL OR h.DMDate  >= @From)
      AND  (@ToNext   IS NULL OR h.DMDate  <  @ToNext)
    OPTION (RECOMPILE);

    /* ---------- DM lines ---------- */
    SELECT  d.id, HeadId = h.id,
            Product  = ISNULL(NULLIF(LTRIM(RTRIM(d.Product)), ''), '(blank)'),
            HsnCode  = ISNULL(d.HsnCode, ''),
            QtyNos   = ISNULL(d.QtyNos, 0), QtyKg = ISNULL(d.QtyKg, 0),
            Rate     = ISNULL(d.Rate, 0), Amount = ISNULL(d.Amount, 0),
            TaxType  = ISNULL(NULLIF(LTRIM(RTRIM(d.TaxType)), ''), CASE WHEN ISNULL(d.TaxPer, 0) = 0 THEN 'Exempt' ELSE 'Tax' END),
            TaxPer   = ISNULL(d.TaxPer, 0), TaxValue = CAST(ISNULL(d.TaxValue, 0) AS decimal(18, 2)),
            /* Line total = amount + tax. If AreaDMPoultry_det.Amount already includes tax, use ISNULL(d.Amount, 0) only. */
            LineTotal = CAST(ISNULL(d.Amount, 0) + ISNULL(d.TaxValue, 0) AS decimal(18, 2))
    INTO    #l
    FROM    #h h
    JOIN    dbo.AreaDMPoultry_det d
            ON d.DMNo = h.DMNo AND d.[Session] = h.Sess AND d.AreaCode = h.AreaKey
    WHERE  (@Product IS NULL OR ISNULL(NULLIF(LTRIM(RTRIM(d.Product)), ''), '(blank)') = @Product);

    IF @Product IS NOT NULL
        DELETE h FROM #h h WHERE NOT EXISTS (SELECT 1 FROM #l l WHERE l.HeadId = h.id);

    /* ---------- bills (header + its line totals) ---------- */
    SELECT  h.*,
            Lines   = ISNULL(x.Lines, 0),
            Taxable = ISNULL(x.Taxable, 0), Tax = ISNULL(x.Tax, 0),
            QtyNos  = ISNULL(x.QtyNos, 0), QtyKg = ISNULL(x.QtyKg, 0),
            Charges = CASE WHEN @Product IS NULL THEN h.Insurance + h.Tcs ELSE 0 END,
            Total   = ISNULL(x.Taxable, 0) + ISNULL(x.Tax, 0) + CASE WHEN @Product IS NULL THEN h.Insurance + h.Tcs ELSE 0 END
    INTO    #b
    FROM    #h h
    OUTER APPLY (SELECT Lines = COUNT(*), Taxable = SUM(Amount), Tax = SUM(TaxValue),
                        QtyNos = SUM(QtyNos), QtyKg = SUM(QtyKg)
                 FROM #l l WHERE l.HeadId = h.id) x;

    /* ---------- receipts (all products) ---------- */
    SELECT  t.id, TRNo = ISNULL(t.TRNo, ''), t.TrDate,
            AreaCode = ISNULL(t.AreaCode, ''), Area = ISNULL(t.Area, ''),
            CustKey  = CAST(ISNULL(NULLIF(LTRIM(RTRIM(t.Code)), ''), '#' + ISNULL(t.CName, '')) AS varchar(200)),
            Code = ISNULL(t.Code, ''), CName = ISNULL(t.CName, ''),
            PayMode = ISNULL(NULLIF(LTRIM(RTRIM(t.Pay_mode)), ''), 'Not specified'),
            PayType = ISNULL(NULLIF(LTRIM(RTRIM(t.Pay_type)), ''), 'Not specified'),
            DD_No = ISNULL(t.DD_No, ''), Bank_det = ISNULL(t.Bank_det, ''), BankDate = t.bankdate,
            Amount = ISNULL(t.TrAmount, 0),
            IsAuth = CASE WHEN t.isAuth = 1 THEN 1 ELSE 0 END, AuthBy = ISNULL(t.AuthBy, ''),
            Remarks = ISNULL(t.Remarks, '')
    INTO    #t
    FROM    dbo.AreaTrPoultry t
    WHERE   t.[session] = @Session
      AND  (@AreaCode IS NULL OR t.AreaCode = @AreaCode)
      AND  (@From     IS NULL OR t.TrDate  >= @From)
      AND  (@ToNext   IS NULL OR t.TrDate  <  @ToNext)
    OPTION (RECOMPILE);

    /* ===== Result 1 : KPIs ===== */
    SELECT  b.DMCount, b.Customers, b.Taxable, b.Tax, b.Charges, b.Sales, b.QtyNos, b.QtyKg,
            AvgBill  = CASE WHEN b.DMCount > 0 THEN b.Sales / b.DMCount ELSE 0 END,
            p.Products, p.LineCount,
            r.ReceiptCount, r.ReceiptAmt, r.AuthAmt, r.PendingAuthAmt, r.PendingAuthCount,
            Outstanding   = b.Sales - r.ReceiptAmt,
            CollectionPct = CASE WHEN b.Sales > 0 THEN r.ReceiptAmt * 100.0 / b.Sales ELSE 0 END,
            ProductFilter = CASE WHEN @Product IS NULL THEN 0 ELSE 1 END
    FROM (  SELECT DMCount = COUNT(*), Customers = COUNT(DISTINCT CustKey),
                   Taxable = ISNULL(SUM(Taxable), 0), Tax = ISNULL(SUM(Tax), 0), Charges = ISNULL(SUM(Charges), 0),
                   Sales = ISNULL(SUM(Total), 0), QtyNos = ISNULL(SUM(QtyNos), 0), QtyKg = ISNULL(SUM(QtyKg), 0)
            FROM #b ) b
    CROSS JOIN ( SELECT Products = COUNT(DISTINCT Product), LineCount = COUNT(*) FROM #l ) p
    CROSS JOIN ( SELECT ReceiptCount = COUNT(*), ReceiptAmt = ISNULL(SUM(Amount), 0),
                        AuthAmt = ISNULL(SUM(CASE WHEN IsAuth = 1 THEN Amount END), 0),
                        PendingAuthAmt = ISNULL(SUM(CASE WHEN IsAuth = 0 THEN Amount END), 0),
                        PendingAuthCount = ISNULL(SUM(CASE WHEN IsAuth = 0 THEN 1 ELSE 0 END), 0)
                 FROM #t ) r;

    /* ===== Result 2 : product-wise ===== */
    SELECT  Product,
            HsnCode   = MAX(HsnCode),
            DMCount   = COUNT(DISTINCT l.HeadId),
            Customers = COUNT(DISTINCT h.CustKey),
            QtyNos    = SUM(QtyNos), QtyKg = SUM(QtyKg),
            Taxable   = SUM(Amount), Tax = SUM(TaxValue), Sales = SUM(LineTotal),
            AvgRate   = CASE WHEN SUM(CASE WHEN QtyKg > 0 THEN QtyKg ELSE QtyNos END) > 0
                             THEN SUM(Amount) / SUM(CASE WHEN QtyKg > 0 THEN QtyKg ELSE QtyNos END) ELSE 0 END,
            RateUnit  = CASE WHEN SUM(QtyKg) > 0 THEN 'kg' ELSE 'nos' END,
            MinRate   = MIN(NULLIF(Rate, 0)), MaxRate = MAX(Rate),
            LastSale  = MAX(h.DMDate)
    FROM #l l JOIN #h h ON h.id = l.HeadId
    GROUP BY Product
    ORDER BY SUM(LineTotal) DESC;

    /* ===== Result 3 : month-wise sales vs receipts ===== */
    ;WITH D AS (SELECT MonthStart = DATEADD(MONTH, DATEDIFF(MONTH, 0, DMDate), 0),
                       Sales = SUM(Total), QtyKg = SUM(QtyKg), QtyNos = SUM(QtyNos), DMCount = COUNT(*)
                FROM #b WHERE DMDate IS NOT NULL GROUP BY DATEADD(MONTH, DATEDIFF(MONTH, 0, DMDate), 0)),
          R AS (SELECT MonthStart = DATEADD(MONTH, DATEDIFF(MONTH, 0, TrDate), 0), ReceiptAmt = SUM(Amount)
                FROM #t WHERE TrDate IS NOT NULL GROUP BY DATEADD(MONTH, DATEDIFF(MONTH, 0, TrDate), 0))
    SELECT  MonthStart = COALESCE(D.MonthStart, R.MonthStart),
            Sales = ISNULL(D.Sales, 0), ReceiptAmt = ISNULL(R.ReceiptAmt, 0),
            QtyKg = ISNULL(D.QtyKg, 0), QtyNos = ISNULL(D.QtyNos, 0), DMCount = ISNULL(D.DMCount, 0)
    FROM D FULL OUTER JOIN R ON R.MonthStart = D.MonthStart
    ORDER BY 1;

    /* ===== Result 4 : month-wise sales of the top 6 products (rest = Others) ===== */
    SELECT TOP (6) Product INTO #top FROM #l GROUP BY Product ORDER BY SUM(LineTotal) DESC;
    SELECT  MonthStart = DATEADD(MONTH, DATEDIFF(MONTH, 0, h.DMDate), 0),
            Product    = ISNULL(t.Product, 'Others'),
            Sales      = SUM(l.LineTotal)
    FROM #l l JOIN #h h ON h.id = l.HeadId LEFT JOIN #top t ON t.Product = l.Product
    WHERE h.DMDate IS NOT NULL
    GROUP BY DATEADD(MONTH, DATEDIFF(MONTH, 0, h.DMDate), 0), ISNULL(t.Product, 'Others')
    ORDER BY 1, 2;

    /* ===== Result 5 : payment mode ===== */
    SELECT PayMode, ReceiptCount = COUNT(*), Amount = SUM(Amount) FROM #t GROUP BY PayMode ORDER BY SUM(Amount) DESC;

    /* ===== Result 6 : tax-wise (GST slabs) ===== */
    SELECT TaxType, TaxPer, LineCount = COUNT(*), Taxable = SUM(Amount), Tax = SUM(TaxValue), Total = SUM(LineTotal)
    FROM #l GROUP BY TaxType, TaxPer ORDER BY TaxPer, TaxType;

    /* ===== Result 7 : area-wise ===== */
    ;WITH D AS (SELECT AreaCode, Area = MAX(Area), DMCount = COUNT(*), Customers = COUNT(DISTINCT CustKey),
                       QtyKg = SUM(QtyKg), QtyNos = SUM(QtyNos), Sales = SUM(Total)
                FROM #b GROUP BY AreaCode),
          R AS (SELECT AreaCode, Area = MAX(Area), ReceiptCount = COUNT(*), ReceiptAmt = SUM(Amount) FROM #t GROUP BY AreaCode)
    SELECT  AreaCode = COALESCE(D.AreaCode, R.AreaCode), Area = COALESCE(NULLIF(D.Area, ''), R.Area, ''),
            DMCount = ISNULL(D.DMCount, 0), Customers = ISNULL(D.Customers, 0),
            QtyKg = ISNULL(D.QtyKg, 0), QtyNos = ISNULL(D.QtyNos, 0), Sales = ISNULL(D.Sales, 0),
            ReceiptCount = ISNULL(R.ReceiptCount, 0), ReceiptAmt = ISNULL(R.ReceiptAmt, 0),
            Balance = ISNULL(D.Sales, 0) - ISNULL(R.ReceiptAmt, 0),
            CollectionPct = CASE WHEN ISNULL(D.Sales, 0) > 0 THEN ISNULL(R.ReceiptAmt, 0) * 100.0 / D.Sales ELSE 0 END
    FROM D FULL OUTER JOIN R ON R.AreaCode = D.AreaCode
    ORDER BY ISNULL(D.Sales, 0) DESC;

    /* ===== Result 8 : customer-wise (top 1000 by sales) ===== */
    ;WITH D AS (SELECT CustKey, Code = MAX(Code), CName = MAX(CName), Area = MAX(Area), DMCount = COUNT(*),
                       QtyKg = SUM(QtyKg), QtyNos = SUM(QtyNos), Sales = SUM(Total), LastDMDate = MAX(DMDate)
                FROM #b GROUP BY CustKey),
          R AS (SELECT CustKey, Code = MAX(Code), CName = MAX(CName), Area = MAX(Area),
                       ReceiptAmt = SUM(Amount), LastReceiptDate = MAX(TrDate)
                FROM #t GROUP BY CustKey)
    SELECT TOP (1000)
            Code  = COALESCE(NULLIF(D.Code, ''), R.Code, ''),
            CName = COALESCE(NULLIF(D.CName, ''), R.CName, ''),
            Area  = COALESCE(NULLIF(D.Area, ''), R.Area, ''),
            DMCount = ISNULL(D.DMCount, 0), QtyKg = ISNULL(D.QtyKg, 0), QtyNos = ISNULL(D.QtyNos, 0),
            Sales = ISNULL(D.Sales, 0), ReceiptAmt = ISNULL(R.ReceiptAmt, 0),
            Balance = ISNULL(D.Sales, 0) - ISNULL(R.ReceiptAmt, 0),
            D.LastDMDate, R.LastReceiptDate
    FROM D FULL OUTER JOIN R ON R.CustKey = D.CustKey
    ORDER BY ISNULL(D.Sales, 0) DESC;

    /* ===== Result 9 : latest DMs (bills) ===== */
    SELECT TOP (300)
            b.DMNo, b.DMDate, b.Code, b.CName, b.Area,
            Products = STUFF((SELECT ', ' + l.Product FROM #l l WHERE l.HeadId = b.id ORDER BY l.id
                              FOR XML PATH(''), TYPE).value('.', 'nvarchar(max)'), 1, 2, ''),
            b.QtyKg, b.QtyNos, b.Taxable, b.Tax, Insurance = CASE WHEN @Product IS NULL THEN b.Insurance ELSE 0 END,
            Tcs = CASE WHEN @Product IS NULL THEN b.Tcs ELSE 0 END, b.Total, b.VehNo, b.DriverName
    FROM #b b
    ORDER BY b.DMDate DESC, b.id DESC;

    /* ===== Result 10 : latest product lines (sales register) ===== */
    SELECT TOP (500)
            h.DMNo, h.DMDate, h.Code, h.CName, h.Area,
            l.Product, l.HsnCode, l.QtyNos, l.QtyKg, l.Rate, l.Amount, l.TaxPer, l.TaxValue, l.LineTotal
    FROM #l l JOIN #h h ON h.id = l.HeadId
    ORDER BY h.DMDate DESC, l.HeadId DESC, l.id;

    /* ===== Result 11 : latest receipts ===== */
    SELECT TOP (300) TRNo, TrDate, Code, CName, Area, PayMode, PayType, DD_No, Bank_det, BankDate, Amount, IsAuth, AuthBy
    FROM #t ORDER BY TrDate DESC, id DESC;
END
GO
