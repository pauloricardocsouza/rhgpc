# ============================================================================
# Script: standardize_cofre.ps1
# Aplica o padrão visual Cofre em batch nas páginas que ainda usam o padrão
# "dashboard genérico" (sidebar branca mas com logo pequeno horizontal, sections
# tipografia padrão, nav-item.active com border-left, footer R2 inline).
#
# Mudanças aplicadas:
#  1. Sidebar styles: logo grande centralizado, JetBrains Mono nas sections,
#     ::before bar laranja flutuante no active state, footer "Desenvolvido por"
#     + logo r2-color.png
#  2. Brand HTML: substitui o brand-sub (em geral nome da empresa repetido)
#     pelo "v.0.1" mono
#  3. Footer HTML: substitui "<span>R2 Soluções</span><span class='v'>v0.1</span>"
#     pelo bloco padrão com logo
#
# Idempotente: só altera se encontrar o pattern antigo exato.
# ============================================================================

$ErrorActionPreference = 'Stop'
# Resolve diretório do próprio script (evita problemas de encoding em paths c/ acento)
$base = Split-Path -Parent $PSScriptRoot
if (-not $base) { $base = Split-Path -Parent $MyInvocation.MyCommand.Definition | Split-Path -Parent }
Set-Location $base

# Pattern CSS antigo (linha única — assim que está nos arquivos)
$cssOldA = @'
.sidebar-brand{height:var(--topbar-h); padding:0 18px; display:flex; align-items:center; gap:10px; border-bottom:1px solid var(--gray1);}
.brand-logo{width:auto; height:30px; display:block; flex-shrink:0;}
.brand-text{display:flex; flex-direction:column; line-height:1.1;}
.brand-name{font-weight:600; font-size:14px;}
.brand-sub{font-size:10.5px; color:var(--txt2);}
.sidebar-section{padding:14px 14px 6px; font-size:10px; text-transform:uppercase; letter-spacing:1.2px; color:var(--txt3); font-weight:500;}
.sidebar-nav{flex:1; overflow-y:auto; padding-bottom:14px;}
.nav-item{display:flex; align-items:center; gap:11px; padding:9px 18px; color:var(--txt2); text-decoration:none; font-size:12.5px; border-left:3px solid transparent; cursor:pointer;}
.nav-item:hover{background:var(--gray1); color:var(--txt);}
.nav-item.active{background:var(--blue2); color:var(--navy); border-left-color:var(--orange); font-weight:600;}
.nav-item svg{width:16px; height:16px; flex-shrink:0; opacity:.85;}
.sidebar-footer{padding:12px 16px; border-top:1px solid var(--gray1); font-size:10.5px; color:var(--txt3); display:flex; align-items:center; justify-content:space-between;}
.sidebar-footer .v{font-family:'JetBrains Mono',monospace;}
'@

# Variação B: nav-item com transition:all .15s
$cssOldB = @'
.sidebar-brand{height:var(--topbar-h); padding:0 18px; display:flex; align-items:center; gap:10px; border-bottom:1px solid var(--gray1);}
.brand-logo{width:auto; height:30px; display:block; flex-shrink:0;}
.brand-text{display:flex; flex-direction:column; line-height:1.1;}
.brand-name{font-weight:600; font-size:14px;}
.brand-sub{font-size:10.5px; color:var(--txt2);}
.sidebar-section{padding:14px 14px 6px; font-size:10px; text-transform:uppercase; letter-spacing:1.2px; color:var(--txt3); font-weight:500;}
.sidebar-nav{flex:1; overflow-y:auto; padding-bottom:14px;}
.nav-item{display:flex; align-items:center; gap:11px; padding:9px 18px; color:var(--txt2); text-decoration:none; font-size:12.5px; border-left:3px solid transparent; transition:all .15s; cursor:pointer;}
.nav-item:hover{background:var(--gray1); color:var(--txt);}
.nav-item.active{background:var(--blue2); color:var(--navy); border-left-color:var(--orange); font-weight:600;}
.nav-item svg{width:16px; height:16px; flex-shrink:0; opacity:.85;}
.sidebar-footer{padding:12px 16px; border-top:1px solid var(--gray1); font-size:10.5px; color:var(--txt3); display:flex; align-items:center; justify-content:space-between;}
.sidebar-footer .v{font-family:'JetBrains Mono',monospace;}
'@

# Variação C: brand-logo como div com gradient (legado da v0.8) + nav-item.active svg opacity
$cssOldC = @'
.sidebar-brand{height:var(--topbar-h); padding:0 18px; display:flex; align-items:center; gap:10px; border-bottom:1px solid var(--gray1); flex-shrink:0;}
.brand-logo{width:34px; height:34px; border-radius:8px; background:linear-gradient(135deg,var(--navy3),var(--orange)); display:flex; align-items:center; justify-content:center; font-weight:700; color:#fff; font-size:14px; letter-spacing:.5px;}
.brand-text{display:flex; flex-direction:column; line-height:1.1;}
.brand-name{font-weight:600; font-size:14px;}
.brand-sub{font-size:10.5px; color:var(--gray3); letter-spacing:.3px;}
.sidebar-section{padding:14px 14px 6px; font-size:10px; text-transform:uppercase; letter-spacing:1.2px; color:var(--txt3); font-weight:500;}
.sidebar-nav{flex:1; overflow-y:auto; padding-bottom:14px;}
.nav-item{display:flex; align-items:center; gap:11px; padding:9px 18px; color:var(--txt2); text-decoration:none; font-size:12.5px; border-left:3px solid transparent; transition:all .15s; cursor:pointer;}
.nav-item:hover{background:var(--gray1); color:var(--txt);}
.nav-item.active{background:var(--blue2); color:var(--navy); border-left-color:var(--orange); font-weight:600;}
.nav-item svg{width:16px; height:16px; flex-shrink:0; opacity:.85;}
.nav-item.active svg{opacity:1;}
.sidebar-footer{padding:12px 16px; border-top:1px solid var(--gray1); font-size:10.5px; color:var(--txt3); display:flex; align-items:center; justify-content:space-between;}
.sidebar-footer .v{color:var(--gray3); font-family:'JetBrains Mono',monospace;}
'@

# Brand HTML legado: <div class="brand-logo">GP</div> (gradient)
$brandLegacy = @'
      <div class="brand-logo">GP</div>
      <div class="brand-text">
'@
$brandLegacyNew = @'
      <img class="brand-logo" src="assets/gpc-color.png" alt="GPC">
      <div class="brand-text">
'@

$cssNew = @'
.sidebar-brand{padding:20px 18px 18px; display:flex; flex-direction:column; align-items:center; gap:8px; border-bottom:1px solid var(--gray1);}
.brand-logo{height:56px; width:auto; max-width:80%;}
.brand-text{display:flex; flex-direction:column; align-items:center; line-height:1.1; gap:3px;}
.brand-name{font-weight:700; font-size:13px;}
.brand-sub{font-family:'JetBrains Mono',monospace; font-size:9px; color:var(--txt2); text-transform:uppercase; letter-spacing:0.18em; font-weight:600;}
.sidebar-section{padding:10px 12px 4px; font-family:'JetBrains Mono',monospace; font-size:9px; text-transform:uppercase; letter-spacing:.14em; color:var(--txt3); font-weight:700;}
.sidebar-nav{flex:1; overflow-y:auto; padding:8px 8px 14px;}
.nav-item{display:flex; align-items:center; gap:10px; padding:7px 10px 7px 12px; color:var(--txt2); text-decoration:none; font-size:13px; font-weight:500; border-radius:6px; position:relative; margin:1px 0; cursor:pointer;}
.nav-item:hover{background:var(--gray1); color:var(--txt);}
.nav-item.active{background:var(--blue2); color:var(--navy); font-weight:600;}
.nav-item.active::before{content:''; position:absolute; left:0; top:6px; bottom:6px; width:3px; background:var(--orange); border-radius:2px;}
.nav-item svg{width:16px; height:16px; flex-shrink:0; opacity:.85;}
.sidebar-footer{padding:12px 18px; border-top:1px solid var(--gray1); display:flex; flex-direction:column; align-items:center; gap:6px;}
.sidebar-r2-lbl{font-family:'JetBrains Mono',monospace; font-size:8.5px; font-weight:700; color:var(--txt3); text-transform:uppercase; letter-spacing:.14em;}
.sidebar-r2-logo{height:22px; opacity:.75;}
'@

# Pattern HTML do footer antigo (várias variações comuns)
$footerOldA = @'
    <div class="sidebar-footer"><span>R2 Soluções</span><span class="v">v0.1</span></div>
'@
$footerOldB = @'
    <div class="sidebar-footer"><span>R2 Soluções</span><span class="v">v0.2</span></div>
'@
$footerOldC = @'
    <div class="sidebar-footer">
      <span>R2 Soluções</span>
      <span class="v">v0.1</span>
    </div>
'@

$footerNew = @'
    <div class="sidebar-footer">
      <span class="sidebar-r2-lbl">Desenvolvido por</span>
      <img class="sidebar-r2-logo" src="assets/r2-color.png" alt="R2">
    </div>
'@

# Pattern HTML do brand antigo (texto duplicado em vários arquivos)
$brandOldA = @'
        <span class="brand-name">Gestão de Pessoas</span>
        <span class="brand-sub">Gestão de Pessoas</span>
'@
$brandNew = @'
        <span class="brand-name">Gestão de Pessoas</span>
        <span class="brand-sub">v.0.1</span>
'@

$files = Get-ChildItem -Path . -Filter "r2_people_*.html"
$count = 0
$skipped = 0

foreach ($f in $files) {
    # Não tocar nas páginas já refatoradas
    $skipList = @(
        'r2_people_notificacoes.html',      # já está no padrão Cofre
        'r2_people_lgpd_cockpit.html',      # refatorada nesta rodada
        'r2_people_notificacoes_admin.html',
        'r2_people_observability_admin.html',
        'r2_people_security_admin.html',
        'r2_people_admin_hub.html',
        'r2_people_billing.html',
        'r2_people_dr_console.html',
        'r2_people_home.html',              # refatorada manualmente
        'r2_people_tenant_setup.html',      # wizard standalone
        'r2_people_pricing.html',           # landing comercial
        'r2_people_landing.html'            # landing comercial
    )
    if ($skipList -contains $f.Name) {
        $skipped++
        continue
    }

    $content = Get-Content $f.FullName -Raw -Encoding UTF8
    $original = $content

    # Aplica transformações apenas se encontrar o pattern exato
    if ($content.Contains($cssOldA)) {
        $content = $content.Replace($cssOldA, $cssNew)
    }
    if ($content.Contains($cssOldB)) {
        $content = $content.Replace($cssOldB, $cssNew)
    }
    if ($content.Contains($cssOldC)) {
        $content = $content.Replace($cssOldC, $cssNew)
    }
    if ($content.Contains($brandLegacy)) {
        $content = $content.Replace($brandLegacy, $brandLegacyNew)
    }

    if ($content.Contains($footerOldA)) {
        $content = $content.Replace($footerOldA, $footerNew)
    }
    if ($content.Contains($footerOldB)) {
        $content = $content.Replace($footerOldB, $footerNew)
    }
    if ($content.Contains($footerOldC)) {
        $content = $content.Replace($footerOldC, $footerNew)
    }

    if ($content.Contains($brandOldA)) {
        $content = $content.Replace($brandOldA, $brandNew)
    }

    if ($content -ne $original) {
        Set-Content -Path $f.FullName -Value $content -Encoding UTF8 -NoNewline
        Write-Host "FIXED: $($f.Name)"
        $count++
    }
}

Write-Host ""
Write-Host "Padronização Cofre completa · $count arquivos modificados · $skipped pulados"
