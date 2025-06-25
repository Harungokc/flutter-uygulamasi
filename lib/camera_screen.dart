import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:image/image.dart' as img_lib;
import 'package:tflite_flutter/tflite_flutter.dart';

// IsolateData ve diğer global fonksiyonlar aynı kalıyor.
class IsolateData {
  final CameraImage cameraImage;
  final int interpreterAddress;
  final List<String> labels;
  IsolateData(this.cameraImage, this.interpreterAddress, this.labels);
}

void imageProcessor(SendPort sendPort) async {
  final port = ReceivePort();
  sendPort.send(port.sendPort);
  await for (final IsolateData isolateData in port) {
    final cameraImage = isolateData.cameraImage;
    final interpreter = Interpreter.fromAddress(isolateData.interpreterAddress);
    final labels = isolateData.labels;
    final input = await _preprocessImage(cameraImage);
    final outputShape = interpreter.getOutputTensor(0).shape;
    final output = List.generate(
      outputShape[0],
      (_) => List.generate(
        outputShape[1],
        (_) => List.filled(outputShape[2], 0.0),
      ),
    );
    interpreter.run(input, output);
    final List<Map<String, dynamic>> results = [];
    final transposedOutput = _transpose(output[0]);
    for (var i = 0; i < transposedOutput.length; i++) {
      final detection = transposedOutput[i];
      final scores = detection.sublist(4);
      var maxScore = 0.0;
      var bestClassIndex = -1;
      for (var j = 0; j < scores.length; j++) {
        if (scores[j] > maxScore) {
          maxScore = scores[j];
          bestClassIndex = j;
        }
      }

      // HATA AYIKLAMA 1: Modelin gördüğü her şeyi düşük bir eşikle konsola yazdıralım.
      if (maxScore > 0.10) {
        debugPrint("MODEL GÖRDÜ -> Sınıf: ${labels[bestClassIndex]}, Güven: ${maxScore.toStringAsFixed(2)}");
      }
      
      // Bu asıl filtremiz, sesli uyarı için kullanılıyor.
      if (maxScore > 0.10) { 
        final box = detection.sublist(0, 4);
        final rect = Rect.fromCenter(
          center: Offset(box[0] / 640, box[1] / 640),
          width: box[2] / 640,
          height: box[3] / 640,
        );
        results.add({
          "rect": rect,
          "label": labels[bestClassIndex],
          "confidence": maxScore,
        });
      }
    }
    sendPort.send(results);
  }
}

Future<List<List<List<List<double>>>>> _preprocessImage(CameraImage image) async {
  final img_lib.Image convertedImage = await _convertYUV420toImageColor(image);
  final resizedImage = img_lib.copyResize(convertedImage, width: 640, height: 640);
  var inputTensor = List.generate(1, 
    (_) => List.generate(640, (y) => List.generate(640, (x) {
      final pixel = resizedImage.getPixel(x, y);
      return [pixel.r / 255.0, pixel.g / 255.0, pixel.b / 255.0];
    }))
  );
  return inputTensor;
}

Future<img_lib.Image> _convertYUV420toImageColor(CameraImage image) async {
  final int width = image.width;
  final int height = image.height;
  final int uvRowStride = image.planes[1].bytesPerRow;
  final int uvPixelStride = image.planes[1].bytesPerPixel!;
  final yPlane = image.planes[0].bytes;
  final uPlane = image.planes[1].bytes;
  final vPlane = image.planes[2].bytes;
  img_lib.Image rgbImage = img_lib.Image(width: width, height: height);
  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      final int uvIndex = uvPixelStride * (x / 2).floor() + uvRowStride * (y / 2).floor();
      final int index = y * width + x;
      final yp = yPlane[index];
      final up = uPlane[uvIndex];
      final vp = vPlane[uvIndex];
      int r = (yp + 1.402 * (vp - 128)).round();
      int g = (yp - 0.344136 * (up - 128) - 0.714136 * (vp - 128)).round();
      int b = (yp + 1.772 * (up - 128)).round();
      rgbImage.setPixelRgb(x, y, r.clamp(0, 255), g.clamp(0, 255), b.clamp(0, 255));
    }
  }
  return rgbImage;
}

List<List<double>> _transpose(List<List<double>> matrix) {
  if (matrix.isEmpty) return [];
  int rowCount = matrix.length;
  int colCount = matrix[0].length;
  List<List<double>> transposed = List.generate(colCount, (_) => List.filled(rowCount, 0.0));
  for (int i = 0; i < rowCount; i++) {
    for (int j = 0; j < colCount; j++) {
      transposed[j][i] = matrix[i][j];
    }
  }
  return transposed;
}

class CameraScreen extends StatefulWidget {
  final CameraDescription camera;
  const CameraScreen({super.key, required this.camera});
  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> with WidgetsBindingObserver {
  late CameraController _controller;
  late Future<void> _initializeControllerFuture;
  
  Interpreter? _interpreter;
  List<String>? _labels;
  
  final FlutterTts _flutterTts = FlutterTts();
  String _lastAnnouncedLabel = '';
  DateTime? _lastAnnouncementTime;
  final Duration _announcementCooldown = const Duration(seconds: 7);
  
  Isolate? _isolate;
  late ReceivePort _receivePort;
  late SendPort _sendPort;
  bool _isDetecting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeTts();
    _controller = CameraController(
      widget.camera,
      ResolutionPreset.medium,
      enableAudio: false,
    );

    _initializeControllerFuture = _controller.initialize().then((_) async {
      if (!mounted) return;
      await _loadModelAndLabels();
      await _startIsolate();
      _controller.startImageStream((CameraImage image) {
        if (!_isDetecting) {
          _isDetecting = true;
          _sendPort.send(IsolateData(image, _interpreter!.address, _labels!));
        }
      });
      setState(() {});
    });
  }

  Future<void> _initializeTts() async {
    await _flutterTts.setLanguage("tr-TR");
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.setVolume(1.0);
    await _flutterTts.awaitSpeakCompletion(true);
  }

  Future<void> _loadModelAndLabels() async {
    try {
      _interpreter = await Interpreter.fromAsset('assets/models/yolov8n_float32.tflite');
      final labelData = await rootBundle.loadString('assets/models/labels.txt');
      _labels = labelData.split('\n').where((s) => s.isNotEmpty).toList();
      debugPrint('Model ve etiketler başarıyla yüklendi.');
    } catch (e) {
      debugPrint('Model veya etiketler yüklenirken hata oluştu: $e');
    }
  }

  Future<void> _startIsolate() async {
    _receivePort = ReceivePort();
    _isolate = await Isolate.spawn(imageProcessor, _receivePort.sendPort);
    _receivePort.listen((dynamic data) {
      if (data is SendPort) {
        _sendPort = data;
      } else if (data is List<Map<String, dynamic>>) {
        _handleDetectionResults(data);
        _isDetecting = false;
      }
    });
  }
  
  void _handleDetectionResults(List<Map<String, dynamic>> results) {
    // HATA AYIKLAMA 2: Isolate'den ana arayüze veri gelip gelmediğini kontrol et.
    debugPrint("Ana Arayüze ${results.length} adet filtrelenmiş sonuç ulaştı.");

    if (results.isEmpty) return;
    
    results.sort((a, b) => (b['confidence'] as double).compareTo(a['confidence'] as double));
    final bestResult = results.first;

    final String label = bestResult['label'];
    final double confidence = bestResult['confidence'];
    
    final now = DateTime.now();

    if (label == _lastAnnouncedLabel && 
        _lastAnnouncementTime != null && 
        now.difference(_lastAnnouncementTime!) < _announcementCooldown) {
      return;
    }
    
    debugPrint("Sesli Bildirim Tetiklendi: $label, Güven: $confidence");
    
    _flutterTts.speak("Önünüzde bir $label var.");
    
    _lastAnnouncedLabel = label;
    _lastAnnouncementTime = now;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _isolate?.kill(priority: Isolate.immediate);
    _receivePort.close();
    _flutterTts.stop();
    if (_controller.value.isInitialized) {
      _controller.stopImageStream();
    }
    _controller.dispose();
    super.dispose();
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_controller.value.isInitialized) return;
    if (state == AppLifecycleState.paused) {
      if (_controller.value.isStreamingImages) _controller.stopImageStream();
    } else if (state == AppLifecycleState.resumed) {
      if (!_controller.value.isStreamingImages) {
        _controller.startImageStream((image) {
          if (!_isDetecting) {
            _isDetecting = true;
            _sendPort.send(IsolateData(image, _interpreter!.address, _labels!));
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("DuruGörü - Engel Tespiti")),
      body: FutureBuilder<void>(
        future: _initializeControllerFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            return CameraPreview(_controller);
          } else {
            return const Center(child: CircularProgressIndicator());
          }
        },
      ),
    );
  }
}