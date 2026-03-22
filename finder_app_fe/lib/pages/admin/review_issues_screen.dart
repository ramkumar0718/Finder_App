import 'package:flutter/material.dart';
import '../../services/api_service.dart';

class ReviewIssueScreen extends StatefulWidget {
  final Map<String, dynamic> issue;
  final Map<String, dynamic>? existingReview;

  const ReviewIssueScreen({
    super.key,
    required this.issue,
    this.existingReview,
  });

  @override
  State<ReviewIssueScreen> createState() => _ReviewIssueScreenState();
}

class _ReviewIssueScreenState extends State<ReviewIssueScreen> {
  final _formKey = GlobalKey<FormState>();
  String _reviewStatus = 'Resolved';
  String? _reviewCategory;
  late final TextEditingController _descriptionController;
  bool _isSubmitting = false;

  final List<String> _statusOptions = ['Resolved', 'Dismissed'];
  final List<String> _categoryOptions = [
    'Action Taken',
    'No Action Required',
    'Warning Sent to User',
    'Post Removed',
    'User Permanently Banned',
  ];

  @override
  void initState() {
    super.initState();
    if (widget.existingReview != null) {
      _reviewStatus = widget.existingReview!['review_status'] ?? 'Resolved';
      _reviewCategory = widget.existingReview!['review_category'];
      _descriptionController = TextEditingController(
        text: widget.existingReview!['description'] ?? '',
      );
    } else {
      _descriptionController = TextEditingController();
    }
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);

    try {
      final response =
          widget.existingReview != null
              ? await ApiService().updateReviewIssue(
                reviewId: widget.existingReview!['review_id'],
                reviewStatus: _reviewStatus,
                reviewCategory: _reviewCategory!,
                description: _descriptionController.text.trim(),
              )
              : await ApiService().submitReview(
                reportId: widget.issue['issue_id'] ?? '',
                postId: widget.issue['post_id'] ?? '',
                reportedUserId: widget.issue['reported_user_id'] ?? '',
                issuerUserId: widget.issue['posted_by'] ?? '',
                reviewStatus: _reviewStatus,
                reviewCategory: _reviewCategory!,
                description: _descriptionController.text.trim(),
              );

      if (mounted) {
        if (response.statusCode == 200 || response.statusCode == 201) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Review submitted successfully!')),
          );
          Navigator.pop(context, true);
        } else {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Error: ${response.body}')));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Widget _buildReadOnlyField(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.black54,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: Text(
              value,
              style: const TextStyle(fontSize: 15, color: Colors.black87),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final issue = widget.issue;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FD),
      appBar: AppBar(
        title: const Text(
          'Review Issue',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.blueAccent,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildReadOnlyField('Post Id', issue['post_id'] ?? '-'),
              _buildReadOnlyField('Report Id', issue['issue_id'] ?? '-'),
              _buildReadOnlyField(
                'Reported User Id',
                issue['reported_user_id'] ?? '-',
              ),
              _buildReadOnlyField('Issuer User Id', issue['posted_by'] ?? '-'),

              const Text(
                'Review Status',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.black54,
                ),
              ),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                initialValue: _reviewStatus,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                ),
                items:
                    _statusOptions
                        .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                        .toList(),
                onChanged: (v) => setState(() => _reviewStatus = v!),
              ),
              const SizedBox(height: 16),

              const Text(
                'Review Category',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.black54,
                ),
              ),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                initialValue: _reviewCategory,
                hint: const Text('Select category'),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                ),
                validator: (v) => v == null ? 'Please select a category' : null,
                items:
                    _categoryOptions
                        .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                        .toList(),
                onChanged: (v) => setState(() => _reviewCategory = v),
              ),
              const SizedBox(height: 16),

              const Text(
                'Description',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.black54,
                ),
              ),
              const SizedBox(height: 6),
              TextFormField(
                controller: _descriptionController,
                maxLines: 5,
                decoration: InputDecoration(
                  hintText: 'Describe the review decision...',
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                ),
                validator:
                    (v) =>
                        (v == null || v.trim().isEmpty)
                            ? 'Description is required'
                            : null,
              ),
              const SizedBox(height: 28),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child:
                      _isSubmitting
                          ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                          : const Text(
                            'Submit',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
