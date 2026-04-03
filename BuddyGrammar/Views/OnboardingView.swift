import AppKit
import SwiftUI

// MARK: - OnboardingView

struct OnboardingView: View {
    enum Step: Int, CaseIterable, Identifiable {
        case welcome
        case apiKey
        case accessibility
        case workflow
        case finish

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .welcome:
                "Welcome"
            case .apiKey:
                "OpenRouter Key"
            case .accessibility:
                "Accessibility"
            case .workflow:
                "How It Works"
            case .finish:
                "Finish"
            }
        }

        var detail: String {
            switch self {
            case .welcome:
                "Set up BuddyGrammar in a couple of minutes."
            case .apiKey:
                "Save the key BuddyGrammar uses for rewrites."
            case .accessibility:
                "Allow cross-app text capture and replacement."
            case .workflow:
                "Choose what happens after a rewrite."
            case .finish:
                "Confirm the app is ready."
            }
        }

        var symbol: String {
            switch self {
            case .welcome:
                "sparkles.rectangle.stack"
            case .apiKey:
                "key.horizontal"
            case .accessibility:
                "hand.raised.circle"
            case .workflow:
                "keyboard"
            case .finish:
                "checkmark.seal"
            }
        }
    }

    @Bindable var model: AppModel
    @State private var currentStep: Step = .welcome
    @State private var accessibilityCheckTrigger = 0
    @State private var accessibilityCheckAttempt = 0
    @State private var isAccessibilityChecking = false
    @State private var accessibilitySecondsUntilRetry = 0

    var body: some View {
        HStack(spacing: 0) {
            progressRail
                .frame(width: 230)
                .padding(20)

            Divider()
                .frame(width: NeoTheme.borderWidth)
                .background(NeoTheme.foreground)
                .padding(.vertical, 20)

            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.horizontal, 28)
                    .padding(.top, 24)
                    .padding(.bottom, 20)

                Divider()
                    .frame(height: NeoTheme.borderWidth)
                    .background(NeoTheme.border)
                    .padding(.horizontal, 28)

                ZStack {
                    stepContent
                        .id(currentStep)
                        .transition(.opacity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(28)

                Divider()
                    .frame(height: NeoTheme.borderWidth)
                    .background(NeoTheme.border)
                    .padding(.horizontal, 28)

                footer
                    .padding(.horizontal, 28)
                    .padding(.vertical, 16)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(NeoTheme.background)
        .foregroundStyle(NeoTheme.foreground)
        .animation(.easeInOut(duration: 0.18), value: currentStep)
        .onAppear {
            model.refreshEnvironmentState()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: currentStep.symbol)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(NeoTheme.primary)

            VStack(alignment: .leading, spacing: 2) {
                Text(currentStep.title)
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .tracking(-0.3)
                Text(currentStep.detail)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(NeoTheme.mutedForeground)
            }
        }
    }

    // MARK: - Progress Rail

    private var progressRail: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("BuddyGrammar")
                .font(.system(size: 18, weight: .black, design: .rounded))
                .tracking(-0.3)
                .foregroundStyle(NeoTheme.foreground)

            Text("Setup")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundStyle(NeoTheme.mutedForeground)
                .padding(.top, 4)

            ForEach(Step.allCases) { step in
                Button {
                    if canJump(to: step) {
                        currentStep = step
                    }
                } label: {
                    HStack(spacing: 10) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(stepAccentColor(step))
                                .frame(width: 28, height: 28)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(NeoTheme.foreground, lineWidth: NeoTheme.borderWidth)
                                )
                            Image(systemName: stepIcon(step))
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(stepIconColor(step))
                        }

                        VStack(alignment: .leading, spacing: 1) {
                            Text(step.title)
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                            Text(step.detail)
                                .font(.system(size: 10, design: .rounded))
                                .foregroundStyle(NeoTheme.mutedForeground)
                                .lineLimit(2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(currentStep == step ? NeoTheme.muted : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: NeoTheme.cornerRadius))
                    .overlay(
                        RoundedRectangle(cornerRadius: NeoTheme.cornerRadius)
                            .stroke(
                                currentStep == step ? NeoTheme.foreground : Color.clear,
                                lineWidth: currentStep == step ? NeoTheme.borderWidth : 0
                            )
                    )
                }
                .buttonStyle(.plain)
                .disabled(!canJump(to: step))
            }

            Spacer()
        }
    }

    // MARK: - Step Content

    @ViewBuilder
    private var stepContent: some View {
        switch currentStep {
        case .welcome:
            welcomeStep
        case .apiKey:
            apiKeyStep
        case .accessibility:
            accessibilityStep
        case .workflow:
            workflowStep
        case .finish:
            finishStep
        }
    }

    // MARK: - Welcome

    private var welcomeStep: some View {
        neoCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("Grab selected text, run the Standard personality, and paste it back with one shortcut.")
                    .font(.system(size: 14, weight: .medium, design: .rounded))

                HStack(spacing: 12) {
                    featurePill(symbol: "keyboard", label: "⌘⇧1")
                    featurePill(symbol: "cpu", label: "gpt-5.4-nano")
                    featurePill(symbol: "menubar.rectangle", label: "Menu bar")
                }

                Text("You can add more personalities later from starter templates like Formal, Email, and Twitter Post.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(NeoTheme.mutedForeground)
            }
        }
    }

    // MARK: - API Key

    private var apiKeyStep: some View {
        neoCard {
            VStack(alignment: .leading, spacing: 14) {
                SecureField("OpenRouter API Key", text: $model.apiKeyDraft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .padding(10)
                    .background(NeoTheme.muted)
                    .clipShape(RoundedRectangle(cornerRadius: NeoTheme.cornerRadius))
                    .overlay(
                        RoundedRectangle(cornerRadius: NeoTheme.cornerRadius)
                            .stroke(NeoTheme.foreground, lineWidth: NeoTheme.borderWidth)
                    )

                Button("Save Key") {
                    model.saveAPIKey()
                }
                .buttonStyle(NeoBrutalistButton())

                if model.hasAPIKey {
                    neoStatusBadge(text: "Key saved", icon: "checkmark.circle.fill", color: NeoTheme.green)
                } else {
                    neoStatusBadge(text: "No key yet", icon: "exclamationmark.triangle.fill", color: NeoTheme.orange)
                }

                if let settingsErrorMessage = model.settingsErrorMessage {
                    neoStatusBadge(text: settingsErrorMessage, icon: "xmark.circle.fill", color: NeoTheme.destructive)
                }
            }
        }
    }

    // MARK: - Accessibility

    private var accessibilityStep: some View {
        neoCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("Enable Accessibility so BuddyGrammar can read and replace selected text.")
                    .font(.system(size: 14, weight: .medium, design: .rounded))

                HStack(spacing: 10) {
                    Button("Open Accessibility Settings") {
                        model.openAccessibilitySettings()
                        accessibilityCheckTrigger += 1
                    }
                    .buttonStyle(NeoBrutalistButton())

                    Button("Check Again") {
                        accessibilityCheckTrigger += 1
                    }
                    .buttonStyle(NeoBrutalistButton(isPrimary: false))
                }

                if model.accessibilityGranted {
                    neoStatusBadge(text: "Permission enabled", icon: "checkmark.circle.fill", color: NeoTheme.green)
                } else {
                    neoStatusBadge(text: "Permission required", icon: "hand.raised.circle.fill", color: NeoTheme.orange)
                }

                if isAccessibilityChecking && !model.accessibilityGranted {
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.7)
                            .controlSize(.small)
                        Text("Checking…")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(NeoTheme.mutedForeground)
                    }
                }
            }
        }
        .task(id: accessibilityCheckTrigger) {
            await runAccessibilityPolling()
        }
        .onAppear {
            accessibilityCheckTrigger += 1
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            accessibilityCheckTrigger += 1
        }
    }

    // MARK: - Workflow

    private var workflowStep: some View {
        neoCard {
            VStack(alignment: .leading, spacing: 14) {
                Picker("After rewriting", selection: outputModeBinding) {
                    ForEach(OutputMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                VStack(alignment: .leading, spacing: 8) {
                    workflowItem(icon: "selection.pin.in.out", text: "Select text anywhere.")
                    workflowItem(icon: "keyboard", text: "Press ⌘⇧1 to run Standard.")
                    workflowItem(
                        icon: "doc.on.clipboard",
                        text: outputModeBinding.wrappedValue == .replaceSelection
                            ? "The corrected text replaces your selection."
                            : "The corrected text goes to the clipboard."
                    )
                }
            }
        }
    }

    // MARK: - Finish

    private var finishStep: some View {
        neoCard {
            VStack(alignment: .leading, spacing: 14) {
                VStack(spacing: 8) {
                    statusRow(
                        title: "API key",
                        isComplete: model.hasAPIKey,
                        successText: "Saved",
                        pendingText: "Missing"
                    )
                    statusRow(
                        title: "Accessibility",
                        isComplete: model.accessibilityGranted,
                        successText: "Enabled",
                        pendingText: "Missing"
                    )
                }

                if isReadyToFinish {
                    neoStatusBadge(text: "Ready to go", icon: "checkmark.seal.fill", color: NeoTheme.green)
                } else {
                    neoStatusBadge(text: "Complete the steps above first", icon: "exclamationmark.triangle.fill", color: NeoTheme.orange)
                }
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button("Back") {
                guard let previous = Step(rawValue: currentStep.rawValue - 1) else { return }
                currentStep = previous
            }
            .buttonStyle(NeoBrutalistButton(isPrimary: false, isDisabled: currentStep == .welcome))
            .disabled(currentStep == .welcome)

            Spacer()

            if currentStep == .finish {
                Button("Start Using BuddyGrammar") {
                    model.completeOnboarding()
                }
                .buttonStyle(NeoBrutalistButton(isDisabled: !isReadyToFinish))
                .disabled(!isReadyToFinish)
                .keyboardShortcut(.defaultAction)
            } else {
                Button("Next") {
                    guard let next = Step(rawValue: currentStep.rawValue + 1) else { return }
                    currentStep = next
                }
                .buttonStyle(NeoBrutalistButton(isDisabled: !canAdvance(from: currentStep)))
                .disabled(!canAdvance(from: currentStep))
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    // MARK: - Shared Components

    private func neoCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(NeoBrutalistCard())
    }

    private func featurePill(symbol: String, label: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(NeoTheme.primary)
            Text(label)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(NeoTheme.accent)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(NeoTheme.muted)
        .clipShape(RoundedRectangle(cornerRadius: NeoTheme.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: NeoTheme.cornerRadius)
                .stroke(NeoTheme.border, lineWidth: 1)
        )
    }

    private func neoStatusBadge(text: String, icon: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
            Text(text)
                .font(.system(size: 12, weight: .bold, design: .rounded))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: NeoTheme.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: NeoTheme.cornerRadius)
                .stroke(color, lineWidth: NeoTheme.borderWidth)
        )
    }

    private func statusRow(title: String, isComplete: Bool, successText: String, pendingText: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 13, weight: .bold, design: .rounded))
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: isComplete ? "checkmark.circle.fill" : "circle.dotted")
                    .font(.system(size: 12, weight: .bold))
                Text(isComplete ? successText : pendingText)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(isComplete ? NeoTheme.green : NeoTheme.orange)
        }
        .padding(10)
        .background(NeoTheme.muted)
        .clipShape(RoundedRectangle(cornerRadius: NeoTheme.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: NeoTheme.cornerRadius)
                .stroke(NeoTheme.border, lineWidth: 1)
        )
    }

    private func workflowItem(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(NeoTheme.accent)
                .frame(width: 18)
            Text(text)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
        }
    }

    // MARK: - Bindings & Logic

    private var outputModeBinding: Binding<OutputMode> {
        Binding(
            get: { model.settingsStore.appSettings.outputMode },
            set: { newValue in
                model.settingsStore.appSettings.outputMode = newValue
            }
        )
    }

    private var isReadyToFinish: Bool {
        model.hasAPIKey && model.accessibilityGranted
    }

    private func canAdvance(from step: Step) -> Bool {
        switch step {
        case .welcome, .workflow:
            true
        case .apiKey:
            model.hasAPIKey
        case .accessibility:
            model.accessibilityGranted
        case .finish:
            isReadyToFinish
        }
    }

    private func canJump(to step: Step) -> Bool {
        step.rawValue <= currentStep.rawValue || Step.allCases[..<step.rawValue].allSatisfy { canAdvance(from: $0) }
    }

    private func stepAccentColor(_ step: Step) -> Color {
        if currentStep == step {
            return NeoTheme.primary
        }
        if canAdvance(from: step) || step == .finish && isReadyToFinish {
            return NeoTheme.green
        }
        return NeoTheme.muted
    }

    private func stepIconColor(_ step: Step) -> Color {
        if currentStep == step {
            return .white
        }
        if canAdvance(from: step) || step == .finish && isReadyToFinish {
            return .white
        }
        return NeoTheme.mutedForeground
    }

    private func stepIcon(_ step: Step) -> String {
        if canAdvance(from: step) || step == .finish && isReadyToFinish {
            return "checkmark"
        }
        return step.symbol
    }

    private func runAccessibilityPolling() async {
        accessibilityCheckAttempt = 0
        accessibilitySecondsUntilRetry = 0
        model.refreshEnvironmentState()

        guard !model.accessibilityGranted else {
            isAccessibilityChecking = false
            return
        }

        isAccessibilityChecking = true

        for attempt in 1...5 {
            guard !Task.isCancelled else {
                isAccessibilityChecking = false
                return
            }

            accessibilityCheckAttempt = attempt
            model.refreshEnvironmentState()

            if model.accessibilityGranted {
                accessibilitySecondsUntilRetry = 0
                isAccessibilityChecking = false
                return
            }

            if attempt < 5 {
                for remaining in stride(from: 3, through: 1, by: -1) {
                    accessibilitySecondsUntilRetry = remaining
                    try? await Task.sleep(for: .seconds(1))
                    guard !Task.isCancelled else {
                        accessibilitySecondsUntilRetry = 0
                        isAccessibilityChecking = false
                        return
                    }
                }
            }
        }

        accessibilitySecondsUntilRetry = 0
        isAccessibilityChecking = false
    }
}
