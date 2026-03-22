from rest_framework import serializers
from .models import Conversation, Message
from core.serializers import UserProfileSerializer

class MessageSerializer(serializers.ModelSerializer):
    sender_user = UserProfileSerializer(source='sender', read_only=True)
    
    class Meta:
        model = Message
        fields = ['id', 'conversation', 'sender', 'sender_user', 'content', 'file', 'msg_type', 'timestamp', 'is_read']
        read_only_fields = ['id', 'timestamp', 'is_read', 'conversation', 'sender']

    def validate_content(self, value):
        if value:
            import re
            clean = re.compile('<.*?>')
            return re.sub(clean, '', value)
        return value

class ConversationSerializer(serializers.ModelSerializer):
    participants = UserProfileSerializer(many=True, read_only=True)
    last_message = serializers.SerializerMethodField()
    unread_count = serializers.SerializerMethodField()

    class Meta:
        model = Conversation
        fields = ['id', 'participants', 'updated_at', 'last_message', 'unread_count']

    def get_last_message(self, obj):
        last_msg = obj.messages.last()
        if last_msg:
            return MessageSerializer(last_msg).data
        return None
        
    def get_unread_count(self, obj):
        request = self.context.get('request')
        if request and request.user:
            return obj.messages.filter(is_read=False).exclude(sender=request.user).count()
        return 0
