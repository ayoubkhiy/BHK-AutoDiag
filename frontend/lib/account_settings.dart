import 'package:material_ui/material_ui.dart' hide Text;

import 'api.dart';
import 'localization.dart' as app;

typedef Text = app.LocalizedText;

class AccountSettingsPage extends StatefulWidget {
  const AccountSettingsPage({
    super.key,
    required this.client,
    required this.user,
  });

  final ApiClient client;
  final ApiUser user;

  @override
  State<AccountSettingsPage> createState() => _AccountSettingsPageState();
}

class _AccountSettingsPageState extends State<AccountSettingsPage> {
  final _passwordFormKey = GlobalKey<FormState>();
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  late String _language;
  bool _isSavingLanguage = false;
  bool _isSavingPassword = false;
  bool _showCurrentPassword = false;
  bool _showNewPassword = false;
  bool _showConfirmPassword = false;

  String _localized(String value) => app.translateText(value);

  @override
  void initState() {
    super.initState();
    final currentLanguage = app.appLocale.value.languageCode;
    _language = const {'fr', 'en', 'ar'}.contains(currentLanguage)
        ? currentLanguage
        : 'fr';
  }

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _saveLanguage(String language) async {
    final previousLocale = app.appLocale.value;
    setState(() {
      _isSavingLanguage = true;
      _language = language;
    });
    app.appLocale.value = Locale(language);
    try {
      await widget.client.put('account/preferences/', {'language': language});
      if (mounted) _showMessage('Langue enregistrée.');
    } on ApiException catch (error) {
      app.appLocale.value = previousLocale;
      if (mounted) {
        setState(() => _language = previousLocale.languageCode);
        _showMessage(error.message);
      }
    } finally {
      if (mounted) setState(() => _isSavingLanguage = false);
    }
  }

  Future<void> _changePassword() async {
    if (!_passwordFormKey.currentState!.validate()) return;
    setState(() => _isSavingPassword = true);
    try {
      await widget.client.post('account/password/', {
        'current_password': _currentPasswordController.text,
        'new_password': _newPasswordController.text,
        'confirm_password': _confirmPasswordController.text,
      });
      if (!mounted) return;
      _currentPasswordController.clear();
      _newPasswordController.clear();
      _confirmPasswordController.clear();
      _showMessage('Mot de passe mis à jour avec succès.');
    } on ApiException catch (error) {
      if (mounted) _showMessage(error.message);
    } finally {
      if (mounted) setState(() => _isSavingPassword = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _passwordField({
    required String label,
    required TextEditingController controller,
    required bool obscureText,
    required VoidCallback onToggleVisibility,
    required String? Function(String?) validator,
    Iterable<String>? autofillHints,
    Key? key,
  }) => TextFormField(
    key: key,
    controller: controller,
    obscureText: obscureText,
    autofillHints: autofillHints ?? const [AutofillHints.newPassword],
    decoration: InputDecoration(
      labelText: _localized(label),
      suffixIcon: IconButton(
        tooltip: _localized(
          obscureText ? 'Afficher le mot de passe' : 'Masquer le mot de passe',
        ),
        onPressed: onToggleVisibility,
        icon: Icon(
          obscureText
              ? Icons.visibility_outlined
              : Icons.visibility_off_outlined,
        ),
      ),
    ),
    validator: validator,
  );

  Widget _profileCard() => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Profil',
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          _profileRow(Icons.person_outline, 'Nom complet', widget.user.name),
          const Divider(height: 20),
          _profileRow(Icons.badge_outlined, 'Numéro CIN', widget.user.cin),
          const Divider(height: 20),
          _profileRow(
            Icons.verified_user_outlined,
            'Type de compte',
            widget.user.isAdmin ? 'Administrateur' : 'Expert',
          ),
        ],
      ),
    ),
  );

  Widget _profileRow(IconData icon, String label, String value) => Row(
    children: [
      Icon(icon, color: const Color(0xFF2D86B7)),
      const SizedBox(width: 12),
      Expanded(child: Text(label)),
      const SizedBox(width: 8),
      Flexible(
        child: Text(
          value,
          textAlign: TextAlign.end,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Paramètres du compte')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _profileCard(),
            const SizedBox(height: 10),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Préférences',
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      key: const Key('account-language'),
                      initialValue: _language,
                      decoration: InputDecoration(
                        labelText: _localized('Langue de l’application'),
                        prefixIcon: const Icon(Icons.language),
                      ),
                      items: [
                        for (final (code, label) in const [
                          ('fr', 'Français'),
                          ('en', 'Anglais'),
                          ('ar', 'العربية'),
                        ])
                          DropdownMenuItem(value: code, child: Text(label)),
                      ],
                      onChanged: _isSavingLanguage
                          ? null
                          : (value) async {
                              if (value != null) await _saveLanguage(value);
                            },
                    ),
                    if (_isSavingLanguage)
                      const Padding(
                        padding: EdgeInsets.only(top: 12),
                        child: LinearProgressIndicator(),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Form(
                  key: _passwordFormKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Sécurité du compte',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Modifier le mot de passe',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 14),
                      _passwordField(
                        key: const Key('current-password'),
                        label: 'Mot de passe actuel',
                        controller: _currentPasswordController,
                        obscureText: !_showCurrentPassword,
                        autofillHints: const [AutofillHints.password],
                        onToggleVisibility: () => setState(
                          () => _showCurrentPassword = !_showCurrentPassword,
                        ),
                        validator: (value) => value == null || value.isEmpty
                            ? _localized(
                                'Le mot de passe actuel est obligatoire.',
                              )
                            : null,
                      ),
                      const SizedBox(height: 12),
                      _passwordField(
                        key: const Key('new-password'),
                        label: 'Nouveau mot de passe',
                        controller: _newPasswordController,
                        obscureText: !_showNewPassword,
                        onToggleVisibility: () => setState(
                          () => _showNewPassword = !_showNewPassword,
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return _localized(
                              'Le nouveau mot de passe est obligatoire.',
                            );
                          }
                          if (value.length < 8) {
                            return _localized(
                              'Le mot de passe doit contenir au moins 8 caractères.',
                            );
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      _passwordField(
                        key: const Key('confirm-password'),
                        label: 'Confirmer le nouveau mot de passe',
                        controller: _confirmPasswordController,
                        obscureText: !_showConfirmPassword,
                        onToggleVisibility: () => setState(
                          () => _showConfirmPassword = !_showConfirmPassword,
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return _localized(
                              'Confirmez votre nouveau mot de passe.',
                            );
                          }
                          if (value != _newPasswordController.text) {
                            return _localized(
                              'Les mots de passe ne correspondent pas.',
                            );
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          key: const Key('change-password'),
                          onPressed: _isSavingPassword ? null : _changePassword,
                          icon: _isSavingPassword
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.lock_reset),
                          label: const Text('Changer le mot de passe'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Les autres sessions seront déconnectées après le changement.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
