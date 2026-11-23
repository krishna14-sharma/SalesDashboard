using System.Web.Script.Services;
using System.Web.Services;
using System.Web.UI;

/// <summary>Chick type-wise last hatch date and outstanding (PrintData + VENTRY ledger). Data via AJAX page methods.</summary>
public partial class ChickTypes : Page
{
    [WebMethod, ScriptMethod(ResponseFormat = ResponseFormat.Json)]
    public static object GetFilters()
    {
        return ChickTypeService.GetFilters();
    }

    [WebMethod, ScriptMethod(ResponseFormat = ResponseFormat.Json)]
    public static object GetSummary(string station, string asOf)
    {
        return ChickTypeService.GetSummary(station, asOf);
    }

    [WebMethod, ScriptMethod(ResponseFormat = ResponseFormat.Json)]
    public static object GetCustomer(string custKey, string asOf)
    {
        return ChickTypeService.GetCustomer(custKey, asOf);
    }
}
