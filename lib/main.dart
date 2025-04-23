import 'package:flutter/material.dart';
import 'package:graduation_project/TextRecognitionScreen.dart';
//import 'text_recognition_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: TextRecognitionScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
