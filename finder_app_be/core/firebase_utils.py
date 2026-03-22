from firebase_admin import auth
from .models import UserProfile
import logging

logger = logging.getLogger(__name__)

def cleanup_orphaned_firebase_users():
    """
    Scans all users in Firebase and deletes those that do not have a corresponding
    UserProfile in the Django database.
    
    Returns:
        dict: Summary of the cleanup operation.
    """
    deleted_count = 0
    errors = []
    total_scanned = 0
    
    try:
        # List all users from Firebase (fetches in batches of 1000)
        page = auth.list_users()
        while page:
            for user in page.users:
                total_scanned += 1
                uid = user.uid
                
                # Check if user exists in Django UserProfile
                if not UserProfile.objects.filter(firebase_uid=uid).exists():
                    try:
                        auth.delete_user(uid)
                        deleted_count += 1
                        logger.info(f"Deleted orphaned Firebase user: {uid}")
                    except Exception as e:
                        error_msg = f"Failed to delete orphaned user {uid}: {str(e)}"
                        logger.error(error_msg)
                        errors.append(error_msg)
            
            # Get next page
            page = page.get_next_page()
            
        return {
            'status': 'success',
            'total_scanned': total_scanned,
            'deleted_count': deleted_count,
            'errors': errors
        }
        
    except Exception as e:
        error_msg = f"Cleanup failed: {str(e)}"
        logger.error(error_msg)
        return {
            'status': 'error',
            'message': error_msg,
            'total_scanned': total_scanned,
            'deleted_count': deleted_count
        }
