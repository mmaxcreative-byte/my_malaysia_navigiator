/// Tetapan aplikasi.
///
/// Token Mapbox boleh ditukar semasa build tanpa ubah kod:
///   flutter build apk --dart-define=MAPBOX_TOKEN=pk.xxxx
/// Jika tidak diberi, token lalai di bawah digunakan.
/// (Token "pk." ialah token awam — selamat untuk aplikasi, tetapi
/// sebaiknya hadkan penggunaannya di akaun Mapbox anda.)
const String kMapboxToken = String.fromEnvironment(
  'MAPBOX_TOKEN',
  defaultValue:
      'pk.eyJ1IjoibW1heC1jcmVhdGl2ZSIsImEiOiJjbXdtZGp2eXQwNDB2MnpxMHpsN3VkNmg3In0.hY_Oosug2VtnJw2HF-VSJg',
);

/// Gaya peta (mod gelap).
const String kMapStyle = 'mapbox://styles/mapbox/dark-v11';

/// Lokasi lalai jika GPS belum tersedia: Kuala Lumpur.
const double kDefaultLat = 3.1390;
const double kDefaultLng = 101.6869;
