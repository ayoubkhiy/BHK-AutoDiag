import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';

import 'package:frontend/login.dart';
import 'package:frontend/main.dart';
import 'package:frontend/operations.dart';
import 'package:frontend/api.dart';
import 'package:frontend/account_settings.dart';
import 'package:frontend/dashboard.dart';
import 'package:frontend/dashboard/admin_dashboard_page.dart';
import 'package:frontend/dashboard/expert_dashboard_page.dart';
import 'package:frontend/inspection_editor.dart';
import 'package:frontend/inspection_report.dart';
import 'package:frontend/localization.dart' as app;

void main() {
  test('release API URLs require HTTPS except for loopback', () {
    expect(
      isAllowedApiBaseUri(
        Uri.parse('https://api.example.test/api/'),
        releaseBuild: true,
      ),
      isTrue,
    );
    expect(
      isAllowedApiBaseUri(
        Uri.parse('http://api.example.test/api/'),
        releaseBuild: true,
      ),
      isFalse,
    );
    expect(
      isAllowedApiBaseUri(
        Uri.parse('http://localhost:8000/api/'),
        releaseBuild: true,
      ),
      isTrue,
    );
    expect(
      isAllowedApiBaseUri(
        Uri.parse('ftp://api.example.test/api/'),
        releaseBuild: false,
      ),
      isFalse,
    );
  });

  testWidgets('splash page transitions to login', (tester) async {
    app.appLocale.value = const Locale('fr');
    await tester.pumpWidget(const MyApp());
    expect(find.text('DIAGNOSTIC AUTOMOBILE'), findsOneWidget);
    expect(find.text('Préparation de votre espace…'), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();

    expect(find.text('Bienvenue'), findsOneWidget);
  });

  testWidgets('Arabic locale translates the app and enables RTL', (
    tester,
  ) async {
    app.appLocale.value = const Locale('fr');
    addTearDown(() => app.appLocale.value = const Locale('fr'));
    await tester.pumpWidget(const MyApp());
    expect(
      find.text('L’expertise automobile, en toute confiance.'),
      findsOneWidget,
    );

    app.appLocale.value = const Locale('ar');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      app.translateText('L’expertise automobile, en toute confiance.'),
      'خبرة السيارات بكل ثقة.',
    );
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).locale,
      const Locale('ar'),
    );
    final slogan = find.text('خبرة السيارات بكل ثقة.');
    expect(slogan, findsOneWidget);
    expect(Directionality.of(tester.element(slogan)), TextDirection.rtl);
  });

  testWidgets('English locale translates the app and keeps left-to-right', (
    tester,
  ) async {
    app.appLocale.value = const Locale('en');
    addTearDown(() => app.appLocale.value = const Locale('fr'));
    await tester.pumpWidget(const MyApp());
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();

    expect(find.text('Welcome'), findsOneWidget);
    expect(
      app.translateText('Connectez-vous à votre espace professionnel.'),
      'Sign in to your professional workspace.',
    );
    expect(
      Directionality.of(tester.element(find.text('Welcome'))),
      TextDirection.ltr,
    );
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).supportedLocales,
      contains(const Locale('en')),
    );
  });

  testWidgets('expert dashboard stat cards scroll horizontally on mobile', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExpertDashboardPage(
            userName: 'Expert Test',
            inspections: const [],
            dashboard: const {},
            canViewHistory: true,
            canViewPersonalCommissions: false,
            canCreateInspection: false,
            onRefresh: () async {},
            onCreateInspection: () {},
            onViewHistory: () {},
            onManageOperations: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final statList = tester.widget<ListView>(
      find.byKey(const Key('dashboard-stat-horizontal')),
    );
    expect(statList.scrollDirection, Axis.horizontal);
    await tester.drag(
      find.byKey(const Key('dashboard-stat-horizontal')),
      const Offset(-240, 0),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('account settings saves the selected language', (tester) async {
    app.appLocale.value = const Locale('fr');
    addTearDown(() => app.appLocale.value = const Locale('fr'));
    String? savedLanguage;
    final client = ApiClient(
      client: MockClient((request) async {
        savedLanguage =
            (jsonDecode(request.body) as Map<String, dynamic>)['language']
                as String;
        return http.Response('{"language":"en"}', 200);
      }),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: AccountSettingsPage(
          client: client,
          user: const ApiUser(
            id: 1,
            cin: 'CIN-001',
            name: 'Expert Test',
            isAdmin: false,
            permissions: {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('account-language')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Anglais'));
    await tester.pumpAndSettle();

    expect(savedLanguage, 'en');
    expect(app.appLocale.value, const Locale('en'));
    expect(find.text('Account settings'), findsOneWidget);
  });

  testWidgets('account settings submits a confirmed password change', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    app.appLocale.value = const Locale('fr');
    addTearDown(() => app.appLocale.value = const Locale('fr'));
    Map<String, dynamic>? submittedPassword;
    final client = ApiClient(
      client: MockClient((request) async {
        submittedPassword = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response('{"ok":true}', 200);
      }),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: AccountSettingsPage(
          client: client,
          user: const ApiUser(
            id: 1,
            cin: 'CIN-001',
            name: 'Expert Test',
            isAdmin: false,
            permissions: {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('current-password')),
      'test-password',
    );
    await tester.enterText(
      find.byKey(const Key('new-password')),
      'Clear-Skyline-417!New',
    );
    await tester.enterText(
      find.byKey(const Key('confirm-password')),
      'Clear-Skyline-417!New',
    );
    await tester.ensureVisible(find.byKey(const Key('change-password')));
    await tester.tap(find.byKey(const Key('change-password')));
    await tester.pumpAndSettle();

    expect(submittedPassword?['current_password'], 'test-password');
    expect(submittedPassword?['new_password'], 'Clear-Skyline-417!New');
    expect(submittedPassword?['confirm_password'], 'Clear-Skyline-417!New');
    expect(find.text('Mot de passe mis à jour avec succès.'), findsOneWidget);
  });

  testWidgets('login page displays CIN and password fields', (tester) async {
    await _openLogin(tester);

    expect(find.text('Numéro CIN'), findsOneWidget);
    expect(find.text('Mot de passe'), findsOneWidget);
    expect(find.byKey(const Key('login-submit')), findsOneWidget);
  });

  testWidgets(
    'settings page saves structured settings without language control',
    (tester) async {
      addTearDown(() => app.appLocale.value = const Locale('fr'));
      tester.view.physicalSize = const Size(1200, 2200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Map<String, dynamic>? savedSettings;
      final client = ApiClient(
        client: MockClient((request) async {
          if (request.method == 'GET') {
            return http.Response('{"settings":{"language":"fr"}}', 200);
          }
          savedSettings =
              (jsonDecode(request.body) as Map<String, dynamic>)['settings']
                  as Map<String, dynamic>;
          return http.Response.bytes(
            utf8.encode(jsonEncode({'settings': savedSettings})),
            200,
          );
        }),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: OperationsModulePage(
            client: client,
            user: const ApiUser(
              id: 1,
              cin: 'ADMIN-1',
              name: 'Admin',
              isAdmin: true,
              permissions: {},
            ),
            module: OperationsModule.settings,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Informations de l’entreprise'), findsOneWidget);
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
      await tester.enterText(
        find.widgetWithText(TextField, 'Nom de l’entreprise'),
        'BHK AutoDiag',
      );
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();

      expect(savedSettings?['language'], 'fr');
      expect(savedSettings?['company']['name'], 'BHK AutoDiag');
      expect(savedSettings?['report']['show_qr'], isTrue);
      expect(savedSettings?['application']['version'], '1.0.0');
    },
  );

  testWidgets('dashboard header switches language and opens notifications', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    app.appLocale.value = const Locale('fr');
    addTearDown(() => app.appLocale.value = const Locale('fr'));
    var notificationReads = 0;
    var notificationReadPatches = 0;
    var notificationRead = false;
    final client = ApiClient(
      client: MockClient((request) async {
        if (request.method == 'PATCH') {
          notificationReadPatches++;
          notificationRead = true;
          return http.Response('{"id":7,"is_read":true}', 200);
        }
        if (request.url.path.endsWith('/notifications/')) {
          notificationReads++;
          return http.Response.bytes(
            utf8.encode(
              '{"notifications":[{"id":7,"title":"Alerte inspection",'
              '"message":"Une inspection est terminée.",'
              '"target":"","is_read":$notificationRead}]}',
            ),
            200,
          );
        }
        if (request.url.path.endsWith('/inspections/')) {
          return http.Response('{"inspections":[]}', 200);
        }
        return http.Response('{"monthly_activity":[]}', 200);
      }),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: BhkDashboard(
          client: client,
          user: const ApiUser(
            id: 1,
            cin: 'ADMIN-1',
            name: 'Admin',
            isAdmin: true,
            permissions: {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AdminDashboardPage), findsOneWidget);
    expect(notificationReads, 1);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('🇫🇷'), findsOneWidget);
    await tester.tap(find.byKey(const Key('language-toggle')));
    await tester.pump();
    expect(app.appLocale.value, const Locale('en'));
    expect(find.text('🇬🇧'), findsOneWidget);
    expect(find.text('Overview'), findsWidgets);
    await tester.tap(find.byKey(const Key('language-toggle')));
    await tester.pump();
    expect(app.appLocale.value, const Locale('ar'));
    expect(find.text('🇲🇦'), findsOneWidget);
    await tester.tap(find.byKey(const Key('language-toggle')));
    await tester.pump();
    expect(app.appLocale.value, const Locale('fr'));
    expect(find.text('🇫🇷'), findsOneWidget);

    await tester.tap(find.byKey(const Key('notifications-button')));
    await tester.pumpAndSettle();
    expect(notificationReads, 2);
    expect(find.text('Alerte inspection'), findsOneWidget);
    expect(find.byIcon(Icons.done_all), findsOneWidget);
    await tester.tap(find.byIcon(Icons.done_all));
    await tester.pumpAndSettle();
    expect(notificationReadPatches, 1);
    expect(find.byIcon(Icons.done_all), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('account-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Paramètres du compte'));
    await tester.pumpAndSettle();
    expect(find.byType(AccountSettingsPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('expert account opens its separate dashboard page', (
    tester,
  ) async {
    final client = ApiClient(
      client: MockClient((request) async {
        if (request.url.path.endsWith('/notifications/')) {
          return http.Response('{"notifications":[]}', 200);
        }
        return http.Response('{"monthly_activity":[]}', 200);
      }),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: BhkDashboard(
          client: client,
          user: const ApiUser(
            id: 2,
            cin: 'EXPERT-1',
            name: 'Expert',
            isAdmin: false,
            permissions: {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ExpertDashboardPage), findsOneWidget);
    expect(find.byType(AdminDashboardPage), findsNothing);
    expect(find.text('Gérer les experts'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('login page renders on a wide screen', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _openLogin(tester);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Bienvenue'), findsOneWidget);
  });

  testWidgets('login form validates required credentials', (tester) async {
    await _openLogin(tester);
    await tester.ensureVisible(find.byKey(const Key('login-submit')));
    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pumpAndSettle();

    expect(find.text('Veuillez saisir votre numéro CIN.'), findsOneWidget);
    expect(find.text('Veuillez saisir votre mot de passe.'), findsOneWidget);
  });

  testWidgets('submits entered CIN and password through callback', (
    tester,
  ) async {
    LoginCredentials? submittedCredentials;
    await tester.pumpWidget(
      MaterialApp(
        home: LoginPage(
          onLogin: (credentials) async => submittedCredentials = credentials,
        ),
      ),
    );

    await tester.enterText(find.byKey(const Key('cin-field')), 'AB123456');
    await tester.enterText(find.byKey(const Key('password-field')), 'secret');
    await tester.ensureVisible(find.byKey(const Key('login-submit')));
    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pump();

    expect(submittedCredentials?.cin, 'AB123456');
    expect(submittedCredentials?.password, 'secret');
  });

  testWidgets(
    'inspection editor presents the vehicle and diagnostic sections',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: InspectionEditorPage(
            client: ApiClient(
              client: MockClient((_) async => http.Response('{}', 200)),
            ),
            canEdit: true,
            canAddPhotos: true,
          ),
        ),
      );

      expect(find.text('Informations du véhicule'), findsOneWidget);
      expect(find.text('Carrosserie et peinture'), findsOneWidget);
      expect(find.text('Inspection mécanique'), findsOneWidget);
      expect(find.text('État des consommables'), findsOneWidget);
      final diagram = find.byKey(const Key('vehicle-body-diagram'));
      expect(find.byKey(const Key('vehicle-car-photo')), findsOneWidget);
      await tester.ensureVisible(diagram);
      final diagramBounds = tester.getRect(diagram);
      await tester.tapAt(
        Offset(
          diagramBounds.left + diagramBounds.width * .5,
          diagramBounds.top + diagramBounds.height * .18,
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Capot'),
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('shows a progress dialog while generating the report', (
    tester,
  ) async {
    final reportResponse = Completer<http.Response>();
    var uploadedReports = 0;
    final report = {
      'id': 7,
      'reference': 'BHK-2026-000007',
      'created_at': '2026-06-01T10:30:00Z',
      'vehicle': {
        'make': 'Renault',
        'model': 'Clio',
        'year': 2022,
        'registration': '',
        'vin': 'VF1TEST1234567890',
        'fuel': 'Essence',
        'transmission': 'Manuelle',
        'extra_information': '',
      },
      'mileage': {'displayed': 45000, 'actual': 45000, 'status': 'real'},
      'body_inspection': <String, dynamic>{},
      'mechanical_inspection': <String, dynamic>{},
      'consumables': <String, dynamic>{},
      'conclusion': '',
      'recommendation': '',
      'photos': <dynamic>[],
    };
    final client = ApiClient(
      client: MockClient((request) async {
        if (request.url.path.endsWith('/report/') && request.method == 'GET') {
          return reportResponse.future;
        }
        if (request.url.path.endsWith('/report-settings/')) {
          return http.Response('{"settings":{}}', 200);
        }
        if (request.url.path.endsWith('/reports/') &&
            request.method == 'POST') {
          uploadedReports++;
          return http.Response('{}', 201);
        }
        return http.Response('{}', 200);
      }),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: InspectionEditorPage(
          client: client,
          canEdit: false,
          canAddPhotos: false,
          canViewReport: true,
          initialData: {
            'id': 7,
            'reference': 'BHK-2026-000007',
            'status': 'completed',
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Ouvrir le rapport PDF'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Génération du rapport'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    reportResponse.complete(
      http.Response(
        jsonEncode(report),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      ),
    );
    await tester.pumpAndSettle();

    expect(uploadedReports, 1);
    expect(find.text('Génération du rapport'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('online payment removes expert customer price input', (
    tester,
  ) async {
    final requests = <http.Request>[];
    final inspection = <String, dynamic>{
      'id': 11,
      'reference': 'BHK-2026-000011',
      'status': 'in_progress',
      'vehicle': {
        'make': 'Renault',
        'model': 'Clio',
        'year': 2022,
        'registration': '',
        'vin': 'VF1TEST1234567890',
        'fuel': 'Essence',
        'transmission': 'Manuelle',
        'extra_information': '',
      },
      'mileage': {'displayed': 45000, 'actual': 45000, 'status': 'real'},
    };
    final client = ApiClient(
      client: MockClient((request) async {
        requests.add(request);
        final responseInspection = {
          ...inspection,
          'status': request.url.path.endsWith('/finish/')
              ? 'completed'
              : 'in_progress',
        };
        return http.Response(
          jsonEncode(responseInspection),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: InspectionEditorPage(
          client: client,
          initialData: inspection,
          canEdit: true,
          canAddPhotos: false,
          canFinish: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const Key('displayed-mileage-field')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(
      find.byKey(const Key('displayed-mileage-field')),
      '47000',
    );
    await tester.enterText(
      find.byKey(const Key('actual-mileage-field')),
      '52000',
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('customer-price-field')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const Key('customer-price-field')), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('customer-price-field')),
      '850.50',
    );
    await tester.ensureVisible(find.byKey(const Key('paid-online-checkbox')));
    await tester.tap(find.byKey(const Key('paid-online-checkbox')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('customer-price-field')), findsNothing);
    await tester.ensureVisible(
      find.text('Enregistrer et terminer l’inspection'),
    );
    await tester.tap(find.text('Enregistrer et terminer l’inspection'));
    await tester.pumpAndSettle();

    final finishRequest = requests.singleWhere(
      (request) => request.url.path.endsWith('/finish/'),
    );
    final updateRequest = requests.singleWhere(
      (request) => request.method == 'PATCH',
    );
    expect(
      (jsonDecode(updateRequest.body) as Map<String, dynamic>)['mileage'],
      {'displayed': 47000, 'actual': 52000, 'status': 'real'},
    );
    expect(
      (jsonDecode(finishRequest.body)
          as Map<String, dynamic>)['customer_price'],
      isNull,
    );
    expect(
      (jsonDecode(finishRequest.body) as Map<String, dynamic>)['paid_online'],
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('admin commission editor previews client and expert shares', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Map<String, dynamic> commission = {
      'id': 4,
      'inspection_id': 11,
      'inspection_reference': 'BHK-2026-000011',
      'expert_name': 'Expert Test',
      'vehicle': {
        'make': 'Renault',
        'model': 'Clio',
        'year': 2022,
        'registration': '12345-A-6',
      },
      'customer_price': '0.00',
      'payment_method': 'card',
      'payment_status': 'paid',
      'online_payment_amount': null,
      'amount': null,
      'status': 'pending',
      'mode': '',
      'value': null,
    };
    Map<String, dynamic>? submittedCommission;
    final client = ApiClient(
      client: MockClient((request) async {
        if (request.method == 'PATCH') {
          submittedCommission =
              (jsonDecode(request.body) as Map<String, dynamic>);
          commission = {
            ...commission,
            ...submittedCommission!,
            'online_payment_amount': submittedCommission!['customer_price'],
            'amount': '120.00',
            'status': 'defined',
          };
          return http.Response(jsonEncode(commission), 200);
        }
        if (request.url.path.endsWith('/commissions/')) {
          return http.Response(
            jsonEncode({
              'commissions': [commission],
            }),
            200,
          );
        }
        if (request.url.path.endsWith('/expenses/')) {
          return http.Response('{"expenses":[]}', 200);
        }
        return http.Response('{}', 200);
      }),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: OperationsModulePage(
          client: client,
          user: const ApiUser(
            id: 1,
            cin: 'ADMIN-1',
            name: 'Admin',
            isAdmin: true,
            permissions: {},
          ),
          module: OperationsModule.finance,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Paiement par carte déclaré'), findsOneWidget);
    expect(find.textContaining('Renault Clio (2022)'), findsOneWidget);
    expect(find.textContaining('12345-A-6'), findsOneWidget);
    expect(find.textContaining('Montant en ligne à confirmer'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.edit_outlined).first);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('admin-customer-price-field')),
      '500',
    );
    await tester.enterText(
      find.byKey(const Key('expert-commission-value-field')),
      '120',
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('500.00 DH'), findsOneWidget);
    expect(find.textContaining('120.00 DH'), findsOneWidget);
    expect(find.textContaining('380.00 DH'), findsOneWidget);
    await tester.tap(find.text('Enregistrer').last);
    await tester.pumpAndSettle();

    expect(submittedCommission?['mode'], 'fixed');
    expect(submittedCommission?['value'], '120.0');
    expect(submittedCommission?['customer_price'], '500.00');
    expect(tester.takeException(), isNull);
  });

  testWidgets('commission list prioritizes pending and can filter status', (
    tester,
  ) async {
    final client = ApiClient(
      client: MockClient((_) async {
        return http.Response(
          jsonEncode({
            'commissions': [
              {
                'id': 5,
                'inspection_reference': 'BHK-2026-PAID',
                'expert_name': 'Expert Test',
                'status': 'paid',
              },
              {
                'id': 6,
                'inspection_reference': 'BHK-2026-PENDING',
                'expert_name': 'Expert Test',
                'status': 'pending',
              },
            ],
          }),
          200,
        );
      }),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: OperationsModulePage(
          client: client,
          user: const ApiUser(
            id: 2,
            cin: 'EXPERT-2',
            name: 'Expert Test',
            isAdmin: false,
            permissions: {'view_personal_commissions': true},
          ),
          module: OperationsModule.finance,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final pending = find.text('BHK-2026-PENDING');
    final paid = find.text('BHK-2026-PAID');
    expect(tester.getTopLeft(pending).dy, lessThan(tester.getTopLeft(paid).dy));

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Payée').last);
    await tester.pumpAndSettle();

    expect(paid, findsOneWidget);
    expect(pending, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('commission summary cards scroll horizontally on mobile', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final client = ApiClient(
      client: MockClient((request) async {
        if (request.url.path.endsWith('/commissions/')) {
          return http.Response('{"commissions":[]}', 200);
        }
        if (request.url.path.endsWith('/expenses/')) {
          return http.Response('{"expenses":[]}', 200);
        }
        return http.Response('{"revenue_total":"100.00"}', 200);
      }),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: OperationsModulePage(
          client: client,
          user: const ApiUser(
            id: 1,
            cin: 'ADMIN-1',
            name: 'Admin',
            isAdmin: true,
            permissions: {},
          ),
          module: OperationsModule.finance,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final metrics = tester.widget<ListView>(
      find.byKey(const Key('commission-metrics-horizontal')),
    );
    expect(metrics.scrollDirection, Axis.horizontal);
    await tester.drag(
      find.byKey(const Key('commission-metrics-horizontal')),
      const Offset(-220, 0),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('experts can open for-sale vehicle details', (tester) async {
    final client = ApiClient(
      client: MockClient((_) async {
        return http.Response(
          jsonEncode({
            'listings': [
              {
                'id': 8,
                'expert_id': 2,
                'expert_name': 'Expert Two',
                'make': 'Dacia',
                'model': 'Sandero',
                'year': 2021,
                'mileage': 32000,
                'price': '85000.00',
                'description': 'Véhicule bien entretenu.',
                'extra_information': {},
                'status': 'published',
                'photos': [],
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: OperationsModulePage(
          client: client,
          user: const ApiUser(
            id: 2,
            cin: 'EXPERT-2',
            name: 'Expert Two',
            isAdmin: false,
            permissions: {'view_listings': true},
          ),
          module: OperationsModule.listings,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Dacia Sandero (2021)'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.info_outline));
    await tester.pumpAndSettle();
    expect(find.text('Véhicule bien entretenu.'), findsOneWidget);
    expect(find.text('Expert Two'), findsOneWidget);
    expect(find.text('32000 km'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('builds a PDF report with the inspection reference', () async {
    final logo = (await rootBundle.load('assets/logoo.png')).buffer
        .asUint8List();
    final bytes = await buildInspectionPdf(
      {
        'reference': 'BHK-2026-000001',
        'created_at': '2026-06-01T10:30:00Z',
        'expert_name': 'Expert Test',
        'vehicle': {
          'make': 'Renault',
          'model': 'Clio',
          'year': 2022,
          'registration': '',
          'vin': 'VF1TEST1234567890',
          'mileage': 45000,
          'fuel': 'Essence',
          'transmission': 'Manuelle',
          'extra_information': '',
        },
        'body_inspection': {
          'hood': {'status': 'Peinture'},
        },
        'mechanical_inspection': {
          'engine': {'result': 'Bon', 'observation': 'RAS'},
        },
        'consumables': {'tyres': 'Moyen'},
      },
      settings: {
        'company': {
          'name': 'Garage Test',
          'address': '10 rue du Test',
          'logo_base64': base64Encode(logo),
        },
        'language': 'ar',
        'report': {
          'title': 'Rapport personnalisé',
          'footer': 'Pied de page personnalisé',
          'show_qr': false,
        },
      },
    );

    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    final pdfContents = latin1.decode(bytes);
    expect(pdfContents, contains('/Width 1024'));
    expect(pdfContents, contains('/Height 1536'));
    expect(pdfContents, contains('/ca 0.4'));
  });
}

Future<void> _openLogin(WidgetTester tester) async {
  await tester.pumpWidget(const MyApp());
  await tester.pump(const Duration(seconds: 3));
  await tester.pumpAndSettle();
}
