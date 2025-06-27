// camera_screen.dart - TESPİT SORUNLARI DÜZELTİLDİ
import 'dart:math' as math;
import 'dart:async';
import 'dart:isolate';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_application_1/tr_labels.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:image/image.dart' as img_lib;
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:vibration/vibration.dart';

// Isolate'a veri göndermek için kullanılan sınıf
class IsolateData {
  final CameraImage cameraImage;
  final int interpreterAddress;
  final List<String> labels;
  IsolateData(this.cameraImage, this.interpreterAddress, this.labels);
}

// Ayrı bir iş parçacığında (Isolate) çalışacak olan görüntü işleme fonksiyonu
void imageProcessor(SendPort sendPort) async {
  final port = ReceivePort();
  sendPort.send(port.sendPort);

  Interpreter? interpreter; // Interpreter başta null

  port.listen((dynamic data) async {
    if (data is IsolateData) {
      // Interpreter daha önce oluşturulmamışsa oluştur
      interpreter ??= Interpreter.fromAddress(data.interpreterAddress);

      final cameraImage = data.cameraImage;
      final labels = data.labels;

      try {
        final input = await _preprocessImage(cameraImage);
        final output = List.filled(1 * 84 * 8400, 0.0).reshape([1, 84, 8400]);

        interpreter!.run(input, output);

        // Modelin çıktısını işle
        final List<List<double>> typedMatrix = (output[0] as List)
            .map<List<double>>((e) => List<double>.from(e))
            .toList();

        final transposedOutput = _transpose(typedMatrix);

        final List<Map<String, dynamic>> results = [];

        for (var i = 0; i < transposedOutput.length; i++) {
          final detection = transposedOutput[i];

          final box = detection.sublist(0, 4);
          final scores = detection.sublist(4);

          var maxScore = 0.0;
          var bestClassIndex = -1;

          for (var j = 0; j < scores.length; j++) {
            if (scores[j] > maxScore) {
              maxScore = scores[j];
              bestClassIndex = j;
            }
          }

          if (maxScore > 0.1 &&
              bestClassIndex >= 0 &&
              bestClassIndex < labels.length) {
            final rect = Rect.fromLTWH(
              box[1] - box[3] / 2, // x - width/2
              box[0] - box[2] / 2, // y - height/2
              box[3], // width
              box[2], // height
            );
            results.add({
              "rect": rect,
              "label": labels[bestClassIndex],
              "confidence": maxScore,
              "classIndex": bestClassIndex,
            });
          }
        }

        final suppressed = nonMaximumSuppression(results, 0.5);

        final mappedResults = suppressed.map((detection) {
          final rect = detection['rect'] as Rect;
          return {
            'label': detection['label'],
            'score':
                detection['confidence'], // confidence değil score kullandığın için değiştirdim
            'rect': {
              'left': rect.left,
              'top': rect.top,
              'width': rect.width,
              'height': rect.height,
            },
          };
        }).toList();

        sendPort.send(mappedResults);
      } catch (e) {
        debugPrint("Görüntü işleme hatası: $e");
        sendPort.send([]);
      }
    } else if (data == 'dispose') {
      // Dispose talebi gelirse interpreter'ı kapat ve portu kapat
      interpreter?.close();
      interpreter = null;
      port.close();
    }
  });
}

// ... [Kodun geri kalımı aynı kalır]

Future<List<List<List<List<double>>>>> _preprocessImage(
  CameraImage image,
) async {
  try {
    final img_lib.Image convertedImage = await _convertYUV420toImageColor(
      image,
    );
    final img_lib.Image rotatedImage = img_lib.copyRotate(
      convertedImage,
      angle: 90,
    );
    final resizedImage = img_lib.copyResize(
      rotatedImage,
      width: 640,
      height: 640,
    );

    // Görüntüyü normalize et (0-1 aralığına)
    var inputTensor = List.generate(
      1,
      (_) => List.generate(
        640,
        (y) => List.generate(640, (x) {
          final pixel = resizedImage.getPixel(x, y);
          return [pixel.r / 255.0, pixel.g / 255.0, pixel.b / 255.0];
        }),
      ),
    );
    return inputTensor;
  } catch (e) {
    debugPrint("Görüntü ön işleme hatası: $e");
    rethrow;
  }
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
      final int uvIndex =
          uvPixelStride * (x / 2).floor() + uvRowStride * (y / 2).floor();
      final int index = y * width + x;

      final yp = yPlane[index];
      final up = uPlane[uvIndex];
      final vp = vPlane[uvIndex];

      int r = (yp + 1.402 * (vp - 128)).round();
      int g = (yp - 0.344136 * (up - 128) - 0.714136 * (vp - 128)).round();
      int b = (yp + 1.772 * (up - 128)).round();

      rgbImage.setPixelRgb(
        x,
        y,
        r.clamp(0, 255),
        g.clamp(0, 255),
        b.clamp(0, 255),
      );
    }
  }
  return rgbImage;
}

List<List<double>> _transpose(List<List<double>> matrix) {
  if (matrix.isEmpty) return [];
  int rowCount = matrix.length;
  int colCount = matrix[0].length;
  List<List<double>> transposed = List.generate(
    colCount,
    (_) => List.filled(rowCount, 0.0),
  );
  for (int i = 0; i < rowCount; i++) {
    for (int j = 0; j < colCount; j++) {
      transposed[j][i] = matrix[i][j];
    }
  }
  return transposed;
}

class CameraScreen extends StatefulWidget {
  final CameraDescription camera;
  final FlutterTts flutterTts;
  const CameraScreen({
    super.key,
    required this.camera,
    required this.flutterTts,
  });
  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver {
  late CameraController _controller;
  late Future<void> _initializeControllerFuture;
  Interpreter? _interpreter;
  List<String>? _labels;

  // Sesli bildirim kontrolü için değişkenler
  final Map<String, DateTime> _lastAnnouncementTimes = {};
  final Duration _announcementCooldown = const Duration(seconds: 3);

  Isolate? _isolate;
  late ReceivePort _receivePort;
  late SendPort _sendPort;
  bool _isDetecting = false;
  int _frameCounter = 0;

  // Güncellenmiş Türkçe etiketler
  final Map<String, String> _turkishLabels = turkishlabels;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = CameraController(
      widget.camera,
      ResolutionPreset.high,
      enableAudio: false,
    );
    _initializeControllerFuture = _controller.initialize().then((_) async {
      if (!mounted) return;
      await _loadModelAndLabels();
      await _startIsolate();

      // Kamera akışını başlat
      _controller.startImageStream((CameraImage image) {
        _frameCounter++;
        // Her 10 frame'de bir tespit yap (performans için)
        if (_frameCounter % 10 == 0) {
          if (!_isDetecting && _interpreter != null && _labels != null) {
            _isDetecting = true;
            _sendPort.send(IsolateData(image, _interpreter!.address, _labels!));
          }
        }
      });
      setState(() {});
    });
  }

  Future<void> _loadModelAndLabels() async {
    try {
      _interpreter = await Interpreter.fromAsset(
        'assets/models/yolov8n_float32.tflite',
      );
      final labelData = await rootBundle.loadString('assets/models/labels.txt');
      _labels = labelData
          .split('\n')
          .where((s) => s.trim().isNotEmpty)
          .toList();
      debugPrint(
        'Model ve etiketler başarıyla yüklendi: ${_labels?.length} sınıf bulundu.',
      );
      debugPrint('Yüklenen etiketler: $_labels');

      // İlk birkaç etiketi kontrol et
      if (_labels != null && _labels!.isNotEmpty) {
        debugPrint('İlk 10 etiket: ${_labels!.take(10).toList()}');
      }
    } catch (e) {
      debugPrint('Model veya etiketler yüklenirken hata oluştu: $e');
    }
  }

  void _triggerVibration(String position) async {
    if (await Vibration.hasVibrator()) {
      if (position == "solunuzda") {
        Vibration.vibrate(pattern: [0, 100, 50, 100]); // kısa-kısa
      } else if (position == "önünüzde") {
        Vibration.vibrate(duration: 300); // uzun titreşim
      } else if (position == "sağınızda") {
        Vibration.vibrate(pattern: [0, 100, 50, 100, 50, 100]); // yoğun sağ
      }
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
    if (results.isEmpty || !mounted) return;

    // En güvenilir tespiti al
    final bestResult = results.first;

    // Rect verisi Map olarak geliyor, Rect nesnesine dönüştür
    final rectMap = bestResult['rect'] as Map<String, dynamic>;
    final rect = Rect.fromLTWH(
      rectMap['left'] as double,
      rectMap['top'] as double,
      rectMap['width'] as double,
      rectMap['height'] as double,
    );

    final centerX = rect.center.dx;
    debugPrint("Nesne x konumu (center.dx): $centerX");

    // Konum hesaplama, 0-1 arası normalize olmuş varsayıyoruz
    String position;
    if (centerX < 0.33) {
      position = "solunuzda";
    } else if (centerX > 0.66) {
      position = "sağınızda";
    } else {
      position = "önünüzde";
    }

    final label = bestResult['label'] as String;
    final turkishLabel = _turkishLabels[label] ?? label;

    final now = DateTime.now();

    final key = "$label-$position";

    if (_lastAnnouncementTimes.containsKey(key)) {
      final timeDiff = now.difference(_lastAnnouncementTimes[key]!);
      if (timeDiff < _announcementCooldown) {
        return; // Çok erken, duyuru yapma
      }
    }

    _lastAnnouncementTimes[key] = now;

    final announcement = "$position bir $turkishLabel var";
    debugPrint("Sesli Bildirim: $announcement");
    widget.flutterTts.speak(announcement);
    _triggerVibration(position);

    // Eski kayıtları temizle
    _lastAnnouncementTimes.removeWhere(
      (key, value) => now.difference(value) > Duration(minutes: 5),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _isolate?.kill(priority: Isolate.immediate);
    _receivePort.close();
    if (_controller.value.isInitialized) {
      _controller.stopImageStream();
    }
    _controller.dispose();
    _interpreter?.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_controller.value.isInitialized) return;

    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      if (_controller.value.isStreamingImages) {
        _controller.stopImageStream();
      }
    } else if (state == AppLifecycleState.resumed) {
      if (!_controller.value.isStreamingImages &&
          _interpreter != null &&
          _labels != null) {
        _controller.startImageStream((image) {
          _frameCounter++;
          if (_frameCounter % 10 == 0) {
            if (!_isDetecting) {
              _isDetecting = true;
              _sendPort.send(
                IsolateData(image, _interpreter!.address, _labels!),
              );
            }
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("DuruGörü - Canlı Tespit"),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: FutureBuilder<void>(
        future: _initializeControllerFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            return Stack(
              children: [
                CameraPreview(_controller),
                // Debug bilgisi (isteğe bağlı)
                Positioned(
                  top: 10,
                  left: 10,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black.withAlpha(179),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Model: ${_interpreter != null ? "Yüklendi" : "Yükleniyor..."}\n'
                      'Etiket Sayısı: ${_labels?.length ?? 0}\n'
                      'Tespit: ${_isDetecting ? "Aktif" : "Bekliyor"}',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                ),
              ],
            );
          } else {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Colors.white),
                  SizedBox(height: 16),
                  Text(
                    'Kamera ve Model Yükleniyor...',
                    style: TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ],
              ),
            );
          }
        },
      ),
    );
  }
}

double _calculateIoU(Rect a, Rect b) {
  final double xA = math.max(a.left, b.left);
  final double yA = math.max(a.top, b.top);
  final double xB = math.min(a.right, b.right);
  final double yB = math.min(a.bottom, b.bottom);

  final double interArea = math.max(0, xB - xA) * math.max(0, yB - yA);
  final double boxAArea = a.width * a.height;
  final double boxBArea = b.width * b.height;

  final double iou = interArea / (boxAArea + boxBArea - interArea);
  return iou;
}

List<Map<String, dynamic>> nonMaximumSuppression(
  List<Map<String, dynamic>> detections,
  double iouThreshold,
) {
  detections.sort(
    (a, b) => (b['confidence'] as double).compareTo(a['confidence'] as double),
  );

  final List<Map<String, dynamic>> finalDetections = [];

  for (var i = 0; i < detections.length; i++) {
    final current = detections[i];
    bool shouldAdd = true;

    for (var j = 0; j < finalDetections.length; j++) {
      final existing = finalDetections[j];

      if (current['classIndex'] == existing['classIndex']) {
        final iou = _calculateIoU(current['rect'], existing['rect']);
        if (iou > iouThreshold) {
          shouldAdd = false;
          break;
        }
      }
    }

    if (shouldAdd) {
      finalDetections.add(current);
    }
  }

  return finalDetections;
}
