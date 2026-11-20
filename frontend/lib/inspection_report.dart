import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'localization.dart';

const _states = {
  'Original': 0xFF2E8B57,
  'Peinture': 0xFF3187B8,
  'Mastic / réparation': 0xFFF0A52B,
  'Défaut': 0xFFB05AA6,
  'Accident / dommage': 0xFFD94A45,
};

const _zones = <_PdfZone>[
  _PdfZone('front_bumper', 'Pare-chocs avant', 44, 1, 52, 7),
  _PdfZone('hood', 'Capot', 32, 9, 76, 41),
  _PdfZone('front_left_fender', 'Aile avant gauche', 20, 17, 20, 39),
  _PdfZone('front_right_fender', 'Aile avant droite', 100, 17, 20, 39),
  _PdfZone('windshield', 'Pare-brise', 37, 51, 66, 32),
  _PdfZone('left_front_door', 'Porte avant gauche', 29, 86, 13, 27),
  _PdfZone('right_front_door', 'Porte avant droite', 98, 86, 13, 27),
  _PdfZone('roof', 'Toit', 40, 85, 60, 62),
  _PdfZone('left_rear_door', 'Porte arrière gauche', 29, 114, 13, 30),
  _PdfZone('right_rear_door', 'Porte arrière droite', 98, 114, 13, 30),
  _PdfZone('rear_window', 'Lunette arrière', 40, 147, 60, 27),
  _PdfZone('left_rocker', 'Bas de caisse gauche', 22, 86, 6, 62),
  _PdfZone('right_rocker', 'Bas de caisse droit', 112, 86, 6, 62),
  _PdfZone('rear_left_fender', 'Aile arrière gauche', 20, 153, 20, 39),
  _PdfZone('rear_right_fender', 'Aile arrière droite', 100, 153, 20, 39),
  _PdfZone('trunk', 'Coffre', 37, 176, 66, 24),
  _PdfZone('rear_bumper', 'Pare-chocs arrière', 43, 202, 54, 7),
  _PdfZone('pillars', 'Montants', 40, 82, 60, 5),
];

const _mechanicalLabels = <String, String>{
  'engine': 'Moteur',
  'gearbox': 'Boîte de vitesses',
  'clutch': 'Embrayage',
  'brakes': 'Freinage',
  'suspension': 'Suspension',
  'steering': 'Direction',
  'leaks': 'Fuites',
  'smoke': 'Fumée',
  'general': 'État général mécanique',
  'wear': 'Consommables',
};

const _consumableLabels = <String, String>{
  'tyres': 'Pneus',
  'pads': 'Plaquettes',
  'discs': 'Disques',
  'battery': 'Batterie',
  'fluids': 'Liquides',
  'other': 'Autres éléments',
};

Future<Uint8List> buildInspectionPdf(
  Map<String, dynamic> inspection, {
  Map<String, dynamic> settings = const {},
}) async {
  final vehicle = inspection['vehicle'] as Map<String, dynamic>;
  final mileage = inspection['mileage'] is Map<String, dynamic>
      ? inspection['mileage'] as Map<String, dynamic>
      : <String, dynamic>{
          'displayed': vehicle['mileage'],
          'actual': null,
          'status': 'unknown',
        };
  final body = inspection['body_inspection'] as Map<String, dynamic>? ?? {};
  final mechanical =
      inspection['mechanical_inspection'] as Map<String, dynamic>? ?? {};
  final consumables = inspection['consumables'] as Map<String, dynamic>? ?? {};
  final companyValue = settings['company'];
  final company = companyValue is Map<String, dynamic>
      ? companyValue
      : const <String, dynamic>{};
  final reportValue = settings['report'];
  final reportSettings = reportValue is Map<String, dynamic>
      ? reportValue
      : const <String, dynamic>{};
  final languageCode = switch (settings['language']) {
    'ar' => 'ar',
    'en' => 'en',
    _ => 'fr',
  };
  final timeSeparator = switch (languageCode) {
    'ar' => 'في',
    'en' => 'at',
    _ => 'à',
  };
  String localize(String value) =>
      translateText(value, languageCode: languageCode);
  pw.Widget section(String title) => _sectionTitle(localize(title));
  final companyName = company['name']?.toString().trim().isNotEmpty == true
      ? company['name'].toString().trim()
      : localize('DIAGNOSTIC AUTOMOBILE');
  final companyContact =
      [
            company['address'],
            company['phone'],
            company['email'],
            company['website'],
          ]
          .map((value) => value?.toString().trim() ?? '')
          .where((value) => value.isNotEmpty)
          .join(' · ');
  final configuredLogo = company['logo_base64']?.toString() ?? '';
  final date = DateTime.tryParse(inspection['created_at'] as String? ?? '')
      ?.toLocal();
  final regularFont = pw.Font.ttf(
    await rootBundle.load('assets/fonts/Cairo-Regular.ttf'),
  );
  final boldFont = pw.Font.ttf(
    await rootBundle.load('assets/fonts/Cairo-Bold.ttf'),
  );
  final logoBytes = configuredLogo.isEmpty
      ? (await rootBundle.load('assets/logoo.png')).buffer.asUint8List()
      : base64Decode(configuredLogo);
  final logo = pw.MemoryImage(logoBytes);
  final qrCode = pw.MemoryImage(
    (await rootBundle.load('assets/QRWEB.png')).buffer.asUint8List(),
  );
  final vehiclePhoto = pw.MemoryImage(
    (await rootBundle.load('assets/voiture2.png')).buffer.asUint8List(),
  );
  final document = pw.Document();

  document.addPage(
    pw.MultiPage(
      theme: pw.ThemeData.withFont(base: regularFont, bold: boldFont),
      textDirection: languageCode == 'ar'
          ? pw.TextDirection.rtl
          : pw.TextDirection.ltr,
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      header: (_) => pw.Container(
        padding: const pw.EdgeInsets.only(bottom: 12),
        decoration: const pw.BoxDecoration(
          border: pw.Border(
            bottom: pw.BorderSide(color: PdfColor.fromInt(0xFFDAE3EC)),
          ),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Row(
              children: [
                pw.Image(logo, width: 30, height: 30),
                pw.SizedBox(width: 8),
                pw.Text(
                  companyName,
                  style: pw.TextStyle(
                    fontSize: 10,
                    fontWeight: pw.FontWeight.bold,
                    color: const PdfColor.fromInt(0xFF142C4C),
                  ),
                ),
              ],
            ),
            pw.Text(
              inspection['reference'] as String? ?? '',
              style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
            ),
          ],
        ),
      ),
      footer: (context) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text(
          localize('Page ${context.pageNumber} / ${context.pagesCount}'),
          style: const pw.TextStyle(
            fontSize: 9,
            color: PdfColor(0.4, 0.45, 0.5),
          ),
        ),
      ),
      build: (_) => [
        pw.SizedBox(height: 18),
        pw.Text(
          localize(
            reportSettings['title']?.toString().trim().isNotEmpty == true
                ? reportSettings['title'].toString().trim()
                : 'Rapport d’inspection automobile',
          ),
          style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 5),
        pw.Text(
          date == null
              ? ''
              : '${date.day.toString().padLeft(2, '0')}/'
                    '${date.month.toString().padLeft(2, '0')}/${date.year} '
                    '$timeSeparator '
                    '${date.hour.toString().padLeft(2, '0')}:'
                    '${date.minute.toString().padLeft(2, '0')}',
          style: const pw.TextStyle(
            fontSize: 10,
            color: PdfColor(0.35, 0.42, 0.5),
          ),
        ),
        pw.SizedBox(height: 18),
        section('Informations du véhicule'),
        _vehicleTable(vehicle, languageCode),
        pw.SizedBox(height: 18),
        section('Kilométrage'),
        _mileageTable(mileage, languageCode),
        pw.SizedBox(height: 18),
        section('Carrosserie et peinture'),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _bodyDiagram(body, vehiclePhoto),
            pw.SizedBox(width: 20),
            pw.Expanded(child: _bodyLegend(body, languageCode)),
          ],
        ),
        _bodyNotes(body, languageCode),
        pw.SizedBox(height: 20),
        section('Inspection mécanique'),
        _mechanicalSection(mechanical, languageCode),
        pw.SizedBox(height: 18),
        section('État des consommables'),
        _consumablesSection(consumables, languageCode),
        if (inspection['report_photos'] is List<dynamic> &&
            (inspection['report_photos'] as List<dynamic>).isNotEmpty) ...[
          pw.SizedBox(height: 18),
          section('Photographies'),
          pw.Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final photo in inspection['report_photos'] as List<dynamic>)
                if (photo is Map<String, dynamic> &&
                    photo['bytes'] is Uint8List)
                  pw.Container(
                    width: 245,
                    padding: const pw.EdgeInsets.all(7),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(
                        color: const PdfColor.fromInt(0xFFDAE3EC),
                      ),
                      borderRadius: pw.BorderRadius.circular(4),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          photo['zone']?.toString().isNotEmpty == true
                              ? photo['zone'].toString()
                              : localize('Photo d’inspection'),
                          style: pw.TextStyle(
                            fontSize: 8,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.SizedBox(height: 5),
                        pw.SizedBox(
                          height: 125,
                          child: pw.Image(
                            pw.MemoryImage(photo['bytes'] as Uint8List),
                            fit: pw.BoxFit.contain,
                          ),
                        ),
                      ],
                    ),
                  ),
            ],
          ),
        ],
        if ((vehicle['extra_information'] as String? ?? '')
            .trim()
            .isNotEmpty) ...[
          pw.SizedBox(height: 18),
          section('Informations complémentaires'),
          pw.Text(vehicle['extra_information'] as String),
        ],
        pw.SizedBox(height: 20),
        section('Conclusion et recommandation'),
        pw.Text(
          (inspection['conclusion'] as String? ?? '').trim().isEmpty
              ? localize('Aucune conclusion enregistrée.')
              : localize(inspection['conclusion'] as String),
        ),
        if ((inspection['recommendation'] as String? ?? '').trim().isNotEmpty)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 8),
            child: pw.Text(
              '${localize('Recommandation')} : '
              '${localize(inspection['recommendation'] as String)}',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
          ),
        pw.SizedBox(height: 10),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  localize(
                    reportSettings['footer']?.toString().trim().isNotEmpty ==
                            true
                        ? reportSettings['footer'].toString().trim()
                        : '$companyName · Rapport d’inspection automobile',
                  ),
                  style: const pw.TextStyle(fontSize: 8),
                ),
                if (companyContact.isNotEmpty)
                  pw.Text(
                    companyContact,
                    style: const pw.TextStyle(fontSize: 7),
                  ),
              ],
            ),
            if (reportSettings['show_qr'] != false)
              pw.Image(qrCode, width: 46, height: 46),
          ],
        ),
        pw.SizedBox(height: 20),
        pw.Text(
          localize(
            'Ce rapport décrit les constatations relevées au moment de l’examen.',
          ),
          style: const pw.TextStyle(
            fontSize: 9,
            color: PdfColor(0.4, 0.45, 0.5),
          ),
        ),
      ],
    ),
  );
  return document.save();
}

Future<void> openInspectionPdf(Map<String, dynamic> inspection) async {
  final bytes = await buildInspectionPdf(inspection);
  await openInspectionPdfBytes(bytes);
}

Future<void> openInspectionPdfBytes(Uint8List bytes) async {
  await Printing.layoutPdf(onLayout: (_) async => bytes);
}

Future<void> shareInspectionPdfBytes(Uint8List bytes) async {
  await Printing.sharePdf(bytes: bytes, filename: 'rapport-inspection.pdf');
}

pw.Widget _sectionTitle(String title) => pw.Padding(
  padding: const pw.EdgeInsets.only(bottom: 8),
  child: pw.Text(
    title,
    style: pw.TextStyle(
      fontSize: 14,
      fontWeight: pw.FontWeight.bold,
      color: const PdfColor.fromInt(0xFF142C4C),
    ),
  ),
);

pw.Widget _vehicleTable(Map<String, dynamic> vehicle, String languageCode) {
  String localize(String value) =>
      translateText(value, languageCode: languageCode);
  final rows = <List<String>>[
    [localize('Marque'), vehicle['make']?.toString() ?? '—'],
    [localize('Modèle'), vehicle['model']?.toString() ?? '—'],
    [localize('Année'), vehicle['year']?.toString() ?? '—'],
    [
      localize('Immatriculation'),
      vehicle['registration']?.toString().isNotEmpty == true
          ? vehicle['registration'].toString()
          : '—',
    ],
    [localize('VIN / châssis'), vehicle['vin']?.toString() ?? '—'],
    [
      localize('Carburant'),
      vehicle['fuel']?.toString().isNotEmpty == true
          ? vehicle['fuel'].toString()
          : '—',
    ],
    [
      localize('Transmission'),
      vehicle['transmission']?.toString().isNotEmpty == true
          ? vehicle['transmission'].toString()
          : '—',
    ],
  ];
  return pw.TableHelper.fromTextArray(
    data: rows,
    border: pw.TableBorder.all(color: const PdfColor.fromInt(0xFFDAE3EC)),
    cellPadding: const pw.EdgeInsets.symmetric(horizontal: 9, vertical: 6),
    cellStyle: const pw.TextStyle(fontSize: 9),
    columnWidths: {
      0: const pw.FlexColumnWidth(1),
      1: const pw.FlexColumnWidth(2),
    },
    oddRowDecoration: const pw.BoxDecoration(
      color: PdfColor.fromInt(0xFFF7F9FC),
    ),
  );
}

pw.Widget _mileageTable(Map<String, dynamic> mileage, String languageCode) {
  String localize(String value) =>
      translateText(value, languageCode: languageCode);
  String formatMileage(Object? value) =>
      value == null ? '—' : '${value.toString()} km';
  final status = switch (mileage['status']) {
    'real' => localize('Réel'),
    'not_real' => localize('Non réel'),
    _ => localize('À vérifier'),
  };
  return pw.TableHelper.fromTextArray(
    data: [
      [
        localize('Kilométrage affiché au compteur'),
        formatMileage(mileage['displayed']),
      ],
      [localize('Kilométrage réel'), formatMileage(mileage['actual'])],
      [localize('Fiabilité du kilométrage'), status],
    ],
    border: pw.TableBorder.all(color: const PdfColor.fromInt(0xFFDAE3EC)),
    cellPadding: const pw.EdgeInsets.symmetric(horizontal: 9, vertical: 6),
    cellStyle: const pw.TextStyle(fontSize: 9),
    columnWidths: {
      0: const pw.FlexColumnWidth(1),
      1: const pw.FlexColumnWidth(2),
    },
    oddRowDecoration: const pw.BoxDecoration(
      color: PdfColor.fromInt(0xFFF7F9FC),
    ),
  );
}

pw.Widget _bodyDiagram(
  Map<String, dynamic> body,
  pw.MemoryImage vehiclePhoto,
) => pw.SizedBox(
  width: 140,
  height: 210,
  child: pw.Stack(
    children: [
      pw.Positioned.fill(child: pw.Image(vehiclePhoto, fit: pw.BoxFit.contain)),
      for (final zone in _zones)
        pw.Positioned(
          left: zone.left,
          top: zone.top,
          child: pw.Opacity(
            opacity: .4,
            child: pw.Container(
              width: zone.width,
              height: zone.height,
              decoration: pw.BoxDecoration(
                color: _pdfZoneColor(
                  body[zone.key]?['status'] as String? ?? 'Original',
                ),
                borderRadius: pw.BorderRadius.circular(2),
                border: pw.Border.all(
                  color: const PdfColor(1, 1, 1, .7),
                  width: .4,
                ),
              ),
            ),
          ),
        ),
    ],
  ),
);

PdfColor _pdfZoneColor(String status) {
  final color = _states[status] ?? _states['Original']!;
  return PdfColor(
    ((color >> 16) & 0xFF) / 255,
    ((color >> 8) & 0xFF) / 255,
    (color & 0xFF) / 255,
  );
}

pw.Widget _bodyLegend(Map<String, dynamic> body, String languageCode) =>
    pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          translateText('État des zones', languageCode: languageCode),
          style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 8),
        for (final entry in _states.entries)
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 5),
            child: pw.Row(
              children: [
                pw.Container(
                  width: 9,
                  height: 9,
                  color: PdfColor.fromInt(entry.value),
                ),
                pw.SizedBox(width: 6),
                pw.Expanded(
                  child: pw.Text(
                    translateText(entry.key, languageCode: languageCode),
                    style: const pw.TextStyle(fontSize: 8),
                  ),
                ),
              ],
            ),
          ),
        pw.SizedBox(height: 12),
        pw.Text(
          translateText(
            'Zones documentées : ${body.length}',
            languageCode: languageCode,
          ),
          style: const pw.TextStyle(fontSize: 8),
        ),
      ],
    );

pw.Widget _bodyNotes(Map<String, dynamic> body, String languageCode) {
  final annotatedZones = _zones.where((zone) {
    final details = body[zone.key];
    if (details is! Map<String, dynamic>) return false;
    final status = details['status'] as String? ?? 'Original';
    return status != 'Original' ||
        [
          'note',
          'observation',
          'comment',
        ].any((field) => (details[field] as String? ?? '').trim().isNotEmpty);
  });
  if (annotatedZones.isEmpty) return pw.SizedBox();
  return pw.Padding(
    padding: const pw.EdgeInsets.only(top: 12),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          translateText(
            'Observations de carrosserie',
            languageCode: languageCode,
          ),
          style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
        ),
        for (final zone in annotatedZones)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 5),
            child: pw.Text(
              '${translateText(zone.label, languageCode: languageCode)} — '
              '${translateText(body[zone.key]['status']?.toString() ?? 'Original', languageCode: languageCode)}'
              '${_zoneDetails(body[zone.key] as Map<String, dynamic>)}',
              style: const pw.TextStyle(fontSize: 8),
            ),
          ),
      ],
    ),
  );
}

String _zoneDetails(Map<String, dynamic> details) {
  final comments = ['note', 'observation', 'comment']
      .map((field) => details[field] as String? ?? '')
      .where((value) => value.trim().isNotEmpty)
      .toList();
  return comments.isEmpty ? '' : ' · ${comments.join(' · ')}';
}

pw.Widget _mechanicalSection(
  Map<String, dynamic> mechanical,
  String languageCode,
) => pw.Column(
  children: [
    for (final entry in _mechanicalLabels.entries)
      if (mechanical[entry.key] is Map<String, dynamic>)
        _finding(
          entry.value,
          mechanical[entry.key] as Map<String, dynamic>,
          languageCode,
        ),
  ],
);

pw.Widget _consumablesSection(
  Map<String, dynamic> consumables,
  String languageCode,
) => pw.Column(
  children: [
    for (final entry in _consumableLabels.entries)
      _finding(entry.value, {
        'result': consumables[entry.key]?.toString() ?? 'Non évalué',
      }, languageCode),
  ],
);

pw.Widget _finding(
  String title,
  Map<String, dynamic> data,
  String languageCode,
) {
  final details = [
    data['observation']?.toString(),
    data['comment']?.toString(),
  ].where((value) => value != null && value.trim().isNotEmpty).join(' · ');
  final result = data['result']?.toString() ?? 'Non évalué';
  return pw.Container(
    padding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 8),
    decoration: const pw.BoxDecoration(
      border: pw.Border(
        bottom: pw.BorderSide(color: PdfColor.fromInt(0xFFDAE3EC)),
      ),
    ),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(
          width: 125,
          child: pw.Text(
            translateText(title, languageCode: languageCode),
            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
          ),
        ),
        pw.SizedBox(
          width: 88,
          child: pw.Text(
            translateText(result, languageCode: languageCode),
            style: const pw.TextStyle(fontSize: 9),
          ),
        ),
        pw.Expanded(
          child: pw.Text(
            details.isEmpty ? '—' : details,
            style: const pw.TextStyle(fontSize: 8),
          ),
        ),
      ],
    ),
  );
}

class _PdfZone {
  const _PdfZone(
    this.key,
    this.label,
    this.left,
    this.top,
    this.width,
    this.height,
  );

  final String key;
  final String label;
  final double left;
  final double top;
  final double width;
  final double height;
}
