/// Model representing an authenticated app user
class AppUser {
  final String id;
  final String name;
  final String? email;
  final String? photoUrl;

  const AppUser({
    required this.id,
    required this.name,
    this.email,
    this.photoUrl,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AppUser &&
        other.id == id &&
        other.name == name &&
        other.email == email &&
        other.photoUrl == photoUrl;
  }

  @override
  int get hashCode => Object.hash(id, name, email, photoUrl);
}

