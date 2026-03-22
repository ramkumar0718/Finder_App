import 'package:finder_app_fe/utils/string_extensions.dart';
import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../home_screen.dart';
import '../item_details_screen.dart';

class AdminIssues extends StatefulWidget {
  const AdminIssues({super.key});

  @override
  State<AdminIssues> createState() => _AdminIssuesState();
}

class _AdminIssuesState extends State<AdminIssues> {
  List<dynamic> _summaries = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchSummaries();
  }

  Future<void> _fetchSummaries() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final data = await ApiService().fetchAdminIssueSummary();
      if (mounted) {
        setState(() {
          _summaries = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Issues', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.blueAccent,
        elevation: 0,
      ),
      backgroundColor: Colors.grey[50],
      body: RefreshIndicator(
        onRefresh: _fetchSummaries,
        child:
            _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _summaries.isEmpty
                ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: const [
                    SizedBox(height: 200),
                    Center(
                      child: Text(
                        'No reported issues found.',
                        style: TextStyle(fontSize: 16, color: Colors.grey),
                      ),
                    ),
                  ],
                )
                : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _summaries.length,
                  itemBuilder: (context, index) {
                    final item = _summaries[index];
                    return _buildIssueCard(item);
                  },
                ),
      ),
    );
  }

  Widget _buildIssueCard(Map<String, dynamic> data) {
    final String postId = data['post_id'] ?? '';
    final String itemName = data['item_name'] ?? 'Unknown Item';
    final String fromUser = data['reported_user_id'] ?? 'Unknown User';
    final int issueCount = data['issue_count'] ?? 0;
    final String? itemImg = data['item_img'];

    return GestureDetector(
      onTap: () => _navigateToDetails(postId),
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
                      itemImg != null
                          ? Image.network(
                            itemImg,
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
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        itemName.toTitleCase(),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'from @$fromUser',
                        style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  issueCount.toString(),
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.red,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _navigateToDetails(String postId) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final isLost = postId.startsWith('lt_');
      final items =
          isLost
              ? await ApiService().fetchLostItems()
              : await ApiService().fetchFoundItems();

      final fullItemJson = items.firstWhere(
        (i) => i['post_id'] == postId,
        orElse: () => throw Exception('Item not found'),
      );

      if (mounted) {
        Navigator.pop(context);
        final currentUserId = await ApiService().getCurrentUserId();

        await Navigator.push(
          context,
          MaterialPageRoute(
            builder:
                (context) => ItemDetailsScreen(
                  item: ItemModel.fromJson(fullItemJson),
                  currentUserId: currentUserId,
                ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading item details: $e')),
        );
      }
    }
  }
}
