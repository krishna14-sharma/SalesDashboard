using System;
using System.Collections.Generic;
using System.Data;
using System.Data.SqlClient;
using System.Globalization;

/// <summary>
/// Feed Sale Review (FeedReview.aspx). SQL: Database/07_Feed_Review.sql
/// </summary>
public static class FeedReviewService
{
    private static readonly HashSet<string> Groups =
        new HashSet<string>(StringComparer.OrdinalIgnoreCase) { "Broiler", "Layer", "Sonali", "Other" };

    public static object GetFilters()
    {
        try
        {
            using (var cn = new SqlConnection(DashboardRepository.ConnectionString))
            using (var cmd = new SqlCommand("dbo.usp_FeedReview_Filters", cn) { CommandType = CommandType.StoredProcedure, CommandTimeout = 120 })
            {
                cn.Open();
                using (var rd = cmd.ExecuteReader())
                {
                    var areas = DashboardRepository.ReadRows(rd);
                    rd.NextResult();
                    var dates = DashboardRepository.ReadRows(rd);
                    return new
                    {
                        ok = true,
                        data = new Dictionary<string, object>
                        {
                            { "areas", areas },
                            { "dates", dates.Count > 0 ? dates[0] : new Dictionary<string, object>() }
                        }
                    };
                }
            }
        }
        catch (Exception ex) { return Fail("GetFilters", ex, "Could not load filters. Please check the database connection."); }
    }

    public static object GetReview(string fromDate, string toDate, string areaCode, string feedGroup)
    {
        try
        {
            DateTime? from = ParseDate(fromDate), to = ParseDate(toDate);
            if (!to.HasValue) to = DateTime.Today;
            if (from.HasValue && from.Value > to.Value) { var t = from; from = to; to = t; }
            if (!string.IsNullOrWhiteSpace(feedGroup) && !Groups.Contains(feedGroup.Trim())) feedGroup = null;

            using (var cn = new SqlConnection(DashboardRepository.ConnectionString))
            using (var cmd = new SqlCommand("dbo.usp_FeedReview", cn) { CommandType = CommandType.StoredProcedure, CommandTimeout = 180 })
            {
                cmd.Parameters.Add("@From", SqlDbType.Date).Value = (object)from ?? DBNull.Value;
                cmd.Parameters.Add("@To", SqlDbType.Date).Value = to.Value;
                DashboardRepository.AddVarChar(cmd, "@AreaCode", 50, areaCode);
                DashboardRepository.AddVarChar(cmd, "@FeedGroup", 20, feedGroup);

                string[] names = { "kpi", "monthly", "groups", "products", "salespeople", "customers", "custMonths" };
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
                var kpi = (List<Dictionary<string, object>>)result["kpi"];
                result["kpi"] = kpi.Count > 0 ? kpi[0] : new Dictionary<string, object>();
                result["generatedAt"] = DateTime.Now.ToString("dd-MM-yyyy HH:mm", CultureInfo.InvariantCulture);
                return new { ok = true, data = result };
            }
        }
        catch (Exception ex) { return Fail("GetReview", ex, "Could not load the feed review. Please try again."); }
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
        System.Diagnostics.Trace.TraceError("FeedReview." + where + " failed: " + ex);
        return new { ok = false, error = message };
    }
}
