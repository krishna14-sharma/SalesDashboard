/* ===== Chick Sales & Payment Dashboard - client script =====
   Talks to the [WebMethod] page methods in Default.aspx.cs via jQuery AJAX,
   so filters update the dashboard without any page reload. */
(function ($) {
    'use strict';

    var cfg = window.DASH_CONFIG || { pageUrl: 'Default.aspx' };

    var state = { session: '', areaCode: '', chickType: '', fromDate: '', toDate: '' };
    var charts = {};
    var currentTable = 'areas';
    var lastData = null;

    var TYPES = ['Broiler', 'Layer', 'Cockrel'];
    var COLORS = {
        Broiler: '#e09a1a', Layer: '#2a9d8f', Cockrel: '#c2553d', Other: '#8d99ae',
        sales: '#34568b', receipt: '#2e8b57', due: '#c0392b', grid: '#eeeae2', ink: '#5b6476'
    };
    var PALETTE = ['#34568b', '#2e8b57', '#e09a1a', '#c2553d', '#2a9d8f', '#7a5195', '#8d99ae', '#bc5090'];
    var TYPE_ICON = { Broiler: 'bi-egg-fried', Layer: 'bi-egg', Cockrel: 'bi-feather', Other: 'bi-question-circle' };
    var TYPE_SOFT = { Broiler: '#fdf3e1', Layer: '#e3f3f1', Cockrel: '#f8e7e3', Other: '#eef0f4' };

    // ------------------------------------------------------------ formatting
    var nfInt = new Intl.NumberFormat('en-IN', { maximumFractionDigits: 0 });
    var nf2 = new Intl.NumberFormat('en-IN', { minimumFractionDigits: 2, maximumFractionDigits: 2 });

    function num(v) { v = Number(v); return isFinite(v) ? v : 0; }
    function fInt(v) { return nfInt.format(num(v)); }
    function fMoney(v) { return '₹' + nf2.format(num(v)); }
    function fPct(v) { return num(v).toFixed(1) + '%'; }
    function fShort(v) {
        v = num(v);
        var a = Math.abs(v);
        if (a >= 1e7) return '₹' + (v / 1e7).toFixed(2) + ' Cr';
        if (a >= 1e5) return '₹' + (v / 1e5).toFixed(2) + ' L';
        return '₹' + nfInt.format(v);
    }
    function fShortNum(v) {
        v = num(v);
        var a = Math.abs(v);
        if (a >= 1e7) return (v / 1e7).toFixed(1) + ' Cr';
        if (a >= 1e5) return (v / 1e5).toFixed(1) + ' L';
        if (a >= 1e3) return (v / 1e3).toFixed(1) + 'K';
        return nfInt.format(v);
    }
    function fDate(s) {
        if (!s) return '';
        var p = String(s).split('-');
        return p.length === 3 ? p[2] + '-' + p[1] + '-' + p[0] : s;
    }
    function monthLabel(s) {
        var p = String(s).split('-');
        var d = new Date(+p[0], +p[1] - 1, 1);
        return d.toLocaleString('en-IN', { month: 'short' }) + ' ' + p[0].slice(2);
    }
    function esc(s) {
        return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) {
            return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
        });
    }
    function dueClass(v) { return num(v) > 0 ? 'text-due' : (num(v) < 0 ? 'text-adv' : ''); }

    // ------------------------------------------------------------ AJAX
    function callApi(method, payload) {
        return $.ajax({
            type: 'POST',
            url: cfg.pageUrl + '/' + method,
            data: JSON.stringify(payload || {}),
            contentType: 'application/json; charset=utf-8',
            dataType: 'json',
            timeout: 120000
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
        busy += on ? 1 : -1;
        if (busy < 0) busy = 0;
        $('#loader').toggleClass('show', busy > 0);
        $('#btnRefresh').toggleClass('spinning', busy > 0);
    }
    function showError(msg) {
        $('#alertText').text(msg);
        $('#alertBox').removeClass('d-none');
    }
    function clearError() { $('#alertBox').addClass('d-none'); }

    // ------------------------------------------------------------ filters
    function fillSessions(list, selected) {
        var $s = $('#ddlSession').empty();
        if (!list.length) $s.append('<option value="">No sessions</option>');
        list.forEach(function (s) { $s.append($('<option>').val(s).text(s)); });
        if (selected) $s.val(selected);
    }
    function fillAreas(list) {
        var $a = $('#ddlArea').empty().append('<option value="">All areas</option>');
        list.forEach(function (a) {
            var label = a.Area ? a.Area + ' (' + a.AreaCode + ')' : a.AreaCode;
            $a.append($('<option>').val(a.AreaCode).text(label));
        });
    }

    function loadFilters(session, firstLoad) {
        loading(true);
        return callApi('GetFilters', { session: session || null })
            .done(function (f) {
                if (firstLoad) fillSessions(f.sessions || [], f.currentSession);
                fillAreas(f.areas || []);
                state.session = f.currentSession || '';
                state.areaCode = '';
            })
            .fail(showError)
            .always(function () { loading(false); });
    }

    function readFilters() {
        state.session = $('#ddlSession').val() || '';
        state.areaCode = $('#ddlArea').val() || '';
        state.chickType = $('input[name=chickType]:checked').val() || '';
        state.fromDate = $('#txtFrom').val() || '';
        state.toDate = $('#txtTo').val() || '';
    }

    // ------------------------------------------------------------ dashboard
    function loadDashboard() {
        readFilters();
        if (!state.session) return;
        clearError();
        loading(true);
        callApi('GetDashboard', state)
            .done(render)
            .fail(showError)
            .always(function () { loading(false); });
    }

    function render(d) {
        lastData = d;
        $('#lblUpdated').text(d.generatedAt || '');
        var k = d.kpi || {};
        var empty = !num(k.DMLines) && !num(k.ReceiptCount);
        $('#emptyState').toggleClass('d-none', !empty);
        $('#dashBody').toggleClass('d-none', empty);
        if (empty) return;

        renderKpis(k);
        renderTypeCards(d.byType || []);
        renderCharts(d);
        renderPayTypes(d.payType || []);
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
        var html = [
            kpiCard({ label: 'Chicks dispatched', icon: 'bi-box-seam', color: COLORS.Broiler,
                value: fInt(k.NetChicks), title: 'Net chicks (total - mortality)',
                sub: 'Total <b>' + fInt(k.TotalChicks) + '</b> &middot; Mort. <b>' + fInt(k.Mortality) + '</b> (' + fPct(k.MortalityPct) + ')' }),
            kpiCard({ label: 'Sales value', icon: 'bi-receipt', color: COLORS.sales,
                value: fShort(k.SalesAmt), title: fMoney(k.SalesAmt),
                sub: '<b>' + fInt(k.DMCount) + '</b> dispatch memos' }),
            kpiCard({ label: 'Payment received', icon: 'bi-cash-coin', color: COLORS.receipt,
                value: fShort(k.ReceiptAmt), title: fMoney(k.ReceiptAmt),
                sub: '<b>' + fInt(k.ReceiptCount) + '</b> receipts' }),
            kpiCard({ label: 'Outstanding', icon: 'bi-hourglass-split', color: COLORS.due,
                value: fShort(k.Outstanding), title: fMoney(k.Outstanding), cls: dueClass(k.Outstanding),
                sub: 'Collected <b>' + fPct(k.CollectionPct) + '</b>',
                extra: '<div class="bar"><span style="width:' + coll + '%"></span></div>' }),
            kpiCard({ label: 'Pending authorisation', icon: 'bi-shield-exclamation', color: '#7a5195',
                value: fShort(k.PendingAuthAmt), title: fMoney(k.PendingAuthAmt),
                sub: '<b>' + fInt(k.PendingAuthCount) + '</b> receipts &middot; Auth. ' + fShort(k.AuthAmt) }),
            kpiCard({ label: 'Avg rate / chick', icon: 'bi-tag', color: COLORS.Layer,
                value: fMoney(k.AvgRate), sub: '<b>' + fInt(k.CustomerCount) + '</b> customers' })
        ];
        $('#kpiRow').html(html.join(''));
    }

    function renderTypeCards(rows) {
        var byName = {};
        rows.forEach(function (r) { byName[r.ChickType] = r; });
        var list = TYPES.slice();
        var other = byName.Other;
        if (other && (num(other.SalesAmt) || num(other.ReceiptAmt))) list.push('Other');

        var html = list.map(function (t) {
            var r = byName[t] || {};
            var dim = state.chickType && state.chickType !== t;
            var coll = Math.max(0, Math.min(100, num(r.CollectionPct)));
            return '<div class="col-12 col-sm-6 col-xl-' + (list.length === 4 ? 3 : 4) + '">' +
                '<div class="type-card' + (dim ? ' dim' : '') + '" style="--tc:' + COLORS[t] + ';--tc-soft:' + TYPE_SOFT[t] + '">' +
                '<div class="type-head"><div class="type-icon"><i class="bi ' + TYPE_ICON[t] + '"></i></div>' +
                '<div><div class="type-name">' + t + '</div><div class="small text-muted">' + fInt(r.DMCount) + ' DMs &middot; ' + fInt(r.ReceiptCount) + ' receipts</div></div>' +
                '<div class="type-chicks"><div class="num">' + fInt(r.NetChicks) + '</div><div class="lbl">net chicks</div></div></div>' +
                '<div class="type-body"><div class="type-grid">' +
                cell('Sales', fShort(r.SalesAmt), fMoney(r.SalesAmt)) +
                cell('Received', fShort(r.ReceiptAmt), fMoney(r.ReceiptAmt)) +
                cell('Outstanding', fShort(r.Outstanding), fMoney(r.Outstanding), dueClass(r.Outstanding)) +
                cell('Avg rate', fMoney(r.AvgRate)) +
                cell('Total chicks', fInt(r.Chicks)) +
                cell('Mortality', fInt(r.Mortality) + ' <span class="text-muted small">(' + fPct(r.MortalityPct) + ')</span>') +
                '</div><div class="type-progress"><div class="bar"><span style="width:' + coll + '%"></span></div>' +
                '<div class="meta"><span>Collection</span><b>' + fPct(r.CollectionPct) + '</b></div></div></div></div></div>';
        });
        $('#typeRow').html(html.join(''));

        function cell(label, val, title, cls) {
            return '<div><div class="lbl">' + label + '</div><div class="val ' + (cls || '') + '" title="' + esc(title || '') + '">' + val + '</div></div>';
        }
    }

    function renderPayTypes(rows) {
        var total = rows.reduce(function (s, r) { return s + num(r.Amount); }, 0);
        if (!rows.length) { $('#payTypeList').html('<span class="small text-muted">No receipts</span>'); return; }
        $('#payTypeList').html(rows.map(function (r) {
            var pct = total ? num(r.Amount) * 100 / total : 0;
            return '<div class="paytype-row"><span>' + esc(r.PayType) + ' <span class="text-muted">(' + fInt(r.ReceiptCount) + ')</span></span>' +
                '<b>' + fShort(r.Amount) + '</b><div class="bar"><span style="width:' + pct.toFixed(1) + '%"></span></div></div>';
        }).join(''));
    }

    // ------------------------------------------------------------ charts
    if (window.Chart) {
        Chart.defaults.font.family = "'Plus Jakarta Sans', system-ui, sans-serif";
        Chart.defaults.color = COLORS.ink;
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
    function moneyTooltip(ctx) { return ' ' + ctx.dataset.label + ': ' + fMoney(ctx.parsed.y != null && ctx.chart.options.indexAxis !== 'y' ? ctx.parsed.y : ctx.parsed.x); }
    function moneyAxis() { return { grid: { color: COLORS.grid }, ticks: { callback: function (v) { return fShort(v); } }, beginAtZero: true }; }

    function renderCharts(d) {
        // 1. Sales vs payment by chick type
        var types = (d.byType || []).filter(function (r) {
            return r.ChickType !== 'Other' || num(r.SalesAmt) || num(r.ReceiptAmt);
        });
        makeChart('chType', {
            type: 'bar',
            data: {
                labels: types.map(function (r) { return r.ChickType; }),
                datasets: [
                    { label: 'Sales', data: types.map(function (r) { return num(r.SalesAmt); }), backgroundColor: COLORS.sales, borderRadius: 6 },
                    { label: 'Received', data: types.map(function (r) { return num(r.ReceiptAmt); }), backgroundColor: COLORS.receipt, borderRadius: 6 },
                    { label: 'Outstanding', data: types.map(function (r) { return num(r.Outstanding); }), backgroundColor: COLORS.due, borderRadius: 6 }
                ]
            },
            options: { plugins: { tooltip: { callbacks: { label: moneyTooltip } } }, scales: { x: { grid: { display: false } }, y: moneyAxis() } }
        });

        // 2. Monthly trend + running outstanding
        var m = d.monthly || [];
        var run = 0;
        var cum = m.map(function (r) { run += num(r.SalesAmt) - num(r.ReceiptAmt); return run; });
        makeChart('chTrend', {
            type: 'bar',
            data: {
                labels: m.map(function (r) { return monthLabel(r.MonthStart); }),
                datasets: [
                    { type: 'line', label: 'Running outstanding', data: cum, borderColor: COLORS.due, backgroundColor: COLORS.due, tension: .3, pointRadius: 3, borderWidth: 2, order: 0 },
                    { label: 'Sales', data: m.map(function (r) { return num(r.SalesAmt); }), backgroundColor: COLORS.sales, borderRadius: 5, order: 1 },
                    { label: 'Received', data: m.map(function (r) { return num(r.ReceiptAmt); }), backgroundColor: COLORS.receipt, borderRadius: 5, order: 1 }
                ]
            },
            options: {
                interaction: { mode: 'index', intersect: false },
                plugins: { tooltip: { callbacks: { label: moneyTooltip } } },
                scales: { x: { grid: { display: false } }, y: moneyAxis() }
            }
        });

        // 3. Monthly chicks by type (stacked)
        var chickSets = TYPES.map(function (t) {
            return { label: t, data: m.map(function (r) { return num(r[t]); }), backgroundColor: COLORS[t], borderRadius: 4, stack: 'c' };
        });
        if (m.some(function (r) { return num(r.OtherChicks); })) {
            chickSets.push({ label: 'Other', data: m.map(function (r) { return num(r.OtherChicks); }), backgroundColor: COLORS.Other, stack: 'c' });
        }
        makeChart('chChicks', {
            type: 'bar',
            data: { labels: m.map(function (r) { return monthLabel(r.MonthStart); }), datasets: chickSets },
            options: {
                interaction: { mode: 'index', intersect: false },
                plugins: { tooltip: { callbacks: { label: function (c) { return ' ' + c.dataset.label + ': ' + fInt(c.parsed.y); } } } },
                scales: {
                    x: { stacked: true, grid: { display: false } },
                    y: { stacked: true, beginAtZero: true, grid: { color: COLORS.grid }, ticks: { callback: fShortNum } }
                }
            }
        });

        // 4. Payment mode doughnut
        var pm = d.payMode || [];
        makeChart('chPayMode', {
            type: 'doughnut',
            data: {
                labels: pm.map(function (r) { return r.PayMode; }),
                datasets: [{ data: pm.map(function (r) { return num(r.Amount); }), backgroundColor: pm.map(function (r, i) { return PALETTE[i % PALETTE.length]; }), borderWidth: 2, borderColor: '#fff' }]
            },
            options: {
                cutout: '62%',
                plugins: {
                    legend: { position: 'right' },
                    tooltip: { callbacks: { label: function (c) {
                        var total = c.dataset.data.reduce(function (a, b) { return a + b; }, 0);
                        return ' ' + c.label + ': ' + fMoney(c.parsed) + ' (' + (total ? (c.parsed * 100 / total).toFixed(1) : 0) + '%)';
                    } } }
                }
            }
        });

        // 5. Top 12 areas (horizontal)
        var ar = (d.areas || []).slice(0, 12);
        makeChart('chArea', {
            type: 'bar',
            data: {
                labels: ar.map(function (r) { return r.Area || r.AreaCode || '(blank)'; }),
                datasets: [
                    { label: 'Sales', data: ar.map(function (r) { return num(r.SalesAmt); }), backgroundColor: COLORS.sales, borderRadius: 4 },
                    { label: 'Received', data: ar.map(function (r) { return num(r.ReceiptAmt); }), backgroundColor: COLORS.receipt, borderRadius: 4 }
                ]
            },
            options: {
                indexAxis: 'y',
                interaction: { mode: 'index', intersect: false },
                plugins: { tooltip: { callbacks: { label: function (c) { return ' ' + c.dataset.label + ': ' + fMoney(c.parsed.x); } } } },
                scales: { y: { grid: { display: false } }, x: moneyAxis() }
            }
        });
    }

    // ------------------------------------------------------------ tables
    function typeBadge(v) { return '<span class="badge-type badge-' + esc(v) + '">' + esc(v) + '</span>'; }

    var TABLES = {
        areas: {
            source: 'areas', file: 'area-summary', sortKey: 'SalesAmt', sortDir: -1,
            cols: [
                { k: 'AreaCode', l: 'Code' }, { k: 'Area', l: 'Area' },
                { k: 'DMCount', l: 'DMs', t: 'int' }, { k: 'Chicks', l: 'Chicks', t: 'int' },
                { k: 'Mortality', l: 'Mortality', t: 'int' }, { k: 'NetChicks', l: 'Net chicks', t: 'int' },
                { k: 'SalesAmt', l: 'Sales', t: 'money' }, { k: 'ReceiptCount', l: 'Receipts', t: 'int' },
                { k: 'ReceiptAmt', l: 'Received', t: 'money' }, { k: 'Outstanding', l: 'Outstanding', t: 'due' },
                { k: 'CollectionPct', l: 'Collected', t: 'pct', noTotal: true }
            ]
        },
        customers: {
            source: 'customers', file: 'customer-outstanding', sortKey: 'Outstanding', sortDir: -1,
            cols: [
                { k: 'Code', l: 'Code' }, { k: 'CName', l: 'Customer' }, { k: 'Area', l: 'Area' },
                { k: 'NetChicks', l: 'Net chicks', t: 'int' }, { k: 'SalesAmt', l: 'Sales', t: 'money' },
                { k: 'ReceiptAmt', l: 'Received', t: 'money' }, { k: 'Outstanding', l: 'Outstanding', t: 'due' },
                { k: 'LastDMDate', l: 'Last DM', t: 'date' }, { k: 'LastReceiptDate', l: 'Last payment', t: 'date' }
            ]
        },
        receipts: {
            source: 'receipts', file: 'payment-receipts', sortKey: 'TrDate', sortDir: -1,
            cols: [
                { k: 'TRNo', l: 'TR No' }, { k: 'TrDate', l: 'Date', t: 'date' },
                { k: 'Code', l: 'Code' }, { k: 'CName', l: 'Customer' }, { k: 'Area', l: 'Area' },
                { k: 'ChickType', l: 'Type', t: 'type' }, { k: 'PayMode', l: 'Mode' }, { k: 'PayType', l: 'Pay type' },
                { k: 'DD_No', l: 'DD / Ref no' }, { k: 'Bank_det', l: 'Bank' },
                { k: 'Amount', l: 'Amount', t: 'money' }, { k: 'IsAuth', l: 'Status', t: 'auth' }
            ]
        },
        dms: {
            source: 'dms', file: 'dispatch-memos', sortKey: 'DMDate', sortDir: -1,
            cols: [
                { k: 'DMNo', l: 'DM No' }, { k: 'DMDate', l: 'Date', t: 'date' },
                { k: 'Code', l: 'Code' }, { k: 'CName', l: 'Customer' }, { k: 'Area', l: 'Area' },
                { k: 'ChickType', l: 'Type', t: 'type' }, { k: 'Chicks', l: 'Chicks', t: 'int' },
                { k: 'Mortality', l: 'Mortality', t: 'int' }, { k: 'NetChicks', l: 'Net', t: 'int' },
                { k: 'Rate', l: 'Rate', t: 'money', noTotal: true }, { k: 'Amount', l: 'Amount', t: 'money' },
                { k: 'Hatchries', l: 'Hatchery' }
            ]
        }
    };
    var NUMERIC = { int: 1, money: 1, due: 1, pct: 1 };

    function tableRows() {
        var T = TABLES[currentTable];
        var rows = (lastData && lastData[T.source]) || [];
        var q = ($('#txtSearch').val() || '').trim().toLowerCase();
        if (q) {
            rows = rows.filter(function (r) {
                return T.cols.some(function (c) { return String(r[c.k] == null ? '' : r[c.k]).toLowerCase().indexOf(q) >= 0; });
            });
        }
        var col = T.cols.filter(function (c) { return c.k === T.sortKey; })[0];
        var isNum = col && (NUMERIC[col.t] || col.t === 'auth');
        return rows.slice().sort(function (a, b) {
            var x = a[T.sortKey], y = b[T.sortKey];
            if (isNum) return (num(x) - num(y)) * T.sortDir;
            return String(x == null ? '' : x).localeCompare(String(y == null ? '' : y), 'en', { numeric: true }) * T.sortDir;
        });
    }

    function cellHtml(c, v) {
        switch (c.t) {
            case 'int': return fInt(v);
            case 'money': return nf2.format(num(v));
            case 'due': return '<span class="' + dueClass(v) + '">' + nf2.format(num(v)) + '</span>';
            case 'pct': return fPct(v);
            case 'date': return fDate(v);
            case 'type': return typeBadge(v);
            case 'auth': return num(v) === 1 ? '<span class="badge text-bg-success">Authorised</span>' : '<span class="badge text-bg-warning">Pending</span>';
            default: return esc(v);
        }
    }

    function renderTable() {
        var T = TABLES[currentTable];
        var all = (lastData && lastData[T.source]) || [];
        var rows = tableRows();

        var head = '<tr>' + T.cols.map(function (c) {
            var sorted = c.k === T.sortKey;
            var icon = sorted ? (T.sortDir > 0 ? 'bi-sort-up' : 'bi-sort-down') : 'bi-arrow-down-up';
            return '<th data-key="' + c.k + '" class="' + (NUMERIC[c.t] ? 'num ' : '') + (sorted ? 'sorted' : '') + '">' +
                esc(c.l) + '<i class="bi ' + icon + ' si"></i></th>';
        }).join('') + '</tr>';

        var body = rows.length ? rows.map(function (r) {
            return '<tr>' + T.cols.map(function (c) {
                return '<td class="' + (NUMERIC[c.t] ? 'num' : '') + '">' + cellHtml(c, r[c.k]) + '</td>';
            }).join('') + '</tr>';
        }).join('') : '<tr><td colspan="' + T.cols.length + '" class="text-center text-muted py-4">No records</td></tr>';

        var foot = '';
        if (rows.length) {
            foot = '<tr>' + T.cols.map(function (c, i) {
                if (i === 0) return '<td>Total</td>';
                if (!NUMERIC[c.t] || c.noTotal) return '<td></td>';
                var s = rows.reduce(function (a, r) { return a + num(r[c.k]); }, 0);
                return '<td class="num">' + (c.t === 'int' ? fInt(s) : cellHtml(c, s)) + '</td>';
            }).join('') + '</tr>';
        }

        $('#tblData thead').html(head);
        $('#tblData tbody').html(body);
        $('#tblData tfoot').html(foot);
        $('#lblRows').text('Showing ' + fInt(rows.length) + ' of ' + fInt(all.length) + ' rows' +
            ((currentTable === 'receipts' || currentTable === 'dms') ? ' (latest 300 for the filters)' : ''));
    }

    function exportCsv() {
        var T = TABLES[currentTable];
        var rows = tableRows();
        var q = function (v) { v = v == null ? '' : String(v); return /[",\n]/.test(v) ? '"' + v.replace(/"/g, '""') + '"' : v; };
        var lines = [T.cols.map(function (c) { return q(c.l); }).join(',')];
        rows.forEach(function (r) {
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
        a.download = T.file + '_' + (state.session || 'all').replace(/[^\w-]/g, '') + '.csv';
        document.body.appendChild(a);
        a.click();
        setTimeout(function () { URL.revokeObjectURL(a.href); a.remove(); }, 500);
    }

    // ------------------------------------------------------------ events
    $(function () {
        $('#ddlSession').on('change', function () {
            loadFilters($(this).val(), false).done(loadDashboard);
        });
        $('#ddlArea, #txtFrom, #txtTo').on('change', loadDashboard);
        $('input[name=chickType]').on('change', loadDashboard);
        $('#btnRefresh').on('click', loadDashboard);

        $('#btnReset').on('click', function () {
            $('#ddlArea').val('');
            $('#ctAll').prop('checked', true);
            $('#txtFrom, #txtTo').val('');
            loadDashboard();
        });

        $('.detail-tabs').on('click', '.nav-link', function () {
            $('.detail-tabs .nav-link').removeClass('active');
            $(this).addClass('active');
            currentTable = $(this).data('table');
            $('#txtSearch').val('');
            renderTable();
        });

        $('#tblData').on('click', 'thead th', function () {
            var T = TABLES[currentTable], key = $(this).data('key');
            if (T.sortKey === key) T.sortDir *= -1;
            else { T.sortKey = key; T.sortDir = -1; }
            renderTable();
        });

        var searchTimer;
        $('#txtSearch').on('input', function () {
            clearTimeout(searchTimer);
            searchTimer = setTimeout(renderTable, 200);
        });
        $('#btnExport').on('click', exportCsv);

        // collapse filters by default on small phones
        if (window.matchMedia('(max-width: 575.98px)').matches) $('#filterBody').removeClass('show');

        loadFilters(null, true).done(loadDashboard);
    });
})(jQuery);
