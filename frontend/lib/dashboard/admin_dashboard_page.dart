import 'package:material_ui/material_ui.dart' hide Text;

import '../localization.dart' as app;
import 'dashboard_widgets.dart';

typedef Text = app.LocalizedText;

class AdminDashboardPage extends StatelessWidget {
  const AdminDashboardPage({
    super.key,
    required this.userName,
    required this.inspections,
    required this.dashboard,
    required this.canViewHistory,
    required this.canCreateInspection,
    required this.onRefresh,
    required this.onCreateInspection,
    required this.onViewHistory,
    required this.onManageExperts,
    required this.onManageOperations,
    this.loadError,
    this.dashboardError,
    this.notificationError,
  });

  final String userName;
  final List<Map<String, dynamic>> inspections;
  final Map<String, dynamic> dashboard;
  final bool canViewHistory;
  final bool canCreateInspection;
  final Future<void> Function() onRefresh;
  final VoidCallback onCreateInspection;
  final VoidCallback onViewHistory;
  final VoidCallback onManageExperts;
  final VoidCallback onManageOperations;
  final String? loadError;
  final String? dashboardError;
  final String? notificationError;

  @override
  Widget build(BuildContext context) {
    final completed = inspections
        .where((item) => item['status'] == 'completed')
        .length;
    final inProgress = inspections.length - completed;
    final activity = _monthList(dashboard['monthly_activity']);
    final revenue = _monthList(dashboard['monthly_revenue']);
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          DashboardWelcomeBanner(
            name: userName,
            subtitle: 'Vue d’ensemble de votre plateforme.',
          ),
          const SizedBox(height: 24),
          if (canViewHistory)
            DashboardStatCards(
              cards: [
                DashboardStatCard(
                  label: 'Inspections visibles',
                  value: '${inspections.length}',
                  icon: Icons.fact_check_outlined,
                ),
                DashboardStatCard(
                  label: 'En cours',
                  value: '$inProgress',
                  icon: Icons.pending_actions_outlined,
                ),
                DashboardStatCard(
                  label: 'Terminées',
                  value: '$completed',
                  icon: Icons.task_alt_outlined,
                ),
                DashboardStatCard(
                  label: 'Inspections aujourd’hui',
                  value: '${dashboard['today_inspections'] ?? 0}',
                  icon: Icons.today_outlined,
                ),
                DashboardStatCard(
                  label: 'Inspections ce mois',
                  value: '${dashboard['month_inspections'] ?? 0}',
                  icon: Icons.calendar_month_outlined,
                ),
                DashboardStatCard(
                  label: 'Experts actifs',
                  value: '${dashboard['active_experts'] ?? 0}',
                  icon: Icons.people_outline,
                ),
                DashboardStatCard(
                  label: 'Chiffre d’affaires (DH)',
                  value: '${dashboard['revenue_total'] ?? '0.00'}',
                  icon: Icons.trending_up,
                ),
                DashboardStatCard(
                  label: 'Dépenses (DH)',
                  value: '${dashboard['expenses_total'] ?? '0.00'}',
                  icon: Icons.receipt_long_outlined,
                ),
                DashboardStatCard(
                  label: 'Commissions en attente',
                  value: '${dashboard['commission_pending'] ?? 0}',
                  icon: Icons.pending_actions_outlined,
                ),
                DashboardStatCard(
                  label: 'Commissions validées',
                  value: '${dashboard['commission_validated'] ?? 0}',
                  icon: Icons.verified_outlined,
                ),
                DashboardStatCard(
                  label: 'Commissions payées',
                  value: '${dashboard['commission_paid'] ?? 0}',
                  icon: Icons.payments_outlined,
                ),
                DashboardStatCard(
                  label: 'Résultat net (DH)',
                  value: '${dashboard['net_result'] ?? '0.00'}',
                  icon: Icons.account_balance_outlined,
                ),
              ],
            ),
          if (activity.isNotEmpty) ...[
            const SizedBox(height: 18),
            DashboardTrendChart(
              title: 'Activité — 6 derniers mois',
              metric: 'inspections',
              months: activity,
            ),
            if (revenue.isNotEmpty)
              DashboardTrendChart(
                title: 'Chiffre d’affaires — 6 derniers mois',
                metric: 'revenue',
                months: revenue,
              ),
          ],
          const SizedBox(height: 26),
          _quickActions(context),
          if (canViewHistory && inspections.isNotEmpty)
            _recentInspections(context),
          if (loadError != null) ...[
            const SizedBox(height: 18),
            DashboardErrorBanner(message: loadError!),
          ],
          if (dashboardError != null) ...[
            const SizedBox(height: 18),
            DashboardErrorBanner(message: dashboardError!),
          ],
          if (notificationError != null) ...[
            const SizedBox(height: 18),
            DashboardErrorBanner(message: notificationError!),
          ],
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _monthList(Object? value) {
    if (value is! List) return const [];
    return value.whereType<Map<String, dynamic>>().toList();
  }

  Widget _quickActions(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Accès rapide',
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              if (canCreateInspection)
                FilledButton.icon(
                  onPressed: onCreateInspection,
                  icon: const Icon(Icons.add),
                  label: const Text('Créer une inspection'),
                ),
              if (canViewHistory)
                OutlinedButton.icon(
                  onPressed: onViewHistory,
                  icon: const Icon(Icons.history),
                  label: const Text('Consulter l’historique'),
                ),
              OutlinedButton.icon(
                onPressed: onManageExperts,
                icon: const Icon(Icons.manage_accounts_outlined),
                label: const Text('Gérer les experts'),
              ),
              OutlinedButton.icon(
                onPressed: onManageOperations,
                icon: const Icon(Icons.tune_outlined),
                label: const Text('Finances et paramètres'),
              ),
            ],
          ),
          if (!canCreateInspection && !canViewHistory) ...[
            const SizedBox(height: 14),
            const Text(
              'Aucun accès n’est activé pour votre compte. '
              'Contactez l’administrateur.',
            ),
          ],
        ],
      ),
    ),
  );

  Widget _recentInspections(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Inspections récentes',
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          for (final item in inspections.take(5))
            Card(
              child: ListTile(
                leading: const Icon(Icons.fact_check_outlined),
                title: Text(
                  '${(item['vehicle'] as Map<String, dynamic>)['make']} '
                  '${(item['vehicle'] as Map<String, dynamic>)['model']}',
                ),
                subtitle: Text(
                  '${item['reference']} · '
                  '${item['status'] == 'completed' ? 'Terminée' : 'En cours'}',
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
