# Chick Sales & Payment Dashboard (ASP.NET Web Forms 4.8)

Session-wise dashboard over `AreaDMData` (dispatch memos = sales) and `AreaTrData` (payment receipts),
split by chick type **Broiler / Layer / Cockrel**. Data loads through jQuery AJAX page methods, so changing
any filter refreshes the dashboard without reloading the page. Layout is Bootstrap 5 and works on mobile,
tablet and desktop.

## Folder layout
```
Database/
  01_Dashboard_Objects.sql        sales dashboard: indexes + 2 stored procedures (run once)
  02_Sample_Data_TEST_ONLY.sql    optional chick demo data - test database only
  03_Customer_Outstanding.sql     outstanding pages: indexes, 4 functions, 3 procedures (run once)
  04_Sample_Poultry_TEST_ONLY.sql optional poultry demo data - test database only
  05_Poultry_Sales.sql            poultry products sales dashboard: 2 indexes + 2 procedures (run once, after 03)
  06_Login.sql                    sign-in procedure over dbo.Usertab4 (run once)
  07_Feed_Review.sql              Feed Sale Review: feed rules, salesperson table, review procedure (run once, after 03)
  08_Chick_Type_Outstanding.sql   chick outstanding + type-wise from PrintData, VENTRY ledger, ACC_HEAD opening (run once)
Web/                              open this folder in Visual Studio as a Web Site
  Default.aspx / .cs              sales dashboard + [WebMethod] AJAX endpoints
  Login.aspx / .cs                sign-in page (AJAX); Logout.aspx signs out
  App_Code/AuthService.cs         password check, lock-out, sign-in cookie
  App_Code/ChatService.cs         dashboard assistant: understands the question, reads the data, writes the answer
  Chat.ashx                       assistant endpoint (signed-in users only)
  assets/js/chatbot.js, css/chatbot.css   chat window, added to every page by Controls/AppNav.ascx
  PoultrySales.aspx / .cs         poultry products sales dashboard
  FeedReview.aspx / .cs           Feed Sale Review for any time period
  ChickTypes.aspx / .cs           chick type-wise last hatch date and outstanding (PrintData + ledger)
  ChickOutstanding.aspx / .cs     customer outstanding - chicks (AreaDMData / AreaTrData)
  PoultryOutstanding.aspx / .cs   customer outstanding - poultry products (AreaDMPoultry + _det / AreaTrPoultry)
  Controls/OutstandingView.ascx   shared markup of the two outstanding pages
  Controls/AppNav.ascx            navigation bar shared by all three pages
  App_Code/DashboardRepository.cs SQL access for the sales dashboard + shared helpers
  App_Code/OutstandingService.cs  SQL access for the outstanding pages
  assets/js/outstanding.js        outstanding pages: AJAX, aging, customer drill-down, statement, print/CSV
  assets/css/dashboard.css
  assets/js/dashboard.js          AJAX calls, charts (Chart.js), tables, CSV export
  Web.config                      connection string "ChickDB"
```

## Setup
1. In SQL Server Management Studio, open your database and run `Database/01_Dashboard_Objects.sql` `Database/03_Customer_Outstanding.sql`, `Database/05_Poultry_Sales.sql`, `Database/06_Login.sql`, `Database/07_Feed_Review.sql` and `Database/08_Chick_Type_Outstanding.sql`.
2. Edit `Web/Web.config` → `connectionStrings/ChickDB` with your server, database and login.
3. Visual Studio → **File › Open › Web Site…** → pick the `Web` folder → run (F5).
   For IIS: copy the `Web` folder to the server, create an application on an
   **.NET CLR v4.0 / Integrated** app pool, and give the app pool identity access to the database.

## What the dashboard shows
| Area | Contents |
|---|---|
| Filters | Session (latest selected automatically), Area, Chick type, From/To date, Reset |
| KPI cards | Net chicks (total, mortality, mortality %), sales value, payment received, outstanding + collection %, receipts pending authorisation, average rate/chick, customer count |
| Chick type cards | Per Broiler/Layer/Cockrel: net chicks, DMs, receipts, sales, received, outstanding, avg rate, mortality, collection bar |
| Charts | Sales vs payment by type · monthly sales/payments with running outstanding · monthly chicks by type (stacked) · payment mode doughnut + payment type bars · top 12 areas |
| Tables | Area summary · customer outstanding · payment receipts · dispatch memos — sortable, searchable, totals row, CSV export |

## Business rules (change in `01_Dashboard_Objects.sql` if yours differ)
- **Sales value = (TotalChicks − Mortality) × Rate.** To bill on total chicks, change the `Amount` line in `#dm`.
- **Payment received = SUM(TrAmount)**; `isAuth = 1` counts as authorised, anything else as pending.
- **Outstanding = Sales − Payments** for the same filters (negative = advance, shown in green).
- Chick type is matched loosely: `%broil%` → Broiler, `%lay%` → Layer, `%cock%` → Cockrel (covers "Cockerel"); anything else → Other (shown only if it has values).
- Date filter applies to `DMDate` for sales and `TrDate` for payments.
- Session list is ordered by most recent DM/TR date.

## Notes
- Libraries load from cdnjs (Bootstrap 5.3, Bootstrap Icons, jQuery 3.7, Chart.js 4.4). For an offline
  server, download those files into `assets/lib` and change the four `<link>/<script>` URLs in `Default.aspx`.
- If you move this into a **Web Application** project instead of a Web Site, change `CodeFile=` to
  `CodeBehind=` in `Default.aspx`, and don't enable `FriendlyUrls` (it breaks page-method AJAX calls).

## Customer outstanding pages (Chick / Poultry products)
Both pages have the same layout. Only the source tables and the supply-line columns differ.

**How outstanding is calculated (FIFO).** For each customer (by `Code`, or by name when the code is blank),
all receipts are adjusted against that customer's supplies oldest first. Whatever is still unpaid
on a supply is its outstanding, and its age is the number of days from its **age date** to the "as on" date.

- **Chicks:** the age date is the **hatch date** (`AreaDMData.HatchDate`); if it's empty, the DM date is used.
  The oldest-first order and the "as on" cut-off use the hatch date too. If one DM has lines with different hatch dates,
  each hatch is treated as a separate supply with its own age. The supply view shows both dates, e.g. "Hatch 16-06-2026 · DM 17-06-2026".
- **Poultry products:** the age date is the DM date, because `AreaDMPoultry` has no hatch date.
If a customer has paid more than they were supplied, the extra is shown as **Advance**.

| Section | Contents |
|---|---|
| Filters | Session (default: all sessions), area, "as on" date, all receipts vs authorised only |
| Live | Figures are read from the tables on every load; auto-refresh every 60 s (toggle in the top bar) |
| KPIs | Total outstanding (and net of advance), overdue > 90 days, weighted average age, customers with dues, advance, collection % |
| Aging | 0-30 / 31-60 / 61-90 / 91-180 / 180+ days strip and tiles (tap a tile to list its customers), top-10 customers chart, area-wise aging table (tap to filter) |
| Customers | Sortable, searchable list with bucket columns, oldest due and last payment; shown as cards on phones; CSV export |
| Customer detail | Tap a customer (tabs: Outstanding supplies · Products · Payments · Statement) to see each unpaid supply: DM no, date, age, bill, amount adjusted, outstanding, plus **particulars, quantity, rate and amount** lines (poultry also shows HSN, kg, tax, insurance, TCS, vehicle and driver). Payments tab; running-balance statement; print; CSV export |

### Products
- **Product-wise table and chart:** quantity (nos / kg), sales, average rate, outstanding, share of total dues, aging, and how many customers owe money on each product.
  On the chick page the products are the chick types.
- **Product filter on the customer list:** tap a product, or pick one from the dropdown, to list only the customers who owe money on it. This shows their share of the supplies, the amount adjusted and the aging for that product.
- **Products tab in the customer view:** the same breakdown for one customer.
- **How outstanding is split:** a supply's outstanding is divided among its products in proportion to each line's value (amount + tax).
  Insurance, TCS and any other bill amount that is not a product line appear as their own row, **"Insurance, TCS & other charges"**,
  so the product rows always add up to the total outstanding.

**Poultry bill value** = sum(`AreaDMPoultry_det.Amount`) + sum(`TaxValue`) + `Insurace` + `Tcs_Amt`.
If `Amount` already includes tax, remove `+ ISNULL(l.Tax, 0)` in `fn_CustOS_Bills` (it's commented in the file).
**Chick bill value** = (TotalChicks − Mortality) × Rate, the same rule as the sales dashboard.
Lines are linked to their header by `DMNo + Session + AreaCode`. The `isDM` and `isGST` flags are not used as filters.

## Poultry products sales dashboard (PoultrySales.aspx)
Session-wise dashboard over `AreaDMPoultry` + `AreaDMPoultry_det` (sales) and `AreaTrPoultry` (payments).

| Section | Contents |
|---|---|
| Filters | Session (latest selected automatically), area, **product**, from/to date, reset |
| KPIs | Sales value (with goods / tax / insurance + TCS split), quantity (kg and nos), payment received, balance + collection %, pending authorisation, average DM value |
| Top products | The 4 best-selling products: sales, share, quantity, average rate, customers. Tap one to filter by it |
| Charts | Monthly sales / payments / running balance · sales share by product · monthly sales by product (top 6 + others) · payment mode · GST slabs · top areas |
| Tables | Products (qty, avg / min / max rate, amount, tax, total) · Customers · Areas · DM register · product lines · receipts. Sortable, searchable, totals row, CSV export |

With a product selected, sales figures cover that product's lines only; insurance and TCS are bill-level, so they're left out.
Receipts aren't recorded per product, so payment figures stay for all products, and the page says so.

## Sign-in (Login.aspx)
Every dashboard page needs a signed-in user (Forms Authentication). Users and passwords come from `dbo.Usertab4`.

- **Password format.** `Usertab4.Pwd` is varbinary. `usp_App_Login` recognises PWDENCRYPT, HASHBYTES SHA2_256 / SHA1 / MD5,
  ENCRYPTBYPASSPHRASE and plain bytes, for both varchar and nvarchar text. To find out which one your system uses, run:
  `EXEC dbo.usp_App_Login @Uname = 'someuser', @Password = N'their-password';`
  The `Method` column tells you. Put that value in Web.config → `Login.PasswordMode` instead of `AUTO`.
  For PASSPHRASE, also put the key in `Login.Passphrase`.
- **Blocked users.** `isUnAuth = 1` cannot sign in; they see "account is blocked".
- **Roles.** `Login.AllowedRoles` (comma-separated) limits sign-in to those roles. Empty means every role.
- **Lock-out.** After 5 wrong passwords for the same user from the same computer, sign-in is blocked for 15 minutes.
- **Session length.** 60 minutes of inactivity (`<forms timeout>`), or 7 days with "Keep me signed in".
  The outstanding pages auto-refresh every minute, so an open outstanding page keeps its sign-in alive.
- **Expired sign-in.** If the sign-in expires while a dashboard is open, the next data request takes the user to the login page
  and brings them back to the same page afterwards.
- **Navigation bar.** Shows the user name, role and a **Sign out** button.
- **Branding.** In Web.config, `App.CompanyName` and `App.LogoUrl` (an image inside the site, e.g. `~/assets/img/logo.png`)
  appear on the sign-in page. `App.Title` sets the product name shown there.
- **HTTPS.** Once the site is on https, set `requireSSL="true"` on `<forms>` in Web.config.
- **Several servers.** If the site runs on more than one server behind a load balancer, add the same `<machineKey>` to each server's
  Web.config so the sign-in cookie works on all of them.

## Feed Sale Review (FeedReview.aspx)
A separate page laid out like the printed "Feed Sale Review" document, for any time period.

- **Time period:** quick buttons (This FY, Last FY, This quarter, Last 3 months, This month, Last month) or any from/to dates,
  plus feed type (Broiler / Layer / Sonali / Other) and area. It opens on the current financial year (1 April to today).
- **Sections:** cover · at a glance (sales, KG and MT, top customer, best month, top-10 share of quantity, outstanding) · month-wise
  sales (peak in orange, part months marked *) · product mix and top products · salesperson-wise · top 10 by quantity ·
  customer-wise outstanding with notes ("100% unpaid", "no billing since Aug") · points for attention · detailed tables
  (customers, month-wise, products, customer × month) with search, sorting, totals and CSV export.
- **Headlines:** each section's headline is written from the figures, e.g. "October was the peak month at ₹4.19 Cr".
- **Print / save as PDF:** the printer button prints one section per landscape page, like the original review.

**Setup and rules** (all in `Database/07_Feed_Review.sql`):
- **Which lines are feed:** `dbo.fn_Feed_IsFeed`: HSN code 2309…, or the product name contains feed, crumb, mash, pellet,
  Bronix, Laynix or Sonali. Edit it if your names differ.
- **Feed type:** `dbo.fn_Feed_Group`: Sonali, then Layer/Laynix, then Broiler/Bronix, else Other.
- **Salesperson:** your tables have no salesperson column, so fill in the new table `dbo.FeedSalesperson`, one row per customer code
  (or one per area code for a whole area). Customers not listed show as "Unassigned". Until the table has rows, that section explains how to set it up.
- **Outstanding:** as on the "to" date, for customers who have bought feed, using the same oldest-first method as the outstanding pages.
  It covers all poultry products, because receipts are not recorded per product.
- **Quantity:** taken from `QtyKg`.

## Chick type-wise outstanding (ChickTypes.aspx, nav: Chicks → Type-wise)
One row per customer with the **last hatch date** and **outstanding** shown separately for Broiler, Layer and Cockrel,
plus **Opening & other** dues.

**Source tables** (`Database/08_Chick_Type_Outstanding.sql`)
- `dbo.PrintData`: chick bills. Chick type comes from `ProductName` (%broil% / %lay% / %cock%), along with HatchDate, BillNo,
  BillDate, Qty, FreeQty, Mortality, Rate, Amount and DiscountAmount. Only rows of the same company (`Cmp_id`) as the ledger are used.
- `dbo.VENTRY_PHHA_2627`: the accounts ledger. Customer account = `Acc_head_code` = `PrintData.AccCode`.
- **When the financial year changes,** edit the view `dbo.vw_ChickLedger` to point at the new year's table (e.g. `VENTRY_PHHA_2728`).
  Use one year only; each year's table carries its own opening balance.

**How it's calculated**
1. Chick customers are the account codes that have Broiler / Layer / Cockrel lines in PrintData.
2. Their ledger entries are grouped per voucher (`Vou_type + Vou_no`). A voucher with more debit than credit counts as a debit;
   the other way round it counts as a credit (receipt, credit note, ...).
3. All credits are adjusted against the debits **oldest first**. A debit that matches a chick bill
   (same AccCode + Vou_type + Vou_no in PrintData) is aged from the bill's **hatch date**; any other debit from its voucher date.
4. What's still unpaid on a chick bill is split between its chick types in proportion to their value (Amount − Discount).
   Debits with no chick bill (opening balance, journals) show under **Opening & other**.
5. **Total due** = the customer's ledger balance (debits − credits up to the "as on" date). A credit balance shows as advance.
6. **Last hatch** = the latest `PrintData.HatchDate` for that chick type (up to the "as on" date); older than 60 days is shown in brown.

**On the page:** filters for station (`PrintData.Station`) and "as on" date; a card per chick type; the customer table (sortable,
searchable, CSV, cards on phones). Tap a customer to see the ledger balance, every unpaid bill by chick type (bill no, voucher,
hatch date, bill date, chicks, free, mortality, rate, amount, discount, paid, outstanding, age), opening/other debits with narration,
and all receipts and credits from the ledger.

## Chick outstanding (ChickOutstanding.aspx): source = PrintData + VENTRY ledger + ACC_HEAD
The main **Chick outstanding** page and the **Type-wise** page now use the same source and the same calculation
(`Database/08_Chick_Type_Outstanding.sql`, procedures `usp_ChickOS_*` and `usp_ChickType_*`), so their totals match.

- **Outstanding** = each chick customer's ledger balance as on the chosen date: opening balance + ledger debits − ledger credits.
- **Opening balance** comes from the account master `ACC_HEAD_PHHA_2627` (`opening_dr − opening_cr`). It's treated as the oldest due,
  dated 1 April of the ledger's financial year. If your VENTRY table *also* has opening-balance vouchers, set the two opening
  columns in `dbo.vw_ChickAccounts` to 0 so it isn't counted twice.
- **Customer name and city** come from the account master (`account_head_name`, `city`). Phone and credit days/limit are read too.
- **Aging:** receipts and credits are taken off the oldest dues first. The opening balance comes first, then chick bills by **hatch date**.
- **Filters:** **Station** (from PrintData) and "as on" date. Session and "authorised receipts only" are hidden on this page,
  because the ledger covers one financial year and has no authorisation flag.
- **Customer view:** each bill (bill no, hatch date, bill date, voucher, chick lines with qty / mortality / free / rate / amount),
  the opening balance and other ledger debits, receipts from the ledger (voucher, mode, cheque no, narration), the products tab
  (chick types + "Opening & other dues"), and the running-balance statement.
- **Who's included:** customers who have at least one chick bill in PrintData. An account with only an opening balance and no
  chick bill isn't listed.
- **Each new financial year:** point `dbo.vw_ChickLedger` and `dbo.vw_ChickAccounts` at the new tables
  (e.g. `VENTRY_PHHA_2728`, `ACC_HEAD_PHHA_2728`) and re-run nothing else.

The poultry outstanding page is unchanged (AreaDMPoultry / AreaTrPoultry).

## Dashboard assistant (chat button on every page)
An **offline** assistant: no AI service, no API key, nothing leaves your server. It's the **Ask** button at the bottom right
of every dashboard page (full screen on phones). It understands a fixed set of question types in English and simple Hinglish
and answers from the same stored procedures the pages use, so its figures match the pages.

| Ask about | Examples |
|---|---|
| One customer's dues (chick + poultry) | "Outstanding of Royal Poultry", "kitna baki hai manohar ka", "DR1002 balance" |
| Last hatch date | "Last hatch of Manohar", "Last hatch dates", "customers with no hatch in 60 days" |
| Payments | "Payments of Royal", "uska payment", "Payments received this month" |
| Dues and aging | "Top 10 chick dues", "dues in Seoni", "Broiler dues over 90 days", "Chick dues 180+", "poultry dues over 60 days in Gorakhpur" |
| Sales | "Broiler sales last month", "chick sales in October", "Poultry sales this FY", "top poultry products last month" |
| Feed review | "Feed sales this FY", "feed sales by salesperson", "feed customers outstanding", "Layer feed sales last month" |

- **Customer names:** any part of the name or the account code works. Words that appear in many names ("poultry", "farm") are
  ignored when matching. If two customers fit equally well, it asks which one you mean.
- **Follow-ups:** "uska payment", "their last hatch" or a short "last hatch?" refer to the customer from the previous answer.
- **Periods:** today, yesterday, this week, this month, last month, last N months/days, this/last quarter, this FY, last FY,
  a month name ("October", "oct 2026", "since August"), or "1-10-2026 to 31-10-2026". The default is this financial year.
- **Places:** chick station names (PrintData.Station) and poultry area names are recognised ("in Raipur").
- **Each answer** can include a short summary, the aging split, a small table, a link to the matching page, and suggested next questions.
- **Speed:** customer lists are cached for 3 minutes, so repeated questions are quick. Totals are always read live.
- **To change what it understands:** the word lists and answers are in `App_Code/ChatService.cs` (look for `Route` and `Query`).

All C# in `App_Code`, the page code-behind files and `Chat.ashx` compile with the C# 5 compiler used by ASP.NET Web Sites;
the assistant was tested against sample data with about 30 real-style questions.
