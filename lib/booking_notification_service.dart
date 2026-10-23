import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import 'medicine_booking_screens.dart';
import 'mongodb_service.dart';

class AppNotificationItem {
  AppNotificationItem({
    required this.id,
    required this.title,
    required this.body,
    required this.timestamp,
    required this.type,
  });

  final String id;
  final String title;
  final String body;
  final String timestamp;
  final String type; // 'booking', 'reminder', 'prescription'
}

/// Handles Section D:
///  - D1: Saving & updating bookings/prescriptions/reminders in Firebase Firestore
///  - D2: Triggering native mobile notifications (booking confirmed & reminders)
class BookingNotificationService {
  BookingNotificationService._();
  static final BookingNotificationService instance =
      BookingNotificationService._();

  FirebaseFirestore get _firestore => FirebaseFirestore.instance;
  FirebaseAuth get _auth => FirebaseAuth.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  final List<AppNotificationItem> notificationHistory = [];

  void clearHistory() {
    notificationHistory.clear();
  }

  // ---------------------------------------------------------------------------
  // D2: Initialize Mobile Local Notifications
  // ---------------------------------------------------------------------------
  Future<void> init() async {
    if (_initialized || kIsWeb) return;
    try {
      tz.initializeTimeZones();
      const androidSettings =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      const initSettings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );

      await _localNotifications.initialize(initSettings);

      // Request Android 13+ runtime notification permission
      final androidPlugin =
          _localNotifications.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.requestNotificationsPermission();
      await androidPlugin?.requestExactAlarmsPermission();

      _initialized = true;
    } catch (e) {
      debugPrint('Notification initialization warning: $e');
    }
  }

  final Map<String, Timer> _activeTimers = {};

  DateTime? parseScheduleTime(String schedule) {
    try {
      final reg = RegExp(r'(\d{1,2}):(\d{2})\s*(AM|PM)?', caseSensitive: false);
      final match = reg.firstMatch(schedule);
      if (match == null) return null;

      int hour = int.parse(match.group(1)!);
      final int minute = int.parse(match.group(2)!);
      final String? amPm = match.group(3)?.toUpperCase();

      if (amPm != null) {
        if (amPm == 'PM' && hour < 12) hour += 12;
        if (amPm == 'AM' && hour == 12) hour = 0;
      }

      final now = DateTime.now();
      var scheduled = DateTime(now.year, now.month, now.day, hour, minute);
      if (scheduled.isBefore(now)) {
        scheduled = scheduled.add(const Duration(days: 1));
      }
      return scheduled;
    } catch (_) {
      return null;
    }
  }

  Future<void> _triggerDeviceNotification({
    required int id,
    required String title,
    required String body,
    required String type,
  }) async {
    notificationHistory.insert(
      0,
      AppNotificationItem(
        id: 'notif-$id',
        title: title,
        body: body,
        timestamp: 'Just now',
        type: type,
      ),
    );

    if (kIsWeb) return;

    try {
      if (!_initialized) await init();

      final androidDetails = AndroidNotificationDetails(
        'medicare_high_importance_channel',
        'MediCare Bookings & Reminders',
        channelDescription:
            'Notifications for confirmed medicine bookings and dose reminders',
        importance: Importance.max,
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
        styleInformation: BigTextStyleInformation(body),
      );
      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      await _localNotifications.show(
        id,
        title,
        body,
        NotificationDetails(android: androidDetails, iOS: iosDetails),
      );
    } catch (e) {
      debugPrint('Local notification error: $e');
    }
  }

  Future<void> showBookingConfirmedNotification(OrderBooking booking) async {
    final id = DateTime.now().millisecondsSinceEpoch.remainder(100000);
    await _triggerDeviceNotification(
      id: id,
      title: '✅ Booking Confirmed • Order #${booking.id}',
      body:
          '${booking.itemsSummary} • ${booking.deliverySlot} • Total ₹${booking.totalAmount.toStringAsFixed(2)} saved in Database.',
      type: 'booking',
    );
  }

  Future<void> showReminderNotification(DoseReminder reminder) async {
    final id = reminder.id.hashCode.abs().remainder(100000);
    await _triggerDeviceNotification(
      id: id,
      title: '⏰ Medicine Reminder: ${reminder.name}',
      body: 'Time to take ${reminder.dosage} (${reminder.schedule}).',
      type: 'reminder',
    );
  }

  Future<void> scheduleReminderNotification(DoseReminder reminder) async {
    final scheduled = parseScheduleTime(reminder.schedule) ??
        DateTime.now().add(const Duration(minutes: 5));
    final id = reminder.id.hashCode.abs().remainder(100000);

    _activeTimers[reminder.id]?.cancel();

    // 1. Mobile Native Background Alarm via flutter_local_notifications
    if (!kIsWeb) {
      try {
        if (!_initialized) await init();

        final tzDate = tz.TZDateTime.from(scheduled, tz.local);
        final androidDetails = AndroidNotificationDetails(
          'medicare_reminder_channel',
          'MediCare Dose Reminders',
          channelDescription:
              'Exact timed notifications for scheduled medicine doses',
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
          styleInformation: BigTextStyleInformation(
            'Time to take ${reminder.dosage} (${reminder.schedule}). Marked in your MediCare schedule.',
          ),
        );
        const iosDetails = DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        );

        await _localNotifications.zonedSchedule(
          id,
          '⏰ Medicine Reminder: ${reminder.name}',
          'Time to take ${reminder.dosage} (${reminder.schedule})',
          tzDate,
          NotificationDetails(android: androidDetails, iOS: iosDetails),
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          matchDateTimeComponents: DateTimeComponents.time,
        );
      } catch (e) {
        debugPrint('Native zonedSchedule note: $e');
      }
    }

    // 2. Exact Timer for foreground / desktop / web
    final diff = scheduled.difference(DateTime.now());
    if (diff > Duration.zero) {
      _activeTimers[reminder.id] = Timer(diff, () async {
        await _triggerDeviceNotification(
          id: id,
          title: '⏰ Medicine Dose Due: ${reminder.name}',
          body:
              'Scheduled time reached! Take ${reminder.dosage} (${reminder.schedule}).',
          type: 'reminder',
        );
      });
    }
  }

  void cancelReminderNotification(String reminderId) {
    _activeTimers[reminderId]?.cancel();
    _activeTimers.remove(reminderId);
    final id = reminderId.hashCode.abs().remainder(100000);
    _localNotifications.cancel(id).catchError((_) {});
  }

  Future<void> showPrescriptionNotification(PrescriptionBooking rx) async {
    final id = DateTime.now().millisecondsSinceEpoch.remainder(100000);
    await _triggerDeviceNotification(
      id: id,
      title: '📋 Prescription Booked • #${rx.id}',
      body:
          'Prescription from ${rx.doctorName} (${rx.hospitalName}) saved to Database and sent for pharmacist verification.',
      type: 'prescription',
    );
  }

  // ---------------------------------------------------------------------------
  // D1: Save & Sync Bookings in Firebase Cloud Firestore & MongoDB Atlas
  // ---------------------------------------------------------------------------

  Future<bool> saveBookingToFirebase(OrderBooking booking) async {
    final user = _auth.currentUser;
    final data = <String, dynamic>{
      'id': booking.id,
      'userId': user?.uid ?? 'guest',
      'userEmail': user?.email ?? user?.phoneNumber ?? 'unknown',
      'userName': user?.displayName ?? 'MediCare Patient',
      'createdAt': booking.createdAt,
      'itemsSummary': booking.itemsSummary,
      'itemDetails': booking.itemDetails,
      'deliverySlot': booking.deliverySlot,
      'paymentMethod': booking.paymentMethod,
      'address': booking.address,
      'totalAmount': booking.totalAmount,
      'status': booking.status,
      'timestamp': FieldValue.serverTimestamp(),
    };

    final futures = <Future>[];

    // Firestore root
    futures.add(_firestore
        .collection('bookings')
        .doc(booking.id)
        .set(data)
        .timeout(const Duration(seconds: 4))
        .catchError((e) {
      debugPrint('Firestore root saveBooking note: $e');
    }));

    // Firestore user collection
    if (user != null) {
      futures.add(_firestore
          .collection('users')
          .doc(user.uid)
          .collection('bookings')
          .doc(booking.id)
          .set(data)
          .timeout(const Duration(seconds: 4))
          .catchError((e) {
        debugPrint('Firestore user saveBooking note: $e');
      }));
    }

    // MongoDB Atlas
    futures.add(MongoDbService.instance
        .saveBooking(booking, userId: user?.uid, userEmail: user?.email)
        .catchError((e) {
      debugPrint('MongoDB saveBooking error: $e');
      return false;
    }));

    await Future.wait(futures);
    return true;
  }

  Future<void> updateBookingStatusInFirebase(
    String bookingId,
    String newStatus,
  ) async {
    final user = _auth.currentUser;
    final futures = <Future>[];
    futures.add(_firestore
        .collection('bookings')
        .doc(bookingId)
        .set({'status': newStatus}, SetOptions(merge: true))
        .timeout(const Duration(seconds: 3))
        .catchError((_) {}));

    if (user != null) {
      futures.add(_firestore
          .collection('users')
          .doc(user.uid)
          .collection('bookings')
          .doc(bookingId)
          .set({'status': newStatus}, SetOptions(merge: true))
          .timeout(const Duration(seconds: 3))
          .catchError((_) {}));
    }
    futures.add(MongoDbService.instance
        .updateBookingStatus(bookingId, newStatus, userId: user?.uid)
        .catchError((_) => false));
    await Future.wait(futures);
  }

  Future<void> savePrescriptionToFirebase(PrescriptionBooking rx) async {
    final user = _auth.currentUser;
    final data = <String, dynamic>{
      'id': rx.id,
      'userId': user?.uid ?? 'guest',
      'patientName': rx.patientName,
      'doctorName': rx.doctorName,
      'hospitalName': rx.hospitalName,
      'documentType': rx.documentType,
      'uploadedAt': rx.uploadedAt,
      'status': rx.status,
      'imagePath': rx.imagePath ?? '',
      'timestamp': FieldValue.serverTimestamp(),
    };

    final futures = <Future>[];
    futures.add(_firestore
        .collection('prescriptions')
        .doc(rx.id)
        .set(data)
        .timeout(const Duration(seconds: 4))
        .catchError((e) {
      debugPrint('Firestore savePrescription note: $e');
    }));

    if (user != null) {
      futures.add(_firestore
          .collection('users')
          .doc(user.uid)
          .collection('prescriptions')
          .doc(rx.id)
          .set(data)
          .timeout(const Duration(seconds: 4))
          .catchError((e) {
        debugPrint('Firestore user rx note: $e');
      }));
    }

    futures.add(MongoDbService.instance
        .savePrescription(rx, userId: user?.uid)
        .catchError((e) {
      debugPrint('MongoDB rx note: $e');
      return false;
    }));

    await Future.wait(futures);
  }

  Future<void> updatePrescriptionStatusInFirebase(
    String rxId,
    String newStatus,
  ) async {
    final user = _auth.currentUser;
    final futures = <Future>[];
    futures.add(_firestore
        .collection('prescriptions')
        .doc(rxId)
        .set({'status': newStatus}, SetOptions(merge: true))
        .timeout(const Duration(seconds: 3))
        .catchError((_) {}));

    if (user != null) {
      futures.add(_firestore
          .collection('users')
          .doc(user.uid)
          .collection('prescriptions')
          .doc(rxId)
          .set({'status': newStatus}, SetOptions(merge: true))
          .timeout(const Duration(seconds: 3))
          .catchError((_) {}));
    }
    futures.add(MongoDbService.instance
        .updatePrescriptionStatus(rxId, newStatus, userId: user?.uid)
        .catchError((_) => false));
    await Future.wait(futures);
  }

  Future<void> saveReminderToFirebase(DoseReminder reminder) async {
    final user = _auth.currentUser;
    final data = <String, dynamic>{
      'id': reminder.id,
      'userId': user?.uid ?? 'guest',
      'name': reminder.name,
      'schedule': reminder.schedule,
      'dosage': reminder.dosage,
      'taken': reminder.taken,
      'timestamp': FieldValue.serverTimestamp(),
    };

    final futures = <Future>[];

    // MongoDB Atlas
    futures.add(MongoDbService.instance
        .saveReminder(reminder, userId: user?.uid)
        .catchError((e) {
      debugPrint('MongoDB saveReminder error: $e');
      return false;
    }));

    // Firestore root
    futures.add(_firestore
        .collection('reminders')
        .doc(reminder.id)
        .set(data)
        .timeout(const Duration(seconds: 4))
        .catchError((e) {
      debugPrint('Firestore root saveReminder error: $e');
    }));

    // Firestore user subcollection
    if (user != null) {
      futures.add(_firestore
          .collection('users')
          .doc(user.uid)
          .collection('reminders')
          .doc(reminder.id)
          .set(data)
          .timeout(const Duration(seconds: 4))
          .catchError((e) {
        debugPrint('Firestore user saveReminder error: $e');
      }));
    }

    await Future.wait(futures);
  }

  Future<void> updateReminderInFirebase(DoseReminder reminder) async {
    final user = _auth.currentUser;
    final futures = <Future>[];

    futures.add(_firestore
        .collection('reminders')
        .doc(reminder.id)
        .update({'taken': reminder.taken})
        .timeout(const Duration(seconds: 3))
        .catchError((_) {}));

    if (user != null) {
      futures.add(_firestore
          .collection('users')
          .doc(user.uid)
          .collection('reminders')
          .doc(reminder.id)
          .update({'taken': reminder.taken})
          .timeout(const Duration(seconds: 3))
          .catchError((_) {}));
    }

    futures.add(MongoDbService.instance
        .updateReminder(reminder, userId: user?.uid)
        .catchError((_) => false));

    await Future.wait(futures);
  }

  Future<void> deleteReminderFromFirebase(String reminderId) async {
    cancelReminderNotification(reminderId);
    final user = _auth.currentUser;
    final futures = <Future>[];

    futures.add(_firestore
        .collection('reminders')
        .doc(reminderId)
        .delete()
        .timeout(const Duration(seconds: 3))
        .catchError((_) {}));

    if (user != null) {
      futures.add(_firestore
          .collection('users')
          .doc(user.uid)
          .collection('reminders')
          .doc(reminderId)
          .delete()
          .timeout(const Duration(seconds: 3))
          .catchError((_) {}));
    }

    futures.add(MongoDbService.instance
        .deleteReminder(reminderId, userId: user?.uid)
        .catchError((_) => false));

    await Future.wait(futures);
  }

  Future<List<OrderBooking>> fetchBookingsFromFirebase() async {
    final user = _auth.currentUser;
    if (user == null) return [];
    final Map<String, OrderBooking> map = {};

    // 0. Seed with cached bookings immediately (0ms)
    try {
      final cached = await MongoDbService.instance.getCachedBookings(
        userId: user.uid,
        userEmail: user.email,
      );
      for (final b in cached) {
        map[b.id] = b;
      }
    } catch (_) {}

    // 1. Fetch concurrently from MongoDB Atlas and Cloud Firestore
    final tasks = <Future>[];

    // MongoDB Atlas
    tasks.add(
      MongoDbService.instance
          .fetchBookings(userId: user.uid, userEmail: user.email)
          .then((mongoBookings) {
        for (final b in mongoBookings) {
          if (map.containsKey(b.id) && map[b.id]!.status == 'Cancelled') {
            b.status = 'Cancelled';
          }
          map[b.id] = b;
        }
      }).catchError((e) {
        debugPrint('MongoDB fetchBookings note: $e');
      }),
    );

    // Cloud Firestore user subcollection
    tasks.add(
      _firestore
          .collection('users')
          .doc(user.uid)
          .collection('bookings')
          .orderBy('timestamp', descending: true)
          .limit(30)
          .get()
          .then((snap) {
        for (final doc in snap.docs) {
          final d = doc.data();
          final id = (d['id'] ?? doc.id).toString();
          final remoteBooking = OrderBooking(
            id: id,
            createdAt: (d['createdAt'] ?? 'Saved in Database').toString(),
            itemsSummary: (d['itemsSummary'] ?? 'Medicine Order').toString(),
            itemDetails: (d['itemDetails'] as List<dynamic>?)
                    ?.map((e) => e.toString())
                    .toList() ??
                [],
            deliverySlot:
                (d['deliverySlot'] ?? 'Standard Delivery').toString(),
            paymentMethod: (d['paymentMethod'] ?? 'UPI').toString(),
            address: (d['address'] ?? '').toString(),
            totalAmount: (d['totalAmount'] as num?)?.toDouble() ?? 0.0,
            status: (d['status'] ?? 'Processing').toString(),
          );
          if (!map.containsKey(id)) {
            map[id] = remoteBooking;
          } else if (map[id]!.status != 'Cancelled' && remoteBooking.status == 'Cancelled') {
            map[id] = remoteBooking;
          }
        }
      }).catchError((e) {
        debugPrint('Firestore user fetchBookings note: $e');
      }),
    );

    // Cloud Firestore root collection - strictly filtered for this user
    tasks.add(
      _firestore
          .collection('bookings')
          .where('userId', isEqualTo: user.uid)
          .limit(30)
          .get()
          .then((rootSnap) {
        for (final doc in rootSnap.docs) {
          final d = doc.data();
          final id = (d['id'] ?? doc.id).toString();
          final remoteBooking = OrderBooking(
            id: id,
            createdAt: (d['createdAt'] ?? 'Saved in Database').toString(),
            itemsSummary: (d['itemsSummary'] ?? 'Medicine Order').toString(),
            itemDetails: (d['itemDetails'] as List<dynamic>?)
                    ?.map((e) => e.toString())
                    .toList() ??
                [],
            deliverySlot:
                (d['deliverySlot'] ?? 'Standard Delivery').toString(),
            paymentMethod: (d['paymentMethod'] ?? 'UPI').toString(),
            address: (d['address'] ?? '').toString(),
            totalAmount: (d['totalAmount'] as num?)?.toDouble() ?? 0.0,
            status: (d['status'] ?? 'Processing').toString(),
          );
          if (!map.containsKey(id)) {
            map[id] = remoteBooking;
          } else if (map[id]!.status != 'Cancelled' && remoteBooking.status == 'Cancelled') {
            map[id] = remoteBooking;
          }
        }
      }).catchError((e) {
        debugPrint('Firestore root fetchBookings note: $e');
      }),
    );

    await Future.wait(tasks).timeout(const Duration(milliseconds: 2500), onTimeout: () => []);

    return map.values.toList();
  }

  Future<List<PrescriptionBooking>> fetchPrescriptionsFromFirebase() async {
    final user = _auth.currentUser;
    if (user == null) return [];
    final Map<String, PrescriptionBooking> map = {};

    // 0. Seed with cached prescriptions immediately (0ms)
    try {
      final cached = await MongoDbService.instance.getCachedPrescriptions(
        userId: user.uid,
        userEmail: user.email,
      );
      for (final p in cached) {
        map[p.id] = p;
      }
    } catch (_) {}

    // 1. Fetch concurrently from MongoDB Atlas and Cloud Firestore
    final tasks = <Future>[];

    // MongoDB Atlas
    tasks.add(
      MongoDbService.instance
          .fetchPrescriptions(userId: user.uid, userEmail: user.email)
          .then((mongoPrescriptions) {
        for (final p in mongoPrescriptions) {
          if (map.containsKey(p.id) && map[p.id]!.status == 'Cancelled') {
            p.status = 'Cancelled';
          }
          map[p.id] = p;
        }
      }).catchError((e) {
        debugPrint('MongoDB fetchPrescriptions note: $e');
      }),
    );

    // Cloud Firestore user subcollection
    tasks.add(
      _firestore
          .collection('users')
          .doc(user.uid)
          .collection('prescriptions')
          .orderBy('timestamp', descending: true)
          .limit(30)
          .get()
          .then((snap) {
        for (final doc in snap.docs) {
          final d = doc.data();
          final id = (d['id'] ?? doc.id).toString();
          final remoteRx = PrescriptionBooking(
            id: id,
            patientName: (d['patientName'] ?? 'Self').toString(),
            doctorName: (d['doctorName'] ?? 'Doctor').toString(),
            hospitalName: (d['hospitalName'] ?? 'Clinic').toString(),
            documentType: (d['documentType'] ?? 'Digital e-Rx').toString(),
            uploadedAt: (d['uploadedAt'] ?? 'Saved in Database').toString(),
            status: (d['status'] ?? 'Under Pharmacist Review').toString(),
            imagePath: d['imagePath']?.toString().isNotEmpty == true
                ? d['imagePath'].toString()
                : null,
          );
          if (!map.containsKey(id)) {
            map[id] = remoteRx;
          } else if (map[id]!.status != 'Cancelled' && remoteRx.status == 'Cancelled') {
            map[id] = remoteRx;
          }
        }
      }).catchError((e) {
        debugPrint('Firestore user fetchPrescriptions note: $e');
      }),
    );

    // Cloud Firestore root collection - strictly filtered for this user
    tasks.add(
      _firestore
          .collection('prescriptions')
          .where('userId', isEqualTo: user.uid)
          .limit(30)
          .get()
          .then((rootSnap) {
        for (final doc in rootSnap.docs) {
          final d = doc.data();
          final id = (d['id'] ?? doc.id).toString();
          final remoteRx = PrescriptionBooking(
            id: id,
            patientName: (d['patientName'] ?? 'Self').toString(),
            doctorName: (d['doctorName'] ?? 'Doctor').toString(),
            hospitalName: (d['hospitalName'] ?? 'Clinic').toString(),
            documentType: (d['documentType'] ?? 'Digital e-Rx').toString(),
            uploadedAt: (d['uploadedAt'] ?? 'Saved in Database').toString(),
            status: (d['status'] ?? 'Under Pharmacist Review').toString(),
            imagePath: d['imagePath']?.toString().isNotEmpty == true
                ? d['imagePath'].toString()
                : null,
          );
          if (!map.containsKey(id)) {
            map[id] = remoteRx;
          } else if (map[id]!.status != 'Cancelled' && remoteRx.status == 'Cancelled') {
            map[id] = remoteRx;
          }
        }
      }).catchError((e) {
        debugPrint('Firestore root fetchPrescriptions note: $e');
      }),
    );

    await Future.wait(tasks).timeout(const Duration(milliseconds: 2500), onTimeout: () => []);

    return map.values.toList();
  }

  Future<List<DoseReminder>> fetchRemindersFromFirebase() async {
    final user = _auth.currentUser;
    if (user == null) return [];
    final Map<String, DoseReminder> map = {};

    // 0. Seed with cached reminders immediately (0ms)
    try {
      final cached = await MongoDbService.instance.getCachedReminders(userId: user.uid);
      for (final r in cached) {
        map[r.id] = r;
      }
    } catch (_) {}

    // 1. Fetch concurrently from MongoDB Atlas and Cloud Firestore
    final tasks = <Future>[];

    // MongoDB Atlas
    tasks.add(
      MongoDbService.instance
          .fetchReminders(userId: user.uid)
          .then((mongoReminders) {
        for (final r in mongoReminders) {
          map[r.id] = r;
        }
      }).catchError((e) {
        debugPrint('MongoDB fetchReminders note: $e');
      }),
    );

    // Firestore user subcollection
    tasks.add(
      _firestore
          .collection('users')
          .doc(user.uid)
          .collection('reminders')
          .orderBy('timestamp', descending: false)
          .limit(30)
          .get()
          .then((snap) {
        for (final doc in snap.docs) {
          final d = doc.data();
          final id = (d['id'] ?? doc.id).toString();
          map[id] = DoseReminder(
            id: id,
            name: (d['name'] ?? 'Medicine').toString(),
            schedule: (d['schedule'] ?? '09:00 AM').toString(),
            dosage: (d['dosage'] ?? '1 Tablet').toString(),
            taken: d['taken'] == true,
          );
        }
      }).catchError((e) {
        debugPrint('Firestore fetchReminders note: $e');
      }),
    );

    // Firestore root reminders - strictly filtered for this user
    tasks.add(
      _firestore
          .collection('reminders')
          .where('userId', isEqualTo: user.uid)
          .limit(30)
          .get()
          .then((rootSnap) {
        for (final doc in rootSnap.docs) {
          final d = doc.data();
          final id = (d['id'] ?? doc.id).toString();
          if (!map.containsKey(id)) {
            map[id] = DoseReminder(
              id: id,
              name: (d['name'] ?? 'Medicine').toString(),
              schedule: (d['schedule'] ?? '09:00 AM').toString(),
              dosage: (d['dosage'] ?? '1 Tablet').toString(),
              taken: d['taken'] == true,
            );
          }
        }
      }).catchError((e) {
        debugPrint('Firestore root reminders fetch note: $e');
      }),
    );

    await Future.wait(tasks).timeout(const Duration(milliseconds: 2500), onTimeout: () => []);

    // Schedule background reminders for loaded reminders
    for (final reminder in map.values) {
      if (!reminder.taken) {
        scheduleReminderNotification(reminder).catchError((_) {});
      }
    }

    return map.values.toList();
  }

  // ---------------------------------------------------------------------------
  // Medicines Database Sync (MongoDB Atlas + Cloud Firestore)
  // ---------------------------------------------------------------------------
  Future<void> saveMedicineToFirebase(MedicineItem med) async {
    final data = <String, dynamic>{
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
      'updatedAt': FieldValue.serverTimestamp(),
    };

    final futures = <Future>[];

    futures.add(_firestore
        .collection('medicines')
        .doc(med.id)
        .set(data, SetOptions(merge: true))
        .timeout(const Duration(seconds: 4))
        .catchError((e) {
      debugPrint('Firestore saveMedicine note: $e');
    }));

    futures.add(MongoDbService.instance
        .saveMedicine(med)
        .catchError((e) {
      debugPrint('MongoDB saveMedicine note: $e');
      return false;
    }));

    await Future.wait(futures);
  }

  Future<List<MedicineItem>> fetchMedicinesFromFirebase() async {
    final Map<String, MedicineItem> map = {};

    // 0. Seed immediately with cached custom medicines
    try {
      final cached = await MongoDbService.instance.getCachedCustomMedicines();
      for (final m in cached) {
        map[m.id] = m;
      }
    } catch (_) {}

    // 1. Fetch concurrently from MongoDB Atlas and Cloud Firestore
    final tasks = <Future>[];

    tasks.add(
      MongoDbService.instance
          .fetchMedicines()
          .then((mongoMeds) {
        for (final m in mongoMeds) {
          map[m.id] = m;
        }
      }).catchError((e) {
        debugPrint('MongoDB fetchMedicines error: $e');
      }),
    );

    tasks.add(
      _firestore
          .collection('medicines')
          .limit(200)
          .get()
          .then((snap) {
        for (final doc in snap.docs) {
          final d = doc.data();
          final id = (d['id'] ?? doc.id).toString();
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
      }).catchError((e) {
        debugPrint('Firestore fetchMedicines note: $e');
      }),
    );

    await Future.wait(tasks).timeout(const Duration(milliseconds: 2500), onTimeout: () => []);

    return map.values.toList();
  }

  Future<void> seedMedicinesToDatabase(List<MedicineItem> medicines) async {
    // 1. Seed MongoDB Atlas
    MongoDbService.instance.seedMedicines(medicines).catchError((_) => 0);

    // 2. Seed Firebase Firestore
    try {
      final batch = _firestore.batch();
      for (final med in medicines.take(60)) {
        final ref = _firestore.collection('medicines').doc(med.id);
        batch.set(
          ref,
          {
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
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      }
      await batch.commit().timeout(const Duration(seconds: 4));
    } catch (e) {
      debugPrint('Firestore seedMedicines note: $e');
    }
  }
}
