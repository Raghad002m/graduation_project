

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';
import 'dart:ui' as ui;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Get available cameras
  final cameras = await availableCameras();
  final firstCamera = cameras.first;

  runApp(
    MaterialApp(
      theme: ThemeData.dark(),
      home: YoloDetectionApp(camera: firstCamera),
    ),
  );
}

class YoloDetectionApp extends StatefulWidget {
  final CameraDescription camera;

  const YoloDetectionApp({Key? key, required this.camera}) : super(key: key);

  @override
  _YoloDetectionAppState createState() => _YoloDetectionAppState();
}

class _YoloDetectionAppState extends State<YoloDetectionApp> {
  late CameraController _controller;
  late Future<void> _initializeControllerFuture;
  bool _isDetecting = false;
  late Interpreter _interpreter;
  bool _modelLoaded = false;
  List<Map<String, dynamic>> _detections = [];

  // Define anchors and classes for YOLO
  List<String> _labels = [];

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _loadModel();
  }

  Future<void> _initializeCamera() async {
    _controller = CameraController(
      widget.camera,
      ResolutionPreset.medium,
      enableAudio: false,
    );

    _initializeControllerFuture = _controller.initialize();
  }

  Future<void> _loadModel() async {
    try {
      // Copy model and labels file to accessible location
      await _copyModelToLocalStorage();

      // Load labels
      final labelData = await rootBundle.loadString('assets/labels.txt');
      _labels = labelData.split('\n');

      // Get model path
      final appDir = await getApplicationDocumentsDirectory();
      final modelPath = '${appDir.path}/yolov8n_float32.tflite';

      // Load interpreter
      final options = InterpreterOptions()..threads = 4;
      _interpreter =
          await Interpreter.fromFile(File(modelPath), options: options);

      setState(() {
        _modelLoaded = true;
      });

      print('Model loaded successfully');
    } catch (e) {
      print('Failed to load model: $e');
    }
  }

  Future<void> _copyModelToLocalStorage() async {
    final appDir = await getApplicationDocumentsDirectory();
    final modelPath = '${appDir.path}/yolov8n_float32.tflite';

    // Check if model already exists
    final modelFile = File(modelPath);
    if (!await modelFile.exists()) {
      // Copy model from assets
      final modelData = await rootBundle.load('assets/yolov8n_float32.tflite');
      await modelFile.writeAsBytes(modelData.buffer.asUint8List());
    }
  }

  Future<void> _detectObjects(CameraImage image) async {
    if (_isDetecting || !_modelLoaded) return;

    _isDetecting = true;

    try {
      // Convert image to format for model input
      final inputData = _prepareInputData(image);

      // Allocate output tensors
      // Output shape depends on your YOLO model variant
      // Typically for YOLOv5 [1, 25200, 85] where 85 = 5 (box) + 80 (classes)
      final outputShape = [1, 25200, 85];
      final outputBuffer =
          List.filled(outputShape[0] * outputShape[1] * outputShape[2], 0.0);

      // Run inference
      final inputs = [inputData];
      final outputs = {0: outputBuffer};

      _interpreter.runForMultipleInputs(inputs, outputs);

      // Process results
      final results =
          _processOutputs(outputBuffer, outputShape, image.width, image.height);

      setState(() {
        _detections = results;
      });
    } catch (e) {
      print('Error during detection: $e');
    } finally {
      _isDetecting = false;
    }
  }

  List<dynamic> _prepareInputData(CameraImage image) {
    // Convert YUV to RGB (simplified)
    // Note: This is a basic conversion and may need optimization
    final inputSize = 640; // Typical YOLO input size

    // Conversion logic would typically go here
    // For simplicity, let's return placeholder data - in a real app you'd convert the camera image

    return [List.filled(1 * inputSize * inputSize * 3, 0.0)];
  }

  List<Map<String, dynamic>> _processOutputs(List<double> outputBuffer,
      List<int> outputShape, int imageWidth, int imageHeight) {
    // Process YOLO outputs to get bounding boxes, scores, classes
    // This is simplified and would need to be adjusted for your specific YOLO model

    final List<Map<String, dynamic>> detections = [];
    final int gridSize = outputShape[1]; // Number of grid cells
    final int numClasses = outputShape[2] - 5; // Number of classes

    // Confidence threshold
    const double confThreshold = 0.5;

    // Process each grid cell
    for (int i = 0; i < gridSize; i++) {
      final objectConfidence = outputBuffer[i * outputShape[2] + 4];

      if (objectConfidence > confThreshold) {
        // Calculate class scores
        int classId = 0;
        double maxScore = 0.0;

        for (int j = 0; j < numClasses; j++) {
          final score = outputBuffer[i * outputShape[2] + 5 + j];
          if (score > maxScore) {
            maxScore = score;
            classId = j;
          }
        }

        // Confidence check with class probability
        final confidence = objectConfidence * maxScore;
        if (confidence > confThreshold) {
          // Get bounding box
          final x = outputBuffer[i * outputShape[2]];
          final y = outputBuffer[i * outputShape[2] + 1];
          final w = outputBuffer[i * outputShape[2] + 2];
          final h = outputBuffer[i * outputShape[2] + 3];

          // Convert to image coordinates
          final boxX = (x - w / 2) * imageWidth;
          final boxY = (y - h / 2) * imageHeight;
          final boxW = w * imageWidth;
          final boxH = h * imageHeight;

          detections.add({
            'bbox': [boxX, boxY, boxW, boxH],
            'class': classId < _labels.length ? _labels[classId] : 'unknown',
            'confidence': confidence,
          });
        }
      }
    }

    return detections;
  }

  void _startDetection() async {
    try {
      // Ensure camera is initialized
      await _initializeControllerFuture;

      setState(() {
        _isDetecting = true;
      });

      // Start image stream
      _controller.startImageStream((CameraImage image) {
        _detectObjects(image);
      });
    } catch (e) {
      print('Error starting detection: $e');
    }
  }

  void _stopDetection() {
    if (_controller.value.isStreamingImages) {
      _controller.stopImageStream();
    }

    setState(() {
      _isDetecting = false;
      _detections = [];
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    if (_modelLoaded) {
      _interpreter.close();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('YOLO Object Detection')),
      body: FutureBuilder<void>(
        future: _initializeControllerFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            return Stack(
              children: [
                // Camera preview
                CameraPreview(_controller),

                // Detection overlays
                CustomPaint(
                  painter: DetectionPainter(detections: _detections),
                  size: Size(
                    MediaQuery.of(context).size.width,
                    MediaQuery.of(context).size.height,
                  ),
                ),
              ],
            );
          } else {
            return const Center(child: CircularProgressIndicator());
          }
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _isDetecting ? _stopDetection : _startDetection,
        child: Icon(_isDetecting ? Icons.stop : Icons.play_arrow),
      ),
    );
  }
}

class DetectionPainter extends CustomPainter {
  final List<Map<String, dynamic>> detections;

  DetectionPainter({required this.detections});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..color = Colors.red;

    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.left,
    );

    for (final detection in detections) {
      final bbox = detection['bbox'] as List<dynamic>;
      final className = detection['class'] as String;
      final confidence = detection['confidence'] as double;

      // Draw bounding box
      final rect = Rect.fromLTWH(
        bbox[0],
        bbox[1],
        bbox[2],
        bbox[3],
      );
      canvas.drawRect(rect, paint);

      // Draw label
      final textSpan = TextSpan(
        text: '$className ${(confidence * 100).toStringAsFixed(1)}%',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16.0,
          backgroundColor: Colors.red,
        ),
      );

      textPainter.text = textSpan;
      textPainter.layout();
      textPainter.paint(canvas, Offset(bbox[0], bbox[1] - 20));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
