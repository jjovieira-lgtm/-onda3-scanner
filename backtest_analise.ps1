function Pct2($p) {
    $loc = [System.Globalization.CultureInfo]::GetCultureInfo("pt-BR")
    $s = if ($p -ge 0) { "+" } else { "" }
    return ($s + $p.ToString("N2", $loc) + "%")
}
function StratRow($entries, $label) {
    $ac = @($entries | Where-Object { $_.res -eq "acerto" })
    $er = @($entries | Where-Object { $_.res -eq "erro"   })
    $ne = @($entries | Where-Object { $_.res -eq "neutro" })
    if ($entries.Count -eq 0) { return "" }
    $acTxt = if ($ac.Count -gt 0) { "Acertos: " + (($ac | ForEach-Object { $_.t + " (" + (Pct2 $_.pct) + ")" }) -join ", ") } else { "" }
    $erTxt = if ($er.Count -gt 0) { "Erros: "   + (($er | ForEach-Object { $_.t + " (" + (Pct2 $_.pct) + ")" }) -join ", ") } else { "" }
    $neTxt = if ($ne.Count -gt 0) { "Neutros: " + (($ne | ForEach-Object { $_.t }) -join ", ") }                               else { "" }
    $acHtml = if ($ac.Count -gt 0) { "<span style='color:#1a7a3a'>$acTxt</span>. " } else { "" }
    $erHtml = if ($er.Count -gt 0) { "<span style='color:#c0392b'>$erTxt</span>. " } else { "" }
    $neHtml = if ($ne.Count -gt 0) { "<span style='color:#888'>$neTxt</span>" }     else { "" }
    "<div style='margin-bottom:6px'><b>$label</b>: $acHtml$erHtml$neHtml</div>"
}
function Build-Analise($allO3, $br, $us, $tBR, $tUS, $logCount) {
    $loc = [System.Globalization.CultureInfo]::GetCultureInfo("pt-BR")
    $allEntries = @($allO3) + @($br) + @($us)
    $totAc = @($allEntries | Where-Object { $_.res -eq "acerto" }).Count
    $totEr = @($allEntries | Where-Object { $_.res -eq "erro"   }).Count
    $totNe = @($allEntries | Where-Object { $_.res -eq "neutro" }).Count
    $totAt = $totAc + $totEr
    $taxa   = if ($totAt -gt 0) { [Math]::Round($totAc / $totAt * 100, 1) } else { 0.0 }
    $cor    = if ($taxa -ge 60) { "#1a7a3a" } elseif ($taxa -ge 40) { "#b7600a" } else { "#c0392b" }
    $sessao = if ($taxa -ge 60) { "Sessao positiva" } elseif ($taxa -ge 40) { "Sessao neutra" } else { "Sessao negativa" }
    $pctStr = $taxa.ToString("N1",$loc)
    $nSinais = $allEntries.Count
    $rowO3  = StratRow $allO3 "Onda 3 BR Swing + Day Trade BR + Day Trade US"
    $rowBR  = StratRow $br    "Resumo Convergencia BR"
    $rowUS  = StratRow $us    "Resumo Convergencia US"
    $rowTBR = if ($tBR.Count -gt 0) { StratRow $tBR "Trifecta BR" } else { "" }
    $rowTUS = if ($tUS.Count -gt 0) { StratRow $tUS "Trifecta US" } else { "" }
    $rank = @($allEntries | Where-Object { $_.res -ne "neutro" } | Sort-Object { [Math]::Abs($_.pct) } -Descending)
    $destHtml = ""
    if ($rank.Count -gt 0) {
        $melhor = $rank | Where-Object { $_.res -eq "acerto" } | Select-Object -First 1
        $pior   = $rank | Where-Object { $_.res -eq "erro"   } | Select-Object -First 1
        $mTxt = if ($melhor) { "<span style='color:#1a7a3a'>Melhor: $($melhor.t) $(Pct2 $melhor.pct) ($($melhor.dir))</span>" } else { "" }
        $pTxt = if ($pior)   { "<span style='color:#c0392b'>Pior: $($pior.t) $(Pct2 $pior.pct) ($($pior.dir))</span>" }         else { "" }
        $sep  = if ($melhor -and $pior) { " -- " } else { "" }
        $destHtml = "<div style='margin-top:6px;font-size:11px'>$mTxt$sep$pTxt</div>"
    }
    $notaNivel = if ($logCount -lt 3) { "Resumo semanal ativo a partir de 3 sessoes." } elseif ($logCount -lt 8) { "Resumo quinzenal ativo a partir de 8 sessoes (atual: $logCount)." } else { "Base suficiente para analise semanal e quinzenal." }
    $notaHtml = "<div style='margin-top:10px;padding:8px 10px;background:#f0f7ff;border-left:3px solid #aac4ff;border-radius:3px;font-size:10px;color:#555'>Base estatistica: $logCount sessao(es). $notaNivel</div>"
    $inner  = "<div style='font-size:11px;font-weight:700;color:#333;text-transform:uppercase;letter-spacing:0.4px;margin-bottom:10px'>Analise do Pregao</div>"
    $inner += "<div style='font-size:12px;font-weight:700;color:$cor;margin-bottom:8px'>$sessao - Taxa: $pctStr% - $totAc acertos / $totEr erros / $totNe neutros - $nSinais sinais</div>"
    $inner += $rowO3 + $rowBR + $rowUS + $rowTBR + $rowTUS + $destHtml + $notaHtml
    return "<div style='margin-top:20px;padding:14px 16px;background:#fafafa;border:1px solid #ddd;border-radius:6px'>$inner</div>"
}
