import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'home_screen.dart'; // Import for ItemModel
import 'item_details_screen.dart';

class MyPostsScreen extends StatefulWidget {
  const MyPostsScreen({super.key});

  @override
  State<MyPostsScreen> createState() => _MyPostsScreenState();
}

class _MyPostsScreenState extends State<MyPostsScreen> {
  bool _isLoading = true;
  List<ItemModel> _foundItems = [];
  List<ItemModel> _lostItems = [];
  String? _currentUserId;
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _fetchCurrentUserAndPosts();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchCurrentUserAndPosts() async {
    setState(() => _isLoading = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() => _isLoading = false);
        return;
      }

      final token = await user.getIdToken();

      // 1. Fetch User Profile to get user_id
      final profileResponse = await http.get(
        Uri.parse('http://10.0.2.2:8000/api/profile/'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (profileResponse.statusCode == 200) {
        final profileData = jsonDecode(profileResponse.body);
        _currentUserId = profileData['user_id'];
      }

      if (_currentUserId == null) {
        setState(() => _isLoading = false);
        return;
      }

      // 2. Fetch Found Items
      final foundResponse = await http.get(
        Uri.parse('http://10.0.2.2:8000/api/found-items/'),
      );

      // 3. Fetch Lost Items
      final lostResponse = await http.get(
        Uri.parse('http://10.0.2.2:8000/api/lost-items/'),
      );

      if (foundResponse.statusCode == 200) {
        final List<dynamic> foundData = jsonDecode(foundResponse.body);
        _foundItems =
            foundData
                .map((json) => ItemModel.fromJson(json))
                .where(
                  (item) => item.postedBy == _currentUserId,
                ) // Filter by poster
                .toList();

        // Sort found items newest first
        _foundItems.sort((a, b) {
          try {
            return DateTime.parse(
              b.postedTime,
            ).compareTo(DateTime.parse(a.postedTime));
          } catch (e) {
            return 0;
          }
        });
      }

      if (lostResponse.statusCode == 200) {
        final List<dynamic> lostData = jsonDecode(lostResponse.body);
        _lostItems =
            lostData
                .map((json) => ItemModel.fromJson(json))
                .where(
                  (item) => item.postedBy == _currentUserId,
                ) // Filter by poster
                .toList();

        // Sort lost items newest first
        _lostItems.sort((a, b) {
          try {
            return DateTime.parse(
              b.postedTime,
            ).compareTo(DateTime.parse(a.postedTime));
          } catch (e) {
            return 0;
          }
        });
      }

      if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      print('Error fetching my posts: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: Colors.grey[100],
        appBar: AppBar(
          title:
              _isSearching
                  ? TextField(
                    controller: _searchController,
                    autofocus: true,
                    style: const TextStyle(color: Colors.white),
                    cursorColor: Colors.white,
                    decoration: const InputDecoration(
                      hintText: 'Search...',
                      hintStyle: TextStyle(color: Colors.white70),
                      border: InputBorder.none,
                    ),
                    onChanged: (value) {
                      setState(() {
                        _searchQuery = value;
                      });
                    },
                  )
                  : const Text(
                    'My Posts',
                    style: TextStyle(color: Colors.white),
                  ),
          backgroundColor: Colors.blueAccent,
          iconTheme: const IconThemeData(color: Colors.white),
          actions: [
            IconButton(
              icon: Icon(_isSearching ? Icons.close : Icons.search),
              onPressed: () {
                setState(() {
                  if (_isSearching) {
                    _isSearching = false;
                    _searchQuery = '';
                    _searchController.clear();
                  } else {
                    _isSearching = true;
                  }
                });
              },
            ),
          ],
          bottom: const TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
            tabs: [Tab(text: 'Found Items'), Tab(text: 'Lost Items')],
          ),
        ),
        body:
            _isLoading
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                  children: [
                    _buildPostsList(_foundItems, 'No found items posted yet.'),
                    _buildPostsList(_lostItems, 'No lost items posted yet.'),
                  ],
                ),
      ),
    );
  }

  Widget _buildPostsList(List<ItemModel> items, String emptyMessage) {
    final filteredItems =
        items.where((item) {
          final query = _searchQuery.toLowerCase();
          return item.itemName.toLowerCase().contains(query) ||
              item.description.toLowerCase().contains(query);
        }).toList();

    if (filteredItems.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.post_add, size: 60, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              _searchQuery.isNotEmpty
                  ? 'No items found matching "$_searchQuery"'
                  : emptyMessage,
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchCurrentUserAndPosts,
      child: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: 0.82, // Adjust for 3/4 image + text
        ),
        itemCount: filteredItems.length,
        itemBuilder: (context, index) {
          return _MyPostCard(
            item: filteredItems[index],
            currentUserId: _currentUserId,
          );
        },
      ),
    );
  }
}

class _MyPostCard extends StatelessWidget {
  final ItemModel item;
  final String? currentUserId;

  const _MyPostCard({required this.item, this.currentUserId});

  String _formatTimeAgo(String timeStr) {
    try {
      final date = DateTime.parse(timeStr);
      final now = DateTime.now();
      final difference = now.difference(date);

      if (difference.inDays > 0) {
        return '${difference.inDays}d';
      } else if (difference.inHours > 0) {
        return '${difference.inHours}h';
      } else if (difference.inMinutes > 0) {
        return '${difference.inMinutes}m';
      } else {
        return 'now';
      }
    } catch (e) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder:
                (context) =>
                    ItemDetailsScreen(item: item, currentUserId: currentUserId),
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.1),
              spreadRadius: 1,
              blurRadius: 5,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image Section (3/4 of the card)
            Expanded(
              flex: 3,
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(16),
                ),
                child:
                    item.itemImg != null
                        ? Image.network(
                          item.itemImg!,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              color: Colors.grey[200],
                              child: const Icon(
                                Icons.broken_image,
                                color: Colors.grey,
                              ),
                            );
                          },
                        )
                        : Container(
                          color: Colors.grey[200],
                          child: const Icon(
                            Icons.image_not_supported,
                            color: Colors.grey,
                          ),
                        ),
              ),
            ),

            // Details Section (Bottom part)
            Padding(
              padding: const EdgeInsets.all(10.0), // Slightly reduced padding
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Item Name
                  Text(
                    item.itemName,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  // Location and Time
                  Row(
                    children: [
                      const Icon(
                        Icons.location_on_outlined,
                        size: 14,
                        color: Colors.grey,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          item.location,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '• ${_formatTimeAgo(item.postedTime)}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
