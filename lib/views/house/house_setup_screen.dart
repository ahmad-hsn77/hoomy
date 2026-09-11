import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/constants/family_relations.dart';
import '../../core/localization/app_localizations.dart';
import '../../models/house.dart';
import '../../services/location_service.dart';
import '../../view_models/app_view_model.dart';
import 'house_qr_tools.dart';

class HouseSetupScreen extends StatefulWidget {
  final AppViewModel viewModel;

  const HouseSetupScreen({super.key, required this.viewModel});

  @override
  State<HouseSetupScreen> createState() => _HouseSetupScreenState();
}

class _HouseSetupScreenState extends State<HouseSetupScreen> {
  final houseName = TextEditingController(text: 'Our home');
  final address = TextEditingController();
  final houseCode = TextEditingController();
  final locationController = TextEditingController();
  final locationService = LocationService();
  String relation = 'Father';
  bool joinMode = false;
  bool locationPermission = false;
  bool locating = false;
  GeoPoint? selectedLocation;
  String? locationMessage;

  @override
  void dispose() {
    houseName.dispose();
    address.dispose();
    houseCode.dispose();
    locationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title:
            Text(joinMode ? l10n.t('joinAHouse') : l10n.t('createYourHouse')),
        backgroundColor: const Color(0xFFF7FFFC),
        actions: [
          IconButton(
            tooltip: l10n.t('signOut'),
            onPressed: widget.viewModel.isBusy
                ? null
                : () async {
                    await widget.viewModel.signOut();
                  },
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
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
              child: Column(
                children: [
                  SvgPicture.asset('assets/illustrations/create_house.svg',
                      height: 156),
                  const SizedBox(height: 10),
                  Text(
                    joinMode ? l10n.t('joinAHouse') : l10n.t('createYourHouse'),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          SegmentedButton<bool>(
            selected: {joinMode},
            segments: [
              ButtonSegment(
                  value: false,
                  label: Text(l10n.t('create')),
                  icon: const Icon(Icons.home_work_outlined)),
              ButtonSegment(
                  value: true,
                  label: Text(l10n.t('join')),
                  icon: const Icon(Icons.group_add_outlined)),
            ],
            onSelectionChanged: (value) =>
                setState(() => joinMode = value.first),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: relation,
            decoration: InputDecoration(labelText: l10n.t('yourFamilyRole')),
            items: familyRelations
                .map((item) => DropdownMenuItem(
                    value: item, child: Text(l10n.relation(item))))
                .toList(),
            onChanged: (value) => setState(() => relation = value ?? relation),
          ),
          if (joinMode) ...[
            const SizedBox(height: 12),
            TextField(
              controller: houseCode,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: l10n.t('houseSpecialNumber'),
                prefixIcon: const Icon(Icons.pin_outlined),
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: widget.viewModel.isBusy ? null : _scanHouseCode,
              icon: const Icon(Icons.qr_code_scanner_outlined),
              label: Text(l10n.t('scanHouseQr')),
            ),
          ] else ...[
            const SizedBox(height: 12),
            TextField(
                controller: houseName,
                decoration: InputDecoration(labelText: l10n.t('houseName'))),
            const SizedBox(height: 12),
            TextField(
                controller: address,
                decoration: InputDecoration(
                    labelText: l10n.t('addressOrNeighborhood'))),
            const SizedBox(height: 12),
            SwitchListTile(
              value: locationPermission,
              onChanged: locating ? null : _toggleLocation,
              title: Text(l10n.t('allowHouseLocation')),
              subtitle: Text(locationMessage ?? l10n.t('usedOutsideMembers')),
            ),
            TextField(
              controller: locationController,
              readOnly: true,
              decoration: InputDecoration(
                labelText: l10n.t('currentLocation'),
                hintText: locating
                    ? l10n.t('gettingCurrentLocation')
                    : l10n.t('noLocationAdded'),
                prefixIcon: locating
                    ? const Padding(
                        padding: EdgeInsets.all(14),
                        child: SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    : const Icon(Icons.location_on_outlined),
              ),
            ),
          ],
          if (widget.viewModel.errorMessage != null) ...[
            const SizedBox(height: 12),
            Text(widget.viewModel.errorMessage!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 20),
          FilledButton.icon(
            icon: widget.viewModel.isBusy
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(joinMode
                    ? Icons.group_add_outlined
                    : Icons.home_work_outlined),
            label: Text(widget.viewModel.isBusy
                ? (joinMode ? l10n.t('joining') : l10n.t('creating'))
                : (joinMode ? l10n.t('joinHouse') : l10n.t('createHouse'))),
            onPressed: widget.viewModel.isBusy
                ? null
                : () async {
                    if (joinMode) {
                      await widget.viewModel.joinHouse(
                        houseCode: houseCode.text.trim(),
                        relation: relation,
                      );
                    } else {
                      final created = await widget.viewModel.createHouse(
                        name: houseName.text.trim().isEmpty
                            ? 'Our home'
                            : houseName.text.trim(),
                        address: address.text.trim(),
                        location: locationPermission ? selectedLocation : null,
                        relation: relation,
                      );
                      if (created && context.mounted) {
                        final specialNumber =
                            widget.viewModel.house?.specialNumber;
                        if (specialNumber?.isNotEmpty == true) {
                          await showHouseQrDialog(context, specialNumber!);
                        }
                      }
                    }
                  },
          ),
        ],
      ),
    );
  }

  Future<void> _toggleLocation(bool value) async {
    final l10n = context.l10n;
    if (!value) {
      setState(() {
        locationPermission = false;
        selectedLocation = null;
        locationController.clear();
        locationMessage = null;
      });
      return;
    }

    final enabled = await locationService.isLocationServiceEnabled();
    if (!enabled && mounted) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l10n.t('enableLocation')),
          content: Text(l10n.t('enableLocationBody')),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(l10n.t('ok')))
          ],
        ),
      );
    }

    setState(() {
      locating = true;
      locationPermission = true;
      locationMessage = l10n.t('gettingCurrentLocation');
      locationController.text = l10n.t('gettingCurrentLocation');
    });

    final location = await locationService.requestCurrentLocation();
    if (!mounted) return;
    setState(() {
      locating = false;
      selectedLocation = location;
      locationPermission = location != null;
      if (location == null) {
        locationController.clear();
        locationMessage = l10n.t('couldNotGetLocation');
      } else {
        final locationText = _locationAddress(location);
        locationController.text = locationText;
        address.text = locationText;
        locationMessage = l10n.t('currentLocationAdded');
      }
    });
  }

  Future<void> _scanHouseCode() async {
    final code = await scanHouseQrCode(context);
    if (!mounted || code == null) return;
    setState(() => houseCode.text = code);
  }

  String _locationAddress(GeoPoint location) {
    return 'Lat ${location.lat.toStringAsFixed(6)}, Lng ${location.lng.toStringAsFixed(6)}';
  }
}
