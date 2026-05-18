# ============================================================================
# Script: standardize_topbar.ps1
# Padroniza o estilo do .topbar-title (CSS) para usar JetBrains Mono c/ separator
# Idempotente
# ============================================================================

$ErrorActionPreference = 'Stop'
$base = Split-Path -Parent $PSScriptRoot
if (-not $base) { $base = Split-Path -Parent $MyInvocation.MyCommand.Definition | Split-Path -Parent }
Set-Location $base

# CSS Old -> New
$cssOld = @'
.topbar-title{font-size:14px; color:var(--txt2);}
.topbar-title strong{color:var(--txt); font-weight:600;}
'@

$cssNew = @'
.topbar-title{font-family:'JetBrains Mono',monospace; font-size:12px; color:var(--txt2); display:flex; align-items:center; gap:8px;}
.topbar-title .sep{color:var(--txt3); font-size:14px;}
.topbar-title .crumb{color:var(--txt); font-weight:700;}
.topbar-title strong{color:var(--txt); font-weight:600;}
'@

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
    # Já padronizadas individualmente (já tem o novo CSS)
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

    if ($content.Contains($cssOld)) {
        $content = $content.Replace($cssOld, $cssNew)
    }

    if ($content -ne $original) {
        Set-Content -Path $f.FullName -Value $content -Encoding UTF8 -NoNewline
        Write-Host "FIXED: $($f.Name)"
        $count++
    }
}

Write-Host ""
Write-Host "Topbar padronizada · $count arquivos modificados"
