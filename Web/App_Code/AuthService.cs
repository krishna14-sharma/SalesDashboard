using System;
using System.Configuration;
using System.Data;
using System.Data.SqlClient;
using System.Linq;
using System.Web;
using System.Web.Caching;
using System.Web.Security;

/// <summary>
/// Login against dbo.Usertab4 (procedure dbo.usp_App_Login, Database/06_Login.sql)
/// using ASP.NET Forms Authentication.
/// Settings (Web.config appSettings):
///   Login.PasswordMode  AUTO | PWDENCRYPT | SHA2_256 | SHA1 | MD5 | PASSPHRASE | PLAIN
///   Login.Passphrase    key used with ENCRYPTBYPASSPHRASE (only for PASSPHRASE)
///   Login.AllowedRoles  comma-separated roles allowed in; empty = every role
/// </summary>
public static class AuthService
{
    private const int MaxFailures = 5;
    private static readonly TimeSpan LockTime = TimeSpan.FromMinutes(15);
    private static readonly TimeSpan RememberFor = TimeSpan.FromDays(7);

    public class LoginResult
    {
        public bool Ok;
        public string Error;
        public string Redirect;
    }

    public static LoginResult Login(string userName, string password, bool remember, string returnUrl)
    {
        userName = (userName ?? "").Trim();
        password = password ?? "";
        if (userName.Length == 0 || password.Length == 0)
            return Fail("Please enter your user name and password.");
        if (userName.Length > 15 || password.Length > 100)
            return Fail("Invalid user name or password.");

        string ip = ClientIp();
        string key = "login-fail:" + ip + ":" + userName.ToLowerInvariant();
        int failures = HttpRuntime.Cache[key] is int ? (int)HttpRuntime.Cache[key] : 0;
        if (failures >= MaxFailures)
            return Fail("Too many failed attempts. Please wait 15 minutes and try again.");

        string role = null, method = null;
        int isUnAuth = 0;
        try
        {
            using (var cn = new SqlConnection(DashboardRepository.ConnectionString))
            using (var cmd = new SqlCommand("dbo.usp_App_Login", cn) { CommandType = CommandType.StoredProcedure, CommandTimeout = 30 })
            {
                cmd.Parameters.Add("@Uname", SqlDbType.VarChar, 15).Value = userName;
                cmd.Parameters.Add("@Password", SqlDbType.NVarChar, 100).Value = password;
                cmd.Parameters.Add("@Mode", SqlDbType.VarChar, 20).Value = Setting("Login.PasswordMode", "AUTO");
                string pass = Setting("Login.Passphrase", "");
                cmd.Parameters.Add("@Passphrase", SqlDbType.NVarChar, 200).Value = pass.Length > 0 ? (object)pass : DBNull.Value;
                cn.Open();
                using (var rd = cmd.ExecuteReader())
                {
                    if (rd.Read())
                    {
                        userName = Convert.ToString(rd["Uname"]).Trim();
                        role = Convert.ToString(rd["Role"]).Trim();
                        isUnAuth = rd["IsUnAuth"] == DBNull.Value ? 0 : Convert.ToInt32(rd["IsUnAuth"]);
                        method = Convert.ToString(rd["Method"]);
                    }
                }
            }
        }
        catch (Exception ex)
        {
            System.Diagnostics.Trace.TraceError("Login failed (database): " + ex);
            return Fail("Could not reach the database. Please try again shortly.");
        }

        if (role == null)
        {
            HttpRuntime.Cache.Insert(key, failures + 1, null, DateTime.UtcNow.Add(LockTime), Cache.NoSlidingExpiration);
            int left = MaxFailures - failures - 1;
            return Fail(left > 0 && left <= 2
                ? "Invalid user name or password. " + left + " attempt" + (left == 1 ? "" : "s") + " left."
                : "Invalid user name or password.");
        }

        if (isUnAuth == 1)
            return Fail("Your account is blocked. Please contact the administrator.");

        string allowed = Setting("Login.AllowedRoles", "");
        if (allowed.Length > 0 &&
            !allowed.Split(',').Select(r => r.Trim()).Any(r => string.Equals(r, role, StringComparison.OrdinalIgnoreCase)))
            return Fail("Your role (" + role + ") does not have access to the dashboards.");

        HttpRuntime.Cache.Remove(key);
        System.Diagnostics.Trace.TraceInformation("Login ok: " + userName + " (" + role + "), password method " + method + ", IP " + ip);

        IssueCookie(userName, role, remember);
        return new LoginResult { Ok = true, Redirect = SafeReturnUrl(returnUrl) };
    }

    public static void Logout()
    {
        FormsAuthentication.SignOut();
        var c = new HttpCookie(FormsAuthentication.FormsCookieName, "")
        {
            Expires = DateTime.Now.AddYears(-1),
            Path = FormsAuthentication.FormsCookiePath,
            HttpOnly = true
        };
        HttpContext.Current.Response.Cookies.Add(c);
    }

    /// <summary>Role saved in the login ticket ("" when not signed in).</summary>
    public static string CurrentRole()
    {
        var ctx = HttpContext.Current;
        if (ctx == null || ctx.User == null || !ctx.User.Identity.IsAuthenticated) return "";
        var id = ctx.User.Identity as FormsIdentity;
        return id != null ? (id.Ticket.UserData ?? "") : "";
    }

    public static string CurrentUser()
    {
        var ctx = HttpContext.Current;
        return ctx != null && ctx.User != null && ctx.User.Identity.IsAuthenticated ? ctx.User.Identity.Name : "";
    }

    // ------------------------------------------------------------------ helpers

    private static void IssueCookie(string userName, string role, bool remember)
    {
        DateTime now = DateTime.Now;
        DateTime expires = now.Add(remember ? RememberFor : FormsAuthentication.Timeout);
        var ticket = new FormsAuthenticationTicket(1, userName, now, expires, remember, role ?? "", FormsAuthentication.FormsCookiePath);
        var cookie = new HttpCookie(FormsAuthentication.FormsCookieName, FormsAuthentication.Encrypt(ticket))
        {
            HttpOnly = true,
            Secure = FormsAuthentication.RequireSSL,
            Path = FormsAuthentication.FormsCookiePath
        };
        if (remember) cookie.Expires = expires;
        HttpContext.Current.Response.Cookies.Add(cookie);
    }

    /// <summary>Only allow redirects back into this site.</summary>
    public static string SafeReturnUrl(string url)
    {
        string fallback = VirtualPathUtility.ToAbsolute(FormsAuthentication.DefaultUrl);
        if (string.IsNullOrWhiteSpace(url)) return fallback;
        url = url.Trim();
        bool local = url.StartsWith("/") && !url.StartsWith("//") && !url.StartsWith("/\\") && url.IndexOf("://", StringComparison.Ordinal) < 0;
        if (!local) return fallback;
        if (url.IndexOf("login.aspx", StringComparison.OrdinalIgnoreCase) >= 0 ||
            url.IndexOf("logout.aspx", StringComparison.OrdinalIgnoreCase) >= 0) return fallback;
        return url;
    }

    private static string Setting(string name, string fallback)
    {
        string v = ConfigurationManager.AppSettings[name];
        return string.IsNullOrWhiteSpace(v) ? fallback : v.Trim();
    }

    private static string ClientIp()
    {
        var r = HttpContext.Current != null ? HttpContext.Current.Request : null;
        return r != null ? (r.UserHostAddress ?? "") : "";
    }

    private static LoginResult Fail(string message) { return new LoginResult { Ok = false, Error = message }; }
}
