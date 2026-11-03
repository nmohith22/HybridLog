package com.example.workout_app

import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val needleExecutor = Executors.newSingleThreadExecutor()

    private external fun nativeInitialize(modelPath: String): String
    private external fun nativeComplete(input: String): String
    private external fun nativeReset()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "hybridlog/needle")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isSupported" -> result.success(Build.SUPPORTED_ABIS.any { it == "arm64-v8a" || it == "armeabi-v7a" })
                    "initialize" -> {
                        val path = call.argument<String>("modelPath")
                        if (path == null) result.error("invalid_model", "Missing model path", null)
                        else needleExecutor.execute {
                            val response = nativeInitialize(path)
                            runOnUiThread { result.success(response) }
                        }
                    }
                    "complete" -> {
                        val input = call.argument<String>("input")
                        if (input == null) result.error("invalid_input", "Missing request", null)
                        else needleExecutor.execute {
                            val response = nativeComplete(input)
                            runOnUiThread { result.success(response) }
                        }
                    }
                    "reset" -> needleExecutor.execute {
                        nativeReset()
                        runOnUiThread { result.success(null) }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    companion object {
        init { System.loadLibrary("needle_bridge") }
    }
}
