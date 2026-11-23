/* =====================================================================
   OPTIONAL - TEST DATA ONLY.  Do NOT run on your live database.
   Creates ~3000 dispatch memos and matching payment receipts for
   sessions 2025-26 and 2026-27 so you can see the dashboard working.
   ===================================================================== */
SET NOCOUNT ON;

DECLARE @areas TABLE (n int PRIMARY KEY, AreaCode varchar(10), Area varchar(50));
INSERT @areas VALUES (0,'A01','Gorakhpur'),(1,'A02','Deoria'),(2,'A03','Kushinagar'),
                     (3,'A04','Basti'),(4,'A05','Maharajganj'),(5,'A06','Azamgarh');

;WITH n AS (
    SELECT TOP (3000) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS rn
    FROM sys.all_objects a CROSS JOIN sys.all_objects b
),
x AS (
    SELECT rn,
           CASE WHEN rn % 3 = 0 THEN '2026-27' ELSE '2025-26' END AS sess,
           ABS(CHECKSUM(rn, 'date'))  AS h1,
           ABS(CHECKSUM(rn, 'type'))  AS h2,
           ABS(CHECKSUM(rn, 'qty'))   AS h3,
           ABS(CHECKSUM(rn, 'cust'))  AS h4
    FROM n
),
y AS (
    SELECT x.*,
           CASE WHEN sess = '2025-26' THEN DATEADD(DAY, h1 % 365, '20250401')
                ELSE DATEADD(DAY, h1 % 205, '20260401') END AS dt,
           CASE WHEN h2 % 10 < 6 THEN 'Broiler' WHEN h2 % 10 < 9 THEN 'Layer' ELSE 'Cockrel' END AS ctype,
           h4 % 120 AS cust
    FROM x
)
INSERT dbo.AreaDMData (AreaCode, Area, DMNo, DMDate, HatchDate, [session], uname, entrydate,
                       Code, CName, Chick_type, Rate, TotalChicks, Mortality, Remarks, Hatchries,
                       dmidarea, isEmailed, isPosted, isAuth, isDisplay)
SELECT a.AreaCode, a.Area,
       'DM' + RIGHT('00000' + CAST(y.rn AS varchar(10)), 5),
       y.dt, DATEADD(DAY, -1, y.dt), y.sess, 'admin', y.dt,
       'C' + RIGHT('000' + CAST(y.cust AS varchar(10)), 3),
       'Customer ' + CAST(y.cust AS varchar(10)),
       y.ctype,
       CASE y.ctype WHEN 'Broiler' THEN 28 + (y.h3 % 18)
                    WHEN 'Layer'   THEN 32 + (y.h3 % 9)
                    ELSE 8 + (y.h3 % 8) END,
       (2 + y.h3 % 30) * 100,
       (y.h3 % 25),
       '', 'Hatchery-' + CAST(1 + y.h2 % 3 AS varchar(2)),
       y.rn, 0, 1, 1, 1
FROM y JOIN @areas a ON a.n = y.cust % 6;

/* Payments : ~85-100 % of each customer's monthly purchase per chick type */
;WITH s AS (
    SELECT [session], AreaCode, Area, Code, CName, Chick_type,
           DATEADD(MONTH, DATEDIFF(MONTH, 0, DMDate), 0) AS m,
           SUM((TotalChicks - Mortality) * Rate) AS amt
    FROM dbo.AreaDMData
    WHERE uname = 'admin' AND Remarks = ''
    GROUP BY [session], AreaCode, Area, Code, CName, Chick_type, DATEADD(MONTH, DATEDIFF(MONTH, 0, DMDate), 0)
),
r AS (
    SELECT s.*, ROW_NUMBER() OVER (ORDER BY m, Code, Chick_type) AS rn FROM s
)
INSERT dbo.AreaTrData (AreaCode, Area, TRNo, TrDate, HatchDate, [session], uname, entrydate, Code, CName,
                       Pay_mode, DD_No, Bank_det, Pay_type, Chick_type, Rate, TrAmount, Remarks,
                       tridarea, isEmailed, isPosted, bankdate, isAuth, AuthBy, vou_no, vou_type)
SELECT AreaCode, Area,
       'TR' + RIGHT('00000' + CAST(rn AS varchar(10)), 5),
       DATEADD(DAY, 10 + ABS(CHECKSUM(rn, 'd')) % 18, m), NULL, [session], 'admin', GETDATE(), Code, CName,
       CHOOSE(1 + ABS(CHECKSUM(rn, 'pm')) % 6, 'Cash', 'NEFT', 'RTGS', 'DD', 'Cheque', 'UPI'),
       CAST(100000 + rn AS varchar(10)),
       CHOOSE(1 + ABS(CHECKSUM(rn, 'bk')) % 4, 'SBI', 'PNB', 'HDFC', 'BOB'),
       CHOOSE(1 + ABS(CHECKSUM(rn, 'pt')) % 3, 'Against Bill', 'Advance', 'Part Payment'),
       Chick_type, 0,
       ROUND(amt * (85 + ABS(CHECKSUM(rn, 'p')) % 16) / 100.0, 0),
       '', rn, 0, 1, DATEADD(DAY, 12, m),
       CASE WHEN ABS(CHECKSUM(rn, 'a')) % 100 < 85 THEN 1 ELSE 0 END,
       'accounts', 'V' + CAST(rn AS varchar(10)), 'RCPT'
FROM r
WHERE m < DATEADD(MONTH, DATEDIFF(MONTH, 0, GETDATE()), 0) OR ABS(CHECKSUM(rn, 'c')) % 2 = 0;

PRINT 'Sample data inserted.';
