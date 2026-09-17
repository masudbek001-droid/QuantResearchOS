"""Build the Uzbek (Cyrillic) futuristic PDF manual for CandleBreakoutEA."""
import pymupdf as fz
from manual_style import (Manual, hexc, wrap, tw, PAGE_W, PAGE_H, M_L, M_R, CONTENT_W,
                          BG, BG_SOFT, PANEL, PANEL_HI, GRID, CYAN, CYAN_DIM, MAGENTA, GREEN,
                          AMBER, RED, TXT, TXT_DIM, TXT_FAINT, WHITE,
                          F_SANS, F_BOLD, F_MONO, F_MONOB)
import manual_diagrams as dg

OUT = "/home/user/QuantResearchOS/03_Documents/Manuals/CandleBreakoutEA_Qollanma.pdf"
m = Manual(OUT)


def section(num, title, color=CYAN):
    m.h1(num, title, color)
    m.bookmark(1, f"{num}. {title}")


def sub(title, color=CYAN):
    m.h2(title, color)
    m.bookmark(2, title)


# ================================================================ МУҚОВА
def cover():
    p = m.page
    p.draw_rect(fz.Rect(M_L, 150, M_L + 190, 152), color=None, fill=hexc(CYAN))
    p.draw_rect(fz.Rect(M_L, 154, M_L + 190, 155), color=None, fill=hexc(MAGENTA))
    m.text(M_L, 132, "MQL5  //  EXPERT ADVISOR  //  v1.00", font=F_MONOB, size=9, color=CYAN)

    m.text(M_L - 2, 232, "CANDLE", font=F_BOLD, size=58, color=WHITE)
    m.text(M_L - 2, 288, "BREAKOUT", font=F_BOLD, size=58, color=CYAN)
    m.text(M_L - 2, 340, "EA", font=F_BOLD, size=58, color=MAGENTA)
    p.draw_line(fz.Point(M_L, 358), fz.Point(PAGE_W - M_R, 358), color=hexc(GRID), width=0.7)

    m.text(M_L, 388, "ФОЙДАЛАНИШ ҚЎЛЛАНМАСИ", font=F_BOLD, size=19, color=WHITE)
    m.text(M_L, 410, "Ўрнатиш  ·  Ишлатиш  ·  Киритиш параметрлари", font=F_SANS, size=11,
           color=TXT_DIM)

    specs = [("ПЛАТФОРМА", "MetaTrader 5"), ("ТИЛ", "MQL5 (OOP)"),
             ("АСОСИЙ ВАҚТ ОРАЛИҒИ", "H1"), ("BREAK EVEN", "M5 свинг"),
             ("ЛОТ РЕЖИМЛАРИ", "4 та"), ("ФИЛЬТРЛАР", "кунлик + соатлик"),
             ("КОМПИЛЯЦИЯ", "0 хато · 0 огоҳлантириш")]
    top = 448
    m.panel(fz.Rect(M_L, top, PAGE_W - M_R, top + 176), fill=PANEL, border=CYAN, radius=5)
    p.draw_rect(fz.Rect(M_L, top, M_L + 4, top + 176), color=None, fill=hexc(CYAN))
    yy = top + 24
    for k, v in specs:
        m.text(M_L + 18, yy, k, font=F_MONO, size=8, color=TXT_DIM)
        vw = tw(v, F_MONOB, 9.4)
        m.text(PAGE_W - M_R - 18 - vw, yy, v, font=F_MONOB, size=9.4, color=WHITE)
        p.draw_line(fz.Point(M_L + 18, yy + 6), fz.Point(PAGE_W - M_R - 18, yy + 6),
                    color=hexc(GRID), width=0.35)
        yy += 22

    m.text(M_L, PAGE_H - 108, "УШБУ ҚЎЛЛАНМА ЭКСПЕРТНИНГ БАРЧА КИРИТИШ", font=F_MONO,
           size=7, color=TXT_FAINT)
    m.text(M_L, PAGE_H - 96, "ПАРАМЕТРЛАРИ ВА ИШЛАШ МАНТИҒИНИ ТЎЛИҚ ТАВСИФЛАЙДИ.",
           font=F_MONO, size=7, color=TXT_FAINT)


# ================================================================ 01
def sec_intro():
    m.new_page()
    section("01", "БУ НИМА ВА ҚАНДАЙ ИШЛАЙДИ")
    m.rich([("CandleBreakoutEA", F_BOLD, CYAN),
            (" — MetaTrader 5 учун ёзилган эксперт. Ҳар янги асосий вақт оралиғи шами "
             "(стандарти бўйича ", F_SANS, TXT),
            ("H1", F_MONOB, WHITE),
            (") очилганда у олдинги шамнинг ", F_SANS, TXT),
            ("High", F_MONOB, GREEN), (" ва ", F_SANS, TXT), ("Low", F_MONOB, MAGENTA),
            (" қийматларини ўқийди ҳамда шу икки даражага ", F_SANS, TXT),
            ("Buy Stop", F_MONOB, GREEN), (" ва ", F_SANS, TXT), ("Sell Stop", F_MONOB, MAGENTA),
            (" ордерларини қўяди. Нарх қайси даражани бузиб ўтса, ўша савдо очилади ва "
             "қарама-қарши ордер дарҳол ўчирилади.", F_SANS, TXT)])
    m.gap(6)
    sub("Асосий қоидалар")
    m.bullets([
        ("Ҳар H1 шамда", "олдинги шамнинг High даражасига Buy Stop, Low даражасига Sell Stop. Силжиш (offset) йўқ."),
        ("Битта савдо", "ордерлардан бири ишга тушса, иккинчиси ўчирилади. Шунинг учун ҳар шамда энг кўпи битта савдо."),
        ("Шам ёпилганда", "очиқ позиция ёпилади, қолган ордерлар ўчирилади. Ҳеч нарса кейинги шамга кўчирилмайди."),
        ("Break even", "позиция очилгач EA M5 га ўтади ва ҳар 2 та тугалланган шамда стопни тасдиқланган свинг ортидан кўчиради."),
        ("СЛ ва ТП йўқ", "битимларга стоп лосс ва тейк профит қўйилмайди. Ягона чиқиш — H1 шам ёпилиши (фойдада ҳам, зарарда ҳам)."),
        ("Ҳимоя", "кунлик фойда/зарар лимити ҳамда соатлар филтри."),
    ])
    m.gap(4)
    sub("Шам ёпилиши учун икки ҳимоя")
    m.numbered([
        ("EA томонидан", "янги шамнинг биринчи тикида барча очиқ савдолар ёпилади ва барча ордерлар ўчирилади."),
        ("Брокер томонидан", "агар брокер қўллаб-қувватласа, ордерларга муддат (expiration) = шам ёпилиш вақти қўйилади. Терминал ўчиб қолса ҳам ордерлар ўзи ўчади."),
    ])
    m.gap(4)
    m.note("Ҳар H1 шамда энг кўпи БИТТА савдо. Позиция шам ичида ёпилса, EA кейинги шамгача "
           "кутиб туради. Буни «Allow Re-Entry After Close In Same Candle» параметри билан "
           "ўзгартириш мумкин (стандарти: false).", CYAN, "БИР ШАМ — БИТТА САВДО")
    m.kv_panel("EA ГРАФИККА ЎРНАТИЛГАНДА", [
        ("Жорий (ярим) шам", "фақат бошланғич нуқта сифатида олинади"),
        ("Биринчи цикл", "кейинги шам очилишида бошланади"),
        ("Очиқ позиция бўлса", "EA уни ўз зиммасига олади ва бошқаради"),
    ], GREEN)


# ================================================================ 02
def sec_files():
    m.new_page()
    section("02", "ЛОЙИҲА ФАЙЛЛАРИ")
    m.para("Лойиҳа модулларга бўлинган: битта кичик .mq5 файл ва эллик учта .mqh синф модули. "
           "Ҳар бир модул фақат ўз вазифасини бажаради.")
    m.code([
        "MQL5/",
        "├── Experts/",
        "│   └── CandleBreakoutEA/",
        "│       └── CandleBreakoutEA.mq5     ← кириш нуқтаси (inputlar, OnInit, OnTick)",
        "└── Include/",
        "    └── CandleBreakoutEA/",
        "        ├── EASettings.mqh           ← enumлар + CEASettings созламалари",
        "        ├── EAUtils.mqh              ← нормаллаштириш, брокер чекловлари",
        "        ├── EALogger.mqh             ← CLogger — логга ягона йўл",
        "        ├── EATradeHistory.mqh       ← кунлик P/L, зарарлар серияси",
        "        ├── EARiskManager.mqh        ← кунлик лимит + соатлар филтри",
        "        ├── EAOrderManager.mqh       ← pending ордерлар",
        "        ├── EAPositionManager.mqh    ← позициялар",
        "        ├── EABreakEvenManager.mqh   ← M5 свинг трейлинг",
        "        ├── EAMomentum.mqh           ← моментум кучини ўлчаш",
        "        ├── EATradeContext.mqh       ← STradeContext: ягона савдо снимкаси",
        "        ├── EAContext/               ← Context Layer: trade/market/strategy/AI",
        "        ├── EAFeatureBuilder/        ← Feature Builder: ягона бозор белгилари манбаи",
        "        ├── EAData/                  ← Data Access Layer: SQLite фақат интерфейс ортида",
        "        ├── EAReplay/                ← Replay: deterministik, фақат маълумотлар базаси",
        "        ├── EAResearch/              ← Research: экспериментлар, бенчмарклар, walk-forward",
"        ├── EAHistory/               ← History: Ticks/Market/Models базалари, импорт, integrity",
        "        ├── EAExitEngine.mqh         ← чиқиш двигатели (lock / momentum / carry)",
        "        ├── EAExitStats.mqh          ← сабаблар статистикаси + CSV журнал",
        "        ├── EADashboard.mqh          ← EXIT ENGINE панел",
        "        ├── EAVisualManager.mqh      ← график объектлари",
        "        └── EATradeManager.mqh       ← шам цикли (ҳолат машинаси)",
    ], GREEN, title="ФАЙЛЛАР ТУЗИЛМАСИ")
    m.para("Include папкаси ном майдонига ажратилган (Include/CandleBreakoutEA/), шунинг учун "
           "у стандарт кутубхона ёки бошқа экспертлар билан тўқнашмайди. EA фақат "
           "<Trade\\Trade.mqh> га таянади — у ҳар бир MetaTrader 5 ўрнатишида мавжуд.")
    dg.modules_diagram(m)


# ================================================================ 03
def sec_install():
    m.new_page()
    section("03", "ЎРНАТИШ")
    sub("1-қадам — Маълумотлар папкасини очиш")
    m.numbered([
        "MetaTrader 5 терминалини ишга туширинг.",
        ("Меню:", "File → Open Data Folder  ( Файл → Маълумотлар папкасини очиш )."),
        "Очилган ойнада MQL5 папкасини топинг — файллар шу ерга нусхаланади.",
    ])
    m.gap(4)
    sub("2-қадам — Файлларни нусхалаш")
    m.table(["Манба (лойиҳадан)", "Манзил (MT5 папкасига)"],
            [["MQL5/Experts/CandleBreakoutEA/", "<Маълумотлар папкаси>/MQL5/Experts/"],
             ["MQL5/Include/CandleBreakoutEA/", "<Маълумотлар папкаси>/MQL5/Include/"]],
            widths=[1, 1.25], mono_cols=(0, 1))
    m.para("Натижада қуйидаги йўллар пайдо бўлиши керак:", size=9)
    m.code([
        "<Маълумотлар папкаси>/MQL5/Experts/CandleBreakoutEA/CandleBreakoutEA.mq5",
        "<Маълумотлар папкаси>/MQL5/Include/CandleBreakoutEA/EASettings.mqh",
        "<Маълумотлар папкаси>/MQL5/Include/CandleBreakoutEA/EATradeManager.mqh",
        "... (жами 53 та .mqh + 9 та .mq5 файл)",
    ], CYAN, title="КУТИЛАЁТГАН НАТИЖА")
    m.gap(2)
    sub("3-қадам — Компиляция қилиш")
    m.numbered([
        "МетаЭдиторни очинг (терминалда F4 ёки Навигатордан).",
        ("Файлни очинг:", "Experts/CandleBreakoutEA/CandleBreakoutEA.mq5."),
        ("Компиляция:", "F7 тугмасини босинг (ёки Compile)."),
    ])
    m.gap(4)
    m.code([
        "compiling MQL5\\Experts\\CandleBreakoutEA\\CandleBreakoutEA.mq5",
        "including MQL5\\Include\\CandleBreakoutEA\\EASettings.mqh",
        "including MQL5\\Include\\CandleBreakoutEA\\EATradeManager.mqh",
        "...",
        "code generated",
        "",
        "Result: 0 errors, 0 warnings, 1324 ms elapsed, cpu='X64 Regular'",
    ], GREEN, title="КОМПИЛЯЦИЯ НАТИЖАСИ (КУТИЛАЁТГАНИ)")
    m.note("«0 errors, 0 warnings» ёзувини кўришингиз керак. Агар «file ... not found» хатоси "
           "чиқса — Include/CandleBreakoutEA папкаси нотўғри жойга нусхаланган. 2-қадамни "
           "текширинг.", AMBER, "ТЕКСИРУВ")
    m.gap(2)
    sub("4-қадам — Терминални янгилаш")
    m.numbered([
        "Терминалга қайтинг ва Навигатор ойнасини янгиланг (ўнг тугма → Refresh).",
        "Навигатор → Expert Advisors рўйхатида CandleBreakoutEA пайдо бўлади.",
    ])


# ================================================================ 04
def sec_attach():
    m.new_page()
    section("04", "ГРАФИККА ЎРНАТИШ")
    m.numbered([
        ("Символ ва вақт оралиғи:", "керакли символ графигини H1 да очинг (EA асосий вақт оралиғини ўзи ўқийди, лекин график H1 бўлгани қулай)."),
        ("Навигатордан:", "Expert Advisors → CandleBreakoutEA ни графикка судранг ёки икки марта босинг."),
        ("«Умумий» варағи:", "«Allow Algo Trading» (Жонли савдога рухсат) белгисини ёқинг."),
        ("«Кириш параметрлари» варағи:", "қуйидаги бўлимдаги параметрларни созланг."),
        ("OK тугмаси:", "EA графикка ўрнатилади."),
        ("Авто-савдо:", "графикнинг юқори қисмидаги «Algo Trading» тугмаси ЁНИҚ (яшил) бўлиши шарт."),
    ])
    m.gap(6)
    m.kv_panel("МУВАФФАҚИЯТ БЕЛГИЛАРИ", [
        ("График юқори ўнг бурчаги", "кулранг бўлса — авто-савдо ўчиқ"),
        ("Экспертлар логи", "«Expert loaded | ...» хабари чиқади"),
        ("Кейинги H1 шамда", "«New Candle» ва «Pending Orders Created» хабарлари"),
    ], GREEN)
    m.gap(4)
    m.code([
        "2026.09.09 15:00:00 [CBEA 20260909 EURUSD] [INFO] Expert loaded | symbol=EURUSD ...",
        "2026.09.09 15:00:00 [CBEA 20260909 EURUSD] [INFO] Baseline candle 14:00 | first cycle ...",
        "2026.09.09 16:00:00 [CBEA 20260909 EURUSD] [INFO] New Candle | #1 | PERIOD_H1 | ...",
        "2026.09.09 16:00:00 [CBEA 20260909 EURUSD] [TRADE] Pending Orders Created | BuyStop ...",
    ], GREEN, title="ЛОГДА КЎРИНАДИГАН БИРИНЧИ ХАБАРЛАР")
    m.note("Агар «Algo Trading» тугмаси ўчиқ бўлса, EA ордер қўя олмайди ва логда "
           "«Trade disabled» хатоси чиқади. Тугмани босинг ёки терминал созламаларида "
           "авто-савдога рухсат беринг.", RED, "МУҲИМ")


# ================================================================ 05
def sec_strategy():
    m.new_page()
    section("05", "СТРАТЕГИЯ ЦИКЛИ")
    m.table(["#", "Босқич", "Нима содир бўлади"],
            [["1", "Шам ёпилиши", "Очиқ позиция ёпилади, қолган ордерлар ўчирилади"],
             ["2", "Фильтрлар", "Соатлар филтри, кунлик фойда ва зарар лимити текширилади"],
             ["3", "Ўқиш", "Олдинги шамнинг High ва Low қийматлари олинади"],
             ["4", "Ордерлар", "Buy Stop = prev High, Sell Stop = prev Low — СЛ ва ТП сиз, силжишсиз"],
             ["5", "Триггер", "Биринчи ишга тушган ордер қарама-қарши ордерни ўчиради"],
             ["6", "Break even + Exit Engine", "Позиция очиқ пайт EA M5 свинг трейлигини бошқаради; чиқиш двигатели фойдани қулфлайди ва моментумни кузатади (07-бўлим)"],
             ["7", "Флэт", "H1 шам ёпилганда ҳаммаси ёпилади; фақат Carry Mode (ўчиқ) кучли фойдали позицияни битта қўшимча шамга ушлаб туради"]],
            widths=[0.3, 1.1, 3.4], mono_cols=(0,))
    dg.strategy_diagram(m)
    sub("Нима учун айнан шундай")
    m.bullets([
        ("Силжиш йўқ", "Buy Stop айнан prev High да, Sell Stop айнан prev Low да туради."),
        ("СЛ ва ТП йўқ", "ордерлар тоза жойлаштирилади; асосий чиқиш — шам ёпилиши. Чиқиш двигатели (07-бўлим) фойдани қулфлаш, моментум ва ихтиёрий break-even орқали эрта ёпиши мумкин."),
        ("Break Even (ихтиёрий)", "ёқилгандагина EA позиция ортидан M5 свинг асосида SL қўяди; стандартида ўчиқ."),
        ("Муддат", "брокер рухсат берса, ордерлар шам ёпилишида автоматик ўчади."),
    ], CYAN)


# ================================================================ 06
def sec_be():
    m.new_page()
    section("06", "BREAK EVEN (M5 СВИНГ)")
    m.rich([("Enable BreakEven = true", F_MONOB, GREEN),
            (" (стандартида false) бўлса, позиция очилгач EA M5 га ўтади. Битимда бошланғич SL бўлмайди — биринчи тасдиқланган свинг уни яратади. У ", F_SANS, TXT),
            ("тўлдирилган", F_BOLD, WHITE),
            (" M5 шамларини санайди ва ҳар ", F_SANS, TXT),
            ("N", F_MONOB, WHITE),
            (" та шамда (стандарти 2) стопни охирги тасдиқланган свинг ортига кўчиради.",
             F_SANS, TXT)])
    m.gap(6)
    sub("Қоидалар")
    m.bullets([
        ("Свинг нима", "пивот шам икки томондан «Swing Bars» та (стандарти 2) шамдан баланд/паст бўлса, у тасдиқланган свинг ҳисобланади."),
        ("Long", "стоп охирги тасдиқланган свинг LOW ортига кўчади."),
        ("Short", "стоп охирги тасдиқланган свинг HIGH ортига кўчади."),
        ("Фақат олдинга", "стоп ҳеч қачон савдо зарарига қайтарилмайди."),
        ("Фақат фойдада", "стоп entry + spread дан ўтмагунча кўчирилмайди."),
        ("Брокер масофаси", "стоп бозор нархига брокер минимал масофасидан яқин қўйилмайди."),
        ("Свинг бўлмаса", "EA кутиб туради, стопни ўзи break-even га сакратмайди."),
    ], AMBER)
    dg.breakeven_diagram(m)
    m.kv_panel("BREAK EVEN СУКУТ ПАРАМЕТРЛАРИ", [
        ("Enable BreakEven", "false (ихтиёрий)"),
        ("BreakEven Timeframe", "PERIOD_M5"),
        ("Swing Bars", "2  (ҳар икки томондан)"),
        ("Update Every N Completed Bars", "2"),
        ("BreakEven Buffer (points)", "0"),
    ], AMBER)


# ================================================================ 07 EXIT ENGINE
def sec_exit():
    m.new_page()
    section("07", "ЧИҚИШ ИНТЕЛЛЕКТ ДВИГАТЕЛИ")
    m.para("Позиция очиқ пайт чиқишлар қатъий устувонлик тартибида текширилади. Кириш "
           "логикаси, pending ордерлар, риск ва лот ҳисоби ТЕГИЛМАГАН — двигатель фақат "
           "эрта ёпади ёки бир шамга ушлайди, янги савдо очмайди.")
    m.table(["#", "Чиқиш", "Триггер", "Сабаб (CSV)"],
            [["1", "BreakEven", "ихтиёрий M5 свинг стоп ишга тушиши (аввалги хатти-ҳаракат)", "BreakEven"],
             ["2", "Profit Lock", "сузувчи фойда «Profit Lock Trigger» га етиб, кейин чўққининг «Keep %» ига қайтса", "Profit Lock"],
             ["3", "Momentum Exit", "3 та тўлган шамдан кейин моментум бали «Momentum Sensitivity» дан тушса", "Momentum Exit"],
             ["4", "Шам ёпилиши", "мажбурий флэт — H1 шам ёпилганда (ҳар доим)", "H1 Close"]],
            widths=[0.3, 1.0, 2.6, 0.9], mono_cols=(0, 3))
    m.gap(2)
    sub("Моментум бали (0–100)")
    m.bullets([
        ("Ўлчов", "CMomentumAnalyzer савдо йўналишидаги охирги 3 та ТЎЛГАН M5 шамни ўқийди: йўналишдаги тўла тана — юқори балл, қарама-қарши соялар ва қарама-қарши шамлар — паст балл."),
        ("Қўшимча жарима", "кетма-кет икки қарама-қарши шам, учта кичраювчи тана ёки охирги шамнинг «доджи» кўриниши баллни камаятиради."),
        ("Фақат ўлчов", "балл ҳеч нима очмайди ва ёпмайди — у фақат чиқиш қарорига ва панелга хизмат қилади."),
    ], CYAN)
    m.gap(2)
    sub("Carry Mode (стандартида ЎЧИҚ)")
    m.bullets([
        ("Битта қўшимча шам", "шам ёпилишида позиция ФОЙДАДА бўлса ва моментум бали «Minimum Trend Strength For Carry» дан юқори бўлса, у РОЗАТТА БИРТА қўшимча шамга қолади."),
        ("Қатъий чегара", "«Maximum Carry Candles» фақат 1 бўлиши мумкин — бошқа қийматни OnInit рад этади."),
        ("Янги савдо йўқ", "carry пайтида янги pending ордерлар қўйилмайди; кейинги шам ёпилишида позиция «Carry Expired» сабаби билан ёпилади."),
    ], MAGENTA)
    m.gap(2)
    sub("Чиқиш журнали ва статистика")
    m.para("Ҳар бир ёпилган савдо (брокер ёки терминал ёпганлари ҳам — «BreakEven» ёки "
           "«Manual» деб таснифланади) логга ёзилади, ҳисоблагичга қўшилади ва CSV файлга "
           "қўшилади: MQL5/Files/CBEA_<magic>_<symbol>_exits.csv")
    m.code([
        "Ticket;OpenTime;CloseTime;Side;Lots;Profit;ExitReason;",
        "MaximumFloatingProfit;MaximumFloatingLoss;ProfitLocked;CarryUsed;MomentumScore;",
        "EntryPrice;ExitPrice;BreakEvenUsed;MomentumExit",
    ], GREEN, title="CSV УСТУНЛАРИ")
    m.gap(2)
    sub("Trade Context ва Dashboard панел")
    m.para("Очиқ позиция пайти trade manager ягона STradeContext снимкасини тўлдиради "
           "(тикет, йўналиш, кириш вақти/шами/нархи, жорий фойда, MFE/MAE, break-even / "
           "profit-lock / carry байроқлари, моментум бали, режалаштирилган чиқиш). Панел ва "
           "журнал фақат шу снимкани ЎҚИЙДИ: Strategy State, BreakEven, Profit Lock, Carry, "
           "Momentum, Floating, Planned Exit, битим хулосаси ва «H1 BE PL MO CR MN ER» "
           "статистикаси. Context Layer (EAContext/, ADR-0001) шу снимка асосида\n           \"тўртта контекстни юритади: trade manager ягона ёзувчи, қолганлари фақат ўқийди.\"")


# ================================================================ 08
def sec_lots():
    m.new_page()
    section("08", "ЛОТ ҲАЖМИ РЕЖИМЛАРИ")
    m.table(["Режим", "Қандай ҳисобланади"],
            [["Fixed Lot", "Fixed Lot қиймати бевосита (символ лот қадами ва min/max га нормаллаштирилади)"],
             ["Risk % of Balance", "баланс × Risk% ÷ (1 лот учун зарар). Масофа «Risk Stop Distance» инпутидан олинади (фақат лот ҳисоби, СЛ ўрнатмайди); 0 бўлса EA огоҳлантириб, ордер қўймайди"],
             ["Soft Martingale", "база лот × Multiplier^min(зарарлар серияси, MaxSteps) — серия MAXIMUM қадамда ТЎХТАЙДИ"],
             ["Hard Martingale", "база лот × Multiplier^(зарарлар серияси mod MaxSteps) — серия MAXIMUM қадамдан кейин НОЛГА қайтади"]],
            widths=[1.1, 3.2], mono_cols=(0,))
    dg.martingale_diagram(m)
    sub("Зарарлар серияси қаердан олинади")
    m.para("Кетма-кет зарарлар сони ҳисоб тарихидан ўқилади (magic + symbol бўйича "
           "филтрланган деаллар). Шунинг учун EA қайта ишга туширилганда ҳам серия "
           "йўқолмайди.")
    m.note("Мартингейл лот ҳажмини оширади ва ҳисобни тез тўлдириши мумкин. «Maximum "
           "Martingale Steps» ни кичик ушланг ва аввал демо ҳисобда синаб кўринг.",
           RED, "ХАВФ")


# ================================================================ 08
def sec_filters():
    m.new_page()
    section("09", "ФИЛЬТРЛАР")
    sub("Кунлик лимитлар")
    m.bullets([
        ("Daily Profit Limit", "жорий сервер кунидаги ёпилган савдолардан олинган фойда (profit + swap + commission). Лимитга етилса, EA янги шамни ўтказиб юборади."),
        ("Daily Loss Limit", "худди шундай, лекин зарар томонида."),
        ("0 қиймати", "лимит ўчиқ дегани."),
        ("Log", "«Daily Limit Reached | profit 512.00 >= 500.00» кўринишида ёзилади."),
    ], GREEN)
    m.gap(6)
    sub("Соатлар филтри — 24 битли ниқоб")
    m.para("«Trading Hours Bitmask» — 24 битли сон. Бит 0 = 00:00, бит 23 = 23:00. Ҳар бир "
           "соат мустақил ёқилади ёки ўчирилади. Қиймат SERVER соатига нисбатан текширилади.")
    dg.hours_diagram(m, set(range(24)), "барча соатлар ёқилган (стандарт)")
    dg.hours_diagram(m, set(range(8, 17)), "фақат 08:00–16:59")
    m.table(["Керакли соатлар", "Ниқоб", "Изоҳ"],
            [["Барча соатлар", "16777215", "стандарт қиймат (0xFFFFFF)"],
             ["00:00–06:59", "127", "Осиё сессияси"],
             ["08:00–16:59", "130816", "Лондон"],
             ["07:00–20:59", "2097024", "Лондон + Нью-Йорк"]],
            widths=[1.4, 0.9, 2.0], mono_cols=(1,))
    m.para("Ихтиёрий қийматни ҳисоблаш: керакли соатларнинг 2 даражаларини қўшинг. "
           "Масалан, 09 ва 17 соатлари учун 2^9 + 2^17 = 512 + 131072 = 131584.", size=9)


# ================================================================ 09 + 10
def sec_visual_log():
    m.new_page()
    section("10", "ГРАФИК ОБЪЕКТЛАРИ")
    m.table(["Объект", "Маъноси"],
            [["Кўк узуқ чизиқ — Prev High", "олдинги шамнинг юқори чегараси (buy trigger)"],
             ["Қизил узуқ чизиқ — Prev Low", "олдинги шамнинг пастки чегараси (sell trigger)"],
             ["Яшил / қизил кесма", "pending ордернинг яшаш муддати"],
             ["Яшил ▲ / қизил ▼", "савдога кириш нуқтаси"],
             ["Сариқ ✕", "савдодан чиқиш нуқтаси"],
             ["Олтин нуқтали чизиқ — BE", "жорий break-even / трейлинг стоп даражаси"],
             ["Юқори-ўнг панел — EXIT ENGINE", "жорий чиқиш ҳолати, моментум бали ва сабаблар статистикаси"]],
            widths=[1.6, 2.6])
    m.para("Барча объектлар «CBEA_<magic>_» префикси билан яратилади ва EA графикдан "
           "олиб ташланганда автоматик ўчирилади. «Draw Chart Objects = false» уларни "
           "бутунлай ўчиради.")
    m.gap(8)
    section("11", "ЭКСПЕРТЛАР ЛОГИ")
    m.para("Ҳар қатор стандарт форматда: «вақт [CBEA magic символ] [ТЕГ] хабар»; тикет бор "
           "бўлса хабарга киради. Фақат етита тег мавжуд: INFO, WARNING, ERROR, TRADE, "
           "EXIT, BREAK EVEN, MOMENTUM.")
    m.code([
        "09.09 14:00 [CBEA 20260909 EURUSD] [INFO]  New Candle | #12 | close 15:00",
        "09.09 14:00 [CBEA 20260909 EURUSD] [TRADE] Pending Orders Created | no SL | no TP",
        "09.09 14:12 [CBEA 20260909 EURUSD] [TRADE] Buy Triggered | #184467448 | 0.10",
        "09.09 14:35 [CBEA ...] [BREAK EVEN] BreakEven Updated | #184467448 ...",
        "09.09 14:41 [CBEA ...] [EXIT] Profit Lock armed | peak 412 | lock 206",
        "09.09 14:52 [CBEA ...] [EXIT] Trade Closed | #184467448 | Profit Lock",
        "09.09 15:00 [CBEA ...] [MOMENTUM] Momentum Exit | score 33 < 40",
        "09.09 15:00 [CBEA ...] [WARNING] Daily Limit Reached | 512.00 >= 500.00",
    ], GREEN, title="ЛОГ НАМУНАЛАРИ")
    m.table(["Log Level", "Нима ёзилади"],
            [["Errors only", "фақат хатолар"],
             ["Errors + Warnings", "хатолар ва огоҳлантиришлар"],
             ["Info", "юқоридагилар + асосий ҳодисалар (стандарт)"],
             ["Everything", "барчаси, жумладан debug хабарлари"]],
            widths=[1.1, 3.0], mono_cols=(0,))


# ================================================================ 11
def sec_inputs():
    m.new_page()
    section("12", "КИРИТИШ ПАРАМЕТРЛАРИ")
    m.para("Барча параметрлар EA ўрнатилаётганда «Кириш параметрлари» варағида кўринади. "
           "Нотўғри қиймат киритилса, EA INIT_PARAMETERS_INCORRECT билан ишдан чиқади ва "
           "сабабини логга ёзади.")

    sub("Trading — савдо", CYAN)
    m.table(["Параметр", "Стандарт", "Тавсиф"],
            [["Main Timeframe", "PERIOD_H1", "Бутун циклни бошқарадиган вақт оралиғи. «Current» танлаш мумкин эмас"],
             ["Magic Number", "20260909", "EA ордерларини, позицияларини ва тарихини ажратиб туради"],
             ["Order Comment", "CandleBreakout", "Ордерларга ёзиладиган изоҳ"],
             ["Allow Re-Entry After Close In Same Candle", "false", "false = ҳар шамда қатъий битта савдо"]],
            widths=[1.5, 0.8, 2.6], mono_cols=(1,))

    sub("Risk — риск ва лот", MAGENTA)
    m.table(["Параметр", "Стандарт", "Тавсиф"],
            [["Lot Mode", "Fixed Lot", "Fixed / Risk % / Soft Martingale / Hard Martingale"],
             ["Fixed Lot", "0.10", "Fixed режимида ишлатилади; мартингейл учун база лот"],
             ["Risk % Of Balance", "1.0", "Risk ва мартингейл режимларида балансдан олинадиган фоиз"],
             ["Martingale Multiplier", "1.5", "Ҳар қадамда лотни кўпайтириш коэффициенти"],
             ["Maximum Martingale Steps", "5", "Soft: чегара. Hard: қайта бошланиш нуқтаси"],
             ["Risk Stop Distance (points)", "500", "Фақат лот ҳисоби учун; ордерга СЛ қўймайди; 0 = огоҳлантириш, ордер қўйилмайди"],
             ["Enable Daily Limits", "true", "Кунлик лимитларни ёқиш"],
             ["Daily Profit Limit", "0", "0 = ўчиқ. Кунлик фойда чегараси"],
             ["Daily Loss Limit", "0", "0 = ўчиқ. Кунлик зарар чегараси"]],
            widths=[1.5, 0.8, 2.6], mono_cols=(1,))

    sub("Break Even", AMBER)
    m.table(["Параметр", "Стандарт", "Тавсиф"],
            [["Enable BreakEven", "false", "M5 свинг трейлинги; ўчиқ бўлса битимда умуман SL бўлмайди"],
             ["BreakEven Timeframe", "PERIOD_M5", "Свинглар қайси вақт оралиғида изланади"],
             ["Swing Bars", "2", "Пивотнинг ҳар икки томонидаги шамлар сони"],
             ["Update Every N Completed Bars", "2", "Стопни кўчириш частотаси"],
             ["BreakEven Buffer (points)", "0", "Свингдан қўшимча масофа"]],
            widths=[1.5, 0.8, 2.6], mono_cols=(1,))

    sub("Exit Engine — чиқиш двигатели", MAGENTA)
    m.table(["Параметр", "Стандарт", "Тавсиф"],
            [["Enable Profit Lock", "true", "Чиқиш #2: катта сузувчи фойданинг фақат бир қисмини қайтариш"],
             ["Profit Lock Trigger (points)", "300", "Қулфни фаоллаштирадиган сузувчи фойда (пункт)"],
             ["Profit Lock Keep (%)", "50", "Чўққидан сақлаб қолинадиган улуш"],
             ["Enable Momentum Exit", "true", "Чиқиш #3: тренд сустлашганда эрта чиқиш"],
             ["Momentum Sensitivity", "40", "Балл (0–100) шундан тушса позиция ёпилади"],
             ["Enable Carry Mode", "false", "Кучли фойдали позицияга битта қўшимча шам"],
             ["Maximum Carry Candles", "1", "Қатъий чегара — бошқа қийматни OnInit рад этади"],
             ["Minimum Trend Strength For Carry", "70", "Carry учун керакли моментум бали"]],
            widths=[1.5, 0.8, 2.6], mono_cols=(1,))

    sub("Advanced — қўшимча", GREEN)
    m.table(["Параметр", "Стандарт", "Тавсиф"],
            [["Enable Trading Hours Filter", "false", "Соатлар филтрини ёқиш"],
             ["Trading Hours Bitmask", "16777215", "24 битли соат ниқоби (bit0 = 00:00)"]],
            widths=[1.5, 0.8, 2.6], mono_cols=(1,))

    sub("Dashboard — панель", CYAN)
    m.table(["Параметр", "Стандарт", "Тавсиф"],
            [["Show Exit Dashboard Panel", "true", "Юқори-ўнг EXIT ENGINE / STATISTICS панел"],
             ["Draw Chart Objects", "true", "График объектларини чизиш"]],
            widths=[1.5, 0.8, 2.6], mono_cols=(1,))

    sub("Logging — лог", GREEN)
    m.table(["Параметр", "Стандарт", "Тавсиф"],
            [["Enable Logging", "true", "Логни бутунлай ўчириш / ёқиш"],
             ["Log Level", "Info", "Errors only / Errors + Warnings / Info / Everything"]],
            widths=[1.5, 0.8, 2.6], mono_cols=(1,))

    sub("Future AI — захира", MAGENTA)
    m.table(["Параметр", "Стандарт", "Тавсиф"],
            [["Reserved for future AI modules", "false", "Фақат захира ўрин; ҳозирча таъсирсиз"]],
            widths=[1.5, 0.8, 2.6], mono_cols=(1,))


# ================================================================ 12 + 13
def sec_extend():
    section("13", "КЕНГАЙТИРИШ")
    m.para("Архитектура янги функцияларни қўшишга мосланган. Ҳар бир ўзгариш битта "
           "жойда қилинади:")
    m.table(["Нима қўшмоқчисиз", "Қаерда ўзгартирасиз"],
            [["Янги лот режими", "ENUM_LOT_MODE га қиймат қўшинг ва CTradeManager::CalculateLotSize ни кенгайтиринг"],
             ["Янги филтр", "CRiskManager::Check га ҳолат қўшинг — у ENUM_TRADE_BLOCK қайтаради ва сабабини ўзи логга ёзади"],
             ["Янги график объекти", "CVisualManager га метод қўшинг — тозалаш префикс орқали автоматик"],
             ["Бошқа чиқиш қоидаcи", "CExitEngine::OnTick га текширув ва ENUM_EXIT_REASON га қиймат қўшинг; мажбурий флэт CTradeManager::CloseCandle да қолади"],
             ["Янги чиқиш статистикаси", "SExitRecord ва CExitStats::Record ни CSV сарлавҳаси билан бирга кенгайтиринг"]],
            widths=[1.2, 3.0])
    m.gap(6)
    section("14", "КОМПИЛЯЦИЯ ТЕКСИРУВИ")
    m.para("Лойиҳа ҳақиқий MetaQuotes компилятори (MetaEditor64.exe) билан текширилган. "
           "06_Tools/build.py скрипти манбаларни ҳақиқий MT5 маълумотлар папкасига жойлайди ва "
           "компилляция қилади:")
    m.code([
        "$ python3 06_Tools/build.py",
        "",
        "staged into     : QuantResearchOS/.build",
        "standard library: True",
        "compiler result : 0 error(s), 0 warning(s)",
        "binary          : CandleBreakoutEA.ex5 (207,814 bytes)",
        "",
        "VERDICT: PASS - 0 errors, 0 warnings, binary produced",
    ], GREEN, title="ТЕКСИРУВ НАТИЖАСИ")
    m.note("Компиляция фақат код тўғри қурилганини тасдиқлайди. Брокер ҳисобидаги ҳақиқий "
           "ишлаш (ордерларнинг бажарилиши, expiration қўллаб-қувватланиши, stops level, "
           "hedging/netting) синовдан ўтказилмаган. Жонли ҳисобдан олдин Strategy Tester ва "
           "демо ҳисобда текширинг.", AMBER, "ЧЕГАРА")


# ================================================================ 14
def sec_warnings():
    m.new_page()
    section("15", "МУҲИМ ЭСЛАТМАЛАР")
    m.bullets([
        ("Нормаллаштириш", "барча нархлар ва лотлар символнинг tick size, digits, lot қадами ҳамда min/max қийматларига мослаштирилади."),
        ("Брокер чекловлари", "stops level ва freeze level pending нархлари, стоплар ва трейлинг учун ҳисобга олинади. Шартни бажара олмайдиган ордер ўтказиб юборилади ва логга огоҳлантириш ёзилади."),
        ("Тўлдириш сиёсати", "SYMBOL_FILLING_MODE дан автоматик танланади (FOK → IOC → RETURN)."),
        ("EA олиб ташланганда", "график объектлари ўчади, лекин очиқ позициялар ва ордерлар ҚОЛАДИ. Уларни ўзингиз ёпишингиз керак."),
        ("Сервер вақти", "соатлар филтри ва кунлик лимитлар SERVER соати бўйича ишлайди, маҳаллий вақт бўйича эмас."),
        ("Magic Number", "бир нечта графикка ўрнатсангиз, ҳар бирига алоҳида magic беринг, акс ҳолда улар бир-бирининг савдоларини бошқаради."),
    ], CYAN)
    m.gap(8)
    m.panel(fz.Rect(M_L, m.y, PAGE_W - M_R, m.y + 100), fill="#1A0F1C", border=RED, radius=4)
    m.page.draw_rect(fz.Rect(M_L, m.y, M_L + 4, m.y + 100), color=None, fill=hexc(RED))
    m.text(M_L + 16, m.y + 24, "ХАВФ-ОГОҲЛАНТИРИШ", font=F_MONOB, size=9, color=RED)
    txt = ("Ушбу эксперт савдо стратегиясини автоматлаштиради ва фойдани кафолатламайди. "
           "Мартингейл режимлари ҳисобни тез йўқотишга олиб келиши мумкин. Ҳар қандай "
           "созламани аввал Strategy Tester ва демо ҳисобда синаб кўринг. Савдо қарорлари "
           "ва натижалари учун жавобгарлик фойдаланувчининг ўзида.")
    yy = m.y + 44
    for line in wrap(F_SANS, txt, 9.0, CONTENT_W - 40):
        m.text(M_L + 16, yy, line, font=F_SANS, size=9.0, color=TXT)
        yy += 13.6
    m.y += 116
    m.gap(6)
    m.kv_panel("ҚЎЛЛАНМА ҲАҚИДА", [
        ("Эксперт", "CandleBreakoutEA v1.00"),
        ("Платформа", "MetaTrader 5 / MQL5 (OOP)"),
        ("Модуллар", "53 та .mqh синф + 1 та .mq5"),
        ("Код ҳажми", "9 603 қатор"),
        ("Компиляция", "0 хато · 0 огоҳлантириш"),
    ], CYAN)


# ================================================================ ЙИҒИШ
cover()
m.bookmark(1, "Муқова", 1)
sec_intro()
sec_files()
sec_install()
sec_attach()
sec_strategy()
sec_be()
sec_exit()
sec_lots()
sec_filters()
sec_visual_log()
sec_inputs()
sec_extend()
sec_warnings()
path = m.save()
print("saved:", path, "| pages:", m.page_no)
