///
///
/// `math_text.dart` LaTeX'ni Unicode'ga o'giradi va kasrni `1/5` shaklida
/// (`(2x+1)/(x-3)`) qavslar tufayli o'qish butunlay qiyinlashadi.
///
///
///
/// ## Qanday ishlaydi
///
/// oddiy `/` (`km/soat`, `2017/2018`) tegilmaydi.
///
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
