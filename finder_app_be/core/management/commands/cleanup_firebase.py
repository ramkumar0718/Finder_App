from django.core.management.base import BaseCommand
from core.firebase_utils import cleanup_orphaned_firebase_users

class Command(BaseCommand):
    help = 'Scans Firebase and deletes all users who do not have a corresponding UserProfile in Django.'

    def handle(self, *args, **options):
        self.stdout.write("Starting Firebase orphaned user cleanup...")
        result = cleanup_orphaned_firebase_users()
        
        if result['status'] == 'success':
            self.stdout.write(self.style.SUCCESS(
                f"Cleanup complete. Scanned {result['total_scanned']} users, deleted {result['deleted_count']} orphans."
            ))
            if result['errors']:
                self.stdout.write(self.style.WARNING(f"Encountered {len(result['errors'])} errors."))
                for err in result['errors']:
                    self.stdout.write(self.style.ERROR(err))
        else:
            self.stdout.write(self.style.ERROR(f"Cleanup failed: {result['message']}"))
