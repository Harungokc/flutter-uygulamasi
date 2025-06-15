import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:camera/camera.dart';

List<CameraDescription>? cameras;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  cameras = await availableCameras();
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
        scaffoldBackgroundColor: const Color.fromARGB(255, 0, 0, 0),
        textTheme: const TextTheme(
          bodyLarge: TextStyle(color: Colors.white, fontSize: 24),
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

  @override
  void initState() {
    super.initState();
    _initializeTts();
  }

  // TTS'i başlangıçta düzgün şekilde başlat
  Future<void> _initializeTts() async {
    try {
      // Mevcut dilleri kontrol et
      List<dynamic> languages = await _flutterTts.getLanguages;
      print("Mevcut diller: $languages");

      // Türkçe dil ayarları
      await _flutterTts.setLanguage("tr-TR");
      
      // Alternatif Türkçe kodları da deneyin
      bool isLanguageSet = await _flutterTts.isLanguageAvailable("tr-TR");
      if (!isLanguageSet) {
        await _flutterTts.setLanguage("tr");
        isLanguageSet = await _flutterTts.isLanguageAvailable("tr");
      }
      
      if (!isLanguageSet) {
        print("Türkçe dil desteği bulunamadı, varsayılan dil kullanılacak");
      }

      // Diğer TTS ayarları
      await _flutterTts.setSpeechRate(0.5); // Biraz daha hızlı konuşma
      await _flutterTts.setVolume(0.8);
      await _flutterTts.setPitch(1.0);

      // iOS için özel ayarlar
      if (Theme.of(context).platform == TargetPlatform.iOS) {
        await _flutterTts.setSharedInstance(true);
        await _flutterTts.setIosAudioCategory(
          IosTextToSpeechAudioCategory.playback,
          [
            IosTextToSpeechAudioCategoryOptions.allowBluetooth,
            IosTextToSpeechAudioCategoryOptions.allowBluetoothA2DP,
            IosTextToSpeechAudioCategoryOptions.mixWithOthers
          ],
          IosTextToSpeechAudioMode.spokenAudio,
        );
      }

      setState(() {
        _isTtsInitialized = true;
      });

      // Test konuşması
      await _speak("DuruGörü uygulamasına hoş geldiniz. Algılamayı başlatmak için butona dokunun.");
      
    } catch (e) {
      print("TTS başlatma hatası: $e");
      setState(() {
        _isTtsInitialized = false;
      });
    }
  }

  Future<void> _speak(String text) async {
    if (!_isTtsInitialized) {
      await _initializeTts();
    }
    
    try {
      // Her konuşma öncesi dil ayarını yenile
      await _flutterTts.setLanguage("tr-TR");
      await _flutterTts.speak(text);
    } catch (e) {
      print("Konuşma hatası: $e");
      // Hata durumunda alternatif dil kodu dene
      try {
        await _flutterTts.setLanguage("tr");
        await _flutterTts.speak(text);
      } catch (e2) {
        print("Alternatif dil ile konuşma hatası: $e2");
      }
    }
  }

  void _startDetection() async {
    await _speak("Algılama başlatıldı.");
    
    // Konuşma bitene kadar bekle
    await Future.delayed(Duration(seconds: 2));
    
    if (cameras != null && cameras!.isNotEmpty) {
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

  // Test butonu ekleyelim
  void _testTurkishSpeech() async {
    await _speak("Bu bir Türkçe test konuşmasıdır. Eğer beni anlıyorsanız, Türkçe dil desteği çalışıyor demektir.");
  }

  @override
  void dispose() {
    _flutterTts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      body: Stack(
        children: [
          // "DuruGörü" yazısı ekranın üst yarısının ortasında
          Positioned(
            top: screenHeight * 0.2,
            left: 0,
            right: 0,
            child: Center(
              child: Column(
                children: [
                  Text(
                    'DuruGörü',
                    style: const TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(height: 10),
                  // TTS durumu göstergesi
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: _isTtsInitialized ? Colors.green : Colors.orange,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _isTtsInitialized ? 'Ses Sistemi Hazır' : 'Ses Sistemi Yükleniyor...',
                      style: TextStyle(
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

          // Algılamayı Başlat butonu ekranın tam ortasında
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                    textStyle: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  icon: const Icon(Icons.hearing),
                  label: const Text("Algılamayı Başlat"),
                  onPressed: _isTtsInitialized ? _startDetection : null,
                ),
                
                SizedBox(height: 20),
                
                // Test butonu
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    textStyle: const TextStyle(fontSize: 18),
                  ),
                  icon: const Icon(Icons.volume_up),
                  label: const Text("Türkçe Ses Testi"),
                  onPressed: _isTtsInitialized ? _testTurkishSpeech : null,
                ),
              ],
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

  @override
  void initState() {
    super.initState();
    _controller = CameraController(
      widget.camera,
      ResolutionPreset.medium,
      enableAudio: false,
    );
    _initializeControllerFuture = _controller.initialize();
    _initializeCameraTts();
  }

  Future<void> _initializeCameraTts() async {
    await _flutterTts.setLanguage("tr-TR");
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.setVolume(0.8);
    await _flutterTts.setPitch(1.0);
    
    // Kamera açıldığında bilgi ver
    Future.delayed(Duration(seconds: 1), () {
      _flutterTts.speak("Kamera aktif. Engel tespiti için hazır.");
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _flutterTts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Kamera Aktif"),
        leading: IconButton(
          icon: Icon(Icons.arrow_back),
          onPressed: () {
            _flutterTts.speak("Kamera kapatıldı.");
            Navigator.pop(context);
          },
        ),
      ),
      body: FutureBuilder<void>(
        future: _initializeControllerFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
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
    );
  }
}