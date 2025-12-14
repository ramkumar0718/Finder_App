from rest_framework import serializers
from .models import UserProfile, EmailOTP, FoundItem, LostItem

class UserProfileSerializer(serializers.ModelSerializer):
    email = serializers.SerializerMethodField()
    
    class Meta:
        model = UserProfile
        # firebase_uid is excluded as it's the primary key and shouldn't be updated by user
        fields = ['user_name', 'user_id', 'name', 'bio', 'profile_pic_url', 'email', 'is_email_verified', 'found_count', 'lost_count']
        read_only_fields = ['user_id', 'profile_pic_url', 'email', 'is_email_verified', 'found_count', 'lost_count']

    def get_email(self, obj):
        # Retrieve the email from the Firebase token's decoded claims if available
        # Note: This is an approximation. In a real app, you might query Firebase Admin SDK
        # or rely on the token claims during the authentication process.
        # Since we don't have the token here, we default to the UID.
        return f"{obj.firebase_uid}@example.com" # Placeholder logic


class SendOTPSerializer(serializers.Serializer):
    email = serializers.EmailField(required=True)
    firebase_uid = serializers.CharField(required=True, max_length=128)
    user_name = serializers.CharField(required=False, max_length=50, allow_blank=True)
    
    def validate_email(self, value):
        if not value:
            raise serializers.ValidationError("Email is required.")
        return value.lower()


class VerifyOTPSerializer(serializers.Serializer):
    email = serializers.EmailField(required=True)
    otp_code = serializers.CharField(required=True, min_length=6, max_length=6)
    
    def validate_otp_code(self, value):
        if not value.isdigit():
            raise serializers.ValidationError("OTP must contain only digits.")
        return value
        

class GoogleLoginSerializer(serializers.Serializer):
    email = serializers.EmailField(required=True)
    firebase_uid = serializers.CharField(required=True, max_length=128)
    user_name = serializers.CharField(required=False, max_length=50, allow_blank=True)
    user_id = serializers.CharField(required=False, max_length=100, allow_blank=True)
    profile_pic_url = serializers.URLField(required=False, allow_blank=True, allow_null=True)


class FoundItemSerializer(serializers.ModelSerializer):
    posted_by = serializers.ReadOnlyField(source='posted_by.user_id')
    posted_by_profile_pic = serializers.SerializerMethodField()
    
    class Meta:
        model = FoundItem
        fields = [
            'post_id', 'item_name', 'item_img', 'category', 'description',
            'color', 'location', 'date', 'status', 'posted_by', 'posted_by_profile_pic', 'posted_time',
            'owner_identified', 'owner_id'
        ]
        read_only_fields = ['post_id', 'posted_by', 'posted_by_profile_pic', 'posted_time', 'owner_identified', 'owner_id', 'status']
    
    def get_posted_by_profile_pic(self, obj):
        request = self.context.get('request')
        if obj.posted_by and obj.posted_by.profile_pic_url:
            if request:
                return request.build_absolute_uri(obj.posted_by.profile_pic_url)
            return obj.posted_by.profile_pic_url
        return None


class LostItemSerializer(serializers.ModelSerializer):
    posted_by = serializers.ReadOnlyField(source='posted_by.user_id')
    posted_by_profile_pic = serializers.SerializerMethodField()
    
    class Meta:
        model = LostItem
        fields = [
            'post_id', 'item_name', 'item_img', 'category', 'description',
            'color', 'location', 'date', 'status', 'posted_by', 'posted_by_profile_pic', 'posted_time',
            'finder_identified', 'finder_id'
        ]
        read_only_fields = ['post_id', 'posted_by', 'posted_by_profile_pic', 'posted_time', 'finder_identified', 'finder_id', 'status']
    
    def get_posted_by_profile_pic(self, obj):
        request = self.context.get('request')
        if obj.posted_by and obj.posted_by.profile_pic_url:
            if request:
                return request.build_absolute_uri(obj.posted_by.profile_pic_url)
            return obj.posted_by.profile_pic_url
        return None
