import '../../l10n/app_localizations.dart';
import '../subjects/subjects.dart';

/// Tillarni FAN KARTASI sifatida ko'rsatish.
///
/// NEGA SHUNDAY. Ilgari til bo'limi bosh sahifada alohida karta edi va
/// ichida yana o'z tanlash qatori bor edi — natijada u ilovaning qolgan
/// qismiga umuman o'xshamasdi. O'quvchi uchun esa "Ingliz tili" ham
/// "Matematika" kabi o'quv predmeti; ular bir xil ko'rinishi va bir xil
/// joyda turishi kerak.
///
/// NEGA KLIENTDA YASALADI. Backend'da tillar `study_languages` jadvalida
/// va ular `subjects` EMAS: ularda savol banki, sinf va qiyinlik yo'q,
/// CEFR darajasi bor. Ularni `/v1/subjects` ga qo'shish ikki xil narsani
/// bitta jadvalga tiqish bo'lardi. Shuning uchun karta uchun kerakli
/// minimal ma'lumot shu yerda yig'iladi — ma'lumot qatlami o'zgarmaydi.
///
/// `id` sifatida `lang_xx` ishlatiladi va `SubjectPalette` da aynan shu
/// kalit bo'yicha rang va belgi turadi.

const _codes = ['en', 'ru', 'de'];

/// Fan to'riga qo'shiladigan uchta karta.
List<Subject> languageSubjects(L10n l) => [
      for (final c in _codes)
        Subject(
          id: 'lang_$c',
          code: 'lang_$c',
          name: switch (c) {
            'en' => l.langEnglish,
            'ru' => l.langRussian,
            _ => l.langGerman,
          },
          // `questionCount` 0 bo'lsa karta "tez orada" holatiga tushib,
          // o'chirilgan ko'rinadi. Tilda savol soni boshqa manbadan keladi,
          // shuning uchun bu yerda shunchaki musbat qiymat — kartani
          // faol holatda ushlab turish uchun.
          questionCount: 1,
        ),
    ];

/// Karta tilga tegishlimi — tegishli bo'lsa til kodi, aks holda `null`.
String? languageCodeOf(Subject s) =>
    s.code.startsWith('lang_') ? s.code.substring(5) : null;
