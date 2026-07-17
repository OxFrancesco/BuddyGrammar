package com.francescooddo.buddygrammar.ime

import android.os.Build
import android.view.inputmethod.EditorInfo
import androidx.compose.animation.animateContentSize
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsIgnoringVisibility
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.windowInsetsBottomHeight
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowForward
import androidx.compose.material.icons.automirrored.rounded.Backspace
import androidx.compose.material.icons.automirrored.rounded.KeyboardReturn
import androidx.compose.material.icons.automirrored.rounded.KeyboardTab
import androidx.compose.material.icons.automirrored.rounded.Send
import androidx.compose.material.icons.automirrored.rounded.Undo
import androidx.compose.material.icons.rounded.ArrowUpward
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.Delete
import androidx.compose.material.icons.rounded.Draw
import androidx.compose.material.icons.rounded.EmojiEmotions
import androidx.compose.material.icons.rounded.Functions
import androidx.compose.material.icons.rounded.GraphicEq
import androidx.compose.material.icons.rounded.KeyboardCapslock
import androidx.compose.material.icons.rounded.Language
import androidx.compose.material.icons.rounded.Mic
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material.icons.rounded.Star
import androidx.compose.material.icons.rounded.Stop
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.emoji2.emojipicker.EmojiPickerView
import com.francescooddo.buddygrammar.core.Suggestion
import com.francescooddo.buddygrammar.core.SuggestionKind

private val BuddyPurple = Color(0xFF6D4AFF)

private val KeyShape = RoundedCornerShape(9.dp)

@Composable
fun BuddyKeyboardTheme(content: @Composable () -> Unit) {
    val darkTheme = isSystemInDarkTheme()
    val context = LocalContext.current
    val colorScheme = when {
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.S ->
            if (darkTheme) dynamicDarkColorScheme(context) else dynamicLightColorScheme(context)
        darkTheme -> darkColorScheme(primary = BuddyPurple)
        else -> lightColorScheme(primary = BuddyPurple)
    }
    MaterialTheme(colorScheme = colorScheme, content = content)
}

@Composable
fun KeyboardScreen(service: BuddyGrammarImeService) {
    BuddyKeyboardTheme {
        Surface(color = MaterialTheme.colorScheme.surfaceContainer) {
            val layout = keyboardLayoutSpec()
            Column(
                modifier = Modifier.fillMaxWidth(),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = layout.sidePaddingDp.dp, vertical = 6.dp)
                        .animateContentSize(),
                    verticalArrangement = Arrangement.spacedBy(5.dp),
                ) {
                    SuggestionStrip(service)
                    when (service.keyboardState.layer) {
                        KeyboardLayer.LETTERS -> LettersLayer(service)
                        KeyboardLayer.NUMBERS -> NumbersLayer(service)
                        KeyboardLayer.SYMBOLS -> SymbolsLayer(service)
                        KeyboardLayer.LATEX -> LatexLayer(service)
                        KeyboardLayer.EMOJI -> EmojiLayer(service)
                        KeyboardLayer.HANDWRITING -> HandwritingLayer(service)
                        KeyboardLayer.VOICE -> VoiceLayer(service)
                    }
                }
                SystemNavigationBarSpace(layout)
            }
        }
    }
}

@Composable
private fun keyboardLayoutSpec(): KeyboardLayoutSpec {
    val configuration = LocalConfiguration.current
    return KeyboardLayoutPolicy.resolve(
        screenWidthDp = configuration.screenWidthDp,
        screenHeightDp = configuration.screenHeightDp,
    )
}

/** Keeps the platform IME switcher, gesture handle, and hide button below our keys. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun SystemNavigationBarSpace(layout: KeyboardLayoutSpec) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(bottom = layout.navigationBarSafetyGapDp.dp)
            .heightIn(min = layout.minimumNavigationBarHeightDp.dp)
            .windowInsetsBottomHeight(WindowInsets.navigationBarsIgnoringVisibility),
    ) {
        HorizontalDivider(
            color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.45f),
        )
    }
}

// region Suggestion strip

@Composable
private fun SuggestionStrip(service: BuddyGrammarImeService) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .height(40.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        val status = service.status
        if (service.canUndoCorrection) {
            Surface(
                onClick = service::undoLastCorrection,
                modifier = Modifier
                    .weight(1f)
                    .height(34.dp)
                    .semantics { contentDescription = "Undo star correction" },
                shape = RoundedCornerShape(8.dp),
                color = MaterialTheme.colorScheme.primaryContainer,
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.Center,
                ) {
                    Icon(
                        Icons.AutoMirrored.Rounded.Undo,
                        contentDescription = null,
                        modifier = Modifier.size(18.dp),
                    )
                    Text(
                        "Undo",
                        modifier = Modifier.padding(start = 6.dp),
                        fontWeight = FontWeight.SemiBold,
                    )
                }
            }
        } else if (status != null) {
            Text(
                text = status.message,
                modifier = Modifier
                    .weight(1f)
                    .padding(horizontal = 8.dp)
                    .semantics { contentDescription = "BuddyGrammar keyboard status" },
                color = if (status.isError) {
                    MaterialTheme.colorScheme.error
                } else {
                    MaterialTheme.colorScheme.onSurfaceVariant
                },
                fontSize = 13.sp,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        } else {
            val suggestions = service.suggestions
            if (suggestions.isEmpty()) {
                Spacer(Modifier.weight(1f))
            } else {
                suggestions.forEach { suggestion ->
                    SuggestionSlot(
                        suggestion = suggestion,
                        modifier = Modifier.weight(1f),
                        onClick = { service.applySuggestion(suggestion) },
                    )
                }
            }
        }
        KeyboardModeButton(
            icon = Icons.Rounded.Functions,
            description = "LaTeX keyboard",
            selected = service.keyboardState.layer == KeyboardLayer.LATEX,
            onClick = { service.setLayer(KeyboardLayer.LATEX) },
        )
        KeyboardModeButton(
            icon = Icons.Rounded.Draw,
            description = "Handwriting",
            selected = service.keyboardState.layer == KeyboardLayer.HANDWRITING,
            onClick = { service.setLayer(KeyboardLayer.HANDWRITING) },
        )
        IconButton(
            onClick = service::insertPendingTranscript,
            modifier = Modifier.size(38.dp),
        ) {
            Icon(
                Icons.Rounded.GraphicEq,
                contentDescription = "Insert latest BuddyGrammar dictation",
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        if (service.isCorrecting) {
            Box(modifier = Modifier.size(38.dp), contentAlignment = Alignment.Center) {
                CircularProgressIndicator(modifier = Modifier.size(20.dp), strokeWidth = 2.dp)
            }
        } else {
            IconButton(
                onClick = service::correctCurrentText,
                modifier = Modifier.size(38.dp),
            ) {
                Icon(
                    Icons.Rounded.Star,
                    contentDescription = "Correct selected text or current sentence",
                    tint = MaterialTheme.colorScheme.primary,
                )
            }
        }
    }
}

@Composable
private fun KeyboardModeButton(
    icon: ImageVector,
    description: String,
    selected: Boolean,
    onClick: () -> Unit,
) {
    IconButton(
        onClick = onClick,
        modifier = Modifier.size(38.dp),
    ) {
        Icon(
            imageVector = icon,
            contentDescription = description,
            tint = if (selected) {
                MaterialTheme.colorScheme.primary
            } else {
                MaterialTheme.colorScheme.onSurfaceVariant
            },
        )
    }
}

@Composable
private fun SuggestionSlot(
    suggestion: Suggestion,
    modifier: Modifier = Modifier,
    onClick: () -> Unit,
) {
    val isCorrection = suggestion.kind == SuggestionKind.CORRECTION
    Surface(
        onClick = onClick,
        modifier = modifier
            .height(34.dp)
            .semantics {
                contentDescription = if (isCorrection) {
                    "Correction suggestion: ${suggestion.text}"
                } else {
                    "Text suggestion: ${suggestion.text}"
                }
            },
        shape = RoundedCornerShape(8.dp),
        color = if (isCorrection) {
            MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.55f)
        } else {
            Color.Transparent
        },
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 5.dp),
            horizontalArrangement = Arrangement.spacedBy(3.dp, Alignment.CenterHorizontally),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            if (isCorrection) {
                Icon(
                    imageVector = Icons.Rounded.Check,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.size(13.dp),
                )
            }
            Text(
                text = suggestion.text,
                fontSize = if (suggestion.isEmoji) 20.sp else 15.sp,
                fontWeight = FontWeight.Medium,
                color = if (isCorrection) {
                    MaterialTheme.colorScheme.primary
                } else {
                    MaterialTheme.colorScheme.onSurface
                },
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
    }
}

// endregion

// region Shared key components

@Composable
private fun keyHeight(): Dp {
    return keyboardLayoutSpec().keyHeightDp.dp
}

@Composable
private fun RowScope.CharKey(
    label: String,
    modifier: Modifier = Modifier,
    output: String = label,
    onKey: (String) -> Unit,
) {
    Surface(
        onClick = { onKey(output) },
        modifier = modifier
            .weight(1f)
            .height(keyHeight())
            .semantics { contentDescription = label },
        shape = KeyShape,
        color = MaterialTheme.colorScheme.surface,
        shadowElevation = 1.dp,
    ) {
        Box(contentAlignment = Alignment.Center) {
            Text(
                text = label,
                fontSize = 20.sp,
                color = MaterialTheme.colorScheme.onSurface,
            )
        }
    }
}

@Composable
private fun FunctionKey(
    modifier: Modifier = Modifier,
    label: String? = null,
    icon: ImageVector? = null,
    description: String,
    prominent: Boolean = false,
    tonal: Boolean = true,
    onClick: () -> Unit,
) {
    val container = when {
        prominent -> MaterialTheme.colorScheme.primary
        tonal -> MaterialTheme.colorScheme.surfaceContainerHighest
        else -> MaterialTheme.colorScheme.surface
    }
    val content = when {
        prominent -> MaterialTheme.colorScheme.onPrimary
        else -> MaterialTheme.colorScheme.onSurfaceVariant
    }
    Surface(
        onClick = onClick,
        modifier = modifier
            .height(keyHeight())
            .semantics { contentDescription = description },
        shape = KeyShape,
        color = container,
        shadowElevation = 1.dp,
    ) {
        Box(contentAlignment = Alignment.Center) {
            if (icon != null) {
                Icon(icon, contentDescription = null, tint = content, modifier = Modifier.size(22.dp))
            } else {
                Text(
                    text = label.orEmpty(),
                    fontSize = 14.sp,
                    fontWeight = FontWeight.Medium,
                    color = content,
                )
            }
        }
    }
}

@Composable
private fun RowScope.SpaceKey(service: BuddyGrammarImeService) {
    Surface(
        onClick = service::onSpaceKey,
        modifier = Modifier
            .weight(1f)
            .height(keyHeight())
            .semantics { contentDescription = "Space" },
        shape = KeyShape,
        color = MaterialTheme.colorScheme.surface,
        shadowElevation = 1.dp,
    ) {
        Box(contentAlignment = Alignment.Center) {
            Text(
                text = "BuddyGrammar",
                fontSize = 11.sp,
                color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.45f),
            )
        }
    }
}

@Composable
private fun ReturnKey(service: BuddyGrammarImeService, modifier: Modifier = Modifier) {
    val (icon, description) = when (service.returnAction) {
        EditorInfo.IME_ACTION_SEARCH -> Icons.Rounded.Search to "Search"
        EditorInfo.IME_ACTION_SEND -> Icons.AutoMirrored.Rounded.Send to "Send"
        EditorInfo.IME_ACTION_GO -> Icons.AutoMirrored.Rounded.ArrowForward to "Go"
        EditorInfo.IME_ACTION_NEXT -> Icons.AutoMirrored.Rounded.KeyboardTab to "Next"
        EditorInfo.IME_ACTION_DONE -> Icons.Rounded.Check to "Done"
        else -> Icons.AutoMirrored.Rounded.KeyboardReturn to "Return"
    }
    FunctionKey(
        modifier = modifier,
        icon = icon,
        description = description,
        prominent = true,
        onClick = service::onReturnKey,
    )
}

@Composable
private fun DeleteKey(service: BuddyGrammarImeService, modifier: Modifier = Modifier) {
    FunctionKey(
        modifier = modifier,
        icon = Icons.AutoMirrored.Rounded.Backspace,
        description = "Delete",
        onClick = service::onDeleteKey,
    )
}

private val functionKeyWidth = Modifier.widthIn(min = 42.dp, max = 96.dp)

@Composable
private fun controlKeyWidth(wide: Boolean): Dp {
    val layout = keyboardLayoutSpec()
    return if (wide) layout.wideControlKeyWidthDp.dp else layout.iconControlKeyWidthDp.dp
}

// endregion

// region Letters, numbers, symbols

@Composable
private fun LettersLayer(service: BuddyGrammarImeService) {
    val state = service.keyboardState
    val uppercase = state.uppercase
    Column(verticalArrangement = Arrangement.spacedBy(5.dp)) {
        SplitKeyRow(
            left = {
                "qwert".forEach { key ->
                    LetterKey(service, key, uppercase)
                }
            },
            right = {
                "yuiop".forEach { key ->
                    LetterKey(service, key, uppercase)
                }
            },
        )
        SplitKeyRow(
            left = {
                CompactOnlySpacer(weight = 0.5f)
                "asdfg".forEach { key ->
                    LetterKey(service, key, uppercase)
                }
            },
            right = {
                SplitOnlySpacer(weight = 0.5f)
                "hjkl".forEach { key ->
                    LetterKey(service, key, uppercase)
                }
                Spacer(Modifier.weight(0.5f))
            },
        )
        SplitKeyRow(
            left = {
                FunctionKey(
                    modifier = functionKeyWidth.weight(1.4f),
                    icon = if (state.capsLock) Icons.Rounded.KeyboardCapslock else Icons.Rounded.ArrowUpward,
                    description = when {
                        state.capsLock -> "Caps lock on"
                        state.shift -> "Shift on"
                        else -> "Shift off"
                    },
                    tonal = !uppercase,
                    prominent = false,
                    onClick = service::onShiftKey,
                )
                "zxcv".forEach { key ->
                    LetterKey(service, key, uppercase)
                }
            },
            right = {
                SplitOnlySpacer(weight = 1f)
                "bnm".forEach { key ->
                    LetterKey(service, key, uppercase)
                }
                DeleteKey(service, modifier = functionKeyWidth.weight(1.4f))
            },
        )
        KeyboardControlRow {
            FunctionKey(
                modifier = Modifier.width(controlKeyWidth(wide = true)),
                label = "?123",
                description = "Numbers and punctuation",
                onClick = { service.setLayer(KeyboardLayer.NUMBERS) },
            )
            FunctionKey(
                modifier = Modifier.width(controlKeyWidth(wide = false)),
                icon = Icons.Rounded.EmojiEmotions,
                description = "Emoji",
                onClick = { service.setLayer(KeyboardLayer.EMOJI) },
            )
            FunctionKey(
                modifier = Modifier.width(controlKeyWidth(wide = false)),
                icon = Icons.Rounded.Language,
                description = "Switch keyboard",
                onClick = service::switchKeyboard,
            )
            Row(modifier = Modifier.weight(3.6f)) {
                SpaceKey(service)
            }
            FunctionKey(
                modifier = Modifier.width(controlKeyWidth(wide = false)),
                icon = Icons.Rounded.Mic,
                description = "Voice typing",
                onClick = { service.setLayer(KeyboardLayer.VOICE) },
            )
            ReturnKey(service, modifier = Modifier.width(controlKeyWidth(wide = true)))
        }
    }
}

@Composable
private fun RowScope.LetterKey(service: BuddyGrammarImeService, key: Char, uppercase: Boolean) {
    val label = if (uppercase) key.uppercaseChar().toString() else key.toString()
    val center = qwertyCenter(key)
    Surface(
        modifier = Modifier
            .weight(1f)
            .height(keyHeight())
            .pointerInput(key) {
                detectTapGestures { offset ->
                    if (size.width <= 0 || size.height <= 0) return@detectTapGestures
                    service.onAdaptiveCharacterKey(
                        value = key.toString(),
                        x = center.first + offset.x.toDouble() / size.width.toDouble() - 0.5,
                        y = center.second + offset.y.toDouble() / size.height.toDouble() - 0.5,
                    )
                }
            }
            .semantics {
                contentDescription = label
                onClick(label = "Type $label") {
                    service.onLiteralCharacterKey(key.toString())
                    true
                }
            },
        shape = KeyShape,
        color = MaterialTheme.colorScheme.surface,
        shadowElevation = 1.dp,
    ) {
        Box(contentAlignment = Alignment.Center) {
            Text(
                text = label,
                fontSize = 20.sp,
                color = MaterialTheme.colorScheme.onSurface,
            )
        }
    }
}

private fun qwertyCenter(key: Char): Pair<Double, Double> {
    val normalized = key.lowercaseChar()
    val top = "qwertyuiop"
    val middle = "asdfghjkl"
    val bottom = "zxcvbnm"
    top.indexOf(normalized).takeIf { it >= 0 }?.let { return 0.5 + it to 0.5 }
    middle.indexOf(normalized).takeIf { it >= 0 }?.let { return 1.0 + it to 1.5 }
    bottom.indexOf(normalized).takeIf { it >= 0 }?.let { return 2.0 + it to 2.5 }
    return 0.0 to 0.0
}

@Composable
private fun NumbersLayer(service: BuddyGrammarImeService) {
    Column(verticalArrangement = Arrangement.spacedBy(5.dp)) {
        SplitKeyRow(
            left = {
                "12345".forEach { key -> CharKey(key.toString(), onKey = service::onCharacterKey) }
            },
            right = {
                "67890".forEach { key -> CharKey(key.toString(), onKey = service::onCharacterKey) }
            },
        )
        SplitKeyRow(
            left = {
                listOf("-", "/", ":", ";", "(").forEach { key ->
                    CharKey(key, onKey = service::onCharacterKey)
                }
            },
            right = {
                listOf(")", "$", "&", "@", "\"").forEach { key ->
                    CharKey(key, onKey = service::onCharacterKey)
                }
            },
        )
        SplitKeyRow(
            left = {
                FunctionKey(
                    modifier = functionKeyWidth.weight(1.4f),
                    label = "#+=",
                    description = "More symbols",
                    onClick = { service.setLayer(KeyboardLayer.SYMBOLS) },
                )
                listOf(".", ",").forEach { key ->
                    CharKey(key, onKey = service::onCharacterKey)
                }
                SplitOnlySpacer(weight = 1f)
            },
            right = {
                listOf("?", "!", "'").forEach { key ->
                    CharKey(key, onKey = service::onCharacterKey)
                }
                DeleteKey(service, modifier = functionKeyWidth.weight(1.4f))
            },
        )
        UtilityControlRow(service)
    }
}

@Composable
private fun SymbolsLayer(service: BuddyGrammarImeService) {
    Column(verticalArrangement = Arrangement.spacedBy(5.dp)) {
        SplitKeyRow(
            left = {
                listOf("[", "]", "{", "}", "#").forEach { key ->
                    CharKey(key, onKey = service::onCharacterKey)
                }
            },
            right = {
                listOf("%", "^", "*", "+", "=").forEach { key ->
                    CharKey(key, onKey = service::onCharacterKey)
                }
            },
        )
        SplitKeyRow(
            left = {
                listOf("_", "\\", "|", "~", "<").forEach { key ->
                    CharKey(key, onKey = service::onCharacterKey)
                }
            },
            right = {
                listOf(">", "€", "£", "¥", "•").forEach { key ->
                    CharKey(key, onKey = service::onCharacterKey)
                }
            },
        )
        SplitKeyRow(
            left = {
                FunctionKey(
                    modifier = functionKeyWidth.weight(1.4f),
                    label = "123",
                    description = "Numbers",
                    onClick = { service.setLayer(KeyboardLayer.NUMBERS) },
                )
                listOf(".", ",").forEach { key ->
                    CharKey(key, onKey = service::onCharacterKey)
                }
                SplitOnlySpacer(weight = 1f)
            },
            right = {
                listOf("?", "!", "'").forEach { key ->
                    CharKey(key, onKey = service::onCharacterKey)
                }
                DeleteKey(service, modifier = functionKeyWidth.weight(1.4f))
            },
        )
        UtilityControlRow(service)
    }
}

/** Control row for the numbers/symbols layers with LaTeX + handwriting entries. */
@Composable
private fun UtilityControlRow(service: BuddyGrammarImeService) {
    KeyboardControlRow {
        FunctionKey(
            modifier = Modifier.width(controlKeyWidth(wide = true)),
            label = "ABC",
            description = "Letters",
            onClick = { service.setLayer(KeyboardLayer.LETTERS) },
        )
        FunctionKey(
            modifier = Modifier.width(controlKeyWidth(wide = false)),
            icon = Icons.Rounded.Functions,
            description = "LaTeX keyboard",
            onClick = { service.setLayer(KeyboardLayer.LATEX) },
        )
        FunctionKey(
            modifier = Modifier.width(controlKeyWidth(wide = false)),
            icon = Icons.Rounded.Draw,
            description = "Handwriting",
            onClick = { service.setLayer(KeyboardLayer.HANDWRITING) },
        )
        Row(modifier = Modifier.weight(3.6f)) {
            SpaceKey(service)
        }
        ReturnKey(service, modifier = Modifier.width(controlKeyWidth(wide = true)))
    }
}

@Composable
private fun KeyRow(content: @Composable RowScope.() -> Unit) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(4.dp),
        content = content,
    )
}

@Composable
private fun SplitKeyRow(
    left: @Composable RowScope.() -> Unit,
    right: @Composable RowScope.() -> Unit,
) {
    val gap = keyboardLayoutSpec().centerGapDp.dp
    KeyRow {
        left()
        if (gap > 0.dp) {
            Spacer(Modifier.width(gap))
        }
        right()
    }
}

@Composable
private fun RowScope.SplitOnlySpacer(weight: Float) {
    if (keyboardLayoutSpec().usesSplitKeyGrid) {
        Spacer(Modifier.weight(weight))
    }
}

@Composable
private fun RowScope.CompactOnlySpacer(weight: Float) {
    if (!keyboardLayoutSpec().usesSplitKeyGrid) {
        Spacer(Modifier.weight(weight))
    }
}

@Composable
private fun KeyboardControlRow(content: @Composable RowScope.() -> Unit) {
    Column(
        modifier = Modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        HorizontalDivider(
            color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.35f),
        )
        KeyRow(content)
    }
}

// endregion

// region LaTeX layer

private data class LatexKey(val display: String, val insert: String)

private val latexRows: List<List<LatexKey>> = listOf(
    listOf(
        LatexKey("¹⁄₂", "\\frac{}{}"),
        LatexKey("√", "\\sqrt{}"),
        LatexKey("xⁿ", "^{}"),
        LatexKey("xₙ", "_{}"),
        LatexKey("∑", "\\sum"),
        LatexKey("∫", "\\int"),
        LatexKey("∏", "\\prod"),
        LatexKey("lim", "\\lim"),
    ),
    listOf(
        LatexKey("α", "\\alpha"),
        LatexKey("β", "\\beta"),
        LatexKey("γ", "\\gamma"),
        LatexKey("δ", "\\delta"),
        LatexKey("θ", "\\theta"),
        LatexKey("λ", "\\lambda"),
        LatexKey("μ", "\\mu"),
        LatexKey("π", "\\pi"),
        LatexKey("σ", "\\sigma"),
        LatexKey("ω", "\\omega"),
    ),
    listOf(
        LatexKey("≤", "\\leq"),
        LatexKey("≥", "\\geq"),
        LatexKey("≠", "\\neq"),
        LatexKey("≈", "\\approx"),
        LatexKey("×", "\\times"),
        LatexKey("·", "\\cdot"),
        LatexKey("±", "\\pm"),
        LatexKey("∞", "\\infty"),
        LatexKey("→", "\\rightarrow"),
    ),
    listOf(
        LatexKey("sin", "\\sin"),
        LatexKey("cos", "\\cos"),
        LatexKey("tan", "\\tan"),
        LatexKey("log", "\\log"),
        LatexKey("ln", "\\ln"),
        LatexKey("exp", "\\exp"),
    ),
)

@Composable
private fun LatexLayer(service: BuddyGrammarImeService) {
    Column(verticalArrangement = Arrangement.spacedBy(5.dp)) {
        latexRows.forEach { row ->
            KeyRow {
                row.forEach { key ->
                    Surface(
                        onClick = { service.onCharacterKey(key.insert) },
                        modifier = Modifier
                            .weight(1f)
                            .height(keyHeight())
                            .semantics { contentDescription = key.insert },
                        shape = KeyShape,
                        color = MaterialTheme.colorScheme.surface,
                        shadowElevation = 1.dp,
                    ) {
                        Box(contentAlignment = Alignment.Center) {
                            Text(
                                text = key.display,
                                fontSize = 17.sp,
                                color = MaterialTheme.colorScheme.onSurface,
                            )
                        }
                    }
                }
            }
        }
        KeyboardControlRow {
            FunctionKey(
                modifier = Modifier.width(controlKeyWidth(wide = true)),
                label = "ABC",
                description = "Letters",
                onClick = { service.setLayer(KeyboardLayer.LETTERS) },
            )
            DeleteKey(service, modifier = Modifier.width(controlKeyWidth(wide = false)))
            Row(modifier = Modifier.weight(4f)) {
                SpaceKey(service)
            }
            ReturnKey(service, modifier = Modifier.width(controlKeyWidth(wide = true)))
        }
    }
}

// endregion

// region Emoji layer

@Composable
private fun EmojiLayer(service: BuddyGrammarImeService) {
    val layout = keyboardLayoutSpec()
    Column(verticalArrangement = Arrangement.spacedBy(5.dp)) {
        AndroidView(
            factory = { context ->
                EmojiPickerView(context).apply {
                    setOnEmojiPickedListener { item -> service.commitEmoji(item.emoji) }
                }
            },
            modifier = Modifier
                .fillMaxWidth()
                .height(layout.emojiPanelHeightDp.dp)
                .clip(RoundedCornerShape(12.dp))
                .background(MaterialTheme.colorScheme.surface),
        )
        KeyboardControlRow {
            FunctionKey(
                modifier = Modifier.width(controlKeyWidth(wide = true)),
                label = "ABC",
                description = "Letters",
                onClick = { service.setLayer(KeyboardLayer.LETTERS) },
            )
            Row(modifier = Modifier.weight(4f)) {
                SpaceKey(service)
            }
            DeleteKey(service, modifier = Modifier.width(controlKeyWidth(wide = false)))
        }
    }
}

// endregion

// region Handwriting layer

@Composable
private fun HandwritingLayer(service: BuddyGrammarImeService) {
    val controller = service.handwriting
    Column(verticalArrangement = Arrangement.spacedBy(5.dp)) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .height(38.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            val status = controller.statusMessage
            if (status != null) {
                if (controller.isModelDownloading) {
                    CircularProgressIndicator(modifier = Modifier.size(18.dp), strokeWidth = 2.dp)
                }
                Text(
                    text = status,
                    fontSize = 13.sp,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            } else if (controller.candidates.isEmpty()) {
                Text(
                    text = "Write below and tap a suggestion.",
                    fontSize = 13.sp,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            } else {
                controller.candidates.forEach { candidate ->
                    Surface(
                        onClick = { service.commitHandwriting(candidate) },
                        modifier = Modifier
                            .weight(1f)
                            .height(32.dp),
                        shape = RoundedCornerShape(16.dp),
                        color = MaterialTheme.colorScheme.secondaryContainer,
                    ) {
                        Box(contentAlignment = Alignment.Center) {
                            Text(
                                text = candidate,
                                fontSize = 15.sp,
                                color = MaterialTheme.colorScheme.onSecondaryContainer,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis,
                            )
                        }
                    }
                }
            }
        }
        HandwritingCanvas(controller, keyboardLayoutSpec().handwritingCanvasHeightDp.dp)
        KeyboardControlRow {
            FunctionKey(
                modifier = Modifier.width(controlKeyWidth(wide = true)),
                label = "ABC",
                description = "Letters",
                onClick = { service.setLayer(KeyboardLayer.LETTERS) },
            )
            FunctionKey(
                modifier = Modifier.width(controlKeyWidth(wide = false)),
                icon = Icons.Rounded.Delete,
                description = "Clear handwriting",
                onClick = controller::clear,
            )
            Row(modifier = Modifier.weight(3f)) {
                SpaceKey(service)
            }
            DeleteKey(service, modifier = Modifier.width(controlKeyWidth(wide = false)))
            ReturnKey(service, modifier = Modifier.width(controlKeyWidth(wide = true)))
        }
    }
}

@Composable
private fun HandwritingCanvas(controller: HandwritingController, height: Dp) {
    val strokeColor = MaterialTheme.colorScheme.onSurface
    Canvas(
        modifier = Modifier
            .fillMaxWidth()
            .height(height)
            .clip(RoundedCornerShape(12.dp))
            .background(MaterialTheme.colorScheme.surface)
            .pointerInput(Unit) {
                detectDragGestures(
                    onDragStart = { offset ->
                        controller.startStroke(offset, System.currentTimeMillis())
                    },
                    onDrag = { change, _ ->
                        change.consume()
                        controller.addPoint(change.position, System.currentTimeMillis())
                    },
                    onDragEnd = { controller.endStroke() },
                    onDragCancel = { controller.endStroke() },
                )
            }
            .semantics { contentDescription = "Handwriting area" },
    ) {
        val allStrokes = controller.finishedStrokes + listOf(controller.activeStroke)
        allStrokes.forEach { points ->
            if (points.size > 1) {
                val path = Path().apply {
                    moveTo(points.first().x, points.first().y)
                    points.drop(1).forEach { point -> lineTo(point.x, point.y) }
                }
                drawPath(
                    path = path,
                    color = strokeColor,
                    style = Stroke(width = 5.dp.toPx(), cap = StrokeCap.Round, join = StrokeJoin.Round),
                )
            } else if (points.size == 1) {
                drawCircle(color = strokeColor, radius = 2.5.dp.toPx(), center = points.first())
            }
        }
    }
}

// endregion

// region Voice layer

@Composable
private fun VoiceLayer(service: BuddyGrammarImeService) {
    val voice = service.voice
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .height(keyboardLayoutSpec().voicePanelHeightDp.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        when {
            service.secureField -> VoiceMessage("Voice typing is disabled in secure fields.")
            !service.hasMicPermission -> {
                VoiceMessage("BuddyGrammar needs microphone access for voice typing.")
                androidx.compose.material3.Button(onClick = service::openAppForMicrophonePermission) {
                    Text("Allow in BuddyGrammar")
                }
            }
            !voice.isRecognitionAvailable ->
                VoiceMessage("Speech recognition is not available on this device.")
            else -> {
                Spacer(Modifier.height(2.dp))
                Text(
                    text = when {
                        voice.isListening && voice.partialText.isNotBlank() -> voice.partialText
                        voice.isListening -> "Listening…"
                        voice.errorMessage != null -> voice.errorMessage.orEmpty()
                        else -> "Tap the microphone to dictate."
                    },
                    modifier = Modifier
                        .weight(1f)
                        .fillMaxWidth()
                        .padding(horizontal = 20.dp),
                    fontSize = 16.sp,
                    color = if (voice.errorMessage != null && !voice.isListening) {
                        MaterialTheme.colorScheme.error
                    } else {
                        MaterialTheme.colorScheme.onSurface
                    },
                    maxLines = 3,
                    overflow = TextOverflow.Ellipsis,
                )
                val pulse by animateFloatAsState(
                    targetValue = if (voice.isListening) 1f + voice.rmsLevel * 0.18f else 1f,
                    label = "micPulse",
                )
                Surface(
                    onClick = voice::toggleListening,
                    modifier = Modifier
                        .size(72.dp)
                        .scale(pulse)
                        .semantics {
                            contentDescription =
                                if (voice.isListening) "Stop dictation" else "Start dictation"
                        },
                    shape = CircleShape,
                    color = if (voice.isListening) {
                        MaterialTheme.colorScheme.error
                    } else {
                        MaterialTheme.colorScheme.primary
                    },
                    shadowElevation = 3.dp,
                ) {
                    Box(contentAlignment = Alignment.Center) {
                        Icon(
                            imageVector = if (voice.isListening) Icons.Rounded.Stop else Icons.Rounded.Mic,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.onPrimary,
                            modifier = Modifier.size(32.dp),
                        )
                    }
                }
            }
        }
        Spacer(Modifier.weight(0.01f))
        KeyboardControlRow {
            FunctionKey(
                modifier = Modifier.width(controlKeyWidth(wide = true)),
                label = "ABC",
                description = "Letters",
                onClick = { service.setLayer(KeyboardLayer.LETTERS) },
            )
            Row(modifier = Modifier.weight(4f)) {
                SpaceKey(service)
            }
            DeleteKey(service, modifier = Modifier.width(controlKeyWidth(wide = false)))
        }
    }
}

@Composable
private fun VoiceMessage(message: String) {
    Text(
        text = message,
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 20.dp, vertical = 12.dp),
        fontSize = 15.sp,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
    )
}

// endregion
