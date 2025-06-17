import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:camera/camera.dart';
// iOS için Flutter TTS ses kategorisi ayarlamaları için gerekli import'lar
// Bu import'lar sadece iOS'e özel olduğu için artık gerekli değil.
// import 'package:flutter_tts/gen/ios_text_to_speech_audio_category.dart';
// import 'package:flutter_tts/gen/ios_text_to_speech_audio_category_options.dart';
// import 'package:flutter_tts/gen/ios_text_to_speech_audio_mode.dart';

// Uygulama genelinde kullanılacak kamera listesi.
// Başlangıçta null olabilir, kamera bulunamazsa boş liste olarak ayarlanır.
List<CameraDescription>? cameras;

void main() async {
  // Flutter widget motorunun başlatıldığından emin olunur.
  // Bu, eklentilerin native kodlarının yüklenmesi için gereklidir.
  WidgetsFlutterBinding.ensureInitialized();

  try {
    // Cihazda mevcut kameraları asenkron olarak alır.
    cameras = await availableCameras();
  } on CameraException catch (e) {
    // Kamera başlatılırken belirli bir kamera eklentisi hatası oluşursa
    debugPrint(
      "Kamera başlatılırken hata oluştu: ${e.code} - ${e.description}",
    );
    // Hata durumunda kameraları boş bir liste olarak ayarlarız,
    // böylece uygulama 'kamera bulunamadı' senaryosunu işleyebilir.
    cameras = [];
  } catch (e) {
    // Diğer beklenmedik hataları yakalar
    debugPrint("Beklenmedik kamera hatası: $e");
    cameras = [];
  }

  // Uygulamayı başlatır.
  runApp(const AccessibleApp());
}

// Uygulamanın ana widget'ı. Bir StatelessWidget'tır çünkü durum tutmaz.
class AccessibleApp extends StatelessWidget {
  const AccessibleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DuruGörü', // Uygulamanın başlığı
      debugShowCheckedModeBanner: false, // Debug bandını gizler
      theme: ThemeData.dark().copyWith(
        // Koyu tema ayarları
        scaffoldBackgroundColor: const Color.fromARGB(
          255,
          0,
          0,
          0,
        ), // Arka plan rengi
        textTheme: const TextTheme(
          bodyLarge: TextStyle(
            color: Colors.white,
            fontSize: 24,
          ), // Varsayılan metin stili
        ),
      ),
      home: const DetectionHomePage(), // Uygulamanın başlangıç ekranı
    );
  }
}

// Algılama ana sayfasının StatefulWidget'ı. Durum tutar (TTS başlatma durumu gibi).
class DetectionHomePage extends StatefulWidget {
  const DetectionHomePage({super.key});

  @override
  State<DetectionHomePage> createState() => _DetectionHomePageState();
}

// _DetectionHomePageState sınıfı, DetectionHomePage'in durumunu yönetir.
class _DetectionHomePageState extends State<DetectionHomePage> {
  // FlutterTts örneği oluşturulur.
  final FlutterTts _flutterTts = FlutterTts();
  // TTS'in başlatılıp başlatılmadığını tutan durum değişkeni.
  bool _isTtsInitialized = false;

  @override
  void initState() {
    super.initState();
    // Widget ilk oluşturulduğunda TTS'i başlatır.
    _initializeTts();
  }

  // TTS'i başlatmak ve yapılandırmak için asenkron metod.
  Future<void> _initializeTts() async {
    try {
      // Mevcut dilleri kontrol et (hata ayıklama için faydalı).
      List<dynamic> languages = await _flutterTts.getLanguages;
      debugPrint("Mevcut diller: $languages");

      // Türkçe dil ayarlarını yap.
      await _flutterTts.setLanguage("tr-TR");

      // Alternatif Türkçe kodları da dene (bazı cihazlarda "tr" olarak geçebilir).
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

      // Diğer TTS ayarları.
      await _flutterTts.setSpeechRate(0.5); // Konuşma hızı
      await _flutterTts.setVolume(0.8); // Ses seviyesi
      await _flutterTts.setPitch(1.0); // Ses perdesi

      // iOS için özel ayarlar kaldırıldı.
      // if (Theme.of(context).platform == TargetPlatform.iOS) {
      //   await _flutterTts.setSharedInstance(true);
      //   await _flutterTts.setIosAudioCategory(
      //     IosTextToSpeechAudioCategory.playback,
      //     [
      //       IosTextToSpeechAudioCategoryOptions.allowBluetooth,
      //       IosTextToSpeechAudioCategoryOptions.allowBluetoothA2DP,
      //       IosTextToSpeechAudioCategoryOptions.mixWithOthers,
      //     ],
      //     IosTextToSpeechAudioMode.spokenAudio,
      //   );
      // }

      // TTS başarıyla başlatıldı, durumu güncelle.
      setState(() {
        _isTtsInitialized = true;
      });

      // Uygulama hoş geldiniz mesajını konuş.
      await _speak(
        "DuruGörü uygulamasına hoş geldiniz. Algılamayı başlatmak için butona dokunun.",
      );
    } catch (e) {
      // TTS başlatma sırasında herhangi bir hata olursa yakala ve logla.
      debugPrint("TTS başlatma hatası: $e");
      setState(() {
        _isTtsInitialized = false;
      });
    }
  }

  // Metin okuma metodunun kendisi.
  Future<void> _speak(String text) async {
    // Eğer TTS başlatılmamışsa tekrar başlatmayı deneme,
    // _isTtsInitialized bayrağına göre butonlar zaten devre dışı kalmalı.
    if (!_isTtsInitialized) {
      debugPrint(
        "TTS henüz başlatılmadı veya başlatılırken hata oluştu. Konuşma yapılamıyor.",
      );
      return;
    }

    try {
      // Her konuşma öncesi dil ayarını yenile (gereksiz olabilir ama sağlamlık için).
      await _flutterTts.setLanguage("tr-TR");
      await _flutterTts.speak(text);
    } catch (e) {
      debugPrint("Konuşma hatası: $e");
      // Hata durumunda alternatif dil kodu dene (bazı cihazlar için "tr" gerekebilir).
      try {
        await _flutterTts.setLanguage("tr");
        await _flutterTts.speak(text);
      } catch (e2) {
        debugPrint("Alternatif dil ile konuşma hatası: $e2");
      }
    }
  }

  // Algılama başlatma butonu işlevi.
  void _startDetection() async {
    await _speak("Algılama başlatıldı.");

    // Konuşmanın bitmesi için kısa bir gecikme.
    await Future.delayed(const Duration(seconds: 2));

    // Kameraların mevcut olup olmadığını kontrol et.
    if (cameras != null && cameras!.isNotEmpty) {
      // Navigasyon öncesi widget'ın hala ekranda olup olmadığını kontrol et.
      if (!mounted) return;
      // Eğer kamera varsa, CameraScreen'e geç.
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) =>
              CameraScreen(camera: cameras![0]), // İlk kamerayı kullan
        ),
      );
    } else {
      // Kamera bulunamazsa sesli geri bildirim ver.
      await _speak("Kamera bulunamadı.");
    }
  }

  // Türkçe ses testi butonu işlevi.
  void _testTurkishSpeech() async {
    await _speak(
      "Bu bir Türkçe test konuşmasıdır. Eğer beni anlıyorsanız, Türkçe dil desteği çalışıyor demektir.",
    );
  }

  @override
  void dispose() {
    // Widget yok edildiğinde TTS motorunu durdur.
    _flutterTts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      body: Stack(
        children: [
          // "DuruGörü" yazısı ekranın üst yarısının ortasında.
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
                  const SizedBox(height: 10),
                  // TTS durumu göstergesi (hazır veya yükleniyor).
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

          // Algılamayı Başlat butonu ekranın tam ortasında.
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 20,
                    ),
                    textStyle: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  icon: const Icon(Icons.hearing), // İşitme simgesi
                  label: const Text("Algılamayı Başlat"),
                  // TTS hazırsa butonu etkinleştir, yoksa devre dışı bırak.
                  onPressed: _isTtsInitialized ? _startDetection : null,
                ),

                const SizedBox(height: 20),

                // Türkçe ses testi butonu.
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 16,
                    ),
                    textStyle: const TextStyle(fontSize: 18),
                  ),
                  icon: const Icon(Icons.volume_up), // Ses simgesi
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

// Kamera ekranı. Kameradan görüntü alır ve gösterir.
class CameraScreen extends StatefulWidget {
  final CameraDescription camera;

  const CameraScreen({super.key, required this.camera});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  late CameraController _controller; // Kamera kontrolcüsü
  late Future<void> _initializeControllerFuture; // Kamera başlatma geleceği
  final FlutterTts _flutterTts = FlutterTts(); // TTS örneği

  @override
  void initState() {
    super.initState();
    // Kamera kontrolcüsünü başlat.
    _controller = CameraController(
      widget.camera, // Dışarıdan gelen kamera açıklamasını kullanır
      ResolutionPreset.medium, // Orta çözünürlük ayarı
      enableAudio: false, // Ses kaydını devre dışı bırakır
    );
    // Kamera kontrolcüsünün başlatılmasını bekleyen Future'ı başlat.
    _initializeControllerFuture = _controller.initialize();
    // Kamera ekranı için TTS'i başlat.
    _initializeCameraTts();
  }

  // Kamera ekranında TTS'i başlatmak için metod.
  Future<void> _initializeCameraTts() async {
    await _flutterTts.setLanguage("tr-TR");
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.setVolume(0.8);
    await _flutterTts.setPitch(1.0);

    // Kamera açıldıktan sonra kullanıcıya bilgi ver.
    // Small delay to ensure camera is visually ready before speaking.
    Future.delayed(const Duration(seconds: 1), () {
      // Konuşma öncesi widget'ın hala ekranda olup olmadığını kontrol et.
      if (!mounted) return;
      _flutterTts.speak("Kamera aktif. Engel tespiti için hazır.");
    });
  }

  @override
  void dispose() {
    // Widget yok edildiğinde kamera kontrolcüsünü ve TTS'i serbest bırak.
    _controller.dispose();
    _flutterTts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Kamera Aktif"),
        backgroundColor: Colors.black, // AppBar rengi
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back,
            color: Colors.white,
          ), // Geri butonu
          onPressed: () {
            // Geri dönme öncesi widget'ın hala ekranda olup olmadığını kontrol et.
            if (!mounted) return;
            _flutterTts.speak("Kamera kapatıldı.");
            Navigator.pop(context); // Önceki ekrana geri dön
          },
        ),
      ),
      body: FutureBuilder<void>(
        future: _initializeControllerFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            // Eğer kamera başlatılırken bir hata oluştuysa
            if (snapshot.hasError) {
              debugPrint("Kamera başlatma hatası: ${snapshot.error}");
              // Hata mesajını TTS ile seslendir (UI güncellendikten sonra çağrılır).
              WidgetsBinding.instance.addPostFrameCallback((_) {
                // Hata mesajı konuşulmadan önce widget'ın hala ekranda olup olmadığını kontrol et.
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
                        // Geri dönme öncesi widget'ın hala ekranda olup olmadığını kontrol et.
                        if (!mounted) return;
                        Navigator.pop(context); // Geri dönme butonu
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red, // Buton rengi
                        foregroundColor: Colors.white,
                      ),
                      child: const Text("Geri Dön"),
                    ),
                  ],
                ),
              );
            }
            // Kamera başarıyla başlatıldıysa önizlemeyi göster.
            return CameraPreview(_controller);
          } else {
            // Kamera hala başlatılıyorsa yükleme göstergesi.
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
//deneme