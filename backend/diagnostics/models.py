import hashlib
import uuid

from django.conf import settings
from django.db import models, transaction
from django.utils import timezone


PERMISSIONS = {
    'create_inspection': "Créer une inspection",
    'edit_inspection': "Modifier une inspection en cours",
    'add_inspection_photos': "Ajouter des photos aux inspections",
    'finish_inspection': "Terminer une inspection",
    'view_history': "Consulter l'historique des inspections",
    'view_reports': "Consulter les rapports",
    'add_listing': "Ajouter un véhicule à vendre",
    'view_listings': "Consulter les véhicules en vente",
    'edit_listings': "Modifier les véhicules en vente",
    'view_personal_commissions': "Consulter ses commissions",
    'view_global_finances': "Consulter les finances globales",
    'manage_experts': "Gérer les comptes experts",
    'manage_commissions': "Gérer les commissions",
    'manage_expenses': "Gérer les dépenses",
    'view_statistics': "Consulter les statistiques globales",
    'edit_settings': "Modifier les paramètres",
    'manage_backups': "Gérer les sauvegardes",
    'view_activity_logs': "Consulter les journaux d'activité",
    'view_sync_errors': "Contrôler les erreurs de synchronisation",
}


class ExpertProfile(models.Model):
    user = models.OneToOneField(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='expert_profile',
    )
    cin = models.CharField(max_length=32, unique=True)

    def save(self, *args, **kwargs):
        self.cin = self.cin.strip().upper()
        super().save(*args, **kwargs)

    def __str__(self):
        return self.cin


class ExpertPermission(models.Model):
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='expert_permissions',
    )
    code = models.CharField(max_length=64, choices=PERMISSIONS)
    enabled = models.BooleanField(default=False)

    class Meta:
        constraints = [
            models.UniqueConstraint(fields=('user', 'code'), name='unique_expert_permission'),
        ]


class ApiToken(models.Model):
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='api_tokens',
    )
    token_hash = models.CharField(max_length=64, unique=True)
    created_at = models.DateTimeField(default=timezone.now)

    @staticmethod
    def digest(token):
        return hashlib.sha256(token.encode('utf-8')).hexdigest()


class InspectionSequence(models.Model):
    year = models.PositiveSmallIntegerField(unique=True)
    last_value = models.PositiveIntegerField(default=0)


class Inspection(models.Model):
    class Status(models.TextChoices):
        IN_PROGRESS = 'in_progress', 'En cours'
        COMPLETED = 'completed', 'Terminée'

    class MileageStatus(models.TextChoices):
        REAL = 'real', 'Réel'
        NOT_REAL = 'not_real', 'Non réel'
        UNKNOWN = 'unknown', 'À vérifier'

    reference = models.CharField(max_length=20, unique=True, blank=True)
    expert = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.PROTECT,
        related_name='inspections',
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    status = models.CharField(
        max_length=16,
        choices=Status.choices,
        default=Status.IN_PROGRESS,
    )
    make = models.CharField(max_length=100)
    model = models.CharField(max_length=100)
    year = models.PositiveSmallIntegerField()
    registration = models.CharField(max_length=32, blank=True)
    vin = models.CharField(max_length=64)
    mileage = models.PositiveIntegerField(null=True, blank=True)
    actual_mileage = models.PositiveIntegerField(null=True, blank=True)
    mileage_status = models.CharField(
        max_length=16,
        choices=MileageStatus.choices,
        default=MileageStatus.UNKNOWN,
    )
    fuel = models.CharField(max_length=32, blank=True)
    transmission = models.CharField(max_length=32, blank=True)
    extra_information = models.TextField(blank=True)
    body_inspection = models.JSONField(default=dict, blank=True)
    mechanical_inspection = models.JSONField(default=dict, blank=True)
    consumables = models.JSONField(default=dict, blank=True)
    conclusion = models.TextField(blank=True)
    recommendation = models.TextField(blank=True)
    customer_price = models.DecimalField(max_digits=10, decimal_places=2, default=0)
    payment_method = models.CharField(max_length=32, blank=True)
    payment_status = models.CharField(max_length=16, default='unpaid')
    online_payment_amount = models.DecimalField(
        max_digits=10,
        decimal_places=2,
        null=True,
        blank=True,
    )

    class Meta:
        ordering = ('-created_at',)

    def save(self, *args, **kwargs):
        if not self.reference:
            with transaction.atomic():
                year = timezone.localdate().year
                sequence, _ = InspectionSequence.objects.get_or_create(year=year)
                sequence = InspectionSequence.objects.select_for_update().get(
                    pk=sequence.pk,
                )
                sequence.last_value += 1
                sequence.save(update_fields=('last_value',))
                self.reference = f'BHK-{year}-{sequence.last_value:06d}'
                super().save(*args, **kwargs)
            return
        super().save(*args, **kwargs)

    def __str__(self):
        return self.reference


def inspection_photo_path(instance, filename):
    extension = filename.rsplit('.', 1)[-1].lower()
    return f'inspections/{instance.inspection.reference}/{uuid.uuid4().hex}.{extension}'


class InspectionPhoto(models.Model):
    inspection = models.ForeignKey(
        Inspection,
        on_delete=models.CASCADE,
        related_name='photos',
    )
    zone = models.CharField(max_length=100, blank=True)
    file = models.FileField(upload_to=inspection_photo_path)
    created_at = models.DateTimeField(auto_now_add=True)


class Commission(models.Model):
    class Status(models.TextChoices):
        PENDING = 'pending', 'En attente'
        DEFINED = 'defined', 'Déterminée'
        VALIDATED = 'validated', 'Validée'
        PAID = 'paid', 'Payée'

    class CalculationMode(models.TextChoices):
        FIXED = 'fixed', 'Montant fixe'
        PERCENTAGE = 'percentage', 'Pourcentage'

    inspection = models.OneToOneField(
        Inspection,
        on_delete=models.CASCADE,
        related_name='commission',
    )
    mode = models.CharField(
        max_length=16,
        choices=CalculationMode.choices,
        blank=True,
    )
    value = models.DecimalField(max_digits=10, decimal_places=2, null=True, blank=True)
    amount = models.DecimalField(max_digits=10, decimal_places=2, null=True, blank=True)
    status = models.CharField(
        max_length=16,
        choices=Status.choices,
        default=Status.PENDING,
    )
    updated_at = models.DateTimeField(auto_now=True)
    paid_at = models.DateTimeField(null=True, blank=True)


class Expense(models.Model):
    amount = models.DecimalField(max_digits=10, decimal_places=2)
    date = models.DateField(default=timezone.localdate)
    category = models.CharField(max_length=80)
    description = models.CharField(max_length=240, blank=True)
    notes = models.TextField(blank=True)
    created_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.PROTECT,
        related_name='recorded_expenses',
    )
    created_at = models.DateTimeField(auto_now_add=True)


class VehicleListing(models.Model):
    class Status(models.TextChoices):
        DRAFT = 'draft', 'Masquée'
        PUBLISHED = 'published', 'Publiée'
        ARCHIVED = 'archived', 'Archivée'

    expert = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.PROTECT,
        related_name='vehicle_listings',
    )
    make = models.CharField(max_length=100)
    model = models.CharField(max_length=100)
    year = models.PositiveSmallIntegerField()
    mileage = models.PositiveIntegerField(null=True, blank=True)
    price = models.DecimalField(max_digits=12, decimal_places=2, null=True, blank=True)
    description = models.TextField(blank=True)
    extra_information = models.JSONField(default=dict, blank=True)
    status = models.CharField(
        max_length=16,
        choices=Status.choices,
        default=Status.DRAFT,
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)


def vehicle_listing_photo_path(instance, filename):
    extension = filename.rsplit('.', 1)[-1].lower()
    return f'listings/{instance.listing_id}/{uuid.uuid4().hex}.{extension}'


class VehicleListingPhoto(models.Model):
    listing = models.ForeignKey(
        VehicleListing,
        on_delete=models.CASCADE,
        related_name='photos',
    )
    file = models.FileField(upload_to=vehicle_listing_photo_path)
    created_at = models.DateTimeField(auto_now_add=True)


class ApplicationSettings(models.Model):
    key = models.CharField(max_length=100, unique=True)
    value = models.JSONField(default=dict)
    updated_at = models.DateTimeField(auto_now=True)


class AccountPreference(models.Model):
    LANGUAGE_CHOICES = (
        ('fr', 'Français'),
        ('en', 'English'),
        ('ar', 'العربية'),
    )

    user = models.OneToOneField(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='account_preferences',
    )
    language = models.CharField(
        max_length=2,
        choices=LANGUAGE_CHOICES,
        null=True,
        blank=True,
    )


class InternalNotification(models.Model):
    recipient = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='notifications',
    )
    title = models.CharField(max_length=160)
    message = models.CharField(max_length=500)
    target = models.CharField(max_length=200, blank=True)
    read_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)


def report_archive_path(instance, filename):
    return f'reports/{instance.inspection.reference}/{filename}'


class ReportArchive(models.Model):
    inspection = models.ForeignKey(
        Inspection,
        on_delete=models.CASCADE,
        related_name='report_versions',
    )
    version = models.PositiveIntegerField()
    file = models.FileField(upload_to=report_archive_path)
    created_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.PROTECT,
        related_name='generated_reports',
    )
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ('-version',)
        constraints = [
            models.UniqueConstraint(
                fields=('inspection', 'version'),
                name='unique_inspection_report_version',
            ),
        ]


