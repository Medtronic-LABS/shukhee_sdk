/// Value types returned by [ShukheeClient]. Plain, immutable, no
/// dependency on any host app's model layer.
library;

/// Statuses the backend (mirroring Shukhee's own vocabulary) considers
/// final — nothing further will change once one of these is reached.
/// Matches `_TERMINAL_STATUSES` in the backend's `consultation.py`.
const Set<String> shukheeTerminalStatuses = {
  'completed',
  'rejected',
  'cancelled',
  'on-hold',
};

/// Result of [ShukheeClient.startConsultation].
class ShukheeBooking {
  const ShukheeBooking({
    required this.callLog,
    required this.callUrl,
    required this.status,
  });

  /// The `Call Logs` doctype record name — pass this to [ShukheeClient.pollStatus]
  /// and [ShukheeClient.getPrescription].
  final String callLog;

  /// The Shukhee join URL. Must be loaded as a genuine top-level navigation
  /// (see [ShukheeCallView]) — never embedded in an `<iframe>`, which breaks
  /// the join (Shukhee's video-call app relies on a first-party session
  /// cookie a cross-origin iframe cannot carry).
  final String callUrl;

  final String status;

  bool get isTerminal => shukheeTerminalStatuses.contains(status);
}

/// Result of [ShukheeClient.pollStatus] (and the terminal shape of
/// [ShukheeClient.getPrescription]).
class ShukheeStatus {
  const ShukheeStatus({
    required this.status,
    this.prescriptionLink,
    this.invoiceLink,
  });

  final String status;
  final String? prescriptionLink;
  final String? invoiceLink;

  bool get isTerminal => shukheeTerminalStatuses.contains(status);
  bool get isCompleted => status == 'completed';
}

/// Result of [ShukheeClient.getPrescription].
class ShukheePrescription {
  const ShukheePrescription({this.prescriptionLink, this.invoiceLink});

  final String? prescriptionLink;
  final String? invoiceLink;
}

/// Result of [ShukheeClient.downloadDocument] — the actual bytes of a
/// completed consultation's prescription or invoice. The backend stores
/// these as private files with no unauthenticated web access, so the host
/// app is expected to write [bytes] to local storage and open it with a
/// platform file viewer, rather than treat [ShukheeStatus.prescriptionLink]/
/// [ShukheeStatus.invoiceLink] as directly-openable URLs.
class ShukheeDocument {
  const ShukheeDocument({required this.filename, required this.bytes});

  final String filename;
  final List<int> bytes;
}
