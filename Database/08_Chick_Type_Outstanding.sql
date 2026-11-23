/* =====================================================================
   Chick type-wise outstanding & last hatch date  (ChickTypes.aspx)
   Sources
     dbo.PrintData           chick bills: chick type, hatch date, qty, rate
     dbo.VENTRY_PHHA_2627    accounts ledger: customer debits / credits
   Safe to re-run. SQL Server 2012 or later.

   How it works
     1. Chick customers = account codes (PrintData.AccCode) that have a
        Broiler / Layer / Cockrel bill line.
     2. Each customer's ledger entries are grouped by voucher
        (Vou_type + Vou_no). A voucher whose debit is bigger than its credit
        is a "debit" (bill, opening balance, journal...); the other way round
        it is a "credit" (receipt, credit note...).
     3. All credits are adjusted against the debits OLDEST FIRST. A debit
        that matches a chick bill in PrintData (same AccCode + Vou_type +
        Vou_no) is aged from that bill's HATCH DATE; any other debit is
        aged from its voucher date.
     4. What is still unpaid on a chick bill is split between its chick
        types in proportion to their value (Amount - DiscountAmount).
        Debits with no chick bill show as "Opening & other dues".
     5. Total due = ledger balance (debits - credits). A credit balance is
        shown as advance.
     6. Last hatch date = latest PrintData.HatchDate for that chick type.

     7. Opening balance comes from the account master (opening_dr -
        opening_cr) and is treated as the oldest due, dated 1 April of
        the ledger's financial year.

   Used by both chick pages: ChickOutstanding.aspx (usp_ChickOS_*)
   and ChickTypes.aspx (usp_ChickType_*).

   EDIT HERE when the financial year changes:
     dbo.vw_ChickLedger    -> points at VENTRY_PHHA_2627
     dbo.vw_ChickAccounts  -> points at ACC_HEAD_PHHA_2627
   ===================================================================== */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/* old objects from the earlier version of this page */
IF OBJECT_ID('dbo.usp_ChickType_Customer', 'P') IS NOT NULL DROP PROCEDURE dbo.usp_ChickType_Customer;
IF OBJECT_ID('dbo.usp_ChickType_Summary', 'P')  IS NOT NULL DROP PROCEDURE dbo.usp_ChickType_Summary;
IF OBJECT_ID('dbo.usp_ChickType_Fill', 'P')     IS NOT NULL DROP PROCEDURE dbo.usp_ChickType_Fill;
IF OBJECT_ID('dbo.usp_ChickType_Filters', 'P')  IS NOT NULL DROP PROCEDURE dbo.usp_ChickType_Filters;
IF OBJECT_ID('dbo.usp_ChickOS_Products', 'P')   IS NOT NULL DROP PROCEDURE dbo.usp_ChickOS_Products;
IF OBJECT_ID('dbo.usp_ChickOS_Customer', 'P')   IS NOT NULL DROP PROCEDURE dbo.usp_ChickOS_Customer;
IF OBJECT_ID('dbo.usp_ChickOS_Summary', 'P')    IS NOT NULL DROP PROCEDURE dbo.usp_ChickOS_Summary;
IF OBJECT_ID('dbo.usp_ChickLedger_Fill', 'P')   IS NOT NULL DROP PROCEDURE dbo.usp_ChickLedger_Fill;
IF OBJECT_ID('dbo.vw_ChickAccounts', 'V')       IS NOT NULL DROP VIEW dbo.vw_ChickAccounts;
IF OBJECT_ID('dbo.vw_ChickBillLines', 'V')      IS NOT NULL DROP VIEW dbo.vw_ChickBillLines;
IF OBJECT_ID('dbo.vw_ChickLedger', 'V')         IS NOT NULL DROP VIEW dbo.vw_ChickLedger;
GO

/* ---------------------------------------------------------------------
   1. Ledger of the current financial year.
      Change the table name each year (e.g. VENTRY_PHHA_2728).
      Use ONE year only: each year's table already carries the opening
      balance, so joining several years would count dues twice.
   --------------------------------------------------------------------- */
CREATE VIEW dbo.vw_ChickLedger
AS
SELECT  Cmp_id, Acc_head_code, Acc_head, Vou_type, Vou_no, Vou_date, dramt, cramt,
        Pay_mode, Cheque_no, Narration, Group_name, Sub_group_name, id
FROM    dbo.VENTRY_PHHA_2627;
GO

/* ---------------------------------------------------------------------
   1b. Account master of the same financial year: name, city, opening.
       If your ledger table ALSO holds opening-balance vouchers, set the
       two opening columns below to 0 so the opening is not counted twice.
   --------------------------------------------------------------------- */
CREATE VIEW dbo.vw_ChickAccounts
AS
SELECT  AccCode     = a.account_code,
        AccName     = a.account_head_name,
        City        = a.city,
        AreaCode    = a.Area_code,
        Phone       = a.phone,
        GroupName   = a.group_name,
        SubGroup    = a.sub_group_name,
        CreditDays  = CASE WHEN ISNUMERIC(a.credit_days) = 1 AND a.credit_days NOT LIKE '%[^0-9]%' THEN CAST(a.credit_days AS int) END,
        CreditLimit = CASE WHEN ISNUMERIC(a.credit_limit) = 1 AND a.credit_limit NOT LIKE '%[^0-9.]%' THEN CAST(a.credit_limit AS decimal(18, 2)) END,
        OpeningDr   = ISNULL(a.opening_dr, 0),
        OpeningCr   = ISNULL(a.opening_cr, 0)
FROM    dbo.ACC_HEAD_PHHA_2627 a;
GO

/* ---------------------------------------------------------------------
   2. Chick bill lines of the same company as the ledger.
      Chick type from ProductName: %broil% Broiler, %lay% Layer,
      %cock% Cockrel (covers "Cockerel"). Other products are left out.
   --------------------------------------------------------------------- */
CREATE VIEW dbo.vw_ChickBillLines
AS
SELECT  p.Vou_type, p.Vou_no, p.AccCode, p.AccName, p.Station, p.ProductName,
        ChickType = CASE WHEN p.ProductName LIKE '%broil%' THEN 'Broiler'
                         WHEN p.ProductName LIKE '%lay%'   THEN 'Layer'
                         ELSE 'Cockrel' END,
        Qty = ISNULL(p.Qty, 0), FreeQty = ISNULL(p.FreeQty, 0), Mortality = ISNULL(p.Mortality, 0),
        Rate = ISNULL(p.Rate, 0), Amount = ISNULL(p.Amount, 0),
        DiscountAmount = ISNULL(p.DiscountAmount, 0), NeccAmount = ISNULL(p.NeccAmount, 0),
        p.HatchDate, p.BillNo, p.BillDate, p.[Session], p.Cmp_id
FROM    dbo.PrintData p
WHERE   (p.ProductName LIKE '%broil%' OR p.ProductName LIKE '%lay%' OR p.ProductName LIKE '%cock%')
  AND   p.Cmp_id = (SELECT TOP (1) l.Cmp_id FROM dbo.vw_ChickLedger l);   -- same company as the ledger table
GO

/* ---------------------------------------------------------------------
   3. Fill - does the work. The CALLER creates #cust, #doc, #split and
      #credit (see the procedures below) and this procedure fills them.
   --------------------------------------------------------------------- */
CREATE PROCEDURE dbo.usp_ChickLedger_Fill
    @Station varchar(50) = NULL,
    @AsOf    date,
    @AccCode varchar(18) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Next datetime = DATEADD(DAY, 1, CAST(@AsOf AS datetime));

    /* chick bill lines up to the "as on" date */
    SELECT  b.*
    INTO    #ln
    FROM    dbo.vw_ChickBillLines b
    WHERE   ISNULL(b.AccCode, '') <> ''
      AND  (b.BillDate IS NULL OR b.BillDate < @Next)
      AND  (@AccCode IS NULL OR b.AccCode = @AccCode)
    OPTION (RECOMPILE);

    /* chick customers + last hatch / bill per type */
    INSERT #cust (AccCode, AccName, Station, BrHatch, LyHatch, CkHatch, BrBill, LyBill, CkBill, LastHatch, LastBill)
    SELECT  AccCode,
            AccName  = MAX(ISNULL(AccName, '')),
            Station  = MAX(ISNULL(Station, '')),
            BrHatch  = CAST(MAX(CASE WHEN ChickType = 'Broiler' THEN HatchDate END) AS date),
            LyHatch  = CAST(MAX(CASE WHEN ChickType = 'Layer'   THEN HatchDate END) AS date),
            CkHatch  = CAST(MAX(CASE WHEN ChickType = 'Cockrel' THEN HatchDate END) AS date),
            BrBill   = CAST(MAX(CASE WHEN ChickType = 'Broiler' THEN BillDate END) AS date),
            LyBill   = CAST(MAX(CASE WHEN ChickType = 'Layer'   THEN BillDate END) AS date),
            CkBill   = CAST(MAX(CASE WHEN ChickType = 'Cockrel' THEN BillDate END) AS date),
            LastHatch = CAST(MAX(HatchDate) AS date),
            LastBill  = CAST(MAX(BillDate) AS date)
    FROM    #ln
    GROUP BY AccCode
    HAVING  @Station IS NULL OR MAX(ISNULL(Station, '')) = @Station;

    /* name, city and credit terms from the account master */
    UPDATE c SET AccName = COALESCE(NULLIF(a.AccName, ''), c.AccName), City = a.City, Phone = a.Phone,
                 CreditDays = a.CreditDays, CreditLimit = a.CreditLimit
    FROM #cust c JOIN dbo.vw_ChickAccounts a ON a.AccCode = c.AccCode;

    /* first day of the ledger's financial year (1 April) */
    DECLARE @FYStart date = (SELECT MIN(Vou_date) FROM dbo.vw_ChickLedger);
    SET @FYStart = ISNULL(@FYStart, @AsOf);
    SET @FYStart = DATEFROMPARTS(YEAR(@FYStart) - CASE WHEN MONTH(@FYStart) < 4 THEN 1 ELSE 0 END, 4, 1);

    /* ledger entries of those customers, one row per voucher */
    SELECT  AccCode   = l.Acc_head_code,
            l.Vou_type, l.Vou_no,
            VouDate   = CAST(MIN(l.Vou_date) AS date),
            Dr        = SUM(ISNULL(l.dramt, 0)),
            Cr        = SUM(ISNULL(l.cramt, 0)),
            PayMode   = MAX(ISNULL(l.Pay_mode, '')),
            ChequeNo  = MAX(ISNULL(l.Cheque_no, '')),
            Narration = MAX(LEFT(ISNULL(l.Narration, ''), 200))
    INTO    #d
    FROM    dbo.vw_ChickLedger l
    JOIN    #cust c ON c.AccCode = l.Acc_head_code
    WHERE   l.Vou_date < @Next
    GROUP BY l.Acc_head_code, l.Vou_type, l.Vou_no;

    /* opening balance from the account master, as the oldest entry */
    INSERT #d (AccCode, Vou_type, Vou_no, VouDate, Dr, Cr, PayMode, ChequeNo, Narration)
    SELECT  a.AccCode, 'Opening', 'Balance b/f', @FYStart, a.OpeningDr, a.OpeningCr, '', '', 'Opening balance'
    FROM    dbo.vw_ChickAccounts a
    JOIN    #cust c ON c.AccCode = a.AccCode
    WHERE   a.OpeningDr <> a.OpeningCr
      AND   @FYStart <= @AsOf;

    /* credits (receipts, credit notes ...) */
    INSERT #credit (AccCode, VouDate, Vou_type, Vou_no, PayMode, ChequeNo, Narration, Amount)
    SELECT AccCode, VouDate, Vou_type, Vou_no, PayMode, ChequeNo, Narration, Cr - Dr
    FROM #d WHERE Cr > Dr;

    /* chick bill per voucher, and per voucher + chick type */
    SELECT  AccCode, Vou_type, Vou_no,
            HatchDate = CAST(MIN(HatchDate) AS date),
            BillDate  = CAST(MIN(BillDate) AS date),
            BillNo    = MIN(BillNo),
            W         = SUM(Amount - DiscountAmount)
    INTO    #bv
    FROM    #ln
    GROUP BY AccCode, Vou_type, Vou_no;

    SELECT  AccCode, Vou_type, Vou_no, ChickType,
            Qty = SUM(Qty), FreeQty = SUM(FreeQty), Mortality = SUM(Mortality),
            Gross = SUM(Amount), Discount = SUM(DiscountAmount), Necc = SUM(NeccAmount),
            W = SUM(Amount - DiscountAmount),
            HatchDate = CAST(MIN(HatchDate) AS date)
    INTO    #bt
    FROM    #ln
    GROUP BY AccCode, Vou_type, Vou_no, ChickType;

    /* debits, oldest first (hatch date for chick bills, voucher date otherwise) */
    ;WITH D AS (
        SELECT  d.AccCode, d.Vou_type, d.Vou_no, d.VouDate, d.Narration,
                Amount  = d.Dr - d.Cr,
                Linked  = CASE WHEN bv.Vou_no IS NOT NULL AND bv.W <> 0 THEN 1 ELSE 0 END,
                AgeDate = CASE WHEN bv.Vou_no IS NOT NULL AND bv.W <> 0 THEN COALESCE(bv.HatchDate, bv.BillDate, d.VouDate) ELSE d.VouDate END,
                bv.BillNo, bv.BillDate
        FROM    #d d
        LEFT JOIN #bv bv ON bv.AccCode = d.AccCode AND bv.Vou_type = d.Vou_type AND bv.Vou_no = d.Vou_no
        WHERE   d.Dr > d.Cr
    ),
    C AS (
        SELECT D.*, Cum = SUM(D.Amount) OVER (PARTITION BY D.AccCode ORDER BY D.AgeDate, CASE WHEN D.Vou_type = 'Opening' THEN 0 ELSE 1 END, D.VouDate, D.Vou_type, D.Vou_no ROWS UNBOUNDED PRECEDING)
        FROM D
    ),
    P AS (SELECT AccCode, Paid = SUM(Amount) FROM #credit GROUP BY AccCode)
    INSERT #doc (AccCode, Vou_type, Vou_no, VouDate, AgeDate, BillNo, BillDate, Narration, Linked, Amount, Adjusted, Outstanding, Days, Bucket)
    SELECT  C.AccCode, C.Vou_type, C.Vou_no, C.VouDate, C.AgeDate, C.BillNo, C.BillDate, C.Narration, C.Linked, C.Amount,
            a.Adjusted, C.Amount - a.Adjusted, dd.Days,
            CASE WHEN dd.Days <= 30 THEN 0 WHEN dd.Days <= 60 THEN 1 WHEN dd.Days <= 90 THEN 2 WHEN dd.Days <= 180 THEN 3 ELSE 4 END
    FROM    C
    LEFT JOIN P ON P.AccCode = C.AccCode
    CROSS APPLY (SELECT Paid = ISNULL(P.Paid, 0)) pp
    CROSS APPLY (SELECT Adjusted = CAST(CASE WHEN pp.Paid >= C.Cum            THEN C.Amount
                                             WHEN pp.Paid <= C.Cum - C.Amount THEN 0
                                             ELSE pp.Paid - (C.Cum - C.Amount) END AS decimal(18, 2))) a
    CROSS APPLY (SELECT Days = DATEDIFF(DAY, C.AgeDate, @AsOf)) dd;

    /* split each chick bill between its chick types; other debits as 'Other' */
    INSERT #split (AccCode, Vou_type, Vou_no, BillNo, BillDate, HatchDate, VouDate, ChickType, Qty, FreeQty, Mortality,
                   Gross, Discount, Necc, Amount, Adjusted, Outstanding, Days, Bucket, Narration)
    SELECT  d.AccCode, d.Vou_type, d.Vou_no, d.BillNo, d.BillDate, t.HatchDate, d.VouDate, t.ChickType, t.Qty, t.FreeQty, t.Mortality,
            t.Gross, t.Discount, t.Necc,
            Amount      = CAST(d.Amount      * t.W / bv.W AS decimal(18, 2)),
            Adjusted    = CAST(d.Adjusted    * t.W / bv.W AS decimal(18, 2)),
            Outstanding = CAST(d.Outstanding * t.W / bv.W AS decimal(18, 2)),
            d.Days, d.Bucket, d.Narration
    FROM    #doc d
    JOIN    #bv bv ON bv.AccCode = d.AccCode AND bv.Vou_type = d.Vou_type AND bv.Vou_no = d.Vou_no
    JOIN    #bt t  ON t.AccCode  = d.AccCode AND t.Vou_type  = d.Vou_type AND t.Vou_no  = d.Vou_no
    WHERE   d.Linked = 1
    UNION ALL
    SELECT  d.AccCode, d.Vou_type, d.Vou_no, NULL, NULL, NULL, d.VouDate, 'Other', 0, 0, 0,
            0, 0, 0, d.Amount, d.Adjusted, d.Outstanding, d.Days, d.Bucket, d.Narration
    FROM    #doc d
    WHERE   d.Linked = 0;
END
GO

/* ---------------------------------------------------------------------
   4. Filters : stations, ledger date range
   --------------------------------------------------------------------- */
CREATE PROCEDURE dbo.usp_ChickType_Filters
AS
BEGIN
    SET NOCOUNT ON;
    SELECT Station = ISNULL(Station, '') FROM dbo.vw_ChickBillLines
    WHERE ISNULL(Station, '') <> '' GROUP BY ISNULL(Station, '') ORDER BY 1;

    SELECT Today = CAST(GETDATE() AS date),
           LedgerFrom = (SELECT CAST(MIN(Vou_date) AS date) FROM dbo.vw_ChickLedger),
           LedgerTo   = (SELECT CAST(MAX(Vou_date) AS date) FROM dbo.vw_ChickLedger);
END
GO

/* ---------------------------------------------------------------------
   5. Summary : chick type totals and one row per customer
   --------------------------------------------------------------------- */
CREATE PROCEDURE dbo.usp_ChickType_Summary
    @Station varchar(50) = NULL,
    @AsOf    date        = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET @Station = NULLIF(LTRIM(RTRIM(@Station)), '');
    SET @AsOf    = ISNULL(@AsOf, CAST(GETDATE() AS date));

    CREATE TABLE #cust (AccCode varchar(18), AccName varchar(150), Station varchar(50),
        BrHatch date, LyHatch date, CkHatch date, BrBill date, LyBill date, CkBill date, LastHatch date, LastBill date,
        City varchar(30) NULL, Phone varchar(20) NULL, CreditDays int NULL, CreditLimit decimal(18, 2) NULL);
    CREATE TABLE #doc (AccCode varchar(18), Vou_type varchar(50), Vou_no varchar(50), VouDate date, AgeDate date, BillNo bigint, BillDate date,
        Narration varchar(200), Linked int, Amount decimal(18, 2), Adjusted decimal(18, 2), Outstanding decimal(18, 2), Days int, Bucket int);
    CREATE TABLE #split (AccCode varchar(18), Vou_type varchar(50), Vou_no varchar(50), BillNo bigint, BillDate date, HatchDate date, VouDate date,
        ChickType varchar(20), Qty decimal(18, 0), FreeQty decimal(18, 0), Mortality decimal(18, 0), Gross decimal(18, 2), Discount decimal(18, 2),
        Necc decimal(18, 2), Amount decimal(18, 2), Adjusted decimal(18, 2), Outstanding decimal(18, 2), Days int, Bucket int, Narration varchar(200));
    CREATE TABLE #credit (AccCode varchar(18), VouDate date, Vou_type varchar(50), Vou_no varchar(50), PayMode varchar(20),
        ChequeNo varchar(15), Narration varchar(200), Amount decimal(18, 2));

    EXEC dbo.usp_ChickLedger_Fill @Station = @Station, @AsOf = @AsOf, @AccCode = NULL;

    /* ===== Result 1 : chick types ===== */
    SELECT  s.ChickType,
            Supplied    = SUM(CASE WHEN s.ChickType = 'Other' THEN s.Amount ELSE s.Gross - s.Discount END),
            Chicks      = SUM(s.Qty),
            Outstanding = SUM(s.Outstanding),
            B0 = SUM(CASE WHEN s.Bucket = 0 THEN s.Outstanding ELSE 0 END), B1 = SUM(CASE WHEN s.Bucket = 1 THEN s.Outstanding ELSE 0 END),
            B2 = SUM(CASE WHEN s.Bucket = 2 THEN s.Outstanding ELSE 0 END), B3 = SUM(CASE WHEN s.Bucket = 3 THEN s.Outstanding ELSE 0 END),
            B4 = SUM(CASE WHEN s.Bucket = 4 THEN s.Outstanding ELSE 0 END),
            Customers  = COUNT(DISTINCT s.AccCode),
            WithDue    = COUNT(DISTINCT CASE WHEN s.Outstanding > 0 THEN s.AccCode END),
            LastSupply = CASE s.ChickType WHEN 'Broiler' THEN (SELECT MAX(BrHatch) FROM #cust)
                                          WHEN 'Layer'   THEN (SELECT MAX(LyHatch) FROM #cust)
                                          WHEN 'Cockrel' THEN (SELECT MAX(CkHatch) FROM #cust)
                                          ELSE MAX(s.VouDate) END
    FROM #split s
    GROUP BY s.ChickType
    ORDER BY CASE s.ChickType WHEN 'Broiler' THEN 1 WHEN 'Layer' THEN 2 WHEN 'Cockrel' THEN 3 ELSE 4 END;

    /* ===== Result 2 : customers ===== */
    ;WITH S AS (
        SELECT  AccCode,
                Outstanding = SUM(Outstanding),
                MaxDays = MAX(CASE WHEN Outstanding > 0 THEN Days END),
                BrSupplied = SUM(CASE WHEN ChickType = 'Broiler' THEN Gross - Discount ELSE 0 END),
                BrChicks = SUM(CASE WHEN ChickType = 'Broiler' THEN Qty ELSE 0 END),
                BrOS = SUM(CASE WHEN ChickType = 'Broiler' THEN Outstanding ELSE 0 END),
                BrDays = MAX(CASE WHEN ChickType = 'Broiler' AND Outstanding > 0 THEN Days END),
                LySupplied = SUM(CASE WHEN ChickType = 'Layer' THEN Gross - Discount ELSE 0 END),
                LyChicks = SUM(CASE WHEN ChickType = 'Layer' THEN Qty ELSE 0 END),
                LyOS = SUM(CASE WHEN ChickType = 'Layer' THEN Outstanding ELSE 0 END),
                LyDays = MAX(CASE WHEN ChickType = 'Layer' AND Outstanding > 0 THEN Days END),
                CkSupplied = SUM(CASE WHEN ChickType = 'Cockrel' THEN Gross - Discount ELSE 0 END),
                CkChicks = SUM(CASE WHEN ChickType = 'Cockrel' THEN Qty ELSE 0 END),
                CkOS = SUM(CASE WHEN ChickType = 'Cockrel' THEN Outstanding ELSE 0 END),
                CkDays = MAX(CASE WHEN ChickType = 'Cockrel' AND Outstanding > 0 THEN Days END),
                OtSupplied = SUM(CASE WHEN ChickType = 'Other' THEN Amount ELSE 0 END),
                OtOS = SUM(CASE WHEN ChickType = 'Other' THEN Outstanding ELSE 0 END),
                OtDays = MAX(CASE WHEN ChickType = 'Other' AND Outstanding > 0 THEN Days END),
                OtLast = MAX(CASE WHEN ChickType = 'Other' THEN VouDate END)
        FROM #split GROUP BY AccCode
    ),
    D AS (SELECT AccCode, Debits = SUM(Amount) FROM #doc GROUP BY AccCode),
    R AS (SELECT AccCode, Received = SUM(Amount), LastPayDate = MAX(VouDate) FROM #credit GROUP BY AccCode),
    LP AS (SELECT AccCode, LastPayAmt = SUM(Amount) FROM (
                SELECT c.AccCode, c.Amount, rk = DENSE_RANK() OVER (PARTITION BY c.AccCode ORDER BY c.VouDate DESC) FROM #credit c) x
           WHERE rk = 1 GROUP BY AccCode)
    SELECT  CustKey = c.AccCode, Code = c.AccCode, CName = c.AccName, Area = c.Station, AreaCode = c.Station,
            Outstanding = ISNULL(S.Outstanding, 0),
            Advance     = CASE WHEN ISNULL(R.Received, 0) > ISNULL(D.Debits, 0) THEN R.Received - ISNULL(D.Debits, 0) ELSE 0 END,
            Balance     = ISNULL(D.Debits, 0) - ISNULL(R.Received, 0),
            MaxDays = S.MaxDays,
            BrLast = c.BrHatch, BrHatch = c.BrHatch, BrBill = c.BrBill, BrSupplied = ISNULL(S.BrSupplied, 0), BrChicks = ISNULL(S.BrChicks, 0), BrOS = ISNULL(S.BrOS, 0), S.BrDays,
            LyLast = c.LyHatch, LyHatch = c.LyHatch, LyBill = c.LyBill, LySupplied = ISNULL(S.LySupplied, 0), LyChicks = ISNULL(S.LyChicks, 0), LyOS = ISNULL(S.LyOS, 0), S.LyDays,
            CkLast = c.CkHatch, CkHatch = c.CkHatch, CkBill = c.CkBill, CkSupplied = ISNULL(S.CkSupplied, 0), CkChicks = ISNULL(S.CkChicks, 0), CkOS = ISNULL(S.CkOS, 0), S.CkDays,
            OtLast = S.OtLast, OtSupplied = ISNULL(S.OtSupplied, 0), OtOS = ISNULL(S.OtOS, 0), S.OtDays,
            LastHatch = c.LastHatch, LastBill = c.LastBill,
            Received = ISNULL(R.Received, 0), R.LastPayDate, LastPayAmt = ISNULL(LP.LastPayAmt, 0)
    FROM #cust c
    LEFT JOIN S  ON S.AccCode  = c.AccCode
    LEFT JOIN D  ON D.AccCode  = c.AccCode
    LEFT JOIN R  ON R.AccCode  = c.AccCode
    LEFT JOIN LP ON LP.AccCode = c.AccCode
    ORDER BY ISNULL(S.Outstanding, 0) DESC, c.LastHatch DESC;

    /* ===== Result 3 : notes ===== */
    SELECT  OtherDues   = ISNULL((SELECT SUM(Outstanding) FROM #doc WHERE Linked = 0), 0),
            Advance     = ISNULL((SELECT SUM(CASE WHEN r.Rec > ISNULL(d.Deb, 0) THEN r.Rec - ISNULL(d.Deb, 0) ELSE 0 END)
                                  FROM (SELECT AccCode, Rec = SUM(Amount) FROM #credit GROUP BY AccCode) r
                                  LEFT JOIN (SELECT AccCode, Deb = SUM(Amount) FROM #doc GROUP BY AccCode) d ON d.AccCode = r.AccCode), 0),
            Customers   = (SELECT COUNT(*) FROM #cust),
            LedgerFrom  = (SELECT CAST(MIN(Vou_date) AS date) FROM dbo.vw_ChickLedger),
            LedgerTo    = (SELECT CAST(MAX(Vou_date) AS date) FROM dbo.vw_ChickLedger),
            AsOf = @AsOf;
END
GO

/* ---------------------------------------------------------------------
   6. One customer : bills by chick type, other dues, credits
   --------------------------------------------------------------------- */
CREATE PROCEDURE dbo.usp_ChickType_Customer
    @AccCode varchar(18),
    @AsOf    date = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET @AsOf = ISNULL(@AsOf, CAST(GETDATE() AS date));

    CREATE TABLE #cust (AccCode varchar(18), AccName varchar(150), Station varchar(50),
        BrHatch date, LyHatch date, CkHatch date, BrBill date, LyBill date, CkBill date, LastHatch date, LastBill date,
        City varchar(30) NULL, Phone varchar(20) NULL, CreditDays int NULL, CreditLimit decimal(18, 2) NULL);
    CREATE TABLE #doc (AccCode varchar(18), Vou_type varchar(50), Vou_no varchar(50), VouDate date, AgeDate date, BillNo bigint, BillDate date,
        Narration varchar(200), Linked int, Amount decimal(18, 2), Adjusted decimal(18, 2), Outstanding decimal(18, 2), Days int, Bucket int);
    CREATE TABLE #split (AccCode varchar(18), Vou_type varchar(50), Vou_no varchar(50), BillNo bigint, BillDate date, HatchDate date, VouDate date,
        ChickType varchar(20), Qty decimal(18, 0), FreeQty decimal(18, 0), Mortality decimal(18, 0), Gross decimal(18, 2), Discount decimal(18, 2),
        Necc decimal(18, 2), Amount decimal(18, 2), Adjusted decimal(18, 2), Outstanding decimal(18, 2), Days int, Bucket int, Narration varchar(200));
    CREATE TABLE #credit (AccCode varchar(18), VouDate date, Vou_type varchar(50), Vou_no varchar(50), PayMode varchar(20),
        ChequeNo varchar(15), Narration varchar(200), Amount decimal(18, 2));

    EXEC dbo.usp_ChickLedger_Fill @Station = NULL, @AsOf = @AsOf, @AccCode = @AccCode;

    /* ===== Result 1 : bills and other debits ===== */
    SELECT  ChickType, Vou_type, Vou_no, BillNo, HatchDate, BillDate, VouDate, Qty, FreeQty, Mortality,
            Rate = CASE WHEN Qty <> 0 THEN Gross / Qty ELSE 0 END,
            Gross, Discount, Necc, Amount, Adjusted, Outstanding, Days, Bucket, Narration
    FROM #split
    ORDER BY CASE ChickType WHEN 'Broiler' THEN 1 WHEN 'Layer' THEN 2 WHEN 'Cockrel' THEN 3 ELSE 4 END,
             COALESCE(HatchDate, VouDate) DESC, Vou_no DESC;

    /* ===== Result 2 : credits (receipts, credit notes ...) ===== */
    SELECT VouDate, Vou_type, Vou_no, PayMode, ChequeNo, Narration, Amount FROM #credit ORDER BY VouDate DESC, Vou_no DESC;

    /* ===== Result 3 : balance ===== */
    SELECT  Debits   = ISNULL((SELECT SUM(Amount) FROM #doc), 0),
            Credits  = ISNULL((SELECT SUM(Amount) FROM #credit), 0),
            LastHatch = (SELECT MAX(LastHatch) FROM #cust);
END
GO

/* =====================================================================
   7. Procedures for the main Chick outstanding page (ChickOutstanding.aspx)
      They return the same columns the page already uses, so the layout
      (aging, top 10, station-wise, customers, statement) is unchanged.
   ===================================================================== */

/* ---- 7a. Summary : KPIs, customers, station-wise ---- */
CREATE PROCEDURE dbo.usp_ChickOS_Summary
    @Station varchar(50) = NULL,
    @AsOf    date        = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET @Station = NULLIF(LTRIM(RTRIM(@Station)), '');
    SET @AsOf    = ISNULL(@AsOf, CAST(GETDATE() AS date));
    CREATE TABLE #cust (AccCode varchar(18), AccName varchar(150), Station varchar(50),
        BrHatch date, LyHatch date, CkHatch date, BrBill date, LyBill date, CkBill date, LastHatch date, LastBill date,
        City varchar(30) NULL, Phone varchar(20) NULL, CreditDays int NULL, CreditLimit decimal(18, 2) NULL);
    CREATE TABLE #doc (AccCode varchar(18), Vou_type varchar(50), Vou_no varchar(50), VouDate date, AgeDate date, BillNo bigint, BillDate date,
        Narration varchar(200), Linked int, Amount decimal(18, 2), Adjusted decimal(18, 2), Outstanding decimal(18, 2), Days int, Bucket int);
    CREATE TABLE #split (AccCode varchar(18), Vou_type varchar(50), Vou_no varchar(50), BillNo bigint, BillDate date, HatchDate date, VouDate date,
        ChickType varchar(20), Qty decimal(18, 0), FreeQty decimal(18, 0), Mortality decimal(18, 0), Gross decimal(18, 2), Discount decimal(18, 2),
        Necc decimal(18, 2), Amount decimal(18, 2), Adjusted decimal(18, 2), Outstanding decimal(18, 2), Days int, Bucket int, Narration varchar(200));
    CREATE TABLE #credit (AccCode varchar(18), VouDate date, Vou_type varchar(50), Vou_no varchar(50), PayMode varchar(20),
        ChequeNo varchar(15), Narration varchar(200), Amount decimal(18, 2));

    EXEC dbo.usp_ChickLedger_Fill @Station = @Station, @AsOf = @AsOf, @AccCode = NULL;

    ;WITH B AS (
        SELECT  AccCode, Bills = COUNT(*), Billed = SUM(Amount), Outstanding = SUM(Outstanding),
                B0 = SUM(CASE WHEN Bucket = 0 THEN Outstanding ELSE 0 END), B1 = SUM(CASE WHEN Bucket = 1 THEN Outstanding ELSE 0 END),
                B2 = SUM(CASE WHEN Bucket = 2 THEN Outstanding ELSE 0 END), B3 = SUM(CASE WHEN Bucket = 3 THEN Outstanding ELSE 0 END),
                B4 = SUM(CASE WHEN Bucket = 4 THEN Outstanding ELSE 0 END),
                OpenBills = SUM(CASE WHEN Outstanding > 0 THEN 1 ELSE 0 END),
                OldestDue = MIN(CASE WHEN Outstanding > 0 THEN AgeDate END),
                MaxDays   = MAX(CASE WHEN Outstanding > 0 THEN Days END),
                DueDays   = SUM(CASE WHEN Outstanding > 0 THEN Outstanding * Days ELSE 0 END),
                LastBillDate = MAX(CASE WHEN Linked = 1 THEN VouDate END)
        FROM #doc GROUP BY AccCode
    ),
    R AS (SELECT AccCode, Received = SUM(Amount), LastPayDate = MAX(VouDate) FROM #credit GROUP BY AccCode),
    LP AS (SELECT AccCode, LastPayAmt = SUM(Amount) FROM (
               SELECT AccCode, Amount, rk = DENSE_RANK() OVER (PARTITION BY AccCode ORDER BY VouDate DESC) FROM #credit) x
           WHERE rk = 1 GROUP BY AccCode)
    SELECT  CustKey = c.AccCode, Code = c.AccCode, CName = c.AccName,
            Area = COALESCE(NULLIF(c.City, ''), c.Station, ''), AreaCode = ISNULL(c.Station, ''),
            Bills = ISNULL(B.Bills, 0), Billed = ISNULL(B.Billed, 0), Received = ISNULL(R.Received, 0),
            Outstanding = ISNULL(B.Outstanding, 0),
            Advance    = CASE WHEN ISNULL(R.Received, 0) > ISNULL(B.Billed, 0) THEN R.Received - ISNULL(B.Billed, 0) ELSE 0 END,
            NetBalance = ISNULL(B.Billed, 0) - ISNULL(R.Received, 0),
            B0 = ISNULL(B.B0, 0), B1 = ISNULL(B.B1, 0), B2 = ISNULL(B.B2, 0), B3 = ISNULL(B.B3, 0), B4 = ISNULL(B.B4, 0),
            OpenBills = ISNULL(B.OpenBills, 0), B.OldestDue, MaxDays = ISNULL(B.MaxDays, 0),
            AvgDays = CASE WHEN ISNULL(B.Outstanding, 0) > 0 THEN B.DueDays / B.Outstanding ELSE 0 END,
            DueDays = ISNULL(B.DueDays, 0),
            LastBillDate = B.LastBillDate, R.LastPayDate, LastPayAmt = ISNULL(LP.LastPayAmt, 0),
            c.LastHatch, c.Phone, c.CreditDays, c.CreditLimit
    INTO    #c
    FROM #cust c
    LEFT JOIN B  ON B.AccCode  = c.AccCode
    LEFT JOIN R  ON R.AccCode  = c.AccCode
    LEFT JOIN LP ON LP.AccCode = c.AccCode;

    /* ===== Result 1 : KPIs ===== */
    SELECT  Billed = ISNULL(SUM(Billed), 0), Received = ISNULL(SUM(Received), 0),
            Outstanding = ISNULL(SUM(Outstanding), 0), Advance = ISNULL(SUM(Advance), 0),
            NetReceivable = ISNULL(SUM(Outstanding), 0) - ISNULL(SUM(Advance), 0),
            B0 = ISNULL(SUM(B0), 0), B1 = ISNULL(SUM(B1), 0), B2 = ISNULL(SUM(B2), 0), B3 = ISNULL(SUM(B3), 0), B4 = ISNULL(SUM(B4), 0),
            C0 = SUM(CASE WHEN B0 > 0 THEN 1 ELSE 0 END), C1 = SUM(CASE WHEN B1 > 0 THEN 1 ELSE 0 END), C2 = SUM(CASE WHEN B2 > 0 THEN 1 ELSE 0 END),
            C3 = SUM(CASE WHEN B3 > 0 THEN 1 ELSE 0 END), C4 = SUM(CASE WHEN B4 > 0 THEN 1 ELSE 0 END),
            Customers = COUNT(*), CustomersWithDue = SUM(CASE WHEN Outstanding > 0 THEN 1 ELSE 0 END),
            CustomersWithAdv = SUM(CASE WHEN Advance > 0 THEN 1 ELSE 0 END),
            OpenBills = ISNULL(SUM(OpenBills), 0),
            AvgDays = CASE WHEN SUM(Outstanding) > 0 THEN SUM(DueDays) / SUM(Outstanding) ELSE 0 END,
            CollectionPct = CASE WHEN SUM(Billed) > 0 THEN SUM(Received) * 100.0 / SUM(Billed) ELSE 0 END,
            AsOf = @AsOf, ServerTime = GETDATE()
    FROM #c;

    /* ===== Result 2 : customers ===== */
    SELECT * FROM #c ORDER BY Outstanding DESC, Advance DESC, CName;

    /* ===== Result 3 : station-wise ===== */
    SELECT  AreaCode = ISNULL(NULLIF(AreaCode, ''), '-'), Area = ISNULL(NULLIF(MAX(AreaCode), ''), '-'),
            Customers = COUNT(*), WithDue = SUM(CASE WHEN Outstanding > 0 THEN 1 ELSE 0 END),
            Billed = SUM(Billed), Received = SUM(Received), Outstanding = SUM(Outstanding), Advance = SUM(Advance),
            B0 = SUM(B0), B1 = SUM(B1), B2 = SUM(B2), B3 = SUM(B3), B4 = SUM(B4)
    FROM #c
    GROUP BY ISNULL(NULLIF(AreaCode, ''), '-')
    ORDER BY SUM(Outstanding) DESC;
END
GO

/* ---- 7b. One customer : bills (debits), bill lines, receipts (credits) ---- */
CREATE PROCEDURE dbo.usp_ChickOS_Customer
    @AccCode varchar(18),
    @AsOf    date = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET @AsOf = ISNULL(@AsOf, CAST(GETDATE() AS date));
    CREATE TABLE #cust (AccCode varchar(18), AccName varchar(150), Station varchar(50),
        BrHatch date, LyHatch date, CkHatch date, BrBill date, LyBill date, CkBill date, LastHatch date, LastBill date,
        City varchar(30) NULL, Phone varchar(20) NULL, CreditDays int NULL, CreditLimit decimal(18, 2) NULL);
    CREATE TABLE #doc (AccCode varchar(18), Vou_type varchar(50), Vou_no varchar(50), VouDate date, AgeDate date, BillNo bigint, BillDate date,
        Narration varchar(200), Linked int, Amount decimal(18, 2), Adjusted decimal(18, 2), Outstanding decimal(18, 2), Days int, Bucket int);
    CREATE TABLE #split (AccCode varchar(18), Vou_type varchar(50), Vou_no varchar(50), BillNo bigint, BillDate date, HatchDate date, VouDate date,
        ChickType varchar(20), Qty decimal(18, 0), FreeQty decimal(18, 0), Mortality decimal(18, 0), Gross decimal(18, 2), Discount decimal(18, 2),
        Necc decimal(18, 2), Amount decimal(18, 2), Adjusted decimal(18, 2), Outstanding decimal(18, 2), Days int, Bucket int, Narration varchar(200));
    CREATE TABLE #credit (AccCode varchar(18), VouDate date, Vou_type varchar(50), Vou_no varchar(50), PayMode varchar(20),
        ChequeNo varchar(15), Narration varchar(200), Amount decimal(18, 2));

    EXEC dbo.usp_ChickLedger_Fill @Station = NULL, @AsOf = @AsOf, @AccCode = @AccCode;

    DECLARE @Area varchar(50) = (SELECT TOP (1) COALESCE(NULLIF(City, ''), Station, '') FROM #cust);

    /* ===== Result 1 : bills / debits ===== */
    SELECT  BillKey   = d.Vou_type + '|' + d.Vou_no,
            DMNo      = CASE WHEN d.Vou_type = 'Opening' THEN 'Opening balance'
                             WHEN d.BillNo IS NOT NULL THEN CAST(d.BillNo AS varchar(20))
                             ELSE d.Vou_type + ' ' + d.Vou_no END,
            BillDate  = d.AgeDate,                         -- hatch date for chick bills
            DMDate    = COALESCE(d.BillDate, d.VouDate),
            [Session] = d.Vou_type + ' ' + d.Vou_no,
            Area      = @Area, AreaCode = '', Code = @AccCode, CName = '',
            Taxable = d.Amount, Tax = CAST(0 AS decimal(18, 2)), Insurance = CAST(0 AS decimal(18, 2)), Tcs = CAST(0 AS decimal(18, 2)),
            d.Amount,
            QtyNos = ISNULL((SELECT SUM(Qty) FROM #split s WHERE s.Vou_type = d.Vou_type AND s.Vou_no = d.Vou_no), 0),
            QtyKg = CAST(0 AS decimal(18, 2)), VehNo = '', DriverName = '',
            Remarks = CASE WHEN d.Linked = 1 THEN '' ELSE d.Narration END,
            d.Adjusted, d.Outstanding, d.Days, d.Bucket
    FROM #doc d
    ORDER BY d.AgeDate DESC, d.Vou_no DESC;

    /* ===== Result 2 : bill lines (PrintData) ===== */
    SELECT  BillKey = b.Vou_type + '|' + b.Vou_no,
            LineId = ROW_NUMBER() OVER (ORDER BY b.Vou_no, b.ChickType),
            Particulars = b.ProductName, HsnCode = '',
            QtyNos = b.Qty, Mortality = b.Mortality, NetQty = b.Qty - b.Mortality, QtyKg = CAST(0 AS decimal(18, 2)),
            b.Rate, Amount = b.Amount - b.DiscountAmount,
            TaxType = '', TaxPer = CAST(0 AS decimal(6, 2)), TaxValue = CAST(0 AS decimal(18, 2)),
            HatchDate = CAST(b.HatchDate AS date),
            Hatchery = CASE WHEN b.FreeQty > 0 THEN 'free ' + CAST(CAST(b.FreeQty AS int) AS varchar(12)) ELSE '' END
                     + CASE WHEN b.DiscountAmount > 0 THEN CASE WHEN b.FreeQty > 0 THEN ', ' ELSE '' END + 'discount ' + CAST(b.DiscountAmount AS varchar(20)) ELSE '' END
    FROM dbo.vw_ChickBillLines b
    WHERE b.AccCode = @AccCode
      AND EXISTS (SELECT 1 FROM #doc d WHERE d.Vou_type = b.Vou_type AND d.Vou_no = b.Vou_no);

    /* ===== Result 3 : receipts and credits ===== */
    SELECT  PayKey = Vou_type + '|' + Vou_no, TRNo = Vou_type + ' ' + Vou_no, TrDate = VouDate,
            [Session] = '', AreaCode = '', Area = @Area,
            PayMode = ISNULL(NULLIF(PayMode, ''), '-'), PayType = Vou_type, DD_No = ChequeNo, Bank_det = '', BankDate = NULL,
            Amount, IsAuth = 1, Remarks = Narration
    FROM #credit
    ORDER BY VouDate DESC, Vou_no DESC;
END
GO

/* ---- 7c. Product-wise (chick types + opening & other) ---- */
CREATE PROCEDURE dbo.usp_ChickOS_Products
    @Station varchar(50) = NULL,
    @AsOf    date        = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET @Station = NULLIF(LTRIM(RTRIM(@Station)), '');
    SET @AsOf    = ISNULL(@AsOf, CAST(GETDATE() AS date));
    CREATE TABLE #cust (AccCode varchar(18), AccName varchar(150), Station varchar(50),
        BrHatch date, LyHatch date, CkHatch date, BrBill date, LyBill date, CkBill date, LastHatch date, LastBill date,
        City varchar(30) NULL, Phone varchar(20) NULL, CreditDays int NULL, CreditLimit decimal(18, 2) NULL);
    CREATE TABLE #doc (AccCode varchar(18), Vou_type varchar(50), Vou_no varchar(50), VouDate date, AgeDate date, BillNo bigint, BillDate date,
        Narration varchar(200), Linked int, Amount decimal(18, 2), Adjusted decimal(18, 2), Outstanding decimal(18, 2), Days int, Bucket int);
    CREATE TABLE #split (AccCode varchar(18), Vou_type varchar(50), Vou_no varchar(50), BillNo bigint, BillDate date, HatchDate date, VouDate date,
        ChickType varchar(20), Qty decimal(18, 0), FreeQty decimal(18, 0), Mortality decimal(18, 0), Gross decimal(18, 2), Discount decimal(18, 2),
        Necc decimal(18, 2), Amount decimal(18, 2), Adjusted decimal(18, 2), Outstanding decimal(18, 2), Days int, Bucket int, Narration varchar(200));
    CREATE TABLE #credit (AccCode varchar(18), VouDate date, Vou_type varchar(50), Vou_no varchar(50), PayMode varchar(20),
        ChequeNo varchar(15), Narration varchar(200), Amount decimal(18, 2));

    EXEC dbo.usp_ChickLedger_Fill @Station = @Station, @AsOf = @AsOf, @AccCode = NULL;

    SELECT s.*, Product = CASE WHEN s.ChickType = 'Other' THEN 'Opening & other dues' ELSE s.ChickType END
    INTO #x FROM #split s;

    /* ===== Result 1 : product-wise ===== */
    SELECT  Product,
            Customers = COUNT(DISTINCT AccCode),
            WithDue   = COUNT(DISTINCT CASE WHEN Outstanding > 0 THEN AccCode END),
            Bills     = COUNT(DISTINCT Vou_type + '|' + Vou_no),
            Qty = SUM(Qty), QtyKg = CAST(0 AS decimal(18, 2)),
            Sales = SUM(Amount),
            AvgRate = CASE WHEN SUM(Qty) > 0 THEN SUM(Gross - Discount) / SUM(Qty) ELSE 0 END,
            Outstanding = SUM(Outstanding),
            B0 = SUM(CASE WHEN Bucket = 0 THEN Outstanding ELSE 0 END), B1 = SUM(CASE WHEN Bucket = 1 THEN Outstanding ELSE 0 END),
            B2 = SUM(CASE WHEN Bucket = 2 THEN Outstanding ELSE 0 END), B3 = SUM(CASE WHEN Bucket = 3 THEN Outstanding ELSE 0 END),
            B4 = SUM(CASE WHEN Bucket = 4 THEN Outstanding ELSE 0 END),
            LastSaleDate = MAX(COALESCE(HatchDate, VouDate))
    FROM #x
    GROUP BY Product
    ORDER BY SUM(Outstanding) DESC, SUM(Amount) DESC;

    /* ===== Result 2 : product x customer with dues ===== */
    SELECT  x.Product, CustKey = x.AccCode, Code = x.AccCode, CName = MAX(c.AccName), Area = MAX(COALESCE(NULLIF(c.City, ''), c.Station, '')),
            Qty = SUM(x.Qty), QtyKg = CAST(0 AS decimal(18, 2)), Sales = SUM(x.Amount), Outstanding = SUM(x.Outstanding),
            B0 = SUM(CASE WHEN x.Bucket = 0 THEN x.Outstanding ELSE 0 END), B1 = SUM(CASE WHEN x.Bucket = 1 THEN x.Outstanding ELSE 0 END),
            B2 = SUM(CASE WHEN x.Bucket = 2 THEN x.Outstanding ELSE 0 END), B3 = SUM(CASE WHEN x.Bucket = 3 THEN x.Outstanding ELSE 0 END),
            B4 = SUM(CASE WHEN x.Bucket = 4 THEN x.Outstanding ELSE 0 END),
            MaxDays = MAX(CASE WHEN x.Outstanding > 0 THEN x.Days END),
            OldestDue = MIN(CASE WHEN x.Outstanding > 0 THEN COALESCE(x.HatchDate, x.VouDate) END)
    FROM #x x JOIN #cust c ON c.AccCode = x.AccCode
    GROUP BY x.Product, x.AccCode
    HAVING SUM(x.Outstanding) > 0
    ORDER BY x.Product, SUM(x.Outstanding) DESC;
END
GO
