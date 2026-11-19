import tempfile
from datetime import timedelta
from decimal import Decimal

from django.contrib.auth import get_user_model
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import TestCase, override_settings
from django.urls import reverse
from django.utils import timezone

from .models import (
    AccountPreference,
    ApiToken,
    ApplicationSettings,
    Commission,
    ExpertPermission,
    ExpertProfile,
    Inspection,
    InspectionPhoto,
    VehicleListingPhoto,
)

User = get_user_model()


class InspectionApiTests(TestCase):
    def setUp(self):
        self.expert = User.objects.create_user(
            username='expert-one',
            password='test-password',
            first_name='Expert',
            last_name='One',
        )
        ExpertProfile.objects.create(user=self.expert, cin='CIN-001')
        self.other_expert = User.objects.create_user(
            username='expert-two',
            password='test-password',
        )
        ExpertProfile.objects.create(user=self.other_expert, cin='CIN-002')
        self.token = self._token_for(self.expert)
        self.client.defaults['HTTP_AUTHORIZATION'] = f'Bearer {self.token}'
        self.vehicle = {
            'make': 'Renault',
            'model': 'Clio',
            'year': 2022,
            'vin': 'VF1TEST1234567890',
        }

    def _token_for(self, user):
        import secrets

        token = secrets.token_urlsafe(32)
        ApiToken.objects.create(user=user, token_hash=ApiToken.digest(token))
        return token

    def _grant(self, user, *codes):
        for code in codes:
            ExpertPermission.objects.create(user=user, code=code, enabled=True)

    @override_settings(API_TOKEN_MAX_AGE_SECONDS=60)
    def test_expired_api_token_is_rejected_and_deleted(self):
        token_hash = ApiToken.digest(self.token)
        ApiToken.objects.filter(token_hash=token_hash).update(
            created_at=timezone.now() - timedelta(seconds=61),
        )

        response = self.client.get(reverse('api-me'))

        self.assertEqual(response.status_code, 401)
        self.assertFalse(ApiToken.objects.filter(token_hash=token_hash).exists())

    def test_creating_inspection_requires_individual_permission(self):
        response = self.client.post(
            reverse('api-inspections'),
            data={'vehicle': self.vehicle},
            content_type='application/json',
        )

        self.assertEqual(response.status_code, 403)
        self.assertEqual(Inspection.objects.count(), 0)

    def test_login_resolves_the_expert_cin_to_the_account(self):
        ApplicationSettings.objects.create(key='language', value='ar')
        response = self.client.post(
            reverse('api-login'),
            data={'cin': 'CIN-001', 'password': 'test-password'},
            content_type='application/json',
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()['user']['id'], self.expert.pk)
        self.assertEqual(response.json()['user']['language'], 'ar')
        self.assertTrue(response.json()['token'])

    def test_login_returns_english_when_configured(self):
        ApplicationSettings.objects.create(key='language', value='en')
        response = self.client.post(
            reverse('api-login'),
            data={'cin': 'CIN-001', 'password': 'test-password'},
            content_type='application/json',
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()['user']['language'], 'en')

    def test_login_defaults_to_french_without_language_setting(self):
        response = self.client.post(
            reverse('api-login'),
            data={'cin': 'CIN-001', 'password': 'test-password'},
            content_type='application/json',
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()['user']['language'], 'fr')

    def test_account_language_is_saved_per_user(self):
        ApplicationSettings.objects.create(key='language', value='en')
        response = self.client.put(
            reverse('api-account-preferences'),
            data={'language': 'ar'},
            content_type='application/json',
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()['language'], 'ar')
        self.assertEqual(
            self.client.get(reverse('api-me')).json()['user']['language'],
            'ar',
        )
        login_response = self.client.post(
            reverse('api-login'),
            data={'cin': 'CIN-001', 'password': 'test-password'},
            content_type='application/json',
        )
        self.assertEqual(login_response.json()['user']['language'], 'ar')

        other_token = self._token_for(self.other_expert)
        other_response = self.client.get(
            reverse('api-me'),
            HTTP_AUTHORIZATION=f'Bearer {other_token}',
        )
        self.assertEqual(other_response.json()['user']['language'], 'en')

    def test_account_language_rejects_unsupported_values(self):
        response = self.client.put(
            reverse('api-account-preferences'),
            data={'language': 'xx'},
            content_type='application/json',
        )

        self.assertEqual(response.status_code, 400)
        self.assertFalse(AccountPreference.objects.filter(user=self.expert).exists())

    def test_changing_password_requires_current_password_and_revokes_other_sessions(self):
        other_token = self._token_for(self.expert)
        response = self.client.post(
            reverse('api-account-password'),
            data={
                'current_password': 'test-password',
                'new_password': 'Clear-Skyline-417!New',
                'confirm_password': 'Clear-Skyline-417!New',
            },
            content_type='application/json',
        )

        self.assertEqual(response.status_code, 200)
        updated_user = User.objects.get(pk=self.expert.pk)
        self.assertTrue(updated_user.check_password('Clear-Skyline-417!New'))
        self.assertTrue(
            ApiToken.objects.filter(token_hash=ApiToken.digest(self.token)).exists(),
        )
        self.assertFalse(
            ApiToken.objects.filter(token_hash=ApiToken.digest(other_token)).exists(),
        )
        self.assertEqual(self.client.get(reverse('api-me')).status_code, 200)

    def test_changing_password_rejects_wrong_current_password(self):
        response = self.client.post(
            reverse('api-account-password'),
            data={
                'current_password': 'incorrect-password',
                'new_password': 'Clear-Skyline-417!New',
                'confirm_password': 'Clear-Skyline-417!New',
            },
            content_type='application/json',
        )

        self.assertEqual(response.status_code, 400)
        unchanged_user = User.objects.get(pk=self.expert.pk)
        self.assertTrue(unchanged_user.check_password('test-password'))

    def test_changing_password_rejects_weak_new_password(self):
        response = self.client.post(
            reverse('api-account-password'),
            data={
                'current_password': 'test-password',
                'new_password': 'weak',
                'confirm_password': 'weak',
            },
            content_type='application/json',
        )

        self.assertEqual(response.status_code, 400)
        unchanged_user = User.objects.get(pk=self.expert.pk)
        self.assertTrue(unchanged_user.check_password('test-password'))

    def test_inspection_is_persisted_with_generated_reference_and_owner_scope(self):
        self._grant(self.expert, 'create_inspection', 'view_history')

        created = self.client.post(
            reverse('api-inspections'),
            data={
                'vehicle': self.vehicle,
                'mileage': {
                    'displayed': 45000,
                    'actual': 45000,
                    'status': 'real',
                },
                'body_inspection': {'hood': {'status': 'Peinture'}},
                'mechanical_inspection': {'engine': {'result': 'Bon'}},
                'consumables': {'tyres': 'Moyen'},
                'conclusion': 'Bon état général.',
                'recommendation': 'Prévoir une révision.',
            },
            content_type='application/json',
        )

        self.assertEqual(created.status_code, 201)
        inspection = created.json()
        self.assertRegex(inspection['reference'], r'^BHK-\d{4}-\d{6}$')
        self.assertEqual(inspection['expert_id'], self.expert.pk)
        self.assertEqual(inspection['vehicle']['vin'], self.vehicle['vin'])
        self.assertNotIn('mileage', inspection['vehicle'])
        self.assertEqual(
            inspection['mileage'],
            {'displayed': 45000, 'actual': 45000, 'status': 'real'},
        )
        self.assertEqual(
            Inspection.objects.get(pk=inspection['id']).actual_mileage,
            45000,
        )
        self.assertEqual(inspection['conclusion'], 'Bon état général.')
        self.assertEqual(inspection['recommendation'], 'Prévoir une révision.')

        second = self.client.post(
            reverse('api-inspections'),
            data={'vehicle': self.vehicle},
            content_type='application/json',
        )
        self.assertEqual(second.status_code, 201)
        self.assertNotEqual(inspection['reference'], second.json()['reference'])

        self.client.defaults['HTTP_AUTHORIZATION'] = (
            f'Bearer {self._token_for(self.other_expert)}'
        )
        self._grant(self.other_expert, 'view_history')
        history = self.client.get(reverse('api-inspections'))
        self.assertEqual(history.status_code, 200)
        self.assertEqual(history.json()['inspections'], [])

    def test_inspection_history_prioritizes_in_progress_inspections(self):
        self._grant(self.expert, 'view_history')
        in_progress = Inspection.objects.create(
            expert=self.expert,
            make='Renault',
            model='Clio',
            year=2022,
            vin='IN-PROGRESS',
        )
        completed = Inspection.objects.create(
            expert=self.expert,
            make='Dacia',
            model='Sandero',
            year=2021,
            vin='COMPLETED',
            status=Inspection.Status.COMPLETED,
        )
        Inspection.objects.filter(pk=completed.pk).update(
            created_at=timezone.now() + timedelta(seconds=1),
        )

        response = self.client.get(reverse('api-inspections'))

        self.assertEqual(response.status_code, 200)
        self.assertEqual(
            [item['id'] for item in response.json()['inspections']],
            [in_progress.pk, completed.pk],
        )

    def test_commission_list_prioritizes_pending_commissions(self):
        self._grant(self.expert, 'view_personal_commissions')
        commissions = []
        for status in (
            Commission.Status.PAID,
            Commission.Status.VALIDATED,
            Commission.Status.DEFINED,
            Commission.Status.PENDING,
        ):
            inspection = Inspection.objects.create(
                expert=self.expert,
                make='Renault',
                model='Clio',
                year=2022,
                vin=f'VIN-{status}',
            )
            commission = Commission.objects.create(
                inspection=inspection,
                status=status,
            )
            commissions.append(commission)

        response = self.client.get(reverse('api-commissions'))

        self.assertEqual(response.status_code, 200)
        self.assertEqual(
            [item['status'] for item in response.json()['commissions']],
            [
                Commission.Status.PENDING,
                Commission.Status.DEFINED,
                Commission.Status.VALIDATED,
                Commission.Status.PAID,
            ],
        )

    def test_online_payment_defers_customer_price_to_admin(self):
        self._grant(self.expert, 'create_inspection', 'finish_inspection')
        created = self.client.post(
            reverse('api-inspections'),
            data={'vehicle': self.vehicle},
            content_type='application/json',
        )
        inspection = created.json()
        finish_url = reverse('api-inspection-finish', args=[inspection['id']])

        missing_price = self.client.post(
            finish_url,
            data={},
            content_type='application/json',
        )
        self.assertEqual(missing_price.status_code, 400)
        self.assertEqual(
            Inspection.objects.get(pk=inspection['id']).status,
            Inspection.Status.IN_PROGRESS,
        )

        finished = self.client.post(
            finish_url,
            data={'paid_online': True},
            content_type='application/json',
        )
        self.assertEqual(finished.status_code, 200)
        self.assertEqual(finished.json()['status'], Inspection.Status.COMPLETED)
        self.assertNotIn('customer_price', finished.json())
        saved = Inspection.objects.get(pk=inspection['id'])
        self.assertEqual(saved.customer_price, Decimal('0'))
        self.assertEqual(saved.payment_method, 'card')
        self.assertEqual(saved.payment_status, 'paid')
        self.assertIsNone(saved.online_payment_amount)
        self._grant(self.expert, 'manage_commissions')
        commission = self.client.get(reverse('api-commissions')).json()[
            'commissions'
        ][0]
        expert_update = self.client.patch(
            reverse('api-commission-detail', args=[commission['id']]),
            data={
                'customer_price': '450.50',
                'mode': 'percentage',
                'value': '24',
            },
            content_type='application/json',
        )
        self.assertEqual(expert_update.status_code, 403)
        saved.refresh_from_db()
        self.assertEqual(saved.customer_price, Decimal('0'))
        private_detail = self.client.get(
            reverse('api-inspection-detail', args=[inspection['id']]),
        )
        self.assertEqual(private_detail.status_code, 403)
        cash_inspection = self.client.post(
            reverse('api-inspections'),
            data={'vehicle': self.vehicle},
            content_type='application/json',
        ).json()
        cash_finished = self.client.post(
            reverse('api-inspection-finish', args=[cash_inspection['id']]),
            data={'customer_price': '450.50'},
            content_type='application/json',
        )
        self.assertEqual(cash_finished.status_code, 200)
        cash_saved = Inspection.objects.get(pk=cash_inspection['id'])
        self.assertEqual(cash_saved.customer_price, Decimal('450.50'))
        self.assertEqual(cash_saved.payment_status, 'unpaid')

    def test_admin_can_change_each_expert_permission(self):
        admin = User.objects.create_superuser(
            username='admin',
            email='admin@example.test',
            password='admin-password',
        )
        self.client.defaults['HTTP_AUTHORIZATION'] = f'Bearer {self._token_for(admin)}'
        permissions_url = reverse(
            'api-expert-permissions',
            args=[self.expert.expert_profile.pk],
        )

        response = self.client.put(
            permissions_url,
            data={'permissions': {'create_inspection': True}},
            content_type='application/json',
        )

        self.assertEqual(response.status_code, 200)
        self.assertTrue(
            ExpertPermission.objects.get(
                user=self.expert,
                code='create_inspection',
            ).enabled,
        )
        permission = next(
            item
            for item in response.json()['permissions']
            if item['code'] == 'create_inspection'
        )
        self.assertTrue(permission['enabled'])

    def test_admin_can_create_edit_and_disable_expert_accounts(self):
        admin = User.objects.create_superuser(
            username='admin',
            email='admin@example.test',
            password='admin-password',
        )
        self.client.defaults['HTTP_AUTHORIZATION'] = f'Bearer {self._token_for(admin)}'
        created = self.client.post(
            reverse('api-experts'),
            data={
                'cin': 'cin-100',
                'first_name': 'New',
                'last_name': 'Expert',
                'password': 'Violet-Engine-247!Stop',
            },
            content_type='application/json',
        )

        self.assertEqual(created.status_code, 201)
        expert_id = created.json()['id']
        expert_user = User.objects.get(username='CIN-100')
        self.assertEqual(expert_user.expert_profile.cin, 'CIN-100')

        changed = self.client.patch(
            reverse('api-expert-detail', args=[expert_id]),
            data={'first_name': 'Updated', 'active': False},
            content_type='application/json',
        )

        self.assertEqual(changed.status_code, 200)
        self.assertEqual(changed.json()['name'], 'Updated Expert')
        expert_user.refresh_from_db()
        self.assertFalse(expert_user.is_active)
        self.client.defaults['HTTP_AUTHORIZATION'] = (
            f'Bearer {self._token_for(expert_user)}'
        )
        self.assertEqual(self.client.get(reverse('api-me')).status_code, 401)

    @override_settings(CORS_ALLOWED_ORIGINS=['http://localhost:5173'])
    def test_development_cors_preflight_allows_local_flutter_web(self):
        response = self.client.options(
            reverse('api-login'),
            HTTP_ORIGIN='http://localhost:5173',
            HTTP_ACCESS_CONTROL_REQUEST_METHOD='POST',
            HTTP_ACCESS_CONTROL_REQUEST_HEADERS='authorization,content-type',
        )

        self.assertEqual(response.status_code, 204)
        self.assertEqual(
            response['Access-Control-Allow-Origin'],
            'http://localhost:5173',
        )

    def test_invalid_vehicle_data_is_rejected(self):
        self._grant(self.expert, 'create_inspection')
        response = self.client.post(
            reverse('api-inspections'),
            data={'vehicle': {'make': 'Renault', 'model': 'Clio', 'year': 2020}},
            content_type='application/json',
        )

        self.assertEqual(response.status_code, 400)
        self.assertEqual(Inspection.objects.count(), 0)

        invalid_mileage = self.client.post(
            reverse('api-inspections'),
            data={
                'vehicle': self.vehicle,
                'mileage': {
                    'displayed': 45000,
                    'actual': -1,
                    'status': 'real',
                },
            },
            content_type='application/json',
        )
        self.assertEqual(invalid_mileage.status_code, 400)
        self.assertEqual(Inspection.objects.count(), 0)

    def test_photo_upload_is_permission_checked_and_can_be_retrieved(self):
        self._grant(self.expert, 'create_inspection', 'view_history')
        created = self.client.post(
            reverse('api-inspections'),
            data={'vehicle': self.vehicle},
            content_type='application/json',
        )
        inspection_id = created.json()['id']
        photo_url = reverse(
            'api-inspection-photos',
            args=[inspection_id],
        )
        image_bytes = b'\xff\xd8\xff' + b'\x00' * 24

        denied = self.client.post(
            photo_url,
            data={
                'zone': 'hood',
                'photo': SimpleUploadedFile(
                    'hood.jpg',
                    image_bytes,
                    content_type='image/jpeg',
                ),
            },
        )
        self.assertEqual(denied.status_code, 403)
        self.assertEqual(InspectionPhoto.objects.count(), 0)

        self._grant(self.expert, 'add_inspection_photos')
        with tempfile.TemporaryDirectory() as media_root:
            with self.settings(MEDIA_ROOT=media_root):
                uploaded = self.client.post(
                    photo_url,
                    data={
                        'zone': 'hood',
                        'photo': SimpleUploadedFile(
                            'hood.jpg',
                            image_bytes,
                            content_type='image/jpeg',
                        ),
                    },
                )
                self.assertEqual(uploaded.status_code, 201)
                download = self.client.get(
                    reverse('api-photo-detail', args=[uploaded.json()['id']]),
                )
                self.assertEqual(download.status_code, 200)
                self.assertEqual(b''.join(download.streaming_content), image_bytes)

    def test_commission_workflow_and_dashboard_financial_totals(self):
        self._grant(
            self.expert,
            'create_inspection',
            'finish_inspection',
            'view_personal_commissions',
        )
        created = self.client.post(
            reverse('api-inspections'),
            data={'vehicle': self.vehicle},
            content_type='application/json',
        )
        inspection = created.json()
        finished = self.client.post(
            reverse('api-inspection-finish', args=[inspection['id']]),
            data={'paid_online': True},
            content_type='application/json',
        )
        self.assertEqual(finished.status_code, 200)

        admin = User.objects.create_superuser(
            username='finance-admin',
            email='finance@example.test',
            password='admin-password',
        )
        self.client.defaults['HTTP_AUTHORIZATION'] = f'Bearer {self._token_for(admin)}'
        self.client.patch(
            reverse('api-inspection-financial', args=[inspection['id']]),
            data={'payment_status': 'paid'},
            content_type='application/json',
        )
        commission = self.client.get(reverse('api-commissions')).json()['commissions'][0]
        self.assertEqual(commission['status'], 'pending')
        self.assertEqual(commission['customer_price'], '0.00')
        self.assertEqual(commission['payment_method'], 'card')
        self.assertEqual(commission['payment_status'], 'paid')
        self.assertIsNone(commission['online_payment_amount'])
        self.assertEqual(
            commission['vehicle'],
            {
                'make': 'Renault',
                'model': 'Clio',
                'year': 2022,
                'registration': '',
            },
        )

        commission_url = reverse('api-commission-detail', args=[commission['id']])
        defined = self.client.patch(
            commission_url,
            data={
                'mode': 'percentage',
                'value': '24',
                'customer_price': '500',
            },
            content_type='application/json',
        )
        self.assertEqual(defined.status_code, 200)
        self.assertEqual(defined.json()['amount'], '120.00')
        self.assertEqual(defined.json()['customer_price'], '500.00')
        financial = self.client.get(
            reverse('api-inspection-financial', args=[inspection['id']]),
        )
        self.assertEqual(financial.json()['customer_price'], '500.00')
        self.assertEqual(financial.json()['online_payment_amount'], '500.00')
        self.assertEqual(
            financial.json()['commission']['company_share'],
            '380.00',
        )
        validated = self.client.patch(
            commission_url,
            data={'status': 'validated'},
            content_type='application/json',
        )
        self.assertEqual(validated.json()['status'], 'validated')
        paid = self.client.patch(
            commission_url,
            data={'status': 'paid'},
            content_type='application/json',
        )
        self.assertEqual(paid.json()['status'], 'paid')

        dashboard = self.client.get(reverse('api-dashboard')).json()
        self.assertEqual(dashboard['revenue_total'], '500.00')
        self.assertEqual(dashboard['commissions_total'], '120.00')
        self.assertEqual(dashboard['net_result'], '380.00')
        self.assertEqual(len(dashboard['monthly_activity']), 6)
        self.assertEqual(dashboard['monthly_activity'][-1]['inspections'], 1)
        self.assertEqual(dashboard['monthly_revenue'][-1]['revenue'], '500.00')
        self.client.defaults['HTTP_AUTHORIZATION'] = (
            f'Bearer {self._token_for(self.expert)}'
        )
        personal = self.client.get(reverse('api-commissions'))
        self.assertEqual(personal.status_code, 200)
        self.assertEqual(personal.json()['commissions'][0]['status'], 'paid')
        self.assertNotIn('customer_price', personal.json()['commissions'][0])
        self.assertNotIn('vehicle', personal.json()['commissions'][0])
        personal_financial = self.client.get(
            reverse('api-inspection-financial', args=[inspection['id']]),
        )
        self.assertEqual(personal_financial.status_code, 200)
        self.assertEqual(personal_financial.json()['customer_price'], '500.00')
        self.assertNotIn(
            'company_share',
            personal_financial.json()['commission'],
        )
        personal_dashboard = self.client.get(reverse('api-dashboard')).json()
        self.assertNotIn('revenue_total', personal_dashboard)
        self.assertNotIn('revenue', personal_dashboard['monthly_activity'][-1])

    def test_listing_visibility_is_owner_scoped_until_admin_publishes(self):
        self._grant(self.expert, 'add_listing', 'view_listings')
        created = self.client.post(
            reverse('api-listings'),
            data={
                'make': 'Dacia',
                'model': 'Sandero',
                'year': 2021,
                'mileage': 45000,
                'price': '85000',
            },
            content_type='application/json',
        )
        self.assertEqual(created.status_code, 201)
        self.assertEqual(created.json()['status'], 'draft')
        self._grant(self.expert, 'edit_listings')
        expert_edit = self.client.patch(
            reverse('api-listing-detail', args=[created.json()['id']]),
            data={'status': 'published'},
            content_type='application/json',
        )
        self.assertEqual(expert_edit.status_code, 403)

        admin = User.objects.create_superuser(
            username='listing-admin',
            email='listing@example.test',
            password='admin-password',
        )
        self.client.defaults['HTTP_AUTHORIZATION'] = f'Bearer {self._token_for(admin)}'
        published = self.client.patch(
            reverse('api-listing-detail', args=[created.json()['id']]),
            data={'status': 'published'},
            content_type='application/json',
        )
        self.assertEqual(published.json()['status'], 'published')

        self.client.defaults['HTTP_AUTHORIZATION'] = (
            f'Bearer {self._token_for(self.other_expert)}'
        )
        self._grant(self.other_expert, 'view_listings')
        visible = self.client.get(reverse('api-listings'))
        self.assertEqual(len(visible.json()['listings']), 1)
        self.assertEqual(visible.json()['listings'][0]['model'], 'Sandero')

    def test_listing_photos_are_private_until_listing_is_published(self):
        self._grant(self.expert, 'add_listing', 'view_listings')
        created = self.client.post(
            reverse('api-listings'),
            data={
                'make': 'Dacia',
                'model': 'Sandero',
                'year': 2021,
                'description': 'Véhicule bien entretenu.',
            },
            content_type='application/json',
        )
        self.assertEqual(created.status_code, 201)
        listing_id = created.json()['id']
        upload_url = reverse('api-listing-photos', args=[listing_id])
        image_bytes = b'\xff\xd8\xff' + b'\x00' * 24

        with tempfile.TemporaryDirectory() as media_root:
            with self.settings(MEDIA_ROOT=media_root):
                uploaded = self.client.post(
                    upload_url,
                    data={
                        'photo': SimpleUploadedFile(
                            'vehicle.jpg',
                            image_bytes,
                            content_type='image/jpeg',
                        ),
                    },
                )
                self.assertEqual(uploaded.status_code, 201)
                self.assertEqual(VehicleListingPhoto.objects.count(), 1)

                self.client.defaults['HTTP_AUTHORIZATION'] = (
                    f'Bearer {self._token_for(self.other_expert)}'
                )
                self._grant(self.other_expert, 'view_listings')
                self.assertEqual(
                    self.client.get(reverse('api-listings')).json()['listings'],
                    [],
                )
                self.assertEqual(
                    self.client.get(
                        reverse(
                            'api-listing-photo-detail',
                            args=[uploaded.json()['id']],
                        ),
                    ).status_code,
                    404,
                )

                admin = User.objects.create_superuser(
                    username='listing-photo-admin',
                    email='listing-photo@example.test',
                    password='admin-password',
                )
                self.client.defaults['HTTP_AUTHORIZATION'] = (
                    f'Bearer {self._token_for(admin)}'
                )
                published = self.client.patch(
                    reverse('api-listing-detail', args=[listing_id]),
                    data={'status': 'published'},
                    content_type='application/json',
                )
                self.assertEqual(published.status_code, 200)

                self.client.defaults['HTTP_AUTHORIZATION'] = (
                    f'Bearer {self._token_for(self.other_expert)}'
                )
                visible = self.client.get(reverse('api-listings')).json()[
                    'listings'
                ][0]
                self.assertEqual(visible['description'], 'Véhicule bien entretenu.')
                self.assertEqual(len(visible['photos']), 1)
                download = self.client.get(
                    reverse(
                        'api-listing-photo-detail',
                        args=[uploaded.json()['id']],
                    ),
                )
                self.assertEqual(download.status_code, 200)
                self.assertEqual(b''.join(download.streaming_content), image_bytes)

    def test_admin_settings_are_persisted_and_expert_access_is_denied(self):
        admin = User.objects.create_superuser(
            username='settings-admin',
            email='settings@example.test',
            password='admin-password',
        )
        self.client.defaults['HTTP_AUTHORIZATION'] = f'Bearer {self._token_for(admin)}'
        saved = self.client.put(
            reverse('api-settings'),
            data={'settings': {'company': {'name': 'BHK AutoDiag'}, 'taxes': {'rate': 20}}},
            content_type='application/json',
        )
        self.assertEqual(saved.status_code, 200)
        self.assertEqual(
            self.client.get(reverse('api-settings')).json()['settings']['company']['name'],
            'BHK AutoDiag',
        )
        self.client.defaults['HTTP_AUTHORIZATION'] = (
            f'Bearer {self._token_for(self.expert)}'
        )
        self.assertEqual(self.client.get(reverse('api-settings')).status_code, 403)

    def test_report_settings_are_limited_to_report_viewers_and_public_categories(self):
        admin = User.objects.create_superuser(
            username='report-settings-admin',
            email='report-settings@example.test',
            password='admin-password',
        )
        self.client.defaults['HTTP_AUTHORIZATION'] = f'Bearer {self._token_for(admin)}'
        self.client.put(
            reverse('api-settings'),
            data={
                'settings': {
                    'company': {'name': 'BHK AutoDiag'},
                    'report': {'title': 'Rapport personnalisé'},
                    'conclusions': {'labels': ['Bon état']},
                    'language': 'ar',
                    'taxes': {'rate': 20},
                },
            },
            content_type='application/json',
        )

        self.client.defaults['HTTP_AUTHORIZATION'] = (
            f'Bearer {self._token_for(self.expert)}'
        )
        self.assertEqual(
            self.client.get(reverse('api-report-settings')).status_code,
            403,
        )
        self._grant(self.expert, 'view_reports')
        response = self.client.get(reverse('api-report-settings'))

        self.assertEqual(response.status_code, 200)
        self.assertEqual(
            response.json()['settings'],
            {
                'company': {'name': 'BHK AutoDiag'},
                'report': {'title': 'Rapport personnalisé'},
                'conclusions': {'labels': ['Bon état']},
                'language': 'ar',
            },
        )
        self.assertNotIn('taxes', response.json()['settings'])

    def test_generated_report_versions_are_archived_without_overwriting(self):
        self._grant(self.expert, 'create_inspection', 'view_reports')
        created = self.client.post(
            reverse('api-inspections'),
            data={'vehicle': self.vehicle},
            content_type='application/json',
        )
        inspection_id = created.json()['id']
        url = reverse('api-inspection-reports', args=[inspection_id])
        pdf = b'%PDF-1.4\nBHK report'
        with tempfile.TemporaryDirectory() as media_root:
            with self.settings(MEDIA_ROOT=media_root):
                versions = []
                for _ in range(2):
                    response = self.client.post(
                        url,
                        data={
                            'report': SimpleUploadedFile(
                                'report.pdf',
                                pdf,
                                content_type='application/pdf',
                            ),
                        },
                    )
                    self.assertEqual(response.status_code, 201)
                    versions.append(response.json()['version'])
                self.assertEqual(versions, [1, 2])
                archive = self.client.get(
                    reverse(
                        'api-report-archive-detail',
                        args=[response.json()['id']],
                    ),
                )
                self.assertEqual(archive.status_code, 200)
                self.assertEqual(b''.join(archive.streaming_content), pdf)
