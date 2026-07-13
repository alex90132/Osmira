/// Small presentation helpers shared across screens.
library;

String formatBytes(int bytes) {
  if (bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final precision = value >= 100 || unit == 0 ? 0 : 1;
  return '${value.toStringAsFixed(precision)} ${units[unit]}';
}

/// Human "x seconds/minutes ago" for a unix-epoch handshake timestamp.
String formatHandshakeAgo(int epochSeconds) {
  if (epochSeconds <= 0) return 'нет рукопожатия';
  final then = DateTime.fromMillisecondsSinceEpoch(epochSeconds * 1000);
  final diff = DateTime.now().difference(then);
  if (diff.inSeconds < 5) return 'только что';
  if (diff.inSeconds < 60) return '${diff.inSeconds} с назад';
  if (diff.inMinutes < 60) return '${diff.inMinutes} мин назад';
  if (diff.inHours < 24) return '${diff.inHours} ч назад';
  return '${diff.inDays} дн назад';
}
