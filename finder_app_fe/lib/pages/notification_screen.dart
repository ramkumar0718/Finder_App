import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'home_screen.dart';
import 'item_details_screen.dart';

class NotificationScreen extends StatefulWidget {
  const NotificationScreen({super.key});

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  List<ItemModel> _recentItems = [];
  bool _isLoading = true;
  String? _currentUserId;

  @override
  void initState() {
    super.initState();
    _fetchCurrentUser();
  }

  Future<void> _fetchCurrentUser() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final token = await user.getIdToken();
        final response = await http.get(
          Uri.parse('http://10.0.2.2:8000/api/profile/'),
          headers: {'Authorization': 'Bearer $token'},
        );
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (mounted) {
            setState(() {
              _currentUserId = data['user_id'];
            });
            _fetchRecentItems();
          }
        }
      }
    } catch (e) {
      print('Error fetching user profile: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _fetchRecentItems() async {
    try {
      // Fetch found items
      final foundResponse = await http.get(
        Uri.parse('http://10.0.2.2:8000/api/found-items/'),
      );

      // Fetch lost items
      final lostResponse = await http.get(
        Uri.parse('http://10.0.2.2:8000/api/lost-items/'),
      );

      List<ItemModel> allItems = [];

      if (foundResponse.statusCode == 200) {
        final List<dynamic> foundData = jsonDecode(foundResponse.body);
        allItems.addAll(foundData.map((json) => ItemModel.fromJson(json)));
      }

      if (lostResponse.statusCode == 200) {
        final List<dynamic> lostData = jsonDecode(lostResponse.body);
        allItems.addAll(lostData.map((json) => ItemModel.fromJson(json)));
      }

      // Filter items from past 30 days and exclude own posts
      final now = DateTime.now();
      final thirtyDaysAgo = now.subtract(const Duration(days: 30));

      final filteredItems =
          allItems.where((item) {
            try {
              final postedDate = DateTime.parse(item.postedTime);
              final isRecent = postedDate.isAfter(thirtyDaysAgo);
              final isNotOwnPost = item.ownerId != _currentUserId;
              return isRecent && isNotOwnPost;
            } catch (e) {
              return false;
            }
          }).toList();

      // Sort by posted_time descending (newest first)
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
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error fetching items: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[200],
      appBar: AppBar(
        title: const Text(
          'Notifications',
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: Colors.blueAccent,
        iconTheme: const IconThemeData(color: Colors.white),
        automaticallyImplyLeading: false,
      ),
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _recentItems.isEmpty
              ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.notifications_off,
                      size: 64,
                      color: Colors.grey[400],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No recent posts',
                      style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Posts from the past 30 days will appear here',
                      style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                    ),
                  ],
                ),
              )
              : RefreshIndicator(
                onRefresh: _fetchRecentItems,
                child: ListView.builder(
                  padding: const EdgeInsets.all(16.0),
                  itemCount: _recentItems.length,
                  itemBuilder: (context, index) {
                    return _buildNotificationCard(_recentItems[index]);
                  },
                ),
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
        child: Container(
          height: 80,
          child: Row(
            children: [
              // Left side - Image (fully covered)
              ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  bottomLeft: Radius.circular(12),
                ),
                child: Container(
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

              // Right side - Description and Time
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
                      // Description (2 lines max)
                      Text(
                        item.description,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.black87,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),

                      // Time posted
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
