/* ===== Dashboard assistant - chat window =====
   Plain JavaScript (no jQuery needed). Talks to Chat.ashx, which answers from the live
   dashboard data without any outside AI service. Included on every page by Controls/AppNav.ascx. */
(function () {
    'use strict';

    var root = document.getElementById('chatbot-root');
    if (!root) return;
    var ENDPOINT = root.getAttribute('data-endpoint') || 'Chat.ashx';
    var STORE = 'chatbot.v1';
    var state = { open: false, ctx: {}, items: [] };   // items: {who:'user'|'bot', text | reply}

    // ------------------------------------------------------------ storage (per browser tab)
    function save() {
        try { sessionStorage.setItem(STORE, JSON.stringify({ open: state.open, ctx: state.ctx, items: state.items.slice(-40) })); } catch (e) { /* ignore */ }
    }
    function load() {
        try {
            var s = JSON.parse(sessionStorage.getItem(STORE) || 'null');
            if (s) { state.open = !!s.open; state.ctx = s.ctx || {}; state.items = s.items || []; }
        } catch (e) { /* ignore */ }
    }

    // ------------------------------------------------------------ DOM helpers
    function el(tag, cls, text) {
        var e = document.createElement(tag);
        if (cls) e.className = cls;
        if (text != null) e.textContent = text;
        return e;
    }
    function icon(name) { var i = el('i', 'bi ' + name); i.setAttribute('aria-hidden', 'true'); return i; }

    /** text with **bold** parts, built safely (no HTML from the server is used) */
    function richText(text) {
        var p = el('p');
        String(text || '').split(/(\*\*[^*]+\*\*)/g).forEach(function (part) {
            if (/^\*\*[^*]+\*\*$/.test(part)) p.appendChild(el('strong', null, part.slice(2, -2)));
            else if (part) p.appendChild(document.createTextNode(part));
        });
        return p;
    }

    // ------------------------------------------------------------ build the window
    var launch = el('button', 'cb-launch');
    launch.type = 'button';
    launch.setAttribute('aria-label', 'Open the dashboard assistant');
    launch.appendChild(icon('bi-chat-dots-fill'));
    launch.appendChild(el('span', null, 'Ask'));

    var panel = el('section', 'cb-panel');
    panel.setAttribute('role', 'dialog');
    panel.setAttribute('aria-label', 'Dashboard assistant');

    var head = el('div', 'cb-head');
    var mark = el('div', 'cb-mark'); mark.appendChild(icon('bi-chat-dots-fill'));
    var titles = el('div');
    titles.appendChild(el('h2', null, 'Dashboard assistant'));
    titles.appendChild(el('p', null, 'Answers from live data · runs on your server'));
    var actions = el('div', 'cb-actions');
    var btnClear = el('button'); btnClear.type = 'button'; btnClear.title = 'Start a new chat'; btnClear.setAttribute('aria-label', 'Start a new chat'); btnClear.appendChild(icon('bi-arrow-counterclockwise'));
    var btnClose = el('button'); btnClose.type = 'button'; btnClose.title = 'Close'; btnClose.setAttribute('aria-label', 'Close the assistant'); btnClose.appendChild(icon('bi-x-lg'));
    actions.appendChild(btnClear); actions.appendChild(btnClose);
    head.appendChild(mark); head.appendChild(titles); head.appendChild(actions);

    var log = el('div', 'cb-log');
    log.setAttribute('aria-live', 'polite');
    var sugg = el('div', 'cb-sugg');

    var form = el('form', 'cb-form');
    var input = el('textarea');
    input.rows = 1;
    input.maxLength = 300;
    input.placeholder = 'Ask about dues, hatch dates, sales…';
    input.setAttribute('aria-label', 'Your question');
    var send = el('button'); send.type = 'submit'; send.setAttribute('aria-label', 'Send'); send.appendChild(icon('bi-send-fill'));
    form.appendChild(input); form.appendChild(send);

    panel.appendChild(head); panel.appendChild(log); panel.appendChild(sugg); panel.appendChild(form);
    document.body.appendChild(launch);
    document.body.appendChild(panel);

    // ------------------------------------------------------------ render
    function renderReply(reply) {
        var box = el('div', 'cb-msg cb-bot');
        (reply.blocks || []).forEach(function (b) {
            if (b.type === 'text') box.appendChild(richText(b.text));
            else if (b.type === 'stats') {
                var g = el('div', 'cb-stats');
                (b.items || []).forEach(function (it) {
                    var s = el('div', 'cb-stat');
                    s.appendChild(el('div', 'l', it.label)); s.appendChild(el('div', 'v', it.value));
                    g.appendChild(s);
                });
                box.appendChild(g);
                if (b.note) box.appendChild(el('div', 'cb-note', b.note));
            } else if (b.type === 'table') {
                var wrap = el('div', 'cb-table-wrap'), t = el('table', 'cb-table'), thead = el('thead'), tr = el('tr');
                var align = b.align || [];
                (b.cols || []).forEach(function (c, i) { var th = el('th', align[i] === 'num' ? 'num' : '', c); tr.appendChild(th); });
                thead.appendChild(tr); t.appendChild(thead);
                var tb = el('tbody');
                (b.rows || []).forEach(function (row) {
                    var r = el('tr');
                    row.forEach(function (v, i) { r.appendChild(el('td', align[i] === 'num' ? 'num' : '', v)); });
                    tb.appendChild(r);
                });
                t.appendChild(tb); wrap.appendChild(t); box.appendChild(wrap);
            } else if (b.type === 'link' && /^[\w\-]+\.aspx(\?[\w=&\-]*)?$/i.test(b.href || '')) {
                var a = el('a', 'cb-link', b.text); a.href = b.href; a.appendChild(icon('bi-arrow-up-right'));
                box.appendChild(a);
            }
        });
        return box;
    }

    function setSuggestions(list) {
        sugg.innerHTML = '';
        (list || []).forEach(function (s) {
            var b = el('button', null, s); b.type = 'button';
            b.addEventListener('click', function () { ask(s); });
            sugg.appendChild(b);
        });
    }

    function renderAll() {
        log.innerHTML = '';
        if (!state.items.length) state.items.push({ who: 'bot', reply: welcome() });
        state.items.forEach(function (it) {
            log.appendChild(it.who === 'user' ? el('div', 'cb-msg cb-user', it.text) : renderReply(it.reply));
        });
        var last = state.items[state.items.length - 1];
        setSuggestions(last && last.who === 'bot' ? last.reply.suggestions : []);
        log.scrollTop = log.scrollHeight;
    }

    function welcome() {
        return {
            blocks: [{ type: 'text', text: 'Hi! Ask me about **customer dues**, **aging**, **last hatch dates**, **sales** or the **feed review**. Type a customer name, or tap a question below.' }],
            suggestions: ['Top 10 chick dues', 'Broiler dues over 90 days', 'Last hatch dates', 'Chick sales this month', 'Feed sales this FY', 'Help']
        };
    }

    // ------------------------------------------------------------ talk to the server
    var busy = false;
    function ask(text) {
        text = String(text || '').trim();
        if (!text || busy) return;
        busy = true; send.disabled = true;
        state.items.push({ who: 'user', text: text });
        log.appendChild(el('div', 'cb-msg cb-user', text));
        setSuggestions([]);
        var typing = el('div', 'cb-typing'); typing.appendChild(el('span')); typing.appendChild(el('span')); typing.appendChild(el('span'));
        typing.setAttribute('aria-label', 'Looking that up');
        log.appendChild(typing);
        log.scrollTop = log.scrollHeight;
        input.value = ''; autosize();

        fetch(ENDPOINT, {
            method: 'POST', credentials: 'same-origin',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ q: text, ctx: state.ctx })
        }).then(function (res) {
            if (res.status === 401 || res.redirected) {
                window.location.href = 'Login.aspx?ReturnUrl=' + encodeURIComponent(window.location.pathname + window.location.search);
                throw new Error('signin');
            }
            if (!res.ok) throw new Error('http ' + res.status);
            return res.json();
        }).then(function (reply) {
            state.ctx = reply.ctx || {};
            state.items.push({ who: 'bot', reply: reply });
        }).catch(function (err) {
            if (err && err.message === 'signin') return;
            state.items.push({ who: 'bot', reply: { blocks: [{ type: 'text', text: 'I couldn’t reach the server. Check your connection and try again.' }], suggestions: [text] } });
        }).then(function () {
            busy = false; send.disabled = false;
            if (typing.parentNode) typing.parentNode.removeChild(typing);
            renderAll(); save();
            if (window.matchMedia('(min-width: 576px)').matches) input.focus();
        });
    }

    // ------------------------------------------------------------ open / close
    function setOpen(open) {
        state.open = open;
        document.body.classList.toggle('cb-open', open);
        launch.setAttribute('aria-expanded', String(open));
        if (open) { renderAll(); setTimeout(function () { input.focus(); }, 30); }
        else launch.focus();
        save();
    }

    function autosize() { input.style.height = 'auto'; input.style.height = Math.min(120, input.scrollHeight) + 'px'; }

    launch.addEventListener('click', function () { setOpen(true); });
    btnClose.addEventListener('click', function () { setOpen(false); });
    btnClear.addEventListener('click', function () { state.items = []; state.ctx = {}; renderAll(); save(); input.focus(); });
    form.addEventListener('submit', function (e) { e.preventDefault(); ask(input.value); });
    input.addEventListener('input', autosize);
    input.addEventListener('keydown', function (e) {
        if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); ask(input.value); }
    });
    panel.addEventListener('keydown', function (e) { if (e.key === 'Escape') setOpen(false); });

    load();
    if (state.open) setOpen(true);
})();
