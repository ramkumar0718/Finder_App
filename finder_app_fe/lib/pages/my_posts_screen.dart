import 'package:finder_app_fe/utils/string_extensions.dart';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'home_screen.dart';
import 'item_details_screen.dart';

class MyPostsScreen extends StatefulWidget {
  final String? userId;
  const MyPostsScreen({super.key, this.userId});

  @override
  State<MyPostsScreen> createState() => _MyPostsScreenState();
}

class _MyPostsScreenState extends State<MyPostsScreen> {
  bool _isLoading = true;
  List<ItemModel> _foundItems = [];
  List<ItemModel> _lostItems = [];
  String? _currentUserId;
  final TextEditingController _searchController = TextEditingController();
  String _selectedFilter = 'All';

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
      if (widget.userId != null) {
        _currentUserId = widget.userId;
      } else {
        final profileData = await ApiService().fetchUserProfile();
        if (profileData == null) {
          setState(() => _isLoading = false);
          return;
        }
        _currentUserId = profileData['user_id'];
      }

      final foundData = await ApiService().fetchFoundItems();
      final lostData = await ApiService().fetchLostItems();

      _foundItems =
          foundData
              .map((json) => ItemModel.fromJson(json))
              .where((item) => item.postedBy == _currentUserId)
              .toList();

      _lostItems =
          lostData
              .map((json) => ItemModel.fromJson(json))
              .where((item) => item.postedBy == _currentUserId)
              .toList();

      if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text(
          widget.userId != null
              ? '${widget.userId?.toTitleCase()}\'s Posts'
              : 'My Posts',
          style: const TextStyle(color: Colors.white),
        ),
        backgroundColor: Colors.blueAccent,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: TextField(
                      controller: _searchController,
                      onChanged: (value) => setState(() {}),
                      decoration: InputDecoration(
                        hintText: 'Search my posts...',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon:
                            _searchController.text.isNotEmpty
                                ? IconButton(
                                  icon: const Icon(
                                    Icons.clear,
                                    color: Colors.white,
                                  ),
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() {});
                                  },
                                )
                                : null,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30.0),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: Colors.grey[200],
                        contentPadding: const EdgeInsets.symmetric(vertical: 0),
                      ),
                    ),
                  ),

                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Row(
                      children:
                          ['All', 'Found', 'Lost', 'Issue'].map((filter) {
                            return Padding(
                              padding: const EdgeInsets.only(right: 12.0),
                              child: _buildFilterButton(filter),
                            );
                          }).toList(),
                    ),
                  ),

                  const SizedBox(height: 16),

                  Expanded(child: _buildFilteredList()),
                ],
              ),
    );
  }

  Widget _buildFilterButton(String filter) {
    final isSelected = _selectedFilter == filter;
    return GestureDetector(
      onTap: () => setState(() => _selectedFilter = filter),
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

  Widget _buildFilteredList() {
    List<ItemModel> allItems = [..._foundItems, ..._lostItems];

    allItems.sort((a, b) {
      try {
        return DateTime.parse(
          b.postedTime,
        ).compareTo(DateTime.parse(a.postedTime));
      } catch (e) {
        return 0;
      }
    });

    final query = _searchController.text.toLowerCase();
    final items =
        allItems.where((item) {
          final matchesSearch =
              item.itemName.toLowerCase().contains(query) ||
              item.description.toLowerCase().contains(query);

          bool matchesFilter = true;
          if (_selectedFilter == 'Found') {
            matchesFilter = item.status.toLowerCase() == 'found';
          } else if (_selectedFilter == 'Lost') {
            matchesFilter = item.status.toLowerCase() == 'lost';
          } else if (_selectedFilter == 'Issue') {
            matchesFilter = item.hasIssue;
          }

          return matchesSearch && matchesFilter;
        }).toList();

    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.post_add, size: 60, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              _searchController.text.isNotEmpty
                  ? 'No items found matching "${_searchController.text}"'
                  : 'No posts found.',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchCurrentUserAndPosts,
      child: GridView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.05,
        ),
        itemCount: items.length,
        itemBuilder: (context, index) {
          return _MyPostCard(item: items[index], currentUserId: _currentUserId);
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
    final status = item.status.toLowerCase();
    final isLost = status == 'lost';
    final statusColor = isLost ? Colors.red : Colors.green;
    final statusText = isLost ? 'Lost' : 'Found';

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
      child: Card(
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 2,
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(12),
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

            // Item Details
            Padding(
              padding: const EdgeInsets.fromLTRB(8.0, 8.0, 8.0, 6.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.itemName.toTitleCase(),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            const Icon(
                              Icons.calendar_today,
                              size: 12,
                              color: Colors.grey,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                _formatTimeAgo(item.postedTime),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey[600],
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),

                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: statusColor, width: 1.5),
                        ),
                        child: Text(
                          statusText,
                          style: TextStyle(
                            color: statusColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
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
