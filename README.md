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
- Panduan lorong kiri ke kanan dengan anak panah bagi setiap arah yang tersedia
- Simbol lampu isyarat berdasarkan data persimpangan di sepanjang laluan
- Banding pilihan laluan mengikut masa, jarak dan anggaran tol kereta dalam RM
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

## Anggaran tol kereta Kelas 1

Aplikasi memadankan plaza tol daripada laluan Mapbox dengan kadar awam, tanpa
kunci TollGuru. Kadar masuk/keluar menggunakan [Kadar Tol Malaysia](https://github.com/mohdsyahid/kadar-tol-malaysia),
yang menerbitkan jadual daripada kalkulator Lembaga Lebuhraya Malaysia. Kadar rata
MEX datang daripada [laman pengendali MEX](https://www.mex.com.my/features-and-facilities/toll-operations/).

Laluan elak tol memaparkan RM 0.00. Anggaran bagi laluan bertol hanya dipaparkan
apabila semua plaza dikenal pasti dan padanan kadar adalah jelas. Liputan bergantung
pada maklumat plaza dalam respons Mapbox dan kadar yang tersedia. Kadar boleh
berbeza daripada transaksi sebenar, contohnya pada waktu diskaun.
