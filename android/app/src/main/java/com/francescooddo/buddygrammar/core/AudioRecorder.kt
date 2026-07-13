package com.francescooddo.buddygrammar.core

import android.content.Context
import android.media.MediaRecorder
import android.os.Build
import java.io.File

class AudioRecorder(private val context: Context) {
    private var recorder: MediaRecorder? = null
    private var outputFile: File? = null

    @Suppress("DEPRECATION")
    fun start() {
        check(recorder == null) { "A recording is already active." }
        val file = File.createTempFile("buddygrammar-", ".m4a", context.cacheDir)
        val mediaRecorder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            MediaRecorder(context)
        } else {
            MediaRecorder()
        }
        try {
            mediaRecorder.setAudioSource(MediaRecorder.AudioSource.MIC)
            mediaRecorder.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
            mediaRecorder.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
            mediaRecorder.setAudioSamplingRate(44_100)
            mediaRecorder.setAudioEncodingBitRate(96_000)
            mediaRecorder.setOutputFile(file.absolutePath)
            mediaRecorder.prepare()
            mediaRecorder.start()
            recorder = mediaRecorder
            outputFile = file
        } catch (error: Throwable) {
            mediaRecorder.release()
            file.delete()
            throw error
        }
    }

    fun stop(): File {
        val activeRecorder = checkNotNull(recorder) { "No recording is active." }
        val file = checkNotNull(outputFile)
        recorder = null
        outputFile = null
        try {
            activeRecorder.stop()
            return file
        } catch (error: Throwable) {
            file.delete()
            throw error
        } finally {
            activeRecorder.release()
        }
    }

    fun cancel() {
        val activeRecorder = recorder
        recorder = null
        runCatching { activeRecorder?.stop() }
        activeRecorder?.release()
        outputFile?.delete()
        outputFile = null
    }
}
