import 'package:deped_reading_app_laravel/constants.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'pages/auth pages/landing_page.dart';

const supabaseUrl = 'https://zrcynmiiduwrtlcyzvzi.supabase.co';
const supabaseAnonKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpyY3lubWlpZHV3cnRsY3l6dnppIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTcyNDExMzIsImV4cCI6MjA3MjgxNzEzMn0.NPDpQKXC5h7qiSTPsIIty8qdNn1DnSHptIkagWlmTHM';

ThemeData buildLightTheme(BuildContext context) {
  return ThemeData.light().copyWith(
    colorScheme: ColorScheme.light(
      primary: kPrimaryColor,
      secondary: kSecondaryColor,
      surface: kLightSurfaceColor,
      background: kLightBackgroundColor,
      onPrimary: kLightOnPrimary,
      onSecondary: kLightOnSecondary,
      onSurface: kLightOnSurface,
      onBackground: kLightOnBackground,
      error: kPrimaryColor,
    ),
    textTheme: Theme.of(context).textTheme
        .copyWith(
          headlineLarge: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            color: kPrimaryColor,
          ),
          headlineMedium: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w600,
            color: kHeadlineMediumColor,
          ),
          headlineSmall: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w500,
            color: kHeadlineSmallColor,
          ),
          bodyLarge: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w400,
            color: kLightOnBackground,
          ),
          bodyMedium: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w400,
            color: const Color.fromARGB(255, 0, 0, 0),
          ),
          bodySmall: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w300,
            color: kHeadlineMediumColor,
          ),
        )
        .apply(fontFamily: 'Poppins'),
  );
}

ThemeData buildDarkTheme(BuildContext context) {
  return ThemeData.dark().copyWith(
    colorScheme: ColorScheme.dark(
      primary: kPrimaryColor,
      secondary: kSecondaryColor,
      surface: kDarkSurfaceColor,
      background: kDarkBackgroundColor,
      onPrimary: kDarkOnPrimary,
      onSecondary: kDarkOnSecondary,
      onSurface: kDarkOnSurface,
      onBackground: kDarkOnBackground,
      error: kPrimaryColor,
    ),
    textTheme: Theme.of(context).textTheme
        .copyWith(
          headlineLarge: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            color: kSecondaryColor,
          ),
          headlineMedium: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w600,
            color: kPrimaryColor,
          ),
          headlineSmall: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w500,
            color: kHeadlineSmallColor,
          ),
          bodyLarge: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w400,
            color: kDarkOnBackground,
          ),
          bodyMedium: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w400,
            color: kHeadlineMediumColor,
          ),
          bodySmall: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w300,
            color: kSecondaryColor,
          ),
        )
        .apply(fontFamily: 'Poppins'),
  );
}

final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.light);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (context, currentTheme, child) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildLightTheme(context),
          darkTheme: buildDarkTheme(context),
          themeMode: currentTheme,
          home: const LandingPage(),
        );
      },
    );
  }
}
