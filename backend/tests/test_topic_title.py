"""Bo'lim sarlavhasi: darslik raqamlashi olinadi, yil oralig'i qoladi.

Bu funksiyada bitta tuzoq bor va u aynan shu testni talab qiladi. Bo'lim
kodlarining ikkala turi ham RAQAM bilan boshlanadi:

    "100-§. Hosilaning geometrik ma'nosi"      -> raqam darslik paragrafi
    "1991-2017-yillarda Fransiya"              -> raqam MA'NONING O'ZI

Kengroq yozilgan "boshidagi raqamni olib tashla" qoidasi ikkinchisini
"-yillarda Fransiya" ga aylantiradi va buni hech qanday test ushlamaydi —
u faqat jahon tarixi bo'limlarini ochgan o'quvchiga ko'rinadi.

`sql/029_topic_titles.sql` bazadagi mavjud qatorlarga xuddi shu mantiqni
qo'llaydi. Ikkalasi bir xil qolishi kerak.
"""
import pytest

from app.ingest.run_subject import topic_title

@pytest.mark.parametrize("code,kutilgan", [
    # --- darslik raqamlashi olinadi ---
    ("100-§. Hosilaning geometrik ma'nosi", "Hosilaning geometrik ma'nosi"),
    ("94-§. Murakkab trigonometriya", "Murakkab trigonometriya"),
    ("14.1-bo'lim. Elementar funksiyalarning hosilasi",
     "Elementar funksiyalarning hosilasi"),
    ("14.1.1-bo'lim. Murakkab funksiyaning hosilasi (qo'shimcha manba)",
     "Murakkab funksiyaning hosilasi (qo'shimcha manba)"),
    # Nuqtasiz `§` va butunlay qavsga o'ralgan qoldiq.
    ("104-§ (test qismi, Variant 47)", "Test qismi, Variant 47"),
])
def test_darslik_raqami_olinadi(code, kutilgan):
    assert topic_title(code) == kutilgan

@pytest.mark.parametrize("code", [
    "1991-2017-yillarda amerika qo'shma shtatlari",
    "1991 – 2017-yillarda dunyo mamlakatlari",
    "1991-2017-yillarda boltiqbo'yi davlatlari",
])
def test_yil_oraligi_saqlanadi(code):
    assert topic_title(code) == code

def test_oddiy_kod_probel_va_bosh_harf():
    assert topic_title("biologiya_hayot_haqidagi_fan") == \
        "Biologiya hayot haqidagi fan"

def test_ichki_bosh_harflar_saqlanadi():
    """`.capitalize()` bo'lsa bu "Xitoy xalq respublikasi" bo'lib qolardi."""
    assert topic_title("Xitoy Xalq Respublikasi") == "Xitoy Xalq Respublikasi"

def test_qavsli_qoldiq_ichki_qavs_bilan_ochilmaydi():
    """Faqat BUTUN sarlavha qavsda bo'lsa ochiladi.

    "Aniq integral (qo'shimcha manba)" — qavs matnning bir qismi, uni
    ochish sarlavhani buzadi.
    """
    assert topic_title("14.4.1-bo'lim. Aniq integral (qo'shimcha manba)") == \
        "Aniq integral (qo'shimcha manba)"

def test_idempotent():
    """Tozalangan sarlavhani qayta o'tkazish uni o'zgartirmaydi."""
    once = topic_title("100-§. Hosilaning geometrik ma'nosi")
    assert topic_title(once) == once
