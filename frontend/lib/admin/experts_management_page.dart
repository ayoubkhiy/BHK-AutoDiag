import 'package:material_ui/material_ui.dart' hide Text;

import '../api.dart';
import '../dashboard/dashboard_widgets.dart';
import '../localization.dart' as app;

typedef Text = app.LocalizedText;

class ExpertsManagementPage extends StatefulWidget {
  const ExpertsManagementPage({super.key, required this.client});

  final ApiClient client;

  @override
  State<ExpertsManagementPage> createState() => _ExpertsManagementPageState();
}

class _ExpertsManagementPageState extends State<ExpertsManagementPage> {
  List<Map<String, dynamic>> _experts = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final response = await widget.client.get('experts/');
      if (!mounted) return;
      setState(() {
        _experts = (response['experts'] as List<dynamic>)
            .cast<Map<String, dynamic>>();
        _isLoading = false;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _isLoading = false;
      });
    }
  }

  Future<void> _createExpert() async {
    final formKey = GlobalKey<FormState>();
    final cin = TextEditingController();
    final firstName = TextEditingController();
    final lastName = TextEditingController();
    final password = TextEditingController();
    final values = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Créer un compte expert'),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _dialogField(cin, 'Numéro CIN', required: true),
                _dialogField(firstName, 'Prénom'),
                _dialogField(lastName, 'Nom'),
                _dialogField(
                  password,
                  'Mot de passe temporaire',
                  required: true,
                  obscure: true,
                  minLength: 8,
                ),
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
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(context, {
                  'cin': cin.text.trim(),
                  'first_name': firstName.text.trim(),
                  'last_name': lastName.text.trim(),
                  'password': password.text,
                });
              }
            },
            child: const Text('Créer le compte'),
          ),
        ],
      ),
    );
    cin.dispose();
    firstName.dispose();
    lastName.dispose();
    password.dispose();
    if (values == null) return;
    try {
      await widget.client.post('experts/', values);
      await _load();
      if (mounted) _showMessage('Compte expert créé.');
    } on ApiException catch (error) {
      if (mounted) _showMessage(error.message);
    }
  }

  Future<void> _toggleActive(Map<String, dynamic> expert) async {
    try {
      final id = expert['id'];
      final response = await widget.client.patch('experts/$id/', {
        'active': !(expert['active'] as bool),
      });
      if (!mounted) return;
      setState(() {
        final index = _experts.indexWhere((item) => item['id'] == id);
        _experts[index] = response;
      });
    } on ApiException catch (error) {
      if (mounted) _showMessage(error.message);
    }
  }

  Future<void> _editExpert(Map<String, dynamic> expert) async {
    final formKey = GlobalKey<FormState>();
    final names = (expert['name'] as String).split(' ');
    final firstName = TextEditingController(
      text: names.isEmpty ? '' : names.first,
    );
    final lastName = TextEditingController(
      text: names.length < 2 ? '' : names.skip(1).join(' '),
    );
    final values = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Modifier le compte expert'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _dialogField(firstName, 'Prénom'),
              _dialogField(lastName, 'Nom'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(context, {
                  'first_name': firstName.text.trim(),
                  'last_name': lastName.text.trim(),
                });
              }
            },
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
    firstName.dispose();
    lastName.dispose();
    if (values == null) return;
    try {
      final response = await widget.client.patch(
        'experts/${expert['id']}/',
        values,
      );
      if (!mounted) return;
      setState(() {
        final index = _experts.indexWhere((item) => item['id'] == expert['id']);
        _experts[index] = response;
      });
    } on ApiException catch (error) {
      if (mounted) _showMessage(error.message);
    }
  }

  Future<void> _managePermissions(Map<String, dynamic> expert) async {
    final id = expert['id'];
    try {
      final response = await widget.client.get('experts/$id/permissions/');
      final permissions = (response['permissions'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => _PermissionsDialog(
          permissions: permissions,
          onChanged: (code, enabled) async {
            try {
              final result = await widget.client.put(
                'experts/$id/permissions/',
                {
                  'permissions': {code: enabled},
                },
              );
              return (result['permissions'] as List<dynamic>)
                  .cast<Map<String, dynamic>>();
            } on ApiException catch (error) {
              if (mounted) _showMessage(error.message);
              rethrow;
            }
          },
        ),
      );
    } on ApiException catch (error) {
      if (mounted) _showMessage(error.message);
    }
  }

  Widget _dialogField(
    TextEditingController controller,
    String label, {
    bool required = false,
    bool obscure = false,
    int? minLength,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        obscureText: obscure,
        decoration: InputDecoration(labelText: app.translateText(label)),
        validator: (value) {
          final text = value?.trim() ?? '';
          if (required && text.isEmpty) {
            return app.translateText('Champ obligatoire.');
          }
          if (minLength != null && text.length < minLength) {
            return app.translateText('Minimum $minLength caractères.');
          }
          return null;
        },
      ),
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: DashboardErrorBanner(message: _error!),
        ),
      );
    }
    if (_experts.isEmpty) {
      return DashboardEmptyState(
        icon: Icons.manage_accounts_outlined,
        title: 'Aucun compte expert',
        subtitle: 'Créez un compte, puis définissez ses accès.',
        action: _createExpert,
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${_experts.length} compte${_experts.length > 1 ? 's' : ''}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              FilledButton.icon(
                onPressed: _createExpert,
                icon: const Icon(Icons.person_add_alt_1),
                label: const Text('Ajouter un expert'),
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: ListView.separated(
              padding: const EdgeInsets.all(20),
              itemCount: _experts.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final expert = _experts[index];
                final active = expert['active'] as bool;
                final name = (expert['name'] as String).trim();
                return Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: const Color(0xFFEAF1F7),
                      child: Text(name.isEmpty ? '?' : name[0].toUpperCase()),
                    ),
                    title: Text(
                      expert['name'] as String,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      '${expert['cin']} · ${active ? 'Actif' : 'Désactivé'}',
                    ),
                    trailing: Wrap(
                      spacing: 4,
                      children: [
                        IconButton(
                          tooltip: app.translateText('Modifier le compte'),
                          onPressed: () => _editExpert(expert),
                          icon: const Icon(Icons.edit_outlined),
                        ),
                        IconButton(
                          tooltip: app.translateText('Définir les permissions'),
                          onPressed: () => _managePermissions(expert),
                          icon: const Icon(Icons.tune),
                        ),
                        Switch(
                          value: active,
                          onChanged: (_) => _toggleActive(expert),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _PermissionsDialog extends StatefulWidget {
  const _PermissionsDialog({
    required this.permissions,
    required this.onChanged,
  });

  final List<Map<String, dynamic>> permissions;
  final Future<List<Map<String, dynamic>>> Function(String, bool) onChanged;

  @override
  State<_PermissionsDialog> createState() => _PermissionsDialogState();
}

class _PermissionsDialogState extends State<_PermissionsDialog> {
  late List<Map<String, dynamic>> _permissions = widget.permissions;
  final Set<String> _updating = {};

  Future<void> _setPermission(String code, bool value) async {
    setState(() => _updating.add(code));
    try {
      final updated = await widget.onChanged(code, value);
      if (mounted) setState(() => _permissions = updated);
    } on ApiException {
      if (mounted) setState(() {});
    } finally {
      if (mounted) setState(() => _updating.remove(code));
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Permissions individuelles'),
    content: SizedBox(
      width: 460,
      child: ListView(
        shrinkWrap: true,
        children: [
          for (final permission in _permissions)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(permission['label'] as String),
              value: permission['enabled'] as bool,
              onChanged: _updating.contains(permission['code'])
                  ? null
                  : (value) =>
                        _setPermission(permission['code'] as String, value),
              secondary: _updating.contains(permission['code'])
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : null,
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
  );
}
