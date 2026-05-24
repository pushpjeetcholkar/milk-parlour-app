class Invoice {
  final int? id;
  final String invoiceNumber;
  final int customerId;
  final String? customerName; // Joined
  final DateTime fromDate;
  final DateTime toDate;
  final double totalQuantity;
  final double totalAmount;
  final String? pdfPath;
  final DateTime createdAt;

  Invoice({
    this.id,
    required this.invoiceNumber,
    required this.customerId,
    this.customerName,
    required this.fromDate,
    required this.toDate,
    required this.totalQuantity,
    required this.totalAmount,
    this.pdfPath,
    required this.createdAt,
  });

  Invoice copyWith({String? pdfPath}) => Invoice(
        id: id,
        invoiceNumber: invoiceNumber,
        customerId: customerId,
        customerName: customerName,
        fromDate: fromDate,
        toDate: toDate,
        totalQuantity: totalQuantity,
        totalAmount: totalAmount,
        pdfPath: pdfPath ?? this.pdfPath,
        createdAt: createdAt,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'invoice_number': invoiceNumber,
        'customer_id': customerId,
        'from_date': fromDate.toIso8601String(),
        'to_date': toDate.toIso8601String(),
        'total_quantity': totalQuantity,
        'total_amount': totalAmount,
        'pdf_path': pdfPath,
        'created_at': createdAt.toIso8601String(),
      };

  factory Invoice.fromMap(Map<String, dynamic> map) => Invoice(
        id: map['id'] as int?,
        invoiceNumber: map['invoice_number'] as String,
        customerId: map['customer_id'] as int,
        customerName: map['customer_name'] as String?,
        fromDate: DateTime.parse(map['from_date'] as String),
        toDate: DateTime.parse(map['to_date'] as String),
        totalQuantity: (map['total_quantity'] as num).toDouble(),
        totalAmount: (map['total_amount'] as num).toDouble(),
        pdfPath: map['pdf_path'] as String?,
        createdAt: DateTime.parse(map['created_at'] as String),
      );
}
