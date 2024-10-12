package com.activity.detector.human_activity_detector


import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import com.android.volley.AuthFailureError
import com.android.volley.Request
import com.android.volley.Response
import com.android.volley.toolbox.JsonObjectRequest
import com.android.volley.toolbox.Volley
import com.google.android.gms.location.SleepClassifyEvent
import com.google.android.gms.location.SleepSegmentEvent
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.MainScope
import org.json.JSONObject
import java.io.File
import java.io.IOException

/**
 * Saves Sleep Events to Database.
 */
class SleepReceiver : BroadcastReceiver() {

    // Used to launch coroutines (non-blocking way to insert data).
    private val scope: CoroutineScope = MainScope()

    override fun onReceive(context: Context, intent: Intent) {
        log("onReceive(): $intent")

        // TODO: Extract sleep information from PendingIntent.
        if (SleepSegmentEvent.hasEvents(intent)) {
            val sleepSegmentEvents: List<SleepSegmentEvent> =
                    SleepSegmentEvent.extractEvents(intent)
            log("SleepSegmentEvent List: $sleepSegmentEvents")
            sleepSegmentEvents.forEach {
                val startTime = it.startTimeMillis
                val endTime = it.endTimeMillis
                val duration: Long = it.segmentDurationMillis
                val status = it.status
                val messageWithSemiColon = "sleepSegment;$startTime;$endTime;$duration;$status;"
                //writeToFile(messageWithSemiColon, context)
                writeToFile2(messageWithSemiColon, context)
                sendHttpRequestSegment(startTime, endTime, duration, status, context)
            }
            //addSleepSegmentEventsToDatabase(repository, sleepSegmentEvents) todo
        } else if (SleepClassifyEvent.hasEvents(intent)) {
            val sleepClassifyEvents: List<SleepClassifyEvent> =
                    SleepClassifyEvent.extractEvents(intent)
            log("SleepClassifyEvent List: $sleepClassifyEvents")
            sleepClassifyEvents.forEach {
                val timestampMillis = it.timestampMillis
                val confidence = it.confidence
                val light = it.light
                val motion = it.motion
                val messageWithSemiColon = "sleepClassify;$timestampMillis;$confidence;$light;$motion;"
                //writeToFile(messageWithSemiColon, context)
                writeToFile2(messageWithSemiColon, context)
                sendHttpRequestClassify(timestampMillis, confidence, light, motion, context)
            }
            //addSleepClassifyEventsToDatabase(repository, sleepClassifyEvents) todo
        }
    }
    companion object {
        const val TAG = "SleepReceiver"
        fun createSleepReceiverPendingIntent(context: Context): PendingIntent {
            val sleepIntent = Intent(context, SleepReceiver::class.java)
            return PendingIntent.getBroadcast(
                    context,
                    0,
                    sleepIntent,
                    PendingIntent.FLAG_CANCEL_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        }
    }


   /* private fun writeToFile(data: String, context: Context) {
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
        try {
            File("sleep2.csv").printWriter().use { out ->
                out.println(data);
            }
        } catch (e: IOException) {
            Log.e("Exception", "File write failed: $e")
        }
    }

    private fun sendHttpRequestSegment(startTime: Long, endTime: Long, duration: Long, status: Int, context: Context) {
        // Instantiate the RequestQueue.
        val queue = Volley.newRequestQueue(context)
        val url = "https://tesibe.swipeapp.studio/sample/tesi"

        val json = JSONObject()
        /*"startTime": startTime,
        "endTime": endTime,
        "duration": duration,
        "status": status,*/
        json.put("startTime", startTime)
        json.put("endTime", endTime)
        json.put("duration", duration)
        json.put("status", status)

        val jsonOblect = object : JsonObjectRequest(
                Request.Method.POST,
                url,
                json,
                Response.Listener {response ->
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
    private fun sendHttpRequestClassify(timestampMillis: Long, confidence: Int, light: Int, motion: Int, context: Context) {
        // Instantiate the RequestQueue.
        val queue = Volley.newRequestQueue(context)
        val url = "https://tesibe.swipeapp.studio/sample/tesi"

        val json = JSONObject()
        /*"startTime": startTime,
        "endTime": endTime,
        "duration": duration,
        "status": status,*/
        json.put("timestampMillis", timestampMillis)
        json.put("confidence", confidence)
        json.put("light", light)
        json.put("motion", motion)

        val jsonOblect = object : JsonObjectRequest(
                Request.Method.POST,
                url,
                json,
                Response.Listener {response ->
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
        Log.d("Android Sleep message:", message)
    }
}
