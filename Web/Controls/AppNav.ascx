<%@ Control Language="C#" ClassName="AppNav" %>
<script runat="server">
    /// <summary>sales | chick | types | psales | poultry | feed</summary>
    public string Active { get; set; }

    protected string Cls(string key)
    {
        return string.Equals(key, Active, StringComparison.OrdinalIgnoreCase) ? "appnav-link active" : "appnav-link";
    }
</script>
<div class="appnav">
    <div class="container-xxl">
        <span class="appnav-group">Chicks</span>
        <a class="<%= Cls("sales") %>" href="<%= ResolveUrl("~/Default.aspx") %>"><i class="bi bi-bar-chart-line"></i><span>Sales</span></a>
        <a class="<%= Cls("chick") %>" href="<%= ResolveUrl("~/ChickOutstanding.aspx") %>"><i class="bi bi-hourglass-split"></i><span>Outstanding</span></a>
        <a class="<%= Cls("types") %>" href="<%= ResolveUrl("~/ChickTypes.aspx") %>"><i class="bi bi-grid-3x3-gap"></i><span>Type-wise</span></a>
        <span class="appnav-sep" aria-hidden="true"></span>
        <span class="appnav-group">Poultry products</span>
        <a class="<%= Cls("psales") %>" href="<%= ResolveUrl("~/PoultrySales.aspx") %>"><i class="bi bi-basket2"></i><span>Sales</span></a>
        <a class="<%= Cls("poultry") %>" href="<%= ResolveUrl("~/PoultryOutstanding.aspx") %>"><i class="bi bi-hourglass-split"></i><span>Outstanding</span></a>
        <a class="<%= Cls("feed") %>" href="<%= ResolveUrl("~/FeedReview.aspx") %>"><i class="bi bi-journal-text"></i><span>Feed review</span></a>

        <%-- dashboard assistant: chat window on every page that shows this navigation bar --%>
        <div id="chatbot-root" hidden="hidden" data-endpoint="<%= ResolveUrl("~/Chat.ashx") %>"></div>
        <link href="<%= ResolveUrl("~/assets/css/chatbot.css") %>?v=1" rel="stylesheet" />
        <script src="<%= ResolveUrl("~/assets/js/chatbot.js") %>?v=1" defer="defer"></script>

        <div class="appnav-user">
            <span class="user-chip" title="Signed in as <%= Server.HtmlEncode(AuthService.CurrentUser()) %>">
                <i class="bi bi-person-circle"></i>
                <span class="u-name"><%= Server.HtmlEncode(AuthService.CurrentUser()) %></span>
                <% if (AuthService.CurrentRole().Length > 0) { %><span class="u-role"><%= Server.HtmlEncode(AuthService.CurrentRole()) %></span><% } %>
            </span>
            <form method="post" action="<%= ResolveUrl("~/Logout.aspx") %>" class="m-0">
                <button type="submit" class="btn-signout" title="Sign out"><i class="bi bi-box-arrow-right"></i><span>Sign out</span></button>
            </form>
        </div>
    </div>
</div>
