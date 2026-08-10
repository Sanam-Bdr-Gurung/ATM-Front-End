package com.chords.finder.chords_finder

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

class MainActivity :
    FlutterActivity(),
    TextToSpeech.OnInitListener {

    companion object {
        private const val TTS_CHANNEL = "chordassist/tts"
        private const val VOICE_CHANNEL = "chordassist/voice"

        private const val UTTERANCE_ID = "chordassist_result"
        private const val WAIT_UTTERANCE_PREFIX = "chordassist_wait_"

        private const val RECORD_AUDIO_REQUEST = 4101
    }

    private var textToSpeech: TextToSpeech? = null

    private var ttsReady = false
    private var ttsInitFailed = false

    // speakAndWait calls that arrived before TTS finished initializing.
    private val queuedSpeakRequests =
        ArrayDeque<Pair<String, MethodChannel.Result>>()

    // Utterance id -> Flutter result awaiting speech completion.
    private val pendingUtterances =
        HashMap<String, MethodChannel.Result>()

    private var utteranceCounter = 0

    private var speechRecognizer: SpeechRecognizer? = null
    private var usingOnDeviceRecognizer = false
    private var forceNetworkRecognizer = false

    private var pendingVoiceResult: MethodChannel.Result? = null
    private var pendingPermissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        configureTextToSpeech(flutterEngine)
        configureVoiceRecognition(flutterEngine)
    }

    // ------------------------------------------------------------------
    // Text to speech
    // ------------------------------------------------------------------

    private fun configureTextToSpeech(flutterEngine: FlutterEngine) {
        textToSpeech = TextToSpeech(this, this)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            TTS_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "speak" -> handleSpeak(call.argument("text"), result)

                "speakAndWait" ->
                    handleSpeakAndWait(call.argument("text"), result)

                "stop" -> {
                    textToSpeech?.stop()
                    resolveAllPendingUtterances()
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun handleSpeak(
        rawText: String?,
        result: MethodChannel.Result
    ) {
        val text = rawText?.trim()

        if (text.isNullOrEmpty()) {
            result.error(
                "EMPTY_TEXT",
                "There is no text to read aloud.",
                null
            )
            return
        }

        if (!ttsReady) {
            result.error(
                "TTS_NOT_READY",
                "Text-to-speech is not ready.",
                null
            )
            return
        }

        val status = textToSpeech?.speak(
            text,
            TextToSpeech.QUEUE_FLUSH,
            null,
            UTTERANCE_ID
        )

        if (status == TextToSpeech.ERROR) {
            result.error(
                "TTS_ERROR",
                "Text-to-speech could not start.",
                null
            )
        } else {
            result.success(null)
        }
    }

    private fun handleSpeakAndWait(
        rawText: String?,
        result: MethodChannel.Result
    ) {
        val text = rawText?.trim()

        if (text.isNullOrEmpty()) {
            result.error(
                "EMPTY_TEXT",
                "There is no text to read aloud.",
                null
            )
            return
        }

        if (ttsInitFailed) {
            result.error(
                "TTS_UNAVAILABLE",
                "Text-to-speech is unavailable on this device.",
                null
            )
            return
        }

        if (!ttsReady) {
            // TTS is still initializing; run this request from onInit.
            queuedSpeakRequests.addLast(text to result)
            return
        }

        beginTrackedSpeech(text, result)
    }

    private fun beginTrackedSpeech(
        text: String,
        result: MethodChannel.Result
    ) {
        utteranceCounter += 1

        val utteranceId = "$WAIT_UTTERANCE_PREFIX$utteranceCounter"

        // A new tracked utterance flushes earlier speech, so release
        // any callers still waiting on utterances that will never finish.
        resolveAllPendingUtterances()

        pendingUtterances[utteranceId] = result

        val status = textToSpeech?.speak(
            text,
            TextToSpeech.QUEUE_FLUSH,
            null,
            utteranceId
        )

        if (status == TextToSpeech.ERROR) {
            pendingUtterances.remove(utteranceId)

            result.error(
                "TTS_ERROR",
                "Text-to-speech could not start.",
                null
            )
        }
    }

    private fun resolveUtterance(utteranceId: String?, failed: Boolean) {
        if (utteranceId == null) {
            return
        }

        runOnUiThread {
            val result = pendingUtterances.remove(utteranceId) ?: return@runOnUiThread

            if (failed) {
                result.error(
                    "TTS_ERROR",
                    "Text-to-speech stopped unexpectedly.",
                    null
                )
            } else {
                result.success(null)
            }
        }
    }

    private fun resolveAllPendingUtterances() {
        if (pendingUtterances.isEmpty()) {
            return
        }

        val waiting = pendingUtterances.values.toList()
        pendingUtterances.clear()

        // Interrupted speech is not an error for the awaiting caller.
        waiting.forEach { it.success(null) }
    }

    override fun onInit(status: Int) {
        if (status != TextToSpeech.SUCCESS) {
            ttsReady = false
            ttsInitFailed = true
            failQueuedSpeakRequests()
            return
        }

        val engine = textToSpeech ?: return

        val languageStatus = engine.setLanguage(Locale.US)

        ttsReady =
            languageStatus != TextToSpeech.LANG_MISSING_DATA &&
            languageStatus != TextToSpeech.LANG_NOT_SUPPORTED

        if (!ttsReady) {
            ttsInitFailed = true
            failQueuedSpeakRequests()
            return
        }

        engine.setSpeechRate(0.9f)
        engine.setPitch(1.0f)

        engine.setOnUtteranceProgressListener(
            object : UtteranceProgressListener() {
                override fun onStart(utteranceId: String?) {}

                override fun onDone(utteranceId: String?) {
                    resolveUtterance(utteranceId, failed = false)
                }

                @Deprecated("Deprecated in Java")
                override fun onError(utteranceId: String?) {
                    resolveUtterance(utteranceId, failed = true)
                }

                override fun onError(utteranceId: String?, errorCode: Int) {
                    resolveUtterance(utteranceId, failed = true)
                }

                override fun onStop(
                    utteranceId: String?,
                    interrupted: Boolean
                ) {
                    resolveUtterance(utteranceId, failed = false)
                }
            }
        )

        runOnUiThread { drainQueuedSpeakRequests() }
    }

    private fun drainQueuedSpeakRequests() {
        // Only the most recent queued request is spoken; speaking each
        // stale one in sequence would delay startup. Earlier callers
        // are released without error.
        val newest = queuedSpeakRequests.removeLastOrNull() ?: return

        while (queuedSpeakRequests.isNotEmpty()) {
            queuedSpeakRequests.removeFirst().second.success(null)
        }

        beginTrackedSpeech(newest.first, newest.second)
    }

    private fun failQueuedSpeakRequests() {
        runOnUiThread {
            while (queuedSpeakRequests.isNotEmpty()) {
                queuedSpeakRequests.removeFirst().second.error(
                    "TTS_UNAVAILABLE",
                    "Text-to-speech is unavailable on this device.",
                    null
                )
            }
        }
    }

    // ------------------------------------------------------------------
    // Voice command recognition
    // ------------------------------------------------------------------

    private fun configureVoiceRecognition(flutterEngine: FlutterEngine) {
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            VOICE_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "hasPermission" ->
                    result.success(hasRecordAudioPermission())

                "requestPermission" ->
                    requestRecordAudioPermission(result)

                "listen" -> startVoiceListening(result)

                "cancel" -> cancelVoiceListening(result)

                else -> result.notImplemented()
            }
        }
    }

    private fun hasRecordAudioPermission(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            return true
        }

        return checkSelfPermission(Manifest.permission.RECORD_AUDIO) ==
            PackageManager.PERMISSION_GRANTED
    }

    private fun requestRecordAudioPermission(result: MethodChannel.Result) {
        if (hasRecordAudioPermission()) {
            result.success(true)
            return
        }

        if (pendingPermissionResult != null) {
            result.error(
                "PERMISSION_REQUEST_IN_PROGRESS",
                "A microphone permission request is already active.",
                null
            )
            return
        }

        pendingPermissionResult = result

        requestPermissions(
            arrayOf(Manifest.permission.RECORD_AUDIO),
            RECORD_AUDIO_REQUEST
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(
            requestCode,
            permissions,
            grantResults
        )

        if (requestCode != RECORD_AUDIO_REQUEST) {
            return
        }

        val granted =
            grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED

        val result = pendingPermissionResult
        pendingPermissionResult = null

        result?.success(granted)
    }

    private fun startVoiceListening(result: MethodChannel.Result) {
        if (pendingVoiceResult != null) {
            result.error(
                "BUSY",
                "Voice recognition is already active.",
                null
            )
            return
        }

        if (!hasRecordAudioPermission()) {
            result.error(
                "PERMISSION_DENIED",
                "Microphone permission was not granted.",
                null
            )
            return
        }

        pendingVoiceResult = result

        beginVoiceRecognition()
    }

    private fun beginVoiceRecognition() {
        if (pendingVoiceResult == null) {
            return
        }

        if (!SpeechRecognizer.isRecognitionAvailable(this)) {
            finishVoiceError(
                "UNAVAILABLE",
                "Speech recognition is unavailable on this device."
            )
            return
        }

        if (speechRecognizer == null) {
            try {
                val useOnDevice =
                    !forceNetworkRecognizer &&
                        Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
                        SpeechRecognizer.isOnDeviceRecognitionAvailable(this)

                speechRecognizer = if (useOnDevice) {
                    SpeechRecognizer.createOnDeviceSpeechRecognizer(this)
                } else {
                    SpeechRecognizer.createSpeechRecognizer(this)
                }

                usingOnDeviceRecognizer = useOnDevice

                speechRecognizer?.setRecognitionListener(
                    createRecognitionListener()
                )
            } catch (_: Exception) {
                finishVoiceError(
                    "INITIALIZATION_FAILED",
                    "Voice recognition could not be initialized."
                )
                return
            }
        }

        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(
                RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                RecognizerIntent.LANGUAGE_MODEL_FREE_FORM
            )

            putExtra(
                RecognizerIntent.EXTRA_LANGUAGE,
                Locale.getDefault().toLanguageTag()
            )

            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 3)
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, false)
        }

        try {
            speechRecognizer?.startListening(intent)
        } catch (_: Exception) {
            finishVoiceError(
                "START_FAILED",
                "Voice recognition could not start."
            )
        }
    }

    private fun createRecognitionListener(): RecognitionListener {
        return object : RecognitionListener {
            override fun onResults(results: Bundle) {
                val phrase = results
                    .getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                    ?.firstOrNull()
                    ?.trim()

                if (phrase.isNullOrEmpty()) {
                    finishVoiceError(
                        "NO_MATCH",
                        "I did not understand that command."
                    )
                    return
                }

                val result = pendingVoiceResult
                pendingVoiceResult = null

                result?.success(phrase)
            }

            override fun onError(error: Int) {
                if (
                    usingOnDeviceRecognizer &&
                    isLanguageUnsupportedError(error)
                ) {
                    // The on-device recognizer lacks this language; retry
                    // once with the standard recognition service.
                    forceNetworkRecognizer = true
                    destroyRecognizer()
                    beginVoiceRecognition()
                    return
                }

                val (code, message) = when (error) {
                    SpeechRecognizer.ERROR_NO_MATCH ->
                        "NO_MATCH" to
                            "I did not understand that command."

                    SpeechRecognizer.ERROR_SPEECH_TIMEOUT ->
                        "TIMEOUT" to
                            "I did not hear a command."

                    SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS ->
                        "PERMISSION_DENIED" to
                            "Microphone permission is required."

                    SpeechRecognizer.ERROR_RECOGNIZER_BUSY ->
                        "BUSY" to
                            "Voice recognition is busy."

                    SpeechRecognizer.ERROR_NETWORK,
                    SpeechRecognizer.ERROR_NETWORK_TIMEOUT ->
                        "NETWORK" to
                            "Voice recognition could not reach the " +
                            "recognition service."

                    else ->
                        "VOICE_ERROR_$error" to
                            "Voice recognition failed. Please try again."
                }

                finishVoiceError(code, message)
            }

            override fun onReadyForSpeech(params: Bundle?) {}
            override fun onBeginningOfSpeech() {}
            override fun onRmsChanged(rmsdB: Float) {}
            override fun onBufferReceived(buffer: ByteArray?) {}
            override fun onEndOfSpeech() {}
            override fun onPartialResults(partialResults: Bundle?) {}
            override fun onEvent(eventType: Int, params: Bundle?) {}
        }
    }

    private fun isLanguageUnsupportedError(error: Int): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            return false
        }

        return error == SpeechRecognizer.ERROR_LANGUAGE_NOT_SUPPORTED ||
            error == SpeechRecognizer.ERROR_LANGUAGE_UNAVAILABLE
    }

    private fun cancelVoiceListening(result: MethodChannel.Result) {
        val listeningResult = pendingVoiceResult
        pendingVoiceResult = null

        speechRecognizer?.cancel()

        listeningResult?.success(null)
        result.success(null)
    }

    private fun finishVoiceError(code: String, message: String) {
        val result = pendingVoiceResult
        pendingVoiceResult = null

        result?.error(code, message, null)
    }

    private fun destroyRecognizer() {
        speechRecognizer?.cancel()
        speechRecognizer?.destroy()
        speechRecognizer = null
        usingOnDeviceRecognizer = false
    }

    override fun onDestroy() {
        // Release any waiting Dart futures as cancellations so the
        // Flutter side never hangs on a destroyed activity.
        pendingVoiceResult?.success(null)
        pendingVoiceResult = null

        pendingPermissionResult?.success(false)
        pendingPermissionResult = null

        destroyRecognizer()
        resolveAllPendingUtterances()

        pendingUtterances.clear()
        queuedSpeakRequests.clear()

        textToSpeech?.stop()
        textToSpeech?.shutdown()

        textToSpeech = null
        ttsReady = false

        super.onDestroy()
    }
}
