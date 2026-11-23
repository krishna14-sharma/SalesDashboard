/* =====================================================================
   Feed Sale Review  -  Database objects (FeedReview.aspx)
   Source : dbo.AreaDMPoultry + dbo.AreaDMPoultry_det (feed lines only)
            outstanding from dbo.fn_CustOS_Allocated (03_Customer_Outstanding.sql)
   Run 03_Customer_Outstanding.sql first. Safe to re-run.

   WHICH LINES ARE "FEED"      -> dbo.fn_Feed_IsFeed   (edit the rules there)
   BROILER / LAYER / SONALI    -> dbo.fn_Feed_Group    (edit the rules there)
   SALESPERSON                 -> table dbo.FeedSalesperson (fill it in, see below)
   ===================================================================== */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/* ---------------------------------------------------------------------
   1. Salesperson mapping (your tables have no salesperson column)
      One row per customer code, or per area code for a whole area.
      A customer-code row wins over an area row. Customers with no
      match show as "Unassigned".
        INSERT dbo.FeedSalesperson (Code, AreaCode, Salesperson) VALUES ('P101', NULL, 'Satish');
        INSERT dbo.FeedSalesperson (Code, AreaCode, Salesperson) VALUES (NULL, 'A03', 'Tiwari Sir');
   --------------------------------------------------------------------- */
IF OBJECT_ID('dbo.FeedSalesperson', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.FeedSalesperson (
        id          int IDENTITY(1, 1) NOT NULL CONSTRAINT PK_FeedSalesperson PRIMARY KEY,
        Code        varchar(50)  NULL,      -- customer code (AreaDMPoultry.Code)
        AreaCode    varchar(50)  NULL,      -- or a whole area
        Salesperson varchar(100) NOT NULL,
        CONSTRAINT CK_FeedSalesperson_Target CHECK (Code IS NOT NULL OR AreaCode IS NOT NULL)
    );
    CREATE INDEX IX_FeedSalesperson_Code ON dbo.FeedSalesperson (Code);
    CREATE INDEX IX_FeedSalesperson_Area ON dbo.FeedSalesperson (AreaCode);
END
GO

IF OBJECT_ID('dbo.usp_FeedReview', 'P')       IS NOT NULL DROP PROCEDURE dbo.usp_FeedReview;
IF OBJECT_ID('dbo.usp_FeedReview_Filters', 'P') IS NOT NULL DROP PROCEDURE dbo.usp_FeedReview_Filters;
IF OBJECT_ID('dbo.fn_Feed_Lines', 'IF')       IS NOT NULL DROP FUNCTION dbo.fn_Feed_Lines;
IF OBJECT_ID('dbo.fn_Feed_IsFeed', 'FN')      IS NOT NULL DROP FUNCTION dbo.fn_Feed_IsFeed;
IF OBJECT_ID('dbo.fn_Feed_Group', 'FN')       IS NOT NULL DROP FUNCTION dbo.fn_Feed_Group;
GO

/* ---------------------------------------------------------------------
   2. Rules - edit these two functions if your product names differ
   --------------------------------------------------------------------- */
CREATE FUNCTION dbo.fn_Feed_IsFeed (@Product varchar(200), @Hsn varchar(50))
RETURNS bit
WITH SCHEMABINDING
AS
BEGIN
    RETURN CASE
        WHEN @Hsn LIKE '2309%'          THEN 1   -- HSN 2309 = animal / poultry feed
        WHEN @Product LIKE '%feed%'     THEN 1
        WHEN @Product LIKE '%crumb%'    THEN 1
        WHEN @Product LIKE '%mash%'     THEN 1
        WHEN @Product LIKE '%pellet%'   THEN 1
        WHEN @Product LIKE '%bronix%'   THEN 1
        WHEN @Product LIKE '%laynix%'   THEN 1
        WHEN @Product LIKE '%sonali%'   THEN 1
        ELSE 0 END;
END
GO

CREATE FUNCTION dbo.fn_Feed_Group (@Product varchar(200))
RETURNS varchar(20)
WITH SCHEMABINDING
AS
BEGIN
    RETURN CASE
        WHEN @Product LIKE '%sonali%'                                   THEN 'Sonali'
        WHEN @Product LIKE '%layer%'  OR @Product LIKE '%laynix%'       THEN 'Layer'
        WHEN @Product LIKE '%broil%'  OR @Product LIKE '%bronix%'       THEN 'Broiler'
        ELSE 'Other' END;
END
GO

/* ---------------------------------------------------------------------
   3. Feed lines (one row per DM line that is feed)
   --------------------------------------------------------------------- */
CREATE FUNCTION dbo.fn_Feed_Lines (@From date, @To date, @AreaCode varchar(50))
RETURNS TABLE
AS
RETURN
    SELECT  LineId   = d.id,
            HeadId   = h.id,
            h.DMNo,
            DMDate   = CAST(h.DMDate AS date),
            AreaCode = ISNULL(h.AreaCode, ''),
            Area     = ISNULL(h.Area, ''),
            CustKey  = CAST(ISNULL(NULLIF(LTRIM(RTRIM(h.Code)), ''), '#' + ISNULL(h.CName, '')) AS varchar(200)),
            Code     = ISNULL(h.Code, ''),
            CName    = ISNULL(h.CName, ''),
            Product  = ISNULL(NULLIF(LTRIM(RTRIM(d.Product)), ''), '(blank)'),
            Grp      = dbo.fn_Feed_Group(d.Product),
            QtyNos   = ISNULL(d.QtyNos, 0),
            QtyKg    = ISNULL(d.QtyKg, 0),
            Amount   = ISNULL(d.Amount, 0),
            /* sales value = amount + tax (feed is normally nil-rated, so tax is 0) */
            Sales    = CAST(ISNULL(d.Amount, 0) + ISNULL(d.TaxValue, 0) AS decimal(18, 2))
    FROM    dbo.AreaDMPoultry h
    JOIN    dbo.AreaDMPoultry_det d
            ON d.DMNo = h.DMNo AND d.[Session] = h.[session] AND d.AreaCode = h.AreaCode
    WHERE   h.DMDate IS NOT NULL
      AND  (@From IS NULL OR h.DMDate >= @From)
      AND  h.DMDate < DATEADD(DAY, 1, CAST(@To AS datetime))
      AND  (@AreaCode IS NULL OR h.AreaCode = @AreaCode)
      AND  dbo.fn_Feed_IsFeed(d.Product, d.HsnCode) = 1;
GO

/* ---------------------------------------------------------------------
   4. Filters : areas, first / last feed date
   --------------------------------------------------------------------- */
CREATE PROCEDURE dbo.usp_FeedReview_Filters
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Today date = CAST(GETDATE() AS date);

    SELECT AreaCode, Area = MAX(Area)
    FROM dbo.fn_Feed_Lines(NULL, @Today, NULL)
    WHERE AreaCode <> ''
    GROUP BY AreaCode
    ORDER BY MAX(Area), AreaCode;

    SELECT FirstDate = MIN(DMDate), LastDate = MAX(DMDate), Today = @Today
    FROM dbo.fn_Feed_Lines(NULL, @Today, NULL);
END
GO

/* ---------------------------------------------------------------------
   5. The review - 7 result sets
      @From / @To : the period (inclusive)
      @FeedGroup  : 'Broiler' | 'Layer' | 'Sonali' | 'Other' | NULL (all)
      Outstanding is as on @To for every feed customer (all poultry
      products, because receipts are not recorded per product).
   --------------------------------------------------------------------- */
CREATE PROCEDURE dbo.usp_FeedReview
    @From      date,
    @To        date,
    @AreaCode  varchar(50) = NULL,
    @FeedGroup varchar(20) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET @AreaCode  = NULLIF(LTRIM(RTRIM(@AreaCode)), '');
    SET @FeedGroup = NULLIF(LTRIM(RTRIM(@FeedGroup)), '');
    IF @To IS NULL SET @To = CAST(GETDATE() AS date);
    IF @From IS NULL OR @From > @To SET @From = DATEFROMPARTS(YEAR(@To) - CASE WHEN MONTH(@To) < 4 THEN 1 ELSE 0 END, 4, 1);

    /* feed lines in the period */
    SELECT * INTO #f FROM dbo.fn_Feed_Lines(@From, @To, @AreaCode)
    WHERE @FeedGroup IS NULL OR Grp = @FeedGroup
    OPTION (RECOMPILE);

    /* feed customers (bought feed at any time up to @To) and their outstanding as on @To */
    SELECT DISTINCT CustKey INTO #fc FROM dbo.fn_Feed_Lines(NULL, @To, @AreaCode);

    SELECT  a.CustKey,
            Outstanding = SUM(CASE WHEN a.Outstanding > 0 THEN a.Outstanding ELSE 0 END),
            B0 = SUM(CASE WHEN a.Bucket = 0 AND a.Outstanding > 0 THEN a.Outstanding ELSE 0 END),
            B1 = SUM(CASE WHEN a.Bucket = 1 AND a.Outstanding > 0 THEN a.Outstanding ELSE 0 END),
            B2 = SUM(CASE WHEN a.Bucket = 2 AND a.Outstanding > 0 THEN a.Outstanding ELSE 0 END),
            B3 = SUM(CASE WHEN a.Bucket = 3 AND a.Outstanding > 0 THEN a.Outstanding ELSE 0 END),
            B4 = SUM(CASE WHEN a.Bucket = 4 AND a.Outstanding > 0 THEN a.Outstanding ELSE 0 END),
            MaxDays = MAX(CASE WHEN a.Outstanding > 0 THEN a.Days END),
            Code = MAX(a.Code), CName = MAX(a.CName), Area = MAX(a.Area), AreaCode = MAX(a.AreaCode)
    INTO    #os
    FROM    dbo.fn_CustOS_Allocated('POULTRY', NULL, @AreaCode, @To, 0) a
    JOIN    #fc ON #fc.CustKey = a.CustKey
    GROUP BY a.CustKey;

    /* last feed billing per customer (any time up to @To) */
    SELECT CustKey, LastFeedDate = MAX(DMDate) INTO #last
    FROM dbo.fn_Feed_Lines(NULL, @To, @AreaCode)
    WHERE @FeedGroup IS NULL OR Grp = @FeedGroup
    GROUP BY CustKey;

    /* customers: period sales FULL JOIN outstanding */
    ;WITH S AS (
        SELECT  CustKey, Code = MAX(Code), CName = MAX(CName), Area = MAX(Area), AreaCode = MAX(AreaCode),
                Sales = SUM(Sales), QtyKg = SUM(QtyKg), QtyNos = SUM(QtyNos),
                DMs = COUNT(DISTINCT HeadId),
                Months = COUNT(DISTINCT DATEADD(MONTH, DATEDIFF(MONTH, 0, DMDate), 0)),
                FirstDate = MIN(DMDate), LastDate = MAX(DMDate)
        FROM #f GROUP BY CustKey
    )
    SELECT  CustKey   = COALESCE(S.CustKey, O.CustKey),
            Code      = COALESCE(NULLIF(S.Code, ''), O.Code, ''),
            CName     = COALESCE(NULLIF(S.CName, ''), O.CName, ''),
            Area      = COALESCE(NULLIF(S.Area, ''), O.Area, ''),
            AreaCode  = COALESCE(NULLIF(S.AreaCode, ''), O.AreaCode, ''),
            Sales     = ISNULL(S.Sales, 0), QtyKg = ISNULL(S.QtyKg, 0), QtyNos = ISNULL(S.QtyNos, 0),
            DMs       = ISNULL(S.DMs, 0), Months = ISNULL(S.Months, 0),
            S.FirstDate, S.LastDate, L.LastFeedDate,
            Outstanding = ISNULL(O.Outstanding, 0),
            B0 = ISNULL(O.B0, 0), B1 = ISNULL(O.B1, 0), B2 = ISNULL(O.B2, 0), B3 = ISNULL(O.B3, 0), B4 = ISNULL(O.B4, 0),
            MaxDays = ISNULL(O.MaxDays, 0)
    INTO    #c0
    FROM    S
    FULL OUTER JOIN (SELECT * FROM #os WHERE Outstanding > 0) O ON O.CustKey = S.CustKey
    LEFT JOIN #last L ON L.CustKey = COALESCE(S.CustKey, O.CustKey);

    /* salesperson: customer-code row first, then area row */
    SELECT  c.*, Salesperson = ISNULL(sp.Salesperson, 'Unassigned')
    INTO    #c
    FROM    #c0 c
    OUTER APPLY (
        SELECT TOP (1) m.Salesperson
        FROM dbo.FeedSalesperson m
        WHERE (m.Code IS NOT NULL AND m.Code = c.Code)
           OR (m.Code IS NULL AND m.AreaCode = c.AreaCode)
        ORDER BY CASE WHEN m.Code IS NOT NULL THEN 0 ELSE 1 END, m.id
    ) sp;

    /* ===== Result 1 : headline figures ===== */
    DECLARE @TotQty decimal(18, 2) = (SELECT ISNULL(SUM(QtyKg), 0) FROM #f);
    SELECT  Sales      = ISNULL((SELECT SUM(Sales) FROM #f), 0),
            QtyKg      = @TotQty,
            QtyNos     = ISNULL((SELECT SUM(QtyNos) FROM #f), 0),
            Customers  = (SELECT COUNT(DISTINCT CustKey) FROM #f),
            DMs        = (SELECT COUNT(DISTINCT HeadId) FROM #f),
            Products   = (SELECT COUNT(DISTINCT Product) FROM #f),
            DataFrom   = (SELECT MIN(DMDate) FROM #f),
            DataTo     = (SELECT MAX(DMDate) FROM #f),
            Top10QtyShare = CASE WHEN @TotQty > 0
                                 THEN (SELECT SUM(QtyKg) FROM (SELECT TOP (10) QtyKg FROM #c ORDER BY QtyKg DESC) t) * 100.0 / @TotQty
                                 ELSE 0 END,
            Outstanding     = ISNULL((SELECT SUM(Outstanding) FROM #c), 0),
            CustomersWithDue = (SELECT COUNT(*) FROM #c WHERE Outstanding > 0),
            SalespersonRows = (SELECT COUNT(*) FROM dbo.FeedSalesperson),
            PeriodFrom = @From, PeriodTo = @To;

    /* ===== Result 2 : month-wise ===== */
    SELECT  MonthStart = DATEADD(MONTH, DATEDIFF(MONTH, 0, DMDate), 0),
            Sales = SUM(Sales), QtyKg = SUM(QtyKg), Customers = COUNT(DISTINCT CustKey), DMs = COUNT(DISTINCT HeadId)
    FROM #f
    GROUP BY DATEADD(MONTH, DATEDIFF(MONTH, 0, DMDate), 0)
    ORDER BY 1;

    /* ===== Result 3 : feed groups ===== */
    SELECT Grp, Sales = SUM(Sales), QtyKg = SUM(QtyKg), Customers = COUNT(DISTINCT CustKey)
    FROM #f GROUP BY Grp ORDER BY SUM(Sales) DESC;

    /* ===== Result 4 : products ===== */
    SELECT  Product, Grp = MAX(Grp), Sales = SUM(Sales), QtyKg = SUM(QtyKg), QtyNos = SUM(QtyNos),
            AvgRate = CASE WHEN SUM(QtyKg) > 0 THEN SUM(Amount) / SUM(QtyKg) ELSE 0 END,
            Customers = COUNT(DISTINCT CustKey)
    FROM #f GROUP BY Product ORDER BY SUM(Sales) DESC;

    /* ===== Result 5 : salesperson-wise ===== */
    SELECT  Salesperson, Sales = SUM(Sales), QtyKg = SUM(QtyKg),
            Customers = SUM(CASE WHEN Sales > 0 THEN 1 ELSE 0 END),
            Outstanding = SUM(Outstanding),
            CustomersWithDue = SUM(CASE WHEN Outstanding > 0 THEN 1 ELSE 0 END)
    FROM #c GROUP BY Salesperson ORDER BY SUM(Sales) DESC;

    /* ===== Result 6 : customers ===== */
    SELECT * FROM #c ORDER BY Sales DESC, Outstanding DESC;

    /* ===== Result 7 : month x customer (for the detailed table) ===== */
    SELECT  CustKey, MonthStart = DATEADD(MONTH, DATEDIFF(MONTH, 0, DMDate), 0), Sales = SUM(Sales), QtyKg = SUM(QtyKg)
    FROM #f GROUP BY CustKey, DATEADD(MONTH, DATEDIFF(MONTH, 0, DMDate), 0);
END
GO
