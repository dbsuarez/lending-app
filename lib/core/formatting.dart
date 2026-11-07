import 'package:intl/intl.dart';

final _peso = NumberFormat.currency(
  locale: 'en_PH',
  symbol: '₱',
  decimalDigits: 2,
);
String formatPeso(int centavos) => _peso.format(centavos / 100);
String formatPhilippineDate(DateTime date) =>
    DateFormat('yyyy-MM-dd').format(date);
String formatPhilippineDateTime(DateTime dateTime) =>
    DateFormat('yyyy-MM-dd HH:mm').format(dateTime);
