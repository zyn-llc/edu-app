import 'package:flutter/material.dart';

///
/// esa 8-avgustda topshiriladi. Bolalar ilovasida moderatsiyasiz rasm
/// (`users.avatar_color`).
///
/// kulrang doiralar qatori chiqmaydi.
class AvatarPalette {
  const AvatarPalette._();

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
          fontSize: size * 0.42,
          fontWeight: FontWeight.w700,
          color: Colors.white,
          height: 1,
        ),
      ),
    );
  }
}
