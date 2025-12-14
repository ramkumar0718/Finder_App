from django.db.models.signals import post_save, post_delete
from django.dispatch import receiver
from .models import FoundItem, LostItem, UserProfile

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
    Decrement found_count when a FoundItem is deleted.
    """
    if instance.posted_by:
        user_profile = instance.posted_by
        user_profile.found_count = FoundItem.objects.filter(posted_by=user_profile).count()
        user_profile.save(update_fields=['found_count'])


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
    Decrement lost_count when a LostItem is deleted.
    """
    if instance.posted_by:
        user_profile = instance.posted_by
        user_profile.lost_count = LostItem.objects.filter(posted_by=user_profile).count()
        user_profile.save(update_fields=['lost_count'])
