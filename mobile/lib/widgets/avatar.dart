import 'package:flutter/material.dart';

/// Foydalanuvchi avatari: ism bosh harfi + rang.
///
/// NEGA RASM EMAS. Fayl yuklash uchun obyekt saqlash (S3/MinIO), o'lcham
/// o'zgartirish, moderatsiya va CDN kerak — birortasi ham hozir yo'q, ilova
/// esa 8-avgustda topshiriladi. Bolalar ilovasida moderatsiyasiz rasm
/// yuklash alohida xavf: bitta nomaqbul avatar butun sinov dasturini
/// to'xtatishi mumkin. Bosh harf + rang esa foydalanuvchini reytingda va
/// ota-ona panelida ajratib turish uchun yetarli va xarajati bitta ustun
/// (`users.avatar_color`).
///
/// Rang tanlanmagan bo'lsa (`colorIndex == null`) — ism hash'idan barqaror
/// indeks olinadi: bir xil ism doim bir xil rangda ko'rinadi, ya'ni bo'sh
/// kulrang doiralar qatori chiqmaydi.
class AvatarPalette {
  const AvatarPalette._();

  /// 12 ta rang. Hammasi to'q — ustidagi oq matn ikkala temada ham
  /// o'qiladi (kontrast ≥ 4.5:1).
  static const colors = <Color>[
    Color(0xFF3B6FE0), // ko'k
    Color(0xFF2FA36B), // yashil
    Color(0xFFCF6A26), // to'q sariq
    Color(0xFF9B4DCA), // siyohrang
    Color(0xFFD64545), // qizil
    Color(0xFF0E8C8C), // firuza
    Color(0xFF7A5AF8), // binafsha
    Color(0xFFB8860B), // oltin
    Color(0xFF2E7D9A), // dengiz ko'ki
    Color(0xFFC2185B), // pushti
    Color(0xFF4E6A2F), // zaytun
    Color(0xFF5D4037), // jigarrang
  ];

  static int get length => colors.length;

  /// Ism uchun barqaror indeks. Tasodifiy emas — foydalanuvchi ilovani qayta
  /// ochganda rangi o'zgarib ketmasligi kerak.
  static int indexForName(String? name) {
    final s = (name ?? '').trim();
    if (s.isEmpty) return 0;
    var h = 0;
    for (final unit in s.codeUnits) {
      h = (h * 31 + unit) & 0x7FFFFFFF;
    }
    return h % colors.length;
  }

  static Color resolve(String? name, int? colorIndex) {
    final i = (colorIndex != null && colorIndex >= 0 && colorIndex < length)
        ? colorIndex
        : indexForName(name);
    return colors[i];
  }
}

/// Ismning ko'rsatiladigan bosh harflari: bir so'z bo'lsa 1 ta, ikki so'z
/// bo'lsa 2 ta ("Diyorbek Karimov" → "DK").
String avatarInitials(String? name) {
  final parts = (name ?? '')
      .trim()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first.characters.first.toUpperCase();
  return (parts[0].characters.first + parts[1].characters.first).toUpperCase();
}

class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    required this.name,
    this.colorIndex,
    this.size = 40,
    this.showBorder = false,
  });

  final String? name;
  final int? colorIndex;
  final double size;

  /// Podiumda/joriy foydalanuvchi qatorida ajratib ko'rsatish uchun.
  final bool showBorder;

  @override
  Widget build(BuildContext context) {
    final color = AvatarPalette.resolve(name, colorIndex);
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: showBorder
            ? Border.all(color: scheme.surface, width: size >= 48 ? 3 : 2)
            : null,
      ),
      child: Text(
        avatarInitials(name),
        style: TextStyle(
          // 0.42 — 40 px doirada 17 px harf: to'la, lekin chetga tegmaydi.
          fontSize: size * 0.42,
          fontWeight: FontWeight.w700,
          color: Colors.white,
          height: 1,
        ),
      ),
    );
  }
}
