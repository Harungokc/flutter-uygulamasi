import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:camera/camera.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'dart:async'; // Zamanlayıcı için gerekli import

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
        // Uygulama arka plan rengini koyu gri/mavi-gri tonu yapıyoruz.
        // Bu, logonun öne çıkmasına yardımcı olacaktır.
        scaffoldBackgroundColor: Colors.blueGrey[900],
        textTheme: const TextTheme(
          bodyLarge: TextStyle(
            color: Colors.white,
            fontSize: 24,
          ), // Varsayılan metin stili
        ),
        // AppBar ve diğer bileşenler için hala koyu renkler uygun
        primaryColor: Colors.black,
        appBarTheme: AppBarTheme(
          // 'withOpacity' yerine 'withAlpha' kullanıldı.
          backgroundColor: Colors.black.withAlpha((255 * 0.8).round()),
          foregroundColor: Colors.white,
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
  // SpeechToText örneği oluşturulur.
  final SpeechToText _speechToText = SpeechToText();
  // TTS'in başlatılıp başlatılmadığını tutan durum değişkeni.
  bool _isTtsInitialized = false;
  // Sesli komutun o anda dinlemede olup olmadığını tutan durum değişkeni.
  bool _isListening = false;
  // Otomatik dinlemeyi durdurmak için kullanılacak zamanlayıcı.
  Timer? _listeningTimer;

  @override
  void initState() {
    super.initState();
    // TTS'i başlat ve tamamlandığında hoş geldiniz mesajını konuş.
    _initializeTts().then((_) {
      // Hoş geldiniz mesajı konuştuktan sonra mikrofonu başlatmayı planla.
      // Mesajın süresi yaklaşık 5 saniye olduğu için biraz daha fazla bekleyelim.
      Future.delayed(const Duration(seconds: 7), () async {
        if (!mounted) return; // Widget hala ekranda mı kontrol et
        bool speechInitialized = await _initializeSpeechToText();
        if (speechInitialized && _isTtsInitialized) {
          _startListening(); // Otomatik olarak dinlemeyi başlat
        } else {
          // Eğer SpeechToText initialize olamazsa, kullanıcıya sesli bir uyarı ver
          if (_isTtsInitialized) {
            await _speak(
              "Sesli komutlar başlatılamadı. Lütfen mikrofon izinlerini ve internet bağlantınızı kontrol edin.",
            );
          }
        }
      });
    });
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

      // TTS başarıyla başlatıldı, durumu güncelle.
      setState(() {
        _isTtsInitialized = true;
      });

      // Uygulama hoş geldiniz mesajını konuş.
      // Mikrofonu başlatmadan önce sadece hoş geldiniz mesajı.
      await _speak(
        "DuruGörüye hoş geldiniz. Lütfen başlamak için sesli komut verin.",
      );
    } catch (e) {
      // TTS başlatma sırasında herhangi bir hata olursa yakala ve logla.
      debugPrint("TTS başlatma hatası: $e");
      setState(() {
        _isTtsInitialized = false;
      });
    }
  }

  // SpeechToText'i başlatmak ve izinleri kontrol etmek için asenkron metod.
  Future<bool> _initializeSpeechToText() async {
    // Burada speech_to_text'in initialize metodu çağrılıyor.
    // onError ve onStatus callback'leri hata ayıklama için kullanılır.
    bool hasSpeech = await _speechToText.initialize(
      onError: (val) => debugPrint("Speech to Text Hatası: ${val.errorMsg}"),
      // val doğrudan String durumunu döndürüyor, .status'a gerek yok.
      onStatus: (val) => debugPrint("Speech to Text Durumu: $val"),
      debugLogging: true, // Hata ayıklama için detaylı logları açar
    );

    if (hasSpeech) {
      debugPrint("Speech to Text başarıyla başlatıldı.");
    } else {
      debugPrint(
        "Speech to Text başlatılamadı. Cihaz desteklemiyor olabilir veya izin yok.",
      );
      // Hata durumunda sesli uyarı initState'de veriliyor.
    }
    return hasSpeech;
  }

  // Metin okuma metodunun kendisi.
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

  // Sesli komut dinlemeyi başlatma metodu
  void _startListening() async {
    // Eğer SpeechToText mevcut değilse, dinleme başlatılamaz.
    if (!_speechToText.isAvailable) {
      debugPrint("Dinleme başlatılamadı: SpeechToText servisi mevcut değil.");
      return;
    }

    // Eğer zaten dinlemedeysek, önceki oturumu ve zamanlayıcıyı iptal et.
    // Bu, hem manuel tekrar başlatmalarda hem de otomatik başlatmanın tekrar tetiklenmesi durumunda önemlidir.
    if (_isListening) {
      _stopListening();
      await Future.delayed(const Duration(milliseconds: 200)); // Kısa gecikme
    }

    setState(() {
      _isListening = true;
    });

    // Kullanıcıya sesli geri bildirim ver: Dinleme başladı.
    if (_isTtsInitialized) {
      await _speak(
        "Dinliyorum. Başlatmak için start deyin. Otomatik olarak 30 saniye sonra duracağım.",
      );
    }

    _speechToText.listen(
      onResult: (result) {
        debugPrint("Tanınan metin: ${result.recognizedWords}");
        // "start" komutunu algıla (büyük/küçük harf duyarlı değil)
        if (result.recognizedWords.toLowerCase().contains("start")) {
          _startDetection(); // Algılamayı başlat
        }
        if (result.finalResult) {
          // Nihai sonuç geldiğinde dinlemeyi durdur (ve zamanlayıcıyı iptal et)
          _stopListening();
        }
      },
      localeId: "tr_TR", // Türkçe dil kodu
      onSoundLevelChange: (level) => debugPrint("Ses Seviyesi: $level"),
      listenFor: const Duration(
        seconds: 25,
      ), // Mikrofonun tek seferde dinleyeceği süre (artırıldı)
      pauseFor: const Duration(
        seconds: 6,
      ), // Sessizlik sonrası duraklama süresi (artırıldı)
      // ignore: deprecated_member_use
      partialResults:
          true, // Kısmi sonuçları da almayı sağlar (hata ayıklama için faydalı)
    );

    // 30 saniye sonra dinlemeyi otomatik olarak durduracak zamanlayıcıyı başlat
    _listeningTimer?.cancel(); // Önceki zamanlayıcı varsa iptal et
    _listeningTimer = Timer(const Duration(seconds: 30), () {
      if (!mounted) return; // Widget hala ekranda mı kontrol et
      if (_isListening) {
        // Sadece hala dinlemede ise durdur
        _stopListening();
        if (_isTtsInitialized) {
          _speak("Sesli komut dinleme otomatik olarak durduruldu.");
        }
      }
    });
  }

  // Sesli komut dinlemeyi durdurma metodu
  void _stopListening() {
    if (!_isListening) return; // Zaten dinlemiyorsa işlem yapma

    _speechToText.stop(); // Konuşma tanıma servisini durdur
    _listeningTimer?.cancel(); // Zamanlayıcıyı da iptal et
    setState(() {
      _isListening = false;
    });
    debugPrint("Dinleme durduruldu.");
  }

  // Algılama başlatma işlevi (hem logo butonu hem de sesli komut için)
  void _startDetection() async {
    // Eğer sesli komutla başlatıldıysa, aktif dinlemeyi durdur.
    if (_isListening) {
      _stopListening();
    }

    // Uygulama aktif olurken seslendirme
    await _speak(
      "DuruGörü aktif, kameranız açılıyor, tehditler algılanmaya hazır.",
    );

    // Seslendirme bitene kadar bekle (yaklaşık 5 saniye sürebilir)
    await Future.delayed(const Duration(seconds: 5));

    // Kameraların mevcut olup olmadığını kontrol et.
    if (cameras != null && cameras!.isNotEmpty) {
      if (!mounted) return; // Widget hala ekranda mı kontrol et
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

  @override
  void dispose() {
    // Widget yok edildiğinde tüm servisleri ve zamanlayıcıları serbest bırak.
    _flutterTts.stop();
    _speechToText.stop();
    _listeningTimer?.cancel(); // Uygulama kapatılırken zamanlayıcıyı iptal et
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      body: Stack(
        children: [
          // Durum göstergeleri (TTS ve Mikrofon) ekranın üst kısmında ortalanmış.
          Positioned(
            top: screenHeight * 0.15,
            left: 0,
            right: 0,
            child: Center(
              child: Column(
                children: [
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
                  const SizedBox(height: 10),
                  // Mikrofon dinleme durumu göstergesi (sadece STT mevcutsa göster)
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

          // Algılamayı Başlat butonu (LOGO BUTONU) ekranın tam ortasında.
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black, // Logo arka planı siyah
                    foregroundColor: Colors.white,
                    // Genişliği ekran genişliğinin %35'i kadar kare bir alan
                    minimumSize: Size(screenWidth * 0.35, screenWidth * 0.35),
                    shape: const StadiumBorder(), // Akuatik model (oval)
                    padding: EdgeInsets.zero, // İç boşluğu sıfırla
                  ),
                  // Logo butonu her zaman aktif olacak (sadece TTS hazırsa)
                  onPressed: _isTtsInitialized
                      ? _startDetection // _isListening kontrolü kaldırıldı
                      : null,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Image.asset(
                      'assets/images/logo.png', // Logo dosyanızın yolu
                      fit: BoxFit.contain, // Logoyu kutuya sığdır
                    ),
                  ),
                ),

                const SizedBox(height: 30), // Butonlar arası boşluk
                // Sesli Komutu Başlat/Durdur Butonu
                // Bu buton artık dinlemeyi manuel olarak kontrol etmek için kullanılır.
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isListening
                        ? Colors.red
                        : Colors.green, // Dinlemedeyse kırmızı, değilse yeşil
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
                  // Eğer STT ve TTS hazırsa buton aktif
                  onPressed: _speechToText.isAvailable && _isTtsInitialized
                      ? (_isListening ? _stopListening : _startListening)
                      : null,
                ),
              ],
            ),
          ),

          // Sağ en altta "DuruGörü" yazısı
          Positioned(
            bottom: 20,
            right: 20,
            child: Text(
              'DuruGörü',
              style: TextStyle(
                // 'withOpacity' yerine 'withAlpha' kullanıldı.
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
