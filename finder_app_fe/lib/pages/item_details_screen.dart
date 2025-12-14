import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'home_screen.dart'; // To access ItemModel
import 'edit_item_screen.dart';

class ItemDetailsScreen extends StatelessWidget {
  final ItemModel item;
  final String? currentUserId;

  const ItemDetailsScreen({super.key, required this.item, this.currentUserId});

  bool get isOwnPost => currentUserId == item.postedBy;

  Color _getColorFromString(String colorName) {
    switch (colorName.toLowerCase()) {
      case 'red':
        return Colors.red;
      case 'green':
        return Colors.green;
      case 'blue':
        return Colors.blue;
      case 'yellow':
        return Colors.yellow;
      case 'black':
        return Colors.black;
      case 'white':
        return Colors.white;
      case 'grey':
        return Colors.grey;
      case 'orange':
        return Colors.orange;
      case 'purple':
        return Colors.purple;
      case 'brown':
        return Colors.brown;
      case 'pink':
        return Colors.pink;
      case 'cyan':
        return Colors.cyan;
      default:
        return Colors.transparent;
    }
  }

  String _formatDate(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      return DateFormat('MMM d, yyyy').format(date);
    } catch (e) {
      return dateStr;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLost = item.status.toLowerCase() == 'lost';
    final statusColor = isLost ? Colors.red : Colors.green;
    final statusBgColor = isLost ? Colors.red[100]! : Colors.green[100]!;
    final statusText = isLost ? 'Lost' : 'Found';

    return Scaffold(
      backgroundColor: Colors.grey[200],
      appBar: AppBar(
        title: const Text(
          'Item Details',
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: Colors.blueAccent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Section
            if (isOwnPost)
              _buildOwnPostHeader(
                context,
                statusText,
                statusColor,
                statusBgColor,
              )
            else
              _buildOtherUserHeader(statusText, statusColor, statusBgColor),

            const SizedBox(height: 16),

            // Item Image
            Container(
              width: double.infinity,
              height:
                  MediaQuery.of(context).size.width -
                  32, // Square minus padding
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
                  item.itemImg != null
                      ? ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(
                          item.itemImg!,
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

            const SizedBox(height: 16),

            // Status Card (Finder/Owner)
            _buildStatusCard(isLost),

            const SizedBox(height: 16),

            // Details Card
            _buildDetailsCard(),

            const SizedBox(height: 24),

            // Contact Button (only for other users)
            if (!isOwnPost)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    // TODO: Implement chat navigation
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Chat functionality coming soon!'),
                      ),
                    );
                  },
                  icon: const Icon(Icons.chat_bubble_outline),
                  label: const Text('Contact'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),

            const SizedBox(height: 20),
          ],
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
        // First row: "Your Post" and status badge
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
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
        // Second row: Edit and Delete buttons
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () async {
                  final result = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => EditItemScreen(item: item),
                    ),
                  );
                  // If edit was successful, go back to home to refresh
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
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final token = await user.getIdToken();
      final endpoint =
          item.status.toLowerCase() == 'found' ? 'found-items' : 'lost-items';

      final response = await http.delete(
        Uri.parse('http://10.0.2.2:8000/api/$endpoint/${item.id}/delete/'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (context.mounted) {
        if (response.statusCode == 204) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Post deleted successfully')),
          );
          Navigator.pop(context); // Go back to home
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to delete post: ${response.statusCode}'),
            ),
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
                  item.profilePicUrl != null
                      ? NetworkImage(item.profilePicUrl!)
                      : null,
              child:
                  item.profilePicUrl == null
                      ? const Icon(Icons.person, color: Colors.white)
                      : null,
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.postedBy, // Assuming postedBy is user_name
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
                Text(
                  '@${item.postedBy}', // Assuming postedBy is also used for @handle for now
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

  Widget _buildStatusCard(bool isLost) {
    if (item.status.toLowerCase() != 'lost' &&
        item.status.toLowerCase() != 'found')
      return const SizedBox.shrink();

    final title = isLost ? 'Finder' : 'Owner';
    final isIdentified = isLost ? item.finderIdentified : item.ownerIdentified;
    final identifiedBy = isLost ? item.finderId : item.ownerId;

    // Identified logic
    final identifiedBgColor =
        isIdentified ? const Color(0xFFEBEAFE) : const Color(0xFFFEE6AA);
    final identifiedTextColor =
        isIdentified ? const Color(0xFF554A8F) : const Color(0xFF9E7230);
    final identifiedText =
        isIdentified
            ? 'Identified'
            : (isLost ? 'Awaiting Finder' : 'Awaiting Owner');

    // Chat logic
    final chatBgColor =
        isIdentified ? Colors.lightBlue[100]! : Colors.grey[200]!;
    final chatTextColor = isIdentified ? Colors.blue : Colors.grey;
    final chatText =
        'Chat'; // User said "Chat is active" or "not active". I'll use text color to imply state.

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
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
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
                Text(
                  isIdentified ? '@$identifiedBy' : 'User Id not available',
                  style: const TextStyle(fontSize: 16, color: Colors.grey),
                ),
                Container(
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
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailsCard() {
    final colorVal = _getColorFromString(item.color);
    final isColorValid = colorVal != Colors.transparent;
    final displayColor = toBeginningOfSentenceCase(item.color) ?? item.color;

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
              Text(
                item.itemName,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                item.description,
                style: const TextStyle(
                  fontSize: 16,
                  height: 1.5,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 16),

              // Category and Color
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.category, size: 20, color: Colors.grey),
                      const SizedBox(width: 8),
                      Text(item.category, style: const TextStyle(fontSize: 16)),
                    ],
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isColorValid)
                        Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            color: colorVal,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.grey),
                          ),
                        )
                      else
                        const Icon(
                          Icons.error_rounded,
                          size: 20,
                          color: Colors.grey,
                        ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          "Color: $displayColor",
                          style: const TextStyle(fontSize: 16),
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // Location and Date
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.location_on_outlined,
                          size: 20,
                          color: Colors.grey,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            item.location,
                            style: const TextStyle(fontSize: 16),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
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
                        _formatDate(item.date),
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
}
