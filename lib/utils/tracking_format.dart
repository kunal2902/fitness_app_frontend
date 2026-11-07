String formatTrackingDuration(Duration value) {
  final int hours = value.inHours;
  final int minutes = value.inMinutes.remainder(60);
  final int seconds = value.inSeconds.remainder(60);
  if (hours > 0) {
    return '${hours.toString().padLeft(2, '0')}:'
        '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }
  return '${minutes.toString().padLeft(2, '0')}:'
      '${seconds.toString().padLeft(2, '0')}';
}

String formatTrackingPace(double? secondsPerKm) {
  if (secondsPerKm == null || !secondsPerKm.isFinite || secondsPerKm <= 0) {
    return '—';
  }
  final int rounded = secondsPerKm.round();
  final int minutes = rounded ~/ 60;
  final int seconds = rounded.remainder(60);
  return '$minutes:${seconds.toString().padLeft(2, '0')} /km';
}

String formatTrackingDistance(double metres) {
  if (!metres.isFinite || metres <= 0) return '0.00 km';
  return '${(metres / 1000).toStringAsFixed(2)} km';
}

String formatActivityDate(DateTime value) {
  const List<String> months = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final DateTime local = value.toLocal();
  final int hour = local.hour == 0
      ? 12
      : local.hour > 12
          ? local.hour - 12
          : local.hour;
  final String minute = local.minute.toString().padLeft(2, '0');
  final String period = local.hour >= 12 ? 'PM' : 'AM';
  return '${local.day} ${months[local.month - 1]} · $hour:$minute $period';
}
