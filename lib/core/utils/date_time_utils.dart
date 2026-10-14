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

  static String formatPostingTime(DateTime? dt) {
    if (dt == null) return 'Posted recently';
    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.isNegative || diff.inSeconds < 45) {
      return 'Just now';
    } else if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m ago';
    } else if (diff.inHours < 24 && dt.day == now.day) {
      return 'Today, ${formatTime(dt)}';
    } else if (diff.inHours < 48 && dt.day == now.subtract(const Duration(days: 1)).day) {
      return 'Yesterday, ${formatTime(dt)}';
    } else {
      return DateFormat('d MMM, hh:mm a').format(dt);
    }
  }
}
