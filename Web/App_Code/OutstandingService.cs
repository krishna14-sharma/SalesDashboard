using System;
using System.Collections.Generic;
using System.Data;
using System.Data.SqlClient;
using System.Globalization;

/// <summary>
/// Customer outstanding &amp; aging. Shared by ChickOutstanding.aspx (Kind = CHICK)
/// and PoultryOutstanding.aspx (Kind = POULTRY).
///   POULTRY : AreaDMPoultry / AreaTrPoultry      - Database/03_Customer_Outstanding.sql
///   CHICK   : PrintData + VENTRY ledger + ACC_HEAD - Database/08_Chick_Type_Outstanding.sql (usp_ChickOS_*)
///             (the "area" filter is the station; session and authorised-only do not apply)
/// Every call reads the live tables, so figures are always current.
/// </summary>
public static class OutstandingService
{
    public const string Chick = "CHICK";
    public const string Poultry = "POULTRY";
    private const int Timeout = 120;

    public static object GetFilters(string kind)
    {
        if (kind == Chick) return ChickFilters();
        try
        {
            using (var cn = new SqlConnection(DashboardRepository.ConnectionString))
            using (var cmd = NewProc(cn, "dbo.usp_CustOS_Filters", kind))
            {
                cn.Open();
                using (var rd = cmd.ExecuteReader())
                {
                    var sessions = new List<string>();
                    while (rd.Read()) sessions.Add(Convert.ToString(rd["Session"]));
                    rd.NextResult();
                    var areas = DashboardRepository.ReadRows(rd);
                    rd.NextResult();
                    string today = rd.Read() ? ((DateTime)rd["Today"]).ToString("yyyy-MM-dd", CultureInfo.InvariantCulture) : null;
                    return Ok(new Dictionary<string, object> { { "sessions", sessions }, { "areas", areas }, { "today", today } });
                }
            }
        }
        catch (Exception ex) { return Fail("GetFilters", ex, "Could not load filters. Please check the database connection."); }
    }

    public static object GetSummary(string kind, string session, string areaCode, string asOf, bool authOnly)
    {
        try
        {
            using (var cn = new SqlConnection(DashboardRepository.ConnectionString))
            using (var cmd = kind == Chick ? ChickProc(cn, "dbo.usp_ChickOS_Summary", areaCode, asOf) : NewProc(cn, "dbo.usp_CustOS_Summary", kind))
            {
                if (kind != Chick) AddFilters(cmd, session, areaCode, asOf, authOnly);
                cn.Open();
                using (var rd = cmd.ExecuteReader())
                {
                    var kpi = DashboardRepository.ReadRows(rd);
                    rd.NextResult();
                    var customers = DashboardRepository.ReadRows(rd);
                    rd.NextResult();
                    var areas = DashboardRepository.ReadRows(rd);
                    return Ok(new Dictionary<string, object>
                    {
                        { "kpi", kpi.Count > 0 ? kpi[0] : new Dictionary<string, object>() },
                        { "customers", customers },
                        { "areas", areas },
                        { "generatedAt", DateTime.Now.ToString("dd-MM-yyyy HH:mm:ss", CultureInfo.InvariantCulture) }
                    });
                }
            }
        }
        catch (Exception ex) { return Fail("GetSummary", ex, "Could not load outstanding data. Please try again."); }
    }

    public static object GetProducts(string kind, string session, string areaCode, string asOf, bool authOnly)
    {
        try
        {
            using (var cn = new SqlConnection(DashboardRepository.ConnectionString))
            using (var cmd = kind == Chick ? ChickProc(cn, "dbo.usp_ChickOS_Products", areaCode, asOf) : NewProc(cn, "dbo.usp_CustOS_Products", kind))
            {
                if (kind != Chick) AddFilters(cmd, session, areaCode, asOf, authOnly);
                cn.Open();
                using (var rd = cmd.ExecuteReader())
                {
                    var products = DashboardRepository.ReadRows(rd);
                    rd.NextResult();
                    var productCustomers = DashboardRepository.ReadRows(rd);
                    return Ok(new Dictionary<string, object> { { "products", products }, { "productCustomers", productCustomers } });
                }
            }
        }
        catch (Exception ex) { return Fail("GetProducts", ex, "Could not load product-wise data. Please try again."); }
    }

    public static object GetCustomer(string kind, string custKey, string session, string areaCode, string asOf, bool authOnly)
    {
        try
        {
            custKey = Clean(custKey, 200);
            if (custKey == null) return new { ok = false, error = "Customer not specified." };

            using (var cn = new SqlConnection(DashboardRepository.ConnectionString))
            using (var cmd = kind == Chick ? ChickCustomerProc(cn, custKey, asOf) : NewProc(cn, "dbo.usp_CustOS_Customer", kind))
            {
                if (kind != Chick)
                {
                    DashboardRepository.AddVarChar(cmd, "@CustKey", 200, custKey);
                    AddFilters(cmd, session, areaCode, asOf, authOnly);
                }
                cn.Open();
                using (var rd = cmd.ExecuteReader())
                {
                    var bills = DashboardRepository.ReadRows(rd);
                    rd.NextResult();
                    var lines = DashboardRepository.ReadRows(rd);
                    rd.NextResult();
                    var payments = DashboardRepository.ReadRows(rd);
                    return Ok(new Dictionary<string, object>
                    {
                        { "bills", bills }, { "lines", lines }, { "payments", payments },
                        { "generatedAt", DateTime.Now.ToString("dd-MM-yyyy HH:mm:ss", CultureInfo.InvariantCulture) }
                    });
                }
            }
        }
        catch (Exception ex) { return Fail("GetCustomer", ex, "Could not load customer details. Please try again."); }
    }

    // ------------------------------------------------------------------ chick (ledger) helpers

    private static object ChickFilters()
    {
        try
        {
            using (var cn = new SqlConnection(DashboardRepository.ConnectionString))
            using (var cmd = new SqlCommand("dbo.usp_ChickType_Filters", cn) { CommandType = CommandType.StoredProcedure, CommandTimeout = Timeout })
            {
                cn.Open();
                using (var rd = cmd.ExecuteReader())
                {
                    var areas = new List<Dictionary<string, object>>();
                    while (rd.Read())
                    {
                        string st = Convert.ToString(rd["Station"]);
                        areas.Add(new Dictionary<string, object> { { "AreaCode", st }, { "Area", "" } });
                    }
                    rd.NextResult();
                    var info = DashboardRepository.ReadRows(rd);
                    var i = info.Count > 0 ? info[0] : new Dictionary<string, object>();
                    return Ok(new Dictionary<string, object>
                    {
                        { "sessions", new List<string>() }, { "areas", areas },
                        { "today", i.ContainsKey("Today") ? i["Today"] : null },
                        { "ledgerFrom", i.ContainsKey("LedgerFrom") ? i["LedgerFrom"] : null },
                        { "ledgerTo", i.ContainsKey("LedgerTo") ? i["LedgerTo"] : null }
                    });
                }
            }
        }
        catch (Exception ex) { return Fail("ChickFilters", ex, "Could not load filters. Please check the database connection."); }
    }

    private static SqlCommand ChickProc(SqlConnection cn, string proc, string station, string asOf)
    {
        var cmd = new SqlCommand(proc, cn) { CommandType = CommandType.StoredProcedure, CommandTimeout = 180 };
        DashboardRepository.AddVarChar(cmd, "@Station", 50, Clean(station, 50));
        cmd.Parameters.Add("@AsOf", SqlDbType.Date).Value = DateOrNull(asOf);
        return cmd;
    }

    private static SqlCommand ChickCustomerProc(SqlConnection cn, string accCode, string asOf)
    {
        var cmd = new SqlCommand("dbo.usp_ChickOS_Customer", cn) { CommandType = CommandType.StoredProcedure, CommandTimeout = 180 };
        DashboardRepository.AddVarChar(cmd, "@AccCode", 18, Clean(accCode, 18));
        cmd.Parameters.Add("@AsOf", SqlDbType.Date).Value = DateOrNull(asOf);
        return cmd;
    }

    private static object DateOrNull(string s)
    {
        DateTime d;
        return !string.IsNullOrWhiteSpace(s) && DateTime.TryParseExact(s.Trim(), "yyyy-MM-dd", CultureInfo.InvariantCulture, DateTimeStyles.None, out d)
            ? (object)d : DBNull.Value;
    }

    // ------------------------------------------------------------------ helpers

    private static SqlCommand NewProc(SqlConnection cn, string proc, string kind)
    {
        if (kind != Chick && kind != Poultry) throw new ArgumentException("Invalid kind");
        var cmd = new SqlCommand(proc, cn) { CommandType = CommandType.StoredProcedure, CommandTimeout = Timeout };
        cmd.Parameters.Add("@Kind", SqlDbType.VarChar, 10).Value = kind;
        return cmd;
    }

    private static void AddFilters(SqlCommand cmd, string session, string areaCode, string asOf, bool authOnly)
    {
        DashboardRepository.AddVarChar(cmd, "@Session", 50, Clean(session, 50));
        DashboardRepository.AddVarChar(cmd, "@AreaCode", 50, Clean(areaCode, 50));
        DateTime d;
        object asOfValue = DBNull.Value;
        if (!string.IsNullOrWhiteSpace(asOf) &&
            DateTime.TryParseExact(asOf.Trim(), "yyyy-MM-dd", CultureInfo.InvariantCulture, DateTimeStyles.None, out d))
            asOfValue = d;
        cmd.Parameters.Add("@AsOf", SqlDbType.Date).Value = asOfValue;
        cmd.Parameters.Add("@AuthOnly", SqlDbType.Bit).Value = authOnly;
    }

    private static string Clean(string value, int max)
    {
        if (string.IsNullOrWhiteSpace(value)) return null;
        value = value.Trim();
        return value.Length > max ? value.Substring(0, max) : value;
    }

    private static object Ok(object data) { return new { ok = true, data = data }; }

    private static object Fail(string where, Exception ex, string message)
    {
        System.Diagnostics.Trace.TraceError("Outstanding." + where + " failed: " + ex);
        return new { ok = false, error = message };
    }
}
