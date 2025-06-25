import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:camera/camera.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'dart:async'; // Zamanlayıcı için gerekli import

// Yeni kamera ekranımızı projemize dahil ediyoruz.
import 'camera_screen.dart';

// Artık bu dosyada TFLite veya görüntü işleme paketlerine ihtiyacımız yok.
// Onların hepsi camera_screen.dart dosyası tarafından yönetiliyor.

// Uygulama genelinde kullanılacak kamera listesi.
List<CameraDescription>? cameras;

void main() async {
  // main fonksiyonunda bir değişiklik yok.
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
    // AccessibleApp sınıfında bir değişiklik yok.
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
  // DetectionHomePage sınıfının içeriğinde bir değişiklik yok.
  // Tüm TTS, SpeechToText ve UI mantığı aynı kalıyor.
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
    );

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
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 10),
      partialResults: true,
      onDevice: true,
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

  // Bu fonksiyon, yeni camera_screen.dart'taki ekranı açar.
  // Bir önceki adımdaki gibi doğru şekilde ayarlanmış haliyle bırakıyoruz.
  void _startDetection() async {
    if (_isListening) {
      _stopListening();
    }
    
    if (cameras == null || cameras!.isEmpty) {
      await _speak("Kamera bulunamadı veya kamera izni verilmemiş.");
      return;
    }

    await _speak(
      "DuruGörü aktif, canlı algılama ekranı açılıyor.",
    );

    if (!mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CameraScreen(camera: cameras![0]),
      ),
    );
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
    // build metodunda (UI) bir değişiklik yok.
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

// ESKİ CameraScreen SINIFI BURADAN TAMAMEN KALDIRILDI.


