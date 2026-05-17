import 'package:flutter/foundation.dart';

final ValueNotifier<int> favoritesRevision = ValueNotifier<int>(0);

void notifyFavoritesChanged() {
  favoritesRevision.value = favoritesRevision.value + 1;
}
