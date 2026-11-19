import 'package:material_ui/material_ui.dart' hide Text;

import 'localization.dart' as app;

typedef Text = app.LocalizedText;

String _localized(String value) => app.translateText(value);

class LoginCredentials {
  const LoginCredentials({required this.cin, required this.password});

  final String cin;
  final String password;
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, this.onLogin});

  final Future<void> Function(LoginCredentials credentials)? onLogin;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _cinController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isPasswordVisible = false;
  bool _rememberMe = false;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _cinController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    if (!_formKey.currentState!.validate()) return;

    final credentials = LoginCredentials(
      cin: _cinController.text.trim(),
      password: _passwordController.text,
    );

    final onLogin = widget.onLogin;
    if (onLogin != null) {
      setState(() => _isSubmitting = true);
      try {
        await onLogin(credentials);
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(content: Text(error.toString())));
        }
      } finally {
        if (mounted) setState(() => _isSubmitting = false);
      }
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text(
            'L’authentification n’est pas encore reliée au serveur.',
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 860;

          return Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFF4F7FB), Color(0xFFEAF0F7)],
              ),
            ),
            child: SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(isWide ? 32 : 20),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1120),
                    child: isWide
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              const Expanded(child: _BrandPanel()),
                              const SizedBox(width: 28),
                              Expanded(child: _buildLoginCard()),
                            ],
                          )
                        : Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const _CompactBrand(),
                              const SizedBox(height: 24),
                              _buildLoginCard(),
                            ],
                          ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildLoginCard() {
    return Card(
      color: Colors.white,
      elevation: 3,
      shadowColor: const Color(0x1A142C4C),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 34),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Bienvenue',
                style: TextStyle(
                  color: Color(0xFF142C4C),
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Connectez-vous à votre espace professionnel.',
                style: TextStyle(color: Colors.blueGrey.shade600, fontSize: 15),
              ),
              const SizedBox(height: 30),
              const _FieldLabel('Numéro CIN'),
              const SizedBox(height: 8),
              TextFormField(
                key: const Key('cin-field'),
                controller: _cinController,
                keyboardType: TextInputType.text,
                textCapitalization: TextCapitalization.characters,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.username],
                decoration: _inputDecoration(
                  hint: 'Saisissez votre numéro CIN',
                  icon: Icons.badge_outlined,
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return _localized('Veuillez saisir votre numéro CIN.');
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),
              const _FieldLabel('Mot de passe'),
              const SizedBox(height: 8),
              TextFormField(
                key: const Key('password-field'),
                controller: _passwordController,
                obscureText: !_isPasswordVisible,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.password],
                onFieldSubmitted: (_) => _submit(),
                decoration: _inputDecoration(
                  hint: 'Saisissez votre mot de passe',
                  icon: Icons.lock_outline,
                  suffix: IconButton(
                    tooltip: _isPasswordVisible
                        ? _localized('Masquer le mot de passe')
                        : _localized('Afficher le mot de passe'),
                    onPressed: () {
                      setState(() {
                        _isPasswordVisible = !_isPasswordVisible;
                      });
                    },
                    icon: Icon(
                      _isPasswordVisible
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                    ),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return _localized('Veuillez saisir votre mot de passe.');
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              CheckboxListTile(
                key: const Key('remember-me'),
                value: _rememberMe,
                onChanged: (value) {
                  setState(() {
                    _rememberMe = value ?? false;
                  });
                },
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                dense: true,
                activeColor: const Color(0xFF2D86B7),
                title: Text(
                  'Se souvenir de moi',
                  style: TextStyle(
                    color: Colors.blueGrey.shade700,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: FilledButton.icon(
                  key: const Key('login-submit'),
                  onPressed: _isSubmitting ? null : _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF142C4C),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: _isSubmitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.login_rounded, size: 20),
                  label: Text(
                    _isSubmitting ? 'Connexion…' : 'Se connecter',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 22),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.verified_user_outlined,
                    size: 17,
                    color: Colors.blueGrey.shade500,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'Accès réservé au personnel autorisé',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.blueGrey.shade500,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String hint,
    required IconData icon,
    Widget? suffix,
  }) {
    return InputDecoration(
      hintText: _localized(hint),
      prefixIcon: Icon(icon, color: const Color(0xFF6D849B)),
      suffixIcon: suffix,
      filled: true,
      fillColor: const Color(0xFFF7F9FC),
      contentPadding: const EdgeInsets.symmetric(vertical: 17, horizontal: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: const BorderSide(color: Color(0xFFDCE4ED)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: const BorderSide(color: Color(0xFFDCE4ED)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: const BorderSide(color: Color(0xFF2D86B7), width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: const BorderSide(color: Color(0xFFB3261E)),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: const BorderSide(color: Color(0xFFB3261E), width: 1.5),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        color: Color(0xFF263B52),
        fontSize: 14,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _CompactBrand extends StatelessWidget {
  const _CompactBrand();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _LogoBadge(size: 66),
        const SizedBox(width: 14),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'BHK',
                style: TextStyle(
                  color: Color(0xFF142C4C),
                  fontSize: 21,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                'DIAGNOSTIC AUTOMOBILE',
                style: TextStyle(
                  color: Color(0xFF55718B),
                  fontSize: 11,
                  letterSpacing: 1.1,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BrandPanel extends StatelessWidget {
  const _BrandPanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 610,
      padding: const EdgeInsets.all(42),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF142C4C), Color(0xFF203F62)],
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x24142C4C),
            blurRadius: 28,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _LogoBadge(size: 158),
          const Spacer(),
          const Text(
            'La précision au service de votre automobile.',
            style: TextStyle(
              color: Colors.white,
              fontSize: 32,
              height: 1.25,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Retrouvez votre espace de travail et suivez vos activités de diagnostic en toute simplicité.',
            style: TextStyle(
              color: Color(0xFFD3DFEA),
              fontSize: 15,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 32),
          const Row(
            children: [
              _FeatureChip(icon: Icons.speed_outlined, label: 'Diagnostic'),
              SizedBox(width: 10),
              _FeatureChip(icon: Icons.build_outlined, label: 'Expertise'),
            ],
          ),
          const Spacer(),
          const Text(
            'BHK • DIAGNOSTIC AUTOMOBILE',
            style: TextStyle(
              color: Color(0xFFB7C8D9),
              fontSize: 11,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _LogoBadge extends StatelessWidget {
  const _LogoBadge({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Image.asset('assets/logoo.png', fit: BoxFit.contain),
    );
  }
}

class _FeatureChip extends StatelessWidget {
  const _FeatureChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0x1FFFFFFF),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: const Color(0x35FFFFFF)),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF91C8E5), size: 17),
          const SizedBox(width: 7),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
