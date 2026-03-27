import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../services/api_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final user = FirebaseAuth.instance.currentUser;
  Map<String, dynamic> _profileData = {};
  bool _isLoading = true;
  File? _newProfileImage;
  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _fetchProfileData();
  }

  Future<void> _fetchProfileData({bool isRefresh = false}) async {
    if (!isRefresh) setState(() => _isLoading = true);

    try {
      final data = await ApiService().fetchUserProfile(forceRefresh: isRefresh);

      if (data != null) {
        _profileData = data;
      } else {
        _profileData = {
          'name': user?.displayName ?? 'New User',
          'email': user?.email,
          'user_name': '',
          'user_id': '',
        };
      }
    } catch (e) {
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickImage() async {
    final pickedFile = await _picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      if (mounted) {
        setState(() {
          _newProfileImage = File(pickedFile.path);
        });
      }
      _uploadImage(_newProfileImage!);
    }
  }

  Future<void> _uploadImage(File image) async {
    setState(() => _isLoading = true);

    final result = await ApiService().uploadProfilePicture(image);

    if (result['success']) {
      if (mounted) {
        setState(() {
          _profileData['profile_pic_url'] = result['data']['profile_pic_url'];
          _newProfileImage = null;
        });
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Profile picture updated!')));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error uploading image: ${result['error']}')),
      );
    }

    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text(
          _profileData['role'] == 'admin' ? 'Admin Profile' : 'Profile',
          style: const TextStyle(color: Colors.white),
        ),
        backgroundColor: Colors.blueAccent,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                onRefresh: () async {
                  await _fetchProfileData(isRefresh: true);
                },
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(18.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      if (_profileData['role'] == 'admin') ...[
                        _buildAdminBadge(),
                        const SizedBox(height: 20),
                      ],

                      _buildProfilePicture(),
                      const SizedBox(height: 12),

                      Text(
                        '@${_profileData['user_id'] ?? 'user'}',
                        style: const TextStyle(
                          fontSize: 18,
                          color: Colors.grey,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 15),

                      if (_profileData['role'] != 'admin') ...[
                        _buildMyPostsCard(),
                        const SizedBox(height: 5),
                      ],

                      _buildSectionHeader(
                        'Personal Details',
                        onEditTap: () async {
                          final result = await Navigator.pushNamed(
                            context,
                            '/edit-profile',
                          );
                          if (result == true) {
                            _fetchProfileData(isRefresh: true);
                          }
                        },
                      ),
                      const SizedBox(height: 5),
                      _buildPersonalDetailsContainer(),

                      const SizedBox(height: 12),

                      _buildSectionHeader('Utilities'),

                      const SizedBox(height: 12),
                      _buildUtilitiesContainer(),
                    ],
                  ),
                ),
              ),
    );
  }

  Widget _buildAdminBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.blueAccent,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: Colors.blueAccent.withOpacity(0.35),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Text(
            'Admin',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
          SizedBox(width: 6),
          Icon(Icons.verified, color: Colors.white, size: 18),
        ],
      ),
    );
  }

  Widget _buildProfilePicture() {
    final imageUrl = _profileData['profile_pic_url'];
    final bool hasValidUrl =
        imageUrl != null &&
        imageUrl.isNotEmpty &&
        imageUrl.toString().isNotEmpty &&
        !imageUrl.toString().contains('cdn.example.com');

    return GestureDetector(
      onTap: _pickImage,
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.grey, width: 2.5),
            ),
            child: CircleAvatar(
              radius: 60,
              backgroundColor: Colors.blueAccent[100],
              child:
                  hasValidUrl
                      ? ClipOval(
                        child: Image.network(
                          imageUrl,
                          width: 120,
                          height: 120,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return const Icon(
                              Icons.person,
                              size: 60,
                              color: Colors.blueAccent,
                            );
                          },
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) return child;
                            return const CircularProgressIndicator();
                          },
                        ),
                      )
                      : const Icon(
                        Icons.person,
                        size: 60,
                        color: Colors.blueAccent,
                      ),
            ),
          ),
          Positioned(
            bottom: 0,
            right: 0,
            child: CircleAvatar(
              radius: 18,
              backgroundColor: Colors.blueAccent,
              child: const Icon(
                Icons.camera_alt,
                color: Colors.white,
                size: 18,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, {VoidCallback? onEditTap}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        if (onEditTap != null)
          TextButton.icon(
            onPressed: onEditTap,
            icon: const Icon(Icons.edit, size: 20, color: Colors.blueAccent),
            label: const Text(
              'Edit',
              style: TextStyle(
                color: Colors.blueAccent,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildPersonalDetailsContainer() {
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
            value: _profileData['email'] ?? user?.email ?? 'Not set',
          ),
        ],
      ),
    );
  }

  Widget _buildUtilitiesContainer() {
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
          _buildUtilityRow(
            icon: Icons.settings_outlined,
            label: 'Settings',
            onTap: () {
              Navigator.pushNamed(context, '/settings');
            },
          ),
          const Divider(height: 1),
          _buildUtilityRow(icon: Icons.logout, label: 'Logout', onTap: _logout),
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

  Widget _buildUtilityRow({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            Icon(icon, color: Colors.blueAccent, size: 22),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                fontSize: 15,
                color: Colors.black87,
                fontWeight: FontWeight.w500,
              ),
            ),
            const Spacer(),
            const Icon(Icons.chevron_right, color: Colors.grey, size: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildMyPostsCard() {
    final foundCount = _profileData['found_count'] ?? 0;
    final lostCount = _profileData['lost_count'] ?? 0;

    final totalPosts = foundCount + lostCount;
    final foundPercentage = totalPosts > 0 ? foundCount / totalPosts : 0.0;
    final lostPercentage = totalPosts > 0 ? lostCount / totalPosts : 0.0;

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
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'My Posts',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
                InkWell(
                  onTap: () {
                    Navigator.pushNamed(context, '/my-posts');
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(0),
                    child: const Icon(
                      Icons.arrow_forward_ios,
                      size: 16,
                      color: Colors.grey,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                height: 12,
                child: Row(
                  children: [
                    if (foundPercentage > 0)
                      Expanded(
                        flex: (foundCount * 100).toInt(),
                        child: Container(color: const Color(0xFF239387)),
                      ),

                    if (lostPercentage > 0)
                      Expanded(
                        flex: (lostCount * 100).toInt(),
                        child: Container(color: Colors.black),
                      ),

                    if (totalPosts == 0)
                      Expanded(child: Container(color: Colors.blue[50])),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: const BoxDecoration(
                        color: Color(0xFF239387),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Found items',
                      style: TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                  ],
                ),
                Text(
                  '$foundCount',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
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
                    Container(
                      width: 12,
                      height: 12,
                      decoration: const BoxDecoration(
                        color: Colors.black,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Lost items',
                      style: TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                  ],
                ),
                Text(
                  '$lostCount',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
