# My Malaysia Navigator

Aplikasi navigasi percuma untuk Malaysia, dibina dengan Flutter + Mapbox.

## Ciri-ciri
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


## Anggaran tol

Aplikasi meminta laluan alternatif dan laluan dengan tetapan elak tol daripada Mapbox.
Laluan tanpa tol memaparkan RM 0.00. Harga untuk laluan lain menggunakan anggaran
minimum TollGuru bagi kereta penumpang dua gandar, jika tersedia dalam MYR.

Untuk membolehkan anggaran harga, terbitkan `services/toll_quote.mjs` sebagai
Cloudflare Worker dan simpan `TOLLGURU_API_KEY` sebagai rahsia Worker. Tetapkan
had kadar pada endpoint sebelum menggunakannya pada APK awam. Simpan URL HTTPS
Worker dalam pemboleh ubah repositori GitHub Actions `TOLL_QUOTE_URL`.
Binaan tempatan menerima `--dart-define=TOLL_QUOTE_URL=https://...`.

Apabila endpoint diaktifkan, aplikasi menghantar bentuk laluan yang dipilih
Mapbox kepada Worker untuk mendapatkan harga. Tanpa endpoint atau apabila
penyedia tiada harga untuk laluan tersebut, aplikasi memaparkan bahawa caj
tidak tersedia.
