# onda3_us_scan.ps1 - Onda 3 Scanner US 3-TF (1m + 5m + 15m)
# 19 papeis US | MIMA8/17/72 (HMA) + Fractal72 + Fibonacci 21.4%/78.6%
# Envio a cada 2h (horario de NY): 9:33, 9:45, 11:45, 13:45, 15:45, 17:45 ET
# Para configurar email local: executar onda3_setup.ps1 uma vez (compartilha .onda3_cred.xml)
param([switch]$SemEmail,[string]$OutFile="")
$ErrorActionPreference = "SilentlyContinue"

function Get-HMA-K([double[]]$arrC,[int]$p,[int]$Kn){
    $half=[Math]::Max(1,[Math]::Round($p/2.0));$sq=[Math]::Max(1,[Math]::Round([Math]::Sqrt($p)))
    $n=$arrC.Length;if($n-lt($p+$sq+$Kn-2)){return $null}
    $dp=$p*($p+1)/2.0;$dh=$half*($half+1)/2.0;$ds=$sq*($sq+1)/2.0;$rawA=[double[]]::new($n)
    for($i=$p-1;$i-lt$n;$i++){$sf=0.0;for($j=0;$j-lt$p;$j++){$sf+=$arrC[$i-$p+1+$j]*($j+1)};$wf=$sf/$dp;$sh=0.0;for($j=0;$j-lt$half;$j++){$sh+=$arrC[$i-$half+1+$j]*($j+1)};$wh=$sh/$dh;$rawA[$i]=2.0*$wh-$wf}
    $hma=[double[]]::new($Kn);for($ki=0;$ki-lt$Kn;$ki++){$i=$n-$Kn+$ki;$s=0.0;for($j=0;$j-lt$sq;$j++){$s+=$rawA[$i-$sq+1+$j]*($j+1)};$hma[$ki]=$s/$ds}
    return ,$hma
}
function Find-Frac72([double[]]$arrH,[double[]]$arrL){
    $n=$arrH.Length;$fhV=[double]::NaN;$flV=[double]::NaN;$lim=[Math]::Max(72,$n-1-72-700)
    for($i=$n-1-72;$i-ge$lim;$i--){
        if([double]::IsNaN($fhV)){$ok=$true;$hi=$arrH[$i];for($j=$i-72;$j-le$i+72;$j++){if($j-ne$i-and$arrH[$j]-ge$hi){$ok=$false;break}};if($ok){$fhV=$hi}}
        if([double]::IsNaN($flV)){$ok=$true;$li=$arrL[$i];for($j=$i-72;$j-le$i+72;$j++){if($j-ne$i-and$arrL[$j]-le$li){$ok=$false;break}};if($ok){$flV=$li}}
        if((-not[double]::IsNaN($fhV))-and(-not[double]::IsNaN($flV))){break}
    }
    return @{FH=$fhV;FL=$flV}
}
function Proc-Bars([double[]]$arrC,[double[]]$arrH,[double[]]$arrL){
    $Kn=6;$n=$arrC.Length;if($n-lt 150){return $null}
    $hma8=Get-HMA-K $arrC 8 $Kn;$hma17=Get-HMA-K $arrC 17 $Kn;$hma72=Get-HMA-K $arrC 72 $Kn
    if((-not$hma8)-or(-not$hma17)-or(-not$hma72)){return $null}
    $cb=$false;$cs=$false
    for($i=0;$i-lt 5;$i++){$cur=$Kn-1-$i;$prv=$Kn-2-$i;if($prv-lt 0){continue};if($hma8[$prv]-le$hma17[$prv]-and$hma8[$cur]-gt$hma17[$cur]){$cb=$true};if($hma8[$prv]-ge$hma17[$prv]-and$hma8[$cur]-lt$hma17[$cur]){$cs=$true}}
    $lc=$arrC[$n-1];$lhma72=$hma72[$Kn-1];$abM=$lc-gt$lhma72
    $fr=Find-Frac72 $arrH $arrL;$fhp=$fr.FH;$flp=$fr.FL
    $abFH=((-not[double]::IsNaN($fhp))-and($lc-gt$fhp));$blFL=((-not[double]::IsNaN($flp))-and($lc-lt$flp))
    $st=if($cb-and$abM-and$abFH){"SC"}elseif($cs-and(-not$abM)-and$blFL){"SV"}elseif($cb-and$abM){"PC"}elseif($cs-and(-not$abM)){"PV"}else{"-"}
    $dir=if($st-match"C"){"BUY"}elseif($st-match"V"){"SELL"}else{"NONE"}
    return @{St=$st;Dir=$dir;LC=[Math]::Round($lc,2);FH=$fhp;FL=$flp;N=$n}
}
function Get-Fib($fhV,$flV,$dir){
    if([double]::IsNaN($fhV)-or[double]::IsNaN($flV)){return $null}
    $sw=$fhV-$flV;$f2=[Math]::Round($flV+$sw*0.214,2);$f7=[Math]::Round($flV+$sw*0.786,2)
    if($dir-eq"BUY"){return @{F2=$f2;F7=$f7;A0=$f7;A1=[Math]::Round($f2+$sw*1.618,2);A2=[Math]::Round($f2+$sw*2.618,2);A3=[Math]::Round($f2+$sw*4.236,2)}}
    else{return @{F2=$f2;F7=$f7;A0=$f2;A1=[Math]::Round($f7-$sw*1.618,2);A2=[Math]::Round($f7-$sw*2.618,2);A3=[Math]::Round($f7-$sw*4.236,2)}}
}
function Classify-3TF($s1,$s5,$s15){
    $dirs=@();$set=0
    foreach($s in @($s1,$s5,$s15)){if($s-match"C"){$dirs+="BUY";if($s-match"^S"){$set++}}elseif($s-match"V"){$dirs+="SELL";if($s-match"^S"){$set++}}}
    $buy=($dirs|Where-Object{$_-eq"BUY"}).Count;$sell=($dirs|Where-Object{$_-eq"SELL"}).Count;$tot=$buy+$sell
    if($buy-gt 0-and$sell-gt 0){return @{Conv="OPOSTO";Dir="NONE";Score=0}}
    $dir=if($buy-gt 0){"BUY"}elseif($sell-gt 0){"SELL"}else{"NONE"}
    if($tot-eq 0){return @{Conv="-";Dir="NONE";Score=0}}
    $conv=if($tot-eq 3){if($set-ge 3){"FORTE"}elseif($set-ge 2){"CONVERGENTE"}elseif($set-ge 1){"PARCIAL"}else{"PRE-3TF"}}elseif($tot-eq 2){"2-TF"}else{"1-TF"}
    $scr=@{"FORTE"=6;"CONVERGENTE"=5;"PARCIAL"=4;"PRE-3TF"=3;"2-TF"=2;"1-TF"=1;"-"=0;"OPOSTO"=-1}[$conv]
    return @{Conv=$conv;Dir=$dir;Score=$scr}
}

$tickers=@("INTC","NVDA","NFLX","AMZN","MU","TSLA","MSFT","GOOG","AMD","META","AAPL","DELL","SPCX","XOM","JPM","V","MA","COST","WMT")
$baseUrl="https://query1.finance.yahoo.com/v8/finance/chart"
$uaStr="Mozilla/5.0 (Windows NT 10.0; Win64; x64)"
$dateStr=(Get-Date -Format "dd/MM/yyyy HH:mm")
$dateFile=(Get-Date -Format "yyyyMMdd_HHmm")
$hourNow=(Get-Date).Hour
$readLabel=if($hourNow-lt 10){"Abertura"}elseif($hourNow-ge 16){"Fechamento"}else{"Intraday"}
Write-Host "[$dateStr] Scan Onda3 US 3-TF (1m/5m/15m) iniciado para $($tickers.Count) papeis... [$readLabel]"
$timer=[System.Diagnostics.Stopwatch]::StartNew()

$dlMap=@{}
foreach($t in $tickers){
    $sym=$t
    foreach($iv in @("1m","5m","15m")){
        $rng=if($iv-eq"1m"){"5d"}elseif($iv-eq"5m"){"30d"}else{"60d"}
        $key="${iv}_$t"
        $wc=[System.Net.WebClient]::new();$wc.Headers.Add("User-Agent",$uaStr)
        $url="$baseUrl/$sym" + "?interval=$iv" + "&range=$rng" + "&includePrePost=false"
        $dlMap[$key]=$wc.DownloadStringTaskAsync($url)
    }
}
$rawMap=@{}
foreach($key in $dlMap.Keys){
    try{$json=$dlMap[$key].GetAwaiter().GetResult();$parsed=$json|ConvertFrom-Json;$ch=$parsed.chart.result[0];$rawMap[$key]=@{ts=$ch.timestamp;q=$ch.indicators.quote[0];n=$ch.timestamp.Count}}catch{$rawMap[$key]=$null}
}
$timer.Stop()
$okCount=($rawMap.Keys|Where-Object{$rawMap[$_]-ne$null}).Count
Write-Host "Download: $($timer.Elapsed.TotalSeconds.ToString("F1"))s | $okCount ok"

$M1R=@{};$M5R=@{};$M15R=@{}
foreach($t in $tickers){
    foreach($iv in @("1m","5m","15m")){
        $rk="${iv}_$t"
        if($rawMap[$rk]){$rd=$rawMap[$rk];$nn=$rd.n;$aC=[double[]]::new($nn);$aHH=[double[]]::new($nn);$aLL=[double[]]::new($nn)
            for($i=0;$i-lt$nn;$i++){$cv=$rd.q.close[$i];$hv=$rd.q.high[$i];$lv=$rd.q.low[$i]
                $aC[$i]=if($null-eq$cv-or[double]$cv-le 0){if($i-gt 0){$aC[$i-1]}else{0.0}}else{[double]$cv}
                $aHH[$i]=if($null-eq$hv-or[double]$hv-le 0){$aC[$i]}else{[double]$hv}
                $aLL[$i]=if($null-eq$lv-or[double]$lv-le 0){$aC[$i]}else{[double]$lv}}
            $res=Proc-Bars $aC $aHH $aLL}else{$res=$null}
        if($iv-eq"1m"){$M1R[$t]=$res}elseif($iv-eq"5m"){$M5R[$t]=$res}else{$M15R[$t]=$res}
    }
}

$results=@()
foreach($t in $tickers){
    $r1=$M1R[$t];$r5=$M5R[$t];$r15=$M15R[$t]
    $s1=if($r1){$r1.St}else{"-"};$s5=if($r5){$r5.St}else{"-"};$s15=if($r15){$r15.St}else{"-"}
    $cls=Classify-3TF $s1 $s5 $s15
    $lc=if($r1-and$r1.LC-gt 0){$r1.LC}elseif($r5-and$r5.LC-gt 0){$r5.LC}elseif($r15-and$r15.LC-gt 0){$r15.LC}else{0}
    $fSrc=$null
    if($r15-and(-not[double]::IsNaN($r15.FH))-and(-not[double]::IsNaN($r15.FL))){$fSrc=$r15}
    elseif($r5-and(-not[double]::IsNaN($r5.FH))-and(-not[double]::IsNaN($r5.FL))){$fSrc=$r5}
    elseif($r1-and(-not[double]::IsNaN($r1.FH))-and(-not[double]::IsNaN($r1.FL))){$fSrc=$r1}
    $fhV=if($fSrc){$fSrc.FH}else{[double]::NaN};$flV=if($fSrc){$fSrc.FL}else{[double]::NaN}
    $fib=if($cls.Dir-ne"NONE"){Get-Fib $fhV $flV $cls.Dir}else{$null}
    $zone="-"
    if($fib-and$lc-gt 0){
        if($cls.Dir-eq"BUY"){if($lc-lt$fib.F2){$zone="Zona Verm"}elseif($lc-lt$fib.F7){$zone="Onda3 Up"}elseif($lc-lt$fhV){$zone="Prox FH"}else{$zone="Acima FH"}}
        else{if($lc-gt$fib.F7){$zone="Zona Verm"}elseif($lc-gt$fib.F2){$zone="Onda3 Dn"}elseif($lc-gt$flV){$zone="Prox FL"}else{$zone="Abaixo FL"}}
    }
    $tgtVal=0.0;$tgtLbl="A0";$tgtPct=0.0;$stale=$false
    if($fib-and$lc-gt 0){
        if($cls.Dir-eq"BUY"){if($lc-gt$fib.A0){$stale=$true;$tgtVal=$fib.A1;$tgtLbl="A1"}else{$tgtVal=$fib.A0}}
        else{if($lc-lt$fib.A0){$stale=$true;$tgtVal=$fib.A1;$tgtLbl="A1"}else{$tgtVal=$fib.A0}}
        if($tgtVal-ne 0-and$lc-gt 0){$tgtPct=[Math]::Round(($tgtVal-$lc)/$lc*100,1)}
    }
    $valid=($cls.Dir-eq"BUY"-and$tgtPct-gt 0)-or($cls.Dir-eq"SELL"-and$tgtPct-lt 0)
    $obs=if($cls.Conv-eq"OPOSTO"){"Conflito de TFs"}
        elseif($cls.Dir-eq"NONE"){"Sem sinal"}
        elseif($stale-or(-not$valid-and$tgtVal-ne 0)){"Fractal obsoleto"}
        elseif($zone-eq"Onda3 Up"-or$zone-eq"Onda3 Dn"){"Onda 3 ativa"}
        elseif($zone-eq"Zona Verm"){"Onda 2, aguardar"}
        elseif($zone-eq"Prox FH"-or$zone-eq"Prox FL"){"Perto do gatilho"}
        elseif($zone-eq"Acima FH"-or$zone-eq"Abaixo FL"){"Setup ativo"}
        else{"-"}
    $results+=[PSCustomObject]@{
        T=$t;C=$cls.Conv;D=$cls.Dir;S=$cls.Score
        S1=$s1;S5=$s5;S15=$s15;LC=$lc
        FH=if((-not[double]::IsNaN($fhV))){[Math]::Round($fhV,2)}else{0}
        FL=if((-not[double]::IsNaN($flV))){[Math]::Round($flV,2)}else{0}
        F2=if($fib){$fib.F2}else{0};F7=if($fib){$fib.F7}else{0}
        A0=if($fib){$fib.A0}else{0};A1=if($fib){$fib.A1}else{0}
        Z=$zone;TG=$tgtVal;TL=$tgtLbl;TP=$tgtPct;ST=$stale;OBS=$obs
    }
}
$sorted=$results|Sort-Object S -Descending

$n2tf=($sorted|Where-Object{$_.S-ge 2}).Count
$n1tf=($sorted|Where-Object{$_.S-eq 1}).Count
$nop=($sorted|Where-Object{$_.S-le 0}).Count

# Build HTML rows (ASCII only in PS code, HTML entities for special chars in output)
$rows=""
$lastScore=99
$tierLabel=@{
    2="2-TF &mdash; Melhor converg&ecirc;ncia dispon&iacute;vel";
    1="1-TF &mdash; Sinal ativo";
    0="Oposto / Sem sinal &mdash; aguardando"
}
$rankNum=0
foreach($r in $sorted){
    $tier=if($r.S-ge 2){2}elseif($r.S-ge 1){1}else{0}
    if($tier-ne$lastScore){
        $lbl=$tierLabel[$tier]
        $rows+="<tr><td colspan='12' style='background:#f0f0f0;font-size:10px;font-weight:600;color:#555;padding:6px 8px;letter-spacing:0.5px;text-transform:uppercase'>$lbl</td></tr>"
        $lastScore=$tier
    }
    $rankNum++
    if($r.D-eq"BUY"){$arrow="<span style='color:#1a7a3a;font-weight:700'>&uarr;</span>"}
    elseif($r.D-eq"SELL"){$arrow="<span style='color:#c0392b;font-weight:700'>&darr;</span>"}
    else{$arrow="<span style='color:#888'>&harr;</span>"}
    $s1Badge=switch($r.S1){"SC"{"<span style='background:#C0DD97;color:#27500A;font-size:9px;font-weight:600;padding:1px 4px;border-radius:2px'>SC</span>"};"SV"{"<span style='background:#F7C1C1;color:#791F1F;font-size:9px;font-weight:600;padding:1px 4px;border-radius:2px'>SV</span>"};"PC"{"<span style='background:#9FE1CB;color:#085041;font-size:9px;font-weight:600;padding:1px 4px;border-radius:2px'>PC</span>"};"PV"{"<span style='background:#F5C4B3;color:#712B13;font-size:9px;font-weight:600;padding:1px 4px;border-radius:2px'>PV</span>"};default{"<span style='color:#aaa'>-</span>"}}
    $s5Badge=switch($r.S5){"SC"{"<span style='background:#C0DD97;color:#27500A;font-size:9px;font-weight:600;padding:1px 4px;border-radius:2px'>SC</span>"};"SV"{"<span style='background:#F7C1C1;color:#791F1F;font-size:9px;font-weight:600;padding:1px 4px;border-radius:2px'>SV</span>"};"PC"{"<span style='background:#9FE1CB;color:#085041;font-size:9px;font-weight:600;padding:1px 4px;border-radius:2px'>PC</span>"};"PV"{"<span style='background:#F5C4B3;color:#712B13;font-size:9px;font-weight:600;padding:1px 4px;border-radius:2px'>PV</span>"};default{"<span style='color:#aaa'>-</span>"}}
    $s15Badge=switch($r.S15){"SC"{"<span style='background:#C0DD97;color:#27500A;font-size:9px;font-weight:600;padding:1px 4px;border-radius:2px'>SC</span>"};"SV"{"<span style='background:#F7C1C1;color:#791F1F;font-size:9px;font-weight:600;padding:1px 4px;border-radius:2px'>SV</span>"};"PC"{"<span style='background:#9FE1CB;color:#085041;font-size:9px;font-weight:600;padding:1px 4px;border-radius:2px'>PC</span>"};"PV"{"<span style='background:#F5C4B3;color:#712B13;font-size:9px;font-weight:600;padding:1px 4px;border-radius:2px'>PV</span>"};default{"<span style='color:#aaa'>-</span>"}}
    $cBg=switch($r.C){"FORTE"{"#FAC775"};"CONVERGENTE"{"#FAC775"};"PARCIAL"{"#B5D4F4"};"PRE-3TF"{"#B5D4F4"};"2-TF"{"#FAC775"};"1-TF"{"#B5D4F4"};"OPOSTO"{"#F0997B"};default{"#ddd"}}
    $cColor=switch($r.C){"FORTE"{"#633806"};"CONVERGENTE"{"#633806"};"PARCIAL"{"#0C447C"};"PRE-3TF"{"#0C447C"};"2-TF"{"#633806"};"1-TF"{"#0C447C"};"OPOSTO"{"#4A1B0C"};default{"#555"}}
    $cBadge="<span style='background:$cBg;color:$cColor;font-size:9px;font-weight:600;padding:2px 5px;border-radius:2px'>$($r.C)</span>"
    $lcFmt=$r.LC.ToString("N2",[System.Globalization.CultureInfo]::GetCultureInfo("en-US"))
    $tgCell=if($r.TG-ne 0){"US`$ $($r.TG.ToString("N2",[System.Globalization.CultureInfo]::GetCultureInfo("en-US"))) <small style='color:#999'>($($r.TL))</small>"}else{"&mdash;"}
    $valid=($r.D-eq"BUY"-and$r.TP-gt 0)-or($r.D-eq"SELL"-and$r.TP-lt 0)
    $tpColor=if($valid){"#1a7a3a"}elseif($r.ST){"#b7600a"}else{"#c0392b"}
    $tpSign=if($r.TP-gt 0){"+"}else{""}
    $tpCell=if($r.TP-ne 0){"<span style='color:$tpColor;font-weight:600'>$tpSign$($r.TP)%</span>"}else{"&mdash;"}
    $flagCell=if($r.ST){"<span style='color:#b7600a' title='Fractal obsoleto'>&#9888;</span>"}else{""}
    $obsTxt=if($r.OBS-eq"Fractal obsoleto"){"$($r.OBS) &#9888;"}else{$r.OBS}
    $rowBg=if($r.C-eq"2-TF"){"background:rgba(250,199,117,0.08);"}elseif($r.C-eq"OPOSTO"){"background:rgba(240,153,123,0.07);"}else{""}
    $rows+="<tr style='border-bottom:1px solid #f0f0f0;$rowBg'><td style='padding:4px 6px;color:#999;font-size:10px'>$rankNum</td><td style='padding:4px 6px;font-weight:600;font-size:12px'>$($r.T)</td><td style='padding:4px 6px;font-size:10px;color:#555'>$obsTxt</td><td style='padding:4px 4px;text-align:center'>$arrow</td><td style='padding:4px 3px'>$s1Badge</td><td style='padding:4px 3px'>$s5Badge</td><td style='padding:4px 3px'>$s15Badge</td><td style='padding:4px 6px'>$cBadge</td><td style='padding:4px 6px;text-align:right;font-size:11px'>$lcFmt</td><td style='padding:4px 6px;font-size:10px;color:#444'>$($r.Z)</td><td style='padding:4px 6px;font-size:10px;text-align:right'>$tgCell</td><td style='padding:4px 4px;text-align:right'>$tpCell $flagCell</td></tr>"
}

# Build Destaques (dynamic highlights)
function JoinT($arr){ if($arr.Count-eq 0){return "nenhum"}; return ($arr -join ", ") }
$dqSell  = @($sorted | Where-Object{ $_.C-eq"2-TF" -and $_.D-eq"SELL" -and (-not $_.ST) })
$dqSellAll = @($sorted | Where-Object{ $_.C-eq"2-TF" -and $_.D-eq"SELL" })
$dqBuyAtv = @($sorted | Where-Object{ $_.D-eq"BUY" -and $_.Z-eq"Onda3 Up" -and (-not $_.ST) })
$dqBuyWait= @($sorted | Where-Object{ $_.D-eq"BUY" -and $_.Z-eq"Zona Verm" } | Sort-Object TP -Descending)
$dqStale  = @($sorted | Where-Object{ $_.OBS-eq"Fractal obsoleto" })
$dqOpp    = @($sorted | Where-Object{ $_.C-eq"OPOSTO" })
$dqSetup  = @($sorted | Where-Object{ $_.S1-match'^S' -or $_.S5-match'^S' -or $_.S15-match'^S' })
$dqLines = @()
if($dqSellAll.Count-gt 0){
    $best=if($dqSell.Count-gt 0){"$($dqSell[0].T) (alvo $($dqSell[0].TL) US`$ $($dqSell[0].TG.ToString('N2',[System.Globalization.CultureInfo]::GetCultureInfo('pt-BR'))))"}else{"nenhum com alvo limpo"}
    $dqLines += "<div style='margin-bottom:5px'><span style='color:#c0392b;font-weight:700'>Melhor venda: </span>$best. Convergencia 2-TF de venda: $(JoinT ($dqSellAll | ForEach-Object{$_.T})).</div>"
}
if($dqBuyAtv.Count-gt 0){ $dqLines += "<div style='margin-bottom:5px'><span style='color:#1a7a3a;font-weight:700'>Compras com Onda 3 ativa: </span>$(JoinT ($dqBuyAtv | ForEach-Object{$_.T})) &mdash; preco entre F21.4% e F78.6%, alvo confiavel.</div>" }
if($dqBuyWait.Count-gt 0){ $dqLines += "<div style='margin-bottom:5px'><span style='color:#9b6000;font-weight:700'>Alto potencial, aguardar: </span>$(JoinT ($dqBuyWait | ForEach-Object{ ""$($_.T) (+$($_.TP)%)"" })) &mdash; em Zona Vermelha (Onda 2), so entrar apos romper F21.4%.</div>" }
if($dqStale.Count-gt 0){ $dqLines += "<div style='margin-bottom:5px'><span style='color:#b7600a;font-weight:700'>Ignorar (fractal obsoleto &#9888;): </span>$(JoinT ($dqStale | ForEach-Object{$_.T})).</div>" }
if($dqOpp.Count-gt 0){ $dqLines += "<div style='margin-bottom:5px'><span style='color:#7a2c2c;font-weight:700'>Sem operacao (conflito de TFs): </span>$(JoinT ($dqOpp | ForEach-Object{$_.T})).</div>" }
$setupTxt=if($dqSetup.Count-gt 0){ JoinT ($dqSetup | ForEach-Object{$_.T}) }else{ "nenhum" }
$dqLines += "<div><span style='color:#333;font-weight:700'>Vies geral: </span>Setups confirmados (SC/SV): $setupTxt. Total: 2-TF=$n2tf, 1-TF=$n1tf, sem operacao=$nop.</div>"
$destaques = "<div style='margin-top:14px;padding:12px 14px;background:#fbf7ef;border:1px solid #f0e2c8;border-radius:6px'><div style='font-size:11px;font-weight:700;color:#633806;margin-bottom:8px;text-transform:uppercase;letter-spacing:0.4px'>Destaques da varredura</div><div style='font-size:11px;color:#333;line-height:1.7'>$($dqLines -join '')</div></div>"

$htmlBody = "<html><head><meta charset='UTF-8'><title>Onda 3 Scanner US</title></head><body style='font-family:Arial,sans-serif;font-size:12px;color:#222;max-width:780px;margin:0 auto;padding:16px'><table width='100%' style='background:#16213e;border-radius:6px;padding:14px 18px;margin-bottom:14px'><tr><td><span style='font-size:17px;font-weight:700;color:#fff'>Onda 3 Scanner &mdash; EUA</span> <span style='background:#FAC775;color:#633806;padding:1px 6px;border-radius:3px;font-size:10px;font-weight:700'>$readLabel</span><br><span style='font-size:11px;color:#aac4ff'>$dateStr | 19 pap&eacute;is US | 1min + 5min + 15min | MIMA8/17/72 + Fractal72 + Fibonacci 21.4%/78.6%</span></td><td style='text-align:right;vertical-align:top'><span style='background:#FAC775;color:#633806;padding:2px 7px;border-radius:3px;font-size:10px;font-weight:600'>2-TF: $n2tf</span>&nbsp;<span style='background:#B5D4F4;color:#0C447C;padding:2px 7px;border-radius:3px;font-size:10px;font-weight:600'>1-TF: $n1tf</span>&nbsp;<span style='background:#eee;color:#555;padding:2px 7px;border-radius:3px;font-size:10px;font-weight:600'>Outros: $nop</span></td></tr></table><table width='100%' cellspacing='0' cellpadding='0' style='border-collapse:collapse;border:1px solid #e8e8e8'><thead><tr style='background:#f8f8f8;border-bottom:2px solid #e0e0e0'><th style='padding:5px 6px;font-size:10px;color:#666;text-align:left;width:22px'>#</th><th style='padding:5px 6px;font-size:10px;color:#666;text-align:left;width:48px'>Papel</th><th style='padding:5px 6px;font-size:10px;color:#666;text-align:left;width:92px'>Obs.</th><th style='padding:5px 4px;font-size:10px;color:#666;width:14px'></th><th style='padding:5px 3px;font-size:10px;color:#666;text-align:left;width:30px'>1m</th><th style='padding:5px 3px;font-size:10px;color:#666;text-align:left;width:30px'>5m</th><th style='padding:5px 3px;font-size:10px;color:#666;text-align:left;width:30px'>15m</th><th style='padding:5px 6px;font-size:10px;color:#666;text-align:left;width:48px'>Conv.</th><th style='padding:5px 6px;font-size:10px;color:#666;text-align:right;width:48px'>Pre&ccedil;o</th><th style='padding:5px 6px;font-size:10px;color:#666;text-align:left;width:70px'>Zona</th><th style='padding:5px 6px;font-size:10px;color:#666;text-align:right;width:80px'>Alvo</th><th style='padding:5px 4px;font-size:10px;color:#666;text-align:right;width:50px'>Pot.%</th></tr></thead><tbody>$rows</tbody></table>$destaques<div style='margin-top:14px;padding:10px 12px;background:#f9f9f9;border-radius:4px;font-size:10px;color:#555;line-height:1.9'><strong>Legenda:</strong><br><strong>Sinais &mdash;</strong> SC=Setup Compra | SV=Setup Venda | PC=Pr&eacute; Compra | PV=Pr&eacute; Venda<br><strong>Converg&ecirc;ncia &mdash;</strong> FORTE=3TFs+3 Setups | CONVERGENTE=3TFs+2SC | PARCIAL=3TFs+1SC | PRE-3TF=3TFs todos PRE | 2-TF=2 TFs alinhados | 1-TF=sinal isolado | OPOSTO=TFs conflitantes<br><strong>Zonas &mdash;</strong> Onda3 Up/Dn=Onda 3 ativa (entre 21.4% e 78.6%) | Zona Verm=Onda 2 em curso | Prox FH/FL=pr&oacute;ximo ao gatilho | Acima FH/Abaixo FL=setup confirmado<br><strong>Fibonacci &mdash;</strong> F21.4%=linha vermelha (fim Onda 2) | F78.6%=Alvo 0 | Ext 1.618/2.618/4.236=proje&ccedil;&otilde;es Onda 3<br><strong>Alvos &mdash;</strong> A0=primeiro alvo | A1=extens&atilde;o 1.618 (quando A0 j&aacute; ultrapassado) | &#9888;=fractal obsoleto<br><strong>Timeframes &mdash;</strong> 1m / 5m / 15m (intradi&aacute;rio) | <strong>MIMA</strong>=Hull MA (HMA) | MIMA8xMIMA17=cruzamento identifica Onda 3 | MIMA72=linha de tend&ecirc;ncia | Fractal72=pivot high/low com 72 barras cada lado</div><p style='font-size:10px;color:#aaa;margin-top:10px;text-align:center'>Onda 3 Scanner &mdash; EUA | Claude Code | Dados: Yahoo Finance | jjovieira@gmail.com</p></body></html>"

if($OutFile -ne ""){ $htmlFile = $OutFile } else { $htmlFile = Join-Path $env:USERPROFILE "Downloads\onda3_us_report_$dateFile.html" }
$htmlBody | Out-File $htmlFile -Encoding UTF8
Write-Host "HTML salvo: $htmlFile"
if($OutFile -ne ""){
    "[Onda3 US] $readLabel $dateStr ET | 2-TF:$n2tf | 1-TF:$n1tf" | Out-File "onda3_us_subject.txt" -Encoding UTF8 -NoNewline; Write-Host "Subject: onda3_us_subject.txt"
    $ptbr=[System.Globalization.CultureInfo]::GetCultureInfo("en-US")
    $eW=[char]::ConvertFromUtf32(0x26A1);$eV=[char]::ConvertFromUtf32(0x1F534);$eC=[char]::ConvertFromUtf32(0x1F7E2);$eA=[char]::ConvertFromUtf32(0x1F7E1);$eX=[char]::ConvertFromUtf32(0x26A0);$eM=[char]::ConvertFromUtf32(0x1F4E7)
    $tg=@()
    $tg+="<b>$eW Onda 3 US ($readLabel) - $dateStr</b>"
    $tg+="1m/5m/15m | 2-TF: $n2tf | 1-TF: $n1tf | Outros: $nop"
    $tg+=""
    if($dqSell.Count -gt 0){$tg+="$eV <b>Melhor venda:</b> $($dqSell[0].T) (alvo $($dqSell[0].TL) US`$ $($dqSell[0].TG.ToString('N2',$ptbr)) / $($dqSell[0].TP)%)"}
    if($dqBuyAtv.Count -gt 0){$tg+="$eC <b>Compras Onda 3 ativa:</b> $(JoinT ($dqBuyAtv|ForEach-Object{$_.T}))"}
    if($dqBuyWait.Count -gt 0){$tg+="$eA <b>Aguardar (Zona Verm):</b> $(JoinT ($dqBuyWait|ForEach-Object{ ""$($_.T) (+$($_.TP)%)"" }))"}
    if($dqStale.Count -gt 0){$tg+="$eX <b>Ignorar (fractal obsoleto):</b> $(JoinT ($dqStale|ForEach-Object{$_.T}))"}
    $tg+=""
    $tg+="$eM Relatorio completo no e-mail."
    ($tg -join "`n") | Out-File "onda3_us_telegram.txt" -Encoding UTF8 -NoNewline; Write-Host "Telegram: onda3_us_telegram.txt"
}

if(-not$SemEmail){
    $credFile = Join-Path $env:USERPROFILE "Downloads\.onda3_cred.xml"
    if(Test-Path $credFile){
        try{
            $cred = Import-Clixml $credFile
            $subject = "[Onda3 US] $readLabel $dateStr ET | 2-TF:$n2tf | 1-TF:$n1tf"
            Send-MailMessage -From $cred.UserName -To "jjovieira@gmail.com" -Subject $subject -Body $htmlBody -BodyAsHtml -SmtpServer "smtp.gmail.com" -Port 587 -UseSsl -Credential $cred -Encoding UTF8
            Write-Host "[OK] Email enviado para jjovieira@gmail.com"
        }catch{
            Write-Host "[ERRO] Falha SMTP: $_"
        }
    }else{
        Write-Host "[AVISO] Credenciais nao encontradas. Execute onda3_setup.ps1 primeiro."
        Write-Host "        HTML disponivel em: $htmlFile"
    }
}
Write-Host "Scan Onda3 US concluido."
