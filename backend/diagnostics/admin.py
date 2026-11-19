
from django.contrib import admin
from django.db.models import Case, IntegerField, Value, When

from diagnostics.models import (
    ExpertProfile,
    ExpertPermission,
    InspectionSequence,
    Inspection,
    ApiToken,
    InspectionPhoto,
    Commission,
    Expense,
    VehicleListing,
    ApplicationSettings,
    InternalNotification,
    ReportArchive,
    VehicleListingPhoto,
)

admin.site.register(ExpertProfile)
admin.site.register(ExpertPermission)
admin.site.register(ApiToken)
admin.site.register(InspectionSequence)
@admin.register(Inspection)
class InspectionAdmin(admin.ModelAdmin):
    list_display = ('reference', 'expert', 'status', 'created_at')
    list_filter = ('status',)

    def get_queryset(self, request):
        return super().get_queryset(request).order_by(
            Case(
                When(status='in_progress', then=Value(0)),
                default=Value(1),
                output_field=IntegerField(),
            ),
            '-created_at',
        )


admin.site.register(InspectionPhoto)


@admin.register(Commission)
class CommissionAdmin(admin.ModelAdmin):
    list_display = ('inspection', 'status', 'amount', 'updated_at')
    list_filter = ('status',)

    def get_queryset(self, request):
        return super().get_queryset(request).order_by(
            Case(
                When(status='pending', then=Value(0)),
                When(status='defined', then=Value(1)),
                When(status='validated', then=Value(2)),
                default=Value(3),
                output_field=IntegerField(),
            ),
            '-updated_at',
        )


admin.site.register(Expense)
admin.site.register(VehicleListing)
admin.site.register(ApplicationSettings)
admin.site.register(InternalNotification)
admin.site.register(ReportArchive)
admin.site.register(VehicleListingPhoto)
