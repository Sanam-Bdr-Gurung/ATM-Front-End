package com.chords.finder.chords_finder
import android.speech.tts.TextToSpeech
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

class MainActivity :
    FlutterActivity(),
    TextToSpeech.OnInitListener {

    companion object {
        private const val CHANNEL =
            "chordassist/tts"

        private const val UTTERANCE_ID =
            "chordassist_result"
    }

    private var textToSpeech:
            TextToSpeech? = null

    private var ttsReady = false

    override fun configureFlutterEngine(
        flutterEngine: FlutterEngine
    ) {
        super.configureFlutterEngine(
            flutterEngine
        )

        textToSpeech =
            TextToSpeech(
                this,
                this
            )

        MethodChannel(
            flutterEngine
                .dartExecutor
                .binaryMessenger,
            CHANNEL
        ).setMethodCallHandler {
                call,
                result ->

            when (call.method) {
                "speak" -> {
                    val text =
                        call.argument<String>(
                            "text"
                        )
                            ?.trim()

                    if (text.isNullOrEmpty()) {
                        result.error(
                            "EMPTY_TEXT",
                            "There is no text "
                                    + "to read aloud.",
                            null
                        )

                        return@setMethodCallHandler
                    }

                    if (!ttsReady) {
                        result.error(
                            "TTS_NOT_READY",
                            "Text-to-speech "
                                    + "is not ready.",
                            null
                        )

                        return@setMethodCallHandler
                    }

                    val status =
                        textToSpeech?.speak(
                            text,
                            TextToSpeech
                                .QUEUE_FLUSH,
                            null,
                            UTTERANCE_ID
                        )

                    if (
                        status ==
                        TextToSpeech.ERROR
                    ) {
                        result.error(
                            "TTS_ERROR",
                            "Text-to-speech "
                                    + "could not start.",
                            null
                        )
                    } else {
                        result.success(null)
                    }
                }

                "stop" -> {
                    textToSpeech?.stop()

                    result.success(null)
                }

                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    override fun onInit(
        status: Int
    ) {
        if (
            status !=
            TextToSpeech.SUCCESS
        ) {
            ttsReady = false
            return
        }

        val engine =
            textToSpeech ?: return

        val languageStatus =
            engine.setLanguage(
                Locale.US
            )

        ttsReady =
            languageStatus !=
                    TextToSpeech
                        .LANG_MISSING_DATA &&
                    languageStatus !=
                    TextToSpeech
                        .LANG_NOT_SUPPORTED

        if (ttsReady) {
            engine.setSpeechRate(
                0.9f
            )

            engine.setPitch(
                1.0f
            )
        }
    }

    override fun onDestroy() {
        textToSpeech?.stop()
        textToSpeech?.shutdown()

        textToSpeech = null
        ttsReady = false

        super.onDestroy()
    }
}