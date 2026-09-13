// 文件用途：集中展示较低频的应用设置入口，保持主设置页面简洁。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_provider.dart';
import 'chat_settings_page.dart';
import 'stickers_page.dart';

class MoreSettingsPage extends ConsumerWidget {
  const MoreSettingsPage({super.key});

  String _text(
    AppLanguage language, {
    required String zhCN,
    required String zhTW,
    required String en,
  }) {
    switch (language) {
      case AppLanguage.en:
        return en;
      case AppLanguage.zhTW:
        return zhTW;
      case AppLanguage.zhCN:
        return zhCN;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final language = ref.watch(languageProvider);
    final themeMode = ref.watch(themeModeProvider);
    final l10n = AppLocalizations(language);

    return Scaffold(
      backgroundColor:
          isDark ? AppColors.darkBackground : AppColors.lightBackground,
      appBar: AppBar(
        title: Text(
          _text(
            language,
            zhCN: '更多设置',
            zhTW: '更多設定',
            en: 'More Settings',
          ),
        ),
        backgroundColor:
            isDark ? AppColors.darkBackground : AppColors.lightBackground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          _MoreSettingsGroup(
            isDark: isDark,
            children: [
              _MoreSettingsTile(
                icon: Icons.chat_bubble_outline,
                iconBgColor: AppColors.primaryFor(context),
                title: l10n.chatSettings,
                onTap: () => _openPage(context, const ChatSettingsPage()),
              ),
              _MoreSettingsTile(
                icon: Icons.emoji_emotions_outlined,
                iconBgColor: const Color(0xFFFFCC00),
                title: l10n.stickersEmoji,
                onTap: () => _openPage(context, const StickersPage()),
              ),
              _MoreSettingsTile(
                icon: Icons.language_outlined,
                iconBgColor: const Color(0xFFAF52DE),
                title: l10n.languageText,
                subtitle: language.displayName,
                onTap: () => _showLanguageSheet(context, ref, language),
              ),
              _MoreSettingsTile(
                icon: Icons.brightness_6_outlined,
                iconBgColor: const Color(0xFF007AFF),
                title: l10n.appearance,
                subtitle: _themeModeText(themeMode, l10n),
                onTap: () => _showThemeSheet(context, ref, l10n, themeMode),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _openPage(BuildContext context, Widget page) {
    HapticFeedback.selectionClick();
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  String _themeModeText(ThemeMode mode, AppLocalizations l10n) {
    switch (mode) {
      case ThemeMode.system:
        return l10n.systemMode;
      case ThemeMode.light:
        return l10n.lightMode;
      case ThemeMode.dark:
        return l10n.darkMode;
    }
  }

  void _showLanguageSheet(
    BuildContext context,
    WidgetRef ref,
    AppLanguage currentLanguage,
  ) {
    final l10n = AppLocalizations(currentLanguage);
    _showSelectionSheet(
      context,
      title: l10n.languageText,
      children: AppLanguage.values
          .map(
            (language) => ListTile(
              title: Text(language.displayName),
              trailing: language == currentLanguage
                  ? Icon(
                      Icons.check_rounded,
                      color: AppColors.controlActiveFor(context),
                    )
                  : null,
              onTap: () {
                ref.read(languageProvider.notifier).setLanguage(language);
                Navigator.pop(context);
              },
            ),
          )
          .toList(),
    );
  }

  void _showThemeSheet(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
    ThemeMode currentMode,
  ) {
    final options = [
      (ThemeMode.system, l10n.systemMode),
      (ThemeMode.light, l10n.lightMode),
      (ThemeMode.dark, l10n.darkMode),
    ];
    _showSelectionSheet(
      context,
      title: l10n.appearance,
      children: options
          .map(
            (option) => ListTile(
              title: Text(option.$2),
              trailing: option.$1 == currentMode
                  ? Icon(
                      Icons.check_rounded,
                      color: AppColors.controlActiveFor(context),
                    )
                  : null,
              onTap: () {
                ref.read(themeModeProvider.notifier).setThemeMode(option.$1);
                Navigator.pop(context);
              },
            ),
          )
          .toList(),
    );
  }

  void _showSelectionSheet(
    BuildContext context, {
    required String title,
    required List<Widget> children,
  }) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.cardFor(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimaryFor(context),
                ),
              ),
              const SizedBox(height: 8),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

class _MoreSettingsGroup extends StatelessWidget {
  final bool isDark;
  final List<Widget> children;

  const _MoreSettingsGroup({required this.isDark, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardFor(context),
        borderRadius: BorderRadius.circular(18),
        border: isDark
            ? Border.all(
                color: AppColors.dividerFor(context).withOpacity(0.75),
              )
            : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: List.generate(children.length * 2 - 1, (index) {
          if (index.isOdd) {
            return Divider(
              height: 1,
              indent: 62,
              color: AppColors.dividerFor(context),
            );
          }
          return children[index ~/ 2];
        }),
      ),
    );
  }
}

class _MoreSettingsTile extends StatelessWidget {
  final IconData icon;
  final Color iconBgColor;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  const _MoreSettingsTile({
    required this.icon,
    required this.iconBgColor,
    required this.title,
    this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 11, 10, 11),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: iconBgColor,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, color: Colors.white, size: 19),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimaryFor(context),
                ),
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(width: 8),
              Flexible(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textTertiaryFor(context),
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(width: 6),
            Icon(
              Icons.chevron_right_rounded,
              size: 21,
              color: AppColors.textTertiaryFor(context),
            ),
          ],
        ),
      ),
    );
  }
}
