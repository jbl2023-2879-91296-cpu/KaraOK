# KaraOK DFD: manual editing guide

Based on commit `b74ceb8`. Path IDs match `karaok-dfd-level-1-unique.png`.

## 1. Keep each symbol unique

Use one **User (guest / signed-in)** entity and one **Administrator** entity. Connect every relevant process to these existing boxes. Draw each process and each store once; do not create duplicate store symbols to shorten a connection.

Guest mode uses audio analysis and local results. Account management and saved amplifier profiles require an account. Guest settings inputs are supplied directly to the recommendation flow; they do not create an owned amplifier-profile record.

## 2. Update the initial diagram

- Remove **Audio Quality Threshold Database**, **Genre Threshold Database**, and the administrator's **Manage Genre Threshold** path.
- Add **F1 Reference Profiles**, a read-only file store. It supplies thresholds and genre targets; it is not an administrator-editable database table.
- Replace the repeated User/Technician symbols with the single User entity.
- Combine initial **3.0 Extract Audio Features** and **4.0 Evaluate Audio Quality** into revised **3.0 Extract Features & Grade Audio**.
- Add revised **4.0 Manage Amplifier Profile**.
- Expand **5.0 Suggest Audio Settings** into **5.0 Recommend & Verify Settings**.
- Combine the initial **6.0** and **7.0** display processes into revised **6.0 View Results & History**.
- Expand initial **8.0 View Assessment Reports** into revised **7.0 Manage Records & Analytics**.
- Replace any direct User-to-database connection with a connection through the appropriate process.

The revised D-number labels are new identifiers. Match stores by name when editing the old DFD.

## 3. Store key

| Store | Contents |
|---|---|
| D1 Users | `user` |
| D2 Sessions & OTP | `refresh_token`, `revoked_access_token`, `registration_otp` |
| D3 Assessments & Results | `assessment`, `audio_upload`, `audio_analysis_result` |
| D4 Amplifier Profiles | `amplifier_profile` |
| D5 Recommendations | `settings_recommendation` |
| D6 Logs | `audit_log`, `api_request_log` |
| F1 Reference Profiles | Versioned quality thresholds, genre targets, control priors; read only |
| F2 Report Images | Server waveform and spectrogram files |
| L1 Guest Records / Cache | Device-local guest results and cached reports |

## 4. New or changed connections

Draw a separate arrow for each direction below. Use the short label on the arrow.

| ID | From | To | Arrow label |
|---|---|---|---|
| S03 | 1.0 Manage Account & Authentication | D2 | Token / OTP changes |
| S04 | D2 | 1.0 | Token / OTP status |
| S05 | 2.0 Capture / Upload Audio | D3 | Upload metadata |
| S06 | 3.0 Extract Features & Grade Audio | D3 | Score / features |
| S07 | F1 | 3.0 | Quality thresholds |
| S08 | 3.0 | F2 | Plots |
| E04 | User | 4.0 Manage Amplifier Profile | Scale / positions |
| E05 | 4.0 | User | Saved profile |
| S09 | 4.0 | D4 | Profile changes |
| S10 | D4 | 4.0 | Profile data |
| E06 | User | 5.0 Recommend & Verify Settings | Genre / settings / status |
| S11 | D4 | 5.0 | Saved scale / positions |
| S12 | F1 | 5.0 | Genre targets / priors |
| P02 | 3.0 | 5.0 | Metrics / new score |
| S13 | 5.0 | D5 | Recommendation / verification |
| S14 | D5 | 5.0 | Prior recommendation |
| E07 | 5.0 | User | Suggested settings |
| E03 | User | 2.0 | Audio / re-record |
| P03 | 3.0 | 6.0 View Results & History | Current result |
| P04 | 5.0 | 6.0 | Settings |
| S16 | D5 | 6.0 | Saved recommendations |
| S17 | F2 | 6.0 | Report images |
| S18 | 6.0 | L1 | Cached report |
| S19 | L1 | 6.0 | Local history |
| E10 | Administrator | 7.0 Manage Records & Analytics | Query / permitted edit |
| E11 | 7.0 | Administrator | Records / analytics |
| S20 | D1 | 7.0 | User records |
| S21 | D3 | 7.0 | Assessment records |
| S22 | D4 | 7.0 | Amplifier records |
| S23 | D5 | 7.0 | Recommendation records |
| S24 | 7.0 | D1 | User status edits |
| S25 | 7.0 | D3 | Assessment edits / deletion |
| S26 | 7.0 | D6 | Audit events |
| S27 | D6 | 7.0 | Logs |

The diagram summarizes API-wide logging with a note: activity from processes 1.0–7.0 writes audit/request metadata to D6. To expand logging explicitly, draw one arrow from each process to the same D6 store; do not duplicate D6.

## 5. Retain and reconnect existing flows

| ID | From | To | Arrow label |
|---|---|---|---|
| E01 | User | 1.0 | Credentials / profile |
| E02 | 1.0 | User | Account / session |
| S01 | 1.0 | D1 | Account changes |
| S02 | D1 | 1.0 | Account data |
| P01 | 2.0 | 3.0 | Audio |
| E08 | User | 6.0 | Report request |
| E09 | 6.0 | User | Scores / plots / settings |
| S15 | D3 | 6.0 | Assessment history |

## 6. Connection rules

- Verification loop: **User → 2.0 → 3.0 → 5.0**. The user adjusts the amplifier manually; the app never controls it.
- Only signed-in assessments and recommendations persist to D3–D5. Completed guest reports stay in L1 and are not imported after login.
- F1 has outgoing read flows only. Do not reconnect administrator threshold editing.
- Administrator mutations are limited by policy: user active status, assessment status, and assessment deletion. D4 and D5 are read-only through the Admin Data API.
- D2 credential records are not readable through the Admin Data API. Do not add D2 → 7.0.
- Settings-profile and recommendation features are disabled by default in the committed configuration; mark 4.0 and 5.0 with the same asterisk.
- Line crossings are not junctions. Do not add join dots unless data flows actually merge.
