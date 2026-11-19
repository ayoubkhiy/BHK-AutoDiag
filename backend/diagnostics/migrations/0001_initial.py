import diagnostics.models
from django.conf import settings
from django.db import migrations, models
import django.db.models.deletion
import django.utils.timezone


class Migration(migrations.Migration):
    initial = True

    dependencies = [
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
    ]

    operations = [
        migrations.CreateModel(
            name='ApiToken',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('token_hash', models.CharField(max_length=64, unique=True)),
                ('created_at', models.DateTimeField(default=django.utils.timezone.now)),
                ('user', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='api_tokens', to=settings.AUTH_USER_MODEL)),
            ],
        ),
        migrations.CreateModel(
            name='ExpertPermission',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('code', models.CharField(choices=[
                    ('create_inspection', 'Créer une inspection'),
                    ('edit_inspection', 'Modifier une inspection en cours'),
                    ('add_inspection_photos', 'Ajouter des photos aux inspections'),
                    ('finish_inspection', 'Terminer une inspection'),
                    ('view_history', "Consulter l'historique des inspections"),
                    ('view_reports', 'Consulter les rapports'),
                    ('add_listing', 'Ajouter un véhicule à vendre'),
                    ('view_listings', 'Consulter les véhicules en vente'),
                    ('edit_listings', 'Modifier les véhicules en vente'),
                    ('view_personal_commissions', 'Consulter ses commissions'),
                    ('view_global_finances', 'Consulter les finances globales'),
                    ('manage_experts', 'Gérer les comptes experts'),
                    ('manage_commissions', 'Gérer les commissions'),
                    ('manage_invoices', 'Gérer les factures et taxes'),
                    ('view_statistics', 'Consulter les statistiques globales'),
                    ('edit_settings', 'Modifier les paramètres'),
                    ('manage_backups', 'Gérer les sauvegardes'),
                    ('view_activity_logs', "Consulter les journaux d'activité"),
                    ('view_sync_errors', 'Contrôler les erreurs de synchronisation'),
                ], max_length=64)),
                ('enabled', models.BooleanField(default=False)),
                ('user', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='expert_permissions', to=settings.AUTH_USER_MODEL)),
            ],
        ),
        migrations.CreateModel(
            name='ExpertProfile',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('cin', models.CharField(max_length=32, unique=True)),
                ('user', models.OneToOneField(on_delete=django.db.models.deletion.CASCADE, related_name='expert_profile', to=settings.AUTH_USER_MODEL)),
            ],
        ),
        migrations.CreateModel(
            name='InspectionSequence',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('year', models.PositiveSmallIntegerField(unique=True)),
                ('last_value', models.PositiveIntegerField(default=0)),
            ],
        ),
        migrations.CreateModel(
            name='Inspection',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('reference', models.CharField(blank=True, max_length=20, unique=True)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('updated_at', models.DateTimeField(auto_now=True)),
                ('status', models.CharField(choices=[('in_progress', 'En cours'), ('completed', 'Terminée')], default='in_progress', max_length=16)),
                ('make', models.CharField(max_length=100)),
                ('model', models.CharField(max_length=100)),
                ('year', models.PositiveSmallIntegerField()),
                ('registration', models.CharField(blank=True, max_length=32)),
                ('vin', models.CharField(max_length=64)),
                ('mileage', models.PositiveIntegerField(blank=True, null=True)),
                ('fuel', models.CharField(blank=True, max_length=32)),
                ('transmission', models.CharField(blank=True, max_length=32)),
                ('extra_information', models.TextField(blank=True)),
                ('body_inspection', models.JSONField(blank=True, default=dict)),
                ('mechanical_inspection', models.JSONField(blank=True, default=dict)),
                ('consumables', models.JSONField(blank=True, default=dict)),
                ('expert', models.ForeignKey(on_delete=django.db.models.deletion.PROTECT, related_name='inspections', to=settings.AUTH_USER_MODEL)),
            ],
            options={
                'ordering': ('-created_at',),
            },
        ),
        migrations.CreateModel(
            name='InspectionPhoto',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('zone', models.CharField(blank=True, max_length=100)),
                ('file', models.FileField(upload_to=diagnostics.models.inspection_photo_path)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('inspection', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='photos', to='diagnostics.inspection')),
            ],
        ),
        migrations.AddConstraint(
            model_name='expertpermission',
            constraint=models.UniqueConstraint(fields=('user', 'code'), name='unique_expert_permission'),
        ),
    ]
