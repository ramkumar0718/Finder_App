import 'dart:async';
import 'package:finder_app_fe/utils/string_extensions.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/api_service.dart';
import 'home_screen.dart'; // To access ItemModel
import 'edit_item_screen.dart';
import 'report_issues_screen.dart';
import 'chat_screen.dart';
import '../models/chat_model.dart';
import '../models/request_model.dart';
import 'admin/issue_details_screen.dart';

class ItemDetailsScreen extends StatefulWidget {
  final ItemModel item;
  final String? currentUserId;

  const ItemDetailsScreen({super.key, required this.item, this.currentUserId});

  @override
  State<ItemDetailsScreen> createState() => _ItemDetailsScreenState();
}

class _ItemDetailsScreenState extends State<ItemDetailsScreen> {
  late ItemModel _item;
  bool _isLoadingRequestStatus = true;
  OwnershipRequest? _pendingRequest;
  bool _isAdmin = false;
  List<dynamic> _issues = [];
  bool _isLoadingIssues = true;

  @override
  void initState() {
    super.initState();
    _item = widget.item;
    _checkPendingRequest();
    _checkAdminRole();
    _fetchIssues();
  }

  Future<void> _checkAdminRole() async {
    try {
      final role = await ApiService().getUserRole();
      if (mounted) {
        setState(() {
          _isAdmin = role == 'admin';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isAdmin = false;
        });
      }
    }
  }

  Future<void> _checkPendingRequest() async {
    if (isOwnPost &&
        _item.status.toLowerCase() == 'found' &&
        !_item.ownerIdentified) {
      try {
        final requests = await ApiService().fetchOwnershipRequests();
        final List<OwnershipRequest> ownershipRequests =
            requests.map((json) => OwnershipRequest.fromJson(json)).toList();

        final pending =
            ownershipRequests
                .where(
                  (r) =>
                      r.foundItemId.toString() == _item.id &&
                      r.status == 'pending',
                )
                .toList();

        if (mounted) {
          setState(() {
            _pendingRequest = pending.isNotEmpty ? pending.first : null;
            _isLoadingRequestStatus = false;
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _isLoadingRequestStatus = false;
          });
        }
      }
    } else {
      if (mounted) {
        setState(() {
          _isLoadingRequestStatus = false;
        });
      }
    }
  }

  Future<void> _fetchIssues() async {
    try {
      final issues = await ApiService().fetchIssuesForPost(_item.id);
      if (mounted) {
        setState(() {
          _issues = issues;
          _isLoadingIssues = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingIssues = false;
        });
      }
    }
  }

  bool get isOwnPost => widget.currentUserId == _item.postedBy;

  String _formatDate(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      return DateFormat('MMM d, yyyy').format(date);
    } catch (e) {
      return dateStr;
    }
  }

  Future<void> _showAssignOwnerDialog() async {
    try {
      final Set<String> processedUserIds = {};
      final List<ChatUser> chatUsers = [];

      if (_isAdmin) {
        final users = await ApiService().fetchAllUsersForAdmin();
        chatUsers.addAll(
          users
              .where((u) => u['user_id'] != _item.postedBy)
              .map(
                (u) => ChatUser(
                  userId: u['user_id'],
                  name: u['name'],
                  profilePicUrl: u['profile_pic_url'] ?? u['profile_pic'],
                ),
              ),
        );
      } else {
        final conversations = await ApiService().fetchConversations();
        for (var conversation in conversations) {
          try {
            final otherUser = conversation.participants.firstWhere(
              (u) => u.userId != widget.currentUserId,
            );

            if (!processedUserIds.contains(otherUser.userId)) {
              processedUserIds.add(otherUser.userId);
              chatUsers.add(otherUser);
            }
          } catch (e) {}
        }
      }

      if (!mounted) return;

      if (chatUsers.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isAdmin
                  ? 'No users found. Please check backend connection.'
                  : 'No active chats found. You can only assign an owner from your active chats.',
            ),
          ),
        );
        return;
      }

      showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Select Potential Owner'),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Choose a user from your active chats to verify ownership.',
                  ),
                  const SizedBox(height: 10),
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: chatUsers.length,
                      itemBuilder: (context, index) {
                        final user = chatUsers[index];
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundImage:
                                user.profilePicUrl != null &&
                                        user.profilePicUrl!.isNotEmpty
                                    ? NetworkImage(user.profilePicUrl!)
                                    : null,
                            child:
                                user.profilePicUrl == null ||
                                        user.profilePicUrl!.isEmpty
                                    ? Text(
                                      user.name.isNotEmpty
                                          ? user.name[0].toUpperCase()
                                          : 'U',
                                    )
                                    : null,
                          ),
                          title: Text(user.name),
                          subtitle: Text('@${user.userId}'),
                          onTap: () async {
                            final outerContext = context;
                            Navigator.pop(context);

                            if (!outerContext.mounted) return;

                            try {
                              showDialog(
                                context: outerContext,
                                barrierDismissible: false,
                                builder:
                                    (context) => const Center(
                                      child: CircularProgressIndicator(),
                                    ),
                              );
                              final lostItems = await ApiService()
                                  .fetchUserLostItems(user.userId);
                              if (outerContext.mounted) {
                                Navigator.pop(outerContext);
                              }

                              if (lostItems.isEmpty) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Error: User @${user.userId} has no lost items posted. Assignment requires a linked lost post.',
                                      ),
                                      // backgroundColor: Colors.red,
                                    ),
                                  );
                                }
                                return;
                              }
                              _showUserLostItemsDialog(user, lostItems);
                            } catch (e) {
                              if (context.mounted) {
                                Navigator.pop(context);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Error checking items: $e'),
                                  ),
                                );
                              }
                            }
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error loading chats: $e')));
      }
    }
  }

  Future<void> _showUserLostItemsDialog(
    ChatUser selectedUser,
    List<dynamic> lostItems,
  ) async {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Select @${selectedUser.userId}\'s Lost Item'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Select which of their lost items matches this found item for verification.',
                ),
                const SizedBox(height: 10),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: lostItems.length,
                    itemBuilder: (context, index) {
                      final item = lostItems[index];
                      return ListTile(
                        leading:
                            item['item_img'] != null
                                ? Image.network(
                                  item['item_img'],
                                  width: 40,
                                  height: 40,
                                  fit: BoxFit.cover,
                                )
                                : const Icon(Icons.inventory_2),
                        title: Text(item['item_name']),
                        subtitle: Text('Post ID: ${item['post_id']}'),
                        onTap: () {
                          Navigator.pop(context);
                          _showRequestConfirmationDialog(selectedUser, item);
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
  }

  void _showRequestConfirmationDialog(
    ChatUser selectedUser,
    Map<String, dynamic>? lostItem,
  ) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(
            _isAdmin ? 'Assign Ownership Directly' : 'Send Ownership Request',
          ),
          content: Text(
            _isAdmin
                ? 'Do you want to directly assign ownership to @${selectedUser.userId}${lostItem != null ? ' for their lost item "${lostItem['item_name']}"?' : '?'}'
                : 'Do you want to send an ownership verification request to @${selectedUser.userId}${lostItem != null ? ' for their lost item "${lostItem['item_name']}"?' : '?'}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context); // Close dialog
                _sendOwnershipRequest(selectedUser, lostItem);
              },
              child: Text(_isAdmin ? 'Assign' : 'Send'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _sendOwnershipRequest(
    ChatUser user,
    Map<String, dynamic>? lostItem,
  ) async {
    final String foundItemId = _item.id;
    final String? lostItemId = lostItem?['post_id'];
    final String ownerUserId = user.userId;

    debugPrint('Sending Ownership Request:');
    debugPrint('- Found Item ID: $foundItemId');
    debugPrint('- Lost Item ID: $lostItemId');
    debugPrint('- Owner User ID: $ownerUserId');

    try {
      final response =
          _isAdmin
              ? await ApiService().directAssignOwnership(
                foundItemId: foundItemId,
                ownerUserId: ownerUserId,
                lostItemId: lostItemId,
              )
              : await ApiService().sendOwnershipRequest(
                foundItemId: foundItemId,
                lostItemId: lostItemId,
                ownerUserId: ownerUserId,
              );

      if (mounted) {
        if (response.statusCode == 200 || response.statusCode == 201) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                _isAdmin
                    ? 'Ownership assigned successfully!'
                    : 'Ownership request sent!',
              ),
            ),
          );

          if (_isAdmin) {
            Navigator.pop(context, true);
          } else {
            _checkPendingRequest();
          }
        } else {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Failed: ${response.body}')));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _unassignOwnership() async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Confirm Unassign'),
            content: const Text(
              'Are you sure you want to unassign this post? This will reset ownership status for both linked posts.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text(
                  'Unassign',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
    );

    if (confirm != true) return;

    try {
      final isLost = _item.status.toLowerCase() == 'lost';
      final response = await ApiService().adminUnassignOwnership(
        postId: _item.id,
        postType: isLost ? 'lost' : 'found',
      );

      if (mounted) {
        if (response.statusCode == 200 || response.statusCode == 201) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Unassigned successfully!')),
          );
          Navigator.pop(context, true);
        } else {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Failed: ${response.body}')));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLost = _item.status.toLowerCase() == 'lost';
    final statusColor = isLost ? Colors.red : Colors.green;
    final statusBgColor = isLost ? Colors.red[100]! : Colors.green[100]!;
    final statusText = isLost ? 'Lost' : 'Found';

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text(
          'Item Details',
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: Colors.blueAccent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          _checkPendingRequest();
          await _fetchIssues();
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isOwnPost || _isAdmin)
                _buildOwnPostHeader(
                  context,
                  statusText,
                  statusColor,
                  statusBgColor,
                )
              else
                _buildOtherUserHeader(statusText, statusColor, statusBgColor),

              const SizedBox(height: 16),

              Container(
                width: double.infinity,
                height: MediaQuery.of(context).size.width - 32,
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child:
                    _item.itemImg != null
                        ? ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.network(
                            _item.itemImg!,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return const Center(
                                child: Icon(
                                  Icons.broken_image,
                                  size: 50,
                                  color: Colors.grey,
                                ),
                              );
                            },
                          ),
                        )
                        : const Center(
                          child: Icon(
                            Icons.image_not_supported,
                            size: 50,
                            color: Colors.grey,
                          ),
                        ),
              ),

              const SizedBox(height: 24),

              _buildStatusCard(context, isLost),

              const SizedBox(height: 16),

              _buildDetailsCard(),

              const SizedBox(height: 16),

              _buildIssuesCard(),

              if (!isOwnPost) ...[
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      final targetId = _item.postedBy;
                      if (targetId.isNotEmpty) {
                        if (targetId == widget.currentUserId) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('You cannot chat with yourself.'),
                            ),
                          );
                          return;
                        }
                        if (_item.postedByRole == 'deleted') {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('This account has been deleted.'),
                            ),
                          );
                          return;
                        }
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder:
                                (context) => ChatScreen(
                                  title: _item.postedByName,
                                  targetUserId: targetId,
                                  targetUserRole: _item.postedByRole,
                                  itemImage: _item.itemImg,
                                  itemSubtitle:
                                      '${_item.itemName} • ${_item.location}',
                                ),
                          ),
                        );
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Cannot chat with this user'),
                          ),
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          _item.postedByRole == 'deleted'
                              ? Colors.grey
                              : Colors.blueAccent,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: Icon(
                      _item.postedByRole == 'deleted' ? Icons.info : Icons.chat,
                      color: Colors.white,
                    ),
                    label: const Text(
                      'Contact',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOwnPostHeader(
    BuildContext context,
    String statusText,
    Color statusColor,
    Color statusBgColor,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_isAdmin && !isOwnPost)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: Colors.grey[300],
                    backgroundImage:
                        _item.profilePicUrl != null &&
                                _item.profilePicUrl!.isNotEmpty
                            ? NetworkImage(_item.profilePicUrl!)
                            : null,
                    child:
                        _item.profilePicUrl == null ||
                                _item.profilePicUrl!.isEmpty
                            ? Text(
                              _item.postedByName.isNotEmpty
                                  ? _item.postedByName[0].toUpperCase()
                                  : 'U',
                            )
                            : null,
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            _item.postedByName.toTitleCase(),
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.black,
                            ),
                          ),
                          if (_item.postedByRole == 'admin') ...[
                            const SizedBox(width: 4),
                            const Icon(
                              Icons.verified,
                              size: 18,
                              color: Colors.blueAccent,
                            ),
                          ],
                        ],
                      ),
                      Text(
                        '@${_item.postedBy}',
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: statusBgColor,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  statusText,
                  style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          )
        else
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Your Post',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: statusBgColor,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  statusText,
                  style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () async {
                  final result = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => EditItemScreen(item: _item),
                    ),
                  );
                  if (result == true && context.mounted) {
                    Navigator.pop(context);
                  }
                },
                icon: const Icon(Icons.edit, size: 16),
                label: const Text('Edit', style: TextStyle(fontSize: 16)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () {
                  _showDeleteConfirmation(context);
                },
                icon: const Icon(Icons.delete, size: 16),
                label: const Text('Delete', style: TextStyle(fontSize: 16)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildOtherUserHeader(
    String statusText,
    Color statusColor,
    Color statusBgColor,
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: Colors.grey[300],
              backgroundImage:
                  _item.profilePicUrl != null && _item.profilePicUrl!.isNotEmpty
                      ? NetworkImage(_item.profilePicUrl!)
                      : null,
              child:
                  _item.profilePicUrl == null || _item.profilePicUrl!.isEmpty
                      ? Text(
                        _item.postedByName.isNotEmpty
                            ? _item.postedByName[0].toUpperCase()
                            : 'U',
                      )
                      : null,
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      _item.postedByName.toTitleCase(),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                    if (_item.postedByRole == 'admin') ...[
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.verified,
                        size: 18,
                        color: Colors.blueAccent,
                      ),
                    ],
                  ],
                ),
                Text(
                  '@${_item.postedBy}',
                  style: const TextStyle(fontSize: 14, color: Colors.grey),
                ),
              ],
            ),
          ],
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: statusBgColor,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            statusText,
            style: TextStyle(color: statusColor, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }

  Widget _buildStatusCard(BuildContext context, bool isLost) {
    if (_item.status.toLowerCase() != 'lost' &&
        _item.status.toLowerCase() != 'found') {
      return const SizedBox.shrink();
    }

    final title = isLost ? 'Finder' : 'Owner';
    final isIdentified =
        isLost ? _item.finderIdentified : _item.ownerIdentified;
    final identifiedBy = isLost ? _item.finderId : _item.ownerId;
    final matchedPost = isLost ? _item.matchedPost : _item.matchedPost;

    final identifiedBgColor =
        isIdentified ? const Color(0xFFEBEAFE) : const Color(0xFFFEE6AA);
    final identifiedTextColor =
        isIdentified ? const Color(0xFF554A8F) : const Color(0xFF9E7230);
    final identifiedText =
        isIdentified
            ? 'Identified'
            : (isLost ? 'Awaiting Finder' : 'Awaiting Owner');

    final chatBgColor =
        isIdentified ? Colors.lightBlue[100]! : Colors.grey[200]!;
    final chatTextColor = isIdentified ? Colors.blue : Colors.grey;
    final chatText = 'Chat';

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (_isAdmin &&
                        isIdentified &&
                        _item.info != null &&
                        _item.info != 'None')
                      ...([
                        const SizedBox(width: 8),
                        AdminInfoIcon(info: _item.info!, iconSize: 24),
                      ]),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: identifiedBgColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    identifiedText,
                    style: TextStyle(
                      color: identifiedTextColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Text(
                      isIdentified ? '@$identifiedBy' : '@user_id: -',
                      style: const TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                  ],
                ),
                InkWell(
                  onTap: () {
                    if (!isIdentified) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Cannot chat with this user'),
                        ),
                      );
                      return;
                    }

                    final targetId = isLost ? _item.finderId : _item.ownerId;

                    if (targetId == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('User ID not available')),
                      );
                      return;
                    }

                    if (targetId == widget.currentUserId) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('You cannot chat with yourself.'),
                        ),
                      );
                      return;
                    }

                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder:
                            (context) => ChatScreen(
                              title: targetId,
                              targetUserId: targetId,
                              targetUserRole:
                                  isLost ? _item.finderRole : _item.ownerRole,
                              itemImage: _item.itemImg,
                              itemSubtitle:
                                  '${_item.itemName} • ${_item.location}',
                            ),
                      ),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: chatBgColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      chatText,
                      style: TextStyle(
                        color: chatTextColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 3),
            Row(
              children: [
                Text(
                  isIdentified ? '@$matchedPost' : '@matched_post_id: -',
                  style: const TextStyle(fontSize: 16, color: Colors.grey),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Builder(
              builder: (context) {
                if ((isOwnPost || _isAdmin) && !isLost && !isIdentified) {
                  if (_isLoadingRequestStatus) {
                    return const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    );
                  }

                  if (_pendingRequest != null) {
                    return Align(
                      alignment: Alignment.centerLeft,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Ownership request is pending verification.',
                              ),
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFEE6AA),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                        icon: const Icon(
                          Icons.hourglass_empty,
                          color: Color(0xFF9E7230),
                          size: 18,
                        ),
                        label: const Text(
                          'Request Sended',
                          style: TextStyle(
                            color: Color(0xFF9E7230),
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    );
                  }

                  return Align(
                    alignment: Alignment.centerLeft,
                    child: ElevatedButton.icon(
                      onPressed: _showAssignOwnerDialog,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueAccent,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                      icon: const Icon(
                        Icons.add_circle_outline,
                        color: Colors.white,
                        size: 18,
                      ),
                      label: const Text(
                        'Assign owner',
                        style: TextStyle(color: Colors.white, fontSize: 14),
                      ),
                    ),
                  );
                } else if (_isAdmin && isIdentified) {
                  return Align(
                    alignment: Alignment.centerLeft,
                    child: ElevatedButton.icon(
                      onPressed: _unassignOwnership,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                      icon: const Icon(
                        Icons.remove_circle_outline,
                        color: Colors.white,
                        size: 18,
                      ),
                      label: const Text(
                        'Unassign Owner',
                        style: TextStyle(color: Colors.white, fontSize: 14),
                      ),
                    ),
                  );
                } else if (!isOwnPost && !_isAdmin) {
                  return SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () async {
                        final result = await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder:
                                (context) => ReportIssuesScreen(item: _item),
                          ),
                        );
                        if (result == true) {
                          _fetchIssues();
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                      child: const Text(
                        'Report',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailsCard() {
    return SizedBox(
      width: double.infinity,
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: _item.itemName.toTitleCase(),
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    TextSpan(
                      text: ' : ${_item.id}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.normal,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _item.description,
                style: const TextStyle(
                  fontSize: 16,
                  height: 1.5,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 16),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.category, size: 20, color: Colors.grey),
                      const SizedBox(width: 8),
                      Text(
                        _item.category,
                        style: const TextStyle(fontSize: 16),
                      ),
                    ],
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_item.colorId != 'none')
                        Builder(
                          builder: (context) {
                            try {
                              String colorStr = _item.colorId;
                              if (!colorStr.startsWith('0X') &&
                                  !colorStr.startsWith('0x')) {
                                if (colorStr.length == 6) {
                                  colorStr = '0XFF$colorStr';
                                }
                              }
                              final colorInt = int.parse(colorStr);
                              return Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  color: Color(colorInt),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.grey.withOpacity(0.5),
                                  ),
                                ),
                              );
                            } catch (e) {
                              return const Icon(
                                Icons.color_lens,
                                color: Colors.grey,
                                size: 24,
                              );
                            }
                          },
                        )
                      else
                        const Icon(
                          Icons.color_lens,
                          color: Colors.grey,
                          size: 24,
                        ),
                      const SizedBox(width: 8),
                      Text(
                        'Color: ${_item.colorName}',
                        style: const TextStyle(fontSize: 16),
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 12),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.location_on_outlined,
                          size: 20,
                          color: Colors.grey,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _item.location,
                            style: const TextStyle(fontSize: 16),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.calendar_today_outlined,
                        size: 20,
                        color: Colors.grey,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _formatDate(_item.date),
                        style: const TextStyle(fontSize: 16),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIssuesCard() {
    if (_isLoadingIssues) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_issues.isEmpty) {
      return const SizedBox.shrink();
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Issues',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _issues.length,
              separatorBuilder: (context, index) => const Divider(),
              itemBuilder: (context, index) {
                final issue = _issues[index];
                final status = issue['issue_status'] ?? 'Not Responded';
                final isResponded = status == 'Responded';

                final statusTextColor =
                    isResponded
                        ? const Color(0xFF554A8F)
                        : const Color(0xFF9E7230);

                final statusBgColor =
                    isResponded
                        ? const Color(0xFFEBEAFE)
                        : const Color(0xFFFEE6AA);

                return InkWell(
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => IssueDetailsScreen(issue: issue),
                      ),
                    );
                    if (mounted) setState(() {});
                    _fetchIssues();
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 30,
                          child: Text(
                            '${index + 1}.',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            issue['issue_id'] ?? '-',
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: statusBgColor,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            status,
                            style: TextStyle(
                              color: statusTextColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.chevron_right,
                          size: 16,
                          color: Colors.grey,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Delete Post'),
          content: const Text(
            'Are you sure you want to delete this post? This action cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                await _deletePost(context);
              },
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _deletePost(BuildContext context) async {
    try {
      final isLost = _item.status.toLowerCase() != 'found';
      final success = await ApiService().deleteItem(_item.id, isLost);

      if (context.mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Post deleted successfully')),
          );
          Navigator.pop(context); // Go back to home
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to delete post')),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error deleting post: $e')));
      }
    }
  }
}

class AdminInfoIcon extends StatefulWidget {
  final String info;
  final double iconSize;

  const AdminInfoIcon({super.key, required this.info, this.iconSize = 18});

  @override
  State<AdminInfoIcon> createState() => _AdminInfoIconState();
}

class _AdminInfoIconState extends State<AdminInfoIcon> {
  OverlayEntry? _overlayEntry;
  Timer? _timer;

  void _showOverlay() {
    _timer?.cancel();
    _overlayEntry?.remove();

    final RenderBox? renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final offset = renderBox.localToGlobal(Offset.zero);

    _overlayEntry = OverlayEntry(
      builder:
          (context) => Positioned(
            left: offset.dx - 40,
            top: offset.dy + renderBox.size.height + 5,
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.blueAccent,
                  borderRadius: BorderRadius.circular(4),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Text(
                  widget.info,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
    );

    Overlay.of(context).insert(_overlayEntry!);

    _timer = Timer(const Duration(seconds: 2), () {
      _overlayEntry?.remove();
      _overlayEntry = null;
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _overlayEntry?.remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _showOverlay,
      child: Container(
        margin: const EdgeInsets.only(left: 6),
        padding: const EdgeInsets.all(2),
        decoration: const BoxDecoration(
          color: Color(0xFFEBEAFE),
          shape: BoxShape.circle,
        ),
        child: Icon(
          Icons.info_outline_rounded,
          size: widget.iconSize,
          color: const Color(0xFF554A8F),
        ),
      ),
    );
  }
}
