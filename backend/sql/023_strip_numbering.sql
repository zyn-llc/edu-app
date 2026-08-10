-- =========================================================================
-- =========================================================================
--
--
--  ichida qoldirgan:
--
--      variantlar:  "A)mavjudod, tajjub"  "B)muhofaza, loqayd"
--
--
--
--
--
--      "12. Tabiat komponentlari"   -> TEGILADI
--
--
--  (masalan "E) harfi") tasodifan kesilmaydi.
--
-- =========================================================================

BEGIN;

UPDATE question_translations
SET stem = regexp_replace(stem, '^\s*\d{1,4}\s*[.)]\s*', '')
WHERE stem ~ '^\s*\d{1,4}\s*[.)]\s*[[:alpha:]]';

-- --- 2. Variantlardagi "A)" / "a." prefiksi -------------------------------
UPDATE option_translations
SET text = regexp_replace(text, '^\s*[A-Da-d]\s*[.)]\s*', '')
WHERE text ~ '^\s*[A-Da-d]\s*[.)]\s*\S';

UPDATE question_translations SET stem = btrim(stem) WHERE stem <> btrim(stem);
UPDATE option_translations   SET text = btrim(text) WHERE text <> btrim(text);

UPDATE questions q
SET status = 'draft'
WHERE q.status = 'active'
  AND EXISTS (
    SELECT 1 FROM question_translations t
    WHERE t.question_id = q.id AND btrim(t.stem) = ''
  );

COMMIT;

--   SELECT count(*) FROM question_translations
--   SELECT count(*) FROM option_translations
