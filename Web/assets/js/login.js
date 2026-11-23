/* ===== Login page - signs in with AJAX (no page reload) ===== */
(function ($) {
    'use strict';
    var cfg = window.LOGIN_CONFIG || { pageUrl: 'Login.aspx', returnUrl: '', reason: '' };

    function show(type, icon, text) {
        $('#msg').removeClass('d-none notice-danger notice-info notice-success').addClass('notice-' + type)
            .empty().append($('<i>').addClass('bi ' + icon)).append($('<span>').text(text));
    }
    function hide() { $('#msg').addClass('d-none'); }
    function busy(on) {
        $('#btnLogin').prop('disabled', on).find('.spinner-border').toggleClass('d-none', !on);
        $('#btnLogin .lbl').text(on ? 'Signing in…' : 'Sign in');
    }

    $(function () {
        // start in the password box when the user name is already filled in
        ($.trim($('#txtUser').val()) ? $('#txtPwd') : $('#txtUser')).trigger('focus');

        if (cfg.reason === 'expired') show('info', 'bi-info-circle-fill', 'Your session has ended. Sign in to continue where you left off.');
        if (cfg.reason === 'out') show('success', 'bi-check-circle-fill', 'You have been signed out.');

        $('#btnShow').on('click', function () {
            var $p = $('#txtPwd'), showing = $p.attr('type') === 'text';
            $p.attr('type', showing ? 'password' : 'text');
            $(this).attr('aria-label', showing ? 'Show password' : 'Hide password').attr('title', showing ? 'Show password' : 'Hide password')
                .find('i').toggleClass('bi-eye', showing).toggleClass('bi-eye-slash', !showing);
            $p.trigger('focus');
        });

        $('#txtPwd').on('keyup keydown', function (e) {
            if (e.originalEvent && e.originalEvent.getModifierState)
                $('#capsWarn').toggleClass('d-none', !e.originalEvent.getModifierState('CapsLock'));
        });
        $('#txtUser, #txtPwd').on('input', function () { $(this).removeClass('is-invalid'); });

        $('#frmLogin').on('submit', function (e) {
            e.preventDefault();
            hide();
            var u = $.trim($('#txtUser').val()), p = $('#txtPwd').val();
            $('#txtUser').toggleClass('is-invalid', !u);
            $('#txtPwd').toggleClass('is-invalid', !p);
            if (!u || !p) {
                show('danger', 'bi-exclamation-triangle-fill', 'Please enter your user name and password.');
                (u ? $('#txtPwd') : $('#txtUser')).trigger('focus');
                return;
            }
            busy(true);
            $.ajax({
                type: 'POST',
                url: cfg.pageUrl + '/Login',
                data: JSON.stringify({ userName: u, password: p, remember: $('#chkRemember').is(':checked'), returnUrl: cfg.returnUrl }),
                contentType: 'application/json; charset=utf-8',
                dataType: 'json',
                timeout: 60000
            }).done(function (resp) {
                var r = resp && resp.d;
                if (r && r.ok) {
                    show('success', 'bi-check-circle-fill', 'Signed in. Opening your dashboard…');
                    window.location.replace(r.redirect || 'Default.aspx');
                    return;
                }
                busy(false);
                show('danger', 'bi-exclamation-triangle-fill', (r && r.error) || 'Sign in failed.');
                $('#txtPwd').val('').addClass('is-invalid').trigger('focus');
                $('.form-card').removeClass('shake'); void $('.form-card')[0].offsetWidth; $('.form-card').addClass('shake');
            }).fail(function (xhr, status) {
                busy(false);
                show('danger', 'bi-wifi-off', status === 'timeout' ? 'The server took too long to respond. Please try again.' : 'Could not reach the server (' + (xhr.status || 'network') + '). Please try again.');
            });
        });
    });
})(jQuery);
