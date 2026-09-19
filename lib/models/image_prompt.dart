class ImagePrompt {
  final String id;
  final String imageUrl;
  final String category;
  final String hiddenPrompt;
  final bool isPremium;

  /// 'male' | 'female' | 'unisex' | 'couple' — controls which prompts show
  /// up in a given user's gallery, and whether generation needs 2 photos.
  final String gender;

  /// Drafts sitting in the admin panel for review are unpublished; missing
  /// on old docs is treated as published so nothing already live is hidden.
  final bool isPublished;

  ImagePrompt({
    required this.id,
    required this.imageUrl,
    required this.category,
    required this.hiddenPrompt,
    this.isPremium = false,
    this.gender = 'unisex',
    this.isPublished = true,
  });

  factory ImagePrompt.fromMap(Map<String, dynamic> data, String id) {
    return ImagePrompt(
      id: id,
      imageUrl: data['imageUrl'] ?? '',
      category: data['category'] ?? 'General',
      hiddenPrompt: data['hiddenPrompt'] ?? '',
      isPremium: data['isPremium'] ?? false,
      gender: data['gender'] ?? 'unisex',
      isPublished: data['isPublished'] ?? true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'imageUrl': imageUrl,
      'category': category,
      'hiddenPrompt': hiddenPrompt,
      'isPremium': isPremium,
      'gender': gender,
      'isPublished': isPublished,
    };
  }

  factory ImagePrompt.fromJson(Map<String, dynamic> json) {
    return ImagePrompt(
      id: json['id'],
      imageUrl: json['imageUrl'],
      category: json['category'],
      hiddenPrompt: json['hiddenPrompt'],
      isPremium: json['isPremium'] ?? false,
      gender: json['gender'] ?? 'unisex',
      isPublished: json['isPublished'] ?? true,
    );
  }
}
