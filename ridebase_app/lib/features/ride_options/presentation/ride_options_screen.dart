import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme.dart';

/// Ride tier data
class RideTier {
  final String id;
  final String name;
  final String description;
  final IconData icon;
  final double baseFare;
  final double perKmRate;
  final int estimatedMinutes;
  final int capacity;

  const RideTier({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    required this.baseFare,
    required this.perKmRate,
    required this.estimatedMinutes,
    required this.capacity,
  });
}

const _tiers = [
  RideTier(
    id: 'MINI',
    name: 'Mini',
    description: 'Affordable everyday rides',
    icon: Icons.directions_car_outlined,
    baseFare: 1.50,
    perKmRate: 0.40,
    estimatedMinutes: 3,
    capacity: 3,
  ),
  RideTier(
    id: 'STANDARD',
    name: 'Standard',
    description: 'Comfortable sedan',
    icon: Icons.directions_car_filled_rounded,
    baseFare: 2.00,
    perKmRate: 0.55,
    estimatedMinutes: 5,
    capacity: 4,
  ),
  RideTier(
    id: 'PRO',
    name: 'Pro',
    description: 'Premium ride experience',
    icon: Icons.star_rounded,
    baseFare: 3.50,
    perKmRate: 0.80,
    estimatedMinutes: 7,
    capacity: 4,
  ),
];

class RideOptionsScreen extends StatefulWidget {
  const RideOptionsScreen({
    super.key,
    this.distanceKm,
    this.pickup,
    this.destination,
  });

  final double? distanceKm;
  final String? pickup;
  final String? destination;

  @override
  State<RideOptionsScreen> createState() => _RideOptionsScreenState();
}

class _RideOptionsScreenState extends State<RideOptionsScreen> {
  String _selectedId = 'STANDARD';
  late final TextEditingController _fareController;
  final TextEditingController _commentController = TextEditingController();

  static const double _minFare = 2.00;

  double _estimateFare(RideTier tier) {
    final km = widget.distanceKm ?? 5.0;
    return tier.baseFare + (tier.perKmRate * km);
  }

  RideTier get _selected => _tiers.firstWhere((t) => t.id == _selectedId);

  @override
  void initState() {
    super.initState();
    final initial = _estimateFare(_tiers.firstWhere((t) => t.id == _selectedId));
    _fareController = TextEditingController(text: initial.toStringAsFixed(2));
  }

  @override
  void dispose() {
    _fareController.dispose();
    _commentController.dispose();
    super.dispose();
  }

  void _onTierTap(String tierId) {
    setState(() => _selectedId = tierId);
    final fare = _estimateFare(_tiers.firstWhere((t) => t.id == tierId));
    _fareController.text = fare.toStringAsFixed(2);
  }

  double get _parsedFare {
    final v = double.tryParse(_fareController.text) ?? _minFare;
    return v < _minFare ? _minFare : v;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.black87, size: 28),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Choose a ride',
          style: GoogleFonts.inter(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // ── Route Summary ──────────────────────────────────────────
          if (widget.pickup != null || widget.destination != null)
            _RouteSummary(
              pickup: widget.pickup ?? 'Pickup',
              destination: widget.destination ?? 'Destination',
              distanceKm: widget.distanceKm,
            ),

          const SizedBox(height: 8),

          // ── Tier List ──────────────────────────────────────────────
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              itemCount: _tiers.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, i) {
                final tier = _tiers[i];
                final selected = tier.id == _selectedId;
                final fare = _estimateFare(tier);
                return _TierCard(
                  tier: tier,
                  estimatedFare: fare,
                  isSelected: selected,
                  onTap: () => _onTierTap(tier.id),
                );
              },
            ),
          ),

          // ── Offer & Comment ────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Divider(height: 24),
                // Fare input
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Your offer',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              color: RideBaseTheme.textSecondary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _fareController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                            ],
                            style: GoogleFonts.inter(
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              color: RideBaseTheme.teal,
                            ),
                            decoration: InputDecoration(
                              prefixText: 'USD ',
                              prefixStyle: GoogleFonts.inter(
                                fontSize: 16,
                                color: RideBaseTheme.textSecondary,
                                fontWeight: FontWeight.w500,
                              ),
                              helperText: 'Min USD ${_minFare.toStringAsFixed(2)}',
                              helperStyle: GoogleFonts.inter(fontSize: 12, color: RideBaseTheme.textSecondary),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: Colors.grey.shade200),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: RideBaseTheme.teal, width: 2),
                              ),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Comment input
                TextField(
                  controller: _commentController,
                  maxLines: 2,
                  maxLength: 200,
                  style: GoogleFonts.inter(fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Add a note for your driver... (optional)',
                    hintStyle: GoogleFonts.inter(fontSize: 14, color: Colors.grey.shade400),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade200),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: RideBaseTheme.teal, width: 2),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    counterStyle: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade400),
                  ),
                ),
              ],
            ),
          ),

          // ── Book Button ────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            child: SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pop({
                    'offerAmount': _parsedFare,
                    'comments': _commentController.text.trim().isEmpty ? null : _commentController.text.trim(),
                  });
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: RideBaseTheme.primaryContainer,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Find ${_selected.name} drivers',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '· USD ${_parsedFare.toStringAsFixed(2)}',
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RouteSummary extends StatelessWidget {
  const _RouteSummary({
    required this.pickup,
    required this.destination,
    this.distanceKm,
  });

  final String pickup;
  final String destination;
  final double? distanceKm;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: RideBaseTheme.teal, width: 2.5),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  pickup,
                  style: GoogleFonts.inter(fontSize: 14, color: Colors.black87),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 4.5),
            child: Row(
              children: [
                Container(width: 1, height: 20, color: Colors.grey.shade300),
              ],
            ),
          ),
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: RideBaseTheme.teal,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  destination,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.black87,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (distanceKm != null)
                Text(
                  '${distanceKm!.toStringAsFixed(1)} km',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: RideBaseTheme.textSecondary,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TierCard extends StatelessWidget {
  const _TierCard({
    required this.tier,
    required this.estimatedFare,
    required this.isSelected,
    required this.onTap,
  });

  final RideTier tier;
  final double estimatedFare;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? RideBaseTheme.teal.withValues(alpha: 0.06)
              : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? RideBaseTheme.teal : Colors.grey.shade200,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            // Icon
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: isSelected
                    ? RideBaseTheme.teal.withValues(alpha: 0.1)
                    : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                tier.icon,
                size: 28,
                color: isSelected ? RideBaseTheme.teal : RideBaseTheme.textSecondary,
              ),
            ),
            const SizedBox(width: 14),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tier.name,
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    tier.description,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: RideBaseTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.access_time_rounded,
                          size: 13, color: RideBaseTheme.textSecondary),
                      const SizedBox(width: 3),
                      Text(
                        '~${tier.estimatedMinutes} min',
                        style: GoogleFonts.inter(
                            fontSize: 12, color: RideBaseTheme.textSecondary),
                      ),
                      const SizedBox(width: 10),
                      Icon(Icons.person_rounded,
                          size: 13, color: RideBaseTheme.textSecondary),
                      const SizedBox(width: 3),
                      Text(
                        '${tier.capacity} seats',
                        style: GoogleFonts.inter(
                            fontSize: 12, color: RideBaseTheme.textSecondary),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Price
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'USD',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: RideBaseTheme.textSecondary,
                  ),
                ),
                Text(
                  estimatedFare.toStringAsFixed(2),
                  style: GoogleFonts.inter(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: isSelected ? RideBaseTheme.teal : Colors.black87,
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
