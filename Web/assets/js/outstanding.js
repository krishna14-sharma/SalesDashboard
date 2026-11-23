/* ===== Customer Outstanding & Aging - client script =====
   Used by ChickOutstanding.aspx (kind CHICK) and PoultryOutstanding.aspx (kind POULTRY).
   All data comes from the page's [WebMethod]s through jQuery AJAX - no page reloads.
   Auto-refresh re-reads the live figures every 60 seconds while the tab is visible. */
(function ($) {
    'use strict';

    var cfg = window.OS_CONFIG || { pageUrl: 'ChickOutstanding.aspx', kind: 'CHICK', title: 'Customer Outstanding' };
    var KIND = cfg.kind;
    var BY_HATCH = KIND === 'CHICK';          // chick supplies are aged from the hatch date
    var LEDGER = !!cfg.ledger;                // chick page: PrintData bills + VENTRY ledger + ACC_HEAD opening
    function billLabel(x) {
        if (!LEDGER) return 'DM ' + x.DMNo;
        return /^\d+$/.test(String(x.DMNo)) ? 'Bill ' + x.DMNo : String(x.DMNo);
    }
    function isChickBill(x) { return !LEDGER || /^\d+$/.test(String(x.DMNo)) || num(x.QtyNos) > 0; }
    var AUTO_MS = 60000;
    var PAGE = 50;

    var BUCKETS = [
        { key: 'B0', cnt: 'C0', label: '0–30 days',   short: '0–30',   color: '#2e8b57', cls: 'b0' },
        { key: 'B1', cnt: 'C1', label: '31–60 days',  short: '31–60',  color: '#8fae2f', cls: 'b1' },
        { key: 'B2', cnt: 'C2', label: '61–90 days',  short: '61–90',  color: '#e09a1a', cls: 'b2' },
        { key: 'B3', cnt: 'C3', label: '91–180 days', short: '91–180', color: '#e0662b', cls: 'b3' },
        { key: 'B4', cnt: 'C4', label: 'Over 180 days', short: '180+', color: '#b0302a', cls: 'b4' }
    ];

    var state = { session: '', areaCode: '', asOf: '', authOnly: false };
    var today = '';
    var data = null;
    var view = { status: 'due', bucket: -1, sortKey: 'Outstanding', sortDir: -1, limit: PAGE, product: '' };
    var prod = { products: [], productCustomers: [] };
    var prodChart = null;
    var cust = { key: null, detail: null };
    var chart = null;
    var autoOn = true, autoTimer = null;

    // ------------------------------------------------------------ formatting
    var nfInt = new Intl.NumberFormat('en-IN', { maximumFractionDigits: 0 });
    var nf2 = new Intl.NumberFormat('en-IN', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
    var nfQty = new Intl.NumberFormat('en-IN', { maximumFractionDigits: 2 });
    function num(v) { v = Number(v); return isFinite(v) ? v : 0; }
    function fInt(v) { return nfInt.format(num(v)); }
    function fAmt(v) { return nf2.format(num(v)); }
    function fMoney(v) { return '₹' + nf2.format(num(v)); }
    function fPct(v) { return num(v).toFixed(1) + '%'; }
    function fShort(v) {
        v = num(v); var a = Math.abs(v);
        if (a >= 1e7) return '₹' + (v / 1e7).toFixed(2) + ' Cr';
        if (a >= 1e5) return '₹' + (v / 1e5).toFixed(2) + ' L';
        return '₹' + nfInt.format(v);
    }
    function fDate(s) {
        if (!s) return '';
        var p = String(s).split('-');
        return p.length === 3 ? p[2] + '-' + p[1] + '-' + p[0] : s;
    }
    function esc(s) {
        return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) {
            return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
        });
    }
    function bucketOf(days) {
        days = num(days);
        return days <= 30 ? 0 : days <= 60 ? 1 : days <= 90 ? 2 : days <= 180 ? 3 : 4;
    }
    function ageBadge(days) {
        var b = BUCKETS[bucketOf(days)];
        return '<span class="age-badge" style="background:' + b.color + '" title="' + b.label + '">' + fInt(days) + ' d</span>';
    }

    // ------------------------------------------------------------ AJAX
    function callApi(method, payload) {
        return $.ajax({
            type: 'POST',
            url: cfg.pageUrl + '/' + method,
            data: JSON.stringify(payload || {}),
            contentType: 'application/json; charset=utf-8',
            dataType: 'json',
            timeout: 150000
        }).then(function (resp) {
            var r = resp && resp.d;
            if (!r || !r.ok) return $.Deferred().reject(r && r.error ? r.error : 'Unexpected server response.').promise();
            return r.data;
        }, function (xhr, status) {
            if (xhr.status === 401 || xhr.status === 403 || status === 'parsererror') {
                // sign-in expired: the server answered with the login page instead of data
                window.location.href = 'Login.aspx?ReturnUrl=' + encodeURIComponent(window.location.pathname + window.location.search);
                return $.Deferred().promise();   // never resolves; the page is navigating away
            }
            var msg = status === 'timeout' ? 'The server took too long to respond.' : 'Server error (' + (xhr.status || 'network') + ').';
            try { if (xhr.responseJSON && xhr.responseJSON.Message) msg = xhr.responseJSON.Message; } catch (e) { /* ignore */ }
            return $.Deferred().reject(msg).promise();
        });
    }
    var busy = 0;
    function loading(on) {
        busy = Math.max(0, busy + (on ? 1 : -1));
        $('#loader').toggleClass('show', busy > 0);
    }
    function spin(on) { $('#btnRefresh').toggleClass('spinning', on); }
    function showError(msg) { $('#alertText').text(msg); $('#alertBox').removeClass('d-none').addClass('d-flex'); }
    function clearError() { $('#alertBox').addClass('d-none').removeClass('d-flex'); }

    // ------------------------------------------------------------ filters
    function readFilters() {
        state.session = $('#ddlSession').val() || '';
        state.areaCode = $('#ddlArea').val() || '';
        state.asOf = $('#txtAsOf').val() || today;
        state.authOnly = $('#ddlAuth').val() === '1';
        var hint = [LEDGER ? '' : (state.session || 'All sessions'), state.areaCode ? $('#ddlArea option:selected').text() : (LEDGER ? 'All stations' : 'All areas'), 'as on ' + fDate(state.asOf)].filter(Boolean);
        $('#filterHint').text('· ' + hint.join(' · '));
    }

    function loadFilters() {
        loading(true);
        return callApi('GetFilters', {})
            .done(function (f) {
                today = f.today || new Date().toISOString().slice(0, 10);
                if (LEDGER && f.ledgerFrom) $('#filterHint').attr('title', 'Ledger ' + fDate(f.ledgerFrom) + ' to ' + fDate(f.ledgerTo));
                var $s = $('#ddlSession').empty().append('<option value="">All sessions</option>');
                (f.sessions || []).forEach(function (s) { $s.append($('<option>').val(s).text(s)); });
                var $a = $('#ddlArea').empty().append('<option value="">' + (LEDGER ? 'All stations' : 'All areas') + '</option>');
                (f.areas || []).forEach(function (a) {
                    $a.append($('<option>').val(a.AreaCode).text(a.Area ? a.Area + ' (' + a.AreaCode + ')' : a.AreaCode));
                });
                $('#txtAsOf').val(today).attr('max', today);
            })
            .fail(showError)
            .always(function () { loading(false); });
    }

    // ------------------------------------------------------------ summary
    function loadSummary(silent) {
        readFilters();
        if (!silent) { clearError(); loading(true); }
        spin(true);
        return callApi('GetSummary', { session: state.session || null, areaCode: state.areaCode || null, asOf: state.asOf, authOnly: state.authOnly })
            .done(function (d) {
                clearError();
                data = d;
                $('#lblUpdated').text((d.generatedAt || '').split(' ')[1] || d.generatedAt || '');
                renderSummary();
            })
            .fail(function (m) { if (!silent) showError(m); })
            .always(function () { if (!silent) loading(false); spin(false); })
            .done(function () { loadProducts(silent); });
    }

    function loadProducts(silent) {
        return callApi('GetProducts', { session: state.session || null, areaCode: state.areaCode || null, asOf: state.asOf, authOnly: state.authOnly })
            .done(function (d) {
                prod = d || { products: [], productCustomers: [] };
                renderProducts();
                if (view.product) renderCustomers();
            })
            .fail(function (m) { if (!silent) showError(m); });
    }

    // ------------------------------------------------------------ products
    function qtyCell(nos, kg) {
        if (KIND === 'CHICK') return fInt(nos);
        if (num(kg) > 0) return nfQty.format(num(kg)) + ' kg' + (num(nos) ? '<div class="cust-sub">' + fInt(nos) + ' nos</div>' : '');
        return fInt(nos) + ' nos';
    }
    function miniStrip(r) {
        var tot = BUCKETS.reduce(function (s, b) { return s + Math.max(0, num(r[b.key])); }, 0);
        if (!tot) return '<span class="text-muted small">–</span>';
        return '<div class="mini-strip" title="' + BUCKETS.map(function (b) { return b.short + ': ' + fAmt(r[b.key]); }).join('  ') + '">' +
            BUCKETS.map(function (b) { return '<span class="' + b.cls + '-bg" style="width:' + (Math.max(0, num(r[b.key])) * 100 / tot).toFixed(1) + '%"></span>'; }).join('') + '</div>';
    }

    function renderProducts() {
        var rows = prod.products || [];
        var totOs = rows.reduce(function (s, r) { return s + num(r.Outstanding); }, 0);
        var totSales = rows.reduce(function (s, r) { return s + num(r.Sales); }, 0);
        var qtyHead = KIND === 'CHICK' ? 'Net chicks' : 'Quantity';
        $('#tblProd thead').html('<tr><th>Product</th><th class="num d-none d-sm-table-cell">' + qtyHead + '</th><th class="num">Sales</th><th class="num d-none d-md-table-cell">Avg rate</th>' +
            '<th class="num">Outstanding</th><th class="num d-none d-md-table-cell">% of dues</th><th class="d-none d-sm-table-cell">Aging</th><th class="num d-none d-md-table-cell">Cust. owing</th></tr>');
        $('#tblProd tbody').html(rows.length ? rows.map(function (r) {
            return '<tr data-product="' + esc(r.Product) + '" class="' + (view.product === r.Product ? 'active' : '') + '">' +
                '<td><div class="prod-name">' + esc(r.Product) + '</div><div class="cust-sub">' + fInt(r.Bills) + ' supplies · ' + fInt(r.Customers) + ' customers</div></td>' +
                '<td class="num d-none d-sm-table-cell">' + (num(r.Qty) || num(r.QtyKg) ? qtyCell(r.Qty, r.QtyKg) : '–') + '</td>' +
                '<td class="num">' + fAmt(r.Sales) + '</td>' +
                '<td class="num d-none d-md-table-cell">' + (num(r.AvgRate) ? fAmt(r.AvgRate) : '–') + '</td>' +
                '<td class="num os ' + (num(r.Outstanding) > 0 ? 'text-due' : '') + '">' + fAmt(r.Outstanding) + '</td>' +
                '<td class="num d-none d-md-table-cell">' + fPct(totOs ? num(r.Outstanding) * 100 / totOs : 0) + '</td>' +
                '<td class="d-none d-sm-table-cell">' + miniStrip(r) + '</td>' +
                '<td class="num d-none d-md-table-cell">' + fInt(r.WithDue) + '</td></tr>';
        }).join('') : '<tr><td colspan="8" class="text-center text-muted py-3">No product lines found</td></tr>');
        $('#tblProd tfoot').html(rows.length ? '<tr><td>Total (' + fInt(rows.length) + ' products)</td><td class="d-none d-sm-table-cell"></td><td class="num">' + fAmt(totSales) +
            '</td><td class="d-none d-md-table-cell"></td><td class="num">' + fAmt(totOs) + '</td><td class="num d-none d-md-table-cell">100%</td><td class="d-none d-sm-table-cell"></td><td class="d-none d-md-table-cell"></td></tr>' : '');

        // product dropdown on the customer list
        var $d = $('#ddlProduct'), cur = view.product;
        $d.empty().append('<option value="">All products</option>');
        rows.forEach(function (r) { $d.append($('<option>').val(r.Product).text(r.Product + (num(r.Outstanding) > 0 ? ' — ' + fShort(r.Outstanding) : ''))); });
        if (cur && !rows.some(function (r) { return r.Product === cur; })) { view.product = ''; cur = ''; }
        $d.val(cur).toggleClass('on', !!cur);

        // chart: top 10 products by outstanding, split by age
        if (!window.Chart) return;
        var top = rows.filter(function (r) { return num(r.Outstanding) > 0; }).slice(0, 10);
        var labels = top.map(function (r) { return r.Product.length > 24 ? r.Product.slice(0, 23) + '…' : r.Product; });
        var sets = BUCKETS.map(function (b) {
            return { label: b.short + ' d', data: top.map(function (r) { return Math.max(0, num(r[b.key])); }), backgroundColor: b.color, borderRadius: 3, stack: 'a' };
        });
        if (prodChart) {
            prodChart.data.labels = labels;
            prodChart.data.datasets.forEach(function (ds, i) { ds.data = sets[i].data; });
            prodChart.$keys = top.map(function (r) { return r.Product; });
            prodChart.update('none');
            return;
        }
        prodChart = new Chart(document.getElementById('chProd'), {
            type: 'bar',
            data: { labels: labels, datasets: sets },
            options: {
                indexAxis: 'y', maintainAspectRatio: false,
                interaction: { mode: 'index', intersect: false },
                plugins: {
                    legend: { position: 'bottom', labels: { boxWidth: 12, usePointStyle: true } },
                    tooltip: { callbacks: {
                        label: function (c) { return c.parsed.x ? ' ' + c.dataset.label + ': ' + fMoney(c.parsed.x) : null; },
                        footer: function (items) { return 'Total: ' + fMoney(items.reduce(function (s, i) { return s + i.parsed.x; }, 0)); }
                    } }
                },
                scales: {
                    x: { stacked: true, beginAtZero: true, grid: { color: '#eeeae2' }, ticks: { callback: function (v) { return fShort(v); } } },
                    y: { stacked: true, grid: { display: false } }
                },
                onClick: function (e, els) { if (els.length && prodChart.$keys) setProduct(prodChart.$keys[els[0].index], true); },
                onHover: function (e, els) { e.native.target.style.cursor = els.length ? 'pointer' : 'default'; }
            }
        });
        prodChart.$keys = top.map(function (r) { return r.Product; });
    }

    function setProduct(p, scroll) {
        view.product = view.product === p && scroll ? '' : (p || '');
        view.limit = PAGE; view.bucket = -1;
        if (view.product) { view.status = 'due'; $('#stDue').prop('checked', true); view.sortKey = 'Outstanding'; view.sortDir = -1; }
        $('#ddlProduct').val(view.product).toggleClass('on', !!view.product);
        $('#tblProd tbody tr').each(function () { $(this).toggleClass('active', $(this).attr('data-product') === view.product); });
        renderCustomers();
        if (scroll) document.getElementById('tblCust').closest('section').scrollIntoView({ behavior: 'smooth', block: 'start' });
    }

    function renderSummary() {
        var k = data.kpi || {};
        renderKpis(k);
        renderAging(k);
        renderTopChart();
        renderAreas();
        renderCustomers();
    }

    function kpiCard(o) {
        return '<div class="col-6 col-md-4 col-xl-2"><div class="kpi' + (o.click ? ' clickable' : '') + '" style="--accent:' + o.color + '"' +
            (o.click ? ' data-act="' + o.click + '"' : '') + '>' +
            '<div class="kpi-label"><i class="bi ' + o.icon + '"></i>' + esc(o.label) + '</div>' +
            '<div class="kpi-value ' + (o.cls || '') + '" title="' + esc(o.title || '') + '">' + o.value + '</div>' +
            '<div class="kpi-sub">' + o.sub + '</div>' + (o.extra || '') + '</div></div>';
    }

    function renderKpis(k) {
        var os = num(k.Outstanding);
        var over90 = num(k.B3) + num(k.B4);
        var over90Cust = (data.customers || []).filter(function (c) { return num(c.B3) + num(c.B4) > 0; }).length;
        var coll = Math.max(0, Math.min(100, num(k.CollectionPct)));
        $('#kpiRow').html([
            kpiCard({ label: 'Total outstanding', icon: 'bi-hourglass-split', color: '#c0392b', cls: 'text-due',
                value: fShort(os), title: fMoney(os),
                sub: 'Net of advance <b>' + fShort(k.NetReceivable) + '</b>' }),
            kpiCard({ label: 'Overdue > 90 days', icon: 'bi-exclamation-octagon', color: BUCKETS[4].color, click: 'b90',
                value: fShort(over90), title: fMoney(over90),
                sub: '<b>' + fPct(os ? over90 * 100 / os : 0) + '</b> of dues · ' + fInt(over90Cust) + ' cust.' }),
            kpiCard({ label: 'Average age of dues', icon: 'bi-calendar-week', color: BUCKETS[2].color,
                value: fInt(k.AvgDays) + ' <small class="fs-6 fw-semibold">days</small>', title: 'Weighted by amount',
                sub: '<b>' + fInt(k.OpenBills) + '</b> unpaid supplies' }),
            kpiCard({ label: 'Customers with dues', icon: 'bi-people', color: '#34568b', click: 'due',
                value: fInt(k.CustomersWithDue),
                sub: 'of <b>' + fInt(k.Customers) + '</b> customers' }),
            kpiCard({ label: 'Advance / credit', icon: 'bi-piggy-bank', color: '#2e8b57', click: 'adv', cls: num(k.Advance) ? 'text-adv' : '',
                value: fShort(k.Advance), title: fMoney(k.Advance),
                sub: '<b>' + fInt(k.CustomersWithAdv) + '</b> customers paid extra' }),
            kpiCard({ label: 'Collected', icon: 'bi-cash-coin', color: '#2a9d8f',
                value: fPct(k.CollectionPct),
                sub: fShort(k.Received) + ' of ' + fShort(k.Billed),
                extra: '<div class="bar"><span style="width:' + coll + '%"></span></div>' })
        ].join(''));
    }

    function renderAging(k) {
        var total = BUCKETS.reduce(function (s, b) { return s + Math.max(0, num(k[b.key])); }, 0);
        $('#ageStrip').html(BUCKETS.map(function (b) {
            var pct = total ? Math.max(0, num(k[b.key])) * 100 / total : 0;
            return '<span class="' + b.cls + '-bg" style="width:' + pct.toFixed(2) + '%" title="' + b.label + ': ' + fMoney(k[b.key]) + '"></span>';
        }).join(''));
        $('#ageTiles').html(BUCKETS.map(function (b, i) {
            var v = num(k[b.key]);
            return '<button type="button" class="age-tile' + (view.bucket === i ? ' active' : '') + '" data-bucket="' + i + '" style="--c:' + b.color + '">' +
                '<div class="t" title="' + b.label + '">' + b.short + ' d</div>' +
                '<div class="v" title="' + fMoney(v) + '">' + fShort(v) + '</div>' +
                '<div class="s" title="' + fInt(k[b.cnt]) + ' customers">' + fPct(total ? v * 100 / total : 0) + ' · ' + fInt(k[b.cnt]) + ' cust.</div></button>';
        }).join(''));
    }

    function renderTopChart() {
        if (!window.Chart) return;
        var top = (data.customers || []).filter(function (c) { return num(c.Outstanding) > 0; })
            .sort(function (a, b) { return num(b.Outstanding) - num(a.Outstanding); }).slice(0, 10);
        var labels = top.map(function (c) { var n = c.CName || c.Code; return n.length > 26 ? n.slice(0, 25) + '…' : n; });
        var sets = BUCKETS.map(function (b) {
            return { label: b.short + ' d', data: top.map(function (c) { return num(c[b.key]); }), backgroundColor: b.color, borderRadius: 3, stack: 'a' };
        });
        if (chart) {
            chart.data.labels = labels;
            chart.data.datasets.forEach(function (ds, i) { ds.data = sets[i].data; });
            chart.$keys = top.map(function (c) { return c.CustKey; });
            chart.update('none');
            return;
        }
        Chart.defaults.font.family = "'Plus Jakarta Sans', system-ui, sans-serif";
        Chart.defaults.color = '#5b6476';
        chart = new Chart(document.getElementById('chTop'), {
            type: 'bar',
            data: { labels: labels, datasets: sets },
            options: {
                indexAxis: 'y', maintainAspectRatio: false,
                interaction: { mode: 'index', intersect: false },
                plugins: {
                    legend: { position: 'bottom', labels: { boxWidth: 12, usePointStyle: true } },
                    tooltip: { callbacks: {
                        label: function (c) { return c.parsed.x ? ' ' + c.dataset.label + ': ' + fMoney(c.parsed.x) : null; },
                        footer: function (items) { return 'Total: ' + fMoney(items.reduce(function (s, i) { return s + i.parsed.x; }, 0)); }
                    } }
                },
                scales: {
                    x: { stacked: true, beginAtZero: true, grid: { color: '#eeeae2' }, ticks: { callback: function (v) { return fShort(v); } } },
                    y: { stacked: true, grid: { display: false } }
                },
                onClick: function (e, els) { if (els.length && chart.$keys) openCustomer(chart.$keys[els[0].index]); },
                onHover: function (e, els) { e.native.target.style.cursor = els.length ? 'pointer' : 'default'; }
            }
        });
        chart.$keys = top.map(function (c) { return c.CustKey; });
    }

    function renderAreas() {
        var rows = data.areas || [];
        var head = '<tr><th>' + (LEDGER ? 'Station' : 'Area') + '</th><th class="num">Cust. with dues</th><th class="num">Outstanding</th>' +
            BUCKETS.map(function (b) { return '<th class="num"><span class="dot" style="background:' + b.color + '"></span>' + b.short + '</th>'; }).join('') +
            '<th class="num">Advance</th><th class="num">Received</th></tr>';
        var body = rows.length ? rows.map(function (r) {
            return '<tr class="area-row" data-area="' + esc(r.AreaCode) + '" style="cursor:pointer" title="Filter by this area">' +
                '<td><b>' + esc(r.Area || r.AreaCode) + '</b>' + (r.Area && r.Area !== r.AreaCode ? ' <span class="text-muted small">' + esc(r.AreaCode) + '</span>' : '') + '</td>' +
                '<td class="num">' + fInt(r.WithDue) + '</td>' +
                '<td class="num os text-due">' + fAmt(r.Outstanding) + '</td>' +
                BUCKETS.map(function (b) { return '<td class="num">' + (num(r[b.key]) ? fAmt(r[b.key]) : '<span class="text-muted">–</span>') + '</td>'; }).join('') +
                '<td class="num text-adv">' + (num(r.Advance) ? fAmt(r.Advance) : '–') + '</td>' +
                '<td class="num">' + fAmt(r.Received) + '</td></tr>';
        }).join('') : '<tr><td colspan="10" class="text-center text-muted py-3">No data</td></tr>';
        var k = data.kpi || {};
        var foot = rows.length ? '<tr><td>Total</td><td class="num">' + fInt(k.CustomersWithDue) + '</td><td class="num">' + fAmt(k.Outstanding) + '</td>' +
            BUCKETS.map(function (b) { return '<td class="num">' + fAmt(k[b.key]) + '</td>'; }).join('') +
            '<td class="num">' + fAmt(k.Advance) + '</td><td class="num">' + fAmt(k.Received) + '</td></tr>' : '';
        $('#tblArea thead').html(head); $('#tblArea tbody').html(body); $('#tblArea tfoot').html(foot);
    }

    // ------------------------------------------------------------ customers list
    var COLS = [
        { k: 'CName', l: 'Customer', t: 'text' },
        { k: 'Billed', l: 'Supplied', pl: 'Product supplied', t: 'num' },
        { k: 'Received', l: 'Received', pl: 'Adjusted', t: 'num' },
        { k: 'Outstanding', l: 'Outstanding', t: 'num' }
    ].concat(BUCKETS.map(function (b) { return { k: b.key, l: b.short, t: 'num', bucket: b }; }))
     .concat([{ k: 'MaxDays', l: BY_HATCH ? 'Oldest due (hatch)' : 'Oldest due', t: 'num' }, { k: 'LastPayDate', l: 'Last payment', t: 'text' }]);

    function filteredCustomers() {
        var q = ($('#txtSearch').val() || '').trim().toLowerCase();
        var rows = (data && data.customers) || [];
        if (view.product) {
            var byKey = {};
            rows.forEach(function (c) { byKey[c.CustKey] = c; });
            rows = (prod.productCustomers || []).filter(function (r) { return r.Product === view.product; }).map(function (r) {
                var c = byKey[r.CustKey] || {};
                return { CustKey: r.CustKey, Code: r.Code, CName: r.CName, Area: r.Area, AreaCode: c.AreaCode,
                         Billed: r.Sales, Received: num(r.Sales) - num(r.Outstanding), Outstanding: r.Outstanding, Advance: 0,
                         B0: r.B0, B1: r.B1, B2: r.B2, B3: r.B3, B4: r.B4, MaxDays: r.MaxDays, OldestDue: r.OldestDue,
                         OpenBills: c.OpenBills, LastPayDate: c.LastPayDate, LastPayAmt: c.LastPayAmt, Qty: r.Qty, QtyKg: r.QtyKg };
            });
        }
        rows = rows.filter(function (c) {
            if (view.status === 'due' && !(num(c.Outstanding) > 0)) return false;
            if (view.status === 'adv' && !(num(c.Advance) > 0)) return false;
            if (view.bucket >= 0 && !(num(c[BUCKETS[view.bucket].key]) > 0)) return false;
            if (q && ((c.CName || '') + ' ' + (c.Code || '') + ' ' + (c.Area || '') + ' ' + (c.AreaCode || '')).toLowerCase().indexOf(q) < 0) return false;
            return true;
        });
        var key = view.sortKey, dir = view.sortDir;
        var col = COLS.filter(function (c) { return c.k === key; })[0] || { t: 'num' };
        return rows.slice().sort(function (a, b) {
            if (col.t === 'num') return (num(a[key]) - num(b[key])) * dir;
            return String(a[key] || '').localeCompare(String(b[key] || ''), 'en', { numeric: true }) * dir;
        });
    }

    function osCell(c) {
        if (num(c.Outstanding) > 0) return '<span class="text-due">' + fAmt(c.Outstanding) + '</span>';
        if (num(c.Advance) > 0) return '<span class="text-adv" title="Advance / credit">Adv ' + fAmt(c.Advance) + '</span>';
        return '<span class="text-muted">0.00</span>';
    }

    function renderCustomers() {
        if (!data) return;
        var rows = filteredCustomers();
        var shown = rows.slice(0, view.limit);

        // bucket chip
        if (view.bucket >= 0) {
            var b = BUCKETS[view.bucket];
            $('#bucketChip').removeClass('d-none').css('--c', b.color)
                .html(esc(b.label) + ' <button type="button" aria-label="Clear bucket filter">&times;</button>');
        } else $('#bucketChip').addClass('d-none').empty();

        // table
        var head = '<tr>' + COLS.map(function (c) {
            var sorted = c.k === view.sortKey;
            var icon = sorted ? (view.sortDir > 0 ? 'bi-sort-up' : 'bi-sort-down') : 'bi-arrow-down-up';
            var dot = c.bucket ? '<span class="dot" style="background:' + c.bucket.color + '"></span>' : '';
            return '<th data-key="' + c.k + '" class="' + (c.t === 'num' ? 'num ' : '') + (sorted ? 'sorted' : '') + '">' + dot + esc(view.product && c.pl ? c.pl : c.l) + '<i class="bi ' + icon + ' si"></i></th>';
        }).join('') + '</tr>';

        var body = shown.length ? shown.map(function (c) {
            return '<tr data-cust="' + esc(c.CustKey) + '">' +
                '<td><div class="cust-name">' + esc(c.CName || '(no name)') + '</div><div class="cust-sub">' + esc(c.Code) + (c.Area ? ' · ' + esc(c.Area) : '') + '</div></td>' +
                '<td class="num">' + fAmt(c.Billed) + '</td>' +
                '<td class="num">' + fAmt(c.Received) + '</td>' +
                '<td class="num os">' + osCell(c) + '</td>' +
                BUCKETS.map(function (b) { var v = num(c[b.key]); return '<td class="num bk' + (v ? '' : ' zero') + '">' + (v ? fAmt(v) : '–') + '</td>'; }).join('') +
                '<td class="num">' + (num(c.MaxDays) > 0 || num(c.Outstanding) > 0 ? ageBadge(c.MaxDays) + '<div class="cust-sub">' + fDate(c.OldestDue) + '</div>' : '<span class="text-muted">–</span>') + '</td>' +
                '<td>' + (c.LastPayDate ? fDate(c.LastPayDate) + '<div class="cust-sub">' + fMoney(c.LastPayAmt) + '</div>' : '<span class="text-muted small">No payment</span>') + '</td>' +
                '</tr>';
        }).join('') : '<tr><td colspan="' + COLS.length + '" class="text-center text-muted py-4">No customers match</td></tr>';

        var sum = function (k) { return rows.reduce(function (s, r) { return s + num(r[k]); }, 0); };
        var foot = rows.length ? '<tr><td>Total (' + fInt(rows.length) + ')</td><td class="num">' + fAmt(sum('Billed')) + '</td><td class="num">' + fAmt(sum('Received')) +
            '</td><td class="num">' + fAmt(sum('Outstanding')) + '</td>' +
            BUCKETS.map(function (b) { return '<td class="num">' + fAmt(sum(b.key)) + '</td>'; }).join('') + '<td></td><td></td></tr>' : '';

        $('#tblCust thead').html(head); $('#tblCust tbody').html(body); $('#tblCust tfoot').html(foot);

        // phone cards
        $('#custCards').html(shown.length ? shown.map(function (c) {
            var tot = BUCKETS.reduce(function (s, b) { return s + Math.max(0, num(c[b.key])); }, 0);
            var strip = BUCKETS.map(function (b) {
                return '<span class="' + b.cls + '-bg" style="width:' + (tot ? Math.max(0, num(c[b.key])) * 100 / tot : 0).toFixed(1) + '%"></span>';
            }).join('');
            return '<div class="cust-card" data-cust="' + esc(c.CustKey) + '" role="button" tabindex="0">' +
                '<div class="min-w-0"><div class="cust-name">' + esc(c.CName || '(no name)') + '</div><div class="cust-sub">' + esc(c.Code) + (c.Area ? ' · ' + esc(c.Area) : '') + '</div></div>' +
                '<div class="os">' + (num(c.Outstanding) > 0 ? '<span class="text-due">' + fShort(c.Outstanding) + '</span>' :
                    (num(c.Advance) > 0 ? '<span class="text-adv">Adv ' + fShort(c.Advance) + '</span>' : '<span class="text-muted">₹0</span>')) +
                (num(c.Outstanding) > 0 ? '<div>' + ageBadge(c.MaxDays) + '</div>' : '') + '</div>' +
                (tot ? '<div class="age-strip">' + strip + '</div>' : '') +
                '<div class="foot"><span>' + (view.product ? esc(view.product) + ' ' + fShort(c.Billed) : 'Supplied ' + fShort(c.Billed) + ' · Recd ' + fShort(c.Received)) + '</span><span>' +
                (c.LastPayDate ? 'Paid ' + fDate(c.LastPayDate) : 'No payment') + '</span></div></div>';
        }).join('') : '<div class="text-center text-muted py-4">No customers match</div>');

        $('#lblRows').text('Showing ' + fInt(shown.length) + ' of ' + fInt(rows.length) + ' customers' +
            (view.product ? ' owing on ' + view.product + ' (their share of each unpaid supply)' : ''));
        $('.status-chips .btn-check').prop('disabled', !!view.product);
        $('#btnMore').toggleClass('d-none', shown.length >= rows.length);
        $('.age-tile').each(function () { $(this).toggleClass('active', +$(this).data('bucket') === view.bucket); });
    }

    function setBucket(i) {
        view.bucket = view.bucket === i ? -1 : i;
        if (view.bucket >= 0) {
            view.status = 'due'; $('#stDue').prop('checked', true);
            view.sortKey = BUCKETS[view.bucket].key; view.sortDir = -1;
        } else { view.sortKey = 'Outstanding'; view.sortDir = -1; }
        view.limit = PAGE;
        renderCustomers();
    }

    function exportCustomers() {
        var rows = filteredCustomers();
        var head = ['Code', 'Customer', 'Area', view.product ? view.product + ' supplied' : 'Supplied', view.product ? 'Adjusted' : 'Received', 'Outstanding', 'Advance']
            .concat(BUCKETS.map(function (b) { return b.label; }))
            .concat(['Unpaid supplies', 'Oldest due date', 'Oldest due days', 'Last payment date', 'Last payment amount']);
        var lines = rows.map(function (c) {
            return [c.Code, c.CName, c.Area, c.Billed, c.Received, c.Outstanding, c.Advance]
                .concat(BUCKETS.map(function (b) { return c[b.key]; }))
                .concat([c.OpenBills, fDate(c.OldestDue), c.MaxDays, fDate(c.LastPayDate), c.LastPayAmt]);
        });
        downloadCsv([head].concat(lines), KIND.toLowerCase() + '-outstanding_' + (view.product ? view.product + '_' : '') + (state.asOf || today) + '.csv');
    }

    function downloadCsv(rows, file) {
        var q = function (v) { v = v == null ? '' : String(v); return /[",\n]/.test(v) ? '"' + v.replace(/"/g, '""') + '"' : v; };
        var blob = new Blob(['﻿' + rows.map(function (r) { return r.map(q).join(','); }).join('\r\n')], { type: 'text/csv;charset=utf-8' });
        var a = document.createElement('a');
        a.href = URL.createObjectURL(blob); a.download = file.replace(/[^\w.\-]/g, '_');
        document.body.appendChild(a); a.click();
        setTimeout(function () { URL.revokeObjectURL(a.href); a.remove(); }, 500);
    }

    // ------------------------------------------------------------ customer detail
    function findCustomer(key) {
        return ((data && data.customers) || []).filter(function (c) { return c.CustKey === key; })[0] || { CustKey: key, CName: key };
    }

    function openCustomer(key) {
        cust.key = key; cust.detail = null;
        var c = findCustomer(key);
        $('#custName').text(c.CName || c.Code || key);
        $('#custMeta').text([c.Code, c.Area, LEDGER ? '' : (state.session || 'All sessions'), 'as on ' + fDate(state.asOf)].filter(Boolean).join(' · '));
        $('#custKpis, #custStrip, #custAgeLegend, #billList').empty();
        $('#tblCustProd thead, #tblCustProd tbody, #tblCustProd tfoot, #tblPays thead, #tblPays tbody, #tblPays tfoot, #tblStmt thead, #tblStmt tbody, #tblStmt tfoot').empty();
        $('#billList').html('<div class="text-center text-muted py-4"><div class="spinner-border spinner-border-sm me-2"></div>Loading supplies…</div>');
        showPane('bills');
        bootstrap.Modal.getOrCreateInstance(document.getElementById('custModal')).show();
        loadCustomer(false);
    }

    function loadCustomer(silent) {
        var key = cust.key;
        if (!key) return;
        callApi('GetCustomer', { custKey: key, session: state.session || null, areaCode: state.areaCode || null, asOf: state.asOf, authOnly: state.authOnly })
            .done(function (d) {
                if (cust.key !== key) return;
                cust.detail = d;
                renderCustomer();
            })
            .fail(function (m) { if (!silent) $('#billList').html('<div class="alert alert-danger">' + esc(m) + '</div>'); });
    }

    function linesByBill() {
        var map = {};
        (cust.detail.lines || []).forEach(function (l) { (map[l.BillKey] = map[l.BillKey] || []).push(l); });
        return map;
    }

    function qtyText(l) {
        if (KIND === 'CHICK') return fInt(l.NetQty) + ' chicks';
        if (num(l.QtyKg) > 0) return nfQty.format(num(l.QtyKg)) + ' kg' + (num(l.QtyNos) > 0 ? ' / ' + fInt(l.QtyNos) + ' nos' : '');
        return fInt(l.QtyNos) + ' nos';
    }
    function partsText(lines) {
        if (!lines || !lines.length) return '—';
        return lines.map(function (l) { return l.Particulars + ' ' + qtyText(l); }).join(', ');
    }

    function renderCustomer() {
        var d = cust.detail;
        var c = findCustomer(cust.key);
        var bills = d.bills || [], pays = d.payments || [];
        var billed = 0, osAmt = 0, b = [0, 0, 0, 0, 0], oldest = null, openCount = 0;
        bills.forEach(function (x) {
            billed += num(x.Amount);
            if (num(x.Outstanding) > 0) {
                osAmt += num(x.Outstanding); b[num(x.Bucket)] += num(x.Outstanding); openCount++;
                if (!oldest || num(x.Days) > num(oldest.Days)) oldest = x;
            }
        });
        var received = pays.reduce(function (s, p) { return s + num(p.Amount); }, 0);
        var advance = Math.max(0, received - billed);
        var lastPay = pays[0];

        if (bills[0] && !c.Code) $('#custMeta').text([bills[0].Code, bills[0].Area, LEDGER ? '' : (state.session || 'All sessions'), 'as on ' + fDate(state.asOf)].filter(Boolean).join(' · '));

        var mk = function (t, v, cls, sub) {
            return '<div class="col-6 col-md"><div class="mini-kpi"><div class="t">' + t + '</div><div class="v ' + (cls || '') + '">' + v + '</div>' +
                (sub ? '<div class="small text-muted">' + sub + '</div>' : '') + '</div></div>';
        };
        $('#custKpis').html(
            mk('Supplied', fShort(billed), '', fInt(bills.length) + ' supplies') +
            mk('Received', fShort(received), '', fInt(pays.length) + ' receipts') +
            mk('Outstanding', fShort(osAmt), osAmt > 0 ? 'text-due' : '', fInt(openCount) + ' unpaid supplies') +
            mk('Oldest due', oldest ? fInt(oldest.Days) + ' days' : '—', '', oldest ? (BY_HATCH ? 'hatched ' : 'since ') + fDate(oldest.BillDate) : 'nothing due') +
            (advance > 0 ? mk('Advance', fShort(advance), 'text-adv', 'paid in excess')
                         : mk('Last payment', lastPay ? fShort(lastPay.Amount) : '—', '', lastPay ? fDate(lastPay.TrDate) : 'no payment'))
        );

        $('#custStrip').html(b.map(function (v, i) {
            return '<span class="' + BUCKETS[i].cls + '-bg" style="width:' + (osAmt ? v * 100 / osAmt : 0).toFixed(2) + '%"></span>';
        }).join(''));
        $('#custAgeLegend').html(b.map(function (v, i) {
            return '<span><i style="background:' + BUCKETS[i].color + '"></i>' + BUCKETS[i].short + ': <b>' + fAmt(v) + '</b></span>';
        }).join(''));

        $('#printTitle').text(cfg.title + ' — ' + (c.CName || '') + ' (' + (c.Code || '') + ') — as on ' + fDate(state.asOf));

        renderBills();
        renderCustProducts();
        renderPayments();
        renderStatement();
    }

    function lineTable(lines) {
        if (!lines || !lines.length) return '<div class="small text-muted mt-2">No line details found for this supply.</div>';
        var h, rows, f, t = { a: 0, q: 0, k: 0, tax: 0, m: 0, n: 0 };
        if (KIND === 'CHICK') {
            h = '<tr><th>Particulars</th><th>Hatch date</th><th class="num">Total chicks</th><th class="num">Mortality</th><th class="num">Net chicks</th><th class="num">Rate</th><th class="num">Amount</th></tr>';
            rows = lines.map(function (l) {
                t.q += num(l.QtyNos); t.m += num(l.Mortality); t.n += num(l.NetQty); t.a += num(l.Amount);
                return '<tr><td>' + esc(l.Particulars) + (l.Hatchery ? ' <span class="text-muted">· ' + esc(l.Hatchery) + '</span>' : '') + '</td><td>' + fDate(l.HatchDate) + '</td>' +
                    '<td class="num">' + fInt(l.QtyNos) + '</td><td class="num">' + fInt(l.Mortality) + '</td><td class="num">' + fInt(l.NetQty) + '</td>' +
                    '<td class="num">' + fAmt(l.Rate) + '</td><td class="num">' + fAmt(l.Amount) + '</td></tr>';
            }).join('');
            f = '<tr><th colspan="2">Total</th><th class="num">' + fInt(t.q) + '</th><th class="num">' + fInt(t.m) + '</th><th class="num">' + fInt(t.n) + '</th><th></th><th class="num">' + fAmt(t.a) + '</th></tr>';
        } else {
            h = '<tr><th>Particulars</th><th>HSN</th><th class="num">Qty (Nos)</th><th class="num">Qty (Kg)</th><th class="num">Rate</th><th class="num">Amount</th><th class="num">Tax</th><th class="num">Total</th></tr>';
            rows = lines.map(function (l) {
                t.q += num(l.QtyNos); t.k += num(l.QtyKg); t.a += num(l.Amount); t.tax += num(l.TaxValue);
                return '<tr><td>' + esc(l.Particulars) + '</td><td>' + esc(l.HsnCode) + '</td>' +
                    '<td class="num">' + (num(l.QtyNos) ? fInt(l.QtyNos) : '–') + '</td><td class="num">' + (num(l.QtyKg) ? nfQty.format(num(l.QtyKg)) : '–') + '</td>' +
                    '<td class="num">' + fAmt(l.Rate) + '</td><td class="num">' + fAmt(l.Amount) + '</td>' +
                    '<td class="num">' + (num(l.TaxValue) ? fAmt(l.TaxValue) + ' <span class="text-muted">(' + num(l.TaxPer) + '%' + (l.TaxType ? ' ' + esc(l.TaxType) : '') + ')</span>' : '–') + '</td>' +
                    '<td class="num">' + fAmt(num(l.Amount) + num(l.TaxValue)) + '</td></tr>';
            }).join('');
            f = '<tr><th colspan="2">Total</th><th class="num">' + fInt(t.q) + '</th><th class="num">' + nfQty.format(t.k) + '</th><th></th><th class="num">' + fAmt(t.a) + '</th><th class="num">' + fAmt(t.tax) + '</th><th class="num">' + fAmt(t.a + t.tax) + '</th></tr>';
        }
        return '<div class="table-responsive"><table class="table table-sm lines-table mb-0"><thead>' + h + '</thead><tbody>' + rows + '</tbody><tfoot>' + f + '</tfoot></table></div>';
    }

    function renderBills() {
        var showSettled = $('#chkSettled').is(':checked');
        var map = linesByBill();
        var bills = (cust.detail.bills || []).filter(function (x) { return showSettled || num(x.Outstanding) > 0; })
            .sort(function (a, b) { return String(a.BillDate || '').localeCompare(String(b.BillDate || '')); });   // oldest first
        if (!bills.length) {
            $('#billList').html('<div class="text-center text-muted py-4"><i class="bi bi-check2-circle fs-3 d-block mb-1 text-success"></i>No outstanding supplies' +
                ((cust.detail.bills || []).length ? ' — turn on "Show settled supplies" to see all.' : '.') + '</div>');
            return;
        }
        $('#billList').html(bills.map(function (x) {
            var due = num(x.Outstanding) > 0;
            var bk = BUCKETS[num(x.Bucket)];
            var paidPct = num(x.Amount) ? Math.min(100, Math.max(0, num(x.Adjusted) * 100 / num(x.Amount))) : 100;
            var lines = map[x.BillKey];
            var extra = [];
            if (KIND === 'POULTRY') {
                extra.push('Goods <b>' + fAmt(x.Taxable) + '</b>');
                if (num(x.Tax)) extra.push('Tax <b>' + fAmt(x.Tax) + '</b>');
                if (num(x.Insurance)) extra.push('Insurance <b>' + fAmt(x.Insurance) + '</b>');
                if (num(x.Tcs)) extra.push('TCS <b>' + fAmt(x.Tcs) + '</b>');
                extra.push('Bill total <b>' + fAmt(x.Amount) + '</b>');
                if (x.VehNo) extra.push('Vehicle <b>' + esc(x.VehNo) + '</b>');
                if (x.DriverName) extra.push('Driver <b>' + esc(x.DriverName) + '</b>');
            }
            extra.push('Adjusted from payments <b>' + fAmt(x.Adjusted) + '</b>');
            if (x.Remarks) extra.push('Remarks <b>' + esc(x.Remarks) + '</b>');
            return '<details class="bill' + (due ? '' : ' settled') + '" style="--c:' + bk.color + '">' +
                '<summary>' +
                '<div class="head"><div class="dm">' + esc(billLabel(x)) + ' ' + (due ? ageBadge(x.Days) : '<span class="badge text-bg-success">Settled</span>') + '</div>' +
                '<div class="meta">' + (!isChickBill(x) ? fDate(x.DMDate)
                    : BY_HATCH ? 'Hatch ' + fDate(x.BillDate) + (x.DMDate && String(x.DMDate) !== String(x.BillDate) ? ' · ' + (LEDGER ? 'bill ' : 'DM ') + fDate(x.DMDate) : '') : fDate(x.BillDate)) +
                ' · ' + esc(x.Session) + (x.Area ? ' · ' + esc(x.Area) : '') + '</div></div>' +
                '<div class="parts" title="' + esc(isChickBill(x) ? partsText(lines) : x.Remarks) + '">' + esc(isChickBill(x) ? partsText(lines) : (x.Remarks || 'Ledger entry')) + '</div>' +
                '<div class="amt"><div class="l">Bill</div><div class="n">' + fAmt(x.Amount) + '</div></div>' +
                '<div class="amt"><div class="l">Adjusted</div><div class="n">' + fAmt(x.Adjusted) + '</div></div>' +
                '<div class="amt os"><div class="l">Outstanding</div><div class="n">' + fAmt(x.Outstanding) + '</div></div>' +
                '<i class="bi bi-chevron-down chev"></i>' +
                '<div class="paidbar"><span style="width:' + paidPct.toFixed(1) + '%"></span></div>' +
                '</summary>' +
                '<div class="bill-body">' + lineTable(lines) + '<div class="bill-extra">' + extra.map(function (e) { return '<span>' + e + '</span>'; }).join('') + '</div></div>' +
                '</details>';
        }).join(''));
        $('#btnExpandAll').text('Expand all');
    }

    function renderCustProducts() {
        var map = linesByBill(), agg = {}, order = [];
        (cust.detail.bills || []).forEach(function (x) {
            var ls = (map[x.BillKey] || []).slice();
            var lt = ls.reduce(function (s, l) { return s + num(l.Amount) + num(l.TaxValue); }, 0);
            var extra = Math.round((num(x.Amount) - lt) * 100) / 100;      // insurance, TCS, other charges
            if (extra !== 0) ls.push({ Particulars: 'Insurance, TCS & other charges', NetQty: 0, QtyKg: 0, Amount: extra, TaxValue: 0 });
            lt = num(x.Amount);
            ls.forEach(function (l) {
                var name = (l.Particulars || '').trim() || '(blank)';
                var a = agg[name];
                if (!a) { a = agg[name] = { Product: name, Qty: 0, QtyKg: 0, Amt: 0, Sales: 0, Outstanding: 0, Supplies: 0, B0: 0, B1: 0, B2: 0, B3: 0, B4: 0, Last: '' }; order.push(name); }
                var v = num(l.Amount) + num(l.TaxValue);
                var share = lt ? num(x.Outstanding) * v / lt : 0;
                a.Qty += num(l.NetQty); a.QtyKg += num(l.QtyKg); a.Amt += num(l.Amount); a.Sales += v; a.Supplies++;
                a.Outstanding += share; a['B' + num(x.Bucket)] += share;
                if (String(x.BillDate || '') > a.Last) a.Last = x.BillDate;
            });
        });
        var rows = order.map(function (n) { return agg[n]; }).sort(function (a, b) { return b.Outstanding - a.Outstanding || b.Sales - a.Sales; });
        var qtyHead = KIND === 'CHICK' ? 'Net chicks' : 'Quantity';
        $('#tblCustProd thead').html('<tr><th>Product</th><th class="num">' + qtyHead + '</th><th class="num">Avg rate</th><th class="num">Supplied</th><th class="num">Outstanding</th>' +
            BUCKETS.map(function (b) { return '<th class="num"><span class="dot" style="background:' + b.color + '"></span>' + b.short + '</th>'; }).join('') + '<th>Last supply</th></tr>');
        $('#tblCustProd tbody').html(rows.length ? rows.map(function (r) {
            var basis = r.QtyKg > 0 ? r.QtyKg : r.Qty;
            return '<tr><td><b>' + esc(r.Product) + '</b><div class="cust-sub">' + fInt(r.Supplies) + ' supplies</div></td>' +
                '<td class="num">' + (basis ? qtyCell(r.Qty, r.QtyKg) : '–') + '</td><td class="num">' + (basis ? fAmt(r.Amt / basis) : '–') + '</td>' +
                '<td class="num">' + fAmt(r.Sales) + '</td><td class="num os ' + (r.Outstanding > 0.005 ? 'text-due' : '') + '">' + fAmt(r.Outstanding) + '</td>' +
                BUCKETS.map(function (b) { return '<td class="num">' + (r[b.key] > 0.005 ? fAmt(r[b.key]) : '<span class="text-muted">–</span>') + '</td>'; }).join('') +
                '<td>' + fDate(r.Last) + '</td></tr>';
        }).join('') : '<tr><td colspan="11" class="text-center text-muted py-3">No product lines</td></tr>');
        var sum = function (k) { return rows.reduce(function (s, r) { return s + r[k]; }, 0); };
        $('#tblCustProd tfoot').html(rows.length ? '<tr><td>Total</td><td></td><td></td><td class="num">' + fAmt(sum('Sales')) + '</td><td class="num">' + fAmt(sum('Outstanding')) + '</td>' +
            BUCKETS.map(function (b) { return '<td class="num">' + fAmt(sum(b.key)) + '</td>'; }).join('') + '<td></td></tr>' : '');
    }

    function renderPayments() {
        var pays = cust.detail.payments || [];
        $('#tblPays thead').html('<tr><th>TR No</th><th>Date</th><th>Mode</th><th>Type</th><th>DD / Ref</th><th>Bank</th><th class="num">Amount</th><th>Status</th></tr>');
        $('#tblPays tbody').html(pays.length ? pays.map(function (p) {
            return '<tr><td>' + esc(p.TRNo) + '</td><td>' + fDate(p.TrDate) + '</td><td>' + esc(p.PayMode) + '</td><td>' + esc(p.PayType) + '</td>' +
                '<td>' + esc(p.DD_No) + '</td><td>' + esc(p.Bank_det) + (p.BankDate ? ' <span class="text-muted small">' + fDate(p.BankDate) + '</span>' : '') + '</td>' +
                '<td class="num">' + fAmt(p.Amount) + '</td>' +
                '<td>' + (num(p.IsAuth) === 1 ? '<span class="badge text-bg-success">Authorised</span>' : '<span class="badge text-bg-warning">Pending</span>') + '</td></tr>';
        }).join('') : '<tr><td colspan="8" class="text-center text-muted py-3">No payments received</td></tr>');
        var tot = pays.reduce(function (s, p) { return s + num(p.Amount); }, 0);
        $('#tblPays tfoot').html(pays.length ? '<tr><td colspan="6">Total</td><td class="num">' + fAmt(tot) + '</td><td></td></tr>' : '');
    }

    function statementRows() {
        var map = linesByBill();
        var e = [];
        (cust.detail.bills || []).forEach(function (x) {
            e.push({ date: x.BillDate, o: 0, ref: billLabel(x),
                     desc: isChickBill(x) ? (BY_HATCH ? 'Hatch ' + fDate(x.BillDate) + ' · ' : '') + partsText(map[x.BillKey]) : (x.Remarks || x.Session || ''),
                     dr: num(x.Amount), cr: 0, bill: true });
        });
        (cust.detail.payments || []).forEach(function (p) {
            e.push({ date: p.TrDate, o: 1, ref: 'TR ' + p.TRNo, desc: 'Payment · ' + p.PayMode + (p.DD_No ? ' · ' + p.DD_No : '') + (num(p.IsAuth) === 1 ? '' : ' (pending auth.)'), dr: 0, cr: num(p.Amount) });
        });
        e.sort(function (a, b) { return String(a.date || '').localeCompare(String(b.date || '')) || a.o - b.o; });
        var bal = 0;
        e.forEach(function (r) { bal += r.dr - r.cr; r.bal = bal; });
        return e;
    }
    function balText(v) { return fAmt(Math.abs(v)) + (v > 0 ? ' Dr' : v < 0 ? ' Cr' : ''); }

    function renderStatement() {
        var e = statementRows();
        var dr = 0, cr = 0;
        $('#tblStmt thead').html('<tr><th>' + (BY_HATCH ? 'Date (supplies: hatch date)' : 'Date') + '</th><th>Ref</th><th>Particulars</th><th class="num">Debit (supply)</th><th class="num">Credit (payment)</th><th class="num">Balance</th></tr>');
        $('#tblStmt tbody').html(e.length ? e.map(function (r) {
            dr += r.dr; cr += r.cr;
            return '<tr class="' + (r.bill ? 'stmt-bill' : '') + '"><td>' + fDate(r.date) + '</td><td>' + esc(r.ref) + '</td><td style="white-space:normal;min-width:200px">' + esc(r.desc) + '</td>' +
                '<td class="num">' + (r.dr ? fAmt(r.dr) : '') + '</td><td class="num">' + (r.cr ? fAmt(r.cr) : '') + '</td>' +
                '<td class="num ' + (r.bal > 0 ? 'text-due' : r.bal < 0 ? 'text-adv' : '') + '">' + balText(r.bal) + '</td></tr>';
        }).join('') : '<tr><td colspan="6" class="text-center text-muted py-3">No transactions</td></tr>');
        $('#tblStmt tfoot').html(e.length ? '<tr class="closing"><td colspan="3">Closing balance as on ' + fDate(state.asOf) + '</td><td class="num">' + fAmt(dr) + '</td><td class="num">' + fAmt(cr) + '</td><td class="num">' + balText(dr - cr) + '</td></tr>' : '');
    }

    function exportStatement() {
        if (!cust.detail) return;
        var c = findCustomer(cust.key);
        var rows = [['Date', 'Ref', 'Particulars', 'Debit', 'Credit', 'Balance']];
        statementRows().forEach(function (r) { rows.push([fDate(r.date), r.ref, r.desc, r.dr || '', r.cr || '', balText(r.bal)]); });
        rows.push([]);
        rows.push(['Outstanding supplies (FIFO)']);
        rows.push(['DM No', BY_HATCH ? 'Hatch date' : 'Date', 'Days', 'Bill amount', 'Adjusted', 'Outstanding']);
        (cust.detail.bills || []).filter(function (x) { return num(x.Outstanding) > 0; }).forEach(function (x) {
            rows.push([x.DMNo, fDate(x.BillDate), x.Days, x.Amount, x.Adjusted, x.Outstanding]);
        });
        downloadCsv(rows, 'statement_' + (c.Code || c.CName || 'customer') + '_' + state.asOf + '.csv');
    }

    function printStatement() {
        if (!cust.detail) return;
        var $closed = $('#billList details:not([open])').attr('open', true);
        $('body').addClass('print-modal');
        var done = function () { $('body').removeClass('print-modal'); $closed.removeAttr('open'); window.removeEventListener('afterprint', done); };
        window.addEventListener('afterprint', done);
        window.print();
        setTimeout(function () { if ($('body').hasClass('print-modal')) done(); }, 1500);
    }

    function showPane(p) {
        $('#custTabs .nav-link').removeClass('active').filter('[data-pane="' + p + '"]').addClass('active');
        $('#paneBills').toggleClass('d-none', p !== 'bills');
        $('#paneProds').toggleClass('d-none', p !== 'prods');
        $('#panePays').toggleClass('d-none', p !== 'pays');
        $('#paneStmt').toggleClass('d-none', p !== 'stmt');
    }

    // ------------------------------------------------------------ auto refresh
    function setAuto(on) {
        autoOn = on;
        $('#btnAuto').toggleClass('active', on).attr('aria-pressed', on)
            .attr('title', 'Auto-refresh every 60 seconds: ' + (on ? 'on' : 'off'));
        $('#liveDot').toggleClass('off', !on);
        clearInterval(autoTimer);
        if (on) autoTimer = setInterval(tick, AUTO_MS);
    }
    function tick() {
        if (document.hidden || busy > 0) return;
        loadSummary(true);
        if (cust.key && $('#custModal').hasClass('show')) loadCustomer(true);
    }

    // ------------------------------------------------------------ events
    $(function () {
        $('#ddlSession, #ddlArea, #txtAsOf, #ddlAuth').on('change', function () { view.limit = PAGE; loadSummary(false); });
        $('#btnRefresh').on('click', function () { loadSummary(false); if (cust.key && $('#custModal').hasClass('show')) loadCustomer(false); });
        $('#btnAuto').on('click', function () { setAuto(!autoOn); });
        $('#btnReset').on('click', function () {
            $('#ddlSession, #ddlArea').val(''); $('#txtAsOf').val(today); $('#ddlAuth').val('0'); $('#txtSearch').val('');
            view = { status: 'due', bucket: -1, sortKey: 'Outstanding', sortDir: -1, limit: PAGE, product: '' };
            $('#ddlProduct').val('');
            $('#stDue').prop('checked', true);
            loadSummary(false);
        });

        $('#kpiRow').on('click', '[data-act]', function () {
            var act = $(this).data('act');
            if (act === 'b90') {   // customers with dues, oldest first
                view.status = 'due'; view.bucket = -1; $('#stDue').prop('checked', true);
                view.sortKey = 'MaxDays'; view.sortDir = -1; renderCustomers();
            } else { view.status = act; view.bucket = -1; $(act === 'adv' ? '#stAdv' : '#stDue').prop('checked', true);
                   view.sortKey = act === 'adv' ? 'Received' : 'Outstanding'; view.sortDir = -1; renderCustomers(); }
            document.getElementById('tblCust').closest('section').scrollIntoView({ behavior: 'smooth', block: 'start' });
        });
        $('#ageTiles').on('click', '.age-tile', function () {
            setBucket(+$(this).data('bucket'));
            document.getElementById('tblCust').closest('section').scrollIntoView({ behavior: 'smooth', block: 'start' });
        });
        $('#bucketChip').on('click', 'button', function () { setBucket(view.bucket); });
        $('input[name=custStatus]').on('change', function () {
            view.status = $(this).val(); view.limit = PAGE;
            if (view.status !== 'due') view.bucket = -1;
            view.sortKey = view.status === 'adv' ? 'Received' : 'Outstanding'; view.sortDir = -1;
            renderCustomers();
        });
        var t;
        $('#txtSearch').on('input', function () { clearTimeout(t); t = setTimeout(function () { view.limit = PAGE; renderCustomers(); }, 200); });
        $('#tblCust').on('click', 'thead th', function () {
            var k = $(this).data('key');
            if (view.sortKey === k) view.sortDir *= -1; else { view.sortKey = k; view.sortDir = k === 'CName' ? 1 : -1; }
            renderCustomers();
        });
        $('#tblCust').on('click', 'tbody tr[data-cust]', function () { openCustomer($(this).attr('data-cust')); });
        $('#custCards').on('click keydown', '.cust-card', function (e) {
            if (e.type === 'keydown' && e.key !== 'Enter') return;
            openCustomer($(this).attr('data-cust'));
        });
        $('#tblArea').on('click', 'tr.area-row', function () {
            var a = $(this).attr('data-area');
            if (!a || a === '-') return;
            $('#ddlArea').val($('#ddlArea').val() === a ? '' : a).trigger('change');
        });
        $('#ddlProduct').on('change', function () { setProduct($(this).val(), false); });
        $('#tblProd').on('click', 'tbody tr[data-product]', function () { setProduct($(this).attr('data-product'), true); });
        $('#btnMore').on('click', function () { view.limit += PAGE; renderCustomers(); });
        $('#btnExport').on('click', exportCustomers);

        $('#custTabs').on('click', '.nav-link', function () { showPane($(this).data('pane')); });
        $('#chkSettled').on('change', function () { if (cust.detail) renderBills(); });
        $('#btnExpandAll').on('click', function () {
            var open = $(this).text() === 'Expand all';
            $('#billList details').prop('open', open);
            $(this).text(open ? 'Collapse all' : 'Expand all');
        });
        $('#btnCustExport').on('click', exportStatement);
        $('#btnPrint').on('click', printStatement);
        $('#custModal').on('hidden.bs.modal', function () { cust.key = null; cust.detail = null; });

        if (window.matchMedia('(max-width: 575.98px)').matches) $('#filterBody').removeClass('show');
        $('#ageFromLbl').text(LEDGER ? 'hatch date (opening balance and other ledger entries from their voucher date)'
                              : BY_HATCH ? 'hatch date (DM date if no hatch date)' : 'DM date');
        if (LEDGER) {
            // ledger covers one financial year and has no "authorised" flag: hide those filters
            $('#ddlSession, #ddlAuth').closest('[class*="col-"]').addClass('d-none');
            $('label[for="ddlArea"]').text('Station');
            $('#areaBody').closest('section').find('.panel-head h3').text('Station-wise aging');
            $('#ddlArea option:first').text('All stations');
            $('#ddlArea').closest('[class*="col-"]').removeClass('col-lg-3').addClass('col-lg-4');
        }

        loadFilters().done(function () { loadSummary(false); setAuto(true); });
    });
})(jQuery);
