from django.utils import timezone
from rest_framework.authentication import BaseAuthentication
from rest_framework.exceptions import AuthenticationFailed
from firebase_admin import auth
from core.models import UserProfile # Import your model

class FirebaseAuthentication(BaseAuthentication):
    """
    Custom authentication class for Django Rest Framework to verify 
    Firebase ID Tokens sent in the Authorization header.
    """

    def authenticate(self, request):
        auth_header = request.META.get("HTTP_AUTHORIZATION")

        if not auth_header:
            return None

        try:
            token_type, id_token = auth_header.split(' ')
        except ValueError:
            raise AuthenticationFailed('Invalid token header. Format: Bearer <token>')

        if token_type.lower() != 'bearer':
            return None

        try:
            # Verify the ID token and decode its payload
            decoded_token = auth.verify_id_token(id_token)
            uid = decoded_token['uid']
            
            # GET LATEST DATA FROM FIREBASE ADMIN SDK (Ground Truth)
            firebase_user = auth.get_user(uid)
            token_email = firebase_user.email
            token_email_verified = firebase_user.email_verified
            token_name = firebase_user.display_name
        except auth.InvalidIdToken:
            raise AuthenticationFailed('Invalid Firebase ID token.')
        except Exception as e:
            #print(f"DEBUG: Token/User fetch error: {e}")
            raise AuthenticationFailed(f'Token verification failed: {e}')
        
        # REQUIRE EMAIL VERIFICATION BEFORE CREATING PROFILE
        if not token_email_verified:
            #print(f"DEBUG: Auth rejected - Email not verified for UID: {uid} (Email: {token_email})")
            return None

        try:
            #print(f"DEBUG: Authenticating Firebase UID: {uid}")
            profile, created = UserProfile.objects.get_or_create(
                firebase_uid=uid,
                defaults={
                    'name': token_name if token_name else (token_email if token_email else uid),
                    'email': token_email,
                    'is_email_verified': True, # We only get here if verified
                }
            )
            #print(f"DEBUG: Profile {'created' if created else 'found'}: {profile.firebase_uid}")
            
            # Sync Email and Name from Firebase (Ground Truth from Firebase User)

            changed = False
            
            # If created, ensure user_name is set from initial displayName
            if created and token_name:
                profile.user_name = token_name
                profile.name = token_name
                changed = True

            # Sync Name if it changed later
            if not created and token_name and token_name != profile.name:
                #print(f"[AuthSync] Updating name: {profile.name} -> {token_name}")
                profile.name = token_name
                changed = True

            # Sync Email (standard sync)
            #print(f"DEBUG: Syncing email - Token: {token_email}, Profile: {profile.email}")
            if token_email and token_email != profile.email:
                print(f"[AuthSync] Updating email: {profile.email} -> {token_email}")
                profile.email = token_email
                changed = True

            # Ensure is_email_verified is True
            if not profile.is_email_verified:
                profile.is_email_verified = True
                changed = True

            # Update activity timestamp
            profile.last_opened = timezone.now()
            changed = True

            if changed:
                profile.save()

            return (profile, id_token)
        except Exception as e:
            import traceback
            traceback.print_exc()
            print(f"DEBUG: Auth error: {e}")
            raise AuthenticationFailed(f'Could not map token to UserProfile: {e}')
