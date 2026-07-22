package com.francescooddo.buddygrammar.ui

import android.Manifest
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.rounded.AutoFixHigh
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.ContentCopy
import androidx.compose.material.icons.rounded.Delete
import androidx.compose.material.icons.rounded.Home
import androidx.compose.material.icons.rounded.Keyboard
import androidx.compose.material.icons.rounded.Mic
import androidx.compose.material.icons.rounded.PrivacyTip
import androidx.compose.material.icons.rounded.Settings
import androidx.compose.material.icons.rounded.Star
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ColorScheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Slider
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import com.francescooddo.buddygrammar.R
import com.francescooddo.buddygrammar.BuildConfig
import com.francescooddo.buddygrammar.core.AppConfig
import com.francescooddo.buddygrammar.core.adaptive.PracticeKind
import com.francescooddo.buddygrammar.core.adaptive.PracticeRecordStatus
import com.francescooddo.buddygrammar.core.adaptive.PracticeResult
import com.francescooddo.buddygrammar.core.adaptive.PracticeTrack
import java.text.DateFormat
import java.util.Date
import kotlin.math.roundToInt

private val BuddyPurple = Color(0xFF6D4AFF)
private val BuddyIndigo = Color(0xFF4C39D9)
private val BuddyInk = Color(0xFF211B35)
private val BuddyLavender = Color(0xFFF3F0FF)
private val BuddyMint = Color(0xFFE3F8EC)
private val BuddyRed = Color(0xFFB3261E)

private enum class LearningResetTarget(val title: String, val message: String) {
    TYPING(
        "Reset touch calibration?",
        "The keyboard will forget its aggregate key offsets.",
    ),
    LANGUAGE(
        "Reset learned words?",
        "The keyboard will forget its local vocabulary and phrase counts.",
    ),
    PRACTICE(
        "Reset practice history?",
        "Adaptive practice will forget its mastery scores and review schedule.",
    ),
    ALL(
        "Reset all learning?",
        "This deletes touch calibration, learned words, and practice progress.",
    ),
}

private val BuddyColors: ColorScheme = lightColorScheme(
    primary = BuddyPurple,
    onPrimary = Color.White,
    primaryContainer = Color(0xFFE8E0FF),
    onPrimaryContainer = BuddyInk,
    secondary = BuddyIndigo,
    background = Color(0xFFFAF9FE),
    surface = Color.White,
    onSurface = BuddyInk,
    error = BuddyRed,
)

@Composable
fun BuddyGrammarApp(
    state: BuddyGrammarAppState,
    onRecord: () -> Unit,
    onOpenKeyboardSettings: () -> Unit,
    onShowKeyboardPicker: () -> Unit,
) {
    MaterialTheme(colorScheme = BuddyColors) {
        Surface(modifier = Modifier.fillMaxSize()) {
            if (state.needsOnboarding) {
                Onboarding(
                    page = state.onboardingPage,
                    onPageChange = state::updateOnboardingPage,
                    onComplete = state::completeOnboarding,
                )
            } else {
                MainShell(
                    state = state,
                    onRecord = onRecord,
                    onOpenKeyboardSettings = onOpenKeyboardSettings,
                    onShowKeyboardPicker = onShowKeyboardPicker,
                )
            }
        }
    }
}

@Composable
private fun Onboarding(
    page: Int,
    onPageChange: (Int) -> Unit,
    onComplete: (Boolean) -> Unit,
) {
    var cloudConsent by remember { mutableStateOf(false) }
    val title = when (page) {
        0 -> "Write with a little magic"
        1 -> "A smarter keyboard everywhere"
        else -> "Your words stay yours"
    }
    val body = when (page) {
        0 -> "Tap ★ to polish the selected text—or the sentence right before your cursor."
        1 -> "Enable BuddyGrammar once, then use its keyboard in messages, notes, email, and more."
        else -> "Text and recordings are processed only when you ask. Provider keys stay on our protected worker, never on your phone."
    }
    val icon = when (page) {
        0 -> Icons.Rounded.AutoFixHigh
        1 -> Icons.Rounded.Keyboard
        else -> Icons.Rounded.PrivacyTip
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(
                Brush.verticalGradient(
                    listOf(Color(0xFFF7F3FF), Color.White, Color(0xFFF1EEFF)),
                ),
            )
            .statusBarsPadding()
            .navigationBarsPadding()
            .padding(28.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.End,
        ) {
            Text("BuddyGrammar", color = BuddyPurple, fontWeight = FontWeight.Bold)
        }
        Spacer(Modifier.weight(1f))
        Box(
            modifier = Modifier
                .size(138.dp)
                .clip(CircleShape)
                .background(
                    Brush.linearGradient(listOf(BuddyPurple, Color(0xFFA058FF))),
                ),
            contentAlignment = Alignment.Center,
        ) {
            Icon(icon, null, tint = Color.White, modifier = Modifier.size(70.dp))
        }
        Spacer(Modifier.height(36.dp))
        Text(
            title,
            fontSize = 32.sp,
            lineHeight = 37.sp,
            fontWeight = FontWeight.ExtraBold,
            textAlign = TextAlign.Center,
            color = BuddyInk,
        )
        Spacer(Modifier.height(14.dp))
        Text(
            body,
            fontSize = 17.sp,
            lineHeight = 25.sp,
            textAlign = TextAlign.Center,
            color = BuddyInk.copy(alpha = 0.72f),
        )
        if (page == 2) {
            Spacer(Modifier.height(22.dp))
            Card(colors = CardDefaults.cardColors(containerColor = Color.White)) {
                Row(
                    modifier = Modifier.padding(12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Checkbox(checked = cloudConsent, onCheckedChange = { cloudConsent = it })
                    Text(
                        "I allow requested text and audio to be securely processed in the cloud.",
                        modifier = Modifier.weight(1f),
                        fontSize = 14.sp,
                    )
                }
            }
        }
        Spacer(Modifier.weight(1f))
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            repeat(3) { index ->
                Box(
                    modifier = Modifier
                        .size(if (index == page) 24.dp else 8.dp, 8.dp)
                        .clip(CircleShape)
                        .background(if (index == page) BuddyPurple else BuddyPurple.copy(alpha = 0.2f)),
                )
            }
        }
        Spacer(Modifier.height(24.dp))
        Button(
            onClick = {
                if (page < 2) onPageChange(page + 1) else onComplete(cloudConsent)
            },
            enabled = page < 2 || cloudConsent,
            modifier = Modifier.fillMaxWidth().height(54.dp),
            shape = RoundedCornerShape(16.dp),
        ) {
            Text(if (page < 2) "Continue" else "Get started", fontWeight = FontWeight.Bold)
        }
        if (page > 0) {
            OutlinedButton(onClick = { onPageChange(page - 1) }, modifier = Modifier.fillMaxWidth()) {
                Text("Back")
            }
        }
    }
}

@Composable
private fun MainShell(
    state: BuddyGrammarAppState,
    onRecord: () -> Unit,
    onOpenKeyboardSettings: () -> Unit,
    onShowKeyboardPicker: () -> Unit,
) {
    val primaryScreens = setOf(AppScreen.HOME, AppScreen.DICTATION, AppScreen.SETTINGS)
    Scaffold(
        bottomBar = {
            if (state.screen in primaryScreens) {
                NavigationBar(modifier = Modifier.navigationBarsPadding()) {
                    NavigationItem("Home", Icons.Rounded.Home, state.screen == AppScreen.HOME) {
                        state.navigate(AppScreen.HOME)
                    }
                    NavigationItem("Dictate", Icons.Rounded.Mic, state.screen == AppScreen.DICTATION) {
                        state.navigate(AppScreen.DICTATION)
                    }
                    NavigationItem("Settings", Icons.Rounded.Settings, state.screen == AppScreen.SETTINGS) {
                        state.navigate(AppScreen.SETTINGS)
                    }
                }
            }
        },
    ) { padding ->
        Box(modifier = Modifier.padding(padding).fillMaxSize()) {
            when (state.screen) {
                AppScreen.HOME -> HomeScreen(
                    state = state,
                    onOpenKeyboardSettings = onOpenKeyboardSettings,
                    onShowKeyboardPicker = onShowKeyboardPicker,
                )
                AppScreen.DICTATION -> DictationScreen(state, onRecord)
                AppScreen.SETTINGS -> SettingsScreen(state, onOpenKeyboardSettings)
                AppScreen.KEYBOARD_LAB -> KeyboardLabScreen(state)
                AppScreen.PRIVACY -> PrivacyScreen(state)
            }
        }
    }
}

@Composable
private fun androidx.compose.foundation.layout.RowScope.NavigationItem(
    label: String,
    icon: ImageVector,
    selected: Boolean,
    onClick: () -> Unit,
) {
    NavigationBarItem(
        selected = selected,
        onClick = onClick,
        icon = { Icon(icon, label) },
        label = { Text(label) },
    )
}

@Composable
private fun HomeScreen(
    state: BuddyGrammarAppState,
    onOpenKeyboardSettings: () -> Unit,
    onShowKeyboardPicker: () -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .statusBarsPadding()
            .padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Card(
            colors = CardDefaults.cardColors(containerColor = Color.Transparent),
            modifier = Modifier.fillMaxWidth(),
        ) {
            Column(
                modifier = Modifier
                    .background(Brush.linearGradient(listOf(BuddyPurple, Color(0xFF9156F8))))
                    .padding(24.dp),
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Box(
                        modifier = Modifier
                            .size(56.dp)
                            .clip(RoundedCornerShape(14.dp))
                            .background(Color.White),
                        contentAlignment = Alignment.Center,
                    ) {
                        Image(
                            painter = painterResource(R.drawable.buddygrammar_logo),
                            contentDescription = "BuddyGrammar logo",
                            modifier = Modifier.size(46.dp),
                        )
                    }
                    Spacer(Modifier.size(14.dp))
                    Icon(Icons.Rounded.Star, null, tint = Color(0xFFFFE278), modifier = Modifier.size(40.dp))
                }
                Spacer(Modifier.height(18.dp))
                Text("Make every sentence shine.", color = Color.White, fontSize = 29.sp, fontWeight = FontWeight.ExtraBold)
                Spacer(Modifier.height(8.dp))
                Text("Use ★ from the BuddyGrammar keyboard to correct text in any app.", color = Color.White.copy(alpha = 0.88f), lineHeight = 22.sp)
            }
        }

        NoticeBanner(state.notice)

        state.pendingTranscript?.let { pending ->
            Card(colors = CardDefaults.cardColors(containerColor = BuddyMint)) {
                Column(
                    modifier = Modifier.fillMaxWidth().padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Text("Ready for keyboard", fontWeight = FontWeight.Bold)
                    Text(
                        pending.text,
                        color = BuddyInk.copy(alpha = 0.72f),
                        maxLines = 4,
                    )
                    OutlinedButton(onClick = state::clearTranscript) {
                        Icon(Icons.Rounded.Delete, null)
                        Spacer(Modifier.size(6.dp))
                        Text("Clear")
                    }
                }
            }
        }

        MicrophonePermissionCard()

        Text("Keyboard setup", fontWeight = FontWeight.Bold, fontSize = 20.sp)
        StatusRow("BuddyGrammar enabled", state.keyboardEnabled)
        StatusRow("BuddyGrammar selected", state.keyboardSelected)
        if (!state.keyboardEnabled) {
            Button(onClick = onOpenKeyboardSettings, modifier = Modifier.fillMaxWidth()) {
                Icon(Icons.Rounded.Keyboard, null)
                Spacer(Modifier.size(8.dp))
                Text("Enable BuddyGrammar keyboard")
            }
        } else if (!state.keyboardSelected) {
            Button(onClick = onShowKeyboardPicker, modifier = Modifier.fillMaxWidth()) {
                Text("Choose BuddyGrammar now")
            }
        }

        FeatureCard(
            icon = Icons.Rounded.Keyboard,
            title = "Try the keyboard",
            body = "Open a safe text field and test typing, ★ correction, and transcript insertion.",
            action = "Open Keyboard Lab",
        ) { state.navigate(AppScreen.KEYBOARD_LAB) }
        FeatureCard(
            icon = Icons.Rounded.Mic,
            title = "Speech to text",
            body = "Record in the app, transcribe with ElevenLabs, then insert it with the keyboard’s Saved dictation action.",
            action = "Start dictating",
        ) { state.navigate(AppScreen.DICTATION) }
    }
}

@Composable
private fun MicrophonePermissionCard() {
    val context = LocalContext.current
    var micGranted by remember {
        mutableStateOf(
            ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) ==
                PackageManager.PERMISSION_GRANTED,
        )
    }
    val micPermissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) { granted -> micGranted = granted }
    if (micGranted) return

    Card(colors = CardDefaults.cardColors(containerColor = BuddyLavender)) {
        Column(
            modifier = Modifier.fillMaxWidth().padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Rounded.Mic, null, tint = BuddyPurple)
                Spacer(Modifier.size(10.dp))
                Text("Microphone for voice typing", fontWeight = FontWeight.Bold)
            }
            Text(
                "The keyboard's voice typing and dictation need microphone access. " +
                    "Keyboards cannot ask for it themselves, so grant it here once.",
                fontSize = 13.sp,
                color = BuddyInk.copy(alpha = 0.7f),
                lineHeight = 19.sp,
            )
            Button(onClick = { micPermissionLauncher.launch(Manifest.permission.RECORD_AUDIO) }) {
                Text("Allow microphone")
            }
        }
    }
}

@Composable
private fun StatusRow(label: String, complete: Boolean) {
    Card(colors = CardDefaults.cardColors(containerColor = if (complete) BuddyMint else BuddyLavender)) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(14.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(
                if (complete) Icons.Rounded.CheckCircle else Icons.Rounded.Keyboard,
                null,
                tint = if (complete) Color(0xFF198754) else BuddyPurple,
            )
            Spacer(Modifier.size(10.dp))
            Text(label, modifier = Modifier.weight(1f), fontWeight = FontWeight.SemiBold)
            Text(if (complete) "Ready" else "Action needed", fontSize = 12.sp)
        }
    }
}

@Composable
private fun FeatureCard(
    icon: ImageVector,
    title: String,
    body: String,
    action: String,
    onClick: () -> Unit,
) {
    Card(colors = CardDefaults.cardColors(containerColor = Color.White)) {
        Column(modifier = Modifier.padding(18.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Icon(icon, null, tint = BuddyPurple)
            Text(title, fontWeight = FontWeight.Bold, fontSize = 18.sp)
            Text(body, color = BuddyInk.copy(alpha = 0.7f), lineHeight = 21.sp)
            FilledTonalButton(onClick = onClick) { Text(action) }
        }
    }
}

@Composable
private fun DictationScreen(state: BuddyGrammarAppState, onRecord: () -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .statusBarsPadding()
            .padding(20.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Text("Dictation", fontSize = 30.sp, fontWeight = FontWeight.ExtraBold, modifier = Modifier.fillMaxWidth())
        Text(
            "ElevenLabs turns your recording into text. Auto-correction can polish it before it reaches the keyboard.",
            color = BuddyInk.copy(alpha = 0.7f),
            lineHeight = 22.sp,
        )
        NoticeBanner(state.notice)
        Button(
            onClick = onRecord,
            enabled = !state.isProcessing,
            modifier = Modifier
                .size(132.dp)
                .semantics { contentDescription = if (state.isRecording) "Stop recording" else "Start recording" },
            shape = CircleShape,
            colors = ButtonDefaults.buttonColors(
                containerColor = if (state.isRecording) BuddyRed else BuddyPurple,
            ),
        ) {
            if (state.isProcessing) {
                CircularProgressIndicator(color = Color.White)
            } else {
                Icon(if (state.isRecording) Icons.Rounded.CheckCircle else Icons.Rounded.Mic, null, modifier = Modifier.size(54.dp))
            }
        }
        Text(
            when {
                state.isProcessing -> "Processing…"
                state.isRecording -> "Tap to stop"
                else -> "Tap to record"
            },
            fontWeight = FontWeight.Bold,
        )
        if (state.isRecording) {
            OutlinedButton(onClick = state::cancelRecording) {
                Text("Discard recording", color = BuddyRed)
            }
        }
        state.detectedLanguage?.let { Text("Detected language: ${it.uppercase()}", fontSize = 13.sp) }
        OutlinedTextField(
            value = state.transcript,
            onValueChange = state::updateTranscript,
            modifier = Modifier.fillMaxWidth().height(190.dp),
            label = { Text("Transcript") },
            placeholder = { Text("Your transcription will appear here.") },
            enabled = !state.isProcessing && !state.isRecording,
        )
        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Button(
                onClick = state::saveTranscript,
                enabled = !state.isProcessing && !state.isRecording,
                modifier = Modifier.weight(1f),
            ) { Text("Save for keyboard") }
            FilledTonalButton(
                onClick = state::copyTranscript,
                enabled = state.transcript.isNotBlank() && !state.isProcessing && !state.isRecording,
            ) { Icon(Icons.Rounded.ContentCopy, "Copy transcript") }
            FilledTonalButton(
                onClick = state::clearTranscript,
                enabled = state.transcript.isNotBlank() && !state.isProcessing && !state.isRecording,
            ) {
                Icon(Icons.Rounded.Delete, "Clear transcript")
            }
        }
    }
}

@Composable
private fun SettingsScreen(state: BuddyGrammarAppState, onOpenKeyboardSettings: () -> Unit) {
    var draft by remember(state.settings) { mutableStateOf(state.settings) }
    var resetTarget by remember { mutableStateOf<LearningResetTarget?>(null) }
    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .statusBarsPadding()
            .padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Text("Settings", fontSize = 30.sp, fontWeight = FontWeight.ExtraBold)
        NoticeBanner(state.notice)
        SettingSwitch(
            title = "Cloud processing",
            body = "Required for ★ correction and ElevenLabs transcription.",
            checked = draft.hasAcceptedCloudProcessing,
        ) { draft = draft.copy(hasAcceptedCloudProcessing = it) }
        SettingSwitch(
            title = "Auto-correct dictation",
            body = "Polish the transcript before saving it for the keyboard.",
            checked = draft.autoCorrectDictation,
        ) { draft = draft.copy(autoCorrectDictation = it) }
        SettingSwitch(
            title = "Copy completed dictation",
            body = "Automatically place completed transcripts on the system clipboard. Off by default; the Copy button always remains available.",
            checked = draft.copiesCompletedDictationToClipboard,
        ) { draft = draft.copy(copiesCompletedDictationToClipboard = it) }
        SettingSwitch(
            title = "Correct words while typing",
            body = "Fix clear keyboard typos on-device when you type punctuation, space, or return.",
            checked = draft.automaticallyCorrectWords,
        ) { draft = draft.copy(automaticallyCorrectWords = it) }
        SettingSwitch(
            title = "Adapt key hit areas",
            body = "Bias ambiguous key edges on-device while every key keeps a literal center.",
            checked = draft.adaptiveTypingEnabled,
        ) { draft = draft.copy(adaptiveTypingEnabled = it) }
        SettingSwitch(
            title = "Personalize practice",
            body = "Choose exercises from your local mastery and review schedule.",
            checked = draft.personalizedPracticeEnabled,
        ) { draft = draft.copy(personalizedPracticeEnabled = it) }
        SettingSwitch(
            title = "Update correction model automatically",
            body = "Use BuddyGrammar’s current recommended OpenRouter model.",
            checked = draft.usesAutomaticModelUpdates,
        ) {
            draft = draft.copy(
                usesAutomaticModelUpdates = it,
                modelId = if (it) AppConfig.DEFAULT_MODEL else draft.modelId,
            )
        }
        OutlinedTextField(
            value = draft.modelId,
            onValueChange = { draft = draft.copy(modelId = it) },
            modifier = Modifier.fillMaxWidth(),
            label = { Text("OpenRouter model") },
            singleLine = true,
            enabled = !draft.usesAutomaticModelUpdates,
        )
        OutlinedTextField(
            value = draft.correctionInstruction,
            onValueChange = { draft = draft.copy(correctionInstruction = it) },
            modifier = Modifier.fillMaxWidth().height(160.dp),
            label = { Text("Correction instruction") },
        )
        Text(
            "Star undo window: ${draft.correctionUndoDurationSeconds} seconds",
            fontWeight = FontWeight.Bold,
        )
        Slider(
            value = draft.correctionUndoDurationSeconds.toFloat(),
            onValueChange = {
                draft = draft.copy(correctionUndoDurationSeconds = it.roundToInt())
            },
            valueRange = 1f..10f,
            steps = 8,
        )
        Text(
            "After a ★ correction, Undo stays available for this duration.",
            fontSize = 13.sp,
            color = BuddyInk.copy(alpha = 0.6f),
        )
        Button(
            onClick = { state.saveSettings(draft.normalized()) },
            enabled = (draft.usesAutomaticModelUpdates || draft.modelId.isNotBlank()) &&
                draft.correctionInstruction.isNotBlank(),
            modifier = Modifier.fillMaxWidth(),
        ) { Text("Save settings") }
        HorizontalDivider()
        OutlinedButton(onClick = onOpenKeyboardSettings, modifier = Modifier.fillMaxWidth()) {
            Icon(Icons.Rounded.Keyboard, null)
            Spacer(Modifier.size(8.dp))
            Text("Android keyboard settings")
        }
        OutlinedButton(onClick = { state.navigate(AppScreen.PRIVACY) }, modifier = Modifier.fillMaxWidth()) {
            Icon(Icons.Rounded.PrivacyTip, null)
            Spacer(Modifier.size(8.dp))
            Text("Privacy and data flow")
        }
        HorizontalDivider()
        Text("On-device learning", fontWeight = FontWeight.Bold)
        Text(
            "Reset each private aggregate independently. Your visible keyboard layout and cloud consent do not change.",
            fontSize = 13.sp,
            color = BuddyInk.copy(alpha = 0.65f),
        )
        OutlinedButton(
            onClick = { resetTarget = LearningResetTarget.TYPING },
            modifier = Modifier.fillMaxWidth(),
            colors = ButtonDefaults.outlinedButtonColors(contentColor = BuddyRed),
        ) { Text("Reset touch calibration") }
        OutlinedButton(
            onClick = { resetTarget = LearningResetTarget.LANGUAGE },
            modifier = Modifier.fillMaxWidth(),
            colors = ButtonDefaults.outlinedButtonColors(contentColor = BuddyRed),
        ) { Text("Reset learned words") }
        OutlinedButton(
            onClick = { resetTarget = LearningResetTarget.PRACTICE },
            modifier = Modifier.fillMaxWidth(),
            colors = ButtonDefaults.outlinedButtonColors(contentColor = BuddyRed),
        ) { Text("Reset practice history") }
        OutlinedButton(
            onClick = { resetTarget = LearningResetTarget.ALL },
            modifier = Modifier.fillMaxWidth(),
            colors = ButtonDefaults.outlinedButtonColors(contentColor = BuddyRed),
        ) { Text("Reset all learning") }
        Text(
            "API credentials are never stored in this app. Requests go through the protected BuddyGrammar worker.",
            fontSize = 13.sp,
            color = BuddyInk.copy(alpha = 0.6f),
        )
        HorizontalDivider()
        Text("About", fontWeight = FontWeight.Bold)
        Text("Version ${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})")
    }

    resetTarget?.let { target ->
        AlertDialog(
            onDismissRequest = { resetTarget = null },
            title = { Text(target.title) },
            text = { Text(target.message) },
            confirmButton = {
                TextButton(
                    onClick = {
                        when (target) {
                            LearningResetTarget.TYPING -> state.resetTypingCalibration()
                            LearningResetTarget.LANGUAGE -> state.resetLearnedWords()
                            LearningResetTarget.PRACTICE -> state.resetPracticeProgress()
                            LearningResetTarget.ALL -> state.resetAllLearning()
                        }
                        resetTarget = null
                    },
                ) { Text("Reset", color = BuddyRed) }
            },
            dismissButton = {
                TextButton(onClick = { resetTarget = null }) { Text("Cancel") }
            },
        )
    }
}

@Composable
private fun SettingSwitch(
    title: String,
    body: String,
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit,
) {
    Card(colors = CardDefaults.cardColors(containerColor = BuddyLavender)) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(16.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(title, fontWeight = FontWeight.Bold)
                Text(body, fontSize = 13.sp, color = BuddyInk.copy(alpha = 0.65f))
            }
            Switch(checked = checked, onCheckedChange = onCheckedChange)
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun KeyboardLabScreen(state: BuddyGrammarAppState) {
    var sample by remember { mutableStateOf("this sentence need a little polish") }
    val prompt = state.practicePrompt
    val result = state.practiceResult
    Column(modifier = Modifier.fillMaxSize()) {
        SimpleTopBar("Keyboard Lab") { state.navigate(AppScreen.HOME) }
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Text("Adaptive practice", fontSize = 26.sp, fontWeight = FontWeight.ExtraBold)
            Text(
                "Build typing accuracy and writing recall with short exercises selected from local progress.",
                color = BuddyInk.copy(alpha = 0.7f),
                lineHeight = 22.sp,
            )
            NoticeBanner(state.notice)
            PracticeSummaryCard(state.practiceSummary)
            PracticeTrackSelector(
                selected = state.practiceTrack,
                onSelect = state::selectPracticeTrack,
            )
            if (!state.settings.personalizedPracticeEnabled) {
                Card(colors = CardDefaults.cardColors(containerColor = BuddyLavender)) {
                    Text(
                        "Personalized scheduling is off. This session is still scored, but progress is not saved.",
                        modifier = Modifier.padding(16.dp),
                        fontSize = 14.sp,
                    )
                }
            }
            if (prompt != null) {
                Card(
                    colors = CardDefaults.cardColors(containerColor = Color.White),
                    elevation = CardDefaults.cardElevation(defaultElevation = 2.dp),
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Column(
                        modifier = Modifier.padding(18.dp),
                        verticalArrangement = Arrangement.spacedBy(14.dp),
                    ) {
                        Text(
                            prompt.kind.displayName(),
                            color = BuddyPurple,
                            fontSize = 13.sp,
                            fontWeight = FontWeight.Bold,
                        )
                        Text(prompt.instruction, fontSize = 18.sp, fontWeight = FontWeight.Bold)
                        prompt.stimulus?.let { stimulus ->
                            Card(colors = CardDefaults.cardColors(containerColor = BuddyLavender)) {
                                Text(
                                    stimulus,
                                    modifier = Modifier.fillMaxWidth().padding(16.dp),
                                    textAlign = TextAlign.Center,
                                    fontSize = 19.sp,
                                    fontWeight = FontWeight.SemiBold,
                                )
                            }
                        }
                        OutlinedTextField(
                            value = state.practiceResponse,
                            onValueChange = state::updatePracticeResponse,
                            modifier = Modifier
                                .fillMaxWidth()
                                .height(132.dp)
                                .onFocusChanged {
                                    state.setPracticeEditorActive(it.isFocused)
                                },
                            label = { Text("Your response") },
                            placeholder = { Text("Type without copying or using suggestions when you can.") },
                            enabled = result == null,
                            keyboardOptions = KeyboardOptions(
                                capitalization = KeyboardCapitalization.Sentences,
                                autoCorrectEnabled = false,
                            ),
                        )
                        if (result == null) {
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.spacedBy(10.dp),
                            ) {
                                Button(
                                    onClick = state::submitPracticeAttempt,
                                    enabled = state.practiceResponse.isNotBlank(),
                                    modifier = Modifier.weight(1f),
                                ) { Text("Submit") }
                                OutlinedButton(
                                    onClick = state::skipPracticePrompt,
                                    modifier = Modifier.weight(1f),
                                ) { Text("Skip") }
                            }
                        } else {
                            PracticeResultCard(result)
                            Button(
                                onClick = state::nextPracticePrompt,
                                modifier = Modifier.fillMaxWidth(),
                            ) { Text("Next exercise") }
                        }
                    }
                }
            }
            OutlinedButton(
                onClick = state::resetPracticeProgress,
                modifier = Modifier.fillMaxWidth(),
            ) {
                Icon(Icons.Rounded.Delete, null)
                Spacer(Modifier.size(8.dp))
                Text("Reset practice progress")
            }
            HorizontalDivider()
            Text("Freeform keyboard test", fontSize = 22.sp, fontWeight = FontWeight.ExtraBold)
            Text(
                "Tap below to open BuddyGrammar, then press ★. Select a phrase first to correct only that selection.",
                lineHeight = 22.sp,
            )
            OutlinedTextField(
                value = sample,
                onValueChange = { sample = it },
                modifier = Modifier
                    .fillMaxWidth()
                    .height(180.dp)
                    .onFocusChanged {
                        if (it.isFocused) state.setPracticeEditorActive(false)
                    },
                label = { Text("Safe test field") },
            )
            Card(colors = CardDefaults.cardColors(containerColor = BuddyLavender)) {
                Text(
                    "Saved dictation inserts the most recent app recording kept for up to 24 hours. Password fields disable cloud and speech actions.",
                    modifier = Modifier.padding(16.dp),
                    fontSize = 14.sp,
                )
            }
        }
    }
}

@Composable
private fun PracticeTrackSelector(
    selected: PracticeTrack,
    onSelect: (PracticeTrack) -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text("Practice focus", fontWeight = FontWeight.Bold)
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            PracticeTrack.entries.forEach { track ->
                if (track == selected) {
                    FilledTonalButton(
                        onClick = { onSelect(track) },
                        modifier = Modifier.weight(1f),
                    ) { Text(track.displayName()) }
                } else {
                    OutlinedButton(
                        onClick = { onSelect(track) },
                        modifier = Modifier.weight(1f),
                    ) { Text(track.displayName()) }
                }
            }
        }
    }
}

@Composable
private fun PracticeSummaryCard(summary: PracticeProgressSummary) {
    val reviewText = when {
        summary.reviewIsDue -> "Due now"
        summary.nextReviewAtEpochMillis != null -> DateFormat.getDateTimeInstance(
            DateFormat.MEDIUM,
            DateFormat.SHORT,
        ).format(Date(summary.nextReviewAtEpochMillis))
        else -> "After your first scored exercise"
    }
    Card(colors = CardDefaults.cardColors(containerColor = BuddyMint)) {
        Column(
            modifier = Modifier.fillMaxWidth().padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Text("Mastery and retention", fontWeight = FontWeight.Bold, fontSize = 17.sp)
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                PracticeMetric("Attempts", summary.completedAttempts.toString())
                PracticeMetric("Accuracy", summary.averageAccuracy.asPercentage())
                PracticeMetric("Mastery", summary.averageMastery.asPercentage())
            }
            Text(
                "${summary.trackedSkills} skills tracked · Next review: $reviewText",
                fontSize = 13.sp,
                color = BuddyInk.copy(alpha = 0.7f),
            )
        }
    }
}

@Composable
private fun androidx.compose.foundation.layout.RowScope.PracticeMetric(
    label: String,
    value: String,
) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Text(value, fontWeight = FontWeight.ExtraBold, fontSize = 19.sp)
        Text(label, fontSize = 12.sp, color = BuddyInk.copy(alpha = 0.65f))
    }
}

@Composable
private fun PracticeResultCard(result: PracticeResult) {
    val title = when (result.status) {
        PracticeRecordStatus.RECORDED -> "Exercise scored"
        PracticeRecordStatus.ABANDONED -> "Exercise skipped"
        PracticeRecordStatus.HOLDOUT -> "Retention check scored"
    }
    Card(colors = CardDefaults.cardColors(containerColor = BuddyMint)) {
        Column(
            modifier = Modifier.fillMaxWidth().padding(14.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            Text(title, fontWeight = FontWeight.Bold)
            Text("Typed accuracy: ${result.rawAccuracy.asPercentage()}")
            if (result.decodedAccuracy != result.rawAccuracy) {
                Text("Keyboard-assisted accuracy: ${result.decodedAccuracy.asPercentage()}")
            }
            Text(
                "Learning evidence: ${(result.evidenceWeight.coerceIn(0.0, 1.5) / 1.5).asPercentage()}",
                fontSize = 13.sp,
                color = BuddyInk.copy(alpha = 0.7f),
            )
        }
    }
}

private fun PracticeTrack.displayName(): String = when (this) {
    PracticeTrack.MOTOR -> "Typing"
    PracticeTrack.WRITING -> "Writing"
    PracticeTrack.MIXED -> "Mixed"
}

private fun PracticeKind.displayName(): String = when (this) {
    PracticeKind.COPY -> "Copy"
    PracticeKind.CLOZE -> "Fill the blank"
    PracticeKind.CORRECTION -> "Correction"
    PracticeKind.RECONSTRUCTION -> "Recall"
    PracticeKind.FREE_PRODUCTION -> "Free writing"
    PracticeKind.MIXED_TRANSFER -> "Transfer"
}

private fun Double.asPercentage(): String = "${(coerceIn(0.0, 1.0) * 100).roundToInt()}%"

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun PrivacyScreen(state: BuddyGrammarAppState) {
    Column(modifier = Modifier.fillMaxSize()) {
        SimpleTopBar("Privacy") { state.navigate(AppScreen.SETTINGS) }
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(18.dp),
        ) {
            Text("Last updated July 21, 2026", color = BuddyInk.copy(alpha = 0.6f))
            PrivacyPoint("What stays on your device", "Normal keyboard input is not sent anywhere. Learned vocabulary, bounded key-offset aggregates, and practice mastery remain local. BuddyGrammar keeps no readable touch history and includes no advertising or analytics SDKs.")
            PrivacyPoint("Star corrections", "When you tap ★ after allowing cloud processing, the selected text or current sentence, correction instruction, and model choice are sent through the BuddyGrammar service to OpenRouter. If ML Kit cannot read handwriting, a normalized black-and-white image can use the same AI fallback. Zero-data-retention routing is requested from OpenRouter.")
            PrivacyPoint("Speech to text", "Direct keyboard voice typing uses your device’s selected Android speech-recognition service. Depending on that service and its settings, audio may be processed on-device or streamed to its provider; BuddyGrammar receives only the returned transcript. Recordings made in the app are sent through the BuddyGrammar service to ElevenLabs and retried once after a failed request. Automatic correction then sends the transcript to OpenRouter. Temporary recording files are deleted after processing.")
            PrivacyPoint("On-device personalization", "Language-scoped vocabulary, context counts, bounded aggregate touch offsets, and practice mastery stay on this device. Practice responses are never saved, and its curated target marker expires after 30 minutes.")
            PrivacyPoint("Accounts, retention, and deletion", "The BuddyGrammar service forwards requested content and does not intentionally log or store it. Provider retention depends on the configured OpenRouter, ElevenLabs, and model-provider settings. Settings can revoke cloud consent and reset touch calibration, learned words, practice history, or all learning independently.")
            PrivacyPoint("Minimal local data", "Settings, a random installation ID, and the latest raw transcript and final text are stored locally until you clear them. The keyboard handoff copy expires after 24 hours or is removed after insertion. Completed dictation reaches the system clipboard automatically only when you enable that setting; manual Copy is always explicit.")
            PrivacyPoint("Secure fields", "The keyboard blocks cloud correction, handwriting fallback, voice typing, and transcript insertion in password and other secure inputs.")
        }
    }
}

@Composable
private fun PrivacyPoint(title: String, body: String) {
    Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Icon(Icons.Rounded.CheckCircle, null, tint = Color(0xFF198754))
        Column {
            Text(title, fontWeight = FontWeight.Bold, fontSize = 17.sp)
            Text(body, color = BuddyInk.copy(alpha = 0.7f), lineHeight = 21.sp)
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SimpleTopBar(title: String, onBack: () -> Unit) {
    TopAppBar(
        title = { Text(title, fontWeight = FontWeight.Bold) },
        navigationIcon = {
            IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Rounded.ArrowBack, "Back") }
        },
        colors = TopAppBarDefaults.topAppBarColors(containerColor = Color.White),
        modifier = Modifier.statusBarsPadding(),
    )
}

@Composable
private fun NoticeBanner(notice: AppNotice?) {
    if (notice == null) return
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = if (notice.isError) Color(0xFFFFE9E7) else BuddyMint,
        ),
    ) {
        Text(
            notice.message,
            modifier = Modifier.padding(13.dp),
            color = if (notice.isError) BuddyRed else Color(0xFF146C43),
            fontSize = 14.sp,
        )
    }
}
