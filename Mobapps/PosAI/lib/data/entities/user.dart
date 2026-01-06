/// lib/data/entities/user.dart
/// User model for authentication.
library;

class User {

  User({
    required this.id,
    required this.username,
    this.planType = 'free',
    this.planExpiredAt,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['user_id'] as int? ?? json['id'] as int,
      username: json['username'] as String,
      planType: json['plan_type'] as String? ?? 'free',
      planExpiredAt: json['plan_expired_at'] != null
          ? DateTime.tryParse(json['plan_expired_at'] as String)
          : null,
    );
  }
  final int id;
  final String username;
  final String planType;
  final DateTime? planExpiredAt;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'plan_type': planType,
      'plan_expired_at': planExpiredAt?.toIso8601String(),
    };
  }

  /// Alias for backward compatibility
  int get userId => id;

  bool get isPremium => planType == 'premium' || planType == 'pro';
  bool get isFree => planType == 'free';
  bool get isExpired =>
      planType == 'expired' ||
      (planExpiredAt != null && planExpiredAt!.isBefore(DateTime.now()));
}
