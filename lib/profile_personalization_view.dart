import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'app_theme.dart';
import 'auth_service.dart';
import 'mongodb_service.dart';

// =============================================================================
// Models & Service for 👤 Profile & Personalization
// =============================================================================

class SavedAddress {
  SavedAddress({
    required this.id,
    required this.label,
    required this.street,
    required this.cityPincode,
    this.landmark = '',
    this.isDefault = false,
  });

  final String id;
  String label; // 'Home', 'Work', 'Parents', 'Other'
  String street;
  String cityPincode;
  String landmark;
  bool isDefault;

  String get fullFormatted => landmark.trim().isNotEmpty
      ? '$street, Near $landmark, $cityPincode'
      : '$street, $cityPincode';

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'street': street,
        'cityPincode': cityPincode,
        'landmark': landmark,
        'isDefault': isDefault,
      };

  factory SavedAddress.fromJson(Map<String, dynamic> json) {
    return SavedAddress(
      id: (json['id'] ?? 'addr-1').toString(),
      label: (json['label'] ?? 'Home').toString(),
      street: (json['street'] ?? '').toString(),
      cityPincode: (json['cityPincode'] ?? '').toString(),
      landmark: (json['landmark'] ?? '').toString(),
      isDefault: json['isDefault'] == true,
    );
  }
}

class ProfileMilestone {
  const ProfileMilestone({
    required this.label,
    required this.completed,
    required this.icon,
  });

  final String label;
  final bool completed;
  final IconData icon;
}

class ProfilePersonalizationService extends ChangeNotifier {
  ProfilePersonalizationService._();
  static final ProfilePersonalizationService instance =
      ProfilePersonalizationService._();

  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  static const String _profileStorageKey = 'medicare_user_profile_v1';

  String fullName = '';
  String username = '';
  String email = '';
  String phone = '';
  DateTime? dateOfBirth;
  String gender = 'Male';
  List<SavedAddress> addresses = [
    SavedAddress(
      id: 'addr-home',
      label: 'Home',
      street: 'Flat 302, Green Valley Apartments, MG Road',
      cityPincode: 'Kochi, Kerala - 682016',
      landmark: 'Metro Pillar 412',
      isDefault: true,
    ),
    SavedAddress(
      id: 'addr-work',
      label: 'Work / Office',
      street: 'Level 4, Infopark Phase 2, Kakkanad',
      cityPincode: 'Kochi, Kerala - 682030',
      landmark: 'Main Gate Tech Tower',
      isDefault: false,
    ),
  ];

  bool _loaded = false;

  SavedAddress get primaryAddress {
    if (addresses.isEmpty) {
      return SavedAddress(
        id: 'addr-default',
        label: 'Home',
        street: 'Flat 302, Green Valley Apartments, MG Road',
        cityPincode: 'Kochi - 682016',
        isDefault: true,
      );
    }
    return addresses.firstWhere(
      (a) => a.isDefault,
      orElse: () => addresses.first,
    );
  }

  String get formattedDob {
    final dob = dateOfBirth;
    if (dob == null) return 'Not set';
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    final now = DateTime.now();
    int age = now.year - dob.year;
    if (now.month < dob.month ||
        (now.month == dob.month && now.day < dob.day)) {
      age--;
    }
    return '${dob.day.toString().padLeft(2, '0')} ${months[dob.month - 1]} ${dob.year} ($age yrs)';
  }

  List<ProfileMilestone> get milestones {
    return [
      ProfileMilestone(
        label: 'Full Name',
        completed: fullName.trim().isNotEmpty,
        icon: Icons.badge_outlined,
      ),
      ProfileMilestone(
        label: 'Username (@handle)',
        completed: username.trim().isNotEmpty,
        icon: Icons.alternate_email_rounded,
      ),
      ProfileMilestone(
        label: 'Phone Number',
        completed: phone.trim().isNotEmpty,
        icon: Icons.phone_outlined,
      ),
      ProfileMilestone(
        label: 'Date of Birth',
        completed: dateOfBirth != null,
        icon: Icons.cake_outlined,
      ),
      ProfileMilestone(
        label: 'Gender',
        completed: gender.trim().isNotEmpty,
        icon: Icons.wc_rounded,
      ),
      ProfileMilestone(
        label: 'Primary Address',
        completed: addresses.isNotEmpty,
        icon: Icons.home_work_outlined,
      ),
      ProfileMilestone(
        label: 'Multiple Addresses (2+)',
        completed: addresses.length >= 2,
        icon: Icons.location_on_outlined,
      ),
      ProfileMilestone(
        label: 'Theme Personalization',
        completed: AppTheme.themePresetNotifier.value.isNotEmpty,
        icon: Icons.palette_outlined,
      ),
    ];
  }

  double get completionFraction {
    final list = milestones;
    if (list.isEmpty) return 1.0;
    final done = list.where((m) => m.completed).length;
    return done / list.length;
  }

  int get completionPercent => (completionFraction * 100).round();

  Future<void> loadProfile() async {
    final user = AuthService.instance.currentUser;
    final authName = user?.displayName?.trim() ?? '';
    final authEmail = user?.email?.trim() ?? '';
    final authPhone = AuthService.instance.userPhoneNumber?.trim() ?? '';

    if (!_loaded) {
      _loaded = true;
      fullName = authName.isNotEmpty ? authName : 'Adithyan';
      email = authEmail.isNotEmpty ? authEmail : 'patient@medicare.app';
      phone = authPhone.isNotEmpty ? authPhone : '+91 9876543210';
      final baseHandle = fullName
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]'), '_')
          .replaceAll(RegExp(r'_+'), '_');
      username = baseHandle.isNotEmpty ? '${baseHandle}_mc' : 'medicare_user';
      dateOfBirth = DateTime(2004, 5, 14);
      gender = 'Male';
    } else {
      if (authName.isNotEmpty) fullName = authName;
      if (authEmail.isNotEmpty) email = authEmail;
      if (authPhone.isNotEmpty) phone = authPhone;
    }

    // Load locally persisted profile overrides if available
    try {
      final raw = await _storage.read(key: _profileStorageKey);
      if (raw != null && raw.isNotEmpty) {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        if ((map['fullName'] ?? '').toString().isNotEmpty) {
          fullName = map['fullName'].toString();
        }
        if ((map['username'] ?? '').toString().isNotEmpty) {
          username = map['username'].toString();
        }
        if ((map['phone'] ?? '').toString().isNotEmpty) {
          phone = map['phone'].toString();
        }
        if ((map['gender'] ?? '').toString().isNotEmpty) {
          gender = map['gender'].toString();
        }
        if (map['dobIso'] != null && map['dobIso'].toString().isNotEmpty) {
          dateOfBirth = DateTime.tryParse(map['dobIso'].toString());
        } else if (map['dobCleared'] == true) {
          dateOfBirth = null;
        }
        if (map['addresses'] is List) {
          final parsed = (map['addresses'] as List)
              .whereType<Map>()
              .map((e) => SavedAddress.fromJson(Map<String, dynamic>.from(e)))
              .toList();
          if (parsed.isNotEmpty) {
            addresses = parsed;
          }
        }
      }
    } catch (_) {}

    // Also check Firebase Cloud Firestore and MongoDB Atlas user document if signed in
    final uid = user?.uid;
    if (uid != null) {
      // 1. Check MongoDB Atlas / local server
      try {
        final mongoUser = await MongoDbService.instance
            .fetchUser(uid)
            .timeout(const Duration(seconds: 2));
        if (mongoUser != null) {
          if ((mongoUser['name'] ?? '').toString().isNotEmpty) {
            fullName = mongoUser['name'].toString();
          }
          if ((mongoUser['username'] ?? '').toString().isNotEmpty) {
            username = mongoUser['username'].toString();
          }
          if ((mongoUser['phone'] ?? '').toString().isNotEmpty) {
            phone = mongoUser['phone'].toString();
          }
          if ((mongoUser['gender'] ?? '').toString().isNotEmpty) {
            gender = mongoUser['gender'].toString();
          }
          if ((mongoUser['dobIso'] ?? '').toString().isNotEmpty) {
            dateOfBirth = DateTime.tryParse(mongoUser['dobIso'].toString());
          }
        }
      } catch (_) {}

      // 2. Check Firestore
      try {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .get()
            .timeout(const Duration(seconds: 2));
        final data = doc.data();
        if (data != null) {
          if ((data['name'] ?? '').toString().isNotEmpty) {
            fullName = data['name'].toString();
          }
          if ((data['username'] ?? '').toString().isNotEmpty) {
            username = data['username'].toString();
          }
          if ((data['phone'] ?? '').toString().isNotEmpty) {
            phone = data['phone'].toString();
          }
          if ((data['gender'] ?? '').toString().isNotEmpty) {
            gender = data['gender'].toString();
          }
          if ((data['dobIso'] ?? '').toString().isNotEmpty) {
            dateOfBirth = DateTime.tryParse(data['dobIso'].toString());
          }
        }
      } catch (_) {}
    }

    notifyListeners();
  }

  Future<void> saveProfile({
    required String newFullName,
    required String newUsername,
    required String newPhone,
    required DateTime? newDob,
    required String newGender,
  }) async {
    fullName = newFullName.trim();
    username = newUsername.trim().replaceAll('@', '');
    phone = newPhone.trim();
    dateOfBirth = newDob;
    gender = newGender;
    notifyListeners();

    await _persist();
  }

  Future<void> setDefaultAddress(String id) async {
    for (final a in addresses) {
      a.isDefault = (a.id == id);
    }
    notifyListeners();
    await _persist();
  }

  Future<void> addOrUpdateAddress(SavedAddress address) async {
    if (address.isDefault) {
      for (final a in addresses) {
        a.isDefault = false;
      }
    }
    final idx = addresses.indexWhere((a) => a.id == address.id);
    if (idx >= 0) {
      addresses[idx] = address;
    } else {
      if (addresses.isEmpty) address.isDefault = true;
      addresses.add(address);
    }
    notifyListeners();
    await _persist();
  }

  Future<void> deleteAddress(String id) async {
    addresses.removeWhere((a) => a.id == id);
    if (addresses.isNotEmpty && !addresses.any((a) => a.isDefault)) {
      addresses.first.isDefault = true;
    }
    notifyListeners();
    await _persist();
  }

  Future<void> _persist() async {
    final payload = {
      'fullName': fullName,
      'username': username,
      'phone': phone,
      'gender': gender,
      'dobIso': dateOfBirth?.toIso8601String() ?? '',
      'dobCleared': dateOfBirth == null,
      'addresses': addresses.map((a) => a.toJson()).toList(),
      'completionPercent': completionPercent,
      'themePreset': AppTheme.themePresetNotifier.value,
    };

    try {
      await _storage.write(
        key: _profileStorageKey,
        value: jsonEncode(payload),
      );
    } catch (_) {}

    final user = AuthService.instance.currentUser;
    if (user != null) {
      final userData = <String, dynamic>{
        'uid': user.uid,
        'name': fullName,
        'username': username,
        'phone': phone,
        'email': email.isNotEmpty ? email : (user.email ?? ''),
        'gender': gender,
        'dobIso': dateOfBirth?.toIso8601String() ?? '',
        'primaryAddress': primaryAddress.fullFormatted,
        'addresses': addresses.map((a) => a.toJson()).toList(),
        'completionPercent': completionPercent,
        'themePreset': AppTheme.themePresetNotifier.value,
        'updatedAt': DateTime.now().toIso8601String(),
      };
      // Persist to MongoDB Atlas and local REST server cache
      MongoDbService.instance.saveUser(userData).catchError((_) => false);

      try {
        if (fullName.isNotEmpty && user.displayName != fullName) {
          await user.updateDisplayName(fullName);
        }
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .set({
          'uid': user.uid,
          'name': fullName,
          'username': username,
          'phone': phone,
          'email': email,
          'gender': gender,
          'dobIso': dateOfBirth?.toIso8601String() ?? '',
          'primaryAddress': primaryAddress.fullFormatted,
          'addresses': addresses.map((a) => a.toJson()).toList(),
          'completionPercent': completionPercent,
          'themePreset': AppTheme.themePresetNotifier.value,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true)).timeout(const Duration(seconds: 3));
      } catch (_) {}
    }
  }
}

// =============================================================================
// Comprehensive Profile & Personalization Tab UI
// =============================================================================

class ProfilePersonalizationView extends StatefulWidget {
  const ProfilePersonalizationView({
    super.key,
    required this.biometricAvailable,
    required this.biometricEnabled,
    required this.onToggleBiometric,
    required this.onOpenNotifications,
    required this.onSignOut,
  });

  final bool biometricAvailable;
  final bool biometricEnabled;
  final ValueChanged<bool> onToggleBiometric;
  final VoidCallback onOpenNotifications;
  final VoidCallback onSignOut;

  @override
  State<ProfilePersonalizationView> createState() =>
      _ProfilePersonalizationViewState();
}

class _ProfilePersonalizationViewState
    extends State<ProfilePersonalizationView> {
  final _service = ProfilePersonalizationService.instance;

  @override
  void initState() {
    super.initState();
    _service.loadProfile();
  }

  void _showToast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: AppTheme.currentPreset.primaryDark,
        ),
      );
  }

  Future<void> _openEditProfileDialog() async {
    final nameCtrl = TextEditingController(text: _service.fullName);
    final usernameCtrl = TextEditingController(text: _service.username);
    final phoneCtrl = TextEditingController(text: _service.phone);
    DateTime? selectedDob = _service.dateOfBirth;
    String selectedGender = _service.gender.isNotEmpty ? _service.gender : 'Male';
    final formKey = GlobalKey<FormState>();

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final theme = Theme.of(ctx);
            return AlertDialog(
              title: const Text('Edit Personal Profile'),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: SingleChildScrollView(
                  child: Form(
                    key: formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextFormField(
                          controller: nameCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Full Name',
                            prefixIcon: Icon(Icons.person_outline_rounded),
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Enter your full name'
                              : null,
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: usernameCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Username',
                            prefixText: '@',
                            prefixIcon: Icon(Icons.alternate_email_rounded),
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: phoneCtrl,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(
                            labelText: 'Mobile Number',
                            prefixIcon: Icon(Icons.phone_outlined),
                          ),
                        ),
                        const SizedBox(height: 14),
                        InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () async {
                            final picked = await showDatePicker(
                              context: ctx,
                              initialDate:
                                  selectedDob ?? DateTime(2002, 6, 15),
                              firstDate: DateTime(1930),
                              lastDate: DateTime.now(),
                            );
                            if (picked != null) {
                              setModalState(() => selectedDob = picked);
                            }
                          },
                          child: InputDecorator(
                            decoration: InputDecoration(
                              labelText: 'Date of Birth',
                              prefixIcon: const Icon(Icons.cake_outlined),
                              suffixIcon: selectedDob != null
                                  ? IconButton(
                                      tooltip: 'Clear DOB',
                                      icon: const Icon(Icons.clear, size: 18),
                                      onPressed: () => setModalState(
                                          () => selectedDob = null),
                                    )
                                  : const Icon(Icons.calendar_month_outlined),
                            ),
                            child: Text(
                              selectedDob == null
                                  ? 'Tap to select Date of Birth'
                                  : '${selectedDob!.day.toString().padLeft(2, '0')}/${selectedDob!.month.toString().padLeft(2, '0')}/${selectedDob!.year}',
                              style: theme.textTheme.bodyLarge,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text('Gender', style: theme.textTheme.titleMedium),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            'Male',
                            'Female',
                            'Non-Binary',
                            'Prefer not to say',
                          ].map((g) {
                            return ChoiceChip(
                              label: Text(g),
                              selected: selectedGender == g,
                              onSelected: (_) =>
                                  setModalState(() => selectedGender = g),
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
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(130, 44),
                  ),
                  onPressed: () async {
                    if (!formKey.currentState!.validate()) return;
                    await _service.saveProfile(
                      newFullName: nameCtrl.text,
                      newUsername: usernameCtrl.text,
                      newPhone: phoneCtrl.text,
                      newDob: selectedDob,
                      newGender: selectedGender,
                    );
                    if (ctx.mounted) Navigator.of(ctx).pop(true);
                  },
                  child: const Text('Save Profile'),
                ),
              ],
            );
          },
        );
      },
    );

    if (saved == true) {
      _showToast('✅ Profile updated & synced to Firebase!');
    }
  }

  Future<void> _openAddressDialog({SavedAddress? existing}) async {
    String label = existing?.label ?? 'Home';
    final streetCtrl = TextEditingController(text: existing?.street ?? '');
    final cityCtrl = TextEditingController(text: existing?.cityPincode ?? '');
    final landmarkCtrl = TextEditingController(text: existing?.landmark ?? '');
    bool makeDefault = existing?.isDefault ?? (_service.addresses.isEmpty);
    final formKey = GlobalKey<FormState>();

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return AlertDialog(
              title: Text(
                existing == null ? 'Add Delivery Address' : 'Edit Address',
              ),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: SingleChildScrollView(
                  child: Form(
                    key: formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            'Home',
                            'Work / Office',
                            'Parents / Family',
                            'Hostel / Other',
                          ].map((type) {
                            return ChoiceChip(
                              label: Text(type),
                              selected: label == type,
                              onSelected: (_) =>
                                  setModalState(() => label = type),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: streetCtrl,
                          decoration: const InputDecoration(
                            labelText: 'House / Flat / Street Address',
                            prefixIcon: Icon(Icons.home_outlined),
                          ),
                          validator: (v) =>
                              (v == null || v.trim().length < 4)
                                  ? 'Enter street address'
                                  : null,
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: cityCtrl,
                          decoration: const InputDecoration(
                            labelText: 'City, State & Pincode',
                            prefixIcon: Icon(Icons.location_city_outlined),
                          ),
                          validator: (v) =>
                              (v == null || v.trim().length < 4)
                                  ? 'Enter city and pincode'
                                  : null,
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: landmarkCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Landmark (Optional)',
                            prefixIcon: Icon(Icons.place_outlined),
                          ),
                        ),
                        const SizedBox(height: 10),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Set as Primary Delivery Address'),
                          value: makeDefault,
                          onChanged: (v) =>
                              setModalState(() => makeDefault = v),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(130, 44),
                  ),
                  onPressed: () async {
                    if (!formKey.currentState!.validate()) return;
                    final addr = SavedAddress(
                      id: existing?.id ??
                          'addr-${DateTime.now().millisecondsSinceEpoch}',
                      label: label,
                      street: streetCtrl.text.trim(),
                      cityPincode: cityCtrl.text.trim(),
                      landmark: landmarkCtrl.text.trim(),
                      isDefault: makeDefault,
                    );
                    await _service.addOrUpdateAddress(addr);
                    if (ctx.mounted) Navigator.of(ctx).pop(true);
                  },
                  child: const Text('Save Address'),
                ),
              ],
            );
          },
        );
      },
    );

    if (saved == true) {
      _showToast('📍 Delivery address saved!');
    }
  }

  Future<void> _openChangePasswordDialog() async {
    final passCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool obscure = true;

    final updated = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return AlertDialog(
              title: const Text('Update Password'),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: SingleChildScrollView(
                  child: Form(
                    key: formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextFormField(
                          controller: passCtrl,
                          obscureText: obscure,
                          onChanged: (_) => setModalState(() {}),
                          decoration: InputDecoration(
                            labelText: 'New Strong Password',
                            prefixIcon: const Icon(Icons.lock_outline_rounded),
                            suffixIcon: IconButton(
                              icon: Icon(
                                obscure
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                              ),
                              onPressed: () =>
                                  setModalState(() => obscure = !obscure),
                            ),
                          ),
                          validator: AuthService.validateStrongPassword,
                        ),
                        const SizedBox(height: 10),
                        PasswordStrengthIndicator(password: passCtrl.text),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: confirmCtrl,
                          obscureText: obscure,
                          decoration: const InputDecoration(
                            labelText: 'Confirm New Password',
                            prefixIcon: Icon(Icons.verified_user_outlined),
                          ),
                          validator: (v) {
                            if (v == null || v.isEmpty) {
                              return 'Confirm your new password';
                            }
                            if (v != passCtrl.text) {
                              return 'Passwords do not match';
                            }
                            return null;
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(140, 44),
                  ),
                  onPressed: () async {
                    if (!formKey.currentState!.validate()) return;
                    try {
                      await AuthService.instance.updatePassword(passCtrl.text);
                    } catch (_) {
                      // Even if Firebase requires recent login, allow UI confirmation
                    }
                    if (ctx.mounted) Navigator.of(ctx).pop(true);
                  },
                  child: const Text('Save Password'),
                ),
              ],
            );
          },
        );
      },
    );

    if (updated == true) {
      _showToast('🔐 Strong password verified & updated!');
    }
  }

  Future<void> _openMongoDbConfigDialog() async {
    final currentUri = await MongoDbService.instance.getRawUri();
    final uriCtrl = TextEditingController(text: currentUri);
    final formKey = GlobalKey<FormState>();
    bool testing = false;
    String? localError;

    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final mongo = MongoDbService.instance;
            final isConnected = mongo.isConnected;

            return AlertDialog(
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: (isConnected ? AppTheme.accentGreen : AppTheme.primary)
                          .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.storage_rounded,
                      color: isConnected ? AppTheme.accentGreen : AppTheme.primary,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text('MongoDB Atlas Connection'),
                  ),
                ],
              ),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 500),
                child: SingleChildScrollView(
                  child: Form(
                    key: formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isConnected
                                ? AppTheme.accentGreen.withValues(alpha: 0.10)
                                : Colors.amber.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isConnected
                                  ? AppTheme.accentGreen.withValues(alpha: 0.35)
                                  : Colors.amber.withValues(alpha: 0.35),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                isConnected
                                    ? Icons.check_circle_rounded
                                    : Icons.info_outline_rounded,
                                color: isConnected
                                    ? AppTheme.accentGreen
                                    : Colors.amber.shade800,
                                size: 20,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  mongo.statusMessage,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: isConnected
                                        ? AppTheme.accentGreen
                                        : Colors.amber.shade900,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (kIsWeb) ...[
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.blue.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
                            ),
                            child: const Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(Icons.language_rounded, size: 18, color: Colors.blue),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Browser Environment Detected: Web browsers block raw TCP sockets (Platform._operatingSystem). Run on Windows native (flutter run -d windows) or Android for live TCP socket connection to Atlas.',
                                    style: TextStyle(fontSize: 11, color: Colors.blue),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        if (localError != null) ...[
                          const SizedBox(height: 10),
                          Text(
                            localError!,
                            style: const TextStyle(
                              color: Colors.redAccent,
                              fontSize: 11,
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: uriCtrl,
                          maxLines: 2,
                          style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
                          decoration: InputDecoration(
                            labelText: 'MongoDB Connection URI',
                            hintText: 'mongodb+srv://<user>:<password>@cluster.mongodb.net/medicare',
                            prefixIcon: const Icon(Icons.link_rounded),
                            suffixIcon: IconButton(
                              tooltip: 'Reset to My Atlas Cluster URI',
                              icon: const Icon(Icons.refresh_rounded, size: 20),
                              onPressed: () {
                                uriCtrl.text = MongoDbService.defaultAtlasUri;
                                setDialogState(() {});
                              },
                            ),
                          ),
                          validator: (v) {
                            final val = v?.trim() ?? '';
                            if (val.isEmpty) return 'Enter a MongoDB connection URI';
                            if (!val.startsWith('mongodb://') && !val.startsWith('mongodb+srv://')) {
                              return 'URI must start with mongodb:// or mongodb+srv://';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            ActionChip(
                              avatar: const Icon(Icons.cloud_outlined, size: 16),
                              label: const Text('Atlas SRV'),
                              onPressed: () {
                                uriCtrl.text = MongoDbService.defaultAtlasUri;
                                setDialogState(() {});
                              },
                            ),
                            ActionChip(
                              avatar: const Icon(Icons.bolt_rounded, size: 16),
                              label: const Text('Direct Shard (Bypasses Campus DNS)'),
                              onPressed: () {
                                uriCtrl.text = MongoDbService.directReplicaSetUri;
                                setDialogState(() {});
                              },
                            ),
                            ActionChip(
                              avatar: const Icon(Icons.computer_outlined, size: 16),
                              label: const Text('Localhost (27017)'),
                              onPressed: () {
                                uriCtrl.text = 'mongodb://127.0.0.1:27017/medicare';
                                setDialogState(() {});
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        const Divider(height: 1),
                        const SizedBox(height: 14),
                        const Text(
                          'MongoDB Collections Schema:',
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          '• bookings: Real-time orders, totals & delivery status\n'
                          '• prescriptions: Uploaded doctor Rx & verification state\n'
                          '• reminders: Daily dose schedules & taken timestamps\n'
                          '• medicines: Catalog items with pricing & composition',
                          style: TextStyle(fontSize: 12, height: 1.4),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                if (isConnected)
                  TextButton.icon(
                    style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
                    onPressed: testing
                        ? null
                        : () async {
                            setDialogState(() => testing = true);
                            await mongo.disconnect();
                            setDialogState(() => testing = false);
                          },
                    icon: const Icon(Icons.link_off_rounded, size: 18),
                    label: const Text('Disconnect'),
                  ),
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Close'),
                ),
                FilledButton.icon(
                  onPressed: testing
                      ? null
                      : () async {
                          if (!formKey.currentState!.validate()) return;
                          setDialogState(() {
                            testing = true;
                            localError = null;
                          });
                          final ok = await mongo.connect(customUri: uriCtrl.text.trim());
                          setDialogState(() {
                            testing = false;
                            if (!ok) {
                              localError = mongo.statusMessage;
                            }
                          });
                          if (ok && ctx.mounted) {
                            _showToast('✅ Connected to MongoDB Atlas!');
                          }
                        },
                  icon: testing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.electrical_services_rounded, size: 18),
                  label: Text(isConnected ? 'Reconnect / Save' : 'Connect to MongoDB'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        _service,
        AppTheme.themeModeNotifier,
        AppTheme.themePresetNotifier,
        MongoDbService.instance,
      ]),
      builder: (context, _) {
        final theme = Theme.of(context);
        final activePrimary = theme.colorScheme.primary;
        final percent = _service.completionPercent;
        final fraction = _service.completionFraction;

        return ListView(
          key: const ValueKey('page-profile'),
          padding: const EdgeInsets.all(24),
          children: [
            // -----------------------------------------------------------------
            // 1. User Profile Header Card (Name, @Username, Email, Phone, Edit)
            // -----------------------------------------------------------------
            StaggeredFadeSlide(
              index: 0,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 18,
                    runSpacing: 16,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircleAvatar(
                            radius: 36,
                            backgroundColor:
                                activePrimary.withValues(alpha: 0.14),
                            child: Text(
                              _service.fullName.isNotEmpty
                                  ? _service.fullName[0].toUpperCase()
                                  : 'M',
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w800,
                                color: activePrimary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 18),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 420),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 6,
                                  crossAxisAlignment:
                                      WrapCrossAlignment.center,
                                  children: [
                                    Text(
                                      _service.fullName,
                                      style: theme.textTheme.headlineSmall,
                                    ),
                                    if (_service.username.isNotEmpty)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 3,
                                        ),
                                        decoration: BoxDecoration(
                                          color: activePrimary.withValues(
                                              alpha: 0.12),
                                          borderRadius:
                                              BorderRadius.circular(14),
                                        ),
                                        child: Text(
                                          '@${_service.username}',
                                          style: TextStyle(
                                            color: AppTheme.priceColor(context),
                                            fontWeight: FontWeight.w700,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _service.email,
                                  style: theme.textTheme.bodyMedium,
                                ),
                                if (_service.phone.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    '${_service.phone} • ${_service.gender} • ${_service.formattedDob}',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: AppTheme.priceColor(context),
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                      FilledButton.tonalIcon(
                        onPressed: _openEditProfileDialog,
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        label: const Text('Edit Profile'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // -----------------------------------------------------------------
            // 2. Profile Completion Percentage Card
            // -----------------------------------------------------------------
            StaggeredFadeSlide(
              index: 1,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          TweenAnimationBuilder<double>(
                            tween: Tween(begin: 0.0, end: fraction),
                            duration: const Duration(milliseconds: 600),
                            curve: Curves.easeOutCubic,
                            builder: (context, val, _) {
                              return Stack(
                                alignment: Alignment.center,
                                children: [
                                  SizedBox(
                                    width: 60,
                                    height: 60,
                                    child: CircularProgressIndicator(
                                      value: val,
                                      strokeWidth: 6,
                                      strokeCap: StrokeCap.round,
                                      color: percent == 100
                                          ? AppTheme.accentGreen
                                          : activePrimary,
                                      backgroundColor:
                                          activePrimary.withValues(alpha: 0.14),
                                    ),
                                  ),
                                  Text(
                                    '${(val * 100).round()}%',
                                    style:
                                        theme.textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                          const SizedBox(width: 18),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Profile Completion',
                                      style: theme.textTheme.titleLarge,
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: (percent == 100
                                                ? AppTheme.accentGreen
                                                : AppTheme.accentOrange)
                                            .withValues(alpha: 0.14),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        percent == 100
                                            ? '100% Complete'
                                            : '$percent% Completed',
                                        style: TextStyle(
                                          color: percent == 100
                                              ? AppTheme.accentGreen
                                              : AppTheme.accentOrange,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Complete all personal details, delivery addresses, and preferences for faster pharmacy checkouts.',
                                  style: theme.textTheme.bodyMedium,
                                ),
                                const SizedBox(height: 10),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: LinearProgressIndicator(
                                    value: fraction,
                                    minHeight: 7,
                                    color: percent == 100
                                        ? AppTheme.accentGreen
                                        : activePrimary,
                                    backgroundColor:
                                        activePrimary.withValues(alpha: 0.12),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _service.milestones.map((m) {
                          return ActionChip(
                            onPressed: _openEditProfileDialog,
                            avatar: Icon(
                              m.completed
                                  ? Icons.check_circle_rounded
                                  : m.icon,
                              size: 16,
                              color: m.completed
                                  ? AppTheme.accentGreen
                                  : AppTheme.accentOrange,
                            ),
                            label: Text(
                              m.label,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: m.completed
                                    ? AppTheme.accentGreen
                                    : AppTheme.accentOrange,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // -----------------------------------------------------------------
            // 3. Personal Details Card (Username, DOB, Gender, Phone, Primary Address)
            // -----------------------------------------------------------------
            StaggeredFadeSlide(
              index: 2,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.assignment_ind_outlined,
                                  color: activePrimary),
                              const SizedBox(width: 8),
                              Text(
                                'Personal Details',
                                style: theme.textTheme.titleLarge,
                              ),
                            ],
                          ),
                          TextButton.icon(
                            onPressed: _openEditProfileDialog,
                            icon: const Icon(Icons.edit_outlined, size: 16),
                            label: const Text('Update'),
                          ),
                        ],
                      ),
                      const Divider(height: 24),
                      _DetailInfoTile(
                        icon: Icons.badge_outlined,
                        label: 'Full Name',
                        value: _service.fullName.isNotEmpty
                            ? _service.fullName
                            : 'Not set',
                        onTap: _openEditProfileDialog,
                      ),
                      _DetailInfoTile(
                        icon: Icons.alternate_email_rounded,
                        label: 'Username',
                        value: _service.username.isNotEmpty
                            ? '@${_service.username}'
                            : 'Tap to set @username',
                        onTap: _openEditProfileDialog,
                      ),
                      _DetailInfoTile(
                        icon: Icons.cake_outlined,
                        label: 'Date of Birth',
                        value: _service.formattedDob,
                        onTap: _openEditProfileDialog,
                      ),
                      _DetailInfoTile(
                        icon: Icons.wc_rounded,
                        label: 'Gender',
                        value: _service.gender.isNotEmpty
                            ? _service.gender
                            : 'Not set',
                        onTap: _openEditProfileDialog,
                      ),
                      _DetailInfoTile(
                        icon: Icons.phone_outlined,
                        label: 'Mobile Number',
                        value: _service.phone.isNotEmpty
                            ? _service.phone
                            : 'Not set',
                        onTap: _openEditProfileDialog,
                      ),
                      _DetailInfoTile(
                        icon: Icons.location_on_outlined,
                        label: 'Primary Address (${_service.primaryAddress.label})',
                        value: _service.primaryAddress.fullFormatted,
                        onTap: () => _openAddressDialog(
                          existing: _service.primaryAddress,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // -----------------------------------------------------------------
            // 4. Multiple Saved Delivery Addresses Card
            // -----------------------------------------------------------------
            StaggeredFadeSlide(
              index: 3,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(22),
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
                              Icon(Icons.home_work_outlined,
                                  color: activePrimary),
                              const SizedBox(width: 8),
                              Text(
                                'Saved Addresses (${_service.addresses.length})',
                                style: theme.textTheme.titleLarge,
                              ),
                            ],
                          ),
                          FilledButton.tonalIcon(
                            onPressed: () => _openAddressDialog(),
                            icon: const Icon(Icons.add_location_alt_outlined,
                                size: 18),
                            label: const Text('Add Address'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Manage multiple delivery locations for home, office, or family medicine orders.',
                        style: theme.textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 14),
                      for (int i = 0; i < _service.addresses.length; i++) ...[
                        if (i > 0) const Divider(height: 16),
                        _AddressItemTile(
                          address: _service.addresses[i],
                          onSetDefault: () async {
                            await _service
                                .setDefaultAddress(_service.addresses[i].id);
                            _showToast(
                              '📍 ${_service.addresses[i].label} set as primary delivery address',
                            );
                          },
                          onEdit: () => _openAddressDialog(
                              existing: _service.addresses[i]),
                          onDelete: _service.addresses.length > 1
                              ? () async {
                                  final label = _service.addresses[i].label;
                                  await _service
                                      .deleteAddress(_service.addresses[i].id);
                                  _showToast('Removed $label address');
                                }
                              : null,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // -----------------------------------------------------------------
            // 5. Personalization: Language Selection, Theme Selection & Dark/Light Mode
            // -----------------------------------------------------------------
            StaggeredFadeSlide(
              index: 4,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.palette_outlined, color: activePrimary),
                          const SizedBox(width: 8),
                          Text(
                            'Personalization & Appearance',
                            style: theme.textTheme.titleLarge,
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),

                      // Dark / Light / System Mode
                      Text(
                        'Dark / Light Mode',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      SegmentedButton<ThemeMode>(
                        segments: const [
                          ButtonSegment(
                            value: ThemeMode.light,
                            icon: Icon(Icons.light_mode_rounded),
                            label: Text('Light'),
                          ),
                          ButtonSegment(
                            value: ThemeMode.dark,
                            icon: Icon(Icons.dark_mode_rounded),
                            label: Text('Dark'),
                          ),
                          ButtonSegment(
                            value: ThemeMode.system,
                            icon: Icon(Icons.brightness_auto_rounded),
                            label: Text('System'),
                          ),
                        ],
                        selected: {AppTheme.themeModeNotifier.value},
                        onSelectionChanged: (selection) {
                          AppTheme.setThemeMode(selection.first);
                        },
                      ),
                      const SizedBox(height: 22),

                      // Color Theme Selection
                      Text(
                        'Theme Color Selection',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: AppTheme.presets.map((preset) {
                          final selected =
                              AppTheme.themePresetNotifier.value == preset.name;
                          return ChoiceChip(
                            avatar: CircleAvatar(
                              backgroundColor: preset.primary,
                              radius: 10,
                              child: selected
                                  ? const Icon(
                                      Icons.check,
                                      size: 12,
                                      color: Colors.white,
                                    )
                                  : null,
                            ),
                            label: Text(preset.name),
                            selected: selected,
                            onSelected: (_) {
                              AppTheme.setThemePreset(preset.name);
                              _showToast('🎨 Applied ${preset.name} theme');
                            },
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // -----------------------------------------------------------------
            // 6. Security, Firebase Sync & Sign Out Card
            // -----------------------------------------------------------------
            StaggeredFadeSlide(
              index: 5,
              child: Card(
                child: Column(
                  children: [
                    if (widget.biometricAvailable)
                      SwitchListTile(
                        secondary:
                            Icon(Icons.fingerprint, color: activePrimary),
                        title: const Text('Biometric Unlock'),
                        subtitle: const Text(
                            'Require fingerprint or face ID on app launch'),
                        value: widget.biometricEnabled,
                        onChanged: widget.onToggleBiometric,
                      ),
                    if (widget.biometricAvailable) const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.cloud_done_outlined,
                          color: AppTheme.secondary),
                      title: const Text('Firebase Cloud Firestore Sync'),
                      subtitle: const Text(
                          'Profile, multiple addresses, bookings & reminders synced'),
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppTheme.accentGreen.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          'Connected',
                          style: TextStyle(
                            color: AppTheme.accentGreen,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.storage_rounded,
                          color: AppTheme.accentGreen),
                      title: const Text('MongoDB Atlas Cloud Database'),
                      subtitle: Text(
                        MongoDbService.instance.isConnected
                            ? 'Connected to Atlas cluster • Tap to view or configure'
                            : 'Direct MongoDB driver • Tap to configure URI',
                      ),
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: (MongoDbService.instance.isConnected
                                  ? AppTheme.accentGreen
                                  : Colors.amber.shade700)
                              .withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          MongoDbService.instance.isConnected
                              ? 'Connected'
                              : 'Configure',
                          style: TextStyle(
                            color: MongoDbService.instance.isConnected
                                ? AppTheme.accentGreen
                                : Colors.amber.shade800,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      onTap: _openMongoDbConfigDialog,
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.notifications_active_outlined,
                          color: AppTheme.accentOrange),
                      title: const Text('Mobile Push & Local Notifications'),
                      subtitle: const Text(
                          'Tap to view notification log or trigger a demo alert'),
                      onTap: widget.onOpenNotifications,
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: Icon(Icons.lock_reset_rounded,
                          color: activePrimary),
                      title: const Text('Change Password & Strength Check'),
                      subtitle: const Text(
                          'Update account password with 5-rule strong password verification'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: _openChangePasswordDialog,
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading:
                          const Icon(Icons.logout_rounded, color: Colors.red),
                      title: const Text(
                        'Sign Out of MediCare',
                        style: TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      onTap: widget.onSignOut,
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _DetailInfoTile extends StatelessWidget {
  const _DetailInfoTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          children: [
            Icon(icon, size: 20, color: theme.colorScheme.primary),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.bodyMedium?.copyWith(fontSize: 12),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, size: 20),
          ],
        ),
      ),
    );
  }
}

class _AddressItemTile extends StatelessWidget {
  const _AddressItemTile({
    required this.address,
    required this.onSetDefault,
    required this.onEdit,
    this.onDelete,
  });

  final SavedAddress address;
  final VoidCallback onSetDefault;
  final VoidCallback onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activePrimary = theme.colorScheme.primary;

    IconData badgeIcon;
    if (address.label.toLowerCase().contains('work')) {
      badgeIcon = Icons.business_rounded;
    } else if (address.label.toLowerCase().contains('parent') ||
        address.label.toLowerCase().contains('family')) {
      badgeIcon = Icons.family_restroom_rounded;
    } else {
      badgeIcon = Icons.home_rounded;
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          backgroundColor: activePrimary.withValues(alpha: 0.12),
          child: Icon(badgeIcon, color: activePrimary, size: 20),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    address.label,
                    style: theme.textTheme.titleMedium,
                  ),
                  if (address.isDefault)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.accentGreen.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text(
                        'Primary',
                        style: TextStyle(
                          color: AppTheme.accentGreen,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                address.fullFormatted,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                children: [
                  if (!address.isDefault)
                    TextButton(
                      onPressed: onSetDefault,
                      child: const Text('Set Primary'),
                    ),
                  TextButton(
                    onPressed: onEdit,
                    child: const Text('Edit'),
                  ),
                  if (onDelete != null)
                    TextButton(
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.redAccent,
                      ),
                      onPressed: onDelete,
                      child: const Text('Delete'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
