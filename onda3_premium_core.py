# -*- coding: utf-8 -*-
"""
onda3_premium_core.py — ESPELHO (vendor) da tese "Onda 3 — Zona Premium".

⚠️ FONTE CANÔNICA: `Trade JV\\Analise JV\\bridge.py`
   (`_detect_onda3_premium_entries`, `_mima_phi3_series`, `_compute_fractal_series`,
    `_onda3_premium_supports_at`, `_onda3_afast_8x17`, `_onda3_estagio`,
    `_count_price_roc_divergences_mtf` e constantes ONDA3_PREMIUM_*).

Este módulo NÃO evolui a tese por conta própria — é uma cópia fiel para rodar a
MESMA lógica na nuvem (GitHub Actions) sobre candles do Yahoo, em vez do SQLite
de ticks do RTD local. A única diferença arquitetural é a FONTE DOS CANDLES:
a detecção aqui recebe a lista de barras pronta (`detectar_onda3_premium(bars,...)`)
em vez de reconstruí-la de `_build_ohlc_pontos_bars`. Toda a máquina de estados
(gatilho 2 estágios 8×17→34×72, avanço, reteste em suporte, confirmação com Leque
alinhado, preço de entrada refinado) é idêntica linha a linha ao bridge.

Se a tese mudar no bridge.py, replicar aqui. Ver memória [[project_onda3_zona_premium]]
e [[feedback_onda3_marcacoes_parity]].

Sem dependências externas (só stdlib) — roda no runner do GitHub Actions sem pip.
"""
from collections import deque

# ── Constantes (idênticas ao bridge.py) ────────────────────────────────────
FRACTAL_PERIODS = (72, 305, 1292)
FRACTAL_HF_PCT  = 0.214
FRACTAL_LF_PCT  = 0.786

ONDA3_PREMIUM_P_RAPIDA = 8
ONDA3_PREMIUM_P_LENTA = 17
ONDA3_PREMIUM_MIN_AVANCO_PCT = 0.0015
ONDA3_PREMIUM_MAX_BARRAS_CICLO = 100
ONDA3_PREMIUM_ALINHAMENTO_TOL_PCT = 0.0005
ONDA3_PENETRACAO_FORTE_PCT = 0.069
ONDA3_DIVERGENCIA_MIN = 2

ONDA3_DIVERGENCIA_LOOKBACK = 30
ONDA3_DIVERGENCIA_ORDEM = 3
ONDA3_DIVERGENCIA_TF_MINUTOS = 4
ONDA3_DIVERGENCIA_TF_LOOKBACK = 30

ONDA3_305_ACUM_PCT = 0.0008
ONDA3_305_FAR_PCT  = 0.0010

MIMAROC_LOOKBACK = 3


# ── Séries base ────────────────────────────────────────────────────────────
def _rolling_extrema(values, periods=None):
    """Máximo/mínimo móvel por período (deque monotônica, O(n))."""
    periods = periods or FRACTAL_PERIODS
    n = len(values)
    out = {}
    for period in periods:
        highs = [None] * n
        lows = [None] * n
        dq_max = deque()
        dq_min = deque()
        for i, v in enumerate(values):
            while dq_max and values[dq_max[-1]] <= v:
                dq_max.pop()
            dq_max.append(i)
            while dq_min and values[dq_min[-1]] >= v:
                dq_min.pop()
            dq_min.append(i)
            lo = i - period + 1
            while dq_max[0] < lo:
                dq_max.popleft()
            while dq_min[0] < lo:
                dq_min.popleft()
            if i >= period - 1:
                highs[i] = values[dq_max[0]]
                lows[i] = values[dq_min[0]]
        out[period] = (highs, lows)
    return out


def _compute_fractal_series(bars, periods=None):
    """Fractal (78,6%/21,4% sobre 72/305/1292) recalculado EM CADA barra.
    Retorna 1 dict por barra com chaves g{period}/r{period}."""
    periods = periods or FRACTAL_PERIODS
    highs_bar = [b["h"] for b in bars]
    lows_bar = [b["l"] for b in bars]
    rolling_high = _rolling_extrema(highs_bar, periods)
    rolling_low = _rolling_extrema(lows_bar, periods)
    out = [{"key": b["key"]} for b in bars]
    for period in periods:
        hh_series, _ = rolling_high[period]
        _, ll_series = rolling_low[period]
        for i in range(len(bars)):
            hh, ll = hh_series[i], ll_series[i]
            if hh is None or ll is None:
                out[i][f"g{period}"] = None
                out[i][f"r{period}"] = None
                continue
            dist = hh - ll
            out[i][f"g{period}"] = round(hh - dist * FRACTAL_HF_PCT, 4)
            out[i][f"r{period}"] = round(hh - dist * FRACTAL_LF_PCT, 4)
    return out


def _mima_phi3_series(closes, period):
    """MIMA = EMA de período N CHEIO sobre a série (o φ³ é a ESCADA de períodos
    8/17/34/72..., já escolhida pelos chamadores — não um divisor por média)."""
    n = len(closes)
    if n == 0:
        return []
    alpha = min(1.0, 2.0 / (period + 1))
    out = [None] * n
    ema = closes[0]
    for i in range(n):
        c = closes[i]
        ema = c if i == 0 else (c * alpha + ema * (1 - alpha))
        out[i] = ema if i >= period else None
    return out


def _mimaroc_series(dema, lookback=MIMAROC_LOOKBACK):
    n = len(dema)
    out = [None] * n
    for i in range(lookback, n):
        antes = dema[i - lookback]
        if dema[i] is None or antes is None or antes == 0:
            continue
        out[i] = (dema[i] - antes) / abs(antes) * 100.0
    return out


def _resample_closes(bars, tf_minutes):
    """Agrupa o fechamento de cada `tf_minutes` barras consecutivas (posicional)."""
    closes = [b["c"] for b in bars]
    if tf_minutes <= 1:
        return closes
    out = []
    for i in range(0, len(closes), tf_minutes):
        chunk = closes[i:i + tf_minutes]
        if chunk:
            out.append(chunk[-1])
    return out


# ── Divergências preço×ROC (informativo, não filtra) ───────────────────────
def _find_local_extremes(values, is_low, order=ONDA3_DIVERGENCIA_ORDEM):
    idxs = []
    n = len(values)
    for i in range(order, n - order):
        if values[i] is None:
            continue
        janela = values[i - order:i + order + 1]
        if any(v is None for v in janela):
            continue
        if is_low and values[i] == min(janela):
            idxs.append(i)
        elif not is_low and values[i] == max(janela):
            idxs.append(i)
    return idxs


def _count_price_roc_divergences(closes, roc, i, bull, lookback=ONDA3_DIVERGENCIA_LOOKBACK):
    start = max(0, i - lookback)
    is_low = bull
    ext_idxs = [start + j for j in _find_local_extremes(closes[start:i + 1], is_low)]
    if len(ext_idxs) < 2:
        return 0
    count = 0
    for a, b in zip(ext_idxs, ext_idxs[1:]):
        if roc[a] is None or roc[b] is None:
            continue
        preco_novo_extremo = (closes[b] < closes[a]) if is_low else (closes[b] > closes[a])
        roc_confirma = (roc[b] <= roc[a]) if is_low else (roc[b] >= roc[a])
        if preco_novo_extremo and not roc_confirma:
            count += 1
    return count


def _count_price_roc_divergences_mtf(bars, i, bull,
                                     tf_minutos=ONDA3_DIVERGENCIA_TF_MINUTOS,
                                     lookback_candles=ONDA3_DIVERGENCIA_TF_LOOKBACK):
    closes_tf = _resample_closes(bars[:i + 1], tf_minutos)
    if len(closes_tf) < 34:
        return 0
    dema34_tf = _mima_phi3_series(closes_tf, 34)
    roc34_tf = _mimaroc_series(dema34_tf)
    i_tf = len(closes_tf) - 1
    return _count_price_roc_divergences(closes_tf, roc34_tf, i_tf, bull, lookback=lookback_candles)


# ── Suportes / afastamento / estágio ───────────────────────────────────────
def _onda3_premium_supports_at(dema34, dema72, fs_series, i, bull):
    """MIMA34, MIMA72 e a linha do Fractal72 do lado certo da direção
    (r72=21,4% p/ ALTA; g72=78,6% p/ BAIXA)."""
    fs = fs_series[i]
    fractal_nome = "Fractal72 21,4%" if bull else "Fractal72 78,6%"
    fractal_nivel = fs.get("r72") if bull else fs.get("g72")
    return {"MIMA34": dema34[i], "MIMA72": dema72[i], fractal_nome: fractal_nivel}


def _onda3_afast_8x17(dema8, dema17, st, bull):
    """Distância do preço de entrada até a zona do cruzamento 8x17 (informativo)."""
    i = st.get("entrada_i")
    close = st.get("entrada_close")
    if i is None or not close or dema8[i] is None or dema17[i] is None:
        return {"zona_8x17": None, "afast_8x17_pct": None}
    zona = (dema8[i] + dema17[i]) / 2
    afast = ((close - zona) / close * 100) if bull else ((zona - close) / close * 100)
    return {"zona_8x17": zona, "afast_8x17_pct": round(afast, 3)}


def _onda3_estagio(close, m305, bull):
    if m305 is None or not close:
        return "premium"
    d = (close - m305) / close
    if bull:
        if d < -ONDA3_305_ACUM_PCT:
            return "acumulacao"
        if d > ONDA3_305_FAR_PCT:
            return "esticado"
        return "premium"
    if d > ONDA3_305_ACUM_PCT:
        return "premium"
    if d < -ONDA3_305_FAR_PCT:
        return "esticado"
    return "premium"


# ── Máquina de estados (idêntica ao bridge, só muda a FONTE dos candles) ────
def detectar_onda3_premium(bars, allowed_dates, win_start="10:00", win_end="17:00"):
    """Detecta entradas de Onda 3 — Zona Premium sobre `bars` (lista de dicts com
    chaves key='YYYY-MM-DD HH:MM', o/h/l/c). `allowed_dates` = conjunto de datas
    (YYYY-MM-DD) em que uma entrada pode ser emitida (a máquina de estados roda
    sobre TODAS as barras p/ warmup e ciclos que atravessam o fim de semana, mas
    só emite gatilho dentro dessas datas e da janela de horário).

    Equivale ao `in_window` do bridge (lá: key_date == date_str). Toda a lógica
    das 4 fases é a mesma."""
    n = len(bars)
    if n < FRACTAL_PERIODS[0]:
        return []
    closes = [b["c"] for b in bars]
    highs = [b["h"] for b in bars]
    lows = [b["l"] for b in bars]
    dema8 = _mima_phi3_series(closes, ONDA3_PREMIUM_P_RAPIDA)
    dema17 = _mima_phi3_series(closes, ONDA3_PREMIUM_P_LENTA)
    dema34 = _mima_phi3_series(closes, 34)
    dema72 = _mima_phi3_series(closes, 72)
    dema305 = _mima_phi3_series(closes, 305)
    roc17 = _mimaroc_series(dema17)
    roc34 = _mimaroc_series(dema34)
    roc72 = _mimaroc_series(dema72)
    fs_series = _compute_fractal_series(bars)

    entries = []
    estado = {"ALTA": None, "BAIXA": None}

    for i in range(n):
        key_date, key_time = bars[i]["key"][:10], bars[i]["key"][11:16]
        in_window = key_date in allowed_dates and win_start <= key_time <= win_end
        close, hi, lo = closes[i], highs[i], lows[i]
        if dema8[i] is None or dema17[i] is None or dema34[i] is None or dema72[i] is None:
            continue

        for direcao, bull in (("ALTA", True), ("BAIXA", False)):
            st = estado[direcao]

            # 1) GATILHO: cruzamento MIMA34×72 na direção, só conta com o AVISO 8×17
            if st is None:
                if i == 0 or dema34[i - 1] is None or dema72[i - 1] is None:
                    continue
                cruzou_34x72 = (dema34[i - 1] <= dema72[i - 1] and dema34[i] > dema72[i]) if bull \
                    else (dema34[i - 1] >= dema72[i - 1] and dema34[i] < dema72[i])
                aviso_ok = (dema8[i] > dema17[i]) if bull else (dema8[i] < dema17[i])
                if cruzou_34x72 and aviso_ok:
                    estado[direcao] = {"fase": "AVANCO", "cross_close": close, "extremo": close,
                                        "barras": 0, "roc17_pullback": False}
                continue

            st["barras"] += 1
            if st["barras"] > ONDA3_PREMIUM_MAX_BARRAS_CICLO:
                estado[direcao] = None
                continue

            # Cruzamento REVERSO do 34×72 invalida imediatamente
            cruzou_reverso = (dema34[i - 1] >= dema72[i - 1] and dema34[i] < dema72[i]) if bull \
                else (dema34[i - 1] <= dema72[i - 1] and dema34[i] > dema72[i])
            if cruzou_reverso:
                estado[direcao] = None
                continue

            # 2) AVANCO
            if st["fase"] == "AVANCO":
                if bull:
                    st["extremo"] = max(st["extremo"], close)
                    avancou = (st["extremo"] - st["cross_close"]) / st["cross_close"] >= ONDA3_PREMIUM_MIN_AVANCO_PCT
                    puxou = close < closes[i - 1]
                else:
                    st["extremo"] = min(st["extremo"], close)
                    avancou = (st["cross_close"] - st["extremo"]) / st["cross_close"] >= ONDA3_PREMIUM_MIN_AVANCO_PCT
                    puxou = close > closes[i - 1]
                if avancou and puxou:
                    st["fase"] = "TESTE"
                continue

            # 3) TESTE: pavio toca suporte + fechamento segura
            if st["fase"] == "TESTE":
                if roc17[i] is not None and roc34[i] is not None and roc72[i] is not None:
                    roc17_contra = (roc17[i] < 0) if bull else (roc17[i] > 0)
                    roc34_favor = (roc34[i] > 0) if bull else (roc34[i] < 0)
                    roc72_favor = (roc72[i] > 0) if bull else (roc72[i] < 0)
                    if roc17_contra and roc34_favor and roc72_favor:
                        st["roc17_pullback"] = True

                supports = _onda3_premium_supports_at(dema34, dema72, fs_series, i, bull)
                suporte_tocado = None
                for nome, nivel in supports.items():
                    if nivel is None:
                        continue
                    if bull and lo <= nivel and close > nivel:
                        suporte_tocado = nome
                        break
                    if not bull and hi >= nivel and close < nivel:
                        suporte_tocado = nome
                        break
                if suporte_tocado:
                    st["fase"] = "CONFIRMACAO"
                    st["suporte"] = suporte_tocado
                    st["suporte_nivel"] = supports[suporte_tocado]
                    st["test_close"] = close
                    st["test_open"] = bars[i]["o"]
                    st["test_high"] = hi
                    st["test_low"] = lo
                    st["entrada_close"] = close
                    st["entrada_hora"] = key_time + ":00"
                    st["entrada_i"] = i
                    st["entrada_key"] = bars[i]["key"]
                    continue
                niveis_validos = [v for v in supports.values() if v is not None]
                if niveis_validos:
                    pior = min(niveis_validos) if bull else max(niveis_validos)
                    if (bull and close < pior) or (not bull and close > pior):
                        estado[direcao] = None
                continue

            # 4) CONFIRMACAO: candle seguinte retoma + Leque alinhado
            if st["fase"] == "CONFIRMACAO":
                novo_extremo = (close < st["entrada_close"]) if bull else (close > st["entrada_close"])
                if novo_extremo:
                    st["entrada_close"] = close
                    st["entrada_hora"] = key_time + ":00"
                    st["entrada_i"] = i
                    st["entrada_key"] = bars[i]["key"]
                resumiu = close > st["test_close"] if bull else close < st["test_close"]
                if resumiu:
                    def _par_ok(rapida, lenta):
                        return rapida >= lenta * (1 - ONDA3_PREMIUM_ALINHAMENTO_TOL_PCT) if bull \
                            else rapida <= lenta * (1 + ONDA3_PREMIUM_ALINHAMENTO_TOL_PCT)
                    alinhado = _par_ok(dema8[i], dema17[i]) and _par_ok(dema17[i], dema34[i]) \
                        and _par_ok(dema34[i], dema72[i])
                    if alinhado and in_window:
                        divergencias = _count_price_roc_divergences_mtf(bars, i, bull)
                        estagio = _onda3_estagio(st["entrada_close"], dema305[i], bull)
                        penetracao_pct = None
                        sup, tlo, thi = st.get("suporte_nivel"), st.get("test_low"), st.get("test_high")
                        if sup and tlo is not None and thi is not None:
                            penetracao_pct = round(((sup - tlo) / sup * 100) if bull else ((thi - sup) / sup * 100), 4)
                        entries.append({
                            "direcao": direcao,
                            "key": st.get("entrada_key"),
                            "hora": st["entrada_hora"], "preco_entrada": st["entrada_close"],
                            "key_confirmacao": bars[i]["key"],
                            "hora_confirmacao": key_time + ":00", "preco_confirmacao": close,
                            "suporte_tocado": st["suporte"],
                            "suporte_nivel": st.get("suporte_nivel"),
                            "test_open": st.get("test_open"), "test_high": st.get("test_high"),
                            "test_low": st.get("test_low"), "test_close": st.get("test_close"),
                            "penetracao_pct": penetracao_pct,
                            "penetracao_forte": bool(penetracao_pct is not None
                                                     and penetracao_pct >= ONDA3_PENETRACAO_FORTE_PCT),
                            "divergencias_roc34": divergencias,
                            "divergencia_confirmada": divergencias >= ONDA3_DIVERGENCIA_MIN,
                            "roc17_pullback": st.get("roc17_pullback", False),
                            **_onda3_afast_8x17(dema8, dema17, st, bull),
                            "estagio": estagio})
                    estado[direcao] = None
    return entries
