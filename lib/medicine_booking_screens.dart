import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'booking_notification_service.dart';
import 'profile_personalization_view.dart';

// =============================================================================
// Data Models for Core Features (C1, C2, D1, D2)
// =============================================================================

class MedicineItem {
  const MedicineItem({
    required this.id,
    required this.name,
    required this.category,
    required this.manufacturer,
    required this.packSize,
    required this.priceValue,
    required this.composition,
    required this.usageGuide,
    required this.inStock,
    required this.requiresRx,
  });

  final String id;
  final String name;
  final String category;
  final String manufacturer;
  final String packSize;
  final double priceValue;
  final String composition;
  final String usageGuide;
  final bool inStock;
  final bool requiresRx;

  String get formattedPrice => '₹${priceValue.toStringAsFixed(2)}';
}

class CartItem {
  CartItem({required this.medicine, this.quantity = 1});

  final MedicineItem medicine;
  int quantity;

  double get subtotal => medicine.priceValue * quantity;
}

class OrderBooking {
  OrderBooking({
    required this.id,
    required this.createdAt,
    required this.itemsSummary,
    required this.itemDetails,
    required this.deliverySlot,
    required this.paymentMethod,
    required this.address,
    required this.totalAmount,
    required this.status,
  });

  final String id;
  final String createdAt;
  final String itemsSummary;
  final List<String> itemDetails;
  final String deliverySlot;
  final String paymentMethod;
  final String address;
  final double totalAmount;
  String status; // 'Processing', 'Out for Delivery', 'Delivered', 'Cancelled'

  bool get canCancel =>
      status == 'Processing' || status == 'Out for Delivery';

  Map<String, dynamic> toJson() => {
    'id': id,
    'createdAt': createdAt,
    'itemsSummary': itemsSummary,
    'itemDetails': itemDetails,
    'deliverySlot': deliverySlot,
    'paymentMethod': paymentMethod,
    'address': address,
    'totalAmount': totalAmount,
    'status': status,
  };

  factory OrderBooking.fromJson(Map<String, dynamic> json) => OrderBooking(
    id: (json['id'] ?? '').toString(),
    createdAt: (json['createdAt'] ?? 'Saved in Database').toString(),
    itemsSummary: (json['itemsSummary'] ?? 'Medicine Order').toString(),
    itemDetails: (json['itemDetails'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        [],
    deliverySlot: (json['deliverySlot'] ?? 'Standard Delivery').toString(),
    paymentMethod: (json['paymentMethod'] ?? 'UPI').toString(),
    address: (json['address'] ?? '').toString(),
    totalAmount: (json['totalAmount'] as num?)?.toDouble() ?? 0.0,
    status: (json['status'] ?? 'Processing').toString(),
  );
}

class PrescriptionBooking {
  PrescriptionBooking({
    required this.id,
    required this.patientName,
    required this.doctorName,
    required this.hospitalName,
    required this.documentType,
    required this.uploadedAt,
    required this.status,
    this.imagePath,
  });

  final String id;
  final String patientName;
  final String doctorName;
  final String hospitalName;
  final String documentType;
  final String uploadedAt;
  final String? imagePath;
  String status; // 'Under Pharmacist Review', 'Verified', 'Cancelled'

  bool get canCancel => status == 'Under Pharmacist Review';

  Map<String, dynamic> toJson() => {
    'id': id,
    'patientName': patientName,
    'doctorName': doctorName,
    'hospitalName': hospitalName,
    'documentType': documentType,
    'uploadedAt': uploadedAt,
    'status': status,
    'imagePath': imagePath ?? '',
  };

  factory PrescriptionBooking.fromJson(Map<String, dynamic> json) => PrescriptionBooking(
    id: (json['id'] ?? '').toString(),
    patientName: (json['patientName'] ?? 'Self').toString(),
    doctorName: (json['doctorName'] ?? 'Doctor').toString(),
    hospitalName: (json['hospitalName'] ?? 'Clinic').toString(),
    documentType: (json['documentType'] ?? 'Digital e-Rx').toString(),
    uploadedAt: (json['uploadedAt'] ?? 'Saved in Database').toString(),
    status: (json['status'] ?? 'Under Pharmacist Review').toString(),
    imagePath: json['imagePath']?.toString().isNotEmpty == true
        ? json['imagePath'].toString()
        : null,
  );
}

class DoseReminder {
  DoseReminder({
    required this.id,
    required this.name,
    required this.schedule,
    required this.dosage,
    required this.taken,
  });

  final String id;
  final String name;
  final String schedule;
  final String dosage;
  bool taken;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'schedule': schedule,
    'dosage': dosage,
    'taken': taken,
  };

  factory DoseReminder.fromJson(Map<String, dynamic> json) => DoseReminder(
    id: (json['id'] ?? '').toString(),
    name: (json['name'] ?? 'Medicine').toString(),
    schedule: (json['schedule'] ?? '09:00 AM').toString(),
    dosage: (json['dosage'] ?? '1 Tablet').toString(),
    taken: json['taken'] == true,
  );
}

class MedicineDetailResult {
  const MedicineDetailResult({
    required this.medicine,
    required this.quantity,
    required this.buyNow,
  });

  final MedicineItem medicine;
  final int quantity;
  final bool buyNow;
}

// =============================================================================
// 1. Medicine Detail Screen (Multi-screen navigation & quantity state)
// =============================================================================

class MedicineDetailScreen extends StatefulWidget {
  const MedicineDetailScreen({super.key, required this.medicine});

  final MedicineItem medicine;

  @override
  State<MedicineDetailScreen> createState() => _MedicineDetailScreenState();
}

class _MedicineDetailScreenState extends State<MedicineDetailScreen> {
  int _quantity = 1;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final med = widget.medicine;
    final total = med.priceValue * _quantity;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Medicine Details'),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _BadgeChip(
                            label: med.category,
                            color: AppTheme.primary,
                          ),
                          _BadgeChip(
                            label: med.requiresRx
                                ? 'Prescription Required (Rx)'
                                : 'OTC • No Rx Needed',
                            color: med.requiresRx
                                ? AppTheme.accentPurple
                                : AppTheme.secondary,
                          ),
                          _BadgeChip(
                            label: med.inStock ? 'In Stock' : 'Out of Stock',
                            color: med.inStock
                                ? AppTheme.accentGreen
                                : Colors.redAccent,
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Text(med.name, style: theme.textTheme.headlineMedium),
                      const SizedBox(height: 6),
                      Text(
                        'Manufactured by ${med.manufacturer} • ${med.packSize}',
                        style: theme.textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: AppTheme.isDark(context)
                              ? AppTheme.darkSurfaceElevated
                              : AppTheme.background,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: theme.dividerColor),
                        ),
                        child: Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 16,
                          runSpacing: 12,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Unit Price (MRP)',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  med.formattedPrice,
                                  style:
                                      theme.textTheme.headlineSmall?.copyWith(
                                    color: AppTheme.priceColor(context),
                                  ),
                                ),
                              ],
                            ),
                            if (med.inStock)
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text(
                                    'Qty:',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  IconButton.outlined(
                                    onPressed: _quantity > 1
                                        ? () => setState(() => _quantity--)
                                        : null,
                                    icon: const Icon(Icons.remove, size: 18),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                    ),
                                    child: Text(
                                      '$_quantity',
                                      style: theme.textTheme.titleLarge,
                                    ),
                                  ),
                                  IconButton.outlined(
                                    onPressed: _quantity < 10
                                        ? () => setState(() => _quantity++)
                                        : null,
                                    icon: const Icon(Icons.add, size: 18),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Active Composition',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 6),
                      Text(med.composition, style: theme.textTheme.bodyLarge),
                      const SizedBox(height: 18),
                      Text(
                        'Dosage & Usage Guidance',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 6),
                      Text(med.usageGuide, style: theme.textTheme.bodyLarge),
                      const SizedBox(height: 28),
                      if (med.inStock)
                        Wrap(
                          spacing: 14,
                          runSpacing: 12,
                          children: [
                            SizedBox(
                              width: 240,
                              child: OutlinedButton.icon(
                                onPressed: () {
                                  Navigator.of(context).pop(
                                    MedicineDetailResult(
                                      medicine: med,
                                      quantity: _quantity,
                                      buyNow: false,
                                    ),
                                  );
                                },
                                icon: const Icon(
                                    Icons.add_shopping_cart_rounded),
                                label: Text(
                                  'Add to Cart (₹${total.toStringAsFixed(0)})',
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 240,
                              child: FilledButton.icon(
                                onPressed: () {
                                  Navigator.of(context).pop(
                                    MedicineDetailResult(
                                      medicine: med,
                                      quantity: _quantity,
                                      buyNow: true,
                                    ),
                                  );
                                },
                                icon: const Icon(Icons.flash_on_rounded),
                                label: const Text('Book / Order Now'),
                              ),
                            ),
                          ],
                        )
                      else
                        const FilledButton(
                          onPressed: null,
                          child: Text('Currently Out of Stock'),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BadgeChip extends StatelessWidget {
  const _BadgeChip({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

// =============================================================================
// 2. Cart & Checkout Booking Screen (Saves to Firebase & Triggers Notification)
// =============================================================================

class CartCheckoutScreen extends StatefulWidget {
  const CartCheckoutScreen({super.key, required this.initialItems});

  final List<CartItem> initialItems;

  @override
  State<CartCheckoutScreen> createState() => _CartCheckoutScreenState();
}

class _CartCheckoutScreenState extends State<CartCheckoutScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _addressCtrl = TextEditingController(
    text: ProfilePersonalizationService.instance.primaryAddress.fullFormatted,
  );
  late final List<CartItem> _items = widget.initialItems
      .map((e) => CartItem(medicine: e.medicine, quantity: e.quantity))
      .toList();

  String _deliverySlot = 'Express 2-Hr Delivery';
  String _paymentMethod = 'UPI / Instant QR';
  bool _saving = false;

  @override
  void dispose() {
    _addressCtrl.dispose();
    super.dispose();
  }

  double get _subtotal =>
      _items.fold(0, (sum, item) => sum + item.subtotal);

  Future<void> _confirmBooking() async {
    if (_items.isEmpty || _saving) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);

    final totalQty = _items.fold<int>(0, (s, i) => s + i.quantity);
    final summary =
        '${_items.first.medicine.name}${_items.length > 1 ? ' + ${_items.length - 1} more' : ''} ($totalQty ${totalQty == 1 ? 'pack' : 'packs'})';

    final details = _items
        .map((i) =>
            '${i.medicine.name} × ${i.quantity} (₹${i.subtotal.toStringAsFixed(2)})')
        .toList();

    final orderNumber =
        'MC-${DateTime.now().millisecondsSinceEpoch.toString().substring(9)}';

    final booking = OrderBooking(
      id: orderNumber,
      createdAt: 'Booked just now',
      itemsSummary: summary,
      itemDetails: details,
      deliverySlot: _deliverySlot,
      paymentMethod: _paymentMethod,
      address: _addressCtrl.text.trim(),
      totalAmount: _subtotal,
      status: 'Processing',
    );

    // D1: Save booking details to Firebase Cloud Firestore
    await BookingNotificationService.instance.saveBookingToFirebase(booking);

    // D2: Trigger mobile device notification immediately
    await BookingNotificationService.instance
        .showBookingConfirmedNotification(booking);

    if (!mounted) return;
    setState(() => _saving = false);

    // D1: Show immediate Booking Confirmation / Acknowledgment Screen
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BookingConfirmationScreen(booking: booking),
      ),
    );

    if (!mounted) return;
    Navigator.of(context).pop(booking);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pharmacy Cart & Booking'),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 820),
              child: _items.isEmpty
                  ? Card(
                      child: Padding(
                        padding: const EdgeInsets.all(40),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.shopping_bag_outlined,
                              size: 56,
                              color: AppTheme.textSecondary,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Your medicine cart is empty',
                              style: theme.textTheme.headlineSmall,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Browse the Medicine Catalog to add medicines and book a delivery.',
                              style: theme.textTheme.bodyMedium,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 24),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 240),
                              child: FilledButton(
                                onPressed: () => Navigator.of(context).pop(),
                                child: const Text('Back to Catalog'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Selected Medicines (${_items.length})',
                            style: theme.textTheme.titleLarge,
                          ),
                          const SizedBox(height: 12),
                          Card(
                            child: Column(
                              children: [
                                for (int i = 0; i < _items.length; i++) ...[
                                  if (i > 0) const Divider(height: 1),
                                  Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                _items[i].medicine.name,
                                                style:
                                                    theme.textTheme.titleMedium,
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                '${_items[i].medicine.formattedPrice} per pack • ${_items[i].medicine.packSize}',
                                                style:
                                                    theme.textTheme.bodyMedium,
                                              ),
                                            ],
                                          ),
                                        ),
                                        IconButton(
                                          tooltip: 'Decrease quantity',
                                          onPressed: () {
                                            setState(() {
                                              if (_items[i].quantity > 1) {
                                                _items[i].quantity--;
                                              } else {
                                                _items.removeAt(i);
                                              }
                                            });
                                          },
                                          icon: const Icon(
                                            Icons.remove_circle_outline,
                                          ),
                                        ),
                                        Text(
                                          '${_items[i].quantity}',
                                          style: theme.textTheme.titleMedium,
                                        ),
                                        IconButton(
                                          tooltip: 'Increase quantity',
                                          onPressed: () {
                                            setState(() {
                                              _items[i].quantity++;
                                            });
                                          },
                                          icon: const Icon(
                                            Icons.add_circle_outline,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          '₹${_items[i].subtotal.toStringAsFixed(0)}',
                                          style: theme.textTheme.titleMedium
                                              ?.copyWith(
                                            color: AppTheme.priceColor(context),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),
                          Text(
                            'Delivery & Booking Details',
                            style: theme.textTheme.titleLarge,
                          ),
                          const SizedBox(height: 12),
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (ProfilePersonalizationService
                                      .instance.addresses.isNotEmpty) ...[
                                    Text(
                                      'Select from Saved Addresses',
                                      style: theme.textTheme.titleMedium,
                                    ),
                                    const SizedBox(height: 8),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: ProfilePersonalizationService
                                          .instance.addresses
                                          .map((addr) {
                                        final selected = _addressCtrl.text ==
                                            addr.fullFormatted;
                                        return ChoiceChip(
                                          avatar: const Icon(
                                            Icons.place_outlined,
                                            size: 16,
                                          ),
                                          label: Text(addr.label),
                                          selected: selected,
                                          onSelected: (_) {
                                            setState(() {
                                              _addressCtrl.text =
                                                  addr.fullFormatted;
                                            });
                                          },
                                        );
                                      }).toList(),
                                    ),
                                    const SizedBox(height: 14),
                                  ],
                                  TextFormField(
                                    controller: _addressCtrl,
                                    decoration: const InputDecoration(
                                      labelText: 'Delivery Address',
                                      prefixIcon:
                                          Icon(Icons.location_on_outlined),
                                    ),
                                    validator: (v) =>
                                        (v == null || v.trim().length < 5)
                                            ? 'Please enter a valid delivery address'
                                            : null,
                                  ),
                                  const SizedBox(height: 18),
                                  Text(
                                    'Preferred Delivery Slot',
                                    style: theme.textTheme.titleMedium,
                                  ),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      'Express 2-Hr Delivery',
                                      'Today by 6:00 PM',
                                      'Tomorrow 9:00 AM',
                                    ].map((slot) {
                                      return ChoiceChip(
                                        label: Text(slot),
                                        selected: _deliverySlot == slot,
                                        onSelected: (_) => setState(
                                            () => _deliverySlot = slot),
                                      );
                                    }).toList(),
                                  ),
                                  const SizedBox(height: 18),
                                  Text(
                                    'Payment Method',
                                    style: theme.textTheme.titleMedium,
                                  ),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      'UPI / Instant QR',
                                      'Cash on Delivery',
                                      'Credit / Debit Card',
                                    ].map((method) {
                                      return ChoiceChip(
                                        label: Text(method),
                                        selected: _paymentMethod == method,
                                        onSelected: (_) => setState(
                                            () => _paymentMethod = method),
                                      );
                                    }).toList(),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Wrap(
                                alignment: WrapAlignment.spaceBetween,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 16,
                                runSpacing: 16,
                                children: [
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Total Payable (Saved to Firebase)',
                                        style: theme.textTheme.bodyMedium
                                            ?.copyWith(fontSize: 13),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '₹${_subtotal.toStringAsFixed(2)}',
                                        style: theme.textTheme.headlineSmall
                                            ?.copyWith(
                                          color: AppTheme.priceColor(context),
                                        ),
                                      ),
                                    ],
                                  ),
                                  SizedBox(
                                    width: 240,
                                    child: FilledButton.icon(
                                      onPressed:
                                          _saving ? null : _confirmBooking,
                                      icon: _saving
                                          ? const SizedBox(
                                              width: 18,
                                              height: 18,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Colors.white,
                                              ),
                                            )
                                          : const Icon(
                                              Icons.check_circle_outline,
                                            ),
                                      label: Text(_saving
                                          ? 'Saving to Firebase...'
                                          : 'Confirm Booking'),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// 3. Booking Confirmation & Acknowledgment Screen (D1 & D2)
// =============================================================================

class BookingConfirmationScreen extends StatelessWidget {
  const BookingConfirmationScreen({super.key, required this.booking});

  final OrderBooking booking;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Booking Confirmation'),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // D2 Live Notification Preview Banner
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryDark,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.primary.withValues(alpha: 0.25),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.16),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.notifications_active_rounded,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'MOBILE NOTIFICATION SENT',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.8,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '✅ Booking Confirmed • Order #${booking.id}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),
                              Text(
                                '${booking.itemsSummary} • ${booking.deliverySlot}',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // D1 Acknowledgment & Firebase Confirmation Card
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Center(
                            child: Container(
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
                                color: AppTheme.accentGreen
                                    .withValues(alpha: 0.12),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.verified_rounded,
                                size: 54,
                                color: AppTheme.accentGreen,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Booking Confirmed!',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.headlineMedium,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Your order acknowledgment has been generated and saved to Firebase Cloud Firestore.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 16),
                          Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.secondary
                                    .withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.cloud_done_outlined,
                                    size: 16,
                                    color: AppTheme.secondary,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Firebase Document: /bookings/${booking.id}',
                                    style: const TextStyle(
                                      color: AppTheme.secondary,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const Divider(height: 32),
                          _ConfirmRow(
                            label: 'Booking Reference',
                            value: '#${booking.id}',
                          ),
                          _ConfirmRow(
                            label: 'Booking Status',
                            value: booking.status,
                          ),
                          _ConfirmRow(
                            label: 'Delivery Slot',
                            value: booking.deliverySlot,
                          ),
                          _ConfirmRow(
                            label: 'Payment Method',
                            value: booking.paymentMethod,
                          ),
                          _ConfirmRow(
                            label: 'Delivery Address',
                            value: booking.address,
                          ),
                          const Divider(height: 28),
                          Text(
                            'Booked Medicines',
                            style: theme.textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          ...booking.itemDetails.map(
                            (item) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.check_circle,
                                    size: 18,
                                    color: AppTheme.accentGreen,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      item,
                                      style: theme.textTheme.bodyLarge,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const Divider(height: 28),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Total Amount Confirmed',
                                style: theme.textTheme.titleMedium,
                              ),
                              Text(
                                '₹${booking.totalAmount.toStringAsFixed(2)}',
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  color: AppTheme.priceColor(context),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 28),
                          OutlinedButton.icon(
                            onPressed: () async {
                              await BookingNotificationService.instance
                                  .showBookingConfirmedNotification(booking);
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context)
                                ..hideCurrentSnackBar()
                                ..showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      '📲 Mobile notification sent for Order #${booking.id}',
                                    ),
                                    backgroundColor: AppTheme.primaryDark,
                                  ),
                                );
                            },
                            icon: const Icon(
                                Icons.notifications_active_outlined),
                            label: const Text(
                              'Send Mobile Notification Again (Demo)',
                            ),
                          ),
                          const SizedBox(height: 12),
                          FilledButton.icon(
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(Icons.receipt_long_rounded),
                            label: const Text('Done • View in My Bookings'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ConfirmRow extends StatelessWidget {
  const _ConfirmRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(fontSize: 14),
          ),
          const SizedBox(width: 16),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
