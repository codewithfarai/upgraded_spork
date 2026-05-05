class OnboardingProfile {
  final String fullName;
  final String phoneNumber;
  final String city;
  final String email;
  final bool isRider;
  final bool isDriver;
  final String roleIntent;
  final bool emailVerified;

  OnboardingProfile({
    required this.fullName,
    required this.phoneNumber,
    required this.city,
    required this.email,
    required this.isRider,
    required this.isDriver,
    required this.roleIntent,
    required this.emailVerified,
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
    );
  }
}
