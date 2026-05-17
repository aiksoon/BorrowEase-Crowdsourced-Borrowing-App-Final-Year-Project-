import 'package:flutter/material.dart';
import 'screens/screens.dart';
import 'utils/navigator_key.dart';
import 'services/api_client.dart';

const Color _ecoTeal = Color(0xFF0D9488);
const Color _appBg = Color(0xFFF9FAFB);

void main() {
  runApp(const BorrowingApp());
}

class BorrowingApp extends StatelessWidget {
  const BorrowingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BorrowEase',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: _ecoTeal),
        scaffoldBackgroundColor: _appBg,
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Colors.grey[800],
          elevation: 0,
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          selectedItemColor: _ecoTeal,
        ),
        textTheme: TextTheme(
          headlineSmall: TextStyle(
            color: Colors.grey[800],
            fontWeight: FontWeight.bold,
          ),
          titleLarge: TextStyle(
            color: Colors.grey[800],
            fontWeight: FontWeight.w700,
          ),
          titleMedium: TextStyle(
            color: Colors.grey[800],
            fontWeight: FontWeight.w600,
          ),
          bodyMedium: TextStyle(color: Colors.grey[500]),
          bodySmall: TextStyle(color: Colors.grey[500]),
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          shadowColor: Colors.black.withOpacity(0.05),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: _ecoTeal,
            foregroundColor: Colors.white,
            minimumSize: const Size(0, 50),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            textStyle: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
            elevation: 0,
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: _ecoTeal,
            minimumSize: const Size(0, 50),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            side: BorderSide(color: _ecoTeal.withOpacity(0.25)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            textStyle: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: _ecoTeal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            textStyle: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          hintStyle: TextStyle(color: Colors.grey[400], fontSize: 14),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey[200]!),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _ecoTeal, width: 1.4),
          ),
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: _ecoTeal,
          foregroundColor: Colors.white,
        ),
        chipTheme: ChipThemeData(
          backgroundColor: _ecoTeal.withOpacity(0.1),
          selectedColor: _ecoTeal.withOpacity(0.18),
          labelStyle: const TextStyle(color: _ecoTeal),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide.none,
          ),
        ),
        fontFamily: 'SF Pro Display',
      ),
      // 🎯 Low-fi phone frame so Chrome looks like a real mobile shell
      home: Scaffold(
        backgroundColor: Colors.grey[300],
        body: Center(
          child: Container(
            width: 390, // iPhone 14 width
            height: 844, // iPhone 14 height
            decoration: BoxDecoration(
              color: _appBg,
              borderRadius: BorderRadius.circular(40),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 30,
                  offset: const Offset(0, 15),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            // Nested Navigator keeps pages inside the phone frame
            child: FutureBuilder<String?>(
              future: TokenStore().getToken(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final hasToken = (snapshot.data ?? '').isNotEmpty;
                final initialPage = hasToken ? const MainNavigationPage() : const WelcomePage();
                return Navigator(
                  key: phoneNavigatorKey,
                  onGenerateRoute: (settings) {
                    return MaterialPageRoute(builder: (context) => initialPage);
                  },
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
