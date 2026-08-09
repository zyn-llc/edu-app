-- Seed reference data: languages (the 2 app versions), regions, the 10 subjects.

INSERT INTO languages (code, name) VALUES
    ('uz-Latn', 'O''zbekcha'),
    ('ru', 'Русский')
ON CONFLICT (code) DO NOTHING;

INSERT INTO regions (code, name) VALUES
    ('tashkent', 'Toshkent'),
    ('samarkand', 'Samarqand'),
    ('bukhara', 'Buxoro'),
    ('andijan', 'Andijon'),
    ('fergana', 'Farg''ona'),
    ('namangan', 'Namangan'),
    ('kashkadarya', 'Qashqadaryo'),
    ('surkhandarya', 'Surxondaryo'),
    ('navoiy', 'Navoiy'),
    ('khorezm', 'Xorazm'),
    ('jizzakh', 'Jizzax'),
    ('syrdarya', 'Sirdaryo'),
    ('karakalpakstan', 'Qoraqalpog''iston')
ON CONFLICT (code) DO NOTHING;

-- 10 launch subjects. Stable codes are permanent IDs; uz-Latn names below.
INSERT INTO subjects (code, sort_order) VALUES
    ('matematika', 1), ('geometriya', 2), ('fizika', 3), ('kimyo', 4),
    ('biologiya', 5), ('geografiya', 6), ('ona_tili', 7), ('jahon_tarixi', 8),
    ('ozbekiston_tarixi', 9), ('huquq', 10)
ON CONFLICT (code) DO NOTHING;

INSERT INTO subject_translations (subject_id, lang, name)
SELECT s.id, 'uz-Latn', v.name
FROM (VALUES
    ('geografiya', 'Geografiya'),
    ('jahon_tarixi', 'Jahon tarixi'),
    ('ozbekiston_tarixi', 'O''zbekiston tarixi'),
    ('matematika', 'Matematika'),
    ('geometriya', 'Geometriya'),
    ('fizika', 'Fizika'),
    ('kimyo', 'Kimyo'),
    ('ona_tili', 'Ona tili'),
    ('biologiya', 'Biologiya'),
    ('huquq', 'Huquq')
) AS v(code, name)
JOIN subjects s ON s.code = v.code
ON CONFLICT (subject_id, lang) DO NOTHING;

-- Temporary guest user (practice submissions before auth is built).
INSERT INTO users (id, role, display_name, locale)
VALUES ('00000000-0000-0000-0000-000000000001', 'student', 'Mehmon', 'uz-Latn')
ON CONFLICT (id) DO NOTHING;
