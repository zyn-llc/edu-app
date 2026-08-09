import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// Harakat tili — bitta joyda.
///
/// ## Nega konstanta
///
/// Ilgari har ekranda `Duration(milliseconds: 140)`, `200`, `300` aralash
/// yozilardi. Ko'z buni sezadi: bir karta tez, yonidagisi sekin ochiladi va
/// interfeys "yig'ma" bo'lib tuyuladi. Bitta shkala — bitta his.
///
/// ## Nega qisqa
///
/// Bu o'quv ilovasi, taqdimot emas. Foydalanuvchi kuniga o'nlab marta
/// dashboardni ochadi; 600 ms li kirish animatsiyasi uchinchi martadayoq
/// bezor qiladi. Shuning uchun eng uzun kirish — 320 ms, hover esa 160 ms.
///
/// ## Kirish animatsiyalari faqat BIR MARTA
///
/// `flutter_animate` vidjet qurilganda ishga tushadi. `IndexedStack` da tab
/// almashganda bolalar qayta qurilmaydi, ya'ni animatsiya takrorlanmaydi —
/// bu ataylab shunday. Lekin `ListView.builder` da element ekrandan chiqib
/// qaytsa qayta ishga tushadi, shuning uchun uzun ro'yxatlarda staggered
/// kirish faqat DASTLABKI ekranga sig'adigan qismga qo'yiladi.
abstract final class Motion {
  /// Hover, bosish, rang o'zgarishi — foydalanuvchi harakatiga javob.
  /// Insonning "darhol" deb his qiladigan chegarasi ~100–200 ms.
  static const fast = Duration(milliseconds: 160);

  /// Holat o'zgarishi: skeleton → kontent, ochilish/yopilish.
  static const normal = Duration(milliseconds: 240);

  /// Sahifaga kirish. Undan uzoq bo'lsa kutish sezila boshlaydi.
  static const slow = Duration(milliseconds: 320);

  /// Ro'yxatda elementlar orasidagi kechikish. 40 ms — ko'z "to'lqin" deb
  /// o'qiydigan eng kichik oraliq; 10 ta elementda umumiy kechikish 400 ms,
  /// ya'ni oxirgisi ham tez chiqadi.
  static const stagger = Duration(milliseconds: 40);

  /// Kirish uchun: tez boshlanadi, yumshoq to'xtaydi.
  static const enter = Curves.easeOutCubic;

  /// Interaktiv javob uchun: chiziqliroq, "elastik" emas.
  static const interactive = Curves.easeOut;

  /// Ochilib-yopiladigan panellar uchun.
  static const emphasized = Curves.easeInOutCubicEmphasized;
}

/// Standart kirish effekti: pastdan biroz suriladi va ochiladi.
///
/// 8 px — ataylab kichik. Kattaroq siljish sahifa "sakragandek" ko'rinadi va
/// scroll paytida kontent qayerda ekanini yo'qotadi.
extension MotionEffects on Widget {
  /// Bitta element uchun kirish.
  Widget enterFade({Duration? delay}) => animate(delay: delay)
      .fadeIn(duration: Motion.slow, curve: Motion.enter)
      .moveY(begin: 8, end: 0, duration: Motion.slow, curve: Motion.enter);

  /// Ro'yxatdagi `index`-element uchun kirish — kechikish o'zi hisoblanadi.
  ///
  /// `maxIndex` — kechikish shundan keyin o'smaydi. Uzun ro'yxatda 30-element
  /// 1.2 soniya kutmasligi kerak: u ekranda ko'rinmaydi ham.
  Widget enterStaggered(int index, {int maxIndex = 8}) => enterFade(
        delay: Motion.stagger * (index > maxIndex ? maxIndex : index),
      );
}
