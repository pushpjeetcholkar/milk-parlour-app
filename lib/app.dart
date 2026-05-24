import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'providers/customer_provider.dart';
import 'providers/milk_entry_provider.dart';
import 'providers/invoice_provider.dart';

import 'screens/splash/splash_screen.dart';
import 'screens/dashboard/dashboard_screen.dart';
import 'screens/customers/customer_list_screen.dart';
import 'screens/customers/add_customer_screen.dart';
import 'screens/milk_entry/add_milk_entry_screen.dart';
import 'screens/invoice/invoice_list_screen.dart';
import 'screens/reports/reports_screen.dart';
import 'screens/backup/backup_screen.dart';
import 'screens/settings/settings_screen.dart';

class MilkParlourApp extends StatelessWidget {
  const MilkParlourApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => CustomerProvider()),
        ChangeNotifierProvider(create: (_) => MilkEntryProvider()),
        ChangeNotifierProvider(create: (_) => InvoiceProvider()),
      ],
      child: MaterialApp(
        title: 'HKMC Milk App',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blue,
            brightness: Brightness.light,
          ),
          useMaterial3: true,
          appBarTheme: AppBarTheme(
            backgroundColor: Colors.blue.shade700,
            foregroundColor: Colors.white,
            elevation: 2,
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue.shade700,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
          cardTheme: CardTheme(
            elevation: 2,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
          ),
          inputDecorationTheme: InputDecorationTheme(
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10)),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
        ),
        initialRoute: '/',
        routes: {
          '/': (_) => const SplashScreen(),
          '/dashboard': (_) => const DashboardScreen(),
          '/customers': (_) => const CustomerListScreen(),
          '/add-customer': (_) => const AddCustomerScreen(),
          '/add-milk-entry': (_) => const AddMilkEntryScreen(),
          '/invoices': (_) => const InvoiceListScreen(),
          '/reports': (_) => const ReportsScreen(),
          '/backup': (_) => const BackupScreen(),
          '/settings': (_) => const SettingsScreen(),
        },
      ),
    );
  }
}
