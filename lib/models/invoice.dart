class Invoice {
  final int? id;
  final String invoiceNumber;
  final int customerId;
  final String? customerName; // Joined

  final DateTime fromDate;
  final DateTime toDate;
  final double totalQuantity;
  final double totalKgFat;

  /// Raw milk-calculation subtotal (sum of all entry amounts).
  final double milkAmount;

  /// Extra bonus/amount to ADD to the milk total (e.g. quality bonus).
  final double extraAmount;

  /// Discount / deduction to SUBTRACT from the milk total.
  final double discount;

  /// Optional note explaining the adjustment.
  final String? adjustmentNote;

  /// Final payable = milkAmount + extraAmount - discount.
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
    this.totalKgFat = 0,
    required this.milkAmount,
    this.extraAmount = 0,
    this.discount = 0,
    this.adjustmentNote,
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
        totalKgFat: totalKgFat,
        milkAmount: milkAmount,
        extraAmount: extraAmount,
        discount: discount,
        adjustmentNote: adjustmentNote,
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
        'total_kgfat': totalKgFat,
        'milk_amount': milkAmount,
        'extra_amount': extraAmount,
        'discount': discount,
        'adjustment_note': adjustmentNote,
        'total_amount': totalAmount,
        'pdf_path': pdfPath,
        'created_at': createdAt.toIso8601String(),
      };

  factory Invoice.fromMap(Map<String, dynamic> map) {
    // milk_amount column may be absent in older rows — fall back to total_amount.
    final milkAmt = (map['milk_amount'] as num?)?.toDouble() ??
        (map['total_amount'] as num).toDouble();
    return Invoice(
      id: map['id'] as int?,
      invoiceNumber: map['invoice_number'] as String,
      customerId: map['customer_id'] as int,
      customerName: map['customer_name'] as String?,
      fromDate: DateTime.parse(map['from_date'] as String),
      toDate: DateTime.parse(map['to_date'] as String),
      totalQuantity: (map['total_quantity'] as num).toDouble(),
      totalKgFat: (map['total_kgfat'] as num?)?.toDouble() ?? 0.0,
      milkAmount: milkAmt,
      extraAmount: (map['extra_amount'] as num?)?.toDouble() ?? 0.0,
      discount: (map['discount'] as num?)?.toDouble() ?? 0.0,
      adjustmentNote: map['adjustment_note'] as String?,
      totalAmount: (map['total_amount'] as num).toDouble(),
      pdfPath: map['pdf_path'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}
