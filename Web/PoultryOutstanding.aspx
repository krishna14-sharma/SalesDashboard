<%@ Page Language="C#" AutoEventWireup="true" CodeFile="PoultryOutstanding.aspx.cs" Inherits="PoultryOutstanding" EnableViewState="false" %>
<%@ Register Src="~/Controls/OutstandingView.ascx" TagPrefix="uc" TagName="OutstandingView" %>
<!DOCTYPE html>
<html lang="en">
<head runat="server">
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>Poultry Products Customer Outstanding</title>
    <link rel="preconnect" href="https://fonts.googleapis.com" />
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin="anonymous" />
    <link href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@400;500;600;700;800&display=swap" rel="stylesheet" />
    <link href="https://cdnjs.cloudflare.com/ajax/libs/bootstrap/5.3.3/css/bootstrap.min.css" rel="stylesheet" />
    <link href="https://cdnjs.cloudflare.com/ajax/libs/bootstrap-icons/1.11.3/font/bootstrap-icons.min.css" rel="stylesheet" />
    <link href="assets/css/dashboard.css?v=4" rel="stylesheet" />
    <link href="assets/css/outstanding.css?v=1" rel="stylesheet" />
</head>
<body>
    <uc:OutstandingView runat="server" ID="view" NavKey="poultry" Icon="bi-basket2"
        Heading="Poultry Products Customer Outstanding"
        SubHeading="Feed · Medicine · Vaccine · Equipment — real-time receivables & aging" />

    <script>
        window.OS_CONFIG = { pageUrl: '<%= ResolveUrl("~/PoultryOutstanding.aspx") %>', kind: 'POULTRY', title: 'Poultry Products Customer Outstanding' };
    </script>
    <script src="https://cdnjs.cloudflare.com/ajax/libs/jquery/3.7.1/jquery.min.js"></script>
    <script src="https://cdnjs.cloudflare.com/ajax/libs/bootstrap/5.3.3/js/bootstrap.bundle.min.js"></script>
    <script src="https://cdnjs.cloudflare.com/ajax/libs/Chart.js/4.4.1/chart.umd.min.js"></script>
    <script src="assets/js/outstanding.js?v=3"></script>
</body>
</html>
