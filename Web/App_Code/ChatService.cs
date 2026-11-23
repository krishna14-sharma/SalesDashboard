using System;
using System.Collections.Generic;
using System.Data;
using System.Data.SqlClient;
using System.Globalization;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;
using System.Web;
using System.Web.Caching;

/// <summary>
/// Offline dashboard assistant (no AI, no outside service).
/// Reads a question in English or simple Hinglish, works out what is being asked
/// (customer dues, aging, last hatch, sales, feed review ...), the period, the customer,
/// the station / area and the chick type, then answers from the same stored procedures
/// the dashboard pages use. Called by Chat.ashx.
/// Written for C# 5 (the compiler used by ASP.NET Web Sites on .NET 4.8).
/// </summary>
public static class ChatService
{
    private static readonly CultureInfo IN = new CultureInfo("en-IN");
    private const int CacheMinutes = 3;

    // ================================================================== entry point

    public static Dictionary<string, object> Answer(string question, Dictionary<string, object> ctx)
    {
        var r = new Reply();
        try
        {
            var q = new Query(question ?? "", ctx);
            Route(q, r);
            r.Ctx["customer"] = q.ContextCustomer;
            r.Ctx["domain"] = q.ContextDomain;
        }
        catch (Exception ex)
        {
            System.Diagnostics.Trace.TraceError("Chat failed for '" + question + "': " + ex);
            r = new Reply();
            r.Text("I couldn't read the data just now. Please try again in a moment, or open the dashboard page directly.");
            r.Suggest("Help");
        }
        return r.ToJson();
    }

    // ================================================================== routing

    private static void Route(Query q, Reply r)
    {
        if (q.IsEmpty || q.Any("help", "madad", "what can you do", "kya kar sakte", "examples") || q.IsGreetingOnly)
        {
            Help(r);
            return;
        }

        bool wantsHatch   = q.Any("hatch", "hatching", "last supply", "last supplied", "aakhri", "akhri", "chuza diya", "supply kab");
        bool wantsSales   = q.Any("sale", "sales", "sold", "bikri", "billing", "billed", "turnover", "revenue", "becha");
        bool wantsPay     = q.Any("payment", "payments", "receipt", "receipts", "received", "paid", "collection", "collected", "jama");
        bool wantsDue     = q.Any("outstanding", "due", "dues", "baki", "bakaya", "baaki", "udhaar", "udhar", "owe", "owes", "balance",
                                  "pending", "receivable", "aging", "ageing", "overdue", "lena", "dena");
        bool wantsSp      = q.Any("salesperson", "sales person", "salesman", "sales man", "salespeople");
        bool wantsTop     = q.Any("top", "biggest", "highest", "largest", "sabse zyada", "sabse jyada", "most");
        bool wantsProduct = q.Any("product", "products", "item", "items");

        // ---- customer named? (or a follow-up about the last customer)
        var cust = FindCustomers(q);
        if (cust.Ambiguous.Count > 1)
        {
            r.Text("I found more than one customer with that name. Which one do you mean?");
            foreach (var c in cust.Ambiguous.Take(5))
                r.Suggest((wantsHatch ? "Last hatch of " : wantsPay ? "Last payment of " : "Outstanding of ") + c.Name + " (" + c.Code + ")");
            return;
        }
        bool fromContext = false;
        if (cust.Chick == null && cust.Poultry == null && q.CtxCustomer != null && q.IsFollowUp && !wantsTop && !q.Any("total", "overall", "all customers", "sab"))
        {
            cust = FindByKey(q.CtxCustomer);
            fromContext = true;
            if (wantsHatch && cust.Chick == null) cust = new CustMatch();   // follow-up hatch about a poultry-only customer: show overall hatch
        }
        if (wantsHatch && cust.Chick == null && cust.Poultry != null && !fromContext)
        {
            r.Text(Bold(cust.Poultry.Name) + " buys poultry products only, so there is no hatch date. Here are the latest hatches instead:");
            OverallHatch(q, r);
            return;
        }

        if (cust.Chick != null || cust.Poultry != null)
        {
            if (wantsHatch && cust.Chick != null) { CustomerHatch(q, r, cust.Chick); return; }
            if (wantsPay && !wantsDue) { CustomerPayments(q, r, cust); return; }
            if (wantsSales && !wantsDue) { CustomerSales(q, r, cust); return; }
            CustomerDues(q, r, cust);
            return;
        }

        // ---- no customer
        if (q.LooksLikeName && !wantsTop && (wantsDue || wantsHatch || wantsPay))
        {
            r.Text("I couldn't find a customer called \"" + q.LeftoverText + "\". Try part of the name or the account code, for example \"Outstanding of Royal\".");
            r.Suggest("Top 10 chick dues"); r.Suggest("Top 10 poultry dues");
            return;
        }

        if (q.Feed && (wantsSales || wantsSp || wantsDue || wantsTop || q.Any("review", "quantity", "kg", "buyers")) || (wantsSp && !q.Chick))
        { FeedReview(q, r, wantsSp, wantsDue && !wantsSales, wantsTop); return; }

        if (wantsHatch) { OverallHatch(q, r); return; }

        if (wantsSales || (wantsProduct && wantsTop && !wantsDue))
        {
            if (q.Poultry && !q.Chick) { PoultrySales(q, r, wantsProduct); return; }
            if (q.Chick && !q.Poultry) { ChickSales(q, r); return; }
            ChickSales(q, r); PoultrySales(q, r, wantsProduct); return;
        }

        if (wantsPay) { Collections(q, r); return; }

        if (wantsDue || wantsTop || q.OverDays > 0)
        {
            if ((q.Poultry && !q.Chick) || (q.PoultryArea != null && q.Station == null)) { PoultryDues(q, r); return; }
            if (q.Chick || q.ChickType != null || (q.Station != null && q.PoultryArea == null)) { ChickDues(q, r); return; }
            ChickDues(q, r); PoultryDues(q, r); return;
        }

        r.Text("Sorry, I didn't understand that. I can answer questions about customer dues, aging, last hatch dates, sales and the feed review. Here are some examples:");
        HelpSuggestions(r);
    }

    // ================================================================== help

    private static void Help(Reply r)
    {
        r.Text("Hi! I answer questions from the live dashboard data. You can ask in English or simple Hinglish, for example:");
        r.Table(new[] { "Ask about", "Example" }, new List<object[]>
        {
            new object[] { "One customer's dues", "Outstanding of Royal Poultry" },
            new object[] { "Last hatch date", "Last hatch of Manohar" },
            new object[] { "Old dues", "Chick dues over 90 days" },
            new object[] { "Biggest dues", "Top 10 poultry dues in Jabalpur" },
            new object[] { "Sales for a period", "Broiler sales last month" },
            new object[] { "Feed review", "Feed sales this FY by salesperson" },
            new object[] { "Collections", "Payments received this month" }
        }, null);
        r.Text("Dates I understand: today, this month, last month, this quarter, last 3 months, this FY, last FY, a month name (\"October\"), or a range like \"1-10-2026 to 31-10-2026\".");
        HelpSuggestions(r);
    }

    private static void HelpSuggestions(Reply r)
    {
        r.Suggest("Top 10 chick dues");
        r.Suggest("Broiler dues over 90 days");
        r.Suggest("Last hatch dates");
        r.Suggest("Chick sales this month");
        r.Suggest("Feed sales this FY");
        r.Suggest("Top poultry products last month");
    }

    // ================================================================== customer answers

    private static void CustomerDues(Query q, Reply r, CustMatch m)
    {
        if (m.Chick != null)
        {
            var c = m.Chick.Row;
            decimal os = D(c, "Outstanding"), adv = D(c, "Advance");
            q.ContextCustomer = m.Chick.Key; q.ContextDomain = "chick";
            r.Text(Bold(m.Chick.Name) + " (" + m.Chick.Code + Area(m.Chick) + ") — chicks: " +
                   (os > 0 ? "owes " + Bold(Inr(os)) : adv > 0 ? "has an advance of " + Bold(Inr(adv)) : "nothing due") +
                   " as on " + LongDate(Today) + ".");
            if (os > 0) r.Stats(BucketStats(c), "Aged from the hatch date");
            var t = ChickTypeRow(m.Chick.Key);
            if (t != null) r.Table(new[] { "Chick type", "Last hatch", "Due", "Oldest" }, TypeRows(t), new[] { "", "", "num", "num" });
            var lines = new List<string>();
            if (S(c, "LastPayDate") != "") lines.Add("Last receipt " + Inr(D(c, "LastPayAmt")) + " on " + Dmy(S(c, "LastPayDate")) + ".");
            lines.Add("Billed " + Inr(D(c, "Billed")) + " (incl. opening), received " + Inr(D(c, "Received")) + " this financial year.");
            r.Text(string.Join(" ", lines));
            r.Link("Open chick outstanding", "ChickOutstanding.aspx");
            r.Suggest("Last hatch of " + m.Chick.Name);
            r.Suggest("Payments of " + m.Chick.Name);
        }
        if (m.Poultry != null)
        {
            var c = m.Poultry.Row;
            decimal os = D(c, "Outstanding"), adv = D(c, "Advance");
            if (m.Chick == null) { q.ContextCustomer = m.Poultry.Key; q.ContextDomain = "poultry"; }
            r.Text(Bold(m.Poultry.Name) + " (" + m.Poultry.Code + Area(m.Poultry) + ") — poultry products: " +
                   (os > 0 ? "owes " + Bold(Inr(os)) : adv > 0 ? "has an advance of " + Bold(Inr(adv)) : "nothing due") +
                   " as on " + LongDate(Today) + ".");
            if (os > 0) r.Stats(BucketStats(c), "Aged from the DM date");
            var extra = new List<string>();
            if (S(c, "OldestDue") != "") extra.Add("Oldest unpaid supply " + Dmy(S(c, "OldestDue")) + " (" + I(c, "MaxDays") + " days).");
            if (S(c, "LastPayDate") != "") extra.Add("Last payment " + Inr(D(c, "LastPayAmt")) + " on " + Dmy(S(c, "LastPayDate")) + ".");
            if (extra.Count > 0) r.Text(string.Join(" ", extra));
            r.Link("Open poultry outstanding", "PoultryOutstanding.aspx");
            if (m.Chick == null) r.Suggest("Payments of " + m.Poultry.Name);
        }
        r.Suggest("Top 10 chick dues");
    }

    private static void CustomerHatch(Query q, Reply r, CustRef c)
    {
        q.ContextCustomer = c.Key; q.ContextDomain = "chick";
        var t = ChickTypeRow(c.Key);
        string last = S(c.Row, "LastHatch");
        r.Text(Bold(c.Name) + " (" + c.Code + Area(c) + "): last hatch supplied " +
               (last != "" ? Bold(Dmy(last)) + " — " + DaysAgo(last) : "not found") + ".");
        if (t != null) r.Table(new[] { "Chick type", "Last hatch", "Due", "Oldest" }, TypeRows(t), new[] { "", "", "num", "num" });
        r.Link("Open chick type-wise", "ChickTypes.aspx");
        r.Suggest("Outstanding of " + c.Name);
        r.Suggest("Customers with no hatch in 60 days");
    }

    private static void CustomerPayments(Query q, Reply r, CustMatch m)
    {
        if (m.Chick != null)
        {
            q.ContextCustomer = m.Chick.Key; q.ContextDomain = "chick";
            var c = m.Chick.Row;
            r.Text(Bold(m.Chick.Name) + " — chicks: received " + Bold(Inr(D(c, "Received"))) + " this financial year" +
                   (S(c, "LastPayDate") != "" ? "; last receipt " + Inr(D(c, "LastPayAmt")) + " on " + Dmy(S(c, "LastPayDate")) + " (" + DaysAgo(S(c, "LastPayDate")) + ")" : "; no receipt yet") +
                   ". Still due: " + Inr(D(c, "Outstanding")) + ".");
        }
        if (m.Poultry != null)
        {
            if (m.Chick == null) { q.ContextCustomer = m.Poultry.Key; q.ContextDomain = "poultry"; }
            var c = m.Poultry.Row;
            r.Text(Bold(m.Poultry.Name) + " — poultry products: received " + Bold(Inr(D(c, "Received"))) +
                   (S(c, "LastPayDate") != "" ? "; last payment " + Inr(D(c, "LastPayAmt")) + " on " + Dmy(S(c, "LastPayDate")) : "; no payment yet") +
                   ". Still due: " + Inr(D(c, "Outstanding")) + ".");
        }
        r.Suggest("Outstanding of " + (m.Chick != null ? m.Chick.Name : m.Poultry.Name));
    }

    private static void CustomerSales(Query q, Reply r, CustMatch m)
    {
        // supplied amounts come from the outstanding data (current financial year + opening)
        if (m.Chick != null)
        {
            q.ContextCustomer = m.Chick.Key; q.ContextDomain = "chick";
            var t = ChickTypeRow(m.Chick.Key);
            r.Text(Bold(m.Chick.Name) + " — chick bills this financial year: " + Bold(Inr(D(m.Chick.Row, "Billed"))) + " (including opening balance).");
            if (t != null)
            {
                var rows = new List<object[]>();
                foreach (var ty in ChickTypes)
                    if (D(t, ty.P + "Supplied") > 0)
                        rows.Add(new object[] { ty.Name, N(D(t, ty.P + "Chicks")), Inr(D(t, ty.P + "Supplied")), Dmy(S(t, ty.P + "Last")) });
                if (rows.Count > 0) r.Table(new[] { "Chick type", "Chicks", "Billed", "Last hatch" }, rows, new[] { "", "num", "num", "" });
            }
        }
        if (m.Poultry != null)
            r.Text(Bold(m.Poultry.Name) + " — poultry products supplied: " + Bold(Inr(D(m.Poultry.Row, "Billed"))) + ", last DM " + Dmy(S(m.Poultry.Row, "LastBillDate")) + ".");
        r.Suggest("Outstanding of " + (m.Chick != null ? m.Chick.Name : m.Poultry.Name));
    }

    // ================================================================== dues summaries

    private static void ChickDues(Query q, Reply r)
    {
        q.ContextDomain = "chick";
        string station = q.Station;
        if (q.ChickType != null) { ChickTypeDues(q, r, station); return; }

        var sets = Exec("dbo.usp_ChickOS_Summary", c => { Str(c, "@Station", 50, station); c.Parameters.Add("@AsOf", SqlDbType.Date).Value = Today; });
        var k = First(sets[0]);
        var rows = sets[1].Where(x => D(x, "Outstanding") > 0).ToList();
        string where = station != null ? " in " + station : "";

        if (q.OverDays > 0)
        {
            OverDaysAnswer(r, "Chick", where, rows, k, q.OverDays, "hatch date");
            r.Link("Open chick outstanding", "ChickOutstanding.aspx");
            r.Suggest("Broiler dues over " + q.OverDays + " days"); r.Suggest("Layer dues over " + q.OverDays + " days"); r.Suggest("Top 10 chick dues");
            return;
        }
        decimal os = D(k, "Outstanding");
        r.Text("Chick outstanding" + where + ": " + Bold(Inr(os)) + " from " + N(D(k, "CustomersWithDue")) + " customers, as on " + LongDate(Today) +
               ". Over 90 days: " + Inr(D(k, "B3") + D(k, "B4")) + " (" + Pct(D(k, "B3") + D(k, "B4"), os) + ").");
        r.Stats(BucketStats(k), "Aged from the hatch date");
        TopDueTable(r, rows, q.TopN, "Station");
        r.Link("Open chick outstanding", "ChickOutstanding.aspx");
        r.Suggest("Broiler dues over 90 days"); r.Suggest("Layer dues"); r.Suggest("Top 10 poultry dues");
    }

    private static void ChickTypeDues(Query q, Reply r, string station)
    {
        var ty = q.ChickType;
        var sets = Exec("dbo.usp_ChickType_Summary", c => { Str(c, "@Station", 50, station); c.Parameters.Add("@AsOf", SqlDbType.Date).Value = Today; });
        var t = sets[0].FirstOrDefault(x => S(x, "ChickType") == ty.Name);
        string where = station != null ? " in " + station : "";
        if (t == null) { r.Text("There are no " + ty.Name.ToLower() + " bills" + where + "."); return; }
        var rows = sets[1].Where(x => D(x, ty.P + "OS") > 0)
                          .Select(x => new { x, due = D(x, ty.P + "OS"), days = I(x, ty.P + "Days") }).ToList();

        if (q.OverDays > 0)
        {
            int n = q.OverDays;
            var old = rows.Where(x => x.days > n).OrderByDescending(x => x.due).ToList();
            decimal olderAmt = BucketsOver(t, n);
            r.Text(ty.Name + " dues" + where + " older than " + n + " days: " + Bold(Plural(old.Count, "customer")) +
                   (olderAmt >= 0 ? ", " + Bold(Inr(olderAmt)) + " in supplies older than " + n + " days" : "") + ".");
            r.Table(new[] { "Customer", "Station", "Due", "Oldest", "Last hatch" },
                old.Take(q.TopN).Select(x => new object[] { S(x.x, "CName"), S(x.x, "Area"), Inr(x.due), x.days + " d", Dmy(S(x.x, ty.P + "Last")) }).ToList(),
                new[] { "", "", "num", "num", "" });
        }
        else
        {
            r.Text(ty.Name + " outstanding" + where + ": " + Bold(Inr(D(t, "Outstanding"))) + " from " + N(D(t, "WithDue")) + " customers. Last " +
                   ty.Name.ToLower() + " hatch supplied " + Dmy(S(t, "LastSupply")) + ".");
            r.Stats(BucketStats(t), "Aged from the hatch date");
            r.Table(new[] { "Customer", "Station", "Due", "Oldest", "Last hatch" },
                rows.OrderByDescending(x => x.due).Take(q.TopN).Select(x => new object[] { S(x.x, "CName"), S(x.x, "Area"), Inr(x.due), x.days + " d", Dmy(S(x.x, ty.P + "Last")) }).ToList(),
                new[] { "", "", "num", "num", "" });
        }
        r.Link("Open chick type-wise", "ChickTypes.aspx");
        foreach (var o in ChickTypes) if (o.Name != ty.Name && o.P != "Ot") r.Suggest(o.Name + " dues");
    }

    private static void PoultryDues(Query q, Reply r)
    {
        q.ContextDomain = "poultry";
        string area = q.PoultryArea;
        var sets = Exec("dbo.usp_CustOS_Summary", c =>
        {
            c.Parameters.Add("@Kind", SqlDbType.VarChar, 10).Value = "POULTRY";
            Str(c, "@Session", 50, null); Str(c, "@AreaCode", 50, area);
            c.Parameters.Add("@AsOf", SqlDbType.Date).Value = Today; c.Parameters.Add("@AuthOnly", SqlDbType.Bit).Value = false;
        });
        var k = First(sets[0]);
        var rows = sets[1].Where(x => D(x, "Outstanding") > 0).ToList();
        string where = area != null ? " in " + AreaName(area) : "";
        if (q.OverDays > 0)
        {
            OverDaysAnswer(r, "Poultry products", where, rows, k, q.OverDays, "DM date");
            r.Link("Open poultry outstanding", "PoultryOutstanding.aspx");
            r.Suggest("Top 10 poultry dues"); r.Suggest("Chick dues over " + q.OverDays + " days");
            return;
        }
        decimal os = D(k, "Outstanding");
        r.Text("Poultry products outstanding" + where + ": " + Bold(Inr(os)) + " from " + N(D(k, "CustomersWithDue")) + " customers. Over 90 days: " +
               Inr(D(k, "B3") + D(k, "B4")) + " (" + Pct(D(k, "B3") + D(k, "B4"), os) + ").");
        r.Stats(BucketStats(k), "Aged from the DM date");
        TopDueTable(r, rows, q.TopN, "Area");
        r.Link("Open poultry outstanding", "PoultryOutstanding.aspx");
        r.Suggest("Poultry dues over 180 days"); r.Suggest("Top 10 chick dues");
    }

    private static void OverDaysAnswer(Reply r, string what, string where, List<Dictionary<string, object>> rows, Dictionary<string, object> k, int n, string ageFrom)
    {
        var old = rows.Where(x => I(x, "MaxDays") > n).OrderByDescending(x => D(x, "Outstanding")).ToList();
        decimal olderAmt = BucketsOver(k, n);
        r.Text(what + " dues" + where + " with supplies older than " + n + " days (from the " + ageFrom + "): " + Bold(Plural(old.Count, "customer")) +
               (olderAmt >= 0 ? ", " + Bold(Inr(olderAmt)) + " of dues are that old" : "") + ".");
        r.Table(new[] { "Customer", "Total due", "Oldest", "Last payment" },
            old.Take(10).Select(x => new object[] { S(x, "CName") + (S(x, "Area") != "" ? ", " + S(x, "Area") : ""), Inr(D(x, "Outstanding")), I(x, "MaxDays") + " d",
                S(x, "LastPayDate") != "" ? Dmy(S(x, "LastPayDate")) : "none" }).ToList(),
            new[] { "", "num", "num", "" });
    }

    private static void TopDueTable(Reply r, List<Dictionary<string, object>> rows, int n, string areaLabel)
    {
        r.Table(new[] { "Customer", areaLabel, "Due", "Oldest" },
            rows.OrderByDescending(x => D(x, "Outstanding")).Take(n)
                .Select(x => new object[] { S(x, "CName"), S(x, "Area"), Inr(D(x, "Outstanding")), I(x, "MaxDays") + " d" }).ToList(),
            new[] { "", "", "num", "num" });
    }

    private static void Collections(Query q, Reply r)
    {
        var lines = new List<object[]>();
        if (!q.Poultry || q.Chick)
        {
            var k = First(Exec("dbo.usp_ChickOS_Summary", c => { Str(c, "@Station", 50, q.Station); c.Parameters.Add("@AsOf", SqlDbType.Date).Value = Today; })[0]);
            lines.Add(new object[] { "Chicks (ledger, this FY)", Inr(D(k, "Received")), Inr(D(k, "Billed")), Pct(D(k, "Received"), D(k, "Billed")) });
        }
        if (q.Poultry || !q.Chick)
        {
            var k = First(Exec("dbo.usp_CustOS_Summary", c =>
            {
                c.Parameters.Add("@Kind", SqlDbType.VarChar, 10).Value = "POULTRY"; Str(c, "@Session", 50, null); Str(c, "@AreaCode", 50, q.PoultryArea);
                c.Parameters.Add("@AsOf", SqlDbType.Date).Value = Today; c.Parameters.Add("@AuthOnly", SqlDbType.Bit).Value = false;
            })[0]);
            lines.Add(new object[] { "Poultry products (all time)", Inr(D(k, "Received")), Inr(D(k, "Billed")), Pct(D(k, "Received"), D(k, "Billed")) });
        }
        if (q.Period.Given)
        {
            // payments inside a period: from the sales dashboards, which filter receipts by date
            if (!q.Poultry || q.Chick)
            {
                var cs = ChickSalesSets(q);
                if (cs != null) lines.Add(new object[] { "Chick receipts " + q.Period.Label, Inr(D(First(cs[0]), "ReceiptAmt")), "", "" });
            }
            if (q.Poultry || !q.Chick)
            {
                var ps = PoultrySalesSets(q);
                if (ps != null) lines.Add(new object[] { "Poultry receipts " + q.Period.Label, Inr(D(First(ps[0]), "ReceiptAmt")), "", "" });
            }
        }
        r.Text("Payments received:");
        r.Table(new[] { "", "Received", "Billed", "Collected" }, lines, new[] { "", "num", "num", "num" });
        r.Suggest("Top 10 chick dues"); r.Suggest("Payments received this month");
    }

    // ================================================================== hatch (no customer)

    private static void OverallHatch(Query q, Reply r)
    {
        q.ContextDomain = "chick";
        var sets = Exec("dbo.usp_ChickType_Summary", c => { Str(c, "@Station", 50, q.Station); c.Parameters.Add("@AsOf", SqlDbType.Date).Value = Today; });
        var rows = new List<object[]>();
        foreach (var t in sets[0])
            if (S(t, "ChickType") != "Other")
                rows.Add(new object[] { S(t, "ChickType"), Dmy(S(t, "LastSupply")), DaysAgo(S(t, "LastSupply")), N(D(t, "Customers")) });
        r.Text("Latest hatch supplied for each chick type" + (q.Station != null ? " in " + q.Station : "") + ":");
        r.Table(new[] { "Chick type", "Last hatch", "", "Customers" }, rows, new[] { "", "", "", "num" });

        int gap = q.OverDays > 0 ? q.OverDays : 60;
        var stale = sets[1].Where(x => D(x, "Outstanding") > 0 && S(x, "LastHatch") != "" && DaysSince(S(x, "LastHatch")) > gap)
                           .OrderByDescending(x => D(x, "Outstanding")).ToList();
        if (stale.Count > 0)
        {
            r.Text(Plural(stale.Count, "customer") + " with dues " + (stale.Count == 1 ? "has" : "have") + " had no hatch for more than " + gap + " days:");
            r.Table(new[] { "Customer", "Last hatch", "Due" },
                stale.Take(q.TopN).Select(x => new object[] { S(x, "CName"), Dmy(S(x, "LastHatch")) + " (" + DaysSince(S(x, "LastHatch")) + " d)", Inr(D(x, "Outstanding")) }).ToList(),
                new[] { "", "", "num" });
        }
        r.Link("Open chick type-wise", "ChickTypes.aspx");
        r.Suggest("Broiler dues"); r.Suggest("Last hatch of " + (sets[1].Count > 0 ? S(sets[1][0], "CName") : "Royal"));
    }

    // ================================================================== sales

    private static List<List<Dictionary<string, object>>> ChickSalesSets(Query q)
    {
        string session = PickSession("dbo.usp_ChickDash_Filters", q.Period);
        if (session == null) return null;
        return Exec("dbo.usp_ChickDash_Data", c =>
        {
            Str(c, "@Session", 50, session); Str(c, "@AreaCode", 50, null); Str(c, "@ChickType", 20, q.ChickType != null && q.ChickType.P != "Ot" ? q.ChickType.Name : null);
            c.Parameters.Add("@FromDate", SqlDbType.Date).Value = q.Period.From; c.Parameters.Add("@ToDate", SqlDbType.Date).Value = q.Period.To;
        });
    }

    private static void ChickSales(Query q, Reply r)
    {
        q.ContextDomain = "chick";
        var sets = ChickSalesSets(q);
        if (sets == null) { r.Text("No chick sales sessions found."); return; }
        var k = First(sets[0]);
        string what = q.ChickType != null ? q.ChickType.Name + " chick" : "Chick";
        r.Text(what + " sales " + q.Period.Label + ": " + Bold(Inr(D(k, "SalesAmt"))) + " for " + N(D(k, "NetChicks")) + " net chicks to " +
               N(D(k, "CustomerCount")) + " customers (average ₹" + D(k, "AvgRate").ToString("0.00", IN) + " a chick, mortality " + D(k, "MortalityPct").ToString("0.0", IN) + "%).");
        if (q.ChickType == null)
            r.Table(new[] { "Chick type", "Net chicks", "Sales", "Avg rate" },
                sets[1].Where(x => D(x, "SalesAmt") > 0).Select(x => new object[] { S(x, "ChickType"), N(D(x, "NetChicks")), Inr(D(x, "SalesAmt")), D(x, "AvgRate").ToString("0.00", IN) }).ToList(),
                new[] { "", "num", "num", "num" });
        var top = sets.Count > 6 ? sets[6].OrderByDescending(x => D(x, "SalesAmt")).Take(q.TopN).ToList() : new List<Dictionary<string, object>>();
        if (top.Count > 0)
            r.Table(new[] { "Top customers", "Net chicks", "Sales" },
                top.Select(x => new object[] { S(x, "CName") + (S(x, "Area") != "" ? ", " + S(x, "Area") : ""), N(D(x, "NetChicks")), Inr(D(x, "SalesAmt")) }).ToList(),
                new[] { "", "num", "num" });
        r.Link("Open chick sales dashboard", "Default.aspx");
        r.Suggest("Broiler sales last month"); r.Suggest("Chick sales this FY");
    }

    private static List<List<Dictionary<string, object>>> PoultrySalesSets(Query q)
    {
        string session = PickSession("dbo.usp_PoultryDash_Filters", q.Period);
        if (session == null) return null;
        return Exec("dbo.usp_PoultryDash_Data", c =>
        {
            Str(c, "@Session", 50, session); Str(c, "@AreaCode", 50, q.PoultryArea); Str(c, "@Product", 200, q.Product);
            c.Parameters.Add("@FromDate", SqlDbType.Date).Value = q.Period.From; c.Parameters.Add("@ToDate", SqlDbType.Date).Value = q.Period.To;
        });
    }

    private static void PoultrySales(Query q, Reply r, bool productsFirst)
    {
        q.ContextDomain = "poultry";
        var sets = PoultrySalesSets(q);
        if (sets == null) { r.Text("No poultry sales sessions found."); return; }
        var k = First(sets[0]);
        string what = q.Product != null ? q.Product : "Poultry products";
        r.Text(what + " sales " + q.Period.Label + (q.PoultryArea != null ? " in " + AreaName(q.PoultryArea) : "") + ": " + Bold(Inr(D(k, "Sales"))) + " in " +
               N(D(k, "DMCount")) + " DMs to " + N(D(k, "Customers")) + " customers" +
               (D(k, "QtyKg") > 0 ? ", " + Kg(D(k, "QtyKg")) : "") + (D(k, "QtyNos") > 0 ? ", " + N(D(k, "QtyNos")) + " nos" : "") + ".");
        if (q.Product == null && sets.Count > 1)
            r.Table(new[] { "Top products", "Quantity", "Sales" },
                sets[1].Take(q.TopN).Select(x => new object[] { S(x, "Product"), D(x, "QtyKg") > 0 ? Kg(D(x, "QtyKg")) : N(D(x, "QtyNos")) + " nos", Inr(D(x, "Sales")) }).ToList(),
                new[] { "", "num", "num" });
        if (!productsFirst && sets.Count > 7)
            r.Table(new[] { "Top customers", "Sales" },
                sets[7].Where(x => D(x, "Sales") > 0).Take(Math.Min(q.TopN, 5)).Select(x => new object[] { S(x, "CName") + (S(x, "Area") != "" ? ", " + S(x, "Area") : ""), Inr(D(x, "Sales")) }).ToList(),
                new[] { "", "num" });
        r.Link("Open poultry sales dashboard", "PoultrySales.aspx");
        r.Suggest("Top poultry products last month"); r.Suggest("Feed sales this FY");
    }

    // ================================================================== feed review

    private static void FeedReview(Query q, Reply r, bool bySalesperson, bool duesOnly, bool top)
    {
        q.ContextDomain = "feed";
        string grp = q.FeedGroup;
        var sets = Exec("dbo.usp_FeedReview", c =>
        {
            c.Parameters.Add("@From", SqlDbType.Date).Value = q.Period.From; c.Parameters.Add("@To", SqlDbType.Date).Value = q.Period.To;
            Str(c, "@AreaCode", 50, q.PoultryArea); Str(c, "@FeedGroup", 20, grp);
        });
        var k = First(sets[0]);
        string what = (grp != null ? grp + " feed" : "Feed");

        if (bySalesperson)
        {
            if (D(k, "SalespersonRows") == 0)
            {
                r.Text("Salespeople aren't set up yet. Add each customer code (or area) and its salesperson to the table dbo.FeedSalesperson, and I'll show them here.");
                return;
            }
            r.Text(what + " sales by salesperson " + q.Period.Label + ":");
            r.Table(new[] { "Salesperson", "Sales", "Share", "Outstanding", "O/S % of sales" },
                sets[4].Select(x => new object[] { S(x, "Salesperson"), Inr(D(x, "Sales")), Pct(D(x, "Sales"), D(k, "Sales")), Inr(D(x, "Outstanding")), Pct(D(x, "Outstanding"), D(x, "Sales")) }).ToList(),
                new[] { "", "num", "num", "num", "num" });
        }
        else if (duesOnly)
        {
            var dues = sets[5].Where(x => D(x, "Outstanding") > 0).OrderByDescending(x => D(x, "Outstanding")).ToList();
            r.Text("Feed customers' outstanding as on " + LongDate(q.Period.To) + ": " + Bold(Inr(D(k, "Outstanding"))) + " from " + Plural(dues.Count, "customer") + " (all poultry products).");
            r.Table(new[] { "Customer", "Outstanding", "Feed billed in period", "Last feed bill" },
                dues.Take(q.TopN).Select(x => new object[] { S(x, "CName") + (S(x, "Area") != "" ? ", " + S(x, "Area") : ""), Inr(D(x, "Outstanding")), Inr(D(x, "Sales")), Dmy(S(x, "LastFeedDate")) }).ToList(),
                new[] { "", "num", "num", "" });
        }
        else
        {
            var months = sets[1];
            var best = months.OrderByDescending(x => D(x, "Sales")).FirstOrDefault();
            r.Text(what + " sales " + q.Period.Label + ": " + Bold(Inr(D(k, "Sales"))) + " — " + Kg(D(k, "QtyKg")) + " (" + N(D(k, "QtyKg") / 1000m) + " MT) to " +
                   N(D(k, "Customers")) + " customers." + (best != null && months.Count > 1 ? " Best month: " + MonthName(S(best, "MonthStart")) + " at " + Inr(D(best, "Sales")) + "." : "") +
                   " Top 10 customers took " + D(k, "Top10QtyShare").ToString("0", IN) + "% of the quantity.");
            if (!top && grp == null && sets[2].Count > 0)
                r.Stats(sets[2].Select(x => new KeyValuePair<string, string>(S(x, "Grp"), Inr(D(x, "Sales")) + " · " + Pct(D(x, "Sales"), D(k, "Sales")))).ToList(), null);
            r.Table(new[] { "Top buyers by quantity", "Quantity", "Sales" },
                sets[5].Where(x => D(x, "QtyKg") > 0).OrderByDescending(x => D(x, "QtyKg")).Take(q.TopN)
                       .Select(x => new object[] { S(x, "CName") + (S(x, "Area") != "" ? ", " + S(x, "Area") : ""), Kg(D(x, "QtyKg")), Inr(D(x, "Sales")) }).ToList(),
                new[] { "", "num", "num" });
        }
        r.Link("Open feed review", "FeedReview.aspx");
        r.Suggest("Feed sales by salesperson"); r.Suggest("Feed customers outstanding"); r.Suggest("Layer feed sales last month");
    }

    // ================================================================== customers: lookup

    private class CustRef
    {
        public string Key, Code, Name, Area, Domain;
        public Dictionary<string, object> Row;
        public string[] Tokens;
    }

    private class CustMatch
    {
        public CustRef Chick, Poultry;
        public List<CustRef> Ambiguous = new List<CustRef>();
    }

    private static List<CustRef> ChickCustomers()
    {
        return Cached("chat-chick-cust", () =>
        {
            var rows = Exec("dbo.usp_ChickOS_Summary", c => { Str(c, "@Station", 50, null); c.Parameters.Add("@AsOf", SqlDbType.Date).Value = Today; })[1];
            return rows.Select(x => MakeRef(x, "chick")).ToList();
        });
    }

    private static List<CustRef> PoultryCustomers()
    {
        return Cached("chat-poultry-cust", () =>
        {
            var rows = Exec("dbo.usp_CustOS_Summary", c =>
            {
                c.Parameters.Add("@Kind", SqlDbType.VarChar, 10).Value = "POULTRY"; Str(c, "@Session", 50, null); Str(c, "@AreaCode", 50, null);
                c.Parameters.Add("@AsOf", SqlDbType.Date).Value = Today; c.Parameters.Add("@AuthOnly", SqlDbType.Bit).Value = false;
            })[1];
            return rows.Select(x => MakeRef(x, "poultry")).ToList();
        });
    }

    private static Dictionary<string, object> ChickTypeRow(string accCode)
    {
        var rows = Cached("chat-chick-types", () =>
            Exec("dbo.usp_ChickType_Summary", c => { Str(c, "@Station", 50, null); c.Parameters.Add("@AsOf", SqlDbType.Date).Value = Today; })[1]);
        return rows.FirstOrDefault(x => S(x, "CustKey") == accCode);
    }

    private static CustRef MakeRef(Dictionary<string, object> x, string domain)
    {
        return new CustRef
        {
            Key = S(x, "CustKey"), Code = S(x, "Code"), Name = S(x, "CName"), Area = S(x, "Area"), Domain = domain, Row = x,
            Tokens = Tokenize(S(x, "CName"))
        };
    }

    private static CustMatch FindByKey(string key)
    {
        var m = new CustMatch();
        m.Chick = ChickCustomers().FirstOrDefault(c => c.Key == key);
        m.Poultry = PoultryCustomers().FirstOrDefault(c => c.Key == key);
        return m;
    }

    private static CustMatch FindCustomers(Query q)
    {
        var m = new CustMatch();
        if (q.NameWords.Length == 0) return m;
        var chick = ChickCustomers();
        var poultry = PoultryCustomers();

        // words that appear in many names ("poultry", "farm", "traders") don't identify anyone
        var df = new Dictionary<string, int>();
        foreach (var c in chick.Concat(poultry))
            foreach (var t in c.Tokens.Distinct())
                df[t] = (df.ContainsKey(t) ? df[t] : 0) + 1;
        int total = Math.Max(1, chick.Count + poultry.Count);
        int common = Math.Max(4, (int)(total * 0.08));

        Func<List<CustRef>, List<KeyValuePair<CustRef, double>>> score = list =>
        {
            var res = new List<KeyValuePair<CustRef, double>>();
            foreach (var c in list)
            {
                if (c.Code != "" && q.Words.Contains(Norm(c.Code))) { res.Add(new KeyValuePair<CustRef, double>(c, 10)); continue; }
                var rare = c.Tokens.Where(t => t.Length >= 3 && !Stop.Contains(t) && (df.ContainsKey(t) ? df[t] : 0) <= common).ToList();
                if (rare.Count == 0) continue;
                int hit = rare.Count(t => q.NameWords.Any(w => w == t || (w.Length >= 4 && t.Length >= 4 && (t.StartsWith(w) || w.StartsWith(t)))));
                if (hit == 0) continue;
                double s = hit + 0.5 * hit / rare.Count;
                res.Add(new KeyValuePair<CustRef, double>(c, s));
            }
            return res.OrderByDescending(p => p.Value).ToList();
        };

        var sc = score(chick);
        var sp = score(poultry);
        double best = Math.Max(sc.Count > 0 ? sc[0].Value : 0, sp.Count > 0 ? sp[0].Value : 0);
        if (best < 1) return m;

        // several different customers equally good -> ask
        var tops = sc.Concat(sp).Where(p => p.Value >= best - 0.001).Select(p => p.Key)
                     .GroupBy(c => Norm(c.Name)).Select(g => g.First()).ToList();
        if (tops.Count > 1) { m.Ambiguous = tops; return m; }

        string name = Norm(tops[0].Name);
        bool dc, dp, dfd;
        q.DomainsIgnoring(tops[0].Tokens, out dc, out dp, out dfd);
        bool chickOnly = dc && !dp && !dfd, poultryOnly = (dp || dfd) && !dc;
        if (!poultryOnly) m.Chick = sc.Where(p => p.Value >= best - 0.001 && Norm(p.Key.Name) == name).Select(p => p.Key).FirstOrDefault()
                                    ?? (sc.Count > 0 && sc[0].Value >= best - 0.001 ? sc[0].Key : null);
        if (!chickOnly) m.Poultry = sp.Where(p => p.Value >= best - 0.001 && Norm(p.Key.Name) == name).Select(p => p.Key).FirstOrDefault()
                                    ?? (sp.Count > 0 && sp[0].Value >= best - 0.001 ? sp[0].Key : null);
        // asked about one side but the customer only exists on the other: still return them
        if (m.Chick == null && m.Poultry == null)
        {
            m.Chick = sc.Where(p => p.Value >= best - 0.001).Select(p => p.Key).FirstOrDefault();
            m.Poultry = sp.Where(p => p.Value >= best - 0.001).Select(p => p.Key).FirstOrDefault();
        }
        return m;
    }

    // ================================================================== question parsing

    private class ChickType { public string P, Name; public string[] Words; }
    private static readonly ChickType[] ChickTypes =
    {
        new ChickType { P = "Br", Name = "Broiler", Words = new[] { "broiler", "broilers", "bronix" } },
        new ChickType { P = "Ly", Name = "Layer", Words = new[] { "layer", "layers", "laynix" } },
        new ChickType { P = "Ck", Name = "Cockrel", Words = new[] { "cockrel", "cockerel", "cockrels", "cockerels", "cock" } },
        new ChickType { P = "Ot", Name = "Other", Words = new[] { "opening balance" } }
    };

    private static readonly HashSet<string> Stop = new HashSet<string>(new[]
    {
        "what", "whats", "is", "the", "of", "for", "how", "much", "many", "show", "me", "tell", "give", "list", "please", "pls", "a", "an", "to", "in",
        "on", "and", "by", "with", "from", "since", "till", "until", "at", "as", "all", "my", "our", "this", "that", "last", "next", "current", "previous",
        "kitna", "kitni", "kitne", "hai", "he", "ka", "ki", "ke", "ko", "se", "kya", "batao", "bata", "dikhao", "mera", "hamara", "kab", "tak", "wala", "wale",
        "outstanding", "due", "dues", "balance", "baki", "baaki", "bakaya", "udhaar", "udhar", "owe", "owes", "pending", "aging", "ageing", "overdue",
        "hatch", "hatching", "date", "dates", "supply", "supplied", "sale", "sales", "sold", "payment", "payments", "receipt", "receipts", "received",
        "paid", "collection", "customer", "customers", "party", "account", "top", "days", "day", "din", "month", "months", "year", "years", "fy",
        "today", "yesterday", "quarter", "week", "chick", "chicks", "poultry", "product", "products", "feed", "broiler", "layer", "cockrel", "cockerel",
        "farm", "farms", "and", "co", "m", "s", "ms", "mr", "shri", "sri", "over", "above", "older", "than", "more", "less", "about", "who", "which",
        "where", "when", "aakhri", "akhri", "dashboard", "status", "report", "details", "detail", "plus", "ago", "since", "upto", "bill", "bills",
        "sale", "dm", "dms", "lakh", "crore", "rs", "rupees", "amount", "value", "average", "avg", "rate", "quantity", "qty", "kg", "nos", "mt", "uska", "unka", "iska", "their", "his", "her", "its", "same", "also", "again", "now", "total"
    });

    private class Period
    {
        public DateTime From, To;
        public string Label;
        public bool Given;
    }

    private class Query
    {
        public string Raw, Text;
        public string[] Words, NameWords;
        public bool IsEmpty, IsGreetingOnly, IsFollowUp, Chick, Poultry, Feed, LooksLikeName;
        public string LeftoverText;
        public ChickType ChickType;
        public string FeedGroup, Station, PoultryArea, Product;
        public int OverDays, TopN = 10;
        public Period Period;
        public string CtxCustomer, ContextCustomer, ContextDomain;

        public Query(string raw, Dictionary<string, object> ctx)
        {
            Raw = raw.Trim();
            if (Raw.Length > 300) Raw = Raw.Substring(0, 300);
            Text = " " + Norm(Raw) + " ";
            Words = Text.Split(new[] { ' ' }, StringSplitOptions.RemoveEmptyEntries);
            IsEmpty = Words.Length == 0;
            IsGreetingOnly = Words.Length <= 3 && Words.All(w => new[] { "hi", "hello", "hey", "namaste", "namaskar", "good", "morning", "evening", "afternoon", "ji", "sir" }.Contains(w));

            if (ctx != null)
            {
                object o;
                if (ctx.TryGetValue("customer", out o) && o != null && Convert.ToString(o) != "") CtxCustomer = Convert.ToString(o);
                if (ctx.TryGetValue("domain", out o) && o != null) ContextDomain = Convert.ToString(o);
            }
            ContextCustomer = CtxCustomer;

            Domains(Text, out Chick, out Poultry, out Feed);

            if (!Feed) foreach (var t in ChickTypes) if (t.P != "Ot" && Any(t.Words)) { ChickType = t; break; }
            if (Any("opening balance", "opening dues", "other dues")) ChickType = ChickTypes[3];
            if (Feed)
            {
                if (Any("broiler", "bronix")) FeedGroup = "Broiler";
                else if (Any("layer", "laynix")) FeedGroup = "Layer";
                else if (Any("sonali")) FeedGroup = "Sonali";
            }

            var m = Regex.Match(Text, @"\b(?:over|above|more than|older than|beyond|greater than|se zyada|se jyada|se upar|purana|purane)\s*(\d{1,3})\b");
            if (!m.Success) m = Regex.Match(Text, @"\b(\d{1,3})\s*(?:\+|plus)?\s*(?:days|din)\s*(?:se\s*)?(?:old|older|purana|purane|zyada|jyada|above|over)\b");
            if (!m.Success) m = Regex.Match(Text, @"\b(\d{2,3}) plus\b");
            if (m.Success) OverDays = int.Parse(m.Groups[1].Value);
            if (OverDays == 0 && Regex.IsMatch(Raw, @"\b(90|180|60|30)\s*\+")) OverDays = int.Parse(Regex.Match(Raw, @"\b(90|180|60|30)\s*\+").Groups[1].Value);

            var tn = Regex.Match(Text, @"\btop\s*(\d{1,2})\b");
            if (tn.Success) TopN = Math.Max(1, Math.Min(25, int.Parse(tn.Groups[1].Value)));

            Period = ParsePeriod(Text, Raw);

            FindPlaces();

            // follow-up about the previous customer: the question refers back ("uska payment", "what about their hatch"),
            // or it is very short and names nothing else ("payments?", "last hatch")
            bool refersBack = Any("uska", "unka", "iska", "inka", "their", "his", "her", "its", "same customer", "this customer", "that customer",
                                  "what about", "and his", "and their", "aur uska", "same party");
            bool aggregate = Any("dates", "customers", "all", "total", "overall", "sab", "list", "summary", "top", "parties");
            IsFollowUp = refersBack || (Words.Length <= 3 && !aggregate && ChickType == null && OverDays == 0 && !Period.Given &&
                                        Station == null && PoultryArea == null && Product == null && !Feed);

            // leftover words (possible customer name the parser didn't recognise)
            // words that could be part of a customer's name (not question words, numbers or months)
            NameWords = Words.Where(w => !Stop.Contains(w) && !Regex.IsMatch(w, @"^\d+\+?$") && !MonthWords.ContainsKey(w) && w.Length >= 2).ToArray();
            var left = NameWords.Where(w => w.Length >= 3).ToList();
            var placeAll = new List<string>();
            if (Station != null) placeAll.AddRange(Tokenize(Station));
            if (PoultryArea != null) placeAll.AddRange(Tokenize(AreaName(PoultryArea)));
            NameWords = NameWords.Where(w => !placeAll.Contains(w)).ToArray();
            var placeWords = new List<string>();
            if (Station != null) placeWords.AddRange(Tokenize(Station));
            if (PoultryArea != null) placeWords.AddRange(Tokenize(AreaName(PoultryArea)));
            if (Product != null) placeWords.AddRange(Tokenize(Product));
            left = left.Where(w => !placeWords.Contains(w)).ToList();
            LooksLikeName = left.Count > 0;
            LeftoverText = string.Join(" ", left);
        }

        public bool Any(params string[] words) { return Has(Text, words); }

        /// <summary>Chick / poultry / feed flags of the question with some words (a customer's name) taken out.</summary>
        public void DomainsIgnoring(string[] nameTokens, out bool chick, out bool poultry, out bool feed)
        {
            var keep = Words.Where(w => !nameTokens.Contains(w));
            Domains(" " + string.Join(" ", keep) + " ", out chick, out poultry, out feed);
        }

        private void FindPlaces()
        {
            // chick stations (PrintData.Station) and poultry areas, matched as whole words
            foreach (var st in ChickStations())
                if (st.Length >= 3 && Text.IndexOf(" " + Norm(st) + " ", StringComparison.Ordinal) >= 0) { Station = st; break; }
            foreach (var a in PoultryAreas())
            {
                string n = Norm(a.Value), code = Norm(a.Key);
                if ((n.Length >= 3 && Text.IndexOf(" " + n + " ", StringComparison.Ordinal) >= 0) || (code.Length >= 2 && Text.IndexOf(" area " + code + " ", StringComparison.Ordinal) >= 0))
                { PoultryArea = a.Key; break; }
            }
            foreach (var p in PoultryProducts())
            {
                string n = Norm(p);
                if (n.Length >= 4 && Text.IndexOf(" " + n + " ", StringComparison.Ordinal) >= 0) { Product = p; break; }
            }
        }
    }

    private static bool Has(string text, params string[] words)
    {
        foreach (var w in words) if (text.IndexOf(" " + w + " ", StringComparison.Ordinal) >= 0) return true;
        return false;
    }

    private static void Domains(string text, out bool chick, out bool poultry, out bool feed)
    {
        feed = Has(text, "feed", "dana", "crumb", "crumbs", "mash", "pellet", "bronix", "laynix", "sonali");
        chick = !feed && Has(text, "chick", "chicks", "chuza", "chooza", "broiler", "broilers", "layer", "layers", "cockrel", "cockerel", "hatch");
        // a bare "poultry" is part of many customer names, so only explicit phrases count
        poultry = Has(text, "poultry product", "poultry products", "medicine", "medicines", "vaccine", "vaccines", "equipment", "product", "products",
                            "poultry dues", "poultry due", "poultry outstanding", "poultry sales", "poultry sale", "poultry customers", "poultry payments",
                            "poultry balance", "poultry aging", "poultry ageing")
                  || Regex.IsMatch(text, @"^\s*poultry\b");
    }

    private static readonly Dictionary<string, int> MonthWords = new Dictionary<string, int>
    {
        { "jan", 1 }, { "january", 1 }, { "feb", 2 }, { "february", 2 }, { "mar", 3 }, { "march", 3 }, { "apr", 4 }, { "april", 4 },
        { "may", 5 }, { "jun", 6 }, { "june", 6 }, { "jul", 7 }, { "july", 7 }, { "aug", 8 }, { "august", 8 }, { "sep", 9 }, { "sept", 9 },
        { "september", 9 }, { "oct", 10 }, { "october", 10 }, { "nov", 11 }, { "november", 11 }, { "dec", 12 }, { "december", 12 }
    };

    private static Period ParsePeriod(string text, string raw)
    {
        DateTime t = Today, fy = FyStart(t);
        Func<DateTime, DateTime, string, Period> P = (f, to, l) => new Period { From = f, To = to > t ? t : to, Label = l, Given = true };

        var rm = Regex.Match(raw, @"(\d{1,2})[-/.](\d{1,2})[-/.](\d{2,4})\s*(?:to|till|until|-|se|tak|and)\s*(\d{1,2})[-/.](\d{1,2})[-/.](\d{2,4})", RegexOptions.IgnoreCase);
        if (rm.Success)
        {
            DateTime a, b;
            if (TryDmy(rm.Groups[1].Value, rm.Groups[2].Value, rm.Groups[3].Value, out a) && TryDmy(rm.Groups[4].Value, rm.Groups[5].Value, rm.Groups[6].Value, out b))
            {
                if (a > b) { var x = a; a = b; b = x; }
                return P(a, b, "from " + Short(a) + " to " + Short(b));
            }
        }
        var single = Regex.Match(raw, @"\bon\s+(\d{1,2})[-/.](\d{1,2})[-/.](\d{2,4})");
        if (single.Success)
        {
            DateTime a;
            if (TryDmy(single.Groups[1].Value, single.Groups[2].Value, single.Groups[3].Value, out a)) return P(a, a, "on " + Short(a));
        }
        Func<string, bool> has = w => text.IndexOf(" " + w + " ", StringComparison.Ordinal) >= 0;

        if (has("today") || has("aaj")) return P(t, t, "today");
        if (has("yesterday")) return P(t.AddDays(-1), t.AddDays(-1), "yesterday");
        if (has("this week") || has("is hafte")) { var ws = t.AddDays(-(((int)t.DayOfWeek + 6) % 7)); return P(ws, t, "this week"); }
        if (has("this month") || has("is mahine") || has("is month") || has("current month") || has("mtd")) return P(new DateTime(t.Year, t.Month, 1), t, "this month");
        if (has("last month") || has("pichle mahine") || has("pichla mahina") || has("previous month"))
        { var lm = new DateTime(t.Year, t.Month, 1).AddMonths(-1); return P(lm, lm.AddMonths(1).AddDays(-1), "in " + lm.ToString("MMMM yyyy", IN)); }
        var nm = Regex.Match(text, @"\b(?:last|past|pichle)\s+(\d{1,2})\s+(months|month|mahine)\b");
        if (nm.Success) { int n = int.Parse(nm.Groups[1].Value); var f = new DateTime(t.Year, t.Month, 1).AddMonths(-(n - 1)); return P(f, t, "in the last " + n + " months"); }
        var nd = Regex.Match(text, @"\b(?:last|past|pichle)\s+(\d{1,3})\s+(days|day|din)\b");
        if (nd.Success) { int n = int.Parse(nd.Groups[1].Value); return P(t.AddDays(-(n - 1)), t, "in the last " + n + " days"); }
        if (has("this quarter") || has("current quarter"))
        { int q = ((t.Month + 8) % 12) / 3; var qs = fy.AddMonths(q * 3); return P(qs, t, "this quarter"); }
        if (has("last quarter") || has("previous quarter"))
        { int q = ((t.Month + 8) % 12) / 3; var qs = fy.AddMonths(q * 3).AddMonths(-3); return P(qs, qs.AddMonths(3).AddDays(-1), "last quarter"); }
        if (has("last year") || has("last fy") || has("previous year") || has("pichle saal") || has("pichla saal") || has("last financial year"))
            return P(fy.AddYears(-1), fy.AddDays(-1), "in FY " + FyLabel(fy.AddYears(-1)));

        // a month name, optionally with a year ("october", "oct 2026", "since august")
        var mm = Regex.Match(text, @"\b(" + string.Join("|", MonthWords.Keys.OrderByDescending(k => k.Length)) + @")\b(?:\s+(\d{4}))?");
        if (mm.Success && !(mm.Groups[1].Value == "may" && !Regex.IsMatch(text, @"\b(in|of|since|for|during)\s+may\b|\bmay\s+\d{4}\b")))
        {
            int mon = MonthWords[mm.Groups[1].Value];
            int year = mm.Groups[2].Success ? int.Parse(mm.Groups[2].Value) : (mon > t.Month ? t.Year - 1 : t.Year);
            var ms = new DateTime(year, mon, 1);
            if (Regex.IsMatch(text, @"\b(since|from|se)\s+" + mm.Groups[1].Value + @"\b")) return P(ms, t, "since " + ms.ToString("MMMM yyyy", IN));
            return P(ms, ms.AddMonths(1).AddDays(-1), "in " + ms.ToString("MMMM yyyy", IN));
        }
        if (has("this year") || has("this fy") || has("current year") || has("is saal") || has("ytd") || has("fy") || has("financial year"))
            return P(fy, t, "this FY (" + FyLabel(fy) + ")");

        return new Period { From = fy, To = t, Label = "this FY (" + FyLabel(fy) + ")", Given = false };
    }

    private static bool TryDmy(string d, string m, string y, out DateTime result)
    {
        int yy = int.Parse(y); if (yy < 100) yy += 2000;
        result = DateTime.MinValue;
        try { result = new DateTime(yy, int.Parse(m), int.Parse(d)); return true; } catch { return false; }
    }

    // ================================================================== reference lists (cached)

    private static List<string> ChickStations()
    {
        return Cached("chat-stations", () =>
        {
            var sets = Exec("dbo.usp_ChickType_Filters", c => { });
            return sets[0].Select(x => S(x, "Station")).Where(s => s != "").ToList();
        });
    }

    private static List<KeyValuePair<string, string>> PoultryAreas()
    {
        return Cached("chat-poultry-areas", () =>
        {
            var sets = Exec("dbo.usp_CustOS_Filters", c => { c.Parameters.Add("@Kind", SqlDbType.VarChar, 10).Value = "POULTRY"; });
            return sets[1].Select(x => new KeyValuePair<string, string>(S(x, "AreaCode"), S(x, "Area"))).ToList();
        });
    }

    private static List<string> PoultryProducts()
    {
        return Cached("chat-poultry-products", () =>
        {
            var sets = Exec("dbo.usp_PoultryDash_Filters", c => { Str(c, "@Session", 50, null); });
            return sets.Count > 2 ? sets[2].Select(x => S(x, "Product")).Where(s => s != "").ToList() : new List<string>();
        });
    }

    private static string AreaName(string code)
    {
        var a = PoultryAreas().FirstOrDefault(x => x.Key == code);
        return a.Value != null && a.Value != "" ? a.Value : code;
    }

    /// <summary>Session whose label contains the financial-year start of the period (e.g. "2026-27"); else the latest.</summary>
    private static string PickSession(string filtersProc, Period p)
    {
        var sessions = Cached("chat-sessions-" + filtersProc, () =>
            Exec(filtersProc, c => { Str(c, "@Session", 50, null); })[0].Select(x => S(x, "Session")).Where(s => s != "").ToList());
        if (sessions.Count == 0) return null;
        string y = FyStart(p.To).Year.ToString(CultureInfo.InvariantCulture);
        string y2 = y.Substring(2);
        return sessions.FirstOrDefault(s => s.StartsWith(y)) ?? sessions.FirstOrDefault(s => s.Contains(y)) ??
               sessions.FirstOrDefault(s => s.StartsWith(y2)) ?? sessions[0];
    }

    // ================================================================== data access

    /// <summary>Runs a stored procedure and returns its result sets. Replaceable so the assistant can be tested without a database.</summary>
    public static Func<string, Action<SqlCommand>, List<List<Dictionary<string, object>>>> Executor = ExecDb;

    private static List<List<Dictionary<string, object>>> Exec(string proc, Action<SqlCommand> addParams)
    {
        var sets = Executor(proc, addParams);
        while (sets.Count < 12) sets.Add(new List<Dictionary<string, object>>());
        return sets;
    }

    private static List<List<Dictionary<string, object>>> ExecDb(string proc, Action<SqlCommand> addParams)
    {
        var sets = new List<List<Dictionary<string, object>>>();
        using (var cn = new SqlConnection(DashboardRepository.ConnectionString))
        using (var cmd = new SqlCommand(proc, cn) { CommandType = CommandType.StoredProcedure, CommandTimeout = 180 })
        {
            addParams(cmd);
            cn.Open();
            using (var rd = cmd.ExecuteReader())
            {
                do { sets.Add(DashboardRepository.ReadRows(rd)); } while (rd.NextResult());
            }
        }
        while (sets.Count < 12) sets.Add(new List<Dictionary<string, object>>());
        return sets;
    }

    private static void Str(SqlCommand c, string name, int size, string value)
    {
        DashboardRepository.AddVarChar(c, name, size, value);
    }

    private static T Cached<T>(string key, Func<T> load) where T : class
    {
        var hit = HttpRuntime.Cache[key] as T;
        if (hit != null) return hit;
        var v = load();
        HttpRuntime.Cache.Insert(key, v, null, DateTime.UtcNow.AddMinutes(CacheMinutes), Cache.NoSlidingExpiration);
        return v;
    }

    // ================================================================== formatting helpers

    private static DateTime Today { get { return DateTime.Today; } }

    private static DateTime FyStart(DateTime d) { return new DateTime(d.Month >= 4 ? d.Year : d.Year - 1, 4, 1); }
    private static string FyLabel(DateTime fy) { return fy.Year + "-" + ((fy.Year + 1) % 100).ToString("00"); }

    private static string Norm(string s)
    {
        if (string.IsNullOrEmpty(s)) return "";
        var sb = new StringBuilder(s.Length);
        foreach (char ch in s.ToLowerInvariant()) sb.Append(char.IsLetterOrDigit(ch) || ch == '+' ? ch : ' ');
        return Regex.Replace(sb.ToString(), @"\s+", " ").Trim();
    }

    private static string[] Tokenize(string s) { return Norm(s).Split(new[] { ' ' }, StringSplitOptions.RemoveEmptyEntries); }

    private static decimal D(Dictionary<string, object> r, string k)
    {
        object v;
        if (r == null || !r.TryGetValue(k, out v) || v == null) return 0;
        try { return Convert.ToDecimal(v, CultureInfo.InvariantCulture); } catch { return 0; }
    }
    private static int I(Dictionary<string, object> r, string k) { return (int)Math.Round(D(r, k)); }
    private static string S(Dictionary<string, object> r, string k)
    {
        object v;
        return r != null && r.TryGetValue(k, out v) && v != null ? Convert.ToString(v, CultureInfo.InvariantCulture).Trim() : "";
    }
    private static Dictionary<string, object> First(List<Dictionary<string, object>> rows) { return rows.Count > 0 ? rows[0] : new Dictionary<string, object>(); }

    private static string Inr(decimal v)
    {
        decimal a = Math.Abs(v);
        if (a >= 10000000m) return "₹" + (v / 10000000m).ToString("0.00", IN) + " Cr";
        if (a >= 100000m) return "₹" + (v / 100000m).ToString("0.00", IN) + " L";
        return "₹" + v.ToString("#,##0", IN);
    }
    private static string N(decimal v) { return v.ToString("#,##0", IN); }
    private static string Kg(decimal v) { return v >= 100000m ? (v / 100000m).ToString("0.00", IN) + " lakh KG" : v.ToString("#,##0", IN) + " KG"; }
    private static string Pct(decimal part, decimal whole) { return whole != 0 ? (part * 100 / whole).ToString("0.0", IN) + "%" : "–"; }
    private static string Bold(string s) { return "**" + s + "**"; }
    private static string Plural(int n, string word) { return n.ToString("#,##0", IN) + " " + word + (n == 1 ? "" : "s"); }
    private static string Area(CustRef c) { return c.Area != "" ? ", " + c.Area : ""; }

    private static DateTime? ParseIso(string s)
    {
        DateTime d;
        return DateTime.TryParseExact(s, "yyyy-MM-dd", CultureInfo.InvariantCulture, DateTimeStyles.None, out d) ? d : (DateTime?)null;
    }
    private static string Dmy(string iso) { var d = ParseIso(iso); return d.HasValue ? d.Value.ToString("dd-MM-yyyy", CultureInfo.InvariantCulture) : (iso == "" ? "–" : iso); }
    private static string Short(DateTime d) { return d.ToString("dd-MM-yyyy", CultureInfo.InvariantCulture); }
    private static string LongDate(DateTime d) { return d.ToString("d MMMM yyyy", IN); }
    private static string MonthName(string iso) { var d = ParseIso(iso); return d.HasValue ? d.Value.ToString("MMMM", IN) : iso; }
    private static int DaysSince(string iso) { var d = ParseIso(iso); return d.HasValue ? (int)(Today - d.Value).TotalDays : 0; }
    private static string DaysAgo(string iso)
    {
        if (iso == "") return "";
        int n = DaysSince(iso);
        return n == 0 ? "today" : n == 1 ? "yesterday" : n + " days ago";
    }

    private static List<KeyValuePair<string, string>> BucketStats(Dictionary<string, object> r)
    {
        return new List<KeyValuePair<string, string>>
        {
            new KeyValuePair<string, string>("0–30 days", Inr(D(r, "B0"))),
            new KeyValuePair<string, string>("31–60", Inr(D(r, "B1"))),
            new KeyValuePair<string, string>("61–90", Inr(D(r, "B2"))),
            new KeyValuePair<string, string>("91–180", Inr(D(r, "B3"))),
            new KeyValuePair<string, string>("180+", Inr(D(r, "B4")))
        };
    }

    /// <summary>Amount in buckets older than n days, when n is a bucket edge (30/60/90/180); otherwise -1.</summary>
    private static decimal BucketsOver(Dictionary<string, object> r, int n)
    {
        switch (n)
        {
            case 30: return D(r, "B1") + D(r, "B2") + D(r, "B3") + D(r, "B4");
            case 60: return D(r, "B2") + D(r, "B3") + D(r, "B4");
            case 90: return D(r, "B3") + D(r, "B4");
            case 180: return D(r, "B4");
            default: return -1;
        }
    }

    private static List<object[]> TypeRows(Dictionary<string, object> t)
    {
        var rows = new List<object[]>();
        foreach (var ty in ChickTypes)
        {
            bool bought = D(t, ty.P + "Supplied") > 0 || S(t, ty.P + "Last") != "";
            if (!bought) continue;
            decimal due = D(t, ty.P + "OS");
            rows.Add(new object[]
            {
                ty.P == "Ot" ? "Opening & other" : ty.Name,
                S(t, ty.P + "Last") != "" ? Dmy(S(t, ty.P + "Last")) + " (" + DaysAgo(S(t, ty.P + "Last")) + ")" : "–",
                due > 0 ? Inr(due) : "nil",
                due > 0 ? I(t, ty.P + "Days") + " d" : ""
            });
        }
        return rows;
    }

    // ================================================================== reply builder

    private class Reply
    {
        public List<Dictionary<string, object>> Blocks = new List<Dictionary<string, object>>();
        public List<string> Suggestions = new List<string>();
        public Dictionary<string, object> Ctx = new Dictionary<string, object>();

        public void Text(string t) { Blocks.Add(new Dictionary<string, object> { { "type", "text" }, { "text", t } }); }

        public void Stats(List<KeyValuePair<string, string>> items, string note)
        {
            Blocks.Add(new Dictionary<string, object>
            {
                { "type", "stats" }, { "note", note },
                { "items", items.Select(i => new Dictionary<string, object> { { "label", i.Key }, { "value", i.Value } }).ToList() }
            });
        }

        public void Table(string[] cols, List<object[]> rows, string[] align)
        {
            if (rows == null || rows.Count == 0) return;
            Blocks.Add(new Dictionary<string, object>
            {
                { "type", "table" }, { "cols", cols }, { "align", align ?? new string[0] },
                { "rows", rows.Select(r => r.Select(c => Convert.ToString(c, CultureInfo.InvariantCulture)).ToArray()).ToList() }
            });
        }

        public void Link(string text, string href) { Blocks.Add(new Dictionary<string, object> { { "type", "link" }, { "text", text }, { "href", href } }); }

        public void Suggest(string s) { if (!Suggestions.Contains(s) && Suggestions.Count < 6) Suggestions.Add(s); }

        public Dictionary<string, object> ToJson()
        {
            return new Dictionary<string, object> { { "blocks", Blocks }, { "suggestions", Suggestions }, { "ctx", Ctx } };
        }
    }
}
