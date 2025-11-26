class DiscoveredUser {
  final String userId;
  final String nickname;
  final DateTime lastSeen;

  DiscoveredUser({
    required this.userId,
    required this.nickname,
    required this.lastSeen,
  });

  DiscoveredUser copyWith({
    String? userId,
    String? nickname,
    DateTime? lastSeen,
  }) {
    return DiscoveredUser(
      userId: userId ?? this.userId,
      nickname: nickname ?? this.nickname,
      lastSeen: lastSeen ?? this.lastSeen,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DiscoveredUser &&
          runtimeType == other.runtimeType &&
          userId == other.userId;

  @override
  int get hashCode => userId.hashCode;
}

