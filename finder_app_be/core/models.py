from django.db import models
from django.utils import timezone
from datetime import timedelta
import re
import random
import string

class UserProfile(models.Model):
    # This ID will be the 'uid' from Firebase
    firebase_uid = models.CharField(max_length=128, unique=True, primary_key=True)
    
    # User identification
    user_name = models.CharField(max_length=50, blank=True)
    user_id = models.CharField(max_length=60, unique=True, blank=True, null=True)
    
    # Profile fields
    name = models.CharField(max_length=100, blank=True)
    bio = models.TextField(blank=True)
    profile_pic_url = models.URLField(max_length=200, blank=True, null=True)
    is_email_verified = models.BooleanField(default=False)
    
    # Stats
    found_count = models.IntegerField(default=0)
    lost_count = models.IntegerField(default=0)

    # Required for DRF authentication
    @property
    def is_authenticated(self):
        """Always return True for authenticated users."""
        return True
    
    @property
    def is_anonymous(self):
        """Always return False since this is an authenticated user."""
        return False

    def save(self, *args, **kwargs):
        # Auto-generate user_id from user_name if not set
        if self.user_name and not self.user_id:
            self.user_id = self.generate_unique_user_id(self.user_name)
        super().save(*args, **kwargs)

    @staticmethod
    def generate_unique_user_id(username):
        """
        Generate a unique user_id from username.
        Format: username_lowercase + random_suffix
        Example: john_doe_a1b2
        """
        # Clean username: lowercase, replace spaces with underscores, remove special chars
        base_id = re.sub(r'[^a-z0-9_]', '', username.lower().replace(' ', '_'))
        
        # Ensure base_id is not empty
        if not base_id:
            base_id = 'user'
        
        # Try without suffix first
        if not UserProfile.objects.filter(user_id=base_id).exists():
            return base_id
        
        # Add random suffix until unique
        max_attempts = 100
        for _ in range(max_attempts):
            suffix = ''.join(random.choices(string.ascii_lowercase + string.digits, k=4))
            user_id = f"{base_id}_{suffix}"
            if not UserProfile.objects.filter(user_id=user_id).exists():
                return user_id
        
        # Fallback: use timestamp
        import time
        return f"{base_id}_{int(time.time())}"

    def __str__(self):
        return self.user_name or self.name or self.firebase_uid


class EmailOTP(models.Model):
    user = models.ForeignKey(UserProfile, on_delete=models.CASCADE, related_name='otp_codes')
    email = models.EmailField()
    otp_code = models.CharField(max_length=6)
    created_at = models.DateTimeField(auto_now_add=True)
    expires_at = models.DateTimeField()
    is_verified = models.BooleanField(default=False)
    attempts = models.IntegerField(default=0)
    
    class Meta:
        ordering = ['-created_at']
    
    def save(self, *args, **kwargs):
        if not self.expires_at:
            self.expires_at = timezone.now() + timedelta(minutes=5)
        super().save(*args, **kwargs)
    
    def is_expired(self):
        return timezone.now() > self.expires_at
    
    def __str__(self):
        return f"OTP for {self.email} - {self.otp_code}"


class FoundItem(models.Model):
    """Model for items that have been found and reported."""
    
    CATEGORY_CHOICES = [
        ('Electronics', 'Electronics'),
        ('Documents', 'Documents'),
        ('Luggage', 'Luggage'),
        ('Apparel', 'Apparel'),
        ('Accessories', 'Accessories'),
        ('Pets', 'Pets'),
        ('Keys', 'Keys'),
        ('Money', 'Money'),
        ('Other', 'Other'),
    ]
    
    # Auto-generated unique ID
    post_id = models.CharField(max_length=50, unique=True, editable=False, blank=True)
    
    # Item details
    item_name = models.CharField(max_length=20)
    item_img = models.ImageField(upload_to='found_items/', blank=True, null=True)
    category = models.CharField(max_length=50, choices=CATEGORY_CHOICES)
    description = models.TextField()
    color = models.CharField(max_length=15)
    location = models.CharField(max_length=60, help_text="Location where item was found")
    date = models.DateField(help_text="Date when item was found")
    
    # Status and ownership
    status = models.CharField(max_length=5, default='found')
    posted_by = models.ForeignKey(
        UserProfile, 
        on_delete=models.CASCADE, 
        related_name='found_items'
    )
    posted_time = models.DateTimeField(auto_now_add=True)
    owner_identified = models.BooleanField(default=False)
    owner_id = models.ForeignKey(
        UserProfile, 
        on_delete=models.SET_NULL, 
        null=True, 
        blank=True, 
        related_name='claimed_items'
    )
    
    def save(self, *args, **kwargs):
        # Auto-generate post_id if not set
        if not self.post_id:
            self.post_id = self.generate_unique_post_id()
        super().save(*args, **kwargs)
    
    @staticmethod
    def generate_unique_post_id():
        """
        Generate a unique post_id with format: fd_XXXXXXXX
        Where X is alphanumeric (lowercase letters and digits)
        """
        max_attempts = 100
        for _ in range(max_attempts):
            # Generate 8 random alphanumeric characters
            suffix = ''.join(random.choices(string.ascii_lowercase + string.digits, k=8))
            post_id = f"fd_{suffix}"
            
            # Check if unique
            if not FoundItem.objects.filter(post_id=post_id).exists():
                return post_id
        
        # Fallback: use timestamp
        import time
        return f"fd_{int(time.time())}"
    
    def __str__(self):
        return f"{self.post_id} - {self.item_name}"
    
    class Meta:
        ordering = ['-posted_time']
        verbose_name = 'Found Item'
        verbose_name_plural = 'Found Items'


class LostItem(models.Model):
    """Model for items that have been lost and reported."""
    
    CATEGORY_CHOICES = [
        ('Electronics', 'Electronics'),
        ('Documents', 'Documents'),
        ('Luggage', 'Luggage'),
        ('Apparel', 'Apparel'),
        ('Accessories', 'Accessories'),
        ('Pets', 'Pets'),
        ('Keys', 'Keys'),
        ('Money', 'Money'),
        ('Other', 'Other'),
    ]
    
    # Auto-generated unique ID
    post_id = models.CharField(max_length=50, unique=True, editable=False, blank=True)
    
    # Item details
    item_name = models.CharField(max_length=20)
    item_img = models.ImageField(upload_to='lost_items/', blank=True, null=True)
    category = models.CharField(max_length=50, choices=CATEGORY_CHOICES)
    description = models.TextField()
    color = models.CharField(max_length=15)
    location = models.CharField(max_length=60, help_text="Location where item was lost")
    date = models.DateField(help_text="Date when item was lost")
    
    # Status and ownership
    status = models.CharField(max_length=5, default='lost')
    posted_by = models.ForeignKey(
        UserProfile, 
        on_delete=models.CASCADE, 
        related_name='lost_items'
    )
    posted_time = models.DateTimeField(auto_now_add=True)
    finder_identified = models.BooleanField(default=False)
    finder_id = models.ForeignKey(
        UserProfile, 
        on_delete=models.SET_NULL, 
        null=True, 
        blank=True, 
        related_name='recovered_items'
    )
    
    def save(self, *args, **kwargs):
        # Auto-generate post_id if not set
        if not self.post_id:
            self.post_id = self.generate_unique_post_id()
        super().save(*args, **kwargs)
    
    @staticmethod
    def generate_unique_post_id():
        """
        Generate a unique post_id with format: lt_XXXXXXXX
        Where X is alphanumeric (lowercase letters and digits)
        """
        max_attempts = 100
        for _ in range(max_attempts):
            # Generate 8 random alphanumeric characters
            suffix = ''.join(random.choices(string.ascii_lowercase + string.digits, k=8))
            post_id = f"lt_{suffix}"
            
            # Check if unique
            if not LostItem.objects.filter(post_id=post_id).exists():
                return post_id
        
        # Fallback: use timestamp
        import time
        return f"lt_{int(time.time())}"
    
    def __str__(self):
        return f"{self.post_id} - {self.item_name}"
    
    class Meta:
        ordering = ['-posted_time']
        verbose_name = 'Lost Item'
        verbose_name_plural = 'Lost Items'
