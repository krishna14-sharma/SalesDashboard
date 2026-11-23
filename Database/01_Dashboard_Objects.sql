/* =====================================================================
   Chick Sales & Payment Dashboard  -  Database objects
   Tables used : dbo.AreaDMData  (Dispatch Memo  = chick SALES)
                 dbo.AreaTrData  (Transaction    = PAYMENT RECEIPTS)
   Run this script once in your database (SQL Server 2012 or later).
   ===================================================================== */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/* ---------------------------------------------------------------------
   1. Indexes (session-wise filtering is the main access path)
   --------------------------------------------------------------------- */
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_AreaDMData_Session_DMDate'
               AND object_id = OBJECT_ID('dbo.AreaDMData'))
    CREATE NONCLUSTERED INDEX IX_AreaDMData_Session_DMDate
        ON dbo.AreaDMData ([session], DMDate)
        INCLUDE (AreaCode, Area, DMNo, Code, CName, Chick_type, Rate, TotalChicks, Mortality, Hatchries);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_AreaTrData_Session_TrDate'
               AND object_id = OBJECT_ID('dbo.AreaTrData'))
    CREATE NONCLUSTERED INDEX IX_AreaTrData_Session_TrDate
        ON dbo.AreaTrData ([session], TrDate)
        INCLUDE (AreaCode, Area, TRNo, Code, CName, Chick_type, Pay_mode, Pay_type, DD_No, Bank_det, TrAmount, isAuth, AuthBy);
GO

/* ---------------------------------------------------------------------
   2. Filter lists : sessions (latest first), areas of a session
   --------------------------------------------------------------------- */
IF OBJECT_ID('dbo.usp_ChickDash_Filters', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_ChickDash_Filters;
GO
CREATE PROCEDURE dbo.usp_ChickDash_Filters
    @Session varchar(50) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT  s.[session] AS [Session],
            MAX(s.dt)   AS LastDate
    INTO    #s
    FROM (
            SELECT [session], DMDate AS dt FROM dbo.AreaDMData WHERE ISNULL([session], '') <> ''
            UNION ALL
            SELECT [session], TrDate       FROM dbo.AreaTrData WHERE ISNULL([session], '') <> ''
         ) s
    GROUP BY s.[session];

    /* Result 1 : sessions, most recent activity first */
    SELECT [Session] FROM #s ORDER BY LastDate DESC, [Session] DESC;

    IF NULLIF(LTRIM(RTRIM(@Session)), '') IS NULL
        SELECT TOP (1) @Session = [Session] FROM #s ORDER BY LastDate DESC, [Session] DESC;

    /* Result 2 : areas of the session */
    SELECT  a.AreaCode, MAX(ISNULL(a.Area, '')) AS Area
    FROM (
            SELECT AreaCode, Area FROM dbo.AreaDMData WHERE [session] = @Session
            UNION ALL
            SELECT AreaCode, Area FROM dbo.AreaTrData WHERE [session] = @Session
         ) a
    WHERE ISNULL(a.AreaCode, '') <> ''
    GROUP BY a.AreaCode
    ORDER BY MAX(ISNULL(a.Area, '')), a.AreaCode;

    /* Result 3 : the session the areas belong to */
    SELECT @Session AS CurrentSession;
END
GO

/* ---------------------------------------------------------------------
   3. Dashboard data - returns 9 result sets in one round trip
      @ChickType : 'Broiler' | 'Layer' | 'Cockrel' | NULL (all)
      Dates filter DMDate for sales and TrDate for payments.
   --------------------------------------------------------------------- */
IF OBJECT_ID('dbo.usp_ChickDash_Data', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_ChickDash_Data;
GO
CREATE PROCEDURE dbo.usp_ChickDash_Data
    @Session   varchar(50),
    @AreaCode  varchar(50) = NULL,
    @ChickType varchar(20) = NULL,
    @FromDate  date        = NULL,
    @ToDate    date        = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SET @AreaCode  = NULLIF(LTRIM(RTRIM(@AreaCode)),  '');
    SET @ChickType = NULLIF(LTRIM(RTRIM(@ChickType)), '');

    DECLARE @From   datetime = CAST(@FromDate AS datetime);
    DECLARE @ToNext datetime = CASE WHEN @ToDate IS NULL THEN NULL
                                    ELSE DATEADD(DAY, 1, CAST(@ToDate AS datetime)) END;

    /* ---------- Sales (Dispatch Memo) ---------- */
    SELECT  d.id,
            ISNULL(d.DMNo, '')     AS DMNo,
            d.DMDate,
            d.HatchDate,
            ISNULL(d.AreaCode, '') AS AreaCode,
            ISNULL(d.Area, '')     AS Area,
            ISNULL(d.Code, '')     AS Code,
            ISNULL(d.CName, '')    AS CName,
            CASE WHEN d.Chick_type LIKE '%broil%' THEN 'Broiler'
                 WHEN d.Chick_type LIKE '%lay%'   THEN 'Layer'
                 WHEN d.Chick_type LIKE '%cock%'  THEN 'Cockrel'   -- matches Cockrel / Cockerel
                 ELSE 'Other' END  AS ChickType,
            ISNULL(d.TotalChicks, 0) AS Chicks,
            ISNULL(d.Mortality, 0)   AS Mortality,
            ISNULL(d.TotalChicks, 0) - ISNULL(d.Mortality, 0) AS NetChicks,
            ISNULL(d.Rate, 0)        AS Rate,
            /* Sale value is billed on net chicks (Total - Mortality).
               To bill on total chicks use: ISNULL(d.TotalChicks,0) * ISNULL(d.Rate,0) */
            (ISNULL(d.TotalChicks, 0) - ISNULL(d.Mortality, 0)) * ISNULL(d.Rate, 0) AS Amount,
            ISNULL(d.Hatchries, '')  AS Hatchries,
            ISNULL(d.Remarks, '')    AS Remarks
    INTO    #dm
    FROM    dbo.AreaDMData d
    WHERE   d.[session] = @Session
      AND  (@AreaCode IS NULL OR d.AreaCode = @AreaCode)
      AND  (@From     IS NULL OR d.DMDate  >= @From)
      AND  (@ToNext   IS NULL OR d.DMDate  <  @ToNext)
    OPTION (RECOMPILE);

    /* ---------- Payments received ---------- */
    SELECT  t.id,
            ISNULL(t.TRNo, '')     AS TRNo,
            t.TrDate,
            ISNULL(t.AreaCode, '') AS AreaCode,
            ISNULL(t.Area, '')     AS Area,
            ISNULL(t.Code, '')     AS Code,
            ISNULL(t.CName, '')    AS CName,
            CASE WHEN t.Chick_type LIKE '%broil%' THEN 'Broiler'
                 WHEN t.Chick_type LIKE '%lay%'   THEN 'Layer'
                 WHEN t.Chick_type LIKE '%cock%'  THEN 'Cockrel'
                 ELSE 'Other' END  AS ChickType,
            ISNULL(NULLIF(LTRIM(RTRIM(t.Pay_mode)), ''), 'Not specified') AS PayMode,
            ISNULL(NULLIF(LTRIM(RTRIM(t.Pay_type)), ''), 'Not specified') AS PayType,
            ISNULL(t.DD_No, '')    AS DD_No,
            ISNULL(t.Bank_det, '') AS Bank_det,
            t.bankdate             AS BankDate,
            ISNULL(t.TrAmount, 0)  AS Amount,
            CASE WHEN t.isAuth = 1 THEN 1 ELSE 0 END AS IsAuth,
            ISNULL(t.AuthBy, '')   AS AuthBy,
            ISNULL(t.vou_no, '')   AS VouNo,
            ISNULL(t.Remarks, '')  AS Remarks
    INTO    #tr
    FROM    dbo.AreaTrData t
    WHERE   t.[session] = @Session
      AND  (@AreaCode IS NULL OR t.AreaCode = @AreaCode)
      AND  (@From     IS NULL OR t.TrDate  >= @From)
      AND  (@ToNext   IS NULL OR t.TrDate  <  @ToNext)
    OPTION (RECOMPILE);

    IF @ChickType IS NOT NULL
    BEGIN
        DELETE FROM #dm WHERE ChickType <> @ChickType;
        DELETE FROM #tr WHERE ChickType <> @ChickType;
    END

    /* ===== Result 1 : KPI summary ===== */
    SELECT  d.DMCount, d.DMLines, d.TotalChicks, d.Mortality, d.NetChicks, d.SalesAmt,
            CASE WHEN d.NetChicks   > 0 THEN d.SalesAmt  / d.NetChicks           ELSE 0 END AS AvgRate,
            CASE WHEN d.TotalChicks > 0 THEN d.Mortality * 100.0 / d.TotalChicks ELSE 0 END AS MortalityPct,
            t.ReceiptCount, t.ReceiptAmt, t.AuthAmt, t.PendingAuthAmt, t.PendingAuthCount,
            d.SalesAmt - t.ReceiptAmt AS Outstanding,
            CASE WHEN d.SalesAmt > 0 THEN t.ReceiptAmt * 100.0 / d.SalesAmt ELSE 0 END AS CollectionPct,
            c.CustomerCount
    FROM (
            SELECT COUNT(DISTINCT DMNo)          AS DMCount,
                   COUNT(*)                      AS DMLines,
                   ISNULL(SUM(Chicks), 0)        AS TotalChicks,
                   ISNULL(SUM(Mortality), 0)     AS Mortality,
                   ISNULL(SUM(NetChicks), 0)     AS NetChicks,
                   ISNULL(SUM(Amount), 0)        AS SalesAmt
            FROM #dm
         ) d
    CROSS JOIN (
            SELECT COUNT(*)                                                AS ReceiptCount,
                   ISNULL(SUM(Amount), 0)                                  AS ReceiptAmt,
                   ISNULL(SUM(CASE WHEN IsAuth = 1 THEN Amount END), 0)    AS AuthAmt,
                   ISNULL(SUM(CASE WHEN IsAuth = 0 THEN Amount END), 0)    AS PendingAuthAmt,
                   ISNULL(SUM(CASE WHEN IsAuth = 0 THEN 1 ELSE 0 END), 0)  AS PendingAuthCount
            FROM #tr
         ) t
    CROSS JOIN (
            SELECT COUNT(*) AS CustomerCount
            FROM (SELECT Code FROM #dm UNION SELECT Code FROM #tr) x
            WHERE x.Code <> ''
         ) c;

    /* ===== Result 2 : by chick type ===== */
    ;WITH T AS (SELECT ChickType, SortNo
                FROM (VALUES ('Broiler', 1), ('Layer', 2), ('Cockrel', 3), ('Other', 4)) v(ChickType, SortNo)),
          D AS (SELECT ChickType, COUNT(DISTINCT DMNo) AS DMCount, SUM(Chicks) AS Chicks,
                       SUM(Mortality) AS Mortality, SUM(NetChicks) AS NetChicks, SUM(Amount) AS SalesAmt
                FROM #dm GROUP BY ChickType),
          R AS (SELECT ChickType, COUNT(*) AS ReceiptCount, SUM(Amount) AS ReceiptAmt
                FROM #tr GROUP BY ChickType)
    SELECT  T.ChickType,
            ISNULL(D.DMCount, 0)      AS DMCount,
            ISNULL(D.Chicks, 0)       AS Chicks,
            ISNULL(D.Mortality, 0)    AS Mortality,
            ISNULL(D.NetChicks, 0)    AS NetChicks,
            ISNULL(D.SalesAmt, 0)     AS SalesAmt,
            CASE WHEN ISNULL(D.NetChicks, 0) > 0 THEN D.SalesAmt / D.NetChicks ELSE 0 END AS AvgRate,
            CASE WHEN ISNULL(D.Chicks, 0) > 0 THEN D.Mortality * 100.0 / D.Chicks ELSE 0 END AS MortalityPct,
            ISNULL(R.ReceiptCount, 0) AS ReceiptCount,
            ISNULL(R.ReceiptAmt, 0)   AS ReceiptAmt,
            ISNULL(D.SalesAmt, 0) - ISNULL(R.ReceiptAmt, 0) AS Outstanding,
            CASE WHEN ISNULL(D.SalesAmt, 0) > 0 THEN ISNULL(R.ReceiptAmt, 0) * 100.0 / D.SalesAmt ELSE 0 END AS CollectionPct
    FROM T
    LEFT JOIN D ON D.ChickType = T.ChickType
    LEFT JOIN R ON R.ChickType = T.ChickType
    ORDER BY T.SortNo;

    /* ===== Result 3 : month-wise trend ===== */
    ;WITH D AS (SELECT DATEADD(MONTH, DATEDIFF(MONTH, 0, DMDate), 0) AS MonthStart,
                       SUM(Amount) AS SalesAmt, SUM(NetChicks) AS Chicks,
                       SUM(CASE WHEN ChickType = 'Broiler' THEN NetChicks ELSE 0 END) AS Broiler,
                       SUM(CASE WHEN ChickType = 'Layer'   THEN NetChicks ELSE 0 END) AS Layer,
                       SUM(CASE WHEN ChickType = 'Cockrel' THEN NetChicks ELSE 0 END) AS Cockrel,
                       SUM(CASE WHEN ChickType = 'Other'   THEN NetChicks ELSE 0 END) AS OtherChicks
                FROM #dm WHERE DMDate IS NOT NULL
                GROUP BY DATEADD(MONTH, DATEDIFF(MONTH, 0, DMDate), 0)),
          R AS (SELECT DATEADD(MONTH, DATEDIFF(MONTH, 0, TrDate), 0) AS MonthStart,
                       SUM(Amount) AS ReceiptAmt
                FROM #tr WHERE TrDate IS NOT NULL
                GROUP BY DATEADD(MONTH, DATEDIFF(MONTH, 0, TrDate), 0))
    SELECT  COALESCE(D.MonthStart, R.MonthStart) AS MonthStart,
            ISNULL(D.SalesAmt, 0)    AS SalesAmt,
            ISNULL(R.ReceiptAmt, 0)  AS ReceiptAmt,
            ISNULL(D.Chicks, 0)      AS Chicks,
            ISNULL(D.Broiler, 0)     AS Broiler,
            ISNULL(D.Layer, 0)       AS Layer,
            ISNULL(D.Cockrel, 0)     AS Cockrel,
            ISNULL(D.OtherChicks, 0) AS OtherChicks
    FROM D FULL OUTER JOIN R ON R.MonthStart = D.MonthStart
    ORDER BY 1;

    /* ===== Result 4 : payment mode ===== */
    SELECT PayMode, COUNT(*) AS ReceiptCount, SUM(Amount) AS Amount
    FROM #tr GROUP BY PayMode ORDER BY SUM(Amount) DESC;

    /* ===== Result 5 : payment type ===== */
    SELECT PayType, COUNT(*) AS ReceiptCount, SUM(Amount) AS Amount
    FROM #tr GROUP BY PayType ORDER BY SUM(Amount) DESC;

    /* ===== Result 6 : area-wise ===== */
    ;WITH D AS (SELECT AreaCode, MAX(Area) AS Area, COUNT(DISTINCT DMNo) AS DMCount,
                       SUM(Chicks) AS Chicks, SUM(Mortality) AS Mortality,
                       SUM(NetChicks) AS NetChicks, SUM(Amount) AS SalesAmt
                FROM #dm GROUP BY AreaCode),
          R AS (SELECT AreaCode, MAX(Area) AS Area, COUNT(*) AS ReceiptCount, SUM(Amount) AS ReceiptAmt
                FROM #tr GROUP BY AreaCode)
    SELECT  COALESCE(D.AreaCode, R.AreaCode)             AS AreaCode,
            COALESCE(NULLIF(D.Area, ''), R.Area, '')     AS Area,
            ISNULL(D.DMCount, 0)      AS DMCount,
            ISNULL(D.Chicks, 0)       AS Chicks,
            ISNULL(D.Mortality, 0)    AS Mortality,
            ISNULL(D.NetChicks, 0)    AS NetChicks,
            ISNULL(D.SalesAmt, 0)     AS SalesAmt,
            ISNULL(R.ReceiptCount, 0) AS ReceiptCount,
            ISNULL(R.ReceiptAmt, 0)   AS ReceiptAmt,
            ISNULL(D.SalesAmt, 0) - ISNULL(R.ReceiptAmt, 0) AS Outstanding,
            CASE WHEN ISNULL(D.SalesAmt, 0) > 0 THEN ISNULL(R.ReceiptAmt, 0) * 100.0 / D.SalesAmt ELSE 0 END AS CollectionPct
    FROM D FULL OUTER JOIN R ON R.AreaCode = D.AreaCode
    ORDER BY ISNULL(D.SalesAmt, 0) DESC;

    /* ===== Result 7 : customer-wise outstanding (top 1000) ===== */
    ;WITH D AS (SELECT Code, MAX(CName) AS CName, MAX(Area) AS Area, SUM(NetChicks) AS NetChicks,
                       SUM(Amount) AS SalesAmt, MAX(DMDate) AS LastDMDate
                FROM #dm WHERE Code <> '' GROUP BY Code),
          R AS (SELECT Code, MAX(CName) AS CName, MAX(Area) AS Area, SUM(Amount) AS ReceiptAmt,
                       MAX(TrDate) AS LastReceiptDate
                FROM #tr WHERE Code <> '' GROUP BY Code)
    SELECT TOP (1000)
            COALESCE(D.Code, R.Code)                    AS Code,
            COALESCE(NULLIF(D.CName, ''), R.CName, '')  AS CName,
            COALESCE(NULLIF(D.Area, ''),  R.Area,  '')  AS Area,
            ISNULL(D.NetChicks, 0)   AS NetChicks,
            ISNULL(D.SalesAmt, 0)    AS SalesAmt,
            ISNULL(R.ReceiptAmt, 0)  AS ReceiptAmt,
            ISNULL(D.SalesAmt, 0) - ISNULL(R.ReceiptAmt, 0) AS Outstanding,
            D.LastDMDate,
            R.LastReceiptDate
    FROM D FULL OUTER JOIN R ON R.Code = D.Code
    ORDER BY ISNULL(D.SalesAmt, 0) - ISNULL(R.ReceiptAmt, 0) DESC;

    /* ===== Result 8 : latest payment receipts ===== */
    SELECT TOP (300) TRNo, TrDate, Code, CName, Area, ChickType, PayMode, PayType,
                     DD_No, Bank_det, BankDate, Amount, IsAuth, AuthBy, VouNo
    FROM #tr ORDER BY TrDate DESC, id DESC;

    /* ===== Result 9 : latest dispatch memos ===== */
    SELECT TOP (300) DMNo, DMDate, HatchDate, Code, CName, Area, ChickType,
                     Chicks, Mortality, NetChicks, Rate, Amount, Hatchries
    FROM #dm ORDER BY DMDate DESC, id DESC;
END
GO
