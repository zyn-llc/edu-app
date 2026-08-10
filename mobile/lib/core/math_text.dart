///
///
/// o'ylaydi.
///
///
/// qoladi — ular kamchilikni tashkil etadi va `\` belgisi ularni ajratib
///
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
  r'\Psi': 'Ψ', r'\Omega': 'Ω', r'\Upsilon': 'Υ',
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

  r'\displaystyle': '', r'\textstyle': '', r'\scriptstyle': '',
  r'\scriptscriptstyle': '', r'\limits': '', r'\nolimits': '',
};

/// Funksiya nomlari. LaTeX'da ular `\log`, `\sin` deb yoziladi.
///
/// pastdagi `_functionSpacing()` ga qarang.
///
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
    if (mapped == null) return '';
    buf.write(mapped);
  }
  return buf.toString();
}

///
/// `\frac{1}{5}` -> `\uE000 1 \uE001 5 \uE002`
///
/// qo'yadi, `MathText` vidjeti esa uni topib, ustma-ust chizadi.
///
/// (`km/soat`, `2017/2018`) tegilmaydi — aks holda "km/soat" ham kasr
const fracOpen = '\uE000';
const fracMid = '\uE001';
const fracClose = '\uE002';

String _fractions(String s) {
  final re = RegExp(r'\\[dt]?frac\s*\{([^{}]*)\}\s*\{([^{}]*)\}');
  var out = s;
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

String renderMathText(String? input) {
  if (input == null || input.isEmpty) return '';
  var s = input;

  if (!s.contains(r'\') && !s.contains(r'$') && !s.contains('^') &&
      !s.contains('_{')) {
    return s;
  }

  try {
    s = s.replaceFirst(RegExp(r'^\s*\(\s*\d{1,4}\s*-\s*\d{1,2}\s*-\s*\d{1,3}\s*\)\s*'), '');

    // 1) Muhitlar: \begin{cases}...\end{cases}, \begin{aligned}, \begin{array}{cc}
    //    satrga chiqaramiz. `{cc}` kabi ustun ta'rifi ham tashlanadi.
    s = s.replaceAllMapped(
        RegExp(r'\\begin\s*\{\w+\*?\}(\s*\{[^{}]*\})?'), (_) => '\n');
    s = s.replaceAll(RegExp(r'\\end\s*\{\w+\*?\}'), '');

    s = s.replaceAll(r'\\', '\n');

    // Massiv/aligned ichidagi tekislash belgisi.
    s = s.replaceAll('&', ' ');

    s = s.replaceAll(r'$$', r'$');
    s = s.replaceAll(r'\(', '').replaceAll(r'\)', '');
    s = s.replaceAll(r'\[', '').replaceAll(r'\]', '');
    s = s.replaceAll(r'$', '');

    s = _fractions(s);

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

    //    belgi (U+0305) shriftlarda ishonchsiz. Mazmuni saqlanadi: "AB".
    s = s.replaceAllMapped(
        RegExp(r'\\(?:text|mathrm|mathbf|mathit|mathsf|mathbb|mathcal'
               r'|operatorname|overline|underline|overbrace|underbrace)'
               r'\s*\{([^{}]*)\}'),
        (m) => m.group(1)!);

    s = _functionSpacing(s);

    final keys = _symbols.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final k in keys) {
      s = s.replaceAll(k, _symbols[k]!);
    }

    //
    // `\mathbb`, `\underbrace` ham bor. Bittasini nomma-nom tuzatish
    //
    //
    //
    //
    s = s.replaceAllMapped(RegExp(r'\\([a-zA-Z]{1,2})(?![a-zA-Z])'),
        (m) => m.group(1)!);
    s = s.replaceAll(RegExp(r'\\[a-zA-Z]+'), '');

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
    s = s.replaceAll('{', '').replaceAll('}', '');
    s = s.replaceAll(RegExp(r'[ \t]{2,}'), ' ');
    s = s.replaceAll(RegExp(r'[ \t]*\n[ \t]*'), '\n');
    s = s.replaceAll(RegExp(r'\n{2,}'), '\n');
    s = s.trim();

    return s;
  } catch (_) {
    return input;
  }
}
