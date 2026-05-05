import 'dart:convert';

/// Decoded user profile from the Authentik OIDC ID token / userinfo.
class RideBaseUser {
  final String sub;
  final String? preferredUsername;
  final String? email;
  final bool emailVerified;
  final List<String> groups;
  final bool isSubscribed;
  final int? authentikPk;

  const RideBaseUser({
    required this.sub,
    this.preferredUsername,
    this.email,
    this.emailVerified = false,
    this.groups = const [],
    this.isSubscribed = false,
    this.authentikPk,
  });

  /// Parse from a decoded JWT claims map (ID token payload).
  factory RideBaseUser.fromIdToken(Map<String, dynamic> claims) {
    return RideBaseUser(
      sub: claims['sub'] as String? ?? '',
      preferredUsername: claims['preferred_username'] as String?,
      email: claims['email'] as String?,
      emailVerified: claims['email_verified'] as bool? ?? false,
      groups: (claims['groups'] as List<dynamic>?)
              ?.map((g) => g.toString())
              .toList() ??
          [],
      isSubscribed: claims['is_subscribed'] as bool? ?? false,
      authentikPk: claims['authentik_pk'] as int?,
    );
  }

  /// Decode a JWT ID token string and extract user info.
  factory RideBaseUser.fromJwt(String idToken) {
    final parts = idToken.split('.');
    if (parts.length != 3) {
      throw FormatException('Invalid JWT: expected 3 parts, got ${parts.length}');
    }

    // Decode the payload (part 1), adding padding if needed
    String payload = parts[1];
    switch (payload.length % 4) {
      case 2:
        payload += '==';
        break;
      case 3:
        payload += '=';
        break;
    }

    final decoded = utf8.decode(base64Url.decode(payload));
    final claims = json.decode(decoded) as Map<String, dynamic>;
    return RideBaseUser.fromIdToken(claims);
  }

  bool get isDriver => groups.contains('ridebase_drivers');
  bool get isRider => groups.contains('ridebase_riders');

  /// Display name: prefer username, fall back to email, then 'User'.
  String get displayName => preferredUsername ?? email ?? 'User';

  @override
  String toString() =>
      'RideBaseUser(sub: $sub, username: $preferredUsername, email: $email, groups: $groups)';
}
