class Brief {
  const Brief({
    required this.success,
    required this.text,
    this.audioUrl,
  });

  final bool success;
  final String text;
  final String? audioUrl;

  factory Brief.fromJson(Map<String, dynamic> json) {
    return Brief(
      success: (json['success'] as bool?) ?? false,
      text: (json['text'] as String?) ?? '',
      audioUrl: json['audio_url'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'success': success,
      'text': text,
      'audio_url': audioUrl,
    };
  }
}
