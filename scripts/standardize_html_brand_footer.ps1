# ============================================================================
# Script: standardize_html_brand_footer.ps1
# Aplica padrão Cofre no HTML do brand (logo) e footer da sidebar em batch
# Idempotente — só altera se encontrar pattern antigo
# ============================================================================

$ErrorActionPreference = 'Stop'
$base = Split-Path -Parent $PSScriptRoot
if (-not $base) { $base = Split-Path -Parent $MyInvocation.MyCommand.Definition | Split-Path -Parent }
Set-Location $base

# --- BRAND HTML antigo (variações comuns) ---
$brandPatterns = @(
    @{ Old = @'
      <img class="brand-logo" src="assets/gpc-color.png" alt="GPC">
      <div class="brand-text">
        <span class="brand-name">Gestão de Pessoas</span>
        <span class="brand-sub">v.0.1</span>
      </div>
'@; New = $null }  # já está OK, não muda
)

# Pattern do brand-sub legado (CTPS/GP/etc) → "v.0.1"
$brandSubPatterns = @(
    @{ Old = '<span class="brand-sub">GP · 367 colaboradores</span>'; New = '<span class="brand-sub">v.0.1</span>' },
    @{ Old = '<span class="brand-sub">GP · 367 pessoas</span>'; New = '<span class="brand-sub">v.0.1</span>' },
    @{ Old = '<span class="brand-sub">Gestão de Pessoas</span>'; New = '<span class="brand-sub">v.0.1</span>' }
)

# --- FOOTER HTML antigo ---
$footerOlds = @(
    @'
    <div class="sidebar-footer"><span>R2 Soluções</span><span class="v">v0.1</span></div>
'@,
    @'
    <div class="sidebar-footer"><span>R2 Soluções</span><span class="v">v0.2</span></div>
'@,
    @'
    <div class="sidebar-footer">
      <span>R2 Soluções</span>
      <span class="v">v0.1</span>
    </div>
'@,
    @'
    <div class="sidebar-footer">
      <span>R2 Soluções</span>
      <span class="v">v0.2</span>
    </div>
'@,
    @'
    <div class="sidebar-footer">
      <span>R2 Soluções</span>
      <span class="v">v0.1.0</span>
    </div>
'@
)

$footerNew = @'
    <div class="sidebar-footer">
      <span class="sidebar-r2-lbl">Desenvolvido por</span>
      <img class="sidebar-r2-logo" src="assets/r2-color.png" alt="R2">
    </div>
'@

# Skip list — páginas já refatoradas manualmente OU standalone
$skipList = @(
    'r2_people_tenant_setup.html',
    'r2_people_pricing.html',
    'r2_people_landing.html',
    'r2_people_login.html',
    'r2_people_onboarding.html',
    'r2_people_error_pages.html',
    'r2_people_ferias_programar.html',
    'r2_people_showcase.html'
)

$files = Get-ChildItem -Path . -Filter "r2_people_*.html"
$count = 0

foreach ($f in $files) {
    if ($skipList -contains $f.Name) { continue }

    $content = Get-Content $f.FullName -Raw -Encoding UTF8
    $original = $content

    # Brand-sub patterns — usa regex para tolerar indentação variável
    $content = $content -replace '<span class="brand-sub">Gestão de Pessoas</span>', '<span class="brand-sub">v.0.1</span>'
    $content = $content -replace '<span class="brand-sub">GP[^<]*</span>', '<span class="brand-sub">v.0.1</span>'
    $content = $content -replace '<span class="brand-sub">grupo pinto cerqueira</span>', '<span class="brand-sub">v.0.1</span>'
    $content = $content -replace '<span class="brand-sub">Grupo Pinto Cerqueira</span>', '<span class="brand-sub">v.0.1</span>'

    # Footer patterns
    foreach ($oldFooter in $footerOlds) {
        if ($content.Contains($oldFooter)) {
            $content = $content.Replace($oldFooter, $footerNew)
        }
    }

    if ($content -ne $original) {
        Set-Content -Path $f.FullName -Value $content -Encoding UTF8 -NoNewline
        Write-Host "FIXED: $($f.Name)"
        $count++
    }
}

Write-Host ""
Write-Host "Brand & footer HTML padronizado · $count arquivos modificados"
