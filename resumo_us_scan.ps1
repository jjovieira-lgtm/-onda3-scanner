# resumo_us_scan.ps1 - Resumo Convergencia (Trifecta + Onda 3) - mercado US
# Cruza as 2 visoes por papel e lista SO os destaques: convergentes (as duas concordam)
# + destaques isolados fortes de cada estrategia. 19 acoes US. Mesma agenda/fluxo dos demais US.
param([switch]$SemEmail,[string]$OutFile="")
$ErrorActionPreference = "SilentlyContinue"

# ============ FUNCOES ONDA 3 (MIMA8/17/72 HMA + Fractal72 + Fibonacci) ============
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
    if($dir-eq"BUY"){return @{F2=$f2;F7=$f7;A0=$f7;A1=[Math]::Round($f2+$sw*1.618,2)}}
    else{return @{F2=$f2;F7=$f7;A0=$f2;A1=[Math]::Round($f7-$sw*1.618,2)}}
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

# ============ FUNCOES TRIFECTA (Vela Elefante Velez + MM20/MM200) ============
$BODY_PCT=70.0;$ATR_FAC=1.3;$ATR_LEN=100;$MM_SHORT=20;$MM_LONG=200;$USE_FILTER=$true
$LB=@{ "2m"=30; "5m"=12; "15m"=8 }
function Get-SMA([double[]]$a,[int]$p){
    $n=$a.Length;$s=[double[]]::new($n);$sum=0.0
    for($i=0;$i-lt$n;$i++){$sum+=$a[$i]; if($i-ge$p){$sum-=$a[$i-$p]}; if($i-ge$p-1){$s[$i]=$sum/$p}else{$s[$i]=[double]::NaN}}
    return ,$s
}
function Get-ATR([double[]]$h,[double[]]$l,[double[]]$c,[int]$p){
    $n=$h.Length;$atr=[double[]]::new($n);for($i=0;$i-lt$n;$i++){$atr[$i]=[double]::NaN}
    if($n-lt $p+1){return ,$atr}
    $tr=[double[]]::new($n)
    for($i=0;$i-lt$n;$i++){if($i-eq 0){$tr[$i]=$h[$i]-$l[$i]}else{$a=$h[$i]-$l[$i];$b=[Math]::Abs($h[$i]-$c[$i-1]);$d=[Math]::Abs($l[$i]-$c[$i-1]);$tr[$i]=[Math]::Max($a,[Math]::Max($b,$d))}}
    $sum=0.0;for($i=0;$i-lt$p;$i++){$sum+=$tr[$i]};$atr[$p-1]=$sum/$p
    for($i=$p;$i-lt$n;$i++){$atr[$i]=($atr[$i-1]*($p-1)+$tr[$i])/$p}
    return ,$atr
}
function Detect-Eleph([double[]]$o,[double[]]$h,[double[]]$l,[double[]]$c,[int]$lookback){
    $n=$c.Length;if($n-lt ($ATR_LEN+2)){return @{Dir="NONE"}}
    $atr=Get-ATR $h $l $c $ATR_LEN;$mm20=Get-SMA $c $MM_SHORT;$mm200=Get-SMA $c $MM_LONG
    $stop=[Math]::Max($ATR_LEN+1,$n-$lookback)
    for($i=$n-1;$i-ge$stop;$i--){
        $rng=$h[$i]-$l[$i];if($rng-le 0){continue}
        $body=[Math]::Abs($o[$i]-$c[$i]);$bp=$body/$rng*100;if($bp-lt$BODY_PCT){continue}
        $ap=$atr[$i-1];if([double]::IsNaN($ap)-or$ap-le 0){continue}
        if($body-lt $ATR_FAC*$ap){continue}
        $dir=if($c[$i]-gt$o[$i]){"BULL"}elseif($c[$i]-lt$o[$i]){"BEAR"}else{continue}
        $ref=if(-not[double]::IsNaN($mm200[$i])){$mm200[$i]}elseif(-not[double]::IsNaN($mm20[$i])){$mm20[$i]}else{[double]::NaN}
        if($USE_FILTER-and -not[double]::IsNaN($ref)){if($dir-eq"BULL"-and -not($c[$i]-gt$ref)){continue};if($dir-eq"BEAR"-and -not($c[$i]-lt$ref)){continue}}
        return @{Dir=$dir;High=[Math]::Round($h[$i],2);Low=[Math]::Round($l[$i],2);Strength=[Math]::Round($body/$ap,2)}
    }
    return @{Dir="NONE"}
}
function Classify-Eleph($e1,$e5,$e15){
    $dirs=@($e1.Dir,$e5.Dir,$e15.Dir)
    $bull=($dirs|Where-Object{$_-eq"BULL"}).Count;$bear=($dirs|Where-Object{$_-eq"BEAR"}).Count
    if($bull-gt 0-and$bear-gt 0){return @{Conv="OPOSTO";Dir="NONE";Score=0}}
    if($bull-gt 0){$t=if($bull-ge 3){"3-TF"}elseif($bull-ge 2){"2-TF"}else{"1-TF"};return @{Conv=$t;Dir="BULL";Score=$bull}}
    if($bear-gt 0){$t=if($bear-ge 3){"3-TF"}elseif($bear-ge 2){"2-TF"}else{"1-TF"};return @{Conv=$t;Dir="BEAR";Score=$bear}}
    return @{Conv="-";Dir="NONE";Score=0}
}
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

# ============ NOTICIAS (RSS Yahoo por ticker; SO manchetes com potencial impacto de preco) ============
$NEWS_KW='earnings|results|revenue|profit|loss|guidance|forecast|outlook|upgrade|downgrade|rating|price target|analyst|deal|acquisition|merger|acquire|buyback|repurchase|dividend|split|lawsuit|investigation|probe|approval|recall|contract|billion|million|stake|offering|bankrupt|layoff|resign|sales|registration|production|beats|surge|plunge|halt|jumps|falls|soars|tumbles|cuts|raises|guidance|lucro|receita|dividendo|contrato|processo|resultado|aquisi|recompra|prejuizo|balanco|producao'
$NEWS_EXCL='Zacks Analyst Blog|Broader Market|While Market (Falls|Rises|Dips)|Stocks to Watch|Magnificent Seven|What You Should Know|Some Facts to Note|Here.s What|Motley Fool|Should You Buy|Is It Time'
function Get-NewsTask([string]$sym){
    $wc=[System.Net.WebClient]::new();$wc.Headers.Add("User-Agent",$uaStr);$wc.Encoding=[System.Text.Encoding]::UTF8
    return $wc.DownloadStringTaskAsync("https://feeds.finance.yahoo.com/rss/2.0/headline?s=$sym&region=US&lang=en-US")
}
function Pick-News([string]$xmlStr,[string]$nameRx){
    if([string]::IsNullOrEmpty($nameRx)){return $null}
    try{
        $xml=[xml]$xmlStr;$items=@($xml.rss.channel.item);$now=[DateTimeOffset]::UtcNow
        foreach($it in $items){
            $title=([string]$it.title).Trim();if($title-eq""){continue}
            if($title-notmatch$nameRx){continue}          # tem que ser sobre A empresa
            if($title-match$NEWS_EXCL){continue}            # exclui filler/roundup sem impacto
            if($title-notmatch$NEWS_KW){continue}          # e ter gatilho de impacto de preco
            $pd=$null;try{$pd=[DateTimeOffset]::Parse([string]$it.pubDate)}catch{}
            if($pd-ne$null-and(($now-$pd).TotalDays-gt 4)){continue}
            return @{Title=$title;Link=([string]$it.link).Trim()}
        }
    }catch{}
    return $null
}

# ============ CONFIG ============
$tickers=@("INTC","NVDA","NFLX","AMZN","MU","TSLA","MSFT","GOOG","AMD","META","AAPL","DELL","SPCX","XOM","JPM","V","MA","COST","WMT")
# nome da empresa (regex) p/ garantir que a noticia e sobre o ativo
$coName=@{
 "INTC"="Intel";"NVDA"="Nvidia";"NFLX"="Netflix";"AMZN"="Amazon";"MU"="Micron";"TSLA"="Tesla";
 "MSFT"="Microsoft";"GOOG"="Google|Alphabet";"AMD"="AMD|Advanced Micro";"META"="Meta Platforms|Facebook|\bMeta\b";
 "AAPL"="Apple";"DELL"="Dell";"SPCX"="SpaceX|Space Exploration";"XOM"="Exxon";"JPM"="JPMorgan|JP Morgan";
 "V"="Visa";"MA"="Mastercard";"COST"="Costco";"WMT"="Walmart"
}
$mkt="US";$ccy="US`$ ";$cult=[System.Globalization.CultureInfo]::GetCultureInfo("en-US");$newsSuffix=""
$baseUrl="https://query1.finance.yahoo.com/v8/finance/chart"
$uaStr="Mozilla/5.0 (Windows NT 10.0; Win64; x64)"
$dateStr=(Get-Date -Format "dd/MM/yyyy HH:mm")
$dateFile=(Get-Date -Format "yyyyMMdd_HHmm")
$hourNow=(Get-Date).Hour
$readLabel=if($hourNow-lt 9){"Pre-Abertura"}elseif($hourNow-lt 10){"Abertura"}elseif($hourNow-ge 16){"Fechamento"}else{"Intraday"}
function PxFmt($v){ if($v-eq 0){return "&mdash;"}; return $ccy+([double]$v).ToString("N2",$cult) }
Write-Host "[$dateStr] Resumo Convergencia $mkt (Trifecta + Onda 3) iniciado p/ $($tickers.Count) papeis... [$readLabel]"
$timer=[System.Diagnostics.Stopwatch]::StartNew()

# ============ DOWNLOAD (4 intervalos: 1m+5m+15m p/ Onda3, 2m+5m+15m p/ Trifecta) ============
$dlMap=@{}
foreach($t in $tickers){
    $sym=$t
    foreach($iv in @("1m","2m","5m","15m")){
        $rng=if($iv-eq"1m"){"5d"}elseif($iv-eq"2m"){"10d"}elseif($iv-eq"5m"){"30d"}else{"60d"}
        $wc=[System.Net.WebClient]::new();$wc.Headers.Add("User-Agent",$uaStr)
        $url="$baseUrl/$sym" + "?interval=$iv" + "&range=$rng" + "&includePrePost=false"
        $dlMap["${iv}_$t"]=$wc.DownloadStringTaskAsync($url)
    }
}
$rawMap=@{}
foreach($key in $dlMap.Keys){
    try{$json=$dlMap[$key].GetAwaiter().GetResult();$p=$json|ConvertFrom-Json;$ch=$p.chart.result[0];$rawMap[$key]=@{q=$ch.indicators.quote[0];n=$ch.timestamp.Count}}catch{$rawMap[$key]=$null}
}
$timer.Stop()
Write-Host "Download: $($timer.Elapsed.TotalSeconds.ToString("F1"))s | $(($rawMap.Keys|Where-Object{$rawMap[$_]-ne$null}).Count)/$($dlMap.Count) ok"

# ============ PROCESSA AS 2 VISOES E CRUZA ============
$results=@()
foreach($t in $tickers){
    # ---- ONDA 3 (1m/5m/15m) ----
    $ro=@{}
    foreach($iv in @("1m","5m","15m")){
        $rd=$rawMap["${iv}_$t"]
        if($rd){$b=Build-OHLC $rd;$ro[$iv]=Proc-Bars $b.C $b.H $b.L}else{$ro[$iv]=$null}
    }
    $so1=if($ro["1m"]){$ro["1m"].St}else{"-"};$so5=if($ro["5m"]){$ro["5m"].St}else{"-"};$so15=if($ro["15m"]){$ro["15m"].St}else{"-"}
    $clsO=Classify-3TF $so1 $so5 $so15
    $lcO=if($ro["1m"]-and$ro["1m"].LC-gt 0){$ro["1m"].LC}elseif($ro["5m"]-and$ro["5m"].LC-gt 0){$ro["5m"].LC}elseif($ro["15m"]-and$ro["15m"].LC-gt 0){$ro["15m"].LC}else{0}
    $fSrc=$null
    foreach($rr in @($ro["15m"],$ro["5m"],$ro["1m"])){if($rr-and(-not[double]::IsNaN($rr.FH))-and(-not[double]::IsNaN($rr.FL))){$fSrc=$rr;break}}
    $fhV=if($fSrc){$fSrc.FH}else{[double]::NaN};$flV=if($fSrc){$fSrc.FL}else{[double]::NaN}
    $fibO=if($clsO.Dir-ne"NONE"){Get-Fib $fhV $flV $clsO.Dir}else{$null}
    $zoneO="-";$tgtPctO=0.0;$staleO=$false
    if($fibO-and$lcO-gt 0){
        if($clsO.Dir-eq"BUY"){if($lcO-lt$fibO.F2){$zoneO="Zona Verm"}elseif($lcO-lt$fibO.F7){$zoneO="Onda3 Up"}elseif($lcO-lt$fhV){$zoneO="Prox FH"}else{$zoneO="Acima FH"};$tg=if($lcO-gt$fibO.A0){$staleO=$true;$fibO.A1}else{$fibO.A0}}
        else{if($lcO-gt$fibO.F7){$zoneO="Zona Verm"}elseif($lcO-gt$fibO.F2){$zoneO="Onda3 Dn"}elseif($lcO-gt$flV){$zoneO="Prox FL"}else{$zoneO="Abaixo FL"};$tg=if($lcO-lt$fibO.A0){$staleO=$true;$fibO.A1}else{$fibO.A0}}
        if($tg-ne 0-and$lcO-gt 0){$tgtPctO=[Math]::Round(($tg-$lcO)/$lcO*100,1)}
    }
    $dirO=if($clsO.Dir-eq"BUY"){"alta"}elseif($clsO.Dir-eq"SELL"){"baixa"}else{"none"}
    $ondaAtiva=($zoneO-eq"Onda3 Up"-or$zoneO-eq"Onda3 Dn")
    $onda3Forte=(($clsO.Score-ge 2)-or$ondaAtiva)-and(-not$staleO)-and($dirO-ne"none")

    # ---- TRIFECTA (2m/5m/15m) ----
    $rt=@{};$bias=@{}
    foreach($iv in @("2m","5m","15m")){
        $rd=$rawMap["${iv}_$t"]
        if($rd){$b=Build-OHLC $rd;$rt[$iv]=Detect-Eleph $b.O $b.H $b.L $b.C $LB[$iv]
            $mm=Get-SMA $b.C $MM_LONG;$li=$b.N-1
            $bias[$iv]=if($li-ge 0-and -not[double]::IsNaN($mm[$li])){if($b.C[$li]-gt$mm[$li]){1}else{-1}}else{0}
        }else{$rt[$iv]=@{Dir="NONE"};$bias[$iv]=0}
    }
    $et2=$rt["2m"];$et5=$rt["5m"];$et15=$rt["15m"]
    $clsT=Classify-Eleph $et2 $et5 $et15
    $bBull=@($bias.Values|Where-Object{$_-eq 1}).Count;$bBear=@($bias.Values|Where-Object{$_-eq -1}).Count;$mmTot=$bBull+$bBear
    $mmDir=if($mmTot-gt 0-and$bBear-eq 0){"BULL"}elseif($mmTot-gt 0-and$bBull-eq 0){"BEAR"}else{"NONE"}
    $triFull=(($clsT.Dir-ne"NONE")-and($mmDir-eq$clsT.Dir)-and($clsT.Score-ge 2)-and($mmTot-ge 2))
    $primT=$null;$primTF=""
    if($clsT.Dir-ne"NONE"){foreach($pp in @(@($et15,"15m"),@($et5,"5m"),@($et2,"2m"))){if($pp[0].Dir-eq$clsT.Dir){$primT=$pp[0];$primTF=$pp[1];break}}}
    $gatT=0.0;$forcaT=0.0
    if($primT){if($clsT.Dir-eq"BULL"){$gatT=$primT.High}else{$gatT=$primT.Low};$forcaT=$primT.Strength}
    $dirT=if($clsT.Dir-eq"BULL"){"alta"}elseif($clsT.Dir-eq"BEAR"){"baixa"}else{"none"}
    $trifForte=(($clsT.Score-ge 2)-or$triFull)-and($dirT-ne"none")

    # ---- CRUZAMENTO ----
    $lc=if($lcO-gt 0){$lcO}else{0}
    $verdict="-";$convDir="none";$rank=0
    if($dirO-ne"none"-and$dirT-ne"none"){
        if($dirO-eq$dirT){$verdict="CONVERGENTE";$convDir=$dirO;$rank=100+$clsO.Score*8+$clsT.Score*8+$(if($triFull){20}else{0})}
        else{$verdict="DIVERGENTE";$convDir="none";$rank=15}
    }elseif($dirT-ne"none"-and$trifForte){$verdict="SO-TRIFECTA";$convDir=$dirT;$rank=55+$clsT.Score*8+$(if($triFull){20}else{0})}
    elseif($dirO-ne"none"-and$onda3Forte){$verdict="SO-ONDA3";$convDir=$dirO;$rank=50+$clsO.Score*8}
    if($verdict-eq"-"){continue}  # nao e destaque -> fora do resumo
    $results+=[PSCustomObject]@{
        T=$t;Verdict=$verdict;ConvDir=$convDir;Rank=$rank;LC=[Math]::Round($lc,2)
        ODir=$dirO;OConv=$clsO.Conv;OZone=$zoneO;OTgt=$tgtPctO;OStale=$staleO
        TDir=$dirT;TConv=$clsT.Conv;TFull=$triFull;TGat=$gatT;TForca=$forcaT;TPrimTF=$primTF;TMM=$mmDir;TMMtot=$mmTot
    }
}
$sorted=$results|Sort-Object Rank -Descending
$nConvA=@($sorted|Where-Object{$_.Verdict-eq"CONVERGENTE"-and$_.ConvDir-eq"alta"}).Count
$nConvB=@($sorted|Where-Object{$_.Verdict-eq"CONVERGENTE"-and$_.ConvDir-eq"baixa"}).Count
$nIso=@($sorted|Where-Object{$_.Verdict-eq"SO-TRIFECTA"-or$_.Verdict-eq"SO-ONDA3"}).Count
$nDiv=@($sorted|Where-Object{$_.Verdict-eq"DIVERGENTE"}).Count

# ---- Noticias (so dos papeis em destaque) ----
$newsMap=@{}
if($sorted.Count-gt 0){
    $ntasks=@{}
    foreach($r in $sorted){ if($coName.ContainsKey($r.T)){ try{$ntasks[$r.T]=Get-NewsTask ($r.T+$newsSuffix)}catch{} } }
    foreach($r in $sorted){ if($ntasks.ContainsKey($r.T)){ try{$newsMap[$r.T]=Pick-News ($ntasks[$r.T].GetAwaiter().GetResult()) $coName[$r.T]}catch{$newsMap[$r.T]=$null} } }
}
$nNews=@($sorted|Where-Object{$newsMap[$_.T]}).Count
Write-Host "Noticias relevantes: $nNews papeis"

# ============ HTML ============
function ArrowH($d){ if($d-eq"alta"){"<span style='color:#1a7a3a;font-weight:700'>&uarr;</span>"}elseif($d-eq"baixa"){"<span style='color:#c0392b;font-weight:700'>&darr;</span>"}else{"<span style='color:#888'>&harr;</span>"} }
function VerdBadge($r){
    switch($r.Verdict){
        "CONVERGENTE"{ $bg=if($r.ConvDir-eq"alta"){"#1a7a3a"}else{"#c0392b"};$tx=if($r.ConvDir-eq"alta"){"CONVERG. ALTA"}else{"CONVERG. BAIXA"};"<span style='background:$bg;color:#fff;font-size:9px;font-weight:700;padding:2px 6px;border-radius:3px'>$tx</span>" }
        "SO-TRIFECTA"{ "<span style='background:#FAC775;color:#633806;font-size:9px;font-weight:600;padding:2px 6px;border-radius:3px'>S&Oacute; TRIFECTA</span>" }
        "SO-ONDA3"{ "<span style='background:#B5D4F4;color:#0C447C;font-size:9px;font-weight:600;padding:2px 6px;border-radius:3px'>S&Oacute; ONDA 3</span>" }
        "DIVERGENTE"{ "<span style='background:#F0997B;color:#4A1B0C;font-size:9px;font-weight:600;padding:2px 6px;border-radius:3px'>DIVERG&Ecirc;NCIA</span>" }
        default{ "" }
    }
}
$rows="";$rankNum=0
foreach($r in $sorted){
    $rankNum++
    $newsFlag=if($newsMap[$r.T]){" <span title='Noticia que pode impactar o preco'>&#128240;</span>"}else{""}
    $oCell=if($r.ODir-eq"none"){"<span style='color:#bbb'>&mdash;</span>"}else{"$(ArrowH $r.ODir) <small>$($r.OConv)$(if($r.OZone-ne'-'){' &middot; '+$r.OZone}else{''})$(if($r.OStale){' &#9888;'}else{''})</small>"}
    $tBadge=if($r.TFull){" <b style='color:#0a7d3a'>&#10003;</b>"}else{""}
    $tCell=if($r.TDir-eq"none"){"<span style='color:#bbb'>&mdash;</span>"}else{"$(ArrowH $r.TDir) <small>$($r.TConv)$tBadge$(if($r.TForca-ne 0){' &middot; '+$r.TForca+'x'}else{''})</small>"}
    $niv=@()
    if($r.TGat-ne 0){$niv+="Gat $(PxFmt $r.TGat)"}
    if($r.OTgt-ne 0){$sgn=if($r.OTgt-gt 0){"+"}else{""};$niv+="Alvo $sgn$($r.OTgt)%"}
    $nivCell=if($niv.Count-gt 0){$niv -join " / "}else{"&mdash;"}
    $rowBg=if($r.Verdict-eq"CONVERGENTE"){if($r.ConvDir-eq"alta"){"background:rgba(26,122,58,0.09);"}else{"background:rgba(192,57,43,0.07);"}}elseif($r.Verdict-eq"DIVERGENTE"){"background:rgba(240,153,123,0.07);"}else{""}
    $rows+="<tr style='border-bottom:1px solid #f0f0f0;$rowBg'><td style='padding:5px 6px;color:#999;font-size:10px'>$rankNum</td><td style='padding:5px 6px;font-weight:700;font-size:12px'>$($r.T)$newsFlag</td><td style='padding:5px 6px'>$(VerdBadge $r)</td><td style='padding:5px 6px;font-size:10px;color:#444'>$oCell</td><td style='padding:5px 6px;font-size:10px;color:#444'>$tCell</td><td style='padding:5px 6px;text-align:right;font-size:11px'>$(PxFmt $r.LC)</td><td style='padding:5px 6px;font-size:10px;text-align:right;color:#333'>$nivCell</td></tr>"
}
if($sorted.Count-eq 0){$rows="<tr><td colspan='7' style='padding:14px;text-align:center;color:#888;font-size:11px'>Nenhum papel em destaque por convergencia neste momento.</td></tr>"}

function JoinT($a){ if($a.Count-eq 0){return "nenhum"}; return ($a -join ", ") }
$dCA=@($sorted|Where-Object{$_.Verdict-eq"CONVERGENTE"-and$_.ConvDir-eq"alta"})
$dCB=@($sorted|Where-Object{$_.Verdict-eq"CONVERGENTE"-and$_.ConvDir-eq"baixa"})
$dST=@($sorted|Where-Object{$_.Verdict-eq"SO-TRIFECTA"})
$dSO=@($sorted|Where-Object{$_.Verdict-eq"SO-ONDA3"})
$dDV=@($sorted|Where-Object{$_.Verdict-eq"DIVERGENTE"})
$dq=@()
if($dCA.Count-gt 0){$dq+="<div style='margin-bottom:5px'><span style='color:#1a7a3a;font-weight:800'>&#9650; CONVERG&Ecirc;NCIA DE ALTA: </span>$(JoinT ($dCA|ForEach-Object{ ""$($_.T)$(if($_.TGat-ne 0){' (gatilho '+(PxFmt $_.TGat)+')'}else{''})"" })) &mdash; as duas vis&otilde;es apontam compra.</div>"}
if($dCB.Count-gt 0){$dq+="<div style='margin-bottom:5px'><span style='color:#c0392b;font-weight:800'>&#9660; CONVERG&Ecirc;NCIA DE BAIXA: </span>$(JoinT ($dCB|ForEach-Object{ ""$($_.T)$(if($_.TGat-ne 0){' (gatilho '+(PxFmt $_.TGat)+')'}else{''})"" })) &mdash; as duas vis&otilde;es apontam venda.</div>"}
if($dST.Count-gt 0){$dq+="<div style='margin-bottom:5px'><span style='color:#9b6000;font-weight:700'>S&oacute; Trifecta (forte): </span>$(JoinT ($dST|ForEach-Object{ ""$($_.T) ($($_.TDir))"" })).</div>"}
if($dSO.Count-gt 0){$dq+="<div style='margin-bottom:5px'><span style='color:#0C447C;font-weight:700'>S&oacute; Onda 3 (forte): </span>$(JoinT ($dSO|ForEach-Object{ ""$($_.T) ($($_.ODir))"" })).</div>"}
if($dDV.Count-gt 0){$dq+="<div style='margin-bottom:5px'><span style='color:#7a2c2c;font-weight:700'>Diverg&ecirc;ncia (vis&otilde;es em conflito, evitar): </span>$(JoinT ($dDV|ForEach-Object{$_.T})).</div>"}
$dq+="<div><span style='color:#333;font-weight:700'>Resumo: </span>Converg. alta=$nConvA, converg. baixa=$nConvB, isolados fortes=$nIso, diverg&ecirc;ncias=$nDiv.</div>"
$destaques="<div style='margin-top:14px;padding:12px 14px;background:#f3effb;border:1px solid #ddd0f0;border-radius:6px'><div style='font-size:11px;font-weight:700;color:#4a2c7a;margin-bottom:8px;text-transform:uppercase;letter-spacing:0.4px'>Leitura do momento</div><div style='font-size:11px;color:#333;line-height:1.7'>$($dq -join '')</div></div>"

$newsLines=@()
foreach($r in $sorted){ $nw=$newsMap[$r.T]; if($nw){ $newsLines+="<div style='margin-bottom:4px'><b>$($r.T):</b> <a href='$($nw.Link)' style='color:#1155cc;text-decoration:none'>$($nw.Title)</a></div>" } }
$newsBlock=if($newsLines.Count-gt 0){"<div style='margin-top:12px;padding:10px 12px;background:#fff8e8;border:1px solid #f0e2c8;border-radius:6px'><div style='font-size:11px;font-weight:700;color:#7a5c00;margin-bottom:6px'>&#128240; NOT&Iacute;CIAS QUE PODEM IMPACTAR O PRE&Ccedil;O</div><div style='font-size:11px;line-height:1.6'>$($newsLines -join '')</div></div>"}else{""}
$htmlBody="<html><head><meta charset='UTF-8'><title>Resumo Convergencia $mkt</title></head><body style='font-family:Arial,sans-serif;font-size:12px;color:#222;max-width:760px;margin:0 auto;padding:16px'><table width='100%' style='background:#2a1e3e;border-radius:6px;padding:14px 18px;margin-bottom:14px'><tr><td><span style='font-size:17px;font-weight:700;color:#fff'>&#127919; Resumo Converg&ecirc;ncia &mdash; EUA</span> <span style='background:#FAC775;color:#633806;padding:1px 6px;border-radius:3px;font-size:10px;font-weight:700'>$readLabel</span><br><span style='font-size:11px;color:#cdb8f0'><b style='color:#ffe8a0'>$dateStr</b> | Trifecta &times; Onda 3 | s&oacute; os destaques | $($tickers.Count) pap&eacute;is US</span></td><td style='text-align:right;vertical-align:top'><span style='background:#1a7a3a;color:#fff;padding:2px 7px;border-radius:3px;font-size:10px;font-weight:600'>&#9650; $nConvA</span>&nbsp;<span style='background:#c0392b;color:#fff;padding:2px 7px;border-radius:3px;font-size:10px;font-weight:600'>&#9660; $nConvB</span></td></tr></table><table width='100%' cellspacing='0' cellpadding='0' style='border-collapse:collapse;border:1px solid #e8e8e8'><thead><tr style='background:#f8f8f8;border-bottom:2px solid #e0e0e0'><th style='padding:6px;font-size:10px;color:#666;text-align:left;width:22px'>#</th><th style='padding:6px;font-size:10px;color:#666;text-align:left;width:50px'>Papel</th><th style='padding:6px;font-size:10px;color:#666;text-align:left;width:96px'>Veredito</th><th style='padding:6px;font-size:10px;color:#666;text-align:left;width:150px'>Onda 3</th><th style='padding:6px;font-size:10px;color:#666;text-align:left;width:150px'>Trifecta</th><th style='padding:6px;font-size:10px;color:#666;text-align:right;width:70px'>Pre&ccedil;o</th><th style='padding:6px;font-size:10px;color:#666;text-align:right;width:120px'>N&iacute;veis</th></tr></thead><tbody>$rows</tbody></table>$destaques$newsBlock<div style='margin-top:14px;padding:10px 12px;background:#f9f9f9;border-radius:4px;font-size:10px;color:#555;line-height:1.8'><strong>Como ler &mdash;</strong> Este resumo cruza as duas estrat&eacute;gias e mostra <strong>s&oacute; os destaques</strong>. <strong>CONVERG&Ecirc;NCIA</strong> = Trifecta (elefante 2/5/15 + MM200) E Onda 3 (MIMA/Fractal/Fib 1/5/15) apontam a MESMA dire&ccedil;&atilde;o (maior convic&ccedil;&atilde;o). <strong>S&oacute; Trifecta / S&oacute; Onda 3</strong> = destaque forte de uma vis&atilde;o s&oacute;. <strong>Diverg&ecirc;ncia</strong> = vis&otilde;es em conflito (evitar). Colunas Onda 3 e Trifecta mostram dire&ccedil;&atilde;o + converg&ecirc;ncia interna; &#10003;=Trifecta completa; &#9888;=fractal obsoleto. N&iacute;veis: Gatilho (entrada Trifecta) / Alvo (potencial Onda 3).</div><p style='font-size:10px;color:#aaa;margin-top:10px;text-align:center'>Resumo Converg&ecirc;ncia (Trifecta + Onda 3) &mdash; EUA | Claude Code | Dados: Yahoo Finance | jjovieira@gmail.com</p></body></html>"

if($OutFile -ne ""){$htmlFile=$OutFile}else{$htmlFile=Join-Path $env:USERPROFILE "Downloads\resumo_us_report_$dateFile.html"}
$htmlBody|Out-File $htmlFile -Encoding UTF8
Write-Host "HTML salvo: $htmlFile"
if($OutFile -ne ""){
    "[Resumo US] $readLabel $dateStr ET | Conv:$($nConvA+$nConvB) Iso:$nIso" | Out-File "resumo_us_subject.txt" -Encoding UTF8 -NoNewline;Write-Host "Subject: resumo_us_subject.txt"
    $eT=[char]::ConvertFromUtf32(0x1F3AF);$eC=[char]::ConvertFromUtf32(0x1F7E2);$eV=[char]::ConvertFromUtf32(0x1F534);$eY=[char]::ConvertFromUtf32(0x1F7E1);$eX=[char]::ConvertFromUtf32(0x26A0);$eM=[char]::ConvertFromUtf32(0x1F4E7);$eN=[char]::ConvertFromUtf32(0x1F4F0)
    $tg=@()
    $tg+="<b>$eT Resumo Convergencia US ($readLabel) - $dateStr</b>"
    $tg+="Trifecta x Onda 3 | Conv. alta: $nConvA | Conv. baixa: $nConvB | Isolados: $nIso"
    $tg+=""
    if($dCA.Count-gt 0){$tg+="$eC <b>Convergencia ALTA:</b> $(JoinT ($dCA|ForEach-Object{ ""$($_.T)$(if($_.TGat-ne 0){' (gat '+$ccy+(([double]$_.TGat).ToString('N2',$cult))+')'}else{''})"" }))"}
    if($dCB.Count-gt 0){$tg+="$eV <b>Convergencia BAIXA:</b> $(JoinT ($dCB|ForEach-Object{ ""$($_.T)$(if($_.TGat-ne 0){' (gat '+$ccy+(([double]$_.TGat).ToString('N2',$cult))+')'}else{''})"" }))"}
    if($dST.Count-gt 0-or$dSO.Count-gt 0){$tg+="$eY <b>Isolados fortes:</b> Trifecta: $(JoinT ($dST|ForEach-Object{$_.T})) | Onda3: $(JoinT ($dSO|ForEach-Object{$_.T}))"}
    if($dDV.Count-gt 0){$tg+="$eX <b>Divergencia (evitar):</b> $(JoinT ($dDV|ForEach-Object{$_.T}))"}
    $newsTk=@($sorted|Where-Object{$newsMap[$_.T]}|ForEach-Object{$_.T})
    if($newsTk.Count-gt 0){$tg+="$eN <b>Com noticia relevante:</b> $(JoinT $newsTk)"}
    $tg+=""
    $tg+="$eM Resumo do momento - detalhes nos relatorios das estrategias."
    ($tg -join "`n")|Out-File "resumo_us_telegram.txt" -Encoding UTF8 -NoNewline;Write-Host "Telegram: resumo_us_telegram.txt"
}
if(-not$SemEmail){
    $credFile=Join-Path $env:USERPROFILE "Downloads\.onda3_cred.xml"
    if(Test-Path $credFile){
        try{$cred=Import-Clixml $credFile
            $subject="[Resumo US] $readLabel $dateStr ET | Conv:$($nConvA+$nConvB) Iso:$nIso"
            Send-MailMessage -From $cred.UserName -To "jjovieira@gmail.com" -Subject $subject -Body $htmlBody -BodyAsHtml -SmtpServer "smtp.gmail.com" -Port 587 -UseSsl -Credential $cred -Encoding UTF8
            Write-Host "[OK] Email enviado"
        }catch{Write-Host "[ERRO] SMTP: $_"}
    }else{Write-Host "[AVISO] Sem credenciais. HTML em: $htmlFile"}
}
Write-Host "Resumo $mkt concluido."
