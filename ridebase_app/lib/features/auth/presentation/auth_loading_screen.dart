import 'package:flutter/material.dart';
import '../../../core/theme.dart';

class AuthLoadingScreen extends StatelessWidget {
  const AuthLoadingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: RideBaseTheme.teal,
      body: Center(
        child: CircularProgressIndicator(
          color: RideBaseTheme.white,
        ),
      ),
    );
  }
}
