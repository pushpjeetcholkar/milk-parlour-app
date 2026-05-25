class MilkEntry {
  final int? id;
  final int customerId;
  final String? customerName; // Joined field, not stored in DB
  final DateTime date;
  final double quantity;
  final double clr;
  final double fat;
  final double rate;
  final double kgFat;
  final double amount;
  final String shift;       // 'Morning' or 'Evening'
  final String? entryTime;  // HH:mm format, e.g. '09:35'

  MilkEntry({
    this.id,
    required this.customerId,
    this.customerName,
    required this.date,
    required this.quantity,
    required this.clr,
    required this.fat,
    required this.rate,
    required this.kgFat,
    required this.amount,
    this.shift = 'Morning',
    this.entryTime,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'customer_id': customerId,
        'date': date.toIso8601String(),
        'quantity': quantity,
        'clr': clr,
        'fat': fat,
        'rate': rate,
        'kgfat': kgFat,
        'amount': amount,
        'shift': shift,
        'entry_time': entryTime,
      };

  factory MilkEntry.fromMap(Map<String, dynamic> map) => MilkEntry(
        id: map['id'] as int?,
        customerId: map['customer_id'] as int,
        customerName: map['customer_name'] as String?,
        date: DateTime.parse(map['date'] as String),
        quantity: (map['quantity'] as num).toDouble(),
        clr: (map['clr'] as num).toDouble(),
        fat: (map['fat'] as num).toDouble(),
        rate: (map['rate'] as num).toDouble(),
        kgFat: (map['kgfat'] as num).toDouble(),
        amount: (map['amount'] as num).toDouble(),
        shift: map['shift'] as String? ?? 'Morning',
        entryTime: map['entry_time'] as String?,
      );
}
