# trifecta_br_scan.ps1 - Scanner Trifecta (Oliver Velez, gatilho barra elefante) - mercado BR (B3)
# 31 papeis BR | 2m + 5m + 15m | Vela Elefante: corpo>=70% + corpo>=1.3*ATR(100) + vies MM200 + MM20
# Logica exata do indicador "VELA ELEFANTE DE OLIVER VELEZ" (Dreadblitz, Pine v4).
# Envio email+Telegram a cada 2h a partir da abertura da B3 (10:00): 10:15,12:15,14:15,16:15,18:15 BRT.
# Para email local: reaproveita .onda3_cred.xml (mesmo setup dos outros scanners).
param([switch]$SemEmail,[string]$OutFile="")
$ErrorActionPreference = "SilentlyContinue"

# ---- Parametros da estrategia (ajustaveis) ----
$BODY_PCT = 70.0    # % minimo do corpo sobre o range (PDCM)
$ATR_FAC  = 1.3     # fator: corpo >= ATR_FAC * ATR(ATR_LEN) (FDB)
$ATR_LEN  = 100     # periodo do ATR (CDBA)
$MM_SHORT = 20      # media curta (Velez) - referencia de curto prazo / contexto
$MM_LONG  = 200     # media longa (Velez) - vies principal da Trifecta
$USE_FILTER = $true # filtra a elefante pelo vies da MM200 (preco acima=so alta, abaixo=so baixa; fallback MM20 se MM200 indisponivel)
# lookback (barras fechadas vasculhadas por TF, p/ nao perder elefante entre varreduras de 2h)
$LB = @{ "2m"=30; "5m"=12; "15m"=8 }

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
    $mm20=Get-SMA $c $MM_SHORT
    $mm200=Get-SMA $c $MM_LONG
    $stop=[Math]::Max($ATR_LEN+1,$n-$lookback)
    for($i=$n-1;$i-ge$stop;$i--){
        $rng=$h[$i]-$l[$i];if($rng-le 0){continue}
        $body=[Math]::Abs($o[$i]-$c[$i]);$bp=$body/$rng*100;if($bp-lt$BODY_PCT){continue}
        $ap=$atr[$i-1];if([double]::IsNaN($ap)-or$ap-le 0){continue}
        if($body-lt $ATR_FAC*$ap){continue}
        $dir=if($c[$i]-gt$o[$i]){"BULL"}elseif($c[$i]-lt$o[$i]){"BEAR"}else{continue}
        # vies de tendencia pela MM200 (fallback MM20 enquanto a MM200 nao tem 200 barras)
        $ref=if(-not[double]::IsNaN($mm200[$i])){$mm200[$i]}elseif(-not[double]::IsNaN($mm20[$i])){$mm20[$i]}else{[double]::NaN}
        if($USE_FILTER-and -not[double]::IsNaN($ref)){
            if($dir-eq"BULL"-and -not($c[$i]-gt$ref)){continue}
            if($dir-eq"BEAR"-and -not($c[$i]-lt$ref)){continue}
        }
        $p20=if([double]::IsNaN($mm20[$i])){0}elseif($c[$i]-gt$mm20[$i]){1}else{-1}
        $p200=if([double]::IsNaN($mm200[$i])){0}elseif($c[$i]-gt$mm200[$i]){1}else{-1}
        return @{Dir=$dir;BarsAgo=($n-1-$i);High=[Math]::Round($h[$i],2);Low=[Math]::Round($l[$i],2);Close=[Math]::Round($c[$i],2);Strength=[Math]::Round($body/$ap,2);P20=$p20;P200=$p200}
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

# Mapa ticker (exibicao) -> simbolo Yahoo (.SA = B3).
$tickers=@(
    @{T="ABEV3";Y="ABEV3.SA"},@{T="ASAI3";Y="ASAI3.SA"},@{T="AXIA3";Y="AXIA3.SA"},@{T="B3SA3";Y="B3SA3.SA"},
    @{T="BBAS3";Y="BBAS3.SA"},@{T="BBDC4";Y="BBDC4.SA"},@{T="BBSE3";Y="BBSE3.SA"},@{T="BEEF3";Y="BEEF3.SA"},
    @{T="BPAC11";Y="BPAC11.SA"},@{T="BRAV3";Y="BRAV3.SA"},@{T="CSAN3";Y="CSAN3.SA"},@{T="CYRE3";Y="CYRE3.SA"},
    @{T="DIRR3";Y="DIRR3.SA"},@{T="EGIE3";Y="EGIE3.SA"},@{T="EMBJ3";Y="EMBJ3.SA"},@{T="EQTL3";Y="EQTL3.SA"},
    @{T="GGBR4";Y="GGBR4.SA"},@{T="HAPV3";Y="HAPV3.SA"},@{T="ITUB4";Y="ITUB4.SA"},@{T="LREN3";Y="LREN3.SA"},
    @{T="MGLU3";Y="MGLU3.SA"},@{T="MOVI3";Y="MOVI3.SA"},@{T="MULT3";Y="MULT3.SA"},@{T="NATU3";Y="NATU3.SA"},
    @{T="PETR4";Y="PETR4.SA"},@{T="PRIO3";Y="PRIO3.SA"},@{T="RADL3";Y="RADL3.SA"},@{T="RAIL3";Y="RAIL3.SA"},
    @{T="RDOR3";Y="RDOR3.SA"},@{T="RENT3";Y="RENT3.SA"},@{T="SBSP3";Y="SBSP3.SA"},@{T="SUZB3";Y="SUZB3.SA"},
    @{T="USIM5";Y="USIM5.SA"},@{T="VALE3";Y="VALE3.SA"},@{T="WEGE3";Y="WEGE3.SA"}
)
$baseUrl="https://query1.finance.yahoo.com/v8/finance/chart"
$uaStr="Mozilla/5.0 (Windows NT 10.0; Win64; x64)"
$enus=[System.Globalization.CultureInfo]::GetCultureInfo("pt-BR")
$dateStr=(Get-Date -Format "dd/MM/yyyy HH:mm")
$dateFile=(Get-Date -Format "yyyyMMdd_HHmm")
$hourNow=(Get-Date).Hour
$readLabel=if($hourNow-lt 10){"Pre-Abertura"}elseif($hourNow-lt 11){"Abertura"}elseif($hourNow-ge 17){"Fechamento"}else{"Day Trade"}
Write-Host "[$dateStr] Scanner Trifecta BR (barra elefante) iniciado para $($tickers.Count) papeis... [$readLabel]"
$timer=[System.Diagnostics.Stopwatch]::StartNew()

$dlMap=@{}
foreach($tk in $tickers){
    $sym=$tk.Y -replace '\^','%5E'
    foreach($iv in @("2m","5m","15m")){
        $rng=if($iv-eq"2m"){"10d"}elseif($iv-eq"5m"){"30d"}else{"60d"}
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
    $ev=@{};$bias=@{}
    $lastC=0.0
    foreach($iv in @("2m","5m","15m")){
        $rd=$rawMap["${iv}_$t"]
        if($rd){
            $b=Build-OHLC $rd
            $ev[$iv]=Detect-Eleph $b.O $b.H $b.L $b.C $LB[$iv]
            $mm200s=Get-SMA $b.C $MM_LONG;$li=$b.N-1
            $bias[$iv]=if($li-ge 0-and -not[double]::IsNaN($mm200s[$li])){if($b.C[$li]-gt$mm200s[$li]){1}else{-1}}else{0}
            if($iv-eq"2m"-and$b.N-gt 0){$lastC=$b.C[$b.N-1]}
        }else{$ev[$iv]=@{Dir="NONE"};$bias[$iv]=0}
    }
    if($lastC-le 0){foreach($iv in @("5m","15m")){$rd=$rawMap["${iv}_$t"];if($rd-and$lastC-le 0){$b=Build-OHLC $rd;if($b.N-gt 0){$lastC=$b.C[$b.N-1]}}}}
    $e1=$ev["2m"];$e5=$ev["5m"];$e15=$ev["15m"]
    $cls=Classify $e1 $e5 $e15
    # vies agregado pela MM200 (independente de elefante): so e direcional se unanime nos TFs com dado
    $bBull=@($bias.Values|Where-Object{$_-eq 1}).Count
    $bBear=@($bias.Values|Where-Object{$_-eq -1}).Count
    $mmTot=$bBull+$bBear
    $mmDir=if($mmTot-gt 0-and$bBear-eq 0){"BULL"}elseif($mmTot-gt 0-and$bBull-eq 0){"BEAR"}else{"NONE"}
    $mmCount=if($mmDir-eq"BULL"){$bBull}elseif($mmDir-eq"BEAR"){$bBear}else{0}
    $trifecta=(($cls.Dir-ne"NONE")-and($mmDir-eq$cls.Dir)-and($cls.Score-ge 2)-and($mmTot-ge 2))
    # elefante primaria p/ gatilho/stop: TF mais longo alinhado a direcao
    $prim=$null;$primTF=""
    if($cls.Dir-ne"NONE"){
        foreach($pair in @(@($e15,"15m"),@($e5,"5m"),@($e1,"2m"))){ if($pair[0].Dir-eq$cls.Dir){$prim=$pair[0];$primTF=$pair[1];break} }
    }
    $gat=0.0;$stp=0.0;$forca=0.0;$barsAgo=0;$riscoPct=0.0
    if($prim){
        if($cls.Dir-eq"BULL"){$gat=$prim.High;$stp=$prim.Low}else{$gat=$prim.Low;$stp=$prim.High}
        $forca=$prim.Strength;$barsAgo=$prim.BarsAgo
        if($gat-ne 0){$riscoPct=[Math]::Round([Math]::Abs($gat-$stp)/$gat*100,2)}
    }
    $obs=if($cls.Conv-eq"OPOSTO"){"Conflito de TFs"}
        elseif($cls.Dir-eq"NONE"){"Sem elefante"}
        else{$d=if($cls.Dir-eq"BULL"){"alta"}else{"baixa"};$tri=if($trifecta){"TRIFECTA &#10003; "}else{""};"${tri}Elefante $d $primTF (${forca}x ATR, ha $barsAgo barras, risco $riscoPct%)"}
    $results+=[PSCustomObject]@{
        T=$t;Conv=$cls.Conv;Dir=$cls.Dir;Score=$cls.Score
        E1=$e1.Dir;E5=$e5.Dir;E15=$e15.Dir
        F1=$e1.Strength;F5=$e5.Strength;F15=$e15.Strength
        MmDir=$mmDir;MmCount=$mmCount;MmTot=$mmTot;Tri=$trifecta
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
function PxFmt($v){ if($v-eq 0){return "&mdash;"}; return "R`$ "+([double]$v).ToString("N2",$enus) }
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
        $rows+="<tr><td colspan='13' style='background:#f0f0f0;font-size:10px;font-weight:600;color:#555;padding:6px 8px;letter-spacing:0.5px;text-transform:uppercase'>$($tierLabel[$tier])</td></tr>"
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
    $mmCell=if($r.MmTot-eq 0){"<span style='color:#bbb'>&mdash;</span>"}elseif($r.MmDir-eq"BULL"){"<span style='background:#C0DD97;color:#27500A;font-size:9px;font-weight:600;padding:1px 4px;border-radius:2px'>&#9650; $($r.MmCount)/$($r.MmTot)</span>"}elseif($r.MmDir-eq"BEAR"){"<span style='background:#F7C1C1;color:#791F1F;font-size:9px;font-weight:600;padding:1px 4px;border-radius:2px'>&#9660; $($r.MmCount)/$($r.MmTot)</span>"}else{"<span style='color:#999;font-size:9px'>misto</span>"}
    $rowBg=if($r.Tri){"background:rgba(10,125,58,0.10);"}elseif($r.Score-ge 2){"background:rgba(250,199,117,0.08);"}elseif($r.Conv-eq"OPOSTO"){"background:rgba(240,153,123,0.07);"}else{""}
    $rows+="<tr style='border-bottom:1px solid #f0f0f0;$rowBg'><td style='padding:4px 6px;color:#999;font-size:10px'>$rankNum</td><td style='padding:4px 6px;font-weight:600;font-size:12px'>$($r.T)</td><td style='padding:4px 6px;font-size:10px;color:#555'>$($r.OBS)</td><td style='padding:4px 4px;text-align:center'>$arrow</td><td style='padding:4px 3px'>$(ElephBadge $r.E1 $r.F1)</td><td style='padding:4px 3px'>$(ElephBadge $r.E5 $r.F5)</td><td style='padding:4px 3px'>$(ElephBadge $r.E15 $r.F15)</td><td style='padding:4px 6px'>$convBadge</td><td style='padding:4px 4px;text-align:left'>$mmCell</td><td style='padding:4px 6px;text-align:right;font-size:11px'>$(PxFmt $r.LC)</td><td style='padding:4px 6px;font-size:10px;text-align:right'>$gatCell</td><td style='padding:4px 6px;font-size:10px;text-align:right;color:#c0392b'>$stpCell</td><td style='padding:4px 6px;text-align:right;font-size:10px'>$forcaCell</td></tr>"
}

function JoinT($arr){ if($arr.Count-eq 0){return "nenhum"}; return ($arr -join ", ") }
$dqBull2 = @($sorted|Where-Object{$_.Dir-eq"BULL"-and$_.Score-ge 2})
$dqBear2 = @($sorted|Where-Object{$_.Dir-eq"BEAR"-and$_.Score-ge 2})
$dqStrong= @($sorted|Where-Object{$_.Dir-ne"NONE"}|Sort-Object Forca -Descending|Select-Object -First 3)
$dqBull1 = @($sorted|Where-Object{$_.Dir-eq"BULL"-and$_.Score-eq 1})
$dqBear1 = @($sorted|Where-Object{$_.Dir-eq"BEAR"-and$_.Score-eq 1})
$dqOpp   = @($sorted|Where-Object{$_.Conv-eq"OPOSTO"})
$dqTri   = @($sorted|Where-Object{$_.Tri})
$dqLines=@()
if($dqTri.Count-gt 0){$dqLines+="<div style='margin-bottom:6px;padding:5px 7px;background:#eaf7ee;border:1px solid #bfe3c8;border-radius:3px'><span style='color:#0a7d3a;font-weight:800'>&#10003; TRIFECTA completa: </span>$(JoinT ($dqTri|ForEach-Object{ ""$($_.T) ($(if($_.Dir-eq'BULL'){'alta'}else{'baixa'}), $($_.Conv), entrada $(PxFmt $_.Gat))"" })) &mdash; elefante multi-TF alinhado ao vi&eacute;s da MM200 nos 3 tempos.</div>"}
if($dqBull2.Count-gt 0){$dqLines+="<div style='margin-bottom:5px'><span style='color:#1a7a3a;font-weight:700'>Elefantes de ALTA (multi-TF): </span>$(JoinT ($dqBull2|ForEach-Object{ ""$($_.T) ($($_.Conv), entrada $(PxFmt $_.Gat))"" })) &mdash; comprar no rompimento da maxima, stop na minima.</div>"}
if($dqBear2.Count-gt 0){$dqLines+="<div style='margin-bottom:5px'><span style='color:#c0392b;font-weight:700'>Elefantes de BAIXA (multi-TF): </span>$(JoinT ($dqBear2|ForEach-Object{ ""$($_.T) ($($_.Conv), entrada $(PxFmt $_.Gat))"" })) &mdash; vender no rompimento da minima, stop na maxima.</div>"}
if($dqStrong.Count-gt 0){$dqLines+="<div style='margin-bottom:5px'><span style='color:#9b6000;font-weight:700'>Elefantes mais fortes (corpo/ATR): </span>$(JoinT ($dqStrong|ForEach-Object{ ""$($_.T) ($($_.Forca)x, $($_.PrimTF))"" })).</div>"}
if($dqBull1.Count-gt 0-or$dqBear1.Count-gt 0){$dqLines+="<div style='margin-bottom:5px'><span style='color:#555;font-weight:700'>Sinais isolados (1-TF): </span>alta: $(JoinT ($dqBull1|ForEach-Object{$_.T})) | baixa: $(JoinT ($dqBear1|ForEach-Object{$_.T})).</div>"}
if($dqOpp.Count-gt 0){$dqLines+="<div style='margin-bottom:5px'><span style='color:#7a2c2c;font-weight:700'>Conflito de TFs (aguardar): </span>$(JoinT ($dqOpp|ForEach-Object{$_.T})).</div>"}
$dqLines+="<div><span style='color:#333;font-weight:700'>Resumo: </span>Alta=$nBull, Baixa=$nBear, Convergentes(>=2TF)=$nConv, Conflitos=$nOpp.</div>"
$destaques="<div style='margin-top:14px;padding:12px 14px;background:#fbf7ef;border:1px solid #f0e2c8;border-radius:6px'><div style='font-size:11px;font-weight:700;color:#633806;margin-bottom:8px;text-transform:uppercase;letter-spacing:0.4px'>Destaques da varredura</div><div style='font-size:11px;color:#333;line-height:1.7'>$($dqLines -join '')</div></div>"

$htmlBody="<html><head><meta charset='UTF-8'><title>Scanner Trifecta BR</title></head><body style='font-family:Arial,sans-serif;font-size:12px;color:#222;max-width:820px;margin:0 auto;padding:16px'><table width='100%' style='background:#1e2b1e;border-radius:6px;padding:14px 18px;margin-bottom:14px'><tr><td><span style='font-size:17px;font-weight:700;color:#fff'>&#128024; Scanner Trifecta &mdash; Brasil (B3)</span> <span style='background:#FAC775;color:#633806;padding:1px 6px;border-radius:3px;font-size:10px;font-weight:700'>$readLabel</span><br><span style='font-size:11px;color:#bfe3bf'><b style='color:#ffe8a0'>$dateStr</b> | Trifecta &middot; Barra Elefante (Oliver Velez) | $($tickers.Count) pap&eacute;is BR | 2m + 5m + 15m | corpo&ge;70% + &ge;1,3&times;ATR(100) + vi&eacute;s MM200 + MM20</span></td><td style='text-align:right;vertical-align:top'><span style='background:#C0DD97;color:#27500A;padding:2px 7px;border-radius:3px;font-size:10px;font-weight:600'>Alta: $nBull</span>&nbsp;<span style='background:#F7C1C1;color:#791F1F;padding:2px 7px;border-radius:3px;font-size:10px;font-weight:600'>Baixa: $nBear</span></td></tr></table><table width='100%' cellspacing='0' cellpadding='0' style='border-collapse:collapse;border:1px solid #e8e8e8'><thead><tr style='background:#f8f8f8;border-bottom:2px solid #e0e0e0'><th style='padding:5px 6px;font-size:10px;color:#666;text-align:left;width:22px'>#</th><th style='padding:5px 6px;font-size:10px;color:#666;text-align:left;width:48px'>Papel</th><th style='padding:5px 6px;font-size:10px;color:#666;text-align:left;width:168px'>Obs.</th><th style='padding:5px 4px;font-size:10px;color:#666;width:14px'></th><th style='padding:5px 3px;font-size:10px;color:#666;text-align:left;width:34px'>2m</th><th style='padding:5px 3px;font-size:10px;color:#666;text-align:left;width:34px'>5m</th><th style='padding:5px 3px;font-size:10px;color:#666;text-align:left;width:34px'>15m</th><th style='padding:5px 6px;font-size:10px;color:#666;text-align:left;width:46px'>Conv.</th><th style='padding:5px 4px;font-size:10px;color:#666;text-align:left;width:50px'>MM200</th><th style='padding:5px 6px;font-size:10px;color:#666;text-align:right;width:74px'>Pre&ccedil;o</th><th style='padding:5px 6px;font-size:10px;color:#666;text-align:right;width:88px'>Gatilho</th><th style='padding:5px 6px;font-size:10px;color:#666;text-align:right;width:74px'>Stop</th><th style='padding:5px 6px;font-size:10px;color:#666;text-align:right;width:42px'>For&ccedil;a</th></tr></thead><tbody>$rows</tbody></table>$destaques<div style='margin-top:14px;padding:10px 12px;background:#f9f9f9;border-radius:4px;font-size:10px;color:#555;line-height:1.9'><strong>Legenda:</strong><br><strong>Barra Elefante &mdash;</strong> candle de corpo cheio (&ge;70% do range) e grande (&ge;1,3&times;ATR de 100 barras). &#128024;&#9650;=elefante de alta | &#128024;&#9660;=elefante de baixa. For&ccedil;a = corpo &divide; ATR (quanto maior, mais dominante).<br><strong>M&eacute;dias (Velez) &mdash;</strong> MM200 = vi&eacute;s principal (s&oacute; conta elefante de alta com pre&ccedil;o ACIMA da MM200, e de baixa ABAIXO) | MM20 = refer&ecirc;ncia de curto prazo. Coluna <strong>MM200</strong> mostra quantos dos 3 tempos est&atilde;o do mesmo lado (&#9650; alta / &#9660; baixa / misto). <strong>TRIFECTA &#10003;</strong> = elefante multi-TF alinhado ao vi&eacute;s un&acirc;nime da MM200.<br><strong>Converg&ecirc;ncia &mdash;</strong> 3-TF=elefante mesma dire&ccedil;&atilde;o nos 3 tempos | 2-TF=em 2 | 1-TF=isolado | OPOSTO=tempos conflitantes.<br><strong>Opera&ccedil;&atilde;o (Oliver Velez) &mdash;</strong> Gatilho=rompimento do extremo da elefante (m&aacute;xima p/ compra, m&iacute;nima p/ venda) | Stop=extremo oposto da mesma barra. Aten&ccedil;&atilde;o: em elefantes grandes o stop fica largo.</div><p style='font-size:10px;color:#aaa;margin-top:10px;text-align:center'>Scanner Trifecta (Oliver Velez) &mdash; Brasil (B3) | Claude Code | Dados: Yahoo Finance | jjovieira@gmail.com</p></body></html>"

if($OutFile -ne ""){$htmlFile=$OutFile}else{$htmlFile=Join-Path $env:USERPROFILE "Downloads\trifecta_br_report_$dateFile.html"}
$htmlBody|Out-File $htmlFile -Encoding UTF8
Write-Host "HTML salvo: $htmlFile"
if($OutFile -ne ""){
    "[Trifecta BR] $readLabel $dateStr | Alta:$nBull Baixa:$nBear" | Out-File "trifecta_br_subject.txt" -Encoding UTF8 -NoNewline;Write-Host "Subject: trifecta_br_subject.txt"
    $eE=[char]::ConvertFromUtf32(0x1F418);$eC=[char]::ConvertFromUtf32(0x1F7E2);$eV=[char]::ConvertFromUtf32(0x1F534);$eS=[char]::ConvertFromUtf32(0x1F4AA);$eX=[char]::ConvertFromUtf32(0x26A0);$eM=[char]::ConvertFromUtf32(0x1F4E7);$eT=[char]::ConvertFromUtf32(0x2705)
    $tg=@()
    $tg+="<b>$eE Trifecta BR ($readLabel) - $dateStr</b>"
    $tg+="Trifecta (Oliver Velez) | Alta: $nBull | Baixa: $nBear | Conflitos: $nOpp"
    $tg+=""
    if($dqTri.Count-gt 0){$tg+="$eT <b>TRIFECTA completa:</b> $(JoinT ($dqTri|ForEach-Object{ ""$($_.T) ($(if($_.Dir-eq'BULL'){'alta'}else{'baixa'}), $($_.Conv))"" }))"}
    if($dqBull2.Count-gt 0){$tg+="$eC <b>Alta multi-TF:</b> $(JoinT ($dqBull2|ForEach-Object{ ""$($_.T) ($($_.Conv), entra R`$ $(([double]$_.Gat).ToString('N2',$enus)))"" }))"}
    if($dqBear2.Count-gt 0){$tg+="$eV <b>Baixa multi-TF:</b> $(JoinT ($dqBear2|ForEach-Object{ ""$($_.T) ($($_.Conv), entra R`$ $(([double]$_.Gat).ToString('N2',$enus)))"" }))"}
    if($dqStrong.Count-gt 0){$tg+="$eS <b>Mais fortes:</b> $(JoinT ($dqStrong|ForEach-Object{ ""$($_.T) ($($_.Forca)x $($_.PrimTF))"" }))"}
    if($dqOpp.Count-gt 0){$tg+="$eX <b>Conflito (aguardar):</b> $(JoinT ($dqOpp|ForEach-Object{$_.T}))"}
    $tg+=""
    $tg+="$eM Relatorio completo no e-mail."
    ($tg -join "`n")|Out-File "trifecta_br_telegram.txt" -Encoding UTF8 -NoNewline;Write-Host "Telegram: trifecta_br_telegram.txt"
}

if(-not$SemEmail){
    $credFile=Join-Path $env:USERPROFILE "Downloads\.onda3_cred.xml"
    if(Test-Path $credFile){
        try{
            $cred=Import-Clixml $credFile
            $subject="[Trifecta BR] $readLabel $dateStr | Alta:$nBull Baixa:$nBear"
            Send-MailMessage -From $cred.UserName -To "jjovieira@gmail.com" -Subject $subject -Body $htmlBody -BodyAsHtml -SmtpServer "smtp.gmail.com" -Port 587 -UseSsl -Credential $cred -Encoding UTF8
            Write-Host "[OK] Email enviado para jjovieira@gmail.com"
        }catch{Write-Host "[ERRO] Falha SMTP: $_"}
    }else{Write-Host "[AVISO] Credenciais nao encontradas (.onda3_cred.xml). HTML em: $htmlFile"}
}
Write-Host "Scan Trifecta BR concluido."
