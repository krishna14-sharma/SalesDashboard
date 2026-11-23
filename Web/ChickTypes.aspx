<%@ Page Language="C#" AutoEventWireup="true" CodeFile="ChickTypes.aspx.cs" Inherits="ChickTypes" EnableViewState="false" %>
<%@ Register Src="~/Controls/AppNav.ascx" TagPrefix="uc" TagName="AppNav" %>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>Chick Type-wise Outstanding</title>
    <link rel="preconnect" href="https://fonts.googleapis.com" />
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin="anonymous" />
    <link href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@400;500;600;700;800&display=swap" rel="stylesheet" />
    <link href="https://cdnjs.cloudflare.com/ajax/libs/bootstrap/5.3.3/css/bootstrap.min.css" rel="stylesheet" />
    <link href="https://cdnjs.cloudflare.com/ajax/libs/bootstrap-icons/1.11.3/font/bootstrap-icons.min.css" rel="stylesheet" />
    <link href="assets/css/dashboard.css?v=4" rel="stylesheet" />
    <link href="assets/css/outstanding.css?v=2" rel="stylesheet" />
    <link href="assets/css/chick-types.css?v=2" rel="stylesheet" />
</head>
<body>
    <nav class="topbar">
        <div class="container-xxl d-flex align-items-center gap-2 gap-md-3">
            <div class="brand-mark"><i class="bi bi-grid-3x3-gap"></i></div>
            <div class="flex-grow-1 min-w-0">
                <h1 class="brand-title">Chick Type-wise Outstanding</h1>
                <div class="brand-sub">Last hatch date and dues for Broiler, Layer and Cockrel, from bills and the accounts ledger</div>
            </div>
            <div class="live-pill" title="Figures are read live from the database"><span class="live-dot"></span><span id="lblUpdated">--:--</span></div>
            <button type="button" id="btnRefresh" class="btn btn-icon" title="Refresh now" aria-label="Refresh now"><i class="bi bi-arrow-clockwise"></i></button>
        </div>
    </nav>
    <uc:AppNav runat="server" ID="nav" Active="types" />

    <main class="container-xxl py-3 py-md-4">
        <section class="filter-card card border-0 mb-3" aria-label="Filters">
            <div class="card-body">
                <div class="d-flex align-items-center justify-content-between d-lg-none mb-2">
                    <span class="fw-semibold"><i class="bi bi-funnel me-1"></i>Filters</span>
                    <button class="btn btn-sm btn-outline-secondary" type="button" data-bs-toggle="collapse" data-bs-target="#filterBody" aria-expanded="true" aria-controls="filterBody"><i class="bi bi-chevron-expand"></i></button>
                </div>
                <div id="filterBody" class="collapse show">
                    <div class="row g-2 g-md-3 align-items-end">
                        <div class="col-6 col-md-4 col-lg-4">
                            <label for="ddlStation" class="form-label">Station</label>
                            <select id="ddlStation" class="form-select"><option value="">All stations</option></select>
                        </div>
                        <div class="col-6 col-md-4 col-lg-3">
                            <label for="txtAsOf" class="form-label">Outstanding as on</label>
                            <input type="date" id="txtAsOf" class="form-control" />
                        </div>
                        <div class="col-12 col-md-4 col-lg-3 d-flex align-items-end">
                            <p class="ledger-info mb-0" id="ledgerInfo"></p>
                        </div>
                        <div class="col-12 col-lg-2 d-grid">
                            <button type="button" id="btnReset" class="btn btn-light border"><i class="bi bi-x-circle me-1"></i>Reset</button>
                        </div>
                    </div>
                </div>
            </div>
        </section>

        <div id="alertBox" class="alert alert-danger d-none" role="alert"></div>

        <!-- one card per chick type -->
        <section class="row g-2 g-md-3 mb-2" id="typeCards" aria-label="Chick types"></section>
        <p class="type-note" id="typeNote"></p>

        <!-- customers -->
        <section class="card panel mb-4">
            <div class="panel-head flex-wrap gap-2">
                <h3 class="me-2">Customers</h3>
                <div class="btn-group btn-group-sm status-chips" role="group" aria-label="Show">
                    <input type="radio" class="btn-check" name="show" id="shDue" value="due" checked="checked" />
                    <label class="btn btn-outline-dark" for="shDue">With dues</label>
                    <input type="radio" class="btn-check" name="show" id="shAll" value="all" />
                    <label class="btn btn-outline-dark" for="shAll">All customers</label>
                </div>
                <select id="ddlType" class="form-select form-select-sm product-select" aria-label="Chick type">
                    <option value="">All chick types</option>
                    <option value="Br">Broiler customers</option>
                    <option value="Ly">Layer customers</option>
                    <option value="Ck">Cockrel customers</option>
                    <option value="Ot">Opening &amp; other dues</option>
                </select>
                <div class="d-flex gap-2 ms-auto table-tools">
                    <div class="input-group input-group-sm">
                        <span class="input-group-text bg-white"><i class="bi bi-search"></i></span>
                        <input type="search" id="txtSearch" class="form-control" placeholder="Customer, code, area" aria-label="Search customers" />
                    </div>
                    <button type="button" id="btnExport" class="btn btn-sm btn-outline-success text-nowrap"><i class="bi bi-filetype-csv me-1"></i>Export</button>
                </div>
            </div>
            <div class="table-responsive table-wrap d-none d-md-block">
                <table class="table table-sm table-hover align-middle mb-0 data-table ct-table" id="tblCust"><thead></thead><tbody></tbody><tfoot></tfoot></table>
            </div>
            <div class="d-md-none ct-cards" id="custCards"></div>
            <div class="d-flex align-items-center flex-wrap gap-2 px-3 py-2 border-top">
                <span class="small text-muted" id="lblRows"></span>
                <button type="button" id="btnMore" class="btn btn-sm btn-outline-secondary ms-auto d-none">Show more</button>
            </div>
        </section>
    </main>

    <!-- customer detail -->
    <div class="modal fade" id="custModal" tabindex="-1" aria-labelledby="custName" aria-hidden="true">
        <div class="modal-dialog modal-xl modal-fullscreen-lg-down modal-dialog-scrollable">
            <div class="modal-content">
                <div class="modal-header cust-head">
                    <div class="min-w-0 me-2">
                        <h2 class="modal-title" id="custName">Customer</h2>
                        <div class="small text-muted" id="custMeta"></div>
                    </div>
                    <button type="button" class="btn-close ms-auto" data-bs-dismiss="modal" aria-label="Close"></button>
                </div>
                <div class="modal-body" id="custBody"></div>
            </div>
        </div>
    </div>

    <div id="loader" class="loader" aria-live="polite"><div class="spinner-border text-warning" role="status"></div><span class="ms-2">Loading…</span></div>

    <script>
        window.CT_CONFIG = { pageUrl: '<%= ResolveUrl("~/ChickTypes.aspx") %>' };
    </script>
    <script src="https://cdnjs.cloudflare.com/ajax/libs/jquery/3.7.1/jquery.min.js"></script>
    <script src="https://cdnjs.cloudflare.com/ajax/libs/bootstrap/5.3.3/js/bootstrap.bundle.min.js"></script>
    <script src="assets/js/chick-types.js?v=2"></script>
</body>
</html>
