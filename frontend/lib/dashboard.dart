import 'package:material_ui/material_ui.dart' hide Text;

import 'api.dart';
import 'account_settings.dart';
import 'admin/experts_management_page.dart';
import 'dashboard/admin_dashboard_page.dart';
import 'dashboard/dashboard_widgets.dart';
import 'dashboard/expert_dashboard_page.dart';
import 'inspection_editor.dart';
import 'localization.dart' as app;
import 'operations.dart';

typedef Text = app.LocalizedText;

class BhkDashboard extends StatefulWidget {
  const BhkDashboard({super.key, required this.client, required this.user});

  final ApiClient client;
  final ApiUser user;

  @override
  State<BhkDashboard> createState() => _BhkDashboardState();
}

class _BhkDashboardState extends State<BhkDashboard> {
  late final List<_Destination> _destinations;
  int _selectedIndex = 0;
  String _inspectionSearch = '';
  String _inspectionStatus = 'all';
  List<Map<String, dynamic>> _inspections = [];
  Map<String, dynamic> _dashboard = {};
  int _unreadNotificationCount = 0;
  String? _notificationError;
  bool _isLoading = true;
  String? _loadError;
  String? _dashboardError;

  bool get _canViewHistory =>
      widget.user.isAdmin ||
      widget.user.permissions['view_history'] == true ||
      widget.user.permissions['view_reports'] == true;

  bool get _canViewPersonalCommissions =>
      widget.user.permissions['view_personal_commissions'] == true ||
      widget.user.permissions['view_global_finances'] == true;

  bool get _canCreateInspection =>
      widget.user.isAdmin ||
      widget.user.permissions['create_inspection'] == true;

  @override
  void initState() {
    super.initState();
    _destinations = [
      const _Destination('Vue d’ensemble', Icons.dashboard_outlined),
      const _Destination('Inspections', Icons.fact_check_outlined),
      if (widget.user.isAdmin)
        const _Destination('Experts', Icons.manage_accounts_outlined),
      const _Destination('Gestion', Icons.tune_outlined),
    ];
    _loadInspections();
    _loadDashboard();
    _loadNotificationCount();
  }

  Future<void> _loadNotificationCount() async {
    try {
      final response = await widget.client.get('notifications/');
      final notifications = (response['notifications'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      if (!mounted) return;
      setState(() {
        _unreadNotificationCount = notifications
            .where((notification) => notification['is_read'] != true)
            .length;
        _notificationError = null;
      });
    } on ApiException catch (error) {
      if (mounted) setState(() => _notificationError = error.message);
    } on TypeError {
      if (mounted) {
        setState(
          () => _notificationError =
              'Les données des notifications reçues sont invalides.',
        );
      }
    }
  }

  Future<void> _openNotifications() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => OperationsModulePage(
          client: widget.client,
          user: widget.user,
          module: OperationsModule.notifications,
        ),
      ),
    );
    await _loadNotificationCount();
  }

  void _openAccountSettings() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) =>
            AccountSettingsPage(client: widget.client, user: widget.user),
      ),
    );
  }

  void _toggleLanguage() {
    final nextLanguage = switch (app.appLocale.value.languageCode) {
      'fr' => 'en',
      'en' => 'ar',
      _ => 'fr',
    };
    app.appLocale.value = Locale(nextLanguage);
    setState(() {});
  }

  Future<void> _loadDashboard() async {
    try {
      final response = await widget.client.get('dashboard/');
      if (mounted) {
        setState(() {
          _dashboard = response;
          _dashboardError = null;
        });
      }
    } on ApiException catch (error) {
      if (mounted) setState(() => _dashboardError = error.message);
    }
  }

  Future<void> _refreshDashboard() async {
    await Future.wait([
      _loadInspections(),
      _loadDashboard(),
      _loadNotificationCount(),
    ]);
  }

  Future<void> _loadInspections() async {
    if (!_canViewHistory) {
      setState(() {
        _inspections = [];
        _isLoading = false;
        _loadError = null;
      });
      return;
    }
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final response = await widget.client.get('inspections/');
      if (!mounted) return;
      setState(() {
        _inspections = (response['inspections'] as List<dynamic>)
            .cast<Map<String, dynamic>>();
        _isLoading = false;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error.message;
        _isLoading = false;
      });
    }
  }

  Future<void> _createInspection() async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => InspectionEditorPage(
          client: widget.client,
          canEdit: _canCreateInspection,
          canAddPhotos:
              widget.user.isAdmin ||
              widget.user.permissions['add_inspection_photos'] == true,
        ),
      ),
    );
    if (result == true) {
      await _loadInspections();
      if (mounted) setState(() => _selectedIndex = 1);
    }
  }

  Future<void> _logout() async {
    try {
      await widget.client.logout();
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Déconnexion : ${error.message}')));
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final title = _destinations[_selectedIndex].label;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          if (_selectedIndex == 1 && _canCreateInspection)
            if (MediaQuery.sizeOf(context).width >= 900)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: FilledButton.icon(
                  onPressed: _createInspection,
                  icon: const Icon(Icons.add),
                  label: const Text('Nouvelle inspection'),
                ),
              ),
          if (MediaQuery.sizeOf(context).width >= 430)
            IconButton(
              tooltip: app.translateText('Actualiser'),
              onPressed: () {
                _loadInspections();
                _loadDashboard();
                _loadNotificationCount();
              },
              icon: const Icon(Icons.refresh),
            ),
          IconButton(
            key: const Key('notifications-button'),
            tooltip: app.translateText('Notifications'),
            onPressed: _openNotifications,
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.notifications_none_rounded),
                if (_unreadNotificationCount > 0)
                  Positioned(
                    top: -5,
                    right: -7,
                    child: Container(
                      constraints: const BoxConstraints(
                        minWidth: 17,
                        minHeight: 17,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFD84343),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                      child: Center(
                        child: Text(
                          _unreadNotificationCount > 99
                              ? '99+'
                              : '$_unreadNotificationCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            height: 1.2,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            key: const Key('language-toggle'),
            tooltip: app.translateText(
              switch (app.appLocale.value.languageCode) {
                'ar' => 'Passer au français',
                'en' => 'Passer à l’arabe',
                _ => 'Passer à l’anglais',
              },
            ),
            onPressed: _toggleLanguage,
            icon: Text(switch (app.appLocale.value.languageCode) {
              'ar' => '🇲🇦',
              'en' => '🇬🇧',
              _ => '🇫🇷',
            }, style: const TextStyle(fontSize: 19)),
          ),
          PopupMenuButton<String>(
            key: const Key('account-menu'),
            tooltip: app.translateText('Compte'),
            onSelected: (value) {
              if (value == 'settings') _openAccountSettings();
              if (value == 'logout') _logout();
            },
            itemBuilder: (_) => [
              PopupMenuItem<String>(
                enabled: false,
                child: Text(widget.user.name),
              ),
              const PopupMenuItem<String>(
                value: 'settings',
                child: Text('Paramètres du compte'),
              ),
              const PopupMenuItem<String>(
                value: 'logout',
                child: Text('Se déconnecter'),
              ),
            ],
            icon: const CircleAvatar(
              radius: 17,
              backgroundColor: Color(0xFFE7EFF6),
              child: Icon(Icons.person_outline, size: 19),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 900;
          final page = _buildPage();
          if (!wide) return page;
          return Row(
            children: [
              NavigationRail(
                backgroundColor: Colors.white,
                selectedIndex: _selectedIndex,
                onDestinationSelected: (index) {
                  setState(() => _selectedIndex = index);
                },
                labelType: NavigationRailLabelType.all,
                destinations: [
                  for (final destination in _destinations)
                    NavigationRailDestination(
                      icon: Icon(destination.icon),
                      label: Text(destination.label),
                    ),
                ],
              ),
              const VerticalDivider(width: 1),
              Expanded(child: page),
            ],
          );
        },
      ),
      bottomNavigationBar: MediaQuery.sizeOf(context).width < 900
          ? NavigationBar(
              selectedIndex: _selectedIndex,
              onDestinationSelected: (index) {
                setState(() => _selectedIndex = index);
              },
              destinations: [
                for (final destination in _destinations)
                  NavigationDestination(
                    icon: Icon(destination.icon),
                    label: app.translateText(destination.label),
                  ),
              ],
            )
          : null,
      floatingActionButton: _selectedIndex == 1 && _canCreateInspection
          ? FloatingActionButton.extended(
              onPressed: _createInspection,
              icon: const Icon(Icons.add),
              label: const Text('Nouvelle inspection'),
            )
          : null,
    );
  }

  Widget _buildPage() {
    if (_selectedIndex == 0) return _buildOverview();
    if (_destinations[_selectedIndex].label == 'Experts') {
      return ExpertsManagementPage(client: widget.client);
    }
    if (_destinations[_selectedIndex].label == 'Gestion') {
      return OperationsPage(client: widget.client, user: widget.user);
    }
    return _buildInspections();
  }

  Future<void> _showInspectionDetails(Map<String, dynamic> inspection) async {
    try {
      final financial = await widget.client.get(
        'inspections/${inspection['id']}/financial/',
      );
      if (!mounted) return;
      final vehicle = inspection['vehicle'] as Map<String, dynamic>;
      final mileage = inspection['mileage'] is Map<String, dynamic>
          ? inspection['mileage'] as Map<String, dynamic>
          : <String, dynamic>{
              'displayed': vehicle['mileage'],
              'actual': null,
              'status': 'unknown',
            };
      final commission = financial['commission'];
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Détails de l’inspection ${inspection['reference']}'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _detailLine(
                    'Véhicule',
                    '${vehicle['make']} ${vehicle['model']} (${vehicle['year']})',
                  ),
                  _detailLine('VIN', vehicle['vin']?.toString() ?? ''),
                  _detailLine(
                    'Immatriculation',
                    vehicle['registration']?.toString() ?? '',
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Kilométrage',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  _detailLine(
                    'Kilométrage affiché au compteur',
                    '${mileage['displayed'] ?? '—'} km',
                  ),
                  _detailLine(
                    'Kilométrage réel',
                    '${mileage['actual'] ?? '—'} km',
                  ),
                  _detailLine(
                    'Fiabilité du kilométrage',
                    app.translateText(switch (mileage['status']) {
                      'real' => 'Réel',
                      'not_real' => 'Non réel',
                      _ => 'À vérifier',
                    }),
                  ),
                  if (widget.user.isAdmin)
                    _detailLine(
                      'Expert',
                      inspection['expert_name']?.toString() ?? '',
                    ),
                  _detailLine(
                    'Statut',
                    inspection['status'] == 'completed'
                        ? 'Terminée'
                        : 'En cours',
                  ),
                  _detailLine(
                    'Prix payé par le client',
                    '${financial['customer_price'] ?? '0.00'} DH',
                  ),
                  if (financial['payment_method'] == 'card' &&
                      financial['payment_status'] == 'paid')
                    _detailLine(
                      'Paiement par carte déclaré',
                      financial['online_payment_amount'] == null
                          ? app.translateText('Montant en ligne à confirmer')
                          : '${financial['online_payment_amount']} DH',
                    ),
                  if (commission is Map<String, dynamic>) ...[
                    _detailLine(
                      'Commission de l’expert',
                      commission['amount'] == null ||
                              commission['status'] == 'pending'
                          ? 'En attente de définition'
                          : '${commission['amount']} DH',
                    ),
                    _detailLine(
                      'Statut de la commission',
                      _commissionStatusLabel(
                        commission['status']?.toString() ?? '',
                      ),
                    ),
                    if (widget.user.isAdmin &&
                        commission['company_share'] != null)
                      _detailLine(
                        'Part de la société',
                        '${commission['company_share']} DH',
                      ),
                  ],
                  if ((inspection['conclusion'] as String? ?? '').isNotEmpty)
                    _detailLine(
                      'Conclusion',
                      inspection['conclusion'] as String,
                    ),
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
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    } on TypeError {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Les données financières de l’inspection sont invalides.',
            ),
          ),
        );
      }
    }
  }

  Widget _detailLine(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 175,
          child: Text(
            app.translateText(label),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        Expanded(child: Text(value.isEmpty ? '—' : value)),
      ],
    ),
  );

  String _commissionStatusLabel(String status) => switch (status) {
    'pending' => 'En attente',
    'defined' => 'Définie',
    'validated' => 'Validée',
    'paid' => 'Payée',
    _ => status,
  };

  Widget _buildOverview() {
    void onViewHistory() => setState(() => _selectedIndex = 1);

    void onManageOperations() {
      setState(() {
        _selectedIndex = _destinations.indexWhere(
          (item) => item.label == 'Gestion',
        );
      });
    }

    if (widget.user.isAdmin) {
      return AdminDashboardPage(
        userName: widget.user.name,
        inspections: _inspections,
        dashboard: _dashboard,
        canViewHistory: _canViewHistory,
        canCreateInspection: _canCreateInspection,
        onRefresh: _refreshDashboard,
        onCreateInspection: _createInspection,
        onViewHistory: onViewHistory,
        onManageOperations: onManageOperations,
        loadError: _loadError,
        dashboardError: _dashboardError,
        notificationError: _notificationError,
        onManageExperts: () => setState(
          () => _selectedIndex = _destinations.indexWhere(
            (item) => item.label == 'Experts',
          ),
        ),
      );
    }
    return ExpertDashboardPage(
      userName: widget.user.name,
      inspections: _inspections,
      dashboard: _dashboard,
      canViewHistory: _canViewHistory,
      canViewPersonalCommissions: _canViewPersonalCommissions,
      canCreateInspection: _canCreateInspection,
      onRefresh: _refreshDashboard,
      onCreateInspection: _createInspection,
      onViewHistory: onViewHistory,
      onManageOperations: onManageOperations,
      loadError: _loadError,
      dashboardError: _dashboardError,
      notificationError: _notificationError,
    );
  }

  Widget _buildInspections() {
    if (!_canViewHistory) {
      return const DashboardPermissionNotice(
        message: 'La consultation de l’historique n’est pas autorisée.',
      );
    }
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: DashboardErrorBanner(message: _loadError!),
        ),
      );
    }
    if (_inspections.isEmpty) {
      return DashboardEmptyState(
        icon: Icons.fact_check_outlined,
        title: 'Aucune inspection',
        subtitle: 'Les inspections autorisées apparaîtront ici.',
        action: _canCreateInspection ? _createInspection : null,
      );
    }
    final filtered = _inspections.where((inspection) {
      if (_inspectionStatus != 'all' &&
          inspection['status'] != _inspectionStatus) {
        return false;
      }
      final vehicle = inspection['vehicle'] as Map<String, dynamic>;
      final searchable = [
        inspection['reference'],
        inspection['expert_name'],
        inspection['created_at'],
        vehicle['vin'],
        vehicle['make'],
        vehicle['model'],
        vehicle['year'],
      ].join(' ').toLowerCase();
      return searchable.contains(_inspectionSearch.trim().toLowerCase());
    }).toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: LayoutBuilder(
            builder: (context, constraints) => Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                SizedBox(
                  width: constraints.maxWidth > 420
                      ? constraints.maxWidth - 192
                      : constraints.maxWidth,
                  child: TextField(
                    decoration: InputDecoration(
                      labelText: app.translateText(
                        'Rechercher référence, VIN, véhicule, date…',
                      ),
                      prefixIcon: const Icon(Icons.search),
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (value) =>
                        setState(() => _inspectionSearch = value),
                  ),
                ),
                SizedBox(
                  width: 180,
                  child: DropdownButtonFormField<String>(
                    initialValue: _inspectionStatus,
                    decoration: InputDecoration(
                      labelText: app.translateText('Statut'),
                      border: const OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'all', child: Text('Tous')),
                      DropdownMenuItem(
                        value: 'in_progress',
                        child: Text('En cours'),
                      ),
                      DropdownMenuItem(
                        value: 'completed',
                        child: Text('Terminées'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _inspectionStatus = value);
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? const Center(child: Text('Aucune inspection correspondante.'))
              : RefreshIndicator(
                  onRefresh: _loadInspections,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final inspection = filtered[index];
                      final vehicle =
                          inspection['vehicle'] as Map<String, dynamic>;
                      final completed = inspection['status'] == 'completed';
                      return Card(
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 8,
                          ),
                          leading: CircleAvatar(
                            backgroundColor: completed
                                ? const Color(0xFFE6F4EA)
                                : const Color(0xFFFFF3DB),
                            child: Icon(
                              completed
                                  ? Icons.task_alt
                                  : Icons.pending_actions,
                              color: completed
                                  ? const Color(0xFF25834A)
                                  : const Color(0xFF9B6A00),
                            ),
                          ),
                          title: Text(
                            '${vehicle['make']} ${vehicle['model']}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(
                            '${inspection['reference']} · ${vehicle['year']} · '
                            '${completed ? 'Terminée' : 'En cours'}',
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: app.translateText(
                                  'Détails de l’inspection',
                                ),
                                onPressed: () =>
                                    _showInspectionDetails(inspection),
                                icon: const Icon(Icons.info_outline),
                              ),
                              const Icon(Icons.chevron_right),
                            ],
                          ),
                          onTap: () async {
                            final changed = await Navigator.of(context).push<bool>(
                              MaterialPageRoute<bool>(
                                builder: (_) => InspectionEditorPage(
                                  client: widget.client,
                                  initialData: inspection,
                                  canEdit:
                                      !completed &&
                                      (widget.user.isAdmin ||
                                          widget
                                                  .user
                                                  .permissions['edit_inspection'] ==
                                              true),
                                  canAddPhotos:
                                      !completed &&
                                      (widget.user.isAdmin ||
                                          widget
                                                  .user
                                                  .permissions['add_inspection_photos'] ==
                                              true),
                                  canFinish:
                                      !completed &&
                                      (widget.user.isAdmin ||
                                          widget
                                                  .user
                                                  .permissions['finish_inspection'] ==
                                              true),
                                  canViewReport:
                                      widget.user.isAdmin ||
                                      widget.user.permissions['view_reports'] ==
                                          true,
                                ),
                              ),
                            );
                            if (changed == true) _loadInspections();
                          },
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

class _Destination {
  const _Destination(this.label, this.icon);

  final String label;
  final IconData icon;
}
