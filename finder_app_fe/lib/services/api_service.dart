import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth_lib;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../models/chat_model.dart';

class ApiService {
  // Singleton instance
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  static String get baseDomain =>
      dotenv.env['BASE_DOMAIN'] ?? 'No base url found';
  // static const baseDomain = 'http://10.0.2.2:8000';
  static String get _baseUrl => '$baseDomain/api';
  final fb_auth_lib.FirebaseAuth _auth = fb_auth_lib.FirebaseAuth.instance;

  // --- Helper Methods ---

  Future<String?> _getIdToken() async {
    final user = _auth.currentUser;
    if (user != null) {
      try {
        return await user.getIdToken();
      } on fb_auth_lib.FirebaseAuthException catch (_) {
        return null;
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  Map<String, String> _jsonHeaders({String? token}) {
    final headers = {'Content-Type': 'application/json'};
    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  // --- Auth & User Sync ---

  Future<void> syncGoogleUser(GoogleSignInAccount googleUser) async {
    final user = fb_auth_lib.FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final body = {
      'email': user.email,
      'firebase_uid': user.uid,
      'user_name':
          googleUser.displayName ?? user.email?.split('@')[0] ?? 'User',
      'profile_pic_url': googleUser.photoUrl,
    };

    final response = await http.post(
      Uri.parse('$_baseUrl/auth/google-login/'),
      headers: _jsonHeaders(),
      body: jsonEncode(body),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to sync user data: ${response.body}');
    }
  }

  Future<void> syncAppleUser(
    AuthorizationCredentialAppleID appleCredential,
  ) async {
    final user = fb_auth_lib.FirebaseAuth.instance.currentUser;
    if (user == null) return;

    String userName = 'User';
    if (appleCredential.givenName != null ||
        appleCredential.familyName != null) {
      userName =
          '${appleCredential.givenName ?? ''} ${appleCredential.familyName ?? ''}'
              .trim();
    } else if (user.displayName != null) {
      userName = user.displayName!;
    } else if (user.email != null) {
      userName = user.email!.split('@')[0];
    }

    final body = {
      'email': user.email,
      'firebase_uid': user.uid,
      'user_name': userName,
    };

    final response = await http.post(
      Uri.parse('$_baseUrl/auth/google-login/'), // Using same endpoint
      headers: _jsonHeaders(),
      body: jsonEncode(body),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to sync user data: ${response.body}');
    }
  }

  // --- OTP Methods ---

  Future<Map<String, dynamic>> sendOTP(String email, {String? username}) async {
    final firebaseUid = fb_auth_lib.FirebaseAuth.instance.currentUser?.uid;

    final body = {
      'email': email,
      if (firebaseUid != null) 'firebase_uid': firebaseUid,
      if (username != null && username.isNotEmpty) 'user_name': username,
    };

    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/auth/send-otp/'),
        headers: _jsonHeaders(),
        body: jsonEncode(body),
      );

      if (response.statusCode == 200) {
        return {'success': true};
      } else {
        final errorData = jsonDecode(response.body);
        return {
          'success': false,
          'error': errorData['error'] ?? 'Failed to send OTP',
        };
      }
    } catch (e) {
      return {'success': false, 'error': 'Network error: $e'};
    }
  }

  Future<Map<String, dynamic>> verifyOTP(String email, String otpCode) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/auth/verify-otp/'),
        headers: _jsonHeaders(),
        body: jsonEncode({'email': email, 'otp_code': otpCode}),
      );

      if (response.statusCode == 200) {
        return {'success': true};
      } else {
        final errorData = jsonDecode(response.body);
        return {
          'success': false,
          'error': errorData['error'] ?? 'Verification failed',
        };
      }
    } catch (e) {
      return {'success': false, 'error': 'Network error: $e'};
    }
  }

  Future<Map<String, dynamic>> resendOTP(String email) async {
    final firebaseUid = fb_auth_lib.FirebaseAuth.instance.currentUser?.uid;

    final body = {
      'email': email,
      if (firebaseUid != null) 'firebase_uid': firebaseUid,
    };

    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/auth/resend-otp/'),
        headers: _jsonHeaders(),
        body: jsonEncode(body),
      );

      if (response.statusCode == 200) {
        return {'success': true};
      } else {
        final errorData = jsonDecode(response.body);
        return {
          'success': false,
          'error': errorData['error'] ?? 'Failed to resend OTP',
        };
      }
    } catch (e) {
      return {'success': false, 'error': 'Network error: $e'};
    }
  }

  Future<Map<String, dynamic>> requestEmailChangeOTP(String newEmail) async {
    final token = await _getIdToken();
    if (token == null) return {'success': false, 'error': 'Not authenticated'};

    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/auth/request-email-change-otp/'),
        headers: _jsonHeaders(token: token),
        body: jsonEncode({'new_email': newEmail}),
      );

      if (response.statusCode == 200) {
        return {
          'success': true,
          'message': jsonDecode(response.body)['message'],
        };
      } else {
        final errorData = jsonDecode(response.body);
        return {
          'success': false,
          'error': errorData['error'] ?? 'Failed to request code',
        };
      }
    } catch (e) {
      return {'success': false, 'error': 'Network error: $e'};
    }
  }

  Future<Map<String, dynamic>> verifyEmailChangeOTP(
    String newEmail,
    String otpCode,
  ) async {
    final token = await _getIdToken();
    if (token == null) return {'success': false, 'error': 'Not authenticated'};

    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/auth/verify-email-change-otp/'),
        headers: _jsonHeaders(token: token),
        body: jsonEncode({'new_email': newEmail, 'otp_code': otpCode}),
      );

      if (response.statusCode == 200) {
        return {'success': true};
      } else {
        final errorData = jsonDecode(response.body);
        return {
          'success': false,
          'error': errorData['error'] ?? 'Verification failed',
        };
      }
    } catch (e) {
      return {'success': false, 'error': 'Network error: $e'};
    }
  }

  // --- Profile Methods ---

  Future<Map<String, dynamic>?> fetchUserProfile() async {
    final token = await _getIdToken();
    if (token == null) return null;

    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/profile/'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        // Store role locally for quick access
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('user_role', data['role'] ?? 'user');
        return data;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<String> getUserRole() async {
    final profile = await fetchUserProfile();
    return profile?['role'] ?? 'user';
  }

  Future<String?> getCurrentUserId() async {
    final profile = await fetchUserProfile();
    return profile?['user_id'];
  }

  Future<bool> updateUserProfile(Map<String, dynamic> data) async {
    final token = await _getIdToken();
    if (token == null) return false;

    try {
      final response = await http.put(
        Uri.parse('$_baseUrl/profile/'),
        headers: _jsonHeaders(token: token),
        body: jsonEncode(data),
      );
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  Future<Map<String, dynamic>> uploadProfilePicture(File image) async {
    final token = await _getIdToken();
    if (token == null) return {'success': false, 'error': 'Not authenticated'};

    var request = http.MultipartRequest(
      'POST',
      Uri.parse('$_baseUrl/profile/upload-pic/'),
    );
    request.headers['Authorization'] = 'Bearer $token';

    final mediaType = _getMediaType(image.path);
    request.files.add(
      await http.MultipartFile.fromPath(
        'profile_pic',
        image.path,
        contentType: mediaType,
      ),
    );

    try {
      final response = await request.send();
      final responseBody = await http.Response.fromStream(response);

      if (response.statusCode == 200) {
        final data = jsonDecode(responseBody.body);
        return {'success': true, 'data': data};
      } else {
        return {
          'success': false,
          'error': 'Failed with status ${response.statusCode}',
        };
      }
    } catch (e) {
      return {'success': false, 'error': 'Network error: $e'};
    }
  }

  // --- Item Methods ---

  Future<List<dynamic>> fetchFoundItems() async {
    try {
      final response = await http.get(Uri.parse('$_baseUrl/found-items/'));
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  Future<List<dynamic>> fetchLostItems() async {
    try {
      final response = await http.get(Uri.parse('$_baseUrl/lost-items/'));
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  Future<http.Response> reportItem({
    required bool isLost,
    required Map<String, String> fields,
    required File image,
  }) async {
    final token = await _getIdToken();
    if (token == null) throw Exception('User not authenticated');

    final endpoint = isLost ? 'lost-items' : 'found-items';
    var request = http.MultipartRequest(
      'POST',
      Uri.parse('$_baseUrl/$endpoint/create/'),
    );

    request.headers['Authorization'] = 'Bearer $token';
    request.fields.addAll(fields);

    final mediaType = _getMediaType(image.path);
    request.files.add(
      await http.MultipartFile.fromPath(
        'item_img',
        image.path,
        contentType: mediaType,
      ),
    );

    final streamedResponse = await request.send();
    return await http.Response.fromStream(streamedResponse);
  }

  Future<http.Response> updateItem({
    required bool isLost,
    required String itemId,
    required Map<String, String> fields,
    File? image,
  }) async {
    final token = await _getIdToken();
    if (token == null) throw Exception('User not authenticated');

    final endpoint = isLost ? 'lost-items' : 'found-items';
    var request = http.MultipartRequest(
      'PUT',
      Uri.parse('$_baseUrl/$endpoint/${Uri.encodeComponent(itemId)}/'),
    );

    request.headers['Authorization'] = 'Bearer $token';
    request.fields.addAll(fields);

    if (image != null) {
      final mediaType = _getMediaType(image.path);
      request.files.add(
        await http.MultipartFile.fromPath(
          'item_img',
          image.path,
          contentType: mediaType,
        ),
      );
    }

    final streamedResponse = await request.send();
    return await http.Response.fromStream(streamedResponse);
  }

  // --- Color API ---

  Future<Map<String, String>> fetchColorInfo(String keyword) async {
    try {
      final response = await http.get(
        Uri.parse('https://color.serialif.com/keyword=$keyword'),
      );

      String colorId = 'none';
      String colorName =
          keyword.isNotEmpty
              ? '${keyword[0].toUpperCase()}${keyword.substring(1)}'
              : keyword;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['status'] == 'success') {
          final hexValue = data['base']['hex']['value'] as String;
          // Store as 0XFF... per instructions
          colorId = hexValue.replaceAll('#', '0XFF');
        }
      }
      return {'color_id': colorId, 'color_name': colorName};
    } catch (_) {
      String colorName =
          keyword.isNotEmpty
              ? '${keyword[0].toUpperCase()}${keyword.substring(1)}'
              : keyword;
      return {'color_id': 'none', 'color_name': colorName};
    }
  }

  Future<bool> deleteItem(String id, bool isLost) async {
    final token = await _getIdToken();
    if (token == null) return false;

    final endpoint = isLost ? 'lost-items' : 'found-items';
    try {
      final response = await http.delete(
        Uri.parse('$_baseUrl/$endpoint/${Uri.encodeComponent(id)}/delete/'),
        headers: {'Authorization': 'Bearer $token'},
      );
      return response.statusCode == 204;
    } catch (_) {
      return false;
    }
  }

  // --- Chat Methods ---

  Future<List<Conversation>> fetchConversations() async {
    final token = await _getIdToken();
    if (token == null) return [];

    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/chat/conversations/'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data.map((e) => Conversation.fromJson(e)).toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  Future<Conversation?> createConversation(String targetUserId) async {
    final token = await _getIdToken();
    if (token == null) return null;

    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/chat/conversations/'),
        headers: _jsonHeaders(token: token),
        body: jsonEncode({'target_user_id': targetUserId}),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        return Conversation.fromJson(jsonDecode(response.body));
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<List<Message>> fetchMessages(String conversationId) async {
    final token = await _getIdToken();
    if (token == null) return [];

    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/chat/conversations/$conversationId/messages/'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data.map((e) => Message.fromJson(e)).toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  Future<Message?> sendMessage(
    String conversationId,
    String content, {
    String msgType = 'text',
    File? file,
  }) async {
    final token = await _getIdToken();
    if (token == null) return null;

    try {
      if (file == null) {
        // Text-only message (JSON)
        final response = await http.post(
          Uri.parse('$_baseUrl/chat/conversations/$conversationId/messages/'),
          headers: _jsonHeaders(token: token),
          body: jsonEncode({'content': content, 'msg_type': msgType}),
        );

        if (response.statusCode == 201) {
          return Message.fromJson(jsonDecode(response.body));
        }
      } else {
        // Multipart message (File + Text)
        var request = http.MultipartRequest(
          'POST',
          Uri.parse('$_baseUrl/chat/conversations/$conversationId/messages/'),
        );
        request.headers['Authorization'] = 'Bearer $token';
        request.fields['content'] = content;
        request.fields['msg_type'] = msgType;

        final mediaType = _getMediaType(file.path);
        request.files.add(
          await http.MultipartFile.fromPath(
            'file',
            file.path,
            contentType: mediaType,
          ),
        );

        final streamedResponse = await request.send();
        final response = await http.Response.fromStream(streamedResponse);

        if (response.statusCode == 201) {
          return Message.fromJson(jsonDecode(response.body));
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  // --- Ownership Request Methods ---

  Future<List<dynamic>> fetchUserLostItems(String userId) async {
    final token = await _getIdToken();
    if (token == null) return [];

    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/users/$userId/lost-items/'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  Future<http.Response> sendOwnershipRequest({
    required String foundItemId,
    String? lostItemId,
    required String ownerUserId,
  }) async {
    final token = await _getIdToken();
    if (token == null) throw Exception('User not authenticated');

    final body = {
      'found_item': foundItemId,
      'lost_item': lostItemId,
      'owner': ownerUserId,
    };

    return await http.post(
      Uri.parse('$_baseUrl/ownership-requests/'),
      headers: _jsonHeaders(token: token),
      body: jsonEncode(body),
    );
  }

  Future<http.Response> directAssignOwnership({
    required String foundItemId,
    required String ownerUserId,
    String? lostItemId,
  }) async {
    final token = await _getIdToken();
    if (token == null) throw Exception('User not authenticated');

    final body = {
      'found_item_id': foundItemId,
      'owner_user_id': ownerUserId,
      'lost_item_id': lostItemId,
    };

    return await http.post(
      Uri.parse('$_baseUrl/admin/direct-assign/'),
      headers: _jsonHeaders(token: token),
      body: jsonEncode(body),
    );
  }

  Future<http.Response> adminUnassignOwnership({
    required String postId,
    required String postType,
  }) async {
    final token = await _getIdToken();
    if (token == null) throw Exception('User not authenticated');

    final body = {'post_id': postId, 'post_type': postType};

    return await http.post(
      Uri.parse('$_baseUrl/admin/unassign/'),
      headers: _jsonHeaders(token: token),
      body: jsonEncode(body),
    );
  }

  Future<List<dynamic>> fetchOwnershipRequests() async {
    final token = await _getIdToken();
    if (token == null) return [];

    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/ownership-requests/'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  Future<http.Response> respondToOwnershipRequest({
    required int requestId,
    required String action, // 'accept' or 'reject'
  }) async {
    final token = await _getIdToken();
    if (token == null) throw Exception('User not authenticated');

    return await http.post(
      Uri.parse('$_baseUrl/ownership-requests/$requestId/respond/'),
      headers: _jsonHeaders(token: token),
      body: jsonEncode({'action': action}),
    );
  }

  // --- Admin Methods ---

  Future<Map<String, dynamic>> fetchAdminUsers({
    String? search,
    String? filter,
  }) async {
    final token = await _getIdToken();
    if (token == null) return {'total_count': 0, 'users': []};

    try {
      final queryParams = <String, String>{};
      if (search != null && search.isNotEmpty) queryParams['search'] = search;
      if (filter != null && filter != 'All') queryParams['filter'] = filter;

      final uri = Uri.parse(
        '$_baseUrl/admin/users/',
      ).replace(queryParameters: queryParams);

      final response = await http.get(
        uri,
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return {'total_count': 0, 'users': []};
    } catch (_) {
      return {'total_count': 0, 'users': []};
    }
  }

  Future<bool> deleteAdminUser(String firebaseUid) async {
    final token = await _getIdToken();
    if (token == null) return false;

    try {
      final response = await http.delete(
        Uri.parse('$_baseUrl/admin/users/$firebaseUid/delete/'),
        headers: {'Authorization': 'Bearer $token'},
      );
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>?> fetchAdminUserProfile(String userId) async {
    final token = await _getIdToken();
    if (token == null) return null;

    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/admin/users/$userId/profile/'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> fetchAdminItems({
    String? search,
    String? filter,
  }) async {
    final token = await _getIdToken();
    if (token == null) return {'total_count': 0, 'items': []};

    try {
      final queryParams = <String, String>{};
      if (search != null && search.isNotEmpty) queryParams['search'] = search;
      if (filter != null && filter != 'All') queryParams['filter'] = filter;

      final uri = Uri.parse(
        '$_baseUrl/admin/items/',
      ).replace(queryParameters: queryParams);

      final response = await http.get(
        uri,
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return {'total_count': 0, 'items': []};
    } catch (_) {
      return {'total_count': 0, 'items': []};
    }
  }

  Future<List<dynamic>> fetchAllUsersForAdmin({String? search}) async {
    final token = await _getIdToken();
    if (token == null) return [];

    try {
      final queryParams = <String, String>{};
      if (search != null && search.isNotEmpty) queryParams['search'] = search;

      final uri = Uri.parse(
        '$_baseUrl/admin/all-users/',
      ).replace(queryParameters: queryParams);

      final response = await http.get(
        uri,
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        return List<dynamic>.from(jsonDecode(response.body));
      } else {
        throw Exception(
          'Failed to load users: ${response.statusCode} - ${response.body}',
        );
      }
    } catch (_) {
      rethrow; // Rethrow to let UI handle it
    }
  }

  // --- Helpers ---
  MediaType _getMediaType(String path) {
    final ext = path.split('.').last.toLowerCase();
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return MediaType('image', 'jpeg');
      case 'png':
        return MediaType('image', 'png');
      case 'webp':
        return MediaType('image', 'webp');
      case 'pdf':
        return MediaType('application', 'pdf');
      default:
        // Default fallback
        return MediaType('application', 'octet-stream');
    }
  }

  Future<http.Response> submitReportIssue({
    required String postId,
    required String itemName,
    required String reportedUserId,
    required String issueCategory,
    required String description,
    File? proofDoc1,
    File? proofDoc2,
  }) async {
    final token = await _getIdToken();
    if (token == null) throw Exception('User not authenticated');

    final uri = Uri.parse('$_baseUrl/report-issues/');
    final request =
        http.MultipartRequest('POST', uri)
          ..headers['Authorization'] = 'Bearer $token'
          ..fields['post_id'] = postId
          ..fields['item_name'] = itemName
          ..fields['reported_user_id'] = reportedUserId
          ..fields['issue_category'] = issueCategory
          ..fields['description'] = description;

    if (proofDoc1 != null) {
      request.files.add(
        await http.MultipartFile.fromPath(
          'proof_doc_1',
          proofDoc1.path,
          contentType: _getMediaType(proofDoc1.path),
        ),
      );
    }
    if (proofDoc2 != null) {
      request.files.add(
        await http.MultipartFile.fromPath(
          'proof_doc_2',
          proofDoc2.path,
          contentType: _getMediaType(proofDoc2.path),
        ),
      );
    }

    final streamedResponse = await request.send();
    return http.Response.fromStream(streamedResponse);
  }

  Future<List<dynamic>> fetchIssuesForPost(String postId) async {
    final token = await _getIdToken();
    if (token == null) return [];

    final response = await http.get(
      Uri.parse('$_baseUrl/report-issues/list/?post_id=$postId'),
      headers: _jsonHeaders(token: token),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as List<dynamic>;
    }
    return [];
  }

  Future<List<dynamic>> fetchAdminIssueSummary() async {
    final token = await _getIdToken();
    if (token == null) return [];

    final response = await http.get(
      Uri.parse('$_baseUrl/admin/report-issues/summary/'),
      headers: _jsonHeaders(token: token),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as List<dynamic>;
    }
    return [];
  }

  Future<http.Response> submitReview({
    required String reportId,
    required String postId,
    required String reportedUserId,
    required String issuerUserId,
    required String reviewStatus,
    required String reviewCategory,
    required String description,
  }) async {
    final token = await _getIdToken();
    if (token == null) throw Exception('User not authenticated');

    return await http.post(
      Uri.parse('$_baseUrl/review-issues/'),
      headers: _jsonHeaders(token: token),
      body: jsonEncode({
        'report_id': reportId,
        'post_id': postId,
        'reported_user_id': reportedUserId,
        'issuer_user_id': issuerUserId,
        'review_status': reviewStatus,
        'review_category': reviewCategory,
        'description': description,
      }),
    );
  }

  Future<Map<String, dynamic>?> fetchReviewForIssue(String reportId) async {
    final token = await _getIdToken();
    if (token == null) return null;

    final response = await http.get(
      Uri.parse('$_baseUrl/review-issues/detail/?report_id=$reportId'),
      headers: _jsonHeaders(token: token),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    return null;
  }

  Future<bool> deleteReportIssue(String issueId) async {
    final token = await _getIdToken();
    if (token == null) return false;

    try {
      final response = await http.delete(
        Uri.parse('$_baseUrl/admin/report-issues/delete/?issue_id=$issueId'),
        headers: _jsonHeaders(token: token),
      );
      return response.statusCode == 204;
    } catch (_) {
      return false;
    }
  }

  Future<bool> deleteReviewIssue(String reviewId) async {
    final token = await _getIdToken();
    if (token == null) return false;

    try {
      final response = await http.delete(
        Uri.parse('$_baseUrl/review-issues/update-delete/?review_id=$reviewId'),
        headers: _jsonHeaders(token: token),
      );
      return response.statusCode == 204;
    } catch (_) {
      return false;
    }
  }

  Future<http.Response> updateReviewIssue({
    required String reviewId,
    required String reviewStatus,
    required String reviewCategory,
    required String description,
  }) async {
    final token = await _getIdToken();
    if (token == null) throw Exception('User not authenticated');

    return await http.put(
      Uri.parse('$_baseUrl/review-issues/update-delete/?review_id=$reviewId'),
      headers: _jsonHeaders(token: token),
      body: jsonEncode({
        'review_status': reviewStatus,
        'review_category': reviewCategory,
        'description': description,
      }),
    );
  }

  Future<Map<String, dynamic>> deleteAccount() async {
    final token = await _getIdToken();
    if (token == null) return {'success': false, 'error': 'Not authenticated'};

    try {
      final response = await http.delete(
        Uri.parse('$_baseUrl/delete-account/'),
        headers: _jsonHeaders(token: token),
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        final error = json.decode(response.body);
        return {'success': false, 'error': error['error'] ?? 'Unknown error'};
      }
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  Future<bool> proxyAdminUser(String firebaseUid) async {
    final token = await _getIdToken();
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/admin/users/$firebaseUid/proxy/'),
        headers: _jsonHeaders(token: token),
      );
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>> getAdminAnalytics(String filter) async {
    final token = await _getIdToken();
    if (token == null) throw Exception('User not authenticated');

    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/admin/analytics/?filter=$filter'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      throw Exception('Failed to load analytics: ${response.statusCode}');
    } catch (e) {
      // Error getting admin analytics
      rethrow;
    }
  }

  /// Downloads a remote file to the temp directory and returns the local file path.
  /// Skips the download if the file already exists (simple cache).
  Future<String> downloadFile(String url) async {
    final uri = Uri.parse(url);
    final tempDir = await getTemporaryDirectory();
    final fileName = path.basename(uri.path);
    final filePath = path.join(tempDir.path, fileName);

    final tempFile = File(filePath);
    if (!tempFile.existsSync()) {
      final response = await http.get(uri);
      if (response.statusCode == 200) {
        await tempFile.writeAsBytes(response.bodyBytes);
      } else {
        throw Exception('Failed to download file: ${response.statusCode}');
      }
    }
    return filePath;
  }
}
