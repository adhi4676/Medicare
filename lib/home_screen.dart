import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'app_theme.dart';
import 'auth_service.dart';
import 'booking_notification_service.dart';
import 'medicine_booking_screens.dart';
import 'medicine_catalog_data.dart';
import 'mongodb_service.dart';
import 'profile_personalization_view.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _auth = AuthService.instance;
  final _notifService = BookingNotificationService.instance;

  int _selectedIndex = 0;
  String _searchQuery = '';
  String _selectedCategory = 'All';
  final TextEditingController _searchCtrl = TextEditingController();

  bool _biometricAvailable = false;
  bool _biometricEnabled = false;

  final List<CartItem> _cart = [];

  final List<DoseReminder> _reminders = [];
  final List<OrderBooking> _orders = [];
  final List<PrescriptionBooking> _prescriptions = [];

  List<MedicineItem> _medicines = List.of(_initialMedicines);
  bool _isLoadingMedicines = false;
  bool _isLoadingOrders = false;
  bool _isLoadingPrescriptions = false;

  static const List<MedicineItem> _initialMedicines = initialMedicinesCatalog;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _openAddNewMedicineDialog() async {
    final nameCtrl = TextEditingController();
    final mfgCtrl = TextEditingController();
    final compCtrl = TextEditingController();
    final priceCtrl = TextEditingController();
    final packCtrl = TextEditingController(text: 'Strip of 10 tablets');
    final guideCtrl = TextEditingController(text: 'Take as directed by doctor.');
    String category = 'Pain Relief';
    bool rxRequired = false;
    final formKey = GlobalKey<FormState>();

    const availableCategories = [
      'Pain Relief',
      'Antibiotics',
      'Vitamins',
      'Diabetes',
      'Cardiac & BP',
      'Cough & Cold',
      'Gastro & Acidity',
      'Skin & Care',
      'First Aid',
      'Eye & Ear Care',
      'Respiratory',
    ];

    final created = await showDialog<MedicineItem>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.medication_rounded, color: AppTheme.primary),
                  SizedBox(width: 8),
                  Text('Add New Medicine'),
                ],
              ),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Form(
                  key: formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextFormField(
                          controller: nameCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Medicine Name & Strength',
                            hintText: 'e.g. Paracetamol 500mg',
                            prefixIcon: Icon(Icons.title_rounded),
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Enter medicine name'
                              : null,
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: category,
                          decoration: const InputDecoration(
                            labelText: 'Category',
                            prefixIcon: Icon(Icons.category_rounded),
                          ),
                          items: availableCategories
                              .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                              .toList(),
                          onChanged: (v) {
                            if (v != null) setDialogState(() => category = v);
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: mfgCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Manufacturer / Brand',
                            hintText: 'e.g. Cipla, Sun Pharma, Abbott',
                            prefixIcon: Icon(Icons.business_rounded),
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Enter manufacturer'
                              : null,
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: priceCtrl,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: const InputDecoration(
                                  labelText: 'Price (₹)',
                                  prefixIcon: Icon(Icons.currency_rupee_rounded),
                                ),
                                validator: (v) {
                                  if (v == null || double.tryParse(v) == null || double.parse(v) <= 0) {
                                    return 'Enter valid price';
                                  }
                                  return null;
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextFormField(
                                controller: packCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'Pack Size',
                                  hintText: 'e.g. Strip of 10 / Bottle 100ml',
                                ),
                                validator: (v) => (v == null || v.trim().isEmpty)
                                    ? 'Enter pack size'
                                    : null,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: compCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Active Salt / Composition',
                            hintText: 'e.g. Paracetamol IP 500mg',
                            prefixIcon: Icon(Icons.science_outlined),
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Enter active ingredients'
                              : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: guideCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Usage Guide / Directions',
                            prefixIcon: Icon(Icons.info_outline_rounded),
                          ),
                        ),
                        const SizedBox(height: 8),
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Requires Doctor Prescription (Rx)'),
                          value: rxRequired,
                          onChanged: (v) =>
                              setDialogState(() => rxRequired = v ?? false),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton.icon(
                  onPressed: () {
                    if (!formKey.currentState!.validate()) return;
                    final price = double.tryParse(priceCtrl.text.trim()) ?? 99.0;
                    final med = MedicineItem(
                      id: 'med-${DateTime.now().millisecondsSinceEpoch}',
                      name: nameCtrl.text.trim(),
                      category: category,
                      manufacturer: mfgCtrl.text.trim(),
                      packSize: packCtrl.text.trim(),
                      priceValue: price,
                      composition: compCtrl.text.trim(),
                      usageGuide: guideCtrl.text.trim().isNotEmpty
                          ? guideCtrl.text.trim()
                          : 'Take as directed by doctor.',
                      inStock: true,
                      requiresRx: rxRequired,
                    );
                    Navigator.of(ctx).pop(med);
                  },
                  icon: const Icon(Icons.save_rounded, size: 18),
                  label: const Text('Save to Database'),
                ),
              ],
            );
          },
        );
      },
    );

    if (created != null && mounted) {
      setState(() {
        _medicines.removeWhere((m) => m.id == created.id);
        _medicines.insert(0, created);
        _selectedCategory = 'All';
        _searchCtrl.clear();
        _searchQuery = '';
      });
      await _notifService.saveMedicineToFirebase(created);
      _showToast('✅ Saved "${created.name}" to Database! Showing at top of catalog.');
    }
  }

  @override
  void initState() {
    super.initState();
    ProfilePersonalizationService.instance.loadProfile();
    _loadBiometricState();
    _loadDatabaseData();
  }

  Future<void> _loadBiometricState() async {
    final available = await _auth.isBiometricAvailable();
    final enabled = await _auth.isBiometricEnabled();
    if (!mounted) return;
    setState(() {
      _biometricAvailable = available;
      _biometricEnabled = enabled;
    });
  }

  Future<void> _loadDatabaseData() async {
    if (!mounted) return;
    setState(() {
      _isLoadingMedicines = true;
      _isLoadingOrders = _orders.isEmpty;
      _isLoadingPrescriptions = _prescriptions.isEmpty;
    });

    // 0. Instantly hydrate cached dynamic records from device secure storage (0 ms)
    try {
      final user = _auth.currentUser;
      final cachedCustomMeds =
          await MongoDbService.instance.getCachedCustomMedicines();
      final cachedBookings = await MongoDbService.instance.getCachedBookings(
        userId: user?.uid,
        userEmail: user?.email,
      );
      final cachedPrescriptions = await MongoDbService.instance.getCachedPrescriptions(
        userId: user?.uid,
        userEmail: user?.email,
      );
      final cachedReminders = await MongoDbService.instance.getCachedReminders(
        userId: user?.uid,
      );

      if (mounted) {
        setState(() {
          if (cachedCustomMeds.isNotEmpty) {
            final customIds = cachedCustomMeds.map((m) => m.id).toSet();
            _medicines = [
              ...cachedCustomMeds,
              ..._initialMedicines.where((m) => !customIds.contains(m.id)),
            ];
            _isLoadingMedicines = false;
          }
          _orders.clear();
          _orders.addAll(cachedBookings);
          _isLoadingOrders = false;

          _prescriptions.clear();
          _prescriptions.addAll(cachedPrescriptions);
          _isLoadingPrescriptions = false;

          _reminders.clear();
          _reminders.addAll(cachedReminders);
        });
      }
    } catch (_) {}

    try {
      MongoDbService.instance.connect().catchError((_) => false);

      // Run all fetches in parallel so data hydrates in milliseconds
      final fMedicines = _notifService
          .fetchMedicinesFromFirebase()
          .timeout(const Duration(seconds: 4), onTimeout: () => [])
          .then((remoteMeds) {
        if (remoteMeds.isNotEmpty && mounted) {
          setState(() {
            final initialIds = _initialMedicines.map((m) => m.id).toSet();
            final customMeds =
                remoteMeds.where((m) => !initialIds.contains(m.id)).toList();

            final Map<String, MedicineItem> map = {};
            // Custom user-added medicines are placed FIRST at the top!
            for (final m in customMeds) {
              map[m.id] = m;
            }
            for (final m in _initialMedicines) {
              if (!map.containsKey(m.id)) {
                map[m.id] = m;
              }
            }
            for (final m in remoteMeds) {
              if (!map.containsKey(m.id)) {
                map[m.id] = m;
              }
            }
            _medicines = map.values.toList();
          });
        }
      }).whenComplete(() {
        if (mounted) setState(() => _isLoadingMedicines = false);
      });

      final fBookings = _notifService
          .fetchBookingsFromFirebase()
          .timeout(const Duration(seconds: 4), onTimeout: () => [])
          .then((remoteBookings) {
        if (mounted) {
          setState(() {
            _orders.clear();
            _orders.addAll(remoteBookings);
          });
        }
      }).whenComplete(() {
        if (mounted) setState(() => _isLoadingOrders = false);
      });

      final fPrescriptions = _notifService
          .fetchPrescriptionsFromFirebase()
          .timeout(const Duration(seconds: 4), onTimeout: () => [])
          .then((remotePrescriptions) {
        if (mounted) {
          setState(() {
            _prescriptions.clear();
            _prescriptions.addAll(remotePrescriptions);
          });
        }
      }).whenComplete(() {
        if (mounted) setState(() => _isLoadingPrescriptions = false);
      });

      final fReminders = _notifService
          .fetchRemindersFromFirebase()
          .timeout(const Duration(seconds: 4), onTimeout: () => [])
          .then((remoteReminders) {
        if (mounted) {
          setState(() {
            _reminders.clear();
            _reminders.addAll(remoteReminders);
          });
        }
      });

      await Future.wait([fMedicines, fBookings, fPrescriptions, fReminders]);
    } catch (e) {
      debugPrint('Error loading database data: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingMedicines = false;
          _isLoadingOrders = false;
          _isLoadingPrescriptions = false;
        });
      }
    }
  }

  Future<void> _toggleBiometric(bool value) async {
    if (value) {
      final ok = await _auth.authenticateWithBiometrics();
      if (!ok) return;
    }
    await _auth.setBiometricEnabled(value);
    if (mounted) setState(() => _biometricEnabled = value);
  }

  int get _cartCount => _cart.fold(0, (sum, item) => sum + item.quantity);

  void _addToCart(MedicineItem medicine, {int quantity = 1}) {
    setState(() {
      final existingIdx =
          _cart.indexWhere((c) => c.medicine.id == medicine.id);
      if (existingIdx >= 0) {
        _cart[existingIdx].quantity += quantity;
      } else {
        _cart.add(CartItem(medicine: medicine, quantity: quantity));
      }
    });
    _showToast('Added $quantity × ${medicine.name} to cart');
  }

  Future<void> _openMedicineDetails(MedicineItem medicine) async {
    final result = await Navigator.of(context).push<MedicineDetailResult>(
      AppTheme.route(MedicineDetailScreen(medicine: medicine)),
    );
    if (result == null || !mounted) return;
    _addToCart(result.medicine, quantity: result.quantity);
    if (result.buyNow) {
      await _openCartCheckout();
    }
  }

  Future<void> _openCartCheckout() async {
    final newBooking = await Navigator.of(context).push<OrderBooking>(
      AppTheme.route(CartCheckoutScreen(initialItems: _cart)),
    );
    if (newBooking == null || !mounted) return;
    setState(() {
      _orders.insert(0, newBooking);
      _cart.clear();
      _selectedIndex = 3; // Navigate to Orders & Care tab to view booking
    });
    _showToast(
      '✅ Booking #${newBooking.id} saved to Firebase & notification sent!',
    );
  }

  Future<void> _confirmCancelOrder(OrderBooking order) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Cancel Order #${order.id}?'),
        content: Text(
          'Are you sure you want to cancel your booking for "${order.itemsSummary}"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep Order'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              minimumSize: const Size(120, 42),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Cancel Booking'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      setState(() => order.status = 'Cancelled');
      await _notifService.updateBookingStatusInFirebase(order.id, 'Cancelled');
      _showToast('Order #${order.id} cancelled in Firebase');
    }
  }

  void _showOrderDetailsSheet(OrderBooking order) {
    Navigator.of(context).push(
      AppTheme.route<void>(BookingConfirmationScreen(booking: order)),
    );
  }

  void _showNotificationsSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final theme = Theme.of(ctx);
            final history = _notifService.notificationHistory;
            return Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
              child: ConstrainedBox(
                constraints:
                    const BoxConstraints(maxWidth: 600, maxHeight: 520),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.notifications_active_rounded,
                              color: AppTheme.primary,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Mobile Notifications (${history.length})',
                              style: theme.textTheme.headlineSmall,
                            ),
                          ],
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Real-time alerts for your medicine bookings and medication dose schedules:',
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 12),
                    if (history.isNotEmpty)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton.icon(
                            onPressed: () {
                              _notifService.clearHistory();
                              setSheetState(() {});
                              setState(() {});
                            },
                            icon: const Icon(Icons.clear_all_rounded, size: 18),
                            label: const Text('Clear History'),
                          ),
                        ],
                      ),
                    const Divider(height: 20),
                    if (history.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 40),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.notifications_none_rounded,
                                size: 48,
                                color: theme.colorScheme.outline,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'No Notifications Yet',
                                style: theme.textTheme.titleMedium,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Real-time alerts will appear here when you place orders or schedule dose reminders.',
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodyMedium,
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      Expanded(
                        child: ListView.separated(
                          itemCount: history.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, idx) {
                            final item = history[idx];
                            final isBooking = item.type == 'booking';
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: CircleAvatar(
                                backgroundColor: (isBooking
                                        ? AppTheme.accentGreen
                                        : AppTheme.accentOrange)
                                    .withValues(alpha: 0.14),
                                child: Icon(
                                  isBooking
                                      ? Icons.check_circle_outline
                                      : Icons.alarm_rounded,
                                  color: isBooking
                                      ? AppTheme.accentGreen
                                      : AppTheme.accentOrange,
                                ),
                              ),
                              title: Text(
                                item.title,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700),
                              ),
                              subtitle: Text('${item.body}\n${item.timestamp}'),
                              isThreeLine: true,
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _openAddPrescriptionDialog() async {
    final doctorCtrl = TextEditingController();
    final clinicCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    String docType = 'Photo Prescription';
    String? pickedImagePath;
    final picker = ImagePicker();

    final created = await showDialog<PrescriptionBooking>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.receipt_long_rounded, color: AppTheme.primary),
                  SizedBox(width: 10),
                  Text('Upload Prescription'),
                ],
              ),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Form(
                  key: formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextFormField(
                          controller: doctorCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Prescribing Doctor Name',
                            prefixIcon: Icon(Icons.medical_information_outlined),
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Enter the doctor name'
                              : null,
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: clinicCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Hospital / Clinic Name',
                            prefixIcon: Icon(Icons.local_hospital_outlined),
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Enter hospital or clinic name'
                              : null,
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Prescription Photo / Scan:',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (pickedImagePath != null) ...[
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Stack(
                              alignment: Alignment.topRight,
                              children: [
                                Container(
                                  height: 160,
                                  width: double.infinity,
                                  color: Colors.black12,
                                  child: kIsWeb
                                      ? Image.network(pickedImagePath!,
                                          fit: BoxFit.cover)
                                      : Image.file(File(pickedImagePath!),
                                          fit: BoxFit.cover),
                                ),
                                IconButton.filled(
                                  style: IconButton.styleFrom(
                                    backgroundColor: Colors.black54,
                                  ),
                                  icon: const Icon(Icons.close,
                                      color: Colors.white, size: 18),
                                  onPressed: () {
                                    setModalState(() => pickedImagePath = null);
                                  },
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                        ],
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                ),
                                icon: const Icon(Icons.camera_alt_outlined),
                                label: const Text('Take Photo'),
                                onPressed: () async {
                                  try {
                                    final img = await picker.pickImage(
                                      source: ImageSource.camera,
                                      maxWidth: 1600,
                                      maxHeight: 1600,
                                      imageQuality: 85,
                                    );
                                    if (img != null) {
                                      setModalState(() {
                                        pickedImagePath = img.path;
                                        docType = 'Camera Capture (Photo)';
                                      });
                                    }
                                  } catch (e) {
                                    debugPrint('Camera picker note: $e');
                                  }
                                },
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                ),
                                icon: const Icon(Icons.photo_library_outlined),
                                label: const Text('Gallery'),
                                onPressed: () async {
                                  try {
                                    final img = await picker.pickImage(
                                      source: ImageSource.gallery,
                                      maxWidth: 1600,
                                      maxHeight: 1600,
                                      imageQuality: 85,
                                    );
                                    if (img != null) {
                                      setModalState(() {
                                        pickedImagePath = img.path;
                                        docType = 'Gallery Upload (Photo)';
                                      });
                                    }
                                  } catch (e) {
                                    debugPrint('Gallery picker note: $e');
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(140, 44),
                  ),
                  onPressed: () {
                    if (!formKey.currentState!.validate()) return;
                    final rxId =
                        'RX-${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}';
                    Navigator.of(ctx).pop(
                      PrescriptionBooking(
                        id: rxId,
                        patientName:
                            _auth.currentUser?.displayName ?? 'Self',
                        doctorName: doctorCtrl.text.trim(),
                        hospitalName: clinicCtrl.text.trim(),
                        documentType: docType,
                        uploadedAt: 'Just now',
                        status: 'Under Pharmacist Review',
                        imagePath: pickedImagePath,
                      ),
                    );
                  },
                  icon: const Icon(Icons.cloud_upload_outlined, size: 18),
                  label: const Text('Submit & Book'),
                ),
              ],
            );
          },
        );
      },
    );

    if (created != null && mounted) {
      setState(() => _prescriptions.insert(0, created));
      await _notifService.savePrescriptionToFirebase(created);
      await _notifService.showPrescriptionNotification(created);
      _showToast(
        '✅ Prescription #${created.id} saved in Database & notification sent!',
      );
    }
  }

  Future<void> _openAddReminderDialog() async {
    final nameCtrl = TextEditingController();
    final dosageCtrl = TextEditingController(text: '1 Tablet');
    TimeOfDay selectedTime = const TimeOfDay(hour: 9, minute: 0);
    String mealInstruction = 'After Meal';
    final formKey = GlobalKey<FormState>();

    const mealOptions = [
      'After Meal',
      'Before Meal',
      'With Meal',
      'At Bedtime',
      'Empty Stomach',
    ];

    final created = await showDialog<DoseReminder>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final period =
                selectedTime.period == DayPeriod.am ? 'AM' : 'PM';
            final hour = selectedTime.hourOfPeriod == 0
                ? 12
                : selectedTime.hourOfPeriod;
            final minute = selectedTime.minute.toString().padLeft(2, '0');
            final formattedTime =
                '${hour.toString().padLeft(2, '0')}:$minute $period';

            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.alarm_add_rounded, color: AppTheme.accentOrange),
                  SizedBox(width: 10),
                  Text('Set Dose Reminder'),
                ],
              ),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Form(
                  key: formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextFormField(
                          controller: nameCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Medicine Name',
                            prefixIcon: Icon(Icons.medication_outlined),
                            hintText: 'e.g. Paracetamol 650',
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Enter medicine name'
                              : null,
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: dosageCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Dosage',
                            prefixIcon: Icon(Icons.scale_outlined),
                            hintText: 'e.g. 1 Tablet, 5ml, 2 Drops',
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Enter dosage'
                              : null,
                        ),
                        const SizedBox(height: 18),
                        const Text(
                          'Reminder Time:',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 8),
                        InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () async {
                            final picked = await showTimePicker(
                              context: ctx,
                              initialTime: selectedTime,
                            );
                            if (picked != null) {
                              setModalState(() => selectedTime = picked);
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: Theme.of(ctx).dividerColor,
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.access_time_filled_rounded,
                                  color: AppTheme.accentOrange,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    formattedTime,
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                const Text(
                                  'Change Time',
                                  style: TextStyle(
                                    color: AppTheme.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        const Text(
                          'Meal Timing Instruction:',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: mealOptions.map((opt) {
                            final isSel = mealInstruction == opt;
                            return ChoiceChip(
                              label: Text(opt),
                              selected: isSel,
                              onSelected: (selected) {
                                if (selected) {
                                  setModalState(() => mealInstruction = opt);
                                }
                              },
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(160, 44),
                  ),
                  onPressed: () {
                    if (!formKey.currentState!.validate()) return;
                    final fullSchedule = '$formattedTime • $mealInstruction';
                    Navigator.of(ctx).pop(
                      DoseReminder(
                        id: 'rem-${DateTime.now().millisecondsSinceEpoch}',
                        name: nameCtrl.text.trim(),
                        schedule: fullSchedule,
                        dosage: dosageCtrl.text.trim(),
                        taken: false,
                      ),
                    );
                  },
                  icon: const Icon(Icons.alarm_on_rounded, size: 18),
                  label: const Text('Save & Schedule'),
                ),
              ],
            );
          },
        );
      },
    );

    if (created != null && mounted) {
      setState(() => _reminders.add(created));
      await _notifService.saveReminderToFirebase(created);
      await _notifService.scheduleReminderNotification(created);
      _showToast(
        '⏰ Reminder for ${created.name} scheduled at ${created.schedule} & saved!',
      );
    }
  }

  Future<void> _handleSignOut() async {
    Navigator.of(context).popUntil((route) => route.isFirst);
    setState(() {
      _orders.clear();
      _prescriptions.clear();
      _reminders.clear();
    });
    _notifService.clearHistory();
    MongoDbService.instance.clearMemoryCache();
    await _auth.signOut();
  }

  void _showToast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: AppTheme.primaryDark,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final user = _auth.currentUser;
    final name = user?.displayName?.trim();
    final greeting = (name != null && name.isNotEmpty)
        ? name.split(' ').first
        : (user?.email?.split('@').first ?? user?.phoneNumber ?? 'Patient');

    return PopScope(
      canPop: _selectedIndex == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _selectedIndex != 0) {
          setState(() => _selectedIndex = 0);
        }
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 860;

          return Scaffold(
            appBar: AppBar(
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.medical_services_rounded,
                      color: AppTheme.primary,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Text('MediCare'),
                ],
              ),
              actions: [
                const ThemeModeToggleButton(),
                ListenableBuilder(
                  listenable: MongoDbService.instance,
                  builder: (context, _) {
                    final connected = MongoDbService.instance.isConnected;
                    return IconButton(
                      tooltip: connected
                          ? 'MongoDB Atlas: Connected'
                          : 'MongoDB Atlas: Disconnected (Tap to Configure)',
                      icon: Badge(
                        backgroundColor: connected
                            ? AppTheme.accentGreen
                            : Colors.amber.shade700,
                        smallSize: 8,
                        child: const Icon(Icons.storage_rounded),
                      ),
                      onPressed: () {
                        setState(() => _selectedIndex = 4);
                      },
                    );
                  },
                ),
                IconButton(
                  tooltip: 'Cart & Booking',
                  icon: Badge(
                    isLabelVisible: _cartCount > 0,
                    label: Text('$_cartCount'),
                    child: const Icon(Icons.shopping_cart_outlined),
                  ),
                  onPressed: _openCartCheckout,
                ),
                IconButton(
                  tooltip: 'Mobile Notifications',
                  icon: Badge(
                    isLabelVisible:
                        _notifService.notificationHistory.isNotEmpty,
                    label: Text('${_notifService.notificationHistory.length}'),
                    child: const Icon(Icons.notifications_active_outlined),
                  ),
                  onPressed: _showNotificationsSheet,
                ),
                const SizedBox(width: 4),
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: TextButton.icon(
                    onPressed: _handleSignOut,
                    icon: const Icon(Icons.logout_rounded, size: 18),
                    label: const Text('Logout'),
                  ),
                ),
              ],
            ),
            floatingActionButton: _cartCount > 0
                ? FloatingActionButton.extended(
                    onPressed: _openCartCheckout,
                    backgroundColor: AppTheme.primaryDark,
                    foregroundColor: Colors.white,
                    icon: const Icon(Icons.shopping_bag_outlined),
                    label: Text('Checkout ($_cartCount)'),
                  )
                : null,
            bottomNavigationBar: isWide
                ? null
                : NavigationBar(
                    selectedIndex: _selectedIndex,
                    onDestinationSelected: (idx) =>
                        setState(() => _selectedIndex = idx),
                    destinations: const [
                      NavigationDestination(
                        icon: Icon(Icons.dashboard_outlined),
                        selectedIcon: Icon(Icons.dashboard_rounded),
                        label: 'Home',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.search_outlined),
                        selectedIcon: Icon(Icons.search_rounded),
                        label: 'Medicines',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.upload_file_outlined),
                        selectedIcon: Icon(Icons.upload_file_rounded),
                        label: 'Rx Upload',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.alarm_outlined),
                        selectedIcon: Icon(Icons.alarm_rounded),
                        label: 'Care & Orders',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.person_outline_rounded),
                        selectedIcon: Icon(Icons.person_rounded),
                        label: 'Profile',
                      ),
                    ],
                  ),
            body: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isWide)
                  NavigationRail(
                    selectedIndex: _selectedIndex,
                    onDestinationSelected: (idx) =>
                        setState(() => _selectedIndex = idx),
                    extended: constraints.maxWidth >= 1120,
                    minWidth: 80,
                    minExtendedWidth: 220,
                    leading: const SizedBox(height: 8),
                    destinations: const [
                      NavigationRailDestination(
                        icon: Icon(Icons.dashboard_outlined),
                        selectedIcon: Icon(Icons.dashboard_rounded),
                        label: Text('Dashboard'),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.search_outlined),
                        selectedIcon: Icon(Icons.search_rounded),
                        label: Text('Medicine Search'),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.upload_file_outlined),
                        selectedIcon: Icon(Icons.upload_file_rounded),
                        label: Text('Prescriptions'),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.alarm_outlined),
                        selectedIcon: Icon(Icons.alarm_rounded),
                        label: Text('Reminders & Orders'),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.person_outline_rounded),
                        selectedIcon: Icon(Icons.person_rounded),
                        label: Text('Profile & Security'),
                      ),
                    ],
                  ),
                if (isWide)
                  VerticalDivider(
                    width: 1,
                    thickness: 1,
                    color: Theme.of(context).dividerColor,
                  ),
                Expanded(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1160),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        transitionBuilder: (child, animation) {
                          final slide = Tween<Offset>(
                            begin: const Offset(0, 0.03),
                            end: Offset.zero,
                          ).animate(animation);
                          return FadeTransition(
                            opacity: animation,
                            child: SlideTransition(
                              position: slide,
                              child: child,
                            ),
                          );
                        },
                        child: _buildSelectedPage(greeting, isWide),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildSelectedPage(String greeting, bool isWide) {
    switch (_selectedIndex) {
      case 0:
        return _buildDashboardView(greeting, isWide);
      case 1:
        return _buildMedicineSearchView(isWide);
      case 2:
        return _buildPrescriptionUploadView(isWide);
      case 3:
        return _buildRemindersAndOrdersView(isWide);
      case 4:
        return _buildProfileView();
      default:
        return _buildDashboardView(greeting, isWide);
    }
  }

  // ---------------------------------------------------------------------------
  // 0. Dashboard View
  // ---------------------------------------------------------------------------
  Widget _buildDashboardView(String greeting, bool isWide) {
    final theme = Theme.of(context);
    final actions = <_QuickAction>[
      _QuickAction(
        'Medicine Search',
        'Browse & book meds',
        Icons.search_rounded,
        AppTheme.primary,
        () => setState(() => _selectedIndex = 1),
      ),
      _QuickAction(
        'Prescription Upload',
        'Book via doctor Rx',
        Icons.upload_file_rounded,
        AppTheme.accentPurple,
        () => setState(() => _selectedIndex = 2),
      ),
      _QuickAction(
        'Dose Reminders',
        'Manage daily schedule',
        Icons.alarm_rounded,
        AppTheme.accentOrange,
        () => setState(() => _selectedIndex = 3),
      ),
      _QuickAction(
        'My Bookings',
        'View or cancel orders',
        Icons.local_shipping_rounded,
        AppTheme.accentGreen,
        () => setState(() => _selectedIndex = 3),
      ),
      _QuickAction(
        'Notifications',
        'Booking & dose alerts',
        Icons.notifications_active_rounded,
        AppTheme.secondary,
        _showNotificationsSheet,
      ),
    ];

    return ListView(
      key: const ValueKey('page-dashboard'),
      padding: EdgeInsets.all(isWide ? 28 : 20),
      children: [
        // Hero Banner
        StaggeredFadeSlide(
          index: 0,
          child: Container(
            padding: EdgeInsets.all(isWide ? 28 : 22),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppTheme.currentPreset.primary,
                  AppTheme.currentPreset.primaryDark,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.currentPreset.primary.withValues(alpha: 0.25),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 20,
              runSpacing: 16,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 540),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          'MEDICARE HEALTH PORTAL',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.9,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Hello, $greeting 👋',
                        style: theme.textTheme.headlineMedium?.copyWith(
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Browse medicines, book instant pharmacy deliveries saved in Firebase, and receive live mobile dose reminders.',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.88),
                          fontSize: 14,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: AppTheme.currentPreset.primaryDark,
                        minimumSize: const Size(170, 48),
                      ),
                      onPressed: () => setState(() => _selectedIndex = 1),
                      icon: const Icon(Icons.medication_outlined),
                      label: const Text('Order Medicines'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),

        // Quick Actions Section
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Quick Actions', style: theme.textTheme.titleLarge),
            TextButton(
              onPressed: () => setState(() => _selectedIndex = 1),
              child: const Text('Browse All Medicines →'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, gridConstraints) {
            final width = gridConstraints.maxWidth;
            final cols = width >= 900
                ? 5
                : width >= 600
                    ? 3
                    : 2;
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: actions.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: cols,
                mainAxisSpacing: 14,
                crossAxisSpacing: 14,
                mainAxisExtent: 148,
              ),
              itemBuilder: (context, index) => StaggeredFadeSlide(
                index: index + 1,
                child: _ActionCard(action: actions[index]),
              ),
            );
          },
        ),
        const SizedBox(height: 28),

        // Responsive Split: Today's Reminders + Active Order & Security
        if (isWide)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 6, child: _buildRemindersSummaryCard(theme)),
              const SizedBox(width: 20),
              Expanded(flex: 5, child: _buildOrderAndSecurityColumn(theme)),
            ],
          )
        else ...[
          _buildRemindersSummaryCard(theme),
          const SizedBox(height: 20),
          _buildOrderAndSecurityColumn(theme),
        ],
      ],
    );
  }

  Widget _buildRemindersSummaryCard(ThemeData theme) {
    final completedCount = _reminders.where((r) => r.taken).length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.medication_liquid_rounded,
                        color: AppTheme.accentOrange),
                    const SizedBox(width: 8),
                    Text("Today's Dose Schedule",
                        style: theme.textTheme.titleLarge),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.accentGreen.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '$completedCount / ${_reminders.length} Taken',
                        style: const TextStyle(
                          color: AppTheme.accentGreen,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton.icon(
                      onPressed: _openAddReminderDialog,
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Add'),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (_reminders.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'No dose reminders scheduled yet. Tap "+ Add" to create one.',
                  style: theme.textTheme.bodyMedium,
                ),
              )
            else
              ..._reminders.map(
                (reminder) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Checkbox(
                    activeColor: AppTheme.accentGreen,
                    value: reminder.taken,
                    onChanged: (v) async {
                      setState(() => reminder.taken = v ?? false);
                      await _notifService.saveReminderToFirebase(reminder);
                    },
                  ),
                  title: Text(
                    reminder.name,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      decoration:
                          reminder.taken ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  subtitle: Text('${reminder.schedule} • ${reminder.dosage}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Send mobile reminder notification now',
                        icon: const Icon(
                          Icons.notifications_active_outlined,
                          size: 20,
                          color: AppTheme.accentOrange,
                        ),
                        onPressed: () async {
                          await _notifService
                              .showReminderNotification(reminder);
                          setState(() {});
                          _showToast(
                            '⏰ Sent mobile reminder for ${reminder.name}',
                          );
                        },
                      ),
                      IconButton(
                        tooltip: 'Delete reminder',
                        icon: const Icon(Icons.delete_outline, size: 20),
                        onPressed: () async {
                          setState(
                            () => _reminders
                                .removeWhere((r) => r.id == reminder.id),
                          );
                          await _notifService
                              .deleteReminderFromFirebase(reminder.id);
                          _showToast('Removed ${reminder.name} reminder');
                        },
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderAndSecurityColumn(ThemeData theme) {
    final hasOrders = _orders.isNotEmpty;
    final activeOrder = hasOrders
        ? _orders.firstWhere(
            (o) => o.canCancel,
            orElse: () => _orders.first,
          )
        : null;

    return Column(
      children: [
        if (activeOrder != null)
          Card(
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () => _showOrderDetailsSheet(activeOrder),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.local_shipping_outlined,
                                color: AppTheme.accentGreen),
                            const SizedBox(width: 8),
                            Text('Booking #${activeOrder.id}',
                                style: theme.textTheme.titleMedium),
                          ],
                        ),
                        _OrderStatusBadge(status: activeOrder.status),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${activeOrder.itemsSummary} • ${activeOrder.deliverySlot}',
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 14),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: activeOrder.status == 'Delivered'
                            ? 1.0
                            : activeOrder.status == 'Cancelled'
                                ? 0.0
                                : 0.7,
                        minHeight: 8,
                        color: activeOrder.status == 'Cancelled'
                            ? Colors.redAccent
                            : AppTheme.accentGreen,
                        backgroundColor: AppTheme.isDark(context)
                            ? AppTheme.darkSurfaceElevated
                            : const Color(0xFFE2E8F0),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      children: [
                        TextButton(
                          onPressed: () => _showOrderDetailsSheet(activeOrder),
                          child: const Text('Confirmation Screen'),
                        ),
                        if (activeOrder.canCancel)
                          TextButton(
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.red.shade700,
                            ),
                            onPressed: () => _confirmCancelOrder(activeOrder),
                            child: const Text('Cancel Booking'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.shopping_bag_outlined,
                          color: AppTheme.primary),
                      const SizedBox(width: 8),
                      Text('No Active Bookings',
                          style: theme.textTheme.titleMedium),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'You currently have no active orders. Browse our catalog and book genuine medicines anytime.',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: () => setState(() => _selectedIndex = 1),
                    icon: const Icon(Icons.search, size: 18),
                    label: const Text('Browse Medicines'),
                  ),
                ],
              ),
            ),
          ),
        if (_biometricAvailable) ...[
          const SizedBox(height: 16),
          Card(
            child: SwitchListTile(
              secondary:
                  const Icon(Icons.fingerprint, color: AppTheme.primary),
              title: const Text(
                'Biometric unlock',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle:
                  const Text('Use fingerprint or face to open MediCare'),
              value: _biometricEnabled,
              onChanged: _toggleBiometric,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildMedicineSearchView(bool isWide) {
    final theme = Theme.of(context);
    const categories = [
      'All',
      'Pain Relief',
      'Antibiotics',
      'Vitamins',
      'Diabetes',
      'Cardiac & BP',
      'Cough & Cold',
      'Gastro & Acidity',
      'Skin & Care',
      'First Aid',
      'Eye & Ear Care',
      'Respiratory',
    ];

    final filtered = _medicines.where((m) {
      final matchesCat =
          _selectedCategory == 'All' || m.category == _selectedCategory;
      final q = _searchQuery.toLowerCase();
      final matchesQuery = q.isEmpty ||
          m.name.toLowerCase().contains(q) ||
          m.composition.toLowerCase().contains(q) ||
          m.manufacturer.toLowerCase().contains(q);
      return matchesCat && matchesQuery;
    }).toList();

    return CustomScrollView(
      key: const ValueKey('page-search'),
      slivers: [
        SliverPadding(
          padding: EdgeInsets.all(isWide ? 28 : 20),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Medicine Catalog (${filtered.length})',
                          style: theme.textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Tap any medicine to view details, select quantity, or book delivery.',
                          style: theme.textTheme.bodyMedium,
                        ),
                      ],
                    ),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        FilledButton.tonalIcon(
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(150, 46),
                          ),
                          onPressed: _openAddNewMedicineDialog,
                          icon: const Icon(Icons.add_circle_outline, size: 18),
                          label: const Text('Add Medicine'),
                        ),
                        if (_cartCount > 0)
                          FilledButton.icon(
                            style: FilledButton.styleFrom(
                              minimumSize: const Size(170, 46),
                            ),
                            onPressed: _openCartCheckout,
                            icon: const Icon(Icons.shopping_cart_checkout_rounded),
                            label: Text('Book Cart ($_cartCount)'),
                          ),
                      ],
                    ),
                  ],
                ),
                if (_isLoadingMedicines) ...[
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(minHeight: 2),
                ],
                const SizedBox(height: 18),
                TextField(
                  controller: _searchCtrl,
                  onChanged: (v) => setState(() => _searchQuery = v),
                  decoration: InputDecoration(
                    hintText:
                        'Search 550+ medicines by name, salt, or manufacturer...',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: categories.map((cat) {
                    final selected = _selectedCategory == cat;
                    return FilterChip(
                      label: Text(cat),
                      selected: selected,
                      onSelected: (_) => setState(() => _selectedCategory = cat),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
        if (filtered.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 48),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.search_off_rounded,
                        size: 56, color: Colors.grey),
                    const SizedBox(height: 12),
                    Text(
                      'No medicines found matching "$_searchQuery"',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    TextButton.icon(
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() {
                          _searchQuery = '';
                          _selectedCategory = 'All';
                        });
                      },
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Show All Medicines'),
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              isWide ? 28 : 20,
              0,
              isWide ? 28 : 20,
              28,
            ),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 380,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                mainAxisExtent: 220,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final item = filtered[index];
                  final card = HoverScaleCard(
                    onTap: () => _openMedicineDetails(item),
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: AppTheme.primary
                                          .withValues(alpha: 0.10),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      item.category,
                                      style: const TextStyle(
                                        color: AppTheme.primary,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  if (item.requiresRx)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.red
                                            .withValues(alpha: 0.10),
                                        borderRadius:
                                            BorderRadius.circular(6),
                                      ),
                                      child: const Text(
                                        'Rx Required',
                                        style: TextStyle(
                                          color: Colors.red,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                item.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleMedium,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${item.manufacturer} • ${item.packSize}',
                                style: theme.textTheme.bodyMedium
                                    ?.copyWith(fontSize: 13),
                              ),
                            ],
                          ),
                          Wrap(
                            alignment: WrapAlignment.spaceBetween,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              Text(
                                item.formattedPrice,
                                style: theme.textTheme.titleLarge?.copyWith(
                                  color: AppTheme.priceColor(context),
                                ),
                              ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    tooltip: 'Medicine Details',
                                    icon: const Icon(Icons.info_outline,
                                        size: 20),
                                    onPressed: () =>
                                        _openMedicineDetails(item),
                                  ),
                                  FilledButton.tonal(
                                    style: FilledButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 8),
                                      visualDensity: VisualDensity.compact,
                                    ),
                                    onPressed: item.inStock
                                        ? () => _addToCart(item)
                                        : null,
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                            Icons.add_shopping_cart_rounded,
                                            size: 16),
                                        const SizedBox(width: 4),
                                        Text(item.inStock
                                            ? 'Add'
                                            : 'Out of Stock'),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );

                  if (index < 12) {
                    return StaggeredFadeSlide(
                      index: index,
                      child: card,
                    );
                  }
                  return card;
                },
                childCount: filtered.length,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildPrescriptionUploadView(bool isWide) {
    final theme = Theme.of(context);
    return ListView(
      key: const ValueKey('page-rx'),
      padding: EdgeInsets.all(isWide ? 28 : 20),
      children: [
        Text('Upload & Book Prescription',
            style: theme.textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text(
          'Submit your doctor’s prescription for pharmacist verification and doorstep medicine delivery.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 20),
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppTheme.accentPurple.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.cloud_upload_outlined,
                    size: 48,
                    color: AppTheme.accentPurple,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Book Medicines via Doctor Prescription',
                  style: theme.textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                Text(
                  'Supported formats: Camera Scan (JPG), Gallery (PNG), or Digital e-Rx (PDF)',
                  style: theme.textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 320),
                  child: FilledButton.icon(
                    onPressed: _openAddPrescriptionDialog,
                    icon: const Icon(Icons.upload_file_rounded),
                    label: const Text('Upload & Book Prescription'),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'My Uploaded Prescriptions (${_prescriptions.length})',
              style: theme.textTheme.titleLarge,
            ),
            IconButton(
              tooltip: 'Sync from Database',
              icon: _isLoadingPrescriptions
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded),
              onPressed: _isLoadingPrescriptions ? null : _loadDatabaseData,
            ),
          ],
        ),
        if (_isLoadingPrescriptions)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 4),
            child: LinearProgressIndicator(minHeight: 2),
          ),
        const SizedBox(height: 12),
        if (_prescriptions.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.description_outlined,
                      size: 44,
                      color: theme.colorScheme.outline,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'No Prescriptions Uploaded Yet',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Upload your doctor’s prescription to book medicines directly with pharmacist review.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 16),
                    FilledButton.tonalIcon(
                      onPressed: _openAddPrescriptionDialog,
                      icon: const Icon(Icons.upload_file_rounded, size: 18),
                      label: const Text('Upload New Prescription'),
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          Card(
            child: Column(
              children: [
                for (int i = 0; i < _prescriptions.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                    onTap: _prescriptions[i].imagePath != null &&
                            _prescriptions[i].imagePath!.isNotEmpty
                        ? () {
                            final path = _prescriptions[i].imagePath!;
                            showDialog(
                              context: context,
                              builder: (ctx) => Dialog(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    AppBar(
                                      title: Text(
                                          'Prescription #${_prescriptions[i].id}'),
                                      automaticallyImplyLeading: false,
                                      actions: [
                                        IconButton(
                                          icon: const Icon(Icons.close),
                                          onPressed: () =>
                                              Navigator.of(ctx).pop(),
                                        ),
                                      ],
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(12),
                                        child: kIsWeb
                                            ? Image.network(path,
                                                fit: BoxFit.contain)
                                            : Image.file(File(path),
                                                fit: BoxFit.contain),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }
                        : null,
                    leading: _prescriptions[i].imagePath != null &&
                            _prescriptions[i].imagePath!.isNotEmpty
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: kIsWeb
                                ? Image.network(
                                    _prescriptions[i].imagePath!,
                                    width: 46,
                                    height: 46,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) =>
                                        const CircleAvatar(
                                      backgroundColor: AppTheme.accentPurple,
                                      child: Icon(Icons.receipt_long,
                                          color: Colors.white),
                                    ),
                                  )
                                : Image.file(
                                    File(_prescriptions[i].imagePath!),
                                    width: 46,
                                    height: 46,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) =>
                                        const CircleAvatar(
                                      backgroundColor: AppTheme.accentPurple,
                                      child: Icon(Icons.receipt_long,
                                          color: Colors.white),
                                    ),
                                  ),
                          )
                        : CircleAvatar(
                            backgroundColor:
                                AppTheme.accentPurple.withValues(alpha: 0.12),
                            child: const Icon(
                              Icons.description_outlined,
                              color: AppTheme.accentPurple,
                            ),
                          ),
                    title: Text(
                      '${_prescriptions[i].id} • ${_prescriptions[i].doctorName}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      '${_prescriptions[i].hospitalName} • ${_prescriptions[i].documentType}\n${_prescriptions[i].uploadedAt} • Status: ${_prescriptions[i].status}',
                    ),
                    isThreeLine: true,
                    trailing: _prescriptions[i].canCancel
                        ? TextButton(
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.red.shade700,
                            ),
                            onPressed: () async {
                              final rxId = _prescriptions[i].id;
                              setState(() {
                                _prescriptions[i].status = 'Cancelled';
                              });
                              await _notifService.updatePrescriptionStatusInFirebase(
                                  rxId, 'Cancelled');
                              _showToast(
                                'Cancelled prescription $rxId in Firebase',
                              );
                            },
                            child: const Text('Cancel'),
                          )
                        : Text(
                            _prescriptions[i].status,
                            style: const TextStyle(
                              color: Colors.redAccent,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildRemindersAndOrdersView(bool isWide) {
    final theme = Theme.of(context);
    return ListView(
      key: const ValueKey('page-care'),
      padding: EdgeInsets.all(isWide ? 28 : 20),
      children: [
        Text('Reminders & Order Bookings',
            style: theme.textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text(
          'Manage your daily medication schedule, view Firebase-saved bookings, or trigger mobile notifications.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 20),
        _buildRemindersSummaryCard(theme),
        const SizedBox(height: 28),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'My Pharmacy Bookings (${_orders.length})',
              style: theme.textTheme.titleLarge,
            ),
            Row(
              children: [
                IconButton(
                  tooltip: 'Sync from Database',
                  icon: _isLoadingOrders
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh_rounded),
                  onPressed: _isLoadingOrders ? null : _loadDatabaseData,
                ),
                TextButton.icon(
                  onPressed: () => setState(() => _selectedIndex = 1),
                  icon: const Icon(Icons.add_shopping_cart_rounded, size: 18),
                  label: const Text('New Booking'),
                ),
              ],
            ),
          ],
        ),
        if (_isLoadingOrders)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 4),
            child: LinearProgressIndicator(minHeight: 2),
          ),
        const SizedBox(height: 12),
        if (_orders.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.receipt_long_outlined,
                      size: 44,
                      color: theme.colorScheme.outline,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'No Orders Placed Yet',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Your medicine orders saved in Firebase and MongoDB will be tracked here in real time.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: () => setState(() => _selectedIndex = 1),
                      icon: const Icon(Icons.shopping_bag_outlined, size: 18),
                      label: const Text('Order Medicines'),
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          Card(
            child: Column(
              children: [
                for (int i = 0; i < _orders.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    onTap: () => _showOrderDetailsSheet(_orders[i]),
                    leading: CircleAvatar(
                      backgroundColor: _orders[i].status == 'Cancelled'
                          ? Colors.red.withValues(alpha: 0.12)
                          : AppTheme.accentGreen.withValues(alpha: 0.12),
                      child: Icon(
                        _orders[i].status == 'Cancelled'
                            ? Icons.cancel_outlined
                            : Icons.local_shipping_rounded,
                        color: _orders[i].status == 'Cancelled'
                            ? Colors.redAccent
                            : AppTheme.accentGreen,
                      ),
                    ),
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Order #${_orders[i].id} • ₹${_orders[i].totalAmount.toStringAsFixed(2)}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        _OrderStatusBadge(status: _orders[i].status),
                      ],
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_orders[i].itemsSummary),
                          const SizedBox(height: 2),
                          Text(
                            '${_orders[i].createdAt} • ${_orders[i].deliverySlot} • Saved in Firebase & MongoDB',
                            style: const TextStyle(fontSize: 12),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 8,
                            children: [
                              TextButton(
                                onPressed: () =>
                                    _showOrderDetailsSheet(_orders[i]),
                                child: const Text('Confirmation Screen'),
                              ),
                              TextButton.icon(
                                onPressed: () async {
                                  await _notifService
                                      .showBookingConfirmedNotification(
                                          _orders[i]);
                                  setState(() {});
                                  _showToast(
                                    '📲 Mobile notification sent for Order #${_orders[i].id}',
                                  );
                                },
                                icon: const Icon(
                                  Icons.notifications_active_outlined,
                                  size: 16,
                                ),
                                label: const Text('Notify Device'),
                              ),
                              if (_orders[i].canCancel)
                                TextButton(
                                  style: TextButton.styleFrom(
                                    foregroundColor: Colors.red.shade700,
                                  ),
                                  onPressed: () =>
                                      _confirmCancelOrder(_orders[i]),
                                  child: const Text('Cancel Booking'),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildProfileView() {
    return ProfilePersonalizationView(
      biometricAvailable: _biometricAvailable,
      biometricEnabled: _biometricEnabled,
      onToggleBiometric: _toggleBiometric,
      onOpenNotifications: _showNotificationsSheet,
      onSignOut: _handleSignOut,
    );
  }
}

class _OrderStatusBadge extends StatelessWidget {
  const _OrderStatusBadge({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final Color color;
    switch (status) {
      case 'Delivered':
        color = AppTheme.accentGreen;
        break;
      case 'Out for Delivery':
        color = AppTheme.primary;
        break;
      case 'Cancelled':
        color = Colors.redAccent;
        break;
      default:
        color = AppTheme.accentOrange;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _QuickAction {
  const _QuickAction(
    this.label,
    this.subtitle,
    this.icon,
    this.color,
    this.onTap,
  );
  final String label;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({required this.action});
  final _QuickAction action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return HoverScaleCard(
      accentColor: action.color,
      onTap: action.onTap,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: action.color.withValues(alpha: 0.12),
              child: Icon(action.icon, color: action.color, size: 24),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  action.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  action.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontSize: 12,
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
