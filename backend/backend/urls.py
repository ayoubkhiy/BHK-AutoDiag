"""
URL configuration for backend project.

The `urlpatterns` list routes URLs to views. For more information please see:
    https://docs.djangoproject.com/en/6.1/topics/http/urls/
Examples:
Function views
    1. Add an import:  from my_app import views
    2. Add a URL to urlpatterns:  path('', views.home, name='home')
Class-based views
    1. Add an import:  from other_app.views import Home
    2. Add a URL to urlpatterns:  path('', Home.as_view(), name='home')
Including another URLconf
    1. Import the include() function: from django.urls import include, path
    2. Add a URL to urlpatterns:  path('blog/', include('blog.urls'))
"""
from django.contrib import admin
from django.urls import path

from diagnostics import api

urlpatterns = [
    path('admin/', admin.site.urls),
    path('api/login/', api.login, name='api-login'),
    path('api/logout/', api.logout, name='api-logout'),
    path('api/me/', api.me, name='api-me'),
    path('api/account/preferences/', api.account_preferences, name='api-account-preferences'),
    path('api/account/password/', api.change_password, name='api-account-password'),
    path('api/dashboard/', api.dashboard, name='api-dashboard'),
    path('api/inspections/', api.inspections, name='api-inspections'),
    path('api/inspections/<int:inspection_id>/', api.inspection_detail, name='api-inspection-detail'),
    path('api/inspections/<int:inspection_id>/report/', api.inspection_report, name='api-inspection-report'),
    path('api/inspections/<int:inspection_id>/finish/', api.finish_inspection, name='api-inspection-finish'),
    path('api/inspections/<int:inspection_id>/photos/', api.inspection_photos, name='api-inspection-photos'),
    path('api/photos/<int:photo_id>/', api.photo_detail, name='api-photo-detail'),
    path('api/inspections/<int:inspection_id>/financial/', api.inspection_financial, name='api-inspection-financial'),
    path('api/inspections/<int:inspection_id>/reports/', api.inspection_reports, name='api-inspection-reports'),
    path('api/reports/<int:report_id>/', api.report_archive_detail, name='api-report-archive-detail'),
    path('api/commissions/', api.commissions, name='api-commissions'),
    path('api/commissions/<int:commission_id>/', api.commissions, name='api-commission-detail'),
    path('api/expenses/', api.expenses, name='api-expenses'),
    path('api/listings/', api.listings, name='api-listings'),
    path('api/listings/<int:listing_id>/photos/', api.listing_photos, name='api-listing-photos'),
    path('api/listings/<int:listing_id>/', api.listing_detail, name='api-listing-detail'),
    path('api/listing-photos/<int:photo_id>/', api.listing_photo_detail, name='api-listing-photo-detail'),
    path('api/settings/', api.app_settings, name='api-settings'),
    path('api/report-settings/', api.report_settings, name='api-report-settings'),
    path('api/notifications/', api.notifications, name='api-notifications'),
    path('api/notifications/<int:notification_id>/', api.notifications, name='api-notification-detail'),
    path('api/experts/', api.experts, name='api-experts'),
    path('api/experts/<int:expert_id>/', api.expert_detail, name='api-expert-detail'),
    path('api/experts/<int:expert_id>/permissions/', api.expert_permissions, name='api-expert-permissions'),
]
