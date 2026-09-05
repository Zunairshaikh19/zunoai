import 'package:cloud_firestore/cloud_firestore.dart';

enum HistoryStatus { success, failed, processing }

class HistoryItem {
  final String id;
  final String? outputUrl;
  final String promptCategory;
  final DateTime timestamp;
  final HistoryStatus status;
  final String? errorMessage;

  HistoryItem({
    required this.id,
    this.outputUrl,
    required this.promptCategory,
    required this.timestamp,
    this.status = HistoryStatus.success,
    this.errorMessage,
  });

  factory HistoryItem.fromMap(Map<String, dynamic> data, String id) {
    HistoryStatus status;
    switch (data['status']) {
      case 'failed':
        status = HistoryStatus.failed;
        break;
      case 'processing':
        status = HistoryStatus.processing;
        break;
      default:
        status = HistoryStatus.success;
    }

    return HistoryItem(
      id: id,
      outputUrl: data['outputUrl'],
      promptCategory: data['promptCategory'] ?? 'General',
      timestamp: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
      status: status,
      errorMessage: data['errorMessage'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'outputUrl': outputUrl,
      'promptCategory': promptCategory,
      'timestamp': Timestamp.fromDate(timestamp),
      'status': status.name,
      'errorMessage': errorMessage,
    };
  }
}
