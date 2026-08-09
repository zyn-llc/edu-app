"""
Uzbekistan regions (viloyatlar) + Karakalpakstan + Tashkent city.

The `code` is the canonical key used in users.region_code and as the region
leaderboard key, so it must stay stable. Names are provided uz-Latn + ru for the
profile dropdown; the client may also localize from these.
"""

REGIONS: list[dict[str, str]] = [
    {"code": "qoraqalpogiston", "uz": "Qoraqalpog'iston", "ru": "Каракалпакстан"},
    {"code": "andijon", "uz": "Andijon", "ru": "Андижан"},
    {"code": "buxoro", "uz": "Buxoro", "ru": "Бухара"},
    {"code": "fargona", "uz": "Farg'ona", "ru": "Фергана"},
    {"code": "jizzax", "uz": "Jizzax", "ru": "Джизак"},
    {"code": "xorazm", "uz": "Xorazm", "ru": "Хорезм"},
    {"code": "namangan", "uz": "Namangan", "ru": "Наманган"},
    {"code": "navoiy", "uz": "Navoiy", "ru": "Навои"},
    {"code": "qashqadaryo", "uz": "Qashqadaryo", "ru": "Кашкадарья"},
    {"code": "samarqand", "uz": "Samarqand", "ru": "Самарканд"},
    {"code": "sirdaryo", "uz": "Sirdaryo", "ru": "Сырдарья"},
    {"code": "surxondaryo", "uz": "Surxondaryo", "ru": "Сурхандарья"},
    {"code": "toshkent", "uz": "Toshkent viloyati", "ru": "Ташкентская обл."},
    {"code": "toshkent_shahri", "uz": "Toshkent shahri", "ru": "город Ташкент"},
]

REGION_CODES: set[str] = {r["code"] for r in REGIONS}
