import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/chat_model.dart';
import '../services/api_service.dart';
import 'chat_screen.dart';
import '../utils/string_extensions.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  late Future<List<Conversation>> _conversationsFuture;
  String? _currentBackendUserId;

  @override
  void initState() {
    super.initState();
    _refreshConversations();
    _initializeUserData();
  }

  Future<void> _initializeUserData() async {
    final profile = await ApiService().fetchUserProfile();
    if (profile != null && mounted) {
      setState(() {
        _currentBackendUserId = profile['user_id'];
      });
    }
  }

  Future<void> _refreshConversations() async {
    if (mounted) {
      setState(() {
        _conversationsFuture = ApiService().fetchConversations();
      });
      await _conversationsFuture;
    }
  }

  String _getOtherUserName(Conversation conversation) {
    if (_currentBackendUserId == null) return 'Loading...';
    try {
      final otherUser = conversation.participants.firstWhere(
        (u) => u.userId != _currentBackendUserId,
      );
      return otherUser.name;
    } catch (e) {
      return 'Unknown User';
    }
  }

  String _getOtherUserProfilePic(Conversation conversation) {
    if (_currentBackendUserId == null) return '';
    try {
      final otherUser = conversation.participants.firstWhere(
        (u) => u.userId != _currentBackendUserId,
      );
      return otherUser.profilePicUrl ?? '';
    } catch (e) {
      return '';
    }
  }

  String _getOtherUserRole(Conversation conversation) {
    if (_currentBackendUserId == null) return 'user';
    try {
      final otherUser = conversation.participants.firstWhere(
        (u) => u.userId != _currentBackendUserId,
      );
      return otherUser.role ?? 'user';
    } catch (e) {
      return 'user';
    }
  }

  String _getLastMessagePreview(Message? msg) {
    if (msg == null) return '(No messages)';
    if (msg.content.isNotEmpty) return msg.content;
    if (msg.msgType == 'image') return '📷 Image';
    if (msg.msgType == 'file') return '📁 Attachment';
    return 'Sent a message';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Chats', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.blueAccent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: FutureBuilder<List<Conversation>>(
        future: _conversationsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return RefreshIndicator(
              onRefresh: _refreshConversations,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(
                    height: 500,
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.chat_bubble_outline,
                            size: 64,
                            color: Colors.grey,
                          ),
                          SizedBox(height: 16),
                          Text(
                            'No messages yet',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          }

          final conversations =
              snapshot.data!.where((c) => c.lastMessage != null).toList();
          if (conversations.isEmpty) {
            return RefreshIndicator(
              onRefresh: _refreshConversations,
              child: ListView(
                children: const [
                  SizedBox(
                    height: 500,
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.chat_bubble_outline,
                            size: 64,
                            color: Colors.grey,
                          ),
                          SizedBox(height: 16),
                          Text(
                            'No messages yet',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: _refreshConversations,
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: conversations.length,
              itemBuilder: (context, index) {
                final conversation = conversations[index];
                final otherUserName = _getOtherUserName(conversation);
                final otherUserPic = _getOtherUserProfilePic(conversation);
                final lastMsg = conversation.lastMessage;
                final isUnread = conversation.unreadCount > 0;

                return ListTile(
                  leading: CircleAvatar(
                    backgroundImage:
                        otherUserPic.isNotEmpty
                            ? NetworkImage(otherUserPic)
                            : null,
                    child:
                        otherUserPic.isEmpty
                            ? Text(otherUserName[0].toUpperCase())
                            : null,
                  ),
                  title: Row(
                    children: [
                      Text(
                        otherUserName.toTitleCase(),
                        style: TextStyle(
                          fontWeight:
                              isUnread ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      if (_getOtherUserRole(conversation) == 'admin') ...[
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.verified,
                          size: 16,
                          color: Colors.blueAccent,
                        ),
                      ],
                      if (_getOtherUserRole(conversation) == 'deleted') ...[
                        const SizedBox(width: 4),
                        Icon(
                          Icons.info_outline,
                          size: 16,
                          color: Colors.grey[600],
                        ),
                      ],
                    ],
                  ),
                  subtitle: Text(
                    _getLastMessagePreview(lastMsg),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight:
                          isUnread ? FontWeight.bold : FontWeight.normal,
                      color: isUnread ? Colors.black87 : Colors.grey,
                    ),
                  ),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (lastMsg != null)
                        Text(
                          DateFormat(
                            'h:mm a',
                          ).format(lastMsg.timestamp.toLocal()),
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                      if (isUnread)
                        Container(
                          margin: const EdgeInsets.only(top: 4),
                          padding: const EdgeInsets.all(6),
                          decoration: const BoxDecoration(
                            color: Colors.blue,
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            '${conversation.unreadCount}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                            ),
                          ),
                        ),
                    ],
                  ),
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder:
                            (context) => ChatScreen(
                              conversationId: conversation.id,
                              title: otherUserName,
                              targetUserRole: _getOtherUserRole(conversation),
                            ),
                      ),
                    );
                    _refreshConversations();
                  },
                );
              },
            ),
          );
        },
      ),
    );
  }
}
