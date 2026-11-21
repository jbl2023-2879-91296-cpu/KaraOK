import 'package:flutter/material.dart';
import 'package:karaok_app/app/app_theme.dart';
import 'package:karaok_app/core/security/session_manager.dart';
import 'package:karaok_app/shared/widgets/brand_logo.dart';

/// One primary destination in the tablet sidebar.
class AppSidebarItem {
  const AppSidebarItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    this.showBadge = false,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool showBadge;
}

/// Tablet navigation: a tinted panel that holds the brand, the primary
/// destinations and (when [extended]) the signed-in account.
///
/// Portrait tablets get a compact rail with labels under the icons; landscape
/// tablets get a labelled sidebar with full-width selection pills.
class AppSidebar extends StatelessWidget {
  const AppSidebar({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
    required this.extended,
    this.onOpenAccount,
  });

  final List<AppSidebarItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final bool extended;
  final VoidCallback? onOpenAccount;

  @override
  Widget build(BuildContext context) {
    final width = extended
        ? AppBreakpoints.sidebarWidth
        : AppBreakpoints.railWidth;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: 'Main navigation',
      child: Container(
        width: width,
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(right: BorderSide(color: Color(0x66B8CEC8))),
        ),
        child: SafeArea(
          right: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(
                  extended ? AppSpacing.lg : AppSpacing.md,
                  AppSpacing.xl,
                  extended ? AppSpacing.lg : AppSpacing.md,
                  AppSpacing.xl,
                ),
                child: _LogoTile(extended: extended),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.symmetric(
                    horizontal: extended ? AppSpacing.md : AppSpacing.sm,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: extended ? AppSpacing.xs : AppSpacing.md,
                    children: [
                      for (var i = 0; i < items.length; i++)
                        extended
                            ? _SidebarTile(
                                item: items[i],
                                selected: i == selectedIndex,
                                onTap: () => onSelected(i),
                              )
                            : _RailTile(
                                item: items[i],
                                selected: i == selectedIndex,
                                onTap: () => onSelected(i),
                              ),
                    ],
                  ),
                ),
              ),
              if (extended)
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: _AccountTile(onTap: onOpenAccount),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LogoTile extends StatelessWidget {
  const _LogoTile({required this.extended});
  final bool extended;

  @override
  Widget build(BuildContext context) => Align(
    alignment: extended ? Alignment.centerLeft : Alignment.center,
    child: Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppRadii.card),
        boxShadow: AppShadows.soft,
      ),
      child: extended
          ? const BrandLogo(width: 116, height: 52)
          : const BrandLogo(width: 60, height: 36),
    ),
  );
}

Widget _icon(AppSidebarItem item, bool selected) {
  final icon = Icon(
    selected ? item.selectedIcon : item.icon,
    color: selected ? AppColors.primary : AppColors.muted,
  );
  return Badge(isLabelVisible: item.showBadge, child: icon);
}

class _SidebarTile extends StatelessWidget {
  const _SidebarTile({
    required this.item,
    required this.selected,
    required this.onTap,
  });
  final AppSidebarItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: item.label,
    excludeSemantics: true,
    child: Material(
      color: selected ? AppColors.mint : Colors.transparent,
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: Row(
            children: [
              _icon(item, selected),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  item.label,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: selected ? AppColors.primary : AppColors.ink,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _RailTile extends StatelessWidget {
  const _RailTile({
    required this.item,
    required this.selected,
    required this.onTap,
  });
  final AppSidebarItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: item.label,
    excludeSemantics: true,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.card),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Column(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              width: 56,
              height: 32,
              decoration: ShapeDecoration(
                color: selected ? AppColors.mint : Colors.transparent,
                shape: const StadiumBorder(),
              ),
              alignment: Alignment.center,
              child: _icon(item, selected),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              item.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: selected ? AppColors.primary : AppColors.muted,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Who is using the app, pinned to the bottom of the landscape sidebar.
class _AccountTile extends StatelessWidget {
  const _AccountTile({this.onTap});
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: UserSession.instance,
    builder: (context, _) {
      final session = UserSession.instance;
      final guest = session.isGuest;
      final name = guest
          ? 'Guest'
          : [session.firstName, session.name, session.username]
                .firstWhere(
                  (v) => v != null && v.trim().isNotEmpty,
                  orElse: () => 'Account',
                )!
                .trim();
      final detail = guest
          ? 'Results stay on this device'
          : (session.email ?? '').trim();
      final image = session.profileImageBytes;
      return Material(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppRadii.card),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: guest ? AppColors.peach : AppColors.mint,
                  foregroundColor: guest
                      ? AppColors.orangeInk
                      : AppColors.primary,
                  backgroundImage: image == null ? null : MemoryImage(image),
                  child: image != null
                      ? null
                      : guest
                      ? const Icon(Icons.person_outline, size: 22)
                      : Text(
                          name.characters.first.toUpperCase(),
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(color: AppColors.primary),
                        ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      if (detail.isNotEmpty)
                        Text(
                          detail,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: AppColors.muted),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
