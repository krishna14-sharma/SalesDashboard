/* =====================================================================
   OPTIONAL - TEST DATA ONLY.  Do NOT run on your live database.
   Creates ~1500 poultry-product DMs (feed, medicine, vaccine, equipment)
   with lines, and payments covering roughly 70-95 % of supplies,
   so the Poultry Outstanding page has something to show.
   ===================================================================== */
SET NOCOUNT ON;

DECLARE @prod TABLE (n int PRIMARY KEY, Product varchar(100), Hsn varchar(20), Rate decimal(18,2), PerKg bit, TaxPer decimal(6,2));
INSERT @prod VALUES
 (0,'Broiler Pre-Starter Feed','23099010',42.50,1,0),
 (1,'Broiler Starter Feed','23099010',40.00,1,0),
 (2,'Broiler Finisher Feed','23099010',38.50,1,0),
 (3,'Layer Mash','23099010',31.00,1,0),
 (4,'Vitamin Premix 1kg','23099090',420.00,0,18),
 (5,'Lasota Vaccine 1000 dose','30023000',260.00,0,5),
 (6,'Gumboro Vaccine 1000 dose','30023000',310.00,0,5),
 (7,'Drinker 3 Ltr','39269099',95.00,0,18),
 (8,'Feeder 8 Kg','39269099',180.00,0,18),
 (9,'Litter Disinfectant 5 Ltr','38089400',650.00,0,18);

DECLARE @areas TABLE (n int PRIMARY KEY, AreaCode varchar(10), Area varchar(50));
INSERT @areas VALUES (0,'A01','Gorakhpur'),(1,'A02','Deoria'),(2,'A03','Kushinagar'),
                     (3,'A04','Basti'),(4,'A05','Maharajganj'),(5,'A06','Azamgarh');

;WITH n AS (SELECT TOP (1500) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) rn
            FROM sys.all_objects a CROSS JOIN sys.all_objects b),
x AS (SELECT rn, cust = ABS(CHECKSUM(rn,'c')) % 90,
             dt = DATEADD(DAY, -(ABS(CHECKSUM(rn,'d')) % 400), CAST(GETDATE() AS date))
      FROM n)
INSERT dbo.AreaDMPoultry (AreaCode, Area, DMNo, DMDate, [session], uname, entrydate, Code, CName, Remarks,
                          Insurace, dmidarea, isEmailed, isPosted, isAuth, VehNo, DriverName, Tcs_Per, Tcs_Amt, isGST, ShedDetails, isDM)
SELECT a.AreaCode, a.Area, 'PD' + RIGHT('00000' + CAST(x.rn AS varchar(10)), 5), x.dt,
       CASE WHEN x.dt >= '20260401' THEN '2026-27' ELSE '2025-26' END, 'testdata', x.dt,
       'P' + RIGHT('000' + CAST(x.cust AS varchar(10)), 3), 'Poultry Farm ' + CAST(x.cust AS varchar(10)), '',
       CASE WHEN x.rn % 5 = 0 THEN 150 ELSE 0 END, x.rn, 0, 1, 1,
       'UP53 AT ' + CAST(1000 + x.rn % 9000 AS varchar(10)), 'Driver ' + CAST(x.rn % 12 AS varchar(5)), 0, 0, 1, '', 1
FROM x JOIN @areas a ON a.n = x.cust % 6;

/* 1-4 lines per DM */
;WITH h AS (SELECT DMNo, [session], AreaCode, id FROM dbo.AreaDMPoultry WHERE uname = 'testdata'),
l AS (SELECT h.*, v.k FROM h CROSS APPLY (VALUES (1),(2),(3),(4)) v(k)
      WHERE v.k <= 1 + ABS(CHECKSUM(h.id,'lines')) % 4)
INSERT dbo.AreaDMPoultry_det (Product, QtyNos, QtyKg, Rate, Amount, HsnCode, DMNo, [Session], AreaCode, TaxType, TaxPer, TaxValue)
SELECT p.Product,
       q.Nos, q.Kg, p.Rate,
       CAST(p.Rate * CASE WHEN p.PerKg = 1 THEN q.Kg ELSE q.Nos END AS decimal(18,2)),
       p.Hsn, l.DMNo, l.[session], l.AreaCode,
       CASE WHEN p.TaxPer > 0 THEN 'GST' ELSE '' END, p.TaxPer,
       CAST(p.Rate * CASE WHEN p.PerKg = 1 THEN q.Kg ELSE q.Nos END * p.TaxPer / 100 AS decimal(8,2))
FROM l
JOIN @prod p ON p.n = ABS(CHECKSUM(l.id, l.k)) % 10
CROSS APPLY (SELECT Nos = CASE WHEN p.PerKg = 1 THEN 10 + ABS(CHECKSUM(l.id,l.k,'q')) % 90 ELSE 1 + ABS(CHECKSUM(l.id,l.k,'q')) % 20 END,
                    Kg  = CASE WHEN p.PerKg = 1 THEN (10 + ABS(CHECKSUM(l.id,l.k,'q')) % 90) * 50 ELSE 0 END) q;

/* Payments: per customer per month, 70-95 % of that month's supplies, not for the last ~45 days */
;WITH s AS (
    SELECT h.Code, h.CName, h.AreaCode, h.Area, h.[session],
           m = DATEADD(MONTH, DATEDIFF(MONTH, 0, h.DMDate), 0),
           amt = SUM(d.Amount + d.TaxValue)
    FROM dbo.AreaDMPoultry h
    JOIN dbo.AreaDMPoultry_det d ON d.DMNo = h.DMNo AND d.[Session] = h.[session] AND d.AreaCode = h.AreaCode
    WHERE h.uname = 'testdata' AND h.DMDate < DATEADD(DAY, -45, GETDATE())
    GROUP BY h.Code, h.CName, h.AreaCode, h.Area, h.[session], DATEADD(MONTH, DATEDIFF(MONTH, 0, h.DMDate), 0)
), r AS (SELECT s.*, rn = ROW_NUMBER() OVER (ORDER BY m, Code) FROM s)
INSERT dbo.AreaTrPoultry (AreaCode, Area, TRNo, TrDate, HatchDate, [session], uname, entrydate, Code, CName,
                          Pay_mode, DD_No, Bank_det, Pay_type, Chick_type, Rate, TrAmount, Remarks,
                          tridarea, isEmailed, isPosted, bankdate, isAuth, AuthBy)
SELECT AreaCode, Area, 'PT' + RIGHT('00000' + CAST(rn AS varchar(10)), 5),
       DATEADD(DAY, 20 + ABS(CHECKSUM(rn,'d')) % 25, m), NULL, [session], 'testdata', GETDATE(), Code, LEFT(CName, 50),
       CHOOSE(1 + ABS(CHECKSUM(rn,'pm')) % 5, 'Cash', 'NEFT', 'RTGS', 'Cheque', 'UPI'),
       CAST(200000 + rn AS varchar(10)), CHOOSE(1 + ABS(CHECKSUM(rn,'bk')) % 3, 'SBI', 'PNB', 'HDFC'),
       'Against Bill', 'Feed', 0,
       ROUND(amt * (70 + ABS(CHECKSUM(rn,'p')) % 26) / 100.0, 0), '',
       rn, 0, 1, NULL, CASE WHEN ABS(CHECKSUM(rn,'a')) % 100 < 90 THEN 1 ELSE 0 END, 'accounts'
FROM r;

PRINT 'Poultry sample data inserted.';
