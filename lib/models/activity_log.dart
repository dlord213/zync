class ActivityLog {
  final int? id;
  final String fileName;
  final String targetDeviceName;
  final String type; // 'sent' or 'received'
  final int timestamp;

  ActivityLog({
    this.id,
    required this.fileName,
    required this.targetDeviceName,
    required this.type,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'fileName': fileName,
      'targetDeviceName': targetDeviceName,
      'type': type,
      'timestamp': timestamp,
    };
  }

  factory ActivityLog.fromMap(Map<String, dynamic> map) {
    return ActivityLog(
      id: map['id'],
      fileName: map['fileName'],
      targetDeviceName: map['targetDeviceName'],
      type: map['type'],
      timestamp: map['timestamp'],
    );
  }
}
