-- =============================================================================
--  018_backfill_grades.sql — `grade = NULL` bo'lib qolgan savollarga sinfni
--  qaytaradi.
--
--  SABAB: `app/ingest/run_subject.py` da
--      grade=c.get("grade", bank_grade)
--  yozilgan edi. Manba JSON'da `"grade": null` kaliti MAVJUD, shuning uchun
--  Python'ning `dict.get(key, default)` standart qiymatni EMAS, `None` ni
--  qaytaradi. Natija: butun banklar sinfsiz yuklandi va ilovada 10/11-sinf
--  bo'limlari bo'sh ko'rindi.
--
--  Kod tuzatildi, lekin allaqachon yuklangan qatorlarni ingest qayta
--  yozmaydi (u `source_ref` bo'yicha mavjudini o'tkazib yuboradi), shuning
--  uchun sinfni shu yerda tiklaymiz.
--
--  Manba: `source_ref` ning o'zi — `math_g10_q0001`, `geo_g7_q0042`.
--  `_g<raqam>_q` shabloniga tushmaydigan qatorlarga TEGILMAYDI.
-- =============================================================================

BEGIN;

-- Tekshiruv uchun: o'zgarishdan oldingi holat.
\echo '--- OLDIN: grade IS NULL ---'
SELECT count(*) AS sinfsiz FROM questions WHERE grade IS NULL;

UPDATE questions
   SET grade = (regexp_match(source_ref, '_g(\d+)_q'))[1]::smallint
 WHERE grade IS NULL
   AND source_ref ~ '_g\d+_q'
   -- Maktab sinflari oralig'idan chiqib ketmasin (masalan "g2024" kabi
   -- kutilmagan prefiks bo'lsa).
   AND ((regexp_match(source_ref, '_g(\d+)_q'))[1]::int BETWEEN 1 AND 11);

\echo '--- KEYIN: sinf bo''yicha taqsimot ---'
SELECT grade, count(*) AS soni
  FROM questions
 WHERE status = 'active'
 GROUP BY grade
 ORDER BY grade NULLS LAST;

COMMIT;
