import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';
import 'main_screen.dart';
import 'item_details_screen.dart';

class ItemModel {
  final String id;
  final String itemName;
  final String? itemImg;
  final String category;
  final String description;
  final String color;
  final String location;
  final String date;
  final String status;
  final String postedBy;
  final String postedTime;
  final String? profilePicUrl;
  final String? ownerId;
  final bool ownerIdentified;
  final String? finderId;
  final bool finderIdentified;

  ItemModel({
    required this.id,
    required this.itemName,
    this.itemImg,
    required this.category,
    required this.description,
    required this.color,
    required this.location,
    required this.date,
    required this.status,
    required this.postedBy,
    required this.postedTime,
    this.profilePicUrl,
    this.ownerId,
    this.ownerIdentified = false,
    this.finderId,
    this.finderIdentified = false,
  });

  factory ItemModel.fromJson(Map<String, dynamic> json) {
    return ItemModel(
      id: json['post_id'] ?? '',
      itemName: json['item_name'] ?? 'Unknown Item',
      itemImg: json['item_img'],
      category: json['category'] ?? 'Other',
      description: json['description'] ?? '',
      color: json['color'] ?? 'Unknown',
      location: json['location'] ?? 'Unknown',
      date: json['date'] ?? '',
      status: json['status'] ?? 'found',
      postedBy: json['posted_by'] ?? 'Unknown',
      postedTime: json['posted_time'] ?? '',
      profilePicUrl: json['posted_by_profile_pic'],
      ownerId: json['owner_id'],
      ownerIdentified: json['owner_identified'] ?? false,
      finderId: json['finder_id'],
      finderIdentified: json['finder_identified'] ?? false,
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  static final GlobalKey<_HomeScreenState> homeKey =
      GlobalKey<_HomeScreenState>();

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<ItemModel> _items = [];
  List<ItemModel> _filteredItems = [];
  bool _isLoading = true;
  String _selectedFilter = 'All';
  final TextEditingController _searchController = TextEditingController();
  String? _currentUserId;

  // Public method to show report options
  void showReportOptions() {
    _showReportOptions(context);
  }

  @override
  void initState() {
    super.initState();
    _fetchCurrentUser();
    _fetchItems();
    _searchController.addListener(_filterItems);
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
          }
        }
      }
    } catch (e) {
      print('Error fetching user profile: $e');
    }
  }

  @override
  void dispose() {
    _searchController.removeListener(_filterItems);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchItems() async {
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

      // Sort by posted_time descending (newest first)
      allItems.sort((a, b) {
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
          _items = allItems;
          _isLoading = false;
        });
        _filterItems();
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

  void _filterItems() {
    if (!mounted) return;
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredItems =
          _items.where((item) {
            final matchesFilter =
                _selectedFilter == 'All' ||
                item.status.toLowerCase() == _selectedFilter.toLowerCase();
            final matchesSearch =
                item.itemName.toLowerCase().contains(query) ||
                item.description.toLowerCase().contains(query);
            return matchesFilter && matchesSearch;
          }).toList();
    });
  }

  void _onFilterChanged(String filter) {
    if (!mounted) return;
    setState(() {
      _selectedFilter = filter;
    });
    _filterItems();
  }

  void _showReportOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Report an Item',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              ListTile(
                leading: const Icon(Icons.check_circle, color: Colors.green),
                title: const Text('Found Item'),
                subtitle: const Text('I found something'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.pushNamed(context, '/report-found').then((_) {
                    _fetchItems();
                  });
                },
              ),
              ListTile(
                leading: const Icon(Icons.help, color: Colors.red),
                title: const Text('Lost Item'),
                subtitle: const Text('I lost something'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.pushNamed(context, '/report-lost').then((_) {
                    _fetchItems();
                  });
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Finder'),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_none),
            onPressed: () {
              MainScreen.navigatorKey.currentState?.navigateToTab(1);
            },
          ),
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: GestureDetector(
              onTap: () {
                Navigator.pushNamed(context, '/profile');
              },
              child: const CircleAvatar(
                radius: 16,
                backgroundColor: Colors.white,
                child: Icon(Icons.person, color: Colors.blueAccent, size: 20),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 8.0,
            ),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search items...',
                prefixIcon: const Icon(Icons.search),
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
          const SizedBox(height: 8),

          // Filter Buttons
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              children: [
                _buildFilterButton('All'),
                const SizedBox(width: 12),
                _buildFilterButton('Found'),
                const SizedBox(width: 12),
                _buildFilterButton('Lost'),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // List
          Expanded(
            child:
                _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : RefreshIndicator(
                      onRefresh: _fetchItems,
                      child:
                          _filteredItems.isEmpty
                              ? const Center(child: Text('No items found.'))
                              : ListView.builder(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                ),
                                itemCount: _filteredItems.length,
                                itemBuilder: (context, index) {
                                  return ItemCard(
                                    item: _filteredItems[index],
                                    currentUserId: _currentUserId,
                                  );
                                },
                              ),
                    ),
          ),
        ],
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 5.0),
        child: FloatingActionButton(
          onPressed: () {
            _showReportOptions(context);
          },
          backgroundColor: Colors.blueAccent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(50),
          ),
          child: const Icon(Icons.add, color: Colors.white),
        ),
      ),
    );
  }

  Widget _buildFilterButton(String filter) {
    final isSelected = _selectedFilter == filter;
    return GestureDetector(
      onTap: () => _onFilterChanged(filter),
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
}

class ItemCard extends StatelessWidget {
  final ItemModel item;
  final String? currentUserId;

  const ItemCard({super.key, required this.item, this.currentUserId});

  String _formatDate(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      return DateFormat('MMM d, yyyy').format(date);
    } catch (e) {
      return dateStr;
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

  String _truncateText(String text, int maxLength) {
    if (text.length <= maxLength) return text;
    return '${text.substring(0, maxLength)}...';
  }

  @override
  Widget build(BuildContext context) {
    final isLost = item.status.toLowerCase() == 'lost';
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
        margin: const EdgeInsets.only(bottom: 16),
        elevation: 5,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12.0, 12.0, 12.0, 7.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: Item Name and User Info
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      _truncateText(
                        toBeginningOfSentenceCase(item.itemName) ??
                            item.itemName,
                        15,
                      ),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 12,
                        backgroundColor: Colors.grey[300],
                        backgroundImage:
                            item.profilePicUrl != null
                                ? NetworkImage(item.profilePicUrl!)
                                : null,
                        child:
                            item.profilePicUrl == null
                                ? const Icon(
                                  Icons.person,
                                  size: 16,
                                  color: Colors.white,
                                )
                                : null,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '@${item.postedBy}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 5),

              // Content: Image and Description with Location/Date
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Item Image
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 100,
                      height: 70,
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
                  const SizedBox(width: 12),
                  // Description, Location, and Date
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Description
                        Text(
                          item.description,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[800],
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 8),
                        // Location and Date in single line
                        Row(
                          children: [
                            Icon(
                              Icons.location_on_outlined,
                              size: 14,
                              color: Colors.blueAccent,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                _truncateText(item.location, 20),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey[600],
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Icon(
                              Icons.calendar_today,
                              size: 14,
                              color: Colors.blueAccent,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _formatDate(item.date),
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 1),

              // Footer: Posted Time and Status Badge
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _formatTimeAgo(item.postedTime),
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: statusColor, width: 1),
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
      ),
    );
  }
}
