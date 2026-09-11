import 'package:flutter/material.dart';

import '../../core/localization/app_localizations.dart';
import '../../models/house.dart';
import '../../view_models/app_view_model.dart';

class HouseSelectionScreen extends StatefulWidget {
  final AppViewModel viewModel;
  final bool showSignOut;
  final bool popOnSuccess;
  final Future<bool> Function(House house)? onHouseSelected;

  const HouseSelectionScreen({
    super.key,
    required this.viewModel,
    this.showSignOut = true,
    this.popOnSuccess = false,
    this.onHouseSelected,
  });

  @override
  State<HouseSelectionScreen> createState() => _HouseSelectionScreenState();
}

class _HouseSelectionScreenState extends State<HouseSelectionScreen> {
  String? selectedHouseId;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AnimatedBuilder(
      animation: widget.viewModel,
      builder: (context, _) {
        final loadingHouseId =
            selectedHouseId ?? widget.viewModel.selectingHouseId;
        return Scaffold(
          appBar: AppBar(
            title: Text(l10n.t('chooseHouse')),
            backgroundColor: const Color(0xFFF7FFFC),
            actions: [
              if (widget.showSignOut)
                IconButton(
                  tooltip: l10n.t('signOut'),
                  onPressed:
                      widget.viewModel.isBusy ? null : widget.viewModel.signOut,
                  icon: const Icon(Icons.logout),
                ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFEFFDF8), Color(0xFFE0F2FE)],
                  ),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 54,
                        height: 54,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Icon(
                          Icons.home_work_outlined,
                          size: 30,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        l10n.t('chooseHouseTitle'),
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 6),
                      Text(l10n.t('chooseHouseBody')),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              ...widget.viewModel.availableHouses.map(
                (house) => _HouseChoiceTile(
                  house: house,
                  busy: loadingHouseId != null,
                  selectedBusy: loadingHouseId == house.id,
                  onTap: () => _selectHouse(house),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _selectHouse(House house) async {
    if (selectedHouseId != null || widget.viewModel.isBusy) return;
    setState(() => selectedHouseId = house.id);
    final selected = await (widget.onHouseSelected?.call(house) ??
        widget.viewModel.selectHouse(house));
    if (!mounted) return;
    setState(() => selectedHouseId = null);
    if (selected && widget.popOnSuccess) {
      Navigator.pop(context, true);
    }
  }
}

class _HouseChoiceTile extends StatelessWidget {
  final House house;
  final bool busy;
  final bool selectedBusy;
  final VoidCallback onTap;

  const _HouseChoiceTile({
    required this.house,
    required this.busy,
    required this.selectedBusy,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: busy ? null : onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: const Color(0xFFEFFDF8),
                  child: Icon(
                    Icons.home_outlined,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        house.name,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        house.address.isNotEmpty
                            ? house.address
                            : l10n.t('noAddressAdded'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ),
                selectedBusy
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.chevron_right),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
