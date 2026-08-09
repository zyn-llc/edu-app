/// LaTeX ko'rinishidagi matematik yozuvni o'qiladigan Unicode matnga o'giradi.
///
/// ## Nega to'liq LaTeX renderi emas
///
/// Savol banki manbadan `$\frac{4\pi}{3}$ radian necha gradusga teng?`
/// ko'rinishida keladi. Foydalanuvchi buni xom holida ko'rsa, savol buzuq deb
/// o'ylaydi.
///
/// `flutter_math_fork` kabi paket haqiqiy LaTeX chizadi, lekin: yangi
/// bog'liqlik, matnni segmentlarga bo'lish, web'da shrift yuklash va
/// `RichText` bilan ishlash kerak. Deadline oldidan bu katta xavf.
///
/// Amaldagi savollarning aksariyati oddiy: kasr, daraja, ildiz, yunon
/// harflari. Ular Unicode bilan to'liq ifodalanadi va hech qanday paket
/// talab qilmaydi. Murakkab formulalar (matritsa, integral) o'girilmay
/// qoladi — ular kamchilikni tashkil etadi va `\` belgisi ularni ajratib
/// turadi, ya'ni keyin SQL bilan topib, ko'rib chiqsa bo'ladi.
///
/// Bu KO'RSATISH qatlami: bazadagi matn o'zgarmaydi, qayta yuklash shart emas.
library;

const _superscript = {
  '0': '⁰', '1': '¹', '2': '²', '3': '³', '4': '⁴',
  '5': '⁵', '6': '⁶', '7': '⁷', '8': '⁸', '9': '⁹',
  '+': '⁺', '-': '⁻', '(': '⁽', ')': '⁾',
  'n': 'ⁿ', 'i': 'ⁱ', 'x': 'ˣ', 'a': 'ᵃ', 'b': 'ᵇ', 'k': 'ᵏ', 'm': 'ᵐ',
};

const _subscript = {
  '0': '₀', '1': '₁', '2': '₂', '3': '₃', '4': '₄',
  '5': '₅', '6': '₆', '7': '₇', '8': '₈', '9': '₉',
  '+': '₊', '-': '₋', '(': '₍', ')': '₎',
  'n': 'ₙ', 'i': 'ᵢ', 'a': 'ₐ', 'k': 'ₖ', 'm': 'ₘ', 'x': 'ₓ',
};

/// Uzunroq nom oldin kelishi SHART: `\theta` dan oldin `\th` almashtirilsa
/// natija buziladi. Shuning uchun ro'yxat uzunlik bo'yicha tartiblangan.
const _symbols = <String, String>{
  r'\alpha': 'α', r'\beta': 'β', r'\gamma': 'γ', r'\delta': 'δ',
  r'\epsilon': 'ε', r'\varepsilon': 'ε', r'\zeta': 'ζ', r'\eta': 'η',
  r'\theta': 'θ', r'\vartheta': 'ϑ', r'\iota': 'ι', r'\kappa': 'κ',
  r'\lambda': 'λ', r'\mu': 'μ', r'\nu': 'ν', r'\xi': 'ξ',
  r'\pi': 'π', r'\rho': 'ρ', r'\sigma': 'σ', r'\tau': 'τ',
  r'\upsilon': 'υ', r'\phi': 'φ', r'\varphi': 'φ', r'\chi': 'χ',
  r'\psi': 'ψ', r'\omega': 'ω',
  r'\Gamma': 'Γ', r'\Delta': 'Δ', r'\Theta': 'Θ', r'\Lambda': 'Λ',
  r'\Xi': 'Ξ', r'\Pi': 'Π', r'\Sigma': 'Σ', r'\Phi': 'Φ',
  r'\Psi': 'Ψ', r'\Omega': 'Ω',
  r'\infty': '∞', r'\partial': '∂', r'\nabla': '∇',
  r'\times': '×', r'\cdot': '·', r'\div': '÷', r'\pm': '±', r'\mp': '∓',
  r'\leq': '≤', r'\le': '≤', r'\geq': '≥', r'\ge': '≥',
  r'\neq': '≠', r'\ne': '≠', r'\approx': '≈', r'\equiv': '≡',
  r'\ll': '≪', r'\gg': '≫',
  r'\rightarrow': '→', r'\leftarrow': '←', r'\Rightarrow': '⇒',
  r'\Leftarrow': '⇐', r'\leftrightarrow': '↔', r'\to': '→',
  r'\in': '∈', r'\notin': '∉', r'\subset': '⊂', r'\subseteq': '⊆',
  r'\cup': '∪', r'\cap': '∩', r'\emptyset': '∅', r'\varnothing': '∅',
  r'\forall': '∀', r'\exists': '∃',
  r'\sum': '∑', r'\prod': '∏', r'\int': '∫',
  r'\angle': '∠', r'\perp': '⊥', r'\parallel': '∥',
  r'\degree': '°', r'\circ': '°',
  r'\ldots': '…', r'\dots': '…', r'\cdots': '⋯',
  r'\%': '%', r'\$': r'$', r'\&': '&', r'\_': '_',
  r'\,': ' ', r'\;': ' ', r'\!': '', r'\quad': '  ', r'\qquad': '    ',
  r'\left': '', r'\right': '',
};

/// Funksiya nomlari. LaTeX'da ular `\log`, `\sin` deb yoziladi.
///
/// ALOHIDA MAP, `_symbols` ICHIDA EMAS. Sabab — 2026-08-07 da sinovda
/// ko'rilgan: manba matnda `\sin` va `\cos` orasida ko'pincha bo'shliq
/// yo'q (`6\sin^2x+\sin x\cos x-\cos^2x=2`). Haqiqiy LaTeX'da bu muammo
/// emas — TeX buyruq nomidan keyin avtomatik ingichka bo'shliq qo'yadi.
/// Bizning oddiy satr almashtirish esa buni bilmaydi: `\cos` ni "cos" ga
/// almashtirsa, oldingi "x" bilan "cos" YOPISHIB QOLADI ("xcos" — bitta
/// so'zday o'qiladi). Shu sababli funksiya nomlari alohida, KONTEKSTni
/// (oldingi/keyingi harf-raqam) ko'radigan bosqichda almashtiriladi —
/// pastdagi `_functionSpacing()` ga qarang.
///
/// Uzunroq nom oldin turishi shart (`arcsin` `sin` dan oldin), aks holda
/// `arcsin` ning boshi oddiy `sin` sifatida yeyilib qoladi.
const _functionNames = <String, String>{
  r'\arcsin': 'arcsin', r'\arccos': 'arccos', r'\arctan': 'arctan',
  r'\sinh': 'sinh', r'\cosh': 'cosh', r'\tanh': 'tanh',
  r'\sin': 'sin', r'\cos': 'cos', r'\tan': 'tan', r'\cot': 'ctg',
  r'\sec': 'sec', r'\csc': 'csc',
  r'\log': 'log', r'\ln': 'ln', r'\lg': 'lg', r'\exp': 'exp',
  r'\lim': 'lim', r'\max': 'max', r'\min': 'min', r'\det': 'det',
  r'\gcd': 'EKUB', r'\deg': 'deg', r'\bmod': 'mod', r'\mod': 'mod',
};

final RegExp _functionRe = RegExp(
  r'([\w)\]])?\\(' +
      (_functionNames.keys.map((k) => RegExp.escape(k.substring(1))).toList()
            ..sort((a, b) => b.length.compareTo(a.length)))
          .join('|') +
      r')(\w)?',
);

/// `x\cos x` -> `x cos x`, lekin `\sin(x)` -> `sin(x)` (qavsdan oldin
/// bo'shliq QO'YILMAYDI — bu standart matematik yozuv). `\cos^2x` ->
/// `cos^2x` ham o'zgarmaydi (`^` harf-raqam emas), keyingi bosqich uni
/// `cos²x` ga aylantiradi — daraja funksiyaga tegishli, orasiga bo'shliq
/// kerak emas.
String _functionSpacing(String s) => s.replaceAllMapped(_functionRe, (m) {
      final before = m.group(1);
      final name = _functionNames[r'\' + m.group(2)!]!;
      final after = m.group(3);
      return '${before != null ? '$before ' : ''}$name'
          '${after != null ? ' $after' : ''}';
    });

String _toScript(String body, Map<String, String> table) {
  final buf = StringBuffer();
  for (final ch in body.split('')) {
    final mapped = table[ch];
    // Bitta belgi ham o'girilmasa — butun ifodani asl holida qoldiramiz,
    // aks holda "x^(2n+1)" ning yarmi yuqoriga chiqib, o'qib bo'lmay qoladi.
    if (mapped == null) return '';
    buf.write(mapped);
  }
  return buf.toString();
}

/// Kasr belgilari (Private Use Area — haqiqiy kontentda hech qachon
/// uchramaydi, ya'ni matn bilan aralashib ketmaydi).
///
/// `\frac{1}{5}` -> `\uE000 1 \uE001 5 \uE002`
///
/// NEGA SENTINEL, NEGA TO'G'RIDAN-TO'G'RI "1/5" EMAS.
/// O'girish `quiz_data.dart` da, ya'ni MODEL qatlamida bo'ladi va natija
/// oddiy `String`. Vertikal kasrni chizish uchun esa vidjet kerak. Sentinel
/// — shu ikki qatlamni bog'lovchi yagona yo'l: model matnni belgilab
/// qo'yadi, `MathText` vidjeti esa uni topib, ustma-ust chizadi.
///
/// MUHIM: sentinel FAQAT `\frac` dan chiqadi. Matndagi oddiy `/`
/// (`km/soat`, `2017/2018`) tegilmaydi — aks holda "km/soat" ham kasr
/// bo'lib chizilardi.
const fracOpen = '\uE000';
const fracMid = '\uE001';
const fracClose = '\uE002';

/// `\frac{a}{b}` -> sentinel bilan belgilangan kasr. Ichma-ich kasrlar
/// uchun tashqaridan ichkariga qavs qo'yiladi: `(a+1)/2`.
String _fractions(String s) {
  final re = RegExp(r'\\[dt]?frac\s*\{([^{}]*)\}\s*\{([^{}]*)\}');
  var out = s;
  // Ichma-ich holatlar uchun bir necha marta yuriladi, lekin cheksiz emas.
  for (var i = 0; i < 4; i++) {
    final next = out.replaceAllMapped(re, (m) {
      final num = m.group(1)!.trim();
      final den = m.group(2)!.trim();
      return '$fracOpen$num$fracMid$den$fracClose';
    });
    if (next == out) break;
    out = next;
  }
  return out;
}

/// Sentinel'larni oddiy `a/b` ga qaytaradi.
///
/// Kerak bo'ladigan joylar: vidjetsiz `Text()`, `SelectableText`,
/// ulashiladigan matn, `semanticsLabel`. Sentinel u yerlarga tushsa
/// foydalanuvchi bo'sh kvadratchalarni ko'radi.
String flattenFractions(String s) {
  if (!s.contains(fracOpen)) return s;
  return s.replaceAllMapped(
    RegExp('$fracOpen([^$fracMid$fracClose]*)$fracMid'
        '([^$fracMid$fracClose]*)$fracClose'),
    (m) {
      final n = m.group(1)!;
      final d = m.group(2)!;
      final ns = n.length > 1 && !RegExp(r'^\w+$').hasMatch(n) ? '($n)' : n;
      final ds = d.length > 1 && !RegExp(r'^\w+$').hasMatch(d) ? '($d)' : d;
      return '$ns/$ds';
    },
  ).replaceAll(fracOpen, '').replaceAll(fracMid, '/').replaceAll(fracClose, '');
}

/// LaTeX -> o'qiladigan matn. Xato bo'lsa asl matn qaytadi (savol hech
/// qachon yo'qolmasligi kerak).
String renderMathText(String? input) {
  if (input == null || input.isEmpty) return '';
  var s = input;

  // Tez yo'l: LaTeX belgisi umuman bo'lmasa hech narsa qilmaymiz.
  if (!s.contains(r'\') && !s.contains(r'$') && !s.contains('^') &&
      !s.contains('_{')) {
    return s;
  }

  try {
    // 0) Manba iqtibosi: "(97-12-30) Tenglamani yeching..." — bu to'plam
    //    raqami, o'quvchiga hech narsa demaydi va savolni chalg'itadi.
    s = s.replaceFirst(RegExp(r'^\s*\(\s*\d{1,4}\s*-\s*\d{1,2}\s*-\s*\d{1,3}\s*\)\s*'), '');

    // 1) Muhitlar: \begin{cases}...\end{cases}, \begin{aligned}, \begin{array}{cc}
    //    Tenglamalar sistemasi bir necha qatordan iborat — har birini yangi
    //    satrga chiqaramiz. `{cc}` kabi ustun ta'rifi ham tashlanadi.
    s = s.replaceAllMapped(
        RegExp(r'\\begin\s*\{\w+\*?\}(\s*\{[^{}]*\})?'), (_) => '\n');
    s = s.replaceAll(RegExp(r'\\end\s*\{\w+\*?\}'), '');

    // 2) Satr ajratkichi. BU YERDA, `\(` dan OLDIN bo'lishi SHART:
    //    aks holda `\\(x-2)` dagi `\\` ning ikkinchi belgisi keyingi qavs
    //    bilan qo'shilib `\(` bo'lib o'qiladi va QAVS yo'qoladi
    //    ("6\x-2)²" — aynan shu xato ko'rilgan).
    s = s.replaceAll(r'\\', '\n');

    // Massiv/aligned ichidagi tekislash belgisi.
    s = s.replaceAll('&', ' ');

    // 3) Matematik rejim ajratkichlari. Matn ichida qoladi, faqat belgilar
    //    olib tashlanadi: "$x$ ni toping" -> "x ni toping".
    s = s.replaceAll(r'$$', r'$');
    s = s.replaceAll(r'\(', '').replaceAll(r'\)', '');
    s = s.replaceAll(r'\[', '').replaceAll(r'\]', '');
    s = s.replaceAll(r'$', '');

    // 2) Kasrlar (belgilardan OLDIN: ichida \pi bo'lishi mumkin).
    s = _fractions(s);

    // 3) Ildiz. Darajali ildiz `\sqrt[4]{1296}` ALOHIDA — u avval kelishi
    //    shart, aks holda `\sqrt` qismi oddiy ildiz sifatida yeyiladi va
    //    `[4]` matnda osilib qoladi ("\sqrt[4]1296" xatosi shundan edi).
    s = s.replaceAllMapped(RegExp(r'\\sqrt\s*\[([^\]]*)\]\s*\{([^{}]*)\}'), (m) {
      final idx = _toScript(m.group(1)!.trim(), _superscript);
      final body = m.group(2)!.trim();
      return '${idx.isEmpty ? '' : idx}√($body)';
    });
    s = s.replaceAllMapped(RegExp(r'\\sqrt\s*\[([^\]]*)\]\s*(\w+)'), (m) {
      final idx = _toScript(m.group(1)!.trim(), _superscript);
      return '${idx.isEmpty ? '' : idx}√${m.group(2)}';
    });
    s = s.replaceAllMapped(
        RegExp(r'\\sqrt\s*\{([^{}]*)\}'), (m) => '√(${m.group(1)!.trim()})');
    s = s.replaceAllMapped(
        RegExp(r'\\sqrt\s*(\w)'), (m) => '√${m.group(1)}');

    // 4) Matn bloklari: \text{...} -> ...
    s = s.replaceAllMapped(
        RegExp(r'\\(?:text|mathrm|mathbf|operatorname)\s*\{([^{}]*)\}'),
        (m) => m.group(1)!);

    // 4.5) Funksiya nomlari — kontekstga qarab bo'shliq bilan.
    s = _functionSpacing(s);

    // 5) Belgilar. Uzun nomlar oldin — `\le` `\leq` ni buzmasin.
    final keys = _symbols.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final k in keys) {
      s = s.replaceAll(k, _symbols[k]!);
    }

    // 6) Daraja va indeks.
    s = s.replaceAllMapped(RegExp(r'\^\s*\{([^{}]*)\}'), (m) {
      final sup = _toScript(m.group(1)!.trim(), _superscript);
      return sup.isEmpty ? '^(${m.group(1)!.trim()})' : sup;
    });
    s = s.replaceAllMapped(RegExp(r'\^\s*(\w)'), (m) {
      final sup = _toScript(m.group(1)!, _superscript);
      return sup.isEmpty ? '^${m.group(1)}' : sup;
    });
    s = s.replaceAllMapped(RegExp(r'_\s*\{([^{}]*)\}'), (m) {
      final sub = _toScript(m.group(1)!.trim(), _subscript);
      return sub.isEmpty ? '_(${m.group(1)!.trim()})' : sub;
    });
    s = s.replaceAllMapped(RegExp(r'_\s*(\w)'), (m) {
      final sub = _toScript(m.group(1)!, _subscript);
      return sub.isEmpty ? '_${m.group(1)}' : sub;
    });

    // 7) Qolgan jingalak qavslar va ortiqcha bo'shliqlar.
    //    DIQQAT: `[ \t]` ishlatilgan, `\s` EMAS — aks holda sistema
    //    qatorlarini ajratib turgan `\n` ham yo'qolardi.
    s = s.replaceAll('{', '').replaceAll('}', '');
    s = s.replaceAll(RegExp(r'[ \t]{2,}'), ' ');
    s = s.replaceAll(RegExp(r'[ \t]*\n[ \t]*'), '\n');
    s = s.replaceAll(RegExp(r'\n{2,}'), '\n');
    s = s.trim();

    return s;
  } catch (_) {
    // O'girish hech qachon savolni yo'qotmasin.
    return input;
  }
}
