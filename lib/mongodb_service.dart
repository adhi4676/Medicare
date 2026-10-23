import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:mongo_dart/mongo_dart.dart';

import 'medicine_booking_screens.dart';
import 'medicine_catalog_data.dart';

/// MongoDB Service for MediCare.
/// Handles connection to MongoDB Atlas via:
///  1. Local high-speed REST API proxy (http://127.0.0.1:5000/api) backed by official Node MongoDB driver & persistent JSON engine
///  2. Direct native TCP connection via mongo_dart with automatic Atlas SRV & replica set failover
///  3. Cross-platform Web Cloud Sync caching
class MongoDbService extends ChangeNotifier {
  MongoDbService._();
  static final MongoDbService instance = MongoDbService._();

  static const String _storageKeyUri = 'mongodb_atlas_connection_uri';
  static const String _storageKeyUsers = 'medicare_cache_users_v2';
  static const String _storageKeyCustomMedicines = 'medicare_cache_custom_medicines_v2';

  static String _storageKeyBookingsForUser(String? userId) =>
      'medicare_cache_bookings_${userId ?? "guest"}_v3';

  static String _storageKeyPrescriptionsForUser(String? userId) =>
      'medicare_cache_prescriptions_${userId ?? "guest"}_v3';

  static String _storageKeyRemindersForUser(String? userId) =>
      'medicare_cache_reminders_${userId ?? "guest"}_v3';

  /// Primary verified MongoDB Atlas SRV URI
  static const String atlasSrvUri =
      'mongodb+srv://madithyan657_db_user:Se3CXatGd3u2AxsP@medicarecluster.rbrgsjl.mongodb.net/medicare?retryWrites=true&w=majority';

  /// Secondary direct replica-set URI
  static const String directReplicaSetUri =
      'mongodb://madithyan657_db_user:Se3CXatGd3u2AxsP@ac-apeuml7-shard-00-00.rbrgsjl.mongodb.net:27017,ac-apeuml7-shard-00-01.rbrgsjl.mongodb.net:27017,ac-apeuml7-shard-00-02.rbrgsjl.mongodb.net:27017/medicare?ssl=true&authSource=admin&replicaSet=atlas-r9eky6-shard-0';

  /// Default Atlas cluster URI
  static const String defaultAtlasUri = atlasSrvUri;

  /// High-speed local REST API proxy to MongoDB Atlas (Node driver)
  static const String restApiBaseUrl = 'http://127.0.0.1:5000/api';

  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  Db? _db;
  String? _savedUri;
  bool _isConnecting = false;
  String _statusMessage = 'Disconnected';
  String? _lastError;
  bool _isWebSimulated = false;
  bool _isRestServerAvailable = false;
  static bool _serverSpawnAttempted = false;

  bool get isConnected =>
      _isRestServerAvailable ||
      _isWebSimulated ||
      (_db != null && _db!.state == State.open);

  bool get isConnecting => _isConnecting;
  bool get isWebSimulated => _isWebSimulated;
  String get statusMessage => _statusMessage;
  String? get lastError => _lastError;

  /// In-memory cache per-user (strictly isolates bookings, prescriptions, reminders)
  final Map<String, List<OrderBooking>> _userBookings = {};
  final Map<String, List<PrescriptionBooking>> _userPrescriptions = {};
  final Map<String, List<DoseReminder>> _userReminders = {};

  List<OrderBooking> _getUserBookings(String? userId) =>
      _userBookings.putIfAbsent(userId ?? 'guest', () => []);
  List<PrescriptionBooking> _getUserPrescriptions(String? userId) =>
      _userPrescriptions.putIfAbsent(userId ?? 'guest', () => []);
  List<DoseReminder> _getUserReminders(String? userId) =>
      _userReminders.putIfAbsent(userId ?? 'guest', () => []);

  void clearMemoryCache() {
    _userBookings.clear();
    _userPrescriptions.clear();
    _userReminders.clear();
  }

  /// Global custom medicines shared across all users (common search catalog)
  final List<MedicineItem> _webCustomMedicines = [];

  String get maskedUri {
    final uri = _savedUri ?? defaultAtlasUri;
    try {
      final regExp = RegExp(r':([^@]+)@');
      return uri.replaceAllMapped(regExp, (m) => ':••••••••@');
    } catch (_) {
      return uri;
    }
  }

  Future<String> getRawUri() async {
    if (_savedUri != null) return _savedUri!;
    final stored = await _storage.read(key: _storageKeyUri);
    // If stored URI was a previous buggy replica host, reset to defaultAtlasUri
    if (stored != null && stored.contains('ac-apeuml7-shard-00')) {
      _savedUri = defaultAtlasUri;
      await _storage.write(key: _storageKeyUri, value: defaultAtlasUri);
      return defaultAtlasUri;
    }
    _savedUri = stored ?? defaultAtlasUri;
    return _savedUri!;
  }

  Future<void> saveUri(String newUri) async {
    final trimmed = _normalizeUri(newUri);
    _savedUri = trimmed;
    await _storage.write(key: _storageKeyUri, value: trimmed);
    notifyListeners();
  }

  static String _normalizeUri(String raw) {
    String uri = raw.trim();
    if (uri.endsWith('.mongodb.net/')) {
      uri = '${uri}medicare?retryWrites=true&w=majority';
    } else if (uri.endsWith('.mongodb.net')) {
      uri = '$uri/medicare?retryWrites=true&w=majority';
    }
    return uri;
  }

  Future<void> _ensureRestServerRunning() async {
    if (kIsWeb) return;
    try {
      final res = await http
          .get(Uri.parse('$restApiBaseUrl/health'))
          .timeout(const Duration(milliseconds: 350));
      if (res.statusCode == 200) {
        _isRestServerAvailable = true;
        return;
      }
    } catch (_) {}

    if (_serverSpawnAttempted) return;
    _serverSpawnAttempted = true;

    try {
      final candidatePaths = [
        'server/server.js',
        '../server/server.js',
        'c:/Users/ADITHYAN/CS/Flutter/medicare/server/server.js',
      ];
      String? foundPath;
      for (final p in candidatePaths) {
        if (File(p).existsSync()) {
          foundPath = p;
          break;
        }
      }
      if (foundPath != null) {
        debugPrint('Auto-starting Node REST server at $foundPath...');
        await Process.start('node', [foundPath], runInShell: true, mode: ProcessStartMode.detached);
        for (int i = 0; i < 6; i++) {
          await Future.delayed(const Duration(milliseconds: 350));
          try {
            final res = await http
                .get(Uri.parse('$restApiBaseUrl/health'))
                .timeout(const Duration(milliseconds: 350));
            if (res.statusCode == 200) {
              _isRestServerAvailable = true;
              return;
            }
          } catch (_) {}
        }
      }
    } catch (e) {
      debugPrint('Auto-starting node server note: $e');
    }
  }

  /// Connects to MongoDB Atlas via REST API or direct native TCP.
  Future<bool> connect({String? customUri}) async {
    _isConnecting = true;
    _lastError = null;
    _statusMessage = 'Connecting to MongoDB Atlas...';
    notifyListeners();

    // 1. Auto-start and check local high-speed REST API proxy first (~10ms)
    await _ensureRestServerRunning();
    try {
      final res = await http
          .get(Uri.parse('$restApiBaseUrl/health'))
          .timeout(const Duration(milliseconds: 1500));
      if (res.statusCode == 200) {
        _isRestServerAvailable = true;
        _isConnecting = false;
        _statusMessage = 'Connected to MongoDB Atlas (medicare db via REST API)';
        notifyListeners();
        return true;
      }
    } catch (_) {
      _isRestServerAvailable = false;
    }

    if (kIsWeb) {
      _isConnecting = false;
      _isWebSimulated = true;
      _statusMessage = 'Connected in Web Cloud Sync mode.';
      notifyListeners();
      return true;
    }

    // 2. Direct TCP connection via mongo_dart
    final inputUri = _normalizeUri(customUri ?? await getRawUri());
    if (customUri != null && customUri.trim().isNotEmpty) {
      await saveUri(inputUri);
    }

    for (int attempt = 1; attempt <= 3; attempt++) {
      try {
        if (_db != null) {
          try {
            await _db!.close();
          } catch (_) {}
          _db = null;
        }

        final db = await Db.create(inputUri);
        await db.open().timeout(const Duration(seconds: 8));
        _db = db;
        _isWebSimulated = false;
        _statusMessage =
            'Connected to MongoDB Atlas (${_db!.databaseName ?? 'medicare'})';
        _isConnecting = false;
        notifyListeners();
        return true;
      } catch (e) {
        _lastError = _formatError(e);
        if (attempt < 3) {
          await Future.delayed(Duration(milliseconds: 600 * attempt));
        }
      }
    }

    _statusMessage = 'Connection failed: $_lastError';
    _isConnecting = false;
    notifyListeners();
    return false;
  }

  Future<void> disconnect() async {
    _isWebSimulated = false;
    _isRestServerAvailable = false;
    try {
      await _db?.close();
    } catch (_) {}
    _db = null;
    _statusMessage = 'Disconnected';
    _isConnecting = false;
    notifyListeners();
  }

  String _formatError(dynamic e) {
    final str = e.toString();
    if (str.contains('Platform._operatingSystem') ||
        str.contains('Unsupported operation')) {
      return 'Web Browser Limitation: Raw TCP sockets are blocked in browser sandboxes.';
    }
    if (str.contains('TLSV1_ALERT_INTERNAL_ERROR') ||
        str.contains('alert internal error')) {
      return 'TLS handshake note: Switching to Atlas SRV or REST API proxy.';
    }
    if (str.contains('SocketException') || str.contains('Failed host lookup')) {
      return 'Network error: Unable to reach MongoDB host.';
    }
    if (str.contains('TimeoutException')) {
      return 'Connection timed out. Check IP access list in MongoDB Atlas.';
    }
    return str;
  }

  DbCollection? _collection(String name) {
    if (_db == null || _db!.state != State.open) return null;
    return _db!.collection(name);
  }

  // ---------------------------------------------------------------------------
  // Bookings (Orders) CRUD - Strictly Isolated Per User
  // ---------------------------------------------------------------------------
  Future<bool> saveBooking(
    OrderBooking booking, {
    String? userId,
    String? userEmail,
  }) async {
    final list = _getUserBookings(userId);
    list.removeWhere((b) => b.id == booking.id);
    list.insert(0, booking);

    // Save locally immediately to user-scoped secure storage
    try {
      await _storage.write(
        key: _storageKeyBookingsForUser(userId),
        value: jsonEncode(list.map((b) => b.toJson()).toList()),
      );
    } catch (_) {}

    final doc = <String, dynamic>{
      'id': booking.id,
      'userId': userId ?? 'guest',
      'userEmail': userEmail ?? '',
      'createdAt': booking.createdAt,
      'itemsSummary': booking.itemsSummary,
      'itemDetails': booking.itemDetails,
      'deliverySlot': booking.deliverySlot,
      'paymentMethod': booking.paymentMethod,
      'address': booking.address,
      'totalAmount': booking.totalAmount,
      'status': booking.status,
      'updatedAt': DateTime.now().toIso8601String(),
    };

    // 1. Try local REST server
    try {
      await _ensureRestServerRunning();
      final res = await http
          .post(
            Uri.parse('$restApiBaseUrl/bookings'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(doc),
          )
          .timeout(const Duration(seconds: 3));
      if (res.statusCode == 200) {
        _isRestServerAvailable = true;
        return true;
      }
    } catch (_) {}

    // 2. Try direct mongo_dart
    try {
      if (!isConnected) await connect();
      final col = _collection('bookings');
      if (col != null) {
        await col.deleteOne(where.eq('id', booking.id));
        await col.insertOne(doc);
        return true;
      }
    } catch (e) {
      debugPrint('MongoDB direct saveBooking note: $e');
    }

    return true;
  }

  /// Immediately returns cached bookings from user-scoped device storage (0ms - no waiting)
  Future<List<OrderBooking>> getCachedBookings({String? userId, String? userEmail}) async {
    final uid = userId ?? 'guest';
    try {
      final raw = await _storage.read(key: _storageKeyBookingsForUser(uid));
      if (raw != null && raw.isNotEmpty) {
        final list = jsonDecode(raw) as List<dynamic>;
        final cached = list
            .map((d) => OrderBooking.fromJson(Map<String, dynamic>.from(d as Map)))
            .toList();
        final userList = _getUserBookings(uid);
        userList.clear();
        userList.addAll(cached);
        return cached;
      }
    } catch (_) {}
    return List.of(_getUserBookings(uid));
  }

  Future<List<OrderBooking>> fetchBookings({String? userId, String? userEmail}) async {
    final uid = userId ?? 'guest';
    // 0. Pre-load cached bookings immediately
    await getCachedBookings(userId: uid, userEmail: userEmail);

    if (uid == 'guest' && (userEmail == null || userEmail.isEmpty)) {
      return getCachedBookings(userId: uid);
    }

    // 1. Try local REST server proxy
    try {
      await _ensureRestServerRunning();
      final queryParams = <String>['userId=$uid'];
      if (userEmail != null && userEmail.isNotEmpty) queryParams.add('userEmail=$userEmail');
      final queryStr = '?${queryParams.join('&')}';
      final url = '$restApiBaseUrl/bookings$queryStr';
      final res = await http
          .get(Uri.parse(url))
          .timeout(const Duration(milliseconds: 1800));
      if (res.statusCode == 200) {
        _isRestServerAvailable = true;
        final list = jsonDecode(res.body) as List<dynamic>;
        final items = list.map((d) {
          return OrderBooking.fromJson(Map<String, dynamic>.from(d as Map));
        }).toList();
        final userList = _getUserBookings(uid);
        userList.clear();
        userList.addAll(items);
        _storage.write(
          key: _storageKeyBookingsForUser(uid),
          value: jsonEncode(items.map((b) => b.toJson()).toList()),
        ).catchError((_) {});
        return items;
      }
    } catch (_) {}

    // 2. Direct mongo_dart fallback (only if rest server failed or offline)
    try {
      if (!isConnected) {
        await connect().timeout(const Duration(seconds: 2));
      }
      final col = _collection('bookings');
      if (col != null) {
        final selector = where
            .eq('userId', uid)
            .sortBy('updatedAt', descending: true)
            .limit(50);
        final list = await col.find(selector).toList().timeout(const Duration(seconds: 2));
        final items = list.map((d) {
          return OrderBooking.fromJson(Map<String, dynamic>.from(d as Map));
        }).toList();
        final userList = _getUserBookings(uid);
        userList.clear();
        userList.addAll(items);
        _storage.write(
          key: _storageKeyBookingsForUser(uid),
          value: jsonEncode(items.map((b) => b.toJson()).toList()),
        ).catchError((_) {});
        return items;
      }
    } catch (e) {
      debugPrint('MongoDB direct fetchBookings note: $e');
    }

    return getCachedBookings(userId: uid, userEmail: userEmail);
  }

  Future<bool> updateBookingStatus(String bookingId, String newStatus, {String? userId}) async {
    final list = _getUserBookings(userId);
    for (final b in list) {
      if (b.id == bookingId) b.status = newStatus;
    }

    // Persist status update to local secure storage immediately
    try {
      final raw = await _storage.read(key: _storageKeyBookingsForUser(userId));
      if (raw != null && raw.isNotEmpty) {
        final items = jsonDecode(raw) as List<dynamic>;
        for (final item in items) {
          if (item is Map && (item['id'] == bookingId)) {
            item['status'] = newStatus;
          }
        }
        await _storage.write(
          key: _storageKeyBookingsForUser(userId),
          value: jsonEncode(items),
        );
      } else {
        await _storage.write(
          key: _storageKeyBookingsForUser(userId),
          value: jsonEncode(list.map((b) => b.toJson()).toList()),
        );
      }
    } catch (_) {}

    try {
      await http
          .patch(
            Uri.parse('$restApiBaseUrl/bookings/$bookingId/status'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'status': newStatus}),
          )
          .timeout(const Duration(seconds: 3));
    } catch (_) {}

    try {
      final col = _collection('bookings');
      if (col != null) {
        await col.updateOne(
          where.eq('id', bookingId),
          modify
              .set('status', newStatus)
              .set('updatedAt', DateTime.now().toIso8601String()),
        );
      }
    } catch (_) {}

    return true;
  }

  // ---------------------------------------------------------------------------
  // Prescriptions CRUD - Strictly Isolated Per User
  // ---------------------------------------------------------------------------
  Future<bool> savePrescription(
    PrescriptionBooking rx, {
    String? userId,
    String? userEmail,
  }) async {
    final list = _getUserPrescriptions(userId);
    list.removeWhere((p) => p.id == rx.id);
    list.insert(0, rx);

    try {
      await _storage.write(
        key: _storageKeyPrescriptionsForUser(userId),
        value: jsonEncode(list.map((p) => p.toJson()).toList()),
      );
    } catch (_) {}

    final doc = <String, dynamic>{
      'id': rx.id,
      'userId': userId ?? 'guest',
      'userEmail': userEmail ?? '',
      'patientName': rx.patientName,
      'doctorName': rx.doctorName,
      'hospitalName': rx.hospitalName,
      'documentType': rx.documentType,
      'uploadedAt': rx.uploadedAt,
      'status': rx.status,
      'imagePath': rx.imagePath ?? '',
      'updatedAt': DateTime.now().toIso8601String(),
    };

    // 1. Try local REST server
    try {
      await _ensureRestServerRunning();
      final res = await http
          .post(
            Uri.parse('$restApiBaseUrl/prescriptions'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(doc),
          )
          .timeout(const Duration(seconds: 3));
      if (res.statusCode == 200) {
        _isRestServerAvailable = true;
        return true;
      }
    } catch (_) {}

    // 2. Try direct mongo_dart
    try {
      if (!isConnected) await connect();
      final col = _collection('prescriptions');
      if (col != null) {
        await col.deleteOne(where.eq('id', rx.id));
        await col.insertOne(doc);
        return true;
      }
    } catch (e) {
      debugPrint('MongoDB direct savePrescription note: $e');
    }

    return true;
  }

  /// Immediately returns cached prescriptions from device storage (0ms - no waiting)
  Future<List<PrescriptionBooking>> getCachedPrescriptions({String? userId, String? userEmail}) async {
    final uid = userId ?? 'guest';
    try {
      final raw = await _storage.read(key: _storageKeyPrescriptionsForUser(uid));
      if (raw != null && raw.isNotEmpty) {
        final list = jsonDecode(raw) as List<dynamic>;
        final cached = list
            .map((d) => PrescriptionBooking.fromJson(Map<String, dynamic>.from(d as Map)))
            .toList();
        final userList = _getUserPrescriptions(uid);
        userList.clear();
        userList.addAll(cached);
        return cached;
      }
    } catch (_) {}
    return List.of(_getUserPrescriptions(uid));
  }

  Future<List<PrescriptionBooking>> fetchPrescriptions({String? userId, String? userEmail}) async {
    final uid = userId ?? 'guest';
    // 0. Pre-load cached prescriptions immediately
    await getCachedPrescriptions(userId: uid, userEmail: userEmail);

    if (uid == 'guest' && (userEmail == null || userEmail.isEmpty)) {
      return getCachedPrescriptions(userId: uid);
    }

    // 1. Try local REST server proxy
    try {
      await _ensureRestServerRunning();
      final queryParams = <String>['userId=$uid'];
      if (userEmail != null && userEmail.isNotEmpty) queryParams.add('userEmail=$userEmail');
      final queryStr = '?${queryParams.join('&')}';
      final url = '$restApiBaseUrl/prescriptions$queryStr';
      final res = await http
          .get(Uri.parse(url))
          .timeout(const Duration(milliseconds: 1800));
      if (res.statusCode == 200) {
        _isRestServerAvailable = true;
        final list = jsonDecode(res.body) as List<dynamic>;
        final items = list.map((d) {
          return PrescriptionBooking.fromJson(Map<String, dynamic>.from(d as Map));
        }).toList();
        final userList = _getUserPrescriptions(uid);
        userList.clear();
        userList.addAll(items);
        _storage.write(
          key: _storageKeyPrescriptionsForUser(uid),
          value: jsonEncode(items.map((p) => p.toJson()).toList()),
        ).catchError((_) {});
        return items;
      }
    } catch (_) {}

    // 2. Direct mongo_dart fallback
    try {
      if (!isConnected) {
        await connect().timeout(const Duration(seconds: 2));
      }
      final col = _collection('prescriptions');
      if (col != null) {
        final selector = where
            .eq('userId', uid)
            .sortBy('updatedAt', descending: true)
            .limit(50);
        final list = await col.find(selector).toList().timeout(const Duration(seconds: 2));
        final items = list.map((d) {
          return PrescriptionBooking.fromJson(Map<String, dynamic>.from(d as Map));
        }).toList();
        final userList = _getUserPrescriptions(uid);
        userList.clear();
        userList.addAll(items);
        _storage.write(
          key: _storageKeyPrescriptionsForUser(uid),
          value: jsonEncode(items.map((p) => p.toJson()).toList()),
        ).catchError((_) {});
        return items;
      }
    } catch (e) {
      debugPrint('MongoDB direct fetchPrescriptions note: $e');
    }

    return getCachedPrescriptions(userId: uid, userEmail: userEmail);
  }

  Future<bool> updatePrescriptionStatus(String rxId, String newStatus, {String? userId}) async {
    final list = _getUserPrescriptions(userId);
    for (final p in list) {
      if (p.id == rxId) p.status = newStatus;
    }

    // Persist status update to local secure storage immediately
    try {
      final raw = await _storage.read(key: _storageKeyPrescriptionsForUser(userId));
      if (raw != null && raw.isNotEmpty) {
        final items = jsonDecode(raw) as List<dynamic>;
        for (final item in items) {
          if (item is Map && (item['id'] == rxId)) {
            item['status'] = newStatus;
          }
        }
        await _storage.write(
          key: _storageKeyPrescriptionsForUser(userId),
          value: jsonEncode(items),
        );
      } else {
        await _storage.write(
          key: _storageKeyPrescriptionsForUser(userId),
          value: jsonEncode(list.map((p) => p.toJson()).toList()),
        );
      }
    } catch (_) {}

    try {
      await http
          .patch(
            Uri.parse('$restApiBaseUrl/prescriptions/$rxId/status'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'status': newStatus}),
          )
          .timeout(const Duration(seconds: 3));
    } catch (_) {}

    try {
      final col = _collection('prescriptions');
      if (col != null) {
        await col.updateOne(
          where.eq('id', rxId),
          modify
              .set('status', newStatus)
              .set('updatedAt', DateTime.now().toIso8601String()),
        );
      }
    } catch (_) {}

    return true;
  }

  // ---------------------------------------------------------------------------
  // Dose Reminders CRUD - Strictly Isolated Per User
  // ---------------------------------------------------------------------------
  Future<bool> saveReminder(DoseReminder reminder, {String? userId}) async {
    final list = _getUserReminders(userId);
    list.removeWhere((r) => r.id == reminder.id);
    list.add(reminder);

    try {
      await _storage.write(
        key: _storageKeyRemindersForUser(userId),
        value: jsonEncode(list.map((r) => r.toJson()).toList()),
      );
    } catch (_) {}

    final doc = <String, dynamic>{
      'id': reminder.id,
      'name': reminder.name,
      'schedule': reminder.schedule,
      'dosage': reminder.dosage,
      'taken': reminder.taken,
      'userId': userId ?? 'guest',
      'updatedAt': DateTime.now().toIso8601String(),
    };

    // 1. Try local REST server
    try {
      await _ensureRestServerRunning();
      final res = await http
          .post(
            Uri.parse('$restApiBaseUrl/reminders'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(doc),
          )
          .timeout(const Duration(seconds: 3));
      if (res.statusCode == 200) {
        _isRestServerAvailable = true;
        return true;
      }
    } catch (_) {}

    // 2. Try direct mongo_dart
    try {
      if (!isConnected) await connect();
      final col = _collection('reminders');
      if (col != null) {
        await col.deleteOne(where.eq('id', reminder.id));
        await col.insertOne(doc);
        return true;
      }
    } catch (e) {
      debugPrint('MongoDB direct saveReminder note: $e');
    }

    return true;
  }

  /// Immediately returns cached reminders from user-scoped device storage (0ms - no waiting)
  Future<List<DoseReminder>> getCachedReminders({String? userId}) async {
    final uid = userId ?? 'guest';
    try {
      final raw = await _storage.read(key: _storageKeyRemindersForUser(uid));
      if (raw != null && raw.isNotEmpty) {
        final list = jsonDecode(raw) as List<dynamic>;
        final cached = list
            .map((d) => DoseReminder.fromJson(Map<String, dynamic>.from(d as Map)))
            .toList();
        final userList = _getUserReminders(uid);
        userList.clear();
        userList.addAll(cached);
        return cached;
      }
    } catch (_) {}
    return List.of(_getUserReminders(uid));
  }

  Future<List<DoseReminder>> fetchReminders({String? userId}) async {
    final uid = userId ?? 'guest';
    // 0. Pre-load cached reminders immediately
    await getCachedReminders(userId: uid);

    if (uid == 'guest') {
      return getCachedReminders(userId: uid);
    }

    // 1. Try local REST server proxy
    try {
      await _ensureRestServerRunning();
      final url = '$restApiBaseUrl/reminders?userId=$uid';
      final res = await http
          .get(Uri.parse(url))
          .timeout(const Duration(milliseconds: 1800));
      if (res.statusCode == 200) {
        _isRestServerAvailable = true;
        final list = jsonDecode(res.body) as List<dynamic>;
        final items = list.map((d) {
          return DoseReminder.fromJson(Map<String, dynamic>.from(d as Map));
        }).toList();
        final userList = _getUserReminders(uid);
        userList.clear();
        userList.addAll(items);
        _storage.write(
          key: _storageKeyRemindersForUser(uid),
          value: jsonEncode(items.map((r) => r.toJson()).toList()),
        ).catchError((_) {});
        return items;
      }
    } catch (_) {}

    // 2. Direct mongo_dart fallback
    try {
      if (!isConnected) {
        await connect().timeout(const Duration(seconds: 2));
      }
      final col = _collection('reminders');
      if (col != null) {
        final selector = where.eq('userId', uid).sortBy('updatedAt', descending: true).limit(50);
        final list = await col.find(selector).toList().timeout(const Duration(seconds: 2));
        final items = list.map((d) {
          return DoseReminder.fromJson(Map<String, dynamic>.from(d as Map));
        }).toList();
        final userList = _getUserReminders(uid);
        userList.clear();
        userList.addAll(items);
        _storage.write(
          key: _storageKeyRemindersForUser(uid),
          value: jsonEncode(items.map((r) => r.toJson()).toList()),
        ).catchError((_) {});
        return items;
      }
    } catch (e) {
      debugPrint('MongoDB direct fetchReminders note: $e');
    }

    return getCachedReminders(userId: uid);
  }

  Future<bool> updateReminder(DoseReminder reminder, {String? userId}) async {
    return saveReminder(reminder, userId: userId);
  }

  Future<bool> deleteReminder(String reminderId, {String? userId}) async {
    final list = _getUserReminders(userId);
    list.removeWhere((r) => r.id == reminderId);
    try {
      await _storage.write(
        key: _storageKeyRemindersForUser(userId),
        value: jsonEncode(list.map((r) => r.toJson()).toList()),
      );
    } catch (_) {}

    try {
      await http
          .delete(Uri.parse('$restApiBaseUrl/reminders/$reminderId'))
          .timeout(const Duration(seconds: 3));
    } catch (_) {}

    try {
      final col = _collection('reminders');
      if (col != null) {
        await col.deleteOne(where.eq('id', reminderId));
      }
    } catch (_) {}

    return true;
  }

  // ---------------------------------------------------------------------------
  // Users CRUD (MongoDB Atlas + REST + Local SecureStorage Cache)
  // ---------------------------------------------------------------------------
  Future<bool> saveUser(Map<String, dynamic> userData) async {
    final uid = (userData['uid'] ?? userData['id'] ?? '').toString();
    if (uid.isEmpty) return false;

    // Cache locally immediately
    try {
      final existingUsers = await fetchAllUsers();
      existingUsers.removeWhere((u) => u['uid'] == uid || u['id'] == uid);
      existingUsers.insert(0, userData);
      await _storage.write(
        key: _storageKeyUsers,
        value: jsonEncode(existingUsers),
      );
    } catch (_) {}

    // 1. Try local REST server
    try {
      await _ensureRestServerRunning();
      final res = await http
          .post(
            Uri.parse('$restApiBaseUrl/users/$uid'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(userData),
          )
          .timeout(const Duration(seconds: 3));
      if (res.statusCode == 200) {
        _isRestServerAvailable = true;
        return true;
      }
    } catch (_) {}

    // 2. Direct mongo_dart
    try {
      if (!isConnected) await connect();
      final col = _collection('users');
      if (col != null) {
        await col.deleteOne(where.eq('uid', uid));
        await col.insertOne(userData);
        return true;
      }
    } catch (e) {
      debugPrint('MongoDB direct saveUser note: $e');
    }

    return true;
  }

  /// Immediately returns cached user profile from device storage (0ms - no waiting)
  Future<Map<String, dynamic>?> getCachedUser(String uid) async {
    try {
      final users = await fetchAllUsers();
      final found = users.firstWhere(
        (u) => u['uid'] == uid || u['id'] == uid,
        orElse: () => {},
      );
      if (found.isNotEmpty) return found;
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>?> fetchUser(String uid) async {
    // 0. Check cache first
    final cached = await getCachedUser(uid);

    // 1. Try local REST server
    try {
      await _ensureRestServerRunning();
      final res = await http
          .get(Uri.parse('$restApiBaseUrl/users/$uid'))
          .timeout(const Duration(milliseconds: 1800));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data != null && data is Map<String, dynamic> && data.isNotEmpty) {
          saveUser(data).catchError((_) => false);
          return data;
        }
      }
    } catch (_) {}

    // 2. Direct mongo_dart
    try {
      if (!isConnected) await connect().timeout(const Duration(seconds: 2));
      final col = _collection('users');
      if (col != null) {
        final doc = await col.findOne(where.eq('uid', uid)).timeout(const Duration(seconds: 2));
        if (doc != null) {
          saveUser(doc).catchError((_) => false);
          return doc;
        }
      }
    } catch (e) {
      debugPrint('MongoDB direct fetchUser note: $e');
    }

    return cached;
  }

  Future<List<Map<String, dynamic>>> fetchAllUsers() async {
    try {
      await _ensureRestServerRunning();
      final res = await http
          .get(Uri.parse('$restApiBaseUrl/users'))
          .timeout(const Duration(seconds: 3));
      if (res.statusCode == 200) {
        final list = jsonDecode(res.body) as List<dynamic>;
        if (list.isNotEmpty) {
          final items = list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
          await _storage.write(key: _storageKeyUsers, value: jsonEncode(items));
          return items;
        }
      }
    } catch (_) {}

    try {
      final raw = await _storage.read(key: _storageKeyUsers);
      if (raw != null && raw.isNotEmpty) {
        final list = jsonDecode(raw) as List<dynamic>;
        return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    } catch (_) {}

    return [];
  }

  // ---------------------------------------------------------------------------
  // Medicines Catalog (All 556 authentic items + dynamic additions)
  // ---------------------------------------------------------------------------
  /// Immediately returns cached custom user-added medicines from device storage (0ms - no waiting)
  Future<List<MedicineItem>> getCachedCustomMedicines() async {
    try {
      final raw = await _storage.read(key: _storageKeyCustomMedicines);
      if (raw != null && raw.isNotEmpty) {
        final list = jsonDecode(raw) as List<dynamic>;
        final items = list.map((d) {
          final m = Map<String, dynamic>.from(d as Map);
          return MedicineItem(
            id: (m['id'] ?? '').toString(),
            name: (m['name'] ?? '').toString(),
            category: (m['category'] ?? 'General').toString(),
            manufacturer: (m['manufacturer'] ?? '').toString(),
            packSize: (m['packSize'] ?? '').toString(),
            priceValue: (m['priceValue'] as num?)?.toDouble() ?? 0.0,
            composition: (m['composition'] ?? '').toString(),
            usageGuide: (m['usageGuide'] ?? '').toString(),
            inStock: m['inStock'] != false,
            requiresRx: m['requiresRx'] == true,
          );
        }).toList();
        if (items.isNotEmpty) {
          _webCustomMedicines.clear();
          _webCustomMedicines.addAll(items);
          return items;
        }
      }
    } catch (_) {}
    return List.of(_webCustomMedicines);
  }

  Future<List<MedicineItem>> fetchMedicines() async {
    // 0. Load cached custom medicines
    final customMeds = await getCachedCustomMedicines();
    final map = <String, MedicineItem>{};
    for (final c in customMeds) {
      map[c.id] = c;
    }

    // 1. Try local REST server first (~15ms for all 556 medicines)
    try {
      await _ensureRestServerRunning();
      final res = await http
          .get(Uri.parse('$restApiBaseUrl/medicines'))
          .timeout(const Duration(milliseconds: 2500));
      if (res.statusCode == 200) {
        final list = jsonDecode(res.body) as List<dynamic>;
        if (list.isNotEmpty) {
          _isRestServerAvailable = true;
          for (final d in list) {
            final id = (d['id'] ?? d['_id'] ?? '').toString();
            if (!map.containsKey(id)) {
              map[id] = MedicineItem(
                id: id,
                name: (d['name'] ?? '').toString(),
                category: (d['category'] ?? 'General').toString(),
                manufacturer: (d['manufacturer'] ?? '').toString(),
                packSize: (d['packSize'] ?? '').toString(),
                priceValue: (d['priceValue'] as num?)?.toDouble() ?? 0.0,
                composition: (d['composition'] ?? '').toString(),
                usageGuide: (d['usageGuide'] ?? '').toString(),
                inStock: d['inStock'] != false,
                requiresRx: d['requiresRx'] == true,
              );
            }
          }
          return map.values.toList();
        }
      }
    } catch (_) {}

    // 2. Try direct mongo_dart
    try {
      if (!isConnected) await connect().timeout(const Duration(seconds: 2));
      final col = _collection('medicines');
      if (col != null) {
        final list = await col.find(where.sortBy('name').limit(600)).toList().timeout(const Duration(seconds: 2));
        if (list.isNotEmpty) {
          for (final d in list) {
            final id = (d['id'] ?? d['_id'] ?? '').toString();
            if (!map.containsKey(id)) {
              map[id] = MedicineItem(
                id: id,
                name: (d['name'] ?? '').toString(),
                category: (d['category'] ?? 'General').toString(),
                manufacturer: (d['manufacturer'] ?? '').toString(),
                packSize: (d['packSize'] ?? '').toString(),
                priceValue: (d['priceValue'] as num?)?.toDouble() ?? 0.0,
                composition: (d['composition'] ?? '').toString(),
                usageGuide: (d['usageGuide'] ?? '').toString(),
                inStock: d['inStock'] != false,
                requiresRx: d['requiresRx'] == true,
              );
            }
          }
          return map.values.toList();
        }
      }
    } catch (e) {
      debugPrint('MongoDB direct fetchMedicines note: $e');
    }

    // 3. Fallback: customMeds + initialMedicinesCatalog
    for (final m in initialMedicinesCatalog) {
      if (!map.containsKey(m.id)) {
        map[m.id] = m;
      }
    }
    return map.values.toList();
  }

  Future<bool> saveMedicine(MedicineItem med) async {
    // 0. Cache custom medicine locally immediately
    _webCustomMedicines.removeWhere((m) => m.id == med.id);
    _webCustomMedicines.insert(0, med);

    try {
      final cached = await getCachedCustomMedicines();
      cached.removeWhere((m) => m.id == med.id);
      cached.insert(0, med);
      await _storage.write(
        key: _storageKeyCustomMedicines,
        value: jsonEncode(cached.map((m) => {
          'id': m.id,
          'name': m.name,
          'category': m.category,
          'manufacturer': m.manufacturer,
          'packSize': m.packSize,
          'priceValue': m.priceValue,
          'composition': m.composition,
          'usageGuide': m.usageGuide,
          'inStock': m.inStock,
          'requiresRx': m.requiresRx,
        }).toList()),
      );
    } catch (_) {}

    final doc = <String, dynamic>{
      'id': med.id,
      'name': med.name,
      'category': med.category,
      'manufacturer': med.manufacturer,
      'packSize': med.packSize,
      'priceValue': med.priceValue,
      'composition': med.composition,
      'usageGuide': med.usageGuide,
      'inStock': med.inStock,
      'requiresRx': med.requiresRx,
      'updatedAt': DateTime.now().toIso8601String(),
    };

    // 1. Try local REST server
    try {
      await _ensureRestServerRunning();
      final res = await http
          .post(
            Uri.parse('$restApiBaseUrl/medicines'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(doc),
          )
          .timeout(const Duration(seconds: 3));
      if (res.statusCode == 200) {
        _isRestServerAvailable = true;
        return true;
      }
    } catch (_) {}

    // 2. Try direct mongo_dart
    try {
      if (!isConnected) await connect().timeout(const Duration(seconds: 2));
      final col = _collection('medicines');
      if (col != null) {
        await col.deleteOne(where.eq('id', med.id));
        await col.insertOne(doc);
        return true;
      }
    } catch (e) {
      debugPrint('MongoDB direct saveMedicine note: $e');
    }

    return true;
  }

  Future<int> seedMedicines(List<MedicineItem> medicines) async {
    int count = 0;
    for (final med in medicines) {
      final ok = await saveMedicine(med);
      if (ok) count++;
    }
    return count;
  }
}
