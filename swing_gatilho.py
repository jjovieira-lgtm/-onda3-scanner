# -*- coding: utf-8 -*-
"""
swing_gatilho.py — SWING Gatilho (Onda 3 — Zona Premium, 30min, semana corrente).

Roda na nuvem (GitHub Actions). Para cada uma das 35 ações BR:
  1. Baixa candles de 30min do Yahoo (~60d de warmup).
  2. Roda a MESMA detecção da Onda 3 Premium do bridge.py (via onda3_premium_core),
     emitindo gatilhos só na SEMANA CORRENTE (seg-sex), na sessão 10:00-17:00.
  3. Apura, para cada gatilho, as bandas de 3% (Banda 1) e 6% (Banda 2) olhando
     os candles seguintes — quando bateu, % atual e drawdown até a Banda 1.
  4. Mantém o estado da semana em swing_gatilho_state.json (só p/ preservar o
     "primeiro visto" de cada gatilho; a detecção é determinística sobre o Yahoo).
  5. Gera swing_gatilho.html (cards no estilo do Trade Gatilho) + o texto do Telegram.

Sem dependências externas (stdlib) — não precisa de pip no runner.
Fonte canônica da tese: Trade JV\\Analise JV\\bridge.py (ver onda3_premium_core.py).
"""
import argparse
import json
import ssl
import sys
import time
import urllib.request
from datetime import datetime, timedelta, timezone

from onda3_premium_core import detectar_onda3_premium

# 35 ações BR (watchlist RTD do IBRA LIVE — mesma lista do onda3_daily_scan.ps1)
TICKERS = ["ABEV3", "ASAI3", "AXIA3", "B3SA3", "BBAS3", "BBDC4", "BBSE3", "BEEF3",
           "BPAC11", "BRAV3", "CSAN3", "CYRE3", "DIRR3", "EGIE3", "EMBJ3", "EQTL3",
           "GGBR4", "HAPV3", "ITUB4", "LREN3", "MGLU3", "MOVI3", "MULT3", "NATU3",
           "PETR4", "PRIO3", "RADL3", "RAIL3", "RDOR3", "RENT3", "SBSP3", "SUZB3",
           "USIM5", "VALE3", "WEGE3"]

BAND1_PCT = 0.03    # Banda 1 = alvo de 3%
BAND2_PCT = 0.06    # Banda 2 = alvo de 6%
SESSION_START = "10:00"
SESSION_END = "17:00"
BRT = timezone(timedelta(hours=-3))     # B3 não tem horário de verão desde 2019
UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"
PAGES_URL = "https://jjovieira-lgtm.github.io/-onda3-scanner/"

DIAS_PT = ["Seg", "Ter", "Qua", "Qui", "Sex", "Sáb", "Dom"]

# Contexto SSL: seguro por padrão (nuvem/Ubuntu). Só desligado com --insecure,
# necessário APENAS nesta máquina local (Root CA malformado, ver
# [[reference_ssl_cert_none_maquina]]) — nunca ativar no GitHub Actions.
_SSL_CTX = None


# ── Yahoo ──────────────────────────────────────────────────────────────────
def fetch_yahoo_30m(ticker, rng="60d"):
    """Retorna lista de barras {key='YYYY-MM-DD HH:MM', o,h,l,c} em horário de
    Brasília, ordem cronológica. Vazio em caso de falha."""
    url = (f"https://query1.finance.yahoo.com/v8/finance/chart/{ticker}.SA"
           f"?interval=30m&range={rng}&includePrePost=false")
    for tentativa in range(3):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": UA})
            with urllib.request.urlopen(req, timeout=30, context=_SSL_CTX) as resp:
                data = json.load(resp)
            res = data["chart"]["result"][0]
            ts = res["timestamp"]
            q = res["indicators"]["quote"][0]
            o, h, l, c = q["open"], q["high"], q["low"], q["close"]
            bars = []
            for k in range(len(ts)):
                if None in (o[k], h[k], l[k], c[k]):
                    continue
                dt = datetime.fromtimestamp(ts[k], BRT)
                hhmm = dt.strftime("%H:%M")
                if not (SESSION_START <= hhmm <= "17:30"):
                    continue
                bars.append({"key": dt.strftime("%Y-%m-%d %H:%M"),
                             "o": float(o[k]), "h": float(h[k]),
                             "l": float(l[k]), "c": float(c[k])})
            return bars
        except Exception as e:
            if tentativa == 2:
                print(f"  ! {ticker}: falha Yahoo ({e})", file=sys.stderr)
                return []
            time.sleep(1.5)
    return []


# ── Semana corrente ────────────────────────────────────────────────────────
def semana_corrente(hoje=None):
    hoje = hoje or datetime.now(BRT).date()
    segunda = hoje - timedelta(days=hoje.weekday())
    dias = [(segunda + timedelta(days=i)) for i in range(5)]      # seg..sex
    return segunda.isoformat(), {d.isoformat() for d in dias}


# ── Apuração das bandas 3%/6% (forward) ────────────────────────────────────
def apurar_bandas(bars, idx_por_key, entry):
    """Mede Banda 1 (3%) / Banda 2 (6%), % atual e drawdown até a Banda 1,
    olhando os candles a partir da CONFIRMAÇÃO (quando o gatilho dispara e vira
    acionável) — não do reteste retrospectivo, que em 30min pode recuar dias.
    Baseline = preço de entrada da tese (o reteste refinado). Direction-aware."""
    p = entry["preco_entrada"]
    bull = entry["direcao"] == "ALTA"
    i0 = idx_por_key.get(entry["key_confirmacao"])
    out = {"b1_key": None, "b2_key": None, "agora": None, "agora_pct": None,
           "dd_pct": None, "dd_preco": None, "max_fav_pct": None}
    if i0 is None or not p:
        return out
    alvo1 = p * (1 + BAND1_PCT) if bull else p * (1 - BAND1_PCT)
    alvo2 = p * (1 + BAND2_PCT) if bull else p * (1 - BAND2_PCT)
    pior = 0.0       # drawdown mais negativo (a favor = positivo, ignorado)
    melhor = 0.0
    for j in range(i0, len(bars)):
        b = bars[j]
        # excursão desfavorável (drawdown) só conta até bater a Banda 1
        if out["b1_key"] is None:
            adverso = (b["l"] - p) / p if bull else (p - b["h"]) / p
            if adverso < pior:
                pior = adverso
                out["dd_pct"] = round(abs(adverso) * 100, 2)
                out["dd_preco"] = round(b["l"] if bull else b["h"], 2)
        fav = (b["h"] - p) / p if bull else (p - b["l"]) / p
        if fav > melhor:
            melhor = fav
        if out["b1_key"] is None:
            if (bull and b["h"] >= alvo1) or (not bull and b["l"] <= alvo1):
                out["b1_key"] = b["key"]
        if out["b2_key"] is None:
            if (bull and b["h"] >= alvo2) or (not bull and b["l"] <= alvo2):
                out["b2_key"] = b["key"]
    if bars:
        ult = bars[-1]["c"]
        out["agora"] = round(ult, 2)
        out["agora_pct"] = round(((ult - p) / p * 100) if bull else ((p - ult) / p * 100), 2)
    out["max_fav_pct"] = round(melhor * 100, 2)
    out["alvo1"] = round(alvo1, 2)
    out["alvo2"] = round(alvo2, 2)
    return out


# ── HTML (cards no estilo do Trade Gatilho) ────────────────────────────────
def fmt(v, dec=2):
    if v is None:
        return "—"
    return f"{v:,.{dec}f}".replace(",", "X").replace(".", ",").replace("X", ".")


def label_dt(key):
    d = datetime.strptime(key, "%Y-%m-%d %H:%M")
    return f"{DIAS_PT[d.weekday()]} {d.strftime('%d/%m')} {d.strftime('%H:%M')}"


def hora_hit(key):
    if not key:
        return None
    d = datetime.strptime(key, "%Y-%m-%d %H:%M")
    return f"{DIAS_PT[d.weekday()]} {d.strftime('%H:%M')}"


def render_card(s):
    bull = s["direcao"] == "ALTA"
    cor = "#1a7f37" if bull else "#cf222e"
    badge = "▲ COMPRA" if bull else "▼ VENDA"
    a = s["apuracao"]
    afast = s.get("afast_8x17_pct")
    if afast is None:
        afast_txt = ""
    elif afast <= 0:
        afast_txt = f"<span style='color:#1a7f37'>{fmt(abs(afast),2)}% antes ✓</span>"
    else:
        afast_txt = f"<span style='color:#9a6700'>{fmt(afast,2)}% depois</span>"

    b1 = hora_hit(a["b1_key"])
    b2 = hora_hit(a["b2_key"])
    b1_cell = (f"<span style='color:#1a7f37;font-weight:700'>{b1}</span>" if b1 else "<span style='color:#8b949e'>—</span>")
    b2_cell = (f"<span style='color:#1a7f37;font-weight:700'>{b2}</span>" if b2 else "<span style='color:#8b949e'>—</span>")

    ag = a.get("agora_pct")
    ag_cor = "#1a7f37" if (ag is not None and ag >= 0) else "#cf222e"
    ag_txt = (f"R$ {fmt(a['agora'])} <b style='color:{ag_cor}'>{'+' if (ag or 0)>=0 else ''}{fmt(ag,2)}%</b>"
              if a.get("agora") is not None else "—")

    tags = []
    if s.get("roc17_pullback"):
        tags.append("<span class='tag' style='background:#dafbe1;color:#1a7f37'>ROC17 pullback</span>")
    if s.get("penetracao_forte"):
        tags.append("<span class='tag' style='background:#ddf4ff;color:#0969da'>penetração forte</span>")
    if s.get("estagio") == "esticado":
        tags.append("<span class='tag' style='background:#ffebe9;color:#cf222e'>esticado</span>")
    elif s.get("estagio") == "acumulacao":
        tags.append("<span class='tag' style='background:#fff8c5;color:#9a6700'>acumulação</span>")
    tags_html = ("<div class='tags'>" + " ".join(tags) + "</div>") if tags else ""

    dd = (f"{fmt(a['dd_pct'],2)}% · R$ {fmt(a['dd_preco'])}" if a.get("dd_pct") is not None
          else "<span style='color:#8b949e'>sem drawdown</span>")

    reteste_row = ""
    if s.get("key") and s["key"] != s["key_confirmacao"]:
        reteste_row = f"<div class='row'><span>Melhor entrada (reteste)</span><span>{label_dt(s['key'])}</span></div>"

    return f"""
    <div class="card" style="border-left:4px solid {cor}">
      <div class="card-hd">
        <span class="dt">{label_dt(s['key_confirmacao'])}</span>
        <span class="tk">{s['ticker']}</span>
        <span class="badge" style="color:{cor}">{badge}</span>
      </div>
      <div class="rows">
        <div class="row"><span>Entrada</span><b>R$ {fmt(s['preco_entrada'])}</b></div>
        {reteste_row}
        <div class="row"><span>Cruzamento 8x17</span><span>{afast_txt}</span></div>
        <div class="row"><span>Suporte</span><span>{s.get('suporte_tocado','—')}</span></div>
        <div class="row"><span>Alvo Banda 1 (+3%)</span><b>R$ {fmt(a.get('alvo1'))}</b></div>
        <div class="row"><span>Alvo Banda 2 (+6%)</span><b>R$ {fmt(a.get('alvo2'))}</b></div>
        <div class="row"><span>Agora</span><span>{ag_txt}</span></div>
        <div class="row"><span>Drawdown até Banda 1</span><span>{dd}</span></div>
      </div>
      {tags_html}
      <div class="bands">
        <span>Banda 1 {b1_cell}</span>
        <span>Banda 2 {b2_cell}</span>
      </div>
    </div>"""


def render_html(signals, semana_id, agora_str):
    compras = sum(1 for s in signals if s["direcao"] == "ALTA")
    vendas = sum(1 for s in signals if s["direcao"] == "BAIXA")
    ativos = len({s["ticker"] for s in signals})
    seg = datetime.strptime(semana_id, "%Y-%m-%d")
    sex = seg + timedelta(days=4)
    semana_txt = f"{seg.strftime('%d/%m')} – {sex.strftime('%d/%m/%Y')}"
    cards = "\n".join(render_card(s) for s in signals) or \
        "<p style='color:#656d76;padding:1rem'>Nenhum gatilho de Onda 3 Premium nesta semana ainda.</p>"
    b1_tot = sum(1 for s in signals if s["apuracao"]["b1_key"])
    b2_tot = sum(1 for s in signals if s["apuracao"]["b2_key"])
    return f"""<!DOCTYPE html>
<html lang="pt-BR"><head>
<meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0">
<meta http-equiv="refresh" content="1800">
<title>SWING Gatilho — Onda 3 Premium</title>
<style>
*{{box-sizing:border-box;margin:0;padding:0}}
body{{background:#ffffff;color:#1f2328;font-family:'Segoe UI',Arial,sans-serif;font-size:14px}}
.hdr{{display:flex;align-items:center;gap:16px;padding:.8rem 1.2rem;background:#f6f8fa;border-bottom:1px solid #d0d7de;flex-wrap:wrap}}
.hdr h1{{font-size:1.1rem;font-weight:800;color:#8250df}}
.hdr .sub{{font-size:.75rem;color:#656d76;max-width:640px}}
.pill{{font-size:.72rem;font-weight:700;padding:2px 9px;border-radius:12px;background:#eaeef2}}
.pill.buy{{background:#dafbe1;color:#1a7f37}} .pill.sell{{background:#ffebe9;color:#cf222e}}
.section{{padding:.9rem 1.2rem 0}}
.section h2{{font-size:.95rem;color:#8250df;font-weight:800;margin-bottom:.5rem;display:flex;gap:10px;align-items:center;flex-wrap:wrap}}
.grid{{display:grid;grid-template-columns:repeat(auto-fill,minmax(255px,1fr));gap:12px;padding:.4rem 1.2rem 2rem}}
.card{{background:#f6f8fa;border:1px solid #d0d7de;border-radius:8px;padding:.7rem .8rem}}
.card-hd{{display:flex;align-items:center;gap:8px;margin-bottom:.5rem}}
.card-hd .dt{{font-size:.68rem;color:#656d76}}
.card-hd .tk{{font-weight:800;font-size:.95rem}}
.card-hd .badge{{margin-left:auto;font-size:.72rem;font-weight:800}}
.rows .row{{display:flex;justify-content:space-between;font-size:.78rem;padding:2px 0;border-bottom:1px dotted #e3e6ea}}
.rows .row span:first-child{{color:#656d76}}
.tags{{margin:.4rem 0 0;display:flex;gap:5px;flex-wrap:wrap}}
.tag{{font-size:.66rem;font-weight:700;padding:1px 7px;border-radius:10px}}
.bands{{display:flex;justify-content:space-between;margin-top:.5rem;padding-top:.4rem;border-top:1px solid #d0d7de;font-size:.74rem;color:#656d76}}
.foot{{font-size:.72rem;color:#8b949e;padding:0 1.2rem 2rem}}
</style></head><body>
<div class="hdr">
  <h1>🌊 SWING Gatilho</h1>
  <div class="sub">Onda 3 — Zona Premium em candles de 30min · gatilhos da <b>semana corrente</b> ({semana_txt}) ·
     bandas 3%/6% · fonte Yahoo · atualiza de hora em hora. Mesma tese do bridge (bridge.py).</div>
  <span class="pill buy">{compras} compra</span>
  <span class="pill sell">{vendas} venda</span>
  <span class="pill">{ativos} ativo(s)</span>
  <span class="pill">B1: {b1_tot} · B2: {b2_tot}</span>
  <span class="pill" style="margin-left:auto">Atualizado {agora_str}</span>
</div>
<div class="section">
  <h2>Onda 3 — Zona Premium <span style="font-weight:400;font-size:.8rem;color:#656d76">(swing · 30min)</span></h2>
</div>
<div class="grid">
{cards}
</div>
<div class="foot">Apuração forward: Banda 1 = ±3% e Banda 2 = ±6% a partir do preço de entrada, medidas nos candles seguintes de 30min.
   "Cruzamento 8x17 X% antes" = entrada antes de o preço alcançar a zona do cruzamento (entrada melhor). Drawdown = pior excursão contra a operação antes de bater a Banda 1.</div>
</body></html>"""


def render_telegram(signals, semana_id, novos, hits):
    compras = sum(1 for s in signals if s["direcao"] == "ALTA")
    vendas = sum(1 for s in signals if s["direcao"] == "BAIXA")
    seg = datetime.strptime(semana_id, "%Y-%m-%d")
    sex = seg + timedelta(days=4)
    linhas = [f"<b>🌊 SWING Gatilho — Onda 3 Premium</b>",
              f"Semana {seg.strftime('%d/%m')}–{sex.strftime('%d/%m')} · {len(signals)} gatilho(s) "
              f"({compras} compra / {vendas} venda)"]
    if novos:
        linhas.append("")
        linhas.append("<b>Novos nesta atualização:</b>")
        for s in novos[:15]:
            seta = "▲" if s["direcao"] == "ALTA" else "▼"
            linhas.append(f"{seta} {s['ticker']} R$ {fmt(s['preco_entrada'])} "
                          f"({label_dt(s['key_confirmacao'])}) · sup {s.get('suporte_tocado','')}")
    if hits:
        linhas.append("")
        linhas.append("<b>Bateram banda:</b>")
        for s, nb in hits[:15]:
            linhas.append(f"✅ {s['ticker']} bateu Banda {nb} "
                          f"(entrada R$ {fmt(s['preco_entrada'])})")
    linhas.append("")
    linhas.append(f'<a href="{PAGES_URL}">Abrir SWING Gatilho</a>')
    return "\n".join(linhas)


# ── Estado semanal ─────────────────────────────────────────────────────────
def carregar_estado(path, semana_id):
    try:
        with open(path, "r", encoding="utf-8") as f:
            st = json.load(f)
        if st.get("week") == semana_id:
            return st
    except Exception:
        pass
    return {"week": semana_id, "signals": {}}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="swing_gatilho.html")
    ap.add_argument("--telegram", default="swing_gatilho_telegram.txt")
    ap.add_argument("--state", default="swing_gatilho_state.json")
    ap.add_argument("--pages", default="_site/index.html")
    ap.add_argument("--limit", type=int, default=0, help="limita nº de tickers (teste)")
    ap.add_argument("--no-write-state", action="store_true")
    ap.add_argument("--insecure", action="store_true",
                    help="desliga verificação SSL — SÓ p/ teste nesta máquina local, nunca na nuvem")
    args = ap.parse_args()
    if args.insecure:
        global _SSL_CTX
        _SSL_CTX = ssl._create_unverified_context()

    agora = datetime.now(BRT)
    semana_id, allowed = semana_corrente(agora.date())
    tickers = TICKERS[:args.limit] if args.limit else TICKERS
    estado = carregar_estado(args.state, semana_id)
    prev_ids = set(estado.get("signals", {}).keys())

    todos = []
    for tk in tickers:
        bars = fetch_yahoo_30m(tk)
        if len(bars) < 72:
            print(f"  - {tk}: {len(bars)} barras (insuficiente)")
            continue
        idx_por_key = {b["key"]: i for i, b in enumerate(bars)}
        entries = detectar_onda3_premium(bars, allowed, SESSION_START, SESSION_END)
        for e in entries:
            e["ticker"] = tk
            e["apuracao"] = apurar_bandas(bars, idx_por_key, e)
            todos.append(e)
        print(f"  - {tk}: {len(bars)} barras, {len(entries)} gatilho(s)")

    todos.sort(key=lambda s: s["key_confirmacao"], reverse=True)

    # merge de estado: preserva first_seen; detecta novos e quem bateu banda
    novos, hits = [], []
    novo_estado_signals = {}
    for s in todos:
        sid = f"{s['ticker']}|{s['key_confirmacao']}|{s['direcao']}"
        prev = estado.get("signals", {}).get(sid, {})
        first_seen = prev.get("first_seen") or agora.strftime("%Y-%m-%d %H:%M")
        if sid not in prev_ids:
            novos.append(s)
        a = s["apuracao"]
        # detecta banda batida desde a última execução
        if a["b2_key"] and not prev.get("b2"):
            hits.append((s, 2))
        elif a["b1_key"] and not prev.get("b1"):
            hits.append((s, 1))
        novo_estado_signals[sid] = {"first_seen": first_seen,
                                     "b1": bool(a["b1_key"]), "b2": bool(a["b2_key"])}

    html = render_html(todos, semana_id, agora.strftime("%d/%m %H:%M"))
    with open(args.out, "w", encoding="utf-8") as f:
        f.write(html)
    # cópia p/ GitHub Pages
    try:
        import os
        os.makedirs(os.path.dirname(args.pages), exist_ok=True)
        with open(args.pages, "w", encoding="utf-8") as f:
            f.write(html)
    except Exception as e:
        print(f"  ! pages: {e}", file=sys.stderr)

    with open(args.telegram, "w", encoding="utf-8") as f:
        f.write(render_telegram(todos, semana_id, novos, hits))

    if not args.no_write_state:
        with open(args.state, "w", encoding="utf-8") as f:
            json.dump({"week": semana_id, "generated": agora.isoformat(),
                       "signals": novo_estado_signals}, f, ensure_ascii=False, indent=1)

    print(f"OK: {len(todos)} gatilho(s) na semana, {len(novos)} novo(s), {len(hits)} banda(s) batida(s).")


if __name__ == "__main__":
    main()
