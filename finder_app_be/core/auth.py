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
            return None # No token provided, proceed as anonymous (if allowed)

        # Expecting format: "Bearer <token>"
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
        except auth.InvalidIdToken:
            raise AuthenticationFailed('Invalid Firebase ID token.')
        except Exception:
            raise AuthenticationFailed('Token verification failed.')

        token_email = decoded_token.get('email')
        
        # Get or create the UserProfile linked to the Firebase UID
        try:
            profile, created = UserProfile.objects.get_or_create(
                firebase_uid=uid,
                defaults={
                    'name': decoded_token.get('name', decoded_token.get('email', uid)),
                    'email': token_email
                }
            )
            
            # If new profile, check if there's a verified OTP for this email
            if created and token_email:
                from core.models import EmailOTP
                verified_otp = EmailOTP.objects.filter(
                    email=token_email,
                    is_verified=True,
                    user__isnull=True
                ).order_by('-created_at').first()
                
                if verified_otp:
                    print(f"[AuthSync] Verified OTP found for {token_email}. Marking profile as verified.")
                    profile.is_email_verified = True
                    
                    # Apply preserved username if available
                    if verified_otp.user_name:
                        print(f"[AuthSync] Applying preserved username: {verified_otp.user_name}")
                        profile.user_name = verified_otp.user_name
                        profile.name = verified_otp.user_name
                    
                    # Link the OTP to the user now
                    verified_otp.user = profile
                    verified_otp.save()
                    changed = True
            
            # Sync email and name from Firebase if necessary
            token_email = decoded_token.get('email')
            token_email_verified = decoded_token.get('email_verified', False)
            token_name = decoded_token.get('name')

            changed = False
            # Sync Name
            if token_name and token_name != profile.name:
                print(f"[AuthSync] Updating name: {profile.name} -> {token_name}")
                profile.name = token_name
                changed = True

            # Sync Email - ONLY if current is empty OR if the token has a fresh VERIFIED email and we aren't already verified
            # This prevents stale tokens from reverting recent manual email changes in the app
            if token_email and token_email != profile.email:
                if not profile.email or (token_email_verified and not profile.is_email_verified):
                    print(f"[AuthSync] Updating email: {profile.email} -> {token_email} (Verified: {token_email_verified})")
                    profile.email = token_email
                    profile.is_email_verified = token_email_verified
                    changed = True
                else:
                    # Log but don't overwrite if local is already verified (possible stale token)
                    print(f"[AuthSync] Skipping email sync (possible stale token): {token_email} vs local {profile.email}")

            # Update activity timestamp
            profile.last_opened = timezone.now()
            changed = True

            if changed:
                profile.save()

            return (profile, id_token)
        except Exception as e:
            raise AuthenticationFailed(f'Could not map token to UserProfile: {e}')
