import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/app_role_provider.dart';
import '../../../core/theme.dart';
import '../../../core/utils/zw_validators.dart';
import '../../onboarding/providers/onboarding_provider.dart';
import '../../onboarding/models/onboarding_profile.dart';

Future<void> _editPhone(
    BuildContext context, WidgetRef ref, String? current) async {
  final controller = TextEditingController(
      text: (current == null || current == '—') ? '' : current);

  final normalised = await showDialog<String>(
    context: context,
    builder: (ctx) {
      String? error;
      return StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          backgroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(
            'Phone Number',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: RideBaseTheme.textPrimary,
            ),
          ),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.phone,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9+\s\-]'))
            ],
            autofocus: true,
            onChanged: (_) {
              if (error != null) setState(() => error = null);
            },
            style: GoogleFonts.plusJakartaSans(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: RideBaseTheme.textPrimary,
            ),
            decoration: InputDecoration(
              hintText: '077 123 4567 or +263 77 123 4567',
              hintStyle: GoogleFonts.plusJakartaSans(
                color: RideBaseTheme.textSecondary,
                fontSize: 13,
              ),
              errorText: error,
              errorStyle: GoogleFonts.plusJakartaSans(fontSize: 12),
              filled: true,
              fillColor: RideBaseTheme.secondaryContainer,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:
                    BorderSide(color: RideBaseTheme.error, width: 1.5),
              ),
              focusedErrorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:
                    BorderSide(color: RideBaseTheme.error, width: 1.5),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                'Cancel',
                style: GoogleFonts.plusJakartaSans(
                  color: RideBaseTheme.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            TextButton(
              onPressed: () {
                final parsed = parseZwNumber(controller.text);
                if (parsed == null) {
                  setState(() => error = zwPhoneError);
                } else {
                  Navigator.pop(ctx, parsed);
                }
              },
              child: Text(
                'Save',
                style: GoogleFonts.plusJakartaSans(
                  color: RideBaseTheme.teal,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      );
    },
  );

  if (normalised != null && context.mounted) {
    try {
      await ref
          .read(onboardingProvider.notifier)
          .updateProfile(phoneNumber: normalised);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to update phone number')),
        );
      }
    }
  }
}

Future<void> _editCity(
    BuildContext context, WidgetRef ref, String? current) async {
  final selected = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 12),
        Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Select City',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: RideBaseTheme.textPrimary,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        for (final city in zwCities) ...[
          InkWell(
            onTap: () => Navigator.pop(ctx, city),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      city,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: RideBaseTheme.textPrimary,
                      ),
                    ),
                  ),
                  if ((current == city))
                    const Icon(Icons.check_rounded,
                        size: 18, color: RideBaseTheme.teal),
                ],
              ),
            ),
          ),
          if (city != zwCities.last)
            Divider(height: 1, color: Colors.black.withValues(alpha: 0.06)),
        ],
        const SizedBox(height: 16),
      ],
    ),
  );

  if (selected != null && context.mounted) {
    try {
      await ref
          .read(onboardingProvider.notifier)
          .updateProfile(city: selected);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to update city')),
        );
      }
    }
  }
}

// Returns the value, or '—' for null/empty strings.
String _orDash(String? v) => (v == null || v.trim().isEmpty) ? '—' : v;

Future<void> _pickImage(BuildContext context, WidgetRef ref) async {
  final picker = ImagePicker();
  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          ListTile(
            leading: const Icon(Icons.photo_library_rounded, color: RideBaseTheme.teal),
            title: Text('Photo Gallery', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
            onTap: () => Navigator.pop(ctx, ImageSource.gallery),
          ),
          ListTile(
            leading: const Icon(Icons.camera_alt_rounded, color: RideBaseTheme.teal),
            title: Text('Camera', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
            onTap: () => Navigator.pop(ctx, ImageSource.camera),
          ),
          const SizedBox(height: 12),
        ],
      ),
    ),
  );

  if (source != null) {
    final image = await picker.pickImage(
      source: source,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 75,
    );

    if (image != null && context.mounted) {
      try {
        await ref.read(onboardingProvider.notifier).updateProfile(profilePhoto: image);
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to upload photo: $e')),
          );
        }
      }
    }
  }
}

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Navigate to home the moment the user becomes unauthenticated (logout).
    ref.listen<AuthState>(authProvider, (_, next) {
      if (!next.isAuthenticated && context.mounted) {
        context.go('/home');
      }
    });

    final user = ref.watch(currentUserProvider);
    final onboarding = ref.watch(onboardingProvider);
    final profile = onboarding.profile;
    final isUpdating = onboarding.isUpdating;

    // Guard: if user is null mid-render, show nothing — the listener above
    // will redirect to /home before the next frame.
    if (user == null) {
      return const Scaffold(backgroundColor: RideBaseTheme.surface);
    }

    final displayName = profile?.fullName ?? user.displayName;
    final initial = displayName[0].toUpperCase();
    final isVerified = user.emailVerified;

    return Scaffold(
      backgroundColor: RideBaseTheme.surface,
      body: Stack(
        children: [
          SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Hero zone — gradient fades into surface ─────────────
                Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    RideBaseTheme.secondaryContainer,
                    RideBaseTheme.surface,
                  ],
                  stops: const [0.0, 1.0],
                ),
              ),
              child: SafeArea(
                bottom: false,
                child: Column(
                  children: [
                    // Nav row
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 4),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: IconButton(
                          icon: const Icon(Icons.arrow_back_rounded),
                          color: RideBaseTheme.textPrimary,
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Avatar
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        GestureDetector(
                          onTap: () => _pickImage(context, ref),
                          child: Container(
                            width: 96,
                            height: 96,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white,
                              border:
                                  Border.all(color: Colors.white, width: 4),
                              boxShadow: [
                                BoxShadow(
                                  color:
                                      Colors.black.withValues(alpha: 0.12),
                                  blurRadius: 20,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: profile?.profilePhotoUrl != null
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(48),
                                    child: Image.network(
                                      profile!.profilePhotoUrl!,
                                      width: 96,
                                      height: 96,
                                      fit: BoxFit.cover,
                                      errorBuilder: (context, error, stackTrace) =>
                                          Center(
                                        child: Text(
                                          initial,
                                          style: GoogleFonts.plusJakartaSans(
                                            fontSize: 40,
                                            fontWeight: FontWeight.w700,
                                            color: RideBaseTheme.teal,
                                          ),
                                        ),
                                      ),
                                    ),
                                  )
                                : Center(
                                    child: Text(
                                      initial,
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 40,
                                        fontWeight: FontWeight.w700,
                                        color: RideBaseTheme.teal,
                                      ),
                                    ),
                                  ),
                          ),
                        ),
                        // Edit overlay
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: GestureDetector(
                            onTap: () => _pickImage(context, ref),
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: RideBaseTheme.teal,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 3),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.2),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.camera_alt_rounded,
                                color: Colors.white,
                                size: 18,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 14),

                    // Name
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          displayName,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            color: RideBaseTheme.textPrimary,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 4),

                    // Email
                    Text(
                      _orDash(user.email),
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        color: RideBaseTheme.textSecondary,
                      ),
                    ),

                    const SizedBox(height: 8),

                    // Verified label
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (isVerified) ...[
                          const Icon(
                            Icons.verified_rounded,
                            color: RideBaseTheme.teal,
                            size: 14,
                          ),
                          const SizedBox(width: 4),
                        ],
                        Text(
                          isVerified ? 'VERIFIED RIDER' : 'RIDER',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: RideBaseTheme.textSecondary,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 28),
                  ],
                ),
              ),
            ),

            // ── Stats bar ───────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              child: _StatsBar(),
            ),

            // ── Sections ────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 48),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Personal Information
                  const _SectionLabel(
                    title: 'Personal Information',
                  ),
                  const SizedBox(height: 10),
                  _Card(
                    children: [
                      _InfoRow(
                        icon: Icons.phone_outlined,
                        label: 'Phone',
                        value: _orDash(profile?.phoneNumber),
                        onEdit: () => _editPhone(context, ref, profile?.phoneNumber),
                      ),
                      const _RowDivider(),
                      _InfoRow(
                        icon: Icons.location_city_outlined,
                        label: 'City',
                        value: _orDash(profile?.city),
                        onEdit: () => _editCity(context, ref, profile?.city),
                      ),
                    ],
                  ),

                  const SizedBox(height: 28),

                  // Recent Rides
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const _SectionLabel(title: 'Recent Rides'),
                      GestureDetector(
                        onTap: () => Navigator.of(context).pop(),
                        child: Row(
                          children: [
                            Text(
                              'View All',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: RideBaseTheme.teal,
                              ),
                            ),
                            const Icon(
                              Icons.arrow_forward_ios_rounded,
                              size: 12,
                              color: RideBaseTheme.teal,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _Card(
                    children: const [
                      _RideRow(
                        destination: 'Avondale Shopping Centre',
                        time: 'Today, 09:42 AM',
                        price: r'$4.50',
                      ),
                      _RowDivider(),
                      _RideRow(
                        destination: "Sam Levy's Village",
                        time: 'Yesterday, 14:15 PM',
                        price: r'$8.00',
                      ),
                    ],
                  ),

                  const SizedBox(height: 28),

                  // Settings
                  const _SectionLabel(title: 'Settings'),
                  const SizedBox(height: 10),
                  _Card(
                    children: [
                      _SettingsRow(
                        icon: Icons.notifications_outlined,
                        label: 'Notifications',
                        onTap: () {},
                      ),
                      const _RowDivider(),
                      _SettingsRow(
                        icon: Icons.security_outlined,
                        label: 'Security & Privacy',
                        onTap: () {},
                      ),
                    ],
                  ),

                  const SizedBox(height: 36),

                  // Sign Out
                  Center(
                    child: Consumer(
                      builder: (context, ref, _) {
                        final isLoading =
                            ref.watch(authProvider).isLoading;
                        return TextButton.icon(
                          onPressed: isLoading
                              ? null
                              : () => ref
                                  .read(authProvider.notifier)
                                  .logout(),
                          icon: const Icon(Icons.logout_rounded, size: 18),
                          label: Text(
                            'Sign Out',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          style: TextButton.styleFrom(
                            foregroundColor: RideBaseTheme.error,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
              ],
            ),
          ),
          if (isUpdating)
            Container(
              color: Colors.black.withOpacity(0.3),
              child: const Center(
                child: CircularProgressIndicator(),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Stats bar ─────────────────────────────────────────────────────────────────

class _StatsBar extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final onboarding = ref.watch(onboardingProvider);
    final profile = onboarding.profile;

    if (profile == null) return const SizedBox.shrink();

    // Show stats based on intent or role.
    // If they are in driver mode, show driver stats.
    final currentRole = ref.watch(appRoleProvider);
    final stats = currentRole == AppRole.driver ? profile.driverStats : profile.riderStats;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            Expanded(
              child: _StatCell(
                value: stats.rating.toStringAsFixed(1),
                icon: Icons.star_rounded,
                label: 'Rating',
              ),
            ),
            VerticalDivider(width: 1, color: Colors.black.withValues(alpha: 0.06)),
            Expanded(
              child: _StatCell(
                value: stats.ridesCompleted.toString(),
                icon: Icons.directions_car_rounded,
                label: 'Rides',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell({required this.value, required this.icon, required this.label});
  final String value;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Column(
        children: [
          Icon(icon, size: 24, color: RideBaseTheme.teal),
          const SizedBox(height: 6),
          Text(
            value,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: RideBaseTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: RideBaseTheme.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Section label ─────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        title.toUpperCase(),
        style: GoogleFonts.plusJakartaSans(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: RideBaseTheme.textSecondary,
          letterSpacing: 1.0,
        ),
      ),
    );
  }
}

// ── Card ─────────────────────────────────────────────────────────────────────

class _Card extends StatelessWidget {
  const _Card({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      clipBehavior: Clip.hardEdge,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

class _RowDivider extends StatelessWidget {
  const _RowDivider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 76),
      child: Divider(
        height: 1,
        color: Colors.black.withValues(alpha: 0.06),
      ),
    );
  }
}

// ── Row types ─────────────────────────────────────────────────────────────────

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.onEdit,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: [
          // Rounded-square icon container
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: RideBaseTheme.secondaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              size: 20,
              color: RideBaseTheme.onSecondaryContainer,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    color: RideBaseTheme.textSecondary,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: RideBaseTheme.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          if (onEdit != null)
            GestureDetector(
              onTap: onEdit,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: RideBaseTheme.teal.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.edit_outlined,
                  size: 16,
                  color: RideBaseTheme.teal,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RideRow extends StatelessWidget {
  const _RideRow({
    required this.destination,
    required this.time,
    required this.price,
  });

  final String destination;
  final String time;
  final String price;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: RideBaseTheme.surfaceContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.directions_car_outlined,
              size: 20,
              color: RideBaseTheme.textSecondary,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  destination,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: RideBaseTheme.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  time,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: RideBaseTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            price,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: RideBaseTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: RideBaseTheme.surfaceContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                size: 20,
                color: RideBaseTheme.textSecondary,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: RideBaseTheme.textPrimary,
                ),
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              size: 22,
              color: RideBaseTheme.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}
