class Customer {
  final int? id;
  final String name;
  final String? mobile;
  final String? address;
  final DateTime createdAt;

  Customer({
    this.id,
    required this.name,
    this.mobile,
    this.address,
    required this.createdAt,
  });

  Customer copyWith({
    int? id,
    String? name,
    String? mobile,
    String? address,
    DateTime? createdAt,
  }) {
    return Customer(
      id: id ?? this.id,
      name: name ?? this.name,
      mobile: mobile ?? this.mobile,
      address: address ?? this.address,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'mobile': mobile,
        'address': address,
        'created_at': createdAt.toIso8601String(),
      };

  factory Customer.fromMap(Map<String, dynamic> map) => Customer(
        id: map['id'] as int?,
        name: map['name'] as String,
        mobile: map['mobile'] as String?,
        address: map['address'] as String?,
        createdAt: DateTime.parse(map['created_at'] as String),
      );

  @override
  String toString() => 'Customer(id: $id, name: $name)';
}
