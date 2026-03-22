import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import 'package:intl/intl.dart';
import '../../utils/string_extensions.dart';

class AdminUserProfileScreen extends StatefulWidget {
  final String userId;
  const AdminUserProfileScreen({super.key, required this.userId});

  @override
  State<AdminUserProfileScreen> createState() => _AdminUserProfileScreenState();
}

class _AdminUserProfileScreenState extends State<AdminUserProfileScreen> {
  Map<String, dynamic> _profileData = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchProfileData();
  }

  Future<void> _fetchProfileData() async {
    setState(() => _isLoading = true);
    try {
      final data = await ApiService().fetchAdminUserProfile(widget.userId);
      if (data != null) {
        setState(() {
          _profileData = data;
        });
      }
    } catch (e) {
      // Error fetching profile data
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text(
          '${widget.userId}\'s Profile',
          style: const TextStyle(color: Colors.white),
        ),
        backgroundColor: Colors.blueAccent,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                onRefresh: _fetchProfileData,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(18.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      _buildProfilePicture(),
                      const SizedBox(height: 12),
                      Text(
                        '@${_profileData['user_id'] ?? widget.userId}',
                        style: const TextStyle(
                          fontSize: 18,
                          color: Colors.grey,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 25),

                      _buildSectionHeader('User Details'),
                      const SizedBox(height: 5),
                      _buildDetailsContainer(),
                    ],
                  ),
                ),
              ),
    );
  }

  Widget _buildProfilePicture() {
    final imageUrl = _profileData['profile_pic_url'];
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.grey, width: 2.5),
      ),
      child: CircleAvatar(
        radius: 60,
        backgroundColor: Colors.blueAccent[100],
        backgroundImage:
            imageUrl != null && imageUrl.isNotEmpty
                ? NetworkImage(imageUrl)
                : null,
        child:
            imageUrl == null || imageUrl.isEmpty
                ? const Icon(Icons.person, size: 60, color: Colors.blueAccent)
                : null,
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: Colors.black87,
        ),
      ),
    );
  }

  Widget _buildDetailsContainer() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          _buildDetailRow(
            icon: Icons.person_outline,
            label: 'Name',
            value: _profileData['name'] ?? 'Not set',
          ),
          const Divider(height: 1),
          _buildDetailRow(
            icon: Icons.email_outlined,
            label: 'Email',
            value: _profileData['email'] ?? 'Not set',
          ),
          const Divider(height: 1),
          _buildDetailRow(
            icon: Icons.calendar_today_outlined,
            label: 'Member Since',
            value: _formatDate(_profileData['joined_date'], dateOnly: true),
          ),
          const Divider(height: 1),
          _buildDetailRow(
            icon: Icons.history,
            label: 'Last Seen',
            value: _formatDate(_profileData['last_opened']),
          ),
          const Divider(height: 1),
          _buildDetailRow(
            icon: Icons.badge_outlined,
            label: 'Role',
            value: _profileData['role']?.toString().toTitleCase() ?? 'User',
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: [
          Icon(icon, color: Colors.blueAccent, size: 22),
          const SizedBox(width: 12),
          Text(
            label,
            style: const TextStyle(
              fontSize: 15,
              color: Colors.black87,
              fontWeight: FontWeight.w500,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 15, color: Colors.black54),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(String? dateStr, {bool dateOnly = false}) {
    if (dateStr == null || dateStr.isEmpty) return 'Never';
    try {
      final date = DateTime.parse(dateStr).toLocal();
      if (dateOnly) {
        return DateFormat('dd:MM:yyyy').format(date);
      }
      return DateFormat('dd:MM:yyyy h:mm a').format(date);
    } catch (e) {
      return dateStr;
    }
  }
}
