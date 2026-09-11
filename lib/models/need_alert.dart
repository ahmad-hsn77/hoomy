enum AlertStatus { open, bought }

class NeedAlert {
  final String id;
  final String title;
  final String note;
  final bool emergency;
  final String quantity;
  final List<String> targetMemberIds;
  final String createdBy;
  final DateTime createdAt;
  final AlertStatus status;
  final String? boughtBy;
  final String? boughtQuantity;
  final String? boughtPrice;
  final DateTime? boughtAt;

  const NeedAlert({
    required this.id,
    required this.title,
    required this.createdBy,
    required this.createdAt,
    this.note = '',
    this.emergency = false,
    this.quantity = '',
    this.targetMemberIds = const [],
    this.status = AlertStatus.open,
    this.boughtBy,
    this.boughtQuantity,
    this.boughtPrice,
    this.boughtAt,
  });

  NeedAlert copyWith({
    AlertStatus? status,
    String? boughtBy,
    String? boughtQuantity,
    String? boughtPrice,
    DateTime? boughtAt,
  }) {
    return NeedAlert(
      id: id,
      title: title,
      note: note,
      emergency: emergency,
      quantity: quantity,
      targetMemberIds: targetMemberIds,
      createdBy: createdBy,
      createdAt: createdAt,
      status: status ?? this.status,
      boughtBy: boughtBy ?? this.boughtBy,
      boughtQuantity: boughtQuantity ?? this.boughtQuantity,
      boughtPrice: boughtPrice ?? this.boughtPrice,
      boughtAt: boughtAt ?? this.boughtAt,
    );
  }
}
