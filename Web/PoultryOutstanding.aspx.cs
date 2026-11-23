using System.Web.Script.Services;
using System.Web.Services;
using System.Web.UI;

/// <summary>Customer outstanding for poultry products (AreaDMPoultry + AreaDMPoultry_det / AreaTrPoultry). Data via AJAX page methods.</summary>
public partial class PoultryOutstanding : Page
{
    private const string Kind = OutstandingService.Poultry;

    [WebMethod, ScriptMethod(ResponseFormat = ResponseFormat.Json)]
    public static object GetFilters()
    {
        return OutstandingService.GetFilters(Kind);
    }

    [WebMethod, ScriptMethod(ResponseFormat = ResponseFormat.Json)]
    public static object GetSummary(string session, string areaCode, string asOf, bool authOnly)
    {
        return OutstandingService.GetSummary(Kind, session, areaCode, asOf, authOnly);
    }

    [WebMethod, ScriptMethod(ResponseFormat = ResponseFormat.Json)]
    public static object GetProducts(string session, string areaCode, string asOf, bool authOnly)
    {
        return OutstandingService.GetProducts(Kind, session, areaCode, asOf, authOnly);
    }

    [WebMethod, ScriptMethod(ResponseFormat = ResponseFormat.Json)]
    public static object GetCustomer(string custKey, string session, string areaCode, string asOf, bool authOnly)
    {
        return OutstandingService.GetCustomer(Kind, custKey, session, areaCode, asOf, authOnly);
    }
}
