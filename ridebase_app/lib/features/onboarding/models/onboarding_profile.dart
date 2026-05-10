class UserStats {
  final double rating;
  final int ridesCompleted;

  UserStats({required this.rating, required this.ridesCompleted});

  factory UserStats.fromJson(Map<String, dynamic> json) {
    return UserStats(
      rating: (json['rating'] as num?)?.toDouble() ?? 5.0,
      ridesCompleted: json['rides_completed'] as int? ?? 0,
    );
  }
}

class OnboardingProfile {
  final String fullName;
  final String phoneNumber;
  final String city;
  final String email;
  final bool isRider;
  final bool isDriver;
  final String roleIntent;
  final bool emailVerified;
  final String? profilePhotoUrl;
  final UserStats driverStats;
  final UserStats riderStats;

  OnboardingProfile({
    required this.fullName,
    required this.phoneNumber,
    required this.city,
    required this.email,
    required this.isRider,
    required this.isDriver,
    required this.roleIntent,
    required this.emailVerified,
    this.profilePhotoUrl,
    required this.driverStats,
    required this.riderStats,
  });

  factory OnboardingProfile.fromJson(Map<String, dynamic> json) {
    return OnboardingProfile(
      fullName: json['full_name'] ?? '',
      phoneNumber: json['phone_number'] ?? '',
      city: json['city'] ?? '',
      email: json['email'] ?? '',
      isRider: json['is_rider'] ?? true,
      isDriver: json['is_driver'] ?? false,
      roleIntent: json['role_intent'] ?? 'RIDER',
      emailVerified: json['email_verified'] ?? false,
      profilePhotoUrl: json['profile_photo_url'],
      driverStats: UserStats.fromJson(json['driver_stats'] ?? {}),
      riderStats: UserStats.fromJson(json['rider_stats'] ?? {}),
    );
  }
}
