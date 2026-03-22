import 'package:finder_app_fe/utils/string_extensions.dart';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'home_screen.dart';
import 'item_details_screen.dart';
import '../models/request_model.dart';

class NotificationScreen extends StatefulWidget {
  const NotificationScreen({super.key});

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  List<ItemModel> _recentItems = [];
  List<OwnershipRequest> _requests = [];
  bool _isLoading = true;
  String? _currentUserId;
  String _selectedFilter = 'All'; // 'All', 'Recent', 'Request'

  @override
  void initState() {
    super.initState();
    _fetchCurrentUser();
  }

  Future<void> _fetchCurrentUser() async {
    try {
      final data = await ApiService().fetchUserProfile();
      if (data != null && mounted) {
        setState(() {
          _currentUserId = data['user_id'];
        });
        _fetchData();
      }
    } catch (e) {
      // Error fetching user profile
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);
    await Future.wait([_fetchRecentItems(), _fetchRequests()]);
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchRequests() async {
    try {
      final data = await ApiService().fetchOwnershipRequests();
      if (mounted) {
        setState(() {
          _requests =
              data.map((json) => OwnershipRequest.fromJson(json)).toList();
        });
      }
    } catch (e) {
      // Error fetching requests
    }
  }

  Future<void> _fetchRecentItems() async {
    try {
      final foundData = await ApiService().fetchFoundItems();
      final lostData = await ApiService().fetchLostItems();

      List<ItemModel> allItems = [];
      allItems.addAll(foundData.map((json) => ItemModel.fromJson(json)));
      allItems.addAll(lostData.map((json) => ItemModel.fromJson(json)));

      final now = DateTime.now();
      final thirtyDaysAgo = now.subtract(const Duration(days: 30));

      final filteredItems =
          allItems.where((item) {
            try {
              final postedDate = DateTime.parse(item.postedTime);
              final isRecent = postedDate.isAfter(thirtyDaysAgo);
              final isNotOwnPost = item.postedBy != _currentUserId;
              return isRecent && isNotOwnPost;
            } catch (e) {
              return false;
            }
          }).toList();

      filteredItems.sort((a, b) {
        try {
          final dateA = DateTime.parse(a.postedTime);
          final dateB = DateTime.parse(b.postedTime);
          return dateB.compareTo(dateA);
        } catch (e) {
          return 0;
        }
      });

      if (mounted) {
        setState(() {
          _recentItems = filteredItems;
        });
      }
    } catch (e) {
      // Error fetching items
    }
  }

  String _formatTimeAgo(String timeStr) {
    try {
      final date = DateTime.parse(timeStr);
      final now = DateTime.now();
      final difference = now.difference(date);

      if (difference.inDays > 0) {
        return '${difference.inDays}d ago';
      } else if (difference.inHours > 0) {
        return '${difference.inHours}h ago';
      } else if (difference.inMinutes > 0) {
        return '${difference.inMinutes}m ago';
      } else {
        return 'Just now';
      }
    } catch (e) {
      return '';
    }
  }

  Future<void> _respondToRequest(int requestId, String action) async {
    try {
      final response = await ApiService().respondToOwnershipRequest(
        requestId: requestId,
        action: action,
      );

      if (response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Request ${action}ed successfully!')),
          );
          _fetchData();
        }
      } else {
        throw Exception('Failed to respond to request');
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
    List<dynamic> combinedList = [];

    if (_selectedFilter == 'All') {
      combinedList.addAll(_requests);
      combinedList.addAll(_recentItems);
      // Sort combined list by time
      combinedList.sort((a, b) {
        DateTime dateA =
            a is OwnershipRequest
                ? a.createdAt
                : DateTime.parse((a as ItemModel).postedTime);
        DateTime dateB =
            b is OwnershipRequest
                ? b.createdAt
                : DateTime.parse((b as ItemModel).postedTime);
        return dateB.compareTo(dateA);
      });
    } else if (_selectedFilter == 'Recent') {
      combinedList.addAll(_recentItems);
    } else if (_selectedFilter == 'Request') {
      combinedList.addAll(_requests);
      // Sort requests by time
      combinedList.sort(
        (a, b) => (b as OwnershipRequest).createdAt.compareTo(
          (a as OwnershipRequest).createdAt,
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text(
          'Notifications',
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: Colors.blueAccent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        automaticallyImplyLeading: false,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  _buildFilterChip('All'),
                  const SizedBox(width: 12),
                  _buildFilterChip('Recent'),
                  const SizedBox(width: 12),
                  _buildFilterChip('Request'),
                ],
              ),
            ),
          ),

          Expanded(
            child:
                _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : combinedList.isEmpty
                    ? _buildEmptyState(
                      'No notifications found',
                      Icons.notifications_none,
                    )
                    : RefreshIndicator(
                      onRefresh: _fetchData,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16.0),
                        itemCount: combinedList.length,
                        itemBuilder: (context, index) {
                          final item = combinedList[index];
                          if (item is OwnershipRequest) {
                            return _buildRequestCard(item);
                          } else {
                            return _buildNotificationCard(item as ItemModel);
                          }
                        },
                      ),
                    ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String filter) {
    final isSelected = _selectedFilter == filter;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedFilter = filter;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blueAccent : Colors.grey[200],
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          filter,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.black,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(String message, IconData icon) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(fontSize: 18, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _buildRequestCard(OwnershipRequest request) {
    final isReceived = request.ownerId == _currentUserId;
    final statusColor =
        request.status == 'accepted'
            ? Colors.green
            : request.status == 'rejected'
            ? Colors.red
            : Colors.orange;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  backgroundColor: const Color(0xFFFFEFEC),
                  radius: 24,
                  child: Icon(
                    isReceived ? Icons.download : Icons.upload,
                    color: Colors.orange,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            isReceived ? 'Request Received' : 'Request Sent',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: statusColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              request.status.toUpperCase(),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: statusColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                      Text(
                        isReceived
                            ? 'from @${request.finderId}'
                            : 'to @${request.ownerId}',
                        style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                      ),
                      if (isReceived && request.status == 'pending')
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            'Please verify within a day !',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: statusColor,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 32),
            Row(
              children: [
                if (request.foundItemDetails['item_img'] != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(
                      request.foundItemDetails['item_img'],
                      width: 65,
                      height: 65,
                      fit: BoxFit.cover,
                    ),
                  )
                else
                  Container(
                    width: 65,
                    height: 65,
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.inventory_2, color: Colors.grey),
                  ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${request.foundItemDetails['item_name']} : ${request.foundItemDetails['post_id']}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      if (request.lostItemDetails != null)
                        Text(
                          'Matched with: ${request.lostItemDetails!['item_name']} : ${request.lostItemDetails!['post_id']}',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                        ),
                    ],
                  ),
                ),
                if (isReceived && request.status == 'pending')
                  Row(
                    children: [
                      _buildCircularActionButton(
                        icon: Icons.check,
                        color: Colors.green,
                        onPressed:
                            () => _respondToRequest(request.id, 'accept'),
                      ),
                      const SizedBox(width: 12),
                      _buildCircularActionButton(
                        icon: Icons.close,
                        color: Colors.red,
                        onPressed:
                            () => _respondToRequest(request.id, 'reject'),
                      ),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCircularActionButton({
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return InkWell(
      onTap: onPressed,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        child: Icon(icon, color: Colors.white, size: 28),
      ),
    );
  }

  Widget _buildNotificationCard(ItemModel item) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder:
                (context) => ItemDetailsScreen(
                  item: item,
                  currentUserId: _currentUserId,
                ),
          ),
        );
      },
      child: Card(
        margin: const EdgeInsets.only(bottom: 16),
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: SizedBox(
          height: 80,
          child: Row(
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  bottomLeft: Radius.circular(12),
                ),
                child: SizedBox(
                  width: 80,
                  height: 80,
                  child:
                      item.itemImg != null
                          ? Image.network(
                            item.itemImg!,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return Container(
                                color: Colors.grey[300],
                                child: const Icon(
                                  Icons.broken_image,
                                  color: Colors.grey,
                                  size: 40,
                                ),
                              );
                            },
                          )
                          : Container(
                            color: Colors.grey[300],
                            child: const Icon(
                              Icons.image,
                              color: Colors.grey,
                              size: 40,
                            ),
                          ),
                ),
              ),

              const SizedBox(width: 12),

              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: 8,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        item.description.toTitleCase(),
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.black87,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),

                      Row(
                        children: [
                          Icon(
                            Icons.access_time,
                            size: 14,
                            color: Colors.grey[600],
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _formatTimeAgo(item.postedTime),
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }
}
