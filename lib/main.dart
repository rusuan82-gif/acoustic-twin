import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'engine.dart';

const channel = MethodChannel('acoustic_twin/recorder');

void main() => runApp(const MaterialApp(debugShowCheckedModeBanner: false, home: Home()));

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  AcousticEngine? engine;
  String status = 'Se încarcă modelul…';
  int? health;
  String verdict = '';
  bool busy = false;

  @override
  void initState() {
    super.initState();
    AcousticEngine.load().then((e) => setState(() { engine = e; status = 'Gata de scanare.'; }));
  }

  Color get _color => health == null ? Colors.cyan
      : health! >= 85 ? Colors.green : health! >= 60 ? Colors.orange : Colors.red;

  Future<void> scan() async {
    if (busy || engine == null) return;
    setState(() { busy = true; health = null; verdict = ''; status = 'Se înregistrează (6 s)…'; });
    if (!await Permission.microphone.request().isGranted) {
      setState(() { busy = false; status = 'Permisiune microfon refuzată.'; });
      return;
    }
    try {
      final bytes = await channel.invokeMethod<Uint8List>('recordSeconds', {'seconds': 6.0});
      final n = bytes!.length ~/ 2;
      final samples = Float32List(n);
      for (int i = 0; i < n; i++) {
        int v = (bytes[2 * i] & 0xFF) | ((bytes[2 * i + 1] & 0xFF) << 8);
        if (v > 32767) v -= 65536;
        samples[i] = v / 32768.0;
      }
      setState(() => status = 'Se analizează on-device…');
      await Future.delayed(const Duration(milliseconds: 100));
      final r = engine!.analyze(samples);
      setState(() { health = r['health'] as int; verdict = r['verdict'] as String; status = 'Scanare finalizată.'; });
    } catch (e) {
      setState(() => status = 'Eroare: $e');
    }
    setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final stare = health == null ? '—'
        : health! >= 85 ? 'SĂNĂTOS' : health! >= 60 ? 'UZURĂ TIMPURIE' : 'ANOMALIE';
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      body: Center(child: SingleChildScrollView(padding: const EdgeInsets.all(24), child: Column(children: [
        const Text('Acoustic Twin 🎧', style: TextStyle(color: Colors.cyan, fontSize: 28, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text(status, style: const TextStyle(color: Colors.white70)),
        const SizedBox(height: 32),
        SizedBox(width: 200, height: 200, child: Stack(alignment: Alignment.center, children: [
          CircularProgressIndicator(value: (health ?? 0) / 100, strokeWidth: 12,
              color: _color, backgroundColor: Colors.white12),
          Column(mainAxisSize: MainAxisSize.min, children: [
            Text(health == null ? '--' : '$health%',
                style: const TextStyle(color: Colors.white, fontSize: 48, fontWeight: FontWeight.bold)),
            Text('Stare: $stare', style: TextStyle(color: _color, fontSize: 14)),
          ]),
        ])),
        const SizedBox(height: 32),
        if (verdict.isNotEmpty)
          Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(
              color: Colors.white10, borderRadius: BorderRadius.circular(12)),
              child: Text(verdict, style: const TextStyle(color: Colors.white, fontSize: 16))),
        const SizedBox(height: 32),
        SizedBox(width: double.infinity, height: 56,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange,
                foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            onPressed: scan,
            child: Text(busy ? 'Se scanează…' : 'Pornește Scanarea',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)))),
      ]))),
    );
  }
}
