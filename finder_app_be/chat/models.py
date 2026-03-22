import uuid
from django.db import models
from core.models import UserProfile, generate_gen_token

class Conversation(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    participants = models.ManyToManyField(UserProfile, related_name='conversations')
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['-updated_at']

    def __str__(self):
        return f"Conversation {self.id}"

def chat_file_path(instance, filename):
    ext = filename.split('.')[-1]
    sender_id = instance.sender.user_id if instance.sender and instance.sender.user_id else instance.sender.pk
    
    receiver_id = "unknown"
    if instance.conversation:
        participants = instance.conversation.participants.exclude(pk=instance.sender.pk).first()
        if participants:
            receiver_id = participants.user_id if participants.user_id else participants.pk

    gen = generate_gen_token(5)
    
    # Determine prefix
    if instance.msg_type == 'image' or ext.lower() in ['jpg', 'jpeg', 'png', 'gif', 'webp']:
        prefix = 'IMG'
    else:
        prefix = 'DOC'
        
    return f'chat_files/{prefix}_{sender_id}_{receiver_id}_{gen}.{ext}'

class Message(models.Model):
    MSG_TYPE_CHOICES = (
        ('text', 'Text'),
        ('image', 'Image'),
        ('file', 'File'),
        ('voice', 'Voice'),
    )

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    conversation = models.ForeignKey(Conversation, related_name='messages', on_delete=models.CASCADE)
    sender = models.ForeignKey(UserProfile, related_name='sent_messages', on_delete=models.CASCADE)
    content = models.TextField(blank=True, null=True)
    file = models.FileField(upload_to=chat_file_path, blank=True, null=True)
    msg_type = models.CharField(max_length=10, choices=MSG_TYPE_CHOICES, default='text')
    timestamp = models.DateTimeField(auto_now_add=True)
    is_read = models.BooleanField(default=False)

    class Meta:
        ordering = ['timestamp']

    def __str__(self):
        return f"Message {self.id} from {self.sender}"
