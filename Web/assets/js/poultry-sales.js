/* ===== Poultry Products Sales Dashboard - client script =====
   Calls the [WebMethod]s in PoultrySales.aspx.cs with jQuery AJAX (no page reloads). */
(function ($) {
    'use strict';

    var cfg = window.PS_CONFIG || { pageUrl: 'PoultrySales.aspx' };
    var state = { session: '', areaCode: '', product: '', fromDate: '', toDate: '' };
    var charts = {};
    var currentTable = 'products';
    var lastData = null;

    var C = { sales: '#34568b', receipt: '#2e8b57', due: '#c0392b', grid: '#eeeae2', ink: '#5b6476' };
    var PALETTE = ['#34568b', '#e09a1a', '#2a9d8f', '#c2553d', '#7a5195', '#8fae2f', '#bc5090', '#5b8fd1', '#a0703b', '#8d99ae'];

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
    function fKg(v) {
        v = num(v);
        if (Math.abs(v) >= 100000) return nfQty.format(v / 1000) + ' t';
        return nfQty.format(v) + ' kg';
    }
    function fDate(s) { if (!s) return ''; var p = String(s).split('-'); return p.length === 3 ? p[2] + '-' + p[1] + '-' + p[0] : s; }
    function monthLabel(s) {
        var p = String(s).split('-'); var d = new Date(+p[0], +p[1] - 1, 1);
        return d.toLocaleString('en-IN', { month: 'short' }) + ' ' + p[0].slice(2);
    }
    function esc(s) {
        return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) {
            return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
        });
    }
    function qtyText(nos, kg) {
        var parts = [];
        if (num(kg)) parts.push(fKg(kg));
        if (num(nos)) parts.push(fInt(nos) + ' nos');
        return parts.join(' · ') || '–';
    }
    function balClass(v) { return num(v) > 0 ? 'text-due' : (num(v) < 0 ? 'text-adv' : ''); }

    // ------------------------------------------------------------ AJAX
    function callApi(method, payload) {
        return $.ajax({
            type: 'POST', url: cfg.pageUrl + '/' + method, data: JSON.stringify(payload || {}),
            contentType: 'application/json; charset=utf-8', dataType: 'json', timeout: 150000
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
        $('#btnRefresh').toggleClass('spinning', busy > 0);
    }
    function showError(m) { $('#alertText').text(m); $('#alertBox').removeClass('d-none').addClass('d-flex'); }
    function clearError() { $('#alertBox').addClass('d-none').removeClass('d-flex'); }

    // ------------------------------------------------------------ filters
    function loadFilters(session, first) {
        loading(true);
        return callApi('GetFilters', { session: session || null })
            .done(function (f) {
                if (first) {
                    var $s = $('#ddlSession').empty();
                    if (!(f.sessions || []).length) $s.append('<option value="">No sessions</option>');
                    (f.sessions || []).forEach(function (s) { $s.append($('<option>').val(s).text(s)); });
                    $s.val(f.currentSession);
                }
                var $a = $('#ddlArea').empty().append('<option value="">All areas</option>');
                (f.areas || []).forEach(function (a) { $a.append($('<option>').val(a.AreaCode).text(a.Area ? a.Area + ' (' + a.AreaCode + ')' : a.AreaCode)); });
                var keep = $('#ddlProduct').val();
                var $p = $('#ddlProduct').empty().append('<option value="">All products</option>');
                (f.products || []).forEach(function (p) { $p.append($('<option>').val(p.Product).text(p.Product)); });
                if (keep && (f.products || []).some(function (p) { return p.Product === keep; })) $p.val(keep);
            })
            .fail(showError)
            .always(function () { loading(false); });
    }

    function readFilters() {
        state.session = $('#ddlSession').val() || '';
        state.areaCode = $('#ddlArea').val() || '';
        state.product = $('#ddlProduct').val() || '';
        state.fromDate = $('#txtFrom').val() || '';
        state.toDate = $('#txtTo').val() || '';
        $('#filterHint').text('· ' + [state.session, state.areaCode ? $('#ddlArea option:selected').text() : 'All areas', state.product || 'All products'].join(' · '));
    }

    function loadDashboard() {
        readFilters();
        if (!state.session) return;
        clearError();
        loading(true);
        callApi('GetDashboard', state).done(render).fail(showError).always(function () { loading(false); });
    }

    // ------------------------------------------------------------ render
    function render(d) {
        lastData = d;
        $('#lblUpdated').text(d.generatedAt || '');
        var k = d.kpi || {};
        var empty = !num(k.DMCount) && !num(k.ReceiptCount);
        $('#emptyState').toggleClass('d-none', !empty);
        $('#dashBody').toggleClass('d-none', empty);
        $('#productNote').toggleClass('d-none', !state.product).toggleClass('d-flex', !!state.product);
        $('#lblProductNote').text(state.product);
        if (empty) return;
        renderKpis(k);
        $('#topRow, #topTitle').toggleClass('d-none', !!state.product);
        renderTopProducts(d.products || [], num(k.Sales));
        renderCharts(d);
        renderTax(d.tax || []);
        renderTable();
    }

    function kpiCard(o) {
        return '<div class="col-6 col-md-4 col-xl-2"><div class="kpi" style="--accent:' + o.color + '">' +
            '<div class="kpi-label"><i class="bi ' + o.icon + '"></i>' + esc(o.label) + '</div>' +
            '<div class="kpi-value ' + (o.cls || '') + '" title="' + esc(o.title || '') + '">' + o.value + '</div>' +
            '<div class="kpi-sub">' + o.sub + '</div>' + (o.extra || '') + '</div></div>';
    }

    function renderKpis(k) {
        var coll = Math.max(0, Math.min(100, num(k.CollectionPct)));
        var allProd = state.product ? ' <span class="text-muted">(all products)</span>' : '';
        var taxLine = 'Goods <b>' + fShort(k.Taxable) + '</b> · Tax <b>' + fShort(k.Tax) + '</b>' + (num(k.Charges) ? ' · Ins./TCS <b>' + fShort(k.Charges) + '</b>' : '');
        $('#kpiRow').html([
            kpiCard({ label: 'Sales value', icon: 'bi-receipt', color: C.sales, value: fShort(k.Sales), title: fMoney(k.Sales),
                sub: '<b>' + fInt(k.DMCount) + '</b> DMs · ' + taxLine }),
            kpiCard({ label: 'Quantity sold', icon: 'bi-box-seam', color: '#e09a1a',
                value: num(k.QtyKg) ? fKg(k.QtyKg) : fInt(k.QtyNos) + ' <small class="fs-6">nos</small>',
                title: nfQty.format(num(k.QtyKg)) + ' kg, ' + fInt(k.QtyNos) + ' nos',
                sub: num(k.QtyKg) ? '<b>' + fInt(k.QtyNos) + '</b> nos (bags / units)' : '&nbsp;' }),
            kpiCard({ label: 'Payment received', icon: 'bi-cash-coin', color: C.receipt, value: fShort(k.ReceiptAmt), title: fMoney(k.ReceiptAmt),
                sub: '<b>' + fInt(k.ReceiptCount) + '</b> receipts' + allProd }),
            kpiCard({ label: state.product ? 'Balance (all products)' : 'Balance', icon: 'bi-hourglass-split', color: C.due,
                value: state.product ? '–' : fShort(k.Outstanding), title: state.product ? 'Not available per product' : fMoney(k.Outstanding),
                cls: state.product ? '' : balClass(k.Outstanding),
                sub: state.product ? 'Clear the product filter to see it' : 'Collected <b>' + fPct(k.CollectionPct) + '</b>',
                extra: state.product ? '' : '<div class="bar"><span style="width:' + coll + '%"></span></div>' }),
            kpiCard({ label: 'Pending authorisation', icon: 'bi-shield-exclamation', color: '#7a5195', value: fShort(k.PendingAuthAmt), title: fMoney(k.PendingAuthAmt),
                sub: '<b>' + fInt(k.PendingAuthCount) + '</b> receipts' + allProd }),
            kpiCard({ label: 'Average DM value', icon: 'bi-calculator', color: '#2a9d8f', value: fShort(k.AvgBill), title: fMoney(k.AvgBill),
                sub: '<b>' + fInt(k.Customers) + '</b> customers · <b>' + fInt(k.Products) + '</b> product' + (num(k.Products) === 1 ? '' : 's') })
        ].join(''));
    }

    function renderTopProducts(rows, total) {
        var top = rows.slice(0, 4);
        if (!top.length) { $('#topRow').html('<div class="col-12 text-muted small">No product lines</div>'); return; }
        $('#topRow').html(top.map(function (r, i) {
            var share = total ? num(r.Sales) * 100 / total : 0;
            return '<div class="col-12 col-sm-6 col-xl-3"><div class="prod-card" style="--pc:' + PALETTE[i] + '" data-product="' + esc(r.Product) + '" title="Filter by this product">' +
                '<div class="rank">#' + (i + 1) + ' by sales' + (r.HsnCode ? ' · HSN ' + esc(r.HsnCode) : '') + '</div>' +
                '<div class="name">' + esc(r.Product) + '</div>' +
                '<div class="sales" title="' + fMoney(r.Sales) + '">' + fShort(r.Sales) + '</div>' +
                '<div class="bar"><span style="width:' + Math.min(100, share).toFixed(1) + '%"></span></div>' +
                '<div class="meta"><span><b>' + fPct(share) + '</b> of sales</span><span>' + qtyText(r.QtyNos, r.QtyKg) + '</span></div>' +
                '<div class="meta"><span>Avg rate <b>' + fAmt(r.AvgRate) + '</b>/' + esc(r.RateUnit) + '</span><span>' + fInt(r.Customers) + ' customers</span></div>' +
                '</div></div>';
        }).join(''));
    }

    function renderTax(rows) {
        if (!rows.length) { $('#taxList').html('<span class="small text-muted">No product lines</span>'); return; }
        $('#taxList').html(rows.map(function (r) {
            var label = num(r.TaxPer) ? r.TaxType + ' ' + nfQty.format(num(r.TaxPer)) + '%' : (r.TaxType === 'Exempt' ? 'Nil / exempt' : r.TaxType + ' 0%');
            return '<div class="tax-row"><span>' + esc(label) + ' <span class="t">(' + fInt(r.LineCount) + ' lines)</span></span>' +
                '<span class="t">on ' + fShort(r.Taxable) + '</span><b>' + fShort(r.Tax) + '</b></div>';
        }).join(''));
    }

    // ------------------------------------------------------------ charts
    if (window.Chart) {
        Chart.defaults.font.family = "'Plus Jakarta Sans', system-ui, sans-serif";
        Chart.defaults.color = C.ink;
        Chart.defaults.plugins.legend.position = 'bottom';
        Chart.defaults.plugins.legend.labels.boxWidth = 12;
        Chart.defaults.plugins.legend.labels.usePointStyle = true;
        Chart.defaults.maintainAspectRatio = false;
    }
    function makeChart(id, config) {
        if (!window.Chart) return;
        if (charts[id]) charts[id].destroy();
        charts[id] = new Chart(document.getElementById(id), config);
    }
    function moneyAxis() { return { grid: { color: C.grid }, ticks: { callback: function (v) { return fShort(v); } }, beginAtZero: true }; }

    function renderCharts(d) {
        var m = d.monthly || [];
        var run = 0, cum = m.map(function (r) { run += num(r.Sales) - num(r.ReceiptAmt); return run; });
        var trendSets = [
            { label: 'Sales', data: m.map(function (r) { return num(r.Sales); }), backgroundColor: C.sales, borderRadius: 5, order: 1 },
            { label: 'Received', data: m.map(function (r) { return num(r.ReceiptAmt); }), backgroundColor: C.receipt, borderRadius: 5, order: 1 }
        ];
        if (!state.product) trendSets.unshift({ type: 'line', label: 'Running balance', data: cum, borderColor: C.due, backgroundColor: C.due, tension: .3, pointRadius: 3, borderWidth: 2, order: 0 });
        makeChart('chTrend', {
            type: 'bar',
            data: { labels: m.map(function (r) { return monthLabel(r.MonthStart); }), datasets: trendSets },
            options: {
                interaction: { mode: 'index', intersect: false },
                plugins: { tooltip: { callbacks: { label: function (c) { return ' ' + c.dataset.label + ': ' + fMoney(c.parsed.y); } } } },
                scales: { x: { grid: { display: false } }, y: moneyAxis() }
            }
        });

        // product share doughnut: top 8 + others
        var prods = d.products || [];
        var top = prods.slice(0, 8), rest = prods.slice(8).reduce(function (s, r) { return s + num(r.Sales); }, 0);
        var labels = top.map(function (r) { return r.Product; }), vals = top.map(function (r) { return num(r.Sales); });
        if (rest > 0) { labels.push('Others'); vals.push(rest); }
        makeChart('chShare', {
            type: 'doughnut',
            data: { labels: labels, datasets: [{ data: vals, backgroundColor: labels.map(function (l, i) { return l === 'Others' ? '#c9c3b7' : PALETTE[i % PALETTE.length]; }), borderWidth: 2, borderColor: '#fff' }] },
            options: {
                cutout: '58%',
                plugins: {
                    legend: { position: window.innerWidth < 576 ? 'bottom' : 'right', labels: { generateLabels: function (ch) {
                        var base = Chart.overrides.doughnut.plugins.legend.labels.generateLabels(ch);
                        base.forEach(function (l) { if (l.text.length > 22) l.text = l.text.slice(0, 21) + '…'; });
                        return base;
                    } } },
                    tooltip: { callbacks: { label: function (c) {
                        var t = c.dataset.data.reduce(function (a, b) { return a + b; }, 0);
                        return ' ' + c.label + ': ' + fMoney(c.parsed) + ' (' + (t ? (c.parsed * 100 / t).toFixed(1) : 0) + '%)';
                    } } }
                },
                onClick: function (e, els) { if (els.length) { var l = labels[els[0].index]; if (l !== 'Others') setProduct(l); } }
            }
        });

        // monthly sales by product (stacked)
        var mp = d.monthlyProducts || [];
        var months = [], prodNames = [];
        mp.forEach(function (r) {
            if (months.indexOf(r.MonthStart) < 0) months.push(r.MonthStart);
            if (prodNames.indexOf(r.Product) < 0) prodNames.push(r.Product);
        });
        months.sort();
        prodNames.sort(function (a, b) {
            if (a === 'Others') return 1; if (b === 'Others') return -1;
            var ia = prods.findIndex(function (p) { return p.Product === a; }), ib = prods.findIndex(function (p) { return p.Product === b; });
            return ia - ib;
        });
        makeChart('chMonthProd', {
            type: 'bar',
            data: {
                labels: months.map(monthLabel),
                datasets: prodNames.map(function (p, i) {
                    return {
                        label: p.length > 22 ? p.slice(0, 21) + '…' : p, fullName: p, stack: 's', borderRadius: 3,
                        backgroundColor: p === 'Others' ? '#c9c3b7' : PALETTE[i % PALETTE.length],
                        data: months.map(function (mo) {
                            var r = mp.filter(function (x) { return x.MonthStart === mo && x.Product === p; })[0];
                            return r ? num(r.Sales) : 0;
                        })
                    };
                })
            },
            options: {
                interaction: { mode: 'index', intersect: false },
                plugins: { tooltip: { callbacks: { label: function (c) { return c.parsed.y ? ' ' + c.dataset.fullName + ': ' + fMoney(c.parsed.y) : null; } } } },
                scales: { x: { stacked: true, grid: { display: false } }, y: Object.assign(moneyAxis(), { stacked: true }) }
            }
        });

        // payment mode
        var pm = d.payMode || [];
        makeChart('chPayMode', {
            type: 'doughnut',
            data: { labels: pm.map(function (r) { return r.PayMode; }),
                datasets: [{ data: pm.map(function (r) { return num(r.Amount); }), backgroundColor: pm.map(function (r, i) { return PALETTE[i % PALETTE.length]; }), borderWidth: 2, borderColor: '#fff' }] },
            options: {
                cutout: '62%',
                plugins: { legend: { position: 'right' },
                    tooltip: { callbacks: { label: function (c) {
                        var t = c.dataset.data.reduce(function (a, b) { return a + b; }, 0);
                        return ' ' + c.label + ': ' + fMoney(c.parsed) + ' (' + (t ? (c.parsed * 100 / t).toFixed(1) : 0) + '%)';
                    } } } }
            }
        });

        // top 12 areas
        var ar = (d.areas || []).slice(0, 12);
        makeChart('chArea', {
            type: 'bar',
            data: {
                labels: ar.map(function (r) { return r.Area || r.AreaCode || '(blank)'; }),
                datasets: [
                    { label: 'Sales', data: ar.map(function (r) { return num(r.Sales); }), backgroundColor: C.sales, borderRadius: 4 },
                    { label: 'Received', data: ar.map(function (r) { return num(r.ReceiptAmt); }), backgroundColor: C.receipt, borderRadius: 4 }
                ]
            },
            options: {
                indexAxis: 'y', interaction: { mode: 'index', intersect: false },
                plugins: { tooltip: { callbacks: { label: function (c) { return ' ' + c.dataset.label + ': ' + fMoney(c.parsed.x); } } } },
                scales: { y: { grid: { display: false } }, x: moneyAxis() }
            }
        });
    }

    // ------------------------------------------------------------ tables
    var TABLES = {
        products: { source: 'products', file: 'products', sortKey: 'Sales', sortDir: -1, click: 'Product', cols: [
            { k: 'Product', l: 'Product' }, { k: 'HsnCode', l: 'HSN' }, { k: 'DMCount', l: 'DMs', t: 'int' }, { k: 'Customers', l: 'Customers', t: 'int' },
            { k: 'QtyNos', l: 'Qty (Nos)', t: 'int' }, { k: 'QtyKg', l: 'Qty (Kg)', t: 'qty' },
            { k: 'AvgRate', l: 'Avg rate', t: 'money', noTotal: true }, { k: 'MinRate', l: 'Min rate', t: 'money', noTotal: true }, { k: 'MaxRate', l: 'Max rate', t: 'money', noTotal: true },
            { k: 'Taxable', l: 'Amount', t: 'money' }, { k: 'Tax', l: 'Tax', t: 'money' }, { k: 'Sales', l: 'Total', t: 'money' },
            { k: 'LastSale', l: 'Last sale', t: 'date' }] },
        customers: { source: 'customers', file: 'customers', sortKey: 'Sales', sortDir: -1, cols: [
            { k: 'Code', l: 'Code' }, { k: 'CName', l: 'Customer' }, { k: 'Area', l: 'Area' }, { k: 'DMCount', l: 'DMs', t: 'int' },
            { k: 'QtyNos', l: 'Qty (Nos)', t: 'int' }, { k: 'QtyKg', l: 'Qty (Kg)', t: 'qty' },
            { k: 'Sales', l: 'Sales', t: 'money' }, { k: 'ReceiptAmt', l: 'Received', t: 'money', allProd: true }, { k: 'Balance', l: 'Balance', t: 'bal', allProd: true },
            { k: 'LastDMDate', l: 'Last DM', t: 'date' }, { k: 'LastReceiptDate', l: 'Last payment', t: 'date' }] },
        areas: { source: 'areas', file: 'areas', sortKey: 'Sales', sortDir: -1, cols: [
            { k: 'AreaCode', l: 'Code' }, { k: 'Area', l: 'Area' }, { k: 'DMCount', l: 'DMs', t: 'int' }, { k: 'Customers', l: 'Customers', t: 'int' },
            { k: 'QtyNos', l: 'Qty (Nos)', t: 'int' }, { k: 'QtyKg', l: 'Qty (Kg)', t: 'qty' }, { k: 'Sales', l: 'Sales', t: 'money' },
            { k: 'ReceiptCount', l: 'Receipts', t: 'int' }, { k: 'ReceiptAmt', l: 'Received', t: 'money', allProd: true },
            { k: 'Balance', l: 'Balance', t: 'bal', allProd: true }, { k: 'CollectionPct', l: 'Collected', t: 'pct', noTotal: true, allProd: true }] },
        dms: { source: 'dms', file: 'dm-register', sortKey: 'DMDate', sortDir: -1, cols: [
            { k: 'DMNo', l: 'DM No' }, { k: 'DMDate', l: 'Date', t: 'date' }, { k: 'Code', l: 'Code' }, { k: 'CName', l: 'Customer' }, { k: 'Area', l: 'Area' },
            { k: 'Products', l: 'Products', t: 'wrap' }, { k: 'QtyNos', l: 'Nos', t: 'int' }, { k: 'QtyKg', l: 'Kg', t: 'qty' },
            { k: 'Taxable', l: 'Amount', t: 'money' }, { k: 'Tax', l: 'Tax', t: 'money' }, { k: 'Insurance', l: 'Insurance', t: 'money' }, { k: 'Tcs', l: 'TCS', t: 'money' },
            { k: 'Total', l: 'Total', t: 'money' }, { k: 'VehNo', l: 'Vehicle' }, { k: 'DriverName', l: 'Driver' }] },
        lines: { source: 'lines', file: 'product-lines', sortKey: 'DMDate', sortDir: -1, cols: [
            { k: 'DMNo', l: 'DM No' }, { k: 'DMDate', l: 'Date', t: 'date' }, { k: 'CName', l: 'Customer' }, { k: 'Area', l: 'Area' },
            { k: 'Product', l: 'Product' }, { k: 'HsnCode', l: 'HSN' }, { k: 'QtyNos', l: 'Nos', t: 'int' }, { k: 'QtyKg', l: 'Kg', t: 'qty' },
            { k: 'Rate', l: 'Rate', t: 'money', noTotal: true }, { k: 'Amount', l: 'Amount', t: 'money' }, { k: 'TaxPer', l: 'Tax %', t: 'qty', noTotal: true },
            { k: 'TaxValue', l: 'Tax', t: 'money' }, { k: 'LineTotal', l: 'Total', t: 'money' }] },
        receipts: { source: 'receipts', file: 'receipts', sortKey: 'TrDate', sortDir: -1, cols: [
            { k: 'TRNo', l: 'TR No' }, { k: 'TrDate', l: 'Date', t: 'date' }, { k: 'Code', l: 'Code' }, { k: 'CName', l: 'Customer' }, { k: 'Area', l: 'Area' },
            { k: 'PayMode', l: 'Mode' }, { k: 'PayType', l: 'Pay type' }, { k: 'DD_No', l: 'DD / Ref' }, { k: 'Bank_det', l: 'Bank' },
            { k: 'Amount', l: 'Amount', t: 'money' }, { k: 'IsAuth', l: 'Status', t: 'auth' }] }
    };
    var NUMERIC = { int: 1, money: 1, qty: 1, pct: 1, bal: 1 };

    function tableRows() {
        var T = TABLES[currentTable];
        var rows = (lastData && lastData[T.source]) || [];
        var q = ($('#txtSearch').val() || '').trim().toLowerCase();
        if (q) rows = rows.filter(function (r) { return T.cols.some(function (c) { return String(r[c.k] == null ? '' : r[c.k]).toLowerCase().indexOf(q) >= 0; }); });
        var col = T.cols.filter(function (c) { return c.k === T.sortKey; })[0] || {};
        var isNum = NUMERIC[col.t] || col.t === 'auth';
        return rows.slice().sort(function (a, b) {
            var x = a[T.sortKey], y = b[T.sortKey];
            if (isNum) return (num(x) - num(y)) * T.sortDir;
            return String(x == null ? '' : x).localeCompare(String(y == null ? '' : y), 'en', { numeric: true }) * T.sortDir;
        });
    }
    function cellHtml(c, v) {
        switch (c.t) {
            case 'int': return num(v) ? fInt(v) : '<span class="text-muted">–</span>';
            case 'qty': return num(v) ? nfQty.format(num(v)) : '<span class="text-muted">–</span>';
            case 'money': return fAmt(v);
            case 'bal': return '<span class="' + balClass(v) + '">' + fAmt(v) + '</span>';
            case 'pct': return fPct(v);
            case 'date': return fDate(v);
            case 'wrap': return '<div style="white-space:normal;min-width:220px">' + esc(v) + '</div>';
            case 'auth': return num(v) === 1 ? '<span class="badge text-bg-success">Authorised</span>' : '<span class="badge text-bg-warning">Pending</span>';
            default: return esc(v);
        }
    }
    function colLabel(c) { return c.l + (c.allProd && state.product ? ' (all products)' : ''); }

    function renderTable() {
        var T = TABLES[currentTable];
        var all = (lastData && lastData[T.source]) || [];
        var rows = tableRows();
        $('#tblData thead').html('<tr>' + T.cols.map(function (c) {
            var sorted = c.k === T.sortKey;
            var icon = sorted ? (T.sortDir > 0 ? 'bi-sort-up' : 'bi-sort-down') : 'bi-arrow-down-up';
            return '<th data-key="' + c.k + '" class="' + (NUMERIC[c.t] ? 'num ' : '') + (sorted ? 'sorted' : '') + '">' + esc(colLabel(c)) + '<i class="bi ' + icon + ' si"></i></th>';
        }).join('') + '</tr>');
        $('#tblData tbody').html(rows.length ? rows.map(function (r) {
            var attr = T.click ? ' data-product="' + esc(r[T.click]) + '" style="cursor:pointer" title="Filter by this product"' : '';
            return '<tr' + attr + '>' + T.cols.map(function (c) { return '<td class="' + (NUMERIC[c.t] ? 'num' : '') + '">' + cellHtml(c, r[c.k]) + '</td>'; }).join('') + '</tr>';
        }).join('') : '<tr><td colspan="' + T.cols.length + '" class="text-center text-muted py-4">No records</td></tr>');
        $('#tblData tfoot').html(rows.length ? '<tr>' + T.cols.map(function (c, i) {
            if (i === 0) return '<td>Total</td>';
            if (!NUMERIC[c.t] || c.noTotal) return '<td></td>';
            var s = rows.reduce(function (a, r) { return a + num(r[c.k]); }, 0);
            return '<td class="num">' + (c.t === 'int' ? fInt(s) : c.t === 'qty' ? nfQty.format(s) : cellHtml(c, s)) + '</td>';
        }).join('') + '</tr>' : '');
        var limited = { dms: 300, lines: 500, receipts: 300 }[currentTable];
        $('#lblRows').text('Showing ' + fInt(rows.length) + ' of ' + fInt(all.length) + ' rows' + (limited ? ' (latest ' + limited + ' for the filters)' : '') +
            (currentTable === 'products' ? ' · tap a product to filter the dashboard' : ''));
    }

    function exportCsv() {
        var T = TABLES[currentTable];
        var q = function (v) { v = v == null ? '' : String(v); return /[",\n]/.test(v) ? '"' + v.replace(/"/g, '""') + '"' : v; };
        var lines = [T.cols.map(function (c) { return q(colLabel(c)); }).join(',')];
        tableRows().forEach(function (r) {
            lines.push(T.cols.map(function (c) {
                var v = r[c.k];
                if (c.t === 'auth') v = num(v) === 1 ? 'Authorised' : 'Pending';
                if (c.t === 'date') v = fDate(v);
                return q(v);
            }).join(','));
        });
        var blob = new Blob(['﻿' + lines.join('\r\n')], { type: 'text/csv;charset=utf-8' });
        var a = document.createElement('a');
        a.href = URL.createObjectURL(blob);
        a.download = ('poultry-' + T.file + '_' + state.session + (state.product ? '_' + state.product : '') + '.csv').replace(/[^\w.\-]/g, '_');
        document.body.appendChild(a); a.click();
        setTimeout(function () { URL.revokeObjectURL(a.href); a.remove(); }, 500);
    }

    function setProduct(p) {
        var cur = $('#ddlProduct').val();
        $('#ddlProduct').val(cur === p ? '' : p);
        window.scrollTo({ top: 0, behavior: 'smooth' });
        loadDashboard();
    }

    // ------------------------------------------------------------ events
    $(function () {
        $('#ddlSession').on('change', function () { loadFilters($(this).val(), false).done(loadDashboard); });
        $('#ddlArea, #ddlProduct, #txtFrom, #txtTo').on('change', loadDashboard);
        $('#btnRefresh').on('click', loadDashboard);
        $('#btnReset').on('click', function () {
            $('#ddlArea, #ddlProduct').val(''); $('#txtFrom, #txtTo').val('');
            loadDashboard();
        });
        $('#topRow').on('click', '.prod-card', function () { setProduct($(this).attr('data-product')); });
        $('#tblData').on('click', 'tbody tr[data-product]', function () { setProduct($(this).attr('data-product')); });
        $('.detail-tabs').on('click', '.nav-link', function () {
            $('.detail-tabs .nav-link').removeClass('active'); $(this).addClass('active');
            currentTable = $(this).data('table'); $('#txtSearch').val(''); renderTable();
        });
        $('#tblData').on('click', 'thead th', function () {
            var T = TABLES[currentTable], key = $(this).data('key');
            if (T.sortKey === key) T.sortDir *= -1; else { T.sortKey = key; T.sortDir = -1; }
            renderTable();
        });
        var t;
        $('#txtSearch').on('input', function () { clearTimeout(t); t = setTimeout(renderTable, 200); });
        $('#btnExport').on('click', exportCsv);
        if (window.matchMedia('(max-width: 575.98px)').matches) $('#filterBody').removeClass('show');
        loadFilters(null, true).done(loadDashboard);
    });
})(jQuery);
