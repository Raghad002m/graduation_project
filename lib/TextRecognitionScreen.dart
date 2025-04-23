import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:permission_handler/permission_handler.dart';


class TextRecognitionScreen extends StatefulWidget {
  const TextRecognitionScreen({super.key});

  @override
  State<TextRecognitionScreen> createState() => _TextRecognitionScreenState();
}

class _TextRecognitionScreenState extends State<TextRecognitionScreen> {
  CameraController? _cameraController;
  bool _isDetecting = false;
  late TextRecognizer _textRecognizer;
  final FlutterTts _flutterTts = FlutterTts();

  String _recognizedText = "";
  String _currentLanguage = "English-US";

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
    _setTtsLanguage();
  }

  Future<void> _setTtsLanguage() async {
    await _flutterTts.setLanguage(_currentLanguage);
    await _flutterTts.setSpeechRate(0.5);
  }

  void _toggleLanguage() async {
    setState(() {
      _currentLanguage = _currentLanguage == "English-US" ? "Arabic " : "English-US";
    });
    await _setTtsLanguage();
  }

  Future<void> _initializeCamera() async {
    await Permission.camera.request();
    final cameras = await availableCameras();
    final camera = cameras.first;

    _cameraController = CameraController(
      camera,
      ResolutionPreset.medium,
      enableAudio: false,
    );

    await _cameraController!.initialize();
    if (!mounted) return;
    setState(() {});
    _cameraController!.startImageStream(_processCameraImage);
  }

  Future<void> _processCameraImage(CameraImage image) async {
    if (_isDetecting) return;
    _isDetecting = true;

    try {
      final WriteBuffer allBytes = WriteBuffer();
      for (Plane plane in image.planes) {
        allBytes.putUint8List(plane.bytes);
      }

      final bytes = allBytes.done().buffer.asUint8List();
      final Size imageSize = Size(image.width.toDouble(), image.height.toDouble());

      final inputImage = InputImage.fromBytes(
        bytes: bytes,
        metadata: InputImageMetadata(
          size: imageSize,
          rotation: InputImageRotation.rotation0deg,
          format: InputImageFormat.nv21,
          bytesPerRow: image.planes[0].bytesPerRow,
        ),
      );

      final RecognizedText recognizedText = await _textRecognizer.processImage(inputImage);
      final newText = recognizedText.text.trim();

      if (newText.isNotEmpty && newText != _recognizedText) {
        setState(() {
          _recognizedText = newText;
        });
        await _flutterTts.setLanguage(_currentLanguage);
        await _flutterTts.speak(newText);
      }
    } catch (e) {
      print("Error: $e");
    } finally {
      _isDetecting = false;
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _textRecognizer.close();
    _flutterTts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("📸 Text Detection"),
        actions: [
          IconButton(
            icon: const Icon(Icons.language),
            onPressed: _toggleLanguage,
            tooltip: "Language",
          ),
        ],
      ),
      body: Stack(
        children: [
          CameraPreview(_cameraController!),
          Container(
            alignment: Alignment.bottomCenter,
            padding: const EdgeInsets.all(16),
            color: Colors.black54,
            child: Text(
              _recognizedText,
              style: const TextStyle(color: Colors.white, fontSize: 20),
            ),
          ),
        ],
      ),
    );
  }
}
