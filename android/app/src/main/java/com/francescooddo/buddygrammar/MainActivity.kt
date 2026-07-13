package com.francescooddo.buddygrammar

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle
import android.provider.Settings
import android.view.inputmethod.InputMethodManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.ContextCompat
import com.francescooddo.buddygrammar.ui.BuddyGrammarApp
import com.francescooddo.buddygrammar.ui.BuddyGrammarAppState

class MainActivity : ComponentActivity() {
    private lateinit var appState: BuddyGrammarAppState

    private val microphonePermission = registerForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) { granted ->
        if (granted) {
            appState.startRecording()
        } else {
            appState.showError("Microphone access is required for speech to text.")
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        appState = BuddyGrammarAppState(this)
        setContent {
            BuddyGrammarApp(
                state = appState,
                onRecord = ::toggleRecording,
                onOpenKeyboardSettings = {
                    startActivity(Intent(Settings.ACTION_INPUT_METHOD_SETTINGS))
                },
                onShowKeyboardPicker = {
                    getSystemService(InputMethodManager::class.java).showInputMethodPicker()
                },
            )
        }
    }

    override fun onResume() {
        super.onResume()
        if (::appState.isInitialized) appState.refresh()
    }

    override fun onStop() {
        if (::appState.isInitialized) appState.cancelRecording()
        super.onStop()
    }

    override fun onDestroy() {
        if (::appState.isInitialized) appState.close()
        super.onDestroy()
    }

    private fun toggleRecording() {
        if (appState.isRecording) {
            appState.stopAndTranscribe()
            return
        }
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            appState.startRecording()
        } else {
            microphonePermission.launch(Manifest.permission.RECORD_AUDIO)
        }
    }
}
