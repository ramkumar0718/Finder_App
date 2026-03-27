from django.db import models
from django.utils import timezone
from datetime import timedelta
import re
import random
import string
import os

def generate_gen_token(min_length=5):
    """
    Generate a random ID with alphabets, numbers, and special characters.
    Minimum length is 5.
    """
    letters = string.ascii_letters
    digits = string.digits
    special = "-_~" # URL and file system safe special characters
    
    # Ensure at least one of each
    chars = [
        random.choice(letters),
        random.choice(digits),
        random.choice(special)
    ]
    
    # Fill remaining capacity
    remaining_length = max(0, min_length - len(chars))
    all_chars = letters + digits + special
    chars.extend(random.choices(all_chars, k=remaining_length))
    
    # Shuffle to randomize positions
    random.shuffle(chars)
    return ''.join(chars)

def found_item_img_path(instance, filename):
    ext = filename.split('.')[-1]
    return f'found_items/IMG_{instance.post_id}.{ext}'

def lost_item_img_path(instance, filename):
    ext = filename.split('.')[-1]
    return f'lost_items/IMG_{instance.post_id}.{ext}'

def report_proof_1_path(instance, filename):
    ext = filename.split('.')[-1]
    return f'report_proofs/DOC_{instance.issue_id}_1.{ext}'

def report_proof_2_path(instance, filename):
    ext = filename.split('.')[-1]
    return f'report_proofs/DOC_{instance.issue_id}_2.{ext}'

class UserProfile(models.Model):
    firebase_uid = models.CharField(max_length=128, unique=True, primary_key=True)
    
    user_name = models.CharField(max_length=50, blank=True)
    user_id = models.CharField(max_length=60, unique=True, blank=True, null=True)
    email = models.EmailField(blank=True, null=True)
    
    name = models.CharField(max_length=100, blank=True)
    profile_pic_url = models.URLField(max_length=200, blank=True, null=True)
    is_email_verified = models.BooleanField(default=False)
    
    role = models.CharField(
        max_length=10,
        choices=[('user', 'User'), ('admin', 'Admin')],
        default='user'
    )
    
    found_count = models.IntegerField(default=0)
    lost_count = models.IntegerField(default=0)
    last_opened = models.DateTimeField(null=True, blank=True)
    joined_date = models.DateTimeField(auto_now_add=True)

    # Required for DRF authentication
    @property
    def is_authenticated(self):
        return True
    
    @property
    def is_anonymous(self):
        return False

    def save(self, *args, **kwargs):
        # Sanitize user_name and name: remove spaces and non-alphanumeric (except underscores)
        if self.user_name:
            self.user_name = re.sub(r'[^a-zA-Z0-9_]', '', self.user_name.replace(' ', ''))
        if self.name:
            self.name = re.sub(r'[^a-zA-Z0-9_]', '', self.name.replace(' ', ''))
            
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

class FoundItem(models.Model):
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
    
    post_id = models.CharField(max_length=50, unique=True, editable=False, blank=True)
    item_name = models.CharField(max_length=20)
    item_img = models.ImageField(upload_to=found_item_img_path, blank=True, null=True)
    category = models.CharField(max_length=50, choices=CATEGORY_CHOICES)
    description = models.TextField()
    color_id = models.CharField(max_length=20, default='none')
    color_name = models.CharField(max_length=50, default='Unknown')
    location = models.CharField(max_length=60)
    date = models.DateField()
    status = models.CharField(max_length=5, default='found')
    posted_by = models.ForeignKey(UserProfile, on_delete=models.CASCADE, related_name='found_items')
    posted_time = models.DateTimeField(auto_now_add=True)
    owner_identified = models.BooleanField(default=False)
    owner_id = models.ForeignKey(UserProfile, on_delete=models.SET_NULL, null=True, blank=True, related_name='claimed_items')
    info = models.CharField(max_length=100, default='None', null=True, blank=True)
    matched_post = models.CharField(max_length=50, default='None', null=True, blank=True)
    
    def save(self, *args, **kwargs):
        # Auto-generate post_id if not set
        if not self.post_id:
            self.post_id = self.generate_unique_post_id()
            
        # Handle updating existing image: if changing image, delete old one from Cloudinary
        if self.pk:
            try:
                old_instance = FoundItem.objects.get(pk=self.pk)
                if old_instance.item_img and self.item_img and old_instance.item_img != self.item_img:
                    import cloudinary.uploader
                    cloudinary.uploader.destroy(old_instance.item_img.name)
            except FoundItem.DoesNotExist:
                pass

        super().save(*args, **kwargs)
    
    @staticmethod
    def generate_unique_post_id():
        """
        Generate a unique post_id with format: FOUND_{GEN}
        """
        max_attempts = 100
        for _ in range(max_attempts):
            gen = generate_gen_token(5)
            post_id = f"FOUND_{gen}"
            
            # Check if unique
            if not FoundItem.objects.filter(post_id=post_id).exists():
                return post_id
        
        # Fallback: use timestamp
        import time
        return f"FOUND_{int(time.time())}"
    
    def __str__(self):
        return f"{self.post_id} - {self.item_name}"
    
    class Meta:
        ordering = ['-posted_time']
        verbose_name = 'Found Item'
        verbose_name_plural = 'Found Items'


class LostItem(models.Model):
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
    
    post_id = models.CharField(max_length=50, unique=True, editable=False, blank=True)
    item_name = models.CharField(max_length=20)
    item_img = models.ImageField(upload_to=lost_item_img_path, blank=True, null=True)
    category = models.CharField(max_length=50, choices=CATEGORY_CHOICES)
    description = models.TextField()
    color_id = models.CharField(max_length=20, default='none')
    color_name = models.CharField(max_length=50, default='Unknown')
    location = models.CharField(max_length=60)
    date = models.DateField()
    status = models.CharField(max_length=5, default='lost')
    posted_by = models.ForeignKey(UserProfile, on_delete=models.CASCADE, related_name='lost_items')
    posted_time = models.DateTimeField(auto_now_add=True)
    finder_identified = models.BooleanField(default=False)
    finder_id = models.ForeignKey(UserProfile, on_delete=models.SET_NULL, null=True, blank=True, related_name='recovered_items')
    info = models.CharField(max_length=100, default='None', null=True, blank=True)
    matched_post = models.CharField(max_length=50, default='None', null=True, blank=True)
    
    def save(self, *args, **kwargs):
        # Auto-generate post_id if not set
        if not self.post_id:
            self.post_id = self.generate_unique_post_id()
            
        # Handle updating existing image: if changing image, delete old one from Cloudinary
        if self.pk:
            try:
                old_instance = LostItem.objects.get(pk=self.pk)
                if old_instance.item_img and self.item_img and old_instance.item_img != self.item_img:
                    import cloudinary.uploader
                    cloudinary.uploader.destroy(old_instance.item_img.name)
            except LostItem.DoesNotExist:
                pass
                
        super().save(*args, **kwargs)
    
    @staticmethod
    def generate_unique_post_id():
        """
        Generate a unique post_id with format: LOST_{GEN}
        """
        max_attempts = 100
        for _ in range(max_attempts):
            gen = generate_gen_token(5)
            post_id = f"LOST_{gen}"
            
            # Check if unique
            if not LostItem.objects.filter(post_id=post_id).exists():
                return post_id
        
        # Fallback: use timestamp
        import time
        return f"LOST_{int(time.time())}"
    
    def __str__(self):
        return f"{self.post_id} - {self.item_name}"
    
    class Meta:
        ordering = ['-posted_time']
        verbose_name = 'Lost Item'
        verbose_name_plural = 'Lost Items'


class OwnershipRequest(models.Model):
    STATUS_CHOICES = [
        ('pending', 'Pending'),
        ('accepted', 'Accepted'),
        ('rejected', 'Rejected'),
        ('expired', 'Expired'),
    ]
    
    finder = models.ForeignKey(UserProfile, on_delete=models.CASCADE, related_name='sent_requests')
    owner = models.ForeignKey(UserProfile, on_delete=models.CASCADE, related_name='received_requests')
    found_item = models.ForeignKey(FoundItem, on_delete=models.CASCADE, related_name='ownership_requests')
    lost_item = models.ForeignKey(LostItem, on_delete=models.SET_NULL, null=True, blank=True, related_name='recovery_requests')
    
    status = models.CharField(max_length=10, choices=STATUS_CHOICES, default='pending')
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    
    def is_expired(self):
        """Check if request is more than 24 hours old and still pending."""
        if self.status == 'pending' and self.created_at:
            return timezone.now() > self.created_at + timedelta(days=1)
        return False

    def save(self, *args, **kwargs):
        # Auto-expire if needed before saving
        if self.is_expired():
            self.status = 'rejected'
        super().save(*args, **kwargs)

    class Meta:
        ordering = ['-created_at']
        verbose_name = 'Ownership Request'
        verbose_name_plural = 'Ownership Requests'

class ReportIssue(models.Model):
    ISSUE_CATEGORY_CHOICES = [
        ('Fake Post', 'Fake Post'),
        ('Technical Bug', 'Technical Bug'),
        ('Harassment', 'Harassment'),
        ('Wrong Owner Assigned', 'Wrong Owner Assigned'),
        ('Other', 'Other'),
    ]

    ISSUE_STATUS_CHOICES = [
        ('Not Responded', 'Not Responded'),
        ('Responded', 'Responded'),
    ]

    issue_id = models.CharField(max_length=20, primary_key=True, unique=True, editable=False)
    post_id = models.CharField(max_length=50)
    item_name = models.CharField(max_length=200)
    reported_user_id = models.CharField(max_length=60)
    issue_status = models.CharField(
        max_length=20,
        choices=ISSUE_STATUS_CHOICES,
        default='Not Responded',
    )
    issue_category = models.CharField(max_length=30, choices=ISSUE_CATEGORY_CHOICES)
    description = models.TextField()
    proof_doc_1 = models.FileField(upload_to=report_proof_1_path, null=True, blank=True)
    proof_doc_2 = models.FileField(upload_to=report_proof_2_path, null=True, blank=True)
    posted_by = models.CharField(max_length=60)
    posted_time = models.DateTimeField(auto_now_add=True)

    def save(self, *args, **kwargs):
        if not self.issue_id:
            self.issue_id = self._generate_issue_id()
        super().save(*args, **kwargs)

    @staticmethod
    def _generate_issue_id():
        import random
        while True:
            number = random.randint(10000, 99999)
            candidate = f'ISSUE_{number}'
            if not ReportIssue.objects.filter(issue_id=candidate).exists():
                return candidate

    class Meta:
        ordering = ['-posted_time']
        verbose_name = 'Report Issue'
        verbose_name_plural = 'Report Issues'


class ReviewIssue(models.Model):
    REVIEW_STATUS_CHOICES = [
        ('Resolved', 'Resolved'),
        ('Dismissed', 'Dismissed'),
    ]

    REVIEW_CATEGORY_CHOICES = [
        ('Action Taken', 'Action Taken'),
        ('No Action Required', 'No Action Required'),
        ('Warning Sent to User', 'Warning Sent to User'),
        ('Post Removed', 'Post Removed'),
        ('User Permanently Banned', 'User Permanently Banned'),
    ]

    review_id = models.CharField(max_length=20, primary_key=True, unique=True, editable=False)
    report_id = models.CharField(max_length=20)  # ReportIssue.issue_id
    post_id = models.CharField(max_length=50)
    reported_user_id = models.CharField(max_length=60)
    issuer_user_id = models.CharField(max_length=60)
    review_status = models.CharField(
        max_length=20,
        choices=REVIEW_STATUS_CHOICES,
        default='Resolved',
    )
    review_category = models.CharField(max_length=30, choices=REVIEW_CATEGORY_CHOICES)
    description = models.TextField()
    reviewed_by = models.CharField(max_length=60)  # admin user_id
    reviewed_time = models.DateTimeField(auto_now_add=True)

    def save(self, *args, **kwargs):
        if not self.review_id:
            self.review_id = self._generate_review_id()
        super().save(*args, **kwargs)
        # Mark the linked report as Responded
        try:
            report = ReportIssue.objects.get(issue_id=self.report_id)
            if report.issue_status != 'Responded':
                report.issue_status = 'Responded'
                report.save()
        except ReportIssue.DoesNotExist:
            pass

    @staticmethod
    def _generate_review_id():
        import random
        while True:
            number = random.randint(10000, 99999)
            candidate = f'REVIEW_{number}'
            if not ReviewIssue.objects.filter(review_id=candidate).exists():
                return candidate

    class Meta:
        ordering = ['-reviewed_time']
        verbose_name = 'Review Issue'
        verbose_name_plural = 'Review Issues'