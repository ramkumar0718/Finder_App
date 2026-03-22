class Conversation {
  final String id;
  final List<ChatUser> participants;
  final Message? lastMessage;
  final int unreadCount;
  final DateTime updatedAt;

  Conversation({
    required this.id,
    required this.participants,
    this.lastMessage,
    required this.unreadCount,
    required this.updatedAt,
  });

  factory Conversation.fromJson(Map<String, dynamic> json) {
    return Conversation(
      id: json['id'],
      participants:
          (json['participants'] as List)
              .map((e) => ChatUser.fromJson(e))
              .toList(),
      lastMessage:
          json['last_message'] != null
              ? Message.fromJson(json['last_message'])
              : null,
      unreadCount: json['unread_count'] ?? 0,
      updatedAt: DateTime.parse(json['updated_at']),
    );
  }
}

class ChatUser {
  final String userId;
  final String name;
  final String? profilePicUrl;
  final String? role;

  ChatUser({
    required this.userId,
    required this.name,
    this.profilePicUrl,
    this.role,
  });

  factory ChatUser.fromJson(Map<String, dynamic> json) {
    return ChatUser(
      userId: json['user_id'],
      name: json['user_name'] ?? json['name'] ?? 'Unknown',
      profilePicUrl: json['profile_pic_url'],
      role: json['role'],
    );
  }
}

class Message {
  final String id;
  final String conversationId;
  final String senderId;
  final ChatUser senderUser;
  final String content;
  final String msgType;
  final String? fileUrl;
  final DateTime timestamp;
  final bool isRead;
  final bool isSending;

  Message({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.senderUser,
    required this.content,
    required this.msgType,
    this.fileUrl,
    required this.timestamp,
    required this.isRead,
    this.isSending = false,
  });

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['id'],
      conversationId: json['conversation'],
      senderId: json['sender'],
      senderUser: ChatUser.fromJson(json['sender_user']),
      content: json['content'] ?? '',
      msgType: json['msg_type'] ?? 'text',
      fileUrl:
          json['file_url'] ??
          json['file'] ??
          json['image'] ??
          json['attachment'],
      timestamp: DateTime.parse(json['timestamp']),
      isRead: json['is_read'] ?? false,
    );
  }
}
