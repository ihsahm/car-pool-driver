import 'package:flutter/material.dart';

class NotAcceptedPage extends StatelessWidget {
  const NotAcceptedPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Text('You have not been accepted yet.'),
      ),
    );
  }
}
