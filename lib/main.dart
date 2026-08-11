import 'package:flutter/material.dart';
import 'package:gemma_poc/features/voice_ai/screens/voice_ai_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const GemmaPocApp());
}

class GemmaPocApp extends StatelessWidget {
  const GemmaPocApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gemma On-Device Voice AI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0F6E56),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      home: const VoiceAiScreen(),
    );
  }
}
