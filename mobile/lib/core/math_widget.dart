/// Kasrlarni ustma-ust (vertikal) chizadigan matn vidjeti.
///
/// ## Nega kerak
///
/// `math_text.dart` LaTeX'ni Unicode'ga o'giradi va kasrni `1/5` shaklida
/// beradi. Sinovda aniqlangan muammo: o'quvchi darslikda kasrni HAR DOIM
/// ustma-ust ko'radi, ilovada esa `1/5` — bu bir qarashda "bir bo'lingan
/// besh" emas, "bir slash besh" bo'lib o'qiladi. Uzun ifodalarda esa
/// (`(2x+1)/(x-3)`) qavslar tufayli o'qish butunlay qiyinlashadi.
///
/// ## Nega to'liq LaTeX renderi emas
///
/// `flutter_math_fork` haqiqiy LaTeX chizadi, lekin: yangi bog'liqlik,
/// web'da qo'shimcha shrift yuklash, matn bilan aralash oqim muammosi.
/// Deadline oldidan bu katta xavf. Bankdagi ifodalarning aksariyati oddiy
/// kasr — ular `Column` + chiziq bilan to'liq chiziladi.
///
/// ## Qanday ishlaydi
///
/// `renderMathText()` kasrni Private Use Area belgilari bilan o'raydi
/// (`fracOpen` + son + `fracMid` + maxraj + `fracClose`). Bu vidjet matnni
/// bo'yicha bo'laklarga ajratadi va kasr bo'lagini `WidgetSpan` sifatida
/// chizadi. Sentinel `\frac` dan boshqa joydan CHIQMAYDI, ya'ni matndagi
/// oddiy `/` (`km/soat`, `2017/2018`) tegilmaydi.
///
/// Sentinel topilmasa vidjet oddiy `Text` ga aylanadi — ya'ni matematikasiz
/// savollar uchun hech qanday qo'shimcha xarajat yo'q.
library;

import 'package:flutter/material.dart';

import 'math_text.dart';

class MathText extends StatelessWidget {
  const MathText(
    this.data, {
    super.key,
    this.style,
    this.textAlign,
    this.maxLines,
    this.overflow,
  });

  final String data;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;

  @override
  Widget build(BuildContext context) {
    final base = style ?? DefaultTextStyle.of(context).style;

    // Tez yo'l: kasr yo'q bo'lsa oddiy matn.
    if (!data.contains(fracOpen)) {
      return Text(data,
          style: style,
          textAlign: textAlign,
          maxLines: maxLines,
          overflow: overflow);
    }

    return Text.rich(
      TextSpan(children: _spans(base)),
      style: style,
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: overflow,
      // Ekran o'quvchisi uchun tekis shakl: "1/5" deb o'qiladi, aks holda
      // PUA belgilari o'qilmaydi va kasr umuman yo'qoladi.
      semanticsLabel: flattenFractions(data),
    );
  }

  List<InlineSpan> _spans(TextStyle base) {
    final out = <InlineSpan>[];
    var i = 0;
    while (i < data.length) {
      final open = data.indexOf(fracOpen, i);
      if (open < 0) {
        out.add(TextSpan(text: data.substring(i)));
        break;
      }
      if (open > i) out.add(TextSpan(text: data.substring(i, open)));

      final mid = data.indexOf(fracMid, open + 1);
      final close = data.indexOf(fracClose, mid + 1);
      // Buzuq sentinel (bo'lishi mumkin emas, lekin matn hech qachon
      // yo'qolmasligi kerak) — qolganini xom holda chiqaramiz.
      if (mid < 0 || close < 0) {
        out.add(TextSpan(text: flattenFractions(data.substring(open))));
        break;
      }

      out.add(WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: _Fraction(
          numerator: data.substring(open + 1, mid),
          denominator: data.substring(mid + 1, close),
          style: base,
        ),
      ));
      i = close + 1;
    }
    return out;
  }
}

class _Fraction extends StatelessWidget {
  const _Fraction({
    required this.numerator,
    required this.denominator,
    required this.style,
  });

  final String numerator;
  final String denominator;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    // Kasr ichidagi matn biroz kichik: aks holda kasr qatorni ikki barobar
    // balandlashtirib, atrofdagi matn qatorlari orasini yirtib yuboradi.
    final inner = style.copyWith(
      fontSize: (style.fontSize ?? 16) * 0.82,
      height: 1.05,
    );
    final line = style.color ?? DefaultTextStyle.of(context).style.color;

    return Padding(
      // Yon tomonlarda kichik nafas: "x = 1/5 ni toping" da kasr qo'shni
      // belgilarga yopishib qolmasin.
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(numerator, style: inner, textAlign: TextAlign.center),
          Container(
            // Chiziq eng uzun qatordan bir oz uzunroq bo'lishi uchun
            // `Column` kengligiga tayanamiz va vertikal joy beramiz.
            margin: const EdgeInsets.symmetric(vertical: 1.5),
            height: 1.2,
            constraints: const BoxConstraints(minWidth: 10),
            color: line,
          ),
          Text(denominator, style: inner, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
