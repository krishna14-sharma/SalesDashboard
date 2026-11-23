<%@ Page Language="C#" AutoEventWireup="true" CodeFile="Login.aspx.cs" Inherits="LoginPage" EnableViewState="false" %>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <meta name="robots" content="noindex" />
    <meta name="theme-color" content="#1B2536" />
    <title>Sign in · <%= Server.HtmlEncode(AppTitle) %></title>
    <link rel="preconnect" href="https://fonts.googleapis.com" />
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin="anonymous" />
    <link href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@400;500;600;700;800&display=swap" rel="stylesheet" />
    <link href="https://cdnjs.cloudflare.com/ajax/libs/bootstrap/5.3.3/css/bootstrap.min.css" rel="stylesheet" />
    <link href="https://cdnjs.cloudflare.com/ajax/libs/bootstrap-icons/1.11.3/font/bootstrap-icons.min.css" rel="stylesheet" />
    <link href="assets/css/login.css?v=2" rel="stylesheet" />
</head>
<body>
    <div class="login-shell">

        <!-- ================= brand side ================= -->
        <aside class="brand-side">
            <div class="brand-id">
                <% if (LogoUrl.Length > 0) { %>
                    <img src="<%= Server.HtmlEncode(LogoUrl) %>" alt="" class="brand-logo" />
                <% } else { %>
                    <span class="egg-mark" aria-hidden="true"></span>
                <% } %>
                <span class="brand-name"><%= Server.HtmlEncode(CompanyName.Length > 0 ? CompanyName : AppTitle) %></span>
            </div>

            <div class="hero">
                <svg class="egg" viewBox="0 0 200 260" role="img" aria-label="Egg-shaped window with bars showing payments due by age">
                    <defs>
                        <clipPath id="eggClip">
                            <path d="M100 4C152 4 196 94 196 162C196 220 152 256 100 256S4 220 4 162C4 94 48 4 100 4Z" />
                        </clipPath>
                        <radialGradient id="yolk" cx="50%" cy="66%" r="55%">
                            <stop offset="0%" stop-color="#F2B632" stop-opacity=".95" />
                            <stop offset="45%" stop-color="#E08E1B" stop-opacity=".45" />
                            <stop offset="100%" stop-color="#1B2536" stop-opacity="0" />
                        </radialGradient>
                        <linearGradient id="shell" x1="0" y1="0" x2="0" y2="1">
                            <stop offset="0%" stop-color="#26324A" />
                            <stop offset="100%" stop-color="#1E293D" />
                        </linearGradient>
                    </defs>
                    <g clip-path="url(#eggClip)">
                        <rect width="200" height="260" fill="url(#shell)" />
                        <circle class="glow" cx="100" cy="172" r="120" fill="url(#yolk)" />
                        <!-- payments due by age: newest (left) to oldest (right) -->
                        <g class="bars">
                            <rect x="38"  y="150" width="18" height="80" rx="4" fill="#3FA77C" />
                            <rect x="64"  y="172" width="18" height="58" rx="4" fill="#A3BE48" />
                            <rect x="90"  y="186" width="18" height="44" rx="4" fill="#F2B632" />
                            <rect x="116" y="198" width="18" height="32" rx="4" fill="#E8742F" />
                            <rect x="142" y="210" width="18" height="20" rx="4" fill="#C2412F" />
                        </g>
                        <line x1="26" y1="231" x2="174" y2="231" stroke="#ffffff" stroke-opacity=".35" stroke-width="1.5" />
                    </g>
                    <path d="M100 4C152 4 196 94 196 162C196 220 152 256 100 256S4 220 4 162C4 94 48 4 100 4Z"
                          fill="none" stroke="#ffffff" stroke-opacity=".18" stroke-width="2" />
                </svg>

                <h2 class="hero-title">Every hatch and every rupee, accounted for.</h2>
                <p class="hero-copy">Chick and poultry product sales, payments received and customer outstanding by age, in one place.</p>
            </div>

            <p class="brand-foot">&copy; <%= DateTime.Now.Year %> <%= Server.HtmlEncode(CompanyName.Length > 0 ? CompanyName : AppTitle) %>. For authorised staff.</p>
        </aside>

        <!-- ================= form side ================= -->
        <main class="form-side">
            <div class="form-card">
                <div class="mobile-id">
                    <% if (LogoUrl.Length > 0) { %>
                        <img src="<%= Server.HtmlEncode(LogoUrl) %>" alt="" class="brand-logo" />
                    <% } else { %>
                        <span class="egg-mark" aria-hidden="true"></span>
                    <% } %>
                    <span><%= Server.HtmlEncode(CompanyName.Length > 0 ? CompanyName : AppTitle) %></span>
                </div>

                <h1>Sign in</h1>
                <p class="sub">to <%= Server.HtmlEncode(AppTitle) %></p>

                <div id="msg" class="notice d-none" role="alert"></div>

                <form id="frmLogin" novalidate="novalidate" autocomplete="on">
                    <div class="field">
                        <label for="txtUser">User name</label>
                        <div class="control">
                            <i class="bi bi-person" aria-hidden="true"></i>
                            <input type="text" id="txtUser" name="username" maxlength="15" value="<%= Server.HtmlEncode(DefaultUser) %>"
                                   autocomplete="username" autocapitalize="none" spellcheck="false" required="required" />
                        </div>
                    </div>

                    <div class="field">
                        <label for="txtPwd">Password</label>
                        <div class="control">
                            <i class="bi bi-lock" aria-hidden="true"></i>
                            <input type="password" id="txtPwd" name="password" maxlength="100"
                                   autocomplete="current-password" required="required" />
                            <button type="button" id="btnShow" class="reveal" aria-label="Show password" title="Show password"><i class="bi bi-eye"></i></button>
                        </div>
                        <div id="capsWarn" class="caps d-none"><i class="bi bi-capslock-fill"></i>Caps Lock is on</div>
                    </div>

                    <label class="remember" for="chkRemember">
                        <input type="checkbox" id="chkRemember" />
                        <span class="box" aria-hidden="true"><i class="bi bi-check-lg"></i></span>
                        <span>Keep me signed in on this device for 7 days</span>
                    </label>

                    <button type="submit" id="btnLogin" class="btn-signin">
                        <span class="spinner-border spinner-border-sm d-none" role="status" aria-hidden="true"></span>
                        <span class="lbl">Sign in</span>
                    </button>
                </form>

                <div class="assist">
                    <p><i class="bi bi-shield-lock"></i>Your session ends after 60 minutes without activity.</p>
                    <p><i class="bi bi-key"></i>Forgot your password? Ask your system administrator to reset it.</p>
                </div>
            </div>
        </main>
    </div>

    <script>
        window.LOGIN_CONFIG = {
            pageUrl: '<%= ResolveUrl("~/Login.aspx") %>',
            returnUrl: <%= ReturnUrlJson %>,
            reason: '<%= Reason %>'
        };
    </script>
    <script src="https://cdnjs.cloudflare.com/ajax/libs/jquery/3.7.1/jquery.min.js"></script>
    <script src="assets/js/login.js?v=3"></script>
</body>
</html>
