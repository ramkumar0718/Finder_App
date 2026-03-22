from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework import status, viewsets, generics, permissions, filters
from django.db.models import Count, Q
from django.db.models.functions import TruncMonth, TruncWeek, TruncYear
from rest_framework.decorators import action
from rest_framework.parsers import MultiPartParser, FormParser
from rest_framework.permissions import AllowAny, IsAuthenticated, IsAdminUser
from django.utils import timezone
from django.db import models
from datetime import timedelta
from django.shortcuts import get_object_or_404
from .firebase_utils import cleanup_orphaned_firebase_users
from .models import UserProfile, EmailOTP, FoundItem, LostItem, OwnershipRequest, ReportIssue
from .serializers import (
    UserProfileSerializer, SendOTPSerializer, VerifyOTPSerializer, 
    GoogleLoginSerializer, FoundItemSerializer, LostItemSerializer,
    OwnershipRequestSerializer, UserLostItemsSerializer, AdminUserSerializer,
    ReportIssueSerializer
)
from .utils import generate_otp, send_otp_email

class UserProfileView(APIView):
    """
    Handles GET and PUT requests for the authenticated user's profile.
    Requires FirebaseAuthentication.
    """
    def get(self, request):
        # request.user is set by FirebaseAuthentication to the UserProfile instance
        serializer = UserProfileSerializer(request.user)
        return Response(serializer.data)

    def put(self, request):
        serializer = UserProfileSerializer(request.user, data=request.data, partial=True)
        if serializer.is_valid():
            serializer.save()
            return Response(serializer.data)
        return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)

class ProfilePictureUploadView(APIView):
    """
    Handles POST request for uploading a profile picture.
    Saves the image to media/profile_pics/ directory.
    """
    parser_classes = (MultiPartParser, FormParser)

    def post(self, request, format=None):
        if 'profile_pic' not in request.FILES:
            return Response({'error': 'No profile_pic file provided'}, status=status.HTTP_400_BAD_REQUEST)

        profile_pic = request.FILES['profile_pic']
        
        allowed_types = ['image/jpeg', 'image/jpg', 'image/png', 'image/webp']
        if profile_pic.content_type not in allowed_types:
            return Response({'error': 'Invalid file type. Only JPEG, PNG, and WebP images are allowed.'}, status=status.HTTP_400_BAD_REQUEST)
        
        if profile_pic.size > 5 * 1024 * 1024:
            return Response({'error': 'File size too large. Maximum size is 5MB.'}, status=status.HTTP_400_BAD_REQUEST)

        try:
            profile = request.user
            
            import cloudinary.uploader
            
            public_id = f"IMG_{profile.user_id}"
            
            upload_result = cloudinary.uploader.upload(
                profile_pic,
                public_id=public_id,
                folder="profile_pics",
                overwrite=True,
                resource_type="image"
            )
            
            profile_pic_url = upload_result.get('secure_url')
            
            profile.profile_pic_url = profile_pic_url
            profile.save()
            
            return Response({
                'profile_pic_url': profile_pic_url,
                'message': 'Profile picture uploaded successfully'
            }, status=status.HTTP_200_OK)
        except Exception as e:
            return Response({'error': str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)



class GoogleLoginView(APIView):
    """
    Handles Google Sign-In user synchronization.
    Creates or updates user profile with automatic user_id generation.
    """
    permission_classes = [AllowAny]

    def post(self, request):
        serializer = GoogleLoginSerializer(data=request.data)
        if not serializer.is_valid():
            return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)

        email = serializer.validated_data['email']
        firebase_uid = serializer.validated_data['firebase_uid']
        user_name = serializer.validated_data.get('user_name', '')
        profile_pic_url = serializer.validated_data.get('profile_pic_url', '')

        import re
        s_user_name = re.sub(r'[^a-zA-Z0-9_]', '', user_name.replace(' ', '')) if user_name else email.split('@')[0]
        s_user_name = s_user_name[:50]

        try:
            user_profile, created = UserProfile.objects.get_or_create(
                firebase_uid=firebase_uid,
                defaults={
                    'name': s_user_name,
                    'user_name': s_user_name,
                    'profile_pic_url': profile_pic_url,
                    'is_email_verified': True,
                    'role': 'user'
                }
            )

            if created and not user_profile.user_id:
                user_profile.save()

            if not created:
                if user_name and not user_profile.user_name:
                    user_profile.user_name = user_name
                    user_profile.name = user_name
                if profile_pic_url:
                    user_profile.profile_pic_url = profile_pic_url
                
                user_profile.is_email_verified = True
                user_profile.save()

            return Response({
                'message': 'User synced successfully',
                'user_id': user_profile.user_id,
                'user_name': user_profile.user_name
            }, status=status.HTTP_200_OK)

        except Exception as e:
            return Response(
                {'error': f'Failed to sync user: {str(e)}'},
                status=status.HTTP_500_INTERNAL_SERVER_ERROR
            )


# OTP Views

class SendOTPView(APIView):
    """
    Send OTP code to user's email.
    This endpoint does not require authentication (used during signup).
    """
    permission_classes = [AllowAny]
    
    def post(self, request):
        serializer = SendOTPSerializer(data=request.data)
        if not serializer.is_valid():
            return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)
        
        email = serializer.validated_data['email']
        firebase_uid = serializer.validated_data.get('firebase_uid')
        user_name = serializer.validated_data.get('user_name', '')
        
        # Sanitize incoming user_name: remove non-alphanumeric (except underscores)
        import re
        if user_name:
            user_name = re.sub(r'[^a-zA-Z0-9_]', '', user_name.replace(' ', ''))
            user_name = user_name[:50]
        
        # Get or create user profile if firebase_uid is provided
        user_profile = None
        if firebase_uid:
            try:
                user_profile, created = UserProfile.objects.get_or_create(
                    firebase_uid=firebase_uid,
                    defaults={
                        'name': email.split('@')[0],
                        'user_name': user_name if user_name else email.split('@')[0],
                        'email': email
                    }
                )
                
                if not created and user_name and not user_profile.user_name:
                    user_profile.user_name = user_name
                    user_profile.save()
                    
            except Exception as e:
                return Response({'error': str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)
            
        recent_otp_record = EmailOTP.objects.filter(
            email=email,
            created_at__gte=timezone.now() - timedelta(seconds=60)
        )
        if user_profile:
            recent_otp_record = recent_otp_record.filter(user=user_profile)
        
        recent_otp = recent_otp_record.first()
        
        if recent_otp:
            time_remaining = 60 - (timezone.now() - recent_otp.created_at).seconds
            return Response(
                {'error': f'Please wait {time_remaining} seconds before requesting a new code.'},
                status=status.HTTP_429_TOO_MANY_REQUESTS
            )
        
        otp_code = generate_otp()
        EmailOTP.objects.create(
            user=user_profile,
            email=email,
            otp_code=otp_code,
            user_name=user_name
        )
        
        recipient_name = user_profile.name if user_profile else (user_name if user_name else email.split('@')[0])
        email_sent = send_otp_email(email, otp_code, recipient_name)
        
        if email_sent:
            return Response(
                {'message': 'OTP sent successfully to your email.'},
                status=status.HTTP_200_OK
            )
        else:
            return Response(
                {'error': 'Failed to send OTP email. Please try again.'},
                status=status.HTTP_500_INTERNAL_SERVER_ERROR
            )


class VerifyOTPView(APIView):
    """
    Verify OTP code submitted by user.
    This endpoint does not require authentication (used during signup).
    """
    permission_classes = [AllowAny]
    
    def post(self, request):
        serializer = VerifyOTPSerializer(data=request.data)
        if not serializer.is_valid():
            return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)
        
        email = serializer.validated_data['email']
        otp_code = serializer.validated_data['otp_code']
        
        try:
            otp_record = EmailOTP.objects.filter(
                email=email,
                is_verified=False
            ).order_by('-created_at').first()
        except Exception:
            return Response(
                {'error': 'Invalid request.'},
                status=status.HTTP_400_BAD_REQUEST
            )
        
        if not otp_record:
            return Response(
                {'error': 'No OTP found for this email. Please request a new code.'},
                status=status.HTTP_404_NOT_FOUND
            )
        
        if otp_record.is_expired():
            return Response(
                {'error': 'OTP has expired. Please request a new code.'},
                status=status.HTTP_400_BAD_REQUEST
            )
        
        if otp_record.attempts >= 3:
            return Response(
                {'error': 'Maximum verification attempts exceeded. Please request a new code.'},
                status=status.HTTP_400_BAD_REQUEST
            )
        
        if otp_record.otp_code == otp_code:
            otp_record.is_verified = True
            otp_record.save()
            
            user_profile = otp_record.user
            if user_profile:
                user_profile.is_email_verified = True
                user_profile.save()
            
            return Response(
                {'message': 'Email verified successfully!'},
                status=status.HTTP_200_OK
            )
        else:
            otp_record.attempts += 1
            otp_record.save()
            
            remaining_attempts = 3 - otp_record.attempts
            return Response(
                {'error': f'Invalid OTP code. {remaining_attempts} attempts remaining.'},
                status=status.HTTP_400_BAD_REQUEST
            )


class ResendOTPView(APIView):
    """
    Resend OTP code to user's email.
    This endpoint does not require authentication (used during signup).
    """
    permission_classes = [AllowAny]
    
    def post(self, request):
        serializer = SendOTPSerializer(data=request.data)
        if not serializer.is_valid():
            return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)
        
        email = serializer.validated_data['email']
        firebase_uid = serializer.validated_data.get('firebase_uid')
        user_name = serializer.validated_data.get('user_name', '')
        
        import re
        if user_name:
            user_name = re.sub(r'[^a-zA-Z0-9_]', '', user_name.replace(' ', ''))
            user_name = user_name[:50]
        
        user_profile = None
        if firebase_uid:
            try:
                user_profile = UserProfile.objects.get(firebase_uid=firebase_uid)
            except UserProfile.DoesNotExist:
                return Response(
                    {'error': 'User not found.'},
                    status=status.HTTP_404_NOT_FOUND
                )
        
        prev_otps = EmailOTP.objects.filter(email=email, is_verified=False)
        if user_profile:
            prev_otps = prev_otps.filter(user=user_profile)
        prev_otps.update(is_verified=True)
        
        otp_code = generate_otp()
        EmailOTP.objects.create(
            user=user_profile,
            email=email,
            otp_code=otp_code,
            user_name=user_name
        )
        
        recipient_name = user_profile.name if user_profile else (user_name if user_name else email.split('@')[0])
        email_sent = send_otp_email(email, otp_code, recipient_name)
        
        if email_sent:
            return Response(
                {'message': 'New OTP sent successfully to your email.'},
                status=status.HTTP_200_OK
            )
        else:
            return Response(
                {'error': 'Failed to send OTP email. Please try again.'},
                status=status.HTTP_500_INTERNAL_SERVER_ERROR
            )


class RequestEmailChangeOTPView(APIView):
    """
    Send OTP code to user's NEW email for change.
    Requires authentication.
    """
    permission_classes = [IsAuthenticated]
    
    def post(self, request):
        new_email = request.data.get('new_email', '').lower()
        if not new_email:
            return Response({'error': 'New email is required.'}, status=status.HTTP_400_BAD_REQUEST)
            
        # Validate email format
        import re
        if not re.match(r"[^@]+@[^@]+\.[^@]+", new_email):
            return Response({'error': 'Invalid email format.'}, status=status.HTTP_400_BAD_REQUEST)

        # Check if new email is already in use in local database
        if UserProfile.objects.filter(email=new_email).exists():
             return Response({'error': 'This email is already registered with another account.'}, status=status.HTTP_400_BAD_REQUEST)

        # Generate and save OTP
        otp_code = generate_otp()
        EmailOTP.objects.create(
            user=request.user,
            email=new_email,
            otp_code=otp_code
        )
        
        # Send OTP email
        email_sent = send_otp_email(new_email, otp_code, request.user.name)
        
        if email_sent:
            return Response(
                {'message': f'OTP sent successfully to {new_email}.'}, 
                status=status.HTTP_200_OK
            )
        else:
            return Response(
                {'error': 'Failed to send OTP email. Please try again later.'}, 
                status=status.HTTP_500_INTERNAL_SERVER_ERROR
            )


class VerifyEmailChangeOTPView(APIView):
    """
    Verify OTP for email change and update Firebase & local profile.
    Requires authentication.
    """
    permission_classes = [IsAuthenticated]
    
    def post(self, request):
        new_email = request.data.get('new_email', '').lower()
        otp_code = request.data.get('otp_code', '')
        
        if not new_email or not otp_code:
            return Response({'error': 'New email and OTP code are required.'}, status=status.HTTP_400_BAD_REQUEST)
            
        # Find the most recent OTP for this email and current authenticated user
        otp_record = EmailOTP.objects.filter(
            user=request.user,
            email=new_email,
            is_verified=False
        ).order_by('-created_at').first()
        
        if not otp_record:
            return Response(
                {'error': 'No pending OTP verification found for this email. Please request a new code.'}, 
                status=status.HTTP_404_NOT_FOUND
            )
            
        # Check if OTP is expired
        if otp_record.is_expired():
            return Response({'error': 'OTP has expired. Please request a new code.'}, status=status.HTTP_400_BAD_REQUEST)
            
        # Check attempts
        if otp_record.attempts >= 3:
            return Response({'error': 'Too many failed attempts. Please request a new code.'}, status=status.HTTP_400_BAD_REQUEST)

        # Verify OTP
        if otp_record.otp_code != otp_code:
            otp_record.attempts += 1
            otp_record.save()
            remaining = 3 - otp_record.attempts
            return Response({'error': f'Invalid code. {remaining} attempts remaining.'}, status=status.HTTP_400_BAD_REQUEST)
            
        # OTP is valid. Now update Firebase Auth and local profile.
        from firebase_admin import auth as firebase_auth
        try:
            # Update Firebase Auth email
            firebase_auth.update_user(
                request.user.firebase_uid,
                email=new_email,
                email_verified=True
            )
            
            # Mark OTP as verified
            otp_record.is_verified = True
            otp_record.save()
            
            # Update local profile
            user_profile = request.user
            user_profile.email = new_email
            user_profile.is_email_verified = True
            user_profile.save()
            
            return Response(
                {'message': 'Email updated successfully!', 'email': new_email}, 
                status=status.HTTP_200_OK
            )
        except firebase_auth.EmailAlreadyExistsError:
            return Response({'error': 'This email is already in use in Firebase.'}, status=status.HTTP_400_BAD_REQUEST)
        except Exception as e:
            print(f"[EmailChange] Error updating Firebase: {str(e)}")
            return Response({'error': f'Internal server error while updating email.'}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)




class FoundItemCreateView(APIView):
    """
    Handles POST request for creating a found item report.
    Requires multipart form data with image upload.
    """
    parser_classes = (MultiPartParser, FormParser)
    
    def post(self, request, format=None):
        if 'item_img' in request.FILES:
            item_img = request.FILES['item_img']
            
            allowed_types = ['image/jpeg', 'image/jpg', 'image/png', 'image/webp']
            if item_img.content_type not in allowed_types:
                return Response(
                    {'error': 'Invalid file type. Only JPEG, PNG, and WebP images are allowed.'},
                    status=status.HTTP_400_BAD_REQUEST
                )
            
            if item_img.size > 5 * 1024 * 1024:
                return Response(
                    {'error': 'File size too large. Maximum size is 5MB.'},
                    status=status.HTTP_400_BAD_REQUEST
                )
        
        try:
            serializer = FoundItemSerializer(data=request.data)
            
            if serializer.is_valid():
                from .models import FoundItem
                post_id = FoundItem.generate_unique_post_id()
                
                if 'item_img' in request.FILES:
                    item_img = request.FILES['item_img']
                    import os
                    file_extension = os.path.splitext(item_img.name)[1]
                    new_filename = f"img_{post_id}{file_extension}"
                    item_img.name = new_filename
                
                found_item = serializer.save(
                    posted_by=request.user,
                    post_id=post_id
                )
                
                return Response(
                    FoundItemSerializer(found_item).data,
                    status=status.HTTP_201_CREATED
                )
            else:
                return Response(
                    serializer.errors,
                    status=status.HTTP_400_BAD_REQUEST
                )
        except Exception as e:
            return Response(
                {'error': 'Internal server error'},
                status=status.HTTP_500_INTERNAL_SERVER_ERROR
            )


class FoundItemListView(APIView):
    """
    Handles GET request for listing found items.
    Returns a list of all found items ordered by posted_time (newest first).
    """
    permission_classes = [AllowAny]  # Or IsAuthenticated if you want to restrict it

    def get(self, request):
        try:
            found_items = FoundItem.objects.all().order_by('-posted_time')
            serializer = FoundItemSerializer(found_items, many=True, context={'request': request})
            return Response(serializer.data, status=status.HTTP_200_OK)
        except Exception as e:
            print(f"[FoundItemList] Error: {str(e)}")
            return Response(
                {'error': 'Internal server error'},
                status=status.HTTP_500_INTERNAL_SERVER_ERROR
            )


class LostItemCreateView(APIView):
    """
    Handles POST request for creating a lost item report.
    Requires multipart form data with image upload.
    """
    parser_classes = (MultiPartParser, FormParser)
    
    def post(self, request, format=None):
        print(f"[LostItemCreate] Request received from user: {request.user}")
        print(f"[LostItemCreate] FILES: {list(request.FILES.keys())}")
        print(f"[LostItemCreate] DATA: {dict(request.data)}")
        
        # Validate image if provided
        if 'item_img' in request.FILES:
            item_img = request.FILES['item_img']
            
            # Validate file type
            allowed_types = ['image/jpeg', 'image/jpg', 'image/png', 'image/webp']
            if item_img.content_type not in allowed_types:
                return Response(
                    {'error': 'Invalid file type. Only JPEG, PNG, and WebP images are allowed.'},
                    status=status.HTTP_400_BAD_REQUEST
                )
            
            # Validate file size (max 5MB)
            if item_img.size > 5 * 1024 * 1024:
                return Response(
                    {'error': 'File size too large. Maximum size is 5MB.'},
                    status=status.HTTP_400_BAD_REQUEST
                )
        
    def post(self, request, format=None):
        try:
            serializer = LostItemSerializer(data=request.data)
            
            if serializer.is_valid():
                from .models import LostItem
                post_id = LostItem.generate_unique_post_id()
                
                if 'item_img' in request.FILES:
                    item_img = request.FILES['item_img']
                    import os
                    file_extension = os.path.splitext(item_img.name)[1]
                    new_filename = f"img_{post_id}{file_extension}"
                    item_img.name = new_filename
                
                found_item = serializer.save(
                    posted_by=request.user,
                    post_id=post_id
                )
                
                return Response(
                    LostItemSerializer(found_item).data,
                    status=status.HTTP_201_CREATED
                )
            else:
                return Response(
                    serializer.errors,
                    status=status.HTTP_400_BAD_REQUEST
                )
        except Exception as e:
            return Response(
                {'error': 'Internal server error'},
                status=status.HTTP_500_INTERNAL_SERVER_ERROR
            )


class LostItemListView(APIView):
    """
    Handles GET request for listing lost items.
    Returns a list of all lost items ordered by posted_time (newest first).
    """
    permission_classes = [AllowAny]

    def get(self, request):
        try:
            from .models import LostItem
            lost_items = LostItem.objects.all().order_by('-posted_time')
            serializer = LostItemSerializer(lost_items, many=True, context={'request': request})
            return Response(serializer.data, status=status.HTTP_200_OK)
        except Exception:
            return Response(
                {'error': 'Internal server error'},
                status=status.HTTP_500_INTERNAL_SERVER_ERROR
            )


# Update and Delete Views for Found and Lost Items

class FoundItemUpdateView(APIView):
    """
    Handles PUT request for updating a found item.
    Only the owner can update their post.
    """
    parser_classes = (MultiPartParser, FormParser)
    
    def put(self, request, post_id, format=None):
        try:
            from .models import FoundItem
            found_item = FoundItem.objects.get(post_id=post_id)
            
            if found_item.posted_by != request.user and getattr(request.user, 'role', 'user') != 'admin':
                return Response(
                    {'error': 'You do not have permission to edit this post'},
                    status=status.HTTP_403_FORBIDDEN
                )
            
            if 'item_img' in request.FILES:
                item_img = request.FILES['item_img']
                
                allowed_types = ['image/jpeg', 'image/jpg', 'image/png', 'image/webp']
                if item_img.content_type not in allowed_types:
                    return Response(
                        {'error': 'Invalid file type. Only JPEG, PNG, and WebP images are allowed.'},
                        status=status.HTTP_400_BAD_REQUEST
                    )
                
                if item_img.size > 5 * 1024 * 1024:
                    return Response(
                        {'error': 'File size too large. Maximum size is 5MB.'},
                        status=status.HTTP_400_BAD_REQUEST
                    )
                
                import os
                file_extension = os.path.splitext(item_img.name)[1]
                new_filename = f"img_{post_id}{file_extension}"
                item_img.name = new_filename
            
            serializer = FoundItemSerializer(found_item, data=request.data, partial=True)
            
            if serializer.is_valid():
                updated_item = serializer.save()
                return Response(
                    FoundItemSerializer(updated_item).data,
                    status=status.HTTP_200_OK
                )
            else:
                return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)
                
        except FoundItem.DoesNotExist:
            return Response(
                {'error': 'Post not found'},
                status=status.HTTP_404_NOT_FOUND
            )
        except Exception as e:
            print(f"[FoundItemUpdate] Error: {str(e)}")
            return Response(
                {'error': 'Internal server error'},
                status=status.HTTP_500_INTERNAL_SERVER_ERROR
            )


class FoundItemDeleteView(APIView):
    """
    Handles DELETE request for deleting a found item.
    Only the owner can delete their post.
    """
    
    def delete(self, request, post_id, format=None):
        try:
            from .models import FoundItem
            found_item = FoundItem.objects.get(post_id=post_id)
            
            if found_item.posted_by != request.user and getattr(request.user, 'role', 'user') != 'admin':
                return Response(
                    {'error': 'You do not have permission to delete this post'},
                    status=status.HTTP_403_FORBIDDEN
                )
            
            found_item.delete()
            return Response(status=status.HTTP_204_NO_CONTENT)
                
        except FoundItem.DoesNotExist:
            return Response(
                {'error': 'Post not found'},
                status=status.HTTP_404_NOT_FOUND
            )
        except Exception as e:
            print(f"[FoundItemDelete] Error: {str(e)}")
            return Response(
                {'error': 'Internal server error'},
                status=status.HTTP_500_INTERNAL_SERVER_ERROR
            )


class LostItemUpdateView(APIView):
    """
    Handles PUT request for updating a lost item.
    Only the owner can update their post.
    """
    parser_classes = (MultiPartParser, FormParser)
    
    def put(self, request, post_id, format=None):
        try:
            from .models import LostItem
            lost_item = LostItem.objects.get(post_id=post_id)
            
            if lost_item.posted_by != request.user and getattr(request.user, 'role', 'user') != 'admin':
                return Response(
                    {'error': 'You do not have permission to edit this post'},
                    status=status.HTTP_403_FORBIDDEN
                )
            
            if 'item_img' in request.FILES:
                item_img = request.FILES['item_img']
                
                allowed_types = ['image/jpeg', 'image/jpg', 'image/png', 'image/webp']
                if item_img.content_type not in allowed_types:
                    return Response(
                        {'error': 'Invalid file type. Only JPEG, PNG, and WebP images are allowed.'},
                        status=status.HTTP_400_BAD_REQUEST
                    )
                
                if item_img.size > 5 * 1024 * 1024:
                    return Response(
                        {'error': 'File size too large. Maximum size is 5MB.'},
                        status=status.HTTP_400_BAD_REQUEST
                    )
                
                import os
                file_extension = os.path.splitext(item_img.name)[1]
                new_filename = f"img_{post_id}{file_extension}"
                item_img.name = new_filename
            
            serializer = LostItemSerializer(lost_item, data=request.data, partial=True)
            
            if serializer.is_valid():
                updated_item = serializer.save()
                return Response(
                    LostItemSerializer(updated_item).data,
                    status=status.HTTP_200_OK
                )
            else:
                return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)
                
        except LostItem.DoesNotExist:
            return Response(
                {'error': 'Post not found'},
                status=status.HTTP_404_NOT_FOUND
            )
        except Exception as e:
            print(f"[LostItemUpdate] Error: {str(e)}")
            return Response(
                {'error': 'Internal server error'},
                status=status.HTTP_500_INTERNAL_SERVER_ERROR
            )


class LostItemDeleteView(APIView):
    """
    Handles DELETE request for deleting a lost item.
    Only the owner can delete their post.
    """
    
    def delete(self, request, post_id, format=None):
        try:
            from .models import LostItem
            lost_item = LostItem.objects.get(post_id=post_id)
            
            if lost_item.posted_by != request.user and getattr(request.user, 'role', 'user') != 'admin':
                return Response(
                    {'error': 'You do not have permission to delete this post'},
                    status=status.HTTP_403_FORBIDDEN
                )
            
            lost_item.delete()
            return Response(status=status.HTTP_204_NO_CONTENT)
                
        except LostItem.DoesNotExist:
            return Response(
                {'error': 'Post not found'},
                status=status.HTTP_404_NOT_FOUND
            )
        except Exception as e:
            print(f"[LostItemDelete] Error: {str(e)}")
            return Response(
                {'error': 'Internal server error'},
                status=status.HTTP_500_INTERNAL_SERVER_ERROR
            )


# Ownership Request Views

class UserLostItemsView(APIView):
    """
    GET: users/<user_id>/lost-items/
    Lists lost items for a specific user so a finder can link their found post.
    """
    def get(self, request, user_id):
        user = get_object_or_404(UserProfile, user_id=user_id)
        lost_items = user.lost_items.filter(finder_identified=False)
        serializer = UserLostItemsSerializer(lost_items, many=True, context={'request': request})
        return Response(serializer.data)


class OwnershipRequestViewSet(viewsets.ModelViewSet):
    """
    Handles creating, listing, and responding to ownership requests.
    """
    serializer_class = OwnershipRequestSerializer
    queryset = OwnershipRequest.objects.all()

    def get_queryset(self):
        # Users see requests where they are either the finder or the potential owner
        queryset = OwnershipRequest.objects.filter(
            models.Q(finder=self.request.user) | models.Q(owner=self.request.user)
        )
        # Check for expired requests and update them
        for req in queryset.filter(status='pending'):
            if req.is_expired():
                req.status = 'rejected'
                req.save()
        return queryset

    def perform_create(self, serializer):
        # Set finder to current user
        serializer.save(finder=self.request.user, status='pending')

    @action(detail=True, methods=['post'])
    def respond(self, request, pk=None):
        """
        Custom action for the potential owner to Accept or Reject a request.
        """
        ownership_request = self.get_object()
        
        # Security: Only the intended owner can respond
        if ownership_request.owner != request.user:
            return Response(
                {'error': 'You do not have permission to respond to this request'},
                status=status.HTTP_403_FORBIDDEN
            )
        
        if ownership_request.status != 'pending':
            return Response(
                {'error': f'Request is already {ownership_request.status}'},
                status=status.HTTP_400_BAD_REQUEST
            )

        respond_action = request.data.get('action') # 'accept' or 'reject'
        
        if respond_action == 'accept':
            # Update request status
            ownership_request.status = 'accepted'
            ownership_request.save()
            
            # Update Found Item
            found_item = ownership_request.found_item
            found_item.owner_identified = True
            found_item.owner_id = ownership_request.owner
            if ownership_request.lost_item:
                found_item.matched_post = ownership_request.lost_item.post_id
            found_item.save()
            
            # Update Lost Item (if linked)
            if ownership_request.lost_item:
                lost_item = ownership_request.lost_item
                lost_item.finder_identified = True
                lost_item.finder_id = ownership_request.finder
                lost_item.matched_post = found_item.post_id
                lost_item.save()
            
            return Response({'status': 'accepted', 'message': 'Ownership confirmed. You can now chat with the finder.'})
            
        elif respond_action == 'reject':
            ownership_request.status = 'rejected'
            ownership_request.save()
            return Response({'status': 'rejected', 'message': 'Request rejected.'})
            
        return Response({'error': 'Invalid action. Use "accept" or "reject".'}, status=status.HTTP_400_BAD_REQUEST)

class AdminUserListView(APIView):
    """
    Admin-only view to list all users with search and filter capabilities.
    """
    permission_classes = [IsAuthenticated]

    def get(self, request):
        if getattr(request.user, 'role', 'user') != 'admin':
            return Response({"error": "Admin access required"}, status=status.HTTP_403_FORBIDDEN)

        users = UserProfile.objects.exclude(role='admin').order_by('-last_opened')
        
        # Search by user_id
        search_query = request.query_params.get('search', None)
        if search_query:
            users = users.filter(user_id__icontains=search_query)
            
        # Filter by Active/Inactive
        status_filter = request.query_params.get('filter', 'All')
        one_month_ago = timezone.now() - timedelta(days=30)
        
        if status_filter == 'Active':
            users = users.filter(last_opened__gte=one_month_ago).exclude(role='deleted')
        elif status_filter == 'Inactive':
            from django.db.models import Q
            users = users.filter(Q(last_opened__lt=one_month_ago) | Q(last_opened__isnull=True)).exclude(role='deleted')
        elif status_filter == 'Proxy':
            users = UserProfile.objects.filter(role='deleted').order_by('-last_opened')
            
        total_count = users.count()
        serializer = AdminUserSerializer(users, many=True, context={'request': request})
        
        return Response({
            "total_count": total_count,
            "users": serializer.data
        })

class AdminDeleteUserView(APIView):
    """
    Admin-only view to delete a user.
    """
    permission_classes = [IsAuthenticated]

    def delete(self, request, firebase_uid):
        if getattr(request.user, 'role', 'user') != 'admin':
            return Response({"error": "Admin access required"}, status=status.HTTP_403_FORBIDDEN)

        user_to_delete = get_object_or_404(UserProfile, firebase_uid=firebase_uid)
        
        try:
            # Deep cleaning for Proxy accounts (role='deleted')
            if getattr(user_to_delete, 'role', 'user') == 'deleted':
                from chat.models import Conversation
                from core.models import FoundItem, LostItem
                
            from .models import FoundItem, LostItem
            from chat.models import Conversation
            
            if user_to_delete.role == 'deleted':
                Conversation.objects.filter(participants=user_to_delete).delete()
                
                FoundItem.objects.filter(owner_id=user_to_delete).update(
                    status='found',
                    owner_identified=False,
                    owner_id=None,
                    info=None,
                    matched_post=None
                )
                
                LostItem.objects.filter(finder_id=user_to_delete).update(
                    status='lost',
                    finder_identified=False,
                    finder_id=None,
                    info=None,
                    matched_post=None
                )

            if getattr(user_to_delete, 'role', 'user') != 'deleted':
                from firebase_admin import auth as firebase_auth
                try:
                    firebase_auth.delete_user(firebase_uid)
                except Exception:
                    pass
            
            user_to_delete.delete()
            return Response({"success": True, "message": "User deleted successfully"})
        except Exception as e:
            return Response({"error": str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)

class AdminUserProfileView(APIView):
    """
    Admin-only view to fetch a specific user's profile data (read-only).
    """
    permission_classes = [IsAuthenticated]

    def get(self, request, user_id):
        if getattr(request.user, 'role', 'user') != 'admin':
            return Response({"error": "Admin access required"}, status=status.HTTP_403_FORBIDDEN)
            
        profile = get_object_or_404(UserProfile, user_id=user_id)
        serializer = UserProfileSerializer(profile)
        return Response(serializer.data)

class AdminItemListView(APIView):
    """
    Admin-only view to list all items (Found + Lost) with search and filter capabilities.
    """
    permission_classes = [IsAuthenticated]

    def get(self, request):
        if getattr(request.user, 'role', 'user') != 'admin':
            return Response({"error": "Admin access required"}, status=status.HTTP_403_FORBIDDEN)

        found_items = FoundItem.objects.all()
        lost_items = LostItem.objects.all()
        
        search_query = request.query_params.get('search')
        if search_query:
            found_items = found_items.filter(item_name__icontains=search_query)
            lost_items = lost_items.filter(item_name__icontains=search_query)
            
        status_filter = request.query_params.get('filter', 'All')
        
        if status_filter == 'Issue':
            from .models import ReportIssue
            reported_post_ids = ReportIssue.objects.values_list('post_id', flat=True).distinct()
            found_items = found_items.filter(post_id__in=reported_post_ids)
            lost_items = lost_items.filter(post_id__in=reported_post_ids)
        
        found_serializer = FoundItemSerializer(found_items, many=True, context={'request': request})
        lost_serializer = LostItemSerializer(lost_items, many=True, context={'request': request})
        
        all_items = []
        if status_filter in ['All', 'Found', 'Issue']:
            for item in found_serializer.data:
                item['status'] = 'found'
                all_items.append(item)
                
        if status_filter in ['All', 'Lost', 'Issue']:
            for item in lost_serializer.data:
                item['status'] = 'lost'
                all_items.append(item)
        
        all_items.sort(key=lambda x: x.get('posted_time', ''), reverse=True)
        
        return Response({
            "total_count": len(all_items),
            "items": all_items
        })

class AdminAllUsersView(APIView):
    """
    Admin-only view to fetch a simple list of all users for assignment dropdowns.
    Returns: [{user_id, name, profile_pic}, ...]
    """
    permission_classes = [IsAuthenticated]

    def get(self, request):
        if getattr(request.user, 'role', 'user') != 'admin':
            return Response({"error": "Admin access required"}, status=status.HTTP_403_FORBIDDEN)

        users = UserProfile.objects.all().order_by('name')
        
        search_query = request.query_params.get('search')
        if search_query:
            from django.db.models import Q
            users = users.filter(
                Q(name__icontains=search_query) | 
                Q(user_id__icontains=search_query)
            )
            
        user_list = []
        for user in users:
            user_list.append({
                'user_id': user.user_id,
                'name': user.name,
                'profile_pic_url': user.profile_pic_url if user.profile_pic_url else None,
            })
            
        return Response(user_list)

class AdminDirectAssignView(APIView):
    """
    Allows admins to directly assign ownership of found/lost items,
    bypassing the request-verification flow.
    """
    permission_classes = [IsAuthenticated]

    def post(self, request):
        if getattr(request.user, 'role', 'user') != 'admin':
            return Response({"error": "Admin access required"}, status=status.HTTP_403_FORBIDDEN)

        found_item_id = request.data.get('found_item_id')
        owner_user_id = request.data.get('owner_user_id')
        lost_item_id = request.data.get('lost_item_id')

        if not found_item_id or not owner_user_id or not lost_item_id:
            return Response({"error": "Missing required fields"}, status=status.HTTP_400_BAD_REQUEST)

        try:
            found_item = FoundItem.objects.get(post_id=found_item_id)
            owner_user = UserProfile.objects.get(user_id=owner_user_id)
            lost_item = LostItem.objects.get(post_id=lost_item_id)

            admin_name = getattr(request.user, 'user_name', 'Admin')
            info_msg = f"{admin_name} Assigned"
            
            found_item.owner_id = owner_user
            found_item.owner_identified = True
            found_item.info = info_msg
            found_item.matched_post = lost_item.post_id
            found_item.save()

            lost_item.finder_id = found_item.posted_by
            lost_item.finder_identified = True
            lost_item.info = info_msg
            lost_item.matched_post = found_item.post_id
            lost_item.save()

            return Response({
                "success": True, 
                "message": f"Ownership of {found_item.item_name} assigned to {owner_user.name}."
            })

        except FoundItem.DoesNotExist:
            return Response({"error": "Found item not found"}, status=status.HTTP_404_NOT_FOUND)
        except LostItem.DoesNotExist:
            return Response({"error": "Lost item not found"}, status=status.HTTP_404_NOT_FOUND)
        except UserProfile.DoesNotExist:
            return Response({"error": "User not found"}, status=status.HTTP_404_NOT_FOUND)
        except Exception as e:
            return Response({"error": str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)

class AdminUnassignView(APIView):
    """
    Allows admins to unassign ownership/finder from posts.
    Resets status and breaking the links.
    """
    permission_classes = [IsAuthenticated]

    def post(self, request):
        if getattr(request.user, 'role', 'user') != 'admin':
            return Response({"error": "Admin access required"}, status=status.HTTP_403_FORBIDDEN)

        post_id = request.data.get('post_id')
        post_type = request.data.get('post_type')

        if not post_id or not post_type:
            return Response({"error": "post_id and post_type are required"}, status=status.HTTP_400_BAD_REQUEST)

        admin_name = getattr(request.user, 'user_name', 'Admin')
        info_msg = f"{admin_name} Unassigned"

        try:
            if post_type == 'found':
                item = FoundItem.objects.get(post_id=post_id)
                matched_post_id = item.matched_post
                
                item.owner_identified = False
                item.owner_id = None
                item.matched_post = 'None'
                item.info = info_msg
                item.save()

                if matched_post_id and matched_post_id != 'None':
                    try:
                        linked_item = LostItem.objects.get(post_id=matched_post_id)
                        linked_item.finder_identified = False
                        linked_item.finder_id = None
                        linked_item.matched_post = 'None'
                        linked_item.info = info_msg
                        linked_item.save()
                    except LostItem.DoesNotExist:
                        pass
            
            elif post_type == 'lost':
                item = LostItem.objects.get(post_id=post_id)
                matched_post_id = item.matched_post
                
                item.finder_identified = False
                item.finder_id = None
                item.matched_post = 'None'
                item.info = info_msg
                item.save()

                if matched_post_id and matched_post_id != 'None':
                    try:
                        linked_item = FoundItem.objects.get(post_id=matched_post_id)
                        linked_item.owner_identified = False
                        linked_item.owner_id = None
                        linked_item.matched_post = 'None'
                        linked_item.info = info_msg
                        linked_item.save()
                    except FoundItem.DoesNotExist:
                        pass
            
            else:
                return Response({"error": "Invalid post_type. Use 'found' or 'lost'"}, status=status.HTTP_400_BAD_REQUEST)

            return Response({
                "success": True,
                "message": f"Successfully unassigned post {post_id}."
            })

        except (FoundItem.DoesNotExist, LostItem.DoesNotExist):
            return Response({"error": f"Item {post_id} not found"}, status=status.HTTP_404_NOT_FOUND)
        except Exception as e:
            return Response({"error": str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


class ReportIssueCreateView(APIView):
    """
    Create a new report issue. POST /api/report-issues/
    Accepts multipart/form-data for proof document uploads.
    """
    permission_classes = [IsAuthenticated]
    parser_classes = [MultiPartParser, FormParser]

    def post(self, request):
        user_id = getattr(request.user, 'user_id', None)
        if not user_id:
            return Response({"error": "User not authenticated"}, status=status.HTTP_401_UNAUTHORIZED)

        data = request.data.copy()
        data['posted_by'] = user_id

        serializer = ReportIssueSerializer(data=data, context={'request': request})
        if serializer.is_valid():
            serializer.save()
            return Response(serializer.data, status=status.HTTP_201_CREATED)
        return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)


class ReportIssueListView(APIView):
    """
    List issues for a post. GET /api/report-issues/?post_id=<id>
    - Admin: sees all issues for the post.
    - User: sees only their own issues for the post.
    """
    permission_classes = [IsAuthenticated]

    def get(self, request):
        post_id = request.query_params.get('post_id')
        if not post_id:
            return Response({"error": "post_id is required"}, status=status.HTTP_400_BAD_REQUEST)

        user_id = getattr(request.user, 'user_id', None)
        role = getattr(request.user, 'role', 'user')

        issues = ReportIssue.objects.filter(post_id=post_id)
        if role != 'admin':
            issues = issues.filter(posted_by=user_id)

        serializer = ReportIssueSerializer(issues, many=True, context={'request': request})
        return Response(serializer.data)


class AdminIssueSummaryView(APIView):
    """
    Get a summary of items with reported issues. Admin only.
    GET /api/admin/report-issues/summary/
    """
    permission_classes = [IsAuthenticated]

    def get(self, request):
        # Check admin role
        role = getattr(request.user, 'role', 'user')
        if role != 'admin':
            return Response({"error": "Admin access required"}, status=status.HTTP_403_FORBIDDEN)

        # Aggregate UNRESOLVED issues by post_id
        from django.db.models import Count
        issue_summaries = ReportIssue.objects.exclude(issue_status='Responded').values('post_id').annotate(
            issue_count=Count('issue_id')
        ).filter(issue_count__gt=0)

        results = []
        for summary in issue_summaries:
            post_id = summary['post_id']
            issue_count = summary['issue_count']

            # Try to fetch actual item for the image and latest metadata
            item_data = None
            try:
                if post_id.startswith('fd_'):
                    from .models import FoundItem
                    item = FoundItem.objects.get(post_id=post_id)
                elif post_id.startswith('lt_'):
                    from .models import LostItem
                    item = LostItem.objects.get(post_id=post_id)
                else:
                    raise ValueError("Invalid post_id prefix")

                item_data = {
                    "post_id": post_id,
                    "item_name": item.item_name,
                    "reported_user_id": item.posted_by.user_id,
                    "issue_count": issue_count,
                    "item_img": item.item_img.url if item.item_img else None
                }
            except Exception:
                # Fallback to metadata stored in the report itself if item is missing
                first_issue = ReportIssue.objects.filter(post_id=post_id).first()
                if first_issue:
                    item_data = {
                        "post_id": post_id,
                        "item_name": first_issue.item_name,
                        "reported_user_id": first_issue.reported_user_id,
                        "issue_count": issue_count,
                        "item_img": None
                    }

            if item_data:
                results.append(item_data)

        return Response(results)


class ReviewIssueCreateView(APIView):
    """
    Create a new review for a report issue. Admin only.
    POST /api/review-issues/
    """
    permission_classes = [IsAuthenticated]

    def post(self, request):
        role = getattr(request.user, 'role', 'user')
        if role != 'admin':
            return Response({"error": "Admin access required"}, status=status.HTTP_403_FORBIDDEN)

        user_id = getattr(request.user, 'user_id', None)
        if not user_id:
            return Response({"error": "User not authenticated"}, status=status.HTTP_401_UNAUTHORIZED)

        from .serializers import ReviewIssueSerializer

        data = request.data.copy()
        data['reviewed_by'] = user_id

        serializer = ReviewIssueSerializer(data=data)
        if serializer.is_valid():
            serializer.save()
            return Response(serializer.data, status=status.HTTP_201_CREATED)
        return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)


class ReviewIssueDetailView(APIView):
    """
    Fetch review details for a report. All authenticated users.
    GET /api/review-issues/detail/?report_id=<id>
    """
    permission_classes = [IsAuthenticated]

    def get(self, request):
        user_id = getattr(request.user, 'user_id', None)
        if not user_id:
            return Response({"error": "User not authenticated"}, status=status.HTTP_401_UNAUTHORIZED)

        report_id = request.query_params.get('report_id')
        if not report_id:
            return Response({"error": "report_id is required"}, status=status.HTTP_400_BAD_REQUEST)

        from .models import ReviewIssue
        from .serializers import ReviewIssueSerializer

        try:
            review = ReviewIssue.objects.get(report_id=report_id)
            serializer = ReviewIssueSerializer(review)
            return Response(serializer.data)
        except ReviewIssue.DoesNotExist:
            return Response({"error": "No review found"}, status=status.HTTP_404_NOT_FOUND)

class ReviewIssueUpdateDeleteView(APIView):
    permission_classes = [IsAuthenticated]

    def put(self, request):
        role = getattr(request.user, 'role', 'user')
        if role != 'admin':
            return Response({"error": "Admin access required"}, status=status.HTTP_403_FORBIDDEN)

        review_id = request.query_params.get('review_id')
        if not review_id:
            return Response({"error": "review_id is required"}, status=status.HTTP_400_BAD_REQUEST)

        from .models import ReviewIssue
        from .serializers import ReviewIssueSerializer

        try:
            review = ReviewIssue.objects.get(review_id=review_id)
            serializer = ReviewIssueSerializer(review, data=request.data, partial=True)
            if serializer.is_valid():
                serializer.save()
                return Response(serializer.data)
            return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)
        except ReviewIssue.DoesNotExist:
            return Response({"error": "No review found"}, status=status.HTTP_404_NOT_FOUND)

    def delete(self, request):
        role = getattr(request.user, 'role', 'user')
        if role != 'admin':
            return Response({"error": "Admin access required"}, status=status.HTTP_403_FORBIDDEN)

        review_id = request.query_params.get('review_id')
        if not review_id:
            return Response({"error": "review_id is required"}, status=status.HTTP_400_BAD_REQUEST)

        from .models import ReviewIssue, ReportIssue
        try:
            review = ReviewIssue.objects.get(review_id=review_id)
            report_id = review.report_id
            review.delete()
            
            try:
                report = ReportIssue.objects.get(issue_id=report_id)
                report.issue_status = 'Pending'
                report.save()
            except ReportIssue.DoesNotExist:
                pass

            return Response(status=status.HTTP_204_NO_CONTENT)
        except ReviewIssue.DoesNotExist:
            return Response({"error": "No review found"}, status=status.HTTP_404_NOT_FOUND)


class AdminReportIssueDeleteView(APIView):
    permission_classes = [IsAuthenticated]

    def delete(self, request):
        role = getattr(request.user, 'role', 'user')
        if role != 'admin':
            return Response({"error": "Admin access required"}, status=status.HTTP_403_FORBIDDEN)

        issue_id = request.query_params.get('issue_id')
        if not issue_id:
            return Response({"error": "issue_id is required"}, status=status.HTTP_400_BAD_REQUEST)

        from .models import ReportIssue
        try:
            report = ReportIssue.objects.get(issue_id=issue_id)
            report.delete()
            return Response(status=status.HTTP_204_NO_CONTENT)
        except ReportIssue.DoesNotExist:
            return Response({"error": "No report found"}, status=status.HTTP_404_NOT_FOUND)

class DeleteAccountView(APIView):
    permission_classes = [IsAuthenticated]

    def delete(self, request):
        user_to_delete = request.user
        firebase_uid = user_to_delete.firebase_uid
        original_user_id = user_to_delete.user_id

        try:
            from .models import UserProfile
            from chat.models import Message, Conversation
            from core.models import FoundItem, LostItem, OwnershipRequest

            shadow_profile, created = UserProfile.objects.get_or_create(
                firebase_uid=f"DELETED_{firebase_uid}",
                defaults={
                    'user_name': f"Deleted_user_{original_user_id}",
                    'user_id': f"deleted_{original_user_id}",
                    'name': f"Deleted_user_{original_user_id}",
                    'role': 'deleted'
                }
            )

            Message.objects.filter(sender=user_to_delete).update(sender=shadow_profile)
            
            conversations = Conversation.objects.filter(participants=user_to_delete)
            for conv in conversations:
                conv.participants.remove(user_to_delete)
                if not conv.participants.filter(firebase_uid=shadow_profile.firebase_uid).exists():
                    conv.participants.add(shadow_profile)

            FoundItem.objects.filter(owner_id=user_to_delete).update(owner_id=shadow_profile)
            LostItem.objects.filter(finder_id=user_to_delete).update(finder_id=shadow_profile)

            OwnershipRequest.objects.filter(finder=user_to_delete).update(finder=shadow_profile)
            OwnershipRequest.objects.filter(owner=user_to_delete).update(owner=shadow_profile)

            from firebase_admin import auth as firebase_auth
            try:
                firebase_auth.delete_user(firebase_uid)
            except Exception:
                pass

            user_to_delete.delete()

            return Response({"success": True, "message": "Account deleted successfully"})
        except Exception as e:
            return Response({"error": str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


class AdminProxyUserView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request, firebase_uid):
        if getattr(request.user, 'role', 'user') != 'admin':
            return Response({"error": "Admin access required"}, status=status.HTTP_403_FORBIDDEN)

        user_to_proxy = get_object_or_404(UserProfile, firebase_uid=firebase_uid)
        
        if user_to_proxy.role == 'deleted':
            return Response({"error": "User is already proxied"}, status=status.HTTP_400_BAD_REQUEST)

        original_user_id = user_to_proxy.user_id

        try:
            from chat.models import Message, Conversation
            from core.models import FoundItem, LostItem, OwnershipRequest

            shadow_profile, created = UserProfile.objects.get_or_create(
                firebase_uid=f"DELETED_{firebase_uid}",
                defaults={
                    'user_name': f"Deleted_user_{original_user_id}",
                    'user_id': f"deleted_{original_user_id}",
                    'name': f"Deleted_user_{original_user_id}",
                    'role': 'deleted'
                }
            )

            Message.objects.filter(sender=user_to_proxy).update(sender=shadow_profile)
            
            conversations = Conversation.objects.filter(participants=user_to_proxy)
            for conv in conversations:
                conv.participants.remove(user_to_proxy)
                if not conv.participants.filter(firebase_uid=shadow_profile.firebase_uid).exists():
                    conv.participants.add(shadow_profile)

            FoundItem.objects.filter(owner_id=user_to_proxy).update(owner_id=shadow_profile)
            LostItem.objects.filter(finder_id=user_to_proxy).update(finder_id=shadow_profile)

            OwnershipRequest.objects.filter(finder=user_to_proxy).update(finder=shadow_profile)
            OwnershipRequest.objects.filter(owner=user_to_proxy).update(owner=shadow_profile)

            from firebase_admin import auth as firebase_auth
            try:
                firebase_auth.delete_user(firebase_uid)
            except Exception:
                pass

            user_to_proxy.delete()

            return Response({"success": True, "message": "User proxied successfully"})
        except Exception as e:
            return Response({"error": str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


class AdminAnalyticsView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        if getattr(request.user, 'role', 'user') != 'admin':
            return Response({"error": "Admin access required"}, status=status.HTTP_403_FORBIDDEN)

        time_filter = request.query_params.get('filter', 'Week')
        now = timezone.now()
        
        if time_filter == 'Week':
            start_date = now.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
            group_by = TruncWeek('posted_time')
        elif time_filter == 'Month':
            start_date = now.replace(month=1, day=1, hour=0, minute=0, second=0, microsecond=0)
            group_by = TruncMonth('posted_time')
        elif time_filter == 'Year':
            earliest_found = FoundItem.objects.all().order_by('posted_time').first()
            earliest_lost = LostItem.objects.all().order_by('posted_time').first()
            dates = [d.posted_time for d in [earliest_found, earliest_lost] if d]
            start_date = min(dates) if dates else now - timedelta(days=365)
            group_by = TruncYear('posted_time')
        else: # 'All'
            start_date = None
            group_by = None

        found_qs = FoundItem.objects.all()
        lost_qs = LostItem.objects.all()
        
        if start_date:
            found_qs = found_qs.filter(posted_time__gte=start_date)
            lost_qs = lost_qs.filter(posted_time__gte=start_date)

        total_found = found_qs.count()
        total_lost = lost_qs.count()
        total_resolved = lost_qs.filter(finder_identified=True).count()

        if group_by:
            comparison_query = lost_qs.annotate(period=group_by).values('period').annotate(
                lost_count=Count('id'),
                resolved_count=Count('id', filter=Q(finder_identified=True))
            ).order_by('period')
            comparison_data = list(comparison_query)
        else:
            comparison_data = [{
                'period': 'All',
                'lost_count': total_lost,
                'resolved_count': total_resolved
            }]

        categories = ['Electronics', 'Documents', 'Luggage', 'Apparel', 'Accessories', 'Pets', 'Keys', 'Money', 'Other']
        category_stats = []

        for cat in categories:
            cat_found = found_qs.filter(category=cat).count()
            cat_lost = lost_qs.filter(category=cat).count()

            if cat_found > 0 or cat_lost > 0:
                found_pct = (cat_found / total_found * 100) \
                    if total_found > 0 else 0
                lost_pct = (cat_lost / total_lost * 100) \
                    if total_lost > 0 else 0
                category_stats.append({
                    'category': cat,
                    'found_pct': round(found_pct, 1),
                    'lost_pct': round(lost_pct, 1),
                    'found_count': cat_found,
                    'lost_count': cat_lost
                })

        return Response({
            'summary': {
                'total_found': total_found,
                'total_lost': total_lost,
                'total_resolved': total_resolved
            },
            'comparison': comparison_data,
            'categories': category_stats
        })


class CleanupFirebaseUsersView(APIView):
    permission_classes = [IsAdminUser]

    def post(self, request):
        result = cleanup_orphaned_firebase_users()
        if result['status'] == 'success':
            return Response(result, status=status.HTTP_200_OK)
        return Response(result, status=status.HTTP_500_INTERNAL_SERVER_ERROR)
