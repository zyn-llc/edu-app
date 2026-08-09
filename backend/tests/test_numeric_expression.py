"""Sonli javob: π, √, daraja va qavs.

MUAMMO (2026-08-09, ilovada ko'rilgan). Javob maydoni ostida beshta tugma
turadi: `a/b`, `√`, `π`, `x²`, `( )`. Grader esa faqat sonni va oddiy
kasrni tushunardi — `float("π/2")` ValueError berardi va javob NOTO'G'RI
deb baholanardi. Ya'ni javobni bilgan o'quvchi ilova o'ZI taklif qilgan
tugmani bosgani uchun ball yo'qotardi.

Bu testda uch guruh bor va uchalasi ham kerak:

  1. ESKI XATTI-HARAKAT O'ZGARMAGANI. Baholash — mahsulotning eng nozik
     joyi: bu yerdagi regressiya to'g'ri javobni noto'g'riga aylantiradi
     va o'quvchi buni o'zidan ko'radi. Ifoda baholagichi ataylab FAQAT
     ilgari ValueError bergan satrlarni ko'radi.

  2. Yangi shakllar — aynan tugmalar chiqaradigan ko'rinishda.

  3. XAVFSIZLIK. Baholagich foydalanuvchi yuborgan satr ustida ishlaydi.
     `eval` ishlatilmaydi; `ast` daraxti oq ro'yxat bo'yicha tekshiriladi.
     Bu guruh o'sha oq ro'yxatni qulflaydi.
"""
import math

import pytest

from app.services.grading import _parse_student_number as parse


class TestEskiXattiHarakat:
    """Ilgari ishlagan har bir shakl AYNAN o'sha qiymatni qaytaradi."""

    @pytest.mark.parametrize("raw,kutilgan", [
        (0.5, 0.5),
        (42, 42.0),
        ("42", 42.0),
        ("0,5", 0.5),          # o'zbek/rus o'nlik vergul
        ("0.5", 0.5),
        ("1/3", 1 / 3),
        ("-16/3", -16 / 3),
        ("−2", -2.0),     # Unicode minus
        ("  7  ", 7.0),
        ("1e3", 1000.0),
    ])
    def test_ozgarmagan(self, raw, kutilgan):
        assert parse(raw) == pytest.approx(kutilgan)

    def test_nolga_bolish_hamon_xato(self):
        with pytest.raises(ValueError):
            parse("1/0")


class TestTugmalarChiqaradiganShakllar:
    """Maydon ostidagi tugmalar aynan shu satrlarni hosil qiladi."""

    @pytest.mark.parametrize("raw,kutilgan", [
        ("π", math.pi),
        ("π/2", math.pi / 2),
        ("π/6", math.pi / 6),
        ("2π", 2 * math.pi),              # yashirin ko'paytirish
        ("2π/3", 2 * math.pi / 3),
        ("√2", math.sqrt(2)),             # qavssiz — eng ko'p uchraydigan shakl
        ("√(9)", 3.0),
        ("√9", 3.0),
        ("3√2", 3 * math.sqrt(2)),
        ("√2/2", math.sqrt(2) / 2),
        ("1/√2", 1 / math.sqrt(2)),
        ("-√4", -2.0),
        ("√π", math.sqrt(math.pi)),
        ("2^3", 8.0),
        ("2^-1", 0.5),
        ("(1+2)/3", 1.0),
        ("(2+3)*4", 20.0),
    ])
    def test_baholanadi(self, raw, kutilgan):
        assert parse(raw) == pytest.approx(kutilgan)

    def test_sqrt_bitta_atomga_tegishli(self):
        """`√2+3` = `sqrt(2)+3`, `sqrt(2+3)` EMAS — matematik odat."""
        assert parse("√2+3") == pytest.approx(math.sqrt(2) + 3)

    def test_javob_kaliti_tolerantligiga_tushadi(self):
        """Amaliy tekshiruv: π/2 javobi saqlangan o'nlik kalitga mos keladi.

        Ingest kalitni `value` + `tolerance` bo'lib saqlaydi (kasr qiymat
        uchun tolerantlik qiymatning 0.1% i). O'quvchi `π/2` deb yozsa,
        natija shu oraliqqa tushishi kerak — aks holda bu tuzatishning
        amalda foydasi yo'q.
        """
        saqlangan = 1.5708                      # kalit shu aniqlikda yozilgan
        tolerantlik = abs(saqlangan) * 1e-3
        assert abs(parse("π/2") - saqlangan) <= tolerantlik


class TestXavfsizlik:
    """Baholagich foydalanuvchi satrini ko'radi — oq ro'yxat qulflanadi."""

    @pytest.mark.parametrize("raw", [
        "__import__('os').system('ls')",
        "eval('1+1')",
        "open('/etc/passwd')",
        "pi.__class__",
        "().__class__.__bases__",
        "[1,2,3]",
        "{'a':1}",
        "lambda: 1",
        "x",
        "abc",
        "1;2",
        "1+",
        "sqrt(-1)",          # haqiqiy son emas
        "9**9**9",           # serverni osishga urinish
        "2^999",
        "1+" * 100 + "1",    # uzunlik chegarasi
        "1+" * 30 + "1",     # daraxt hajmi chegarasi
        "",                  # bo'sh javob — SyntaxError 500 ga aylanmasin
        "   ",
    ])
    def test_rad_etiladi(self, raw):
        with pytest.raises((ValueError, SyntaxError, TypeError)):
            parse(raw)

    def test_grader_500_bermaydi(self):
        """Noto'g'ri kirish 500 emas, «noto'g'ri javob» bo'lishi kerak."""
        from app.schemas.question import GradingQuestion, QuestionType
        from app.services.grading import _GRADERS

        q = GradingQuestion(
            id="x", type=QuestionType.numeric, max_score=1,
            grading_spec={"value": 1.0, "tolerance": 0.0},
        )
        grader = _GRADERS[QuestionType.numeric]
        assert grader(q, {"value": "__import__('os')"}) is False
        assert grader(q, {"value": "9**9**9"}) is False
