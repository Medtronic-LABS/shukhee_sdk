## 0.5.0

* **Breaking:** `ShukheeClient.startConsultation`'s `medias`/`documentType` params are replaced
  by a single `mediaGroups` (`Map<String, List<ShukheeMediaFile>>`, keyed by
  `'prescription' | 'lab_report' | 'other'`) -- lets a host app attach both a prescription
  *and* a lab report in the same booking. Each group is sent as its own repeated
  `medias_<type>` multipart field (Shukhee's own upload API only accepts one `type` per
  call, so the backend now makes one upload call per non-empty group instead of one call
  for everything).

## 0.4.0

* `ShukheeClient.startConsultation` gains `medias` (`List<ShukheeMediaFile>`) and
  `documentType` (`'prescription' | 'lab_report' | 'other'`, default `'other'`) --
  forwards to the backend's already-accepted `medias` multipart field and its now-accepted
  `document_type` field, so a host app can attach up to a few prescription/lab-report photos
  at booking time instead of only after the fact.
* Add `ShukheeMediaFile` — plain filename + bytes + optional mime type, deliberately not tied
  to any particular picker package.
* Add `ShukheeClient.getSpecialities`/`ShukheeSpeciality` — live specialities from Shukhee's
  own `GET /patient/emergency-request-specialities` (via the backend's new `get_specialities`
  endpoint), so a booking form can offer the real, current speciality list instead of a
  hardcoded guess that could silently drift out of sync with Shukhee's own data.

## 0.3.0

* `ShukheeStatus`/`ShukheePrescription` gain `doctorName`/`doctorSpeciality`/`doctorFacility` --
  Shukhee assigns a doctor to the request (sometimes before the call reaches a terminal
  status), and the backend now surfaces those fields instead of discarding them.
* `ShukheeClient.pollStatus` gains an optional `onUpdate` callback, fired after every
  attempt (not just the final terminal/exhausted result) -- lets a caller react to a
  mid-call change (e.g. a doctor being assigned) without waiting for the whole poll loop
  to finish.

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
