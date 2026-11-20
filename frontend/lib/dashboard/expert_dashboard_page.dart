import 'package:material_ui/material_ui.dart' hide Text;

import '../localization.dart' as app;
import 'dashboard_widgets.dart';

typedef Text = app.LocalizedText;

class ExpertDashboardPage extends StatelessWidget {
  const ExpertDashboardPage({
    super.key,
    required this.userName,
    required this.inspections,
    required this.dashboard,
    required this.canViewHistory,
    required this.canViewPersonalCommissions,
    required this.canCreateInspection,
    required this.onRefresh,
    required this.onCreateInspection,
    required this.onViewHistory,
    required this.onManageOperations,
    this.loadError,
    this.dashboardError,
    this.notificationError,
  });

  final String userName;
  final List<Map<String, dynamic>> inspections;
  final Map<String, dynamic> dashboard;
  final bool canViewHistory;
  final bool canViewPersonalCommissions;
  final bool canCreateInspection;
  final Future<void> Function() onRefresh;
  final VoidCallback onCreateInspection;
  final VoidCallback onViewHistory;
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
    final activity = dashboard['monthly_activity'];
    final months = activity is List
        ? activity.whereType<Map<String, dynamic>>().toList()
        : const <Map<String, dynamic>>[];
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          DashboardWelcomeBanner(
            name: userName,
            subtitle: 'Retrouvez vos inspections et votre activité.',
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
              ],
            ),
          if (canViewPersonalCommissions) ...[
            if (canViewHistory) const SizedBox(height: 18),
            DashboardStatCards(
              cards: [
                DashboardStatCard(
                  label: 'Gains versés (DH)',
                  value: '${dashboard['paid_commissions_total'] ?? '0.00'}',
                  icon: Icons.account_balance_wallet_outlined,
                ),
              ],
            ),
          ],
          if (months.isNotEmpty) ...[
            const SizedBox(height: 18),
            DashboardTrendChart(
              title: 'Activité — 6 derniers mois',
              metric: 'inspections',
              months: months,
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
