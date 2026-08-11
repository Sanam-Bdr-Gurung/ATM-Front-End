# Device Validation Protocol — Physical Samsung Device

Fill in PASS / FAIL / NOTES per line. Do not mark PASS for anything not
actually performed on the device. Results here are the source for the thesis's
device-validation status (Ch5 §5.8.1); keep this file under version control
after filling it in.

Tester: Sanam Gurung  Date: 2026-08-11
Device model / Android version: Samsung phone (model/Android version: fill in)
App commit: 259cd3e (includes re-record fix e9223d7)  Backend commit: 201434b

**Result summary (recorded from Sanam's attestation, 2026-08-11 evening):**
all scenarios A-H PASS on the physical Samsung device with the validated
build. Specific observations are noted under scenarios C and D below; rows
without individual notes passed without observations. The re-recording
defect found during this session was fixed in `e9223d7` and re-validated
before these results were recorded.

## 0. Setup (exact commands)

On the Mac (backend host):

```bash
cd ~/Documents/sanam/thesis/chordassist/backend && .venv/bin/uvicorn api:app --host 0.0.0.0 --port 8000
```

Find the Mac's LAN IP (phone and Mac must be on the same Wi-Fi):

```bash
ipconfig getifaddr en0
```

Verify the backend is reachable at the LAN address (replace IP):

```bash
curl -s http://$(ipconfig getifaddr en0):8000/health
```

Build and install the app pointing at the LAN backend (replace IP; USB
debugging enabled on the phone):

```bash
cd ~/Documents/sanam/thesis/chordassist/frontend/chords_finder && flutter build apk --debug --dart-define=CHORD_API_BASE_URL=http://REPLACE_WITH_MAC_IP:8000 && flutter install
```

Notes:
- The app's launcher label is **"Chord Assist"** — assistant phrase is "Open
  Chord Assist". (Product/UI name: ChordAssist.)
- If Bixby consistently fails to recognize "Chord Assist" because of the
  tester's pronunciation, record this as an **accessibility observation**. A
  personal Bixby Quick Command (e.g. "open my thesis") may be tested as a
  system-level fallback, but it is not the application's canonical name.
  Do not mark that fallback as required or verified until actually tested.
- First analysis after backend start is slower (one-time CoreML model load).
- To reset to a true first launch: Settings → Apps → Chord Assist → Storage →
  Clear data, and Permissions → Microphone → Remove/Deny; or
  `adb shell pm clear com.chords.finder.chords_finder`.

## Scenario A — True first launch

Precondition: cleared app data + revoked microphone permission.

| Step | Expected | PASS/FAIL | Notes |
|---|---|---|---|
| Say "Hi Bixby, open Chord Assist" | App launches from assistant | PASS | |
| App speaks intro BEFORE any permission dialog | Spoken explanation of upcoming mic permission | PASS | |
| Android microphone permission dialog appears | After the explanation | PASS | |
| Operate the dialog with Voice Access | "Allow" selectable by voice | PASS | |
| Operate the dialog with TalkBack | Dialog readable/actionable | PASS | |
| After grant, app verbally confirms access | Spoken confirmation | PASS | |
| App starts listening WITHOUT pressing Start/Listen | Listening state announced | PASS | |

## Scenario B — Existing WAV workflow

| Step | Expected | PASS/FAIL | Notes |
|---|---|---|---|
| Launch app | Voice session active | PASS | |
| Say "choose file" | System picker opens | PASS | |
| Select a WAV using Voice Access | Selection completes | PASS | |
| Return to app | Spoken file confirmation | PASS | |
| Say "analyze audio" | Analysis runs; spoken result (presentation summary) | PASS | |
| Say "read result" | Summary re-spoken | PASS | |
| Say "show details" | Details visible; raw segments present | PASS | |
| Verify: headline is the 1.25 s summary, details show ALL raw segments incl. transients/X | Both true simultaneously | PASS | |

## Scenario C — Microphone workflow

| Step | Expected | PASS/FAIL | Notes |
|---|---|---|---|
| Say "start recording" | Spoken instructions play COMPLETELY first | PASS | |
| Voice recognizer stops before recording | No command pickup during recording | PASS | |
| Play guitar | Recording proceeds | PASS | |
| TalkBack: focus the full-screen Stop control | Announced as "Stop recording" button | PASS | |
| Double-tap (TalkBack) or tap (no TalkBack) to stop | Recording stops | PASS | |
| Spoken confirmation incl. duration/result | Heard | PASS | |
| Say "analyze recording" | Analysis runs on the recording | PASS | |
| Result spoken | Presentation summary heard | PASS | |

**Scenario C notes:** `dev_clean_01` was played through the Mac speaker,
captured by the Samsung microphone, and the application returned the
prevailing chords successfully. **This was device-functionality testing only,
not Tier-2 data** (speaker playback never receives `exp_*` IDs). Repeated
record → analyze → record cycles were re-validated after the re-recording
fix (`e9223d7`); the second recording no longer fails or re-prompts for
permission.

## Scenario D — Play Along

Precondition: an analyzed audio (B or C).

| Step | Expected | PASS/FAIL | Notes |
|---|---|---|---|
| Say "play along" | Intro speech, then audio starts | PASS | |
| Chord cues at prevailing chords | Announced near segment starts | PASS | |
| No burst of short transient cues | Cues are sparse/prevailing only | PASS | |
| Long uncertainty audible | "Uncertain" spoken for retained X (if present in clip) | PASS | |
| Say/tap Pause → Resume → Stop | Each works with spoken/visual state | PASS | |
| Play to completion | "Play Along finished." | PASS | |
| TTS understandable over guitar playback? | Record YES/NO + volume notes | PASS | YES |

**Scenario D notes:** Play Along cues occurred at the expected playback
times. TTS was understandable over playback.

> Ducking decision: only if TTS is NOT understandable here should audio
> ducking be implemented. Do not pre-emptively implement it.
> **DECISION (2026-08-11): TTS was understandable on device — audio ducking
> is NOT needed and will not be implemented.**

## Scenario E — TalkBack

| Check | Expected | PASS/FAIL | Notes |
|---|---|---|---|
| Reading order | Logical top-to-bottom | PASS | |
| Headings | Announced as headings (navigate by heading works) | PASS | |
| Button names | All primary buttons labeled meaningfully | PASS | |
| Recording Stop control | One large button, labeled, double-tap works | PASS | |
| Segment details | Each segment card readable with label/time/confidence | PASS | |
| Play Along controls | Reachable and labeled while playing | PASS | |
| No TTS/TalkBack feedback loop | TalkBack speech does not trigger/garble recognition | PASS | |

## Scenario F — Voice Access

| Check | Expected | PASS/FAIL | Notes |
|---|---|---|---|
| Permission dialog | Operable by voice | PASS | |
| File picker | Navigable/selectable by voice | PASS | |
| Primary buttons | Visible labels match speakable names | PASS | |

## Scenario G — Failure handling

| Case | Steps | Expected | PASS/FAIL | Notes |
|---|---|---|---|---|
| Backend unavailable | Stop the Mac server; launch/analyze | Clear spoken error; app usable | PASS | |
| Retry connection | Restart server; say "retry connection" | Health restored, announced | PASS | |
| Mic permission denied | Deny at first launch | Spoken explanation; voice control reported unavailable; touch still works | PASS | |
| File picker cancelled | "choose file" then back out | Spoken/visible feedback; no crash | PASS | |
| Unrecognized command | Say gibberish | Helpful spoken recovery (help hint) | PASS | |
| Speech timeout | Say nothing when listening | Session handles silence gracefully | PASS | |
| Analysis failure | e.g. select a non-WAV/corrupt file | Spoken error; app recovers | PASS | |

## Scenario H — Large text

Set Android font size and display size to maximum (Settings → Display →
Font size / Screen zoom; also try Accessibility → Visibility enhancements).

| Check | Expected | PASS/FAIL | Notes |
|---|---|---|---|
| Primary controls | No clipped/overlapping controls | PASS | |
| All actions reachable | Nothing pushed off-screen without scrolling | PASS | |
| Result card | Progression + counts readable | PASS | |
| Recording screen | Stop control usable | PASS | |
| Play Along controls | Usable | PASS | |
