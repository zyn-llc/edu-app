import 'package:flutter/material.dart';

/// Per-subject ACCENT color + fallback icon, keyed by the stable subject `code`
/// from the backend. Used only on covers, identity chips and progress fills —
/// never on chrome. Brightness picks the light/dark variant.
class SubjectStyle {
  final Color light;
  final Color dark;
  final IconData icon; // fallback when no cover image_url is present
  const SubjectStyle(this.light, this.dark, this.icon);

  Color color(Brightness b) => b == Brightness.dark ? dark : light;
}

class SubjectPalette {
  SubjectPalette._();

  static const _map = <String, SubjectStyle>{
    'geografiya':
        SubjectStyle(Color(0xFF2FA36B), Color(0xFF37B97D), Icons.public),
    'jahon_tarixi':
        SubjectStyle(Color(0xFFD9962A), Color(0xFFE8A53B), Icons.account_balance),
    'ozbekiston_tarixi':
        SubjectStyle(Color(0xFFC0492F), Color(0xFFD55A3F), Icons.flag),
    'matematika':
        SubjectStyle(Color(0xFF2F6FB0), Color(0xFF4A8BD0), Icons.calculate),
    'geometriya':
        SubjectStyle(Color(0xFF6A53C7), Color(0xFF8470DE), Icons.change_history),
    'fizika':
        SubjectStyle(Color(0xFF1E9E8F), Color(0xFF2BB6A6), Icons.bolt),
    'kimyo':
        SubjectStyle(Color(0xFFC7508A), Color(0xFFDC66A0), Icons.science),
    'ona_tili':
        SubjectStyle(Color(0xFFE0653B), Color(0xFFF07A50), Icons.menu_book),
    'biologiya':
        SubjectStyle(Color(0xFF5AA02C), Color(0xFF6FB83E), Icons.eco),
    'huquq':
        SubjectStyle(Color(0xFF3E5168), Color(0xFF56697F), Icons.gavel),
  };

  static const _fallback =
      SubjectStyle(Color(0xFF8A837A), Color(0xFFA39A8E), Icons.school);

  static SubjectStyle of(String code) => _map[code] ?? _fallback;
}
