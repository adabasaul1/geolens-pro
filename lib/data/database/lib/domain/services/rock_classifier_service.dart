// lib/domain/services/rock_classifier_service.dart
//
// GeoLens Pro — Motor de clasificación petrográfica offline
// Modelo: TensorFlow Lite MobileNetV3-Large fine-tuned
// Clases: Andesita | Dacita | Riolita | Basalto | Granito |
//         Caliza | Arenisca cuarzosa | Lutita | Esquisto | Ignimbrita
// Resolución entrada: 224×224 px, RGB float32 normalizado [0,1]
// Output: vector de probabilidades softmax (10 clases)

import 'dart:io';
import 'dart:typed_data';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;
import 'package:logger/logger.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ETIQUETAS IUGS (orden debe coincidir con el modelo .tflite exportado)
// ─────────────────────────────────────────────────────────────────────────────
const List<RockClass> kRockClasses = [
  RockClass(
    label: 'Andesita',
    labelEs: 'Andesita',
    iugs: 'Roca ígnea volcánica intermedia',
    diagrama: 'TAS',
    siO2Range: (52, 63),
    regiones: ['Sierra', 'Costa'],
    formacionesAsociadas: ['Ma', 'VCo', 'VTu'],
  ),
  RockClass(
    label: 'Dacita',
    labelEs: 'Dacita',
    iugs: 'Roca ígnea volcánica intermedia-ácida',
    diagrama: 'TAS',
    siO2Range: (63, 68),
    regiones: ['Sierra'],
    formacionesAsociadas: ['VCo'],
  ),
  RockClass(
    label: 'Riolita',
    labelEs: 'Riolita / Ignimbrita',
    iugs: 'Roca ígnea volcánica ácida',
    diagrama: 'TAS',
    siO2Range: (68, 77),
    regiones: ['Sierra'],
    formacionesAsociadas: ['Ch'],
  ),
  RockClass(
    label: 'Basalto',
    labelEs: 'Basalto',
    iugs: 'Roca ígnea volcánica máfica',
    diagrama: 'TAS',
    siO2Range: (45, 52),
    regiones: ['Costa', 'Sierra'],
    formacionesAsociadas: ['Pi', 'VTu'],
  ),
  RockClass(
    label: 'Granito',
    labelEs: 'Granito / Tonalita',
    iugs: 'Roca ígnea plutónica ácida',
    diagrama: 'QAPF',
    siO2Range: (68, 77),
    regiones: ['Sierra'],
    formacionesAsociadas: [],
  ),
  RockClass(
    label: 'Caliza',
    labelEs: 'Caliza / Wackestone',
    iugs: 'Roca sedimentaria carbonatada',
    diagrama: 'Folk',
    siO2Range: null,
    regiones: ['Oriente', 'Costa'],
    formacionesAsociadas: ['GNa'],
  ),
  RockClass(
    label: 'AreniscaCuarzosa',
    labelEs: 'Arenisca cuarzosa (ortocuarcita)',
    iugs: 'Roca sedimentaria siliciclástica',
    diagrama: 'Folk',
    siO2Range: null,
    regiones: ['Oriente'],
    formacionesAsociadas: ['Ho'],
  ),
  RockClass(
    label: 'Lutita',
    labelEs: 'Lutita / Shale',
    iugs: 'Roca sedimentaria pelítica',
    diagrama: 'Folk',
    siO2Range: null,
    regiones: ['Oriente', 'Costa'],
    formacionesAsociadas: ['GNa', 'GTe'],
  ),
  RockClass(
    label: 'Esquisto',
    labelEs: 'Esquisto (metamórfico)',
    iugs: 'Roca metamórfica foliada',
    diagrama: null,
    siO2Range: null,
    regiones: ['Sierra'],
    formacionesAsociadas: ['UPe'],
  ),
  RockClass(
    label: 'AreniscaVolcaniclastica',
    labelEs: 'Arenisca volcaniclástica / Litarenita',
    iugs: 'Roca sedimentaria volcaniclástica',
    diagrama: 'Folk',
    siO2Range: null,
    regiones: ['Sierra', 'Costa'],
    formacionesAsociadas: ['Ang', 'Ch'],
  ),
];

// ─────────────────────────────────────────────────────────────────────────────
// MODELO DE DATOS
// ─────────────────────────────────────────────────────────────────────────────
class RockClass {
  final String label;
  final String labelEs;
  final String iugs;
  final String? diagrama;
  final (double, double)? siO2Range;
  final List<String> regiones;
  final List<String> formacionesAsociadas;

  const RockClass({
    required this.label,
    required this.labelEs,
    required this.iugs,
    required this.diagrama,
    required this.siO2Range,
    required this.regiones,
    required this.formacionesAsociadas,
  });
}

class ClassificationResult {
  final RockClass rockClass;
  final double confidence;
  final List<(RockClass, double)> topK;
  final String? alertaGeologica;

  const ClassificationResult({
    required this.rockClass,
    required this.confidence,
    required this.topK,
    this.alertaGeologica,
  });

  bool get isReliable => confidence >= 0.65;

  String get confidenceLabel {
    if (confidence >= 0.85) return 'Alta confianza';
    if (confidence >= 0.65) return 'Confianza moderada';
    return 'Baja confianza — verificar en campo';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SERVICIO PRINCIPAL
// ─────────────────────────────────────────────────────────────────────────────
class RockClassifierService {
  static const String _modelPath = 'assets/models/geolens_ecuador_v1.tflite';
  static const int _inputSize = 224;
  static const int _topK = 3;

  Interpreter? _interpreter;
  bool _initialized = false;
  final _log = Logger(printer: PrettyPrinter(methodCount: 0));

  Future<void> initialize() async {
    if (_initialized) return;
    try {
      final options = InterpreterOptions()
        ..threads = 4
        ..useNnApiForAndroid = true;   // NNAPI para hardware acelerado

      _interpreter = await Interpreter.fromAsset(
        _modelPath,
        options: options,
      );
      _initialized = true;
      _log.i('Modelo TFLite inicializado: $_modelPath');
    } catch (e) {
      _log.e('Error al cargar modelo TFLite: $e');
      rethrow;
    }
  }

  void dispose() {
    _interpreter?.close();
    _initialized = false;
  }

  // ── PIPELINE DE INFERENCIA ───────────────────────────────────────────────

  Future<ClassificationResult> classifyImage(File imageFile) async {
    assert(_initialized, 'Llama initialize() antes de clasificar');

    // 1. Cargar y preprocesar imagen
    final inputTensor = await _preprocessImage(imageFile);

    // 2. Preparar buffer de salida
    final output = List.filled(kRockClasses.length, 0.0).reshape([1, kRockClasses.length]);

    // 3. Inferencia (100% offline)
    _interpreter!.run(inputTensor, output);

    // 4. Extraer probabilidades softmax
    final probs = (output[0] as List<double>);
    return _buildResult(probs);
  }

  Future<List<List<List<List<double>>>>> _preprocessImage(File file) async {
    final bytes = await file.readAsBytes();
    var image = img.decodeImage(bytes)!;

    // Recorte central cuadrado (center crop)
    final minDim = image.width < image.height ? image.width : image.height;
    final xOff = (image.width - minDim) ~/ 2;
    final yOff = (image.height - minDim) ~/ 2;
    image = img.copyCrop(image, x: xOff, y: yOff, width: minDim, height: minDim);

    // Redimensionar a 224×224
    image = img.copyResize(image, width: _inputSize, height: _inputSize);

    // Normalizar a float32 [0, 1] — shape: [1, 224, 224, 3]
    final tensor = List.generate(
      1,
      (_) => List.generate(
        _inputSize,
        (y) => List.generate(
          _inputSize,
          (x) {
            final pixel = image.getPixel(x, y);
            return [
              pixel.r / 255.0,
              pixel.g / 255.0,
              pixel.b / 255.0,
            ];
          },
        ),
      ),
    );
    return tensor;
  }

  ClassificationResult _buildResult(List<double> probs) {
    // Ordenar por probabilidad descendente
    final indexed = probs.asMap().entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final topClass = kRockClasses[indexed[0].key];
    final confidence = indexed[0].value;

    final topK = indexed
        .take(_topK)
        .map((e) => (kRockClasses[e.key], e.value))
        .toList();

    // Alerta geológica contextual
    String? alerta;
    if (topClass.label == 'Esquisto' && confidence > 0.7) {
      alerta = '⚠ Posible presencia de minerales de alta presión (glaucofana). '
          'Verificar en Unidad Peltetec (Morona Santiago / Zamora-Chinchipe).';
    } else if (topClass.label == 'Caliza' && confidence > 0.7) {
      alerta = '💧 Prueba de campo recomendada: aplicar HCl 10% — efervescencia vigorosa confirma calcita.';
    } else if (topClass.label == 'AreniscaCuarzosa' && confidence > 0.8) {
      alerta = '🛢 Potencial reservorio. Corroborar con índice ZTR y porosimetría. '
          'Asociar a Formación Hollín (Aptiano, Oriente).';
    }

    return ClassificationResult(
      rockClass: topClass,
      confidence: confidence,
      topK: topK,
      alertaGeologica: alerta,
    );
  }
}


// ─────────────────────────────────────────────────────────────────────────────
// lib/domain/services/utm_service.dart
//
// Servicio de georreferenciación WGS84 / UTM Ecuador
// Zonas soportadas: 17N (Costa/Sierra norte), 17S (Sierra sur/Oriente),
//                   18S (Galápagos / Oriente extremo E)
// Implementación: proj4dart (EPSG oficiales)
// ─────────────────────────────────────────────────────────────────────────────

// ignore_for_file: avoid_classes_with_only_static_members
import 'package:geolocator/geolocator.dart';
import 'package:proj4dart/proj4dart.dart';
import 'package:latlong2/latlong.dart';

class UtmResult {
  final double easting;
  final double northing;
  final String zone;
  final String epsg;

  const UtmResult({
    required this.easting,
    required this.northing,
    required this.zone,
    required this.epsg,
  });

  @override
  String toString() =>
      '${zone} — E: ${easting.toStringAsFixed(1)} m, N: ${northing.toStringAsFixed(1)} m';
}

class UtmService {
  // EPSG definitions para Ecuador
  static final _proj17N = Projection.add(
    'EPSG:32617',
    '+proj=utm +zone=17 +ellps=WGS84 +datum=WGS84 +units=m +no_defs',
  );
  static final _proj17S = Projection.add(
    'EPSG:32717',
    '+proj=utm +zone=17 +south +ellps=WGS84 +datum=WGS84 +units=m +no_defs',
  );
  static final _proj18S = Projection.add(
    'EPSG:32718',
    '+proj=utm +zone=18 +south +ellps=WGS84 +datum=WGS84 +units=m +no_defs',
  );
  static final _wgs84 = Projection.get('EPSG:4326')!;

  /// Convierte coordenadas WGS84 a UTM automáticamente detectando la zona
  static UtmResult wgs84ToUtm(double lat, double lon) {
    final point = Point(x: lon, y: lat);
    late Projection utmProj;
    late String zone;
    late String epsg;

    if (lon >= -78.0 && lon < -75.0) {
      // Galápagos y extremo E del Oriente → Zona 18S
      utmProj = _proj18S;
      zone = '18S';
      epsg = 'EPSG:32718';
    } else if (lat >= 0.0) {
      // Hemisferio Norte (norte de la línea ecuatorial) → Zona 17N
      utmProj = _proj17N;
      zone = '17N';
      epsg = 'EPSG:32617';
    } else {
      // Hemisferio Sur → Zona 17S
      utmProj = _proj17S;
      zone = '17S';
      epsg = 'EPSG:32717';
    }

    final result = _wgs84.transform(utmProj, point);
    return UtmResult(
      easting: result.x,
      northing: result.y,
      zone: zone,
      epsg: epsg,
    );
  }

  /// Obtiene la posición actual del dispositivo
  static Future<Position> getCurrentPosition() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw const LocationException('Servicio GPS desactivado en el dispositivo');
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw const LocationException('Permiso de ubicación denegado');
      }
    }
    if (permission == LocationPermission.deniedForever) {
      throw const LocationException('Permiso de ubicación permanentemente denegado');
    }

    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0,
      ),
    );
  }

  /// Obtiene posición actual y la convierte a UTM
  static Future<({Position pos, UtmResult utm})> getPositionWithUtm() async {
    final pos = await getCurrentPosition();
    final utm = wgs84ToUtm(pos.latitude, pos.longitude);
    return (pos: pos, utm: utm);
  }
}

class LocationException implements Exception {
  final String message;
  const LocationException(this.message);
  @override
  String toString() => 'LocationException: $message';
}
