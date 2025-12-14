import random
import string
from django.core.mail import send_mail
from django.conf import settings


def generate_otp():
    """Generate a random 6-digit OTP code."""
    return ''.join(random.choices(string.digits, k=6))


def send_otp_email(email, otp_code, user_name=None):
    """
    Send OTP code via email.
    
    Args:
        email (str): Recipient email address
        otp_code (str): 6-digit OTP code
        user_name (str): Optional user name for personalization
    
    Returns:
        bool: True if email sent successfully, False otherwise
    """

    app_name = "Finder"

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
    
    # html_message = f"""
    # <html>
    #     <body style="font-family: Arial, sans-serif; line-height: 1.6; color: #333;">
    #         <div style="max-width: 600px; margin: 0 auto; padding: 20px;">
    #             <h2 style="color: #673AB7;">FindMate Verification</h2>
    #             <p>{greeting}</p>
    #             <p>Thank you for signing up with FindMate!</p>
    #             <div style="background-color: #f5f5f5; padding: 20px; border-radius: 8px; text-align: center; margin: 20px 0;">
    #                 <p style="margin: 0; font-size: 14px; color: #666;">Your verification code is:</p>
    #                 <h1 style="color: #673AB7; font-size: 36px; letter-spacing: 8px; margin: 10px 0;">{otp_code}</h1>
    #             </div>
    #             <p style="color: #666; font-size: 14px;">This code will expire in 5 minutes.</p>
    #             <p style="color: #999; font-size: 12px; margin-top: 30px;">
    #                 If you didn't request this code, please ignore this email.
    #             </p>
    #             <hr style="border: none; border-top: 1px solid #eee; margin: 20px 0;">
    #             <p style="color: #999; font-size: 12px;">Best regards,<br>The FindMate Team</p>
    #         </div>
    #     </body>
    # </html>
    # """
    
    try:
        send_mail(
            subject=subject,
            message=message,
            from_email=settings.DEFAULT_FROM_EMAIL,
            recipient_list=[email],
            # html_message=html_message,
            fail_silently=False,
        )
        return True
    except Exception as e:
        print(f"Error sending OTP email: {e}")
        return False
