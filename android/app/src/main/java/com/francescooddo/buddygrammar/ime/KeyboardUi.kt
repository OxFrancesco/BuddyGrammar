package com.francescooddo.buddygrammar.ime

import android.os.Build
import android.view.inputmethod.EditorInfo
import androidx.compose.animation.animateContentSize
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsIgnoringVisibility
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.requiredWidth
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.windowInsetsBottomHeight
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.Backspace
import androidx.compose.material.icons.automirrored.rounded.Undo
import androidx.compose.material.icons.rounded.ArrowUpward
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.Delete
import androidx.compose.material.icons.rounded.Draw
import androidx.compose.material.icons.rounded.EmojiEmotions
import androidx.compose.material.icons.rounded.Functions
import androidx.compose.material.icons.rounded.KeyboardCapslock
import androidx.compose.material.icons.rounded.Language
import androidx.compose.material.icons.rounded.Mic
import androidx.compose.material.icons.rounded.Star
import androidx.compose.material.icons.rounded.Stop
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Button
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
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
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.ui.zIndex
import androidx.emoji2.emojipicker.EmojiPickerView
import com.francescooddo.buddygrammar.core.Suggestion
import com.francescooddo.buddygrammar.core.SuggestionKind
import com.francescooddo.buddygrammar.core.BuddyRewriteIntent
import com.francescooddo.buddygrammar.core.InteractionTarget
import com.francescooddo.buddygrammar.core.KeyboardPointerBinding
import com.francescooddo.buddygrammar.core.KeySpaceTransform
import com.francescooddo.buddygrammar.core.QwertyKeyLayout
import com.francescooddo.buddygrammar.core.ReturnIntent
import com.francescooddo.buddygrammar.core.userPerceivedCharacters

private val BuddyPurple = Color(0xFF6D4AFF)

private val KeyShape = RoundedCornerShape(9.dp)

private val LocalKeyboardInteractions = staticCompositionLocalOf<KeyboardInteractionComposeAdapter> {
    error("Keyboard interaction adapter was not provided.")
}

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
        val interactions = rememberKeyboardInteractionAdapter(service)
        CompositionLocalProvider(LocalKeyboardInteractions provides interactions) {
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
                        if (service.reviewProposal == null) {
                            SuggestionStrip(service)
                        } else {
                            ReviewProposalCard(service)
                        }
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
private fun ReviewProposalCard(service: BuddyGrammarImeService) {
    val transaction = service.reviewProposal ?: return
    val proposal = transaction.proposal
    val change = proposal.change
    Surface(
        modifier = Modifier
            .fillMaxWidth()
            .semantics {
                contentDescription =
                    "${proposal.intent.title} cloud proposal for ${transaction.scope.displayName}"
            },
        shape = RoundedCornerShape(12.dp),
        color = MaterialTheme.colorScheme.surfaceContainerHighest,
        shadowElevation = 2.dp,
    ) {
        Column(
            modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(5.dp),
        ) {
            Text(
                "${proposal.intent.title} • Cloud • ${transaction.scope.displayName}",
                fontSize = 12.sp,
                fontWeight = FontWeight.SemiBold,
                color = MaterialTheme.colorScheme.primary,
            )
            Text(
                "Original: ${boundedChangeText(change.commonPrefix, change.originalChangedText, change.commonSuffix)}",
                fontSize = 13.sp,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Text(
                "Proposed: ${boundedChangeText(change.commonPrefix, change.proposedChangedText, change.commonSuffix)}",
                fontSize = 13.sp,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
                color = MaterialTheme.colorScheme.onSurface,
            )
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.End),
            ) {
                OutlinedButton(onClick = { service.dismissReviewProposal(proposal.id) }) {
                    Text("Dismiss")
                }
                Button(onClick = { service.acceptReviewProposal(proposal.id) }) {
                    Text("Accept")
                }
            }
        }
    }
}

internal fun boundedChangeText(prefix: String, changed: String, suffix: String): String {
    val prefixCharacters = prefix.userPerceivedCharacters()
    val suffixCharacters = suffix.userPerceivedCharacters()
    val leading = prefixCharacters.takeLast(24).joinToString("").let {
        if (prefixCharacters.size > 24) "…$it" else it
    }
    val trailing = suffixCharacters.take(24).joinToString("").let {
        if (suffixCharacters.size > 24) "$it…" else it
    }
    val visibleChange = changed.ifEmpty { "∅" }
    return leading + "⟦" + visibleChange + "⟧" + trailing
}

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
        } else if (service.localCorrectionOriginalText != null) {
            val originalText = requireNotNull(service.localCorrectionOriginalText)
            Surface(
                onClick = { service.revertLocalCorrection() },
                modifier = Modifier
                    .weight(1f)
                    .height(34.dp)
                    .semantics {
                        contentDescription = "Restore original word $originalText"
                    },
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
                        "Undo “$originalText”",
                        modifier = Modifier.padding(start = 6.dp),
                        fontWeight = FontWeight.SemiBold,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
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
            val suggestions = service.suggestions.take(3)
            repeat(3) { index ->
                val suggestion = suggestions.getOrNull(index)
                if (suggestion == null) {
                    Spacer(Modifier.weight(1f))
                } else {
                    SuggestionSlot(
                        suggestion = suggestion,
                        modifier = Modifier.weight(1f),
                        allowsCorrectionActions =
                            service.canOfferCorrectionPreferenceActions(suggestion),
                        onClick = { service.applySuggestion(suggestion) },
                        onAddToDictionary = {
                            service.addCorrectionCandidateToDictionary(suggestion)
                        },
                        onNeverSuggest = { service.neverSuggestCorrection(suggestion) },
                    )
                }
            }
        }
        BuddyActionButton(service)
    }
}

@Composable
private fun BuddyActionButton(service: BuddyGrammarImeService) {
    var expanded by remember { mutableStateOf(false) }
    Box {
        IconButton(
            onClick = { expanded = true },
            modifier = Modifier.size(38.dp),
        ) {
            if (service.isCorrecting) {
                CircularProgressIndicator(modifier = Modifier.size(20.dp), strokeWidth = 2.dp)
            } else {
                Icon(
                    Icons.Rounded.Star,
                    contentDescription = "Buddy actions",
                    tint = MaterialTheme.colorScheme.primary,
                )
            }
        }
        DropdownMenu(
            expanded = expanded,
            onDismissRequest = { expanded = false },
            modifier = Modifier.width(228.dp),
        ) {
            BuddyRewriteIntent.entries.forEach { intent ->
                val capability = service.editorCapabilities.starCorrection
                BuddyActionItem(
                    label = intent.title,
                    enabled = capability.isAllowed && !service.isCorrecting,
                    unavailableReason = capability
                        .takeUnless { it.isAllowed }
                        ?.denialMessage(intent.title),
                ) {
                    expanded = false
                    service.correctCurrentText(intent)
                }
            }
            HorizontalDivider()
            val voice = service.editorCapabilities.voice
            BuddyActionItem(
                label = "Voice",
                enabled = voice.isAllowed,
                unavailableReason = voice.takeUnless { it.isAllowed }?.denialMessage("Voice typing"),
            ) {
                expanded = false
                service.setLayer(KeyboardLayer.VOICE)
            }
            val handwriting = service.editorCapabilities.localHandwriting
            BuddyActionItem(
                label = "Handwriting",
                enabled = handwriting.isAllowed,
                unavailableReason = handwriting
                    .takeUnless { it.isAllowed }
                    ?.denialMessage("Handwriting"),
            ) {
                expanded = false
                service.setLayer(KeyboardLayer.HANDWRITING)
            }
            val latex = service.editorCapabilities.literalTools
            BuddyActionItem(
                label = "LaTeX",
                enabled = latex.isAllowed,
                unavailableReason = latex
                    .takeUnless { it.isAllowed }
                    ?.denialMessage("LaTeX"),
            ) {
                expanded = false
                service.setLayer(KeyboardLayer.LATEX)
            }
            val transcript = service.editorCapabilities.pendingTranscript
            BuddyActionItem(
                label = "Saved dictation",
                enabled = transcript.isAllowed,
                unavailableReason = transcript
                    .takeUnless { it.isAllowed }
                    ?.denialMessage("Saved dictation"),
            ) {
                expanded = false
                service.insertPendingTranscript()
            }
            val clipboard = service.editorCapabilities.clipboardInsertion
            BuddyActionItem(
                label = "Clipboard",
                enabled = clipboard.isAllowed,
                unavailableReason = clipboard
                    .takeUnless { it.isAllowed }
                    ?.denialMessage("Clipboard"),
            ) {
                expanded = false
                service.insertClipboardText()
            }
            BuddyActionItem(label = "Delete word") {
                expanded = false
                service.onDeleteWordKey()
            }
            BuddyActionItem(label = "BuddyGrammar settings") {
                expanded = false
                service.openBuddyGrammarSettings()
            }
        }
    }
}

@Composable
private fun BuddyActionItem(
    label: String,
    enabled: Boolean = true,
    unavailableReason: String? = null,
    onClick: () -> Unit,
) {
    DropdownMenuItem(
        text = {
            Column {
                Text(label, fontWeight = FontWeight.Medium)
                if (!enabled && unavailableReason != null) {
                    Text(
                        unavailableReason,
                        fontSize = 11.sp,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
            }
        },
        enabled = enabled,
        onClick = onClick,
    )
}

@Composable
private fun SuggestionSlot(
    suggestion: Suggestion,
    modifier: Modifier = Modifier,
    allowsCorrectionActions: Boolean,
    onClick: () -> Unit,
    onAddToDictionary: () -> Boolean,
    onNeverSuggest: () -> Boolean,
) {
    val isCorrection = suggestion.kind == SuggestionKind.CORRECTION
    var actionsExpanded by remember(suggestion) { mutableStateOf(false) }
    Box(
        modifier = modifier
            .height(34.dp)
            .combinedClickable(
                onClick = onClick,
                onLongClick = if (isCorrection && allowsCorrectionActions) {
                    { actionsExpanded = true }
                } else {
                    null
                },
            )
            .semantics {
                contentDescription = if (isCorrection) {
                    "Correction suggestion: ${suggestion.text}"
                } else {
                    "Text suggestion: ${suggestion.text}"
                }
                if (isCorrection && allowsCorrectionActions) {
                    customActions = listOf(
                        CustomAccessibilityAction("Add typed word to dictionary") {
                            onAddToDictionary()
                        },
                        CustomAccessibilityAction(
                            "Never suggest ${suggestion.text} for this exact word",
                        ) {
                            onNeverSuggest()
                        },
                    )
                }
            },
    ) {
        Surface(
            modifier = Modifier.fillMaxSize(),
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
        DropdownMenu(
            expanded = actionsExpanded && allowsCorrectionActions,
            onDismissRequest = { actionsExpanded = false },
        ) {
            DropdownMenuItem(
                text = { Text("Add typed word to dictionary") },
                onClick = {
                    actionsExpanded = false
                    onAddToDictionary()
                },
            )
            DropdownMenuItem(
                text = { Text("Never suggest this exact correction") },
                onClick = {
                    actionsExpanded = false
                    onNeverSuggest()
                },
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
    enabled: Boolean = true,
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
        enabled = enabled,
        modifier = modifier
            .height(keyHeight())
            .semantics { contentDescription = description },
        shape = KeyShape,
        color = container,
        shadowElevation = 1.dp,
    ) {
        Box(contentAlignment = Alignment.Center) {
            if (icon != null) {
                Icon(
                    icon,
                    contentDescription = null,
                    tint = content.copy(alpha = if (enabled) 1f else 0.38f),
                    modifier = Modifier.size(22.dp),
                )
            } else {
                Text(
                    text = label.orEmpty(),
                    fontSize = 14.sp,
                    fontWeight = FontWeight.Medium,
                    color = content.copy(alpha = if (enabled) 1f else 0.38f),
                )
            }
        }
    }
}

@Composable
private fun RowScope.SpaceKey(service: BuddyGrammarImeService) {
    val interactions = LocalKeyboardInteractions.current
    val target = InteractionTarget.Space
    val cursor = service.editorCapabilities.moveCursor
    val pressed = interactions.visualState.pressedTarget == target
    Box(
        modifier = Modifier
            .weight(1f)
            .height(keyHeight())
            .routedKeyboardPointer(
                interactionKey = "space-${cursor.isAllowed}",
                adapter = interactions,
            ) { _, _ ->
                KeyboardPointerBinding.Space(cursorMovementEnabled = cursor.isAllowed)
            }
            .semantics {
                contentDescription = if (cursor.isAllowed) {
                    "${service.keyboardPresentation.language.spaceLabel}. Swipe left or right to move the cursor."
                } else {
                    service.keyboardPresentation.language.spaceLabel
                }
                onClick(label = "Type space") {
                    service.onSpaceKey()
                    true
                }
                if (cursor.isAllowed) {
                    customActions = listOf(
                        CustomAccessibilityAction("Move cursor left") {
                            service.moveCursorBy(-1)
                            true
                        },
                        CustomAccessibilityAction("Move cursor right") {
                            service.moveCursorBy(1)
                            true
                        },
                    )
                }
            },
    ) {
        Surface(
            modifier = Modifier.fillMaxSize(),
            shape = KeyShape,
            color = if (pressed) {
                MaterialTheme.colorScheme.primaryContainer
            } else {
                MaterialTheme.colorScheme.surface
            },
            shadowElevation = if (pressed) 0.dp else 1.dp,
        ) {
            Row(
                modifier = Modifier.padding(horizontal = 12.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text("‹", color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.55f))
                Text(
                    text = if (pressed && cursor.isAllowed) {
                        "Move cursor"
                    } else {
                        service.keyboardPresentation.language.spaceLabel
                    },
                    fontSize = 11.sp,
                    color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.65f),
                )
                Text("›", color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.55f))
            }
        }
    }
}

@Composable
private fun ReturnKey(service: BuddyGrammarImeService, modifier: Modifier = Modifier) {
    val intent = when (service.returnAction) {
        EditorInfo.IME_ACTION_SEARCH -> ReturnIntent.SEARCH
        EditorInfo.IME_ACTION_SEND -> ReturnIntent.SEND
        EditorInfo.IME_ACTION_GO -> ReturnIntent.GO
        EditorInfo.IME_ACTION_NEXT -> ReturnIntent.NEXT
        EditorInfo.IME_ACTION_DONE -> ReturnIntent.DONE
        else -> ReturnIntent.NEWLINE
    }
    val localizedLabel = service.keyboardPresentation.language.returnLabels[intent]
        ?: intent.name.lowercase()
    val visibleLabel = localizedLabel.replaceFirstChar { it.uppercaseChar() }
    FunctionKey(
        modifier = modifier,
        label = visibleLabel,
        description = visibleLabel,
        prominent = true,
        onClick = service::onReturnKey,
    )
}

@Composable
private fun DeleteKey(service: BuddyGrammarImeService, modifier: Modifier = Modifier) {
    val interactions = LocalKeyboardInteractions.current
    val target = InteractionTarget.Delete
    val pressed = interactions.visualState.pressedTarget == target
    Box(
        modifier = modifier
            .height(keyHeight())
            .routedKeyboardPointer(
                interactionKey = target,
                adapter = interactions,
            ) { _, _ -> KeyboardPointerBinding.Delete }
            .semantics {
                contentDescription =
                    "Delete. Hold to repeatedly delete characters. Use Delete previous word for a whole word."
                onClick(label = "Delete character") {
                    service.onDeleteKey()
                    true
                }
                customActions = listOf(
                    CustomAccessibilityAction("Delete previous word") {
                        service.onDeleteWordKey()
                        true
                    },
                )
            },
    ) {
        Surface(
            modifier = Modifier.fillMaxSize(),
            shape = KeyShape,
            color = if (pressed) {
                MaterialTheme.colorScheme.primaryContainer
            } else {
                MaterialTheme.colorScheme.surfaceContainerHighest
            },
            shadowElevation = if (pressed) 0.dp else 1.dp,
        ) {
            Box(contentAlignment = Alignment.Center) {
                Icon(
                    Icons.AutoMirrored.Rounded.Backspace,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.size(22.dp),
                )
            }
        }
    }
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
        val inlineKeys = service.keyboardPresentation.inlineKeys
        KeyboardControlRow {
            FunctionKey(
                modifier = Modifier.width(controlKeyWidth(wide = true)),
                label = "?123",
                description = "Numbers and punctuation",
                onClick = { service.setLayer(KeyboardLayer.NUMBERS) },
            )
            if (inlineKeys.size < 3) {
                FunctionKey(
                    modifier = Modifier.width(controlKeyWidth(wide = false)),
                    icon = Icons.Rounded.EmojiEmotions,
                    description = "Emoji",
                    onClick = { service.setLayer(KeyboardLayer.EMOJI) },
                )
            }
            FunctionKey(
                modifier = Modifier.width(controlKeyWidth(wide = false)),
                icon = Icons.Rounded.Language,
                description = "Switch keyboard",
                onClick = service::switchKeyboard,
            )
            inlineKeys.forEach { key ->
                CharKey(
                    label = key.label,
                    output = key.output,
                    onKey = service::onCharacterKey,
                )
            }
            Row(modifier = Modifier.weight(if (inlineKeys.isEmpty()) 3.6f else 2.2f)) {
                SpaceKey(service)
            }
            ReturnKey(service, modifier = Modifier.width(controlKeyWidth(wide = true)))
        }
    }
}

@Composable
private fun RowScope.LetterKey(service: BuddyGrammarImeService, key: Char, uppercase: Boolean) {
    val label = if (uppercase) key.uppercaseChar().toString() else key.toString()
    val center = qwertyCenter(key)
    val swipeCenter = requireNotNull(QwertyKeyLayout.center(key))
    val language = service.keyboardPresentation.language
    val alternates = remember(key, uppercase, language.id) {
        language.alternates[key.lowercaseChar()]
            .orEmpty()
            .map { value -> if (uppercase) value.uppercase() else value }
    }
    val target = remember(label, alternates, service.editorCapabilities.swipe.isAllowed) {
        InteractionTarget.Key(
            literal = label,
            alternates = alternates,
            allowsSwipe = service.editorCapabilities.swipe.isAllowed,
        )
    }
    val interactions = LocalKeyboardInteractions.current
    val visualState = interactions.visualState
    val pressed = visualState.pressedTarget == target
    Box(
        modifier = Modifier
            .weight(1f)
            .height(keyHeight())
            .zIndex(if (pressed) 2f else 0f)
            .routedKeyboardPointer(
                interactionKey = target,
                adapter = interactions,
            ) { width, height ->
                KeyboardPointerBinding.Letter(
                    target = target,
                    transform = KeySpaceTransform(
                        centerX = center.first,
                        centerY = center.second,
                        width = width,
                        height = height,
                    ),
                    swipeTransform = KeySpaceTransform(
                        centerX = swipeCenter.x,
                        centerY = swipeCenter.y,
                        width = width,
                        height = height,
                    ),
                )
            }
            .semantics {
                contentDescription = label
                onClick(label = "Type $label") {
                    service.onLiteralCharacterKey(key.toString())
                    true
                }
                if (alternates.isNotEmpty()) {
                    customActions = alternates.map { alternate ->
                        CustomAccessibilityAction("Type $alternate") {
                            service.onCharacterKey(alternate)
                            true
                        }
                    }
                }
            },
    ) {
        Surface(
            modifier = Modifier.fillMaxSize(),
            shape = KeyShape,
            color = if (pressed) {
                MaterialTheme.colorScheme.primaryContainer
            } else {
                MaterialTheme.colorScheme.surface
            },
            shadowElevation = if (pressed) 0.dp else 1.dp,
        ) {
            Box(contentAlignment = Alignment.Center) {
                Text(
                    text = label,
                    fontSize = 20.sp,
                    color = MaterialTheme.colorScheme.onSurface,
                )
            }
        }
        if (pressed) KeyInteractionPopover(visualState)
    }
}

@Composable
private fun BoxScope.KeyInteractionPopover(
    state: com.francescooddo.buddygrammar.core.KeyboardInteractionVisualState,
) {
    val alternates = state.alternates
    if (!alternates.isNullOrEmpty()) {
        val width = (alternates.size * 38).coerceIn(48, 280).dp
        Surface(
            modifier = Modifier
                .align(Alignment.TopCenter)
                .offset(y = (-43).dp)
                .requiredWidth(width)
                .height(40.dp)
                .zIndex(4f),
            shape = RoundedCornerShape(10.dp),
            color = MaterialTheme.colorScheme.surfaceContainerHighest,
            shadowElevation = 5.dp,
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                alternates.forEachIndexed { index, alternate ->
                    Box(
                        modifier = Modifier
                            .weight(1f)
                            .fillMaxSize()
                            .background(
                                if (index == state.selectedAlternateIndex) {
                                    MaterialTheme.colorScheme.primaryContainer
                                } else {
                                    Color.Transparent
                                },
                            ),
                        contentAlignment = Alignment.Center,
                    ) {
                        Text(alternate, fontSize = 19.sp, fontWeight = FontWeight.Medium)
                    }
                }
            }
        }
    } else if (state.previewText != null) {
        Surface(
            modifier = Modifier
                .align(Alignment.TopCenter)
                .offset(y = (-39).dp)
                .size(42.dp)
                .zIndex(4f),
            shape = RoundedCornerShape(10.dp),
            color = MaterialTheme.colorScheme.primaryContainer,
            shadowElevation = 4.dp,
        ) {
            Box(contentAlignment = Alignment.Center) {
                Text(
                    state.previewText,
                    fontSize = 24.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = MaterialTheme.colorScheme.onPrimaryContainer,
                )
            }
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
    when (service.editorCapabilities.fieldKind) {
        EditorFieldKind.NUMBER,
        EditorFieldKind.DECIMAL,
        EditorFieldKind.PHONE,
        EditorFieldKind.DATETIME,
        -> PurposeBuiltNumericLayer(service)
        else -> GenericNumbersLayer(service)
    }
}

@Composable
private fun PurposeBuiltNumericLayer(service: BuddyGrammarImeService) {
    val fieldKind = service.editorCapabilities.fieldKind
    val finalRow = when (fieldKind) {
        EditorFieldKind.DECIMAL -> listOf(
            service.keyboardPresentation.language.decimalSeparator,
            "0",
            "-",
        )
        EditorFieldKind.PHONE -> listOf("+", "0", "#", "*")
        EditorFieldKind.DATETIME -> listOf("/", "0", ":", "-")
        else -> listOf("-", "0")
    }
    Column(verticalArrangement = Arrangement.spacedBy(5.dp)) {
        listOf(
            listOf("1", "2", "3"),
            listOf("4", "5", "6"),
            listOf("7", "8", "9"),
        ).forEach { row ->
            KeyRow {
                CompactOnlySpacer(weight = 0.5f)
                row.forEach { key -> CharKey(key, onKey = service::onCharacterKey) }
                CompactOnlySpacer(weight = 0.5f)
            }
        }
        KeyRow {
            finalRow.forEach { key -> CharKey(key, onKey = service::onCharacterKey) }
            DeleteKey(service, modifier = Modifier.weight(1f))
        }
        KeyboardControlRow {
            FunctionKey(
                modifier = Modifier.width(controlKeyWidth(wide = true)),
                label = "ABC",
                description = "Letters",
                onClick = { service.setLayer(KeyboardLayer.LETTERS) },
            )
            FunctionKey(
                modifier = Modifier.width(controlKeyWidth(wide = false)),
                icon = Icons.Rounded.Language,
                description = "Switch keyboard",
                onClick = service::switchKeyboard,
            )
            Spacer(Modifier.weight(1f))
            ReturnKey(service, modifier = Modifier.width(controlKeyWidth(wide = true)))
        }
    }
}

@Composable
private fun GenericNumbersLayer(service: BuddyGrammarImeService) {
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
    val latex = service.editorCapabilities.literalTools
    val handwriting = service.editorCapabilities.localHandwriting
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
            description = latex.takeUnless { it.isAllowed }
                ?.denialMessage("LaTeX")
                ?: "LaTeX keyboard",
            enabled = latex.isAllowed,
            onClick = { service.setLayer(KeyboardLayer.LATEX) },
        )
        FunctionKey(
            modifier = Modifier.width(controlKeyWidth(wide = false)),
            icon = Icons.Rounded.Draw,
            description = handwriting.takeUnless { it.isAllowed }
                ?.denialMessage("Handwriting")
                ?: "Handwriting",
            enabled = handwriting.isAllowed,
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
                        onClick = { service.insertLatex(key.insert) },
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
                if (controller.isModelDownloading || controller.isUsingCloud) {
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
        Text(
            text = "Voice uses your selected Android speech recognition service and may process audio locally or remotely.",
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 20.dp),
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            fontSize = 11.sp,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
        )
        when {
            !service.editorCapabilities.voice.isAllowed ->
                VoiceMessage(service.editorCapabilities.voice.denialMessage("Voice typing"))
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
                    onClick = service::toggleVoiceListening,
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
