import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:camera/camera.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'dart:async'; // Zamanlayıcı için gerekli import

// TensorFlow Lite ve görüntü işleme paketleri
import 'package:tflite_flutter/tflite_flutter.dart';
import 'dart:typed_data'; // Uint8List ve Float32List için
import 'package:image/image.dart' as img_lib; // 'image' paketi için takma ad
import 'package:flutter/services.dart'
    show rootBundle; // Assets'ten dosya yüklemek için

// SpeechListenOptions import'unu kaldırıldı, çünkü speech_to_text 7.x.x'te 'options' parametresi doğrudan listen metoduna taşındı.
// Eğer bu uyarılar tekrar gelirse, bu durum linter'ın eski kural setini kullanmasından kaynaklanıyor olabilir ve derlemeyi engellemez.
// import 'package:speech_to_text/speech_listen_options.dart';

// Uygulama genelinde kullanılacak kamera listesi.
List<CameraDescription>? cameras;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    cameras = await availableCameras();
  } on CameraException catch (e) {
    debugPrint(
      "Kamera başlatılırken hata oluştu: ${e.code} - ${e.description}",
    );
    cameras = [];
  } catch (e) {
    debugPrint("Beklenmedik kamera hatası: $e");
    cameras = [];
  }
  runApp(const AccessibleApp());
}

class AccessibleApp extends StatelessWidget {
  const AccessibleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DuruGörü',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Colors.blueGrey[900],
        textTheme: const TextTheme(
          bodyLarge: TextStyle(color: Colors.white, fontSize: 24),
        ),
        primaryColor: Colors.black,
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.black.withAlpha((255 * 0.8).round()),
          foregroundColor: Colors.white,
        ),
      ),
      home: const DetectionHomePage(),
    );
  }
}

class DetectionHomePage extends StatefulWidget {
  const DetectionHomePage({super.key});

  @override
  State<DetectionHomePage> createState() => _DetectionHomePageState();
}

class _DetectionHomePageState extends State<DetectionHomePage> {
  final FlutterTts _flutterTts = FlutterTts();
  final SpeechToText _speechToText = SpeechToText();
  bool _isTtsInitialized = false;
  bool _isListening = false;
  Timer? _listeningTimer;

  @override
  void initState() {
    super.initState();
    _initializeTts().then((_) {
      Future.delayed(const Duration(seconds: 7), () async {
        if (!mounted) return;
        bool speechInitialized = await _initializeSpeechToText();
        if (speechInitialized && _isTtsInitialized) {
          _startListening();
        } else {
          if (_isTtsInitialized) {
            await _speak(
              "Sesli komutlar başlatılamadı. Lütfen mikrofon izinlerini ve internet bağlantınızı kontrol edin.",
            );
          }
        }
      });
    });
  }

  Future<void> _initializeTts() async {
    try {
      List<dynamic> languages = await _flutterTts.getLanguages;
      debugPrint("Mevcut diller: $languages");
      await _flutterTts.setLanguage("tr-TR");
      bool isLanguageSet = await _flutterTts.isLanguageAvailable("tr-TR");
      if (!isLanguageSet) {
        await _flutterTts.setLanguage("tr");
        isLanguageSet = await _flutterTts.isLanguageAvailable("tr");
      }
      if (!isLanguageSet) {
        debugPrint(
          "Türkçe dil desteği bulunamadı, varsayılan dil kullanılacak.",
        );
      }
      await _flutterTts.setSpeechRate(0.5);
      await _flutterTts.setVolume(0.6);
      await _flutterTts.setPitch(1.0);
      setState(() {
        _isTtsInitialized = true;
      });
      await _speak(
        "DuruGörüye hoş geldiniz. Lütfen başlamak için sesli komut verin.",
      );
    } catch (e) {
      debugPrint("TTS başlatma hatası: $e");
      setState(() {
        _isTtsInitialized = false;
      });
    }
  }

  Future<bool> _initializeSpeechToText() async {
    bool hasSpeech = await _speechToText.initialize(
      onError: (val) => debugPrint("Speech to Text Hatası: ${val.errorMsg}"),
      onStatus: (val) => debugPrint("Speech to Text Durumu: $val"),
      debugLogging: true,
    );
    if (hasSpeech) {
      debugPrint("Speech to Text başarıyla başlatıldı.");
    } else {
      debugPrint(
        "Speech to Text başlatılamadı. Cihaz desteklemiyor olabilir veya izin yok.",
      );
    }
    return hasSpeech;
  }

  Future<void> _speak(String text) async {
    if (!_isTtsInitialized) {
      debugPrint(
        "TTS henüz başlatılmadı veya başlatılırken hata oluştu. Konuşma yapılamıyor.",
      );
      return;
    }
    try {
      await _flutterTts.setLanguage("tr-TR");
      await _flutterTts.speak(text);
    } catch (e) {
      debugPrint("Konuşma hatası: $e");
      try {
        await _flutterTts.setLanguage("tr");
        await _flutterTts.speak(text);
      } catch (e2) {
        debugPrint("Alternatif dil ile konuşma hatası: $e2");
      }
    }
  }

  void _startListening() async {
    if (!_speechToText.isAvailable) {
      debugPrint("Dinleme başlatılamadı: SpeechToText servisi mevcut değil.");
      return;
    }

    if (_isListening) {
      _stopListening();
      await Future.delayed(const Duration(milliseconds: 200));
    }

    setState(() {
      _isListening = true;
    });

    if (_isTtsInitialized) {
      await _speak("Dinliyorum. Lütfen 'başlat' veya 'start' komutunu verin.");
    }

    await Future.delayed(
      const Duration(seconds: 6),
    ); // TTS bitişini garantilemek için ek gecikme

    // speech_to_text 7.0.0 API'si için parametreler doğrudan `listen` metoduna veriliyor.
    // Linter uyarıları (deprecated) gelirse, bu paketin sürümünün tam olarak 7.0.0 olup olmadığını kontrol edin.
    // Eğer hala uyarı veriyorsa, bu uyarılar derlemeyi engellemez ve göz ardı edilebilir.
    _speechToText.listen(
      onResult: (result) {
        debugPrint("Tanınan metin: ${result.recognizedWords}");
        if (result.recognizedWords.toLowerCase().contains("start") ||
            result.recognizedWords.toLowerCase().contains("başlat")) {
          _startDetection();
        }
        if (result.finalResult) {
          _stopListening();
        }
      },
      localeId: "tr_TR",
      onSoundLevelChange: (level) => debugPrint("Ses Seviyesi: $level"),
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 10),
      // ignore: deprecated_member_use
      partialResults: true, // v7.0.0'da doğrudan parametre
      // ignore: deprecated_member_use
      onDevice: true, // v7.0.0'da doğrudan parametre
    );

    _listeningTimer?.cancel();
    _listeningTimer = Timer(const Duration(seconds: 30), () {
      if (!mounted) return;
      if (_isListening) {
        _stopListening();
        if (_isTtsInitialized) {
          _speak("Sesli komut dinleme otomatik olarak durduruldu.");
        }
      }
    });
  }

  void _stopListening() {
    if (!_isListening) return;
    _speechToText.stop();
    _listeningTimer?.cancel();
    setState(() {
      _isListening = false;
    });
    debugPrint("Dinleme durduruldu.");
  }

  void _startDetection() async {
    if (_isListening) {
      _stopListening();
    }
    await _speak(
      "DuruGörü aktif, kameranız açılıyor, tehditler algılanmaya hazır.",
    );
    await Future.delayed(const Duration(seconds: 5));
    if (cameras != null && cameras!.isNotEmpty) {
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => CameraScreen(camera: cameras![0]),
        ),
      );
    } else {
      await _speak("Kamera bulunamadı.");
    }
  }

  @override
  void dispose() {
    _flutterTts.stop();
    _speechToText.stop();
    _listeningTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      body: Stack(
        children: [
          Positioned(
            top: screenHeight * 0.15,
            left: 0,
            right: 0,
            child: Center(
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _isTtsInitialized ? Colors.green : Colors.orange,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _isTtsInitialized
                          ? 'Ses Sistemi Hazır'
                          : 'Ses Sistemi Yükleniyor...',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (_speechToText.isAvailable)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: _isListening ? Colors.redAccent : Colors.grey,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _isListening ? 'Dinliyor...' : 'Sesli Komut Hazır',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    foregroundColor: Colors.white,
                    minimumSize: Size(screenWidth * 0.35, screenWidth * 0.35),
                    shape: const StadiumBorder(),
                    padding: EdgeInsets.zero,
                  ),
                  onPressed: _isTtsInitialized ? _startDetection : null,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Image.asset(
                      'assets/images/logo.png',
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
                const SizedBox(height: 30),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isListening ? Colors.red : Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 16,
                    ),
                    textStyle: const TextStyle(fontSize: 18),
                  ),
                  icon: Icon(_isListening ? Icons.mic_off : Icons.mic),
                  label: Text(
                    _isListening ? "Dinlemeyi Durdur" : "Sesli Komutu Başlat",
                  ),
                  onPressed: _speechToText.isAvailable && _isTtsInitialized
                      ? (_isListening ? _stopListening : _startListening)
                      : null,
                ),
              ],
            ),
          ),
          Positioned(
            bottom: 20,
            right: 20,
            child: Text(
              'DuruGörü',
              style: TextStyle(
                color: Colors.white.withAlpha((255 * 0.5).toInt()),
                fontSize: 14,
                fontWeight: FontWeight.w300,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class CameraScreen extends StatefulWidget {
  final CameraDescription camera;

  const CameraScreen({super.key, required this.camera});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  late CameraController _controller;
  late Future<void> _initializeControllerFuture;
  final FlutterTts _flutterTts = FlutterTts();

  // TFLite ile ilgili değişkenler
  Interpreter? _interpreter;
  List<String>? _labels;
  bool _isModelLoaded = false;
  bool _isDetecting = false; // Bir frame'in zaten işlenip işlenmediği kontrolü

  @override
  void initState() {
    super.initState();
    _controller = CameraController(
      widget.camera,
      ResolutionPreset.medium,
      enableAudio: false,
    );
    _initializeControllerFuture = _controller.initialize().then((_) {
      if (mounted) {
        // Kamera başarılıysa akışı başlat. Emülatörde siyah ekran olabilir.
        // _startImageStream(); // Canlı kamera akışını başlatmak için bu satırı etkinleştirin.
      }
    });
    _initializeCameraTts(); // TTS'i başlat
    _loadModel(); // Modeli yükle
    _loadLabels(); // Etiketleri yükle
  }

  // Kamera ekranı için TTS'i başlatmak için metod.
  Future<void> _initializeCameraTts() async {
    await _flutterTts.setLanguage("tr-TR");
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.setVolume(0.8);
    await _flutterTts.setPitch(1.0);

    Future.delayed(const Duration(seconds: 1), () {
      if (!mounted) return;
      _flutterTts.speak("Kamera aktif. Engel tespiti için hazır.");
    });
  }

  // TFLite modelini assets'ten yükle
  Future<void> _loadModel() async {
    try {
      _interpreter = await Interpreter.fromAsset(
        'assets/models/mobilenet_v2_035_128_classification.tflite',
      );
      setState(() {
        _isModelLoaded = true;
      });
      debugPrint('Model yüklendi: $_interpreter');
    } catch (e) {
      debugPrint('Model yüklenirken hata oluştu: $e');
    }
  }

  // Etiket dosyasını (labels.txt) assets'ten yükle
  Future<void> _loadLabels() async {
    try {
      final labelData = await rootBundle.loadString('assets/models/labels.txt');
      _labels = labelData.split('\n').where((s) => s.isNotEmpty).toList();
      debugPrint('Etiketler yüklendi: $_labels');
    } catch (e) {
      debugPrint('Etiketler yüklenirken hata oluştu: $e');
    }
  }

  // TEST METODU: Statik bir görseli yükle ve işle
  Future<void> _testStaticImageDetection() async {
    if (!_isModelLoaded || _labels == null) {
      await _flutterTts.speak(
        "Model veya etiketler henüz yüklenmedi. Lütfen bekleyin.",
      );
      return;
    }
    if (_isDetecting) {
      await _flutterTts.speak("Önceki görsel işleniyor. Lütfen bekleyin.");
      return;
    }

    _isDetecting = true; // İşlem başladığını işaretle
    await _flutterTts.speak("Test görseli yükleniyor ve işleniyor.");
    debugPrint("Test görseli işleniyor...");

    try {
      // 1. Test görselini assets'ten Uint8List olarak yükle
      final ByteData imageData = await rootBundle.load(
        'assets/images/test_image.jpg',
      );
      final Uint8List bytes = imageData.buffer.asUint8List();

      // 2. Yüklenen byte'ları img_lib.Image nesnesine dönüştür
      // `decodeImage` null dönebilir, kontrol edelim.
      final img_lib.Image? originalImage = img_lib.decodeImage(bytes);
      if (originalImage == null) {
        debugPrint("Test görseli çözümlenemedi.");
        await _flutterTts.speak(
          "Test görseli yüklenemedi veya desteklenmiyor.",
        );
        _isDetecting = false;
        return;
      }

      // Modelin beklediği boyutlar (MobileNetV2 035_128 için 128x128)
      final int targetWidth = 128;
      final int targetHeight = 128;

      // 3. Modeline uygun boyuta yeniden boyutlandır
      final resizedImage = img_lib.copyResize(
        originalImage,
        width: targetWidth,
        height: targetHeight,
      );

      // 4. Piksel verilerini Float32List'e dönüştür ve normalize et (0-1 aralığı)
      var input = Float32List(1 * targetWidth * targetHeight * 3);
      int pixelIndex = 0;
      for (int y = 0; y < targetHeight; y++) {
        for (int x = 0; x < targetWidth; x++) {
          final pixel = resizedImage.getPixel(x, y);

          final r = pixel.r.toDouble();
          final g = pixel.g.toDouble();
          final b = pixel.b.toDouble();

          input[pixelIndex++] = r / 255.0;
          input[pixelIndex++] = g / 255.0;
          input[pixelIndex++] = b / 255.0;

          // img_lib.getAlpha(pixel) kullanımı kaldırıldı çünkü model RGB kanallarını bekliyor.
        }
      }
      var inputTensor = input.reshape([1, targetWidth, targetHeight, 3]);

      // 5. Çıkış tensörü için alan ayırma (MobileNetV2 035_128 için 1x1001)
      var output = Float32List(1 * 1001).reshape([1, 1001]);

      // 6. Modeli çalıştır
      _interpreter!.run(inputTensor, output);

      // 7. Sonuçları işleme
      var maxScore = -1.0;
      var predictedIndex = -1;
      for (int i = 0; i < output[0].length; i++) {
        if (output[0][i] > maxScore) {
          maxScore = output[0][i];
          predictedIndex = i;
        }
      }

      if (predictedIndex != -1 && _labels != null && _labels!.isNotEmpty) {
        final String predictedLabel = _labels![predictedIndex];
        if (maxScore > 0.5) {
          // %50 olasılıktan yüksekse seslendir
          await _flutterTts.speak(
            'Test görselinde algılandı: $predictedLabel, Olasılık: ${maxScore.toStringAsFixed(2)}',
          );
          debugPrint(
            'Test Tahmin: $predictedLabel (Olasılık: ${maxScore.toStringAsFixed(2)})',
          );
        } else {
          await _flutterTts.speak(
            "Test görselinde belirgin bir nesne algılanamadı.",
          );
          debugPrint(
            "Test Tahmin: Belirgin nesne yok (En yüksek olasılık: $maxScore)",
          );
        }
      } else {
        await _flutterTts.speak(
          "Test görseli işlenirken bir hata oluştu veya etiketler eksik.",
        );
        debugPrint("Test Tahmin: Sonuç işlenemedi.");
      }
    } catch (e) {
      debugPrint('Test görseli işlenirken hata oluştu: $e');
      await _flutterTts.speak(
        "Test görseli işlenirken beklenmedik bir hata oluştu.",
      );
    } finally {
      _isDetecting = false; // İşlem bitti
    }
  }

  // Bu metot kamera akışından gelen frame'leri işler.
  // Gerçek cihazda kamera testi için bu metot etkinleştirilebilir.
  // Eğer etkinleştirilirse, `_controller.startImageStream()` çağrısını `initState` içinde açmanız gerekecek.
  // 'The declaration '_processCameraImage' isn't referenced.' uyarısı bu yüzden geliyordu.

  @override
  void dispose() {
    // Akışı durdur (eğer aktifse)
    if (_controller.value.isStreamingImages) {
      _controller.stopImageStream();
    }
    _controller.dispose();
    _interpreter?.close(); // Yorumlayıcıyı serbest bırakmayı unutmayın
    _flutterTts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Kamera Ekranı (Test Modu)"),
        backgroundColor: Colors.black,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            if (!mounted) return;
            _flutterTts.speak("Kamera test ekranı kapatıldı.");
            Navigator.pop(context);
          },
        ),
      ),
      body: Stack(
        children: [
          // Kamera önizlemesi (emülatörde siyah kalacaktır, gerçek cihazda görüntü verir)
          FutureBuilder<void>(
            future: _initializeControllerFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.done) {
                if (snapshot.hasError) {
                  debugPrint("Kamera başlatma hatası: ${snapshot.error}");
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) return;
                    _flutterTts.speak("Kamera başlatılırken bir hata oluştu.");
                  });
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.error_outline,
                          color: Colors.red,
                          size: 60,
                        ),
                        const SizedBox(height: 20),
                        Text(
                          "Kamera başlatılamadı: ${snapshot.error}",
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 20),
                        ElevatedButton(
                          onPressed: () {
                            if (!mounted) return;
                            Navigator.pop(context);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text("Geri Dön"),
                        ),
                      ],
                    ),
                  );
                }
                // Kamera açıldıysa önizlemeyi göster (emülatörde siyah olabilir)
                return CameraPreview(_controller);
              } else {
                return const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 20),
                      Text(
                        "Kamera başlatılıyor...",
                        style: TextStyle(color: Colors.white, fontSize: 18),
                      ),
                    ],
                  ),
                );
              }
            },
          ),

          // Ortada test butonu
          Center(
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 16,
                ),
                textStyle: const TextStyle(fontSize: 20),
              ),
              icon: const Icon(Icons.image),
              label: Text(
                _isDetecting ? "İşleniyor..." : "Test Görselini Algıla",
              ),
              onPressed: _isModelLoaded && !_isDetecting
                  ? _testStaticImageDetection
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}
