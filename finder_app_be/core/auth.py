from rest_framework.authentication import BaseAuthentication
from rest_framework.exceptions import AuthenticationFailed
from firebase_admin import auth
from core.models import UserProfile # Import your model
from django.contrib.auth.models import AnonymousUser

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

        # Get or create the UserProfile linked to the Firebase UID
        # Note: We are using UserProfile as the "user" object for DRF.
        try:
            profile, created = UserProfile.objects.get_or_create(
                firebase_uid=uid,
                defaults={'name': decoded_token.get('name', decoded_token.get('email', uid))}
            )
            # You can also update the email/name here if necessary
            return (profile, id_token) # (user_instance, auth_token)
        except Exception as e:
            raise AuthenticationFailed(f'Could not map token to UserProfile: {e}')
