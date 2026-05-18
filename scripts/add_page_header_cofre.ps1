# ============================================================================
# Script: add_page_header_cofre.ps1
# Adiciona classes Cofre (.page-eyebrow, .page-title, .page-title em,
# .page-subtitle) ao CSS de cada página — SEM remover .page-header existente.
# Idempotente: só adiciona se .page-eyebrow ainda não existe.
# ============================================================================

$ErrorActionPreference = 'Stop'
$base = Split-Path -Parent $PSScriptRoot
if (-not $base) { $base = Split-Path -Parent $MyInvocation.MyCommand.Definition | Split-Path -Parent }
Set-Location $base

# Bloco a injetar após .topbar-title strong (que já foi padronizado pelo script anterior)
$injectAfter = ".topbar-title strong{color:var(--txt); font-weight:600;}"

$cofreClasses = @"

/* Page header · padrão Cofre */
.page-eyebrow{font-family:'JetBrains Mono',monospace; font-size:10px; color:var(--txt2); text-transform:uppercase; letter-spacing:.18em; margin-bottom:8px; font-weight:600;}
.page-eyebrow .sep{color:var(--txt3); margin:0 6px;}
.page-title{font-size:28px; font-weight:800; letter-spacing:-.02em; line-height:1.15;}
.page-title em{font-style:italic; color:var(--orange);}
.page-subtitle{margin-top:6px; color:var(--txt2); font-size:13px;}
"@

$skipList = @(
    'r2_people_tenant_setup.html',
    'r2_people_pricing.html',
    'r2_people_landing.html',
    'r2_people_login.html',
    'r2_people_onboarding.html',
    'r2_people_error_pages.html',
    'r2_people_ferias_programar.html',
    'r2_people_showcase.html',
    'r2_people_demo.html',
    # Já tem o pattern Cofre completo:
    'r2_people_lgpd_cockpit.html',
    'r2_people_notificacoes_admin.html',
    'r2_people_observability_admin.html',
    'r2_people_security_admin.html',
    'r2_people_admin_hub.html',
    'r2_people_billing.html',
    'r2_people_dr_console.html',
    'r2_people_notificacoes.html'
)

$files = Get-ChildItem -Path . -Filter "r2_people_*.html"
$count = 0

foreach ($f in $files) {
    if ($skipList -contains $f.Name) { continue }

    $content = Get-Content $f.FullName -Raw -Encoding UTF8
    $original = $content

    # Já tem .page-eyebrow? Skip
    if ($content.Contains('.page-eyebrow')) { continue }

    # Procura ponto de injeção (após .topbar-title strong padronizado)
    if ($content.Contains($injectAfter)) {
        $content = $content.Replace($injectAfter, $injectAfter + $cofreClasses)
    }

    if ($content -ne $original) {
        Set-Content -Path $f.FullName -Value $content -Encoding UTF8 -NoNewline
        Write-Host "FIXED: $($f.Name)"
        $count++
    }
}

Write-Host ""
Write-Host "Page-header classes Cofre adicionadas em $count arquivos"
