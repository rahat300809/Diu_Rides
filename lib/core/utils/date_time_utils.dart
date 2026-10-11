import 'package:intl/intl.dart';

class DateTimeUtils {
  DateTimeUtils._();

  static String formatTime(DateTime time) {
    return DateFormat('hh:mm a').format(time);
  }

  static String formatDate(DateTime date) {
    return DateFormat('EEE, d MMM').format(date);
  }

  static String formatFullDateTime(DateTime dt) {
    return DateFormat('d MMM yyyy, hh:mm a').format(dt);
  }

  static String formatRelativeTime(DateTime dt) {
    final now = DateTime.now();
    final difference = dt.difference(now);

    if (difference.inMinutes <= 0) {
      return 'Departed';
    } else if (difference.inMinutes < 60) {
      return 'Leaving in ${difference.inMinutes}m';
    } else if (difference.inHours < 24) {
      return 'Leaving in ${difference.inHours}h';
    } else {
      return formatDate(dt);
    }
  }
}
