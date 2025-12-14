from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework import status
from rest_framework.parsers import MultiPartParser, FormParser
from rest_framework.permissions import AllowAny
from django.utils import timezone
from datetime import timedelta
from .models import UserProfile, EmailOTP, FoundItem
from .serializers import UserProfileSerializer, SendOTPSerializer, VerifyOTPSerializer, GoogleLoginSerializer, FoundItemSerializer, LostItemSerializer
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
        print(f"[ProfilePicUpload] Request received")  # Debug
        print(f"[ProfilePicUpload] User: {request.user}")  # Debug
        print(f"[ProfilePicUpload] FILES keys: {list(request.FILES.keys())}")  # Debug
        print(f"[ProfilePicUpload] POST keys: {list(request.POST.keys())}")  # Debug
        print(f"[ProfilePicUpload] Content-Type: {request.content_type}")  # Debug
        
        if 'profile_pic' not in request.FILES:
            print(f"[ProfilePicUpload] ERROR: No profile_pic in FILES")  # Debug
            return Response({'error': 'No profile_pic file provided'}, status=status.HTTP_400_BAD_REQUEST)

        profile_pic = request.FILES['profile_pic']
        print(f"[ProfilePicUpload] File received: {profile_pic.name}, size: {profile_pic.size}, type: {profile_pic.content_type}")  # Debug
        
        # Validate file type
        allowed_types = ['image/jpeg', 'image/jpg', 'image/png', 'image/webp']
        if profile_pic.content_type not in allowed_types:
            print(f"[ProfilePicUpload] ERROR: Invalid file type: {profile_pic.content_type}")  # Debug
            return Response({'error': 'Invalid file type. Only JPEG, PNG, and WebP images are allowed.'}, status=status.HTTP_400_BAD_REQUEST)
        
        # Validate file size (max 5MB)
        if profile_pic.size > 5 * 1024 * 1024:
            print(f"[ProfilePicUpload] ERROR: File too large: {profile_pic.size} bytes")  # Debug
            return Response({'error': 'File size too large. Maximum size is 5MB.'}, status=status.HTTP_400_BAD_REQUEST)

        try:
            profile = request.user
            user_uid = profile.firebase_uid
            
            # Create profile_pics directory if it doesn't exist
            import os
            from django.conf import settings
            profile_pics_dir = os.path.join(settings.MEDIA_ROOT, 'profile_pics')
            os.makedirs(profile_pics_dir, exist_ok=True)
            
            # Generate unique filename
            import uuid
            file_extension = os.path.splitext(profile_pic.name)[1]
            unique_filename = f"{user_uid}_{uuid.uuid4().hex[:8]}{file_extension}"
            file_path = os.path.join(profile_pics_dir, unique_filename)
            
            # Save the file
            with open(file_path, 'wb+') as destination:
                for chunk in profile_pic.chunks():
                    destination.write(chunk)
            
            # Generate full URL (for development, use the request's host)
            # In production, you would use your actual domain
            host = request.get_host()  # Gets '10.0.2.2:8000' or '127.0.0.1:8000'
            protocol = 'https' if request.is_secure() else 'http'
            profile_pic_url = f"{protocol}://{host}{settings.MEDIA_URL}profile_pics/{unique_filename}"
            
            print(f"[ProfilePicUpload] Saved to: {file_path}")  # Debug
            print(f"[ProfilePicUpload] URL: {profile_pic_url}")  # Debug
            
            # Update profile
            profile.profile_pic_url = profile_pic_url
            profile.save()
            
            return Response({
                'profile_pic_url': profile_pic_url,
                'message': 'Profile picture uploaded successfully'
            }, status=status.HTTP_200_OK)
        except Exception as e:
            print(f"[ProfilePicUpload] Error: {str(e)}")  # Debug
            import traceback
            traceback.print_exc()  # Print full traceback
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

        print(f"[GoogleLogin] Received user_name: '{user_name}'")  # Debug

        try:
            user_profile, created = UserProfile.objects.get_or_create(
                firebase_uid=firebase_uid,
                defaults={
                    'name': (user_name[:50] if user_name else email.split('@')[0])[:50],
                    'user_name': (user_name[:50] if user_name else email.split('@')[0])[:50],
                    'profile_pic_url': profile_pic_url,
                    'is_email_verified': True  # Google accounts are verified
                }
            )

            print(f"[GoogleLogin] After get_or_create - user_name: '{user_profile.user_name}', user_id: '{user_profile.user_id}'")  # Debug

            # Ensure user_id is generated for new users
            if created and not user_profile.user_id:
                user_profile.save()  # Trigger user_id generation
                print(f"[GoogleLogin] After save - user_id: '{user_profile.user_id}'")  # Debug

            if not created:
                # Update existing user details if provided
                if user_name and not user_profile.user_name:
                    user_profile.user_name = user_name
                    user_profile.name = user_name
                if profile_pic_url:
                    user_profile.profile_pic_url = profile_pic_url
                
                # Ensure email verified is true for Google login
                user_profile.is_email_verified = True
                user_profile.save()  # This will trigger auto user_id generation if needed

            print(f"[GoogleLogin] Final - user_name: '{user_profile.user_name}', user_id: '{user_profile.user_id}'")  # Debug

            return Response({
                'message': 'User synced successfully',
                'user_id': user_profile.user_id,
                'user_name': user_profile.user_name
            }, status=status.HTTP_200_OK)

        except Exception as e:
            print(f"[GoogleLogin] Error: {str(e)}")  # Debug
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
        firebase_uid = serializer.validated_data['firebase_uid']
        user_name = serializer.validated_data.get('user_name', '')
        
        # Get or create user profile
        try:
            user_profile, created = UserProfile.objects.get_or_create(
                firebase_uid=firebase_uid,
                defaults={
                    'name': email.split('@')[0],
                    'user_name': user_name if user_name else email.split('@')[0]
                }
            )
            
            # Update user_name if profile already exists but user_name is provided
            if not created and user_name and not user_profile.user_name:
                user_profile.user_name = user_name
                user_profile.save()
                
        except Exception as e:
            return Response(
                {'error': f'Failed to create user profile: {str(e)}'},
                status=status.HTTP_500_INTERNAL_SERVER_ERROR
            )
        
        # Check rate limiting - prevent sending OTP too frequently
        recent_otp = EmailOTP.objects.filter(
            user=user_profile,
            email=email,
            created_at__gte=timezone.now() - timedelta(seconds=60)
        ).first()
        
        if recent_otp:
            time_remaining = 60 - (timezone.now() - recent_otp.created_at).seconds
            return Response(
                {'error': f'Please wait {time_remaining} seconds before requesting a new code.'},
                status=status.HTTP_429_TOO_MANY_REQUESTS
            )
        
        # Generate and save OTP
        otp_code = generate_otp()
        EmailOTP.objects.create(
            user=user_profile,
            email=email,
            otp_code=otp_code
        )
        
        # Send OTP email
        email_sent = send_otp_email(email, otp_code, user_profile.name)
        
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
        
        # Find the most recent OTP for this email
        try:
            otp_record = EmailOTP.objects.filter(
                email=email,
                is_verified=False
            ).order_by('-created_at').first()
        except Exception as e:
            return Response(
                {'error': 'Invalid request.'},
                status=status.HTTP_400_BAD_REQUEST
            )
        
        if not otp_record:
            return Response(
                {'error': 'No OTP found for this email. Please request a new code.'},
                status=status.HTTP_404_NOT_FOUND
            )
        
        # Check if OTP is expired
        if otp_record.is_expired():
            return Response(
                {'error': 'OTP has expired. Please request a new code.'},
                status=status.HTTP_400_BAD_REQUEST
            )
        
        # Check maximum attempts
        if otp_record.attempts >= 3:
            return Response(
                {'error': 'Maximum verification attempts exceeded. Please request a new code.'},
                status=status.HTTP_400_BAD_REQUEST
            )
        
        # Verify OTP
        if otp_record.otp_code == otp_code:
            # Mark OTP as verified
            otp_record.is_verified = True
            otp_record.save()
            
            # Mark user as email verified
            user_profile = otp_record.user
            user_profile.is_email_verified = True
            user_profile.save()
            
            return Response(
                {'message': 'Email verified successfully!'},
                status=status.HTTP_200_OK
            )
        else:
            # Increment attempts
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
        firebase_uid = serializer.validated_data['firebase_uid']
        
        # Get user profile
        try:
            user_profile = UserProfile.objects.get(firebase_uid=firebase_uid)
        except UserProfile.DoesNotExist:
            return Response(
                {'error': 'User not found.'},
                status=status.HTTP_404_NOT_FOUND
            )
        
        # Check rate limiting
        recent_otp = EmailOTP.objects.filter(
            user=user_profile,
            email=email,
            created_at__gte=timezone.now() - timedelta(seconds=60)
        ).first()
        
        if recent_otp:
            time_remaining = 60 - (timezone.now() - recent_otp.created_at).seconds
            return Response(
                {'error': f'Please wait {time_remaining} seconds before requesting a new code.'},
                status=status.HTTP_429_TOO_MANY_REQUESTS
            )
        
        # Invalidate previous OTPs
        EmailOTP.objects.filter(
            user=user_profile,
            email=email,
            is_verified=False
        ).update(is_verified=True)  # Mark as verified to invalidate
        
        # Generate and save new OTP
        otp_code = generate_otp()
        EmailOTP.objects.create(
            user=user_profile,
            email=email,
            otp_code=otp_code
        )
        
        # Send OTP email
        email_sent = send_otp_email(email, otp_code, user_profile.name)
        
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


class FoundItemCreateView(APIView):
    """
    Handles POST request for creating a found item report.
    Requires multipart form data with image upload.
    """
    parser_classes = (MultiPartParser, FormParser)
    
    def post(self, request, format=None):
        print(f"[FoundItemCreate] Request received from user: {request.user}")
        print(f"[FoundItemCreate] FILES: {list(request.FILES.keys())}")
        print(f"[FoundItemCreate] DATA: {dict(request.data)}")
        
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
        
        try:
            # Create serializer with request data
            serializer = FoundItemSerializer(data=request.data)
            
            if serializer.is_valid():
                # Generate post_id manually to use in filename
                from .models import FoundItem
                post_id = FoundItem.generate_unique_post_id()
                
                # Rename image if present
                if 'item_img' in request.FILES:
                    item_img = request.FILES['item_img']
                    import os
                    file_extension = os.path.splitext(item_img.name)[1]
                    new_filename = f"img_{post_id}{file_extension}"
                    item_img.name = new_filename
                
                # Save with generated post_id and current user
                found_item = serializer.save(
                    posted_by=request.user,
                    post_id=post_id
                )
                
                print(f"[FoundItemCreate] Created item: {found_item.post_id}")
                
                return Response(
                    FoundItemSerializer(found_item).data,
                    status=status.HTTP_201_CREATED
                )
            else:
                print(f"[FoundItemCreate] Validation errors: {serializer.errors}")
                return Response(
                    serializer.errors,
                    status=status.HTTP_400_BAD_REQUEST
                )
        except Exception as e:
            print(f"[FoundItemCreate] Error: {str(e)}")
            import traceback
            traceback.print_exc()
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
        
        try:
            # Create serializer with request data
            serializer = LostItemSerializer(data=request.data)
            
            if serializer.is_valid():
                # Generate post_id manually to use in filename
                from .models import LostItem
                post_id = LostItem.generate_unique_post_id()
                
                # Rename image if present
                if 'item_img' in request.FILES:
                    item_img = request.FILES['item_img']
                    import os
                    file_extension = os.path.splitext(item_img.name)[1]
                    new_filename = f"img_{post_id}{file_extension}"
                    item_img.name = new_filename
                
                # Save with generated post_id and current user
                found_item = serializer.save(
                    posted_by=request.user,
                    post_id=post_id
                )
                
                print(f"[LostItemCreate] Created item: {found_item.post_id}")
                
                return Response(
                    LostItemSerializer(found_item).data,
                    status=status.HTTP_201_CREATED
                )
            else:
                print(f"[LostItemCreate] Validation errors: {serializer.errors}")
                return Response(
                    serializer.errors,
                    status=status.HTTP_400_BAD_REQUEST
                )
        except Exception as e:
            print(f"[LostItemCreate] Error: {str(e)}")
            import traceback
            traceback.print_exc()
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
        except Exception as e:
            print(f"[LostItemList] Error: {str(e)}")
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
        print(f"[FoundItemUpdate] Request received for post_id: {post_id}")
        print(f"[FoundItemUpdate] User: {request.user}")
        
        try:
            from .models import FoundItem
            found_item = FoundItem.objects.get(post_id=post_id)
            
            # Check if user owns this post
            if found_item.posted_by != request.user:
                return Response(
                    {'error': 'You do not have permission to edit this post'},
                    status=status.HTTP_403_FORBIDDEN
                )
            
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
                
                # Rename image with post_id
                import os
                file_extension = os.path.splitext(item_img.name)[1]
                new_filename = f"img_{post_id}{file_extension}"
                item_img.name = new_filename
            
            # Update with serializer
            serializer = FoundItemSerializer(found_item, data=request.data, partial=True)
            
            if serializer.is_valid():
                updated_item = serializer.save()
                print(f"[FoundItemUpdate] Updated item: {updated_item.post_id}")
                
                return Response(
                    FoundItemSerializer(updated_item).data,
                    status=status.HTTP_200_OK
                )
            else:
                print(f"[FoundItemUpdate] Validation errors: {serializer.errors}")
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
        print(f"[FoundItemDelete] Request received for post_id: {post_id}")
        print(f"[FoundItemDelete] User: {request.user}")
        
        try:
            from .models import FoundItem
            found_item = FoundItem.objects.get(post_id=post_id)
            
            # Check if user owns this post
            if found_item.posted_by != request.user:
                return Response(
                    {'error': 'You do not have permission to delete this post'},
                    status=status.HTTP_403_FORBIDDEN
                )
            
            # Delete the item
            found_item.delete()
            print(f"[FoundItemDelete] Deleted item: {post_id}")
            
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
        print(f"[LostItemUpdate] Request received for post_id: {post_id}")
        print(f"[LostItemUpdate] User: {request.user}")
        
        try:
            from .models import LostItem
            lost_item = LostItem.objects.get(post_id=post_id)
            
            # Check if user owns this post
            if lost_item.posted_by != request.user:
                return Response(
                    {'error': 'You do not have permission to edit this post'},
                    status=status.HTTP_403_FORBIDDEN
                )
            
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
                
                # Rename image with post_id
                import os
                file_extension = os.path.splitext(item_img.name)[1]
                new_filename = f"img_{post_id}{file_extension}"
                item_img.name = new_filename
            
            # Update with serializer
            serializer = LostItemSerializer(lost_item, data=request.data, partial=True)
            
            if serializer.is_valid():
                updated_item = serializer.save()
                print(f"[LostItemUpdate] Updated item: {updated_item.post_id}")
                
                return Response(
                    LostItemSerializer(updated_item).data,
                    status=status.HTTP_200_OK
                )
            else:
                print(f"[LostItemUpdate] Validation errors: {serializer.errors}")
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
        print(f"[LostItemDelete] Request received for post_id: {post_id}")
        print(f"[LostItemDelete] User: {request.user}")
        
        try:
            from .models import LostItem
            lost_item = LostItem.objects.get(post_id=post_id)
            
            # Check if user owns this post
            if lost_item.posted_by != request.user:
                return Response(
                    {'error': 'You do not have permission to delete this post'},
                    status=status.HTTP_403_FORBIDDEN
                )
            
            # Delete the item
            lost_item.delete()
            print(f"[LostItemDelete] Deleted item: {post_id}")
            
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
