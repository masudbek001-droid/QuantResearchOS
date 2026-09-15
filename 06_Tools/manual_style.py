"""Futuristic dark-HUD design system for the CandleBreakoutEA manual (PyMuPDF)."""
import pymupdf as fz

# ---------------------------------------------------------------- palette
BG        = "#060A14"
BG_SOFT   = "#0B1120"
PANEL     = "#0E1526"
PANEL_HI  = "#121B31"
GRID      = "#16203A"
CYAN      = "#22E1FF"
CYAN_DIM  = "#0E7E93"
MAGENTA   = "#FF4FD8"
GREEN     = "#3BFFB2"
AMBER     = "#FFC857"
RED       = "#FF5A7A"
TXT       = "#D6E4FF"
TXT_DIM   = "#7E92B8"
TXT_FAINT = "#4A5B7A"
WHITE     = "#FFFFFF"

F_SANS  = "sans"
F_BOLD  = "bold"
F_MONO  = "mono"
F_MONOB = "monob"

_FONT_DIR   = "/usr/share/fonts/truetype/dejavu/"
_FONT_FILES = {F_SANS: "DejaVuSans.ttf", F_BOLD: "DejaVuSans-Bold.ttf",
               F_MONO: "DejaVuSansMono.ttf", F_MONOB: "DejaVuSansMono-Bold.ttf"}
_FONTS = {k: fz.Font(fontfile=_FONT_DIR + v) for k, v in _FONT_FILES.items()}

PAGE_W, PAGE_H = fz.paper_size("a4")          # 595 x 842 pt
M_L, M_R       = 46, 46
M_T, M_B       = 96, 62
CONTENT_W      = PAGE_W - M_L - M_R


# ---------------------------------------------------------------- helpers
def hexc(h):
    """Hex string -> (r,g,b) floats, the form PyMuPDF expects."""
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))


def tw(text, font=F_SANS, size=10):
    """Accurate string width in points, measured against the real TTF."""
    return _FONTS[font].text_length(text, fontsize=size)


def wrap(font, text, size, max_w):
    """Greedy word wrap; returns a list of lines."""
    out = []
    for para in text.split("\n"):
        line = ""
        for w in para.split(" "):
            test = w if not line else line + " " + w
            if tw(test, font, size) <= max_w:
                line = test
            else:
                if line:
                    out.append(line)
                line = w
        out.append(line)
    return out


# ---------------------------------------------------------------- document
class Manual:
    def __init__(self, path):
        self.doc = fz.open()
        self.doc.set_metadata({
            "title": "CandleBreakoutEA — Фойдаланиш қўлланмаси",
            "author": "CandleBreakoutEA",
            "subject": "MetaTrader 5 Expert Advisor",
            "keywords": "MQL5, MetaTrader 5, Expert Advisor, CandleBreakout",
        })
        self.doc.set_toc([])
        self.page = None
        self.y = 0
        self.page_no = 0
        self.toc = []
        self.path = path
        self.new_page()

    # ------------------------------------------------------------- text
    def text(self, x, y, s, font=F_SANS, size=10, color=TXT):
        """insert_text with the TTF attached and a hex colour."""
        path = _FONT_DIR + _FONT_FILES[font]
        self.page.insert_font(fontname=font, fontfile=path)
        return self.page.insert_text(fz.Point(x, y), s, fontname=font, fontfile=path,
                                     fontsize=size, color=hexc(color))

    def bookmark(self, level, title, page=None):
        self.toc.append([level, title, page or self.page_no])

    # ------------------------------------------------------------- pages
    def new_page(self):
        self.page = self.doc.new_page(width=PAGE_W, height=PAGE_H)
        self.page_no += 1
        self._paint_background()
        self.y = M_T

    def _paint_background(self):
        p = self.page
        p.draw_rect(fz.Rect(0, 0, PAGE_W, PAGE_H), color=None, fill=hexc(BG))
        for x in range(0, int(PAGE_W) + 1, 24):
            p.draw_line(fz.Point(x, 0), fz.Point(x, PAGE_H), color=hexc(GRID), width=0.25)
        for y in range(0, int(PAGE_H) + 1, 24):
            p.draw_line(fz.Point(0, y), fz.Point(PAGE_W, y), color=hexc(GRID), width=0.25)
        p.draw_rect(fz.Rect(0, 0, PAGE_W, 4), color=None, fill=hexc(CYAN))
        p.draw_rect(fz.Rect(0, 4, PAGE_W, 5), color=None, fill=hexc(MAGENTA))
        p.draw_rect(fz.Rect(0, PAGE_H - 5, PAGE_W, PAGE_H - 4), color=None, fill=hexc(MAGENTA))
        p.draw_rect(fz.Rect(0, PAGE_H - 4, PAGE_W, PAGE_H), color=None, fill=hexc(CYAN))
        p.draw_rect(fz.Rect(0, 0, 3, PAGE_H), color=None, fill=hexc(CYAN_DIM))
        self._chrome()

    def _chrome(self):
        p = self.page
        self.text(M_L, 34, "CANDLEBREAKOUT EA", font=F_BOLD, size=9, color=CYAN)
        self.text(M_L, 46, "METATRADER 5  //  ФОЙДАЛАНИШ ҚЎЛЛАНМАСИ", font=F_MONO, size=6.6,
                  color=TXT_FAINT)
        p.draw_line(fz.Point(M_L, 54), fz.Point(PAGE_W - M_R, 54), color=hexc(GRID), width=0.6)
        label = f"{self.page_no:02d}"
        w = tw(label, F_MONOB, 10) + 16
        bx = PAGE_W - M_R - w
        self.panel(fz.Rect(bx, 20, PAGE_W - M_R, 44), fill=PANEL_HI, border=CYAN_DIM, radius=3)
        self.text(bx + 8, 36, label, font=F_MONOB, size=10, color=CYAN)

    def footer(self, text):
        p = self.page
        p.draw_line(fz.Point(M_L, PAGE_H - M_B + 14), fz.Point(PAGE_W - M_R, PAGE_H - M_B + 14),
                    color=hexc(GRID), width=0.5)
        self.text(M_L, PAGE_H - M_B + 27, text, font=F_MONO, size=6.4, color=TXT_FAINT)
        self.text(PAGE_W - M_R - 150, PAGE_H - M_B + 27, "CANDLEBREAKOUT EA v1.00  //  MQL5",
                  font=F_MONO, size=6.4, color=TXT_FAINT)

    def ensure(self, needed):
        if self.y + needed > PAGE_H - M_B:
            self.footer("CANDLEBREAKOUT EA  //  ҚЎЛЛАНМА")
            self.new_page()
            return True
        return False

    def gap(self, h=10):
        self.y += h

    # ------------------------------------------------------------- shapes
    def panel(self, rect, fill=PANEL, border=None, radius=4, width=0.8):
        """radius is given in POINTS here and converted to the fraction PyMuPDF wants."""
        rect = fz.Rect(rect)
        frac = None
        if radius:
            short = min(rect.width, rect.height)
            if short > 0:
                frac = max(0.01, min(0.5, radius / short))
        self.page.draw_rect(rect, color=hexc(border) if border else None,
                            fill=hexc(fill) if fill else None, radius=frac, width=width)

    def neon_bar(self, color=CYAN, w=34, h=3):
        self.page.draw_rect(fz.Rect(M_L, self.y, M_L + w, self.y + h), color=None,
                            fill=hexc(color))

    def tag(self, x, y, text, color=CYAN, size=6.6):
        w = tw(text, F_MONOB, size) + 14
        self.panel(fz.Rect(x, y, x + w, y + 15), fill=BG_SOFT, border=color, radius=2)
        self.text(x + 7, y + 10.4, text, font=F_MONOB, size=size, color=color)
        return w

    # ------------------------------------------------------------- headings
    def h1(self, num, title, color=CYAN):
        self.ensure(96)
        self.neon_bar(color=color, w=46)
        self.y += 12
        if num:
            self.text(M_L, self.y + 22, num, font=F_MONOB, size=30, color=PANEL_HI)
            tx = M_L + 46
        else:
            tx = M_L
        self.text(tx, self.y + 20, title.upper(), font=F_BOLD, size=17, color=WHITE)
        self.y += 30
        self.page.draw_line(fz.Point(M_L, self.y), fz.Point(PAGE_W - M_R, self.y),
                            color=hexc(color), width=0.8)
        self.y += 16

    def h2(self, text, color=CYAN):
        self.ensure(46)
        self.page.draw_rect(fz.Rect(M_L, self.y + 1, M_L + 3, self.y + 13), color=None,
                            fill=hexc(color))
        self.text(M_L + 10, self.y + 11, text, font=F_BOLD, size=11.5, color=color)
        self.y += 24

    def h3(self, text, color=TXT):
        self.ensure(34)
        self.text(M_L, self.y + 10, text, font=F_BOLD, size=10, color=color)
        self.y += 18

    # ------------------------------------------------------------- body
    def para(self, text, size=9.4, color=TXT, font=F_SANS, indent=0, leading=14.2):
        for line in wrap(font, text, size, CONTENT_W - indent):
            self.ensure(leading + 2)
            self.text(M_L + indent, self.y + 10, line, font=font, size=size, color=color)
            self.y += leading
        return self

    def rich(self, chunks, size=9.4, indent=0, leading=14.2):
        """chunks = [(text, font, color), ...] rendered as one wrapped paragraph."""
        words = []
        for t, f, c in chunks:
            for i, w in enumerate(t.split(" ")):
                words.append((w, f, c, i > 0))
        line, line_w = [], 0.0
        max_w = CONTENT_W - indent
        sp = tw(" ", F_SANS, size)

        def flush():
            nonlocal line, line_w
            if not line:
                return
            self.ensure(leading + 2)
            x = M_L + indent
            for txt, f, c, needs_space in line:
                if needs_space:
                    x += sp
                self.text(x, self.y + 10, txt, font=f, size=size, color=c)
                x += tw(txt, f, size)
            self.y += leading
            line, line_w = [], 0.0

        for txt, f, c, needs_space in words:
            w = tw(txt, f, size)
            add = (sp if needs_space and line else 0) + w
            if line and line_w + add > max_w:
                flush()
                add = w
            line.append((txt, f, c, needs_space))
            line_w += add
        flush()

    def bullets(self, items, color=CYAN, size=9.4, indent=6):
        for it in items:
            self.ensure(18)
            self.page.draw_rect(fz.Rect(M_L + indent, self.y + 5, M_L + indent + 5,
                                        self.y + 10), color=None, fill=hexc(color))
            if isinstance(it, tuple):
                head, rest = it
                self.rich([(head + " —", F_BOLD, color), (" " + rest, F_SANS, TXT)], size=size,
                          indent=indent + 14)
            else:
                self.text(M_L + indent + 14, self.y + 10, it, font=F_SANS, size=size, color=TXT)
                self.y += 15

    def numbered(self, items, color=CYAN, size=9.4):
        for i, it in enumerate(items, 1):
            self.ensure(30)
            self.panel(fz.Rect(M_L, self.y, M_L + 20, self.y + 16), fill=BG_SOFT, border=color,
                       radius=2)
            self.text(M_L + 4.5, self.y + 11.4, f"{i:02d}", font=F_MONOB, size=8, color=color)
            if isinstance(it, tuple):
                self.rich([(it[0] + " —", F_BOLD, WHITE), (" " + it[1], F_SANS, TXT)],
                          size=size, indent=28)
            else:
                self.text(M_L + 28, self.y + 11, it, font=F_SANS, size=size, color=TXT)
                self.y += 16

    def code(self, lines, color=GREEN, size=8.1, title=None):
        line_h = 12.4
        total = 16 + len(lines) * line_h + (18 if title else 0)
        self.ensure(total + 6)
        top = self.y
        self.panel(fz.Rect(M_L, top, PAGE_W - M_R, top + total), fill="#070C16",
                   border=CYAN_DIM, radius=3)
        self.page.draw_rect(fz.Rect(M_L, top, M_L + 3, top + total), color=None,
                            fill=hexc(color))
        yy = top + 13
        if title:
            self.text(M_L + 12, yy, title, font=F_MONOB, size=7, color=TXT_FAINT)
            yy += 15
        for ln in lines:
            self.text(M_L + 12, yy, ln, font=F_MONO, size=size, color=color)
            yy += line_h
        self.y = top + total + 10

    def note(self, text, color=AMBER, label="ДИҚҚАТ"):
        lines = wrap(F_SANS, text, 9.0, CONTENT_W - 34)
        h = 34 + len(lines) * 13.4
        self.ensure(h + 6)
        top = self.y
        self.panel(fz.Rect(M_L, top, PAGE_W - M_R, top + h), fill="#141026", border=color,
                   radius=3)
        self.page.draw_rect(fz.Rect(M_L, top, M_L + 3, top + h), color=None, fill=hexc(color))
        self.tag(M_L + 12, top + 7, label, color=color)
        yy = top + 32
        for ln in lines:
            self.text(M_L + 14, yy, ln, font=F_SANS, size=9.0, color=TXT)
            yy += 13.4
        self.y = top + h + 12

    def table(self, headers, rows, widths, size=8.4, head_color=CYAN, mono_cols=()):
        total = sum(widths)
        cols = [CONTENT_W * w / total for w in widths]
        line_h = 15.2
        x_acc = [M_L]
        for c in cols:
            x_acc.append(x_acc[-1] + c)

        def head_row():
            top = self.y
            self.page.draw_rect(fz.Rect(M_L, top, PAGE_W - M_R, top + 19), color=None,
                                fill=hexc(PANEL_HI))
            x = M_L
            for i, htxt in enumerate(headers):
                self.text(x + 7, top + 13, htxt, font=F_MONOB, size=7.2, color=head_color)
                x += cols[i]
            self.y = top + 19

        self.ensure(line_h * 2 + 12)
        head_row()

        for r, row in enumerate(rows):
            cells, max_lines = [], 1
            for i, cell in enumerate(row):
                f = F_MONO if i in mono_cols else F_SANS
                ls = wrap(f, str(cell), size, cols[i] - 12)
                cells.append((ls, f))
                max_lines = max(max_lines, len(ls))
            h = max(line_h, 6 + max_lines * (size + 4.2))
            if self.y + h > PAGE_H - M_B:
                self.footer("CANDLEBREAKOUT EA  //  ҚЎЛЛАНМА")
                self.new_page()
                head_row()
            if r % 2 == 0:
                self.page.draw_rect(fz.Rect(M_L, self.y, PAGE_W - M_R, self.y + h), color=None,
                                    fill=hexc("#0A1020"))
            self.page.draw_line(fz.Point(M_L, self.y), fz.Point(PAGE_W - M_R, self.y),
                                color=hexc(GRID), width=0.35)
            yy = self.y + 11.4
            for i, (ls, f) in enumerate(cells):
                cyy = yy
                for ln in ls:
                    self.text(x_acc[i] + 7, cyy, ln, font=f, size=size,
                              color=WHITE if i == 0 else TXT)
                    cyy += size + 4.2
            self.y += h
        self.page.draw_line(fz.Point(M_L, self.y), fz.Point(PAGE_W - M_R, self.y),
                            color=hexc(CYAN_DIM), width=0.6)
        self.y += 12

    def kv_panel(self, title, pairs, color=CYAN):
        line_h = 15.0
        h = 24 + len(pairs) * line_h + 8
        self.ensure(h + 6)
        top = self.y
        self.panel(fz.Rect(M_L, top, PAGE_W - M_R, top + h), fill=PANEL, border=color, radius=4)
        self.text(M_L + 12, top + 16, title, font=F_MONOB, size=7.4, color=color)
        yy = top + 34
        for k, v in pairs:
            self.text(M_L + 12, yy, k, font=F_SANS, size=8.8, color=TXT_DIM)
            vw = tw(v, F_MONO, 8.6)
            self.text(PAGE_W - M_R - 12 - vw, yy, v, font=F_MONO, size=8.6, color=WHITE)
            yy += line_h
        self.y = top + h + 12

    def save(self):
        self.footer("CANDLEBREAKOUT EA  //  ҚЎЛЛАНМА")
        self.doc.set_toc(self.toc)
        self.doc.save(self.path, garbage=4, deflate=True)
        self.doc.close()
        return self.path
