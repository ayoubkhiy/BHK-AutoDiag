import 'package:material_ui/material_ui.dart' hide Text;

import '../localization.dart' as app;

typedef Text = app.LocalizedText;

class DashboardWelcomeBanner extends StatelessWidget {
  const DashboardWelcomeBanner({
    super.key,
    required this.name,
    required this.subtitle,
  });

  final String name;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF142C4C), Color(0xFF245477)],
      ),
      borderRadius: BorderRadius.circular(22),
      boxShadow: const [
        BoxShadow(
          color: Color(0x1A142C4C),
          blurRadius: 18,
          offset: Offset(0, 8),
        ),
      ],
    ),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'BHK  •  DIAGNOSTIC AUTOMOBILE',
                style: TextStyle(
                  color: Color(0xFFB8D5E6),
                  fontSize: 11,
                  letterSpacing: 1.1,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Bonjour, $name',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: const TextStyle(color: Color(0xFFE0ECF4), fontSize: 14),
              ),
            ],
          ),
        ),
        const SizedBox(width: 14),
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Icon(
            Icons.directions_car_filled_outlined,
            color: Colors.white,
            size: 33,
          ),
        ),
      ],
    ),
  );
}

class DashboardStatCard extends StatelessWidget {
  const DashboardStatCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 218,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: const Color(0xFFEAF3F8),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(icon, color: const Color(0xFF2D86B7), size: 22),
            ),
            const SizedBox(height: 14),
            Text(
              value,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                color: const Color(0xFF142C4C),
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                color: Colors.blueGrey.shade600,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class DashboardStatCards extends StatelessWidget {
  const DashboardStatCards({super.key, required this.cards});

  final List<DashboardStatCard> cards;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth < 620) {
        return SizedBox(
          height: 184,
          child: ListView.separated(
            key: const Key('dashboard-stat-horizontal'),
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: cards.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (_, index) => cards[index],
          ),
        );
      }
      return Wrap(
        key: const Key('dashboard-stat-wrap'),
        spacing: 16,
        runSpacing: 16,
        children: cards,
      );
    },
  );
}

class DashboardTrendChart extends StatelessWidget {
  const DashboardTrendChart({
    super.key,
    required this.title,
    required this.metric,
    required this.months,
  });

  final String title;
  final String metric;
  final List<Map<String, dynamic>> months;

  @override
  Widget build(BuildContext context) {
    final values = months
        .map((month) => double.tryParse(month[metric]?.toString() ?? '') ?? 0)
        .toList();
    final maximum = values.fold<double>(
      1,
      (current, value) => value > current ? value : current,
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            for (var index = 0; index < months.length; index++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    SizedBox(
                      width: 58,
                      child: Text(
                        '${months[index]['month'].toString().padLeft(2, '0')}/'
                        '${months[index]['year']}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    Expanded(
                      child: LinearProgressIndicator(
                        value: values[index] / maximum,
                        minHeight: 8,
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 78,
                      child: Text(
                        metric == 'revenue'
                            ? '${months[index][metric]} DH'
                            : '${months[index][metric]}',
                        textAlign: TextAlign.end,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class DashboardEmptyState extends StatelessWidget {
  const DashboardEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.action,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? action;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 52, color: const Color(0xFF7A91A6)),
          const SizedBox(height: 14),
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 6),
          Text(subtitle, textAlign: TextAlign.center),
          if (action != null) ...[
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: action,
              icon: const Icon(Icons.add),
              label: const Text('Créer'),
            ),
          ],
        ],
      ),
    ),
  );
}

class DashboardPermissionNotice extends StatelessWidget {
  const DashboardPermissionNotice({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Text(message, textAlign: TextAlign.center),
    ),
  );
}

class DashboardErrorBanner extends StatelessWidget {
  const DashboardErrorBanner({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Card(
    color: const Color(0xFFFFF2F0),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Text(message, style: const TextStyle(color: Color(0xFF9B1C12))),
    ),
  );
}
