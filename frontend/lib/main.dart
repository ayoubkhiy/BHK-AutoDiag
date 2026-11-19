import 'package:material_ui/material_ui.dart';

import 'api.dart';
import 'dashboard.dart';
import 'login.dart';
import 'localization.dart';
import 'splach.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Locale>(
      valueListenable: appLocale,
      builder: (context, locale, _) => MaterialApp(
        title: 'BHK Diagnostic Automobile',
        locale: locale,
        supportedLocales: const [Locale('fr'), Locale('en'), Locale('ar')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF142C4C),
            primary: const Color(0xFF142C4C),
            secondary: const Color(0xFF2D86B7),
          ),
          scaffoldBackgroundColor: const Color(0xFFF4F7FA),
          appBarTheme: const AppBarTheme(
            backgroundColor: Colors.white,
            foregroundColor: Color(0xFF142C4C),
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 1,
            titleTextStyle: TextStyle(
              color: Color(0xFF142C4C),
              fontFamily: 'Cairo',
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          cardTheme: CardThemeData(
            color: Colors.white,
            elevation: 0,
            margin: const EdgeInsets.symmetric(vertical: 6),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: const BorderSide(color: Color(0xFFE6ECF2)),
            ),
          ),
          inputDecorationTheme: const InputDecorationTheme(
            filled: true,
            fillColor: Colors.white,
            contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(12)),
              borderSide: BorderSide(color: Color(0xFFDCE4ED)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(12)),
              borderSide: BorderSide(color: Color(0xFFDCE4ED)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(12)),
              borderSide: BorderSide(color: Color(0xFF2D86B7), width: 1.5),
            ),
          ),
          filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 46),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              textStyle: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          outlinedButtonTheme: OutlinedButtonThemeData(
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF142C4C),
              minimumSize: const Size(0, 44),
              side: const BorderSide(color: Color(0xFFD5E0EA)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              textStyle: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          floatingActionButtonTheme: FloatingActionButtonThemeData(
            backgroundColor: const Color(0xFF2D86B7),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          snackBarTheme: const SnackBarThemeData(
            behavior: SnackBarBehavior.floating,
            backgroundColor: Color(0xFF142C4C),
            contentTextStyle: TextStyle(
              color: Colors.white,
              fontFamily: 'Cairo',
            ),
          ),
          navigationBarTheme: const NavigationBarThemeData(
            backgroundColor: Colors.white,
            indicatorColor: Color(0xFFE7F0F6),
            elevation: 4,
            surfaceTintColor: Colors.transparent,
          ),
          fontFamily: 'Cairo',
          useMaterial3: true,
        ),
        home: const _AppEntry(),
      ),
    );
  }
}

class _AppEntry extends StatelessWidget {
  const _AppEntry();

  @override
  Widget build(BuildContext context) => SplashPage(
    onContinue: () => Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (loginContext) => LoginPage(
          onLogin: (credentials) async {
            final client = ApiClient();
            final response = await client.post('login/', {
              'cin': credentials.cin,
              'password': credentials.password,
            });
            client.token = response['token'] as String;
            final userData = response['user'] as Map<String, dynamic>;
            appLocale.value = Locale(switch (userData['language']) {
              'ar' => 'ar',
              'en' => 'en',
              _ => 'fr',
            });
            final user = ApiUser.fromJson(userData);
            if (!loginContext.mounted) return;
            await Navigator.of(loginContext).pushReplacement(
              MaterialPageRoute<void>(
                builder: (_) => BhkDashboard(client: client, user: user),
              ),
            );
          },
        ),
      ),
    ),
  );
}
