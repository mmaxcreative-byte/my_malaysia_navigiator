# My Malaysia Navigator

Aplikasi navigasi percuma untuk Malaysia, dibina dengan Flutter + Mapbox.

## Ciri-ciri
- Paparan navigasi baharu: papan tanda biru (destinasi & nombor EXIT), anak panah lorong, bar ETA, nama jalan semasa
- Ikon lokasi berbentuk anak panah yang berpusing ikut arah kenderaan
- Peta 3D (Mapbox Standard) dengan pencahayaan siang/malam
- Peta navigasi siang/malam (auto ikut waktu, atau pilih sendiri)
- Lapisan trafik & insiden langsung di peta
- Laluan diwarnakan ikut kesesakan (biru lancar, oren perlahan, merah sesak)
- Amaran insiden di hadapan: kemalangan, kerja jalan, jalan ditutup, cuaca/banjir
- Arahan suara Bahasa Melayu (sandaran: suara Indonesia jika BM tiada)
- Panduan lorong (anak panah lorong) bila data tersedia
- Laju semasa + had laju (bila data tersedia)
- Cari stesen minyak berdekatan atau di sepanjang laluan, dan singgah
- Skrin kekal menyala semasa aplikasi dibuka
- Susun atur khas untuk telefon melintang (landscape)
- Kira semula laluan automatik jika tersalah jalan

## Struktur kod (`navigator_app/lib`)
| Fail | Fungsi |
|---|---|
| `main.dart` | Titik mula aplikasi |
| `config.dart` | Token Mapbox, gaya peta, lokasi lalai |
| `navigation_screen.dart` | Skrin utama: peta, carian, navigasi, suara |
| `widgets.dart` | Komponen paparan (kad arahan, lorong, laju, ringkasan) |
| `voice.dart` | Suara arahan (Text-to-Speech) |
| `puck.dart` | Ikon anak panah lokasi |
| `app_theme.dart` | Tema siang/malam |
| `mapbox_api.dart` | Panggilan API carian & laluan Mapbox |
| `instructions_ms.dart` | Arahan Bahasa Melayu & format jarak/masa |
| `geo_utils.dart` | Kiraan jarak (haversine, terkeluar laluan) |
| `models.dart` | Kelas data |

## Bina APK
APK dibina automatik oleh GitHub Actions (`.github/workflows/bina-apk.yml`)
setiap kali anda push. Muat turun dari tab **Actions → run terkini → Artifacts → navigator-apk**.

Atau di Codespaces:
```bash
cd navigator_app
flutter pub get
flutter test
flutter build apk --release
```

Tukar token Mapbox tanpa ubah kod:
```bash
flutter build apk --release --dart-define=MAPBOX_TOKEN=pk.xxxxx
```
