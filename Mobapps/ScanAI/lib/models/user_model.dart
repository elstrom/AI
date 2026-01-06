class UserModel {
  const UserModel({
    required this.id,
    required this.username,
    required this.planType,
    this.planExpiredAt,
    this.createdAt,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['user_id'] is int ? (json['user_id'] as int).toLong() : json['user_id'], // Handle potential int/long issues
      username: json['username'] as String,
      planType: json['plan_type'] as String,
      // Add other fields if necessary
    );
  }

  // Helper for more robust parsing
  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      id: map['id'] ?? map['user_id'] ?? 0,
      username: map['username'] ?? '',
      planType: map['plan_type'] ?? 'unknown',
    );
  }

  final dynamic id;
  final String username;
  final String planType;
  final DateTime? planExpiredAt;
  final DateTime? createdAt;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'plan_type': planType,
      'plan_expired_at': planExpiredAt?.toIso8601String(),
      'created_at': createdAt?.toIso8601String(),
    };
  }
}

extension IntToLong on int {
  int toLong() => this; // Placeholder for dart int (which is 64-bit anyway)
}
