# GeoLens Pro — Guía de Compilación y Despliegue
# Android (APK / Google Play Store)

## ═══════════════════════════════════════════════════════════
## 1. PRERREQUISITOS DE ENTORNO
## ═══════════════════════════════════════════════════════════

# Flutter SDK (canal stable ≥ 3.16)
flutter --version
# Requerido: Flutter 3.16.x + Dart 3.2.x

# Android SDK
# - API Level mínimo: 24 (Android 7.0 Nougat)
# - API Level objetivo: 34 (Android 14)
# - Build Tools: 34.0.0
# - NDK: 25.1.8937393 (para tflite_flutter)

# JDK 17 (OpenJDK recomendado)
java -version   # Verificar: openjdk 17.x.x

# Gradle Wrapper: 8.2 (configurado en android/gradle/wrapper/)
# CMake: 3.22.1 (para compilación nativa TFLite)


## ═══════════════════════════════════════════════════════════
## 2. CONFIGURACIÓN ANDROID
## ═══════════════════════════════════════════════════════════

# android/app/build.gradle
# ───────────────────────────────────────
# android {
#     compileSdk 34
#
#     defaultConfig {
#         applicationId "ec.geoiige.geolens_pro"
#         minSdk 24
#         targetSdk 34
#         versionCode 1
#         versionName "1.0.0"
#
#         # Para TFLite (evitar compresión del modelo)
#         aaptOptions {
#             noCompress "tflite"
#             noCompress "lite"
#         }
#     }
#
#     # Firma de release
#     signingConfigs {
#         release {
#             keyAlias    keystoreProperties['keyAlias']
#             keyPassword keystoreProperties['keyPassword']
#             storeFile   file(keystoreProperties['storeFile'])
#             storePassword keystoreProperties['storePassword']
#         }
#     }
#
#     buildTypes {
#         release {
#             signingConfig signingConfigs.release
#             minifyEnabled true
#             proguardFiles getDefaultProguardFile('proguard-android.txt'),
#                          'proguard-rules.pro'
#         }
#     }
#
#     # Soporte NNAPI (aceleración hardware para TFLite)
#     packagingOptions {
#         pickFirst '**/*.so'
#     }
#
#     # ABI filters (reduce tamaño APK)
#     splits {
#         abi {
#             enable true
#             reset()
#             include "armeabi-v7a", "arm64-v8a", "x86_64"
#             universalApk true    # APK universal como fallback
#         }
#     }
# }

# android/app/proguard-rules.pro (para TFLite)
# ───────────────────────────────────────
# -keep class org.tensorflow.** { *; }
# -keep class org.tensorflow.lite.** { *; }
# -dontwarn org.tensorflow.**


## ═══════════════════════════════════════════════════════════
## 3. PERMISOS AndroidManifest.xml
## ═══════════════════════════════════════════════════════════

# android/app/src/main/AndroidManifest.xml → dentro de <manifest>:
#
# <!-- GPS — georreferenciación UTM campo -->
# <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
# <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
#
# <!-- Cámara — captura petrográfica -->
# <uses-permission android:name="android.permission.CAMERA"/>
# <uses-feature android:name="android.hardware.camera" android:required="true"/>
# <uses-feature android:name="android.hardware.camera.autofocus" android:required="false"/>
#
# <!-- Almacenamiento — exportación fichas PDF -->
# <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE"
#     android:maxSdkVersion="29"/>
# <uses-permission android:name="android.permission.READ_MEDIA_IMAGES"/>
#
# <!-- NNAPI para aceleración TFLite -->
# <uses-feature android:name="android.software.nnapi" android:required="false"/>


## ═══════════════════════════════════════════════════════════
## 4. GENERACIÓN DE KEYSTORE (PRIMERA VEZ SOLAMENTE)
## ═══════════════════════════════════════════════════════════

# Generar keystore de producción (GUARDAR EN LUGAR SEGURO — NO en el repo)
keytool -genkey -v \
  -keystore ~/keystores/geolens_pro_release.jks \
  -alias geolens_pro \
  -keyalg RSA \
  -keysize 4096 \
  -validity 10000 \
  -dname "CN=GeoLens Pro, OU=Geologia, O=IIGE-Ecuador, L=Quito, S=Pichincha, C=EC"

# Crear archivo de propiedades (NO incluir en .gitignore)
# android/key.properties:
# storePassword=<CONTRASEÑA_KEYSTORE>
# keyPassword=<CONTRASEÑA_ALIAS>
# keyAlias=geolens_pro
# storeFile=/home/user/keystores/geolens_pro_release.jks


## ═══════════════════════════════════════════════════════════
## 5. MODELO TFLITE — PREPARACIÓN
## ═══════════════════════════════════════════════════════════

# El modelo debe colocarse en:
# assets/models/geolens_ecuador_v1.tflite
#
# Proceso de entrenamiento recomendado:
# ──────────────────────────────────────
# 1. Dataset: ~500-2000 imágenes por clase (10 clases)
#    Fuentes: colecciones IIGE, muestras de campo georreferenciadas
#
# 2. Base model: MobileNetV3-Large (ImageNet pretrained)
#    Fine-tuning en TensorFlow/Keras:
#
#    base = tf.keras.applications.MobileNetV3Large(
#        input_shape=(224, 224, 3), include_top=False, weights='imagenet'
#    )
#    base.trainable = True  # Fine-tuning completo (última mitad)
#    for layer in base.layers[:100]: layer.trainable = False
#
#    model = tf.keras.Sequential([
#        base,
#        tf.keras.layers.GlobalAveragePooling2D(),
#        tf.keras.layers.Dropout(0.3),
#        tf.keras.layers.Dense(10, activation='softmax')  # 10 clases IUGS
#    ])
#
# 3. Exportar a TFLite con cuantización float16:
#
#    converter = tf.lite.TFLiteConverter.from_keras_model(model)
#    converter.optimizations = [tf.lite.Optimize.DEFAULT]
#    converter.target_spec.supported_types = [tf.float16]
#    tflite_model = converter.convert()
#    with open('geolens_ecuador_v1.tflite', 'wb') as f:
#        f.write(tflite_model)
#
# Tamaño esperado del modelo: ~8-12 MB (float16)
# Precisión objetivo: >85% accuracy en test set balanceado


## ═══════════════════════════════════════════════════════════
## 6. COMANDOS DE COMPILACIÓN
## ═══════════════════════════════════════════════════════════

# Limpiar build anterior
flutter clean

# Obtener dependencias
flutter pub get

# Generar código (si se usa build_runner)
dart run build_runner build --delete-conflicting-outputs

# ── APK de desarrollo (debug) ─────────────────────────────
flutter build apk --debug

# ── APK universal release (para distribución directa) ─────
flutter build apk --release \
  --target-platform android-arm,android-arm64,android-x64 \
  --split-per-abi

# Salida APKs:
# build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk  (~25 MB)
# build/app/outputs/flutter-apk/app-arm64-v8a-release.apk    (~28 MB)
# build/app/outputs/flutter-apk/app-x86_64-release.apk       (~30 MB)
# build/app/outputs/flutter-apk/app-release.apk              (universal)

# ── Android App Bundle (AAB) para Google Play ─────────────
# OBLIGATORIO para publicación en Play Store desde agosto 2021
flutter build appbundle --release

# Salida: build/app/outputs/bundle/release/app-release.aab


## ═══════════════════════════════════════════════════════════
## 7. GUÍA DE PUBLICACIÓN EN GOOGLE PLAY
## ═══════════════════════════════════════════════════════════

# PASO 1: Crear cuenta de desarrollador
# ─────────────────────────────────────
# URL: https://play.google.com/console
# Tarifa única: USD 25
# Organización: IIGE (Instituto de Investigación Geológico del Ecuador)
# Correo de contacto: geolens@iige.gob.ec (recomendado)

# PASO 2: Crear aplicación en Play Console
# ─────────────────────────────────────────
# Nombre de la app:      GeoLens Pro — Ecuador
# Idioma predeterminado: Español (es-419 — Latinoamérica)
# Tipo:                  Aplicación
# Categoría:             Herramientas / Ciencia
# Gratis/pago:           Gratis (o de pago, según política del IIGE)
# Datos de contacto:     Correo institucional obligatorio

# PASO 3: Clasificación de contenido (Content Rating)
# ─────────────────────────────────────────────────────
# Clasificación esperada: E (Everyone) / Todo público
# Cuestionario IARC:
#   - Sin contenido violento
#   - Sin lenguaje adulto
#   - Sin interacción de usuario (no red social)
#   - Acceso a ubicación: SÍ (justificar: georreferenciación científica de campo)
#   - Acceso a cámara: SÍ (identificación de muestras petrográficas)
# IARC Género esperado: PEGI 3 / Google: Todo público

# PASO 4: Política de privacidad (OBLIGATORIA)
# ─────────────────────────────────────────────
# Requerida porque la app accede a UBICACIÓN y CÁMARA.
# Puntos OBLIGATORIOS a incluir:
#
# ┌──────────────────────────────────────────────────────────────┐
# │  DATOS RECOLECTADOS:                                         │
# │  • Ubicación GPS — SOLO procesada localmente (offline)       │
# │  • Fotos de muestras — SOLO almacenadas en el dispositivo    │
# │  • NO se transmite ningún dato a servidores externos         │
# │  • Toda la inferencia de IA ocurre en el dispositivo         │
# │                                                              │
# │  DATOS NO RECOLECTADOS:                                      │
# │  • Identificadores de publicidad                             │
# │  • Datos biométricos                                         │
# │  • Datos de uso/analytics (sin telemetría)                   │
# └──────────────────────────────────────────────────────────────┘
#
# Hospedar la política en: https://iige.gob.ec/geolens-privacy
# O usar GitHub Pages si el IIGE no tiene servidor web.

# PASO 5: Ficha de Play Store
# ─────────────────────────────
# Título (≤30 chars):  "GeoLens Pro Ecuador"
# Descripción corta:   "Identifica rocas offline con IA. Geología ecuatoriana."
# Descripción larga:   [Ver plantilla abajo]
# Capturas de pantalla: Mínimo 2 (recomendado 4-8)
#   - 1. Pantalla de clasificación (resultado con confianza)
#   - 2. Diagrama TAS con punto de muestra
#   - 3. Formulario de campo (Munsell, UTM, mineralogía)
#   - 4. Mapa de formaciones geológicas
# Ícono (512×512 px):  Logo GeoLens Pro
# Imagen destacada (1024×500 px): Banner geológico Ecuador

# ── PLANTILLA DESCRIPCIÓN LARGA (≤4000 chars) ────────────────
# GeoLens Pro es una herramienta petrográfica de precisión diseñada
# para geólogos que trabajan en Ecuador. Funciona completamente
# offline — sin conexión a internet requerida.
#
# CLASIFICACIÓN OFFLINE CON IA
# Motor de reconocimiento basado en TensorFlow Lite, entrenado
# específicamente con rocas del arco volcánico ecuatoriano y cuencas
# sedimentarias del Oriente. Clasifica 10 tipos de rocas según la
# nomenclatura IUGS (Le Maitre et al., 2002).
#
# BASE DE CONOCIMIENTO GEOLÓGICO ECUATORIANO
# Incluye ontología de formaciones del Mapa Geológico Nacional (IIGE):
# Formación Piñón, Unidad Peltetec, Grupo Napo, Formación Hollín,
# Complejo Volcánico Cotopaxi, Formación Chalcana y más.
#
# GEORREFERENCIACIÓN UTM
# Soporte nativo para coordenadas UTM Zonas 17N, 17S y 18S (WGS84),
# incluyendo territorio continental e insular (Galápagos).
#
# DIAGRAMAS DE CLASIFICACIÓN TÉCNICA
# • Diagrama TAS (Le Bas et al., 1986) para rocas volcánicas
# • Triángulo QAPF de Streckeisen para plutónicas e intrusivas
# • Diagrama de Folk (1980) para rocas sedimentarias
#
# REGISTRO DE CAMPO CIENTÍFICO
# • Color Munsell, textura, estructura
# • Mineralogía principal y accesoria
# • Referencias bibliográficas Q1/Q2 (Litherland, Spikings, Pratt...)
# • Exportación de fichas en PDF
#
# TECNOLOGÍA ZERO-CONNECTIVITY
# Todo el motor de IA y la base de datos de formaciones están
# embebidos en la aplicación. Ideal para trabajo en campo remoto
# en la Amazonía o los Andes.
#
# PARA GEÓLOGOS PROFESIONALES
# Desarrollado con literatura científica indexada (Q1/Q2) y datos
# del Instituto de Investigación Geológico y Energético del Ecuador.

# PASO 6: Permisos sensibles — Declaración
# ─────────────────────────────────────────
# En Play Console → Contenido de la app → Permisos:
# 
# UBICACIÓN:
#   Tipo: Primer plano (foreground)
#   Justificación: "Georreferenciación de muestras petrográficas de campo.
#                   Las coordenadas WGS84/UTM se almacenan localmente.
#                   No se comparten con terceros."
#
# CÁMARA:
#   Justificación: "Captura de imágenes de muestras de rocas para
#                   clasificación petrográfica offline mediante IA.
#                   Las imágenes no se transmiten fuera del dispositivo."

# PASO 7: Revisión y publicación
# ───────────────────────────────
# Tiempo de revisión: 1-7 días hábiles (promedio 3 días)
# Canal recomendado para primera publicación: Canal de prueba cerrada
#   → Invitar 20+ testers (geólogos del IIGE/universidades)
#   → Mínimo 14 días en prueba cerrada
#   → Luego solicitar acceso a producción
# Canal de producción: Una vez aprobado por la revisión de Google

# PASO 8: Actualizaciones
# ────────────────────────
# Incrementar versionCode en build.gradle con cada release
# Actualizar CHANGELOG.md con cambios en el modelo o la BD geológica
# Firma: SIEMPRE usar el mismo keystore (no reemplazable sin pérdida de usuarios)


## ═══════════════════════════════════════════════════════════
## 8. VERIFICACIÓN PRE-RELEASE
## ═══════════════════════════════════════════════════════════

# Análisis estático
flutter analyze

# Tests unitarios
flutter test

# Test de integración en dispositivo físico (preferible Snapdragon/MediaTek)
flutter drive --target=test_driver/app.dart

# Verificar tamaño del bundle
flutter build appbundle --analyze-size

# Verificar que el modelo TFLite no está comprimido en el APK
unzip -l build/app/outputs/bundle/release/app-release.aab | grep tflite

# Benchmark offline (importante: sin conexión a internet)
# 1. Activar modo avión en el dispositivo
# 2. Abrir la app
# 3. Capturar foto de una roca
# 4. Verificar clasificación exitosa (<3 segundos en dispositivo mid-range)

echo "Guía de despliegue GeoLens Pro — IIGE Ecuador — v1.0"
echo "Contacto técnico: geolens@iige.gob.ec"
