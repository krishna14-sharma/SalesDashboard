<%@ Page Language="C#" AutoEventWireup="true" CodeFile="Default.aspx.cs" Inherits="_Default" EnableViewState="false" %>
<%@ Register Src="~/Controls/AppNav.ascx" TagPrefix="uc" TagName="AppNav" %>
<!DOCTYPE html>
<html lang="en">
<head runat="server">
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>Chick Sales &amp; Payment Dashboard</title>

    <link rel="preconnect" href="https://fonts.googleapis.com" />
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin="anonymous" />
    <link href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@400;500;600;700;800&display=swap" rel="stylesheet" />
    <link href="https://cdnjs.cloudflare.com/ajax/libs/bootstrap/5.3.3/css/bootstrap.min.css" rel="stylesheet" />
    <link href="https://cdnjs.cloudflare.com/ajax/libs/bootstrap-icons/1.11.3/font/bootstrap-icons.min.css" rel="stylesheet" />
    <link href="assets/css/dashboard.css?v=4" rel="stylesheet" />
</head>
<body>

    <!-- ============ Top bar ============ -->
    <nav class="topbar">
        <div class="container-xxl d-flex align-items-center gap-3">
            <div class="brand-mark"><i class="bi bi-egg-fried"></i></div>
            <div class="flex-grow-1 min-w-0">
                <h1 class="brand-title">Chick Sales &amp; Payment Dashboard</h1>
                <div class="brand-sub">Dispatch memos &middot; Payment receipts &middot; Outstanding</div>
            </div>
            <div class="d-none d-md-block text-end small text-white-50 me-1">
                Updated <span id="lblUpdated">&mdash;</span>
            </div>
            <button type="button" id="btnRefresh" class="btn btn-icon" title="Refresh data" aria-label="Refresh data">
                <i class="bi bi-arrow-clockwise"></i>
            </button>
        </div>
    </nav>
    <uc:AppNav runat="server" ID="nav" Active="sales" />

    <main class="container-xxl py-3 py-md-4">

        <!-- ============ Filters ============ -->
        <section class="filter-card card border-0 mb-3" aria-label="Filters">
            <div class="card-body">
                <div class="d-flex align-items-center justify-content-between d-lg-none mb-2">
                    <span class="fw-semibold"><i class="bi bi-funnel me-1"></i>Filters</span>
                    <button class="btn btn-sm btn-outline-secondary" type="button" data-bs-toggle="collapse"
                            data-bs-target="#filterBody" aria-expanded="true" aria-controls="filterBody">
                        <i class="bi bi-chevron-expand"></i>
                    </button>
                </div>
                <div id="filterBody" class="collapse show">
                    <div class="row g-2 g-md-3 align-items-end">
                        <div class="col-6 col-md-4 col-lg-2">
                            <label for="ddlSession" class="form-label">Session</label>
                            <select id="ddlSession" class="form-select"><option value="">Loading…</option></select>
                        </div>
                        <div class="col-6 col-md-4 col-lg-2">
                            <label for="ddlArea" class="form-label">Area</label>
                            <select id="ddlArea" class="form-select"><option value="">All areas</option></select>
                        </div>
                        <div class="col-12 col-md-4 col-lg-4">
                            <span class="form-label d-block">Chick type</span>
                            <div class="btn-group w-100 type-switch" role="group" aria-label="Chick type">
                                <input type="radio" class="btn-check" name="chickType" id="ctAll" value="" checked="checked" />
                                <label class="btn btn-outline-dark" for="ctAll">All</label>
                                <input type="radio" class="btn-check" name="chickType" id="ctBroiler" value="Broiler" />
                                <label class="btn btn-outline-dark" for="ctBroiler"><span class="dot dot-broiler"></span>Broiler</label>
                                <input type="radio" class="btn-check" name="chickType" id="ctLayer" value="Layer" />
                                <label class="btn btn-outline-dark" for="ctLayer"><span class="dot dot-layer"></span>Layer</label>
                                <input type="radio" class="btn-check" name="chickType" id="ctCockrel" value="Cockrel" />
                                <label class="btn btn-outline-dark" for="ctCockrel"><span class="dot dot-cockrel"></span>Cockrel</label>
                            </div>
                        </div>
                        <div class="col-6 col-md-4 col-lg-1-5">
                            <label for="txtFrom" class="form-label">From</label>
                            <input type="date" id="txtFrom" class="form-control" />
                        </div>
                        <div class="col-6 col-md-4 col-lg-1-5">
                            <label for="txtTo" class="form-label">To</label>
                            <input type="date" id="txtTo" class="form-control" />
                        </div>
                        <div class="col-12 col-md-4 col-lg-1 d-grid">
                            <button type="button" id="btnReset" class="btn btn-light border">
                                <i class="bi bi-x-circle me-1"></i>Reset
                            </button>
                        </div>
                    </div>
                </div>
            </div>
        </section>

        <div id="alertBox" class="alert alert-danger d-none d-flex align-items-center gap-2" role="alert">
            <i class="bi bi-exclamation-triangle-fill"></i><span id="alertText"></span>
        </div>

        <div id="emptyState" class="empty-state d-none">
            <i class="bi bi-inbox"></i>
            <p class="mb-0">No sales or payments found for the selected filters.</p>
        </div>

        <div id="dashBody">
            <!-- ============ KPI cards ============ -->
            <section class="row g-2 g-md-3 mb-3" id="kpiRow" aria-label="Key figures"></section>

            <!-- ============ Chick type cards ============ -->
            <h2 class="section-title">Chick type wise</h2>
            <section class="row g-2 g-md-3 mb-3" id="typeRow" aria-label="Chick type summary"></section>

            <!-- ============ Charts ============ -->
            <section class="row g-2 g-md-3 mb-3">
                <div class="col-12 col-lg-5">
                    <div class="card panel h-100">
                        <div class="panel-head"><h3>Sales vs payment by chick type</h3></div>
                        <div class="chart-box"><canvas id="chType"></canvas></div>
                    </div>
                </div>
                <div class="col-12 col-lg-7">
                    <div class="card panel h-100">
                        <div class="panel-head"><h3>Monthly sales, payments &amp; running outstanding</h3></div>
                        <div class="chart-box"><canvas id="chTrend"></canvas></div>
                    </div>
                </div>
                <div class="col-12 col-lg-7">
                    <div class="card panel h-100">
                        <div class="panel-head"><h3>Monthly chicks dispatched (net)</h3></div>
                        <div class="chart-box"><canvas id="chChicks"></canvas></div>
                    </div>
                </div>
                <div class="col-12 col-lg-5">
                    <div class="card panel h-100">
                        <div class="panel-head"><h3>Payment received by mode</h3></div>
                        <div class="chart-box chart-box-sm"><canvas id="chPayMode"></canvas></div>
                        <div class="px-3 pb-3">
                            <div class="small text-uppercase text-muted fw-semibold mb-1">By payment type</div>
                            <div id="payTypeList" class="paytype-list"></div>
                        </div>
                    </div>
                </div>
                <div class="col-12">
                    <div class="card panel">
                        <div class="panel-head"><h3>Top areas &mdash; sales vs payment</h3></div>
                        <div class="chart-box chart-box-lg"><canvas id="chArea"></canvas></div>
                    </div>
                </div>
            </section>

            <!-- ============ Detail tables ============ -->
            <section class="card panel mb-4">
                <div class="panel-head flex-wrap gap-2">
                    <ul class="nav nav-pills detail-tabs" role="tablist">
                        <li class="nav-item" role="presentation">
                            <button class="nav-link active" data-table="areas" type="button" role="tab">Area summary</button>
                        </li>
                        <li class="nav-item" role="presentation">
                            <button class="nav-link" data-table="customers" type="button" role="tab">Customer outstanding</button>
                        </li>
                        <li class="nav-item" role="presentation">
                            <button class="nav-link" data-table="receipts" type="button" role="tab">Payment receipts</button>
                        </li>
                        <li class="nav-item" role="presentation">
                            <button class="nav-link" data-table="dms" type="button" role="tab">Dispatch memos</button>
                        </li>
                    </ul>
                    <div class="d-flex gap-2 ms-auto table-tools">
                        <div class="input-group input-group-sm">
                            <span class="input-group-text bg-white"><i class="bi bi-search"></i></span>
                            <input type="search" id="txtSearch" class="form-control" placeholder="Search…" aria-label="Search table" />
                        </div>
                        <button type="button" id="btnExport" class="btn btn-sm btn-outline-success text-nowrap">
                            <i class="bi bi-filetype-csv me-1"></i>Export
                        </button>
                    </div>
                </div>
                <div class="tab-content">
                    <div class="tab-pane fade show active" id="tabTable" role="tabpanel">
                        <div class="table-responsive table-wrap">
                            <table class="table table-sm table-hover align-middle mb-0 data-table" id="tblData">
                                <thead></thead><tbody></tbody><tfoot></tfoot>
                            </table>
                        </div>
                        <div class="px-3 py-2 small text-muted" id="lblRows"></div>
                    </div>
                </div>
            </section>
        </div>
    </main>

    <!-- loading overlay -->
    <div id="loader" class="loader" aria-live="polite" aria-busy="true">
        <div class="spinner-border text-warning" role="status"></div>
        <span class="ms-2">Loading…</span>
    </div>

    <script>
        window.DASH_CONFIG = { pageUrl: '<%= ResolveUrl("~/Default.aspx") %>' };
    </script>
    <script src="https://cdnjs.cloudflare.com/ajax/libs/jquery/3.7.1/jquery.min.js"></script>
    <script src="https://cdnjs.cloudflare.com/ajax/libs/bootstrap/5.3.3/js/bootstrap.bundle.min.js"></script>
    <script src="https://cdnjs.cloudflare.com/ajax/libs/Chart.js/4.4.1/chart.umd.min.js"></script>
    <script src="assets/js/dashboard.js?v=1"></script>
</body>
</html>
