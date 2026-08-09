import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/breakpoints.dart';
import '../features/home/home_shell.dart';
import '../features/news/news_screen.dart';
import '../features/notes/notes_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/settings/support_section.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_colors.dart';
import '../theme/spacing.dart';

/// Sahifa oxiri.
///
/// ## Nega kerak edi
///
/// Sinovda aytilgan: "sahifalar to'satdan tugaydi". Bu haqiqat edi — oxirgi
/// kartadan keyin bo'sh joy boshlanardi va foydalanuvchi "yuklanmay qoldimi?"
/// deb o'ylardi. Footer sahifaga OXIR beradi.
///
/// ## Nega ikkita variant
///
/// Bu ilova — kirilgan panel (dashboard), marketing sayti emas. Har bir
/// tabning ostiga uch ustunli katta footer qo'yish interfeysni YOMONLASHTIRADI:
/// reyting yoki bellashuv ro'yxatini skroll qilgan odam pastda "Biz bilan"
/// ustunini ko'rishni xohlamaydi.
///
///  * [AppFooter.full] — faqat BOSH ekranda. U kashfiyot yuzasi: bu yerda
///    boshqa bo'limlarga havola mantiqli.
///  * [AppFooter.compact] — qolgan hamma joyda. Bitta qator, ikkita havola.
///
/// ## Nega umumiy SaaS ustunlari yo'q
///
/// "About / Services / Solutions / Resources" — shablon footer. Bu yerda
/// faqat o'quvchi va ota-onaga HAQIQATAN kerak bo'ladigan yo'llar bor, va
/// har bir havola ishlaydigan joyga olib boradi (mavjud bo'lmagan
/// "Maxfiylik siyosati" sahifasiga havola ataylab qo'yilmagan).
class AppFooter extends ConsumerWidget {
  const AppFooter.full({super.key}) : compact = false;
  const AppFooter.compact({super.key}) : compact = true;

  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return compact ? _buildCompact(context, ref) : _buildFull(context, ref);
  }

  // ---- kichik variant ------------------------------------------------------
  Widget _buildCompact(BuildContext context, WidgetRef ref) {
    final l = L10n.of(context);
    final text = Theme.of(context).textTheme;
    final palette = Theme.of(context).extension<AppPalette>()!;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
          Spacing.md, Spacing.xl, Spacing.md, Spacing.lg),
      child: Column(
        children: [
          Divider(color: palette.hairline, height: 1),
          const Gap.ms(),
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: Spacing.sm,
            runSpacing: Spacing.xs,
            children: [
              Text('Topag‘on',
                  style: text.labelMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const _Dot(),
              _FooterLink(l.footerHelp,
                  onTap: () => openFeedbackDialog(context, ref)),
              const _Dot(),
              const _FooterLink('Telegram', onTap: _openTelegram),
              const _Dot(),
              Text(l.footerCopyright(DateTime.now().year),
                  style: text.labelSmall?.copyWith(color: palette.faint)),
            ],
          ),
        ],
      ),
    );
  }

  // ---- to'liq variant ------------------------------------------------------
  Widget _buildFull(BuildContext context, WidgetRef ref) {
    final l = L10n.of(context);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final palette = Theme.of(context).extension<AppPalette>()!;

    final columns = <Widget>[
      _FooterColumn(
        title: l.footerPlatform,
        links: [
          (l.navLeaderboard, () => _goTab(ref, 1)),
          (l.navChallenges, () => _goTab(ref, 2)),
          (l.navParent, () => _goTab(ref, 3)),
          (l.notesTitle, () => NotesScreen.open(context)),
        ],
      ),
      _FooterColumn(
        title: l.footerHelp,
        links: [
          (l.newsTitle, () => _push(context, const NewsScreen())),
          (l.supportFeedback, () => openFeedbackDialog(context, ref)),
          (l.settings, () => _push(context, const SettingsScreen())),
        ],
      ),
      _FooterColumn(
        title: l.footerContact,
        links: const [
          ('Telegram', _openTelegram),
        ],
      ),
    ];

    final brand = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircleAvatar(
                radius: 18, backgroundImage: AssetImage('assets/logo.png')),
            const Gap.ms(),
            Text('Topag‘on',
                style: text.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          ],
        ),
        const Gap.sm(),
        // Shiorning kengligi cheklanadi: 1100 px li footerda bitta qatorga
        // cho'zilgan matnni ko'z o'qimaydi.
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 280),
          child: Text(l.footerTagline, style: text.bodySmall),
        ),
      ],
    );

    return Container(
      margin: const EdgeInsets.only(top: Spacing.xxl),
      padding: const EdgeInsets.fromLTRB(
          Spacing.md, Spacing.xl, Spacing.md, Spacing.lg),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: palette.hairline)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Keng ekranda brend chapda, uchta ustun qolgan joyni TENG bo'lib
          // oladi — ya'ni footer butun kenglikni egallaydi. Birinchi
          // versiyada ustunlar `Wrap` ichida edi va desktopda hammasi CHAP
          // CHETGA yopishib qolardi: 1100 px li footerning o'ng yarmi bo'sh
          // turardi. Tor ekranda ustma-ust joylashuv qoladi — 360 px da
          // to'rtta ustunni yonma-yon qo'yib bo'lmaydi.
          //
          // NEGA `MediaQuery`, `LayoutBuilder` EMAS. Footer
          // `SliverFillRemaining(hasScrollBody: false)` ichida turadi
          // (`FooterSliver`) va u bolasining INTRINSIC balandligini
          // so'raydi. `LayoutBuilder` esa intrinsic o'lchamni bermaydi va
          // "LayoutBuilder does not support returning intrinsic dimensions"
          // bilan yiqiladi — bu xato `flutter test` da tutildi.
          //
          // `expanded` (≥840 dp) — rail chiqqandan keyin footerga qoladigan
          // kenglik uchta ustunni yonma-yon ko'rsatishga yetadigan chegara.
          if (context.windowSize.index >= WindowSize.expanded.index)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Brend blokiga ustunlarnikidan ko'proq joy: unda logo va
                // ikki qatorli shior bor.
                Expanded(flex: 4, child: brand),
                for (final col in columns) Expanded(flex: 3, child: col),
              ],
            )
          else ...[
            brand,
            const Gap.xl(),
            Wrap(
              spacing: Spacing.xl,
              runSpacing: Spacing.lg,
              children: columns,
            ),
          ],

          const Gap.xl(),
          Divider(color: palette.hairline, height: 1),
          const Gap.sm(),
          Row(
            children: [
              Expanded(
                child: Text(l.footerCopyright(DateTime.now().year),
                    style: text.labelSmall?.copyWith(color: palette.faint)),
              ),
              // Tilni almashtirish sozlamalarda; bu yerda unga qisqa yo'l.
              TextButton.icon(
                onPressed: () => _push(context, const SettingsScreen()),
                icon: Icon(Icons.language_rounded,
                    size: 16, color: scheme.primary),
                label: Text(l.language, style: text.labelSmall),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static void _goTab(WidgetRef ref, int index) =>
      ref.read(homeTabProvider.notifier).state = index;

  static void _push(BuildContext context, Widget screen) => Navigator.push(
      context, MaterialPageRoute(builder: (_) => screen));

  static Future<void> _openTelegram() async {
    await launchUrl(
      Uri.parse('https://t.me/$kSupportTelegram'),
      mode: LaunchMode.externalApplication,
    );
  }
}

/// Footer — sliver sifatida, EKRAN PASTIGA bosilgan holda.
///
/// ## Muammo
///
/// Reyting sahifasida bitta qator bor. Footer to'g'ridan-to'g'ri ro'yxatdan
/// keyin turgani uchun u ekranning o'rtasida qolib, ostida ~400 px bo'sh
/// oq joy paydo bo'lardi. Sahifa "yuklanmay qolgandek" ko'rinadi.
///
/// ## Yechim
///
/// `SliverFillRemaining(hasScrollBody: false)` — viewportda qolgan bo'sh
/// joyni oladi (kontent kalta bo'lsa), kontent uzun bo'lsa esa faqat
/// bolasining balandligini oladi. Ichidagi `Column(mainAxisAlignment: end)`
/// footerni pastga bosadi.
///
/// NEGA `Column(Expanded(scroll), Footer())` EMAS: u footerni DOIMIY
/// ko'rinadigan qilib qo'yadi va uzun ro'yxatda ham ekranning pastki
/// qismini egallab turadi. Bu yerda kerak bo'lgani boshqa — kontent kalta
/// bo'lsa pastda, uzun bo'lsa scroll oxirida.
///
/// `SizedBox(height: 400)` bilan "to'ldirish" YARAMAYDI: u faqat bitta
/// ekran o'lchamida to'g'ri ko'rinadi.
class FooterSliver extends StatelessWidget {
  const FooterSliver({super.key, this.full = false});

  /// `true` — bosh ekrandagi to'liq (uch ustunli) variant.
  final bool full;

  @override
  Widget build(BuildContext context) {
    return SliverFillRemaining(
      hasScrollBody: false,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          full ? const AppFooter.full() : const AppFooter.compact(),
        ],
      ),
    );
  }
}

class _FooterColumn extends StatelessWidget {
  const _FooterColumn({required this.title, required this.links});

  final String title;
  final List<(String, VoidCallback)> links;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final palette = Theme.of(context).extension<AppPalette>()!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title.toUpperCase(),
            style: text.labelSmall?.copyWith(
              color: palette.muted,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            )),
        const Gap.sm(),
        for (final (label, onTap) in links)
          Padding(
            padding: const EdgeInsets.only(bottom: Spacing.xs),
            child: _FooterLink(label, onTap: onTap),
          ),
      ],
    );
  }
}

/// Footer havolasi. `TextButton` EMAS: uning ichki paddingi 8–16 px va
/// ustun ichida havolalar bir-biridan juda uzoqda turadi.
class _FooterLink extends StatefulWidget {
  const _FooterLink(this.label, {required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  State<_FooterLink> createState() => _FooterLinkState();
}

class _FooterLinkState extends State<_FooterLink> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final palette = Theme.of(context).extension<AppPalette>()!;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Text(
          widget.label,
          style: text.bodySmall?.copyWith(
            color: _hover ? scheme.primary : palette.muted,
            decoration: _hover ? TextDecoration.underline : null,
            decorationColor: scheme.primary,
          ),
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot();

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    return Text('·', style: TextStyle(color: palette.faint));
  }
}
