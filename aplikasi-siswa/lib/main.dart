import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:typed_data';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:file_picker/file_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:audioplayers/audioplayers.dart'; // Tambahan package audio
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';

/// Menyimpan lampiran langsung ke Cloud Firestore tanpa Firebase Storage
/// dan tanpa layanan pihak ketiga. File besar dipecah menjadi beberapa dokumen
/// kecil agar setiap dokumen tetap di bawah batas ukuran Firestore.
const int _firestoreChunkSize = 600 * 1024; // 600 KB data mentah/chunk

/// Membuat pemutar video dari bytes yang disimpan di Firestore.
/// File sementara dibuat di penyimpanan cache perangkat agar video bisa
/// diputar kembali oleh siswa tanpa Firebase Storage.
Future<VideoPlayerController> createVideoControllerFromBytes(
  Uint8List bytes,
  String fileName,
) async {
  final directory = await getTemporaryDirectory();
  final safeName = fileName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
  final file = File(
    '${directory.path}/aspirasi_${DateTime.now().microsecondsSinceEpoch}_$safeName',
  );
  await file.writeAsBytes(bytes, flush: true);
  final controller = VideoPlayerController.file(file);
  await controller.initialize();
  return controller;
}

Future<Map<String, dynamic>> _saveMediaChunksToFirestore({
  required DocumentReference<Map<String, dynamic>> parentRef,
  required Uint8List bytes,
  required String fileName,
  required String contentType,
  required String subcollection,
}) async {
  final chunks = <Uint8List>[];
  for (int offset = 0; offset < bytes.length; offset += _firestoreChunkSize) {
    final end = (offset + _firestoreChunkSize < bytes.length)
        ? offset + _firestoreChunkSize
        : bytes.length;
    chunks.add(Uint8List.fromList(bytes.sublist(offset, end)));
  }

  final chunksRef = parentRef.collection(subcollection);
  final batch = FirebaseFirestore.instance.batch();

  for (int i = 0; i < chunks.length; i++) {
    final chunkRef = chunksRef.doc(i.toString().padLeft(6, '0'));
    batch.set(chunkRef, {
      'index': i,
      'data': base64Encode(chunks[i]),
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  await batch.commit();

  return {
    'mediaStorage': 'firestore',
    'mediaUrl': '',
    'mediaName': fileName,
    'mediaContentType': contentType,
    'mediaChunkCount': chunks.length,
    'mediaChunkCollection': subcollection,
    'mediaSizeBytes': bytes.length,
  };
}

// PENANGKAP PESAN SAAT APLIKASI DITUTUP TOTAL / BACKGROUND
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint("Pesan diterima di background: ${message.messageId}");
}

// INISIALISASI NOTIFIKASI
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

// INISIALISASI PEMUTAR AUDIO
final AudioPlayer _audioPlayer = AudioPlayer();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: "YOUR_FIREBASE_WEB_API_KEY",
        authDomain: "pengaduansekolah-eb875.firebaseapp.com",
        projectId: "pengaduansekolah-eb875",
        storageBucket: "pengaduansekolah-eb875.firebasestorage.app",
        messagingSenderId: "265155033945",
        appId: "1:265155033945:web:87b10e00993670c2922a48",
        measurementId: "G-WN6RZCQHEL",
      ),
    );

    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initializationSettings =
        InitializationSettings(android: initializationSettingsAndroid);

    if (!kIsWeb) {
      await flutterLocalNotificationsPlugin.initialize(initializationSettings);
    }
  } catch (e) {
    debugPrint("Error init: $e");
  }

  runApp(const AspirasiSiswaApp());
}

class AspirasiSiswaApp extends StatelessWidget {
  const AspirasiSiswaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Aspirasi Siswa SMKN 1 Sanden',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primaryColor: const Color(0xFF1565C0),
        scaffoldBackgroundColor: const Color(0xFF1565C0),
        fontFamily: 'Roboto',
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1565C0),
          primary: const Color(0xFF1565C0),
        ),
      ),
      home: const LoadingScreen(),
    );
  }
}

// WIDGET REUSABLE UNTUK BACKGROUND VIDEO DINAMIS
class VideoBackgroundWidget extends StatefulWidget {
  final String videoAssetPath;
  final Widget child;
  const VideoBackgroundWidget({
    super.key,
    required this.videoAssetPath,
    required this.child,
  });

  @override
  State<VideoBackgroundWidget> createState() => _VideoBackgroundWidgetState();
}

class _VideoBackgroundWidgetState extends State<VideoBackgroundWidget> {
  late VideoPlayerController _videoController;
  bool _isVideoInitialized = false;

  @override
  void initState() {
    super.initState();
    _videoController = VideoPlayerController.asset(widget.videoAssetPath)
      ..initialize().then((_) {
        if (mounted) {
          setState(() {
            _isVideoInitialized = true;
          });
        }
        _videoController.setLooping(true);
        _videoController.setVolume(0.0);
        _videoController.play();
      }).catchError((error) {
        debugPrint("Error loading video (${widget.videoAssetPath}): $error");
      });
  }

  @override
  void dispose() {
    _videoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        _isVideoInitialized
            ? SizedBox.expand(
                child: FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: _videoController.value.size.width,
                    height: _videoController.value.size.height,
                    child: VideoPlayer(_videoController),
                  ),
                ),
              )
            : Container(color: const Color(0xFF1565C0)),
        Container(color: Colors.black.withAlpha(120)),
        widget.child,
      ],
    );
  }
}

// Pemutar bukti video yang tersimpan sebagai potongan (chunk) di Firestore.
Future<Uint8List> _loadMediaBytesFromFirestore(
  DocumentReference<Map<String, dynamic>> aspirasiRef,
  Map<String, dynamic> data,
) async {
  final collectionName = data['mediaChunkCollection']?.toString() ?? '';
  final chunkCount =
      int.tryParse(data['mediaChunkCount']?.toString() ?? '') ?? 0;
  if (collectionName.isEmpty || chunkCount <= 0) {
    throw Exception('Data video tidak lengkap atau sudah tidak tersedia.');
  }

  final snapshot =
      await aspirasiRef.collection(collectionName).orderBy('index').get();

  if (snapshot.docs.isEmpty) {
    throw Exception('Potongan video tidak ditemukan di Firestore.');
  }

  final bytes = <int>[];
  for (final doc in snapshot.docs) {
    final encoded = doc.data()['data']?.toString() ?? '';
    if (encoded.isEmpty) continue;
    bytes.addAll(base64Decode(encoded));
  }

  if (bytes.isEmpty) {
    throw Exception('Isi video kosong.');
  }
  return Uint8List.fromList(bytes);
}

class _HistoryVideoViewer extends StatefulWidget {
  final DocumentReference<Map<String, dynamic>> aspirasiRef;
  final Map<String, dynamic> data;

  const _HistoryVideoViewer({
    required this.aspirasiRef,
    required this.data,
  });

  @override
  State<_HistoryVideoViewer> createState() => _HistoryVideoViewerState();
}

class _HistoryVideoViewerState extends State<_HistoryVideoViewer> {
  VideoPlayerController? _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadVideo();
  }

  Future<void> _loadVideo() async {
    try {
      final bytes = await _loadMediaBytesFromFirestore(
        widget.aspirasiRef,
        widget.data,
      );
      final controller = await createVideoControllerFromBytes(
        bytes,
        widget.data['mediaName']?.toString() ?? 'bukti.mp4',
      );
      if (!mounted) {
        await controller.dispose();
        return;
      }
      controller.setLooping(false);
      setState(() => _controller = controller);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 42),
            const SizedBox(height: 12),
            const Text(
              'Video tidak dapat diputar.',
              style: TextStyle(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              _error!,
              style: const TextStyle(fontSize: 11, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const Padding(
        padding: EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 14),
            Text('Memuat video bukti...'),
          ],
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AspectRatio(
          aspectRatio: controller.value.aspectRatio == 0
              ? 16 / 9
              : controller.value.aspectRatio,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: VideoPlayer(controller),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              tooltip: controller.value.isPlaying ? 'Jeda' : 'Putar',
              icon: Icon(
                controller.value.isPlaying
                    ? Icons.pause_circle_filled
                    : Icons.play_circle_fill,
                size: 42,
                color: const Color(0xFF1565C0),
              ),
              onPressed: () {
                setState(() {
                  controller.value.isPlaying
                      ? controller.pause()
                      : controller.play();
                });
              },
            ),
            IconButton(
              tooltip: 'Ulangi',
              icon: const Icon(Icons.replay, color: Color(0xFF1565C0)),
              onPressed: () async {
                await controller.seekTo(Duration.zero);
                await controller.play();
                if (mounted) setState(() {});
              },
            ),
          ],
        ),
        Text(
          widget.data['mediaName']?.toString() ?? 'Bukti video',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 11, color: Colors.grey),
        ),
      ],
    );
  }
}

// 1. WELCOME SCREEN

// LOADING SCREEN / SPLASH SCREEN
// Aplikasi bersifat ONLINE-ONLY: selama internet belum tersedia,
// pengguna tetap berada di splash screen dan tidak dapat masuk ke aplikasi.
class LoadingScreen extends StatefulWidget {
  const LoadingScreen({super.key});

  @override
  State<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<LoadingScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _fadeAnimation;
  StreamSubscription<InternetStatus>? _internetSubscription;
  bool _isOnline = false;
  bool _isEntering = false;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _scaleAnimation = Tween<double>(begin: 0.94, end: 1.04).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    _fadeAnimation = Tween<double>(begin: 0.65, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    _checkInternet();
    _internetSubscription =
        InternetConnection().onStatusChange.listen((status) {
      final connected = status == InternetStatus.connected;
      if (!mounted) return;
      setState(() => _isOnline = connected);
      if (connected) _enterAppWhenReady();
    });
  }

  Future<void> _checkInternet() async {
    try {
      final connected = await InternetConnection().hasInternetAccess;
      if (!mounted) return;
      setState(() => _isOnline = connected);
      if (connected) _enterAppWhenReady();
    } catch (_) {
      if (!mounted) return;
      setState(() => _isOnline = false);
    }
  }

  Future<void> _enterAppWhenReady() async {
    if (_isEntering) return;
    _isEntering = true;

    // Beri waktu singkat agar loading tetap terlihat walaupun koneksi cepat.
    await Future.delayed(const Duration(milliseconds: 1200));
    if (!mounted) return;

    // Pastikan internet masih tersedia tepat sebelum masuk aplikasi.
    try {
      final connected = await InternetConnection().hasInternetAccess;
      if (!connected) {
        _isEntering = false;
        if (mounted) setState(() => _isOnline = false);
        return;
      }
    } catch (_) {
      _isEntering = false;
      if (mounted) setState(() => _isOnline = false);
      return;
    }

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const WelcomeScreen(),
        transitionDuration: const Duration(milliseconds: 650),
        transitionsBuilder: (_, animation, __, child) => FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: child,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _internetSubscription?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0D47A1), Color(0xFF1565C0), Color(0xFF42A5F5)],
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              top: -100,
              right: -80,
              child: Container(
                width: 260,
                height: 260,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.07),
                ),
              ),
            ),
            Positioned(
              bottom: -120,
              left: -90,
              child: Container(
                width: 300,
                height: 300,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.06),
                ),
              ),
            ),
            SafeArea(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AnimatedBuilder(
                        animation: _controller,
                        builder: (context, child) => Opacity(
                          opacity: _fadeAnimation.value,
                          child: Transform.scale(
                            scale: _scaleAnimation.value,
                            child: child,
                          ),
                        ),
                        child: Container(
                          width: 128,
                          height: 128,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.22),
                                blurRadius: 28,
                                spreadRadius: 3,
                              ),
                            ],
                          ),
                          child: Image.asset(
                            'assets/logo_sekolah.png',
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                      const SizedBox(height: 28),
                      const Text(
                        'ASPIRASI SISWA',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 25,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 2.0,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'SMK NEGERI 1 SANDEN',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Platform Aspirasi & Pengaduan Siswa',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 42),
                      // Spinner terus berputar selama menunggu koneksi.
                      SizedBox(
                        width: 42,
                        height: 42,
                        child: CircularProgressIndicator(
                          strokeWidth: 4,
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                          backgroundColor: Colors.white.withOpacity(0.20),
                        ),
                      ),
                      const SizedBox(height: 18),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 250),
                        child: Text(
                          _isOnline
                              ? 'Internet tersedia • Menyiapkan aplikasi...'
                              : 'Menghubungkan ke internet...',
                          key: ValueKey(_isOnline),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: _isOnline ? Colors.white : Colors.white70,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _isOnline
                            ? 'Koneksi online aktif'
                            : 'Aplikasi membutuhkan koneksi internet',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 48),
                      const Text(
                        '© Nareva Ranov • Student Developer',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white54,
                          fontSize: 11,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  void _showTutorialDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.help_outline, color: Color(0xFF1565C0)),
            SizedBox(width: 8),
            Text('Tutorial Penggunaan', style: TextStyle(fontSize: 18)),
          ],
        ),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Panduan Singkat Aplikasi Aspirasi Siswa:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text(
                  '1. Buat Akun / Daftar menggunakan NIS, Nama, Kelas, dan Password Anda jika belum terdaftar.'),
              SizedBox(height: 6),
              Text('2. Masuk (Login) menggunakan NIS dan Password akun Anda.'),
              SizedBox(height: 6),
              Text(
                  '3. Pada Dashboard, pilih kategori aspirasi (Sarana, Kebersihan, Kurikulum, dll).'),
              SizedBox(height: 6),
              Text(
                  '4. Isi lokasi/sarana sekolah dan keterangan detail pengaduan Anda.'),
              SizedBox(height: 6),
              Text(
                  '5. Anda dapat melampirkan beberapa foto bukti dari Kamera atau Galeri, serta bukti video/audio sesuai fitur aplikasi.'),
              SizedBox(height: 6),
              Text(
                  '6. Kirim aspirasi, klik grafik batang laporan untuk memfilter status (Menunggu, Diproses, Selesai), dan pantau tanggapan secara real-time.'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Mengerti',
                style: TextStyle(
                    color: Color(0xFF1565C0), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: VideoBackgroundWidget(
        videoAssetPath: 'assets/profil_sekolah.mp4',
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Align(
                  alignment: Alignment.topRight,
                  child: IconButton(
                    icon: const Icon(Icons.help_outline,
                        color: Colors.white, size: 26),
                    tooltip: 'Tutorial Bantuan',
                    onPressed: () => _showTutorialDialog(context),
                  ),
                ),
                Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withAlpha(50),
                            blurRadius: 10,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: Image.asset(
                        'assets/logo_bg.png',
                        height: 80,
                        width: 80,
                        errorBuilder: (context, error, stackTrace) =>
                            const Icon(
                          Icons.school,
                          size: 70,
                          color: Color(0xFF1565C0),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'ASPIRASI SISWA',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const SizedBox(height: 10),
                    const Text(
                      'SELAMAT DATANG 👋',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: .6,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'SMKN 1 SANDEN',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                        letterSpacing: 1.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Sampaikan aspirasi, saran, dan pengaduan untuk lingkungan sekolah yang lebih baik.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12.5,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(.16),
                        borderRadius: BorderRadius.circular(30),
                        border:
                            Border.all(color: Colors.white.withOpacity(.25)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.access_time_rounded,
                              color: Colors.white, size: 17),
                          SizedBox(width: 7),
                          Text(
                            'Layanan Aspirasi 24 Jam',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                Column(
                  children: [
                    InkWell(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (context) =>
                                  const ProfilSekolahScreen()),
                        );
                      },
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            vertical: 16, horizontal: 16),
                        decoration: BoxDecoration(
                          color: Colors.white.withAlpha(35),
                          borderRadius: BorderRadius.circular(16),
                          border:
                              Border.all(color: Colors.white.withAlpha(100)),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.info_outline,
                                color: Colors.white, size: 28),
                            SizedBox(width: 14),
                            Expanded(
                              child: Text(
                                'Profil & Informasi Sekolah',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16),
                              ),
                            ),
                            Icon(Icons.arrow_forward_ios,
                                color: Colors.white70, size: 16),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: const Color(0xFF1565C0),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                          elevation: 4,
                        ),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (context) => const LoginScreen()),
                          );
                        },
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.school_rounded, size: 22),
                            SizedBox(width: 10),
                            Text(
                              'Masuk Aplikasi',
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const Text(
                  '2026 Developed by NarevaRanovP',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// 2. PROFIL SEKOLAH SCREEN
class ProfilSekolahScreen extends StatelessWidget {
  const ProfilSekolahScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1565C0),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1565C0),
        elevation: 0,
        title: const Text(
          'Profil & Informasi Sekolah',
          style: TextStyle(
              color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: double.infinity,
                height: 280,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: ShaderMask(
                        shaderCallback: (Rect bounds) {
                          return LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.white,
                              Colors.white,
                              Colors.transparent,
                            ],
                            stops: const [0.0, 0.5, 1.0],
                          ).createShader(bounds);
                        },
                        blendMode: BlendMode.dstIn,
                        child: Image.asset(
                          'assets/sekolah.png',
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              Container(color: const Color(0xFF0D47A1)),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              const Color(0xFF1565C0).withOpacity(0.7),
                              const Color(0xFF1565C0).withOpacity(0.95),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black26,
                                    blurRadius: 8,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Image.asset(
                                'assets/logo_bg.png',
                                height: 65,
                                width: 65,
                                errorBuilder: (context, error, stackTrace) =>
                                    const Icon(
                                  Icons.school,
                                  size: 55,
                                  color: Color(0xFF1565C0),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'SMK NEGERI 1 SANDEN',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.2,
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Kabupaten Bantul, Daerah Istimewa Yogyakarta',
                              style: TextStyle(
                                  color: Colors.white70, fontSize: 12.5),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0D47A1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.history_edu,
                                  color: Colors.white, size: 22),
                              SizedBox(width: 8),
                              Text(
                                'Sejarah & Alamat',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          SizedBox(height: 10),
                          Text(
                            'SMK Negeri 1 Sanden didirikan pada tahun 2004. Sekolah kejuruan negeri ini berfokus pada bidang teknologi, rekayasa, serta potensi kelautan dan kemaritiman di Kabupaten Bantul.',
                            style: TextStyle(
                                color: Colors.white, fontSize: 13, height: 1.4),
                          ),
                          SizedBox(height: 10),
                          Text(
                            'Alamat: Jl. Samas Km. 11, Ngemplak, Srigading, Sanden, Kabupaten Bantul.',
                            style: TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                                height: 1.4),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    const SizedBox(height: 24),
                    _buildProfileSectionTitle(Icons.visibility_rounded, 'Visi'),
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0D47A1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: const Text(
                        '“Mewujudkan generasi yang unggul, berkarakter, kompeten, kreatif, dan adaptif terhadap perkembangan teknologi serta siap menghadapi dunia kerja dan masa depan.”',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            height: 1.6,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(height: 24),
                    _buildProfileSectionTitle(
                        Icons.rocket_launch_rounded, 'Misi'),
                    const SizedBox(height: 10),
                    _buildMisiCard(
                        '01',
                        'Pendidikan Berkualitas',
                        'Menyelenggarakan pendidikan yang berkualitas dan relevan dengan perkembangan dunia kerja.',
                        Icons.school_rounded),
                    _buildMisiCard(
                        '02',
                        'Kompetensi & Teknologi',
                        'Mengembangkan kompetensi dan keterampilan siswa melalui pembelajaran inovatif dan berbasis teknologi.',
                        Icons.computer_rounded),
                    _buildMisiCard(
                        '03',
                        'Karakter',
                        'Membentuk siswa yang disiplin, bertanggung jawab, berintegritas, dan memiliki kepedulian sosial.',
                        Icons.diversity_3_rounded),
                    _buildMisiCard(
                        '04',
                        'Kreativitas & Inovasi',
                        'Mendorong kreativitas dan inovasi siswa melalui kegiatan akademik maupun nonakademik.',
                        Icons.lightbulb_rounded),
                    _buildMisiCard(
                        '05',
                        'Lingkungan Positif',
                        'Membangun lingkungan sekolah yang aman, nyaman, bersih, dan mendukung proses pembelajaran.',
                        Icons.eco_rounded),
                    _buildMisiCard(
                        '06',
                        'Masa Depan Siswa',
                        'Meningkatkan kesiapan siswa untuk melanjutkan pendidikan, memasuki dunia kerja, maupun berwirausaha.',
                        Icons.trending_up_rounded),
                    const SizedBox(height: 24),
                    _buildProfileSectionTitle(
                        Icons.stars_rounded, 'Nilai Utama'),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                            child: _buildNilaiCard(
                                Icons.workspace_premium_rounded, 'Unggul')),
                        const SizedBox(width: 10),
                        Expanded(
                            child: _buildNilaiCard(
                                Icons.psychology_rounded, 'Kreatif')),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                            child: _buildNilaiCard(
                                Icons.verified_user_rounded, 'Berkarakter')),
                        const SizedBox(width: 10),
                        Expanded(
                            child: _buildNilaiCard(
                                Icons.devices_rounded, 'Adaptif')),
                      ],
                    ),
                    const SizedBox(height: 28),
                    const Text(
                      'Program Keahlian / Jurusan',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    _buildJurusanCard(
                      title: 'Nautika Kapal Penangkap Ikan (NKPI)',
                      description:
                          'Mempelajari navigasi, teknik berlayar, dan pengoperasian kapal penangkap ikan profesional.',
                      icon: Icons.directions_boat,
                    ),
                    _buildJurusanCard(
                      title: 'Teknika Kapal Penangkap Ikan (TKPI)',
                      description:
                          'Fokus pada pemeliharaan, perbaikan mesin, dan sistem kelistrikan kapal penangkap ikan.',
                      icon: Icons.engineering,
                    ),
                    _buildJurusanCard(
                      title: 'Agrobisnis Pengolahan Hasil Perikanan (APHPI)',
                      description:
                          'Mempelajari teknologi pengawetan, pengolahan, dan uji mutu produk hasil perikanan.',
                      icon: Icons.set_meal,
                    ),
                    _buildJurusanCard(
                      title: 'Agribisnis Perikanan Air Tawar (APAT)',
                      description:
                          'Teknik budidaya ikan air tawar, manajemen kualitas air, serta penetasan benih unggul.',
                      icon: Icons.tsunami,
                    ),
                    _buildJurusanCard(
                      title: 'Rekayasa Perangkat Lunak (RPL)',
                      description:
                          'Pengembangan aplikasi mobile, web, pemrograman software, dan basis data teknologi masa kini.',
                      icon: Icons.code,
                    ),
                    _buildJurusanCard(
                      title: 'Teknik Kendaraan Ringan Otomotif (TKRO)',
                      description:
                          'Perawatan, servis, dan perbaikan mesin serta sistem kelistrikan mobil modern.',
                      icon: Icons.directions_car,
                    ),
                    _buildJurusanCard(
                      title: 'Teknik Bodi Otomotif (TBO)',
                      description:
                          'Keahlian perbaikan rangka kendaraan, pengecatan bodi mobil, dan restorasi bodi kendaraan.',
                      icon: Icons.car_repair,
                    ),
                    const SizedBox(height: 30),
                    const Center(
                      child: Text('2026 Developed by NarevaRanovP',
                          style:
                              TextStyle(color: Colors.white70, fontSize: 12)),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfileSectionTitle(IconData icon, String title) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: const Color(0xFF1565C0), size: 21),
        ),
        const SizedBox(width: 10),
        Text(title,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800)),
      ],
    );
  }

  Widget _buildMisiCard(
      String number, String title, String description, IconData icon) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0D47A1),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
                color: Colors.white, borderRadius: BorderRadius.circular(13)),
            child: Icon(icon, color: const Color(0xFF1565C0), size: 23),
          ),
          const SizedBox(width: 12),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('$number  $title',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(description,
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 12, height: 1.45)),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _buildNilaiCard(IconData icon, String title) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF0D47A1),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(children: [
        Icon(icon, color: Colors.white, size: 27),
        const SizedBox(height: 7),
        Text(title,
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 12.5)),
      ]),
    );
  }

  Widget _buildJurusanCard(
      {required String title,
      required String description,
      required IconData icon}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0D47A1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white24),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withAlpha(30),
              blurRadius: 6,
              offset: const Offset(0, 3)),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: const Color(0xFF1565C0), size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 12.5, height: 1.3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// PORTAL ADMIN DI DALAM APLIKASI MOBILE
// Menggunakan akun Firebase Authentication yang sama dengan Portal Admin Web.
// -----------------------------------------------------------------------------
class AdminDashboardMobile extends StatefulWidget {
  const AdminDashboardMobile({super.key});

  @override
  State<AdminDashboardMobile> createState() => _AdminDashboardMobileState();
}

class _AdminDashboardMobileState extends State<AdminDashboardMobile> {
  bool _loading = true;
  String _filter = 'Semua';
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _items = [];
  bool _ratingsLoading = true;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _ratings = [];

  @override
  void initState() {
    super.initState();
    _loadAspirasi();
    _loadRatings();
  }

  Future<void> _loadRatings() async {
    try {
      final snap =
          await FirebaseFirestore.instance.collection('rating_aplikasi').get();
      final ratings = [...snap.docs];
      ratings.sort((a, b) {
        final ad = a.data()['createdAt'];
        final bd = b.data()['createdAt'];
        final at = ad is Timestamp ? ad : Timestamp(0, 0);
        final bt = bd is Timestamp ? bd : Timestamp(0, 0);
        return bt.compareTo(at);
      });
      if (mounted) {
        setState(() {
          _ratings = ratings;
          _ratingsLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _ratingsLoading = false);
    }
  }

  double get _averageRating {
    if (_ratings.isEmpty) return 0;
    final total = _ratings.fold<double>(0, (sum, doc) {
      final value = doc.data()['rating'];
      return sum + (value is num ? value.toDouble() : 0);
    });
    return total / _ratings.length;
  }

  Future<void> _loadAspirasi() async {
    setState(() => _loading = true);
    try {
      final snap =
          await FirebaseFirestore.instance.collection('aspirasi').get();
      final items = [...snap.docs];
      items.sort((a, b) {
        final ad = a.data()['createdAt'];
        final bd = b.data()['createdAt'];
        DateTime at = ad is Timestamp ? ad.toDate() : DateTime(1970);
        DateTime bt = bd is Timestamp ? bd.toDate() : DateTime(1970);
        return bt.compareTo(at);
      });
      if (mounted)
        setState(() {
          _items = items;
          _loading = false;
        });
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal memuat data aspirasi: $e')),
        );
      }
    }
  }

  String _status(Map<String, dynamic> d) =>
      (d['status'] ?? d['state'] ?? 'Menunggu').toString();

  List<QueryDocumentSnapshot<Map<String, dynamic>>> get _filtered {
    if (_filter == 'Semua') return _items;
    return _items.where((e) {
      final s = _status(e.data()).toLowerCase();
      return s == _filter.toLowerCase();
    }).toList();
  }

  int _count(String status) => _items.where((e) {
        final s = _status(e.data()).toLowerCase();
        return status == 'Semua' ? true : s == status.toLowerCase();
      }).length;

  Future<void> _changeStatus(
      QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    final current = _status(doc.data());
    final selected = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Ubah Status Aspirasi'),
        children: ['Menunggu', 'Diproses', 'Selesai', 'Ditolak'].map((s) {
          return SimpleDialogOption(
            onPressed: () => Navigator.pop(context, s),
            child: Row(
              children: [
                Icon(
                    s == current
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    color: const Color(0xFF1565C0)),
                const SizedBox(width: 10),
                Text(s),
              ],
            ),
          );
        }).toList(),
      ),
    );
    if (selected == null || selected == current) return;
    try {
      await doc.reference.update({
        'status': selected,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      await _loadAspirasi();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal mengubah status: $e')),
        );
      }
    }
  }

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  String _formatDate(dynamic value) {
    if (value is! Timestamp) return '-';
    final d = value.toDate();
    const months = [
      'Januari',
      'Februari',
      'Maret',
      'April',
      'Mei',
      'Juni',
      'Juli',
      'Agustus',
      'September',
      'Oktober',
      'November',
      'Desember'
    ];
    final h = d.hour.toString().padLeft(2, '0');
    final m = d.minute.toString().padLeft(2, '0');
    return '${d.day} ${months[d.month - 1]} ${d.year}, $h:$m';
  }

  Widget _stat(String title, int value, IconData icon) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(.06), blurRadius: 12)
          ],
        ),
        child: Column(children: [
          Icon(icon, color: const Color(0xFF1565C0), size: 25),
          const SizedBox(height: 5),
          Text('$value',
              style:
                  const TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
          Text(title,
              style: const TextStyle(fontSize: 10.5, color: Colors.grey)),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final list = _filtered;
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F1D38),
        foregroundColor: Colors.white,
        title: const Text('Portal Admin',
            style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(onPressed: _loadAspirasi, icon: const Icon(Icons.refresh)),
          IconButton(onPressed: _logout, icon: const Icon(Icons.logout)),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadAspirasi,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [Color(0xFF0F1D38), Color(0xFF1565C0)]),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(children: [
                Container(
                    width: 52,
                    height: 52,
                    decoration: const BoxDecoration(
                        color: Colors.white24, shape: BoxShape.circle),
                    child: const Icon(Icons.admin_panel_settings,
                        color: Colors.white, size: 30)),
                const SizedBox(width: 14),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      const Text('Selamat datang, Admin',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text(user?.email ?? '-',
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 12),
                          overflow: TextOverflow.ellipsis),
                    ])),
              ]),
            ),
            const SizedBox(height: 14),
            Row(children: [
              _stat('Total', _count('Semua'), Icons.inbox_rounded),
              _stat(
                  'Menunggu', _count('Menunggu'), Icons.hourglass_top_rounded),
              _stat('Diproses', _count('Diproses'), Icons.autorenew_rounded),
              _stat('Selesai', _count('Selesai'), Icons.check_circle_rounded),
            ]),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(.05), blurRadius: 12)
                ],
              ),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const Icon(Icons.star_rounded,
                          color: Colors.amber, size: 26),
                      const SizedBox(width: 8),
                      const Expanded(
                          child: Text('Rating & Komentar Aplikasi',
                              style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF0F1D38)))),
                      Text('${_averageRating.toStringAsFixed(1)} / 5',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1565C0))),
                    ]),
                    const SizedBox(height: 7),
                    Row(children: [
                      ...List.generate(
                          5,
                          (i) => Icon(
                              i < _averageRating.round()
                                  ? Icons.star
                                  : Icons.star_border,
                              color: Colors.amber,
                              size: 19)),
                      const SizedBox(width: 8),
                      Text('${_ratings.length} penilaian',
                          style: const TextStyle(
                              color: Colors.grey, fontSize: 12)),
                    ]),
                    const SizedBox(height: 10),
                    if (_ratingsLoading)
                      const Center(
                          child: Padding(
                              padding: EdgeInsets.all(8),
                              child: CircularProgressIndicator()))
                    else if (_ratings.isEmpty)
                      const Text('Belum ada rating dari siswa.',
                          style: TextStyle(color: Colors.grey))
                    else
                      ..._ratings.take(5).map((doc) {
                        final r = doc.data();
                        final nama = (r['nama'] ?? 'Siswa').toString();
                        final kelas = (r['kelas'] ?? '').toString();
                        final komentar = (r['komentar'] ?? '').toString();
                        final nilai = r['rating'] is num
                            ? (r['rating'] as num).toInt().clamp(1, 5)
                            : 0;
                        return Container(
                          margin: const EdgeInsets.only(top: 8),
                          padding: const EdgeInsets.all(11),
                          decoration: BoxDecoration(
                              color: const Color(0xFFF7F9FC),
                              borderRadius: BorderRadius.circular(12)),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(children: [
                                  Expanded(
                                      child: Text(
                                          '$nama${kelas.isNotEmpty ? ' • $kelas' : ''}',
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w600))),
                                  ...List.generate(
                                      5,
                                      (i) => Icon(
                                          i < nilai
                                              ? Icons.star
                                              : Icons.star_border,
                                          color: Colors.amber,
                                          size: 15)),
                                ]),
                                if (komentar.isNotEmpty) ...[
                                  const SizedBox(height: 5),
                                  Text(komentar,
                                      style: const TextStyle(
                                          color: Colors.black87, fontSize: 13)),
                                ],
                              ]),
                        );
                      }),
                  ]),
            ),
            const SizedBox(height: 20),
            const Text('Riwayat Aspirasi',
                style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F1D38))),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                  children: [
                'Semua',
                'Menunggu',
                'Diproses',
                'Selesai',
                'Ditolak'
              ]
                      .map((s) => Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                                label: Text(s),
                                selected: _filter == s,
                                onSelected: (_) => setState(() => _filter = s)),
                          ))
                      .toList()),
            ),
            const SizedBox(height: 12),
            if (_loading)
              const Center(
                  child: Padding(
                      padding: EdgeInsets.all(35),
                      child: CircularProgressIndicator()))
            else if (list.isEmpty)
              const Padding(
                  padding: EdgeInsets.all(35),
                  child: Center(child: Text('Belum ada aspirasi.')))
            else
              ...list.map((doc) {
                final d = doc.data();
                final status = _status(d);
                final kategori =
                    (d['kategori'] ?? d['category'] ?? 'Pengaduan').toString();
                final nama =
                    (d['nama'] ?? d['namaSiswa'] ?? 'Siswa').toString();
                final isi = (d['keterangan'] ??
                        d['deskripsi'] ??
                        d['isi'] ??
                        d['pesan'] ??
                        '-')
                    .toString();
                Color statusColor = status.toLowerCase() == 'selesai'
                    ? Colors.green
                    : status.toLowerCase() == 'diproses'
                        ? Colors.deepPurple
                        : status.toLowerCase() == 'ditolak'
                            ? Colors.red
                            : Colors.orange;
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Expanded(
                                child: Text(kategori,
                                    style: const TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF1565C0)))),
                            InkWell(
                                onTap: () => _changeStatus(doc),
                                borderRadius: BorderRadius.circular(10),
                                child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 7),
                                    decoration: BoxDecoration(
                                        color: statusColor.withOpacity(.12),
                                        borderRadius:
                                            BorderRadius.circular(10)),
                                    child: Text(status,
                                        style: TextStyle(
                                            color: statusColor,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12)))),
                          ]),
                          const SizedBox(height: 8),
                          Text(_formatDate(d['createdAt']),
                              style: const TextStyle(
                                  color: Colors.grey, fontSize: 12)),
                          const SizedBox(height: 8),
                          Text(nama,
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Text(isi,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.black87)),
                          const SizedBox(height: 10),
                          OutlinedButton.icon(
                              onPressed: () => _changeStatus(doc),
                              icon: const Icon(Icons.edit_outlined, size: 18),
                              label: const Text('Ubah Status')),
                        ]),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}

// 3. LOGIN SCREEN
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _idController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;
  String _role = 'siswa';

  Future<void> _login() async {
    final id = _idController.text.trim();
    final password = _passwordController.text.trim();

    if (id.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_role == 'siswa'
              ? 'NIS dan Password harus diisi!'
              : _role == 'petugas'
                  ? 'ID Petugas dan Password harus diisi!'
                  : 'Email Admin dan Password harus diisi!'),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      if (_role == 'siswa') {
        final query = await FirebaseFirestore.instance
            .collection('siswa')
            .where('nis', isEqualTo: id)
            .where('password', isEqualTo: password)
            .limit(1)
            .get();

        if (!mounted) return;
        setState(() => _isLoading = false);

        if (query.docs.isNotEmpty) {
          final data = query.docs.first.data();
          final nama = data['nama']?.toString() ?? 'Siswa';
          final kelas = data['kelas']?.toString() ?? 'XII RPL 2';
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) =>
                  DashboardScreen(nis: id, nama: nama, kelas: kelas),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('NIS atau Password salah / belum terdaftar!')),
          );
        }
      } else if (_role == 'admin') {
        try {
          await FirebaseAuth.instance.signInWithEmailAndPassword(
            email: id,
            password: password,
          );
          if (!mounted) return;
          setState(() => _isLoading = false);
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
                builder: (context) => const AdminDashboardMobile()),
          );
        } on FirebaseAuthException catch (e) {
          if (!mounted) return;
          setState(() => _isLoading = false);
          final message = e.code == 'invalid-credential' ||
                  e.code == 'wrong-password' ||
                  e.code == 'user-not-found'
              ? 'Email Admin atau Password salah.'
              : 'Login Admin gagal: ${e.message ?? e.code}';
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(message)));
        }
      } else {
        // Kompatibel dengan beberapa bentuk data petugas yang umum digunakan:
        // document ID, idPetugas, id, atau username. Field password tetap dibaca
        // dari Firestore agar tidak mengubah struktur database yang sudah ada.
        DocumentSnapshot<Map<String, dynamic>>? petugasDoc;

        final directDoc = await FirebaseFirestore.instance
            .collection('petugas')
            .doc(id)
            .get();
        if (directDoc.exists) {
          final d = directDoc.data() ?? {};
          final storedPassword = d['password']?.toString() ?? '';
          final status = (d['status'] ?? 'aktif').toString().toLowerCase();
          final active = d['aktif'] is bool ? d['aktif'] as bool : true;
          if (storedPassword == password &&
              active &&
              status != 'nonaktif' &&
              status != 'inactive') {
            petugasDoc = directDoc;
          }
        }

        Future<DocumentSnapshot<Map<String, dynamic>>?> findPetugas(
            String field) async {
          final q = await FirebaseFirestore.instance
              .collection('petugas')
              .where(field, isEqualTo: id)
              .where('password', isEqualTo: password)
              .limit(1)
              .get();
          if (q.docs.isEmpty) return null;
          final d = q.docs.first.data();
          final status = (d['status'] ?? 'aktif').toString().toLowerCase();
          final active = d['aktif'] is bool ? d['aktif'] as bool : true;
          if (!active || status == 'nonaktif' || status == 'inactive')
            return null;
          return q.docs.first;
        }

        if (petugasDoc == null) {
          petugasDoc = await findPetugas('idPetugas');
        }
        if (petugasDoc == null) {
          petugasDoc = await findPetugas('id');
        }
        if (petugasDoc == null) {
          petugasDoc = await findPetugas('username');
        }

        if (!mounted) return;
        setState(() => _isLoading = false);

        if (petugasDoc != null && petugasDoc.exists) {
          final data = petugasDoc.data() ?? {};
          final nama = data['nama']?.toString() ?? 'Petugas';
          final bidang = data['bidang']?.toString() ??
              data['jabatan']?.toString() ??
              'Petugas Sekolah';
          final idPetugas = data['idPetugas']?.toString() ??
              data['id']?.toString() ??
              petugasDoc.id;
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => PetugasDashboardScreen(
                idPetugas: idPetugas,
                nama: nama,
                bidang: bidang,
              ),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text(
                    'ID Petugas/Username atau Password salah, atau akun tidak aktif!')),
          );
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal terhubung ke server: $e')),
      );
    }
  }

  Widget _buildRoleButton({
    required String label,
    required IconData icon,
    required String value,
  }) {
    final selected = _role == value;
    return InkWell(
      onTap: _isLoading
          ? null
          : () => setState(() {
                _role = value;
                _idController.clear();
                _passwordController.clear();
              }),
      borderRadius: BorderRadius.circular(11),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(11),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                size: 18,
                color: selected ? const Color(0xFF1565C0) : Colors.white70),
            const SizedBox(width: 7),
            Text(
              label,
              style: TextStyle(
                color: selected ? const Color(0xFF1565C0) : Colors.white70,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _idController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: VideoBackgroundWidget(
        videoAssetPath: 'assets/video_ikan.mp4',
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                        color: Colors.white.withAlpha(200),
                        shape: BoxShape.circle),
                    child: Image.asset(
                      'assets/logo_bg.png',
                      height: 60,
                      width: 60,
                      errorBuilder: (context, error, stackTrace) => const Icon(
                          Icons.school,
                          size: 50,
                          color: Color(0xFF1565C0)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'SMKN 1 SANDEN',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5),
                  ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(35),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.white.withAlpha(100)),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withAlpha(30),
                            blurRadius: 15,
                            offset: const Offset(0, 8)),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          _role == 'siswa'
                              ? 'Masuk Akun Siswa'
                              : _role == 'petugas'
                                  ? 'Masuk Akun Petugas'
                                  : 'Masuk Akun Admin',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 24),
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.black.withAlpha(35),
                            borderRadius: BorderRadius.circular(14),
                            border:
                                Border.all(color: Colors.white.withAlpha(70)),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: _buildRoleButton(
                                  label: 'Siswa',
                                  icon: Icons.school_rounded,
                                  value: 'siswa',
                                ),
                              ),
                              Expanded(
                                child: _buildRoleButton(
                                  label: 'Petugas',
                                  icon: Icons.engineering_rounded,
                                  value: 'petugas',
                                ),
                              ),
                              Expanded(
                                child: _buildRoleButton(
                                  label: 'Admin',
                                  icon: Icons.admin_panel_settings_rounded,
                                  value: 'admin',
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                        TextField(
                          controller: _idController,
                          keyboardType: TextInputType.text,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: Colors.black.withAlpha(40),
                            prefixIcon: Icon(
                              _role == 'siswa'
                                  ? Icons.badge_outlined
                                  : _role == 'petugas'
                                      ? Icons.badge
                                      : Icons.email_outlined,
                              color: Colors.white70,
                            ),
                            hintText: _role == 'siswa'
                                ? 'NIS (Nomor Induk Siswa)'
                                : _role == 'petugas'
                                    ? 'ID Petugas'
                                    : 'Email Administrator',
                            hintStyle: const TextStyle(
                                color: Colors.white70, fontSize: 14),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide.none),
                            contentPadding:
                                const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: Colors.black.withAlpha(40),
                            prefixIcon: const Icon(Icons.lock_outline,
                                color: Colors.white70),
                            suffixIcon: IconButton(
                              icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_off
                                      : Icons.visibility,
                                  color: Colors.white70),
                              onPressed: () => setState(
                                  () => _obscurePassword = !_obscurePassword),
                            ),
                            hintText: 'Password',
                            hintStyle: const TextStyle(
                                color: Colors.white70, fontSize: 14),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide.none),
                            contentPadding:
                                const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: const Color(0xFF1565C0),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                          ),
                          onPressed: _isLoading ? null : _login,
                          child: _isLoading
                              ? const CircularProgressIndicator(
                                  color: Color(0xFF1565C0))
                              : Text(
                                  _role == 'siswa'
                                      ? 'Masuk sebagai Siswa'
                                      : 'Masuk sebagai Petugas',
                                  style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold)),
                        ),
                        if (_role == 'siswa') ...[
                          const SizedBox(height: 16),
                          Center(
                            child: GestureDetector(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (context) =>
                                          const RegisterScreen()),
                                );
                              },
                              child: const Text(
                                'Belum punya akun? Buat Akun Baru',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 30),
                  const Text('2026 Developed by NarevaRanovP',
                      style: TextStyle(color: Colors.white70, fontSize: 12)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// DASHBOARD PETUGAS
// Petugas menggunakan APK yang sama dengan siswa. Admin tetap menggunakan web terpisah.
// Web Admin harus mengisi field `petugasId` pada dokumen aspirasi ketika melakukan assignment.
class PetugasDashboardScreen extends StatefulWidget {
  final String idPetugas;
  final String nama;
  final String bidang;

  const PetugasDashboardScreen({
    super.key,
    required this.idPetugas,
    required this.nama,
    required this.bidang,
  });

  @override
  State<PetugasDashboardScreen> createState() => _PetugasDashboardScreenState();
}

class _PetugasDashboardScreenState extends State<PetugasDashboardScreen> {
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _searchController = TextEditingController();
  String _petugasFilter = 'Semua';

  Future<void> _updateStatus(String docId, String status) async {
    try {
      await FirebaseFirestore.instance
          .collection('aspirasi')
          .doc(docId)
          .update({
        'status': status,
        'petugasId': widget.idPetugas,
        'petugasNama': widget.nama,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Status berhasil diubah menjadi $status.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal mengubah status: $e')),
      );
    }
  }

  Future<void> _addHandlingProof(
      DocumentSnapshot<Map<String, dynamic>> doc) async {
    final noteController = TextEditingController();
    XFile? pickedImage;
    XFile? pickedVideo;
    PlatformFile? pickedVideoFile;
    PlatformFile? pickedAudio;
    String proofType = 'none';

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Text('Bukti Penanganan'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                    'Tambahkan catatan dan bukti foto, video, atau audio.'),
                const SizedBox(height: 14),
                TextField(
                  controller: noteController,
                  maxLines: 4,
                  decoration: InputDecoration(
                    labelText: 'Catatan Petugas',
                    hintText: 'Contoh: Lampu sudah diganti dan diuji.',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () async {
                    final file = await _picker.pickImage(
                      source: ImageSource.camera,
                      maxWidth: 1200,
                      maxHeight: 1200,
                      imageQuality: 60,
                    );
                    if (file != null) {
                      setDialogState(() {
                        pickedImage = file;
                        pickedVideo = null;
                        pickedVideoFile = null;
                        pickedAudio = null;
                        proofType = 'image';
                      });
                    }
                  },
                  icon: const Icon(Icons.camera_alt_outlined),
                  label: const Text('Ambil Foto Bukti'),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    final file = await _picker.pickImage(
                      source: ImageSource.gallery,
                      maxWidth: 1200,
                      maxHeight: 1200,
                      imageQuality: 60,
                    );
                    if (file != null) {
                      setDialogState(() {
                        pickedImage = file;
                        pickedVideo = null;
                        pickedVideoFile = null;
                        pickedAudio = null;
                        proofType = 'image';
                      });
                    }
                  },
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Pilih Foto'),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    final file = await _picker.pickVideo(
                      source: ImageSource.camera,
                      maxDuration: const Duration(seconds: 60),
                    );
                    if (file != null) {
                      setDialogState(() {
                        pickedVideo = file;
                        pickedImage = null;
                        pickedVideoFile = null;
                        pickedAudio = null;
                        proofType = 'video';
                      });
                    }
                  },
                  icon: const Icon(Icons.videocam_outlined),
                  label: const Text('Rekam Video Bukti'),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    final result = await FilePicker.platform.pickFiles(
                      type: FileType.video,
                      withData: true,
                    );
                    if (result != null && result.files.single.bytes != null) {
                      final file = result.files.single;
                      // Video dari file picker ditangani sebagai bytes pada saat simpan.
                      setDialogState(() {
                        pickedVideo = null;
                        pickedImage = null;
                        pickedAudio = null;
                        pickedVideoFile = file;
                        proofType = 'video_file';
                      });
                    }
                  },
                  icon: const Icon(Icons.video_library_outlined),
                  label: const Text('Pilih Video'),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    final result = await FilePicker.platform.pickFiles(
                      type: FileType.audio,
                      withData: true,
                    );
                    if (result != null && result.files.single.bytes != null) {
                      setDialogState(() {
                        pickedAudio = result.files.single;
                        pickedImage = null;
                        pickedVideo = null;
                        pickedVideoFile = null;
                        proofType = 'audio';
                      });
                    }
                  },
                  icon: const Icon(Icons.audiotrack_outlined),
                  label: const Text('Pilih Audio'),
                ),
                if (proofType != 'none')
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      proofType == 'image'
                          ? 'Foto bukti dipilih.'
                          : proofType == 'video'
                              ? 'Video bukti dipilih.'
                              : proofType == 'video_file'
                                  ? 'Video file dipilih: ${pickedVideoFile?.name ?? '-'}'
                                  : 'Audio dipilih: ${pickedAudio?.name ?? '-'}',
                      style: const TextStyle(color: Colors.green),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Batal')),
            ElevatedButton(
              onPressed: () async {
                try {
                  String proofUrl = '';
                  String legacyPhoto = '';
                  String contentType = '';
                  String storedName = '';
                  String finalType = proofType;
                  Map<String, dynamic> proofMeta = {};

                  if (pickedImage != null) {
                    final bytes = await pickedImage!.readAsBytes();
                    legacyPhoto =
                        'data:image/jpeg;base64,${base64Encode(bytes)}';
                    // Foto bukti disimpan langsung di Firestore.
                    proofUrl = legacyPhoto;
                    contentType = 'image/jpeg';
                    storedName = pickedImage!.name;
                    finalType = 'image';
                  } else if (pickedVideo != null) {
                    final bytes = await pickedVideo!.readAsBytes();
                    contentType = 'video/mp4';
                    storedName = pickedVideo!.name;
                    finalType = 'video';
                    proofMeta = await _saveMediaChunksToFirestore(
                      parentRef: doc.reference,
                      bytes: bytes,
                      fileName: storedName,
                      contentType: contentType,
                      subcollection: 'handling_media_chunks',
                    );
                  } else if (pickedVideoFile != null &&
                      pickedVideoFile!.bytes != null) {
                    final bytes = pickedVideoFile!.bytes!;
                    contentType = 'video/mp4';
                    storedName = pickedVideoFile!.name;
                    finalType = 'video';
                    proofMeta = await _saveMediaChunksToFirestore(
                      parentRef: doc.reference,
                      bytes: bytes,
                      fileName: storedName,
                      contentType: contentType,
                      subcollection: 'handling_media_chunks',
                    );
                  } else if (pickedAudio != null &&
                      pickedAudio!.bytes != null) {
                    final bytes = pickedAudio!.bytes!;
                    final guessedType = pickedAudio!.extension == 'mp3'
                        ? 'audio/mpeg'
                        : pickedAudio!.extension == 'wav'
                            ? 'audio/wav'
                            : 'audio/mp4';
                    contentType = guessedType;
                    storedName = pickedAudio!.name;
                    finalType = 'audio';
                    proofMeta = await _saveMediaChunksToFirestore(
                      parentRef: doc.reference,
                      bytes: bytes,
                      fileName: storedName,
                      contentType: contentType,
                      subcollection: 'handling_media_chunks',
                    );
                  }

                  await FirebaseFirestore.instance
                      .collection('aspirasi')
                      .doc(doc.id)
                      .update({
                    'catatanPetugas': noteController.text.trim(),
                    // Field lama tetap dipertahankan agar tidak merusak web Admin.
                    'buktiPenanganan': legacyPhoto,
                    // Field baru untuk bukti multimedia petugas.
                    'buktiPenangananUrl': proofUrl,
                    'buktiPenangananType': finalType,
                    'buktiPenangananName': storedName,
                    'buktiPenangananContentType': contentType,
                    'buktiPenangananStorage': proofMeta['mediaStorage'] ??
                        (finalType == 'image' ? 'firestore' : ''),
                    'buktiPenangananChunkCount':
                        proofMeta['mediaChunkCount'] ?? 0,
                    'buktiPenangananChunkCollection':
                        proofMeta['mediaChunkCollection'] ?? '',
                    'buktiPenangananSizeBytes':
                        proofMeta['mediaSizeBytes'] ?? 0,
                    'petugasId': widget.idPetugas,
                    'petugasNama': widget.nama,
                    'tanggalPenanganan': FieldValue.serverTimestamp(),
                    'updatedAt': FieldValue.serverTimestamp(),
                  });
                  if (!mounted) return;
                  Navigator.pop(dialogContext);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text(
                            'Bukti penanganan berhasil disimpan ke Firebase.')),
                  );
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Gagal menyimpan bukti: $e')),
                  );
                }
              },
              child: const Text('Simpan'),
            ),
          ],
        ),
      ),
    );
    noteController.dispose();
  }

  void _showDetail(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    final lokasi = data['lokasi']?.toString() ?? '-';
    final keterangan = data['keterangan']?.toString() ?? '-';
    final kategori = data['kategori']?.toString() ?? '-';
    final status = data['status']?.toString() ?? 'Menunggu';
    final namaSiswa = data['nama']?.toString() ?? '-';
    final kelas = data['kelas']?.toString() ?? '-';
    final foto = data['fotoUrl']?.toString() ?? '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.78,
        minChildSize: 0.55,
        maxChildSize: 0.95,
        builder: (_, controller) => Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: ListView(
            controller: controller,
            children: [
              Center(
                child: Container(
                  width: 45,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text('Detail Tugas Penanganan',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 14),
              _detailRow(Icons.person, 'Pelapor', '$namaSiswa • $kelas'),
              _detailRow(Icons.category_outlined, 'Kategori', kategori),
              _detailRow(Icons.location_on_outlined, 'Lokasi', lokasi),
              _detailRow(Icons.info_outline, 'Status', status),
              const SizedBox(height: 8),
              const Text('Keterangan',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text(keterangan, style: const TextStyle(height: 1.45)),
              if (foto.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text('Bukti dari Siswa',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                _buildImageFromBase64(foto),
              ],
              if ((data['catatanPetugas']?.toString() ?? '').isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text('Catatan Petugas',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text(data['catatanPetugas'].toString(),
                    style: const TextStyle(height: 1.4)),
              ],
              if ((data['buktiPenanganan']?.toString() ?? '').isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text('Bukti Penanganan',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                _buildImageFromBase64(data['buktiPenanganan'].toString()),
              ],
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _addHandlingProof(doc),
                  icon: const Icon(Icons.camera_alt_outlined),
                  label: const Text('Tambah / Perbarui Bukti Penanganan'),
                ),
              ),
              const SizedBox(height: 22),
              const Text('Update Status',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: ['Diproses', 'Selesai']
                    .map(
                      (value) => OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          _updateStatus(doc.id, value);
                        },
                        icon: Icon(value == 'Selesai'
                            ? Icons.check_circle_outline
                            : Icons.sync),
                        label: Text(value),
                      ),
                    )
                    .toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailRow(IconData icon, String title, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: const Color(0xFF1565C0), size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: RichText(
                text: TextSpan(
                  style: const TextStyle(color: Colors.black87),
                  children: [
                    TextSpan(
                        text: '$title\n',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    TextSpan(text: value),
                  ],
                ),
              ),
            ),
          ],
        ),
      );

  Widget _buildImageFromBase64(String base64String, {double? height = 160}) {
    try {
      final clean = base64String.contains(',')
          ? base64String.split(',').last
          : base64String;
      return ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Image.memory(
          base64Decode(clean),
          height: 190,
          width: double.infinity,
          fit: BoxFit.cover,
        ),
      );
    } catch (_) {
      return const Text('Bukti foto tidak dapat ditampilkan.');
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stream = FirebaseFirestore.instance
        .collection('aspirasi')
        .where('petugasId', isEqualTo: widget.idPetugas)
        .snapshots();

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
      drawer: Drawer(
        child: SafeArea(
          child: Column(children: [
            Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 22),
                decoration: const BoxDecoration(
                    gradient: LinearGradient(
                        colors: [Color(0xFF0D47A1), Color(0xFF1976D2)]),
                    borderRadius:
                        BorderRadius.only(bottomRight: Radius.circular(28))),
                child: Row(children: [
                  const CircleAvatar(
                      radius: 29,
                      backgroundColor: Colors.white,
                      child: Icon(Icons.engineering_rounded,
                          color: Color(0xFF1565C0), size: 32)),
                  const SizedBox(width: 13),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(widget.nama,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Text(widget.bidang,
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 12)),
                        const SizedBox(height: 5),
                        const Text('PETUGAS',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold))
                      ]))
                ])),
            ListTile(
                leading: const Icon(Icons.dashboard_rounded),
                title: const Text('Dashboard'),
                onTap: () => Navigator.pop(context)),
            ListTile(
                leading: const Icon(Icons.assignment_outlined),
                title: const Text('Tugas Saya'),
                onTap: () => Navigator.pop(context)),
            ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('Panduan Petugas'),
                onTap: () {
                  Navigator.pop(context);
                  showDialog(
                      context: context,
                      builder: (_) => AlertDialog(
                              title: const Text('Panduan Petugas'),
                              content: const Text(
                                  'Buka detail tugas, perbarui status, lalu tambahkan catatan dan bukti penanganan. Semua perubahan tersimpan ke Firebase agar dapat dipantau Admin dan siswa.'),
                              actions: [
                                TextButton(
                                    onPressed: () => Navigator.pop(context),
                                    child: const Text('Mengerti'))
                              ]));
                }),
            const Spacer(),
            const Divider(height: 1),
            ListTile(
                leading: const Icon(Icons.logout_rounded, color: Colors.red),
                title:
                    const Text('Keluar', style: TextStyle(color: Colors.red)),
                onTap: () => Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (_) => const WelcomeScreen()),
                    (route) => false)),
            const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text('Nareva Ranov • Student Developer',
                    style: TextStyle(fontSize: 10, color: Colors.grey))),
          ]),
        ),
      ),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1565C0),
        elevation: 0,
        title: const Text('Dashboard Petugas',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
              tooltip: 'Keluar',
              icon: const Icon(Icons.logout, color: Colors.white),
              onPressed: () => Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => const WelcomeScreen()),
                  (route) => false)),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: stream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Gagal memuat tugas. Pastikan web Admin menyimpan field petugasId.\n\n${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = [...(snapshot.data?.docs ?? [])];
          docs.sort((a, b) {
            final ad = a.data()['createdAt'];
            final bd = b.data()['createdAt'];
            final at = ad is Timestamp ? ad : Timestamp(0, 0);
            final bt = bd is Timestamp ? bd : Timestamp(0, 0);
            return bt.compareTo(at);
          });

          final menunggu = docs
              .where((d) => (d.data()['status'] ?? 'Menunggu') == 'Menunggu')
              .length;
          final proses = docs
              .where((d) => (d.data()['status'] ?? '') == 'Diproses')
              .length;
          final selesai =
              docs.where((d) => (d.data()['status'] ?? '') == 'Selesai').length;
          final queryText = _searchController.text.trim().toLowerCase();
          final filteredDocs = docs.where((d) {
            final data = d.data();
            final status = data['status']?.toString() ?? 'Menunggu';
            final haystack =
                '${data['nama'] ?? ''} ${data['kelas'] ?? ''} ${data['lokasi'] ?? ''} ${data['kategori'] ?? ''} ${data['keterangan'] ?? ''}'
                    .toLowerCase();
            final matchesSearch =
                queryText.isEmpty || haystack.contains(queryText);
            final matchesStatus =
                _petugasFilter == 'Semua' || status == _petugasFilter;
            return matchesSearch && matchesStatus;
          }).toList();

          return RefreshIndicator(
            onRefresh: () async =>
                Future.delayed(const Duration(milliseconds: 500)),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                        colors: [Color(0xFF0D47A1), Color(0xFF1565C0)]),
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withAlpha(20),
                          blurRadius: 14,
                          offset: const Offset(0, 7))
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 58,
                        height: 58,
                        padding: const EdgeInsets.all(9),
                        decoration: const BoxDecoration(
                            color: Colors.white, shape: BoxShape.circle),
                        child: Image.asset('assets/logo_bg.png',
                            errorBuilder: (_, __, ___) => const Icon(
                                Icons.engineering,
                                color: Color(0xFF1565C0))),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Halo, ${widget.nama}',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 19,
                                    fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            Text('${widget.bidang} • ID ${widget.idPetugas}',
                                style: const TextStyle(color: Colors.white70)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                        child: _statCard('Menunggu', menunggu, Icons.schedule,
                            Colors.orange)),
                    const SizedBox(width: 8),
                    Expanded(
                        child: _statCard(
                            'Diproses', proses, Icons.sync, Colors.blue)),
                    const SizedBox(width: 8),
                    Expanded(
                        child: _statCard('Selesai', selesai, Icons.check_circle,
                            Colors.green)),
                  ],
                ),
                const SizedBox(height: 22),
                TextField(
                  controller: _searchController,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchController.text.isEmpty
                        ? null
                        : IconButton(
                            onPressed: () {
                              _searchController.clear();
                              setState(() {});
                            },
                            icon: const Icon(Icons.clear)),
                    hintText: 'Cari lokasi, kategori, atau nama siswa...',
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                      children: ['Semua', 'Menunggu', 'Diproses', 'Selesai']
                          .map((v) => Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                  label: Text(v),
                                  selected: _petugasFilter == v,
                                  onSelected: (_) =>
                                      setState(() => _petugasFilter = v))))
                          .toList()),
                ),
                const SizedBox(height: 18),
                const Text('Tugas Penanganan',
                    style:
                        TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                if (filteredDocs.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(28),
                    decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18)),
                    child: const Column(
                      children: [
                        Icon(Icons.inbox_outlined,
                            size: 50, color: Colors.black26),
                        SizedBox(height: 10),
                        Text('Belum ada tugas yang diberikan Admin.'),
                        SizedBox(height: 4),
                        Text('Tugas baru akan muncul otomatis.',
                            style: TextStyle(color: Colors.black54)),
                      ],
                    ),
                  )
                else
                  ...filteredDocs.map((doc) {
                    final d = doc.data();
                    final status = d['status']?.toString() ?? 'Menunggu';
                    final kategori = d['kategori']?.toString() ?? 'Aspirasi';
                    final lokasi = d['lokasi']?.toString() ?? '-';
                    final nama = d['nama']?.toString() ?? 'Siswa';
                    final statusColor = status == 'Selesai'
                        ? Colors.green
                        : status == 'Diproses'
                            ? Colors.blue
                            : Colors.orange;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      elevation: 1,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18)),
                      child: InkWell(
                        onTap: () => _showDetail(doc),
                        borderRadius: BorderRadius.circular(18),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                      child: Text(kategori,
                                          style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold))),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 5),
                                    decoration: BoxDecoration(
                                        color: statusColor.withAlpha(25),
                                        borderRadius:
                                            BorderRadius.circular(20)),
                                    child: Text(status,
                                        style: TextStyle(
                                            color: statusColor,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12)),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text('$nama • $lokasi',
                                  style:
                                      const TextStyle(color: Colors.black54)),
                              const SizedBox(height: 10),
                              const Row(
                                children: [
                                  Icon(Icons.touch_app,
                                      size: 16, color: Color(0xFF1565C0)),
                                  SizedBox(width: 5),
                                  Text(
                                      'Ketuk untuk melihat detail & memperbarui status',
                                      style: TextStyle(
                                          color: Color(0xFF1565C0),
                                          fontSize: 12)),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                const SizedBox(height: 12),
                const Center(
                    child: Text('© Nareva Ranov • Student Developer',
                        style: TextStyle(color: Colors.black38, fontSize: 11))),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _statCard(String title, int value, IconData icon, Color color) =>
      Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(16)),
        child: Column(
          children: [
            Icon(icon, color: color),
            const SizedBox(height: 6),
            Text('$value',
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            Text(title,
                style: const TextStyle(fontSize: 11, color: Colors.black54)),
          ],
        ),
      );
}

// 4. REGISTER SCREEN
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _nisController = TextEditingController();
  final _namaController = TextEditingController();
  final _kelasController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;

  void _register() async {
    String nis = _nisController.text.trim();
    String nama = _namaController.text.trim();
    String kelas = _kelasController.text.trim();
    String password = _passwordController.text.trim();

    if (nis.isEmpty || nama.isEmpty || kelas.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Semua kolom wajib diisi!')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      await FirebaseFirestore.instance.collection('siswa').doc(nis).set({
        'nis': nis,
        'nama': nama,
        'kelas': kelas,
        'password': password,
        'createdAt': Timestamp.now(),
      });

      if (!mounted) return;
      setState(() => _isLoading = false);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Registrasi Berhasil! Silakan Masuk.')),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal Mendaftar: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: VideoBackgroundWidget(
        videoAssetPath: 'assets/video_ikan.mp4',
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                        color: Colors.white.withAlpha(200),
                        shape: BoxShape.circle),
                    child: Image.asset(
                      'assets/logo_bg.png',
                      height: 60,
                      width: 60,
                      errorBuilder: (context, error, stackTrace) => const Icon(
                          Icons.school,
                          size: 50,
                          color: Color(0xFF1565C0)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'SMKN 1 SANDEN',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5),
                  ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(35),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.white.withAlpha(100)),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withAlpha(30),
                            blurRadius: 15,
                            offset: const Offset(0, 8)),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Registrasi Siswa',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 20),
                        TextField(
                          controller: _nisController,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: Colors.black.withAlpha(40),
                            prefixIcon: const Icon(Icons.badge_outlined,
                                color: Colors.white70),
                            hintText: 'NIS (Nomor Induk Siswa)',
                            hintStyle: const TextStyle(
                                color: Colors.white70, fontSize: 14),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide.none),
                            contentPadding:
                                const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: _namaController,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: Colors.black.withAlpha(40),
                            prefixIcon: const Icon(Icons.person_outline,
                                color: Colors.white70),
                            hintText: 'Nama Lengkap Siswa',
                            hintStyle: const TextStyle(
                                color: Colors.white70, fontSize: 14),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide.none),
                            contentPadding:
                                const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: _kelasController,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: Colors.black.withAlpha(40),
                            prefixIcon: const Icon(Icons.book_outlined,
                                color: Colors.white70),
                            hintText: 'Kelas (contoh: XII NKN 1)',
                            hintStyle: const TextStyle(
                                color: Colors.white70, fontSize: 14),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide.none),
                            contentPadding:
                                const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: Colors.black.withAlpha(40),
                            prefixIcon: const Icon(Icons.lock_outline,
                                color: Colors.white70),
                            suffixIcon: IconButton(
                              icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_off
                                      : Icons.visibility,
                                  color: Colors.white70),
                              onPressed: () => setState(
                                  () => _obscurePassword = !_obscurePassword),
                            ),
                            hintText: 'Password',
                            hintStyle: const TextStyle(
                                color: Colors.white70, fontSize: 14),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide.none),
                            contentPadding:
                                const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                        const SizedBox(height: 20),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: const Color(0xFF1565C0),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                          ),
                          onPressed: _isLoading ? null : _register,
                          child: _isLoading
                              ? const CircularProgressIndicator(
                                  color: Color(0xFF1565C0))
                              : const Text('Daftar Sekarang',
                                  style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(height: 14),
                        Center(
                          child: GestureDetector(
                            onTap: () => Navigator.pop(context),
                            child: const Text(
                              'Sudah punya akun? Login di sini',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text('2026 Developed by NarevaRanovP',
                      style: TextStyle(color: Colors.white70, fontSize: 12)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// 5. DASHBOARD SISWA SCREEN
class DashboardScreen extends StatefulWidget {
  final String nis;
  final String nama;
  final String kelas;

  const DashboardScreen({
    super.key,
    required this.nis,
    required this.nama,
    required this.kelas,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  String _selectedKategori = 'Sarana';
  String _filterStatus = 'Semua';
  final _lokasiController = TextEditingController();
  final _keteranganController = TextEditingController();

  Uint8List? _imageBytes;
  final List<Uint8List> _imageBytesList = [];
  Uint8List? _videoBytes;
  Uint8List? _audioBytes;
  String? _videoName;
  String? _audioName;
  bool _isLoading = false;
  final ScrollController _dashboardScrollController = ScrollController();
  final GlobalKey _historyKey = GlobalKey();
  final Map<String, String> _lastKnownStatuses = {};

  final List<String> _kategoriList = [
    'Sarana',
    'Kebersihan',
    'Kurikulum',
    'Lainnya'
  ];
  final ImagePicker _picker = ImagePicker();

  String _formatAspirasiDate(dynamic value) {
    DateTime? date;
    if (value is Timestamp) {
      date = value.toDate();
    } else if (value is DateTime) {
      date = value;
    } else if (value is String) {
      date = DateTime.tryParse(value);
    }
    if (date == null) return 'Tanggal belum tersedia';
    const months = [
      'Januari',
      'Februari',
      'Maret',
      'April',
      'Mei',
      'Juni',
      'Juli',
      'Agustus',
      'September',
      'Oktober',
      'November',
      'Desember'
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}, '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  List<String> _readPhotoList(Map<String, dynamic> data) {
    final raw = data['fotoUrls'];
    if (raw is List) {
      return raw.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
    }
    final single = data['fotoUrl']?.toString() ?? '';
    return single.isNotEmpty ? [single] : [];
  }

  void _showPhotoGallery(
    BuildContext context,
    List<Uint8List> photos, {
    int initialIndex = 0,
  }) {
    if (photos.isEmpty) return;
    final controller = PageController(initialPage: initialIndex);
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(10),
        child: Stack(
          children: [
            SizedBox(
              height: MediaQuery.of(context).size.height * .72,
              child: PageView.builder(
                controller: controller,
                itemCount: photos.length,
                itemBuilder: (_, index) => InteractiveViewer(
                  minScale: .8,
                  maxScale: 4,
                  child: Center(
                    child: Image.memory(photos[index], fit: BoxFit.contain),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close, color: Colors.white, size: 28),
              ),
            ),
            if (photos.length > 1)
              Positioned(
                bottom: 10,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'Geser untuk melihat ${photos.length} foto',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showHistoryPhotoGallery(List<String> photos, {int initialIndex = 0}) {
    if (photos.isEmpty) return;
    final controller = PageController(initialPage: initialIndex);
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(10),
        child: Stack(
          children: [
            SizedBox(
              height: MediaQuery.of(context).size.height * .78,
              child: PageView.builder(
                controller: controller,
                itemCount: photos.length,
                itemBuilder: (_, index) => InteractiveViewer(
                  minScale: .8,
                  maxScale: 4,
                  child: Center(
                      child:
                          _buildImageFromBase64(photos[index], height: null)),
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close, color: Colors.white, size: 28),
              ),
            ),
            if (photos.length > 1)
              Positioned(
                bottom: 10,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'Geser untuk melihat ${photos.length} foto',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _requestNotificationPermissionAndSaveToken();
  }

  Future<void> _requestNotificationPermissionAndSaveToken() async {
    FirebaseMessaging messaging = FirebaseMessaging.instance;
    NotificationSettings settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      String? token = await messaging.getToken();
      if (token != null) {
        await FirebaseFirestore.instance
            .collection('siswa')
            .doc(widget.nis)
            .set({
          'fcmToken': token,
        }, SetOptions(merge: true));
      }
    }
  }

  // Fungsi untuk memutar file audio notif.mp3
  Future<void> _playNotificationSound() async {
    try {
      await _audioPlayer.play(AssetSource('notif.mp3'));
    } catch (e) {
      debugPrint("Gagal memutar suara notifikasi: $e");
    }
  }

  Future<void> _showNotification(String title, String body) async {
    // 1. Putar suara kustom notif.mp3 di dalam aplikasi
    await _playNotificationSound();

    if (kIsWeb) return;

    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'aspirasi_channel',
      'Update Aspirasi',
      channelDescription: 'Notifikasi perubahan status aspirasi',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
    );
    const NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);

    await flutterLocalNotificationsPlugin.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      platformChannelSpecifics,
    );
  }

  Future<void> _pilihGambar(ImageSource source) async {
    try {
      if (source == ImageSource.gallery) {
        final List<XFile> pickedFiles = await _picker.pickMultiImage(
          maxWidth: 600,
          maxHeight: 600,
          imageQuality: 35,
        );

        if (pickedFiles.isEmpty) return;
        if (pickedFiles.length > 5) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Maksimal 5 foto dalam satu aspirasi.'),
          ));
        }

        final selected = pickedFiles.take(5).toList();
        final List<Uint8List> bytesList = [];
        for (final file in selected) {
          bytesList.add(await file.readAsBytes());
        }

        if (!mounted) return;
        setState(() {
          _imageBytesList
            ..clear()
            ..addAll(bytesList);
          _imageBytes = bytesList.isNotEmpty ? bytesList.first : null;
          _videoBytes = null;
          _videoName = null;
          _audioBytes = null;
          _audioName = null;
        });
      } else {
        final XFile? pickedFile = await _picker.pickImage(
          source: source,
          maxWidth: 600,
          maxHeight: 600,
          imageQuality: 35,
        );

        if (pickedFile != null) {
          final bytes = await pickedFile.readAsBytes();
          if (!mounted) return;
          setState(() {
            _imageBytesList
              ..clear()
              ..add(bytes);
            _imageBytes = bytes;
            _videoBytes = null;
            _videoName = null;
            _audioBytes = null;
            _audioName = null;
          });
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal mengambil foto: $e')),
      );
    }
  }

  Future<void> _pilihVideo(ImageSource source) async {
    try {
      final XFile? pickedFile = await _picker.pickVideo(
        source: source,
        maxDuration: const Duration(minutes: 2),
      );
      if (pickedFile != null) {
        final bytes = await pickedFile.readAsBytes();
        if (bytes.length > 12 * 1024 * 1024) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Video maksimal 12 MB agar pengiriman tetap ringan.'),
          ));
          return;
        }
        setState(() {
          _videoBytes = bytes;
          _videoName = pickedFile.name;
          _imageBytesList.clear();
          _imageBytes = null;
          _audioBytes = null;
          _audioName = null;
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Gagal mengambil video: $e')));
    }
  }

  Future<void> _pilihAudio() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.audio,
        withData: true,
      );
      if (result != null && result.files.single.bytes != null) {
        final file = result.files.single;
        final bytes = file.bytes!;
        if (bytes.length > 12 * 1024 * 1024) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Audio maksimal 12 MB agar pengiriman tetap ringan.'),
          ));
          return;
        }
        setState(() {
          _audioBytes = bytes;
          _audioName = file.name;
          _imageBytesList.clear();
          _imageBytes = null;
          _videoBytes = null;
          _videoName = null;
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Gagal memilih audio: $e')));
    }
  }

  void _showEvidencePicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
                width: 42,
                height: 5,
                decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(10))),
            const SizedBox(height: 16),
            const Align(
                alignment: Alignment.centerLeft,
                child: Text('Lampiran Bukti',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
            const SizedBox(height: 6),
            const Align(
                alignment: Alignment.centerLeft,
                child: Text('Kirim bukti berupa foto, video, atau audio.',
                    style: TextStyle(color: Colors.grey))),
            const SizedBox(height: 14),
            ListTile(
              leading:
                  const CircleAvatar(child: Icon(Icons.photo_camera_outlined)),
              title: const Text('Foto'),
              subtitle:
                  const Text('Kamera atau galeri (bisa pilih sampai 5 foto)'),
              onTap: () {
                Navigator.pop(sheetContext);
                _showImageSourceDialog();
              },
            ),
            ListTile(
              leading: const CircleAvatar(child: Icon(Icons.videocam_outlined)),
              title: const Text('Video'),
              subtitle: const Text('Rekam atau pilih video'),
              onTap: () {
                Navigator.pop(sheetContext);
                showModalBottomSheet(
                  context: context,
                  builder: (_) => SafeArea(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                    ListTile(
                        leading: const Icon(Icons.videocam),
                        title: const Text('Rekam Video'),
                        onTap: () {
                          Navigator.pop(context);
                          _pilihVideo(ImageSource.camera);
                        }),
                    ListTile(
                        leading: const Icon(Icons.video_library),
                        title: const Text('Pilih Video dari Galeri'),
                        onTap: () {
                          Navigator.pop(context);
                          _pilihVideo(ImageSource.gallery);
                        }),
                  ])),
                );
              },
            ),
            ListTile(
              leading:
                  const CircleAvatar(child: Icon(Icons.audiotrack_outlined)),
              title: const Text('Audio'),
              subtitle: const Text('Pilih rekaman/audio dari perangkat'),
              onTap: () {
                Navigator.pop(sheetContext);
                _pilihAudio();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showImageSourceDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Pilih Sumber Foto'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Color(0xFF1565C0)),
              title: const Text('Kamera'),
              onTap: () {
                Navigator.pop(context);
                _pilihGambar(ImageSource.camera);
              },
            ),
            ListTile(
              leading:
                  const Icon(Icons.photo_library, color: Color(0xFF1565C0)),
              title: const Text('Galeri'),
              onTap: () {
                Navigator.pop(context);
                _pilihGambar(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showRatingDialog() {
    int ratingBintang = 5;
    final komentarController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.star, color: Colors.amber),
              SizedBox(width: 8),
              Text('Beri Rating & Komentar', style: TextStyle(fontSize: 16)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Bagaimana pengalaman Anda menggunakan aplikasi ini?'),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (index) {
                  int starVal = index + 1;
                  return GestureDetector(
                    onTap: () {
                      setStateDialog(() {
                        ratingBintang = starVal;
                      });
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Icon(
                        starVal <= ratingBintang
                            ? Icons.star
                            : Icons.star_border,
                        color: Colors.amber,
                        size: 32,
                      ),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: komentarController,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'Tuliskan ulasan atau masukan untuk aplikasi...',
                  hintStyle: const TextStyle(fontSize: 13),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Batal', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1565C0)),
              onPressed: () async {
                String komentar = komentarController.text.trim();
                try {
                  await FirebaseFirestore.instance
                      .collection('rating_aplikasi')
                      .add({
                    'nis': widget.nis,
                    'nama': widget.nama,
                    'kelas': widget.kelas,
                    'rating': ratingBintang,
                    'komentar': komentar,
                    'createdAt': FieldValue.serverTimestamp(),
                  });
                  if (!mounted) return;
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text(
                            'Terima kasih atas rating dan komentar Anda!')),
                  );
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Gagal mengirim ulasan: $e')),
                  );
                }
              },
              child: const Text('Kirim', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  void _kirimAspirasi() async {
    String lokasi = _lokasiController.text.trim();
    String keterangan = _keteranganController.text.trim();

    if (lokasi.isEmpty || keterangan.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Lokasi dan Keterangan aspirasi harus diisi!')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      String base64Foto = '';
      final List<String> base64Fotos = _imageBytesList
          .map((bytes) => 'data:image/jpeg;base64,${base64Encode(bytes)}')
          .toList();
      if (base64Fotos.isNotEmpty) {
        base64Foto = base64Fotos.first;
      }
      String mediaUrl = '';
      String mediaType = 'none';
      Map<String, dynamic> mediaMeta = {};

      // Buat ID dokumen terlebih dahulu supaya semua bagian lampiran
      // bisa disimpan sebagai subcollection Firestore pada aspirasi yang sama.
      final aspirasiRef =
          FirebaseFirestore.instance.collection('aspirasi').doc();

      if (base64Fotos.isNotEmpty) {
        mediaUrl = base64Fotos.first;
        mediaType = 'image';
      } else if (_videoBytes != null) {
        mediaType = 'video';
        mediaMeta = await _saveMediaChunksToFirestore(
          parentRef: aspirasiRef,
          bytes: _videoBytes!,
          fileName: _videoName ?? 'bukti.mp4',
          contentType: 'video/mp4',
          subcollection: 'media_chunks',
        );
      } else if (_audioBytes != null) {
        mediaType = 'audio';
        mediaMeta = await _saveMediaChunksToFirestore(
          parentRef: aspirasiRef,
          bytes: _audioBytes!,
          fileName: _audioName ?? 'bukti.m4a',
          contentType: 'audio/m4a',
          subcollection: 'media_chunks',
        );
      }

      await aspirasiRef.set({
        'nis': widget.nis,
        'nama': widget.nama,
        'kelas': widget.kelas,
        'kategori': _selectedKategori,
        'lokasi': lokasi,
        'keterangan': keterangan,
        // Field lama yang sudah dipakai database/web Admin tetap dipertahankan.
        'hasImage': base64Fotos.isNotEmpty,
        'hasImages': base64Fotos.isNotEmpty,
        'fotoUrl': base64Foto,
        'fotoUrls': base64Fotos,
        'mediaUrl': mediaUrl,
        'mediaType': mediaType,
        'mediaStorage': mediaType == 'image'
            ? 'firestore'
            : (mediaMeta['mediaStorage'] ?? ''),
        'mediaName': base64Fotos.isNotEmpty
            ? 'bukti-${base64Fotos.length}-foto.jpg'
            : (_videoName ?? _audioName ?? ''),
        'mediaContentType': mediaType == 'image'
            ? 'image/jpeg'
            : (mediaMeta['mediaContentType'] ?? ''),
        'mediaChunkCount': mediaMeta['mediaChunkCount'] ?? 0,
        'mediaChunkCollection': mediaMeta['mediaChunkCollection'] ?? '',
        'mediaSizeBytes': mediaMeta['mediaSizeBytes'] ??
            _imageBytesList.fold<int>(0, (sum, item) => sum + item.length),
        'hasVideo': _videoBytes != null,
        'hasAudio': _audioBytes != null,
        'status': 'Menunggu',
        'feedbackAdmin': '',
        'fotoUrlAdmin': '',
        // Field assignment petugas. Admin Web tinggal mengisi petugasId.
        'petugasId': '',
        'petugasNama': '',
        'catatanPetugas': '',
        'buktiPenanganan': '',
        'buktiPenangananUrl': '',
        'buktiPenangananType': '',
        'updatedAt': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;

      _lokasiController.clear();
      _keteranganController.clear();
      setState(() {
        _imageBytesList.clear();
        _imageBytes = null;
        _videoBytes = null;
        _audioBytes = null;
        _videoName = null;
        _audioName = null;
        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aspirasi berhasil dikirim!')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal mengirim aspirasi: $e')),
      );
    }
  }

  Widget _buildImageFromBase64(String base64String, {double? height = 160}) {
    try {
      String cleanBase64 = base64String;
      if (base64String.contains(',')) {
        cleanBase64 = base64String.split(',').last;
      }
      Uint8List bytes = base64Decode(cleanBase64);
      return Image.memory(
        bytes,
        height: height,
        width: double.infinity,
        fit: BoxFit.cover,
      );
    } catch (e) {
      return const SizedBox();
    }
  }

  @override
  void dispose() {
    _lokasiController.dispose();
    _keteranganController.dispose();
    _dashboardScrollController.dispose();
    super.dispose();
  }

  Widget _buildStudentDrawer(BuildContext context) {
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                    colors: [Color(0xFF0D47A1), Color(0xFF1976D2)]),
                borderRadius:
                    BorderRadius.only(bottomRight: Radius.circular(28)),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                      radius: 30,
                      backgroundColor: Colors.white,
                      child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: Image.asset('assets/logo_bg.png',
                              errorBuilder: (_, __, ___) => const Icon(
                                  Icons.school,
                                  color: Color(0xFF1565C0))))),
                  const SizedBox(width: 14),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(widget.nama,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16)),
                        const SizedBox(height: 4),
                        Text('NIS ${widget.nis} • ${widget.kelas}',
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 12)),
                        const SizedBox(height: 5),
                        Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                                color: Colors.white24,
                                borderRadius: BorderRadius.circular(20)),
                            child: const Text('SISWA',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold))),
                      ])),
                ],
              ),
            ),
            const SizedBox(height: 10),
            ListTile(
                leading: const Icon(Icons.dashboard_rounded),
                title: const Text('Dashboard'),
                onTap: () => Navigator.pop(context)),
            ListTile(
                leading: const Icon(Icons.add_circle_outline),
                title: const Text('Aspirasi Baru'),
                onTap: () {
                  Navigator.pop(context);
                  _dashboardScrollController.animateTo(0,
                      duration: const Duration(milliseconds: 450),
                      curve: Curves.easeOut);
                }),
            ListTile(
                leading: const Icon(Icons.history_rounded),
                title: const Text('Riwayat Aspirasi'),
                onTap: () {
                  Navigator.pop(context);
                  final ctx = _historyKey.currentContext;
                  if (ctx != null)
                    Scrollable.ensureVisible(ctx,
                        duration: const Duration(milliseconds: 500),
                        curve: Curves.easeOut);
                }),
            ListTile(
                leading: const Icon(Icons.school_outlined),
                title: const Text('Profil Sekolah'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const ProfilSekolahScreen()));
                }),
            ListTile(
                leading: const Icon(Icons.star_rounded, color: Colors.amber),
                title: const Text('Beri Rating & Komentar'),
                subtitle: const Text('Bagikan pengalaman menggunakan aplikasi'),
                onTap: () {
                  Navigator.pop(context);
                  _showRatingDialog();
                }),
            ListTile(
                leading: const Icon(Icons.info_outline_rounded),
                title: const Text('Tentang Aplikasi'),
                onTap: () {
                  Navigator.pop(context);
                  showDialog(
                      context: context,
                      builder: (_) => AlertDialog(
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16)),
                            title: const Row(
                              children: [
                                Icon(Icons.info_outline_rounded,
                                    color: Color(0xFF1565C0)),
                                SizedBox(width: 8),
                                Text('Tentang Aplikasi'),
                              ],
                            ),
                            content: const Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Aspirasi SMKN 1 Sanden',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16)),
                                SizedBox(height: 10),
                                Text(
                                    'Aplikasi layanan aspirasi siswa untuk menyampaikan laporan, memantau status, dan melihat tanggapan sekolah.'),
                                SizedBox(height: 12),
                                Text('Versi 1.0',
                                    style:
                                        TextStyle(fontWeight: FontWeight.w600)),
                                SizedBox(height: 4),
                                Text(
                                    'Dikembangkan untuk layanan aspirasi SMKN 1 Sanden.'),
                              ],
                            ),
                            actions: [
                              TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('Tutup')),
                            ],
                          ));
                }),
            ListTile(
                leading: const Icon(Icons.help_outline_rounded),
                title: const Text('Bantuan'),
                onTap: () {
                  Navigator.pop(context);
                  showDialog(
                      context: context,
                      builder: (_) => AlertDialog(
                              title: const Text('Bantuan'),
                              content: const Text(
                                  'Pilih kategori, isi lokasi dan keterangan, lalu lampirkan bukti berupa foto, video, atau audio. Pastikan internet aktif karena aplikasi berjalan secara online.'),
                              actions: [
                                TextButton(
                                    onPressed: () => Navigator.pop(context),
                                    child: const Text('Mengerti'))
                              ]));
                }),
            const Spacer(),
            const Divider(height: 1),
            ListTile(
                leading: const Icon(Icons.logout_rounded, color: Colors.red),
                title: const Text('Keluar',
                    style: TextStyle(
                        color: Colors.red, fontWeight: FontWeight.w600)),
                onTap: () => Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (_) => const WelcomeScreen()),
                    (route) => false)),
            const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text('Nareva Ranov • Student Developer',
                    style: TextStyle(fontSize: 10, color: Colors.grey))),
          ],
        ),
      ),
    );
  }

  void _showHistoryVideo(
    DocumentReference<Map<String, dynamic>> aspirasiRef,
    Map<String, dynamic> data,
  ) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) => Dialog(
        backgroundColor: Colors.white,
        insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 30),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Icon(Icons.videocam_outlined, color: Color(0xFF1565C0)),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Bukti Video Aspirasi',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              _HistoryVideoViewer(aspirasiRef: aspirasiRef, data: data),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: _buildStudentDrawer(context),
      backgroundColor: const Color(0xFF1565C0),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1565C0),
        elevation: 0,
        title: const Text(
          'Aspirasi SMKN 1 Sanden',
          style: TextStyle(
              color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            tooltip: 'Keluar',
            onPressed: () => Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (context) => const WelcomeScreen()),
              (route) => false,
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        controller: _dashboardScrollController,
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF0D47A1),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withAlpha(25),
                      blurRadius: 8,
                      offset: const Offset(0, 4)),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(
                        color: Colors.white, shape: BoxShape.circle),
                    child: Image.asset(
                      'assets/logo_bg.png',
                      height: 40,
                      width: 40,
                      errorBuilder: (context, error, stackTrace) => const Icon(
                          Icons.school,
                          size: 35,
                          color: Color(0xFF1565C0)),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.nama,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'NIS: ${widget.nis}  |  Kelas: ${widget.kelas}',
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFFF4F6F9),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.edit_note, color: Color(0xFF1565C0)),
                      SizedBox(width: 8),
                      Text(
                        'Sampaikan Aspirasi Baru',
                        style: TextStyle(
                            color: Color(0xFF1565C0),
                            fontSize: 16,
                            fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const Divider(height: 24, thickness: 1),
                  const Text('Kategori Aspirasi',
                      style: TextStyle(color: Colors.grey, fontSize: 12)),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _selectedKategori,
                        isExpanded: true,
                        items: _kategoriList.map((String value) {
                          return DropdownMenuItem<String>(
                            value: value,
                            child: Row(
                              children: [
                                const Icon(Icons.category_outlined,
                                    size: 18, color: Color(0xFF1565C0)),
                                const SizedBox(width: 10),
                                Text(value,
                                    style: const TextStyle(fontSize: 14)),
                              ],
                            ),
                          );
                        }).toList(),
                        onChanged: (newValue) {
                          setState(() {
                            _selectedKategori = newValue!;
                          });
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _lokasiController,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.location_on_outlined,
                          color: Color(0xFF1565C0)),
                      hintText: 'Lokasi / Sarana Sekolah',
                      hintStyle:
                          const TextStyle(color: Colors.grey, fontSize: 14),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.grey.shade300)),
                      enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.grey.shade300)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _keteranganController,
                    maxLines: 3,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.description_outlined,
                          color: Color(0xFF1565C0)),
                      hintText: 'Keterangan Aspirasi / Detail',
                      hintStyle:
                          const TextStyle(color: Colors.grey, fontSize: 14),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.grey.shade300)),
                      enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.grey.shade300)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF1565C0),
                      side: const BorderSide(color: Color(0xFF1565C0)),
                      padding: const EdgeInsets.symmetric(
                          vertical: 12, horizontal: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _showEvidencePicker,
                    icon: const Icon(Icons.attach_file_rounded),
                    label: Text(
                      _imageBytesList.isEmpty &&
                              _videoBytes == null &&
                              _audioBytes == null
                          ? 'Lampirkan Bukti Foto / Video / Audio'
                          : 'Ganti / Tambah Lampiran',
                    ),
                  ),
                  if (_imageBytesList.isNotEmpty ||
                      _videoBytes != null ||
                      _audioBytes != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEAF3FF),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFB7D5FF)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                _videoBytes != null
                                    ? Icons.videocam
                                    : (_audioBytes != null
                                        ? Icons.audiotrack
                                        : Icons.photo_library_outlined),
                                color: const Color(0xFF1565C0),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _videoBytes != null
                                      ? (_videoName ?? 'Video dipilih')
                                      : (_audioBytes != null
                                          ? (_audioName ?? 'Audio dipilih')
                                          : '${_imageBytesList.length} foto dipilih'),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Hapus lampiran',
                                onPressed: () => setState(() {
                                  _imageBytesList.clear();
                                  _imageBytes = null;
                                  _videoBytes = null;
                                  _audioBytes = null;
                                  _videoName = null;
                                  _audioName = null;
                                }),
                                icon:
                                    const Icon(Icons.close, color: Colors.red),
                              ),
                            ],
                          ),
                          if (_imageBytesList.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            SizedBox(
                              height: 78,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemCount: _imageBytesList.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(width: 8),
                                itemBuilder: (context, index) =>
                                    GestureDetector(
                                  onTap: () => _showPhotoGallery(
                                    context,
                                    _imageBytesList,
                                    initialIndex: index,
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: Image.memory(
                                      _imageBytesList[index],
                                      width: 78,
                                      height: 78,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Ketuk foto untuk melihat lebih besar.',
                              style:
                                  TextStyle(fontSize: 10, color: Colors.grey),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1565C0),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: _isLoading ? null : _kirimAspirasi,
                      child: _isLoading
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.send_rounded, size: 18),
                                SizedBox(width: 8),
                                Text('Kirim Aspirasi',
                                    style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold)),
                              ],
                            ),
                    ),
                  ),
                  const Divider(height: 35, thickness: 1.5),

                  // STREAM BUILDER GRAFIK 📊 & FILTER
                  StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('aspirasi')
                        .where('nis', isEqualTo: widget.nis)
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(
                            child: CircularProgressIndicator(
                                color: Color(0xFF1565C0)));
                      }

                      var docs = snapshot.hasData ? snapshot.data!.docs : [];

                      int totalLaporan = docs.length;
                      int jumlahMenunggu = 0;
                      int jumlahDiproses = 0;
                      int jumlahSelesai = 0;

                      for (var doc in docs) {
                        var data = doc.data() as Map<String, dynamic>;
                        String docId = doc.id;
                        String currentStatus = data['status'] ?? 'Menunggu';
                        String lokasi = data['lokasi'] ?? 'Aspirasi';

                        String stLower = currentStatus.toLowerCase();
                        if (stLower == 'selesai') {
                          jumlahSelesai++;
                        } else if (stLower == 'diproses' ||
                            stLower == 'proses') {
                          jumlahDiproses++;
                        } else {
                          jumlahMenunggu++;
                        }

                        if (_lastKnownStatuses.containsKey(docId)) {
                          if (_lastKnownStatuses[docId] != currentStatus) {
                            _showNotification(
                              'Update Status Aspirasi! 🔔',
                              'Laporan "$lokasi" Anda kini berstatus: $currentStatus',
                            );
                          }
                        }
                        _lastKnownStatuses[docId] = currentStatus;
                      }

                      var filteredDocs = docs.where((doc) {
                        var data = doc.data() as Map<String, dynamic>;
                        String st =
                            (data['status'] ?? 'Menunggu').toLowerCase();
                        if (_filterStatus == 'Semua') return true;
                        if (_filterStatus == 'Menunggu')
                          return st == 'menunggu';
                        if (_filterStatus == 'Diproses')
                          return st == 'diproses' || st == 'proses';
                        if (_filterStatus == 'Selesai') return st == 'selesai';
                        return true;
                      }).toList();

                      // Riwayat selalu diurutkan berdasarkan tanggal & waktu
                      // terbaru ke terlama, sehingga 26 Agustus tampil di atas
                      // 25 Agustus, lalu 24 Agustus, dan seterusnya.
                      filteredDocs.sort((a, b) {
                        final ad =
                            (a.data() as Map<String, dynamic>)['createdAt'];
                        final bd =
                            (b.data() as Map<String, dynamic>)['createdAt'];
                        final at = ad is Timestamp ? ad : Timestamp(0, 0);
                        final bt = bd is Timestamp ? bd : Timestamp(0, 0);
                        final result = bt.compareTo(at);
                        return result != 0 ? result : b.id.compareTo(a.id);
                      });

                      int maxVal = [
                        totalLaporan,
                        jumlahMenunggu,
                        jumlahDiproses,
                        jumlahSelesai,
                        1
                      ].reduce((a, b) => a > b ? a : b);

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: Colors.blue.shade100),
                              boxShadow: [
                                BoxShadow(
                                    color: Colors.blue.withAlpha(15),
                                    blurRadius: 6,
                                    offset: const Offset(0, 3)),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Expanded(
                                      child: Row(
                                        children: [
                                          Icon(Icons.bar_chart,
                                              color: Color(0xFF1565C0),
                                              size: 18),
                                          SizedBox(width: 6),
                                          Flexible(
                                            child: Text(
                                              'Grafik Ringkasan Laporan 📊',
                                              style: TextStyle(
                                                  color: Color(0xFF1565C0),
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 13),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (_filterStatus != 'Semua')
                                      InkWell(
                                        onTap: () => setState(
                                            () => _filterStatus = 'Semua'),
                                        child: const Padding(
                                          padding: EdgeInsets.all(4.0),
                                          child: Text('Reset',
                                              style: TextStyle(
                                                  color: Colors.red,
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.bold)),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                    'Klik batang grafik untuk memfilter riwayat laporan:',
                                    style: TextStyle(
                                        fontSize: 10, color: Colors.grey)),
                                const Divider(height: 14),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceAround,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    _buildBarChartItem('Total', totalLaporan,
                                        maxVal, Colors.blue.shade800, 'Semua'),
                                    _buildBarChartItem(
                                        'Menunggu',
                                        jumlahMenunggu,
                                        maxVal,
                                        Colors.orange.shade800,
                                        'Menunggu'),
                                    _buildBarChartItem(
                                        'Diproses',
                                        jumlahDiproses,
                                        maxVal,
                                        Colors.purple.shade800,
                                        'Diproses'),
                                    _buildBarChartItem(
                                        'Selesai',
                                        jumlahSelesai,
                                        maxVal,
                                        Colors.green.shade800,
                                        'Selesai'),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                          Row(
                            key: _historyKey,
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.history,
                                      color: Color(0xFF1565C0)),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Riwayat Aspirasi (${_filterStatus == 'Semua' ? 'Semua' : _filterStatus})',
                                    style: const TextStyle(
                                        color: Color(0xFF1565C0),
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          if (filteredDocs.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 15),
                              child: Center(
                                child: Text(
                                  'Tidak ada riwayat untuk status ini.',
                                  style: TextStyle(
                                      color: Colors.grey, fontSize: 13),
                                ),
                              ),
                            )
                          else
                            ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: filteredDocs.length,
                              itemBuilder: (context, index) {
                                var data = filteredDocs[index].data()
                                    as Map<String, dynamic>;
                                String kategori = data['kategori'] ?? '-';
                                String lokasi = data['lokasi'] ?? '-';
                                String keterangan = data['keterangan'] ?? '-';
                                String status = data['status'] ?? 'Menunggu';
                                bool hasImage = (data['hasImage'] ??
                                        data['hasImages'] ??
                                        false) ==
                                    true;
                                String mediaType =
                                    data['mediaType']?.toString() ??
                                        (hasImage ? 'image' : 'none');

                                String feedbackAdmin = data['feedbackAdmin'] ??
                                    data['feedback'] ??
                                    '';
                                String fotoUrlAdmin = data['fotoUrlAdmin'] ??
                                    data['fotoAdminUrl'] ??
                                    '';
                                final List<String> fotoList =
                                    _readPhotoList(data);
                                final String tanggalAspirasi =
                                    _formatAspirasiDate(data['createdAt']);

                                return Container(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(12),
                                    border:
                                        Border.all(color: Colors.grey.shade200),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            kategori,
                                            style: const TextStyle(
                                                color: Color(0xFF1565C0),
                                                fontWeight: FontWeight.bold,
                                                fontSize: 14),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: status.toLowerCase() ==
                                                      'selesai'
                                                  ? Colors.green.shade100
                                                  : status.toLowerCase() ==
                                                              'diproses' ||
                                                          status.toLowerCase() ==
                                                              'proses'
                                                      ? Colors.purple.shade100
                                                      : Colors.orange.shade100,
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              status,
                                              style: TextStyle(
                                                color: status.toLowerCase() ==
                                                        'selesai'
                                                    ? Colors.green.shade800
                                                    : status.toLowerCase() ==
                                                                'diproses' ||
                                                            status.toLowerCase() ==
                                                                'proses'
                                                        ? Colors.purple.shade800
                                                        : Colors
                                                            .orange.shade800,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          const Icon(
                                              Icons.calendar_today_outlined,
                                              size: 13,
                                              color: Colors.grey),
                                          const SizedBox(width: 5),
                                          Text(
                                            tanggalAspirasi,
                                            style: const TextStyle(
                                                fontSize: 11,
                                                color: Colors.grey),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        lokasi,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                            color: Colors.black87),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        keterangan,
                                        style: const TextStyle(
                                            color: Colors.black54,
                                            fontSize: 12),
                                      ),
                                      if (fotoList.isNotEmpty) ...[
                                        const SizedBox(height: 10),
                                        GestureDetector(
                                          onTap: () => _showHistoryPhotoGallery(
                                              fotoList),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              ClipRRect(
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                                child: _buildImageFromBase64(
                                                    fotoList.first),
                                              ),
                                              const SizedBox(height: 5),
                                              Row(
                                                children: [
                                                  const Icon(
                                                      Icons
                                                          .photo_library_outlined,
                                                      size: 15,
                                                      color: Color(0xFF1565C0)),
                                                  const SizedBox(width: 5),
                                                  Text(
                                                    '${fotoList.length} foto • Ketuk untuk melihat',
                                                    style: const TextStyle(
                                                        fontSize: 11,
                                                        color:
                                                            Color(0xFF1565C0),
                                                        fontWeight:
                                                            FontWeight.w600),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                      ] else if (mediaType == 'video') ...[
                                        const SizedBox(height: 10),
                                        InkWell(
                                          borderRadius:
                                              BorderRadius.circular(10),
                                          onTap: () => _showHistoryVideo(
                                            filteredDocs[index].reference,
                                            data,
                                          ),
                                          child: Container(
                                            width: double.infinity,
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 12, vertical: 11),
                                            decoration: BoxDecoration(
                                              color: Colors.blue.shade50,
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                              border: Border.all(
                                                  color: Colors.blue.shade200),
                                            ),
                                            child: const Row(
                                              children: [
                                                Icon(Icons.play_circle_fill,
                                                    color: Color(0xFF1565C0),
                                                    size: 25),
                                                SizedBox(width: 9),
                                                Expanded(
                                                  child: Text(
                                                    'Bukti video • Ketuk untuk menonton',
                                                    style: TextStyle(
                                                        fontSize: 12,
                                                        color:
                                                            Color(0xFF1565C0),
                                                        fontWeight:
                                                            FontWeight.w600),
                                                  ),
                                                ),
                                                Icon(Icons.chevron_right,
                                                    color: Color(0xFF1565C0)),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ] else if (mediaType != 'none') ...[
                                        const SizedBox(height: 8),
                                        Row(
                                          children: [
                                            const Icon(
                                                Icons.audiotrack_outlined,
                                                size: 16,
                                                color: Color(0xFF1565C0)),
                                            const SizedBox(width: 6),
                                            const Text(
                                              'Dilampirkan dengan audio',
                                              style: TextStyle(
                                                  fontSize: 11,
                                                  color: Colors.grey),
                                            ),
                                          ],
                                        ),
                                      ],
                                      if ((data['petugasNama']?.toString() ??
                                                  '')
                                              .isNotEmpty ||
                                          (data['catatanPetugas']?.toString() ??
                                                  '')
                                              .isNotEmpty ||
                                          (data['buktiPenangananUrl']
                                                      ?.toString() ??
                                                  '')
                                              .isNotEmpty) ...[
                                        const SizedBox(height: 10),
                                        Container(
                                          width: double.infinity,
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color: Colors.green.shade50,
                                            borderRadius:
                                                BorderRadius.circular(10),
                                            border: Border.all(
                                                color: Colors.green.shade200),
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              const Row(children: [
                                                Icon(Icons.engineering_outlined,
                                                    size: 16,
                                                    color: Colors.green),
                                                SizedBox(width: 6),
                                                Text('Penanganan Petugas',
                                                    style: TextStyle(
                                                        fontSize: 12,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        color: Colors.green)),
                                              ]),
                                              if ((data['petugasNama']
                                                          ?.toString() ??
                                                      '')
                                                  .isNotEmpty) ...[
                                                const SizedBox(height: 6),
                                                Text(
                                                    'Petugas: ${data['petugasNama']}',
                                                    style: const TextStyle(
                                                        fontSize: 12,
                                                        fontWeight:
                                                            FontWeight.w600)),
                                              ],
                                              if ((data['catatanPetugas']
                                                          ?.toString() ??
                                                      '')
                                                  .isNotEmpty) ...[
                                                const SizedBox(height: 4),
                                                Text(
                                                    '${data['catatanPetugas']}',
                                                    style: const TextStyle(
                                                        fontSize: 12,
                                                        color: Colors.black87)),
                                              ],
                                              if ((data['buktiPenangananUrl']
                                                          ?.toString() ??
                                                      '')
                                                  .isNotEmpty) ...[
                                                const SizedBox(height: 6),
                                                Text(
                                                    'Bukti penanganan tersimpan: ${data['buktiPenangananType']?.toString() ?? 'media'}',
                                                    style: const TextStyle(
                                                        fontSize: 11,
                                                        color: Colors.green)),
                                              ],
                                            ],
                                          ),
                                        ),
                                      ],
                                      if (feedbackAdmin.isNotEmpty ||
                                          fotoUrlAdmin.isNotEmpty) ...[
                                        const SizedBox(height: 10),
                                        Container(
                                          width: double.infinity,
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color: Colors.blue.shade50,
                                            borderRadius:
                                                BorderRadius.circular(10),
                                            border: Border.all(
                                                color: Colors.blue.shade200),
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              const Row(
                                                children: [
                                                  Icon(
                                                      Icons
                                                          .admin_panel_settings,
                                                      size: 16,
                                                      color: Color(0xFF1565C0)),
                                                  SizedBox(width: 6),
                                                  Text(
                                                    'Tanggapan & Bukti Admin:',
                                                    style: TextStyle(
                                                        fontSize: 12,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        color:
                                                            Color(0xFF1565C0)),
                                                  ),
                                                ],
                                              ),
                                              if (feedbackAdmin.isNotEmpty) ...[
                                                const SizedBox(height: 6),
                                                Text(
                                                  feedbackAdmin,
                                                  style: const TextStyle(
                                                      fontSize: 13,
                                                      fontWeight:
                                                          FontWeight.w500,
                                                      color: Colors.black87),
                                                ),
                                              ],
                                              if (fotoUrlAdmin.isNotEmpty) ...[
                                                const SizedBox(height: 10),
                                                ClipRRect(
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                  child: _buildImageFromBase64(
                                                      fotoUrlAdmin),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                );
                              },
                            ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const Text('2026 Developed by NarevaRanovP',
                style: TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Widget _buildBarChartItem(
      String label, int value, int maxVal, Color color, String targetStatus) {
    bool isSelected = _filterStatus == targetStatus;
    double barHeight = maxVal > 0 ? (value / maxVal) * 70.0 : 4.0;
    if (barHeight < 8.0) barHeight = 8.0;

    return GestureDetector(
      onTap: () {
        setState(() {
          _filterStatus = targetStatus;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? color.withAlpha(25) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: isSelected ? color : Colors.transparent, width: 1.5),
        ),
        child: Column(
          children: [
            Text(
              value.toString(),
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.bold, color: color),
            ),
            const SizedBox(height: 4),
            Container(
              width: 24,
              height: barHeight,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? color : Colors.black54,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
