-- =============================================================================
--  quality_audit.sql — sifatsiz kontentni topish.
--
--    Get-Content sql/quality_audit.sql | docker compose exec -T db psql -U edu -d edu
--
--  Bu fayl HECH NARSANI O'ZGARTIRMAYDI — faqat SELECT. Ro'yxatni ko'rasan,
--  keyin oxiridagi shablon bilan o'zing chiqarib tashlaysan.
--
--  MUHIM: savolni DELETE qilma, `status='draft'` qil. Uch sabab:
--    1. `submissions` unga FK bilan bog'langan — o'chirsang tarix buziladi.
--    2. `run_subject.py` `source_ref` bo'yicha skip qiladi; o'chirilgan savol
--       keyingi yuklamada QAYTA kirib keladi.
--    3. `draft` qaytarib olinadi, DELETE qaytarilmaydi.
--  `content.py` faqat `status='active'` ni tarqatadi, ya'ni draft = ko'rinmaydi.
-- =============================================================================

\echo '===== 1. BO`SH VA KAM MAVZULAR ====='
-- Katalogda ko'rinadi-yu, ochsang savol yo'q yoki 3-4 ta. O'quvchi uchun
-- eng yomon tajriba: mavzuni tanlaydi, quiz boshlanmaydi.
SELECT s.code AS fan, t.code AS mavzu, tt.title AS sarlavha,
       count(q.id) FILTER (WHERE q.status = 'active') AS aktiv,
       count(q.id) FILTER (WHERE q.status = 'draft')  AS draft
FROM topics t
JOIN subjects s ON s.id = t.subject_id
LEFT JOIN topic_translations tt ON tt.topic_id = t.id AND tt.lang = 'uz-Latn'
LEFT JOIN questions q ON q.topic_id = t.id
GROUP BY s.code, t.code, tt.title
HAVING count(q.id) FILTER (WHERE q.status = 'active') < 5
ORDER BY 4, 1, 2;

\echo ''
\echo '===== 2. VARIANTI KAM YOKI BO`SH SAVOLLAR ====='
-- 2 tadan kam variant, yoki matni bo'sh variant. Bular javob berib
-- bo'lmaydigan savollar.
SELECT q.id, q.source_ref, s.code AS fan, q.grade,
       count(o.id) AS variant,
       count(*) FILTER (WHERE coalesce(ot.text,'') = '') AS bosh_variant
FROM questions q
JOIN subjects s ON s.id = q.subject_id
LEFT JOIN options o ON o.question_id = q.id
LEFT JOIN option_translations ot ON ot.option_id = o.id AND ot.lang = 'uz-Latn'
WHERE q.status = 'active'
GROUP BY q.id, q.source_ref, s.code, q.grade
HAVING count(o.id) < 2 OR count(*) FILTER (WHERE coalesce(ot.text,'') = '') > 0
ORDER BY s.code, q.source_ref;

\echo ''
\echo '===== 3. JUDA QISQA YOKI KESILGAN SAVOL MATNI ====='
-- 20 belgidan qisqa savol odatda OCR chala o'qigan qator. Oxiri "..." yoki
-- "___" bilan tugagani ham shunday.
SELECT q.id, q.source_ref, s.code AS fan, q.grade,
       length(qt.stem) AS uzunlik, left(qt.stem, 70) AS matn
FROM questions q
JOIN subjects s ON s.id = q.subject_id
JOIN question_translations qt ON qt.question_id = q.id AND qt.lang = 'uz-Latn'
WHERE q.status = 'active'
  AND (length(qt.stem) < 20 OR qt.stem ~ '(\.\.\.|_{3,})\s*$')
ORDER BY length(qt.stem), s.code;

\echo ''
\echo '===== 4. TAKRORLANGAN SAVOLLAR ====='
-- Bir xil matn bir necha marta. Birinchisini qoldirib qolganini draft qilasan.
SELECT s.code AS fan, count(*) AS nusxa,
       string_agg(q.source_ref, ', ' ORDER BY q.source_ref) AS source_reflar,
       left(qt.stem, 60) AS matn
FROM questions q
JOIN subjects s ON s.id = q.subject_id
JOIN question_translations qt ON qt.question_id = q.id AND qt.lang = 'uz-Latn'
WHERE q.status = 'active'
GROUP BY s.code, qt.stem
HAVING count(*) > 1
ORDER BY count(*) DESC, s.code
LIMIT 100;

\echo ''
\echo '===== 5. BIR XIL VARIANTLI SAVOLLAR ====='
-- Ikki variant matni aynan bir xil bo'lsa, savolning javobi noaniq bo'lib
-- qoladi — o'quvchi to'g'ri tanlab ham xato oladi.
SELECT q.id, q.source_ref, s.code AS fan, ot.text AS takror_variant
FROM questions q
JOIN subjects s ON s.id = q.subject_id
JOIN options o ON o.question_id = q.id
JOIN option_translations ot ON ot.option_id = o.id AND ot.lang = 'uz-Latn'
WHERE q.status = 'active'
GROUP BY q.id, q.source_ref, s.code, ot.text
HAVING count(*) > 1
ORDER BY s.code, q.source_ref
LIMIT 100;

\echo ''
\echo '===== 6. JAVOB KALITI QIYSHAYGAN MAVZULAR ====='
-- Bitta mavzuda javoblarning 70%+ bir harfda bo'lsa, bu qiyin mavzu emas —
-- odatda javob kaliti noto'g'ri o'qilgan.
WITH k AS (
  SELECT q.topic_id, q.grading_spec->'correct_option_ids'->>0 AS kalit
  FROM questions q WHERE q.status = 'active' AND q.topic_id IS NOT NULL
), agg AS (
  SELECT topic_id, kalit, count(*) AS soni,
         sum(count(*)) OVER (PARTITION BY topic_id) AS jami
  FROM k GROUP BY topic_id, kalit
)
SELECT s.code AS fan, tt.title AS mavzu, a.kalit, a.soni, a.jami,
       round(100.0 * a.soni / a.jami, 1) AS foiz
FROM agg a
JOIN topics t ON t.id = a.topic_id
JOIN subjects s ON s.id = t.subject_id
LEFT JOIN topic_translations tt ON tt.topic_id = t.id AND tt.lang = 'uz-Latn'
WHERE a.jami >= 10 AND 100.0 * a.soni / a.jami > 70
ORDER BY 6 DESC;

\echo ''
\echo '===== 7. RASMSIZ RASMLI SAVOLLAR (aktiv qolganlari) ====='
SELECT count(*) AS aktiv_rasmli
FROM questions WHERE media IS NOT NULL AND status = 'active';

\echo ''
\echo '===== 8. UMUMIY HISOBOT ====='
SELECT s.code AS fan, q.grade,
       count(*) FILTER (WHERE q.status = 'active') AS aktiv,
       count(*) FILTER (WHERE q.status = 'draft')  AS draft
FROM questions q JOIN subjects s ON s.id = q.subject_id
GROUP BY s.code, q.grade ORDER BY s.code, q.grade;


-- =============================================================================
--  CHIQARIB TASHLASH — yuqoridagi ro'yxatdan id yoki source_ref olib ishlat.
--  Izohni ochib, o'z ro'yxatingni qo'y.
-- =============================================================================

-- -- Bittalab, id bo'yicha:
-- UPDATE questions SET status = 'draft', updated_at = now()
-- WHERE id IN ('...uuid...', '...uuid...');

-- -- source_ref bo'yicha (o'qish osonroq):
-- UPDATE questions SET status = 'draft', updated_at = now()
-- WHERE source_ref IN ('bio_g7_q0043', 'geo_g8_q0112');

-- -- Butun mavzuni yopish (masalan savoli 3 ta bo'lgan mavzu):
-- UPDATE questions SET status = 'draft', updated_at = now()
-- WHERE topic_id = (SELECT t.id FROM topics t JOIN subjects s ON s.id=t.subject_id
--                   WHERE s.code='huquq' AND t.code='law_dtm_practice');

-- -- Qaytarib olish:
-- UPDATE questions SET status = 'active', updated_at = now()
-- WHERE source_ref IN ('...');

-- -- Savol matnini tuzatish (o'chirishdan ko'ra yaxshiroq):
-- UPDATE question_translations SET stem = 'To''g''ri matn'
-- WHERE question_id = '...uuid...' AND lang = 'uz-Latn';

-- -- Javob kalitini tuzatish (variant harfi bilan, masalan 'c'):
-- UPDATE questions SET grading_spec = '{"correct_option_ids":["c"]}'::jsonb,
--        updated_at = now()
-- WHERE source_ref = 'bio_g7_q0043';
-- -- Keyin MAJBURIY: python -m app.ingest.audit_grading  -> 0 muammo bo'lsin.
