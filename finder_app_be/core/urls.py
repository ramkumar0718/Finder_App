from django.urls import path, include
from rest_framework.routers import DefaultRouter
from .views import (
    MyApiView,
    UserProfileView, 
    ProfilePictureUploadView,
    SendOTPView,
    VerifyOTPView,
    ResendOTPView,
    GoogleLoginView,
    FoundItemCreateView,
    FoundItemListView,
    FoundItemUpdateView,
    FoundItemDeleteView,
    LostItemCreateView,
    LostItemListView,
    LostItemUpdateView,
    LostItemDeleteView,
    UserLostItemsView,
    OwnershipRequestViewSet,
    RequestEmailChangeOTPView,
    VerifyEmailChangeOTPView,
    AdminUserListView,
    AdminDeleteUserView,
    AdminUserProfileView,
    AdminItemListView,
    AdminAllUsersView,
    AdminDirectAssignView,
    AdminUnassignView,
    ReportIssueCreateView,
    ReportIssueListView,
    AdminIssueSummaryView,
    ReviewIssueCreateView,
    ReviewIssueDetailView,
    ReviewIssueUpdateDeleteView,
    AdminReportIssueDeleteView,
    DeleteAccountView,
    AdminProxyUserView,
    AdminAnalyticsView,
    CleanupFirebaseUsersView,
)

router = DefaultRouter()
router.register(r'ownership-requests', OwnershipRequestViewSet, basename='ownership-request')

urlpatterns = [
    path('message/', MyApiView.as_view(), name='message'),

    path('profile/', UserProfileView.as_view(), name='user-profile'),
    path('profile/upload-pic/', ProfilePictureUploadView.as_view(), name='profile-pic-upload'),
    path('delete-account/', DeleteAccountView.as_view(), name='delete-account'),
    
    path('auth/send-otp/', SendOTPView.as_view(), name='send-otp'),
    path('auth/verify-otp/', VerifyOTPView.as_view(), name='verify-otp'),
    path('auth/resend-otp/', ResendOTPView.as_view(), name='resend-otp'),
    path('auth/request-email-change-otp/', RequestEmailChangeOTPView.as_view(), name='request-email-change-otp'),
    path('auth/verify-email-change-otp/', VerifyEmailChangeOTPView.as_view(), name='verify-email-change-otp'),
    path('auth/google-login/', GoogleLoginView.as_view(), name='google-login'),
    
    path('found-items/create/', FoundItemCreateView.as_view(), name='create-found-item'),
    path('found-items/', FoundItemListView.as_view(), name='list-found-items'),
    path('found-items/<str:post_id>/', FoundItemUpdateView.as_view(), name='update-found-item'),
    path('found-items/<str:post_id>/delete/', FoundItemDeleteView.as_view(), name='delete-found-item'),
    
    path('lost-items/create/', LostItemCreateView.as_view(), name='create-lost-item'),
    path('lost-items/', LostItemListView.as_view(), name='list-lost-items'),
    path('lost-items/<str:post_id>/', LostItemUpdateView.as_view(), name='update-lost-item'),
    path('lost-items/<str:post_id>/delete/', LostItemDeleteView.as_view(), name='delete-lost-item'),
    
    path('users/<str:user_id>/lost-items/', UserLostItemsView.as_view(), name='user-lost-items'),
    
    path('admin/users/', AdminUserListView.as_view(), name='admin-user-list'),
    path('admin/users/<str:firebase_uid>/delete/', AdminDeleteUserView.as_view(), name='admin-delete-user'),
    path('admin/users/<str:firebase_uid>/proxy/', AdminProxyUserView.as_view(), name='admin-proxy-user'),
    path('admin/users/<str:user_id>/profile/', AdminUserProfileView.as_view(), name='admin-user-profile'),
    path('admin/analytics/', AdminAnalyticsView.as_view(), name='admin-analytics'),
    path('admin/cleanup-firebase/', CleanupFirebaseUsersView.as_view(), name='cleanup-firebase'),
    
    path('admin/items/', AdminItemListView.as_view(), name='admin-item-list'),
    
    path('admin/all-users/', AdminAllUsersView.as_view(), name='admin-all-users'),
    path('admin/direct-assign/', AdminDirectAssignView.as_view(), name='admin-direct-assign'),
    path('admin/unassign/', AdminUnassignView.as_view(), name='admin-unassign'),
    
    path('', include(router.urls)),

    path('report-issues/', ReportIssueCreateView.as_view(), name='report-issue-create'),
    path('report-issues/list/', ReportIssueListView.as_view(), name='report-issue-list'),
    path('admin/report-issues/summary/', AdminIssueSummaryView.as_view(), name='admin-issue-summary'),
    path('admin/report-issues/delete/', AdminReportIssueDeleteView.as_view(), name='admin-report-issue-delete'),

    path('review-issues/', ReviewIssueCreateView.as_view(), name='review-issue-create'),
    path('review-issues/detail/', ReviewIssueDetailView.as_view(), name='review-issue-detail'),
    path('review-issues/update-delete/', ReviewIssueUpdateDeleteView.as_view(), name='review-issue-update-delete'),
]
