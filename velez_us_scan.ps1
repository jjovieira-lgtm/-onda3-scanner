# velez_us_scan.ps1 - Scanner Barra Elefante (Oliver Velez) - mercado US
# 19 papeis US | 1m + 5m + 15m | Vela Elefante: corpo>=70% + corpo>=1.3*ATR(100) + filtro tendencia (SMA8)
# Logica exata do indicador "VELA ELEFANTE DE OLIVER VELEZ" (Dreadblitz, Pine v4).
# Envio email+Telegram a cada 2h a partir da abertura da NYSE (9:30 ET): 9:45,11:45,13:45,15:45,17:45 ET.
# Para email local: reaproveita .onda3_cred.xml (mesmo setup dos outros scanners).
param([switch]$SemEmail,[string]$OutFile="")
$ErrorActionPreference = "SilentlyContinue"

# ---- Parametros da estrategia (ajustaveis) ----
$BODY_PCT = 70.0    # % minimo do corpo sobre o range (PDCM)
$ATR_FAC  = 1.3     # fator: corpo >= ATR_FAC * ATR(ATR_LEN) (FDB)
$ATR_LEN  = 100     # periodo do ATR (CDBA)
$SMA_FAST = 8       # media rapida para o filtro de tendencia
$USE_FILTER = $true # CON FILTRADO DE TENDENCIA (so elefantes a favor da direcao da SMA rapida)
# lookback (barras fechadas vasculhadas por TF, p/ nao perder elefante entre varreduras de 2h)
$LB = @{ "1m"=30; "5m"=12; "15m"=8 }

function Get-SMA([double[]]$a,[int]$p){
    $n=$a.Length;$s=[double[]]::new($n);$sum=0.0
    for($i=0;$i-lt$n;$i++){
        $sum+=$a[$i]; if($i-ge$p){$sum-=$a[$i-$p]}
        if($i-ge$p-1){$s[$i]=$sum/$p}else{$s[$i]=[double]::NaN}
    }
    return ,$s
}
function Get-ATR([double[]]$h,[double[]]$l,[double[]]$c,[int]$p){
    $n=$h.Length;$atr=[double[]]::new($n);for($i=0;$i-lt$n;$i++){$atr[$i]=[double]::NaN}
    if($n-lt $p+1){return ,$atr}
    $tr=[double[]]::new($n)
    for($i=0;$i-lt$n;$i++){
        if($i-eq 0){$tr[$i]=$h[$i]-$l[$i]}
        else{$a=$h[$i]-$l[$i];$b=[Math]::Abs($h[$i]-$c[$i-1]);$d=[Math]::Abs($l[$i]-$c[$i-1]);$tr[$i]=[Math]::Max($a,[Math]::Max($b,$d))}
    }
    $sum=0.0;for($i=0;$i-lt$p;$i++){$sum+=$tr[$i]};$atr[$p-1]=$sum/$p
    for($i=$p;$i-lt$n;$i++){$atr[$i]=($atr[$i-1]*($p-1)+$tr[$i])/$p}
    return ,$atr
}
# Detecta a elefante mais recente dentro do lookback. Retorna direcao + extremos + forca (corpo/ATR).
function Detect-Eleph([double[]]$o,[double[]]$h,[double[]]$l,[double[]]$c,[int]$lookback){
    $n=$c.Length
    if($n-lt ($ATR_LEN+2)){return @{Dir="NONE"}}
    $atr=Get-ATR $h $l $c $ATR_LEN
    $sma=if($USE_FILTER){Get-SMA $c $SMA_FAST}else{$null}
    $stop=[Math]::Max($ATR_LEN+1,$n-$lookback)
    for($i=$n-1;$i-ge$stop;$i--){
        $rng=$h[$i]-$l[$i];if($rng-le 0){continue}
        $body=[Math]::Abs($o[$i]-$c[$i]);$bp=$body/$rng*100;if($bp-lt$BODY_PCT){continue}
        $ap=$atr[$i-1];if([double]::IsNaN($ap)-or$ap-le 0){continue}
        if($body-lt $ATR_FAC*$ap){continue}
        $dir=if($c[$i]-gt$o[$i]){"BULL"}elseif($c[$i]-lt$o[$i]){"BEAR"}else{continue}
        if($USE_FILTER){
            $sf=$sma[$i];$sfp=$sma[$i-1]
            if([double]::IsNaN($sf)-or[double]::IsNaN($sfp)){continue}
            if($dir-eq"BULL"-and -not($sf-gt$sfp)){continue}
            if($dir-eq"BEAR"-and -not($sf-lt$sfp)){continue}
        }
        return @{Dir=$dir;BarsAgo=($n-1-$i);High=[Math]::Round($h[$i],2);Low=[Math]::Round($l[$i],2);Close=[Math]::Round($c[$i],2);Strength=[Math]::Round($body/$ap,2)}
    }
    return @{Dir="NONE"}
}
function Classify($e1,$e5,$e15){
    $dirs=@($e1.Dir,$e5.Dir,$e15.Dir)
    $bull=($dirs|Where-Object{$_-eq"BULL"}).Count
    $bear=($dirs|Where-Object{$_-eq"BEAR"}).Count
    if($bull-gt 0-and$bear-gt 0){return @{Conv="OPOSTO";Dir="NONE";Score=0}}
    if($bull-gt 0){$tier=if($bull-ge 3){"3-TF"}elseif($bull-ge 2){"2-TF"}else{"1-TF"};return @{Conv=$tier;Dir="BULL";Score=$bull}}
    if($bear-gt 0){$tier=if($bear-ge 3){"3-TF"}elseif($bear-ge 2){"2-TF"}else{"1-TF"};return @{Conv=$tier;Dir="BEAR";Score=$bear}}
    return @{Conv="-";Dir="NONE";Score=0}
}

# Mapa ticker (exibicao) -> simbolo Yahoo. SPX = indice ^GSPC.
$tickers=@(
    @{T="INTC";Y="INTC"},@{T="NVDA";Y="NVDA"},@{T="NFLX";Y="NFLX"},@{T="AMZN";Y="AMZN"},
    @{T="MU";Y="MU"},@{T="TSLA";Y="TSLA"},@{T="MSFT";Y="MSFT"},@{T="GOOG";Y="GOOG"},
    @{T="AMD";Y="AMD"},@{T="META";Y="META"},@{T="AAPL";Y="AAPL"},@{T="DELL";Y="DELL"},
    @{T="SPCX";Y="SPCX"},@{T="XOM";Y="XOM"},@{T="JPM";Y="JPM"},@{T="V";Y="V"},
    @{T="MA";Y="MA"},@{T="COST";Y="COST"},@{T="WMT";Y="WMT"}
)
$baseUrl="https://query1.finance.yahoo.com/v8/finance/chart"
$uaStr="Mozilla/5.0 (Windows NT 10.0; Win64; x64)"
$enus=[System.Globalization.CultureInfo]::GetCultureInfo("en-US")
$dateStr=(Get-Date -Format "dd/MM/yyyy HH:mm")
$dateFile=(Get-Date -Format "yyyyMMdd_HHmm")
$hourNow=(Get-Date).Hour
$readLabel=if($hourNow-lt 10){"Abertura"}elseif($hourNow-ge 16){"Fechamento"}else{"Intraday"}
Write-Host "[$dateStr] Scanner Velez US (barra elefante) iniciado para $($tickers.Count) papeis... [$readLabel]"
$timer=[System.Diagnostics.Stopwatch]::StartNew()

$dlMap=@{}
foreach($tk in $tickers){
    $sym=$tk.Y -replace '\^','%5E'
    foreach($iv in @("1m","5m","15m")){
        $rng=if($iv-eq"1m"){"5d"}elseif($iv-eq"5m"){"30d"}else{"60d"}
        $key="${iv}_$($tk.T)"
        $wc=[System.Net.WebClient]::new();$wc.Headers.Add("User-Agent",$uaStr)
        $url="$baseUrl/$sym" + "?interval=$iv" + "&range=$rng" + "&includePrePost=false"
        $dlMap[$key]=$wc.DownloadStringTaskAsync($url)
    }
}
$rawMap=@{}
foreach($key in $dlMap.Keys){
    try{$json=$dlMap[$key].GetAwaiter().GetResult();$parsed=$json|ConvertFrom-Json;$ch=$parsed.chart.result[0];$rawMap[$key]=@{q=$ch.indicators.quote[0];n=$ch.timestamp.Count}}catch{$rawMap[$key]=$null}
}
$timer.Stop()
$okCount=($rawMap.Keys|Where-Object{$rawMap[$_]-ne$null}).Count
Write-Host "Download: $($timer.Elapsed.TotalSeconds.ToString("F1"))s | $okCount/$($dlMap.Count) ok"

# Processa cada TF: monta arrays OHLC e detecta elefante
function Build-OHLC($rd){
    $nn=$rd.n;$aO=[double[]]::new($nn);$aC=[double[]]::new($nn);$aH=[double[]]::new($nn);$aL=[double[]]::new($nn)
    for($i=0;$i-lt$nn;$i++){
        $ov=$rd.q.open[$i];$cv=$rd.q.close[$i];$hv=$rd.q.high[$i];$lv=$rd.q.low[$i]
        $aC[$i]=if($null-eq$cv-or[double]$cv-le 0){if($i-gt 0){$aC[$i-1]}else{0.0}}else{[double]$cv}
        $aO[$i]=if($null-eq$ov-or[double]$ov-le 0){$aC[$i]}else{[double]$ov}
        $aH[$i]=if($null-eq$hv-or[double]$hv-le 0){$aC[$i]}else{[double]$hv}
        $aL[$i]=if($null-eq$lv-or[double]$lv-le 0){$aC[$i]}else{[double]$lv}
    }
    return @{O=$aO;H=$aH;L=$aL;C=$aC;N=$nn}
}

$results=@()
foreach($tk in $tickers){
    $t=$tk.T
    $ev=@{}
    $lastC=0.0
    foreach($iv in @("1m","5m","15m")){
        $rd=$rawMap["${iv}_$t"]
        if($rd){
            $b=Build-OHLC $rd
            $ev[$iv]=Detect-Eleph $b.O $b.H $b.L $b.C $LB[$iv]
            if($iv-eq"1m"-and$b.N-gt 0){$lastC=$b.C[$b.N-1]}
        }else{$ev[$iv]=@{Dir="NONE"}}
    }
    if($lastC-le 0){foreach($iv in @("5m","15m")){$rd=$rawMap["${iv}_$t"];if($rd-and$lastC-le 0){$b=Build-OHLC $rd;if($b.N-gt 0){$lastC=$b.C[$b.N-1]}}}}
    $e1=$ev["1m"];$e5=$ev["5m"];$e15=$ev["15m"]
    $cls=Classify $e1 $e5 $e15
    # elefante primaria p/ gatilho/stop: TF mais longo alinhado a direcao
    $prim=$null;$primTF=""
    if($cls.Dir-ne"NONE"){
        foreach($pair in @(@($e15,"15m"),@($e5,"5m"),@($e1,"1m"))){ if($pair[0].Dir-eq$cls.Dir){$prim=$pair[0];$primTF=$pair[1];break} }
    }
    $gat=0.0;$stp=0.0;$forca=0.0;$barsAgo=0;$riscoPct=0.0
    if($prim){
        if($cls.Dir-eq"BULL"){$gat=$prim.High;$stp=$prim.Low}else{$gat=$prim.Low;$stp=$prim.High}
        $forca=$prim.Strength;$barsAgo=$prim.BarsAgo
        if($gat-ne 0){$riscoPct=[Math]::Round([Math]::Abs($gat-$stp)/$gat*100,2)}
    }
    $obs=if($cls.Conv-eq"OPOSTO"){"Conflito de TFs"}
        elseif($cls.Dir-eq"NONE"){"Sem elefante"}
        else{$d=if($cls.Dir-eq"BULL"){"alta"}else{"baixa"};"Elefante $d $primTF (${forca}x ATR, ha $barsAgo barras, risco $riscoPct%)"}
    $results+=[PSCustomObject]@{
        T=$t;Conv=$cls.Conv;Dir=$cls.Dir;Score=$cls.Score
        E1=$e1.Dir;E5=$e5.Dir;E15=$e15.Dir
        F1=$e1.Strength;F5=$e5.Strength;F15=$e15.Strength
        LC=[Math]::Round($lastC,2);PrimTF=$primTF;Gat=$gat;Stp=$stp;Forca=$forca;BarsAgo=$barsAgo;Risco=$riscoPct;OBS=$obs
    }
}
# ordena: convergencia (Score desc), depois forca da elefante primaria
$sorted=$results|Sort-Object @{Expression="Score";Descending=$true},@{Expression="Forca";Descending=$true}

$nBull=@($sorted|Where-Object{$_.Dir-eq"BULL"}).Count
$nBear=@($sorted|Where-Object{$_.Dir-eq"BEAR"}).Count
$nConv=@($sorted|Where-Object{$_.Score-ge 2}).Count
$nOpp=@($sorted|Where-Object{$_.Conv-eq"OPOSTO"}).Count

# ---- HTML ----
function PxFmt($v){ if($v-eq 0){return "&mdash;"}; return "US`$ "+([double]$v).ToString("N2",$enus) }
function ElephBadge($dir,$forca){
    if($dir-eq"BULL"){return "<span style='background:#C0DD97;color:#27500A;font-size:9px;font-weight:600;padding:1px 4px;border-radius:2px' title='$forca x ATR'>&#128024;&#9650;</span>"}
    elseif($dir-eq"BEAR"){return "<span style='background:#F7C1C1;color:#791F1F;font-size:9px;font-weight:600;padding:1px 4px;border-radius:2px' title='$forca x ATR'>&#128024;&#9660;</span>"}
    else{return "<span style='color:#bbb'>-</span>"}
}
$rows=""
$lastTier=99
$tierLabel=@{3="3-TF &mdash; Elefante nos 3 tempos";2="2-TF &mdash; Convergencia em 2 tempos";1="1-TF &mdash; Sinal isolado";0="Sem elefante / Conflito"}
$rankNum=0
foreach($r in $sorted){
    $tier=if($r.Score-ge 3){3}elseif($r.Score-ge 2){2}elseif($r.Score-ge 1){1}else{0}
    if($tier-ne$lastTier){
        $rows+="<tr><td colspan='12' style='background:#f0f0f0;font-size:10px;font-weight:600;color:#555;padding:6px 8px;letter-spacing:0.5px;text-transform:uppercase'>$($tierLabel[$tier])</td></tr>"
        $lastTier=$tier
    }
    $rankNum++
    $arrow=if($r.Dir-eq"BULL"){"<span style='color:#1a7a3a;font-weight:700'>&uarr;</span>"}elseif($r.Dir-eq"BEAR"){"<span style='color:#c0392b;font-weight:700'>&darr;</span>"}else{"<span style='color:#888'>&harr;</span>"}
    $convBg=switch($r.Conv){"3-TF"{"#FAC775"};"2-TF"{"#FAC775"};"1-TF"{"#B5D4F4"};"OPOSTO"{"#F0997B"};default{"#ddd"}}
    $convColor=switch($r.Conv){"3-TF"{"#633806"};"2-TF"{"#633806"};"1-TF"{"#0C447C"};"OPOSTO"{"#4A1B0C"};default{"#555"}}
    $convBadge="<span style='background:$convBg;color:$convColor;font-size:9px;font-weight:600;padding:2px 5px;border-radius:2px'>$($r.Conv)</span>"
    $gatCell=if($r.Gat-ne 0){"$(PxFmt $r.Gat) <small style='color:#999'>($($r.PrimTF))</small>"}else{"&mdash;"}
    $stpCell=PxFmt $r.Stp
    $forcaCell=if($r.Forca-ne 0){"<span style='font-weight:600'>$($r.Forca)x</span>"}else{"&mdash;"}
    $rowBg=if($r.Score-ge 2){"background:rgba(250,199,117,0.08);"}elseif($r.Conv-eq"OPOSTO"){"background:rgba(240,153,123,0.07);"}else{""}
    $rows+="<tr style='border-bottom:1px solid #f0f0f0;$rowBg'><td style='padding:4px 6px;color:#999;font-size:10px'>$rankNum</td><td style='padding:4px 6px;font-weight:600;font-size:12px'>$($r.T)</td><td style='padding:4px 6px;font-size:10px;color:#555'>$($r.OBS)</td><td style='padding:4px 4px;text-align:center'>$arrow</td><td style='padding:4px 3px'>$(ElephBadge $r.E1 $r.F1)</td><td style='padding:4px 3px'>$(ElephBadge $r.E5 $r.F5)</td><td style='padding:4px 3px'>$(ElephBadge $r.E15 $r.F15)</td><td style='padding:4px 6px'>$convBadge</td><td style='padding:4px 6px;text-align:right;font-size:11px'>$(PxFmt $r.LC)</td><td style='padding:4px 6px;font-size:10px;text-align:right'>$gatCell</td><td style='padding:4px 6px;font-size:10px;text-align:right;color:#c0392b'>$stpCell</td><td style='padding:4px 6px;text-align:right;font-size:10px'>$forcaCell</td></tr>"
}

function JoinT($arr){ if($arr.Count-eq 0){return "nenhum"}; return ($arr -join ", ") }
$dqBull2 = @($sorted|Where-Object{$_.Dir-eq"BULL"-and$_.Score-ge 2})
$dqBear2 = @($sorted|Where-Object{$_.Dir-eq"BEAR"-and$_.Score-ge 2})
$dqStrong= @($sorted|Where-Object{$_.Dir-ne"NONE"}|Sort-Object Forca -Descending|Select-Object -First 3)
$dqBull1 = @($sorted|Where-Object{$_.Dir-eq"BULL"-and$_.Score-eq 1})
$dqBear1 = @($sorted|Where-Object{$_.Dir-eq"BEAR"-and$_.Score-eq 1})
$dqOpp   = @($sorted|Where-Object{$_.Conv-eq"OPOSTO"})
$dqLines=@()
if($dqBull2.Count-gt 0){$dqLines+="<div style='margin-bottom:5px'><span style='color:#1a7a3a;font-weight:700'>Elefantes de ALTA (multi-TF): </span>$(JoinT ($dqBull2|ForEach-Object{ ""$($_.T) ($($_.Conv), entrada $(PxFmt $_.Gat))"" })) &mdash; comprar no rompimento da maxima, stop na minima.</div>"}
if($dqBear2.Count-gt 0){$dqLines+="<div style='margin-bottom:5px'><span style='color:#c0392b;font-weight:700'>Elefantes de BAIXA (multi-TF): </span>$(JoinT ($dqBear2|ForEach-Object{ ""$($_.T) ($($_.Conv), entrada $(PxFmt $_.Gat))"" })) &mdash; vender no rompimento da minima, stop na maxima.</div>"}
if($dqStrong.Count-gt 0){$dqLines+="<div style='margin-bottom:5px'><span style='color:#9b6000;font-weight:700'>Elefantes mais fortes (corpo/ATR): </span>$(JoinT ($dqStrong|ForEach-Object{ ""$($_.T) ($($_.Forca)x, $($_.PrimTF))"" })).</div>"}
if($dqBull1.Count-gt 0-or$dqBear1.Count-gt 0){$dqLines+="<div style='margin-bottom:5px'><span style='color:#555;font-weight:700'>Sinais isolados (1-TF): </span>alta: $(JoinT ($dqBull1|ForEach-Object{$_.T})) | baixa: $(JoinT ($dqBear1|ForEach-Object{$_.T})).</div>"}
if($dqOpp.Count-gt 0){$dqLines+="<div style='margin-bottom:5px'><span style='color:#7a2c2c;font-weight:700'>Conflito de TFs (aguardar): </span>$(JoinT ($dqOpp|ForEach-Object{$_.T})).</div>"}
$dqLines+="<div><span style='color:#333;font-weight:700'>Resumo: </span>Alta=$nBull, Baixa=$nBear, Convergentes(>=2TF)=$nConv, Conflitos=$nOpp.</div>"
$destaques="<div style='margin-top:14px;padding:12px 14px;background:#fbf7ef;border:1px solid #f0e2c8;border-radius:6px'><div style='font-size:11px;font-weight:700;color:#633806;margin-bottom:8px;text-transform:uppercase;letter-spacing:0.4px'>Destaques da varredura</div><div style='font-size:11px;color:#333;line-height:1.7'>$($dqLines -join '')</div></div>"

$htmlBody="<html><head><meta charset='UTF-8'><title>Scanner Barra Elefante US</title></head><body style='font-family:Arial,sans-serif;font-size:12px;color:#222;max-width:820px;margin:0 auto;padding:16px'><table width='100%' style='background:#1e2b1e;border-radius:6px;padding:14px 18px;margin-bottom:14px'><tr><td><span style='font-size:17px;font-weight:700;color:#fff'>&#128024; Scanner Barra Elefante &mdash; EUA</span> <span style='background:#FAC775;color:#633806;padding:1px 6px;border-radius:3px;font-size:10px;font-weight:700'>$readLabel</span><br><span style='font-size:11px;color:#bfe3bf'>$dateStr | M&eacute;todo Oliver Velez | $($tickers.Count) pap&eacute;is US | 1m + 5m + 15m | corpo&ge;70% + &ge;1,3&times;ATR(100) + filtro SMA8</span></td><td style='text-align:right;vertical-align:top'><span style='background:#C0DD97;color:#27500A;padding:2px 7px;border-radius:3px;font-size:10px;font-weight:600'>Alta: $nBull</span>&nbsp;<span style='background:#F7C1C1;color:#791F1F;padding:2px 7px;border-radius:3px;font-size:10px;font-weight:600'>Baixa: $nBear</span></td></tr></table><table width='100%' cellspacing='0' cellpadding='0' style='border-collapse:collapse;border:1px solid #e8e8e8'><thead><tr style='background:#f8f8f8;border-bottom:2px solid #e0e0e0'><th style='padding:5px 6px;font-size:10px;color:#666;text-align:left;width:22px'>#</th><th style='padding:5px 6px;font-size:10px;color:#666;text-align:left;width:48px'>Papel</th><th style='padding:5px 6px;font-size:10px;color:#666;text-align:left;width:200px'>Obs.</th><th style='padding:5px 4px;font-size:10px;color:#666;width:14px'></th><th style='padding:5px 3px;font-size:10px;color:#666;text-align:left;width:34px'>1m</th><th style='padding:5px 3px;font-size:10px;color:#666;text-align:left;width:34px'>5m</th><th style='padding:5px 3px;font-size:10px;color:#666;text-align:left;width:34px'>15m</th><th style='padding:5px 6px;font-size:10px;color:#666;text-align:left;width:46px'>Conv.</th><th style='padding:5px 6px;font-size:10px;color:#666;text-align:right;width:74px'>Pre&ccedil;o</th><th style='padding:5px 6px;font-size:10px;color:#666;text-align:right;width:88px'>Gatilho</th><th style='padding:5px 6px;font-size:10px;color:#666;text-align:right;width:74px'>Stop</th><th style='padding:5px 6px;font-size:10px;color:#666;text-align:right;width:42px'>For&ccedil;a</th></tr></thead><tbody>$rows</tbody></table>$destaques<div style='margin-top:14px;padding:10px 12px;background:#f9f9f9;border-radius:4px;font-size:10px;color:#555;line-height:1.9'><strong>Legenda:</strong><br><strong>Barra Elefante &mdash;</strong> candle de corpo cheio (&ge;70% do range) e grande (&ge;1,3&times;ATR de 100 barras). &#128024;&#9650;=elefante de alta | &#128024;&#9660;=elefante de baixa. For&ccedil;a = corpo &divide; ATR (quanto maior, mais dominante).<br><strong>Filtro de tend&ecirc;ncia &mdash;</strong> s&oacute; conta o elefante a favor da dire&ccedil;&atilde;o da m&eacute;dia r&aacute;pida (SMA $SMA_FAST).<br><strong>Converg&ecirc;ncia &mdash;</strong> 3-TF=elefante mesma dire&ccedil;&atilde;o nos 3 tempos | 2-TF=em 2 | 1-TF=isolado | OPOSTO=tempos conflitantes.<br><strong>Opera&ccedil;&atilde;o (Oliver Velez) &mdash;</strong> Gatilho=rompimento do extremo da elefante (m&aacute;xima p/ compra, m&iacute;nima p/ venda) | Stop=extremo oposto da mesma barra. Aten&ccedil;&atilde;o: em elefantes grandes o stop fica largo.</div><p style='font-size:10px;color:#aaa;margin-top:10px;text-align:center'>Scanner Barra Elefante (Oliver Velez) &mdash; EUA | Claude Code | Dados: Yahoo Finance | jjovieira@gmail.com</p></body></html>"

if($OutFile -ne ""){$htmlFile=$OutFile}else{$htmlFile=Join-Path $env:USERPROFILE "Downloads\velez_us_report_$dateFile.html"}
$htmlBody|Out-File $htmlFile -Encoding UTF8
Write-Host "HTML salvo: $htmlFile"
if($OutFile -ne ""){
    "[Velez US] $readLabel $dateStr ET | Alta:$nBull Baixa:$nBear" | Out-File "velez_us_subject.txt" -Encoding UTF8 -NoNewline;Write-Host "Subject: velez_us_subject.txt"
    $eE=[char]::ConvertFromUtf32(0x1F418);$eC=[char]::ConvertFromUtf32(0x1F7E2);$eV=[char]::ConvertFromUtf32(0x1F534);$eS=[char]::ConvertFromUtf32(0x1F4AA);$eX=[char]::ConvertFromUtf32(0x26A0);$eM=[char]::ConvertFromUtf32(0x1F4E7)
    $tg=@()
    $tg+="<b>$eE Barra Elefante US ($readLabel) - $dateStr</b>"
    $tg+="Metodo Oliver Velez | Alta: $nBull | Baixa: $nBear | Conflitos: $nOpp"
    $tg+=""
    if($dqBull2.Count-gt 0){$tg+="$eC <b>Alta multi-TF:</b> $(JoinT ($dqBull2|ForEach-Object{ ""$($_.T) ($($_.Conv), entra US`$ $(([double]$_.Gat).ToString('N2',$enus)))"" }))"}
    if($dqBear2.Count-gt 0){$tg+="$eV <b>Baixa multi-TF:</b> $(JoinT ($dqBear2|ForEach-Object{ ""$($_.T) ($($_.Conv), entra US`$ $(([double]$_.Gat).ToString('N2',$enus)))"" }))"}
    if($dqStrong.Count-gt 0){$tg+="$eS <b>Mais fortes:</b> $(JoinT ($dqStrong|ForEach-Object{ ""$($_.T) ($($_.Forca)x $($_.PrimTF))"" }))"}
    if($dqOpp.Count-gt 0){$tg+="$eX <b>Conflito (aguardar):</b> $(JoinT ($dqOpp|ForEach-Object{$_.T}))"}
    $tg+=""
    $tg+="$eM Relatorio completo no e-mail."
    ($tg -join "`n")|Out-File "velez_us_telegram.txt" -Encoding UTF8 -NoNewline;Write-Host "Telegram: velez_us_telegram.txt"
}

if(-not$SemEmail){
    $credFile=Join-Path $env:USERPROFILE "Downloads\.onda3_cred.xml"
    if(Test-Path $credFile){
        try{
            $cred=Import-Clixml $credFile
            $subject="[Velez US] $readLabel $dateStr ET | Alta:$nBull Baixa:$nBear"
            Send-MailMessage -From $cred.UserName -To "jjovieira@gmail.com" -Subject $subject -Body $htmlBody -BodyAsHtml -SmtpServer "smtp.gmail.com" -Port 587 -UseSsl -Credential $cred -Encoding UTF8
            Write-Host "[OK] Email enviado para jjovieira@gmail.com"
        }catch{Write-Host "[ERRO] Falha SMTP: $_"}
    }else{Write-Host "[AVISO] Credenciais nao encontradas (.onda3_cred.xml). HTML em: $htmlFile"}
}
Write-Host "Scan Velez US concluido."
