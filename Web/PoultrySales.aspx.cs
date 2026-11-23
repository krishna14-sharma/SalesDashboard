using System.Web.Script.Services;
using System.Web.Services;
using System.Web.UI;

/// <summary>Poultry products sales dashboard. Data via AJAX page methods, no postbacks.</summary>
public partial class PoultrySales : Page
{
    [WebMethod, ScriptMethod(ResponseFormat = ResponseFormat.Json)]
    public static object GetFilters(string session)
    {
        return PoultrySalesService.GetFilters(session);
    }

    [WebMethod, ScriptMethod(ResponseFormat = ResponseFormat.Json)]
    public static object GetDashboard(string session, string areaCode, string product, string fromDate, string toDate)
    {
        return PoultrySalesService.GetDashboard(session, areaCode, product, fromDate, toDate);
    }
}
