import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:camera/camera.dart';

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
  bool _isTtsInitialized = false;
  bool _isDetectionStarting = false;

  @override
  void initState() {
    super.initState();
    _initializeTts().then((_) {
      Future.delayed(const Duration(seconds: 7), () async {
        if (!mounted) return;
        if (_isTtsInitialized) {
          await _speak(
            "DuruGörüye hoş geldiniz. Lütfen başlamak için ekrandaki butona tıklayın.",
          );
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
        "DuruGörüye hoş geldiniz. Lütfen başlamak için ekrandaki butona tıklayın.",
      );
    } catch (e) {
      debugPrint("TTS başlatma hatası: $e");
    }
  }

  Future<void> _speak(String text) async {
    if (!_isTtsInitialized) return;
    await _flutterTts.speak(text);
  }

  void _startDetection() async {
    // Eğer zaten bir algılama işlemi başlatılıyorsa, tekrar başlatmayı engelle
    if (_isDetectionStarting) return;

    setState(() {
      _isDetectionStarting = true;
    });

    if (cameras == null || cameras!.isEmpty) {
      await _speak("Kamera bulunamadı veya kamera izni verilmemiş.");
      setState(() {
        _isDetectionStarting = false;
      }); // Bayrağı sıfırla
      return;
    }

    await _speak("DuruGörü aktif, canlı algılama ekranı açılıyor.");

    if (!mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CameraScreen(
          camera: cameras![0],
          flutterTts: _flutterTts, // TTS nesnesini iletiyoruz
        ),
      ),
    ).then((_) {
      // Kamera ekranından geri dönüldüğünde bu blok çalışır
      if (mounted) {
        setState(() {
          _isDetectionStarting =
              false; // Bayrağı sıfırla ki tekrar başlatılabilsin
        });
      }
    });
  }

  @override
  void dispose() {
    _flutterTts.stop();
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
