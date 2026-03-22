import random
import string
from django.core.mail import send_mail
from django.conf import settings


def generate_otp():
    return ''.join(random.choices(string.digits, k=6))


def send_otp_email(email, otp_code, user_name=None):
    app_name = "Finder App"
    subject = f'{app_name} - Your Verification Code'
    greeting = f"Hello {user_name}," if user_name else "Hello,"
    
    message = f"""
{greeting}

Thank you for signing up with {app_name}!

Your 6-digit verification code is: {otp_code}

This code will expire in 5 minutes. Please enter it in the app to verify your account.

If you didn't request this code, please ignore this email.

Best regards,
The {app_name} Team
    """
    
    try:
        send_mail(
            subject=subject,
            message=message,
            from_email=settings.DEFAULT_FROM_EMAIL,
            recipient_list=[email],
            fail_silently=False,
        )
        return True
    except Exception as e:
        return False
