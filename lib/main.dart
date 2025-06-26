// main.dart - SON HALİ

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:camera/camera.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'dart:async'; // Zamanlayıcı için gerekli import

import 'camera_screen.dart';

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
  bool _isDetectionStarting = false; // Yeniden yönlendirmeyi önlemek için bayrak

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
      await _flutterTts.setLanguage("tr-TR");
      await _flutterTts.setSpeechRate(0.5);
      await _flutterTts.setVolume(0.8);
      await _flutterTts.setPitch(1.0);
      setState(() {
        _isTtsInitialized = true;
      });
      await _speak(
        "DuruGörüye hoş geldiniz. Lütfen başlamak için sesli komut verin.",
      );
    } catch (e) {
      debugPrint("TTS başlatma hatası: $e");
    }
  }

  Future<bool> _initializeSpeechToText() async {
    bool hasSpeech = await _speechToText.initialize(
      onError: (val) => debugPrint("Speech to Text Hatası: ${val.errorMsg}"),
      onStatus: (val) => debugPrint("Speech to Text Durumu: $val"),
      debugLogging: true,
    );
    return hasSpeech;
  }

  Future<void> _speak(String text) async {
    if (!_isTtsInitialized) return;
    await _flutterTts.speak(text);
  }

  void _startListening() async {
    if (!_speechToText.isAvailable || _isListening) return;

    setState(() {
      _isListening = true;
    });

    await _speak("Dinliyorum. Lütfen 'başlat' veya 'start' komutunu verin.");
    
    _speechToText.listen(
      onResult: (result) {
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
      if (_isListening) _stopListening();
    });
  }

  void _stopListening() {
    if (!_isListening) return;
    _speechToText.stop();
    _listeningTimer?.cancel();
    if(mounted) {
      setState(() {
        _isListening = false;
      });
    }
    debugPrint("Dinleme durduruldu.");
  }
  
  void _startDetection() async {
    // Eğer zaten bir algılama işlemi başlatılıyorsa, tekrar başlatmayı engelle
    if (_isDetectionStarting) return;

    setState(() {
      _isDetectionStarting = true;
    });

    if (_isListening) {
      _stopListening();
    }
    
    if (cameras == null || cameras!.isEmpty) {
      await _speak("Kamera bulunamadı veya kamera izni verilmemiş.");
      setState(() { _isDetectionStarting = false; }); // Bayrağı sıfırla
      return;
    }

    await _speak(
      "DuruGörü aktif, canlı algılama ekranı açılıyor.",
    );

    if (!mounted) return;
    
    // --- BURASI GÜNCELLENDİ ---
    Navigator.push(
      context,
      MaterialPageRoute(
        // CameraScreen'i doğru parametrelerle çağırıyoruz
        builder: (context) => CameraScreen(
          camera: cameras![0],
          flutterTts: _flutterTts, // TTS nesnesini iletiyoruz
        ),
      ),
    ).then((_) {
      // Kamera ekranından geri dönüldüğünde bu blok çalışır
      if(mounted) {
        setState(() {
          _isDetectionStarting = false; // Bayrağı sıfırla ki tekrar başlatılabilsin
        });
        // Tekrar dinlemeyi başlat
        if (_isTtsInitialized) {
          _startListening();
        }
      }
    });
    // --- GÜNCELLEME SONU ---
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
    // UI kodunda değişiklik yok
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
