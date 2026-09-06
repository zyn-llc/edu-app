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

///
///
///
///
/// tabning ostiga uch ustunli katta footer qo'yish interfeysni YOMONLASHTIRADI:
///
///
///
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
          // CHETGA yopishib qolardi: 1100 px li footerning o'ng yarmi bo'sh
          //
          // `SliverFillRemaining(hasScrollBody: false)` ichida turadi
          // (`FooterSliver`) va u bolasining INTRINSIC balandligini
          // "LayoutBuilder does not support returning intrinsic dimensions"
          //
          if (context.windowSize.index >= WindowSize.expanded.index)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // o'ngga yig'iladi.
                //
                Expanded(child: brand),
                for (final col in columns) ...[
                  const SizedBox(width: Spacing.xxl),
                  col,
                ],
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
              TextButton.icon(
                onPressed: () => _push(context, const SettingsScreen()),
                icon: Icon(Icons.language_rounded,
                    size: 20, color: scheme.primary),
                label: Text(l.language,
                    style: text.labelMedium?.copyWith(color: scheme.primary)),
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

///
///
///
/// ## Yechim
///
/// `SliverFillRemaining(hasScrollBody: false)` — viewportda qolgan bo'sh
/// bolasining balandligini oladi. Ichidagi `Column(mainAxisAlignment: end)`
/// footerni pastga bosadi.
///
///
class FooterSliver extends StatelessWidget {
  const FooterSliver({super.key, this.full = false});

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
