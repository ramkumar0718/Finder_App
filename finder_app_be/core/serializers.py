from rest_framework import serializers
from .models import UserProfile, FoundItem, LostItem, OwnershipRequest, ReportIssue, ReviewIssue


class UserLostItemsSerializer(serializers.ModelSerializer):
    class Meta:
        model = LostItem
        fields = ['post_id', 'item_name', 'item_img']


class OwnershipRequestSerializer(serializers.ModelSerializer):
    finder_id = serializers.ReadOnlyField(source='finder.user_id')
    owner_id = serializers.ReadOnlyField(source='owner.user_id')
    
    owner = serializers.SlugRelatedField(
        slug_field='user_id',
        queryset=UserProfile.objects.all()
    )
    found_item = serializers.SlugRelatedField(
        slug_field='post_id',
        queryset=FoundItem.objects.all()
    )
    lost_item = serializers.SlugRelatedField(
        slug_field='post_id',
        queryset=LostItem.objects.all(),
        required=False,
        allow_null=True
    )
    
    found_item_details = serializers.SerializerMethodField()
    lost_item_details = serializers.SerializerMethodField()

    class Meta:
        model = OwnershipRequest
        fields = [
            'id', 'finder', 'owner', 'found_item', 'lost_item', 
            'status', 'created_at', 'updated_at',
            'finder_id', 'owner_id', 'found_item_details', 'lost_item_details'
        ]
        read_only_fields = ['id', 'finder', 'created_at', 'updated_at', 'status']

    def get_found_item_details(self, obj):
        return {
            'item_name': obj.found_item.item_name,
            'item_img': obj.found_item.item_img.url if obj.found_item.item_img else None,
            'post_id': obj.found_item.post_id
        }

    def get_lost_item_details(self, obj):
        if obj.lost_item:
            return {
                'item_name': obj.lost_item.item_name,
                'item_img': obj.lost_item.item_img.url if obj.lost_item.item_img else None,
                'post_id': obj.lost_item.post_id
            }
        return None

class UserProfileSerializer(serializers.ModelSerializer):
    class Meta:
        model = UserProfile
        fields = ['user_name', 'user_id', 'name', 'profile_pic_url', 'email', 'is_email_verified', 'found_count', 'lost_count', 'role', 'last_opened', 'joined_date']
        read_only_fields = ['user_id', 'profile_pic_url', 'email', 'is_email_verified', 'found_count', 'lost_count', 'role', 'last_opened', 'joined_date']


class AdminUserSerializer(serializers.ModelSerializer):
    status = serializers.SerializerMethodField()

    class Meta:
        model = UserProfile
        fields = ['firebase_uid', 'user_name', 'user_id', 'name', 'profile_pic_url', 'email', 'last_opened', 'status', 'joined_date']

    def get_status(self, obj):
        if getattr(obj, 'role', 'user') == 'deleted':
            return "Proxy"
            
        if not obj.last_opened:
            return "Inactive"
        
        from django.utils import timezone
        from datetime import timedelta
        
        one_month_ago = timezone.now() - timedelta(days=30)
        return "Active" if obj.last_opened >= one_month_ago else "Inactive"


class SendOTPSerializer(serializers.Serializer):
    email = serializers.EmailField(required=True)
    firebase_uid = serializers.CharField(required=False, max_length=128, allow_blank=True)
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
    posted_by_name = serializers.ReadOnlyField(source='posted_by.user_name')
    posted_by_role = serializers.ReadOnlyField(source='posted_by.role')
    posted_by_profile_pic = serializers.SerializerMethodField()
    owner_id = serializers.SlugRelatedField(
        slug_field='user_id',
        queryset=UserProfile.objects.all(),
        required=False,
        allow_null=True
    )
    owner_role = serializers.ReadOnlyField(source='owner_id.role')
    has_issue = serializers.SerializerMethodField()
    
    class Meta:
        model = FoundItem
        fields = [
            'post_id', 'item_name', 'item_img', 'category', 'description',
            'color_id', 'color_name', 'location', 'date', 'status', 'posted_by', 'posted_by_name', 
            'posted_by_role', 'posted_by_profile_pic', 'posted_time',
            'owner_identified', 'owner_id', 'owner_role', 'info', 'matched_post', 'has_issue'
        ]
        read_only_fields = ['post_id', 'posted_by', 'posted_by_profile_pic', 'posted_time']

    def validate_description(self, value):
        if value:
            import re
            clean = re.compile('<.*?>')
            return re.sub(clean, '', value)
        return value
    
    def get_posted_by_profile_pic(self, obj):
        request = self.context.get('request')
        if obj.posted_by and obj.posted_by.profile_pic_url:
            return obj.posted_by.profile_pic_url
        return None

    def get_has_issue(self, obj):
        from .models import ReportIssue
        return ReportIssue.objects.filter(post_id=obj.post_id).exists()



class LostItemSerializer(serializers.ModelSerializer):
    posted_by = serializers.ReadOnlyField(source='posted_by.user_id')
    posted_by_name = serializers.ReadOnlyField(source='posted_by.user_name')
    posted_by_role = serializers.ReadOnlyField(source='posted_by.role')
    posted_by_profile_pic = serializers.SerializerMethodField()
    finder_id = serializers.SlugRelatedField(
        slug_field='user_id',
        queryset=UserProfile.objects.all(),
        required=False,
        allow_null=True
    )
    finder_role = serializers.ReadOnlyField(source='finder_id.role')
    has_issue = serializers.SerializerMethodField()
    
    class Meta:
        model = LostItem
        fields = [
            'post_id', 'item_name', 'item_img', 'category', 'description',
            'color_id', 'color_name', 'location', 'date', 'status', 'posted_by', 'posted_by_name', 
            'posted_by_role', 'posted_by_profile_pic', 'posted_time',
            'finder_identified', 'finder_id', 'finder_role', 'info', 'matched_post', 'has_issue'
        ]
        read_only_fields = ['post_id', 'posted_by', 'posted_by_profile_pic', 'posted_time']

    def validate_description(self, value):
        if value:
            import re
            clean = re.compile('<.*?>')
            return re.sub(clean, '', value)
        return value
    
    def get_posted_by_profile_pic(self, obj):
        request = self.context.get('request')
        if obj.posted_by and obj.posted_by.profile_pic_url:
            return obj.posted_by.profile_pic_url
        return None

    def get_has_issue(self, obj):
        from .models import ReportIssue
        return ReportIssue.objects.filter(post_id=obj.post_id).exists()



class ReportIssueSerializer(serializers.ModelSerializer):
    class Meta:
        model = ReportIssue
        fields = [
            'issue_id', 'post_id', 'item_name', 'reported_user_id',
            'issue_status', 'issue_category', 'description',
            'proof_doc_1', 'proof_doc_2', 'posted_by', 'posted_time',
        ]
        read_only_fields = ['issue_id', 'posted_time']



class ReviewIssueSerializer(serializers.ModelSerializer):
    class Meta:
        model = ReviewIssue
        fields = [
            'review_id', 'report_id', 'post_id', 'reported_user_id',
            'issuer_user_id', 'review_status', 'review_category',
            'description', 'reviewed_by', 'reviewed_time',
        ]
        read_only_fields = ['review_id', 'reviewed_time']
