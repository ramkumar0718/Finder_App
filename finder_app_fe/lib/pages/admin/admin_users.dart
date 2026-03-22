import 'package:finder_app_fe/utils/string_extensions.dart';
import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../my_posts_screen.dart';
import 'admin_user_profile.dart';

class AdminUsers extends StatefulWidget {
  const AdminUsers({super.key});

  @override
  State<AdminUsers> createState() => _AdminUsersState();
}

class _AdminUsersState extends State<AdminUsers> {
  final TextEditingController _searchController = TextEditingController();
  String _selectedFilter = 'All';
  List<dynamic> _users = [];
  int _totalCount = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchUsers();
  }

  Future<void> _fetchUsers() async {
    setState(() => _isLoading = true);
    final result = await ApiService().fetchAdminUsers(
      search: _searchController.text,
      filter: _selectedFilter,
    );
    if (!mounted) return;
    setState(() {
      _users = result['users'];
      _totalCount = result['total_count'];
      _isLoading = false;
    });
  }

  void _onSearch(String value) {
    _fetchUsers();
  }

  void _onFilterChanged(String filter) {
    setState(() {
      _selectedFilter = filter;
    });
    _fetchUsers();
  }

  Future<void> _deleteUser(
    String firebaseUid,
    String userId, {
    bool isProxied = false,
  }) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(isProxied ? 'Delete Proxy Account' : 'Delete User'),
            content: Text(
              isProxied
                  ? 'Are you sure you want to delete this proxy account (@$userId)? All historical chat and ownership data associated with it will be permanently removed.'
                  : 'Are you sure you want to delete user @$userId? This action cannot be undone and will remove all their posts.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text(
                  'Delete',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
    );

    if (confirmed == true) {
      final success = await ApiService().deleteAdminUser(firebaseUid);
      if (success) {
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text(
              isProxied
                  ? 'Proxy account deleted successfully'
                  : 'User deleted successfully',
            ),
          ),
        );
        _fetchUsers();
      } else {
        scaffoldMessenger.showSnackBar(
          const SnackBar(content: Text('Failed to delete user')),
        );
      }
    }
  }

  Future<void> _proxyUser(String firebaseUid, String userId) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Proxy User'),
            content: Text(
              'Convert @$userId to a Proxy account? This will anonymize the profile, preserve its chat history/claims, and delete the original account. This action cannot be undone.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text(
                  'Convert to Proxy',
                  style: TextStyle(color: Colors.orange),
                ),
              ),
            ],
          ),
    );

    if (confirmed == true) {
      setState(() => _isLoading = true);
      final success = await ApiService().proxyAdminUser(firebaseUid);
      if (!mounted) return;
      setState(() => _isLoading = false);

      if (success) {
        scaffoldMessenger.showSnackBar(
          const SnackBar(content: Text('User converted to Proxy successfully')),
        );
        _fetchUsers();
      } else {
        scaffoldMessenger.showSnackBar(
          const SnackBar(content: Text('Failed to proxy user')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Users', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.blueAccent,
        elevation: 0,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              onChanged: (value) {
                setState(() {});
              },
              onSubmitted: _onSearch,
              decoration: InputDecoration(
                hintText: 'Search User Id ...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon:
                    _searchController.text.isNotEmpty
                        ? IconButton(
                          icon: const Icon(Icons.clear, color: Colors.grey),
                          onPressed: () {
                            _searchController.clear();
                            _fetchUsers();
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
                  ['All', 'Active', 'Inactive', 'Proxy'].map((filter) {
                    return Padding(
                      padding: const EdgeInsets.only(right: 12.0),
                      child: _buildFilterButton(filter),
                    );
                  }).toList(),
            ),
          ),

          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(
              vertical: 8.0,
              horizontal: 16.0,
            ),
            child: Text(
              'Total Users ($_totalCount)',
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
          ),
          const SizedBox(height: 12),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Row(
              children: const [
                Expanded(
                  flex: 1,
                  child: Text(
                    'User Id',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                      fontSize: 17,
                    ),
                  ),
                ),
                Expanded(
                  flex: 1,
                  child: Text(
                    'Status',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                      fontSize: 17,
                    ),
                  ),
                ),
                Expanded(
                  flex: 1,
                  child: Text(
                    'Post',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                      fontSize: 17,
                    ),
                  ),
                ),
                Expanded(
                  flex: 1,
                  child: Text(
                    'Action',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                      fontSize: 17,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, indent: 20, endIndent: 20),

          Expanded(
            child:
                _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : RefreshIndicator(
                      onRefresh: _fetchUsers,
                      child: ListView.builder(
                        itemCount: _users.length,
                        itemBuilder: (context, index) {
                          final user = _users[index];
                          return _buildUserRow(user);
                        },
                      ),
                    ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserRow(dynamic user) {
    final status = user['status'] ?? 'Inactive';
    final isActive = status == 'Active';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 1,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                const SizedBox(width: 10),
                CircleAvatar(
                  radius: 13,
                  backgroundColor: Colors.blueAccent.withOpacity(0.1),
                  backgroundImage:
                      user['profile_pic_url'] != null &&
                              user['profile_pic_url'].toString().isNotEmpty
                          ? NetworkImage(user['profile_pic_url'])
                          : null,
                  child:
                      user['profile_pic_url'] == null ||
                              user['profile_pic_url'].toString().isEmpty
                          ? const Icon(
                            Icons.person,
                            size: 16,
                            color: Colors.blueAccent,
                          )
                          : null,
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Tooltip(
                    message: user['user_id'] ?? 'No User ID',
                    triggerMode: TooltipTriggerMode.tap,
                    showDuration: const Duration(seconds: 2),
                    decoration: BoxDecoration(
                      color: Colors.blueAccent.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    textStyle: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                    ),
                    child: Text(
                      (user['user_id'] != null
                              ? user['user_id'].toString().toTitleCase()
                              : null) ??
                          (user['name'] != null
                              ? user['name'].toString().toTitleCase()
                              : 'User'),
                      style: const TextStyle(fontWeight: FontWeight.w500),
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
          ),

          Expanded(
            flex: 1,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color:
                      status == 'Proxy'
                          ? Colors.orange.withOpacity(0.1)
                          : isActive
                          ? Colors.green.withOpacity(0.1)
                          : Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.circle,
                      size: 8,
                      color:
                          status == 'Proxy'
                              ? Colors.orange
                              : isActive
                              ? Colors.green
                              : Colors.red,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      status,
                      style: TextStyle(
                        color:
                            status == 'Proxy'
                                ? Colors.orange
                                : isActive
                                ? Colors.green
                                : Colors.red,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          Expanded(
            flex: 1,
            child: Center(
              child: ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder:
                          (context) => MyPostsScreen(
                            userId: user['user_id'] ?? 'unknown',
                          ),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  minimumSize: const Size(0, 32),
                ),
                child: const Text('Open', style: TextStyle(fontSize: 12)),
              ),
            ),
          ),

          Expanded(
            flex: 1,
            child: Center(
              child: PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, color: Colors.grey),
                onSelected: (value) async {
                  if (value == 'profile') {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder:
                            (context) => AdminUserProfileScreen(
                              userId: user['user_id'] ?? '',
                            ),
                      ),
                    );
                    _fetchUsers();
                  } else if (value == 'delete') {
                    _deleteUser(
                      user['firebase_uid'],
                      user['user_id'] ?? 'unknown',
                      isProxied: user['status'] == 'Proxy',
                    );
                  } else if (value == 'proxy') {
                    _proxyUser(
                      user['firebase_uid'],
                      user['user_id'] ?? 'unknown',
                    );
                  }
                },
                itemBuilder:
                    (context) => [
                      const PopupMenuItem(
                        value: 'profile',
                        child: Text('View Profile'),
                      ),
                      if (status != 'Proxy')
                        const PopupMenuItem(
                          value: 'proxy',
                          child: Text(
                            'Proxy',
                            style: TextStyle(color: Colors.orange),
                          ),
                        ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Text(
                          'Delete',
                          style: TextStyle(color: Colors.red),
                        ),
                      ),
                    ],
              ),
            ),
          ),
        ],
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
