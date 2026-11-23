<%@ Control Language="C#" ClassName="OutstandingView" %>
<%@ Register Src="~/Controls/AppNav.ascx" TagPrefix="uc" TagName="AppNav" %>
<script runat="server">
    public string NavKey { get; set; }
    public string Heading { get; set; }
    public string SubHeading { get; set; }
    public string Icon { get; set; }

    protected void Page_Load(object sender, EventArgs e)
    {
        nav.Active = NavKey;
    }
</script>

<!-- ============ Top bar ============ -->
<nav class="topbar">
    <div class="container-xxl d-flex align-items-center gap-2 gap-md-3">
        <div class="brand-mark"><i class="bi <%= Icon %>"></i></div>
        <div class="flex-grow-1 min-w-0">
            <h1 class="brand-title"><%= Server.HtmlEncode(Heading) %></h1>
            <div class="brand-sub"><%= Server.HtmlEncode(SubHeading) %></div>
        </div>
        <div class="live-pill" title="Figures are read live from the database">
            <span class="live-dot" id="liveDot"></span>
            <span class="d-none d-sm-inline">Live&nbsp;·&nbsp;</span><span id="lblUpdated">--:--</span>
        </div>
        <button type="button" id="btnAuto" class="btn btn-icon active" title="Auto-refresh every 60 seconds: on" aria-pressed="true" aria-label="Toggle auto-refresh">
            <i class="bi bi-broadcast"></i>
        </button>
        <button type="button" id="btnRefresh" class="btn btn-icon" title="Refresh now" aria-label="Refresh now">
            <i class="bi bi-arrow-clockwise"></i>
        </button>
    </div>
</nav>
<uc:AppNav runat="server" ID="nav" />

<main class="container-xxl py-3 py-md-4">

    <!-- ============ Filters ============ -->
    <section class="filter-card card border-0 mb-3" aria-label="Filters">
        <div class="card-body">
            <div class="d-flex align-items-center justify-content-between d-lg-none mb-2">
                <span class="fw-semibold"><i class="bi bi-funnel me-1"></i>Filters <span id="filterHint" class="text-muted small fw-normal"></span></span>
                <button class="btn btn-sm btn-outline-secondary" type="button" data-bs-toggle="collapse"
                        data-bs-target="#filterBody" aria-expanded="true" aria-controls="filterBody">
                    <i class="bi bi-chevron-expand"></i>
                </button>
            </div>
            <div id="filterBody" class="collapse show">
                <div class="row g-2 g-md-3 align-items-end">
                    <div class="col-6 col-md-3 col-lg-2">
                        <label for="ddlSession" class="form-label">Session</label>
                        <select id="ddlSession" class="form-select"><option value="">All sessions</option></select>
                    </div>
                    <div class="col-6 col-md-3 col-lg-3">
                        <label for="ddlArea" class="form-label">Area</label>
                        <select id="ddlArea" class="form-select"><option value="">All areas</option></select>
                    </div>
                    <div class="col-6 col-md-3 col-lg-2">
                        <label for="txtAsOf" class="form-label">Outstanding as on</label>
                        <input type="date" id="txtAsOf" class="form-control" />
                    </div>
                    <div class="col-6 col-md-3 col-lg-3">
                        <label for="ddlAuth" class="form-label">Count payments</label>
                        <select id="ddlAuth" class="form-select">
                            <option value="0">All receipts</option>
                            <option value="1">Authorised receipts only</option>
                        </select>
                    </div>
                    <div class="col-12 col-lg-2 d-grid">
                        <button type="button" id="btnReset" class="btn btn-light border"><i class="bi bi-x-circle me-1"></i>Reset</button>
                    </div>
                </div>
            </div>
        </div>
    </section>

    <div id="alertBox" class="alert alert-danger d-none align-items-center gap-2" role="alert">
        <i class="bi bi-exclamation-triangle-fill"></i><span id="alertText"></span>
    </div>

    <!-- ============ KPIs ============ -->
    <section class="row g-2 g-md-3 mb-3" id="kpiRow" aria-label="Key figures"></section>

    <!-- ============ Aging ============ -->
    <section class="row g-2 g-md-3 mb-3">
        <div class="col-12 col-xl-5">
            <div class="card panel h-100">
                <div class="panel-head"><h3>Aging of outstanding</h3><span class="ms-auto small text-muted">tap a bucket to list its customers</span></div>
                <div class="p-3 pt-2">
                    <div class="age-strip" id="ageStrip"></div>
                    <div class="age-tiles" id="ageTiles"></div>
                    <p class="small text-muted mt-3 mb-0">
                        <i class="bi bi-info-circle me-1"></i>Each customer's payments are adjusted against their oldest supplies first.
                        Whatever is still unpaid on a supply is aged from its <b id="ageFromLbl">DM date</b> to the "as on" date.
                    </p>
                </div>
            </div>
        </div>
        <div class="col-12 col-xl-7">
            <div class="card panel h-100">
                <div class="panel-head"><h3>Top 10 customers by outstanding</h3></div>
                <div class="chart-box"><canvas id="chTop"></canvas></div>
            </div>
        </div>
    </section>

    <!-- ============ Area-wise ============ -->
    <section class="card panel mb-3">
        <div class="panel-head">
            <h3>Area-wise aging</h3>
            <button class="btn btn-sm btn-link ms-auto text-decoration-none" type="button" data-bs-toggle="collapse" data-bs-target="#areaBody" aria-expanded="true">
                <i class="bi bi-chevron-expand"></i>
            </button>
        </div>
        <div id="areaBody" class="collapse show">
            <div class="table-responsive table-wrap table-wrap-sm">
                <table class="table table-sm table-hover align-middle mb-0 data-table" id="tblArea"><thead></thead><tbody></tbody><tfoot></tfoot></table>
            </div>
        </div>
    </section>

    <!-- ============ Products ============ -->
    <section class="row g-2 g-md-3 mb-3" id="productSection">
        <div class="col-12 col-xl-7">
            <div class="card panel h-100">
                <div class="panel-head flex-wrap gap-2">
                    <h3>Product-wise sales &amp; outstanding</h3>
                    <span class="ms-auto small text-muted">tap a product to see who owes on it</span>
                </div>
                <div class="table-responsive table-wrap table-wrap-sm">
                    <table class="table table-sm table-hover align-middle mb-0 data-table" id="tblProd"><thead></thead><tbody></tbody><tfoot></tfoot></table>
                </div>
            </div>
        </div>
        <div class="col-12 col-xl-5">
            <div class="card panel h-100">
                <div class="panel-head"><h3>Outstanding by product &amp; age</h3></div>
                <div class="chart-box"><canvas id="chProd"></canvas></div>
            </div>
        </div>
    </section>

    <!-- ============ Customers ============ -->
    <section class="card panel mb-4">
        <div class="panel-head flex-wrap gap-2">
            <h3 class="me-2">Customers</h3>
            <div class="btn-group btn-group-sm status-chips" role="group" aria-label="Customer status">
                <input type="radio" class="btn-check" name="custStatus" id="stDue" value="due" checked="checked" />
                <label class="btn btn-outline-dark" for="stDue">With dues</label>
                <input type="radio" class="btn-check" name="custStatus" id="stAdv" value="adv" />
                <label class="btn btn-outline-dark" for="stAdv">Advance</label>
                <input type="radio" class="btn-check" name="custStatus" id="stAll" value="all" />
                <label class="btn btn-outline-dark" for="stAll">All</label>
            </div>
            <span id="bucketChip" class="bucket-chip d-none"></span>
            <select id="ddlProduct" class="form-select form-select-sm product-select" aria-label="Product">
                <option value="">All products</option>
            </select>
            <div class="d-flex gap-2 ms-auto table-tools">
                <div class="input-group input-group-sm">
                    <span class="input-group-text bg-white"><i class="bi bi-search"></i></span>
                    <input type="search" id="txtSearch" class="form-control" placeholder="Customer, code, area…" aria-label="Search customers" />
                </div>
                <button type="button" id="btnExport" class="btn btn-sm btn-outline-success text-nowrap"><i class="bi bi-filetype-csv me-1"></i>Export</button>
            </div>
        </div>

        <!-- desktop / tablet table -->
        <div class="table-responsive table-wrap d-none d-md-block">
            <table class="table table-sm table-hover align-middle mb-0 data-table cust-table" id="tblCust"><thead></thead><tbody></tbody><tfoot></tfoot></table>
        </div>
        <!-- phone cards -->
        <div class="d-md-none cust-cards" id="custCards"></div>

        <div class="d-flex align-items-center flex-wrap gap-2 px-3 py-2 border-top">
            <span class="small text-muted" id="lblRows"></span>
            <button type="button" id="btnMore" class="btn btn-sm btn-outline-secondary ms-auto d-none">Show more</button>
        </div>
    </section>
</main>

<!-- ============ Customer detail ============ -->
<div class="modal fade" id="custModal" tabindex="-1" aria-labelledby="custName" aria-hidden="true">
    <div class="modal-dialog modal-xl modal-fullscreen-lg-down modal-dialog-scrollable">
        <div class="modal-content">
            <div class="modal-header cust-head">
                <div class="min-w-0 me-2">
                    <h2 class="modal-title" id="custName">Customer</h2>
                    <div class="small text-muted" id="custMeta"></div>
                </div>
                <div class="ms-auto d-flex gap-2 no-print">
                    <button type="button" class="btn btn-sm btn-outline-secondary" id="btnPrint" title="Print statement"><i class="bi bi-printer"></i><span class="d-none d-sm-inline ms-1">Print</span></button>
                    <button type="button" class="btn btn-sm btn-outline-success" id="btnCustExport" title="Export statement"><i class="bi bi-filetype-csv"></i><span class="d-none d-sm-inline ms-1">Export</span></button>
                    <button type="button" class="btn-close ms-1" data-bs-dismiss="modal" aria-label="Close"></button>
                </div>
            </div>
            <div class="modal-body">
                <div class="print-only mb-2" id="printTitle"></div>
                <div class="row g-2 mb-3" id="custKpis"></div>
                <div class="mb-3">
                    <div class="small text-uppercase fw-bold text-muted mb-1">Aging of this customer's outstanding</div>
                    <div class="age-strip age-strip-sm" id="custStrip"></div>
                    <div class="age-legend" id="custAgeLegend"></div>
                </div>

                <ul class="nav nav-pills detail-tabs mb-2 no-print" id="custTabs">
                    <li class="nav-item"><button type="button" class="nav-link active" data-pane="bills">Outstanding supplies</button></li>
                    <li class="nav-item"><button type="button" class="nav-link" data-pane="prods">Products</button></li>
                    <li class="nav-item"><button type="button" class="nav-link" data-pane="pays">Payments</button></li>
                    <li class="nav-item"><button type="button" class="nav-link" data-pane="stmt">Statement</button></li>
                </ul>

                <div class="cust-pane" id="paneBills">
                    <div class="d-flex align-items-center flex-wrap gap-2 mb-2 no-print">
                        <div class="form-check form-switch mb-0">
                            <input class="form-check-input" type="checkbox" id="chkSettled" />
                            <label class="form-check-label small" for="chkSettled">Show settled supplies too</label>
                        </div>
                        <button type="button" class="btn btn-sm btn-link text-decoration-none ms-auto" id="btnExpandAll">Expand all</button>
                    </div>
                    <div id="billList"></div>
                </div>
                <div class="cust-pane d-none" id="paneProds">
                    <div class="table-responsive"><table class="table table-sm align-middle data-table" id="tblCustProd"><thead></thead><tbody></tbody><tfoot></tfoot></table></div>
                    <div class="small text-muted">Outstanding on a supply is shared among its products in proportion to their value on that supply.</div>
                </div>
                <div class="cust-pane d-none" id="panePays">
                    <div class="table-responsive"><table class="table table-sm align-middle data-table" id="tblPays"><thead></thead><tbody></tbody><tfoot></tfoot></table></div>
                </div>
                <div class="cust-pane d-none" id="paneStmt">
                    <div class="table-responsive"><table class="table table-sm align-middle data-table" id="tblStmt"><thead></thead><tbody></tbody><tfoot></tfoot></table></div>
                </div>
            </div>
        </div>
    </div>
</div>

<div id="loader" class="loader" aria-live="polite">
    <div class="spinner-border text-warning" role="status"></div><span class="ms-2">Loading…</span>
</div>
