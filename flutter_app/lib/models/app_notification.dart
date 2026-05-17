class AppNotification {
  final String id;
  final String title;
  final String body;
  final String? url;
  final String type;
  final String? category;
  final String? source;
  final String? eventType;
  final String? feedPostId;
  final String? status;
  final String? ctaLabel;
  final DateTime createdAt;
  final bool read;

  const AppNotification({
    required this.id,
    required this.title,
    required this.body,
    this.url,
    required this.type,
    this.category,
    this.source,
    this.eventType,
    this.feedPostId,
    this.status,
    this.ctaLabel,
    required this.createdAt,
    required this.read,
  });

  factory AppNotification.fromApiJson(Map<String, dynamic> json) {
    return AppNotification(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? 'Notifikasi').toString(),
      body: (json['body'] ?? '').toString(),
      url: json['url']?.toString(),
      type: (json['type'] ?? json['segment'] ?? 'info').toString(),
      category: json['category']?.toString(),
      source: json['source']?.toString(),
      eventType: json['eventType']?.toString(),
      feedPostId: (json['feedPostId'] ?? json['videoId'])?.toString(),
      status: json['status']?.toString(),
      ctaLabel: json['ctaLabel']?.toString(),
      createdAt: DateTime.tryParse((json['createdAt'] ?? '').toString()) ??
          DateTime.now(),
      read: json['read'] == true,
    );
  }
}
