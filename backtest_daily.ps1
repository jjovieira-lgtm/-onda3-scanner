# backtest_daily.ps1 - Valida sinais D-1 vs fechamento de hoje. Grava log acumulado.
# Uso: ./backtest_daily.ps1 -SemEmail -OutFile backtest_report.html
param([switch]$SemEmail, [string]$OutFile="")
$ErrorActionPreference = "SilentlyContinue"

$ptbr = [System.Globalization.CultureInfo]::GetCultureInfo("pt-BR")
$uaStr = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"

function Prev-TradingDay([DateTime]$d) {
    $p = $d.AddDays(-1)
    while ($p.DayOfWeek -eq "Saturday" -or $p.DayOfWeek -eq "Sunday") { $p = $p.AddDays(-1) }
    return $p
}

function Eval-Signal($dir, $pct) {
    if ([Math]::Abs($pct) -lt 0.15) { return "neutro" }
    if ($dir -eq "BUY" -or $dir -eq "alta")  { if ($pct -gt 0) { return "acerto" } else { return "erro" } }
    if ($dir -eq "SELL" -or $dir -eq "baixa") { if ($pct -lt 0) { return "acerto" } else { return "erro" } }
    return "neutro"
}

function Calc-Score($entries) {
    $c = @($entries | Where-Object { $_.res -eq "acerto" }).Count
    $w = @($entries | Where-Object { $_.res -eq "erro"   }).Count
    $n = @($entries | Where-Object { $_.res -eq "neutro" }).Count
    $active = $c + $w
    [PSCustomObject]@{ c=$c; w=$w; n=$n; t=($c+$w+$n); pct=if($active-gt 0){[Math]::Round($c/$active*100,1)}else{0.0} }
}

function Agg-Log($log, $nDays) {
    $recent = @($log | Sort-Object date -Descending | Select-Object -First $nDays)
    if ($recent.Count -eq 0) { return $null }
    $tot = @{ onda3_diario=@{c=0;w=0;n=0;t=0}; resumo_br=@{c=0;w=0;n=0;t=0}; resumo_us=@{c=0;w=0;n=0;t=0}; trifecta_br=@{c=0;w=0;n=0;t=0}; trifecta_us=@{c=0;w=0;n=0;t=0} }
    foreach ($e in $recent) {
        foreach ($s in @("onda3_diario","resumo_br","resumo_us","trifecta_br","trifecta_us")) {
            $sc = $e.scores.$s
            if ($sc) { $tot[$s].c+=$sc.c; $tot[$s].w+=$sc.w; $tot[$s].n+=$sc.n; $tot[$s].t+=$sc.t }
        }
    }
    $res = @{}
    foreach ($s in $tot.Keys) {
        $d = $tot[$s]; $active = $d.c+$d.w
        $res[$s] = [PSCustomObject]@{ c=$d.c; w=$d.w; n=$d.n; t=$d.t; pct=if($active-gt 0){[Math]::Round($d.c/$active*100,1)}else{0.0} }
    }
    @{ days=$recent.Count; from=$recent[-1].date; to=$recent[0].date; scores=$res }
}

function FmtPct($p) {
    if ([Math]::Abs($p) -lt 0.15) { return "<span style='color:#888'>~0,00%</span>" }
    $c = if ($p -gt 0) { "#1a7a3a" } else { "#c0392b" }
    "<span style='color:$c;font-weight:600'>$(if($p-gt 0){'+'}else{''})$($p.ToString('N2',$ptbr))%</span>"
}

function ScoreBar($sc, $label) {
    $pc = if ($sc.pct -ge 60) { "#1a7a3a" } elseif ($sc.pct -ge 40) { "#b7600a" } else { "#c0392b" }
    $w = [Math]::Max([int]$sc.pct, 0)
    "<div style='margin-bottom:10px'><span style='font-size:11px;font-weight:600'>$label</span><div style='display:flex;align-items:center;gap:8px;margin-top:2px'><div style='flex:1;background:#e8e8e8;border-radius:3px;height:5px'><div style='height:100%;background:$pc;width:$w%'></div></div><span style='color:$pc;font-weight:700;min-width:42px;text-align:right;font-size:12px'>$($sc.pct.ToString('N1',$ptbr))%</span><span style='color:#888;font-size:10px'>($($sc.c)&#10003; $($sc.w)&#10007; $($sc.n)~) de $($sc.t) sinais</span></div></div>"
}

function AggBlock($agg, $title, $icon) {
    if (-not $agg -or $agg.days -eq 0) { return "" }
    $rows = ""
    foreach ($s in @("onda3_diario","resumo_br","resumo_us","trifecta_br","trifecta_us")) {
        $nm = @{onda3_diario="Onda 3 Diario"; resumo_br="Resumo BR"; resumo_us="Resumo US"; trifecta_br="Trifecta BR"; trifecta_us="Trifecta US"}[$s]
        $sc = $agg.scores[$s]; if (-not $sc) { continue }
        $pc = if ($sc.pct -ge 60){"#1a7a3a"}elseif($sc.pct -ge 40){"#b7600a"}else{"#c0392b"}
        $rows += "<tr><td style='padding:3px 8px;font-size:11px'>$nm</td><td style='padding:3px 8px;font-weight:700;color:$pc;text-align:right'>$($sc.pct.ToString('N1',$ptbr))%</td><td style='padding:3px 8px;color:#888;font-size:10px'>$($sc.c)&#10003; $($sc.w)&#10007; $($sc.n)~</td><td style='padding:3px 8px;color:#888;font-size:10px'>$($sc.t) sinais</td></tr>"
    }
    "<div style='margin-top:18px;padding:12px 14px;background:#f0f7ff;border:1px solid #c8dff8;border-radius:6px'><div style='font-size:11px;font-weight:700;color:#0C447C;margin-bottom:8px'>$icon $title &mdash; $($agg.from) a $($agg.to) ($($agg.days) sess&otilde;es)</div><table width='100%'>$rows</table></div>"
}

function TableSection($entries, $title, $color, $ccy) {
    if ($entries.Count -eq 0) { return "" }
    $th = "<tr style='background:#f5f5f5'><th style='padding:5px 6px;text-align:left;font-size:10px;color:#666'>Papel</th><th style='padding:5px 6px;text-align:left;font-size:10px;color:#666'>Sinal</th><th style='padding:5px 6px;text-align:left;font-size:10px;color:#666'>Obs</th><th style='padding:5px 6px;text-align:right;font-size:10px;color:#666'>Preco D-1</th><th style='padding:5px 6px;text-align:right;font-size:10px;color:#666'>Preco D</th><th style='padding:5px 6px;text-align:right;font-size:10px;color:#666'>Var%</th><th style='padding:5px 6px;text-align:center;font-size:10px;color:#666'>OK?</th></tr>"
    $rows = ""
    foreach ($e in $entries) {
        $dClr = if ($e.dir -eq "BUY" -or $e.dir -eq "alta") { "#1a7a3a" } else { "#c0392b" }
        $dArr = if ($e.dir -eq "BUY" -or $e.dir -eq "alta") { "&#8593;" } else { "&#8595;" }
        $rBg  = if ($e.res -eq "acerto"){"rgba(26,122,58,0.07)"}elseif($e.res -eq "erro"){"rgba(192,57,43,0.07)"}else{""}
        $rIco = if ($e.res -eq "acerto"){"<span style='color:#1a7a3a;font-size:13px'>&#10003;</span>"}elseif($e.res -eq "erro"){"<span style='color:#c0392b;font-size:13px'>&#10007;</span>"}else{"<span style='color:#888'>~</span>"}
        $obs  = if ($e.obs){"<small style='color:#777'>$($e.obs)</small>"}elseif($e.verdict){"<small style='color:#777'>$($e.verdict)</small>"}else{""}
        $sig  = if ($e.conv){"$dArr <small style='color:#666'>$($e.conv)</small>"}else{"$dArr <small style='color:#666'>$($e.verdict)</small>"}
        $rows += "<tr style='border-bottom:0.5px solid #f0f0f0;background:$rBg'><td style='padding:5px 6px;font-weight:600'>$($e.t)</td><td style='padding:5px 6px'><span style='color:$dClr;font-weight:700'>$sig</span></td><td style='padding:5px 6px'>$obs</td><td style='padding:5px 6px;text-align:right;font-size:11px'>$ccy$($e.sp.ToString('N2',$ptbr))</td><td style='padding:5px 6px;text-align:right;font-size:11px'>$ccy$($e.vp.ToString('N2',$ptbr))</td><td style='padding:5px 6px;text-align:right'>$(FmtPct $e.pct)</td><td style='padding:5px 6px;text-align:center'>$rIco</td></tr>"
    }
    "<div style='margin-top:16px'><div style='font-size:12px;font-weight:700;color:$color;padding-left:8px;border-left:3px solid $color;margin-bottom:6px'>$title</div><table width='100%' style='border-collapse:collapse;border:1px solid #eee;font-size:12px'><thead>$th</thead><tbody>$rows</tbody></table></div>"
}

# ======================== MAIN ========================
# BRT = UTC-3, sem horario de verao desde 2019. Calcular explicitamente para
# evitar comportamento instavel do Get-Date com TZ= no pwsh do Ubuntu.
$now      = [DateTime]::UtcNow.AddHours(-3)
$todayBRT = $now.Date
$sigTD    = Prev-TradingDay $todayBRT
$sigDate  = $sigTD.ToString("yyyyMMdd")
$todayStr = $todayBRT.ToString("yyyy-MM-dd")
$dateStr  = $now.ToString("dd/MM/yyyy HH:mm")

$validDate = $sigTD  # validacao = fechamento do pregao dos sinais (D-1)
$validStr  = $validDate.ToString("yyyy-MM-dd")
Write-Host "[$dateStr] Backtest: sinais=$sigDate fechamento-validado=$validStr gerado-em=$todayStr"

# Ler sinais de D-1 (pregao anterior)
$fO3  = "signals/signals_${sigDate}_onda3.json"
$fBR  = "signals/signals_${sigDate}_resumo_br.json"
$fUS  = "signals/signals_${sigDate}_resumo_us.json"
function Read-SignalFile($path) {
    if (-not (Test-Path $path)) { return @() }
    try {
        $raw = Get-Content $path -Encoding UTF8 -Raw
        $parsed = $raw | ConvertFrom-Json
        return @($parsed | ForEach-Object { $_ })
    } catch { return @() }
}
$sigO3 = Read-SignalFile $fO3
$sigBR = Read-SignalFile $fBR
$sigUS = Read-SignalFile $fUS

if ($sigO3.Count + $sigBR.Count + $sigUS.Count -eq 0) {
    Write-Host "AVISO: Nenhum sinal em signals/*${sigDate}*.json. Encerrando."
    exit 0
}
Write-Host "Sinais: Onda3=$($sigO3.Count) BR=$($sigBR.Count) US=$($sigUS.Count)"

# Download precos Yahoo Finance v8 com crumb (obrigatorio desde 2023)
$allSyms = @()
foreach ($s in @($sigO3) + @($sigBR)) { if ($s.t) { $allSyms += "$($s.t).SA" } }
foreach ($s in $sigUS)                  { if ($s.t) { $allSyms += $s.t } }
$allSyms = @($allSyms | Select-Object -Unique)
Write-Host "Baixando $($allSyms.Count) precos (com crumb)..."

# Buscar precos via Yahoo Finance v8 (WebClient, compativel PS5.1, range=10d)
# Duas estrategias de validacao:
#   Swing (onda3 diario): sinal gerado apos fechamento D-1, validar vs D (hoje) -> cl[-1]
#   Day trade (resumo BR/US): sinal gerado no inicio de D-1, validar vs fechamento D-1 -> cl[-2]
$priceMapD  = @{}   # fechamento D (swing): cl[-1]
$priceMapD1 = @{}   # fechamento D-1 (day trade): cl[-2]
$dlTasks = @{}
foreach ($sym in $allSyms) {
    $url = "https://query2.finance.yahoo.com/v8/finance/chart/$sym`?interval=1d&range=10d"
    $wc = [System.Net.WebClient]::new()
    $wc.Headers.Add("User-Agent", $uaStr)
    $dlTasks[$sym] = $wc.DownloadStringTaskAsync($url)
}
foreach ($sym in @($dlTasks.Keys)) {
    try {
        $j  = $dlTasks[$sym].GetAwaiter().GetResult() | ConvertFrom-Json
        $cl = @($j.chart.result[0].indicators.quote[0].close | Where-Object { $null -ne $_ -and [double]$_ -gt 0 })
        $n  = $cl.Count; if ($n -lt 2) { continue }
        $vpD  = [Math]::Round([double]$cl[$n-1], 2)   # D: ultimo disponivel
        $vpD1 = [Math]::Round([double]$cl[$n-2], 2)   # D-1: pregao dos sinais
        if ($vpD  -gt 0) { $priceMapD[$sym]  = $vpD  }
        if ($vpD1 -gt 0) { $priceMapD1[$sym] = $vpD1 }
    } catch {}
}
Write-Host "Precos D: $($priceMapD.Count)/$($allSyms.Count) | D-1: $($priceMapD1.Count)/$($allSyms.Count)"

# Avaliar cada sinal
# $pmap = mapa de precos de validacao (D para swing, D-1 para day trade)
function Eval-Entries($signals, $isBR, $pmap) {
    $out = @()
    foreach ($sig in $signals) {
        if (-not $sig.t) { continue }
        $sym = if ($isBR) { "$($sig.t).SA" } else { $sig.t }
        $vp  = $pmap[$sym]; if ($null -eq $vp) { continue }
        $sp  = if ($sig.lc -and [double]$sig.lc -gt 0) { [Math]::Round([double]$sig.lc, 2) } else { 0 }
        $pct = if ($sp -gt 0) { [Math]::Round(($vp - $sp) / $sp * 100, 2) } else { 0.0 }
        $dir     = if ($sig.d)   { $sig.d }   else { "none" }
        $conv    = if ($sig.c)   { $sig.c }   else { $null }
        $obs     = if ($sig.obs) { $sig.obs } else { $null }
        $verdict = if ($sig.v)   { $sig.v }   else { $null }
        $out += [PSCustomObject]@{
            t=$sig.t; dir=$dir; conv=$conv; obs=$obs; verdict=$verdict
            sp=$sp; vp=$vp; pct=$pct; res=(Eval-Signal $dir $pct)
        }
    }
    return $out
}

# Onda3 (swing trade): valida sinais de D-1 vs fechamento de D (hoje)
# Resumo BR/US (day trade): valida sinais de D-1 vs fechamento de D-1 (mesmo pregao)
$o3Entries  = Eval-Entries $sigO3 $true  $priceMapD
$brEntries  = Eval-Entries $sigBR $true  $priceMapD1
$usEntries  = Eval-Entries $sigUS $false $priceMapD1

# Derivar entradas Trifecta (v = CONVERGENTE ou SO-TRIFECTA significa que o Trifecta estava ativo)
$trifBREntries = @($brEntries | Where-Object { $_.verdict -eq "CONVERGENTE" -or $_.verdict -eq "SO-TRIFECTA" })
$trifUSEntries = @($usEntries | Where-Object { $_.verdict -eq "CONVERGENTE" -or $_.verdict -eq "SO-TRIFECTA" })

$scO3     = Calc-Score $o3Entries
$scBR     = Calc-Score $brEntries
$scUS     = Calc-Score $usEntries
$scTrifBR = Calc-Score $trifBREntries
$scTrifUS = Calc-Score $trifUSEntries
Write-Host "Scores: O3=$($scO3.pct)% BR=$($scBR.pct)% US=$($scUS.pct)% TrifBR=$($scTrifBR.pct)% TrifUS=$($scTrifUS.pct)%"

# Ler/Atualizar log persistido
$logFile = "backtest_log.json"
$log = @()
if (Test-Path $logFile) { try { $log = @(Get-Content $logFile -Encoding UTF8 | ConvertFrom-Json) } catch {} }
$log = @($log | Where-Object { $_.date -ne $todayStr })
$logEntry = [PSCustomObject]@{
    date=$todayStr; signal_date=$sigDate
    n=[PSCustomObject]@{ o3=$o3Entries.Count; br=$brEntries.Count; us=$usEntries.Count; trifbr=$trifBREntries.Count; trifus=$trifUSEntries.Count }
    scores=[PSCustomObject]@{ onda3_diario=$scO3; resumo_br=$scBR; resumo_us=$scUS; trifecta_br=$scTrifBR; trifecta_us=$scTrifUS }
    entries=@(
        @($o3Entries | Select-Object @{n="strat";e={"onda3_diario"}},t,dir,conv,obs,@{n="verdict";e={$null}},sp,vp,pct,res) +
        @($brEntries | Select-Object @{n="strat";e={"resumo_br"}},t,dir,@{n="conv";e={$null}},@{n="obs";e={$null}},verdict,sp,vp,pct,res) +
        @($usEntries | Select-Object @{n="strat";e={"resumo_us"}},t,dir,@{n="conv";e={$null}},@{n="obs";e={$null}},verdict,sp,vp,pct,res)
    )
}
$log = @($log) + @($logEntry)
($log | ConvertTo-Json -Depth 10 -Compress) | Out-File $logFile -Encoding UTF8 -NoNewline
Write-Host "Log: $($log.Count) entradas -> $logFile"

# Estatisticas acumuladas (semanal ~5 sessoes, quinzenal ~10 sessoes)
$wk5  = Agg-Log $log 5
$bwk10 = Agg-Log $log 10
$isFriday    = $now.DayOfWeek -eq "Friday"
$hasWeekly   = $wk5   -and $wk5.days   -ge 3
$hasBiweekly = $bwk10 -and $bwk10.days -ge 8

# ---- Montar HTML ----
$totalSinais = $o3Entries.Count + $brEntries.Count + $usEntries.Count

$dLabel = $sigTD.ToString('dd/MM')
$secO3     = TableSection $o3Entries     "Onda 3 SWING TRADE (Diario) — sinal $dLabel vs fechamento $($todayBRT.ToString('dd/MM'))"        "#1a1a2e" "R$ "
$secBR     = TableSection $brEntries     "Resumo Convergencia BR — day trade $dLabel (abertura vs fechamento)" "#2a1e3e" "R$ "
$secUS     = TableSection $usEntries     "Resumo Convergencia US — day trade $dLabel (abertura vs fechamento)" "#1e3e2a" "US$ "
$secTrifBR = TableSection $trifBREntries "Trifecta BR (Convergente+Exclusivo) — day trade $dLabel"  "#2a3e1e" "R$ "
$secTrifUS = TableSection $trifUSEntries "Trifecta US (Convergente+Exclusivo) — day trade $dLabel"  "#1e2e3e" "US$ "
$secWk     = if ($hasWeekly)   { AggBlock $wk5   "Resumo Semanal (ultimas 5 sessoes)"    "&#128197;" } else { "" }
$secBwk    = if ($hasBiweekly) { AggBlock $bwk10 "Resumo Quinzenal (ultimas 10 sessoes)" "&#128198;" } else { "" }

$htmlBody = @"
<html><head><meta charset='UTF-8'><title>Backtest $dateStr</title></head>
<body style='font-family:Arial,sans-serif;font-size:12px;color:#222;max-width:780px;margin:0 auto;padding:16px'>
<table width='100%' style='background:#1a2a3a;border-radius:6px;padding:14px 18px;margin-bottom:16px'><tr><td>
<span style='font-size:17px;font-weight:700;color:#fff'>&#128202; Backtest Di&aacute;rio</span><br>
<span style='font-size:11px;color:#aac4ff'><b style='color:#ffe8a0'>Pregão: $($sigTD.ToString('dd/MM/yyyy'))</b> &nbsp;|&nbsp; Fechamento validado: $($validDate.ToString('dd/MM/yyyy')) &nbsp;|&nbsp; Backtest gerado: $dateStr (BRT) &nbsp;|&nbsp; $totalSinais sinais avaliados</span>
</td></tr></table>
<div style='padding:12px 16px;background:#f9f9f9;border:1px solid #e0e0e0;border-radius:6px;margin-bottom:16px'>
<div style='font-size:11px;font-weight:700;color:#333;margin-bottom:10px;text-transform:uppercase;letter-spacing:0.4px'>Assertividade de hoje</div>
$(ScoreBar $scO3     'Onda 3 SWING TRADE (Diario)')
$(ScoreBar $scBR     'Resumo Convergencia BR (Intradiario)')
$(ScoreBar $scUS     'Resumo Convergencia US (Intradiario)')
$(ScoreBar $scTrifBR 'Trifecta BR (Velez)')
$(ScoreBar $scTrifUS 'Trifecta US (Velez)')
</div>
$secO3 $secBR $secUS $secTrifBR $secTrifUS $secWk $secBwk
<p style='font-size:10px;color:#aaa;margin-top:18px;text-align:center'>Backtest autom&aacute;tico &mdash; Claude Code | Yahoo Finance | jjovieira@gmail.com</p>
</body></html>
"@

if ($OutFile -ne "") { $htmlFile = $OutFile } else { $htmlFile = Join-Path ([System.IO.Path]::GetTempPath()) "backtest_$(Get-Date -Format 'yyyyMMdd_HHmm').html" }
$htmlBody | Out-File $htmlFile -Encoding UTF8
Write-Host "HTML: $htmlFile"

if ($OutFile -ne "") {
    $titleWeek = if ($isFriday -and $hasWeekly) { "Semanal " } else { "" }
    $subj = "[Backtest ${titleWeek}$($sigTD.ToString('dd/MM'))] O3:$($scO3.pct)% BR:$($scBR.pct)% US:$($scUS.pct)% TBR:$($scTrifBR.pct)% TUS:$($scTrifUS.pct)%"
    $subj | Out-File "backtest_subject.txt" -Encoding UTF8 -NoNewline

    # Telegram
    $eB=[char]::ConvertFromUtf32(0x1F4CA);$eG=[char]::ConvertFromUtf32(0x1F7E2);$eR=[char]::ConvertFromUtf32(0x1F534);$eY=[char]::ConvertFromUtf32(0x1F7E1)
    $eW=[char]::ConvertFromUtf32(0x1F4C5);$eQ=[char]::ConvertFromUtf32(0x1F4C6)
    function TgLine($sc,$label){
        $e=if($sc.pct-ge 60){$eG}elseif($sc.pct-ge 40){$eY}else{$eR}
        "$e <b>$label</b>: $($sc.pct)% ($($sc.c)&#10003; $($sc.w)&#10007; $($sc.n)~)"
    }
    $tg=@()
    $tg+="$eB <b>Backtest Pregão $($sigTD.ToString('dd/MM/yyyy'))</b>"
    $tg+="Fechamento validado: $($validDate.ToString('dd/MM')) | $totalSinais sinais | Log: $($log.Count) sessoes"
    $tg+=""
    $tg+=TgLine $scO3     "Onda 3 Diario"
    $tg+=TgLine $scBR     "Resumo BR"
    $tg+=TgLine $scUS     "Resumo US"
    $tg+=TgLine $scTrifBR "Trifecta BR"
    $tg+=TgLine $scTrifUS "Trifecta US"
    if ($hasWeekly) {
        $tg+="";$tg+="$eW <b>Ultimas 5 sessoes:</b>"
        foreach ($s in @("onda3_diario","resumo_br","resumo_us","trifecta_br","trifecta_us")) {
            $nm=@{onda3_diario="O3";resumo_br="BR";resumo_us="US";trifecta_br="TrifBR";trifecta_us="TrifUS"}[$s];$sc=$wk5.scores[$s]
            if($sc){$tg+="  $nm $($sc.pct)% ($($sc.c)/$($sc.c+$sc.w))"}
        }
    }
    if ($hasBiweekly) {
        $tg+="";$tg+="$eQ <b>Ultimas 10 sessoes:</b>"
        foreach ($s in @("onda3_diario","resumo_br","resumo_us","trifecta_br","trifecta_us")) {
            $nm=@{onda3_diario="O3";resumo_br="BR";resumo_us="US";trifecta_br="TrifBR";trifecta_us="TrifUS"}[$s];$sc=$bwk10.scores[$s]
            if($sc){$tg+="  $nm $($sc.pct)% ($($sc.c)/$($sc.c+$sc.w))"}
        }
    }
    ($tg -join "`n") | Out-File "backtest_telegram.txt" -Encoding UTF8 -NoNewline
    Write-Host "Telegram: backtest_telegram.txt"
}

if (-not $SemEmail) {
    $credFile = Join-Path $env:USERPROFILE "Downloads/.onda3_cred.xml"
    if (Test-Path $credFile) {
        try {
            $cred = Import-Clixml $credFile
            $subj = "[Backtest $($sigTD.ToString('dd/MM'))] O3:$($scO3.pct)% BR:$($scBR.pct)% US:$($scUS.pct)% TBR:$($scTrifBR.pct)% TUS:$($scTrifUS.pct)%"
            Send-MailMessage -From $cred.UserName -To "jjovieira@gmail.com" -Subject $subj -Body $htmlBody -BodyAsHtml -SmtpServer "smtp.gmail.com" -Port 587 -UseSsl -Credential $cred -Encoding UTF8
            Write-Host "[OK] Email enviado"
        } catch { Write-Host "[ERRO] SMTP: $_" }
    }
}
