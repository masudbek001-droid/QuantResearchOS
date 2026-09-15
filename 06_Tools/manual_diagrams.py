"""Vector diagrams for the manual: strategy cycle, break-even swings, hour mask, modules."""
import pymupdf as fz
from manual_style import (BG_SOFT, PANEL, PANEL_HI, GRID, CYAN, CYAN_DIM, MAGENTA, GREEN,
                          AMBER, RED, TXT, TXT_DIM, TXT_FAINT, WHITE, F_MONO, F_MONOB, F_SANS,
                          F_BOLD, hexc, tw, PAGE_W, M_L, M_R, CONTENT_W)

AXIS = "#2A3A5C"


def _frame(m, top, height, title=None, color=CYAN):
    rect = fz.Rect(M_L, top, PAGE_W - M_R, top + height)
    m.panel(rect, fill="#070C16", border=CYAN_DIM, radius=4)
    m.page.draw_rect(fz.Rect(M_L, top, PAGE_W - M_R, top + 3), color=None, fill=hexc(color))
    if title:
        m.text(M_L + 12, top + 18, title, font=F_MONOB, size=7.4, color=color)
    return rect


def _axis(m, rect, pad_l=44, pad_b=24, pad_t=28):
    x0, y0 = rect.x0 + pad_l, rect.y0 + pad_t
    x1, y1 = rect.x1 - 14, rect.y1 - pad_b
    m.page.draw_line(fz.Point(x0, y0), fz.Point(x0, y1), color=hexc(AXIS), width=0.8)
    m.page.draw_line(fz.Point(x0, y1), fz.Point(x1, y1), color=hexc(AXIS), width=0.8)
    return x0, y0, x1, y1


def _candle(m, x, top, bottom, body_top, body_bottom, color):
    m.page.draw_line(fz.Point(x, top), fz.Point(x, bottom), color=hexc(color), width=0.9)
    m.page.draw_rect(fz.Rect(x - 4.5, body_top, x + 4.5, body_bottom), color=hexc(color),
                     fill=hexc(BG_SOFT), width=1.0)


def _dashed(m, p1, p2, color, dash=(4, 3), width=0.9):
    m.page.draw_line(p1, p2, color=hexc(color), width=width, dashes=dash)


def _label(m, x, y, text, color=TXT_DIM, font=F_MONO, size=7.0, anchor="left"):
    if anchor == "right":
        x -= tw(text, font, size)
    m.text(x, y, text, font=font, size=size, color=color)


# ---------------------------------------------------------------- 1. cycle
def strategy_diagram(m):
    """H1 candle with the two stop orders, the fill and the flatten at close."""
    H = 244
    m.ensure(H + 10)
    top = m.y
    rect = _frame(m, top, H, "СТРАТЕГИЯ ЦИКЛИ  //  H1 ШАМ")
    x0, y0, x1, y1 = _axis(m, rect)

    hi = y0 + 40
    lo = y1 - 50
    mid = (hi + lo) / 2

    cx_start = x0 + 10
    cx_end = x1 - 62
    for cx, lbl in ((cx_start, "H1 ОЧИЛИШИ"), (cx_end - 2, "H1 ЁПИЛИШИ")):
        _dashed(m, fz.Point(cx, y0), fz.Point(cx, y1), CYAN_DIM)
        _label(m, cx + 4, y0 + 10, lbl, CYAN_DIM, F_MONO, 6.2)

    # the previous candle that defines the levels
    _candle(m, cx_start, hi - 8, lo + 8, hi + 14, lo - 14, TXT_FAINT)
    _label(m, cx_start - 40, y0 + 10, "ОЛДИНГИ", TXT_FAINT, F_MONO, 6.0)
    _label(m, cx_start - 40, y0 + 18, "ШАМ", TXT_FAINT, F_MONO, 6.0)

    _dashed(m, fz.Point(cx_start, hi), fz.Point(cx_end, hi), CYAN)
    _dashed(m, fz.Point(cx_start, lo), fz.Point(cx_end, lo), MAGENTA)
    _label(m, cx_end + 4, hi + 3, "PREV HIGH", CYAN, F_MONOB, 6.4)
    _label(m, cx_end + 4, lo + 3, "PREV LOW", MAGENTA, F_MONOB, 6.4)

    # rising candle that triggers the buy
    trig = cx_start + (cx_end - cx_start) * 0.34
    _candle(m, trig, hi - 28, mid + 6, hi - 20, mid + 12, GREEN)
    m.page.draw_circle(fz.Point(trig, hi), 3.4, color=None, fill=hexc(GREEN))
    _label(m, trig + 9, hi - 22, "BUY STOP ИШГА ТУШДИ", GREEN, F_MONOB, 6.8)

    # break-even ladder
    be1, be2 = hi - 10, hi - 24
    bx1 = trig + (cx_end - trig) * 0.34
    bx2 = trig + (cx_end - trig) * 0.68
    segs = [((trig, mid + 10), (bx1, mid + 10)), ((bx1, mid + 10), (bx1, be1)),
            ((bx1, be1), (bx2, be1)), ((bx2, be1), (bx2, be2)),
            ((bx2, be2), (cx_end - 6, be2))]
    for a, b in segs:
        m.page.draw_line(fz.Point(*a), fz.Point(*b), color=hexc(AMBER), width=1.1)
    _label(m, bx1 + 6, mid + 24, "BREAK EVEN (M5 СВИНГ)", AMBER, F_MONOB, 6.4)

    # the untouched sell stop
    _dashed(m, fz.Point(cx_start, lo + 14), fz.Point(cx_end, lo + 14), TXT_FAINT, (2, 4))
    _label(m, cx_start + 8, lo + 26, "SELL STOP → ЎЧИРИЛДИ", TXT_FAINT, F_MONO, 6.2)

    # flatten
    m.page.draw_circle(fz.Point(cx_end - 6, be2), 3.4, color=None, fill=hexc(RED))
    _label(m, cx_end - 100, be2 - 8, "ЁПИЛИШДА ФЛЭТ", RED, F_MONOB, 6.6)

    ly = rect.y1 - 12
    for i, (c, t) in enumerate(((CYAN, "Buy Stop"), (MAGENTA, "Sell Stop"),
                                (AMBER, "Break Even"), (RED, "Флэт"))):
        lx = M_L + 14 + i * 84
        m.page.draw_rect(fz.Rect(lx, ly - 5, lx + 10, ly - 2), color=None, fill=hexc(c))
        m.text(lx + 14, ly - 1, t, font=F_MONO, size=6.4, color=TXT_DIM)
    m.y = top + H + 14


# ---------------------------------------------------------------- 2. break even
def breakeven_diagram(m):
    H = 216
    m.ensure(H + 10)
    top = m.y
    rect = _frame(m, top, H, "BREAK EVEN  //  M5 СВИНГ ЛОГИКАСИ (ЛОНГ)", color=AMBER)
    x0, y0, x1, y1 = _axis(m, rect)

    base = y1 - 8
    step = (x1 - x0 - 24) / 9
    pts = [0, 18, 6, 34, 22, 52, 38, 70, 58, 88]
    coords = [(x0 + 12 + i * step, base - v) for i, v in enumerate(pts)]

    for i in range(len(coords) - 1):
        m.page.draw_line(fz.Point(*coords[i]), fz.Point(*coords[i + 1]), color=hexc(CYAN),
                         width=1.1)

    for si in (3, 5):
        sx, sy = coords[si]
        m.page.draw_circle(fz.Point(sx, sy), 3.6, color=hexc(AMBER), fill=hexc(BG_SOFT),
                           width=1.2)
    _label(m, coords[3][0] - 28, coords[3][1] + 18, "СВИНГ LOW #1", AMBER, F_MONOB, 6.4)
    _label(m, coords[5][0] - 28, coords[5][1] + 18, "СВИНГ LOW #2", AMBER, F_MONOB, 6.4)

    ey = base - 2
    _dashed(m, fz.Point(x0, ey), fz.Point(x1, ey), TXT_FAINT)
    _label(m, x1 - 40, ey - 5, "ENTRY", TXT_FAINT, F_MONOB, 6.4)

    s1 = coords[3][1] + 6
    s2 = coords[5][1] + 6
    sa, sb = coords[4][0], coords[7][0]
    for a, b in (((x0 + 12, ey - 8), (sa, ey - 8)), ((sa, ey - 8), (sa, s1)),
                 ((sa, s1), (sb, s1)), ((sb, s1), (sb, s2)), ((sb, s2), (x1 - 10, s2))):
        m.page.draw_line(fz.Point(*a), fz.Point(*b), color=hexc(GREEN), width=1.0)
    _label(m, x0 + 14, ey - 13, "SL = СВИНГ #1", GREEN, F_MONO, 6.2)
    _label(m, x1 - 62, s2 - 5, "ЯНГИ SL", GREEN, F_MONOB, 6.4)

    ly = rect.y1 - 12
    for i, t in enumerate(("СТОП ФАҚАТ ФОЙДА ТОМОН", "СВИНГ КИРИШДАН КЕЙИН",
                           "БРОКЕР МАСОФАСИДАН ТАШҚАРИДА")):
        lx = M_L + 14 + i * 168
        m.page.draw_rect(fz.Rect(lx, ly - 5, lx + 8, ly - 2), color=None, fill=hexc(AMBER))
        m.text(lx + 12, ly - 1, t, font=F_MONO, size=6.2, color=TXT_DIM)
    m.y = top + H + 14


# ---------------------------------------------------------------- 3. hour mask
def hours_diagram(m, enabled=None, caption=None):
    enabled = enabled if enabled is not None else set(range(24))
    H = 100
    m.ensure(H + 10)
    top = m.y
    rect = _frame(m, top, H, "СОАТЛАР НИҚОБИ  //  24 БИТ", color=MAGENTA)
    gx0 = rect.x0 + 14
    gy0 = rect.y0 + 32
    cw = (rect.x1 - rect.x0 - 28) / 24
    ch = 26
    for h in range(24):
        x = gx0 + h * cw
        on = h in enabled
        m.page.draw_rect(fz.Rect(x + 1, gy0, x + cw - 1, gy0 + ch),
                         color=hexc(GREEN if on else "#1B2438"),
                         fill=hexc("#0F2A22" if on else "#0B1120"), width=0.7)
        lbl = f"{h:02d}"
        m.text(x + (cw - tw(lbl, F_MONO, 6.0)) / 2, gy0 + 17, lbl, font=F_MONO, size=6.0,
               color=GREEN if on else TXT_FAINT)
        bit = "1" if on else "0"
        m.text(x + (cw - tw(bit, F_MONOB, 6.0)) / 2, gy0 - 4, bit, font=F_MONOB, size=6.0,
               color=GREEN if on else TXT_FAINT)
    total = sum(1 << h for h in enabled)
    m.text(gx0, gy0 + ch + 17, "НИҚОБ ҚИЙМАТИ:", font=F_MONO, size=7.0, color=TXT_DIM)
    m.text(gx0 + 76, gy0 + ch + 17, str(total), font=F_MONOB, size=9.0, color=MAGENTA)
    if caption:
        m.text(gx0 + 76 + tw(str(total), F_MONOB, 9.0) + 12, gy0 + ch + 17, caption,
               font=F_SANS, size=7.4, color=TXT)
    m.y = top + H + 14


# ---------------------------------------------------------------- 4. martingale
def martingale_diagram(m):
    H = 190
    m.ensure(H + 10)
    top = m.y
    rect = _frame(m, top, H, "МАРТИНГЕЙЛ  //  ЮМШОҚ ВА ҚАТТИҚ (1.5x, MAX 3)", color=MAGENTA)
    x0, y0, x1, y1 = _axis(m, rect, pad_b=32)
    base = y1
    steps = [0, 1, 2, 3, 4, 5]
    soft = [1.5 ** min(s, 3) for s in steps]
    hard = [1.5 ** (s % 3) for s in steps]
    bw = (x1 - x0 - 40) / (len(steps) * 2 + 1)
    scale = (base - y0 - 28) / max(soft)
    for i, s in enumerate(steps):
        cx = x0 + 14 + i * bw * 2
        for k, (vals, col, fill) in enumerate(((soft, CYAN, "#0B1A26"), (hard, MAGENTA, "#22102A"))):
            h = max(2.0, vals[i] * scale)
            x = cx + k * (bw + 2)
            m.page.draw_rect(fz.Rect(x, base - h, x + bw, base), color=hexc(col),
                             fill=hexc(fill), width=0.9)
            vl = f"{vals[i]:.2f}"
            m.text(x + (bw - tw(vl, F_MONO, 6.0)) / 2, base - h - 4, vl, font=F_MONO, size=6.0,
                   color=col)
        lbl = f"L{s}"
        m.text(cx + 2, base + 12, lbl, font=F_MONOB, size=6.6, color=TXT_DIM)
    m.text(x0 + 6, y0 + 12, "× база лот", font=F_MONO, size=6.4, color=TXT_FAINT)
    ly = rect.y1 - 12
    for i, (c, t) in enumerate(((CYAN, "ЮМШОҚ — 3-қадамда ТЎХТАЙДИ"),
                                (MAGENTA, "ҚАТТИҚ — 3-қадамда ҚАЙТА БОШЛАНАДИ"))):
        lx = M_L + 14 + i * 250
        m.page.draw_rect(fz.Rect(lx, ly - 5, lx + 10, ly - 2), color=None, fill=hexc(c))
        m.text(lx + 14, ly - 1, t, font=F_MONO, size=6.4, color=TXT_DIM)
    m.y = top + H + 14


# ---------------------------------------------------------------- 5. modules
def modules_diagram(m):
    mods = [
        ("EASettings.mqh", "созламалар", CYAN),
        ("EAUtils.mqh", "ёмдамчи", CYAN),
        ("EALogger.mqh", "лог", GREEN),
        ("EATradeHistory.mqh", "тарих", GREEN),
        ("EARiskManager.mqh", "фильтр", AMBER),
        ("EAOrderManager.mqh", "ордерлар", MAGENTA),
        ("EAPositionManager.mqh", "позициялар", MAGENTA),
        ("EABreakEvenManager.mqh", "break even", AMBER),
        ("EAVisualManager.mqh", "график", CYAN),
        ("EATradeManager.mqh", "СТРАТЕГИЯ", WHITE),
    ]
    cols, rows = 2, 5
    cw = (CONTENT_W - 14) / cols
    rh = 34
    H = rows * rh + 34
    m.ensure(H + 10)
    top = m.y
    rect = _frame(m, top, H, "МОДУЛЛАР АРХИТЕКТУРАСИ", color=CYAN)
    for i, (name, role, col) in enumerate(mods):
        r, c = divmod(i, cols)
        x = rect.x0 + 10 + c * (cw + 4)
        y = rect.y0 + 26 + r * rh
        m.panel(fz.Rect(x, y, x + cw - 6, y + rh - 6), fill=PANEL_HI, border=col, radius=3,
                width=0.8)
        m.page.draw_rect(fz.Rect(x, y, x + 3, y + rh - 6), color=None, fill=hexc(col))
        m.text(x + 10, y + 14, name, font=F_MONOB, size=7.6, color=WHITE)
        m.text(x + 10, y + 25, role, font=F_SANS, size=7.2, color=col)
    m.y = top + H + 14
