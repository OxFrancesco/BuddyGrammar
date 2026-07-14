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
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
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
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import com.francescooddo.buddygrammar.R
import com.francescooddo.buddygrammar.core.BuddySettings

private val BuddyPurple = Color(0xFF6D4AFF)
private val BuddyIndigo = Color(0xFF4C39D9)
private val BuddyInk = Color(0xFF211B35)
private val BuddyLavender = Color(0xFFF3F0FF)
private val BuddyMint = Color(0xFFE3F8EC)
private val BuddyRed = Color(0xFFB3261E)

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
            body = "Record in the app, transcribe with ElevenLabs, then insert it from the keyboard mic.",
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
    val clipboard = LocalClipboardManager.current
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
                onClick = { clipboard.setText(AnnotatedString(state.transcript)) },
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
        OutlinedTextField(
            value = draft.modelId,
            onValueChange = { draft = draft.copy(modelId = it) },
            modifier = Modifier.fillMaxWidth(),
            label = { Text("OpenRouter model") },
            singleLine = true,
        )
        OutlinedTextField(
            value = draft.correctionInstruction,
            onValueChange = { draft = draft.copy(correctionInstruction = it) },
            modifier = Modifier.fillMaxWidth().height(160.dp),
            label = { Text("Correction instruction") },
        )
        Button(
            onClick = { state.saveSettings(draft.sanitized()) },
            enabled = draft.modelId.isNotBlank() && draft.correctionInstruction.isNotBlank(),
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
        Text(
            "API credentials are never stored in this app. Requests go through the protected BuddyGrammar worker.",
            fontSize = 13.sp,
            color = BuddyInk.copy(alpha = 0.6f),
        )
    }
}

private fun BuddySettings.sanitized(): BuddySettings = copy(
    modelId = modelId.trim(),
    correctionInstruction = correctionInstruction.trim(),
)

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
    Column(modifier = Modifier.fillMaxSize()) {
        SimpleTopBar("Keyboard Lab") { state.navigate(AppScreen.HOME) }
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Text("Tap below to open BuddyGrammar, then press ★. Select a phrase first to correct only that selection.", lineHeight = 22.sp)
            OutlinedTextField(
                value = sample,
                onValueChange = { sample = it },
                modifier = Modifier.fillMaxWidth().height(180.dp),
                label = { Text("Safe test field") },
            )
            Card(colors = CardDefaults.cardColors(containerColor = BuddyLavender)) {
                Text(
                    "The mic key inserts the most recent dictation saved within 24 hours. Password fields disable all cloud actions.",
                    modifier = Modifier.padding(16.dp),
                    fontSize = 14.sp,
                )
            }
        }
    }
}

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
            PrivacyPoint("Only on request", "Text leaves the device only when you tap ★. Audio leaves only after you finish a recording.")
            PrivacyPoint("Protected credentials", "OpenRouter and ElevenLabs keys live on the BuddyGrammar worker and are not bundled with the app or keyboard.")
            PrivacyPoint("Minimal local data", "Settings, a random installation ID, and the latest transcript are stored locally. Transcripts expire from keyboard access after 24 hours.")
            PrivacyPoint("Secure fields", "The keyboard blocks cloud correction and transcript insertion in password and other secure inputs.")
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
