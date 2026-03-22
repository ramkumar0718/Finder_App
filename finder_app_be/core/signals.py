from django.db.models.signals import post_save, post_delete
from django.dispatch import receiver
from .models import FoundItem, LostItem, UserProfile, ReportIssue
from firebase_admin import auth
import cloudinary.uploader

# Found Item Signals

@receiver(post_save, sender=FoundItem)
def update_found_count_on_save(sender, instance, created, **kwargs):
    """
    Increment found_count when a new FoundItem is created.
    """
    if created and instance.posted_by:
        user_profile = instance.posted_by
        user_profile.found_count = FoundItem.objects.filter(posted_by=user_profile).count()
        user_profile.save(update_fields=['found_count'])

@receiver(post_delete, sender=FoundItem)
def update_found_count_on_delete(sender, instance, **kwargs):
    """
    Decrement found_count when a FoundItem is deleted, and destroy Cloudinary image.
    """
    if instance.posted_by:
        user_profile = instance.posted_by
        user_profile.found_count = FoundItem.objects.filter(posted_by=user_profile).count()
        user_profile.save(update_fields=['found_count'])
        
    if instance.item_img:
        try:
            cloudinary.uploader.destroy(instance.item_img.name)
        except Exception:
            pass


# Lost Item Signals

@receiver(post_save, sender=LostItem)
def update_lost_count_on_save(sender, instance, created, **kwargs):
    """
    Increment lost_count when a new LostItem is created.
    """
    if created and instance.posted_by:
        user_profile = instance.posted_by
        user_profile.lost_count = LostItem.objects.filter(posted_by=user_profile).count()
        user_profile.save(update_fields=['lost_count'])

@receiver(post_delete, sender=LostItem)
def update_lost_count_on_delete(sender, instance, **kwargs):
    """
    Decrement lost_count when a LostItem is deleted, and destroy Cloudinary image.
    """
    if instance.posted_by:
        user_profile = instance.posted_by
        user_profile.lost_count = LostItem.objects.filter(posted_by=user_profile).count()
        user_profile.save(update_fields=['lost_count'])
        
    if instance.item_img:
        try:
            cloudinary.uploader.destroy(instance.item_img.name)
        except Exception:
            pass


# Firebase User Signals

@receiver(post_delete, sender=UserProfile)
def delete_firebase_user_on_profile_delete(sender, instance, **kwargs):
    """
    Automatically delete the corresponding Firebase account when a UserProfile is deleted,
    and wipe their Cloudinary custom profile picture.
    """
    if instance.firebase_uid:
        try:
            auth.delete_user(instance.firebase_uid)
            print(f"Successfully deleted Firebase user: {instance.firebase_uid}")
        except Exception as e:
            # Log the error but don't re-raise to avoid blocking Django deletion
            print(f"Failed to delete Firebase user {instance.firebase_uid}: {e}")
            
    if instance.profile_pic_url and 'res.cloudinary.com' in instance.profile_pic_url:
        try:
            # The custom uploaded pics are saved explicitly to this public_id
            public_id = f"profile_pics/IMG_{instance.user_id}"
            cloudinary.uploader.destroy(public_id)
        except Exception:
            pass

# Report Issue Signals
@receiver(post_delete, sender=ReportIssue)
def cleanup_report_issue_docs(sender, instance, **kwargs):
    """
    Destroy proof documents in Cloudinary when an issue is deleted.
    """
    if instance.proof_doc_1:
        try:
            cloudinary.uploader.destroy(instance.proof_doc_1.name)
        except Exception:
            pass
    if instance.proof_doc_2:
        try:
            cloudinary.uploader.destroy(instance.proof_doc_2.name)
        except Exception:
            pass
