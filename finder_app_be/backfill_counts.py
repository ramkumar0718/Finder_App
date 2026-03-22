import os
import django

# Set up Django environment
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'finder_app_be.settings')
django.setup()

from core.models import UserProfile, FoundItem, LostItem

def backfill_counts():
    # print("Starting backfill of user post counts...")
    users = UserProfile.objects.all()
    count = 0
    for user in users:
        found = FoundItem.objects.filter(posted_by=user).count()
        lost = LostItem.objects.filter(posted_by=user).count()
        
        if user.found_count != found or user.lost_count != lost:
            user.found_count = found
            user.lost_count = lost
            user.save(update_fields=['found_count', 'lost_count'])
            # print(f"Updated {user.user_name}: Found={found}, Lost={lost}")
            count += 1
            
    # print(f"Backfill complete. Updated {count} users.")

if __name__ == "__main__":
    backfill_counts()
