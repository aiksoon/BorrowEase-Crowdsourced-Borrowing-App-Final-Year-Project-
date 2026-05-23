import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String defaultBaseUrl = 'https://borrowease-crowdsourced-borrowing-app.onrender.com';
const String _tokenKey = 'auth_token';
const String _userKey = 'auth_user';

/// Simple token store backed by SharedPreferences.
class TokenStore {
  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  Future<void> setToken(String? token) async {
    final prefs = await SharedPreferences.getInstance();
    if (token == null || token.isEmpty) {
      await prefs.remove(_tokenKey);
    } else {
      await prefs.setString(_tokenKey, token);
    }
  }

  Future<Map<String, dynamic>?> getUser() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_userKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded;
    } catch (_) {
      await prefs.remove(_userKey);
      return null;
    }
  }

  Future<void> setUser(Map<String, dynamic>? user) async {
    final prefs = await SharedPreferences.getInstance();
    if (user == null) {
      await prefs.remove(_userKey);
    } else {
      await prefs.setString(_userKey, jsonEncode(user));
    }
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userKey);
  }
}

/// Thin API client for the backend (auth, items, requests).
class ApiClient {
  ApiClient({Dio? dio, TokenStore? tokenStore, String baseUrl = defaultBaseUrl})
    : _tokenStore = tokenStore ?? TokenStore(),
      _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: baseUrl,
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 10),
            ),
          ) {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await _tokenStore.getToken();
          if (token != null && token.isNotEmpty) {
            options.headers.putIfAbsent('Authorization', () => 'Bearer $token');
          }
          options.headers.putIfAbsent('Content-Type', () => 'application/json');
          return handler.next(options);
        },
      ),
    );
  }

  final Dio _dio;
  final TokenStore _tokenStore;

  Future<void> signOut() => _tokenStore.clear();

  Future<Map<String, dynamic>?> getStoredUser() => _tokenStore.getUser();

  Future<Map<String, dynamic>> getMe() async {
    final response = await _dio.get<Map<String, dynamic>>('/auth/me');
    final data = response.data ?? <String, dynamic>{};
    final user = data['user'] as Map<String, dynamic>?;
    if (user != null) {
      await _tokenStore.setUser(user);
    }
    return data;
  }

  Future<Map<String, dynamic>> register({
    required String email,
    required String password,
    required String name,
    String? location,
    String? phone,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/auth/register',
      data: {
        'email': email,
        'password': password,
        'name': name,
        if (location != null) 'location': location,
        if (phone != null) 'phone': phone,
      },
    );
    final data = response.data ?? <String, dynamic>{};
    final token = data['token'] as String?;
    Map<String, dynamic>? user = data['user'] as Map<String, dynamic>?;
    if (user != null && location != null && (user['location'] == null)) {
      user = Map<String, dynamic>.from(user)..['location'] = location;
    }
    if (token != null) await _tokenStore.setToken(token);
    if (user != null) await _tokenStore.setUser(user);
    return data;
  }

  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/auth/login',
      data: {'email': email, 'password': password},
    );
    final data = response.data ?? <String, dynamic>{};
    final token = data['token'] as String?;
    Map<String, dynamic>? user = data['user'] as Map<String, dynamic>?;
    final existingUser = await _tokenStore.getUser();
    if (user != null &&
        (user['location'] == null ||
            (user['location'] as String?)?.isEmpty == true) &&
        existingUser != null &&
        (existingUser['location'] as String?)?.isNotEmpty == true) {
      user = Map<String, dynamic>.from(user)
        ..['location'] = existingUser['location'];
    }
    if (token != null) await _tokenStore.setToken(token);
    if (user != null) await _tokenStore.setUser(user);
    return data;
  }

  // ---------------- Users ----------------

  Future<Map<String, dynamic>> updateMe({
    String? phone,
    String? location,
    String? avatarUrl,
    String? payoutBankName,
    String? payoutAccountHolder,
    String? payoutAccountNumber,
  }) async {
    final payload = <String, dynamic>{
      if (phone != null) 'phone': phone,
      if (location != null) 'location': location,
      if (avatarUrl != null) 'avatar_url': avatarUrl,
      if (payoutBankName != null) 'payout_bank_name': payoutBankName,
      if (payoutAccountHolder != null)
        'payout_account_holder': payoutAccountHolder,
      if (payoutAccountNumber != null)
        'payout_account_number': payoutAccountNumber,
    };
    final response = await _dio.patch<Map<String, dynamic>>(
      '/auth/me',
      data: payload,
    );
    final data = response.data ?? <String, dynamic>{};
    final user = data['user'] as Map<String, dynamic>?;
    if (user != null) {
      await _tokenStore.setUser(user);
    }
    return data;
  }

  Future<Map<String, dynamic>> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/auth/change-password',
      data: {'current_password': currentPassword, 'new_password': newPassword},
    );
    return response.data ?? <String, dynamic>{};
  }

  Future<Map<String, dynamic>> getUserProfile(int userId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/users/$userId/profile',
    );
    return response.data ?? <String, dynamic>{};
  }

  Future<List<dynamic>> getSystemNotifications({int limit = 80}) async {
    final response = await _dio.get<List<dynamic>>(
      '/users/me/system-notifications',
      queryParameters: {'limit': limit},
    );
    return response.data ?? <dynamic>[];
  }

  Future<void> requestPasswordReset({required String email}) async {
    await _dio.post('/auth/forgot', data: {'email': email});
  }

  Future<void> resetPassword({
    required String email,
    required String otp,
    required String newPassword,
  }) async {
    await _dio.post(
      '/auth/reset-password',
      data: {'email': email, 'otp': otp, 'new_password': newPassword},
    );
  }

  // ---------------- Items ----------------

  Future<List<dynamic>> getItems({
    String? query,
    String? category,
    int? ownerId,
    bool availableOnly = false,
    int limit = 50,
    int offset = 0,
  }) async {
    final response = await _dio.get<List<dynamic>>(
      '/items',
      queryParameters: {
        if (query != null && query.isNotEmpty) 'q': query,
        if (category != null) 'category': category,
        if (ownerId != null) 'owner_id': ownerId,
        'available_only': availableOnly ? 'true' : 'false',
        'limit': limit,
        'offset': offset,
      },
    );
    return response.data ?? <dynamic>[];
  }

  Future<Map<String, dynamic>> getItemDetail(int id) async {
    final response = await _dio.get<Map<String, dynamic>>('/items/$id');
    return response.data ?? <String, dynamic>{};
  }

  Future<int> createItem({
    required String title,
    required num pricePerDay,
    required String imageUrl,
    String? videoUrl,
    num? depositAmount,
    String? locationText,
    String? category,
    String? description,
    num? latitude,
    num? longitude,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/items',
      data: {
        'title': title,
        'price_per_day': pricePerDay,
        'image_url': imageUrl,
        if (videoUrl != null) 'video_url': videoUrl,
        if (depositAmount != null) 'deposit_amount': depositAmount,
        if (locationText != null) 'location_text': locationText,
        if (category != null) 'category': category,
        if (description != null) 'description': description,
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
      },
    );
    return _extractId(response.data);
  }

  Future<Map<String, dynamic>> updateItem({
    required int id,
    String? title,
    num? pricePerDay,
    num? depositAmount,
    String? locationText,
    String? category,
    String? description,
    String? imageUrl,
    String? videoUrl,
    num? latitude,
    num? longitude,
    String? availability,
  }) async {
    final response = await _dio.patch<Map<String, dynamic>>(
      '/items/$id',
      data: {
        if (title != null) 'title': title,
        if (pricePerDay != null) 'price_per_day': pricePerDay,
        if (depositAmount != null) 'deposit_amount': depositAmount,
        if (locationText != null) 'location_text': locationText,
        if (category != null) 'category': category,
        if (description != null) 'description': description,
        if (imageUrl != null) 'image_url': imageUrl,
        if (videoUrl != null) 'video_url': videoUrl,
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
        if (availability != null) 'availability': availability,
      },
    );
    return response.data ?? <String, dynamic>{};
  }

  Future<void> deleteItem(int id) async {
    await _dio.delete('/items/$id');
  }

  // ---------------- Community Posts ----------------

  Future<List<dynamic>> getCommunityPosts({bool nearby = false}) async {
    final response = await _dio.get<List<dynamic>>(
      '/community/posts',
      queryParameters: nearby ? {'nearby': 'true'} : null,
    );
    return response.data ?? <dynamic>[];
  }

  Future<int> createCommunityPost({
    required String content,
    String? imageUrl,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/community/posts',
      data: {'content': content, if (imageUrl != null) 'image_url': imageUrl},
    );
    return _extractId(response.data);
  }

  Future<Map<String, dynamic>> updateCommunityPost({
    required int postId,
    required String content,
    String? imageUrl,
  }) async {
    final response = await _dio.patch<Map<String, dynamic>>(
      '/community/posts/$postId',
      data: {'content': content, if (imageUrl != null) 'image_url': imageUrl},
    );
    return response.data ?? <String, dynamic>{};
  }

  Future<void> deleteCommunityPost(int postId) async {
    await _dio.delete('/community/posts/$postId');
  }

  // ---------------- Requests ----------------

  Future<int> createRequest({
    required int itemId,
    required String startDate,
    required String endDate,
    String? message,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/requests',
      data: {
        'item_id': itemId,
        'start_date': startDate,
        'end_date': endDate,
        if (message != null) 'message': message,
      },
    );
    return _extractId(response.data);
  }

  Future<List<dynamic>> getRequests({String? role}) async {
    final response = await _dio.get<List<dynamic>>(
      '/requests',
      queryParameters: role != null ? {'role': role} : null,
    );
    return response.data ?? <dynamic>[];
  }

  Future<List<Map<String, dynamic>>> getBlockedDatesForItem(int itemId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/requests/item/$itemId/blocked-dates',
    );
    final ranges = response.data?['ranges'] as List<dynamic>?;
    return ranges
            ?.whereType<Map<String, dynamic>>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList() ??
        <Map<String, dynamic>>[];
  }

  Future<Map<String, dynamic>> updateRequestStatus({
    required int requestId,
    required String nextStatus,
  }) async {
    final response = await _dio.patch<Map<String, dynamic>>(
      '/requests/$requestId/status',
      data: {'next_status': nextStatus},
    );
    return response.data ?? <String, dynamic>{};
  }

  // ---------------- Transactions (simulated) ----------------

  Future<Map<String, dynamic>> getTransaction(int requestId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/transactions/$requestId',
    );
    return response.data ?? <String, dynamic>{};
  }

  Future<Map<String, dynamic>> payTransaction(int requestId) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/transactions/$requestId/pay',
    );
    return response.data ?? <String, dynamic>{};
  }

  Future<Map<String, dynamic>> refundTransaction(int requestId) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/transactions/$requestId/refund',
    );
    return response.data ?? <String, dynamic>{};
  }

  // ---------------- Chats (REST polling) ----------------

  Future<Map<String, dynamic>> createChat(int requestId) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/chats',
      data: {'request_id': requestId},
    );
    return response.data ?? <String, dynamic>{};
  }

  Future<Map<String, dynamic>> getChatByRequest(int requestId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/chats',
      queryParameters: {'request_id': requestId},
    );
    return response.data ?? <String, dynamic>{};
  }

  Future<List<dynamic>> getChats() async {
    final response = await _dio.get<List<dynamic>>(
      '/chats',
      queryParameters: {'_ts': DateTime.now().millisecondsSinceEpoch},
    );
    return response.data ?? <dynamic>[];
  }

  Future<Map<String, dynamic>> getOrCreateDirectChat({
    required int peerUserId,
    int? itemId,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/chats/direct',
      data: {'peer_user_id': peerUserId, if (itemId != null) 'item_id': itemId},
    );
    return response.data ?? <String, dynamic>{};
  }

  Future<List<dynamic>> getMessages(int chatId) async {
    final response = await _dio.get<List<dynamic>>(
      '/chats/$chatId/messages',
      queryParameters: {'_ts': DateTime.now().millisecondsSinceEpoch},
    );
    return response.data ?? <dynamic>[];
  }

  Future<Map<String, dynamic>> sendMessage({
    required int chatId,
    required String content,
    String messageType = 'text',
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/chats/$chatId/messages',
      data: {'content': content, 'message_type': messageType},
    );
    return response.data ?? <String, dynamic>{};
  }

  Future<void> deleteChat(int chatId) async {
    await _dio.delete('/chats/$chatId');
  }

  // ---------------- Reviews ----------------

  Future<int> createReview({
    required int requestId,
    required int revieweeId,
    required int rating,
    String? comment,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/reviews',
      data: {
        'request_id': requestId,
        'reviewee_id': revieweeId,
        'rating': rating,
        if (comment != null) 'comment': comment,
      },
    );
    return _extractId(response.data);
  }

  Future<List<dynamic>> getReviews({int? userId}) async {
    final response = await _dio.get<List<dynamic>>(
      '/reviews',
      queryParameters: userId != null ? {'user_id': userId} : null,
    );
    return response.data ?? <dynamic>[];
  }

  // ---------------- Favorites ----------------

  Future<List<dynamic>> getFavorites() async {
    final response = await _dio.get<List<dynamic>>('/favorites');
    return response.data ?? <dynamic>[];
  }

  Future<void> addFavorite(int itemId) async {
    await _dio.post('/favorites', data: {'item_id': itemId});
  }

  Future<void> removeFavorite(int itemId) async {
    await _dio.delete('/favorites/$itemId');
  }

  // ---------------- Uploads & Evidence ----------------

  Future<List<String>> uploadFiles(List<MultipartFile> files) async {
    final form = FormData.fromMap({'files': files});
    final response = await _dio.post<Map<String, dynamic>>(
      '/uploads',
      data: form,
      options: Options(contentType: 'multipart/form-data'),
    );
    final urls = response.data?['urls'] as List<dynamic>?;
    return urls?.map((e) => e.toString()).toList() ?? <String>[];
  }

  Future<Map<String, dynamic>> attachEvidence({
    required int requestId,
    required String type, // handover | return
    required List<String> urls,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/requests/$requestId/evidence',
      data: {'type': type, 'urls': urls},
    );
    return response.data ?? <String, dynamic>{};
  }

  // ---------------- Reports ----------------

  Future<int> createReport({
    int? requestId,
    String? targetType,
    int? targetId,
    String? reason,
    String? reasonCategory,
    String? description,
    List<String>? mediaUrls,
  }) async {
    final resolvedRequestId = requestId ?? targetId;
    if (resolvedRequestId == null || resolvedRequestId <= 0) {
      throw ArgumentError('requestId is required');
    }

    final response = await _dio.post<Map<String, dynamic>>(
      '/reports',
      data: {
        'request_id': resolvedRequestId,
        'target_type': targetType ?? 'request',
        'target_id': resolvedRequestId,
        'reason_category': reasonCategory ?? reason ?? 'Other',
        'description': description ?? reason ?? '',
        if (reason != null && reason.isNotEmpty) 'reason': reason,
        if (mediaUrls != null) 'media_urls': mediaUrls,
      },
    );
    return _extractId(response.data);
  }

  Future<List<dynamic>> getReports() async {
    final response = await _dio.get<List<dynamic>>('/reports');
    return response.data ?? <dynamic>[];
  }

  Future<List<dynamic>> getAdminReports() async {
    final response = await _dio.get<List<dynamic>>('/admin/reports');
    return response.data ?? <dynamic>[];
  }

  Future<Map<String, dynamic>> getAdminReportDetails(int reportId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/admin/reports/$reportId',
    );
    return response.data ?? <String, dynamic>{};
  }

  Future<Map<String, dynamic>> updateAdminReportStatus({
    required int reportId,
    required String status,
    String? resolutionNote,
  }) async {
    final response = await _dio.patch<Map<String, dynamic>>(
      '/admin/reports/$reportId/status',
      data: {
        'status': status,
        if (resolutionNote != null) 'resolution_note': resolutionNote,
      },
    );
    return response.data ?? <String, dynamic>{};
  }

  Future<List<dynamic>> getAdminTransactions() async {
    final response = await _dio.get<List<dynamic>>('/admin/transactions');
    return response.data ?? <dynamic>[];
  }

  Future<Map<String, dynamic>> getAdminTransactionEvidence(
    int requestId,
  ) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/admin/transactions/$requestId/evidence',
    );
    return response.data ?? <String, dynamic>{};
  }

  Future<Map<String, dynamic>> confiscateTransactionDeposit({
    required int requestId,
    required String reason,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/admin/transactions/$requestId/confiscate',
      data: {'reason': reason},
    );
    return response.data ?? <String, dynamic>{};
  }

  Future<List<dynamic>> getAdminUsers({String? query}) async {
    final response = await _dio.get<List<dynamic>>(
      '/admin/users',
      queryParameters: {
        if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
      },
    );
    return response.data ?? <dynamic>[];
  }

  Future<Map<String, dynamic>> setAdminUserBan({
    required int userId,
    required bool isBanned,
  }) async {
    final response = await _dio.patch<Map<String, dynamic>>(
      '/admin/users/$userId/ban',
      data: {'is_banned': isBanned},
    );
    return response.data ?? <String, dynamic>{};
  }

  Future<List<dynamic>> getAdminListings({
    required String availability,
    String? query,
  }) async {
    final response = await _dio.get<List<dynamic>>(
      '/admin/listings',
      queryParameters: {
        'availability': availability,
        if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
      },
    );
    return response.data ?? <dynamic>[];
  }

  Future<Map<String, dynamic>> deleteAdminListingsBulk(List<int> ids) async {
    final response = await _dio.delete<Map<String, dynamic>>(
      '/admin/listings/bulk',
      data: {'ids': ids},
    );
    return response.data ?? <String, dynamic>{};
  }

  // ---------------- KYC ----------------

  Future<Map<String, dynamic>> getAdminDashboardStats() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/admin/dashboard-stats',
    );
    return response.data ?? <String, dynamic>{};
  }

  Future<Map<String, dynamic>> getKyc() async {
    final response = await _dio.get<Map<String, dynamic>>('/kyc');
    return response.data ?? <String, dynamic>{};
  }

  Future<List<dynamic>> getPendingKycs() async {
    final response = await _dio.get<List<dynamic>>('/kyc/pending');
    return response.data ?? <dynamic>[];
  }

  Future<Map<String, dynamic>> getKycByUserId(int userId) async {
    final response = await _dio.get<Map<String, dynamic>>('/kyc/$userId');
    return response.data ?? <String, dynamic>{};
  }

  Future<Map<String, dynamic>> submitKyc({
    required String docType,
    required String idImageUrl,
    required String selfieImageUrl,
    String? note,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/kyc/submit',
      data: {
        'kyc_doc_type': docType,
        'kyc_id_image_url': idImageUrl,
        'kyc_selfie_image_url': selfieImageUrl,
        if (note != null) 'kyc_note': note,
      },
    );
    return response.data ?? <String, dynamic>{};
  }

  Future<Map<String, dynamic>> adminUpdateKyc({
    required int userId,
    required String status,
    String? note,
  }) async {
    final response = await _dio.patch<Map<String, dynamic>>(
      '/kyc/$userId/status',
      data: {'status': status, if (note != null) 'note': note},
    );
    return response.data ?? <String, dynamic>{};
  }

  int _extractId(Map<String, dynamic>? data) {
    if (data == null || !data.containsKey('id')) {
      throw StateError('Response missing id');
    }
    return (data['id'] as num).toInt();
  }
}

/* Quick usage example (pseudo):
final api = ApiClient(baseUrl: 'http://localhost:4000');
await api.register(email: 'a@x.com', password: 'Passw0rd!', name: 'User A');
final items = await api.getItems();
*/
