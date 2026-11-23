<%@ Page Language="C#" AutoEventWireup="true" EnableViewState="false" %>
<script runat="server">
    // Signs the user out (POST from the "Sign out" button) and returns to the login page.
    protected void Page_Load(object sender, EventArgs e)
    {
        if (string.Equals(Request.HttpMethod, "POST", StringComparison.OrdinalIgnoreCase))
        {
            AuthService.Logout();
            Response.Redirect(ResolveUrl("~/Login.aspx?r=out"), false);
        }
        else
        {
            Response.Redirect(ResolveUrl("~/Default.aspx"), false);
        }
        Context.ApplicationInstance.CompleteRequest();
    }
</script>
