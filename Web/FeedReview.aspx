<%@ Page Language="C#" AutoEventWireup="true" CodeFile="FeedReview.aspx.cs" Inherits="FeedReview" EnableViewState="false" %>
<%@ Register Src="~/Controls/AppNav.ascx" TagPrefix="uc" TagName="AppNav" %>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>Feed Sale Review</title>
    <link rel="preconnect" href="https://fonts.googleapis.com" />
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin="anonymous" />
    <link href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@400;500;600;700;800&family=Space+Grotesk:wght@500;600;700&display=swap" rel="stylesheet" />
    <link href="https://cdnjs.cloudflare.com/ajax/libs/bootstrap/5.3.3/css/bootstrap.min.css" rel="stylesheet" />
    <link href="https://cdnjs.cloudflare.com/ajax/libs/bootstrap-icons/1.11.3/font/bootstrap-icons.min.css" rel="stylesheet" />
    <link href="assets/css/dashboard.css?v=4" rel="stylesheet" />
    <link href="assets/css/feed-review.css?v=1" rel="stylesheet" />
</head>
<body class="fr">
    <nav class="topbar no-print">
        <div class="container-xxl d-flex align-items-center gap-3">
            <div class="brand-mark"><i class="bi bi-journal-text"></i></div>
            <div class="flex-grow-1 min-w-0">
                <h1 class="brand-title">Feed Sale Review</h1>
                <div class="brand-sub">Feed division sales, customers and outstanding for any period</div>
            </div>
            <button type="button" id="btnPrint" class="btn btn-icon" title="Print or save as PDF" aria-label="Print or save as PDF"><i class="bi bi-printer"></i></button>
            <button type="button" id="btnRefresh" class="btn btn-icon" title="Refresh" aria-label="Refresh"><i class="bi bi-arrow-clockwise"></i></button>
        </div>
    </nav>
    <div class="no-print"><uc:AppNav runat="server" ID="nav" Active="feed" /></div>

    <!-- ============ period picker ============ -->
    <section class="period-bar no-print" aria-label="Time period">
        <div class="container-xxl">
            <div class="period-inner">
                <div class="presets" role="group" aria-label="Quick periods" id="presets">
                    <button type="button" data-preset="fy">This FY</button>
                    <button type="button" data-preset="lastfy">Last FY</button>
                    <button type="button" data-preset="quarter">This quarter</button>
                    <button type="button" data-preset="last3">Last 3 months</button>
                    <button type="button" data-preset="month">This month</button>
                    <button type="button" data-preset="lastmonth">Last month</button>
                </div>
                <div class="custom">
                    <label>From <input type="date" id="txtFrom" class="form-control form-control-sm" /></label>
                    <label>To <input type="date" id="txtTo" class="form-control form-control-sm" /></label>
                    <select id="ddlGroup" class="form-select form-select-sm" aria-label="Feed type">
                        <option value="">All feed</option>
                        <option value="Broiler">Broiler</option>
                        <option value="Layer">Layer</option>
                        <option value="Sonali">Sonali</option>
                        <option value="Other">Other feed</option>
                    </select>
                    <select id="ddlArea" class="form-select form-select-sm" aria-label="Area"><option value="">All areas</option></select>
                </div>
            </div>
        </div>
    </section>

    <div class="container-xxl"><div id="alertBox" class="alert alert-danger d-none mt-3" role="alert"></div></div>

    <main id="review" class="review">
        <!-- 1. cover -->
        <section class="sheet cover">
            <div class="container-xxl">
                <p class="kicker">Feed division sales review</p>
                <h2 class="cover-title"><span id="coverTitle">Feed Sale Review</span></h2>
                <p class="cover-period" id="coverPeriod">&nbsp;</p>
                <p class="cover-meta" id="coverMeta">&nbsp;</p>
            </div>
        </section>

        <div id="emptyState" class="container-xxl d-none">
            <div class="empty"><i class="bi bi-inbox"></i><p>No feed sales in this period. Pick a longer period or another area.</p></div>
        </div>

        <div id="reviewBody">
            <!-- 2. at a glance -->
            <section class="sheet">
                <div class="container-xxl">
                    <p class="kicker" id="glanceKicker">At a glance</p>
                    <h3 class="finding" id="glanceTitle">&nbsp;</h3>
                    <div class="glance" id="glance"></div>
                    <p class="note" id="glanceNote"></p>
                </div>
            </section>

            <!-- 3. month-wise -->
            <section class="sheet">
                <div class="container-xxl">
                    <p class="kicker">Month-wise sales</p>
                    <h3 class="finding" id="monthTitle">&nbsp;</h3>
                    <div class="months-scroll"><div class="months" id="months"></div></div>
                    <p class="note" id="monthNote"></p>
                </div>
            </section>

            <!-- 4. product mix -->
            <section class="sheet">
                <div class="container-xxl">
                    <p class="kicker">Product mix</p>
                    <h3 class="finding" id="mixTitle">&nbsp;</h3>
                    <div class="mix-bar" id="mixBar"></div>
                    <div class="mix-legend" id="mixLegend"></div>
                    <h4 class="sub-head">Top products by sales value</h4>
                    <div class="hbars" id="productBars"></div>
                    <p class="note" id="mixNote"></p>
                </div>
            </section>

            <!-- 5. salesperson -->
            <section class="sheet">
                <div class="container-xxl">
                    <p class="kicker">Salesperson-wise</p>
                    <h3 class="finding" id="spTitle">&nbsp;</h3>
                    <div class="table-responsive">
                        <table class="sp-table" id="spTable"><thead></thead><tbody></tbody></table>
                    </div>
                    <p class="note" id="spNote"></p>
                </div>
            </section>

            <!-- 6. top by quantity -->
            <section class="sheet">
                <div class="container-xxl">
                    <p class="kicker">Highest feed purchase by quantity</p>
                    <h3 class="finding" id="qtyTitle">&nbsp;</h3>
                    <ol class="rank" id="qtyRank"></ol>
                    <p class="note" id="qtyNote"></p>
                </div>
            </section>

            <!-- 7. outstanding -->
            <section class="sheet">
                <div class="container-xxl">
                    <p class="kicker" id="osKicker">Customer-wise outstanding</p>
                    <h3 class="finding" id="osTitle">&nbsp;</h3>
                    <div class="os-list" id="osList"></div>
                    <p class="note" id="osNote"></p>
                </div>
            </section>

            <!-- 8. points for attention -->
            <section class="sheet dark">
                <div class="container-xxl">
                    <p class="kicker">Summary</p>
                    <h3 class="finding">Points for attention</h3>
                    <div class="points" id="points"></div>
                </div>
            </section>

            <!-- 9. detailed tables -->
            <section class="sheet detail no-print">
                <div class="container-xxl">
                    <div class="d-flex flex-wrap align-items-center gap-2 mb-2">
                        <h3 class="finding m-0 me-auto">Detailed tables</h3>
                        <div class="tabs" role="tablist" id="tabs">
                            <button type="button" class="active" data-t="customers">Customers</button>
                            <button type="button" data-t="months">Month-wise</button>
                            <button type="button" data-t="products">Products</button>
                            <button type="button" data-t="custmonth">Customer × month</button>
                        </div>
                        <input type="search" id="txtSearch" class="form-control form-control-sm search" placeholder="Search" aria-label="Search table" />
                        <button type="button" id="btnExport" class="btn btn-sm btn-outline-success"><i class="bi bi-filetype-csv me-1"></i>Export</button>
                    </div>
                    <div class="table-responsive table-wrap">
                        <table class="table table-sm table-hover align-middle mb-0 data-table" id="tblData"><thead></thead><tbody></tbody><tfoot></tfoot></table>
                    </div>
                    <p class="note" id="tblNote"></p>
                </div>
            </section>
        </div>
    </main>

    <div id="loader" class="loader" aria-live="polite"><div class="spinner-border text-warning" role="status"></div><span class="ms-2">Loading…</span></div>

    <script>
        window.FR_CONFIG = { pageUrl: '<%= ResolveUrl("~/FeedReview.aspx") %>', user: '<%= HttpUtility.JavaScriptStringEncode(AuthService.CurrentUser()) %>' };
    </script>
    <script src="https://cdnjs.cloudflare.com/ajax/libs/jquery/3.7.1/jquery.min.js"></script>
    <script src="https://cdnjs.cloudflare.com/ajax/libs/bootstrap/5.3.3/js/bootstrap.bundle.min.js"></script>
    <script src="assets/js/feed-review.js?v=1"></script>
</body>
</html>
