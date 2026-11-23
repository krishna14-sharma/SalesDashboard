/* ===== Feed Sale Review - client script =====
   Loads the review for the chosen period through the page methods in FeedReview.aspx.cs
   and writes each section's headline from the figures, like the printed review. */
(function ($) {
    'use strict';

    var cfg = window.FR_CONFIG || { pageUrl: 'FeedReview.aspx', user: '' };
    var today = new Date();
    var data = null;
    var table = { name: 'customers', sortKey: null, sortDir: -1 };
    var MONTHS = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

    // ------------------------------------------------------------ formatting
    var nfInt = new Intl.NumberFormat('en-IN', { maximumFractionDigits: 0 });
    var nf2 = new Intl.NumberFormat('en-IN', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
    function num(v) { v = Number(v); return isFinite(v) ? v : 0; }
    function esc(s) {
        return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) {
            return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
        });
    }
    function money(v) {                       // ₹19.54 Cr / ₹81.87 L / ₹1,410
        v = num(v); var a = Math.abs(v);
        if (a >= 1e7) return '₹' + (v / 1e7).toFixed(2) + ' Cr';
        if (a >= 1e5) return '₹' + (v / 1e5).toFixed(2) + ' L';
        return '₹' + nfInt.format(Math.round(v));
    }
    function kg(v) {                          // 8.81 L KG / 9,500 KG
        v = num(v);
        if (Math.abs(v) >= 1e5) return (v / 1e5).toFixed(2) + ' L KG';
        return nfInt.format(Math.round(v)) + ' KG';
    }
    function pct(v, d) { return num(v).toFixed(d == null ? 0 : d) + '%'; }
    function iso(d) { return d.getFullYear() + '-' + ('0' + (d.getMonth() + 1)).slice(-2) + '-' + ('0' + d.getDate()).slice(-2); }
    function parse(s) { var p = String(s).slice(0, 10).split('-'); return new Date(+p[0], +p[1] - 1, +p[2]); }
    function longDate(s) { var d = parse(s); return d.getDate() + ' ' + MONTHS[d.getMonth()] + ' ' + d.getFullYear(); }
    function monShort(s) { return MONTHS[parse(s).getMonth()].slice(0, 3); }
    function monName(s) { return MONTHS[parse(s).getMonth()]; }
    function dmy(s) { if (!s) return ''; var p = String(s).split('-'); return p[2] + '-' + p[1] + '-' + p[0]; }
    function who(c) { var n = c.CName || c.Code || '(no name)'; return c.Area ? n + ', ' + c.Area : n; }
    function fyStart(d) { return new Date(d.getMonth() < 3 ? d.getFullYear() - 1 : d.getFullYear(), 3, 1); }
    function fyLabel(d) { var y = fyStart(d).getFullYear(); return 'FY ' + y + '-' + String(y + 1).slice(2); }
    function share(part, whole) { return whole ? part * 100 / whole : 0; }
    function fractionWords(p) {               // 67 -> "two-thirds"
        if (p >= 97) return 'almost all';
        if (p >= 72 && p <= 78) return 'three-quarters';
        if (p >= 63 && p <= 70) return 'two-thirds';
        if (p >= 47 && p <= 53) return 'half';
        if (p >= 31 && p <= 35) return 'a third';
        if (p >= 23 && p <= 27) return 'a quarter';
        return pct(p) ;
    }

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

    // ------------------------------------------------------------ periods
    function presetRange(p) {
        var t = new Date(today.getFullYear(), today.getMonth(), today.getDate()), f;
        switch (p) {
            case 'lastfy': f = fyStart(t); return [new Date(f.getFullYear() - 1, 3, 1), new Date(f.getFullYear(), 2, 31)];
            case 'quarter': { var fs = fyStart(t), q = Math.floor(((t.getMonth() - 3 + 12) % 12) / 3); return [new Date(fs.getFullYear(), 3 + q * 3, 1), t]; }
            case 'last3': return [new Date(t.getFullYear(), t.getMonth() - 2, 1), t];
            case 'month': return [new Date(t.getFullYear(), t.getMonth(), 1), t];
            case 'lastmonth': return [new Date(t.getFullYear(), t.getMonth() - 1, 1), new Date(t.getFullYear(), t.getMonth(), 0)];
            default: return [fyStart(t), t];
        }
    }
    function setPreset(p) {
        var r = presetRange(p);
        $('#txtFrom').val(iso(r[0])); $('#txtTo').val(iso(r[1]));
        markPreset();
        load();
    }
    function markPreset() {
        var f = $('#txtFrom').val(), t = $('#txtTo').val();
        $('#presets button').each(function () {
            var r = presetRange($(this).data('preset'));
            $(this).toggleClass('active', iso(r[0]) === f && iso(r[1]) === t);
        });
    }

    // ------------------------------------------------------------ load
    function load() {
        var f = $('#txtFrom').val(), t = $('#txtTo').val();
        if (!t) return;
        $('#alertBox').addClass('d-none');
        loading(true);
        callApi('GetReview', { fromDate: f, toDate: t, areaCode: $('#ddlArea').val() || null, feedGroup: $('#ddlGroup').val() || null })
            .done(function (d) { data = d; render(); })
            .fail(function (m) { $('#alertBox').text(m).removeClass('d-none'); })
            .always(function () { loading(false); });
    }

    // ------------------------------------------------------------ render
    function render() {
        var k = data.kpi || {};
        var from = k.PeriodFrom, to = k.PeriodTo;
        var groupLbl = $('#ddlGroup').val() ? $('#ddlGroup option:selected').text() + ' feed' : 'feed';
        var areaLbl = $('#ddlArea').val() ? $('#ddlArea option:selected').text() : '';
        var isFY = iso(fyStart(parse(to))) === String(from).slice(0, 10);

        // cover
        $('#coverTitle').html('Feed Sale Review' + (isFY ? '<br>' + fyLabel(parse(to)) : ''));
        $('#coverPeriod').text(longDate(from) + ' to ' + longDate(to) + ' · Month-wise, customer-wise and outstanding' + (areaLbl ? ' · ' + areaLbl : ''));
        $('#coverMeta').text((cfg.user ? 'Prepared by ' + cfg.user + ' · ' : '') + longDate(iso(today)));

        var empty = !num(k.Sales) && !num(k.Outstanding);
        $('#emptyState').toggleClass('d-none', !empty);
        $('#reviewBody').toggleClass('d-none', empty);
        if (empty) return;

        var months = data.monthly || [];
        var partial = partialMonths(months, from, to);
        renderGlance(k, months, groupLbl, from, to, partial);
        renderMonths(months, partial, to);
        renderMix(k, groupLbl);
        renderSalespeople(k);
        renderQty(k, groupLbl);
        renderOutstanding(k, to);
        renderPoints(k, to);
        table.sortKey = null;
        renderTable();
    }

    function partialMonths(months, from, to) {
        var out = {};
        months.forEach(function (m) {
            var ms = parse(m.MonthStart), me = new Date(ms.getFullYear(), ms.getMonth() + 1, 0);
            if (parse(from) > ms || parse(to) < me) out[String(m.MonthStart).slice(0, 10)] = true;
        });
        return out;
    }

    function renderGlance(k, months, groupLbl, from, to, partial) {
        var custs = data.customers || [];
        var top = custs.filter(function (c) { return num(c.Sales) > 0; }).sort(function (a, b) { return num(b.Sales) - num(a.Sales); })[0];
        var best = months.slice().sort(function (a, b) { return num(b.Sales) - num(a.Sales); })[0];
        var sMonth = monShort(from), eMonth = monShort(to);
        $('#glanceKicker').text('At a glance · ' + (sMonth === eMonth && String(from).slice(0, 7) === String(to).slice(0, 7) ? MONTHS[parse(from).getMonth()] + ' ' + parse(from).getFullYear() : sMonth + '–' + eMonth + ' ' + parse(to).getFullYear()));
        $('#glanceTitle').text(money(k.Sales) + ' of ' + groupLbl + ' sold to ' + nfInt.format(num(k.Customers)) + ' customer' + (num(k.Customers) === 1 ? '' : 's'));
        var cards = [
            { v: money(k.Sales), l: 'Total sales value' },
            { v: (num(k.QtyKg) >= 1e5 ? (num(k.QtyKg) / 1e5).toFixed(2) + ' lakh' : nfInt.format(num(k.QtyKg))), l: 'KG sold (' + nfInt.format(num(k.QtyKg) / 1000) + ' MT)' },
            { v: top ? money(top.Sales) : '–', l: top ? 'Top customer: ' + who(top) : 'Top customer' },
            { v: best ? money(best.Sales) : '–', l: best ? 'Best month: ' + monName(best.MonthStart) + ' (' + nfInt.format(num(best.Customers)) + ' customers billed)' : 'Best month' },
            { v: pct(k.Top10QtyShare), l: 'Quantity bought by the top ' + Math.min(10, num(k.Customers)) + ' customers' },
            { v: money(k.Outstanding), l: 'Outstanding from ' + nfInt.format(num(k.CustomersWithDue)) + ' customers (' + pct(share(num(k.Outstanding), num(k.Sales)), 1) + ' of sales)', dark: true }
        ];
        $('#glance').html(cards.map(function (c) {
            return '<div class="g-card' + (c.dark ? ' dark' : '') + '"><div class="g-value">' + esc(c.v) + '</div><div class="g-label">' + esc(c.l) + '</div></div>';
        }).join(''));
        var pm = Object.keys(partial).map(function (m) { return monName(m); });
        $('#glanceNote').text('Source: feed lines of the dispatch memos (AreaDMPoultry) · outstanding as on ' + longDate(to) +
            (pm.length ? ' · ' + pm.join(' and ') + ' ' + (pm.length > 1 ? 'are' : 'is') + ' part of a month' : ''));
    }

    function renderMonths(months, partial, to) {
        if (!months.length) { $('#months').html(''); $('#monthTitle').text('No feed sales in this period'); return; }
        var max = Math.max.apply(null, months.map(function (m) { return num(m.Sales); }).concat([1]));
        var best = months.reduce(function (a, b) { return num(b.Sales) > num(a.Sales) ? b : a; });
        var inCr = max >= 1e7;
        var unit = inCr ? 'Crore' : 'lakh';
        var fmt = function (v) { return (num(v) / (inCr ? 1e7 : 1e5)).toFixed(2); };
        $('#monthTitle').text(months.length === 1 ? monName(best.MonthStart) + ': ' + money(best.Sales) + ' of feed sold'
            : monName(best.MonthStart) + ' was the peak month at ' + money(best.Sales));
        var cols = months.map(function (m) {
            var key = String(m.MonthStart).slice(0, 10), isPeak = m === best && months.length > 1, isPart = !!partial[key];
            var h = Math.max(1, num(m.Sales) * 100 / max);
            return '<div class="m-col' + (isPeak ? ' peak' : '') + (isPart && !isPeak ? ' partial' : '') + '" title="' + esc(monName(m.MonthStart) + ': ' + money(m.Sales) + ', ' + kg(m.QtyKg) + ', ' + m.Customers + ' customers') + '">' +
                '<div class="m-val">' + fmt(m.Sales) + (isPeak ? ' (peak)' : '') + (isPart ? '*' : '') + '</div>' +
                '<div class="m-bar" style="height:' + (h * 0.82).toFixed(1) + '%"></div></div>';
        }).join('');
        var labels = months.map(function (m) {
            var key = String(m.MonthStart).slice(0, 10);
            return '<div class="m-lab"><b>' + monShort(m.MonthStart) + (partial[key] ? '*' : '') + '</b><span>' + kg(m.QtyKg) + '</span></div>';
        }).join('');
        $('#months').html(cols);
        if (!$('#months').next('.m-labels').length) $('#months').after('<div class="m-labels"></div>');
        $('#months').next('.m-labels').html(labels);
        var pm = Object.keys(partial);
        $('#monthNote').text('Sales in ₹ ' + unit + '; quantity below each month' +
            (pm.length ? ' · *' + pm.map(function (m) { return monName(m); }).join(', ') + ' ' + (pm.length > 1 ? 'are' : 'is') + ' part of a month (up to ' + longDate(to).replace(/ \d{4}$/, '') + ')' : ''));
    }

    function renderMix(k, groupLbl) {
        var groups = data.groups || [], total = num(k.Sales);
        var order = ['Broiler', 'Layer', 'Sonali', 'Other'];
        groups.sort(function (a, b) { return order.indexOf(a.Grp) - order.indexOf(b.Grp); });
        var lead = groups.slice().sort(function (a, b) { return num(b.Sales) - num(a.Sales); })[0];
        var brand = { Broiler: 'Broiler (Bronix)', Layer: 'Layer (Laynix)', Sonali: 'Sonali', Other: 'Other feed' };
        $('#mixTitle').text(lead ? (lead.Grp === 'Other' ? 'Other feed' : lead.Grp + ' feed') + ' is ' + fractionWords(share(num(lead.Sales), total)) + ' of sales' : '');
        $('#mixBar').html(groups.map(function (g) {
            return '<span class="c-' + esc(g.Grp) + '" style="width:' + share(num(g.Sales), total).toFixed(2) + '%" title="' + esc(g.Grp + ': ' + money(g.Sales)) + '"></span>';
        }).join(''));
        $('#mixLegend').html(groups.map(function (g) {
            return '<span><b>' + esc(brand[g.Grp] || g.Grp) + '</b> ' + money(g.Sales) + ' · ' + pct(share(num(g.Sales), total), 1) + '</span>';
        }).join(''));
        var prods = data.products || [];
        var top = prods.slice(0, 6), rest = prods.slice(6);
        var restSum = rest.reduce(function (s, p) { return s + num(p.Sales); }, 0);
        var max = Math.max.apply(null, top.map(function (p) { return num(p.Sales); }).concat([restSum, 1]));
        var inCr = max >= 1e7;
        var fmt = function (v) { return (num(v) / (inCr ? 1e7 : 1e5)).toFixed(2); };
        var rows = top.map(function (p) { return { name: p.Product, v: num(p.Sales), cls: 'c-' + p.Grp }; });
        if (restSum > 0) rows.push({ name: 'All other products', v: restSum, cls: 'c-Other' });
        $('#productBars').html(rows.map(function (r) {
            return '<div class="hb"><span class="name" title="' + esc(r.name) + '">' + esc(r.name) + '</span><span class="track"><span class="bar ' + r.cls + '" style="width:' + (r.v * 82 / max).toFixed(1) + '%"></span><span class="val">' + fmt(r.v) + '</span></span></div>';
        }).join(''));
        $('#mixNote').text('₹ ' + (inCr ? 'Crore' : 'lakh') + ' · blue = broiler, orange = layer, navy = sonali, grey = other' + (rest.length ? ' · ' + rest.length + ' smaller products are in "All other products"' : ''));
    }

    function renderSalespeople(k) {
        var sp = data.salespeople || [], total = num(k.Sales), osTotal = num(k.Outstanding);
        if (!num(k.SalespersonRows)) {
            $('#spTitle').text('Salespeople are not set up yet');
            $('#spTable thead').empty();
            $('#spTable tbody').html('<tr><td class="text-muted" style="border:0;padding:0">Add each customer code (or area) and its salesperson to the table <b>dbo.FeedSalesperson</b> ' +
                '(see Database/07_Feed_Review.sql). This section then fills in by itself.</td></tr>');
            $('#spNote').text('');
            return;
        }
        var lead = sp[0];
        var dues = sp.slice().sort(function (a, b) { return num(b.Outstanding) - num(a.Outstanding); })[0];
        $('#spTitle').text(!lead ? '' : (dues && dues.Salesperson !== lead.Salesperson && num(dues.Outstanding) > 0)
            ? lead.Salesperson + ' leads sales; ' + dues.Salesperson + '’s accounts hold most dues'
            : lead.Salesperson + ' leads sales and holds most dues');
        var maxS = Math.max.apply(null, sp.map(function (s) { return num(s.Sales); }).concat([1]));
        var inCr = maxS >= 1e7;
        $('#spTable thead').html('<tr><th>Salesperson</th><th>Sales (₹ ' + (inCr ? 'Cr' : 'lakh') + ') and share of total</th><th class="num">Outstanding</th><th class="num">O/S % of sales</th></tr>');
        $('#spTable tbody').html(sp.map(function (s) {
            var osPct = share(num(s.Outstanding), num(s.Sales)), hi = osPct >= 15 && num(s.Outstanding) > 0;
            return '<tr class="' + (hi ? 'hi' : '') + '"><td class="name">' + esc(s.Salesperson) + '</td>' +
                '<td><div class="share"><span class="bar" style="width:' + (num(s.Sales) * 60 / maxS).toFixed(1) + '%"></span><span>' + (num(s.Sales) / (inCr ? 1e7 : 1e5)).toFixed(2) + ' · ' + pct(share(num(s.Sales), total), 1) + '</span></div></td>' +
                '<td class="num os">' + money(s.Outstanding) + '</td>' +
                '<td class="num pct">' + (num(s.Sales) ? pct(osPct, 1) + (hi ? ' (high)' : '') : '–') + '</td></tr>';
        }).join(''));
        $('#spNote').text('L = lakh' + (dues && osTotal ? ' · ' + dues.Salesperson + '’s outstanding is ' + pct(share(num(dues.Outstanding), osTotal)) + ' of the total ' + money(osTotal) : '') +
            (sp.some(function (s) { return s.Salesperson === 'Unassigned'; }) ? ' · "Unassigned" = customers not yet in dbo.FeedSalesperson' : ''));
    }

    function renderQty(k, groupLbl) {
        var c = (data.customers || []).filter(function (x) { return num(x.QtyKg) > 0; }).sort(function (a, b) { return num(b.QtyKg) - num(a.QtyKg); });
        var top = c.slice(0, 10), n = top.length;
        var max = n ? num(top[0].QtyKg) : 1;
        $('#qtyTitle').text(n ? 'Top ' + n + ' customer' + (n === 1 ? '' : 's') + ' bought ' + pct(k.Top10QtyShare) + ' of all ' + groupLbl : 'No quantity recorded');
        $('#qtyRank').html(top.map(function (x) {
            return '<li><span class="who" title="' + esc(who(x)) + '">' + esc(who(x)) + '</span><span class="track"><span class="bar" style="width:' + (num(x.QtyKg) * 82 / max).toFixed(1) + '%"></span><span class="val">' + kg(x.QtyKg) + '</span></span></li>';
        }).join(''));
        $('#qtyNote').text(n ? 'L KG = lakh KG · ' + who(top[0]) + ' alone: ' + pct(share(num(top[0].QtyKg), num(k.QtyKg)), 1) + ' of quantity, ' + money(top[0].Sales) + ' of sales' : '');
    }

    function osTag(c, to) {
        var cutoff = new Date(parse(to)); cutoff.setDate(cutoff.getDate() - 60);
        var stale = c.LastFeedDate && parse(c.LastFeedDate) < cutoff;
        var since = c.LastFeedDate ? 'no billing since ' + monShort(c.LastFeedDate) : 'no feed billing';
        if (!num(c.Sales)) return { t: since.charAt(0).toUpperCase() + since.slice(1), warn: true };
        var p = share(num(c.Outstanding), num(c.Sales));
        if (p >= 99.5) return { t: '100% unpaid' + (stale ? ', ' + since : ''), warn: true };
        return { t: pct(p) + ' of its billing' + (stale ? ', ' + since : ''), warn: stale };
    }

    function renderOutstanding(k, to) {
        var c = (data.customers || []).filter(function (x) { return num(x.Outstanding) > 0; }).sort(function (a, b) { return num(b.Outstanding) - num(a.Outstanding); });
        var total = num(k.Outstanding), top = c.slice(0, 10);
        $('#osKicker').text('Customer-wise outstanding · total ' + money(total));
        if (!top.length) { $('#osTitle').text('No outstanding from feed customers'); $('#osList').empty(); $('#osNote').text(''); return; }
        var lead = top[0], leadShare = share(num(lead.Outstanding), total);
        $('#osTitle').text(leadShare >= 25 ? (lead.CName || lead.Code) + ' alone is ' + pct(leadShare) + ' of all outstanding'
            : 'The top ' + top.length + ' customers hold ' + pct(share(top.reduce(function (s, x) { return s + num(x.Outstanding); }, 0), total)) + ' of outstanding');
        var max = num(lead.Outstanding);
        $('#osList').html(top.map(function (x) {
            var tag = osTag(x, to);
            return '<div class="os-row"><span class="who" title="' + esc(who(x)) + '">' + esc(who(x)) + '</span>' +
                '<span class="track"><span class="bar" style="width:' + (num(x.Outstanding) * 70 / max).toFixed(1) + '%"></span><span class="val">' + money(x.Outstanding) + '</span></span>' +
                '<span class="tag' + (tag.warn ? ' warn' : '') + '">' + esc(tag.t) + '</span></div>';
        }).join(''));
        var topSum = top.reduce(function (s, x) { return s + num(x.Outstanding); }, 0);
        $('#osNote').text('L = lakh · These ' + top.length + ' customers hold ' + pct(share(topSum, total)) + ' of total outstanding · ' + c.length + ' customers have dues in all · ' +
            'outstanding is as on ' + longDate(to) + ' and covers all poultry products, as receipts are not recorded per product');
    }

    function renderPoints(k, to) {
        var custs = data.customers || [];
        var byQty = custs.filter(function (x) { return num(x.QtyKg) > 0; }).sort(function (a, b) { return num(b.QtyKg) - num(a.QtyKg); });
        var dues = custs.filter(function (x) { return num(x.Outstanding) > 0; }).sort(function (a, b) { return num(b.Outstanding) - num(a.Outstanding); });
        var cutoff = new Date(parse(to)); cutoff.setDate(cutoff.getDate() - 60);
        var old = dues.filter(function (x) { return !x.LastFeedDate || parse(x.LastFeedDate) < cutoff; });
        var pts = [];
        pts.push({ h: 'Customer concentration', p: byQty.length
            ? 'Top ' + Math.min(10, byQty.length) + ' customers take ' + pct(k.Top10QtyShare) + ' of quantity; ' + (byQty[0].CName || byQty[0].Code) + ' alone ' + pct(share(num(byQty[0].QtyKg), num(k.QtyKg))) + '.'
            : 'No quantity recorded in this period.' });
        pts.push({ h: 'Dues concentration', p: dues.length
            ? (dues[0].CName || dues[0].Code) + ' owes ' + money(dues[0].Outstanding) + ', ' + pct(share(num(dues[0].Outstanding), num(k.Outstanding))) + ' of the ' + money(k.Outstanding) + ' outstanding.'
            : 'No outstanding from feed customers.' });
        pts.push({ h: 'Old dues with no new billing', p: old.length
            ? old.slice(0, 3).map(function (x) { return (x.CName || x.Code) + ' (' + money(x.Outstanding) + (x.LastFeedDate ? ', since ' + monShort(x.LastFeedDate) : '') + ')'; }).join(', ') +
              (old.length > 3 ? ' and ' + (old.length - 3) + ' more' : '') + '.'
            : 'Every customer with dues was billed in the last 60 days.' });
        $('#points').html(pts.map(function (x) { return '<div class="pt"><h4>' + esc(x.h) + '</h4><p>' + esc(x.p) + '</p></div>'; }).join(''));
    }

    // ------------------------------------------------------------ detailed tables
    function defs() {
        var months = (data.monthly || []).map(function (m) { return String(m.MonthStart).slice(0, 10); });
        return {
            customers: { sort: 'Sales', file: 'customers', rows: data.customers || [], cols: [
                { k: 'Code', l: 'Code' }, { k: 'CName', l: 'Customer' }, { k: 'Area', l: 'Area' }, { k: 'Salesperson', l: 'Salesperson' },
                { k: 'Sales', l: 'Sales', t: 'money' }, { k: 'QtyKg', l: 'Qty (KG)', t: 'int' }, { k: 'DMs', l: 'DMs', t: 'int' }, { k: 'Months', l: 'Months billed', t: 'int', noTotal: true },
                { k: 'LastFeedDate', l: 'Last feed bill', t: 'date' }, { k: 'Outstanding', l: 'Outstanding', t: 'money' }, { k: 'MaxDays', l: 'Oldest due (days)', t: 'int', noTotal: true }] },
            months: { sort: 'MonthStart', dir: 1, file: 'month-wise', rows: (data.monthly || []).map(function (m) { return $.extend({ AvgRate: num(m.QtyKg) ? num(m.Sales) / num(m.QtyKg) : 0 }, m); }), cols: [
                { k: 'MonthStart', l: 'Month', t: 'month' }, { k: 'Sales', l: 'Sales', t: 'money' }, { k: 'QtyKg', l: 'Qty (KG)', t: 'int' },
                { k: 'AvgRate', l: 'Avg ₹/KG', t: 'money', noTotal: true }, { k: 'Customers', l: 'Customers billed', t: 'int', noTotal: true }, { k: 'DMs', l: 'DMs', t: 'int' }] },
            products: { sort: 'Sales', file: 'products', rows: data.products || [], cols: [
                { k: 'Product', l: 'Product' }, { k: 'Grp', l: 'Feed type' }, { k: 'Sales', l: 'Sales', t: 'money' }, { k: 'QtyKg', l: 'Qty (KG)', t: 'int' },
                { k: 'QtyNos', l: 'Bags / nos', t: 'int' }, { k: 'AvgRate', l: 'Avg ₹/KG', t: 'money', noTotal: true }, { k: 'Customers', l: 'Customers', t: 'int', noTotal: true }] },
            custmonth: (function () {
                var map = {};
                (data.custMonths || []).forEach(function (r) { (map[r.CustKey] = map[r.CustKey] || {})[String(r.MonthStart).slice(0, 10)] = num(r.Sales); });
                var rows = (data.customers || []).filter(function (c) { return num(c.Sales) > 0; }).map(function (c) {
                    var r = { CName: c.CName, Area: c.Area, Sales: c.Sales };
                    months.forEach(function (m) { r['m' + m] = (map[c.CustKey] || {})[m] || 0; });
                    return r;
                });
                return { sort: 'Sales', file: 'customer-month', rows: rows, cols: [{ k: 'CName', l: 'Customer' }, { k: 'Area', l: 'Area' }]
                    .concat(months.map(function (m) { return { k: 'm' + m, l: monShort(m) + ' ' + String(parse(m).getFullYear()).slice(2), t: 'money' }; }))
                    .concat([{ k: 'Sales', l: 'Total', t: 'money' }]) };
            })()
        };
    }
    var NUMERIC = { money: 1, int: 1 };
    function cell(c, v) {
        switch (c.t) {
            case 'money': return num(v) ? nf2.format(num(v)) : '<span class="text-muted">–</span>';
            case 'int': return num(v) ? nfInt.format(num(v)) : '<span class="text-muted">–</span>';
            case 'date': return dmy(v);
            case 'month': return monName(v) + ' ' + parse(v).getFullYear();
            default: return esc(v);
        }
    }
    function currentRows(D) {
        var q = ($('#txtSearch').val() || '').trim().toLowerCase(), key = table.sortKey || D.sort, dir = table.sortKey ? table.sortDir : (D.dir || -1);
        var col = D.cols.filter(function (c) { return c.k === key; })[0] || {};
        var rows = D.rows.filter(function (r) { return !q || D.cols.some(function (c) { return String(r[c.k] == null ? '' : r[c.k]).toLowerCase().indexOf(q) >= 0; }); });
        return rows.slice().sort(function (a, b) {
            if (NUMERIC[col.t]) return (num(a[key]) - num(b[key])) * dir;
            return String(a[key] == null ? '' : a[key]).localeCompare(String(b[key] == null ? '' : b[key]), 'en', { numeric: true }) * dir;
        });
    }
    function renderTable() {
        if (!data) return;
        var D = defs()[table.name], rows = currentRows(D), key = table.sortKey || D.sort;
        $('#tblData thead').html('<tr>' + D.cols.map(function (c) {
            return '<th data-key="' + c.k + '" class="' + (NUMERIC[c.t] ? 'num ' : '') + (c.k === key ? 'sorted' : '') + '">' + esc(c.l) + '<i class="bi bi-arrow-down-up si"></i></th>';
        }).join('') + '</tr>');
        $('#tblData tbody').html(rows.length ? rows.map(function (r) {
            return '<tr>' + D.cols.map(function (c) { return '<td class="' + (NUMERIC[c.t] ? 'num' : '') + '">' + cell(c, r[c.k]) + '</td>'; }).join('') + '</tr>';
        }).join('') : '<tr><td colspan="' + D.cols.length + '" class="text-center text-muted py-4">No rows</td></tr>');
        $('#tblData tfoot').html(rows.length ? '<tr>' + D.cols.map(function (c, i) {
            if (i === 0) return '<td>Total</td>';
            if (!NUMERIC[c.t] || c.noTotal) return '<td></td>';
            return '<td class="num">' + cell(c, rows.reduce(function (s, r) { return s + num(r[c.k]); }, 0)) + '</td>';
        }).join('') + '</tr>' : '');
        $('#tblNote').text(rows.length + ' rows' + (table.name === 'customers' ? ' · includes customers with dues but no feed billing in this period' : ''));
    }
    function exportCsv() {
        if (!data) return;
        var D = defs()[table.name];
        var q = function (v) { v = v == null ? '' : String(v); return /[",\n]/.test(v) ? '"' + v.replace(/"/g, '""') + '"' : v; };
        var lines = [D.cols.map(function (c) { return q(c.l); }).join(',')];
        currentRows(D).forEach(function (r) {
            lines.push(D.cols.map(function (c) { var v = r[c.k]; if (c.t === 'date') v = dmy(v); if (c.t === 'month') v = monName(v) + ' ' + parse(v).getFullYear(); return q(v); }).join(','));
        });
        var blob = new Blob(['﻿' + lines.join('\r\n')], { type: 'text/csv;charset=utf-8' });
        var a = document.createElement('a');
        a.href = URL.createObjectURL(blob);
        a.download = ('feed-review-' + D.file + '_' + $('#txtFrom').val() + '_to_' + $('#txtTo').val() + '.csv').replace(/[^\w.\-]/g, '_');
        document.body.appendChild(a); a.click();
        setTimeout(function () { URL.revokeObjectURL(a.href); a.remove(); }, 500);
    }

    // ------------------------------------------------------------ events
    $(function () {
        $('#presets').on('click', 'button', function () { setPreset($(this).data('preset')); });
        $('#txtFrom, #txtTo').on('change', function () { markPreset(); load(); });
        $('#ddlGroup, #ddlArea').on('change', load);
        $('#btnRefresh').on('click', load);
        $('#btnPrint').on('click', function () { window.print(); });
        $('#tabs').on('click', 'button', function () {
            $('#tabs button').removeClass('active'); $(this).addClass('active');
            table = { name: $(this).data('t'), sortKey: null, sortDir: -1 }; $('#txtSearch').val(''); renderTable();
        });
        $('#tblData').on('click', 'thead th', function () {
            var k = $(this).data('key');
            if (table.sortKey === k) table.sortDir *= -1; else { table.sortKey = k; table.sortDir = -1; }
            renderTable();
        });
        var t; $('#txtSearch').on('input', function () { clearTimeout(t); t = setTimeout(renderTable, 200); });
        $('#btnExport').on('click', exportCsv);

        loading(true);
        callApi('GetFilters', {})
            .done(function (f) {
                if (f.dates && f.dates.Today) today = parse(f.dates.Today);
                (f.areas || []).forEach(function (a) { $('#ddlArea').append($('<option>').val(a.AreaCode).text(a.Area ? a.Area + ' (' + a.AreaCode + ')' : a.AreaCode)); });
                setPreset('fy');
            })
            .fail(function (m) { $('#alertBox').text(m).removeClass('d-none'); })
            .always(function () { loading(false); });
    });
})(jQuery);
