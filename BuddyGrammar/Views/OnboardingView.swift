import AppKit
import SwiftUI

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
        HStack(spacing: 28) {
            progressRail
                .frame(width: 220)

            VStack(alignment: .leading, spacing: 24) {
                header

                ZStack {
                    stepContent
                        .id(currentStep)
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                footer
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.14, green: 0.16, blue: 0.23),
                    Color(red: 0.08, green: 0.10, blue: 0.14)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .foregroundStyle(.white)
        .animation(.easeInOut(duration: 0.22), value: currentStep)
        .onAppear {
            model.refreshEnvironmentState()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("BuddyGrammar")
                .font(.system(size: 34, weight: .bold, design: .rounded))
            Text(currentStep.title)
                .font(.system(size: 28, weight: .semibold, design: .rounded))
            Text(currentStep.detail)
                .font(.title3)
                .foregroundStyle(.white.opacity(0.72))
        }
    }

    private var progressRail: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Setup")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.82))

            ForEach(Step.allCases) { step in
                Button {
                    if canJump(to: step) {
                        currentStep = step
                    }
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(stepAccentColor(step))
                                .frame(width: 30, height: 30)
                            Image(systemName: stepIcon(step))
                                .font(.system(size: 13, weight: .semibold))
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(step.title)
                                .font(.headline)
                            Text(step.detail)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.65))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(.white.opacity(currentStep == step ? 0.14 : 0.06), in: RoundedRectangle(cornerRadius: 18))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18)
                            .strokeBorder(.white.opacity(currentStep == step ? 0.16 : 0.08))
                    }
                }
                .buttonStyle(.plain)
                .disabled(!canJump(to: step))
            }
        }
    }

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

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            onboardingPanel {
                VStack(alignment: .leading, spacing: 14) {
                    Text("BuddyGrammar lives in the menu bar, grabs the text you selected, sends it to OpenRouter, and gives you back cleaner writing in a single shortcut.")
                        .font(.title3)

                    HStack(spacing: 14) {
                        featurePill(symbol: "keyboard", title: "Default shortcut", detail: "⌘⇧F")
                        featurePill(symbol: "arrow.trianglehead.2.clockwise.rotate.90", title: "Fixed model", detail: "openai/gpt-5.4-nano")
                        featurePill(symbol: "sparkles.rectangle.stack", title: "Overlay", detail: "Top live status")
                    }

                    Text("This setup will walk through the required permissions first, then show the basic rewrite flow.")
                        .foregroundStyle(.white.opacity(0.74))
                }
            }
        }
    }

    private var apiKeyStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            onboardingPanel {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Paste your OpenRouter API key. BuddyGrammar stores it in Keychain and uses it for every prompt profile.")
                        .font(.title3)

                    SecureField("OpenRouter API Key", text: $model.apiKeyDraft)
                        .textFieldStyle(.roundedBorder)

                    HStack(spacing: 12) {
                        Button("Save Key") {
                            model.saveAPIKey()
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Open Settings") {
                            model.openSettings()
                        }
                        .buttonStyle(.bordered)
                    }

                    if model.hasAPIKey {
                        Label("API key saved in Keychain.", systemImage: "checkmark.shield.fill")
                            .foregroundStyle(.green)
                    } else {
                        Label("No API key saved yet.", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }

                    if let settingsErrorMessage = model.settingsErrorMessage {
                        Text(settingsErrorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    Text("Provider and model are fixed in v1: OpenRouter + `openai/gpt-5.4-nano`.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.68))
                }
            }
        }
    }

    private var accessibilityStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            onboardingPanel {
                VStack(alignment: .leading, spacing: 16) {
                    Text("BuddyGrammar needs Accessibility permission to read selected text from other apps and paste corrected text back when replace mode is enabled.")
                        .font(.title3)

                    VStack(alignment: .leading, spacing: 10) {
                        permissionRow(
                            title: "Accessibility",
                            detail: "Required. Lets BuddyGrammar read selected text and replace it in other apps."
                        )
                        permissionRow(
                            title: "Network access",
                            detail: "Used to send the selected text to OpenRouter for rewriting."
                        )
                        permissionRow(
                            title: "Keychain storage",
                            detail: "Used to store your OpenRouter API key securely on this Mac."
                        )
                    }

                    HStack(spacing: 12) {
                        Button("Open Accessibility Settings") {
                            model.openAccessibilitySettings()
                            accessibilityCheckTrigger += 1
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Check Again") {
                            accessibilityCheckTrigger += 1
                        }
                        .buttonStyle(.bordered)
                    }

                    if model.accessibilityGranted {
                        Label("Accessibility permission is enabled.", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Label("Accessibility is still required.", systemImage: "hand.raised.circle.fill")
                            .foregroundStyle(.orange)
                    }

                    if isAccessibilityChecking {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Waiting for macOS to apply the permission.", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                                .foregroundStyle(.white.opacity(0.88))
                            Text("BuddyGrammar rechecks automatically when you come back from System Settings.")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.72))

                            if accessibilityCheckAttempt > 0 {
                                Text("Attempt \(accessibilityCheckAttempt) of 5")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.72))
                            }

                            if accessibilitySecondsUntilRetry > 0 {
                                Text("Next retry in \(accessibilitySecondsUntilRetry)s")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.72))
                            }
                        }
                    } else if accessibilityCheckAttempt == 5 && !model.accessibilityGranted {
                        Text("No change detected after 5 checks. If you just enabled it, wait a second and press Check Again.")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                    }

                    Text("System Settings > Privacy & Security > Accessibility > enable BuddyGrammar.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.68))

                    if model.isRunningFromDerivedData {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Current app bundle")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.82))

                            Text(model.appBundlePath)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                                .foregroundStyle(.white.opacity(0.68))

                            Text("This is a debug build running from DerivedData. If you rebuild and reopen a different bundle, macOS can treat it as a different app for Accessibility.")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.68))

                            Button("Reveal Current App in Finder") {
                                model.revealCurrentAppInFinder()
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(.top, 8)
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

    private var workflowStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            onboardingPanel {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Choose what happens after a rewrite, then test the default Grammar profile in any app.")
                        .font(.title3)

                    Picker("After rewriting", selection: outputModeBinding) {
                        ForEach(OutputMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    VStack(alignment: .leading, spacing: 10) {
                        Label("Select text in TextEdit, Notes, Mail, or a browser field.", systemImage: "selection.pin.in.out")
                        Label("Press `⌘⇧F` to run the built-in Grammar profile.", systemImage: "keyboard")
                        Label("Watch the top overlay while BuddyGrammar is fixing your text.", systemImage: "sparkles.rectangle.stack")
                        Label(outputModeBinding.wrappedValue == .replaceSelection ? "The corrected text will paste back into the active app." : "The corrected text will go to the clipboard without changing the original text.", systemImage: "doc.on.clipboard")
                    }
                    .font(.headline)

                    HStack(spacing: 12) {
                        Button("Open Full Settings") {
                            model.openSettings()
                        }
                        .buttonStyle(.bordered)

                        Text("You can add more prompt profiles and give each one its own shortcut later.")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.68))
                    }
                }
            }
        }
    }

    private var finishStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            onboardingPanel {
                VStack(alignment: .leading, spacing: 16) {
                    Text("BuddyGrammar is ready once the API key and Accessibility permission are both in place.")
                        .font(.title3)

                    statusRow(
                        title: "OpenRouter API key",
                        isComplete: model.hasAPIKey,
                        successText: "Saved in Keychain",
                        pendingText: "Still missing"
                    )

                    statusRow(
                        title: "Accessibility permission",
                        isComplete: model.accessibilityGranted,
                        successText: "Enabled",
                        pendingText: "Still missing"
                    )

                    statusRow(
                        title: "Default Grammar shortcut",
                        isComplete: true,
                        successText: "⌘⇧F",
                        pendingText: "⌘⇧F"
                    )

                    if isReadyToFinish {
                        Label("Setup complete. You can close this window and use BuddyGrammar from any app.", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                    } else {
                        Text("Go back and finish the required setup steps before closing onboarding.")
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("Back") {
                guard let previous = Step(rawValue: currentStep.rawValue - 1) else { return }
                currentStep = previous
            }
            .buttonStyle(.bordered)
            .disabled(currentStep == .welcome)

            Spacer()

            if currentStep == .finish {
                Button("Start Using BuddyGrammar") {
                    model.completeOnboarding()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isReadyToFinish)
                .keyboardShortcut(.defaultAction)
            } else {
                Button("Next") {
                    guard let next = Step(rawValue: currentStep.rawValue + 1) else { return }
                    currentStep = next
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canAdvance(from: currentStep))
                .keyboardShortcut(.defaultAction)
            }
        }
    }

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
            return Color(red: 0.44, green: 0.72, blue: 1.0)
        }

        if canAdvance(from: step) || step == .finish && isReadyToFinish {
            return Color.green.opacity(0.88)
        }

        return .white.opacity(0.18)
    }

    private func stepIcon(_ step: Step) -> String {
        if canAdvance(from: step) || step == .finish && isReadyToFinish {
            return "checkmark"
        }
        return step.symbol
    }

    private func onboardingPanel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 24))
            .overlay {
                RoundedRectangle(cornerRadius: 24)
                    .strokeBorder(.white.opacity(0.08))
            }
    }

    private func featurePill(symbol: String, title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
            Text(title)
                .font(.headline)
            Text(detail)
                .foregroundStyle(.white.opacity(0.74))
        }
        .padding(16)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(.white.opacity(0.08))
        }
    }

    private func statusRow(title: String, isComplete: Bool, successText: String, pendingText: String) -> some View {
        HStack {
            Text(title)
                .font(.headline)
            Spacer()
            Label(isComplete ? successText : pendingText, systemImage: isComplete ? "checkmark.circle.fill" : "circle.dotted")
                .foregroundStyle(isComplete ? .green : .orange)
        }
        .padding(.vertical, 8)
    }

    private func permissionRow(title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.shield")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.84))
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .padding(14)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18))
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
