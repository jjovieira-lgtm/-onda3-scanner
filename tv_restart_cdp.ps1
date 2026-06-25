# tv_restart_cdp.ps1
# Reinicia o TradingView Desktop com CDP (porta 9222) habilitado para uso pelo MCP do Claude.
# COMO USAR: Executar como ADMINISTRADOR antes de pedir ao Claude para acessar dados do TradingView.
#            Apos reiniciar, espere ~10 segundos antes de usar o MCP.
# NOTA: Nao e necessario para os scanners automaticos (GitHub Actions usa Yahoo Finance).
#       Use apenas para analises manuais via Claude + TradingView.

$tvPkg = "TradingView.Desktop_3.2.0.7916_x64__n534cwy3pjxzj"
$tvExe = "C:\Program Files\WindowsApps\$tvPkg\TradingView.exe"

# Verifica se o executavel existe
if (-not (Test-Path $tvExe)) {
    # Tenta encontrar versao instalada mais recente
    $pkgDir = Get-ChildItem "C:\Program Files\WindowsApps" -Filter "TradingView.Desktop*" -Directory -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($pkgDir) { $tvExe = Join-Path $pkgDir.FullName "TradingView.exe" }
}

if (-not (Test-Path $tvExe)) {
    Write-Host "ERRO: TradingView Desktop nao encontrado em WindowsApps." -ForegroundColor Red
    Write-Host "Instale via Microsoft Store e tente novamente."
    exit 1
}

Write-Host "Encerrando TradingView..." -ForegroundColor Yellow
Stop-Process -Name TradingView -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

Write-Host "Iniciando TradingView com CDP (porta 9222)..." -ForegroundColor Cyan
try {
    Start-Process $tvExe -ArgumentList "--remote-debugging-port=9222" -ErrorAction Stop
    Start-Sleep -Seconds 3
    Write-Host "TradingView iniciado. Aguarde ~10s para carregar e entao use o Claude." -ForegroundColor Green
    Write-Host "Porta CDP: 9222 (acesso local apenas)" -ForegroundColor Gray
} catch {
    Write-Host "AVISO: Falha ao iniciar diretamente ($($_))." -ForegroundColor Yellow
    Write-Host "Alternativa: feche o TradingView manualmente e use o atalho abaixo:"
    Write-Host "  $tvExe --remote-debugging-port=9222" -ForegroundColor White
}
