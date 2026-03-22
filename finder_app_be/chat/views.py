from rest_framework import status, permissions
from rest_framework.generics import ListCreateAPIView
from rest_framework.response import Response
from rest_framework.views import APIView
from .models import Conversation, Message
from .serializers import ConversationSerializer, MessageSerializer
from core.models import UserProfile

class ConversationListCreateView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        conversations = Conversation.objects.filter(participants=request.user)
        serializer = ConversationSerializer(conversations, many=True, context={'request': request})
        return Response(serializer.data)

    def post(self, request):
        target_user_id = request.data.get('target_user_id')
        if not target_user_id:
            return Response({'error': 'target_user_id is required'}, status=status.HTTP_400_BAD_REQUEST)

        try:
            target_user = UserProfile.objects.get(user_id=target_user_id)
        except UserProfile.DoesNotExist:
            return Response({'error': 'User not found'}, status=status.HTTP_404_NOT_FOUND)

        if target_user == request.user:
            return Response({'error': 'Cannot chat with yourself'}, status=status.HTTP_400_BAD_REQUEST)

        # Check for existing conversation
        conversations = Conversation.objects.filter(participants=request.user).filter(participants=target_user)
        if conversations.exists():
            conversation = conversations.first()
            serializer = ConversationSerializer(conversation, context={'request': request})
            return Response(serializer.data)

        conversation = Conversation.objects.create()
        conversation.participants.add(request.user, target_user)
        conversation.save()
        
        serializer = ConversationSerializer(conversation, context={'request': request})
        return Response(serializer.data, status=status.HTTP_201_CREATED)

class MessageListCreateView(ListCreateAPIView):
    serializer_class = MessageSerializer
    permission_classes = [permissions.IsAuthenticated]

    def get_queryset(self):
        conversation_id = self.kwargs['conversation_id']
        conversation = Conversation.objects.get(id=conversation_id)
        
        if self.request.user not in conversation.participants.all():
            return Message.objects.none()
            
        unread_messages = conversation.messages.filter(is_read=False).exclude(sender=self.request.user)
        unread_messages.update(is_read=True)
        
        return conversation.messages.all()

    def perform_create(self, serializer):
        conversation_id = self.kwargs['conversation_id']
        conversation = Conversation.objects.get(id=conversation_id)
        
        if self.request.user not in conversation.participants.all():
            raise permissions.PermissionDenied("You are not a participant of this conversation")
            
        serializer.save(sender=self.request.user, conversation=conversation)
        
        conversation.save()
