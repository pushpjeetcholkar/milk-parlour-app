import 'milk_entry.dart';

enum ScanStatus { valid, hasWarnings, hasErrors }

/// Represents one data row parsed from a scanned register page.
class ScannedEntry {
  int? sr;
  int? customerId;
  DateTime? date;
  String? shift;     // 'Morning' or 'Evening'
  String? milkType;  // 'Cow' or 'Buffalo'
  double? quantity;
  double? fat;
  double? rate;
  double? kgFat;
  String? itemName;
  double? itemAmount;
  double? amount;

  final String rawLine;
  List<String> errors   = [];
  List<String> warnings = [];
  bool selected = true; // include in batch save

  ScannedEntry({required this.rawLine});

  // ── Status ──────────────────────────────────────────────────────────────────

  ScanStatus get status {
    if (errors.isNotEmpty) return ScanStatus.hasErrors;
    if (warnings.isNotEmpty) return ScanStatus.hasWarnings;
    return ScanStatus.valid;
  }

  bool get isValid  => errors.isEmpty;
  bool get canSave  => isValid &&
      customerId != null && date != null && shift != null &&
      milkType   != null && quantity != null && fat != null;

  // ── Calculate derived fields ─────────────────────────────────────────────────

  void calculate(double defaultRate) {
    rate ??= defaultRate;
    if (quantity != null && fat != null) {
      kgFat ??= double.parse(
          ((quantity! * fat!) / 100.0).toStringAsFixed(4));
    }
    if (quantity != null && fat != null && rate != null) {
      amount ??= double.parse(
          (quantity! * fat! * rate!).toStringAsFixed(2));
    }
  }

  // ── Validate ─────────────────────────────────────────────────────────────────

  void validate() {
    errors.clear();
    warnings.clear();

    // Mandatory
    if (customerId == null)       errors.add('Customer ID (CID) is missing');
    else if (customerId! <= 0)    errors.add('Invalid CID: $customerId');
    if (date == null)             errors.add('Date is missing');
    if (shift == null)            errors.add('Shift (M/E) is missing');
    if (milkType == null)         errors.add('Milk type (C/B) is missing');
    if (quantity == null)         errors.add('Quantity is missing');
    else if (quantity! <= 0)      errors.add('Quantity must be > 0');
    if (fat == null)              errors.add('FAT% is missing');
    else if (fat! <= 0 || fat! > 20)
      warnings.add('FAT% ${fat!.toStringAsFixed(2)}% seems unusual');

    // Optional / calculable
    if (rate == null)   warnings.add('Rate not found — default rate will be used');
    if (kgFat == null)  warnings.add('KG Fat will be auto-calculated');
    if (amount == null) warnings.add('Amount will be auto-calculated');

    // Sanity
    if (quantity != null && quantity! > 300)
      warnings.add('Quantity ${quantity!.toStringAsFixed(1)} L seems very high');
  }

  // ── Convert to MilkEntry for DB insert ──────────────────────────────────────

  MilkEntry toMilkEntry() => MilkEntry(
        customerId: customerId!,
        date:       date!,
        quantity:   quantity!,
        clr:        0.0, // CLR not captured in register format
        fat:        fat!,
        rate:       rate!,
        kgFat:      kgFat!,
        amount:     amount!,
        shift:      shift!,
        milkType:   milkType ?? 'Cow',
        itemName:   itemName,
        itemAmount: itemAmount ?? 0.0,
      );

  // ── Copy with edits ──────────────────────────────────────────────────────────

  ScannedEntry copyWith({
    int? customerId,
    DateTime? date,
    String? shift,
    String? milkType,
    double? quantity,
    double? fat,
    double? rate,
    double? kgFat,
    String? itemName,
    double? itemAmount,
    double? amount,
  }) {
    final c = ScannedEntry(rawLine: rawLine)
      ..sr          = sr
      ..customerId  = customerId  ?? this.customerId
      ..date        = date        ?? this.date
      ..shift       = shift       ?? this.shift
      ..milkType    = milkType    ?? this.milkType
      ..quantity    = quantity    ?? this.quantity
      ..fat         = fat         ?? this.fat
      ..rate        = rate        ?? this.rate
      ..kgFat       = kgFat       ?? this.kgFat
      ..itemName    = itemName    ?? this.itemName
      ..itemAmount  = itemAmount  ?? this.itemAmount
      ..amount      = amount      ?? this.amount
      ..selected    = selected;
    return c;
  }
}
