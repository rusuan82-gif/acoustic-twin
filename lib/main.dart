import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:audioplayers/audioplayers.dart';

// --- CLASA DE EMISIE ULTRASONICĂ ---
class UltrasonicEmitter {
  double frequency = 19000.0;
  int sampleRate = 44100;
  bool isPlaying = false;
  
  AudioPlayer? _player;
  String? _tempFilePath;

  Future<void> start() async {
    if (isPlaying) return;
    isPlaying = true;

    try {
      // Generăm un buffer WAV simplu în memorie
      final duration = 1.0; // 1 secundă loop
      final samples = (sampleRate * duration).toInt();
      final buffer = Int16List(samples);
      
      for (int i = 0; i < samples; i++) {
        double t = i / sampleRate;
        double value = math.sin(2 * math.pi * frequency * t);
        buffer[i] = (value * 32767).toInt().clamp(-32768, 32767);
      }

      // Convertim în bytes WAV (header simplificat)
      final byteData = ByteData(44 + buffer.length * 2);
      // RIFF header
      byteData.setUint8(0, 0x52); // R
      byteData.setUint8(1, 0x49); // I
      byteData.setUint8(2, 0x46); // F
      byteData.setUint8(3, 0x46); // F
      byteData.setUint32(4, 36 + buffer.length * 2, Endian.little); // ChunkSize
      byteData.setUint8(8, 0x57); // W
      byteData.setUint8(9, 0x41); // A
      byteData.setUint8(10, 0x56); // V
      byteData.setUint8(11, 0x45); // E
      // fmt subchunk
      byteData.setUint8(12, 0x66); // f
      byteData.setUint8(13, 0x6D); // m
      byteData.setUint8(14, 0x74); // t
      byteData.setUint8(15, 0x20); // space
      byteData.setUint32(16, 16, Endian.little); // Subchunk1Size
      byteData.setUint16(20, 1, Endian.little); // AudioFormat (PCM)
      byteData.setUint16(22, 1, Endian.little); // NumChannels
      byteData.setUint32(24, sampleRate, Endian.little); // SampleRate
      byteData.setUint32(28, sampleRate * 2, Endian.little); // ByteRate
      byteData.setUint16(32, 2, Endian.little); // BlockAlign
      byteData.setUint16(34, 16, Endian.little); // BitsPerSample
      // data subchunk
      byteData.setUint8(36, 0x64); // d
      byteData.setUint8(37, 0x61); // a
      byteData.setUint8(38, 0x74); // t
      byteData.setUint8(39, 0x61); // a
      byteData.setUint32(40, buffer.length * 2, Endian.little); // Subchunk2Size
      
      // Scriem datele audio
      for (int i = 0; i < buffer.length; i++) {
        byteData.setInt16(44 + i * 2, buffer[i], Endian.little);
      }

      // Salvăm într-un fișier temporar
      final directory = await getTemporaryDirectory();
      _tempFilePath = '${directory.path}/ultrasonic.wav';
      final file = File(_tempFilePath!);
      await file.writeAsBytes(byteData.buffer.asUint8List());

      // Redăm fișierul
      _player = AudioPlayer();
      await _player!.setSource(DeviceFileSource(_tempFilePath!));
      await _player!.setReleaseMode(ReleaseMode.loop);
      await _player!.resume();
      
    } catch (e) {
      print("Eroare la emiterea sunetului: $e");
      isPlaying = false;
    }
  }

  Future<void> stop() async {
    isPlaying = false;
    await _player?.stop();
    await _player?.dispose();
    _player = null;
    
    // Ștergem fișierul temporar
    if (_tempFilePath != null) {
      try {
        await File(_tempFilePath!).delete();
      } catch (e) {}
    }
  }
}

void main() {
  runApp(const AcousticTwinApp());
}

class AcousticTwinApp extends StatelessWidget {
  const AcousticTwinApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Acoustic Twin // NEXUS',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: const Color(0xFF020205),
        fontFamily: 'ShareTechMono', 
        useMaterial3: true,
      ),
      home: const NexusScreen(),
    );
  }
}

class NexusScreen extends StatefulWidget {
  const NexusScreen({super.key});

  @override
  State<NexusScreen> createState() => _NexusScreenState();
}

class _NexusScreenState extends State<NexusScreen> with TickerProviderStateMixin {
  bool isScanning = false;
  String scanType = ''; 
  int countdown = 6;
  double energyLevel = 0.0;
  String statusText = 'SYSTEM STANDBY';
  String scoreDisplay = '--';
  Color primaryColor = const Color(0xFF00F3FF); 
  
  late AnimationController _radarController;
  late AnimationController _glowController;
  
  Timer? scanTimer;
  Timer? countdownTimer;
  
  final UltrasonicEmitter emitter = UltrasonicEmitter();

  @override
  void initState() {
    super.initState();
    _radarController = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();
    _glowController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _radarController.dispose();
    _glowController.dispose();
    scanTimer?.cancel();
    countdownTimer?.cancel();
    emitter.stop();
    super.dispose();
  }

  void startScan(String type) {
    if (isScanning) return;
    
    setState(() {
      isScanning = true;
      scanType = type;
      countdown = 6;
      scoreDisplay = '...';
      statusText = type == 'RESONANCE' ? 'EMITTING SONIC PULSE...' : 'ANALYZING WAVEFORMS...';
      primaryColor = type == 'RESONANCE' ? const Color(0xFFBC13FE) : const Color(0xFF00F3FF);
    });

    HapticFeedback.mediumImpact();

    // ✅ FIX: Pornim EMIȚIA REALĂ dacă e modul Rezonanță
    if (type == 'RESONANCE') {
      emitter.start();
      Future.delayed(const Duration(milliseconds: 100), () => HapticFeedback.lightImpact());
    }

    countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (countdown > 0) {
        setState(() => countdown--);
      } else {
        timer.cancel();
        finishScan(type);
      }
    });

    scanTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      setState(() {
        energyLevel = math.Random().nextDouble() * (type == 'RESONANCE' ? 0.8 : 0.5);
      });
    });
  }

  void finishScan(String type) {
    // ✅ FIX: Oprim EMIIA după scanare
    emitter.stop();
    
    scanTimer?.cancel();
    
    final health = math.Random().nextInt(100);
    final isCritical = health < 55;
    final isWarning = health >= 55 && health < 80;

    setState(() {
      isScanning = false;
      scoreDisplay = '$health%';
      statusText = isCritical 
          ? 'CRITICAL FAILURE IMMINENT' 
          : (isWarning ? 'ANOMALY DETECTED' : 'SYSTEM OPTIMAL');
      
      if (isCritical) {
        primaryColor = const Color(0xFFFF0055); 
        HapticFeedback.heavyImpact();
      } else if (isWarning) {
        primaryColor = const Color(0xFFFFEE00); 
        HapticFeedback.selectionClick();
      } else {
        primaryColor = const Color(0xFF00FF9D); 
        HapticFeedback.lightImpact();
      }
    });

    showDialog(
      context: context,
      builder: (ctx) => DiagnosticReportDialog(
        health: health,
        type: type,
        color: primaryColor,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('NEXUS PROTOCOL v2.0', 
                    style: TextStyle(color: primaryColor, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 2)),
                  AnimatedBuilder(
                    animation: _glowController,
                    builder: (context, child) => Container(
                      width: 12, height: 12, decoration: BoxDecoration(
                        color: isScanning ? Colors.yellow : Colors.green,
                        shape: BoxShape.circle,
                        boxShadow: [BoxShadow(color: isScanning ? Colors.yellow : Colors.green, blurRadius: 10 * _glowController.value)],
                      ),
                    ),
                  )
                ],
              ),
              const SizedBox(height: 30),

              Expanded(
                flex: 3,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CustomPaint(painter: RadarPainter(primaryColor, isScanning, _radarController)),
                    Text(scoreDisplay, 
                      style: TextStyle(color: primaryColor, fontSize: 60, fontWeight: FontWeight.w900, shadows: [Shadow(color: primaryColor, blurRadius: 20)])),
                  ],
                ),
              ),

              Text(statusText, textAlign: TextAlign.center, 
                style: TextStyle(color: primaryColor.withOpacity(0.8), fontSize: 14, letterSpacing: 1.5)),
              const SizedBox(height: 30),

              Row(
                children: [
                  Expanded(child: ScanButton(label: 'PASSIVE SCAN', color: const Color(0xFF00F3FF), onPressed: () => startScan('PASSIVE'), disabled: isScanning)),
                  const SizedBox(width: 15),
                  Expanded(child: ScanButton(label: 'RESONANCE', color: const Color(0xFFBC13FE), onPressed: () => startScan('RESONANCE'), disabled: isScanning)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ScanButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onPressed;
  final bool disabled;

  const ScanButton({super.key, required this.label, required this.color, required this.onPressed, required this.disabled});

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: disabled ? null : onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.transparent,
        side: BorderSide(color: disabled ? Colors.grey.shade800 : color, width: 2),
        padding: const EdgeInsets.symmetric(vertical: 18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      child: Text(label, style: TextStyle(color: disabled ? Colors.grey : color, fontWeight: FontWeight.bold, letterSpacing: 1)),
    );
  }
}

class DiagnosticReportDialog extends StatelessWidget {
  final int health;
  final String type;
  final Color color;

  const DiagnosticReportDialog({super.key, required this.health, required this.type, required this.color});

  @override
  Widget build(BuildContext context) {
    final isCritical = health < 55;
    
    List<Map<String, String>> faults = [];
    if (type == 'RESONANCE') {
      faults.add({'code': '0xR1-S', 'name': 'CHASSIS_LOOSE', 'prob': '94%', 'time': 'Immediate'});
    } else {
      if (isCritical) faults.add({'code': '0x9E1F', 'name': 'THERMAL_RUNAWAY', 'prob': '92%', 'time': '<24h'});
      else faults.add({'code': '0x0000', 'name': 'NO_FAULTS', 'prob': '100%', 'time': 'N/A'});
    }

    return AlertDialog(
      backgroundColor: const Color(0xFF111111),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: color)),
      title: Text('DIAGNOSTIC REPORT #QX-${math.Random().nextInt(9000)+1000}', 
        style: TextStyle(color: color, fontSize: 16)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...faults.map((f) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('${f['code']}: ${f['name']}', style: const TextStyle(color: Color(0xFFFF0055), fontWeight: FontWeight.bold)),
                Text('${f['prob']} | ETA: ${f['time']}', style: const TextStyle(color: Color(0xFFFFEE00))),
              ],
            ),
          )),
          const Divider(color: Colors.white24),
          Text(isCritical ? '⚠️ IMMEDIATE ACTION REQUIRED' : '✅ STATUS NOMINAL', 
            style: TextStyle(color: color, fontWeight: FontWeight.bold)),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text('ACKNOWLEDGE', style: TextStyle(color: color))),
      ],
    );
  }
}

class RadarPainter extends CustomPainter {
  final Color color;
  final bool active;
  final Animation<double> animation;

  RadarPainter(this.color, this.active, this.animation) : super(repaint: animation);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 10;

    final basePaint = Paint()..color = color.withOpacity(0.2)..style = PaintingStyle.stroke..strokeWidth = 2;
    canvas.drawCircle(center, radius, basePaint);

    if (active) {
      final sweepPaint = Paint()
        ..shader = SweepGradient(colors: [color.withOpacity(0), color.withOpacity(0.6)], transform: GradientRotation(animation.value * 2 * math.pi)).createShader(Rect.fromCircle(center: center, radius: radius))
        ..style = PaintingStyle.fill;
      canvas.drawArc(Rect.fromCircle(center: center, radius: radius), -math.pi/2, 2*math.pi, true, sweepPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
