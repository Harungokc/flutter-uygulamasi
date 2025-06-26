// camera_screen.dart - TESPİT SORUNLARI DÜZELTİLDİ

import 'dart:async';
import 'dart:isolate';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:image/image.dart' as img_lib;
import 'package:tflite_flutter/tflite_flutter.dart';

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

  await for (final IsolateData isolateData in port) {
    final cameraImage = isolateData.cameraImage;
    final interpreter = Interpreter.fromAddress(isolateData.interpreterAddress);
    final labels = isolateData.labels;

    try {
      final input = await _preprocessImage(cameraImage);
      final output = List.filled(1 * 84 * 8400, 0.0).reshape([1, 84, 8400]);

      interpreter.run(input, output);

      // Modelin çıktısını işle
      final List<List<dynamic>> outputMatrix = output[0];
      final List<List<double>> typedMatrix = outputMatrix.map((row) => List<double>.from(row)).toList();
      final transposedOutput = _transpose(typedMatrix);

      final List<Map<String, dynamic>> results = [];
      
      // Her tespit için döngü
      for (var i = 0; i < transposedOutput.length; i++) {
        final detection = transposedOutput[i];
        
        // İlk 4 değer bounding box koordinatları
        final box = detection.sublist(0, 4);
        // Geri kalan değerler sınıf puanları
        final scores = detection.sublist(4);
        
        var maxScore = 0.0;
        var bestClassIndex = -1;

        // En yüksek puanlı sınıfı bul
        for (var j = 0; j < scores.length; j++) {
          if (scores[j] > maxScore) {
            maxScore = scores[j];
            bestClassIndex = j;
          }
        }

        // Güven eşiğini kontrol et (0.5'e çıkardım daha kararlı tespit için)
        if (maxScore > 0.5 && bestClassIndex >= 0 && bestClassIndex < labels.length) {
          // Bounding box'ı normalize et
          final rect = Rect.fromLTWH(
            (box[0] - box[2] / 2) / 640.0, // x_center - width/2
            (box[1] - box[3] / 2) / 640.0, // y_center - height/2  
            box[2] / 640.0, // width
            box[3] / 640.0, // height
          );
          
          // Geçerli tespit sonucunu ekle
          results.add({
            "rect": rect,
            "label": labels[bestClassIndex],
            "confidence": maxScore,
            "classIndex": bestClassIndex,
          });
        }
      }
      
      sendPort.send(results);
    } catch (e) {
      debugPrint("Tespit işlemi sırasında hata: $e");
      sendPort.send(<Map<String, dynamic>>[]);
    }
  }
}

Future<List<List<List<List<double>>>>> _preprocessImage(CameraImage image) async {
  try {
    final img_lib.Image convertedImage = await _convertYUV420toImageColor(image);
    final img_lib.Image rotatedImage = img_lib.copyRotate(convertedImage, angle: 90);
    final resizedImage = img_lib.copyResize(rotatedImage, width: 640, height: 640);
    
    // Görüntüyü normalize et (0-1 aralığına)
    var inputTensor = List.generate(1,
        (_) => List.generate(640, (y) => List.generate(640, (x) {
              final pixel = resizedImage.getPixel(x, y);
              return [
                pixel.r / 255.0, 
                pixel.g / 255.0, 
                pixel.b / 255.0
              ];
            })));
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
  final FlutterTts flutterTts;
  const CameraScreen({super.key, required this.camera, required this.flutterTts});
  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> with WidgetsBindingObserver {
  late CameraController _controller;
  late Future<void> _initializeControllerFuture;
  Interpreter? _interpreter;
  List<String>? _labels;
  
  // Sesli bildirim kontrolü için değişkenler
  Map<String, DateTime> _lastAnnouncementTimes = {};
  final Duration _announcementCooldown = const Duration(seconds: 3);
  
  Isolate? _isolate;
  late ReceivePort _receivePort;
  late SendPort _sendPort;
  bool _isDetecting = false;
  int _frameCounter = 0;
  
  // Güncellenmiş Türkçe etiketler
  final Map<String, String> _turkishLabels = {
    'person': 'insan', 'bicycle': 'bisiklet', 'car': 'araba', 'motorcycle': 'motosiklet', 
    'airplane': 'uçak', 'bus': 'otobüs', 'train': 'tren', 'truck': 'kamyon', 'boat': 'tekne', 
    'traffic light': 'trafik ışığı', 'fire hydrant': 'yangın musluğu', 'stop sign': 'dur tabelası', 
    'parking meter': 'parkmetre', 'bench': 'bank', 'bird': 'kuş', 'cat': 'kedi', 'dog': 'köpek', 
    'horse': 'at', 'sheep': 'koyun', 'cow': 'inek', 'elephant': 'fil', 'bear': 'ayı', 'zebra': 'zebra', 
    'giraffe': 'zürafa', 'backpack': 'sırt çantası', 'umbrella': 'şemsiye', 'handbag': 'el çantası',
    'tie': 'kravat', 'suitcase': 'bavul', 'frisbee': 'frizbi', 'skis': 'kayak', 'snowboard': 'kar kayağı',
    'sports ball': 'top', 'kite': 'uçurtma', 'baseball bat': 'beyzbol sopası', 'baseball glove': 'beyzbol eldiveni',
    'skateboard': 'kaykay', 'surfboard': 'sörf tahtası', 'tennis racket': 'tenis raketi', 'bottle': 'şişe',
    'wine glass': 'şarap kadehi', 'cup': 'fincan', 'fork': 'çatal', 'knife': 'bıçak', 'spoon': 'kaşık', 
    'bowl': 'kase', 'banana': 'muz', 'apple': 'elma', 'sandwich': 'sandviç', 'orange': 'portakal', 
    'broccoli': 'brokoli', 'carrot': 'havuç', 'hot dog': 'sosisli sandviç', 'pizza': 'pizza', 
    'donut': 'çörek', 'cake': 'kek', 'chair': 'sandalye', 'couch': 'kanepe', 'potted plant': 'saksı bitkisi', 
    'bed': 'yatak', 'dining table': 'yemek masası', 'toilet': 'tuvalet', 'tv': 'televizyon', 
    'laptop': 'dizüstü bilgisayar', 'mouse': 'fare', 'remote': 'uzaktan kumanda', 'keyboard': 'klavye', 
    'cell phone': 'cep telefonu', 'microwave': 'mikrodalga fırın', 'oven': 'fırın', 'toaster': 'tost makinesi', 
    'sink': 'lavabo', 'refrigerator': 'buzdolabı', 'book': 'kitap', 'clock': 'saat', 'vase': 'vazo', 
    'scissors': 'makas', 'teddy bear': 'oyuncak ayı', 'hair drier': 'saç kurutma makinesi', 
    'toothbrush': 'diş fırçası', 'tree': 'ağaç', 'building': 'bina', 'wall': 'duvar', 'door': 'kapı',
    'window': 'pencere', 'table': 'masa', 'flower': 'çiçek', 'plant': 'bitki'
  };

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
      _interpreter = await Interpreter.fromAsset('assets/models/yolov8n_float32.tflite');
      final labelData = await rootBundle.loadString('assets/models/labels.txt');
      _labels = labelData.split('\n').where((s) => s.trim().isNotEmpty).toList();
      debugPrint('Model ve etiketler başarıyla yüklendi: ${_labels?.length} sınıf bulundu.');
      
      // İlk birkaç etiketi kontrol et
      if (_labels != null && _labels!.isNotEmpty) {
        debugPrint('İlk 10 etiket: ${_labels!.take(10).toList()}');
      }
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
    if (results.isEmpty || !mounted) return;
    
    // Güven puanına göre sırala (en yüksek önce)
    results.sort((a, b) => (b['confidence'] as double).compareTo(a['confidence'] as double));
    
    // En güvenilir tespiti al
    final bestResult = results.first;
    final String label = bestResult['label'];
    final double confidence = bestResult['confidence'];
    final int classIndex = bestResult['classIndex'] ?? -1;
    
    debugPrint("Tespit edildi: $label (İndeks: $classIndex), Güven: ${(confidence * 100).toStringAsFixed(1)}%");
    
    final now = DateTime.now();
    
    // Bu nesne için son duyuru zamanını kontrol et
    if (_lastAnnouncementTimes.containsKey(label)) {
      final timeDiff = now.difference(_lastAnnouncementTimes[label]!);
      if (timeDiff < _announcementCooldown) {
        return; // Çok erken, duyuru yapma
      }
    }
    
    // Türkçe etiketi al
    final String turkishLabel = _turkishLabels[label] ?? label;
    
    // Güven oranını yüzde olarak hesapla
    final int confidencePercent = (confidence * 100).round();
    
    // Sesli bildirimi yap
    final String announcement = "Önünüzde bir $turkishLabel var";
    debugPrint("Sesli Bildirim: $announcement");
    
    widget.flutterTts.speak(announcement);
    
    // Son duyuru zamanını güncelle
    _lastAnnouncementTimes[label] = now;
    
    // Eski kayıtları temizle (bellek yönetimi için)
    _lastAnnouncementTimes.removeWhere((key, value) => 
        now.difference(value) > Duration(minutes: 5));
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
    
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      if (_controller.value.isStreamingImages) {
        _controller.stopImageStream();
      }
    } else if (state == AppLifecycleState.resumed) {
      if (!_controller.value.isStreamingImages && _interpreter != null && _labels != null) {
        _controller.startImageStream((image) {
          _frameCounter++;
          if (_frameCounter % 10 == 0) {
            if (!_isDetecting) {
              _isDetecting = true;
              _sendPort.send(IsolateData(image, _interpreter!.address, _labels!));
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
                      color: Colors.black.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Model: ${_interpreter != null ? "Yüklendi" : "Yükleniyor..."}\n'
                      'Etiket Sayısı: ${_labels?.length ?? 0}\n'
                      'Tespit: ${_isDetecting ? "Aktif" : "Bekliyor"}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                      ),
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

