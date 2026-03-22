import 'package:finder_app_fe/utils/string_extensions.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import '../../services/api_service.dart';
import 'review_issues_screen.dart';

class IssueDetailsScreen extends StatefulWidget {
  final Map<String, dynamic> issue;

  const IssueDetailsScreen({super.key, required this.issue});

  @override
  State<IssueDetailsScreen> createState() => _IssueDetailsScreenState();
}

class _IssueDetailsScreenState extends State<IssueDetailsScreen> {
  Map<String, dynamic>? _review;
  bool _isLoadingReview = true;
  late Map<String, dynamic> _issue;
  bool _isAdmin = false;

  @override
  void initState() {
    super.initState();
    _issue = widget.issue;
    _checkAdminRole();
    _fetchReview();
  }

  Future<void> _checkAdminRole() async {
    try {
      final role = await ApiService().getUserRole();
      if (mounted) {
        setState(() {
          _isAdmin = role == 'admin';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isAdmin = false;
        });
      }
    }
  }

  Future<void> _fetchReview() async {
    setState(() => _isLoadingReview = true);
    try {
      final review = await ApiService().fetchReviewForIssue(
        _issue['issue_id'] ?? '',
      );
      if (mounted) {
        setState(() {
          _review = review;
          _isLoadingReview = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingReview = false);
    }
  }

  String _formatDateTime(String? raw) {
    if (raw == null) return '-';
    try {
      final dt = DateTime.parse(raw).toLocal();
      return DateFormat('dd MMM yyyy, hh:mm a').format(dt);
    } catch (_) {
      return raw;
    }
  }

  String _getAbsoluteUrl(String url) {
    if (url.isEmpty) return '';
    if (url.startsWith('http')) return url;
    if (url.startsWith('assets/')) return url;

    final cleanPath = url.startsWith('/') ? url : '/$url';

    final baseUrl = ApiService.baseDomain;
    return '$baseUrl$cleanPath';
  }

  void _showFullscreenImage(String imageUrl) {
    final absoluteUrl = _getAbsoluteUrl(imageUrl);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (context) => Scaffold(
              backgroundColor: Colors.black,
              appBar: AppBar(
                backgroundColor: Colors.black,
                iconTheme: const IconThemeData(color: Colors.white),
                elevation: 0,
              ),
              body: Center(
                child: InteractiveViewer(
                  child: Image.network(
                    absoluteUrl,
                    fit: BoxFit.contain,
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return const Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      );
                    },
                    errorBuilder:
                        (context, error, stackTrace) => const Center(
                          child: Icon(
                            Icons.broken_image,
                            color: Colors.white,
                            size: 50,
                          ),
                        ),
                  ),
                ),
              ),
            ),
      ),
    );
  }

  Future<void> _openFile(String? url) async {
    if (url == null || url.isEmpty) return;

    final lowerUrl = url.toLowerCase();
    if (lowerUrl.endsWith('.jpg') ||
        lowerUrl.endsWith('.jpeg') ||
        lowerUrl.endsWith('.png') ||
        lowerUrl.endsWith('.webp')) {
      _showFullscreenImage(url);
      return;
    }

    try {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Opening file...'),
            duration: Duration(seconds: 2),
          ),
        );
      }

      String filePath;

      if (url.startsWith('http')) {
        filePath = await ApiService().downloadFile(url);
      } else if (url.startsWith('/')) {
        if (url.startsWith('/data/') ||
            url.startsWith('/storage/') ||
            url.startsWith('/var/')) {
          filePath = url;
        } else {
          final absoluteUrl = _getAbsoluteUrl(url);
          return _openFile(absoluteUrl);
        }
      } else {
        throw Exception('Invalid file URL/path');
      }

      final result = await OpenFilex.open(filePath);
      if (result.type != ResultType.done) {
        throw Exception(result.message);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Widget _buildStatusBadge(String text, {Color? bg, Color? textColor}) {
    final isResponded = text == 'Responded' || text == 'Resolved';
    final bgC =
        bg ?? (isResponded ? const Color(0xFFEBEAFE) : const Color(0xFFFEE6AA));
    final fgC =
        textColor ??
        (isResponded ? const Color(0xFF554A8F) : const Color(0xFF9E7230));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bgC,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(color: fgC, fontWeight: FontWeight.bold, fontSize: 12),
      ),
    );
  }

  Widget _buildIdChip(String text, double verticalSize) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: verticalSize),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.blueAccent.withOpacity(0.3)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 13,
          color: Colors.black87,
        ),
      ),
    );
  }

  Widget _buildIdChipWithMenu(String text, VoidCallback onDelete) {
    return PopupMenuButton<String>(
      onSelected: (value) {
        if (value == 'delete') {
          onDelete();
        }
      },
      itemBuilder:
          (context) => [
            const PopupMenuItem(
              value: 'delete',
              child: Row(
                children: [
                  Icon(Icons.delete, color: Colors.red, size: 20),
                  SizedBox(width: 8),
                  Text('Delete', style: TextStyle(color: Colors.red)),
                ],
              ),
            ),
          ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.blueAccent.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              text,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: Colors.black87,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(
              Icons.arrow_forward_ios,
              size: 12,
              color: Colors.black54,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteReportIssue() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Delete Report'),
            content: const Text(
              'Are you sure you want to delete this report? This will also delete any associated reviews.',
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

    if (confirm != true) return;

    final success = await ApiService().deleteReportIssue(_issue['issue_id']);
    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Report deleted successfully.')),
      );
      Navigator.pop(context, true); // Go back to list
    } else if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Failed to delete report.')));
    }
  }

  Widget _buildGreyIdChip(String text, double verticalSize) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: verticalSize),
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 13,
          color: Colors.black87,
        ),
      ),
    );
  }

  Widget _buildGreyIdChipWithMenu(
    String text,
    VoidCallback onEdit,
    VoidCallback onDelete,
  ) {
    return PopupMenuButton<String>(
      onSelected: (value) {
        if (value == 'edit') {
          onEdit();
        } else if (value == 'delete') {
          onDelete();
        }
      },
      itemBuilder:
          (context) => [
            const PopupMenuItem(
              value: 'edit',
              child: Row(
                children: [
                  Icon(Icons.edit, color: Colors.blueAccent, size: 20),
                  SizedBox(width: 8),
                  Text('Edit', style: TextStyle(color: Colors.blueAccent)),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'delete',
              child: Row(
                children: [
                  Icon(Icons.delete, color: Colors.red, size: 20),
                  SizedBox(width: 8),
                  Text('Delete', style: TextStyle(color: Colors.red)),
                ],
              ),
            ),
          ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              text,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: Colors.black87,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(
              Icons.arrow_forward_ios,
              size: 12,
              color: Colors.black54,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editReviewIssue() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder:
            (context) =>
                ReviewIssueScreen(issue: _issue, existingReview: _review),
      ),
    );
    if (result == true) {
      _fetchReview();
    }
  }

  Future<void> _deleteReviewIssue() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Delete Review'),
            content: const Text('Are you sure you want to delete this review?'),
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

    if (confirm != true) return;

    final success = await ApiService().deleteReviewIssue(_review!['review_id']);
    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Review deleted successfully.')),
      );
      setState(() {
        _review = null;
        _issue['issue_status'] = 'Pending';
      });
      _fetchReview();
    } else if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Failed to delete review.')));
    }
  }

  Widget _buildBox1() {
    final issue = _issue;
    final proofDoc1 = issue['proof_doc_1'];
    final proofDoc2 = issue['proof_doc_2'];
    final proofDocs =
        <String?>[
          proofDoc1,
          proofDoc2,
        ].where((d) => d != null && d.toString().isNotEmpty).toList();

    return Container(
      decoration: BoxDecoration(
        color: Colors.blueAccent,
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _isAdmin
                      ? _buildIdChipWithMenu(
                        issue['issue_id'] ?? '-',
                        _deleteReportIssue,
                      )
                      : _buildIdChip(issue['issue_id'] ?? '-', 6),
                  _buildStatusBadge(issue['issue_status'] ?? 'Not Responded'),
                ],
              ),
              const SizedBox(height: 8),
              _buildIdChip('@${issue['posted_by'] ?? '-'}', 2),
            ],
          ),

          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      issue['item_name'].toString().toTitleCase(),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const Text(
                    '  :  ',
                    style: TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                  Expanded(
                    child: Text(
                      issue['post_id'] ?? '-',
                      style: const TextStyle(
                        fontSize: 20,
                        color: Colors.white70,
                      ),
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'by @${issue['reported_user_id'] ?? '-'}',
                style: const TextStyle(fontSize: 14, color: Colors.white70),
              ),
            ],
          ),

          Container(
            width: double.infinity,
            height: 100,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${issue['issue_category'] ?? '-'} :',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  () {
                    final desc = issue['description'] ?? '-';
                    return desc.length > 50
                        ? desc.substring(0, 50) + '...'
                        : desc;
                  }(),
                  style: const TextStyle(color: Colors.black87, fontSize: 13),
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),

          Row(
            children: [
              ...proofDocs.map(
                (url) => GestureDetector(
                  onTap: () => _openFile(url),
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child:
                          (url!.toLowerCase().endsWith('.jpg') ||
                                  url.toLowerCase().endsWith('.jpeg') ||
                                  url.toLowerCase().endsWith('.png') ||
                                  url.toLowerCase().endsWith('.webp'))
                              ? ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: Image.network(
                                  _getAbsoluteUrl(url),
                                  width: 40,
                                  height: 40,
                                  fit: BoxFit.cover,
                                  errorBuilder:
                                      (context, error, stackTrace) =>
                                          const Icon(
                                            Icons.image_not_supported,
                                            size: 20,
                                            color: Colors.blueAccent,
                                          ),
                                ),
                              )
                              : const Icon(
                                Icons.attach_file,
                                color: Colors.blueAccent,
                                size: 20,
                              ),
                    ),
                  ),
                ),
              ),
              const Spacer(),
              Text(
                _formatDateTime(issue['posted_time']),
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBox2() {
    if (_isLoadingReview) {
      return Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_review == null) {
      return Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 24),
        child: Column(
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              color: Colors.blueAccent,
              size: 100,
            ),
            const SizedBox(height: 12),
            const Text(
              'Waiting for review',
              style: TextStyle(fontSize: 22, color: Colors.black54),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed:
                    _isAdmin
                        ? () async {
                          final result = await Navigator.push<bool>(
                            context,
                            MaterialPageRoute(
                              builder:
                                  (context) => ReviewIssueScreen(issue: _issue),
                            ),
                          );
                          if (result == true) _fetchReview();
                        }
                        : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      _isAdmin ? Colors.blueAccent : Colors.grey[400],
                  disabledBackgroundColor: Colors.grey[400],
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Make Response',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final review = _review!;
    final reviewStatus = review['review_status'] ?? 'Resolved';
    final isResolved = reviewStatus == 'Resolved';
    final statusBg =
        isResolved ? const Color(0xFFEBEAFE) : const Color(0xFFFEE6AA);
    final statusFg =
        isResolved ? const Color(0xFF554A8F) : const Color(0xFF9E7230);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _isAdmin
                      ? _buildGreyIdChipWithMenu(
                        review['review_id'] ?? '-',
                        _editReviewIssue,
                        _deleteReviewIssue,
                      )
                      : _buildGreyIdChip(review['review_id'] ?? '-', 6),
                  _buildStatusBadge(
                    reviewStatus,
                    bg: statusBg,
                    textColor: statusFg,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _buildGreyIdChip('@${review['reviewed_by'] ?? '-'}', 2),
            ],
          ),

          Container(
            width: double.infinity,
            height: 120,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${review['review_category'] ?? '-'} :',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  () {
                    final desc = review['description'] ?? '-';
                    return desc.length > 80
                        ? desc.substring(0, 80) + '...'
                        : desc;
                  }(),
                  style: const TextStyle(color: Colors.black87, fontSize: 13),
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          _buildStatusBadge(
            "Based on the submitted proof, the review process has now been concluded.",
          ),

          Align(
            alignment: Alignment.centerRight,
            child: Text(
              _formatDateTime(review['reviewed_time']),
              style: TextStyle(fontSize: 13, color: Colors.grey[500]),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[200],
      appBar: AppBar(
        title: const Text(
          'Issue Details',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.blueAccent,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: RefreshIndicator(
        onRefresh: _fetchReview,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Expanded(flex: 1, child: _buildBox1()),
                    const SizedBox(height: 16),

                    Expanded(flex: 1, child: _buildBox2()),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
