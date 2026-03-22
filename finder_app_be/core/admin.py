from django.contrib import admin
from .models import UserProfile, FoundItem, LostItem, ReportIssue, ReviewIssue

admin.site.register(UserProfile)
admin.site.register(FoundItem)
admin.site.register(LostItem)
admin.site.register(ReportIssue)
admin.site.register(ReviewIssue)