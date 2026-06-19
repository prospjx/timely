import 'package:flutter/material.dart';
import 'package:kairos/screens/splash/splash_screen.dart';
import 'package:kairos/screens/shell/app_shell.dart';

class AppRoutes {
  static const String splash = '/splash';
  static const String dashboard = '/';
  static const String account = '/account';

  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case splash:
        return MaterialPageRoute<void>(
          builder: (_) => const SplashScreen(),
          settings: settings,
        );
      case account:
        return MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Center(child: Text('Account'))),
          settings: settings,
        );
      case dashboard:
      default:
        return MaterialPageRoute<void>(
          builder: (_) => const AppShell(),
          settings: settings,
        );
    }
  }
}
