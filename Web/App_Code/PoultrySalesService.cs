using System;
using System.Collections.Generic;
using System.Data;
using System.Data.SqlClient;
using System.Globalization;

/// <summary>
/// Poultry products sales dashboard (AreaDMPoultry + AreaDMPoultry_det / AreaTrPoultry).
/// SQL: Database/05_Poultry_Sales.sql
/// </summary>
public static class PoultrySalesService
{
    private const int Timeout = 120;

    public static object GetFilters(string session)
    {
        try
        {
            using (var cn = new SqlConnection(DashboardRepository.ConnectionString))
            using (var cmd = new SqlCommand("dbo.usp_PoultryDash_Filters", cn) { CommandType = CommandType.StoredProcedure, CommandTimeout = Timeout })
            {
                DashboardRepository.AddVarChar(cmd, "@Session", 50, Clean(session, 50));
                cn.Open();
                using (var rd = cmd.ExecuteReader())
                {
                    var sessions = new List<string>();
                    while (rd.Read()) sessions.Add(Convert.ToString(rd["Session"]));
                    rd.NextResult();
                    var areas = DashboardRepository.ReadRows(rd);
                    rd.NextResult();
                    var products = DashboardRepository.ReadRows(rd);
                    rd.NextResult();
                    string current = null;
                    if (rd.Read() && rd["CurrentSession"] != DBNull.Value) current = Convert.ToString(rd["CurrentSession"]);
                    return new
                    {
                        ok = true,
                        data = new Dictionary<string, object>
                        {
                            { "sessions", sessions }, { "areas", areas }, { "products", products }, { "currentSession", current }
                        }
                    };
                }
            }
        }
        catch (Exception ex) { return Fail("GetFilters", ex, "Could not load filter values. Please check the database connection."); }
    }

    public static object GetDashboard(string session, string areaCode, string product, string fromDate, string toDate)
    {
        try
        {
            session = Clean(session, 50);
            if (session == null) return new { ok = false, error = "Please select a session." };

            DateTime? from = ParseDate(fromDate), to = ParseDate(toDate);
            if (from.HasValue && to.HasValue && from.Value > to.Value) { var t = from; from = to; to = t; }

            using (var cn = new SqlConnection(DashboardRepository.ConnectionString))
            using (var cmd = new SqlCommand("dbo.usp_PoultryDash_Data", cn) { CommandType = CommandType.StoredProcedure, CommandTimeout = Timeout })
            {
                DashboardRepository.AddVarChar(cmd, "@Session", 50, session);
                DashboardRepository.AddVarChar(cmd, "@AreaCode", 50, Clean(areaCode, 50));
                DashboardRepository.AddVarChar(cmd, "@Product", 200, Clean(product, 200));
                cmd.Parameters.Add("@FromDate", SqlDbType.Date).Value = (object)from ?? DBNull.Value;
                cmd.Parameters.Add("@ToDate", SqlDbType.Date).Value = (object)to ?? DBNull.Value;

                string[] names = { "kpi", "products", "monthly", "monthlyProducts", "payMode", "tax", "areas", "customers", "dms", "lines", "receipts" };
                var result = new Dictionary<string, object>();
                cn.Open();
                using (var rd = cmd.ExecuteReader())
                {
                    int i = 0;
                    do
                    {
                        if (i >= names.Length) break;
                        result[names[i++]] = DashboardRepository.ReadRows(rd);
                    } while (rd.NextResult());
                }
                var kpi = result.ContainsKey("kpi") ? (List<Dictionary<string, object>>)result["kpi"] : null;
                result["kpi"] = kpi != null && kpi.Count > 0 ? kpi[0] : new Dictionary<string, object>();
                result["generatedAt"] = DateTime.Now.ToString("dd-MM-yyyy HH:mm", CultureInfo.InvariantCulture);
                return new { ok = true, data = result };
            }
        }
        catch (Exception ex) { return Fail("GetDashboard", ex, "Could not load dashboard data. Please try again."); }
    }

    private static string Clean(string value, int max)
    {
        if (string.IsNullOrWhiteSpace(value)) return null;
        value = value.Trim();
        return value.Length > max ? value.Substring(0, max) : value;
    }

    private static DateTime? ParseDate(string value)
    {
        DateTime d;
        if (!string.IsNullOrWhiteSpace(value) &&
            DateTime.TryParseExact(value.Trim(), "yyyy-MM-dd", CultureInfo.InvariantCulture, DateTimeStyles.None, out d))
            return d;
        return null;
    }

    private static object Fail(string where, Exception ex, string message)
    {
        System.Diagnostics.Trace.TraceError("PoultrySales." + where + " failed: " + ex);
        return new { ok = false, error = message };
    }
}
