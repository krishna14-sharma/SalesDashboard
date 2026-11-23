/* ===== Chick type-wise outstanding - client script ===== */
(function ($) {
    'use strict';

    var cfg = window.CT_CONFIG || { pageUrl: 'ChickTypes.aspx' };
    var PAGE = 50;
    var TYPES = [
        { p: 'Br', name: 'Broiler', color: '#e09a1a' },
        { p: 'Ly', name: 'Layer', color: '#2a9d8f' },
        { p: 'Ck', name: 'Cockrel', color: '#c2553d' },
        { p: 'Ot', name: 'Other', label: 'Opening & other', color: '#8d99ae' }
    ];
    var BUCKETS = [
        { key: 'B0', short: '0–30', color: '#2e8b57', cls: 'b0' }, { key: 'B1', short: '31–60', color: '#8fae2f', cls: 'b1' },
        { key: 'B2', short: '61–90', color: '#e09a1a', cls: 'b2' }, { key: 'B3', short: '91–180', color: '#e0662b', cls: 'b3' },
        { key: 'B4', short: '180+', color: '#b0302a', cls: 'b4' }
    ];
    var STALE_DAYS = 60;      // last hatch older than this is highlighted
    function lbl(t) { return t.label || t.name; }

    var today = '', data = null, shown = [];
    var view = { show: 'due', type: '', sortKey: 'Outstanding', sortDir: -1, limit: PAGE };

    // ------------------------------------------------------------ formatting
    var nfInt = new Intl.NumberFormat('en-IN', { maximumFractionDigits: 0 });
    var nf2 = new Intl.NumberFormat('en-IN', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
    function num(v) { v = Number(v); return isFinite(v) ? v : 0; }
    function fAmt(v) { return nf2.format(num(v)); }
    function fShort(v) {
        v = num(v); var a = Math.abs(v);
        if (a >= 1e7) return '₹' + (v / 1e7).toFixed(2) + ' Cr';
        if (a >= 1e5) return '₹' + (v / 1e5).toFixed(2) + ' L';
        return '₹' + nfInt.format(v);
    }
    function dmy(s) { if (!s) return ''; var p = String(s).split('-'); return p.length === 3 ? p[2] + '-' + p[1] + '-' + p[0] : s; }
    function esc(s) {
        return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) {
            return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
        });
    }
    function daysBetween(a, b) {
        if (!a || !b) return null;
        var pa = String(a).split('-'), pb = String(b).split('-');
        return Math.round((Date.UTC(+pb[0], +pb[1] - 1, +pb[2]) - Date.UTC(+pa[0], +pa[1] - 1, +pa[2])) / 864e5);
    }
    function bucketOf(d) { d = num(d); return d <= 30 ? 0 : d <= 60 ? 1 : d <= 90 ? 2 : d <= 180 ? 3 : 4; }
    function ageBadge(d) { var b = BUCKETS[bucketOf(d)]; return '<span class="age-badge" style="background:' + b.color + '">' + nfInt.format(num(d)) + ' d</span>'; }
    function lastSupply(date) {
        if (!date) return '<span class="na">–</span>';
        var ago = daysBetween(date, asOf());
        return '<div class="ls"><span class="d">' + dmy(date) + '</span><span class="ago' + (ago > STALE_DAYS ? ' stale' : '') + '">' +
            (ago === 0 ? 'today' : nfInt.format(ago) + ' days ago') + '</span></div>';
    }
    function asOf() { return $('#txtAsOf').val() || today; }

    // ------------------------------------------------------------ AJAX
    function callApi(method, payload) {
        return $.ajax({
            type: 'POST', url: cfg.pageUrl + '/' + method, data: JSON.stringify(payload || {}),
            contentType: 'application/json; charset=utf-8', dataType: 'json', timeout: 200000
        }).then(function (resp) {
            var r = resp && resp.d;
            if (!r || !r.ok) return $.Deferred().reject(r && r.error ? r.error : 'Unexpected server response.').promise();
            return r.data;
        }, function (xhr, status) {
            if (xhr.status === 401 || xhr.status === 403 || status === 'parsererror') {
                window.location.href = 'Login.aspx?ReturnUrl=' + encodeURIComponent(window.location.pathname + window.location.search);
                return $.Deferred().promise();
            }
            return $.Deferred().reject(status === 'timeout' ? 'The server took too long to respond.' : 'Server error (' + (xhr.status || 'network') + ').').promise();
        });
    }
    var busy = 0;
    function loading(on) { busy = Math.max(0, busy + (on ? 1 : -1)); $('#loader').toggleClass('show', busy > 0); $('#btnRefresh').toggleClass('spinning', busy > 0); }
    function filters() {
        return { station: $('#ddlStation').val() || null, asOf: asOf() };
    }

    // ------------------------------------------------------------ load
    function loadSummary() {
        $('#alertBox').addClass('d-none');
        loading(true);
        callApi('GetSummary', filters())
            .done(function (d) { data = d; $('#lblUpdated').text((d.generatedAt || '').split(' ')[1] || ''); render(); })
            .fail(function (m) { $('#alertBox').text(m).removeClass('d-none'); })
            .always(function () { loading(false); });
    }

    function present() {     // chick types that appear in the data, in fixed order
        var have = {};
        (data.types || []).forEach(function (t) { have[t.ChickType] = t; });
        return TYPES.filter(function (t) { return have[t.name] && (t.p !== 'Ot' || num(have[t.name].Supplied)); })
            .map(function (t) { return $.extend({ row: have[t.name] }, t); });
    }

    function render() {
        renderCards();
        renderTable();
    }

    function renderCards() {
        var ts = present();
        var col = ts.length >= 4 ? 'col-xl-3' : 'col-xl-4';
        $('#typeCards').html(ts.map(function (t) {
            var r = t.row, os = num(r.Outstanding);
            var tot = BUCKETS.reduce(function (s, b) { return s + Math.max(0, num(r[b.key])); }, 0);
            var over90 = num(r.B3) + num(r.B4);
            return '<div class="col-12 col-sm-6 ' + col + '"><button type="button" class="tcard' + (view.type === t.p ? ' active' : '') + '" data-p="' + t.p + '" style="--tc:' + t.color + '">' +
                '<div class="tname"><span class="dot"></span>' + esc(lbl(t)) + '</div>' +
                '<div class="tdue' + (os > 0 ? '' : ' zero') + '" title="' + fAmt(os) + '">' + fShort(os) + '</div>' +
                '<div class="tsub">outstanding from <b>' + nfInt.format(num(r.WithDue)) + '</b> of ' + nfInt.format(num(r.Customers)) + ' customers</div>' +
                '<div class="age-strip">' + BUCKETS.map(function (b) {
                    return '<span class="' + b.cls + '-bg" style="width:' + (tot ? Math.max(0, num(r[b.key])) * 100 / tot : 0).toFixed(1) + '%" title="' + b.short + ' days: ' + fAmt(r[b.key]) + '"></span>';
                }).join('') + '</div>' +
                '<div class="tgrid">' +
                '<span>Over 90 days<b>' + fShort(over90) + '</b></span>' +
                '<span>' + (t.p === 'Ot' ? 'Last entry' : 'Last hatch') + '<b>' + (r.LastSupply ? dmy(r.LastSupply) : '–') + '</b></span>' +
                '<span>' + (t.p === 'Ot' ? 'Debits' : 'Billed') + '<b>' + fShort(r.Supplied) + '</b></span>' +
                (t.p === 'Ot' ? '<span>Not linked to a chick bill<b>&nbsp;</b></span>' : '<span>Chicks billed<b>' + nfInt.format(num(r.Chicks)) + '</b></span>') +
                '</div></button></div>';
        }).join(''));

        var n = data.notes || {}, notes = [];
        notes.push('Outstanding is the accounts ledger balance (' + (n.LedgerFrom ? dmy(n.LedgerFrom) + ' to ' + dmy(n.LedgerTo) : 'ledger') + '). ' +
            'Receipts are adjusted against the oldest bills first; chick bills are aged from their hatch date.');
        if (num(n.OtherDues) > 0) notes.push(fShort(n.OtherDues) + ' is due on ledger debits that are not chick bills (opening balance, journals).');
        if (num(n.Advance) > 0) notes.push(fShort(n.Advance) + ' is held as advance.');
        $('#typeNote').text(notes.join(' '));

        // only offer the types that exist
        $('#ddlType option').each(function () {
            var v = $(this).val();
            $(this).prop('hidden', !!v && !ts.some(function (t) { return t.p === v; }));
        });
    }

    // ------------------------------------------------------------ customer table
    function cols() {
        var c = [{ k: 'CName', l: 'Customer', t: 'text' }];
        present().forEach(function (t) {
            c.push({ k: t.p + 'Last', l: t.p === 'Ot' ? 'Last entry' : 'Last hatch', t: 'date', grp: t, first: true });
            c.push({ k: t.p + 'OS', l: 'Due', t: 'num', grp: t });
            c.push({ k: t.p + 'Days', l: 'Oldest', t: 'num', grp: t });
        });
        c.push({ k: 'Outstanding', l: 'Total due', t: 'num', sep: true });
        c.push({ k: 'LastPayDate', l: 'Last receipt', t: 'date' });
        return c;
    }

    function rows() {
        var q = ($('#txtSearch').val() || '').trim().toLowerCase();
        var r = (data && data.customers || []).filter(function (c) {
            if (view.type) {
                if (!(num(c[view.type + 'Supplied']) > 0 || c[view.type + 'Last'])) return false;
                if (view.show === 'due' && !(num(c[view.type + 'OS']) > 0)) return false;
            } else if (view.show === 'due' && !(num(c.Outstanding) > 0)) return false;
            if (q && ((c.CName || '') + ' ' + (c.Code || '') + ' ' + (c.Area || '')).toLowerCase().indexOf(q) < 0) return false;
            return true;
        });
        var key = view.sortKey, dir = view.sortDir;
        var col = cols().filter(function (c) { return c.k === key; })[0] || { t: 'num' };
        return r.sort(function (a, b) {
            if (col.t === 'num') return (num(a[key]) - num(b[key])) * dir;
            return String(a[key] || '').localeCompare(String(b[key] || ''), 'en', { numeric: true }) * dir;
        });
    }

    function cellFor(c, r) {
        if (c.k === 'CName') return '<td><div class="cust-name">' + esc(r.CName || '(no name)') + '</div><div class="cust-sub">' + esc(r.Code) + (r.Area ? ' · ' + esc(r.Area) : '') + '</div></td>';
        if (c.k === 'LastPayDate') return '<td>' + (r.LastPayDate ? dmy(r.LastPayDate) + '<div class="cust-sub">' + fShort(r.LastPayAmt) + '</div>' : '<span class="text-muted small">No receipt</span>') + '</td>';
        if (c.k === 'Outstanding') return '<td class="num os sep">' + (num(r.Outstanding) > 0 ? '<span class="text-due">' + fAmt(r.Outstanding) + '</span>'
            : num(r.Advance) > 0 ? '<span class="text-adv">Adv ' + fAmt(r.Advance) + '</span>' : '<span class="na">0.00</span>') + '</td>';
        var p = c.grp.p;
        var bought = num(r[p + 'Supplied']) > 0 || r[p + 'Last'];
        if (c.t === 'date') return '<td class="sep">' + (bought ? lastSupply(r[p + 'Last']) : '<span class="na">' + (p === 'Ot' ? '–' : 'not bought') + '</span>') + '</td>';
        if (c.k === p + 'OS') return '<td class="num">' + (!bought ? '' : num(r[p + 'OS']) > 0 ? '<b class="text-due">' + fAmt(r[p + 'OS']) + '</b>' : '<span class="na">nil</span>') + '</td>';
        return '<td class="num">' + (num(r[p + 'OS']) > 0 && r[p + 'Days'] != null ? ageBadge(r[p + 'Days']) : '') + '</td>';
    }

    function renderTable() {
        if (!data) return;
        var C = cols(), all = rows(); shown = all.slice(0, view.limit);
        var ts = present();
        var grpRow = '<tr class="grp"><th class="blank"></th>' + ts.map(function (t) { return '<th colspan="3" class="g-' + t.p + '">' + esc(lbl(t)).toUpperCase() + '</th>'; }).join('') + '<th colspan="2" class="blank"></th></tr>';
        var colRow = '<tr class="cols">' + C.map(function (c) {
            var sorted = c.k === view.sortKey, icon = sorted ? (view.sortDir > 0 ? 'bi-sort-up' : 'bi-sort-down') : 'bi-arrow-down-up';
            return '<th data-key="' + c.k + '" class="' + (c.t === 'num' ? 'num ' : '') + (c.first || c.sep ? 'sep ' : '') + (sorted ? 'sorted' : '') + '">' + esc(c.l) + '<i class="bi ' + icon + ' si"></i></th>';
        }).join('') + '</tr>';
        $('#tblCust thead').html(grpRow + colRow);
        $('#tblCust tbody').html(shown.length ? shown.map(function (r) {
            return '<tr data-cust="' + esc(r.CustKey) + '">' + C.map(function (c) { return cellFor(c, r); }).join('') + '</tr>';
        }).join('') : '<tr><td colspan="' + C.length + '" class="text-center text-muted py-4">No customers match</td></tr>');
        var sum = function (k) { return all.reduce(function (s, r) { return s + num(r[k]); }, 0); };
        $('#tblCust tfoot').html(all.length ? '<tr><td>Total (' + nfInt.format(all.length) + ')</td>' + ts.map(function (t) {
            return '<td class="sep"></td><td class="num">' + fAmt(sum(t.p + 'OS')) + '</td><td></td>';
        }).join('') + '<td class="num sep">' + fAmt(sum('Outstanding')) + '</td><td></td></tr>' : '');

        // phone cards
        $('#custCards').html(shown.length ? shown.map(function (r) {
            return '<div class="ct-card" data-cust="' + esc(r.CustKey) + '" role="button" tabindex="0">' +
                '<div class="top"><div class="min-w-0"><div class="cust-name">' + esc(r.CName || '(no name)') + '</div><div class="cust-sub">' + esc(r.Code) + (r.Area ? ' · ' + esc(r.Area) : '') + '</div></div>' +
                '<div class="tot">' + (num(r.Outstanding) > 0 ? '<span class="text-due">' + fShort(r.Outstanding) + '</span>' : num(r.Advance) > 0 ? '<span class="text-adv">Adv ' + fShort(r.Advance) + '</span>' : '<span class="text-muted">₹0</span>') + '</div></div>' +
                ts.filter(function (t) { return num(r[t.p + 'Supplied']) > 0 || r[t.p + 'Last']; }).map(function (t) {
                    var ago = daysBetween(r[t.p + 'Last'], asOf());
                    return '<div class="trow"><span class="tn"><i style="background:' + t.color + '"></i>' + esc(t.p === 'Ot' ? 'Other' : t.name) + '</span>' +
                        '<span>' + dmy(r[t.p + 'Last']) + ' <span class="text-muted">· ' + ago + ' d ago</span></span>' +
                        '<span class="due' + (num(r[t.p + 'OS']) > 0 ? '' : ' zero') + '">' + (num(r[t.p + 'OS']) > 0 ? fShort(r[t.p + 'OS']) + ' ' + ageBadge(r[t.p + 'Days']) : 'nil') + '</span></div>';
                }).join('') + '</div>';
        }).join('') : '<div class="text-center text-muted py-4">No customers match</div>');

        $('#lblRows').text('Showing ' + nfInt.format(shown.length) + ' of ' + nfInt.format(all.length) + ' customers · last hatch older than ' + STALE_DAYS + ' days is shown in brown');
        $('#btnMore').toggleClass('d-none', shown.length >= all.length);
        $('.tcard').each(function () { $(this).toggleClass('active', $(this).data('p') === view.type); });
    }

    function exportCsv() {
        if (!data) return;
        var ts = present();
        var head = ['Code', 'Customer', 'Area'];
        ts.forEach(function (t) { head.push(lbl(t) + (t.p === 'Ot' ? ' last entry' : ' last hatch'), lbl(t) + ' last bill', lbl(t) + ' due', lbl(t) + ' oldest due (days)'); });
        head.push('Total due', 'Advance', 'Ledger balance', 'Last receipt', 'Last receipt amount');
        var lines = [head].concat(rows().map(function (r) {
            var a = [r.Code, r.CName, r.Area];
            ts.forEach(function (t) { a.push(dmy(r[t.p + 'Last']), dmy(r[t.p + 'Bill']), r[t.p + 'OS'], num(r[t.p + 'OS']) > 0 ? r[t.p + 'Days'] : ''); });
            a.push(r.Outstanding, r.Advance, r.Balance, dmy(r.LastPayDate), r.LastPayAmt);
            return a;
        }));
        var q = function (v) { v = v == null ? '' : String(v); return /[",\n]/.test(v) ? '"' + v.replace(/"/g, '""') + '"' : v; };
        var blob = new Blob(['﻿' + lines.map(function (l) { return l.map(q).join(','); }).join('\r\n')], { type: 'text/csv;charset=utf-8' });
        var a = document.createElement('a');
        a.href = URL.createObjectURL(blob); a.download = 'chick-type-outstanding_' + asOf() + '.csv';
        document.body.appendChild(a); a.click(); setTimeout(function () { URL.revokeObjectURL(a.href); a.remove(); }, 500);
    }

    // ------------------------------------------------------------ customer detail
    function openCustomer(key) {
        var c = (data.customers || []).filter(function (x) { return x.CustKey === key; })[0] || { CName: key };
        $('#custName').text(c.CName || c.Code || key);
        $('#custMeta').text([c.Code, c.Area, 'as on ' + dmy(asOf())].filter(Boolean).join(' · '));
        $('#custBody').html('<div class="text-center text-muted py-4"><div class="spinner-border spinner-border-sm me-2"></div>Loading bills…</div>');
        bootstrap.Modal.getOrCreateInstance(document.getElementById('custModal')).show();
        callApi('GetCustomer', { custKey: key, asOf: asOf() })
            .done(function (d) { renderCustomer(c, d); })
            .fail(function (m) { $('#custBody').html('<div class="alert alert-danger">' + esc(m) + '</div>'); });
    }

    function renderCustomer(c, d) {
        var bills = d.bills || [], credits = d.credits || [], bal = d.balance || {};
        var showAll = false;
        function mini(t, v, cls, sub) { return '<div class="mini-kpi"><div class="t">' + t + '</div><div class="v ' + (cls || '') + '">' + v + '</div>' + (sub ? '<div class="small text-muted">' + sub + '</div>' : '') + '</div>'; }
        function body() {
            var balance = num(bal.Debits) - num(bal.Credits);
            var html = '<div class="ct-mini">' +
                mini('Ledger balance', balance >= 0 ? fShort(balance) : 'Adv ' + fShort(-balance), balance > 0 ? 'text-due' : 'text-adv',
                     'debits ' + fShort(bal.Debits) + ' · credits ' + fShort(bal.Credits)) +
                TYPES.filter(function (t) { return bills.some(function (x) { return x.ChickType === t.name; }); }).map(function (t) {
                    var s = bills.filter(function (x) { return x.ChickType === t.name; });
                    var due = s.reduce(function (a, x) { return a + Math.max(0, num(x.Outstanding)); }, 0);
                    var last = s.reduce(function (a, x) { var v = t.p === 'Ot' ? x.VouDate : x.HatchDate; return String(v || '') > a ? v : a; }, '');
                    var lastC = t.p === 'Ot' ? '' : c[t.p + 'Last'];
                    return mini(esc(lbl(t)) + ' due', fShort(due), due > 0 ? 'text-due' : '', (t.p === 'Ot' ? 'last entry ' : 'last hatch ') + dmy(lastC || last));
                }).join('') + '</div>';
            html += '<div class="form-check form-switch mb-2"><input class="form-check-input" type="checkbox" id="chkAllSup"' + (showAll ? ' checked' : '') + '>' +
                '<label class="form-check-label small" for="chkAllSup">Show paid bills too</label></div>';

            TYPES.forEach(function (t) {
                var s = bills.filter(function (x) { return x.ChickType === t.name; });
                if (!s.length) return;
                var list = s.filter(function (x) { return showAll || num(x.Outstanding) > 0; });
                var due = s.reduce(function (a, x) { return a + Math.max(0, num(x.Outstanding)); }, 0);
                var head = '<div class="tsec" style="--tc:' + t.color + '"><div class="tsec-head"><h3>' + esc(lbl(t)) + '</h3>';
                if (t.p !== 'Ot') {
                    var lastH = c[t.p + 'Last'] || s.reduce(function (a, x) { return String(x.HatchDate || '') > a ? x.HatchDate : a; }, '');
                    head += '<span>Last hatch <b>' + dmy(lastH) + '</b>' + (lastH ? ' (' + daysBetween(lastH, asOf()) + ' days ago)' : '') + '</span>';
                }
                head += '<span>Due <b class="' + (due > 0 ? 'due' : '') + '">' + fAmt(due) + '</b></span></div>';
                html += head;
                if (!list.length) html += '<div class="px-3 pb-3 small text-muted">Nothing unpaid.</div>';
                else if (t.p !== 'Ot') {
                    html += '<div class="table-responsive"><table class="table table-sm align-middle"><thead><tr><th>Bill no</th><th>Voucher</th><th>Hatch date</th><th>Bill date</th>' +
                        '<th class="num">Chicks</th><th class="num">Free</th><th class="num">Mortality</th><th class="num">Rate</th><th class="num">Amount</th><th class="num">Discount</th>' +
                        '<th class="num">Bill value</th><th class="num">Paid</th><th class="num">Outstanding</th><th>Age</th></tr></thead><tbody>' +
                        list.map(function (x) {
                            var open = num(x.Outstanding) > 0;
                            return '<tr class="' + (open ? '' : 'paid') + '"><td>' + esc(x.BillNo) + '</td><td>' + esc(x.Vou_type) + ' ' + esc(x.Vou_no) + '</td>' +
                                '<td>' + dmy(x.HatchDate) + '</td><td>' + dmy(x.BillDate) + '</td>' +
                                '<td class="num">' + nfInt.format(num(x.Qty)) + '</td><td class="num">' + nfInt.format(num(x.FreeQty)) + '</td><td class="num">' + nfInt.format(num(x.Mortality)) + '</td>' +
                                '<td class="num">' + fAmt(x.Rate) + '</td><td class="num">' + fAmt(x.Gross) + '</td><td class="num">' + fAmt(x.Discount) + '</td>' +
                                '<td class="num">' + fAmt(x.Amount) + '</td><td class="num">' + fAmt(x.Adjusted) + '</td>' +
                                '<td class="num">' + (open ? '<b class="text-due">' + fAmt(x.Outstanding) + '</b>' : '<span class="badge text-bg-success">Paid</span>') + '</td>' +
                                '<td>' + (open ? ageBadge(x.Days) : '') + '</td></tr>';
                        }).join('') + '</tbody></table></div>';
                } else {
                    html += '<div class="table-responsive"><table class="table table-sm align-middle"><thead><tr><th>Date</th><th>Voucher</th><th>Narration</th>' +
                        '<th class="num">Debit</th><th class="num">Paid</th><th class="num">Outstanding</th><th>Age</th></tr></thead><tbody>' +
                        list.map(function (x) {
                            var open = num(x.Outstanding) > 0;
                            return '<tr class="' + (open ? '' : 'paid') + '"><td>' + dmy(x.VouDate) + '</td><td>' + esc(x.Vou_type) + ' ' + esc(x.Vou_no) + '</td>' +
                                '<td class="narr">' + esc(x.Narration) + '</td><td class="num">' + fAmt(x.Amount) + '</td><td class="num">' + fAmt(x.Adjusted) + '</td>' +
                                '<td class="num">' + (open ? '<b class="text-due">' + fAmt(x.Outstanding) + '</b>' : '<span class="badge text-bg-success">Paid</span>') + '</td>' +
                                '<td>' + (open ? ageBadge(x.Days) : '') + '</td></tr>';
                        }).join('') + '</tbody></table></div>';
                }
                html += '</div>';
            });

            html += '<div class="tsec" style="--tc:#34568b"><div class="tsec-head"><h3>Receipts &amp; credits</h3><span><b>' + credits.length + '</b> entries · <b>' +
                fAmt(credits.reduce(function (a, p) { return a + num(p.Amount); }, 0)) + '</b></span></div>' +
                (credits.length ? '<div class="table-responsive"><table class="table table-sm align-middle"><thead><tr><th>Date</th><th>Voucher</th><th>Mode</th><th>Cheque no</th><th>Narration</th><th class="num">Amount</th></tr></thead><tbody>' +
                    credits.map(function (p) {
                        return '<tr><td>' + dmy(p.VouDate) + '</td><td>' + esc(p.Vou_type) + ' ' + esc(p.Vou_no) + '</td><td>' + esc(p.PayMode) + '</td><td>' + esc(p.ChequeNo) + '</td>' +
                            '<td class="narr">' + esc(p.Narration) + '</td><td class="num">' + fAmt(p.Amount) + '</td></tr>';
                    }).join('') + '</tbody></table></div>' : '<div class="px-3 pb-3 small text-muted">No receipts or credits in the ledger.</div>') + '</div>';
            $('#custBody').html(html);
            $('#chkAllSup').on('change', function () { showAll = this.checked; body(); });
        }
        body();
    }

    // ------------------------------------------------------------ events
    $(function () {
        $('#ddlStation, #txtAsOf').on('change', function () { view.limit = PAGE; loadSummary(); });
        $('#btnRefresh').on('click', loadSummary);
        $('#btnReset').on('click', function () {
            $('#ddlStation, #ddlType').val(''); $('#txtAsOf').val(today); $('#txtSearch').val('');
            view = { show: 'due', type: '', sortKey: 'Outstanding', sortDir: -1, limit: PAGE }; $('#shDue').prop('checked', true);
            loadSummary();
        });
        $('#typeCards').on('click', '.tcard', function () {
            var p = $(this).data('p');
            view.type = view.type === p ? '' : p;
            view.sortKey = view.type ? view.type + 'OS' : 'Outstanding'; view.sortDir = -1; view.limit = PAGE;
            $('#ddlType').val(view.type);
            renderTable();
        });
        $('#ddlType').on('change', function () {
            view.type = $(this).val(); view.sortKey = view.type ? view.type + 'OS' : 'Outstanding'; view.sortDir = -1; view.limit = PAGE; renderTable();
        });
        $('input[name=show]').on('change', function () { view.show = $(this).val(); view.limit = PAGE; renderTable(); });
        var t; $('#txtSearch').on('input', function () { clearTimeout(t); t = setTimeout(function () { view.limit = PAGE; renderTable(); }, 200); });
        $('#tblCust').on('click', 'thead tr.cols th', function () {
            var k = $(this).data('key');
            if (view.sortKey === k) view.sortDir *= -1; else { view.sortKey = k; view.sortDir = k === 'CName' ? 1 : -1; }
            renderTable();
        });
        $('#tblCust').on('click', 'tbody tr[data-cust]', function () { openCustomer($(this).attr('data-cust')); });
        $('#custCards').on('click keydown', '.ct-card', function (e) { if (e.type === 'keydown' && e.key !== 'Enter') return; openCustomer($(this).attr('data-cust')); });
        $('#btnMore').on('click', function () { view.limit += PAGE; renderTable(); });
        $('#btnExport').on('click', exportCsv);
        if (window.matchMedia('(max-width: 575.98px)').matches) $('#filterBody').removeClass('show');

        loading(true);
        callApi('GetFilters', {})
            .done(function (f) {
                today = f.today || new Date().toISOString().slice(0, 10);
                (f.stations || []).forEach(function (s) { $('#ddlStation').append($('<option>').val(s).text(s)); });
                if (f.ledgerFrom) $('#ledgerInfo').text('Ledger entries from ' + dmy(f.ledgerFrom) + ' to ' + dmy(f.ledgerTo) + ' (VENTRY).');
                $('#txtAsOf').val(today).attr('max', today);
                loadSummary();
            })
            .fail(function (m) { $('#alertBox').text(m).removeClass('d-none'); })
            .always(function () { loading(false); });
    });
})(jQuery);
