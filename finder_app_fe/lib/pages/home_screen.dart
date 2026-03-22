import 'package:flutter/material.dart';

import 'package:intl/intl.dart';
import '../services/api_service.dart';
import 'main_screen.dart';
import 'item_details_screen.dart';

class ItemModel {
  final String id;
  final String itemName;
  final String? itemImg;
  final String category;
  final String description;
  final String colorId;
  final String colorName;
  final String location;
  final String date;
  final String status;
  final String postedBy;
  final String postedByName;
  final String? postedByRole;
  final String postedTime;
  final String? profilePicUrl;
  final String? ownerId;
  final String? ownerRole;
  final bool ownerIdentified;
  final String? finderId;
  final String? finderRole;
  final bool finderIdentified;

  final String? info;
  final String? matchedPost;
  final bool hasIssue;

  ItemModel({
    required this.id,
    required this.itemName,
    this.itemImg,
    required this.category,
    required this.description,
    required this.colorId,
    required this.colorName,
    required this.location,
    required this.date,
    required this.status,
    required this.postedBy,
    required this.postedByName,
    this.postedByRole,
    required this.postedTime,
    this.profilePicUrl,
    this.ownerId,
    this.ownerRole,
    this.ownerIdentified = false,
    this.finderId,
    this.finderRole,
    this.finderIdentified = false,
    this.info,
    this.matchedPost,
    this.hasIssue = false,
  });

  factory ItemModel.fromJson(Map<String, dynamic> json) {
    return ItemModel(
      id: json['post_id']?.toString() ?? '',
      itemName: json['item_name']?.toString() ?? 'Unknown Item',
      itemImg: json['item_img']?.toString(), // Handle null dynamically
      category: json['category']?.toString() ?? 'Other',
      description: json['description']?.toString() ?? '',
      colorId: json['color_id']?.toString() ?? 'none',
      colorName: json['color_name']?.toString() ?? 'Unknown',
      location: json['location']?.toString() ?? 'Unknown',
      date: json['date']?.toString() ?? '',
      status: json['status']?.toString() ?? 'found',
      postedBy: json['posted_by']?.toString() ?? 'Unknown',
      postedByName: json['posted_by_name']?.toString() ?? 'Unknown',
      postedByRole: json['posted_by_role'],
      postedTime: json['posted_time']?.toString() ?? '',
      profilePicUrl: json['posted_by_profile_pic'],
      ownerId: json['owner_id'],
      ownerRole: json['owner_role'],
      ownerIdentified: json['owner_identified'] ?? false,
      finderId: json['finder_id'],
      finderRole: json['finder_role'],
      finderIdentified: json['finder_identified'] ?? false,
      info: json['info']?.toString(),
      matchedPost: json['matched_post']?.toString(),
      hasIssue: json['has_issue'] ?? false,
    );
  }
}

class FilterCriteria {
  String itemType;
  String userId;
  String category;
  String color;
  String location;
  DateTime? dateFrom;
  DateTime? dateTo;
  String matched;

  FilterCriteria({
    this.itemType = 'All',
    this.userId = '',
    this.category = 'All',
    this.color = '',
    this.location = '',
    this.dateFrom,
    this.dateTo,
    this.matched = 'All',
  });

  bool get isActive =>
      itemType != 'All' ||
      userId.isNotEmpty ||
      category != 'All' ||
      color.isNotEmpty ||
      location.isNotEmpty ||
      dateFrom != null ||
      dateTo != null ||
      matched != 'All';

  void reset() {
    itemType = 'All';
    userId = '';
    category = 'All';
    color = '';
    location = '';
    dateFrom = null;
    dateTo = null;
    matched = 'All';
  }

  FilterCriteria copy() {
    return FilterCriteria(
      itemType: itemType,
      userId: userId,
      category: category,
      color: color,
      location: location,
      dateFrom: dateFrom,
      dateTo: dateTo,
      matched: matched,
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
  final TextEditingController _searchController = TextEditingController();
  String? _currentUserId;

  FilterCriteria _filters = FilterCriteria();

  final List<String> _categories = [
    'All',
    'Electronics',
    'Documents',
    'Luggage',
    'Apparel',
    'Accessories',
    'Pets',
    'Keys',
    'Money',
    'Other',
  ];

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
      final userProfile = await ApiService().fetchUserProfile();
      if (userProfile != null && mounted) {
        setState(() {
          _currentUserId = userProfile['user_id'];
        });
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
      final foundData = await ApiService().fetchFoundItems();
      final lostData = await ApiService().fetchLostItems();

      List<ItemModel> allItems = [];

      allItems.addAll(foundData.map((json) => ItemModel.fromJson(json)));
      allItems.addAll(lostData.map((json) => ItemModel.fromJson(json)));

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
            final matchesSearch =
                query.isEmpty ||
                item.itemName.toLowerCase().contains(query) ||
                item.description.toLowerCase().contains(query);
            if (!matchesSearch) return false;

            if (_filters.itemType != 'All' &&
                item.status.toLowerCase() != _filters.itemType.toLowerCase()) {
              return false;
            }

            if (_filters.userId.isNotEmpty &&
                !item.postedBy.toLowerCase().contains(
                  _filters.userId.toLowerCase(),
                )) {
              return false;
            }

            if (_filters.category != 'All' &&
                item.category != _filters.category) {
              return false;
            }

            if (_filters.color.isNotEmpty &&
                !item.colorName.toLowerCase().contains(
                  _filters.color.toLowerCase(),
                )) {
              return false;
            }

            if (_filters.location.isNotEmpty &&
                !item.location.toLowerCase().contains(
                  _filters.location.toLowerCase(),
                )) {
              return false;
            }

            try {
              final itemDate = DateTime.parse(item.date);
              if (_filters.dateFrom != null &&
                  itemDate.isBefore(_filters.dateFrom!)) {
                return false;
              }
              if (_filters.dateTo != null &&
                  itemDate.isAfter(_filters.dateTo!)) {
                return false;
              }
            } catch (e) {
              // If date parsing fails, keep the item or hide it?
              // Re-check formatting if needed.
            }

            if (_filters.matched == 'Yes' && item.matchedPost == null) {
              return false;
            }
            if (_filters.matched == 'No' && item.matchedPost != null) {
              return false;
            }

            return true;
          }).toList();
    });
  }

  void _showFilterBottomSheet() {
    FilterCriteria tempFilters = _filters.copy();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
                left: 16,
                right: 16,
                top: 16,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Center(
                      child: Text(
                        'Filter Items',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Item Type',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'All', label: Text('All')),
                        ButtonSegment(value: 'Found', label: Text('Found')),
                        ButtonSegment(value: 'Lost', label: Text('Lost')),
                      ],
                      selected: {tempFilters.itemType},
                      onSelectionChanged: (Set<String> newSelection) {
                        setModalState(() {
                          tempFilters.itemType = newSelection.first;
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      decoration: const InputDecoration(
                        labelText: 'User ID',
                        prefixText: '@',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (val) => tempFilters.userId = val,
                      controller: TextEditingController(
                        text: tempFilters.userId,
                      ),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: tempFilters.category,
                      decoration: const InputDecoration(
                        labelText: 'Category',
                        border: OutlineInputBorder(),
                      ),
                      items:
                          _categories.map((cat) {
                            return DropdownMenuItem(
                              value: cat,
                              child: Text(cat),
                            );
                          }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setModalState(() => tempFilters.category = val);
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            decoration: const InputDecoration(
                              labelText: 'Color',
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (val) => tempFilters.color = val,
                            controller: TextEditingController(
                              text: tempFilters.color,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            decoration: const InputDecoration(
                              labelText: 'Location',
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (val) => tempFilters.location = val,
                            controller: TextEditingController(
                              text: tempFilters.location,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Date Range',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate:
                                    tempFilters.dateFrom ?? DateTime.now(),
                                firstDate: DateTime(2000),
                                lastDate: DateTime.now(),
                              );
                              if (picked != null) {
                                setModalState(
                                  () => tempFilters.dateFrom = picked,
                                );
                              }
                            },
                            child: Text(
                              tempFilters.dateFrom == null
                                  ? 'From'
                                  : DateFormat(
                                    'yyyy-MM-dd',
                                  ).format(tempFilters.dateFrom!),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate:
                                    tempFilters.dateTo ?? DateTime.now(),
                                firstDate: DateTime(2000),
                                lastDate: DateTime.now(),
                              );
                              if (picked != null) {
                                setModalState(
                                  () => tempFilters.dateTo = picked,
                                );
                              }
                            },
                            child: Text(
                              tempFilters.dateTo == null
                                  ? 'To'
                                  : DateFormat(
                                    'yyyy-MM-dd',
                                  ).format(tempFilters.dateTo!),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Matched Item',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'All', label: Text('All')),
                        ButtonSegment(value: 'Yes', label: Text('Yes')),
                        ButtonSegment(value: 'No', label: Text('No')),
                      ],
                      selected: {tempFilters.matched},
                      onSelectionChanged: (Set<String> newSelection) {
                        setModalState(() {
                          tempFilters.matched = newSelection.first;
                        });
                      },
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              setModalState(() {
                                tempFilters.reset();
                              });
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.grey[300],
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(30),
                              ),
                            ),
                            child: const Text('Reset All'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              setState(() {
                                _filters = tempFilters;
                              });
                              _filterItems();
                              Navigator.pop(context);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blueAccent,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(30),
                              ),
                            ),
                            child: const Text('Apply Filters'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
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
      backgroundColor: Colors.grey[50],
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
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 8.0,
            ),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search items...',
                prefixIcon: const Icon(Icons.search, color: Colors.grey),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_searchController.text.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {});
                        },
                      ),
                    IconButton(
                      icon: Icon(
                        _filters.isActive
                            ? Icons.filter_list
                            : Icons.filter_list_outlined,
                        color:
                            _filters.isActive ? Colors.blueAccent : Colors.grey,
                      ),
                      onPressed: _showFilterBottomSheet,
                    ),
                  ],
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30.0),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Colors.grey[200],
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
              ),
              onChanged: (value) {
                setState(() {});
              },
            ),
          ),

          if (_filters.isActive)
            Padding(
              padding: const EdgeInsets.only(right: 16.0, bottom: 8.0),
              child: Align(
                alignment: Alignment.centerRight,
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _filters.reset();
                    });
                    _filterItems();
                  },
                  child: const Text(
                    'Clear Filters',
                    style: TextStyle(
                      color: Colors.blueAccent,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 8),
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
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      _truncateText(
                        item.itemName.isNotEmpty
                            ? '${item.itemName[0].toUpperCase()}${item.itemName.substring(1)}'
                            : item.itemName,
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
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
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
