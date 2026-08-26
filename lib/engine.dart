import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

const sr = 16000, nFft = 1024, hop = 512, nMels = 64, clipFrames = 64;
const fmax = 8000.0;

class AcousticEngine {
  late Interpreter _interp;
  late double _mu, _sigma;
  late List<List<double>> _fb;
  late List<double> _centers;

  static Future<AcousticEngine> load() async {
    final e = AcousticEngine._();
    e._interp = await Interpreter.fromAsset('assets/models/autoencoder.tflite');
    final cfg = jsonDecode(await rootBundle.loadString('assets/models/baseline.json'));
    e._mu = (cfg['mu'] as num).toDouble();
    e._sigma = (cfg['sigma'] as num).toDouble();
    e._buildFilterbank();
    return e;
  }

  AcousticEngine._();

  void _buildFilterbank() {
    final nBins = nFft ~/ 2 + 1;
    double hz2mel(double f) => 2595.0 * math.log(1 + f / 700) / math.ln10;
    double mel2hz(double m) => 700.0 * (math.pow(10, m / 2595.0) - 1);
    final lo = hz2mel(0), hi = hz2mel(fmax);
    _centers = List.generate(nMels, (i) => mel2hz(lo + (hi - lo) * (i + 1) / (nMels + 1)));
    final hz = List.generate(nMels + 2, (i) => mel2hz(lo + (hi - lo) * i / (nMels + 1)));
    final bin = hz.map((f) => (f * nFft / sr).floor()).toList();
    _fb = List.generate(nMels, (f) {
      final row = List.filled(nBins, 0.0);
      final d1 = math.max(1, bin[f + 1] - bin[f]), d2 = math.max(1, bin[f + 2] - bin[f + 1]);
      for (int k = bin[f]; k <= bin[f + 1] && k < nBins; k++) row[k] = (k - bin[f]) / d1;
      for (int k = bin[f + 1]; k <= bin[f + 2] && k < nBins; k++) row[k] = (bin[f + 2] - k) / d2;
      return row;
    });
  }

  Map<String, dynamic> analyze(Float32List x) {
    final mel = _logMel(x);
    final T = mel[0].length;
    double errSum = 0; int nW = 0;
    for (int s = 0; s + clipFrames <= T; s += 32) { errSum += _windowError(mel, s); nW++; }
    final err = errSum / math.max(1, nW);
    final z = (err - _mu) / _sigma;
    final health = (100 - z * (100 / 6)).clamp(0, 100).round();
    return {
      'health': health,
      'verdict': health < 85 ? _diagnose(mel) : 'Semnătură acustică normală.',
    };
  }

  List<List<double>> _logMel(Float32List x) {
    final nFrames = (x.length - nFft) ~/ hop + 1;
    final win = Float64List(nFft);
    for (int i = 0; i < nFft; i++) win[i] = 0.5 - 0.5 * math.cos(2 * math.pi * i / (nFft - 1));
    final re = Float64List(nFft), im = Float64List(nFft);
    final nBins = nFft ~/ 2 + 1;
    final db = List.generate(nMels, (_) => List.filled(nFrames, 0.0));
    final power = Float64List(nBins);
    for (int f = 0; f < nFrames; f++) {
      for (int i = 0; i < nFft; i++) { re[i] = x[f * hop + i] * win[i]; im[i] = 0; }
      _fft(re, im);
      for (int k = 0; k < nBins; k++) power[k] = re[k] * re[k] + im[k] * im[k];
      for (int m = 0; m < nMels; m++) {
        double s = 0;
        for (int k = 0; k < nBins; k++) s += _fb[m][k] * power[k];
        db[m][f] = 10 * math.log(s + 1e-10) / math.ln10;
      }
    }
    double mx = -1e30;
    for (final r in db) for (final v in r) if (v > mx) mx = v;
    double mean = 0;
    for (final r in db) for (final v in r) mean += v - mx;
    mean /= nMels * nFrames;
    double va = 0;
    for (final r in db) for (final v in r) { final d = v - mx - mean; va += d * d; }
    final std = math.sqrt(va / (nMels * nFrames)) + 1e-6;
    for (int m = 0; m < nMels; m++)
      for (int f = 0; f < nFrames; f++) db[m][f] = (db[m][f] - mx - mean) / std;
    return db;
  }

  double _windowError(List<List<double>> mel, int s) {
    final input = List.generate(1, (_) => List.generate(clipFrames,
        (t) => List.generate(nMels, (m) => [mel[m][s + t]])));
    final output = List.generate(1, (_) => List.generate(clipFrames,
        (t) => List.generate(nMels, (m) => [0.0])));
    _interp.run(input, output);
    double e = 0;
    for (int t = 0; t < clipFrames; t++)
      for (int m = 0; m < nMels; m++) {
        final d = (output[0][t][m][0] as double) - mel[m][s + t];
        e += d * d;
      }
    return e / (clipFrames * nMels);
  }

  String _diagnose(List<List<double>> mel) {
    final T = mel[0].length;
    final flux = List.filled(T - 1, 0.0);
    for (int t = 0; t < T - 1; t++) {
      double s = 0;
      for (int m = 0; m < nMels; m++) { final d = mel[m][t + 1] - mel[m][t]; if (d > 0) s += d; }
      flux[t] = s;
    }
    final sorted = [...flux]..sort();
    final med = sorted[sorted.length ~/ 2];
    final peaks = flux.where((v) => v > 6 * med).length;
    final clicksPs = peaks / ((T - 1) / (sr / hop));
    double mx = 0, sum = 0; int cnt = 0;
    for (int m = 0; m < nMels; m++) {
      if (_centers[m] > 1500 && _centers[m] < 6000) {
        double s = 0;
        for (int t = 0; t < T; t++) s += math.exp(mel[m][t]);
        final avg = s / T; sum += avg; cnt++;
        if (avg > mx) mx = avg;
      }
    }
    final tonal = cnt > 0 ? mx / (sum / cnt + 1e-9) : 0.0;
    if (clicksPs > 1.5) return 'Click-uri anormale (${clicksPs.toStringAsFixed(1)}/s) → posibil HDD / mecanism.';
    if (tonal > 8) return 'Șuierat tonal în banda înaltă → rulment / ventilator cu uzură.';
    return 'Semnătură anormală nespecificată → inspectează echipamentul.';
  }

  void _fft(Float64List re, Float64List im) {
    final n = re.length;
    for (int i = 1, j = 0; i < n; i++) {
      int bit = n >> 1;
      for (; (j & bit) != 0; bit >>= 1) j ^= bit;
      j ^= bit;
      if (i < j) {
        final tr = re[i]; re[i] = re[j]; re[j] = tr;
        final ti = im[i]; im[i] = im[j]; im[j] = ti;
      }
    }
    for (int len = 2; len <= n; len <<= 1) {
      final h = len >> 1;
      final wr = math.cos(-2 * math.pi / len), wi = math.sin(-2 * math.pi / len);
      for (int i = 0; i < n; i += len) {
        double cr = 1, ci = 0;
        for (int k = 0; k < h; k++) {
          final ur = re[i + k], ui = im[i + k];
          final vr = re[i + k + h] * cr - im[i + k + h] * ci;
          final vi = re[i + k + h] * ci + im[i + k + h] * cr;
          re[i + k] = ur + vr; im[i + k] = ui + vi;
          re[i + k + h] = ur - vr; im[i + k + h] = ui - vi;
          final nr = cr * wr - ci * wi; ci = cr * wi + ci * wr; cr = nr;
        }
      }
    }
  }
}
