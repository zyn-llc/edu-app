import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_client.dart';
import '../../api/api_error.dart';
import '../../auth/auth_controller.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/spacing.dart';
import '../../widgets/avatar.dart';
import '../auth/password_screen.dart';
import '../../core/breakpoints.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  late final TextEditingController _name;
  String? _region;
  int? _grade;
  int? _avatarColor;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final u = ref.read(authControllerProvider).user;
    _name = TextEditingController(text: u?.displayName ?? '');
    _region = u?.regionCode;
    _grade = u?.grade;
    // Tanlanmagan bo'lsa — ism hash'idan barqaror rang. Foydalanuvchi hech
    // narsa tanlamasa ham avatari "tasodifiy" emas, o'ziniki bo'lib qoladi.
    _avatarColor =
        u?.avatarColor ?? AvatarPalette.indexForName(u?.displayName);
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l = L10n.of(context);
    final name = _name.text.trim();
    if (name.isEmpty || name.length > 40) {
      setState(() => _error = l.profileNameError);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(authControllerProvider.notifier).updateProfile(
            displayName: name,
            regionCode: _region,
            grade: _grade,
            avatarColor: _avatarColor,
          );
      // refresh dependent views (dashboard strip, leaderboard "you")
      ref.invalidate(meOverviewProvider);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l.profileSaved)));
        Navigator.pop(context);
      }
    } on DioException catch (e) {
      // Ilgari bu yerda HAR QANDAY DioException "Ulanishda xatolik" bo'lardi:
      // 400 (noto'g'ri hudud), 401 (token eskirgan) va haqiqiy tarmoq uzilishi
      // bir xil ko'rinardi va nima bo'lganini bilishning iloji yo'q edi.
      // `humanError` serverning RFC 7807 `title` maydonini ko'rsatadi.
      setState(() => _error = humanError(e, l));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final lang = ref.watch(localeCodeProvider);
    final regionsAsync = ref.watch(regionsProvider);
    // `watch`, `read` emas: parol o'rnatilgandan keyin `refreshMe()` holatni
    // yangilaydi va "Parol" bandi darhol "O'rnatilgan" ga o'tishi kerak.
    final user = ref.watch(authControllerProvider).user;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        title: Text(l.profileTitle),
      ),
      body: ContentWidth(
        maxWidth: 560,
        child: ListView(
          padding: const EdgeInsets.all(22),
          children: [
            // Avatar — ekranning boshida: foydalanuvchi o'zgarishni darhol
            // ko'radi (ism yozilganda bosh harf ham yangilanadi).
            Center(
              child: UserAvatar(
                name: _name.text.trim().isEmpty ? null : _name.text.trim(),
                colorIndex: _avatarColor,
                size: 88,
              ),
            ),
            const Gap.ms(),
            Center(
              child: Text(l.profileAvatarHint,
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center),
            ),
            const Gap.ms(),
            Wrap(
              spacing: Spacing.sm,
              runSpacing: Spacing.sm,
              alignment: WrapAlignment.center,
              children: [
                for (var i = 0; i < AvatarPalette.length; i++)
                  _ColorDot(
                    color: AvatarPalette.colors[i],
                    selected: _avatarColor == i,
                    onTap: () => setState(() => _avatarColor = i),
                  ),
              ],
            ),
            const Gap.lg(),
            Text(l.profileName,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            TextField(
              controller: _name,
              // Bosh harf avatarda jonli yangilansin.
              onChanged: (_) => setState(() {}),
              // Ism REYTINGDA va BELLASHUVDA boshqalarga ko'rinadi. Emoji,
              // CJK va o'ngdan-chapga yoziladigan matn qatorni buzadi —
              // sinovda `火` ismli hisob paydo bo'lgan edi. Serverda ham
              // (`core/names.py`) shu qoida bor; bu yerdagisi faqat qulaylik:
              // foydalanuvchi xatoni yuborishdan OLDIN ko'radi.
              inputFormatters: [
                LengthLimitingTextInputFormatter(40),
                FilteringTextInputFormatter.allow(
                    RegExp(r"[A-Za-z0-9\u0400-\u04FF\u2018\u2019\u02BB\u02BC' .\-]")),
              ],
              decoration: InputDecoration(
                hintText: l.profileNameHint,
                helperText: l.nameInvalidChars,
                helperMaxLines: 2,
                border: const OutlineInputBorder(),
                errorText: _error,
              ),
            ),
            const SizedBox(height: 20),
            Text(l.profileRegion,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            regionsAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (_, __) => Text(l.authNetworkError),
              data: (regions) => DropdownButtonFormField<String>(
                initialValue: _region,
                isExpanded: true,
                decoration: const InputDecoration(border: OutlineInputBorder()),
                hint: Text(l.profileRegionHint),
                items: [
                  for (final r in regions)
                    DropdownMenuItem(value: r.code, child: Text(r.name(lang))),
                ],
                onChanged: (v) => setState(() => _region = v),
              ),
            ),
            const SizedBox(height: 20),
            Text(l.profileGrade,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            DropdownButtonFormField<int>(
              initialValue: _grade,
              isExpanded: true,
              decoration: const InputDecoration(border: OutlineInputBorder()),
              hint: Text(l.profileGradeHint),
              items: [
                for (var g = 1; g <= 11; g++)
                  DropdownMenuItem(value: g, child: Text(l.gradeN(g))),
              ],
              onChanged: (v) => setState(() => _grade = v),
            ),
            const SizedBox(height: 28),
            FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(50)),
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(l.profileSave),
            ),
            const SizedBox(height: 28),
            const Divider(height: 1),
            const SizedBox(height: 16),
            _PasswordRow(username: user?.username),
          ],
        ),
      ),
    );
  }
}

/// Profildagi "Parol" bandi.
///
/// Telegram bilan kirgan hisobda `username` bo'lmaydi — o'sha holatda bu
/// yerda nima uchun har safar Telegram'ga o'tish kerakligi va uni qanday
/// to'xtatish mumkinligi aytiladi. Aynan shu bosqichda foydalanuvchi
/// muammoni his qilib turadi, ya'ni taklif joyida bo'ladi.
class _PasswordRow extends StatelessWidget {
  const _PasswordRow({this.username});

  final String? username;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final has = (username ?? '').isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(has ? Icons.lock_rounded : Icons.lock_open_rounded,
              size: 20, color: scheme.primary),
          const SizedBox(width: Spacing.sm),
          Text(l.pwProfileTitle,
              style: const TextStyle(fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 6),
        Text(has ? '@$username · ${l.pwProfileSet}' : l.pwProfileNotSet,
            style: text.bodySmall),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: () =>
              SetPasswordSheet.show(context, existingUsername: username),
          icon: const Icon(Icons.key_outlined, size: 18),
          label: Text(has ? l.pwProfileChange : l.pwSetTitle),
        ),
      ],
    );
  }
}

/// Palitradagi bitta rang. Tanlanganda ichida belgi chiqadi — faqat halqa
/// bilan ajratish rang ko'rish buzilishi bor foydalanuvchiga yetarli emas.
class _ColorDot extends StatelessWidget {
  const _ColorDot({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: selected
              ? Border.all(color: scheme.onSurface, width: 3)
              : null,
        ),
        child: selected
            ? const Icon(Icons.check_rounded, size: 20, color: Colors.white)
            : null,
      ),
    );
  }
}
