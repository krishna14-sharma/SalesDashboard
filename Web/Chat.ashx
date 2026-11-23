<%@ WebHandler Language="C#" Class="ChatHandler" %>

using System;
using System.Collections.Generic;
using System.IO;
using System.Web;
using System.Web.Script.Serialization;

/// <summary>
/// Endpoint of the dashboard assistant. POST {"q": "question", "ctx": {...}} -> JSON reply.
/// Signed-in users only (Web.config denies anonymous users for the whole site).
/// </summary>
public class ChatHandler : IHttpHandler
{
    private const int MaxBody = 4096;

    public void ProcessRequest(HttpContext context)
    {
        var res = context.Response;
        res.ContentType = "application/json";
        res.Cache.SetNoStore();

        if (context.User == null || !context.User.Identity.IsAuthenticated)
        {
            res.StatusCode = 401;
            res.Write("{\"error\":\"Please sign in again.\"}");
            return;
        }
        if (!string.Equals(context.Request.HttpMethod, "POST", StringComparison.OrdinalIgnoreCase))
        {
            res.StatusCode = 405;
            res.Write("{\"error\":\"Use POST.\"}");
            return;
        }

        var json = new JavaScriptSerializer();
        string question = "";
        Dictionary<string, object> ctx = null;
        try
        {
            string body;
            using (var reader = new StreamReader(context.Request.InputStream))
            {
                var buf = new char[MaxBody + 1];
                int n = reader.ReadBlock(buf, 0, buf.Length);
                if (n > MaxBody) { res.StatusCode = 413; res.Write("{\"error\":\"Question is too long.\"}"); return; }
                body = new string(buf, 0, n);
            }
            var data = json.Deserialize<Dictionary<string, object>>(body);
            object o;
            if (data != null && data.TryGetValue("q", out o) && o != null) question = Convert.ToString(o);
            if (data != null && data.TryGetValue("ctx", out o)) ctx = o as Dictionary<string, object>;
        }
        catch (Exception)
        {
            res.StatusCode = 400;
            res.Write("{\"error\":\"Could not read the question.\"}");
            return;
        }

        res.Write(json.Serialize(ChatService.Answer(question, ctx)));
    }

    public bool IsReusable { get { return true; } }
}
