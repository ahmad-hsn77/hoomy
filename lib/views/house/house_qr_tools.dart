import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/localization/app_localizations.dart';

Future<void> showHouseQrDialog(BuildContext context, String houseCode) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      title: Text(context.l10n.t('houseQrCode')),
      content: SizedBox(
        width: 260,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox.square(
              dimension: 220,
              child: QrImageView(
                data: houseCode,
                version: QrVersions.auto,
                backgroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            SelectableText(
              houseCode,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.t('close')),
        ),
      ],
    ),
  );
}

Future<String?> scanHouseQrCode(BuildContext context) {
  return Navigator.push<String>(
    context,
    MaterialPageRoute(builder: (_) => const HouseQrScannerScreen()),
  );
}

class HouseQrScannerScreen extends StatefulWidget {
  const HouseQrScannerScreen({super.key});

  @override
  State<HouseQrScannerScreen> createState() => _HouseQrScannerScreenState();
}

class _HouseQrScannerScreenState extends State<HouseQrScannerScreen> {
  final controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool scanned = false;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.t('scanHouseQr'))),
      body: Stack(
        children: [
          MobileScanner(
            controller: controller,
            onDetect: (capture) {
              if (scanned) return;
              String? value;
              for (final barcode in capture.barcodes) {
                final rawValue = barcode.rawValue?.trim();
                if (rawValue != null && rawValue.isNotEmpty) {
                  value = rawValue;
                  break;
                }
              }
              if (value == null) return;
              scanned = true;
              Navigator.pop(context, value);
            },
          ),
          Center(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 3),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
              color: Colors.black.withValues(alpha: 0.55),
              child: Text(
                context.l10n.t('pointCameraAtQr'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
