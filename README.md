# My Malaysia Navigator

Aplikasi navigasi percuma untuk Malaysia, dibina dengan Flutter + Mapbox.

## Ciri-ciri
- Peta gelap dengan lokasi semasa anda (titik biru berdenyut)
- Carian destinasi di Malaysia, termasuk tempat terkenal (KLCC, Mid Valley, dll.)
- Laluan memandu dengan trafik semasa, dilukis di peta
- Masa perjalanan, jarak dan waktu tiba yang sebenar
- Arahan belokan demi belokan dalam Bahasa Melayu
- Kamera ikut kereta semasa navigasi (3D), butang "pusat semula"
- Kira semula laluan secara automatik jika tersalah jalan
- Notis "Anda telah tiba"

## Struktur kod (`navigator_app/lib`)
| Fail | Fungsi |
|---|---|
| `main.dart` | Titik mula aplikasi |
| `config.dart` | Token Mapbox, gaya peta, lokasi lalai |
| `navigation_screen.dart` | Skrin utama: peta, carian, navigasi |
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
