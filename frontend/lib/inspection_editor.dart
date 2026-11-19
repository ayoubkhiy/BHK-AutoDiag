import 'dart:async';

import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart' hide Text;

import 'api.dart';
import 'inspection_report.dart';
import 'localization.dart' as app;

typedef Text = app.LocalizedText;

String _localized(String value) => app.translateText(value);

const _bodyStates = [
  'Original',
  'Peinture',
  'Mastic / réparation',
  'Défaut',
  'Accident / dommage',
];
const _bodyStateColors = {
  'Original': Color(0xFF2E8B57),
  'Peinture': Color(0xFF3187B8),
  'Mastic / réparation': Color(0xFFF0A52B),
  'Défaut': Color(0xFFB05AA6),
  'Accident / dommage': Color(0xFFD94A45),
};

const _mechanicalPoints = <String, String>{
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

const _consumablePoints = <String, String>{
  'tyres': 'Pneus',
  'pads': 'Plaquettes',
  'discs': 'Disques',
  'battery': 'Batterie',
  'fluids': 'Liquides',
  'other': 'Autres éléments',
};

const _inspectionZones = <String, String>{
  'front_bumper': 'Pare-chocs avant',
  'hood': 'Capot',
  'front_left_fender': 'Aile avant gauche',
  'front_right_fender': 'Aile avant droite',
  'windshield': 'Pare-brise',
  'left_front_door': 'Porte avant gauche',
  'roof': 'Toit',
  'right_front_door': 'Porte avant droite',
  'left_rear_door': 'Porte arrière gauche',
  'rear_window': 'Lunette arrière',
  'right_rear_door': 'Porte arrière droite',
  'left_rocker': 'Bas de caisse gauche',
  'right_rocker': 'Bas de caisse droit',
  'rear_left_fender': 'Aile arrière gauche',
  'rear_right_fender': 'Aile arrière droite',
  'trunk': 'Coffre',
  'rear_bumper': 'Pare-chocs arrière',
  'pillars': 'Montants',
};

class InspectionEditorPage extends StatefulWidget {
  const InspectionEditorPage({
    super.key,
    required this.client,
    required this.canEdit,
    required this.canAddPhotos,
    this.initialData,
    this.canFinish = false,
    this.canViewReport = false,
  });

  final ApiClient client;
  final bool canEdit;
  final bool canAddPhotos;
  final bool canFinish;
  final bool canViewReport;
  final Map<String, dynamic>? initialData;

  @override
  State<InspectionEditorPage> createState() => _InspectionEditorPageState();
}

class _InspectionEditorPageState extends State<InspectionEditorPage> {
  final _formKey = GlobalKey<FormState>();
  final _picker = ImagePicker();
  late final Map<String, TextEditingController> _vehicle;
  late Map<String, Map<String, dynamic>> _body;
  late Map<String, Map<String, dynamic>> _mechanical;
  late Map<String, String> _consumables;
  late final TextEditingController _conclusion;
  late final TextEditingController _recommendation;
  late final TextEditingController _customerPrice;
  late final TextEditingController _displayedMileage;
  late final TextEditingController _actualMileage;
  final Map<String, List<XFile>> _pendingPhotos = {};
  String? _selectedZone;
  String _mileageStatus = 'unknown';
  bool _paidOnline = false;
  bool _isSaving = false;
  bool _isGeneratingReport = false;
  late Map<String, dynamic>? _savedInspection;
  List<String> _conclusionLabels = [];

  bool get _isCompleted => _savedInspection?['status'] == 'completed';
  bool get _canChange => widget.canEdit && !_isCompleted;
  bool get _canAttachPhotos => widget.canAddPhotos && !_isCompleted;
  bool get _hasPendingPhotos =>
      _pendingPhotos.values.any((photos) => photos.isNotEmpty);

  @override
  void initState() {
    super.initState();
    _savedInspection = widget.initialData;
    final initialVehicle =
        widget.initialData?['vehicle'] as Map<String, dynamic>? ?? {};
    final initialMileage =
        widget.initialData?['mileage'] as Map<String, dynamic>? ?? {};
    _vehicle = {
      'make': _controller(initialVehicle['make']),
      'model': _controller(initialVehicle['model']),
      'year': _controller(initialVehicle['year']),
      'registration': _controller(initialVehicle['registration']),
      'vin': _controller(initialVehicle['vin']),
      'fuel': _controller(initialVehicle['fuel']),
      'transmission': _controller(initialVehicle['transmission']),
      'extra_information': _controller(initialVehicle['extra_information']),
    };
    _displayedMileage = _controller(
      initialMileage['displayed'] ?? initialVehicle['mileage'],
    );
    _actualMileage = _controller(initialMileage['actual']);
    _mileageStatus = initialMileage['status'] as String? ?? 'unknown';
    _body = _mapOfMaps(widget.initialData?['body_inspection']);
    _mechanical = _mapOfMaps(widget.initialData?['mechanical_inspection']);
    _conclusion = _controller(widget.initialData?['conclusion']);
    _recommendation = _controller(widget.initialData?['recommendation']);
    _customerPrice = _controller(widget.initialData?['customer_price']);
    final savedConsumables = widget.initialData?['consumables'];
    _consumables = savedConsumables is Map<String, dynamic>
        ? savedConsumables.map((key, value) => MapEntry(key, value.toString()))
        : {};
    if (widget.canViewReport) unawaited(_loadConclusionLabels());
  }

  Future<void> _loadConclusionLabels() async {
    try {
      final response = await widget.client.get('report-settings/');
      final settings = response['settings'] as Map<String, dynamic>;
      final conclusions = settings['conclusions'];
      final labels = conclusions is Map<String, dynamic>
          ? conclusions['labels']
          : null;
      if (mounted && labels is List) {
        setState(
          () => _conclusionLabels = labels
              .whereType<String>()
              .where((label) => label.trim().isNotEmpty)
              .toList(),
        );
      }
    } on ApiException catch (error) {
      if (mounted) _showReportError(error.message);
    } on TypeError {
      if (mounted) {
        _showReportError('Les paramètres reçus du serveur sont invalides.');
      }
    }
  }

  TextEditingController _controller(Object? value) =>
      TextEditingController(text: value?.toString() ?? '');

  Map<String, Map<String, dynamic>> _mapOfMaps(Object? value) {
    if (value is! Map<String, dynamic>) return {};
    return value.map((key, item) {
      if (item is Map<String, dynamic>) return MapEntry(key, item);
      return MapEntry(key, <String, dynamic>{});
    });
  }

  @override
  void dispose() {
    for (final controller in _vehicle.values) {
      controller.dispose();
    }
    _conclusion.dispose();
    _recommendation.dispose();
    _customerPrice.dispose();
    _displayedMileage.dispose();
    _actualMileage.dispose();
    super.dispose();
  }

  Future<void> _editBodyZone(String zone) async {
    final current = _body[zone] ?? <String, dynamic>{};
    var status = current['status'] as String? ?? 'Original';
    final note = TextEditingController(text: current['note'] as String? ?? '');
    final observation = TextEditingController(
      text: current['observation'] as String? ?? '',
    );
    final comment = TextEditingController(
      text: current['comment'] as String? ?? '',
    );
    final selectedPhotos = List<XFile>.of(_pendingPhotos[zone] ?? []);
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(_inspectionZones[zone]!),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: status,
                    decoration: InputDecoration(labelText: _localized('État')),
                    items: [
                      for (final item in _bodyStates)
                        DropdownMenuItem(value: item, child: Text(item)),
                    ],
                    onChanged: _canChange
                        ? (value) {
                            if (value != null) {
                              setDialogState(() => status = value);
                            }
                          }
                        : null,
                  ),
                  const SizedBox(height: 12),
                  _textField(note, 'Note', enabled: _canChange),
                  _textField(
                    observation,
                    'Observation',
                    enabled: _canChange,
                    maxLines: 2,
                  ),
                  _textField(
                    comment,
                    'Commentaire',
                    enabled: _canChange,
                    maxLines: 2,
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _canAttachPhotos
                        ? () async {
                            final images = await _pickImages();
                            setDialogState(() => selectedPhotos.addAll(images));
                          }
                        : null,
                    icon: const Icon(Icons.add_a_photo_outlined),
                    label: Text('${selectedPhotos.length} photo(s) ajoutée(s)'),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: _canChange || _canAttachPhotos
                  ? () => Navigator.pop(context, true)
                  : () => Navigator.pop(context, false),
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
    if (saved == true && mounted) {
      setState(() {
        if (_canChange) {
          _body[zone] = {
            'status': status,
            'note': note.text.trim(),
            'observation': observation.text.trim(),
            'comment': comment.text.trim(),
          };
        }
        if (_canAttachPhotos && selectedPhotos.isNotEmpty) {
          _pendingPhotos[zone] = selectedPhotos;
        }
        _selectedZone = zone;
      });
    }
    note.dispose();
    observation.dispose();
    comment.dispose();
  }

  Future<void> _editMechanicalPoint(String key, String title) async {
    final current = _mechanical[key] ?? <String, dynamic>{};
    final observation = TextEditingController(
      text: current['observation'] as String? ?? '',
    );
    final comment = TextEditingController(
      text: current['comment'] as String? ?? '',
    );
    final selectedPhotos = List<XFile>.of(
      _pendingPhotos['mechanical_$key'] ?? [],
    );
    var result = current['result'] as String? ?? 'À contrôler';
    var importance = current['importance'] as String? ?? 'Normal';
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: result,
                    decoration: InputDecoration(
                      labelText: _localized('Résultat'),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'À contrôler',
                        child: Text('À contrôler'),
                      ),
                      DropdownMenuItem(value: 'Bon', child: Text('Bon')),
                      DropdownMenuItem(value: 'Moyen', child: Text('Moyen')),
                      DropdownMenuItem(
                        value: 'À réparer',
                        child: Text('À réparer'),
                      ),
                      DropdownMenuItem(value: 'Défaut', child: Text('Défaut')),
                    ],
                    onChanged: _canChange
                        ? (value) {
                            if (value != null) {
                              setDialogState(() => result = value);
                            }
                          }
                        : null,
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: importance,
                    decoration: InputDecoration(
                      labelText: _localized('Niveau d’importance'),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'Normal', child: Text('Normal')),
                      DropdownMenuItem(
                        value: 'À surveiller',
                        child: Text('À surveiller'),
                      ),
                      DropdownMenuItem(
                        value: 'Important',
                        child: Text('Important'),
                      ),
                    ],
                    onChanged: _canChange
                        ? (value) {
                            if (value != null) {
                              setDialogState(() => importance = value);
                            }
                          }
                        : null,
                  ),
                  const SizedBox(height: 12),
                  _textField(
                    observation,
                    'Observation',
                    enabled: _canChange,
                    maxLines: 3,
                  ),
                  _textField(
                    comment,
                    'Commentaire',
                    enabled: _canChange,
                    maxLines: 2,
                  ),
                  OutlinedButton.icon(
                    onPressed: _canAttachPhotos
                        ? () async {
                            final images = await _pickImages();
                            setDialogState(() => selectedPhotos.addAll(images));
                          }
                        : null,
                    icon: const Icon(Icons.add_a_photo_outlined),
                    label: Text('${selectedPhotos.length} photo(s) ajoutée(s)'),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: _canChange || _canAttachPhotos
                  ? () => Navigator.pop(context, true)
                  : () => Navigator.pop(context, false),
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
    if (saved == true && mounted) {
      setState(() {
        if (_canChange) {
          _mechanical[key] = {
            'result': result,
            'importance': importance,
            'observation': observation.text.trim(),
            'comment': comment.text.trim(),
          };
        }
        if (_canAttachPhotos && selectedPhotos.isNotEmpty) {
          _pendingPhotos['mechanical_$key'] = selectedPhotos;
        }
      });
    }
    observation.dispose();
    comment.dispose();
  }

  Future<void> _chooseConsumablePhoto(String key) async {
    final images = await _pickImages();
    if (images.isEmpty || !mounted || !_canAttachPhotos) return;
    setState(() {
      _pendingPhotos['consumable_$key'] = [
        ...?_pendingPhotos['consumable_$key'],
        ...images,
      ];
    });
  }

  Future<List<XFile>> _pickImages() async {
    try {
      return await _picker.pickMultiImage(imageQuality: 85);
    } on PlatformException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error.message ?? 'Impossible de sélectionner les photos.',
            ),
          ),
        );
      }
      return [];
    }
  }

  Future<void> _save({bool finish = false}) async {
    if (!_canChange && !finish && !_hasPendingPhotos) return;
    if (_canChange && !_formKey.currentState!.validate()) return;
    final customerPrice = finish && !_paidOnline
        ? double.tryParse(_customerPrice.text.trim())
        : null;
    if (finish &&
        !_paidOnline &&
        (customerPrice == null ||
            !customerPrice.isFinite ||
            customerPrice < 0 ||
            customerPrice > 99999999.99)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Saisissez un prix client valide (0 à 99 999 999,99).'),
        ),
      );
      return;
    }
    setState(() => _isSaving = true);
    try {
      var inspection = _savedInspection;
      if (_canChange) {
        final vehicle = <String, dynamic>{
          for (final entry in _vehicle.entries)
            entry.key: entry.value.text.trim(),
        };
        vehicle['year'] = int.parse(vehicle['year'] as String);
        final displayedMileage = _displayedMileage.text.trim();
        final actualMileage = _actualMileage.text.trim();
        final payload = {
          'vehicle': vehicle,
          'mileage': {
            'displayed': displayedMileage.isEmpty
                ? null
                : int.parse(displayedMileage),
            'actual': actualMileage.isEmpty ? null : int.parse(actualMileage),
            'status': _mileageStatus,
          },
          'body_inspection': _body,
          'mechanical_inspection': _mechanical,
          'consumables': _consumables,
          'conclusion': _conclusion.text.trim(),
          'recommendation': _recommendation.text.trim(),
        };
        final id = inspection?['id'];
        final response = id == null
            ? await widget.client.post('inspections/', payload)
            : await widget.client.patch('inspections/$id/', payload);
        inspection = response;
      }
      if (_hasPendingPhotos) {
        final inspectionId = inspection?['id'] as int?;
        if (inspectionId == null) {
          throw const ApiException(
            'Enregistrez l’inspection avant d’ajouter des photos.',
          );
        }
        for (final entry in Map<String, List<XFile>>.of(
          _pendingPhotos,
        ).entries) {
          for (final image in List<XFile>.of(entry.value)) {
            await widget.client.uploadPhoto(
              inspectionId: inspectionId,
              zone: entry.key,
              name: image.name,
              bytes: await image.readAsBytes(),
            );
            if (mounted) {
              setState(() {
                _pendingPhotos[entry.key]?.remove(image);
                if (_pendingPhotos[entry.key]?.isEmpty == true) {
                  _pendingPhotos.remove(entry.key);
                }
              });
            }
          }
        }
      }
      if (finish) {
        final id = inspection?['id'];
        if (id == null) {
          throw const ApiException(
            'Enregistrez l’inspection avant de la terminer.',
          );
        }
        inspection = await widget.client.post('inspections/$id/finish/', {
          'paid_online': _paidOnline,
          if (!_paidOnline) 'customer_price': customerPrice!.toStringAsFixed(2),
        });
      }
      if (!mounted) return;
      setState(() {
        _savedInspection = inspection;
        _pendingPhotos.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            finish ? 'Inspection terminée.' : 'Inspection enregistrée.',
          ),
        ),
      );
      Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    } on FormatException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Vérifiez l’année et le kilométrage.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _openReport() async {
    try {
      await openInspectionPdfBytes(await _generateReportWithProgress());
    } on ApiException catch (error) {
      _showReportError(error.message);
    } on PlatformException catch (error) {
      _showReportError(
        error.message ?? 'Impossible d’ouvrir le rapport sur cet appareil.',
      );
    } on MissingPluginException {
      _showReportError(
        'L’ouverture des PDF n’est pas disponible sur cet appareil.',
      );
    }
  }

  Future<void> _shareReport() async {
    try {
      await shareInspectionPdfBytes(await _generateReportWithProgress());
    } on ApiException catch (error) {
      _showReportError(error.message);
    } on PlatformException catch (error) {
      _showReportError(
        error.message ?? 'Impossible de partager le rapport sur cet appareil.',
      );
    } on MissingPluginException {
      _showReportError(
        'Le partage de PDF n’est pas disponible sur cet appareil.',
      );
    }
  }

  Future<Uint8List> _generateReportWithProgress() async {
    if (_isGeneratingReport) {
      throw const ApiException('Le rapport est déjà en cours de génération.');
    }
    setState(() => _isGeneratingReport = true);
    unawaited(
      showDialog<void>(
        context: context,
        useRootNavigator: true,
        barrierDismissible: false,
        builder: (_) => PopScope(
          canPop: false,
          child: AlertDialog(
            title: const Text('Génération du rapport'),
            content: Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                CircularProgressIndicator(),
                SizedBox(width: 16),
                Flexible(
                  child: Text(
                    'Veuillez patienter, le rapport est en cours de génération…',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    try {
      await Future<void>.delayed(Duration.zero);
      return await _generateAndArchiveReport();
    } finally {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        setState(() => _isGeneratingReport = false);
      }
    }
  }

  Future<Uint8List> _generateAndArchiveReport() async {
    final id = _savedInspection?['id'];
    if (id is! int) {
      throw const ApiException(
        'Enregistrez l’inspection avant de générer le PDF.',
      );
    }
    final report = await widget.client.get('inspections/$id/report/');
    final photos = report['photos'] as List<dynamic>? ?? [];
    final pdfPhotos = <Map<String, dynamic>>[];
    for (final photo in photos) {
      if (photo is Map<String, dynamic> && photo['url'] is String) {
        pdfPhotos.add({
          'zone': photo['zone']?.toString() ?? '',
          'bytes': await widget.client.getBytes(photo['url'] as String),
        });
      }
    }
    report['report_photos'] = pdfPhotos;
    final settingsResponse = await widget.client.get('report-settings/');
    final reportSettings = Map<String, dynamic>.from(
      settingsResponse['settings'] as Map<String, dynamic>,
    )..['language'] = 'fr';
    report['settings'] = reportSettings;
    final bytes = await buildInspectionPdf(report, settings: reportSettings);
    await widget.client.uploadReport(inspectionId: id, bytes: bytes);
    return bytes;
  }

  Future<void> _showReportVersions() async {
    final id = _savedInspection?['id'];
    if (id is! int) return;
    try {
      final response = await widget.client.get('inspections/$id/reports/');
      final versions = (response['reports'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Versions archivées du rapport'),
          content: SizedBox(
            width: 420,
            height: 360,
            child: versions.isEmpty
                ? const Text('Aucun rapport archivé.')
                : ListView(
                    shrinkWrap: true,
                    children: [
                      for (final version in versions)
                        ListTile(
                          leading: const Icon(Icons.picture_as_pdf_outlined),
                          title: Text('Version ${version['version']}'),
                          subtitle: Text(version['created_at'] as String),
                          onTap: () {
                            Navigator.pop(context);
                            _openArchivedReport(version);
                          },
                        ),
                    ],
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Fermer'),
            ),
          ],
        ),
      );
    } on ApiException catch (error) {
      _showReportError(error.message);
    }
  }

  Future<void> _openArchivedReport(Map<String, dynamic> version) async {
    try {
      final bytes = await widget.client.getBytes(version['url'] as String);
      await openInspectionPdfBytes(bytes);
    } on ApiException catch (error) {
      _showReportError(error.message);
    } on PlatformException catch (error) {
      _showReportError(
        error.message ?? 'Impossible d’ouvrir cette version du rapport.',
      );
    } on MissingPluginException {
      _showReportError(
        'L’ouverture des PDF n’est pas disponible sur cet appareil.',
      );
    }
  }

  void _showReportError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final reference = _savedInspection?['reference'] as String?;
    return Scaffold(
      appBar: AppBar(
        title: Text(reference ?? 'Nouvelle inspection'),
        actions: [
          if (widget.canViewReport && _savedInspection != null)
            IconButton(
              tooltip: _localized('Versions archivées'),
              onPressed: _showReportVersions,
              icon: const Icon(Icons.history),
            ),
          if (widget.canViewReport && _savedInspection != null)
            IconButton(
              tooltip: _localized('Ouvrir le rapport PDF'),
              onPressed: _isGeneratingReport ? null : _openReport,
              icon: const Icon(Icons.picture_as_pdf_outlined),
            ),
          if (widget.canViewReport && _savedInspection != null)
            IconButton(
              tooltip: _localized('Partager le rapport PDF'),
              onPressed: _isGeneratingReport ? null : _shareReport,
              icon: const Icon(Icons.share_outlined),
            ),
          if (_canChange || (_canAttachPhotos && _hasPendingPhotos))
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FilledButton.icon(
                onPressed: _isSaving ? null : () => _save(),
                icon: const Icon(Icons.save_outlined),
                label: const Text('Enregistrer'),
              ),
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1180),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
              children: [
                if (reference != null) _referenceBanner(reference),
                _sectionTitle('Informations du véhicule', Icons.directions_car),
                _vehicleCard(),
                const SizedBox(height: 18),
                _sectionTitle('Kilométrage', Icons.speed_outlined),
                _mileageCard(),
                const SizedBox(height: 18),
                _sectionTitle(
                  'Carrosserie et peinture',
                  Icons.car_crash_outlined,
                ),
                _bodyCard(),
                const SizedBox(height: 18),
                _sectionTitle('Inspection mécanique', Icons.handyman_outlined),
                _mechanicalCard(),
                const SizedBox(height: 18),
                _sectionTitle(
                  'État des consommables',
                  Icons.build_circle_outlined,
                ),
                _consumablesCard(),
                const SizedBox(height: 18),
                if (widget.canFinish && !_isCompleted) ...[
                  _sectionTitle(
                    'Montant reçu du client',
                    Icons.payments_outlined,
                  ),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        children: [
                          if (!_paidOnline)
                            TextFormField(
                              key: const Key('customer-price-field'),
                              controller: _customerPrice,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                  RegExp(r'^\d*\.?\d{0,2}'),
                                ),
                              ],
                              decoration: InputDecoration(
                                labelText: _localized(
                                  'Prix de la prestation (DH)',
                                ),
                                prefixIcon: const Icon(Icons.payments_outlined),
                                helperText: _localized(
                                  'Ce montant ne sera pas affiché dans le rapport PDF.',
                                ),
                              ),
                            ),
                          CheckboxListTile(
                            key: const Key('paid-online-checkbox'),
                            contentPadding: EdgeInsets.zero,
                            value: _paidOnline,
                            title: Text(
                              _localized(
                                'Le client a déjà payé en ligne par carte',
                              ),
                            ),
                            controlAffinity: ListTileControlAffinity.leading,
                            onChanged: _canChange
                                ? (value) => setState(
                                    () => _paidOnline = value ?? false,
                                  )
                                : null,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                ],
                _sectionTitle(
                  'Conclusion et recommandation',
                  Icons.fact_check_outlined,
                ),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      children: [
                        _textField(
                          _conclusion,
                          'Conclusion générale',
                          maxLines: 4,
                        ),
                        if (_conclusionLabels.isNotEmpty)
                          Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              children: [
                                for (final label in _conclusionLabels)
                                  ChoiceChip(
                                    label: Text(label),
                                    selected: _conclusion.text == label,
                                    onSelected: !_canChange
                                        ? null
                                        : (selected) {
                                            if (selected) {
                                              setState(
                                                () => _conclusion.text = label,
                                              );
                                            }
                                          },
                                  ),
                              ],
                            ),
                          ),
                        _textField(
                          _recommendation,
                          'Recommandation finale',
                          maxLines: 4,
                        ),
                      ],
                    ),
                  ),
                ),
                if ((_savedInspection?['photos'] as List<dynamic>?)
                        ?.isNotEmpty ==
                    true) ...[
                  const SizedBox(height: 18),
                  _sectionTitle(
                    'Photos de l’inspection',
                    Icons.photo_library_outlined,
                  ),
                  _photoGallery(),
                ],
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: widget.canFinish && !_isCompleted
          ? SafeArea(
              minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: FilledButton.icon(
                onPressed: _isSaving ? null : () => _save(finish: true),
                icon: const Icon(Icons.task_alt),
                label: const Text('Enregistrer et terminer l’inspection'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                ),
              ),
            )
          : null,
    );
  }

  Widget _referenceBanner(String reference) => Card(
    color: const Color(0xFFEAF1F7),
    child: ListTile(
      leading: const Icon(Icons.tag, color: Color(0xFF142C4C)),
      title: Text(
        reference,
        style: const TextStyle(
          color: Color(0xFF142C4C),
          fontWeight: FontWeight.w700,
        ),
      ),
      subtitle: Text(
        _formatDateTime(_savedInspection?['created_at'] as String?),
      ),
      trailing: Chip(
        label: Text(_isCompleted ? 'Terminée' : 'En cours'),
        avatar: Icon(
          _isCompleted ? Icons.check_circle_outline : Icons.pending_outlined,
          size: 18,
        ),
      ),
    ),
  );

  Widget _sectionTitle(String title, IconData icon) => Padding(
    padding: const EdgeInsets.only(bottom: 10, top: 8),
    child: Row(
      children: [
        Icon(icon, color: const Color(0xFF2D86B7)),
        const SizedBox(width: 10),
        Text(title, style: Theme.of(context).textTheme.titleLarge),
      ],
    ),
  );

  String _formatDateTime(String? value) {
    final date = DateTime.tryParse(value ?? '')?.toLocal();
    if (date == null) return '';
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    final separator = switch (app.appLocale.value.languageCode) {
      'ar' => 'في',
      'en' => 'at',
      _ => 'à',
    };
    return '$day/$month/${date.year} $separator $hour:$minute';
  }

  Widget _vehicleCard() => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 680 ? 2 : 1;
          final gap = 12.0;
          final fieldWidth =
              (constraints.maxWidth - gap * (columns - 1)) / columns;
          final fields = <Widget>[
            _requiredField('make', 'Marque'),
            _requiredField('model', 'Modèle'),
            _requiredField(
              'year',
              'Année',
              numeric: true,
              validator: _validateYear,
            ),
            _requiredField('vin', 'VIN / numéro de châssis'),
            _textField(
              _vehicle['registration']!,
              'Immatriculation (facultative)',
            ),
            _textField(_vehicle['fuel']!, 'Type de carburant'),
            _textField(_vehicle['transmission']!, 'Transmission'),
          ];
          return Wrap(
            spacing: gap,
            runSpacing: 4,
            children: [
              for (final field in fields)
                SizedBox(width: fieldWidth, child: field),
              SizedBox(
                width: constraints.maxWidth,
                child: _textField(
                  _vehicle['extra_information']!,
                  'Informations complémentaires (facultatif)',
                  maxLines: 3,
                ),
              ),
            ],
          );
        },
      ),
    ),
  );

  Widget _mileageCard() => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        children: [
          _textField(
            _displayedMileage,
            'Kilométrage affiché au compteur',
            key: const Key('displayed-mileage-field'),
            numeric: true,
            validator: _validateMileage,
          ),
          _textField(
            _actualMileage,
            'Kilométrage réel',
            key: const Key('actual-mileage-field'),
            numeric: true,
            validator: _validateMileage,
          ),
          DropdownButtonFormField<String>(
            initialValue: _mileageStatus,
            decoration: InputDecoration(
              labelText: _localized('Fiabilité du kilométrage'),
            ),
            items: const [
              DropdownMenuItem(value: 'real', child: Text('Réel')),
              DropdownMenuItem(value: 'not_real', child: Text('Non réel')),
              DropdownMenuItem(value: 'unknown', child: Text('À vérifier')),
            ],
            onChanged: _canChange
                ? (value) {
                    if (value != null) {
                      setState(() => _mileageStatus = value);
                    }
                  }
                : null,
          ),
        ],
      ),
    ),
  );

  String? _validateMileage(String? value) {
    if (value == null || value.isEmpty) return null;
    final number = int.tryParse(value);
    return number == null || number < 0
        ? _localized('Saisissez un kilométrage valide.')
        : null;
  }

  String? _validateYear(String? value) {
    if (value == null || value.isEmpty) {
      return _localized('Champ obligatoire.');
    }
    final year = int.tryParse(value);
    final currentYear = DateTime.now().year + 1;
    if (year == null || year < 1886 || year > currentYear) {
      return _localized('Saisissez une année valide.');
    }
    return null;
  }

  Widget _requiredField(
    String key,
    String label, {
    bool numeric = false,
    String? Function(String?)? validator,
  }) {
    final controller = _vehicle[key]!;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        readOnly: !_canChange,
        keyboardType: numeric ? TextInputType.number : TextInputType.text,
        inputFormatters: numeric
            ? [FilteringTextInputFormatter.digitsOnly]
            : null,
        textCapitalization: TextCapitalization.characters,
        decoration: InputDecoration(labelText: _localized(label)),
        validator:
            validator ??
            (value) => value == null || value.trim().isEmpty
                ? _localized('Champ obligatoire.')
                : null,
      ),
    );
  }

  Widget _textField(
    TextEditingController controller,
    String label, {
    bool enabled = true,
    bool numeric = false,
    int maxLines = 1,
    Key? key,
    String? Function(String?)? validator,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      key: key,
      controller: controller,
      readOnly: !enabled || !_canChange,
      keyboardType: numeric ? TextInputType.number : TextInputType.text,
      inputFormatters: numeric
          ? [FilteringTextInputFormatter.digitsOnly]
          : null,
      maxLines: maxLines,
      decoration: InputDecoration(labelText: _localized(label)),
      validator: validator,
    ),
  );

  Widget _bodyCard() => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Touchez une zone du véhicule pour documenter son état.',
            style: TextStyle(color: Color(0xFF5F7182)),
          ),
          const SizedBox(height: 14),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: AspectRatio(
                aspectRatio: 2 / 3,
                child: LayoutBuilder(
                  builder: (context, constraints) => GestureDetector(
                    key: const Key('vehicle-body-diagram'),
                    onTapDown: _canChange || _canAttachPhotos
                        ? (details) {
                            final selected = _zoneAt(
                              details.localPosition.dx / constraints.maxWidth,
                              details.localPosition.dy / constraints.maxHeight,
                            );
                            if (selected != null) _editBodyZone(selected);
                          }
                        : null,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.asset(
                          'assets/voiture.png',
                          key: const Key('vehicle-car-photo'),
                          fit: BoxFit.contain,
                        ),
                        CustomPaint(
                          painter: _VehiclePainter(
                            body: _body,
                            selected: _selectedZone,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              for (final entry in _bodyStateColors.entries)
                _LegendItem(color: entry.value, label: entry.key),
            ],
          ),
        ],
      ),
    ),
  );

  String? _zoneAt(double x, double y) {
    for (final zone in _schematicZones.reversed) {
      if (zone.shape.contains(Offset(x, y))) return zone.key;
    }
    return null;
  }

  Widget _mechanicalCard() => Card(
    child: Column(
      children: [
        for (final entry in _mechanicalPoints.entries)
          ListTile(
            leading: CircleAvatar(
              backgroundColor: const Color(0xFFEAF1F7),
              child: Icon(
                Icons.build_outlined,
                size: 19,
                color: _resultColor(
                  _mechanical[entry.key]?['result'] as String? ?? 'À contrôler',
                ),
              ),
            ),
            title: Text(entry.value),
            subtitle: Text(
              _mechanical[entry.key]?['result'] as String? ?? 'À contrôler',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _editMechanicalPoint(entry.key, entry.value),
          ),
      ],
    ),
  );

  Color _resultColor(String value) => switch (value) {
    'Bon' => const Color(0xFF2E8B57),
    'Moyen' => const Color(0xFFF0A52B),
    'À réparer' || 'Défaut' => const Color(0xFFD94A45),
    _ => const Color(0xFF7A91A6),
  };

  Widget _consumablesCard() => Card(
    child: Column(
      children: [
        for (final entry in _consumablePoints.entries)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                Expanded(child: Text(entry.value)),
                SizedBox(
                  width: 175,
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: _consumables[entry.key] ?? 'Non évalué',
                    decoration: const InputDecoration(isDense: true),
                    items: const [
                      DropdownMenuItem(
                        value: 'Non évalué',
                        child: Text('Non évalué'),
                      ),
                      DropdownMenuItem(value: 'Bon', child: Text('Bon')),
                      DropdownMenuItem(value: 'Moyen', child: Text('Moyen')),
                      DropdownMenuItem(
                        value: 'À remplacer',
                        child: Text('À remplacer'),
                      ),
                    ],
                    onChanged: _canChange
                        ? (value) {
                            if (value != null) {
                              setState(() => _consumables[entry.key] = value);
                            }
                          }
                        : null,
                  ),
                ),
                IconButton(
                  tooltip: _localized(
                    '${_pendingPhotos['consumable_${entry.key}']?.length ?? 0} photo(s)',
                  ),
                  onPressed: _canAttachPhotos
                      ? () => _chooseConsumablePhoto(entry.key)
                      : null,
                  icon: const Icon(Icons.add_a_photo_outlined),
                ),
              ],
            ),
          ),
        const SizedBox(height: 8),
      ],
    ),
  );

  Widget _photoGallery() {
    final photos = (_savedInspection?['photos'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    return SizedBox(
      height: 148,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: photos.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final photo = photos[index];
          return SizedBox(
            width: 190,
            child: Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Image.network(
                      widget.client.photoUri(photo['url'] as String).toString(),
                      headers: widget.client.photoHeaders,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const Center(
                        child: Icon(Icons.broken_image_outlined),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(
                      (photo['zone'] as String).replaceAll('_', ' '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 11,
        height: 11,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 5),
      Text(label, style: const TextStyle(fontSize: 12)),
    ],
  );
}

class _SchematicZone {
  const _SchematicZone(this.key, this.shape);

  final String key;
  final Path shape;
}

Path _roundedPanel(double left, double top, double right, double bottom) {
  const radius = .014;
  return Path()
    ..moveTo(left + radius, top)
    ..lineTo(right - radius, top)
    ..quadraticBezierTo(right, top, right, top + radius)
    ..lineTo(right, bottom - radius)
    ..quadraticBezierTo(right, bottom, right - radius, bottom)
    ..lineTo(left + radius, bottom)
    ..quadraticBezierTo(left, bottom, left, bottom - radius)
    ..lineTo(left, top + radius)
    ..quadraticBezierTo(left, top, left + radius, top)
    ..close();
}

Path _frontFender(bool left) {
  final path = Path()
    ..moveTo(.27, .08)
    ..cubicTo(.22, .10, .17, .17, .16, .25)
    ..quadraticBezierTo(.21, .29, .30, .28)
    ..lineTo(.32, .12)
    ..quadraticBezierTo(.30, .09, .27, .08)
    ..close();
  if (left) return path;
  return Path()
    ..moveTo(.73, .08)
    ..cubicTo(.78, .10, .83, .17, .84, .25)
    ..quadraticBezierTo(.79, .29, .70, .28)
    ..lineTo(.68, .12)
    ..quadraticBezierTo(.70, .09, .73, .08)
    ..close();
}

Path _rearFender(bool left) {
  final path = Path()
    ..moveTo(.30, .73)
    ..quadraticBezierTo(.21, .72, .16, .77)
    ..cubicTo(.17, .85, .22, .92, .28, .94)
    ..quadraticBezierTo(.31, .92, .32, .87)
    ..close();
  if (left) return path;
  return Path()
    ..moveTo(.70, .73)
    ..quadraticBezierTo(.79, .72, .84, .77)
    ..cubicTo(.83, .85, .78, .92, .72, .94)
    ..quadraticBezierTo(.69, .92, .68, .87)
    ..close();
}

final _schematicZones = <_SchematicZone>[
  _SchematicZone('front_bumper', _roundedPanel(.31, .005, .69, .045)),
  _SchematicZone('hood', _roundedPanel(.27, .045, .73, .245)),
  _SchematicZone('front_left_fender', _frontFender(true)),
  _SchematicZone('front_right_fender', _frontFender(false)),
  _SchematicZone('windshield', _roundedPanel(.26, .245, .74, .40)),
  _SchematicZone('left_front_door', _roundedPanel(.205, .415, .30, .535)),
  _SchematicZone('right_front_door', _roundedPanel(.70, .415, .795, .535)),
  _SchematicZone('roof', _roundedPanel(.29, .405, .71, .70)),
  _SchematicZone('left_rear_door', _roundedPanel(.205, .545, .30, .69)),
  _SchematicZone('right_rear_door', _roundedPanel(.70, .545, .795, .69)),
  _SchematicZone('rear_window', _roundedPanel(.28, .70, .72, .835)),
  _SchematicZone('left_rocker', _roundedPanel(.16, .405, .20, .72)),
  _SchematicZone('right_rocker', _roundedPanel(.80, .405, .84, .72)),
  _SchematicZone('rear_left_fender', _rearFender(true)),
  _SchematicZone('rear_right_fender', _rearFender(false)),
  _SchematicZone('trunk', _roundedPanel(.28, .84, .72, .95)),
  _SchematicZone('rear_bumper', _roundedPanel(.32, .955, .68, .995)),
  _SchematicZone(
    'pillars',
    Path()
      ..addPath(_roundedPanel(.28, .39, .72, .415), Offset.zero)
      ..addPath(_roundedPanel(.28, .69, .72, .715), Offset.zero),
  ),
];

class _VehiclePainter extends CustomPainter {
  _VehiclePainter({required this.body, required this.selected});

  final Map<String, Map<String, dynamic>> body;
  final String? selected;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width, size.height);
    for (final zone in _schematicZones) {
      final status = body[zone.key]?['status'] as String? ?? 'Original';
      final color = _bodyStateColors[status] ?? const Color(0xFF91A2B0);
      final fill = Paint()
        ..color = color.withValues(
          alpha: zone.key == selected
              ? .48
              : status == 'Original'
              ? .26
              : .42,
        );
      canvas.drawPath(zone.shape, fill);
      canvas.drawPath(
        zone.shape,
        Paint()
          ..color = const Color(0xBFFFFFFF)
          ..style = PaintingStyle.stroke
          ..strokeWidth = .0025,
      );
      if (zone.key == selected) {
        canvas.drawPath(
          zone.shape,
          Paint()
            ..color = const Color(0xFF142C4C)
            ..style = PaintingStyle.stroke
            ..strokeWidth = .006,
        );
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _VehiclePainter oldDelegate) =>
      oldDelegate.selected != selected || oldDelegate.body != body;
}
