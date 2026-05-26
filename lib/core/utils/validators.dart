import '../constants/app_constants.dart';

class Validators {
  static String? validateCustomerName(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Customer name is required';
    }
    if (value.trim().length < 2) {
      return 'Name must be at least 2 characters';
    }
    return null;
  }

  static String? validateMobile(String? value) {
    if (value == null || value.trim().isEmpty) return null; // Optional
    if (!RegExp(r'^\d{10}$').hasMatch(value.trim())) {
      return 'Enter a valid 10-digit mobile number';
    }
    return null;
  }

  static String? validateQuantity(String? value) {
    if (value == null || value.trim().isEmpty) return 'Quantity is required';
    final d = double.tryParse(value.trim());
    if (d == null) return 'Enter a valid number';
    if (d < AppConstants.minQuantity) return 'Quantity must be greater than 0';
    return null;
  }

  static String? validateFat(String? value) {
    if (value == null || value.trim().isEmpty) return 'FAT is required';
    final d = double.tryParse(value.trim());
    if (d == null) return 'Enter a valid number';
    if (d < AppConstants.minFat || d > AppConstants.maxFat) {
      return 'FAT must be between 0 and 15';
    }
    return null;
  }

  static String? validateClr(String? value) {
    if (value == null || value.trim().isEmpty) return null; // CLR is optional
    final d = double.tryParse(value.trim());
    if (d == null) return 'Enter a valid number';
    return null;
  }

  static String? validateRate(String? value) {
    if (value == null || value.trim().isEmpty) return 'Rate is required';
    final d = double.tryParse(value.trim());
    if (d == null) return 'Enter a valid number';
    if (d < AppConstants.minRate) return 'Rate must be greater than 0';
    return null;
  }
}
