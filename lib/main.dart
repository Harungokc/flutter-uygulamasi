import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:camera/camera.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'dart:async';

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
        scaffoldBackgroundColor: const Color.fromARGB(255, 8, 8, 8),
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
      // Hoş geldiniz mesajı konuştuktan sonra mikrofonu başlatmayı planla.
      // Mesajın süresi yaklaşık 5 saniye olduğu için biraz daha fazla bekleyelim.
      Future.delayed(const Duration(seconds: 7), () async {
        if (!mounted) return;
        bool speechInitialized = await _initializeSpeechToText();
        if (speechInitialized && _isTtsInitialized) {
          _startListeningDelayed(); // Yeni metodu çağır
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
        "DuruGörüye hoş geldiniz. Lütfen devam etmek için başlat komutunu verin.",
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

  // Yeni metod: Sesli komut dinlemeyi gecikmeli olarak başlatır
  // Böylece "Dinliyorum..." konuşması bittikten sonra mikrofon devreye girer.
  void _startListeningDelayed() async {
    _startListening();
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

    // Artık _startListeningDelayed() içinde konuşuyoruz, burada tekrar konuşmaya gerek yok
    // if (_isTtsInitialized) {
    //   await _speak("Dinliyorum. Lütfen 'başlat' veya 'start' komutunu verin.");
    // }

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
      listenFor: const Duration(
        seconds: 30,
      ), // Mikrofonun tek seferde dinleyeceği süre
      pauseFor: const Duration(
        seconds: 10,
      ), // Sessizlik sonrası duraklama süresi
      partialResults: true,
      // onDevice: true, // Eğer sadece cihaz içi tanıma istiyorsanız ekleyebilirsiniz
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
                      ? (_isListening
                            ? _stopListening
                            : _startListeningDelayed) // _startListening yerine _startListeningDelayed çağrıldı
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

    Future.delayed(const Duration(seconds: 1), () {
      if (!mounted) return;
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
        backgroundColor: Colors.black,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            if (!mounted) return;
            _flutterTts.speak("Kamera kapatıldı.");
            Navigator.pop(context);
          },
        ),
      ),
      body: FutureBuilder<void>(
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
                      style: const TextStyle(color: Colors.white, fontSize: 18),
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
