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
    this.doctorName,
    this.doctorSpeciality,
    this.doctorFacility,
  });

  final String status;
  final String? prescriptionLink;
  final String? invoiceLink;

  /// Populated once Shukhee assigns a doctor to the request -- this can
  /// happen before the call reaches a terminal status, so it may already be
  /// non-null on a non-terminal poll. Null until then.
  final String? doctorName;

  /// From Shukhee's `doctor.specialty.title`.
  final String? doctorSpeciality;

  /// From Shukhee's `doctor.working_at` -- a raw facility code (e.g. "DMC"),
  /// not a formatted facility name. Shown as-is by convention; do not
  /// reformat it into something that looks like a real facility name.
  final String? doctorFacility;

  bool get isTerminal => shukheeTerminalStatuses.contains(status);
  bool get isCompleted => status == 'completed';
}

/// Result of [ShukheeClient.getPrescription].
class ShukheePrescription {
  const ShukheePrescription({
    this.prescriptionLink,
    this.invoiceLink,
    this.doctorName,
    this.doctorSpeciality,
    this.doctorFacility,
  });

  final String? prescriptionLink;
  final String? invoiceLink;
  final String? doctorName;
  final String? doctorSpeciality;
  final String? doctorFacility;
}

/// Result of [ShukheeClient.downloadDocument] — the actual bytes of a
/// completed consultation's prescription or invoice. The backend stores
/// these as private files with no unauthenticated web access, so the host
/// app fetches bytes here (rather than treating [ShukheeStatus.prescriptionLink]/
/// [ShukheeStatus.invoiceLink] as directly-openable URLs) and is expected to
/// render/open them itself, e.g. with an in-app PDF viewer.
class ShukheeDocument {
  const ShukheeDocument({required this.filename, required this.bytes});

  final String filename;
  final List<int> bytes;
}

/// An in-memory file to attach to [ShukheeClient.startConsultation] (e.g. a
/// photographed prescription or lab report). Deliberately plain bytes +
/// filename rather than a Flutter-picker type (`XFile`) or a `dio`-specific
/// type (`MultipartFile`) — this package has no dependency on any particular
/// picker, and a host app can construct one trivially in tests without
/// touching disk.
class ShukheeMediaFile {
  const ShukheeMediaFile({
    required this.filename,
    required this.bytes,
    this.mimeType,
  });

  final String filename;
  final List<int> bytes;

  /// e.g. `'image/jpeg'`. Null lets the underlying HTTP client infer a type
  /// from [filename].
  final String? mimeType;
}
