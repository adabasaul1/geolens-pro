// lib/data/database/geo_database_initializer.dart
//
// GeoLens Pro — Inicializador de base de datos geológica ecuatoriana
// Ontología basada en:
//   • Mapa Geológico de la República del Ecuador (IIGE / BGR, 2017)
//   • Litherland et al. (1994) — The Geology of Ecuador
//   • Spikings et al. (2010) — Thermochronology of the Ecuadorian Andes
//   • Pratt et al. (2005) — Lithospheric structure of the Ecuadorian Andes
//   • Vallejo et al. (2009) — Cretaceous forearc basins, Ecuador
// Clasificación petrográfica conforme a IUGS (Le Maitre et al., 2002)

import 'dart:async';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:logger/logger.dart';

final _log = Logger(printer: PrettyPrinter(methodCount: 0));

// ─────────────────────────────────────────────────────────────────────────────
// SCHEMA VERSION
// ─────────────────────────────────────────────────────────────────────────────
const int kDbVersion = 3;
const String kDbName = 'geolens_ecuador.db';

// ─────────────────────────────────────────────────────────────────────────────
// SINGLETON
// ─────────────────────────────────────────────────────────────────────────────
class GeoDatabase {
  GeoDatabase._();
  static final GeoDatabase instance = GeoDatabase._();
  Database? _db;

  Future<Database> get database async {
    _db ??= await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, kDbName);
    _log.i('Inicializando GeoLens DB en: $path');

    return openDatabase(
      path,
      version: kDbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onConfigure: (db) async => await db.execute('PRAGMA foreign_keys = ON'),
    );
  }

  // ── DDL ──────────────────────────────────────────────────────────────────

  Future<void> _onCreate(Database db, int version) async {
    await db.transaction((txn) async {
      await _createSchema(txn);
      await _seedFormacionesEcuatorianas(txn);
      await _seedMineralesIndicadores(txn);
      await _seedReferencias(txn);
      _log.i('Base de datos geológica inicializada correctamente (v$version)');
    });
  }

  Future<void> _onUpgrade(Database db, int oldV, int newV) async {
    _log.w('Migración DB: v$oldV → v$newV');
    // Migraciones incrementales se agregan aquí
  }

  Future<void> _createSchema(DatabaseExecutor db) async {
    // Tabla principal: formaciones geológicas del Ecuador
    await db.execute('''
      CREATE TABLE IF NOT EXISTS formaciones (
        id              INTEGER PRIMARY KEY AUTOINCREMENT,
        codigo          TEXT UNIQUE NOT NULL,       -- Código IIGE (ej: "Pi", "UPe")
        nombre          TEXT NOT NULL,              -- Nombre científico completo
        nombre_informal TEXT,                       -- Nombre coloquial / campo
        tipo_unidad     TEXT NOT NULL,              -- Formación|Grupo|Unidad|Miembro
        era             TEXT,                       -- Precámbrico|Paleozoico|Mesozoico|Cenozoico
        periodo         TEXT,
        epoca           TEXT,
        edad_ma_min     REAL,                       -- Ma (millones de años — mínimo)
        edad_ma_max     REAL,                       -- Ma (millones de años — máximo)
        region          TEXT NOT NULL,              -- Costa|Sierra|Oriente|Galápagos
        provincia_ref   TEXT,                       -- Provincia tipo de afloramiento
        ambiente_dep    TEXT,                       -- Ambiente deposicional / geodinámico
        litologia_dom   TEXT NOT NULL,              -- Litología dominante (texto libre)
        clasificacion_iugs TEXT,                    -- Clasificación IUGS formal
        diagrama_iugs   TEXT,                       -- QAPF|TAS|Folk|Wentworth
        vertices_diagrama TEXT,                     -- JSON: coords en diagrama QAPF/TAS
        color_munsell   TEXT,                       -- Código Munsell (ej: "5Y 4/3")
        textura         TEXT,
        estructura      TEXT,
        mineralogia     TEXT,                       -- Minerales principales (CSV)
        mineralogia_acc TEXT,                       -- Minerales accesorios (CSV)
        referencias     TEXT,                       -- Claves de tabla referencias (CSV)
        notas_campo     TEXT,
        creado_en       TEXT DEFAULT (datetime('now'))
      )
    ''');

    // Tabla: minerales indicadores / clave
    await db.execute('''
      CREATE TABLE IF NOT EXISTS minerales (
        id              INTEGER PRIMARY KEY AUTOINCREMENT,
        nombre          TEXT UNIQUE NOT NULL,
        formula         TEXT,
        sistema_crist   TEXT,
        dureza_mohs     REAL,
        densidad        REAL,
        color_tipico    TEXT,
        brillo          TEXT,
        exfoliacion     TEXT,
        notas_id        TEXT                       -- Caracteres diagnósticos en campo
      )
    ''');

    // Tabla: minerales ↔ formaciones (N:M)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS formacion_mineral (
        formacion_id  INTEGER REFERENCES formaciones(id),
        mineral_id    INTEGER REFERENCES minerales(id),
        rol           TEXT,   -- "principal" | "accesorio" | "alteracion"
        abundancia_pct REAL,
        PRIMARY KEY (formacion_id, mineral_id, rol)
      )
    ''');

    // Tabla: bibliografía Q1/Q2
    await db.execute('''
      CREATE TABLE IF NOT EXISTS referencias (
        id        INTEGER PRIMARY KEY AUTOINCREMENT,
        clave     TEXT UNIQUE NOT NULL,            -- BibTeX key (ej: "Litherland1994")
        autores   TEXT NOT NULL,
        anio      INTEGER,
        titulo    TEXT,
        revista   TEXT,
        volumen   TEXT,
        doi       TEXT,
        quartil   TEXT                             -- Q1|Q2|Q3|Libro
      )
    ''');

    // Tabla: muestras de campo registradas por el usuario
    await db.execute('''
      CREATE TABLE IF NOT EXISTS muestras (
        id              TEXT PRIMARY KEY,           -- UUID
        formacion_id    INTEGER REFERENCES formaciones(id),
        nombre_muestra  TEXT,
        fecha           TEXT NOT NULL,
        colector        TEXT,
        latitud_wgs84   REAL,
        longitud_wgs84  REAL,
        altitud_m       REAL,
        utm_zona        TEXT,                       -- "17N"|"17S"|"18S"
        utm_norte       REAL,
        utm_este        REAL,
        color_munsell   TEXT,
        textura_obs     TEXT,
        estructura_obs  TEXT,
        mineralogia_obs TEXT,
        foto_path       TEXT,                       -- Ruta local
        confianza_ia    REAL,                       -- Score 0–1 del modelo TFLite
        clase_ia        TEXT,                       -- Clase predicha
        notas           TEXT,
        creado_en       TEXT DEFAULT (datetime('now'))
      )
    ''');

    // Índices para rendimiento offline
    await db.execute('CREATE INDEX IF NOT EXISTS idx_form_region   ON formaciones(region)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_form_periodo  ON formaciones(periodo)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_form_iugs     ON formaciones(clasificacion_iugs)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_muestra_fecha ON muestras(fecha)');
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SEED: FORMACIONES GEOLÓGICAS DEL ECUADOR
  // Fuente primaria: IIGE (2017) y Litherland et al. (1994)
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _seedFormacionesEcuatorianas(DatabaseExecutor db) async {
    final formaciones = <Map<String, dynamic>>[

      // ── BLOQUE COSTERO / TERRENOS ALÓCTONOS ──────────────────────────────
      {
        'codigo': 'Pi',
        'nombre': 'Formación Piñón',
        'nombre_informal': 'Piñón',
        'tipo_unidad': 'Formación',
        'era': 'Mesozoico',
        'periodo': 'Cretácico',
        'epoca': 'Cenomaniano-Turoniano',
        'edad_ma_min': 90.0,
        'edad_ma_max': 100.0,
        'region': 'Costa',
        'provincia_ref': 'Guayas',
        'ambiente_dep': 'Plateau oceánico / MORB-like magmatism',
        'litologia_dom': 'Basaltos almohadillados, dolerita, gabro',
        'clasificacion_iugs': 'Basalto',
        'diagrama_iugs': 'TAS',
        'vertices_diagrama': '{"SiO2_min":45,"SiO2_max":52,"Na2O_K2O_min":0,"Na2O_K2O_max":3}',
        'color_munsell': '5Y 2.5/1',
        'textura': 'Afanítica a subofítica; pillow structure',
        'estructura': 'Almohadillada (pillow lava); brechas hialoclásticas',
        'mineralogia': 'Plagioclasa (labradorita-bytownita), clinopiroxeno (augita)',
        'mineralogia_acc': 'Magnetita titánica, ilmenita, olivino (parcial)',
        'referencias': 'Litherland1994,Vallejo2009,Kerr2002',
        'notas_campo': 'Basamento del terreno alóctono Piñón. Geoquímica OIB/plateau oceánico. '
            'Afloramientos en Manta, Jipijapa, Macuchi. Contacto fallado con Unidad Macuchi al E.',
      },

      {
        'codigo': 'Ma',
        'nombre': 'Unidad Macuchi',
        'nombre_informal': 'Macuchi',
        'tipo_unidad': 'Unidad',
        'era': 'Mesozoico',
        'periodo': 'Cretácico Superior',
        'epoca': 'Campaniano-Maastrichtiano',
        'edad_ma_min': 66.0,
        'edad_ma_max': 80.0,
        'region': 'Sierra',
        'provincia_ref': 'Bolívar',
        'ambiente_dep': 'Arco de islas intra-oceánico',
        'litologia_dom': 'Andesitas, basaltos, tobas volcánicas, lavas en almohadilla',
        'clasificacion_iugs': 'Andesita basáltica',
        'diagrama_iugs': 'TAS',
        'vertices_diagrama': '{"SiO2_min":52,"SiO2_max":57,"Na2O_K2O_min":2,"Na2O_K2O_max":5}',
        'color_munsell': '5GY 4/1',
        'textura': 'Porfírica a microcristalina; fenocristales de plagioclasa',
        'estructura': 'Masiva, almohadillada subordinada; intercalaciones piroclásticas',
        'mineralogia': 'Plagioclasa (andesina), clinopiroxeno, hornblenda',
        'mineralogia_acc': 'Epidota, clorita (alteración), titanita',
        'referencias': 'Litherland1994,Spikings2010,Hughes1998',
        'notas_campo': 'Arco intra-oceánico Cretácico. Geoquímica calc-alcalina. '
            'Cizallamiento y metamorfismo de bajo grado frecuente. '
            'No confundir con Formación Piñón (OIB).',
      },

      // ── TERRENO PELTETEC (Unidades metamórficas) ─────────────────────────
      {
        'codigo': 'UPe',
        'nombre': 'Unidad Peltetec',
        'nombre_informal': 'Peltetec',
        'tipo_unidad': 'Unidad',
        'era': 'Paleozoico',
        'periodo': 'Ordovícico-Devónico',
        'epoca': null,
        'edad_ma_min': 350.0,
        'edad_ma_max': 490.0,
        'region': 'Sierra',
        'provincia_ref': 'Morona Santiago',
        'ambiente_dep': 'Margen continental activo; metamorfismo de alta P/T',
        'litologia_dom': 'Esquistos de glaucofana, eclogitas, metabasaltos de alta presión',
        'clasificacion_iugs': 'Esquisto (metamórfico)',
        'diagrama_iugs': null,
        'vertices_diagrama': null,
        'color_munsell': '5B 3/2',
        'textura': 'Foliación penetrativa S1; lineación de estiramiento L2',
        'estructura': 'Esquistosidad, pliegues isoclinales, boudinage',
        'mineralogia': 'Glaucofana, epidota, lawsonita (relicta), fengita',
        'mineralogia_acc': 'Omfacita (relicta), granate, rutilo, titanita',
        'referencias': 'Litherland1994,Spikings2005,Bosch2002',
        'notas_campo': 'Facies de esquistos azules/eclogitas; P~1.0–1.5 GPa, T~350–500°C. '
            'Indicador clave de subducción Paleozoica en los Andes Ecuatorianos. '
            'Afloramientos en Zamora-Chinchipe y Morona Santiago.',
      },

      // ── GRUPO NAPO (Cretácico sedimentario, Oriente) ─────────────────────
      {
        'codigo': 'GNa',
        'nombre': 'Grupo Napo',
        'nombre_informal': 'Napo',
        'tipo_unidad': 'Grupo',
        'era': 'Mesozoico',
        'periodo': 'Cretácico',
        'epoca': 'Albiano-Coniaciano',
        'edad_ma_min': 85.0,
        'edad_ma_max': 108.0,
        'region': 'Oriente',
        'provincia_ref': 'Napo',
        'ambiente_dep': 'Plataforma marina epicontinental; rampa carbonatada',
        'litologia_dom': 'Calizas, lutitas calcáreas, areniscas cretácicas',
        'clasificacion_iugs': 'Caliza bioclástica / Wackestone',
        'diagrama_iugs': 'Folk',
        'vertices_diagrama': null,
        'color_munsell': '2.5Y 8/2',
        'textura': 'Micrítica a esparítica; bioclastos de equinodermos y bivalvos',
        'estructura': 'Estratificación paralela, laminación; nódulos de pedernal',
        'mineralogia': 'Calcita, dolomita subordinada, cuarzo (chert)',
        'mineralogia_acc': 'Pirita framboidal, glauconita, fragmentos de ammonites',
        'referencias': 'Dashwood1995,Balkwill1995,Jaillard1997',
        'notas_campo': 'Unidad reservorio/sello clave en cuenca petrolífera del Oriente. '
            'Incluye Mbros.: Napo Inferior (T), Napo Medio (M), Napo Superior (U). '
            'Efervescencia con HCl diagnóstica. POI hidrocarburos (API 20–35).',
      },

      // ── GRUPO TENA (Cretácico tardío, transición continental) ────────────
      {
        'codigo': 'GTe',
        'nombre': 'Grupo Tena',
        'nombre_informal': 'Tena',
        'tipo_unidad': 'Grupo',
        'era': 'Mesozoico',
        'periodo': 'Cretácico Superior',
        'epoca': 'Maastrichtiano',
        'edad_ma_min': 66.0,
        'edad_ma_max': 72.0,
        'region': 'Oriente',
        'provincia_ref': 'Napo',
        'ambiente_dep': 'Fluvio-deltaico a marino marginal; regresión',
        'litologia_dom': 'Lutitas rojas, areniscas líticas, conglomerados basales',
        'clasificacion_iugs': 'Arenisca lítica / Sublitarenita (Folk, 1980)',
        'diagrama_iugs': 'Folk',
        'vertices_diagrama': '{"Qt":65,"F":10,"Lt":25}',
        'color_munsell': '10R 4/4',
        'textura': 'Grano fino a medio; sub-redondeado; moderadamente clasificado',
        'estructura': 'Estratificación cruzada tabular, laminación horizontal',
        'mineralogia': 'Cuarzo, fragmentos líticos volcánicos, plagioclasa',
        'mineralogia_acc': 'Zircón, turmalina, oxidos Fe (cemento hematítico)',
        'referencias': 'Dashwood1995,Jaillard1997',
        'notas_campo': 'Color rojo diagnóstico en campo. Base: discordancia con Grupo Napo. '
            'Sello estructural para trampas en reservorios M-1 y U (Napo).',
      },

      // ── FORMACIÓN ANGAMARCA (Paleógeno volcaniclástico) ──────────────────
      {
        'codigo': 'Ang',
        'nombre': 'Formación Angamarca',
        'nombre_informal': 'Angamarca',
        'tipo_unidad': 'Formación',
        'era': 'Cenozoico',
        'periodo': 'Paleógeno',
        'epoca': 'Eoceno',
        'edad_ma_min': 34.0,
        'edad_ma_max': 55.0,
        'region': 'Sierra',
        'provincia_ref': 'Cotopaxi',
        'ambiente_dep': 'Cuenca de antearco; turbiditas volcaniclásticas',
        'litologia_dom': 'Areniscas volcaniclásticas, lutitas, turbiditas',
        'clasificacion_iugs': 'Arenisca volcaniclástica / Litarenita',
        'diagrama_iugs': 'Folk',
        'vertices_diagrama': '{"Qt":30,"F":20,"Lt":50}',
        'color_munsell': '5GY 5/1',
        'textura': 'Grano fino; matriz arcillosa; gradación normal en turbiditas',
        'estructura': 'Secuencias de Bouma (Ta-Te), flute casts, groove casts',
        'mineralogia': 'Fragmentos volcánicos, plagioclasa, vidrio volcánico',
        'mineralogia_acc': 'Hornblenda, biotita, zircón',
        'referencias': 'Litherland1994,Alvarado2016',
        'notas_campo': 'Turbiditas diagnósticas con secuencias de Bouma. '
            'Paleovolcanismo arco Eoceno representado en clastos. '
            'Deformación andina posterior (pliegues vergentes al E).',
      },

      // ── VOLCANES CUATERNARIOS / ARCO ECUATORIANO ─────────────────────────
      {
        'codigo': 'VCo',
        'nombre': 'Depósitos Volcánicos Cotopaxi',
        'nombre_informal': 'Cotopaxi',
        'tipo_unidad': 'Unidad',
        'era': 'Cenozoico',
        'periodo': 'Cuaternario',
        'epoca': 'Pleistoceno-Holoceno',
        'edad_ma_min': 0.0,
        'edad_ma_max': 0.5,
        'region': 'Sierra',
        'provincia_ref': 'Cotopaxi',
        'ambiente_dep': 'Estratovolcán de arco continental; ambiente suprasubducción',
        'litologia_dom': 'Andesitas, dacitas, pumicitas, lahares, ignimbritas',
        'clasificacion_iugs': 'Andesita / Dacita',
        'diagrama_iugs': 'TAS',
        'vertices_diagrama': '{"SiO2_min":57,"SiO2_max":68,"Na2O_K2O_min":3,"Na2O_K2O_max":7}',
        'color_munsell': '10YR 5/2',
        'textura': 'Porfírica; fenocristales de plagioclasa > hornblenda; pasta afanítica',
        'estructura': 'Flujos de lava masivos; depósitos de caída pumícea; lahares',
        'mineralogia': 'Plagioclasa (andesina-oligoclasa), hornblenda, ortopiroxeno',
        'mineralogia_acc': 'Magnetita, ilmenita, apatito, zircón',
        'referencias': 'Hall1977,Hidalgo2007,Garrison2011',
        'notas_campo': 'Estratovolcán calc-alcalino activo. Mayor peligro volcánico de Ecuador. '
            'Series geoquímicas: TAS andesita (57–63% SiO₂) y dacita (63–68% SiO₂). '
            'Geoquímica: La/Yb 10–20; Ba/Nb 50–100 (signatura arco).',
      },

      {
        'codigo': 'VTu',
        'nombre': 'Complejo Volcánico Tungurahua',
        'nombre_informal': 'Tungurahua',
        'tipo_unidad': 'Unidad',
        'era': 'Cenozoico',
        'periodo': 'Cuaternario',
        'epoca': 'Pleistoceno-Holoceno',
        'edad_ma_min': 0.0,
        'edad_ma_max': 0.3,
        'region': 'Sierra',
        'provincia_ref': 'Tungurahua',
        'ambiente_dep': 'Estratovolcán de arco andino',
        'litologia_dom': 'Basaltos andesíticos, andesitas, piroclastos',
        'clasificacion_iugs': 'Basalto andesítico / Andesita basáltica',
        'diagrama_iugs': 'TAS',
        'vertices_diagrama': '{"SiO2_min":52,"SiO2_max":60,"Na2O_K2O_min":3,"Na2O_K2O_max":6}',
        'color_munsell': '2.5Y 3/1',
        'textura': 'Afanítica a porfírica; microporfírica en lavas recientes',
        'estructura': 'Flujos de lava aa y pahoe-hoe; caída escoria; PDC',
        'mineralogia': 'Plagioclasa, clinopiroxeno, olivino, ortopiroxeno',
        'mineralogia_acc': 'Magnetita, apatito',
        'referencias': 'Hall1977,Samaniego2011',
        'notas_campo': 'Erupción continua desde 1999. Composición máfica-intermedia. '
            'SiO₂: 52–60%. Alto contenido de CO₂ y SO₂ magmático.',
      },

      // ── FORMACIÓN HOLLÍN (Jurásico-Cretácico, Oriente) ───────────────────
      {
        'codigo': 'Ho',
        'nombre': 'Formación Hollín',
        'nombre_informal': 'Hollín',
        'tipo_unidad': 'Formación',
        'era': 'Mesozoico',
        'periodo': 'Cretácico Inferior',
        'epoca': 'Aptiano',
        'edad_ma_min': 112.0,
        'edad_ma_max': 125.0,
        'region': 'Oriente',
        'provincia_ref': 'Sucumbíos',
        'ambiente_dep': 'Fluvial a marino transicional; transgresión marina',
        'litologia_dom': 'Areniscas cuarzosas blancas, cuarcitas, conglomerados basales',
        'clasificacion_iugs': 'Ortocuarcita / Arenisca cuarzosa (Folk, 1980)',
        'diagrama_iugs': 'Folk',
        'vertices_diagrama': '{"Qt":95,"F":3,"Lt":2}',
        'color_munsell': '10YR 8/2',
        'textura': 'Grano medio a grueso; bien redondeado; bien clasificado',
        'estructura': 'Estratificación cruzada planar y en artesa; moteado de bioturbación',
        'mineralogia': 'Cuarzo monocristalino (>90%), feldespato potásico subordinado',
        'mineralogia_acc': 'Zircón, turmalina, rutilo (ZTR index alto)',
        'referencias': 'Dashwood1995,Balkwill1995',
        'notas_campo': 'Reservorio de hidrocarburos principal del Oriente ecuatoriano. '
            'Alta madurez textural y mineralógica. Porosidad primaria 15–25%. '
            'Efervescencia con HCl NEGATIVA (puro cuarzo). Color blanco diagnóstico.',
      },

      // ── FORMACIÓN CHALCANA (Mioceno, cuenca intermontañosa) ──────────────
      {
        'codigo': 'Ch',
        'nombre': 'Formación Chalcana',
        'nombre_informal': 'Chalcana',
        'tipo_unidad': 'Formación',
        'era': 'Cenozoico',
        'periodo': 'Neógeno',
        'epoca': 'Mioceno Medio',
        'edad_ma_min': 11.0,
        'edad_ma_max': 16.0,
        'region': 'Sierra',
        'provincia_ref': 'Pichincha',
        'ambiente_dep': 'Cuenca intermontañosa andina; lacustre-fluvial',
        'litologia_dom': 'Tobas, areniscas volcaniclásticas, lutitas lacustres, paleosuelos',
        'clasificacion_iugs': 'Toba riolítica / Ignimbrita',
        'diagrama_iugs': 'TAS',
        'vertices_diagrama': '{"SiO2_min":70,"SiO2_max":78,"Na2O_K2O_min":6,"Na2O_K2O_max":10}',
        'color_munsell': '2.5Y 7/2',
        'textura': 'Vítrea a parcialmente desvitrificada; esquirlas de vidrio (shards)',
        'estructura': 'Estratificación fina; horizontes de paleosuelo; laminación lacustre',
        'mineralogia': 'Vidrio volcánico, cuarzo, sanidina, biotita',
        'mineralogia_acc': 'Zircón, apatito, feldespato plagioclasa',
        'referencias': 'Hungerbuhler2002,Egbue2010',
        'notas_campo': 'Cuencas: Quito, Latacunga, Riobamba. Facies volcaniclásticas. '
            'Útil para datación K/Ar y U-Pb en zircón. '
            'Asociación con actividad caldérica Miocena del arco.',
      },
    ];

    for (final f in formaciones) {
      await db.insert(
        'formaciones',
        f,
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    _log.i('Sembradas ${formaciones.length} formaciones geológicas ecuatorianas');
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SEED: MINERALES INDICADORES
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _seedMineralesIndicadores(DatabaseExecutor db) async {
    final minerales = <Map<String, dynamic>>[
      {
        'nombre': 'Plagioclasa',
        'formula': 'NaAlSi₃O₈ – CaAl₂Si₂O₈',
        'sistema_crist': 'Triclínico',
        'dureza_mohs': 6.0,
        'densidad': 2.65,
        'color_tipico': 'Blanco, gris, verdoso (saussuritización)',
        'brillo': 'Vítreo',
        'exfoliacion': 'Perfecta en 2 direcciones (001) y (010); 86°',
        'notas_id': 'Macla polisintética diagnóstica. Saussuritización en rocas alteradas.',
      },
      {
        'nombre': 'Hornblenda',
        'formula': 'Ca₂(Mg,Fe,Al)₅(Al,Si)₈O₂₂(OH)₂',
        'sistema_crist': 'Monoclínico',
        'dureza_mohs': 5.5,
        'densidad': 3.2,
        'color_tipico': 'Verde oscuro a negro',
        'brillo': 'Vítreo a resinoso',
        'exfoliacion': 'Perfecta en 2 planos a 56° y 124°',
        'notas_id': 'Exfoliación a 60°/120° diagnostica anfibol. Hábito prismático.',
      },
      {
        'nombre': 'Glaucofana',
        'formula': 'Na₂(Mg,Fe²⁺)₃Al₂Si₈O₂₂(OH)₂',
        'sistema_crist': 'Monoclínico',
        'dureza_mohs': 6.0,
        'densidad': 3.1,
        'color_tipico': 'Azul lavanda, azul grisáceo',
        'brillo': 'Vítreo',
        'exfoliacion': 'Perfecta a 56°/124°',
        'notas_id': 'Indicador de facies esquistos azules. Alta presión (>0.6 GPa). '
            'Color azul lavanda ÚNICO entre anfibolitas. Solo en Unidad Peltetec.',
      },
      {
        'nombre': 'Olivino',
        'formula': '(Mg,Fe)₂SiO₄',
        'sistema_crist': 'Ortorrómbico',
        'dureza_mohs': 7.0,
        'densidad': 3.3,
        'color_tipico': 'Verde oliva a amarillo-verde',
        'brillo': 'Vítreo',
        'exfoliacion': 'Imperfecta; fractura concoidal',
        'notas_id': 'Solo en rocas ultramáficas/máficas primitivas. '
            'Serpentinización frecuente (color verde-negro, aspecto grasoso).',
      },
      {
        'nombre': 'Cuarzo',
        'formula': 'SiO₂',
        'sistema_crist': 'Trigonal (hexagonal)',
        'dureza_mohs': 7.0,
        'densidad': 2.65,
        'color_tipico': 'Incoloro, blanco lechoso',
        'brillo': 'Vítreo; graso en fractura',
        'exfoliacion': 'Sin exfoliación; fractura concoidal',
        'notas_id': 'Brillo graso en fractura. No efervescencia con HCl. '
            'Raya el acero. Diagnóstico en areniscas cuarzosas (Hollín).',
      },
      {
        'nombre': 'Calcita',
        'formula': 'CaCO₃',
        'sistema_crist': 'Trigonal',
        'dureza_mohs': 3.0,
        'densidad': 2.71,
        'color_tipico': 'Blanco, incoloro, gris',
        'brillo': 'Vítreo a nacarado',
        'exfoliacion': 'Perfecta romboédrica (3 planos a 75°)',
        'notas_id': 'Efervescencia VIGOROSA con HCl diluido. '
            'Clivaje romboédrico perfecto diagnóstico. Dureza raya con uña de cobre.',
      },
    ];

    for (final m in minerales) {
      await db.insert('minerales', m, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SEED: REFERENCIAS BIBLIOGRÁFICAS Q1/Q2
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _seedReferencias(DatabaseExecutor db) async {
    final refs = <Map<String, dynamic>>[
      {
        'clave': 'Litherland1994',
        'autores': 'Litherland, M., Aspden, J.A., Jemielita, R.A.',
        'anio': 1994,
        'titulo': 'The Metamorphic Belts of Ecuador',
        'revista': 'British Geological Survey, Overseas Memoir 11',
        'doi': null,
        'quartil': 'Libro',
      },
      {
        'clave': 'Spikings2010',
        'autores': 'Spikings, R.A., Cochrane, R., Villagomez, D., Van der Lelij, R., '
            'Vallejo, C., Winkler, W., Beate, B.',
        'anio': 2010,
        'titulo': 'The geological history of northwestern South America: from Pangaea '
            'to the early collision of the Caribbean Large Igneous Province',
        'revista': 'Gondwana Research',
        'volumen': '27, 95–139',
        'doi': '10.1016/j.gr.2014.06.004',
        'quartil': 'Q1',
      },
      {
        'clave': 'Vallejo2009',
        'autores': 'Vallejo, C., Winkler, W., Spikings, R.A., Luzieux, L., '
            'Heller, F., Bussy, F.',
        'anio': 2009,
        'titulo': 'Mode and timing of terrane accretion in the forearc of the Andes '
            'in Ecuador',
        'revista': 'Geological Society of America Memoir',
        'volumen': '204, 197–216',
        'doi': '10.1130/2009.1204(09)',
        'quartil': 'Q1',
      },
      {
        'clave': 'Pratt2005',
        'autores': 'Pratt, W.T., Duque, P., Ponce, M.',
        'anio': 2005,
        'titulo': 'An autochthonous geological model for the eastern Andes of Ecuador',
        'revista': 'Tectonophysics',
        'volumen': '399, 251–278',
        'doi': '10.1016/j.tecto.2004.12.025',
        'quartil': 'Q1',
      },
      {
        'clave': 'Dashwood1995',
        'autores': 'Dashwood, M.F., Abbotts, I.L.',
        'anio': 1995,
        'titulo': 'Aspects of the petroleum geology of the Oriente Basin, Ecuador',
        'revista': 'Geological Society London Special Publications',
        'volumen': '50, 89–117',
        'doi': '10.1144/GSL.SP.1990.050.01.06',
        'quartil': 'Q2',
      },
      {
        'clave': 'Kerr2002',
        'autores': 'Kerr, A.C., White, R.V., Thompson, P.M.E., Tarney, J., Saunders, A.D.',
        'anio': 2002,
        'titulo': 'No oceanic plateau — no Caribbean plate? The seminal role of an '
            'oceanic plateau in Caribbean plate evolution',
        'revista': 'Geological Society of America Special Papers',
        'volumen': '328, 126–168',
        'doi': '10.1130/0-8137-2328-0.126',
        'quartil': 'Q1',
      },
      {
        'clave': 'LeMaitre2002',
        'autores': 'Le Maitre, R.W. (ed.)',
        'anio': 2002,
        'titulo': 'Igneous Rocks: A Classification and Glossary of Terms',
        'revista': 'Cambridge University Press (IUGS)',
        'doi': null,
        'quartil': 'Libro',
      },
      {
        'clave': 'Folk1980',
        'autores': 'Folk, R.L.',
        'anio': 1980,
        'titulo': 'Petrology of Sedimentary Rocks',
        'revista': 'Hemphill Publishing, Austin TX',
        'doi': null,
        'quartil': 'Libro',
      },
    ];

    for (final r in refs) {
      await db.insert('referencias', r, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    _log.i('Sembradas ${refs.length} referencias bibliográficas Q1/Q2');
  }
}
