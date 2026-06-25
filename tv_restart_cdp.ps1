# tv_restart_cdp.ps1
# Reinicia o TradingView Desktop com CDP (porta 9222) para uso pelo MCP do Claude.
# Executar uma vez antes de usar "dados do TradingView" no Claude.
# Nao precisa de admin — usa IApplicationActivationManager (COM nativo do Windows).

param([int]$Port = 9222)

# Interface COM correta para passar args a apps da Windows Store (MSIX/AppX)
Add-Type @'
using System;
using System.Runtime.InteropServices;
public class TvCdpLauncher {
    [ComImport, Guid("45ba127d-10a8-46ea-8ab7-56ea9078943c"), ClassInterface(ClassInterfaceType.None)]
    class ApplicationActivationManager {}
    [ComImport, Guid("2e941141-7f97-4756-ba1d-9decde894a3d"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IApplicationActivationManager {
        uint ActivateApplication([MarshalAs(UnmanagedType.LPWStr)] string appUserModelId,
                                 [MarshalAs(UnmanagedType.LPWStr)] string arguments,
                                 int options, out uint processId);
        uint ActivateForFile([MarshalAs(UnmanagedType.LPWStr)] string a, IntPtr b,
                             [MarshalAs(UnmanagedType.LPWStr)] string c, out uint d);
        uint ActivateForProtocol([MarshalAs(UnmanagedType.LPWStr)] string a, IntPtr b, out uint c);
    }
    public static uint Launch(string aumid, string args) {
        var mgr = (IApplicationActivationManager)new ApplicationActivationManager();
        uint pid; mgr.ActivateApplication(aumid, args, 0, out pid); return pid;
    }
}
'@ -ErrorAction SilentlyContinue

$aumid = "TradingView.Desktop_n534cwy3pjxzj!TradingView.Desktop"

# 1. Encerrar instancia atual
Write-Host "Encerrando TradingView..." -ForegroundColor Yellow
Get-Process -Name TradingView -ErrorAction SilentlyContinue | Stop-Process -Force
$sw = [System.Diagnostics.Stopwatch]::StartNew()
while ((Get-Process -Name TradingView -ErrorAction SilentlyContinue) -and $sw.Elapsed.TotalSeconds -lt 8) {
    Start-Sleep -Milliseconds 400
}
Start-Sleep -Seconds 1

# 2. Reabrir com CDP
Write-Host "Iniciando TradingView com --remote-debugging-port=$Port..." -ForegroundColor Cyan
$newPid = [TvCdpLauncher]::Launch($aumid, "--remote-debugging-port=$Port")
Write-Host "  Processo iniciado (PID $newPid)" -ForegroundColor Gray

# 3. Aguardar carregamento e verificar porta
Write-Host "Aguardando carregamento (~15s)..." -ForegroundColor Gray
Start-Sleep -Seconds 15
try {
    $ver = (Invoke-WebRequest -Uri "http://localhost:$Port/json/version" -TimeoutSec 5 -ErrorAction Stop).Content | ConvertFrom-Json
    Write-Host ""
    Write-Host "CDP ATIVO na porta $Port!" -ForegroundColor Green
    Write-Host "  $($ver.Browser)" -ForegroundColor Gray
    Write-Host "  Pronto. Abra o Claude e use dados do TradingView normalmente." -ForegroundColor Green
} catch {
    Write-Host "Porta $Port ainda nao responde — aguarde mais 30s." -ForegroundColor Yellow
    Write-Host "Verifique: Invoke-WebRequest http://localhost:$Port/json/version" -ForegroundColor Gray
}
