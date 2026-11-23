using System;
using System.Web.Script.Serialization;
using System.Web.Script.Services;
using System.Web.Services;
using System.Web.UI;

/// <summary>Sign-in page. The form posts with AJAX to the Login page method.</summary>
public partial class LoginPage : Page
{
    /// <summary>ReturnUrl as a JavaScript string literal (safely encoded).</summary>
    protected string ReturnUrlJson = "\"\"";
    /// <summary>"expired" when sent here from a dashboard whose sign-in ran out; "out" after signing out.</summary>
    protected string Reason = "";
    /// <summary>Web.config App.Title / App.CompanyName / App.LogoUrl</summary>
    protected string AppTitle = "Chick & Poultry Dashboards";
    protected string CompanyName = "";
    protected string LogoUrl = "";
    /// <summary>Web.config Login.DefaultUser - user name filled in when the page opens</summary>
    protected string DefaultUser = "";

    protected void Page_Load(object sender, EventArgs e)
    {
        Response.Cache.SetNoStore();
        AppTitle = Setting("App.Title", AppTitle);
        CompanyName = Setting("App.CompanyName", "");
        DefaultUser = Setting("Login.DefaultUser", "");
        if (DefaultUser.Length > 15) DefaultUser = DefaultUser.Substring(0, 15);
        string logo = Setting("App.LogoUrl", "");
        // only local images (e.g. ~/assets/img/logo.png) - never an outside address
        if (logo.StartsWith("~/") || (logo.StartsWith("/") && !logo.StartsWith("//")))
            LogoUrl = ResolveUrl(logo);

        string ret = Request.QueryString["ReturnUrl"];

        // already signed in -> go straight to the dashboard
        if (User != null && User.Identity.IsAuthenticated)
        {
            Response.Redirect(AuthService.SafeReturnUrl(ret), false);
            Context.ApplicationInstance.CompleteRequest();
            return;
        }

        ReturnUrlJson = new JavaScriptSerializer().Serialize(AuthService.SafeReturnUrl(ret));
        string r = Request.QueryString["r"];
        if (r == "expired" || r == "out") Reason = r;
        else if (!string.IsNullOrEmpty(ret)) Reason = "expired";
    }

    private static string Setting(string name, string fallback)
    {
        string v = System.Configuration.ConfigurationManager.AppSettings[name];
        return string.IsNullOrWhiteSpace(v) ? fallback : v.Trim();
    }

    [WebMethod, ScriptMethod(ResponseFormat = ResponseFormat.Json)]
    public static object Login(string userName, string password, bool remember, string returnUrl)
    {
        var r = AuthService.Login(userName, password, remember, returnUrl);
        return new { ok = r.Ok, error = r.Error, redirect = r.Redirect };
    }
}
