import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/auth_controller.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_colors.dart';
import '../../theme/spacing.dart';
import 'invite_screen.dart';
import 'password_screen.dart';
import 'phone_screen.dart';
import 'telegram_screen.dart';

/// Yagona kirish nuqtasi.
///
/// MUAMMO (2026-08-06). Ilova har joydan to'g'ridan-to'g'ri `PhoneScreen` ni
/// ochardi. Prodda esa `SMS_PROVIDER=disabled` — foydalanuvchi raqamini
/// kiritib, "Kod yuborish" ni bosib, 503 olardi. Telegram va taklif kodi
/// tugmalari o'sha ekranning PASTIDA, telefon maydonidan keyin turardi.
/// Ya'ni ishlaydigan yagona yo'l eng oxirida edi.
///
/// YECHIM. Kirish endi varaq (bottom sheet) bilan boshlanadi: server
/// `GET /v1/auth/methods` da qaysi usul ochiqligini aytadi, varaq faqat
/// ochiqlarini va aynan shu tartibda ko'rsatadi. Telefon o'chirilgan bo'lsa
/// u umuman chizilmaydi — foydalanuvchi mavjud bo'lmagan yo'lga urinmaydi.
///
/// Qaytish qiymati: `true` — kirish muvaffaqiyatli tugadi.
class LoginSheet extends ConsumerWidget {
  const LoginSheet({super.key, this.reason});

  /// Ixtiyoriy sarlavha osti: nega kirish taklif qilinyapti
  /// ("natijangiz saqlanmayapti", "bellashuv uchun hisob kerak"...).
  final String? reason;

  static Future<bool> show(BuildContext context, {String? reason}) async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 520),
      builder: (_) => LoginSheet(reason: reason),
    );
    return ok == true;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L10n.of(context);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final palette = Theme.of(context).extension<AppPalette>()!;
    final methods = ref.watch(authMethodsProvider);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            Spacing.lg, Spacing.sm, Spacing.lg, Spacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                    color: palette.primaryTint, shape: BoxShape.circle),
                child: Icon(Icons.login_rounded,
                    size: 30, color: scheme.primary),
              ),
            ),
            const Gap.md(),
            Text(l.authLoginTitle,
                style: text.headlineSmall, textAlign: TextAlign.center),
            const Gap.sm(),
            Text(reason ?? l.authLoginBenefit,
                style: text.bodySmall, textAlign: TextAlign.center),
            const Gap.lg(),
            methods.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: Spacing.lg),
                child: Center(child: CircularProgressIndicator()),
              ),
              // Xato bo'lsa ham provider `AuthMethods()` qaytaradi, shuning
              // uchun bu shox amalda chaqirilmaydi — lekin `when` to'liq
              // bo'lishi kerak.
              error: (_, __) => _options(context, const AuthMethods()),
              data: (m) => _options(context, m),
            ),
            const Gap.sm(),
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l.guestLater),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context, Widget screen) async {
    final navigator = Navigator.of(context);
    final ok = await navigator.push<bool>(
        MaterialPageRoute(builder: (_) => screen));
    if (ok == true && navigator.canPop()) navigator.pop(true);
  }

  Widget _options(BuildContext context, AuthMethods m) =>
      _Options(methods: m, open: _open);
}

/// Kirish usullari: BITTA asosiy tugma + «Boshqa usullar».
///
/// Ilgari to'rttasi ham teng kattalikda, ketma-ket turardi. Bu ilovadagi eng
/// ko'p odam yo'qotadigan nuqta va u yerda to'rtta teng variant tanlov
/// falajini beradi: yangi kelgan odam qaysi biri «to'g'ri» ekanini bilmaydi.
/// Endi eng oson yo'l (odatda Telegram — yozadigan narsa yo'q) yagona katta
/// tugma, qolganlari esa bir bosish orqasida.
class _Options extends StatefulWidget {
  const _Options({required this.methods, required this.open});

  final AuthMethods methods;
  final Future<void> Function(BuildContext, Widget) open;

  @override
  State<_Options> createState() => _OptionsState();
}

class _OptionsState extends State<_Options> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final m = widget.methods;

    if (!m.any) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: Spacing.md),
        child: Text(l.authNoMethods, textAlign: TextAlign.center),
      );
    }

    // Tartib ataylab (2026-08-06 da O'ZGARTIRILDI):
    //   1. Telegram— YANGI foydalanuvchi uchun eng tez yo'l: yozadigan
    //                narsa yo'q, parol o'ylab topish kerak emas, telefon
    //                raqami so'ralmaydi. Kirgandan keyin ilova darhol
    //                "hisobingizni saqlab qo'ying" deb parol taklif qiladi
    //                (`TelegramLoginScreen` -> `SetPasswordSheet`), ya'ni
    //                keyingi safar Telegramga qaytish shart emas.
    //   2. parol   — QAYTIB kirish yo'li. Ilgari u BIRINCHI turardi va
    //                natijada yangi kelgan odam darhol "nom o'ylab top,
    //                parol o'ylab top" ekraniga tushardi — bu esa eng
    //                og'ir birinchi qadam. Telegram bilan boshlagan odam
    //                parolni KEYIN, hisobi allaqachon borligini bilgan
    //                holda qo'yadi.
    //   3. taklif  — beta kodi bo'lganlar uchun, bir martalik.
    //   4. telefon — eng oxirida: SMS kutish kerak, shlyuz esa moderatsiyada.
    final tiles = <Widget>[
      if (m.telegram)
        _Tile(
          icon: Icons.send_rounded,
          title: l.authTelegramButton,
          subtitle: l.authTelegramSubtitle,
          primary: true,
          onTap: () => widget.open(context, const TelegramLoginScreen()),
        ),
      if (m.password)
        _Tile(
          icon: Icons.lock_outline_rounded,
          title: l.pwButton,
          // Yopiq betada parol bilan RO'YXATDAN O'TISH taklif kodi so'raydi.
          // Kodsiz kelgan odam tugmani bosib, kutilmaganda kod maydonini
          // ko'rardi. Endi tavsif buni oldindan aytadi.
          subtitle: m.passwordRegisterRequiresInvite
              ? l.pwButtonSubtitleExisting
              : l.pwButtonSubtitle,
          primary: !m.telegram,
          onTap: () => widget.open(context, const PasswordScreen()),
        ),
      if (m.invite)
        _Tile(
          icon: Icons.confirmation_number_outlined,
          title: l.authInviteButton,
          subtitle: l.authInviteSubtitle,
          primary: !m.password && !m.telegram,
          onTap: () => widget.open(context, const InviteScreen()),
        ),
      if (m.phone)
        _Tile(
          icon: Icons.phone_iphone_rounded,
          title: l.authPhoneButton,
          subtitle: l.authPhoneSubtitle,
          primary: !m.password && !m.telegram && !m.invite,
          onTap: () => widget.open(context, const PhoneScreen()),
        ),
    ];

    // Bitta usul bo'lsa yashiradigan narsa yo'q.
    final rest = tiles.length > 1 ? tiles.sublist(1) : const <Widget>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        tiles.first,
        if (rest.isNotEmpty && !_expanded) ...[
          const Gap.sm(),
          TextButton(
            onPressed: () => setState(() => _expanded = true),
            child: Text(l.authOtherMethods),
          ),
        ],
        if (_expanded)
          for (final t in rest) ...[const Gap.sm(), t],
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool primary;
  final VoidCallback onTap;
  const _Tile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.primary,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final palette = Theme.of(context).extension<AppPalette>()!;
    final fg = primary ? scheme.onPrimary : scheme.onSurface;

    return Material(
      color: primary ? scheme.primary : palette.surfaceAlt,
      borderRadius: Radii.cardRadius,
      child: InkWell(
        onTap: onTap,
        borderRadius: Radii.cardRadius,
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: Spacing.md, vertical: Spacing.ms),
          child: Row(
            children: [
              Icon(icon, color: fg),
              const SizedBox(width: Spacing.ms),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: fg)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: TextStyle(
                            fontSize: 12,
                            height: 1.3,
                            color: fg.withValues(alpha: 0.8))),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  color: fg.withValues(alpha: 0.7)),
            ],
          ),
        ),
      ),
    );
  }
}
