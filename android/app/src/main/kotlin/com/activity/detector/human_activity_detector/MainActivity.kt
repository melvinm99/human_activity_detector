package com.activity.detector.human_activity_detector

import android.Manifest
import android.annotation.SuppressLint
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Context.*
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.media.AudioManager
import android.os.Environment
import android.provider.MediaStore.Audio
import android.util.Log
import androidx.annotation.NonNull
import androidx.core.app.ActivityCompat
import com.android.volley.AuthFailureError
import com.android.volley.Request
import com.android.volley.Response
import com.android.volley.toolbox.JsonObjectRequest
import com.android.volley.toolbox.Volley
import com.google.android.gms.location.ActivityRecognition
import com.google.android.gms.location.SleepClassifyEvent
import com.google.android.gms.location.SleepSegmentEvent
import com.google.android.gms.location.SleepSegmentRequest
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.BasicMessageChannel
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StringCodec
import org.json.JSONObject
import java.io.File
import java.io.IOException
import java.util.Date


class MainActivity: FlutterFragmentActivity() {

    private val CHANNEL = "com.activity.detector/sleep_detector"
    private val AUDIO_CHANNEL = "com.activity.detector/audio_processing"
    private val RINGTONE_CHANNEL = "com.activity.detector/ringtone"

    private val audioProcessor = AudioProcessor()

    @SuppressLint("UnspecifiedRegisterReceiverFlag")
    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        audioProcessor.setApplicationContext(applicationContext)
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, AUDIO_CHANNEL).setMethodCallHandler { call, result ->
            if (call.method.equals("startAudioRecording")) {
                audioProcessor.startRecordingSession()
                result.success(true)
            }
            else if (call.method.equals("stopAudioRecording")) {
                audioProcessor.stopRecordingSession(true)
                result.success(true)
            }
            else if (call.method.equals("computeMfccFeatures")) { // not necessary
                var success = audioProcessor.calculateMFCCFeatures()
                result.success(success)
            }
            else if (call.method.equals("getMfccFilePath")) {
                var file = audioProcessor.getMFCCFile()
                result.success(file.absolutePath)
            }

        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, RINGTONE_CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "getRingerMode") {
                val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                result.success(audioManager.ringerMode)
            }

        }

        val channel = BasicMessageChannel<String>(flutterEngine.getDartExecutor(), "com.activity.detector/sleep_detector_messages", StringCodec.INSTANCE)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            val broadCastReceiver = object : BroadcastReceiver() {
                override fun onReceive(contxt: Context?, intent: Intent?) {
                    if(intent == null) return
                    log("onReceive(): $intent")
                    // TODO: Extract sleep information from PendingIntent.
                    if (SleepSegmentEvent.hasEvents(intent)) {
                        val sleepSegmentEvents: List<SleepSegmentEvent> =
                                SleepSegmentEvent.extractEvents(intent)
                        log("SleepSegmentEvent List: $sleepSegmentEvents")
                        for (sleepSegmentEvent in sleepSegmentEvents) {
                            log("SleepSegmentEvent Event Found: ${sleepSegmentEvent.status}")
                            val startTime = Date(sleepSegmentEvent.startTimeMillis)
                            val endTime = Date(sleepSegmentEvent.endTimeMillis)
                            val duration: Long = sleepSegmentEvent.segmentDurationMillis
                            val status = sleepSegmentEvent.status
                            val messageWithSemiColon = "sleepSegment;$startTime;$endTime;$duration;$status"
                            channel.send(messageWithSemiColon)
                            //result.success(messageWithSemiColon)
                            //handler.sendMessage(message)
                        }
                    } else if (SleepClassifyEvent.hasEvents(intent)) {
                        val sleepClassifyEvents: List<SleepClassifyEvent> =
                                SleepClassifyEvent.extractEvents(intent)
                        log("SleepClassifyEvent List: $sleepClassifyEvents")
                        for (sleepClassifyEvent in sleepClassifyEvents) {
                            log("SleepClassifyEvent Event Found: ${sleepClassifyEvent.motion}")
                            val timestamp = Date(sleepClassifyEvent.timestampMillis)
                            val confidence = sleepClassifyEvent.confidence
                            val light = sleepClassifyEvent.light
                            val motion = sleepClassifyEvent.motion
                            val messageWithSemiColon = "sleepClassify;$timestamp;$confidence;$light;$motion"
                            channel.send(messageWithSemiColon)
                            //result.success(messageWithSemiColon)
                        }
                    }
                    /*when (intent?.action) {
                        BROADCAST_DEFAULT_ALBUM_CHANGED -> handleAlbumChanged()
                        BROADCAST_CHANGE_TYPE_CHANGED -> handleChangeTypeChanged()
                    }*/

                }
            }
            val intentFilter = IntentFilter( "com.activity.detector")
            registerReceiver(broadCastReceiver, intentFilter)

            if (call.method == "initSleepApi") {
                ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.ACTIVITY_RECOGNITION), 1)

                if (ActivityCompat.checkSelfPermission(this, Manifest.permission.ACTIVITY_RECOGNITION) == PackageManager.PERMISSION_GRANTED) {

                    //val sleepIntent = Intent("com.activity.detector")
                    //val pendingIntent = PendingIntent.getBroadcast(applicationContext, 0, sleepIntent, PendingIntent.FLAG_IMMUTABLE)
                    val pendingIntent =
                            SleepReceiver.createSleepReceiverPendingIntent(context = applicationContext)

                    val task = ActivityRecognition.getClient(applicationContext)
                            .requestSleepSegmentUpdates(
                                    pendingIntent,
                                    SleepSegmentRequest.getDefaultSleepSegmentRequest())
                            .addOnSuccessListener {
                                //result.success(second)
                                log("Successfully subscribed to sleep data.")
                                createFile();
                                result.success("sleepInitSuccess")
                                channel.send("sleepInitSuccess")
                                //writeToFile("Successfully subscribed to sleep data.", applicationContext)
                                writeToFile2("Successfully subscribed to sleep data.", applicationContext)
                                sendHttpRequest("Successfully subscribed to sleep data.", applicationContext)
                            }
                            .addOnFailureListener { exception ->
                                log("Exception when subscribing to sleep data: $exception")
                                result.error("sleepInitError", "Exception when subscribing to sleep data: $exception", null)
                                channel.send("sleepInitError")
                                createFile();
                                //writeToFile("Exception when subscribing to sleep data: $exception", applicationContext)
                                writeToFile2("Exception when subscribing to sleep data: $exception", applicationContext)
                                sendHttpRequest("Exception when subscribing to sleep data: $exception", applicationContext)
                            }

                }
            }
            else if (call.method == "stopSleepApi") {
                ActivityRecognition.getClient(applicationContext)
                        .removeSleepSegmentUpdates(PendingIntent.getBroadcast(applicationContext, 0, Intent(applicationContext, SleepReceiver::class.java), PendingIntent.FLAG_IMMUTABLE))
                        .addOnSuccessListener {
                            log("Successfully unsubscribed from sleep data.")
                            result.success("sleepStopSuccess")
                            channel.send("sleepStopSuccess")
                            //writeToFile("Successfully unsubscribed to sleep data.", applicationContext)
                            writeToFile2("Unsubscribed to sleep data.", applicationContext)
                            sendHttpRequest("Successfully unsubscribed to sleep data.", applicationContext)
                        }
                        .addOnFailureListener { exception ->
                            log("Exception when unsubscribing from sleep data: $exception")
                            result.error("sleepStopError", "Exception when unsubscribing from sleep data: $exception", null)
                            channel.send("sleepStopError")
                            //writeToFile("Exception when unsubscribing from sleep data: $exception", applicationContext)
                            writeToFile2("Exception when unsubscribing from sleep data: $exception", applicationContext)
                            sendHttpRequest("Exception when unsubscribing from sleep data: $exception", applicationContext)
                        }
            }


        }
    }

    private fun createFile() {

        /*val file = File("sleep.csv")
        if (!file.exists()) {
            file.createNewFile()
        }*/
        var downloadFolder = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS);
        val file2 = File(downloadFolder, "sleep2.csv")
        if (!file2.exists()) {
            file2.createNewFile()
        }
    }
    /*private fun writeToFile(data: String, context: Context) {
        return;
        try {
            val outputStreamWriter = OutputStreamWriter(context.openFileOutput("sleep.csv", FlutterFragmentActivity.MODE_PRIVATE))
            outputStreamWriter.appendLine(data)
            outputStreamWriter.close()
        } catch (e: IOException) {
            Log.e("Exception", "File write failed: $e")
        }
    }*/

    private fun writeToFile2(data: String, context: Context) {
        var downloadFolder = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS);

        val file = File(downloadFolder, "sleep2.csv")
        try {
            file.printWriter().use { out ->
                out.println(data);
            }
        } catch (e: IOException) {
            Log.e("Exception", "File write failed: $e")
        }
    }

    private fun sendHttpRequest(data: String, context: Context) {
        // Instantiate the RequestQueue.
        val queue = Volley.newRequestQueue(context)
        val url = "https://tesibe.swipeapp.studio/sample/tesi"

        val json = JSONObject()
        /*"startTime": startTime,
        "endTime": endTime,
        "duration": duration,
        "status": status,*/
        json.put("data", data)

        val jsonOblect = object : JsonObjectRequest(
                Request.Method.POST,
                url,
                json,
                Response.Listener { response ->
                    // Get your json response and convert it to whatever you want.

                },
                Response.ErrorListener {

                }
        ){
            @Throws(AuthFailureError::class)
            override fun getHeaders(): Map<String, String> {
                val headers = HashMap<String, String>()
                headers.put("Content-Type", "application/json")
                return headers
            }
        }

        // Add the request to the RequestQueue.
        queue.add(jsonOblect)
        //queue.start()
    }

    private fun log(message: String) {
        Log.d("Android message:", message)
    }

}
