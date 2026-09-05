class ImagePrompt {
  final String id;
  final String imageUrl;
  final String category;
  final String hiddenPrompt;
  final bool isPremium;

  ImagePrompt({
    required this.id,
    required this.imageUrl,
    required this.category,
    required this.hiddenPrompt,
    this.isPremium = false,
  });

  factory ImagePrompt.fromMap(Map<String, dynamic> data, String id) {
    return ImagePrompt(
      id: id,
      imageUrl: data['imageUrl'] ?? '',
      category: data['category'] ?? 'General',
      hiddenPrompt: data['hiddenPrompt'] ?? '',
      isPremium: data['isPremium'] ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'imageUrl': imageUrl,
      'category': category,
      'hiddenPrompt': hiddenPrompt,
      'isPremium': isPremium,
    };
  }

  factory ImagePrompt.fromJson(Map<String, dynamic> json) {
    return ImagePrompt(
      id: json['id'],
      imageUrl: json['imageUrl'],
      category: json['category'],
      hiddenPrompt: json['hiddenPrompt'],
      isPremium: json['isPremium'] ?? false,
    );
  }
}
