## 0.3.0

* `ShukheeStatus`/`ShukheePrescription` gain `doctorName`/`doctorSpeciality`/`doctorFacility` --
  Shukhee assigns a doctor to the request (sometimes before the call reaches a terminal
  status), and the backend now surfaces those fields instead of discarding them.

## 0.2.0

* Add `ShukheeClient.downloadDocument`/`ShukheeDocument` — prescription/invoice files are
  private on the backend (no unauthenticated web access), so `ShukheeStatus.prescriptionLink`/
  `invoiceLink` are no longer directly openable URLs; fetch bytes via this method (same
  bearer-token auth as every other call) and open them from local storage instead.
* Fix: `startConsultation` now coerces a numeric `call_log` (the `Call Logs` doctype uses
  `autoname: "autoincrement"`, so its name can come back as a JSON number) to a string
  instead of crashing on the cast.

## 0.1.0

* Initial release: `ShukheeClient` (`startConsultation`/`pollStatus`/`getPrescription`, scoped to the
  `shukhee_integration` backend's 3 consultation endpoints), `ShukheeConfig`, `ShukheeCallView` (top-level
  WebView video-call embed), and `ShukheeException` subclasses.
