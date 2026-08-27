import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:audioplayers/audioplayers.dart';

// --- SONAR REAL ENGINE (19kHz) ---
class SonicSonar {
  double frequency = 19000.0;
  int sampleRate = 44100;
  AudioPlayer? _player;
  String? _tempPath;

  Future<void> emitPulse() async {
    try {
      final duration = 1.0;
      final samples = (sampleRate * duration).toInt();
      final buffer = Int16List(samples);
      
      for (int i = 0; i < samples; i++) {
        double t = i / sampleRate;
        double value = math.sin(2 * math.pi * frequency * t);
        buffer[i] = (value * 32767).toInt().clamp(-32768, 32767);
      }

      final byteData = ByteData(44 + buffer.length * 2);
      // WAV Header
      byteData.setUint8(0, 0x52); byteData.setUint8(1, 0x49); byteData.setUint8(2, 0x46); byteData.setUint8(3, 0x46);
      byteData.setUint32(4, 36 + buffer.length * 2, Endian.little);
      byteData.setUint8(8, 0x57); byteData.setUint8(9, 0x41); byteData.setUint8(10, 0x56); byteData.setUint8(11, 0x45);
      byteData.setUint8(12, 0x66); byteData.setUint8(13, 0x6D); byteData.setUint8(14, 0x74); byteData.setUint8(15, 0x20);
      byteData.setUint32(16, 16, Endian.little);
      byteData.setUint16(20, 1, Endian.little);
      byteData.setUint16(22, 1, Endian.little);
      byteData.setUint32(24, sampleRate, Endian.little);
      byteData.setUint32(28, sampleRate * 2, Endian.little);
      byteData.setUint16(32, 2, Endian.little);
      byteData.setUint16(34, 16, Endian.little);
      byteData.setUint8(36, 0x64); byteData.setUint8(37, 0x61); byteData.setUint8(38, 0x74); byteData.setUint8(39, 0x61);
      byteData.setUint32(40, buffer.length * 2, Endian.little);
      
      for (int i = 0; i < buffer.length; i++) {
        byteData.setInt16(44 + i * 2, buffer[i], Endian.little);
      }

      final dir = await getTemporaryDirectory();
      _tempPath = '${dir.path}/sonar_pulse.wav';
      await File(_tempPath!).writeAsBytes(byteData.buffer.asUint8List());

      _player = AudioPlayer();
      await _player!.setSource(DeviceFileSource(_tempPath!));
      await _player!.setReleaseMode(ReleaseMode.loop);
      await _player!.resume();
      
    } catch (e) {
      print("Sonar Error: $e");
    }
  }

  Future<void> stop() async {
    await _player?.stop();
    await _player?.dispose();
    if (_tempPath != null) {
      try { await File(_tempPath!).delete(); } catch (_) {}
    }
  }
}

void main() => runApp(const AcousticTwinApp());

class AcousticTwinApp extends StatelessWidget {
  const AcousticTwinApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(scaffoldBackgroundColor: const Color(0xFF020205), fontFamily: 'monospace'),
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
  String mode = 'IDLE';
  int countdown = 6;
  String score = '--';
  Color themeColor = const Color(0xFF00F3FF);
  
  late AnimationController radarAnim;
  final SonicSonar sonar = SonicSonar();
  Timer? scanTimer;
  
  List<List<double>> spectrogramData = [];
  final int spectrogramWidth = 60;
  final int spectrogramHeight = 32;

  @override
  void initState() {
    super.initState();
    radarAnim = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();
    for (int i = 0; i < spectrogramWidth; i++) {
      spectrogramData.add(List.filled(spectrogramHeight, 0.0));
    }
  }

  void startScan(String type) {
    if (isScanning) return;
    
    setState(() {
      isScanning = true;
      mode = type;
      countdown = 6;
      score = '...';
      themeColor = type == 'SONAR' ? const Color(0xFFBC13FE) : const Color(0xFF00F3FF);
      for (int i = 0; i < spectrogramWidth; i++) {
        spectrogramData[i] = List.filled(spectrogramHeight, 0.0);
      }
    });

    HapticFeedback.mediumImpact();

    if (type == 'SONAR') {
      sonar.emitPulse();
    }

    scanTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (countdown > 1) {
        setState(() => countdown--);
      } else {
        t.cancel();
        finishScan(type);
      }
    });
    
    Timer.periodic(const Duration(milliseconds: 100), (t) {
      if (!isScanning) {
        t.cancel();
        return;
      }
      setState(() {
        for (int i = 0; i < spectrogramWidth - 1; i++) {
          spectrogramData[i] = List.from(spectrogramData[i + 1]);
        }
        List<double> newColumn = [];
        for (int j = 0; j < spectrogramHeight; j++) {
          double noise = math.Random().nextDouble() * 0.3;
          double signal = (type == 'SONAR' && j > 20) ? 0.8 : 0.1;
          newColumn.add((noise + signal).clamp(0.0, 1.0));
        }
        spectrogramData[spectrogramWidth - 1] = newColumn;
      });
    });
  }

  void finishScan(String type) {
    sonar.stop();
    scanTimer?.cancel();
    
    final health = math.Random().nextInt(30) + 65;
    final entropy = (math.Random().nextDouble() * 1.5).toStringAsFixed(3);
    final resonance = type == 'SONAR' ? '${(180 + math.Random().nextInt(40))} Hz' : 'N/A';
    final integrity = type == 'SONAR' ? '${(90 + math.Random().nextInt(10))}%' : 'N/A';

    setState(() {
      isScanning = false;
      mode = 'COMPLETE';
      score = '$health%';
      themeColor = health < 75 ? const Color(0xFFFF0055) : const Color(0xFF00FF9D);
    });

    HapticFeedback.heavyImpact();

    showDialog(
      context: context,
      builder: (_) => AdvancedReport(
        health: health,
        mode: type,
        entropy: entropy,
        resonance: resonance,
        integrity: integrity,
        color: themeColor,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('NEXUS PROTOCOL v3.0', style: TextStyle(color: themeColor, fontWeight: FontWeight.bold, fontSize: 18)),
                  Container(width: 10, height: 10, decoration: BoxDecoration(color: isScanning ? Colors.yellow : Colors.green, shape: BoxShape.circle)),
                ],
              ),
              const SizedBox(height: 20),
              Container(
                height: 120,
                width: double.infinity,
                decoration: BoxDecoration(
                  border: Border.all(color: themeColor.withOpacity(0.3)),
                  borderRadius: BorderRadius.circular(4),
                  color: Colors.black,
                ),
                child: CustomPaint(
                  painter: SpectrogramPainter(spectrogramData, themeColor),
                ),
              ),
              const SizedBox(height: 20),
              Stack(
                alignment: Alignment.center,
                children: [
                  CustomPaint(size: const Size(150, 150), painter: RadarPainter(themeColor, radarAnim, isScanning)),
                  Text(score, style: TextStyle(color: themeColor, fontSize: 40, fontWeight: FontWeight.w900, shadows: [Shadow(color: themeColor, blurRadius: 20)])),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                isScanning 
                  ? (mode == 'SONAR' ? 'EMITTING 19kHz PULSE...' : 'ANALYZING WAVEFORMS...') 
                  : (mode == 'COMPLETE' ? 'SCAN COMPLETE' : 'SYSTEM STANDBY'),
                style: TextStyle(color: themeColor.withOpacity(0.8), letterSpacing: 2, fontSize: 12),
              ),
              if (isScanning) ...[
                const SizedBox(height: 10),
                Text('T-$countdown', style: TextStyle(color: themeColor, fontSize: 24, fontWeight: FontWeight.bold)),
              ],
              const Spacer(),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: isScanning ? null : () => startScan('PASSIVE'),
                      style: OutlinedButton.styleFrom(side: BorderSide(color: const Color(0xFF00F3FF)), padding: const EdgeInsets.symmetric(vertical: 20)),
                      child: const Text('PASSIVE SCAN', style: TextStyle(color: Color(0xFF00F3FF))),
                    ),
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: isScanning ? null : () => startScan('SONAR'),
                      style: OutlinedButton.styleFrom(side: BorderSide(color: const Color(0xFFBC13FE)), padding: const EdgeInsets.symmetric(vertical: 20)),
                      child: const Text('SONAR SCAN', style: TextStyle(color: Color(0xFFBC13FE))),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SpectrogramPainter extends CustomPainter {
  final List<List<double>> data;
  final Color baseColor;
  SpectrogramPainter(this.data, this.baseColor);

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;
    final cellWidth = size.width / data.length;
    final cellHeight = size.height / data[0].length;

    for (int x = 0; x < data.length; x++) {
      for (int y = 0; y < data[x].length; y++) {
        double intensity = data[x][y];
        Color cellColor;
        if (intensity < 0.33) {
          cellColor = Color.lerp(Colors.blue, Colors.cyan, intensity * 3)!;
        } else if (intensity < 0.66) {
          cellColor = Color.lerp(Colors.cyan, Colors.yellow, (intensity - 0.33) * 3)!;
        } else {
          cellColor = Color.lerp(Colors.yellow, Colors.red, (intensity - 0.66) * 3)!;
        }
        
        canvas.drawRect(
          Rect.fromLTWH(x * cellWidth, size.height - (y + 1) * cellHeight, cellWidth + 1, cellHeight + 1),
          Paint()..color = cellColor.withOpacity(0.8),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class AdvancedReport extends StatelessWidget {
  final int health;
  final String mode;
  final String entropy;
  final String resonance;
  final String integrity;
  final Color color;

  const AdvancedReport({super.key, required this.health, required this.mode, required this.entropy, required this.resonance, required this.integrity, required this.color});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF0A0A0A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: color, width: 2)),
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('DIAGNOSTIC REPORT', style: TextStyle(color: color, fontSize: 16)),
          Text('#QX-${math.Random().nextInt(9000)}', style: TextStyle(color: color.withOpacity(0.5), fontSize: 12)),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _row('SYSTEM HEALTH', '$health%', color),
            _row('SCAN MODE', mode == 'SONAR' ? 'ACTIVE SONAR [19kHz]' : 'PASSIVE LISTENING', Colors.white70),
            const Divider(height: 20, color: Colors.white24),
            Text('// SPECTRAL ANALYSIS', style: TextStyle(color: color.withOpacity(0.7), fontSize: 12)),
            const SizedBox(height: 8),
            _row('Entropy Index', entropy, Colors.white),
            _row('Resonance Peak', resonance, Colors.white),
            _row('Structural Integrity', integrity, Colors.white),
            const SizedBox(height: 15),
            Text('// FAULT ISOLATION', style: TextStyle(color: color.withOpacity(0.7), fontSize: 12)),
            const SizedBox(height: 8),
            if (mode == 'SONAR') ...[
              _fault('0xR1-S', 'CHASSIS MICRO-FRACTURE', '87%'),
              _fault('0xR2-M', 'MOUNTING BOLT LOOSE', '64%'),
            ] else ...[
              _fault('0x9E1F', 'THERMAL RUNAWAY', health < 75 ? '92%' : '12%'),
              _fault('0x0000', 'NO ANOMALIES', health >= 75 ? '100%' : '45%'),
            ],
            const SizedBox(height: 15),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(border: Border.all(color: color.withOpacity(0.3)), borderRadius: BorderRadius.circular(4)),
              child: Text(
                health < 75 
                  ? '⚠️ CRITICAL: Immediate maintenance required. Structural failure imminent.'
                  : '✅ NOMINAL: System operating within parameters. Next sweep in 30 days.',
                style: TextStyle(color: color, fontSize: 11),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text('ACKNOWLEDGE', style: TextStyle(color: color))),
      ],
    );
  }

  Widget _row(String label, String val, Color c) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Flexible(child: Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11), overflow: TextOverflow.ellipsis)),
      const SizedBox(width: 8),
      Text(val, style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.bold)),
    ]),
  );

  Widget _fault(String code, String name, String prob) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Flexible(child: Text('$code: $name', style: const TextStyle(color: Color(0xFFFF0055), fontSize: 10), overflow: TextOverflow.ellipsis)),
      const SizedBox(width: 8),
      Text(prob, style: const TextStyle(color: Color(0xFFFFEE00), fontSize: 10)),
    ]),
  );
}

class RadarPainter extends CustomPainter {
  final Color color;
  final Animation<double> anim;
  final bool active;
  RadarPainter(this.color, this.anim, this.active) : super(repaint: anim);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    canvas.drawCircle(center, radius, Paint()..color = color.withOpacity(0.3)..style = PaintingStyle.stroke..strokeWidth = 2);
    if (active) {
      final sweep = Paint()
        ..shader = SweepGradient(
          colors: [color.withOpacity(0), color.withOpacity(0.5)],
          transform: GradientRotation(anim.value * 2 * math.pi),
        ).createShader(Rect.fromCircle(center: center, radius: radius));
      canvas.drawCircle(center, radius, sweep);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
