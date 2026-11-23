import 'package:flutter/material.dart';

import 'pdf_observation_host.dart';

/// Separate entry. The shelf, catalog, text reader, and scan reader stay on
/// the production `main`.
///
/// ```bash
/// flutter run -t lib/pdf_probe/observation_main.dart
/// ```
void main() {
  runApp(const PdfObservationApp());
}
