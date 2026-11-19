import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart' hide Text;

import 'api.dart';
import 'inspection_editor.dart';
import 'inspection_report.dart';
import 'localization.dart' as app;

typedef Text = app.LocalizedText;

enum OperationsModule { finance, listings, notifications, settings }

const _applicationVersion = '1.0.0';

class OperationsPage extends StatelessWidget {
  const OperationsPage({super.key, required this.client, required this.user});

  final ApiClient client;
  final ApiUser user;

  @override
  Widget build(BuildContext context) {
    final modules = <(OperationsModule, String, IconData, bool)>[
      (
        OperationsModule.finance,
        user.isAdmin ? 'Finances et commissions' : 'Mes commissions',
        Icons.account_balance_wallet_outlined,
        user.isAdmin ||
            user.permissions['view_personal_commissions'] == true ||
            user.permissions['view_global_finances'] == true,
      ),
      (
        OperationsModule.listings,
        'Véhicules à vendre',
        Icons.directions_car_outlined,
        user.isAdmin ||
            user.permissions['view_listings'] == true ||
            user.permissions['add_listing'] == true,
      ),
      (
        OperationsModule.notifications,
        'Notifications',
        Icons.notifications_none_outlined,
        true,
      ),
      (
        OperationsModule.settings,
        'Paramètres',
        Icons.settings_outlined,
        user.isAdmin || user.permissions['edit_settings'] == true,
      ),
    ];
    final visible = modules.where((item) => item.$4).toList();
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 860),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'Gestion de l’activité',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: const Color(0xFF142C4C),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            for (final (module, title, icon, _) in visible)
              Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 6,
                  ),
                  leading: CircleAvatar(
                    backgroundColor: const Color(0xFFEAF3F8),
                    child: Icon(icon, color: const Color(0xFF2D86B7)),
                  ),
                  title: Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  trailing: const Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 16,
                  ),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => OperationsModulePage(
                        client: client,
                        user: user,
                        module: module,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class OperationsModulePage extends StatefulWidget {
  const OperationsModulePage({
    super.key,
    required this.client,
    required this.user,
    required this.module,
  });

  final ApiClient client;
  final ApiUser user;
  final OperationsModule module;

  @override
  State<OperationsModulePage> createState() => _OperationsModulePageState();
}

class _OperationsModulePageState extends State<OperationsModulePage> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];
  Map<String, dynamic> _summary = {};
  List<Map<String, dynamic>> _expenses = [];
  Map<String, dynamic> _settings = {};
  final _companyName = TextEditingController();
  final _companyAddress = TextEditingController();
  final _companyPhone = TextEditingController();
  final _companyEmail = TextEditingController();
  final _companyWebsite = TextEditingController();
  final _reportTitle = TextEditingController();
  final _reportFooter = TextEditingController();
  final _conclusionLabels = TextEditingController();
  String _logoBase64 = '';
  bool _showQr = true;
  bool _savingSettings = false;
  String _commissionStatus = 'all';

  @override
  void dispose() {
    _companyName.dispose();
    _companyAddress.dispose();
    _companyPhone.dispose();
    _companyEmail.dispose();
    _companyWebsite.dispose();
    _reportTitle.dispose();
    _reportFooter.dispose();
    _conclusionLabels.dispose();
    super.dispose();
  }

  String get _title => switch (widget.module) {
    OperationsModule.finance =>
      widget.user.isAdmin ? 'Finances et commissions' : 'Mes commissions',
    OperationsModule.listings => 'Véhicules à vendre',
    OperationsModule.notifications => 'Notifications',
    OperationsModule.settings => 'Paramètres',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      switch (widget.module) {
        case OperationsModule.finance:
          final response = await widget.client.get('commissions/');
          _items = (response['commissions'] as List<dynamic>)
              .cast<Map<String, dynamic>>();
          if (widget.user.isAdmin) {
            _summary = await widget.client.get('dashboard/');
            final expenseResponse = await widget.client.get('expenses/');
            _expenses = (expenseResponse['expenses'] as List<dynamic>)
                .cast<Map<String, dynamic>>();
          }
        case OperationsModule.listings:
          final response = await widget.client.get('listings/');
          _items = (response['listings'] as List<dynamic>)
              .cast<Map<String, dynamic>>();
        case OperationsModule.notifications:
          final response = await widget.client.get('notifications/');
          _items = (response['notifications'] as List<dynamic>)
              .cast<Map<String, dynamic>>();
        case OperationsModule.settings:
          final response = await widget.client.get('settings/');
          _settings = response['settings'] as Map<String, dynamic>;
          _populateSettingsFields();
      }
      if (mounted) setState(() => _loading = false);
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          _error = error.message;
          _loading = false;
        });
      }
    } on TypeError {
      if (mounted) {
        setState(() {
          _error = 'Les données reçues du serveur sont invalides.';
          _loading = false;
        });
      }
    }
  }

  void _message(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Map<String, dynamic> _settingsCategory(String key) {
    final value = _settings[key];
    return value is Map<String, dynamic> ? value : const {};
  }

  void _populateSettingsFields() {
    final company = _settingsCategory('company');
    final report = _settingsCategory('report');
    final conclusions = _settingsCategory('conclusions');
    _companyName.text = company['name']?.toString() ?? '';
    _companyAddress.text = company['address']?.toString() ?? '';
    _companyPhone.text = company['phone']?.toString() ?? '';
    _companyEmail.text = company['email']?.toString() ?? '';
    _companyWebsite.text = company['website']?.toString() ?? '';
    _reportTitle.text =
        report['title']?.toString() ?? 'Rapport d’inspection automobile';
    _reportFooter.text = report['footer']?.toString() ?? '';
    final labels = conclusions['labels'];
    _conclusionLabels.text = labels is List
        ? labels.map((label) => label.toString()).join('\n')
        : '';
    _logoBase64 = company['logo_base64']?.toString() ?? '';
    _showQr = report['show_qr'] != false;
  }

  Future<void> _pickLogo() async {
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1200,
        maxHeight: 1200,
        imageQuality: 85,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      final isPng =
          bytes.length >= 8 &&
          bytes[0] == 0x89 &&
          bytes[1] == 0x50 &&
          bytes[2] == 0x4E &&
          bytes[3] == 0x47;
      final isJpeg =
          bytes.length >= 3 &&
          bytes[0] == 0xFF &&
          bytes[1] == 0xD8 &&
          bytes[2] == 0xFF;
      if (!isPng && !isJpeg) {
        _message('Choisissez une image PNG ou JPEG.');
        return;
      }
      if (bytes.length > 1536 * 1024) {
        _message('Le logo ne doit pas dépasser 1,5 Mo.');
        return;
      }
      setState(() => _logoBase64 = base64Encode(bytes));
    } on PlatformException catch (error) {
      _message(error.message ?? 'Impossible de charger le logo.');
    }
  }

  Future<void> _saveSettings() async {
    final updatedSettings = Map<String, dynamic>.from(_settings)
      ..addAll({
        'company': {
          'name': _companyName.text.trim(),
          'address': _companyAddress.text.trim(),
          'phone': _companyPhone.text.trim(),
          'email': _companyEmail.text.trim(),
          'website': _companyWebsite.text.trim(),
          'logo_base64': _logoBase64,
        },
        'report': {
          'title': _reportTitle.text.trim(),
          'footer': _reportFooter.text.trim(),
          'show_qr': _showQr,
        },
        'conclusions': {
          'labels': _conclusionLabels.text
              .split('\n')
              .map((label) => label.trim())
              .where((label) => label.isNotEmpty)
              .toList(),
        },
        'application': {'version': _applicationVersion},
      });
    setState(() => _savingSettings = true);
    try {
      await widget.client.put('settings/', {'settings': updatedSettings});
      _message('Paramètres enregistrés.');
      await _load();
    } on ApiException catch (error) {
      if (mounted) _message(error.message);
    } finally {
      if (mounted) setState(() => _savingSettings = false);
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
      if (mounted) await _load();
    } on ApiException catch (error) {
      if (mounted) _message(error.message);
    }
  }

  Future<String?> _inputDialog(
    String title,
    List<(String, String)> fields,
  ) async {
    final controllers = <String, TextEditingController>{
      for (final (key, initial) in fields)
        key: TextEditingController(text: initial),
    };
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (key, _) in fields)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: TextField(
                    controller: controllers[key],
                    decoration: InputDecoration(
                      labelText: app.translateText(key),
                    ),
                    keyboardType:
                        const {
                          'Montant',
                          'Prix',
                          'Kilométrage',
                          'Année',
                        }.contains(key)
                        ? const TextInputType.numberWithOptions(decimal: true)
                        : TextInputType.text,
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, {
              for (final entry in controllers.entries)
                entry.key: entry.value.text.trim(),
            }),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
    for (final controller in controllers.values) {
      controller.dispose();
    }
    return result == null ? null : jsonEncode(result);
  }

  Future<Map<String, String>?> _form(
    String title,
    List<(String, String)> fields,
  ) async {
    final encoded = await _inputDialog(title, fields);
    if (encoded == null) return null;
    return (jsonDecode(encoded) as Map<String, dynamic>).cast<String, String>();
  }

  Future<void> _addExpense() async {
    final data = await _form('Nouvelle dépense', const [
      ('Montant', ''),
      ('Catégorie', ''),
      ('Description', ''),
      ('Date (AAAA-MM-JJ)', ''),
    ]);
    if (data == null) return;
    await _run(() async {
      await widget.client.post('expenses/', {
        'amount': data['Montant'],
        'category': data['Catégorie'],
        'description': data['Description'],
        if (data['Date (AAAA-MM-JJ)']!.isNotEmpty)
          'date': data['Date (AAAA-MM-JJ)'],
      });
    });
  }

  Future<void> _addListing() async {
    final controllers = {
      'Marque': TextEditingController(),
      'Modèle': TextEditingController(),
      'Année': TextEditingController(),
      'Kilométrage': TextEditingController(),
      'Prix': TextEditingController(),
      'Description': TextEditingController(),
    };
    final selectedPhotos = <XFile>[];
    final data = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Ajouter un véhicule'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final entry in controllers.entries)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: TextField(
                        controller: entry.value,
                        keyboardType:
                            const {
                              'Année',
                              'Kilométrage',
                              'Prix',
                            }.contains(entry.key)
                            ? const TextInputType.numberWithOptions(
                                decimal: true,
                              )
                            : TextInputType.text,
                        decoration: InputDecoration(
                          labelText: app.translateText(entry.key),
                        ),
                        maxLines: entry.key == 'Description' ? 3 : 1,
                      ),
                    ),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final photos = await _chooseListingPhotos();
                        if (photos != null && mounted) {
                          setDialogState(() => selectedPhotos.addAll(photos));
                        }
                      },
                      icon: const Icon(Icons.add_photo_alternate_outlined),
                      label: const Text('Ajouter des photos'),
                    ),
                  ),
                  if (selectedPhotos.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        for (
                          var index = 0;
                          index < selectedPhotos.length;
                          index++
                        )
                          InputChip(
                            label: Text(selectedPhotos[index].name),
                            onDeleted: () => setDialogState(
                              () => selectedPhotos.removeAt(index),
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, {
                for (final entry in controllers.entries)
                  entry.key: entry.value.text.trim(),
                'photos': List<XFile>.of(selectedPhotos),
              }),
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
    for (final controller in controllers.values) {
      controller.dispose();
    }
    if (data == null) return;
    final photos = data['photos'] as List<XFile>;
    if (!await _validateListingPhotos(photos)) return;
    try {
      final listing = await widget.client.post('listings/', {
        'make': data['Marque'],
        'model': data['Modèle'],
        'year': int.tryParse(data['Année'] ?? ''),
        'mileage': int.tryParse(data['Kilométrage'] ?? ''),
        'price': data['Prix'],
        'description': data['Description'],
      });
      final listingId = listing['id'];
      if (listingId is! int) {
        throw const ApiException(
          'Les données reçues du serveur sont invalides.',
        );
      }
      await _uploadListingPhotos(listingId, photos);
      if (mounted) {
        _message('Véhicule ajouté à la vente.');
        await _load();
      }
    } on ApiException catch (error) {
      if (mounted) {
        _message(error.message);
        await _load();
      }
    } on PlatformException catch (error) {
      if (mounted) {
        _message(error.message ?? 'Impossible de charger les photos.');
        await _load();
      }
    } on MissingPluginException {
      if (mounted) {
        _message(
          'La sélection des photos n’est pas disponible sur cet appareil.',
        );
        await _load();
      }
    }
  }

  Future<List<XFile>?> _chooseListingPhotos() async {
    try {
      return await ImagePicker().pickMultiImage(
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
      );
    } on PlatformException catch (error) {
      if (mounted) {
        _message(error.message ?? 'Impossible de sélectionner les photos.');
      }
    } on MissingPluginException {
      if (mounted) {
        _message(
          'La sélection des photos n’est pas disponible sur cet appareil.',
        );
      }
    }
    return null;
  }

  Future<bool> _validateListingPhotos(
    List<XFile> photos, {
    int existingCount = 0,
  }) async {
    if (existingCount + photos.length > 10) {
      _message('Une annonce ne peut pas contenir plus de 10 photos.');
      return false;
    }
    for (final photo in photos) {
      final extension = photo.name.split('.').last.toLowerCase();
      if (!{'jpg', 'jpeg', 'png', 'webp'}.contains(extension)) {
        _message('Format accepté : JPEG, PNG ou WebP.');
        return false;
      }
      try {
        if (await photo.length() > 10 * 1024 * 1024) {
          _message('Une photo de 10 Mo maximum est obligatoire.');
          return false;
        }
      } on PlatformException catch (error) {
        _message(error.message ?? 'Impossible de charger les photos.');
        return false;
      } on MissingPluginException {
        _message(
          'La sélection des photos n’est pas disponible sur cet appareil.',
        );
        return false;
      }
    }
    return true;
  }

  Future<void> _uploadListingPhotos(int listingId, List<XFile> photos) async {
    for (final photo in photos) {
      await widget.client.uploadListingPhoto(
        listingId: listingId,
        name: photo.name,
        bytes: await photo.readAsBytes(),
      );
    }
  }

  Future<void> _addListingPhotos(Map<String, dynamic> listing) async {
    final existingCount = (listing['photos'] as List<dynamic>? ?? []).length;
    final photos = await _chooseListingPhotos();
    if (photos == null ||
        photos.isEmpty ||
        !await _validateListingPhotos(photos, existingCount: existingCount)) {
      return;
    }
    try {
      final listingId = listing['id'];
      if (listingId is! int) {
        throw const ApiException(
          'Les données reçues du serveur sont invalides.',
        );
      }
      await _uploadListingPhotos(listingId, photos);
      if (mounted) _message('Photos ajoutées à l’annonce.');
    } on ApiException catch (error) {
      if (mounted) _message(error.message);
    } on PlatformException catch (error) {
      if (mounted) {
        _message(error.message ?? 'Impossible de charger les photos.');
      }
    } on MissingPluginException {
      if (mounted) {
        _message(
          'La sélection des photos n’est pas disponible sur cet appareil.',
        );
      }
    } finally {
      if (mounted) await _load();
    }
  }

  bool _canAddListingPhotos(Map<String, dynamic> listing) =>
      widget.user.isAdmin ||
      (listing['expert_id'] == widget.user.id &&
          widget.user.permissions['add_listing'] == true);

  Future<void> _showListingDetails(Map<String, dynamic> listing) async {
    final photos = (listing['photos'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .toList();
    final extra = listing['extra_information'] is Map<String, dynamic>
        ? listing['extra_information'] as Map<String, dynamic>
        : const <String, dynamic>{};
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${listing['make']} ${listing['model']}'),
        content: SizedBox(
          width: 540,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _listingDetail('Année', '${listing['year']}'),
                _listingDetail(
                  'Kilométrage',
                  '${listing['mileage'] ?? '—'} km',
                ),
                _listingDetail(
                  'Prix',
                  '${listing['price'] ?? 'Prix non défini'} DH',
                ),
                _listingDetail('Statut', _statusLabel(listing['status'] ?? '')),
                _listingDetail(
                  'Expert',
                  listing['expert_name']?.toString() ?? '—',
                ),
                if ((listing['description'] as String? ?? '').isNotEmpty)
                  _listingDetail(
                    'Description',
                    listing['description'] as String,
                  ),
                for (final entry in extra.entries)
                  _listingDetail(entry.key, entry.value.toString()),
                if (photos.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Photos du véhicule',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final photo in photos)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.network(
                            widget.client
                                .photoUri(photo['url'] as String)
                                .toString(),
                            headers: widget.client.photoHeaders,
                            width: 112,
                            height: 88,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => const SizedBox(
                              width: 112,
                              height: 88,
                              child: Icon(Icons.broken_image_outlined),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
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
  }

  Widget _listingDetail(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 135,
          child: Text(
            app.translateText(label),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        Expanded(child: Text(value)),
      ],
    ),
  );

  Future<void> _defineCommission(Map<String, dynamic> commission) async {
    final customerPrice =
        double.tryParse(commission['customer_price']?.toString() ?? '') ?? 0;
    final paidOnline =
        commission['payment_method'] == 'card' &&
        commission['payment_status'] == 'paid';
    var onlinePaymentText =
        commission['online_payment_amount']?.toString() ??
        (customerPrice > 0 ? customerPrice.toStringAsFixed(2) : '');
    var mode = 'fixed';
    var enteredValue = '';
    final data = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final value = double.tryParse(enteredValue.trim());
          final updatedCustomerPrice = paidOnline
              ? double.tryParse(onlinePaymentText.trim())
              : customerPrice;
          final onlinePaymentValid =
              !paidOnline ||
              (updatedCustomerPrice != null &&
                  updatedCustomerPrice.isFinite &&
                  updatedCustomerPrice > 0 &&
                  updatedCustomerPrice <= 99999999.99);
          final effectiveCustomerPrice = updatedCustomerPrice ?? 0;
          final validValue =
              value != null &&
              value.isFinite &&
              value >= 0 &&
              (mode != 'percentage' || value <= 100) &&
              (mode != 'fixed' || value <= effectiveCustomerPrice) &&
              onlinePaymentValid;
          final expertShare = !validValue
              ? null
              : mode == 'fixed'
              ? value
              : effectiveCustomerPrice * value / 100;
          final companyShare = expertShare == null
              ? null
              : effectiveCustomerPrice - expertShare;
          return AlertDialog(
            title: const Text('Définir la commission'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${app.translateText('Prix payé par le client')} : '
                  '${effectiveCustomerPrice.toStringAsFixed(2)} DH',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                if (paidOnline) ...[
                  const SizedBox(height: 8),
                  Text(app.translateText('Paiement par carte déclaré')),
                  const SizedBox(height: 8),
                  TextFormField(
                    key: const Key('admin-customer-price-field'),
                    initialValue: onlinePaymentText,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                        RegExp(r'^\d*\.?\d{0,2}'),
                      ),
                    ],
                    decoration: InputDecoration(
                      labelText: app.translateText('Prix payé en ligne (DH)'),
                      suffixText: 'DH',
                    ),
                    onChanged: (value) => setDialogState(() {
                      onlinePaymentText = value;
                    }),
                  ),
                ],
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: mode,
                  decoration: InputDecoration(
                    labelText: app.translateText('Mode de commission'),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'fixed',
                      child: Text('Montant fixe'),
                    ),
                    DropdownMenuItem(
                      value: 'percentage',
                      child: Text('Pourcentage du prix client'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => mode = value);
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('expert-commission-value-field'),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                      RegExp(r'^\d*\.?\d{0,2}'),
                    ),
                  ],
                  decoration: InputDecoration(
                    labelText: app.translateText(
                      mode == 'fixed'
                          ? 'Part de l’expert (DH)'
                          : 'Part de l’expert (%)',
                    ),
                  ),
                  onChanged: (value) => setDialogState(() {
                    enteredValue = value;
                  }),
                ),
                if (expertShare != null) ...[
                  const SizedBox(height: 14),
                  Text(
                    '${app.translateText('Montant pour l’expert')} : '
                    '${expertShare.toStringAsFixed(2)} DH',
                  ),
                  Text(
                    '${app.translateText('Part de la société')} : '
                    '${companyShare!.toStringAsFixed(2)} DH',
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Annuler'),
              ),
              FilledButton(
                onPressed: validValue
                    ? () => Navigator.pop(context, {
                        'mode': mode,
                        'value': value.toString(),
                        if (paidOnline)
                          'customer_price': updatedCustomerPrice!
                              .toStringAsFixed(2),
                      })
                    : null,
                child: const Text('Enregistrer'),
              ),
            ],
          );
        },
      ),
    );
    if (data == null) return;
    await _run(() async {
      final update = <String, dynamic>{
        'mode': data['mode'],
        'value': data['value'],
      };
      if (data['customer_price'] != null) {
        update['customer_price'] = data['customer_price'];
      }
      await widget.client.patch('commissions/${commission['id']}/', update);
    });
  }

  Future<void> _changeListingStatus(
    Map<String, dynamic> listing,
    String status,
  ) => _run(() async {
    await widget.client.patch('listings/${listing['id']}/', {'status': status});
  });

  Future<void> _markNotificationRead(Map<String, dynamic> notification) =>
      _run(() async {
        await widget.client.patch('notifications/${notification['id']}/', {});
      });

  Future<void> _markAllNotificationsRead() async {
    final unread = _items
        .where((notification) => notification['is_read'] != true)
        .toList();
    try {
      for (final notification in unread) {
        await widget.client.patch(
          'notifications/${notification['id']}/',
          const {},
        );
      }
    } on ApiException catch (error) {
      if (mounted) _message(error.message);
      await _load();
      return;
    }
    await _load();
  }

  Future<void> _openNotification(Map<String, dynamic> notification) async {
    try {
      await widget.client.patch('notifications/${notification['id']}/', {});
      await _load();
    } on ApiException catch (error) {
      if (mounted) _message(error.message);
      return;
    }
    if (!mounted) return;
    final target = notification['target'] as String? ?? '';
    if (target.startsWith('commissions/')) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => OperationsModulePage(
            client: widget.client,
            user: widget.user,
            module: OperationsModule.finance,
          ),
        ),
      );
    } else if (target.startsWith('reports/')) {
      try {
        await openInspectionPdfBytes(await widget.client.getBytes(target));
      } on ApiException catch (error) {
        _message(error.message);
      } on PlatformException catch (error) {
        _message(error.message ?? 'Impossible d’ouvrir le rapport.');
      } on MissingPluginException {
        _message('L’ouverture des PDF n’est pas disponible sur cet appareil.');
      }
    } else if (target.startsWith('inspections/')) {
      final id = int.tryParse(
        target.split('/').where((part) => part.isNotEmpty).last,
      );
      if (id == null) return;
      try {
        final response = await widget.client.get('inspections/');
        if (!mounted) return;
        final inspections = (response['inspections'] as List<dynamic>)
            .cast<Map<String, dynamic>>();
        final inspection = inspections.where((item) => item['id'] == id);
        if (inspection.isEmpty) {
          _message('Cette inspection n’est pas accessible.');
          return;
        }
        final item = inspection.first;
        final completed = item['status'] == 'completed';
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => InspectionEditorPage(
              client: widget.client,
              initialData: item,
              canEdit:
                  !completed &&
                  (widget.user.isAdmin ||
                      widget.user.permissions['edit_inspection'] == true),
              canAddPhotos:
                  !completed &&
                  (widget.user.isAdmin ||
                      widget.user.permissions['add_inspection_photos'] == true),
              canFinish:
                  !completed &&
                  (widget.user.isAdmin ||
                      widget.user.permissions['finish_inspection'] == true),
              canViewReport:
                  widget.user.isAdmin ||
                  widget.user.permissions['view_reports'] == true,
            ),
          ),
        );
      } on ApiException catch (error) {
        _message(error.message);
      }
    } else if (target.startsWith('listings/')) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => OperationsModulePage(
            client: widget.client,
            user: widget.user,
            module: OperationsModule.listings,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_title),
        actions: [
          if (widget.module == OperationsModule.notifications &&
              _items.any((notification) => notification['is_read'] != true))
            IconButton(
              tooltip: app.translateText('Marquer toutes comme lues'),
              onPressed: _markAllNotificationsRead,
              icon: const Icon(Icons.done_all),
            ),
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      floatingActionButton: switch (widget.module) {
        OperationsModule.finance when widget.user.isAdmin =>
          FloatingActionButton.extended(
            onPressed: _addExpense,
            icon: const Icon(Icons.add),
            label: const Text('Dépense'),
          ),
        OperationsModule.listings => FloatingActionButton.extended(
          onPressed: _addListing,
          icon: const Icon(Icons.add),
          label: const Text('Ajouter'),
        ),
        OperationsModule.settings => FloatingActionButton.extended(
          onPressed: _savingSettings ? null : _saveSettings,
          icon: _savingSettings
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_outlined),
          label: const Text('Enregistrer'),
        ),
        _ => null,
      },
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text(_error!, textAlign: TextAlign.center))
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1180),
                child: RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
                    children: _buildContent(),
                  ),
                ),
              ),
            ),
    );
  }

  List<Widget> _buildContent() {
    return switch (widget.module) {
      OperationsModule.finance => _financeContent(),
      OperationsModule.listings => _listingContent(),
      OperationsModule.notifications => _notificationContent(),
      OperationsModule.settings => _settingsContent(),
    };
  }

  List<Widget> _financeContent() {
    final children = <Widget>[];
    final commissions =
        _items
            .where(
              (item) =>
                  _commissionStatus == 'all' ||
                  item['status'] == _commissionStatus,
            )
            .toList()
          ..sort(
            (first, second) =>
                _commissionStatusPriority(
                  first['status'] as String? ?? 'pending',
                ).compareTo(
                  _commissionStatusPriority(
                    second['status'] as String? ?? 'pending',
                  ),
                ),
          );
    if (widget.user.isAdmin) {
      children.add(_financeMetrics());
      children.addAll([
        _section('Dépenses'),
        for (final expense in _expenses)
          ListTile(
            title: Text('${expense['category']} · ${expense['amount']} DH'),
            subtitle: Text(
              '${expense['date']} ${expense['description'] ?? ''}',
            ),
          ),
      ]);
    }
    children.add(_section('Commissions'));
    children.add(
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: DropdownButtonFormField<String>(
          initialValue: _commissionStatus,
          decoration: InputDecoration(
            labelText: app.translateText('Statut'),
            border: const OutlineInputBorder(),
          ),
          items: const [
            DropdownMenuItem(value: 'all', child: Text('Tous')),
            DropdownMenuItem(value: 'pending', child: Text('En attente')),
            DropdownMenuItem(value: 'defined', child: Text('Déterminée')),
            DropdownMenuItem(value: 'validated', child: Text('Validée')),
            DropdownMenuItem(value: 'paid', child: Text('Payée')),
          ],
          onChanged: (value) {
            if (value != null) {
              setState(() => _commissionStatus = value);
            }
          },
        ),
      ),
    );
    for (final item in commissions) {
      final status = item['status'] as String? ?? 'pending';
      final customerPrice =
          double.tryParse(item['customer_price']?.toString() ?? '') ?? 0;
      final expertShare = double.tryParse(item['amount']?.toString() ?? '');
      final companyShare = expertShare == null
          ? null
          : customerPrice - expertShare;
      final vehicleValue = item['vehicle'];
      final vehicle = vehicleValue is Map<String, dynamic>
          ? vehicleValue
          : const <String, dynamic>{};
      final vehicleName = [
        vehicle['make']?.toString(),
        vehicle['model']?.toString(),
      ].where((part) => part != null && part.trim().isNotEmpty).join(' ');
      final vehicleLabel = vehicle['year'] == null
          ? vehicleName
          : '$vehicleName (${vehicle['year']})';
      final registration = vehicle['registration']?.toString().trim() ?? '';
      final paidOnline =
          widget.user.isAdmin &&
          item['payment_method'] == 'card' &&
          item['payment_status'] == 'paid';
      final onlinePaymentAmount = item['online_payment_amount'];
      final details = <String>[
        if (vehicleLabel.isNotEmpty) vehicleLabel,
        if (registration.isNotEmpty)
          '${app.translateText('Immatriculation')} : $registration',
        '${item['expert_name'] ?? 'Mes commissions'} · ${_statusLabel(status)}',
        if (widget.user.isAdmin)
          '${app.translateText('Prix client')} : '
              '${paidOnline && onlinePaymentAmount == null ? app.translateText('Montant en ligne à confirmer') : '${customerPrice.toStringAsFixed(2)} DH'}',
        if (paidOnline) app.translateText('Paiement par carte déclaré'),
        if (expertShare != null)
          '${app.translateText('Part de l’expert')} : ${expertShare.toStringAsFixed(2)} DH',
        if (widget.user.isAdmin && companyShare != null)
          '${app.translateText('Part de la société')} : ${companyShare.toStringAsFixed(2)} DH',
      ];
      children.add(
        Card(
          child: ListTile(
            leading: const Icon(
              Icons.directions_car_outlined,
              color: Color(0xFF2D86B7),
            ),
            title: Text('${item['inspection_reference']}'),
            subtitle: Text(details.join('\n')),
            trailing: widget.user.isAdmin
                ? Wrap(
                    children: [
                      if (status == 'pending' || status == 'defined')
                        IconButton(
                          tooltip: app.translateText('Définir'),
                          onPressed: () => _defineCommission(item),
                          icon: const Icon(Icons.edit_outlined),
                        ),
                      if (status == 'defined')
                        IconButton(
                          tooltip: app.translateText('Valider'),
                          onPressed: () => _run(() async {
                            await widget.client.patch(
                              'commissions/${item['id']}/',
                              {'status': 'validated'},
                            );
                          }),
                          icon: const Icon(Icons.check_circle_outline),
                        ),
                      if (status == 'validated')
                        IconButton(
                          tooltip: app.translateText('Marquer payée'),
                          onPressed: () => _run(() async {
                            await widget.client.patch(
                              'commissions/${item['id']}/',
                              {'status': 'paid'},
                            );
                          }),
                          icon: const Icon(Icons.payments_outlined),
                        ),
                    ],
                  )
                : null,
          ),
        ),
      );
    }
    if (commissions.isEmpty) {
      children.add(const _EmptyText('Aucune commission correspondante.'));
    }
    return children;
  }

  int _commissionStatusPriority(String status) => switch (status) {
    'pending' => 0,
    'defined' => 1,
    'validated' => 2,
    'paid' => 3,
    _ => 4,
  };

  List<Widget> _listingContent() {
    if (_items.isEmpty) return [const _EmptyText('Aucune annonce.')];
    return [
      for (final item in _items)
        Card(
          child: ListTile(
            title: Text('${item['make']} ${item['model']} (${item['year']})'),
            subtitle: Text(
              '${item['price'] ?? 'Prix non défini'} DH · '
              '${_statusLabel(item['status'] as String? ?? '')}',
            ),
            trailing: Wrap(
              children: [
                IconButton(
                  tooltip: app.translateText('Afficher les informations'),
                  onPressed: () => _showListingDetails(item),
                  icon: const Icon(Icons.info_outline),
                ),
                if (_canAddListingPhotos(item))
                  IconButton(
                    tooltip: app.translateText('Ajouter des photos'),
                    onPressed: () => _addListingPhotos(item),
                    icon: const Icon(Icons.add_photo_alternate_outlined),
                  ),
                if (widget.user.isAdmin)
                  PopupMenuButton<String>(
                    onSelected: (status) => _changeListingStatus(item, status),
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'published', child: Text('Publier')),
                      PopupMenuItem(value: 'draft', child: Text('Masquer')),
                      PopupMenuItem(value: 'archived', child: Text('Archiver')),
                    ],
                  ),
              ],
            ),
          ),
        ),
    ];
  }

  List<Widget> _notificationContent() {
    if (_items.isEmpty) return [const _EmptyText('Aucune notification.')];
    return [
      for (final item in _items)
        Card(
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 18,
              vertical: 8,
            ),
            leading: CircleAvatar(
              backgroundColor: item['is_read'] == true
                  ? const Color(0xFFF0F3F6)
                  : const Color(0xFFEAF3F8),
              child: Icon(
                item['is_read'] == true
                    ? Icons.notifications_none
                    : Icons.notifications_active_outlined,
                color: item['is_read'] == true
                    ? const Color(0xFF718096)
                    : const Color(0xFF2D86B7),
              ),
            ),
            title: Text(
              item['title'] as String? ?? '',
              style: TextStyle(
                fontWeight: item['is_read'] == true
                    ? FontWeight.w500
                    : FontWeight.w700,
              ),
            ),
            subtitle: Text(item['message'] as String? ?? ''),
            onTap: () => _openNotification(item),
            trailing: item['is_read'] == true
                ? null
                : IconButton(
                    tooltip: app.translateText('Marquer comme lue'),
                    onPressed: () => _markNotificationRead(item),
                    icon: const Icon(Icons.done),
                  ),
          ),
        ),
    ];
  }

  List<Widget> _settingsContent() {
    return [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _section('Informations de l’entreprise'),
              _settingsField(_companyName, 'Nom de l’entreprise'),
              _settingsField(_companyAddress, 'Adresse'),
              _settingsField(_companyPhone, 'Téléphone'),
              _settingsField(_companyEmail, 'E-mail'),
              _settingsField(_companyWebsite, 'Site web'),
              const SizedBox(height: 12),
              Row(
                children: [
                  if (_logoBase64.isNotEmpty)
                    SizedBox(width: 72, height: 72, child: _logoPreview())
                  else
                    const SizedBox(
                      width: 72,
                      height: 72,
                      child: Icon(Icons.image_outlined, size: 36),
                    ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: _pickLogo,
                    icon: const Icon(Icons.upload_outlined),
                    label: const Text('Choisir un logo'),
                  ),
                  if (_logoBase64.isNotEmpty)
                    IconButton(
                      tooltip: app.translateText('Supprimer le logo'),
                      onPressed: () => setState(() => _logoBase64 = ''),
                      icon: const Icon(Icons.delete_outline),
                    ),
                ],
              ),
              _section('Paramètres du rapport PDF'),
              _settingsField(_reportTitle, 'Titre du rapport'),
              _settingsField(_reportFooter, 'Texte de pied de page'),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Afficher le QR code'),
                value: _showQr,
                onChanged: (value) => setState(() => _showQr = value),
              ),
              _section('Libellés des conclusions'),
              TextField(
                controller: _conclusionLabels,
                minLines: 3,
                maxLines: 7,
                decoration: InputDecoration(
                  labelText: app.translateText('Un libellé par ligne'),
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
      ),
      Card(
        child: ListTile(
          leading: const Icon(Icons.info_outline),
          title: const Text('Version de l’application'),
          subtitle: const Text(_applicationVersion),
        ),
      ),
    ];
  }

  Widget _settingsField(TextEditingController controller, String label) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: app.translateText(label),
            border: const OutlineInputBorder(),
          ),
        ),
      );

  Widget _logoPreview() {
    try {
      return Image.memory(base64Decode(_logoBase64), fit: BoxFit.contain);
    } on FormatException {
      return const Center(child: Text('Logo invalide'));
    }
  }

  Widget _metric(String label, Object? value) => SizedBox(
    width: 190,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value?.toString() ?? '0'),
            Text(label, style: TextStyle(color: Colors.blueGrey.shade600)),
          ],
        ),
      ),
    ),
  );

  Widget _financeMetrics() {
    final metrics = [
      _metric('Chiffre d’affaires', _summary['revenue_total']),
      _metric('Dépenses', _summary['expenses_total']),
      _metric('Commissions', _summary['commissions_total']),
      _metric('Résultat net', _summary['net_result']),
      _metric('Commissions en attente', _summary['commission_pending']),
      _metric('Validées', _summary['commission_validated']),
      _metric('Payées', _summary['commission_paid']),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 620) {
          return SizedBox(
            height: 110,
            child: ListView.separated(
              key: const Key('commission-metrics-horizontal'),
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: metrics.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (_, index) => metrics[index],
            ),
          );
        }
        return Wrap(
          key: const Key('commission-metrics-wrap'),
          spacing: 10,
          runSpacing: 10,
          children: metrics,
        );
      },
    );
  }

  Widget _section(String title) => Padding(
    padding: const EdgeInsets.only(top: 18, bottom: 8),
    child: Text(
      title,
      style: Theme.of(context).textTheme.titleMedium
          ?.copyWith(fontWeight: FontWeight.w700),
    ),
  );

  String _statusLabel(String status) => switch (status) {
    'pending' => 'En attente',
    'defined' => 'Déterminée',
    'validated' => 'Validée',
    'paid' => 'Payée',
    'published' => 'Publiée',
    'draft' => 'Masquée',
    'archived' => 'Archivée',
    _ => status,
  };
}

class _EmptyText extends StatelessWidget {
  const _EmptyText(this.message);

  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Text(message, textAlign: TextAlign.center),
  );
}
