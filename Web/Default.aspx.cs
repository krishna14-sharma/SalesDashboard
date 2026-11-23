using System;
using System.Collections.Generic;
using System.Globalization;
using System.Web.Script.Services;
using System.Web.Services;
using System.Web.UI;

/// <summary>
/// Dashboard page. Data is fetched with jQuery AJAX calls to the static
/// [WebMethod] page methods below, so the page never posts back / reloads.
/// </summary>
public partial class _Default : Page
{
    private static readonly HashSet<string> AllowedChickTypes =
        new HashSet<string>(StringComparer.OrdinalIgnoreCase) { "Broiler", "Layer", "Cockrel" };

    protected void Page_Load(object sender, EventArgs e)
    {
        // Nothing server-side: everything is loaded through AJAX.
    }

    [WebMethod]
    [ScriptMethod(ResponseFormat = ResponseFormat.Json)]
    public static object GetFilters(string session)
    {
        try
        {
            return new { ok = true, data = DashboardRepository.GetFilters(Limit(session, 50)) };
        }
        catch (Exception ex)
        {
            System.Diagnostics.Trace.TraceError("GetFilters failed: " + ex);
            return new { ok = false, error = "Could not load filter values. Please check the database connection." };
        }
    }

    [WebMethod]
    [ScriptMethod(ResponseFormat = ResponseFormat.Json)]
    public static object GetDashboard(string session, string areaCode, string chickType, string fromDate, string toDate)
    {
        try
        {
            session = Limit(session, 50);
            if (string.IsNullOrEmpty(session))
                return new { ok = false, error = "Please select a session." };

            if (!string.IsNullOrWhiteSpace(chickType) && !AllowedChickTypes.Contains(chickType.Trim()))
                chickType = null;

            DateTime? from = ParseDate(fromDate);
            DateTime? to = ParseDate(toDate);
            if (from.HasValue && to.HasValue && from.Value > to.Value)
            {
                var tmp = from; from = to; to = tmp;
            }

            var data = DashboardRepository.GetDashboard(session, Limit(areaCode, 50), chickType, from, to);
            data["generatedAt"] = DateTime.Now.ToString("dd-MM-yyyy HH:mm", CultureInfo.InvariantCulture);
            return new { ok = true, data = data };
        }
        catch (Exception ex)
        {
            System.Diagnostics.Trace.TraceError("GetDashboard failed: " + ex);
            return new { ok = false, error = "Could not load dashboard data. Please try again." };
        }
    }

    private static string Limit(string value, int max)
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
}
