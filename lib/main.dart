import 'package:flutter/material.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';
import 'package:provider/provider.dart';
import 'dart:io';
import 'dart:async';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:audioplayers/audioplayers.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Window manager ayarları
  await windowManager.ensureInitialized();
  WindowOptions windowOptions = WindowOptions(
    size: Size(400, 500),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden,
    minimumSize: Size(400, 500),
  );

  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(
    ChangeNotifierProvider(
      create: (context) => PomodoroModel(),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with TrayListener {
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  @override
  void initState() {
    super.initState();
    _initTray();
    _initNotifications();
    trayManager.addListener(this);
  }

  @override
  void dispose() {
    trayManager.removeListener(this);
    super.dispose();
  }

  Future<void> _initTray() async {
    final String iconPath = Platform.isWindows ? 'tray_icon.ico' : 'AppIcon.png';
    await trayManager.setIcon(iconPath);

    Menu menu = Menu(
      items: [
        MenuItem(key: 'show_app', label: 'Göster'),
        MenuItem.separator(),
        MenuItem(key: 'start_pomodoro', label: 'Pomodoro Başlat (25 dk)'),
        MenuItem(key: 'start_short_break', label: 'Kısa Mola Başlat (5 dk)'),
        MenuItem(key: 'start_long_break', label: 'Uzun Mola Başlat (15 dk)'),
        MenuItem.separator(),
        MenuItem(key: 'exit', label: 'Çıkış'),
      ],
    );

    await trayManager.setContextMenu(menu);
  }

  Future<void> _initNotifications() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    final DarwinInitializationSettings initializationSettingsDarwin =
        DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    final InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsDarwin,
      macOS: initializationSettingsDarwin,
    );

    await flutterLocalNotificationsPlugin.initialize(initializationSettings);
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    final pomodoroModel = Provider.of<PomodoroModel>(context, listen: false);

    switch (menuItem.key) {
      case 'show_app':
        windowManager.show();
        break;
      case 'start_pomodoro':
        pomodoroModel.startPomodoro();
        break;
      case 'start_short_break':
        pomodoroModel.startShortBreak();
        break;
      case 'start_long_break':
        pomodoroModel.startLongBreak();
        break;
      case 'exit':
        exit(0);
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Pomodoro Timer',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.red),
        useMaterial3: true,
      ),
      home: const PomodoroScreen(),
    );
  }
}

class PomodoroModel extends ChangeNotifier {
  static const int pomodoroTime = 25 * 60;
  static const int shortBreakTime = 5 * 60;
  static const int longBreakTime = 15 * 60;

  Timer? _timer;
  int _currentTime = pomodoroTime;
  bool _isRunning = false;
  String _currentMode = 'pomodoro';
  int _completedPomodoros = 0;
  final AudioPlayer _audioPlayer = AudioPlayer();

  int get currentTime => _currentTime;
  bool get isRunning => _isRunning;
  String get currentMode => _currentMode;
  int get completedPomodoros => _completedPomodoros;

  String get timeDisplay {
    int minutes = _currentTime ~/ 60;
    int seconds = _currentTime % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  void startPomodoro() {
    _currentMode = 'pomodoro';
    _currentTime = pomodoroTime;
    _startTimer();
    notifyListeners();
  }

  void startShortBreak() {
    _currentMode = 'shortBreak';
    _currentTime = shortBreakTime;
    _startTimer();
    notifyListeners();
  }

  void startLongBreak() {
    _currentMode = 'longBreak';
    _currentTime = longBreakTime;
    _startTimer();
    notifyListeners();
  }

  void toggleTimer() {
    if (_isRunning) {
      _pauseTimer();
    } else {
      _startTimer();
    }
    notifyListeners();
  }

  void _startTimer() {
    if (_isRunning) return;

    _isRunning = true;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_currentTime > 0) {
        _currentTime--;
        notifyListeners();
        _updateTrayTitle();
      } else {
        _timer?.cancel();
        _isRunning = false;

        // Ses çal (loop modunda)
        _playSound();
        _showNotification();

        // Mod değiştirme
        if (_currentMode == 'pomodoro') {
          _completedPomodoros++;
          if (_completedPomodoros % 4 == 0) {
            startLongBreak();
          } else {
            startShortBreak();
          }
        } else {
          startPomodoro();
        }
      }
    });
  }

  void _pauseTimer() {
    if (!_isRunning) return;
    _timer?.cancel();
    _timer = null;
    _isRunning = false;
    notifyListeners();
    _updateTrayTitle();
  }

  void resetTimer() {
    _pauseTimer();
    switch (_currentMode) {
      case 'pomodoro':
        _currentTime = pomodoroTime;
        break;
      case 'shortBreak':
        _currentTime = shortBreakTime;
        break;
      case 'longBreak':
        _currentTime = longBreakTime;
        break;
    }
    notifyListeners();
  }

  Future<void> _playSound() async {
    await _audioPlayer.setReleaseMode(ReleaseMode.loop);
    await _audioPlayer.play(AssetSource('sounds/bell.mp3'));
  }

  Future<void> stopSound() async {
    await _audioPlayer.stop();
  }

  Future<void> _showNotification() async {
    String title = '';
    String body = '';

    if (_currentMode == 'pomodoro') {
      title = 'Pomodoro Tamamlandı!';
      body = 'Şimdi mola zamanı.';
    } else {
      title = 'Mola Süresi Bitti!';
      body = 'Çalışmaya devam etme zamanı.';
    }

    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'pomodoro_channel',
      'Pomodoro Bildirimleri',
      importance: Importance.max,
      priority: Priority.high,
    );

    const DarwinNotificationDetails darwinPlatformChannelSpecifics =
        DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
      iOS: darwinPlatformChannelSpecifics,
      macOS: darwinPlatformChannelSpecifics,
    );

    await FlutterLocalNotificationsPlugin().show(
      0,
      title,
      body,
      platformChannelSpecifics,
    );
  }

  void _updateTrayTitle() async {
    try {
      await trayManager.setTitle(timeDisplay);
    } catch (e) {
      print('Tray title güncellenirken hata: $e');
    }
  }

  void setCustomTime(int minutes) {
    if (_isRunning) {
      _pauseTimer();
    }
    _currentTime = minutes * 60;
    _updateTrayTitle();
    notifyListeners();
  }
}

class PomodoroScreen extends StatelessWidget {
  const PomodoroScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<PomodoroModel>(
      builder: (context, pomodoroModel, child) {
        Color backgroundColor;
        switch (pomodoroModel.currentMode) {
          case 'pomodoro':
            backgroundColor = Colors.red.shade800;
            break;
          case 'shortBreak':
            backgroundColor = Colors.green.shade700;
            break;
          case 'longBreak':
            backgroundColor = Colors.blue.shade700;
            break;
          default:
            backgroundColor = Colors.red.shade800;
        }

        return Scaffold(
          backgroundColor: backgroundColor,
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final double titleFontSize = constraints.maxWidth < 350 ? 20 : 24;
                final double timerFontSize = constraints.maxWidth < 350 ? 60 : 80;
                final double buttonFontSize = constraints.maxWidth < 350 ? 14 : 18;

                return SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(height: 20),
                        Text(
                          pomodoroModel.currentMode == 'pomodoro'
                              ? 'Pomodoro'
                              : pomodoroModel.currentMode == 'shortBreak'
                                  ? 'Kısa Mola'
                                  : 'Uzun Mola',
                          style: TextStyle(
                            fontSize: titleFontSize,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 40),
                        Text(
                          pomodoroModel.timeDisplay,
                          style: TextStyle(
                            fontSize: timerFontSize,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 40),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Expanded(
                              child: ElevatedButton(
                                onPressed: () => pomodoroModel.toggleTimer(),
                                style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 15),
                                ),
                                child: Text(
                                  pomodoroModel.isRunning ? 'Duraklat' : 'Başlat',
                                  style: TextStyle(fontSize: buttonFontSize),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: () => pomodoroModel.resetTimer(),
                                style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 15),
                                ),
                                child: Text(
                                  'Sıfırla',
                                  style: TextStyle(fontSize: buttonFontSize),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: () => pomodoroModel.stopSound(),
                                style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 15),
                                  backgroundColor: Colors.orange.shade700,
                                ),
                                child: Text(
                                  'Sesi Durdur',
                                  style: TextStyle(fontSize: buttonFontSize),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 30),
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            ElevatedButton(
                              onPressed: () => pomodoroModel.startPomodoro(),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: pomodoroModel.currentMode == 'pomodoro'
                                    ? Colors.white.withOpacity(0.3)
                                    : null,
                              ),
                              child: const Text('Pomodoro'),
                            ),
                            ElevatedButton(
                              onPressed: () => pomodoroModel.startShortBreak(),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: pomodoroModel.currentMode == 'shortBreak'
                                    ? Colors.white.withOpacity(0.3)
                                    : null,
                              ),
                              child: const Text('Kısa Mola'),
                            ),
                            ElevatedButton(
                              onPressed: () => pomodoroModel.startLongBreak(),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: pomodoroModel.currentMode == 'longBreak'
                                    ? Colors.white.withOpacity(0.3)
                                    : null,
                              ),
                              child: const Text('Uzun Mola'),
                            ),
                            ElevatedButton(
                              onPressed: () =>
                                  _showCustomTimeDialog(context, pomodoroModel),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.purple.shade700,
                              ),
                              child: const Text('Manuel Süre'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'Tamamlanan Pomodoro: ${pomodoroModel.completedPomodoros}',
                          style: const TextStyle(color: Colors.white, fontSize: 16),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}

void _showCustomTimeDialog(BuildContext context, PomodoroModel model) {
  final TextEditingController controller = TextEditingController();

  showDialog(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        title: const Text('Manuel Süre Ayarla'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Dakika',
            hintText: 'Dakika cinsinden süre girin',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
          TextButton(
            onPressed: () {
              final int? minutes = int.tryParse(controller.text);
              if (minutes != null && minutes > 0) {
                model.setCustomTime(minutes);
                Navigator.pop(context);
              }
            },
            child: const Text('Ayarla'),
          ),
        ],
      );
    },
  );
}
