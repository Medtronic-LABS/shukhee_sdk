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

/// Appointment-level statuses from Shukhee's nested `appointment.status` —
/// distinct from [ShukheeStatus.status]'s outer, lowercase vocabulary.
/// Title-case, matching the vendor's own casing verbatim.
const String kAppointmentScheduled = 'Scheduled';
const String kAppointmentConsultationStarted = 'ConsultationStarted';
const String kAppointmentConsultationEnd = 'ConsultationEnd';
const String kAppointmentCompleted = 'Completed';

/// One entry from [ShukheeClinicalData.medicine].
class ShukheeMedicine {
  const ShukheeMedicine({
    this.dar,
    this.dosage,
    this.duration,
    this.strength,
    this.brandName,
    this.frequency,
    this.genericName,
    this.instruction,
    this.prescriptionMedicineName,
  });

  final String? dar;
  final String? dosage;
  final String? duration;
  final String? strength;
  final String? brandName;
  final String? frequency;
  final String? genericName;
  final String? instruction;
  final String? prescriptionMedicineName;

  // Every field uses ?.toString() rather than `as String?` -- confirmed
  // necessary against real data: the vendor's own sandbox returns some
  // numeric-looking fields (e.g. clinicalData.followUpDay) as a raw JSON
  // number, not a string, and an unsafe cast throws a TypeError that isn't a
  // DioException, so ShukheeClient.pollStatus's own catch clause doesn't
  // catch it -- it aborts the whole poll silently instead of just failing to
  // parse one field. Apply the same defensive parsing everywhere in this
  // model, not just where a numeric value has actually been observed yet.
  factory ShukheeMedicine.fromJson(Map<String, dynamic> json) => ShukheeMedicine(
        dar: json['dar']?.toString(),
        dosage: json['dosage']?.toString(),
        duration: json['duration']?.toString(),
        strength: json['strength']?.toString(),
        brandName: json['brandName']?.toString(),
        frequency: json['frequency']?.toString(),
        genericName: json['genericName']?.toString(),
        instruction: json['instruction']?.toString(),
        prescriptionMedicineName: json['prescriptionMedicineName']?.toString(),
      );
}

/// One entry from [ShukheeClinicalData.mealInstruction].
class ShukheeMealInstruction {
  const ShukheeMealInstruction({this.duration, this.mealType, this.instruction});

  final String? duration;
  final String? mealType;
  final String? instruction;

  factory ShukheeMealInstruction.fromJson(Map<String, dynamic> json) => ShukheeMealInstruction(
        duration: json['duration']?.toString(),
        mealType: json['mealType']?.toString(),
        instruction: json['instruction']?.toString(),
      );
}

/// [ShukheeClinicalData.lastVital] -- vitals as recorded by the doctor at the
/// end of the consultation (distinct from any vitals sent *at booking time*).
class ShukheeVital {
  const ShukheeVital({
    this.temperature,
    this.pulseRate,
    this.respiratoryRate,
    this.bloodPressure,
    this.spo2,
    this.date,
  });

  final String? temperature;
  final String? pulseRate;
  final String? respiratoryRate;
  final String? bloodPressure;
  final String? spo2;
  final String? date;

  factory ShukheeVital.fromJson(Map<String, dynamic> json) => ShukheeVital(
        temperature: json['temperature']?.toString(),
        pulseRate: json['pulseRate']?.toString(),
        respiratoryRate: json['respiratoryRate']?.toString(),
        bloodPressure: json['bloodPressure']?.toString(),
        spo2: json['spo2']?.toString(),
        date: json['date'] as String?,
      );
}

/// The full read-only clinical record for a completed consultation --
/// mirrors Shukhee's `appointment.clinicalData` verbatim. Only ever
/// populated once [ShukheeStatus.status]/[ShukheePrescription] reflects a
/// completed consultation.
class ShukheeClinicalData {
  const ShukheeClinicalData({
    this.chiefComplaints = const [],
    this.diagnosis = const [],
    this.labTest = const [],
    this.advice = const [],
    this.drugHistory = const [],
    this.medicine = const [],
    this.mealInstruction = const [],
    this.lastVital,
    this.followUpComment,
    this.followUpDay,
    this.followUpDate,
  });

  final List<String> chiefComplaints;
  final List<String> diagnosis;
  final List<String> labTest;
  final List<String> advice;
  final List<String> drugHistory;
  final List<ShukheeMedicine> medicine;
  final List<ShukheeMealInstruction> mealInstruction;
  final ShukheeVital? lastVital;
  final String? followUpComment;
  final String? followUpDay;
  final String? followUpDate;

  static List<String> _strList(dynamic value) =>
      (value as List<dynamic>? ?? const []).map((e) => e.toString()).toList();

  factory ShukheeClinicalData.fromJson(Map<String, dynamic> json) => ShukheeClinicalData(
        chiefComplaints: _strList(json['chiefComplaints']),
        diagnosis: _strList(json['diagnosis']),
        labTest: _strList(json['labTest']),
        advice: _strList(json['advice']),
        drugHistory: _strList(json['drugHistory']),
        medicine: (json['medicine'] as List<dynamic>? ?? const [])
            .map((e) => ShukheeMedicine.fromJson(e as Map<String, dynamic>))
            .toList(),
        mealInstruction: (json['mealInstruction'] as List<dynamic>? ?? const [])
            .map((e) => ShukheeMealInstruction.fromJson(e as Map<String, dynamic>))
            .toList(),
        lastVital: json['lastVital'] != null
            ? ShukheeVital.fromJson(json['lastVital'] as Map<String, dynamic>)
            : null,
        followUpComment: json['followUpComment']?.toString(),
        // Confirmed against real data: the vendor sends this as a raw JSON
        // number (e.g. 7), not a string -- see the class-level note above.
        followUpDay: json['followUpDay']?.toString(),
        followUpDate: json['followUpDate']?.toString(),
      );
}

/// One entry from [ShukheeClient.getSpecialities] — field names match
/// Shukhee's own `GET /patient/emergency-request-specialities` response
/// verbatim (`specialityId`, `title`), not a re-keyed shape, so [title] can
/// be sent straight back as [ShukheeClient.startConsultation]'s
/// `requestedSpeciality` with no risk of a translation/relabeling mismatch
/// silently falling back to the wrong speciality server-side.
class ShukheeSpeciality {
  const ShukheeSpeciality({required this.specialityId, required this.title});

  final String specialityId;
  final String title;
}

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
    this.appointmentStatus,
    this.clinicalData,
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

  /// The nested `appointment.status` (Title Case: Scheduled/
  /// ConsultationStarted/ConsultationEnd/Completed) -- distinct from
  /// [status]'s outer, lowercase vocabulary. Gates when a host app should
  /// show the live call view vs. a prescription-in-progress wait -- use
  /// [isConsultationStarted]/[isConsultationEnded], not a raw string compare.
  final String? appointmentStatus;

  /// The vendor's `appointment.clinicalData`, populated once [status] is
  /// `completed`. Null before then, and null on any consultation completed
  /// before this field existed (permanently -- a completed consultation is
  /// never re-polled).
  final ShukheeClinicalData? clinicalData;

  bool get isTerminal => shukheeTerminalStatuses.contains(status);
  bool get isCompleted => status == 'completed';

  /// True once the doctor has actually joined the call (or moved past that
  /// point) -- "at-or-past ConsultationStarted", not an exact-equals check,
  /// so a caller polling less frequently than Shukhee's own state changes
  /// doesn't get stuck waiting for a value it may skip straight over.
  bool get isConsultationStarted =>
      appointmentStatus == kAppointmentConsultationStarted ||
      appointmentStatus == kAppointmentConsultationEnd ||
      appointmentStatus == kAppointmentCompleted;

  /// True once the doctor has ended the consultation (prescription may
  /// still be in progress) -- at-or-past ConsultationEnd, same reasoning as
  /// [isConsultationStarted].
  bool get isConsultationEnded =>
      appointmentStatus == kAppointmentConsultationEnd || appointmentStatus == kAppointmentCompleted;
}

/// Result of [ShukheeClient.getPrescription].
class ShukheePrescription {
  const ShukheePrescription({
    this.prescriptionLink,
    this.invoiceLink,
    this.doctorName,
    this.doctorSpeciality,
    this.doctorFacility,
    this.appointmentStatus,
    this.clinicalData,
  });

  final String? prescriptionLink;
  final String? invoiceLink;
  final String? doctorName;
  final String? doctorSpeciality;
  final String? doctorFacility;
  final String? appointmentStatus;
  final ShukheeClinicalData? clinicalData;
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
