import json
import secrets
from datetime import datetime, timedelta
from decimal import Decimal, InvalidOperation, ROUND_HALF_UP

from django.conf import settings
from django.contrib.auth import authenticate, get_user_model, password_validation
from django.core.exceptions import ValidationError
from django.db import IntegrityError, transaction
from django.db.models import Case, Count, IntegerField, Q, Sum, Value, When
from django.http import FileResponse, JsonResponse
from django.utils import timezone
from django.views.decorators.csrf import csrf_exempt
from django.views.decorators.http import require_http_methods

from .models import (
    AccountPreference,
    PERMISSIONS,
    ApiToken,
    ApplicationSettings,
    Commission,
    Expense,
    ExpertPermission,
    ExpertProfile,
    InternalNotification,
    Inspection,
    InspectionPhoto,
    ReportArchive,
    VehicleListing,
    VehicleListingPhoto,
)

User = get_user_model()
MAX_PHOTO_SIZE = 10 * 1024 * 1024
MAX_LISTING_PHOTOS = 10
PHOTO_EXTENSIONS = {
    'image/jpeg': {'jpg', 'jpeg'},
    'image/png': {'png'},
    'image/webp': {'webp'},
}
PHOTO_SIGNATURES = {
    'image/jpeg': lambda data: data.startswith(b'\xff\xd8\xff'),
    'image/png': lambda data: data.startswith(b'\x89PNG\r\n\x1a\n'),
    'image/webp': lambda data: data.startswith(b'RIFF') and data[8:12] == b'WEBP',
}


def _json_body(request):
    try:
        body = json.loads(request.body or b'{}')
    except (json.JSONDecodeError, UnicodeDecodeError):
        return None
    return body if isinstance(body, dict) else None


def _error(message, status=400):
    return JsonResponse({'error': message}, status=status)


def _photo_upload_error(uploaded):
    if uploaded is None or uploaded.size > MAX_PHOTO_SIZE:
        return 'Une photo de 10 Mo maximum est obligatoire.'
    signature = uploaded.read(12)
    uploaded.seek(0)
    is_valid = PHOTO_SIGNATURES.get(uploaded.content_type)
    extension = uploaded.name.rsplit('.', 1)[-1].lower()
    if (
        is_valid is None
        or extension not in PHOTO_EXTENSIONS[uploaded.content_type]
        or not is_valid(signature)
    ):
        return 'Format accepté : JPEG, PNG ou WebP.'
    return None


def _user(request):
    authorization = request.headers.get('Authorization', '')
    scheme, _, token = authorization.partition(' ')
    if scheme.lower() != 'bearer' or not token:
        return None
    try:
        api_token = ApiToken.objects.select_related('user').get(
            token_hash=ApiToken.digest(token),
        )
    except ApiToken.DoesNotExist:
        return None
    if api_token.created_at <= timezone.now() - timedelta(
        seconds=settings.API_TOKEN_MAX_AGE_SECONDS,
    ):
        api_token.delete()
        return None
    return api_token.user if api_token.user.is_active else None


def _authorized(request, permission=None):
    user = _user(request)
    if user is None:
        return None, _error('Authentification requise.', 401)
    if user.is_staff or user.is_superuser:
        return user, None
    if permission is None:
        return user, None
    allowed = ExpertPermission.objects.filter(
        user=user,
        code=permission,
        enabled=True,
    ).exists()
    if not allowed:
        return None, _error('Permission insuffisante.', 403)
    return user, None


def _authorized_any(request, *permissions):
    user = _user(request)
    if user is None:
        return None, _error('Authentification requise.', 401)
    if user.is_staff or user.is_superuser:
        return user, None
    if ExpertPermission.objects.filter(
        user=user,
        code__in=permissions,
        enabled=True,
    ).exists():
        return user, None
    return None, _error('Permission insuffisante.', 403)


def _permissions(user):
    values = {code: False for code in PERMISSIONS}
    if user.is_staff or user.is_superuser:
        return {code: True for code in values}
    values.update(dict(
        ExpertPermission.objects.filter(user=user).values_list('code', 'enabled'),
    ))
    return values


def _user_payload(user):
    profile = getattr(user, 'expert_profile', None)
    language = AccountPreference.objects.filter(
        user=user,
    ).values_list('language', flat=True).first()
    if language not in ('fr', 'en', 'ar'):
        language = ApplicationSettings.objects.filter(
            key='language',
        ).values_list('value', flat=True).first()
    return {
        'id': user.pk,
        'cin': profile.cin if profile else user.username,
        'name': user.get_full_name() or user.username,
        'is_admin': user.is_staff or user.is_superuser,
        'permissions': _permissions(user),
        'language': language if language in ('fr', 'en', 'ar') else 'fr',
    }


def _notify(recipients, title, message, target=''):
    InternalNotification.objects.bulk_create([
        InternalNotification(
            recipient=recipient,
            title=title,
            message=message,
            target=target,
        )
        for recipient in recipients
    ])


def _admin_users():
    return User.objects.filter(is_active=True).filter(
        Q(is_staff=True) | Q(is_superuser=True),
    )


def _expert_payload(profile):
    return {
        **_user_payload(profile.user),
        'id': profile.pk,
        'user_id': profile.user_id,
        'active': profile.user.is_active,
    }


def _inspection_payload(inspection):
    return {
        'id': inspection.pk,
        'reference': inspection.reference,
        'expert_id': inspection.expert_id,
        'expert_name': inspection.expert.get_full_name() or inspection.expert.username,
        'created_at': inspection.created_at.isoformat(),
        'updated_at': inspection.updated_at.isoformat(),
        'status': inspection.status,
        'vehicle': {
            'make': inspection.make,
            'model': inspection.model,
            'year': inspection.year,
            'registration': inspection.registration,
            'vin': inspection.vin,
            'fuel': inspection.fuel,
            'transmission': inspection.transmission,
            'extra_information': inspection.extra_information,
        },
        'mileage': {
            'displayed': inspection.mileage,
            'actual': inspection.actual_mileage,
            'status': inspection.mileage_status,
        },
        'body_inspection': inspection.body_inspection,
        'mechanical_inspection': inspection.mechanical_inspection,
        'consumables': inspection.consumables,
        'conclusion': inspection.conclusion,
        'recommendation': inspection.recommendation,
        'photos': [
            {
                'id': photo.pk,
                'zone': photo.zone,
                'url': f'photos/{photo.pk}/',
            }
            for photo in inspection.photos.all()
        ],
    }


@csrf_exempt
@require_http_methods(['POST'])
def login(request):
    body = _json_body(request)
    if body is None:
        return _error('Corps de requête JSON invalide.')
    cin = body.get('cin', '')
    if not isinstance(cin, str):
        return _error('Le CIN doit être une chaîne de caractères.')
    cin = cin.strip().upper()
    password = body.get('password')
    if not cin or not isinstance(password, str):
        return _error('CIN et mot de passe obligatoires.')
    profile = ExpertProfile.objects.select_related('user').filter(cin__iexact=cin).first()
    account = profile.user if profile else User.objects.filter(
        username__iexact=cin,
    ).first()
    username = account.username if account else cin
    user = authenticate(request, username=username, password=password)
    if user is None or not user.is_active:
        return _error('Identifiants invalides.', 401)
    token = secrets.token_urlsafe(32)
    ApiToken.objects.create(user=user, token_hash=ApiToken.digest(token))
    return JsonResponse({'token': token, 'user': _user_payload(user)})


@csrf_exempt
@require_http_methods(['GET'])
def me(request):
    user, error = _authorized(request)
    if error:
        return error
    return JsonResponse({'user': _user_payload(user)})


@csrf_exempt
@require_http_methods(['PUT'])
def account_preferences(request):
    user, error = _authorized(request)
    if error:
        return error
    body = _json_body(request)
    if body is None:
        return _error('Corps de requête JSON invalide.')
    language = body.get('language')
    if language not in {'fr', 'en', 'ar'}:
        return _error('Langue invalide.')
    preference, _ = AccountPreference.objects.get_or_create(user=user)
    preference.language = language
    preference.save(update_fields=('language',))
    return JsonResponse({'language': preference.language})


@csrf_exempt
@require_http_methods(['POST'])
def change_password(request):
    user, error = _authorized(request)
    if error:
        return error
    body = _json_body(request)
    if body is None:
        return _error('Corps de requête JSON invalide.')
    current_password = body.get('current_password')
    new_password = body.get('new_password')
    confirm_password = body.get('confirm_password')
    if not all(
        isinstance(value, str) and value
        for value in (current_password, new_password, confirm_password)
    ):
        return _error('Tous les champs du mot de passe sont obligatoires.')
    if not user.check_password(current_password):
        return _error('Mot de passe actuel incorrect.', 400)
    if new_password != confirm_password:
        return _error('Les nouveaux mots de passe ne correspondent pas.')
    try:
        password_validation.validate_password(new_password, user=user)
    except ValidationError:
        return _error(
            'Le nouveau mot de passe ne respecte pas les exigences de sécurité.',
        )

    authorization = request.headers.get('Authorization', '')
    _, _, token = authorization.partition(' ')
    current_token_hash = ApiToken.digest(token)
    with transaction.atomic():
        user.set_password(new_password)
        user.save(update_fields=('password',))
        ApiToken.objects.filter(user=user).exclude(
            token_hash=current_token_hash,
        ).delete()
    return JsonResponse({'ok': True})


@csrf_exempt
@require_http_methods(['POST'])
def logout(request):
    authorization = request.headers.get('Authorization', '')
    _, _, token = authorization.partition(' ')
    if token:
        ApiToken.objects.filter(token_hash=ApiToken.digest(token)).delete()
    return JsonResponse({'ok': True})


def _valid_inspection_data(body):
    vehicle = body.get('vehicle')
    if not isinstance(vehicle, dict):
        return None, 'Les informations du véhicule sont obligatoires.'
    text_fields = (
        'make',
        'model',
        'registration',
        'vin',
        'fuel',
        'transmission',
        'extra_information',
    )
    if any(
        field in vehicle and not isinstance(vehicle[field], str)
        for field in text_fields
    ):
        return None, 'Les informations textuelles du véhicule sont invalides.'
    make = vehicle.get('make', '').strip()
    model = vehicle.get('model', '').strip()
    vin = vehicle.get('vin', '').strip()
    year_value = vehicle.get('year')
    if (
        isinstance(year_value, bool)
        or not isinstance(year_value, (int, str))
        or (isinstance(year_value, str) and not year_value.strip().isdigit())
    ):
        return None, "L'année doit être un nombre entier."
    mileage_data = body.get('mileage')
    if mileage_data is None:
        mileage_data = {
            'displayed': vehicle.get('mileage'),
            'actual': None,
            'status': Inspection.MileageStatus.UNKNOWN,
        }
    if not isinstance(mileage_data, dict):
        return None, 'Les informations de kilométrage sont invalides.'
    mileage_values = {}
    for field in ('displayed', 'actual'):
        value = mileage_data.get(field)
        if value not in (None, '') and (
            isinstance(value, bool)
            or not isinstance(value, (int, str))
            or (isinstance(value, str) and not value.strip().isdigit())
        ):
            return None, 'Le kilométrage doit être un nombre entier.'
        try:
            number = int(value) if value not in (None, '') else None
        except (TypeError, ValueError):
            return None, 'Le kilométrage doit être un nombre entier.'
        if number is not None and number < 0:
            return None, 'Le kilométrage ne peut pas être négatif.'
        mileage_values[field] = number
    mileage_status = mileage_data.get(
        'status',
        Inspection.MileageStatus.UNKNOWN,
    )
    if mileage_status not in Inspection.MileageStatus.values:
        return None, 'L’état du kilométrage est invalide.'
    try:
        year = int(year_value)
    except (TypeError, ValueError):
        return None, "L'année doit être numérique."
    if (
        not make
        or not model
        or not vin
        or year < 1886
        or year > timezone.localdate().year + 1
    ):
        return None, 'Marque, modèle, année valide et numéro VIN obligatoires.'
    result = {
        'make': make,
        'model': model,
        'year': year,
        'registration': vehicle.get('registration', '').strip(),
        'vin': vin,
        'mileage': mileage_values['displayed'],
        'actual_mileage': mileage_values['actual'],
        'mileage_status': mileage_status,
        'fuel': vehicle.get('fuel', '').strip(),
        'transmission': vehicle.get('transmission', '').strip(),
        'extra_information': vehicle.get('extra_information', '').strip(),
    }
    for field in ('conclusion', 'recommendation'):
        if field in body and not isinstance(body[field], str):
            return None, f'Le champ {field} doit être une chaîne de caractères.'
        result[field] = body.get(field, '').strip()
    for field in ('body_inspection', 'mechanical_inspection', 'consumables'):
        if field in body and not isinstance(body[field], dict):
            return None, f'Le champ {field} doit être un objet JSON.'
        result[field] = body.get(field, {})
    return result, None


@csrf_exempt
@require_http_methods(['GET', 'POST'])
def inspections(request):
    if request.method == 'GET':
        user, error = _authorized_any(request, 'view_history', 'view_reports')
    else:
        user, error = _authorized(request, 'create_inspection')
    if error:
        return error
    if request.method == 'GET':
        queryset = Inspection.objects.select_related(
            'expert',
        ).prefetch_related('photos').order_by(
            Case(
                When(status=Inspection.Status.IN_PROGRESS, then=Value(0)),
                default=Value(1),
                output_field=IntegerField(),
            ),
            '-created_at',
        )
        if not (user.is_staff or user.is_superuser):
            queryset = queryset.filter(expert=user)
        return JsonResponse({'inspections': [_inspection_payload(item) for item in queryset]})
    body = _json_body(request)
    if body is None:
        return _error('Corps de requête JSON invalide.')
    data, message = _valid_inspection_data(body)
    if message:
        return _error(message)
    inspection = Inspection.objects.create(expert=user, **data)
    return JsonResponse(_inspection_payload(inspection), status=201)


@csrf_exempt
@require_http_methods(['GET', 'PATCH'])
def inspection_detail(request, inspection_id):
    inspection = Inspection.objects.filter(pk=inspection_id).select_related('expert').first()
    if inspection is None:
        return _error('Inspection introuvable.', 404)
    if request.method == 'GET':
        user, error = _authorized_any(request, 'view_history', 'view_reports')
    else:
        user, error = _authorized(request, 'edit_inspection')
    if error:
        return error
    if not (user.is_staff or user.is_superuser) and inspection.expert_id != user.pk:
        return _error('Inspection introuvable.', 404)
    if request.method == 'GET':
        return JsonResponse(_inspection_payload(inspection))
    if inspection.status == Inspection.Status.COMPLETED:
        return _error('Une inspection terminée ne peut plus être modifiée.', 409)
    body = _json_body(request)
    if body is None:
        return _error('Corps de requête JSON invalide.')
    data, message = _valid_inspection_data(body)
    if message:
        return _error(message)
    for field, value in data.items():
        setattr(inspection, field, value)
    inspection.save()
    return JsonResponse(_inspection_payload(inspection))


@csrf_exempt
@require_http_methods(['GET'])
def inspection_report(request, inspection_id):
    user, error = _authorized(request, 'view_reports')
    if error:
        return error
    inspection = Inspection.objects.filter(pk=inspection_id).select_related('expert').first()
    if inspection is None or (
        not (user.is_staff or user.is_superuser) and inspection.expert_id != user.pk
    ):
        return _error('Rapport introuvable.', 404)
    return JsonResponse(_inspection_payload(inspection))


@csrf_exempt
@require_http_methods(['POST'])
def finish_inspection(request, inspection_id):
    user, error = _authorized(request, 'finish_inspection')
    if error:
        return error
    inspection = Inspection.objects.filter(pk=inspection_id).first()
    if inspection is None or (
        not (user.is_staff or user.is_superuser) and inspection.expert_id != user.pk
    ):
        return _error('Inspection introuvable.', 404)
    if inspection.status == Inspection.Status.COMPLETED:
        return _error('Cette inspection est déjà terminée.', 409)
    body = _json_body(request)
    if body is None:
        return _error('Corps de requête JSON invalide.')
    paid_online = body.get('paid_online', False)
    if not isinstance(paid_online, bool):
        return _error('Le statut de paiement en ligne est invalide.')
    if 'customer_price' not in body and not paid_online:
        return _error('Le prix facturé au client est obligatoire.')
    customer_price = _valid_decimal(body.get('customer_price', 0))
    if (
        customer_price is None
        or customer_price < 0
        or customer_price > Decimal('99999999.99')
    ):
        return _error('Le prix facturé au client est invalide.')
    customer_price = customer_price.quantize(
        Decimal('0.01'),
        rounding=ROUND_HALF_UP,
    )
    inspection.status = Inspection.Status.COMPLETED
    inspection.customer_price = customer_price
    if paid_online:
        inspection.payment_method = 'card'
        inspection.payment_status = 'paid'
        inspection.online_payment_amount = None
    inspection.save(
        update_fields=(
            'status',
            'customer_price',
            'payment_method',
            'payment_status',
            'online_payment_amount',
            'updated_at',
        ),
    )
    Commission.objects.get_or_create(inspection=inspection)
    _notify(
        _admin_users(),
        'Inspection terminée',
        f'L’inspection {inspection.reference} est terminée.',
        f'inspections/{inspection.pk}/',
    )
    _notify(
        [user],
        'Commission en attente',
        f'La commission de l’inspection {inspection.reference} est en attente.',
        f'commissions/{inspection.pk}/',
    )
    return JsonResponse(_inspection_payload(inspection))


@csrf_exempt
@require_http_methods(['GET', 'POST'])
def experts(request):
    user, error = _authorized(request, 'manage_experts')
    if error:
        return error
    if request.method == 'GET':
        return JsonResponse({
            'experts': [
                {
                    **_expert_payload(expert),
                }
                for expert in ExpertProfile.objects.select_related('user').order_by('cin')
            ],
        })
    body = _json_body(request)
    if body is None:
        return _error('Corps de requête JSON invalide.')
    cin = body.get('cin', '')
    if not isinstance(cin, str):
        return _error('Le CIN doit être une chaîne de caractères.')
    cin = cin.strip().upper()
    password = body.get('password')
    if not cin or not isinstance(password, str) or len(password) < 8:
        return _error('Un CIN et un mot de passe de huit caractères minimum sont requis.')
    new_user = User(username=cin)
    try:
        password_validation.validate_password(password, user=new_user)
    except ValidationError as error:
        return _error(' '.join(error.messages))
    try:
        with transaction.atomic():
            new_user = User.objects.create_user(
                username=cin,
                password=password,
                first_name=str(body.get('first_name', '')).strip(),
                last_name=str(body.get('last_name', '')).strip(),
            )
            profile = ExpertProfile.objects.create(user=new_user, cin=cin)
    except IntegrityError:
        return _error('Un compte existe déjà pour ce CIN.', 409)
    return JsonResponse(_expert_payload(profile), status=201)


@csrf_exempt
@require_http_methods(['PATCH'])
def expert_detail(request, expert_id):
    user, error = _authorized(request, 'manage_experts')
    if error:
        return error
    expert = ExpertProfile.objects.select_related('user').filter(pk=expert_id).first()
    if expert is None:
        return _error('Compte expert introuvable.', 404)
    body = _json_body(request)
    if body is None:
        return _error('Corps de requête JSON invalide.')
    if 'active' in body and not isinstance(body['active'], bool):
        return _error('Le statut actif doit être un booléen.')
    if any(
        field in body and not isinstance(body[field], str)
        for field in ('first_name', 'last_name')
    ):
        return _error('Le prénom et le nom doivent être des chaînes.')
    expert_user = expert.user
    if 'active' in body:
        expert_user.is_active = body['active']
    if 'first_name' in body:
        expert_user.first_name = str(body['first_name']).strip()
    if 'last_name' in body:
        expert_user.last_name = str(body['last_name']).strip()
    expert_user.save(update_fields=('is_active', 'first_name', 'last_name'))
    return JsonResponse(_expert_payload(expert))


@csrf_exempt
@require_http_methods(['GET', 'PUT'])
def expert_permissions(request, expert_id):
    user, error = _authorized(request, 'manage_experts')
    if error:
        return error
    expert = ExpertProfile.objects.filter(pk=expert_id).first()
    if expert is None:
        return _error('Compte expert introuvable.', 404)
    if request.method == 'GET':
        return JsonResponse({
            'permissions': [
                {'code': code, 'label': label, 'enabled': _permissions(expert.user)[code]}
                for code, label in PERMISSIONS.items()
            ],
        })
    body = _json_body(request)
    changes = body.get('permissions') if body else None
    if not isinstance(changes, dict) or any(
        code not in PERMISSIONS or not isinstance(enabled, bool)
        for code, enabled in changes.items()
    ):
        return _error('La liste de permissions contient des valeurs invalides.')
    with transaction.atomic():
        for code, enabled in changes.items():
            ExpertPermission.objects.update_or_create(
                user=expert.user,
                code=code,
                defaults={'enabled': enabled},
            )
    return JsonResponse({
        'permissions': [
            {'code': code, 'label': label, 'enabled': _permissions(expert.user)[code]}
            for code, label in PERMISSIONS.items()
        ],
    })


@csrf_exempt
@require_http_methods(['POST'])
def inspection_photos(request, inspection_id):
    user, error = _authorized(request, 'add_inspection_photos')
    if error:
        return error
    inspection = Inspection.objects.filter(pk=inspection_id).first()
    if inspection is None or (
        not (user.is_staff or user.is_superuser) and inspection.expert_id != user.pk
    ):
        return _error('Inspection introuvable.', 404)
    if inspection.status == Inspection.Status.COMPLETED:
        return _error('Une inspection terminée ne peut plus recevoir de photos.', 409)
    uploaded = request.FILES.get('photo')
    message = _photo_upload_error(uploaded)
    if message:
        return _error(message)
    photo = InspectionPhoto.objects.create(
        inspection=inspection,
        zone=str(request.POST.get('zone', '')).strip()[:100],
        file=uploaded,
    )
    return JsonResponse({
        'id': photo.pk,
        'zone': photo.zone,
        'url': f'photos/{photo.pk}/',
    }, status=201)


@csrf_exempt
@require_http_methods(['GET'])
def photo_detail(request, photo_id):
    user, error = _authorized_any(request, 'view_history', 'view_reports')
    if error:
        return error
    photo = InspectionPhoto.objects.select_related('inspection').filter(pk=photo_id).first()
    if photo is None or (
        not (user.is_staff or user.is_superuser)
        and photo.inspection.expert_id != user.pk
    ):
        return _error('Photo introuvable.', 404)
    return FileResponse(photo.file.open('rb'))


def _money(value):
    return str(
        Decimal(value or 0).quantize(Decimal('0.01'), rounding=ROUND_HALF_UP),
    )


def _commission_payload(commission, *, include_customer_price=False):
    inspection = commission.inspection
    payload = {
        'id': commission.pk,
        'inspection_id': inspection.pk,
        'inspection_reference': inspection.reference,
        'expert_id': inspection.expert_id,
        'expert_name': inspection.expert.get_full_name() or inspection.expert.username,
        'status': commission.status,
        'mode': commission.mode,
        'value': _money(commission.value) if commission.value is not None else None,
        'amount': _money(commission.amount) if commission.amount is not None else None,
        'updated_at': commission.updated_at.isoformat(),
        'paid_at': commission.paid_at.isoformat() if commission.paid_at else None,
    }
    if include_customer_price:
        payload['vehicle'] = {
            'make': inspection.make,
            'model': inspection.model,
            'year': inspection.year,
            'registration': inspection.registration,
        }
        payload['customer_price'] = _money(inspection.customer_price)
        payload['payment_method'] = inspection.payment_method
        payload['payment_status'] = inspection.payment_status
        payload['online_payment_amount'] = (
            _money(inspection.online_payment_amount)
            if inspection.online_payment_amount is not None
            else None
        )
    return payload


@csrf_exempt
@require_http_methods(['GET'])
def dashboard(request):
    user, error = _authorized(request)
    if error:
        return error
    queryset = Inspection.objects.all()
    if not (user.is_staff or user.is_superuser):
        queryset = queryset.filter(expert=user)
    today = timezone.localdate()
    month_inspections = queryset.filter(
        created_at__year=today.year,
        created_at__month=today.month,
    )
    commissions = Commission.objects.filter(inspection__in=queryset)
    response = {
        'total_inspections': queryset.count(),
        'today_inspections': queryset.filter(created_at__date=today).count(),
        'month_inspections': month_inspections.count(),
        'in_progress': queryset.filter(status=Inspection.Status.IN_PROGRESS).count(),
        'completed': queryset.filter(status=Inspection.Status.COMPLETED).count(),
        'recent_inspections': [
            _inspection_payload(item)
            for item in queryset.select_related('expert').prefetch_related('photos')[:8]
        ],
        'commission_pending': commissions.filter(
            status__in=(Commission.Status.PENDING, Commission.Status.DEFINED),
        ).count(),
        'commission_validated': commissions.filter(
            status=Commission.Status.VALIDATED,
        ).count(),
        'commission_paid': commissions.filter(
            status=Commission.Status.PAID,
        ).count(),
    }
    month_index = today.year * 12 + today.month - 1 - 5
    start_year, start_month = divmod(month_index, 12)
    start = timezone.make_aware(datetime(start_year, start_month + 1, 1))
    monthly_rows = queryset.filter(created_at__gte=start).values(
        'created_at__year',
        'created_at__month',
    ).annotate(
        inspections=Count('pk'),
        revenue=Sum('customer_price'),
    )
    monthly_values = {
        (row['created_at__year'], row['created_at__month']): row
        for row in monthly_rows
    }
    activity_months = []
    revenue_months = []
    is_admin = user.is_staff or user.is_superuser
    for offset in range(5, -1, -1):
        index = today.year * 12 + today.month - 1 - offset
        year, month_index = divmod(index, 12)
        month = month_index + 1
        row = monthly_values.get((year, month), {})
        activity_months.append({
            'year': year,
            'month': month,
            'inspections': row.get('inspections', 0),
        })
        revenue_months.append({
            'year': year,
            'month': month,
            'revenue': _money(row.get('revenue')),
        })
    response['monthly_activity'] = activity_months
    if is_admin:
        response['monthly_revenue'] = revenue_months
        revenue = Inspection.objects.aggregate(total=Sum('customer_price'))['total']
        expenses = Expense.objects.aggregate(total=Sum('amount'))['total']
        commissions_total = commissions.exclude(amount=None).aggregate(
            total=Sum('amount'),
        )['total']
        response.update({
            'active_experts': ExpertProfile.objects.filter(user__is_active=True).count(),
            'revenue_total': _money(revenue),
            'expenses_total': _money(expenses),
            'commissions_total': _money(commissions_total),
            'net_result': _money((revenue or Decimal('0')) - (expenses or Decimal('0'))
                                 - (commissions_total or Decimal('0'))),
        })
    else:
        permissions = _permissions(user)
        if (
            permissions['view_personal_commissions']
            or permissions['view_global_finances']
        ):
            paid_commissions_total = commissions.filter(
                status=Commission.Status.PAID,
            ).exclude(amount=None).aggregate(total=Sum('amount'))['total']
            response['paid_commissions_total'] = _money(paid_commissions_total)
        response['commissions'] = [
            _commission_payload(item)
            for item in commissions.select_related('inspection', 'inspection__expert')
        ]
    return JsonResponse(response)


@csrf_exempt
@require_http_methods(['GET', 'PATCH'])
def commissions(request, commission_id=None):
    if request.method == 'GET':
        user, error = _authorized_any(
            request,
            'manage_commissions',
            'view_personal_commissions',
            'view_global_finances',
        )
        if error:
            return error
        queryset = Commission.objects.select_related('inspection', 'inspection__expert')
        if not (user.is_staff or user.is_superuser):
            queryset = queryset.filter(inspection__expert=user)
        queryset = queryset.order_by(
            Case(
                When(status=Commission.Status.PENDING, then=Value(0)),
                When(status=Commission.Status.DEFINED, then=Value(1)),
                When(status=Commission.Status.VALIDATED, then=Value(2)),
                default=Value(3),
                output_field=IntegerField(),
            ),
            '-updated_at',
        )
        return JsonResponse({
            'commissions': [
                _commission_payload(
                    item,
                    include_customer_price=user.is_staff or user.is_superuser,
                )
                for item in queryset
            ],
        })
    user, error = _authorized(request, 'manage_commissions')
    if error:
        return error
    commission = Commission.objects.select_related(
        'inspection', 'inspection__expert',
    ).filter(pk=commission_id).first()
    if commission is None:
        return _error('Commission introuvable.', 404)
    body = _json_body(request)
    if body is None:
        return _error('Corps de requête JSON invalide.')
    status = body.get('status')
    if status is not None and status not in Commission.Status.values:
        return _error('Statut de commission invalide.')
    if commission.status == Commission.Status.PAID:
        return _error('Une commission validée ne peut plus être modifiée.', 409)
    if commission.status == Commission.Status.VALIDATED and (
        'mode' in body
        or 'value' in body
        or 'customer_price' in body
        or 'online_payment_amount' in body
        or status != Commission.Status.PAID
    ):
        return _error('Une commission validée ne peut plus être modifiée.', 409)
    price_field = (
        'customer_price'
        if 'customer_price' in body
        else 'online_payment_amount'
        if 'online_payment_amount' in body
        else None
    )
    customer_price = commission.inspection.customer_price
    if price_field is not None:
        if not (user.is_staff or user.is_superuser):
            return _error('Seul un administrateur peut définir ce prix.', 403)
        if (
            commission.inspection.payment_method != 'card'
            or commission.inspection.payment_status != 'paid'
        ):
            return _error('Aucun paiement en ligne n’est enregistré.')
        customer_price = _valid_decimal(body[price_field])
        if (
            customer_price is None
            or customer_price <= 0
            or customer_price > Decimal('99999999.99')
        ):
            return _error('Le prix payé en ligne est invalide.')
    if (
        commission.inspection.payment_method == 'card'
        and commission.inspection.payment_status == 'paid'
        and customer_price <= 0
        and ('mode' in body or 'value' in body)
        and price_field is None
    ):
        return _error('Définissez le prix payé en ligne avant la commission.')
    if (
        'mode' in body
        or 'value' in body
        or (
            price_field is not None
            and commission.mode
            and commission.value is not None
        )
    ):
        mode = body.get('mode', commission.mode)
        if mode not in Commission.CalculationMode.values:
            return _error('Mode de calcul invalide.')
        value = _valid_decimal(body.get('value', commission.value))
        if value is None:
            return _error('Valeur de commission invalide.')
        if value < 0 or (mode == Commission.CalculationMode.PERCENTAGE and value > 100):
            return _error('La commission doit être positive et le pourcentage inférieur ou égal à 100.')
        amount = (
            value if mode == Commission.CalculationMode.FIXED
            else (customer_price * value / Decimal('100'))
        ).quantize(Decimal('0.01'), rounding=ROUND_HALF_UP)
        if amount > customer_price:
            return _error(
                'La commission ne peut pas dépasser le prix facturé au client.',
            )
        commission.mode = mode
        commission.value = value
        commission.amount = amount
        commission.status = Commission.Status.DEFINED
    if price_field is not None:
        commission.inspection.customer_price = customer_price
        commission.inspection.online_payment_amount = customer_price.quantize(
            Decimal('0.01'),
            rounding=ROUND_HALF_UP,
        )
    if status == Commission.Status.VALIDATED:
        if commission.status != Commission.Status.DEFINED:
            return _error('Définissez la commission avant de la valider.', 409)
        commission.status = status
    elif status == Commission.Status.PAID:
        if commission.status != Commission.Status.VALIDATED:
            return _error('Validez la commission avant de la marquer payée.', 409)
        commission.status = status
        commission.paid_at = timezone.now()
    elif status == Commission.Status.DEFINED and commission.amount is None:
        return _error('Définissez le montant avant de changer le statut.', 409)
    commission.save()
    if price_field is not None:
        commission.inspection.save(
            update_fields=(
                'customer_price',
                'online_payment_amount',
                'updated_at',
            ),
        )
    _notify(
        [commission.inspection.expert],
        f'Commission {commission.get_status_display().lower()}',
        f'La commission de {commission.inspection.reference} est '
        f'{commission.get_status_display().lower()}.',
        f'commissions/{commission.pk}/',
    )
    return JsonResponse(
        _commission_payload(
            commission,
            include_customer_price=user.is_staff or user.is_superuser,
        ),
    )


@csrf_exempt
@require_http_methods(['GET', 'PATCH'])
def inspection_financial(request, inspection_id):
    inspection = Inspection.objects.select_related('expert').filter(
        pk=inspection_id,
    ).first()
    if inspection is None:
        return _error('Inspection introuvable.', 404)
    if request.method == 'GET':
        user, error = _authorized_any(
            request,
            'manage_commissions',
            'view_personal_commissions',
            'view_history',
            'view_reports',
        )
        if error:
            return error
        is_admin = user.is_staff or user.is_superuser
        if not is_admin and inspection.expert_id != user.pk:
            return _error('Inspection introuvable.', 404)
        commission = Commission.objects.filter(inspection=inspection).first()
        commission_data = None
        if commission is not None:
            commission_data = {
                'status': commission.status,
                'mode': commission.mode,
                'value': (
                    _money(commission.value)
                    if commission.value is not None
                    else None
                ),
                'amount': (
                    _money(commission.amount)
                    if commission.amount is not None
                    else None
                ),
            }
            if is_admin:
                commission_data.update({
                    'payment_method': inspection.payment_method,
                    'payment_status': inspection.payment_status,
                    'online_payment_amount': (
                        _money(inspection.online_payment_amount)
                        if inspection.online_payment_amount is not None
                        else None
                    ),
                })
            if is_admin and commission.amount is not None:
                commission_data['company_share'] = _money(
                    inspection.customer_price - commission.amount,
                )
        return JsonResponse({
            'inspection_id': inspection.pk,
            'customer_price': _money(inspection.customer_price),
            'payment_method': inspection.payment_method,
            'payment_status': inspection.payment_status,
            'online_payment_amount': (
                _money(inspection.online_payment_amount)
                if is_admin and inspection.online_payment_amount is not None
                else None
            ),
            'commission': commission_data,
        })
    user, error = _authorized(request, 'manage_commissions')
    if error:
        return error
    body = _json_body(request)
    if body is None:
        return _error('Corps de requête JSON invalide.')
    if 'customer_price' in body:
        price = _valid_decimal(body['customer_price'])
        if price is None:
            return _error('Prix de prestation invalide.')
        if price < 0:
            return _error('Le prix ne peut pas être négatif.')
        inspection.customer_price = price
    if 'payment_method' in body:
        if not isinstance(body['payment_method'], str):
            return _error('Mode de paiement invalide.')
        inspection.payment_method = body['payment_method'].strip()[:32]
    if 'payment_status' in body:
        if body['payment_status'] not in ('unpaid', 'paid', 'partial'):
            return _error('Statut de paiement invalide.')
        inspection.payment_status = body['payment_status']
    inspection.save(update_fields=(
        'customer_price', 'payment_method', 'payment_status', 'updated_at',
    ))
    return JsonResponse({
        'inspection_id': inspection.pk,
        'customer_price': _money(inspection.customer_price),
        'payment_method': inspection.payment_method,
        'payment_status': inspection.payment_status,
    })


def _valid_decimal(value):
    try:
        amount = Decimal(str(value))
    except (InvalidOperation, TypeError):
        return None
    return amount if amount.is_finite() else None


def _valid_amount(value):
    amount = _valid_decimal(value)
    return amount if amount is not None and amount > 0 else None


@csrf_exempt
@require_http_methods(['GET', 'POST'])
def expenses(request):
    user, error = _authorized(request, 'manage_expenses')
    if error:
        return error
    if request.method == 'GET':
        return JsonResponse({
            'expenses': [
                {
                    'id': item.pk,
                    'amount': _money(item.amount),
                    'date': item.date.isoformat(),
                    'category': item.category,
                    'description': item.description,
                    'notes': item.notes,
                }
                for item in Expense.objects.order_by('-date', '-pk')
            ],
        })
    body = _json_body(request)
    if body is None:
        return _error('Corps de requête JSON invalide.')
    amount = _valid_amount(body.get('amount'))
    category = body.get('category')
    if amount is None or not isinstance(category, str) or not category.strip():
        return _error('Montant positif et catégorie obligatoires.')
    date_value = body.get('date')
    try:
        expense_date = timezone.datetime.fromisoformat(date_value).date() if date_value else timezone.localdate()
    except (TypeError, ValueError):
        return _error('Date de dépense invalide.')
    item = Expense.objects.create(
        amount=amount,
        date=expense_date,
        category=category.strip()[:80],
        description=str(body.get('description', '')).strip()[:240],
        notes=str(body.get('notes', '')).strip(),
        created_by=user,
    )
    return JsonResponse({'id': item.pk, 'amount': _money(item.amount)}, status=201)


@csrf_exempt
@require_http_methods(['GET', 'POST'])
def listings(request):
    if request.method == 'GET':
        user, error = _authorized_any(request, 'view_listings', 'add_listing')
    else:
        user, error = _authorized(request, 'add_listing')
    if error:
        return error
    queryset = VehicleListing.objects.select_related('expert').prefetch_related(
        'photos',
    )
    if not (user.is_staff or user.is_superuser):
        queryset = queryset.filter(Q(expert=user) | Q(status=VehicleListing.Status.PUBLISHED))
    if request.method == 'GET':
        return JsonResponse({'listings': [_listing_payload(item) for item in queryset]})
    body = _json_body(request)
    if body is None:
        return _error('Corps de requête JSON invalide.')
    data, message = _listing_data(body)
    if message:
        return _error(message)
    item = VehicleListing.objects.create(expert=user, **data)
    return JsonResponse(_listing_payload(item), status=201)


def _listing_data(body, partial=False):
    text_fields = ('make', 'model', 'description')
    if any(field in body and not isinstance(body[field], str) for field in text_fields):
        return None, 'Les informations du véhicule sont invalides.'
    data = {}
    for field in ('make', 'model'):
        value = body.get(field)
        if value is None and partial:
            continue
        if not isinstance(value, str) or not value.strip():
            return None, 'Marque et modèle obligatoires.'
        data[field] = value.strip()[:100]
    for field in ('year', 'mileage'):
        if field not in body and partial:
            continue
        value = body.get(field)
        if value in (None, '') and field == 'mileage':
            data[field] = None
            continue
        try:
            number = int(value)
        except (TypeError, ValueError):
            return None, f'{field} doit être un nombre entier.'
        if number < 0 or (field == 'year' and number < 1886):
            return None, f'{field} invalide.'
        data[field] = number
    if 'price' in body:
        if body['price'] in (None, ''):
            data['price'] = None
        else:
            amount = _valid_amount(body['price'])
            if amount is None:
                return None, 'Prix invalide.'
            data['price'] = amount
    if 'description' in body:
        data['description'] = body['description'].strip()
    if 'extra_information' in body:
        if not isinstance(body['extra_information'], dict):
            return None, 'Les informations complémentaires doivent être un objet.'
        data['extra_information'] = body['extra_information']
    return data, None


def _listing_payload(item):
    return {
        'id': item.pk,
        'expert_id': item.expert_id,
        'expert_name': item.expert.get_full_name() or item.expert.username,
        'make': item.make,
        'model': item.model,
        'year': item.year,
        'mileage': item.mileage,
        'price': _money(item.price) if item.price is not None else None,
        'description': item.description,
        'extra_information': item.extra_information,
        'status': item.status,
        'created_at': item.created_at.isoformat(),
        'photos': [
            {'id': photo.pk, 'url': f'listing-photos/{photo.pk}/'}
            for photo in item.photos.all()
        ],
    }


@csrf_exempt
@require_http_methods(['POST'])
def listing_photos(request, listing_id):
    user, error = _authorized(request, 'add_listing')
    if error:
        return error
    listing = VehicleListing.objects.filter(pk=listing_id).first()
    if listing is None or (
        not (user.is_staff or user.is_superuser)
        and listing.expert_id != user.pk
    ):
        return _error('Annonce introuvable.', 404)
    if listing.photos.count() >= MAX_LISTING_PHOTOS:
        return _error('Une annonce ne peut pas contenir plus de 10 photos.', 409)
    uploaded = request.FILES.get('photo')
    message = _photo_upload_error(uploaded)
    if message:
        return _error(message)
    photo = VehicleListingPhoto.objects.create(
        listing=listing,
        file=uploaded,
    )
    return JsonResponse({
        'id': photo.pk,
        'url': f'listing-photos/{photo.pk}/',
    }, status=201)


@csrf_exempt
@require_http_methods(['GET'])
def listing_photo_detail(request, photo_id):
    user, error = _authorized_any(request, 'view_listings', 'add_listing')
    if error:
        return error
    photo = VehicleListingPhoto.objects.select_related(
        'listing',
    ).filter(pk=photo_id).first()
    if photo is None or (
        not (user.is_staff or user.is_superuser)
        and photo.listing.expert_id != user.pk
        and photo.listing.status != VehicleListing.Status.PUBLISHED
    ):
        return _error('Photo introuvable.', 404)
    return FileResponse(photo.file.open('rb'))


@csrf_exempt
@require_http_methods(['PATCH'])
def listing_detail(request, listing_id):
    user, error = _authorized(request, 'edit_listings')
    if error:
        return error
    if not (user.is_staff or user.is_superuser):
        return _error('Seul un administrateur peut modifier une annonce.', 403)
    item = VehicleListing.objects.filter(pk=listing_id).first()
    if item is None:
        return _error('Annonce introuvable.', 404)
    body = _json_body(request)
    if body is None:
        return _error('Corps de requête JSON invalide.')
    data, message = _listing_data(body, partial=True)
    if message:
        return _error(message)
    if 'status' in body:
        if body['status'] not in VehicleListing.Status.values:
            return _error('Statut d’annonce invalide.')
        item.status = body['status']
    for field, value in data.items():
        setattr(item, field, value)
    item.save()
    return JsonResponse(_listing_payload(item))


@csrf_exempt
@require_http_methods(['GET', 'PUT'])
def app_settings(request):
    if request.method == 'GET':
        user, error = _authorized_any(request, 'edit_settings')
    else:
        user, error = _authorized(request, 'edit_settings')
    if error:
        return error
    if request.method == 'GET':
        return JsonResponse({
            'settings': dict(ApplicationSettings.objects.values_list('key', 'value')),
        })
    body = _json_body(request)
    settings_data = body.get('settings') if body else None
    if not isinstance(settings_data, dict) or any(
        not isinstance(key, str) or not isinstance(value, (str, int, float, bool, list, dict, type(None)))
        for key, value in settings_data.items()
    ):
        return _error('Paramètres invalides.')
    with transaction.atomic():
        for key, value in settings_data.items():
            ApplicationSettings.objects.update_or_create(
                key=key[:100],
                defaults={'value': value},
            )
    return JsonResponse({'settings': settings_data})


@csrf_exempt
@require_http_methods(['GET'])
def report_settings(request):
    user, error = _authorized(request, 'view_reports')
    if error:
        return error
    settings_data = dict(
        ApplicationSettings.objects.filter(
            key__in=('company', 'report', 'conclusions', 'language'),
        ).values_list('key', 'value'),
    )
    return JsonResponse({'settings': settings_data})


@csrf_exempt
@require_http_methods(['GET', 'PATCH'])
def notifications(request, notification_id=None):
    user, error = _authorized(request)
    if error:
        return error
    if request.method == 'GET':
        items = InternalNotification.objects.filter(recipient=user)
        return JsonResponse({
            'notifications': [
                {
                    'id': item.pk,
                    'title': item.title,
                    'message': item.message,
                    'target': item.target,
                    'is_read': item.read_at is not None,
                    'created_at': item.created_at.isoformat(),
                }
                for item in items[:100]
            ],
        })
    item = InternalNotification.objects.filter(
        pk=notification_id,
        recipient=user,
    ).first()
    if item is None:
        return _error('Notification introuvable.', 404)
    item.read_at = timezone.now()
    item.save(update_fields=('read_at',))
    return JsonResponse({'id': item.pk, 'is_read': True})


@csrf_exempt
@require_http_methods(['GET', 'POST'])
def inspection_reports(request, inspection_id):
    user, error = _authorized(request, 'view_reports')
    if error:
        return error
    inspection = Inspection.objects.filter(pk=inspection_id).first()
    if inspection is None or (
        not (user.is_staff or user.is_superuser)
        and inspection.expert_id != user.pk
    ):
        return _error('Inspection introuvable.', 404)
    if request.method == 'GET':
        return JsonResponse({
            'reports': [
                {
                    'id': item.pk,
                    'version': item.version,
                    'created_at': item.created_at.isoformat(),
                    'url': f'reports/{item.pk}/',
                }
                for item in inspection.report_versions.all()
            ],
        })
    uploaded = request.FILES.get('report')
    if uploaded is None or uploaded.size > 20 * 1024 * 1024:
        return _error('Un fichier PDF de 20 Mo maximum est obligatoire.')
    if uploaded.content_type != 'application/pdf' or not uploaded.read(5).startswith(b'%PDF-'):
        return _error('Le fichier doit être un document PDF valide.')
    uploaded.seek(0)
    version = (inspection.report_versions.order_by('-version').values_list(
        'version', flat=True,
    ).first() or 0) + 1
    archive = ReportArchive.objects.create(
        inspection=inspection,
        version=version,
        file=uploaded,
        created_by=user,
    )
    _notify(
        [inspection.expert],
        'Rapport généré',
        f'Le rapport {inspection.reference} (version {version}) est archivé.',
        f'reports/{archive.pk}/',
    )
    return JsonResponse({
        'id': archive.pk,
        'version': archive.version,
        'created_at': archive.created_at.isoformat(),
    }, status=201)


@csrf_exempt
@require_http_methods(['GET'])
def report_archive_detail(request, report_id):
    user, error = _authorized(request, 'view_reports')
    if error:
        return error
    archive = ReportArchive.objects.select_related('inspection').filter(pk=report_id).first()
    if archive is None or (
        not (user.is_staff or user.is_superuser)
        and archive.inspection.expert_id != user.pk
    ):
        return _error('Rapport introuvable.', 404)
    return FileResponse(
        archive.file.open('rb'),
        as_attachment=True,
        filename=f'{archive.inspection.reference}-v{archive.version}.pdf',
        content_type='application/pdf',
    )
