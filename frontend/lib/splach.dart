import 'dart:async';

import 'package:material_ui/material_ui.dart' hide Text;

import 'localization.dart' as app;
import 'login.dart';

typedef Text = app.LocalizedText;

class SplashPage extends StatefulWidget {
  const SplashPage({
    super.key,
    this.transitionDelay = const Duration(seconds: 3),
    this.onContinue,
  });

  final Duration transitionDelay;
  final VoidCallback? onContinue;

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animationController;
  late final Animation<double> _fadeAnimation;
  Timer? _navigationTimer;
  bool _isNavigating = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
    );
    _animationController.forward();
    _navigationTimer = Timer(widget.transitionDelay, _openLogin);
  }

  @override
  void dispose() {
    _navigationTimer?.cancel();
    _animationController.dispose();
    super.dispose();
  }

  void _openLogin() {
    if (!mounted || _isNavigating) return;
    _isNavigating = true;
    final onContinue = widget.onContinue;
    if (onContinue != null) {
      onContinue();
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const LoginPage()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF10243D), Color(0xFF1B3B5D)],
              ),
            ),
          ),
          const Positioned(
            top: -150,
            right: -110,
            child: _GlowCircle(size: 370, opacity: 0.08),
          ),
          const Positioned(
            bottom: -180,
            left: -120,
            child: _GlowCircle(size: 420, opacity: 0.06),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 184,
                          height: 184,
                          padding: const EdgeInsets.all(15),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(34),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x332D86B7),
                                blurRadius: 38,
                                spreadRadius: 4,
                              ),
                            ],
                          ),
                          child: Image.asset(
                            'assets/logoo.png',
                            fit: BoxFit.contain,
                          ),
                        ),
                        const SizedBox(height: 34),
                        const Text(
                          'BHK',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 38,
                            height: 1.1,
                            letterSpacing: 4,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 5),
                        const Text(
                          'DIAGNOSTIC AUTOMOBILE',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Color(0xFFB7D7EA),
                            fontSize: 13,
                            letterSpacing: 2.1,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 27),
                        Container(
                          width: 42,
                          height: 3,
                          decoration: BoxDecoration(
                            color: const Color(0xFF55B5E4),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          'L’expertise automobile, en toute confiance.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Color(0xFFE7EFF6),
                            fontSize: 16,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 48),
                        const SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Color(0xFF72C8EE),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          'Préparation de votre espace…',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.72),
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 20),
                        TextButton(
                          onPressed: _openLogin,
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Continuer'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const Positioned(
            bottom: 20,
            left: 16,
            right: 16,
            child: Text(
              'DIAGNOSTIC  •  EXPERTISE  •  CONFIANCE',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFFB7C8D9),
                fontSize: 10,
                letterSpacing: 1.6,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GlowCircle extends StatelessWidget {
  const _GlowCircle({required this.size, required this.opacity});

  final double size;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF65B9E3).withValues(alpha: opacity),
      ),
    );
  }
}
