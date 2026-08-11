# Device Validation Protocol — Physical Samsung Device

Fill in PASS / FAIL / NOTES per line. Do not mark PASS for anything not
actually performed on the device. Results here are the source for the thesis's
device-validation status (Ch5 §5.8.1); keep this file under version control
after filling it in.

Tester: ______________  Date: ______________
Device model / Android version: ______________
App commit: ______________  Backend commit: ______________

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
| Say "Hi Bixby, open Chord Assist" | App launches from assistant | | |
| App speaks intro BEFORE any permission dialog | Spoken explanation of upcoming mic permission | | |
| Android microphone permission dialog appears | After the explanation | | |
| Operate the dialog with Voice Access | "Allow" selectable by voice | | |
| Operate the dialog with TalkBack | Dialog readable/actionable | | |
| After grant, app verbally confirms access | Spoken confirmation | | |
| App starts listening WITHOUT pressing Start/Listen | Listening state announced | | |

## Scenario B — Existing WAV workflow

| Step | Expected | PASS/FAIL | Notes |
|---|---|---|---|
| Launch app | Voice session active | | |
| Say "choose file" | System picker opens | | |
| Select a WAV using Voice Access | Selection completes | | |
| Return to app | Spoken file confirmation | | |
| Say "analyze audio" | Analysis runs; spoken result (presentation summary) | | |
| Say "read result" | Summary re-spoken | | |
| Say "show details" | Details visible; raw segments present | | |
| Verify: headline is the 1.25 s summary, details show ALL raw segments incl. transients/X | Both true simultaneously | | |

## Scenario C — Microphone workflow

| Step | Expected | PASS/FAIL | Notes |
|---|---|---|---|
| Say "start recording" | Spoken instructions play COMPLETELY first | | |
| Voice recognizer stops before recording | No command pickup during recording | | |
| Play guitar | Recording proceeds | | |
| TalkBack: focus the full-screen Stop control | Announced as "Stop recording" button | | |
| Double-tap (TalkBack) or tap (no TalkBack) to stop | Recording stops | | |
| Spoken confirmation incl. duration/result | Heard | | |
| Say "analyze recording" | Analysis runs on the recording | | |
| Result spoken | Presentation summary heard | | |

## Scenario D — Play Along

Precondition: an analyzed audio (B or C).

| Step | Expected | PASS/FAIL | Notes |
|---|---|---|---|
| Say "play along" | Intro speech, then audio starts | | |
| Chord cues at prevailing chords | Announced near segment starts | | |
| No burst of short transient cues | Cues are sparse/prevailing only | | |
| Long uncertainty audible | "Uncertain" spoken for retained X (if present in clip) | | |
| Say/tap Pause → Resume → Stop | Each works with spoken/visual state | | |
| Play to completion | "Play Along finished." | | |
| TTS understandable over guitar playback? | Record YES/NO + volume notes | | |

> Ducking decision: only if TTS is NOT understandable here should audio
> ducking be implemented. Do not pre-emptively implement it.

## Scenario E — TalkBack

| Check | Expected | PASS/FAIL | Notes |
|---|---|---|---|
| Reading order | Logical top-to-bottom | | |
| Headings | Announced as headings (navigate by heading works) | | |
| Button names | All primary buttons labeled meaningfully | | |
| Recording Stop control | One large button, labeled, double-tap works | | |
| Segment details | Each segment card readable with label/time/confidence | | |
| Play Along controls | Reachable and labeled while playing | | |
| No TTS/TalkBack feedback loop | TalkBack speech does not trigger/garble recognition | | |

## Scenario F — Voice Access

| Check | Expected | PASS/FAIL | Notes |
|---|---|---|---|
| Permission dialog | Operable by voice | | |
| File picker | Navigable/selectable by voice | | |
| Primary buttons | Visible labels match speakable names | | |

## Scenario G — Failure handling

| Case | Steps | Expected | PASS/FAIL | Notes |
|---|---|---|---|---|
| Backend unavailable | Stop the Mac server; launch/analyze | Clear spoken error; app usable | | |
| Retry connection | Restart server; say "retry connection" | Health restored, announced | | |
| Mic permission denied | Deny at first launch | Spoken explanation; voice control reported unavailable; touch still works | | |
| File picker cancelled | "choose file" then back out | Spoken/visible feedback; no crash | | |
| Unrecognized command | Say gibberish | Helpful spoken recovery (help hint) | | |
| Speech timeout | Say nothing when listening | Session handles silence gracefully | | |
| Analysis failure | e.g. select a non-WAV/corrupt file | Spoken error; app recovers | | |

## Scenario H — Large text

Set Android font size and display size to maximum (Settings → Display →
Font size / Screen zoom; also try Accessibility → Visibility enhancements).

| Check | Expected | PASS/FAIL | Notes |
|---|---|---|---|
| Primary controls | No clipped/overlapping controls | | |
| All actions reachable | Nothing pushed off-screen without scrolling | | |
| Result card | Progression + counts readable | | |
| Recording screen | Stop control usable | | |
| Play Along controls | Usable | | |
