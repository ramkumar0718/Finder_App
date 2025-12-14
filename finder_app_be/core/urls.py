from django.urls import path
from .views import (
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
    LostItemDeleteView
)

urlpatterns = [
    path('profile/', UserProfileView.as_view(), name='user-profile'),
    path('profile/upload-pic/', ProfilePictureUploadView.as_view(), name='profile-pic-upload'),
    
    # OTP endpoints
    path('auth/send-otp/', SendOTPView.as_view(), name='send-otp'),
    path('auth/verify-otp/', VerifyOTPView.as_view(), name='verify-otp'),
    path('auth/resend-otp/', ResendOTPView.as_view(), name='resend-otp'),
    path('auth/google-login/', GoogleLoginView.as_view(), name='google-login'),
    
    # Found Items
    path('found-items/create/', FoundItemCreateView.as_view(), name='create-found-item'),
    path('found-items/', FoundItemListView.as_view(), name='list-found-items'),
    path('found-items/<str:post_id>/', FoundItemUpdateView.as_view(), name='update-found-item'),
    path('found-items/<str:post_id>/delete/', FoundItemDeleteView.as_view(), name='delete-found-item'),
    
    # Lost Items
    path('lost-items/create/', LostItemCreateView.as_view(), name='create-lost-item'),
    path('lost-items/', LostItemListView.as_view(), name='list-lost-items'),
    path('lost-items/<str:post_id>/', LostItemUpdateView.as_view(), name='update-lost-item'),
    path('lost-items/<str:post_id>/delete/', LostItemDeleteView.as_view(), name='delete-lost-item'),
]
