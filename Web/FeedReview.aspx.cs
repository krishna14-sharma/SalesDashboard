using System.Web.Script.Services;
using System.Web.Services;
using System.Web.UI;

/// <summary>Feed Sale Review for any time period. Data via AJAX page methods.</summary>
public partial class FeedReview : Page
{
    [WebMethod, ScriptMethod(ResponseFormat = ResponseFormat.Json)]
    public static object GetFilters()
    {
        return FeedReviewService.GetFilters();
    }

    [WebMethod, ScriptMethod(ResponseFormat = ResponseFormat.Json)]
    public static object GetReview(string fromDate, string toDate, string areaCode, string feedGroup)
    {
        return FeedReviewService.GetReview(fromDate, toDate, areaCode, feedGroup);
    }
}
