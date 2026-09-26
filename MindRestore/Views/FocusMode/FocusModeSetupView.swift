import SwiftUI
import FamilyControls

// MARK: - FocusModeSetupView
//
// 4-step setup sheet for Focus Mode.
// Step 0: Intro
// Step 1: Pick apps (FamilyActivityPicker)
// Step 2: Schedule (always-on or timed window)
// Step 3: Duration + enable (requests authorization, applies shields, dismisses)

struct FocusModeSetupView: View {

    /// Optional completion handler — used when embedded in onboarding.
    /// When nil, the view dismisses itself via `dismiss()`.
    var onComplete: (() -> Void)?
    var onSkip: (() -> Void)?

    init(initialStep: Int = 1, onComplete: (() -> Void)? = nil, onSkip: (() -> Void)? = nil) {
        self.onComplete = onComplete
        self.onSkip = onSkip
        _currentStep = State(initialValue: initialStep)
    }

    // MARK: Environment

    @Environment(FocusModeService.self) private var focusModeService
    @Environment(StoreService.self) private var storeService
    @Environment(\.dismiss) private var dismiss

    // MARK: State

    /// Start at "pick apps" — the intro step is skipped when used inline in onboarding.
    @State private var currentStep: Int
    @State private var scheduleEnabled = false
    // Default to evening/bedtime block (22:00 → 08:00) — matches FocusModeService's default and
    // the feature's primary intent (block distractions when winding down / sleeping).
    @State private var scheduleStart = Calendar.current.date(from: DateComponents(hour: 22)) ?? Date()
    @State private var scheduleEnd   = Calendar.current.date(from: DateComponents(hour: 8)) ?? Date()
    @State private var scheduleDays: Set<Int> = [1, 2, 3, 4, 5, 6, 7] // 1=Sun, 7=Sat
    @State private var showingProPaywall = false
    @State private var showingAppPicker = false
    /// Where Memo stands on step 1, so the hill's crest meets his feet.
    @State private var climbCrestY: CGFloat?

    private let dayLabels = ["S", "M", "T", "W", "T", "F", "S"]
    private let dayIndices = [1, 2, 3, 4, 5, 6, 7] // Sunday=1 through Saturday=7

    /// True when this view is being shown as part of OnboardingView — hides the inner page dots
    /// because the outer onboarding flow renders its own progress indicator.
    private var isEmbeddedInOnboarding: Bool { onComplete != nil }

    /// iPhone SE and friends: smaller headline and Memo so the actions stay on screen.
    private var isCompactHeight: Bool { UIScreen.main.bounds.height < 700 }

    private var currentSelectionExceedsFreeLimit: Bool {
        focusModeService.activitySelection.applicationTokens.count > 1 ||
        !focusModeService.activitySelection.categoryTokens.isEmpty ||
        !focusModeService.activitySelection.webDomainTokens.isEmpty
    }

    private var totalSelectedCount: Int {
        focusModeService.activitySelection.applicationTokens.count +
        focusModeService.activitySelection.categoryTokens.count +
        focusModeService.activitySelection.webDomainTokens.count
    }

    // MARK: Body

    var body: some View {
        ZStack(alignment: .bottom) {
            // Memo's hill, the same world as Home.
            OnboardingClimbBackdrop(sky: .twilight, crestY: climbCrestY)

            VStack(spacing: 0) {
                TabView(selection: $currentStep) {
                    pickAppsStep.tag(1)
                    scheduleStep.tag(2)
                    durationStep.tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .scrollDisabled(true)
                .animation(.easeInOut, value: currentStep)

                // Inner page indicator — only shown when used as a standalone sheet (not in onboarding).
                if !isEmbeddedInOnboarding {
                    HStack(spacing: 8) {
                        ForEach(1..<4, id: \.self) { index in
                            Capsule()
                                .fill(
                                    index == currentStep
                                        ? AnyShapeStyle(AppColors.accentGradient)
                                        : AnyShapeStyle(Color.gray.opacity(0.25))
                                )
                                .frame(width: index == currentStep ? 24 : 8, height: 8)
                                .animation(.spring(response: 0.3), value: currentStep)
                        }
                    }
                    .padding(.bottom, 20)
                }
            }
        }
        .coordinateSpace(name: ClimbReporter.space)
        .environment(\.climbReporter, ClimbReporter(crest: { y in if climbCrestY != y { climbCrestY = y } }))
        .preferredColorScheme(.dark)
        .environment(\.colorScheme, .dark)
    }

    // MARK: - Step 1: Pick Apps

    private var pickAppsStep: some View {
        let totalSelected = totalSelectedCount

        return VStack(spacing: isCompactHeight ? 12 : 20) {
            Spacer().frame(height: isCompactHeight ? 8 : 26)

            VStack(alignment: .leading, spacing: 8) {
                ClimbHeadline(text: "Pick what\nMemo bounces.", size: isCompactHeight ? 30 : 36, alignment: .leading)

                ClimbBodyText(text: "Put your worst apps behind the rope.", size: 16, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 32)

            targetBouncerScene(totalSelected: totalSelected)
                .padding(.horizontal, 24)

            Spacer()

            setupBottomActions(totalSelected: totalSelected)
        }
        .padding(.bottom, onSkip == nil ? 8 : 2)
        .responsiveContent(maxWidth: 500)
        .frame(maxWidth: .infinity)
        .familyActivityPicker(isPresented: $showingAppPicker, selection: Binding(
            get: { focusModeService.activitySelection },
            set: { newSelection in
                let exceedsFreeLimit = newSelection.applicationTokens.count > 1 ||
                    !newSelection.categoryTokens.isEmpty ||
                    !newSelection.webDomainTokens.isEmpty

                if !storeService.isProUser && exceedsFreeLimit {
                    showingProPaywall = true
                    return
                }

                focusModeService.updateActivitySelection(newSelection)

                if isEmbeddedInOnboarding && totalCount(for: newSelection) > 0 {
                    withAnimation(.easeInOut(duration: 0.24)) {
                        currentStep = 2
                    }
                }
            }
        ))
        .sheet(isPresented: $showingProPaywall) {
            PaywallView(triggerSource: "focus_mode_limit")
        }
    }

    private func targetBouncerScene(totalSelected: Int) -> some View {
        Button {
            showingAppPicker = true
        } label: {
            VStack(spacing: 12) {
                hitListSurface(totalSelected: totalSelected)

                // Memo stands guard on the hill below his list.
                ClimbMemo(mood: .neutral, size: isCompactHeight ? 84 : 118)
                    .padding(.top, isCompactHeight ? 0 : 6)

                HStack(spacing: 8) {
                    StickerIcon(kind: .crown, size: 18)
                    Text(storeService.isProUser ? "Memo guards the whole feed" : "Starter access guards 1 app")
                        .font(.brand(size: 13, weight: .bold))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(totalSelected > 0 ? "\(totalSelected) Focus Mode targets selected. Edit targets." : "No Focus Mode targets selected. Pick targets.")
    }

    private func hitListSurface(totalSelected: Int) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center) {
                Text("MEMO'S HIT LIST")
                    .font(.system(size: 12, weight: .black, design: .monospaced))
                    .tracking(1.4)
                    .foregroundStyle(ClimbColor.mint)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 18, weight: .black))
                    .foregroundStyle(ClimbColor.mint.opacity(0.8))
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(totalSelected > 0 ? "\(totalSelected) targets blocked" : "Waiting for targets")
                    .font(.brand(size: 25, weight: .heavy))
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                    Text(totalSelected > 0 ? "Tap to edit the apps Memo blocks." : "Pick the apps built to pull you back.")
                    .font(.brand(size: 14, weight: .semibold))
                    .foregroundStyle(AppColors.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ZStack(alignment: .bottomTrailing) {
                hitListEvidenceGrid(totalSelected: totalSelected)

                if totalSelected > 0 {
                    Text("BLOCKED")
                        .font(.system(size: 22, weight: .black, design: .monospaced))
                        .tracking(2.0)
                        .foregroundStyle(AppColors.accent)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .overlay {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(AppColors.accent, lineWidth: 2)
                        }
                        .rotationEffect(.degrees(-8))
                        .offset(x: -74, y: -6)
                        .transition(.scale(scale: 1.08).combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color(red: 0.024, green: 0.118, blue: 0.149).opacity(0.88)))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(ClimbColor.ink, lineWidth: 2.5))
        .background(RoundedRectangle(cornerRadius: 25.5, style: .continuous).strokeBorder(.white.opacity(0.9), lineWidth: 2).padding(-2))
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(ClimbColor.ink).offset(y: 5))
    }

    private func hitListEvidenceGrid(totalSelected: Int) -> some View {
        let appTokens = Array(focusModeService.activitySelection.applicationTokens)
        let categoryTokens = Array(focusModeService.activitySelection.categoryTokens)
        let totalTokens = appTokens.count + categoryTokens.count + focusModeService.activitySelection.webDomainTokens.count

        return HStack(alignment: .center, spacing: 12) {
            if totalSelected == 0 {
                ForEach(0..<3, id: \.self) { index in
                    ghostEvidenceSlot(index: index)
                }
            } else {
                ForEach(Array(appTokens.prefix(4).enumerated()), id: \.element) { index, token in
                    Label(token)
                        .labelStyle(.iconOnly)
                        .scaleEffect(1.42)
                        .frame(width: 82, height: 82)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .rotationEffect(.degrees([-6, 4, -3, 5][min(index, 3)]))
                        .shadow(color: AppColors.pageBg.opacity(0.56), radius: 12, y: 7)
                }

                let categorySlots = max(0, 4 - appTokens.prefix(4).count)
                ForEach(Array(categoryTokens.prefix(categorySlots).enumerated()), id: \.element) { index, token in
                    Label(token)
                        .labelStyle(.iconOnly)
                        .scaleEffect(1.42)
                        .frame(width: 82, height: 82)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .rotationEffect(.degrees([5, -5, 3, -3][min(index, 3)]))
                        .shadow(color: AppColors.pageBg.opacity(0.56), radius: 12, y: 7)
                }

                if totalTokens > 4 {
                    Text("+\(totalTokens - 4)")
                        .font(.system(size: 19, weight: .black, design: .monospaced))
                        .foregroundStyle(AppColors.textPrimary)
                        .frame(width: 62, height: 62)
                        .background(AppColors.accent.opacity(0.24), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(AppColors.accent.opacity(0.46), lineWidth: 1.2)
                        }
                        .rotationEffect(.degrees(5))
                }
            }

            Spacer(minLength: 44)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func ghostEvidenceSlot(index: Int) -> some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .strokeBorder(style: StrokeStyle(lineWidth: 1.4, dash: [5, 4]))
            .foregroundStyle(AppColors.textTertiary.opacity(0.46))
            .frame(width: 62, height: 62)
            .overlay {
                Image(systemName: ["app.dashed", "lock.fill", "plus"][min(index, 2)])
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(AppColors.textTertiary.opacity(0.54))
            }
            .rotationEffect(.degrees([-5, 3, -2][min(index, 2)]))
    }

    private func totalCount(for selection: FamilyActivitySelection) -> Int {
        selection.applicationTokens.count +
        selection.categoryTokens.count +
        selection.webDomainTokens.count
    }

    private func setupBottomActions(totalSelected: Int) -> some View {
        VStack(spacing: 12) {
            ChunkyButton(
                title: totalSelected > 0 ? "Bounce these apps" : "Pick apps",
                systemImage: totalSelected > 0 ? nil : "plus"
            ) {
                guard totalSelected > 0 else {
                    showingAppPicker = true
                    return
                }

                if !storeService.isProUser && currentSelectionExceedsFreeLimit {
                    showingProPaywall = true
                } else {
                    currentStep = 2
                }
            }

            if let onSkip {
                Button {
                    onSkip()
                } label: {
                    Text("Set up later")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(minHeight: 28)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 32)
    }

    // MARK: - Step 2: Schedule

    private var scheduleStep: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 14)

            VStack(alignment: .leading, spacing: 8) {
                Text("When should\nMemo block?")
                    .font(.brand(size: 36, weight: .heavy))
                    .foregroundStyle(AppColors.textPrimary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .minimumScaleFactor(0.86)
                    .fixedSize(horizontal: false, vertical: true)

                Text("All day, or only when the feed usually wins.")
                    .font(.brand(size: 18, weight: .semibold))
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.leading)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 32)
                .padding(.bottom, 20)

            targetReceiptLine
                .padding(.horizontal, 32)
                .padding(.bottom, 18)

            shiftChoiceList
                .padding(.horizontal, 32)

            // Time + day pickers when schedule is selected
            if scheduleEnabled {
                dangerHoursControls
                    .padding(.horizontal, 32)
                    .padding(.top, 14)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Spacer()

            continueButton("Set block schedule") { currentStep = 3 }
        }
        .padding(.bottom, 8)
        .responsiveContent(maxWidth: 500)
        .frame(maxWidth: .infinity)
    }

    private var targetReceiptLine: some View {
        HStack(spacing: 14) {
            selectedTargetTokensStrip

            VStack(alignment: .leading, spacing: 3) {
                Text(scheduleEnabled ? "DANGER-HOURS TARGETS" : "ALWAYS-ON TARGETS")
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .tracking(1.1)
                    .foregroundStyle(scheduleEnabled ? AppColors.violet : AppColors.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text(scheduleEnabled ? "Blocking these when the feed gets loud." : "Blocking these until you train.")
                    .font(.brand(size: 14, weight: .semibold))
                    .foregroundStyle(AppColors.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(AppColors.cardBorder.opacity(0.50))
                .frame(height: 1)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppColors.cardBorder.opacity(0.50))
                .frame(height: 1)
        }
        .frame(maxWidth: .infinity)
    }

    private var selectedTargetTokensStrip: some View {
        HStack(spacing: -8) {
            selectedApplicationTokenIcons
            selectedCategoryTokenIcons
            hiddenTargetBadge
        }
        .frame(width: targetStripWidth, height: 44, alignment: .leading)
        .opacity(totalVisibleAndHiddenTargets > 0 ? 1 : 0)
        .accessibilityHidden(totalVisibleAndHiddenTargets == 0)
    }

    private var visibleApplicationTokenCount: Int {
        min(3, focusModeService.activitySelection.applicationTokens.count)
    }

    private var visibleCategoryTokenCount: Int {
        let remainingSlots = max(0, 3 - visibleApplicationTokenCount)
        return min(remainingSlots, focusModeService.activitySelection.categoryTokens.count)
    }

    private var hiddenTargetCount: Int {
        let selection = focusModeService.activitySelection
        let total = selection.applicationTokens.count
            + selection.categoryTokens.count
            + selection.webDomainTokens.count
        return max(0, total - visibleApplicationTokenCount - visibleCategoryTokenCount)
    }

    private var totalVisibleAndHiddenTargets: Int {
        visibleApplicationTokenCount + visibleCategoryTokenCount + hiddenTargetCount
    }

    private var targetStripWidth: CGFloat {
        let badgeCount = hiddenTargetCount > 0 ? 1 : 0
        let slots = visibleApplicationTokenCount + visibleCategoryTokenCount + badgeCount
        return slots == 0 ? 0 : CGFloat(slots * 32 + 8)
    }

    private var selectedApplicationTokenIcons: some View {
        let tokens = Array(focusModeService.activitySelection.applicationTokens.prefix(3))
        let angles: [Double] = [-6, 4, -3]

        return ForEach(Array(tokens.enumerated()), id: \.element) { index, token in
            Label(token)
                .labelStyle(.iconOnly)
                .scaleEffect(1.04)
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .rotationEffect(.degrees(angles[index]))
                .shadow(color: AppColors.pageBg.opacity(0.55), radius: 7, y: 4)
        }
    }

    private var selectedCategoryTokenIcons: some View {
        let slots = max(0, 3 - visibleApplicationTokenCount)
        let tokens = Array(focusModeService.activitySelection.categoryTokens.prefix(slots))
        let angles: [Double] = [5, -5, 3]

        return ForEach(Array(tokens.enumerated()), id: \.element) { index, token in
            Label(token)
                .labelStyle(.iconOnly)
                .scaleEffect(1.04)
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .rotationEffect(.degrees(angles[index]))
                .shadow(color: AppColors.pageBg.opacity(0.55), radius: 7, y: 4)
        }
    }

    @ViewBuilder
    private var hiddenTargetBadge: some View {
        if hiddenTargetCount > 0 {
            Text("+\(hiddenTargetCount)")
                .font(.system(size: 14, weight: .black, design: .monospaced))
                .foregroundStyle(AppColors.textPrimary)
                .frame(width: 38, height: 38)
                .background(AppColors.accent.opacity(0.22), in: Circle())
                .overlay {
                    Circle()
                        .stroke(AppColors.accent.opacity(0.42), lineWidth: 1)
                }
                .rotationEffect(.degrees(5))
        }
    }

    private var shiftChoiceList: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(AppColors.cardBorder.opacity(0.62))
                .frame(height: 1)

            shiftModeButton(
                title: "Always on",
                subtitle: "No weak hours. Apps stay blocked until you train.",
                icon: "lock.fill",
                tint: AppColors.accent,
                isSelected: !scheduleEnabled
            ) { selectSchedule(enabled: false) }

            Rectangle()
                .fill(AppColors.cardBorder.opacity(0.62))
                .frame(height: 1)

            shiftModeButton(
                title: "Danger hours",
                subtitle: "Nights, mornings, or whenever the feed wins.",
                icon: "moon.fill",
                tint: AppColors.violet,
                isSelected: scheduleEnabled
            ) { selectSchedule(enabled: true) }

            Rectangle()
                .fill(AppColors.cardBorder.opacity(0.62))
                .frame(height: 1)
        }
    }

    private func shiftModeButton(title: String, subtitle: String, icon: String, tint: Color, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(isSelected ? tint.opacity(0.20) : AppColors.cardBorder.opacity(0.20))
                        .frame(width: 42, height: 42)

                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .black))
                        .foregroundStyle(isSelected ? tint : AppColors.textSecondary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.brand(size: 20, weight: .heavy))
                        .foregroundStyle(AppColors.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)

                    Text(subtitle)
                        .font(.brand(size: 12, weight: .semibold))
                        .foregroundStyle(AppColors.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22, weight: .black))
                        .foregroundStyle(tint)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.vertical, 14)
            .padding(.leading, 14)
            .padding(.trailing, 2)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .leading) {
                if isSelected {
                    Capsule()
                        .fill(tint)
                        .frame(width: 4, height: 48)
                        .shadow(color: tint.opacity(0.42), radius: 12, x: 0, y: 0)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func selectSchedule(enabled: Bool) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
            scheduleEnabled = enabled
        }
    }

    private var dangerHoursControls: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("DANGER HOURS")
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .tracking(1.2)
                    .foregroundStyle(AppColors.violet)

                Spacer()

                Text("\(formattedTime(scheduleStart)) - \(formattedTime(scheduleEnd))")
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .foregroundStyle(AppColors.violet)
                    .monospacedDigit()
            }

            Rectangle()
                .fill(AppColors.cardBorder.opacity(0.50))
                .frame(height: 1)

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Start")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(AppColors.textSecondary)
                    DatePicker("", selection: $scheduleStart, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                }

                Spacer()

                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(AppColors.violet.opacity(0.86))

                Spacer()

                VStack(alignment: .trailing, spacing: 5) {
                    Text("End")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(AppColors.textSecondary)
                    DatePicker("", selection: $scheduleEnd, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                }
            }

            Rectangle()
                .fill(AppColors.cardBorder.opacity(0.50))
                .frame(height: 1)

            HStack(spacing: 6) {
                ForEach(Array(zip(dayIndices, dayLabels)), id: \.0) { index, label in
                    let isActive = scheduleDays.contains(index)
                    Button {
                        withAnimation(.spring(response: 0.22, dampingFraction: 0.88)) {
                            if scheduleDays.contains(index) {
                                if scheduleDays.count > 1 {
                                    scheduleDays.remove(index)
                                }
                            } else {
                                scheduleDays.insert(index)
                            }
                        }
                    } label: {
                        Text(label)
                            .font(.system(size: 13, weight: .black, design: .rounded))
                            .foregroundStyle(isActive ? AppColors.textPrimary : AppColors.textSecondary)
                            .frame(width: 34, height: 34)
                            .background(
                                isActive ? AppColors.violet.opacity(0.34) : AppColors.cardBorder.opacity(0.18),
                                in: Circle()
                            )
                            .overlay {
                                Circle()
                                    .stroke(isActive ? AppColors.violet.opacity(0.62) : AppColors.cardBorder.opacity(0.28), lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(label) schedule day")
                    .accessibilityValue(isActive ? "Selected" : "Not selected")
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.top, 2)
    }

    // MARK: - Step 3: Duration + Enable

    private var durationStep: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 14)

            VStack(alignment: .leading, spacing: 8) {
                Text("Every pass is\na gamble.")
                    .font(.brand(size: 36, weight: .heavy))
                    .foregroundStyle(AppColors.textPrimary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .minimumScaleFactor(0.86)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Spin the slot when you train. You win 5, 10, or 20 minutes.")
                    .font(.brand(size: 18, weight: .semibold))
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 32)
                .padding(.bottom, 24)

            passDurationHero
                .padding(.horizontal, 32)
                .padding(.top, 4)
                .padding(.bottom, 30)

            passTextSelector
                .padding(.horizontal, 32)

            Spacer()

            // Enable Focus Mode CTA
            Button {
                if !storeService.isProUser && currentSelectionExceedsFreeLimit {
                    showingProPaywall = true
                    return
                }

                Task {
                    await focusModeService.requestAuthorization()
                    focusModeService.updateScheduleDays(scheduleDays)
                    focusModeService.updateSchedule(
                        enabled: scheduleEnabled,
                        start: scheduleStart,
                        end: scheduleEnd
                    )
                    focusModeService.enable()
                    Analytics.focusSetupCompleted()
                    if let onComplete {
                        onComplete()
                    } else {
                        dismiss()
                    }
                }
            } label: {
                Text("Turn on app blocking")
                    .gradientButton()
            }
            .padding(.horizontal, 32)
        }
        .padding(.bottom, 8)
        .responsiveContent(maxWidth: 500)
        .frame(maxWidth: .infinity)
    }

    private var passDurationHero: some View {
        VStack(spacing: 14) {
            passHeroTokenRow

            ZStack {
                Circle()
                    .fill(AppColors.violet.opacity(0.14))
                    .frame(width: 188, height: 188)
                    .blur(radius: 22)

                VStack(spacing: -4) {
                    Text("5–20")
                        .font(.system(size: 96, weight: .black, design: .rounded))
                        .foregroundStyle(AppColors.textPrimary)
                        .monospacedDigit()
                        .minimumScaleFactor(0.78)

                    Text("MIN PASS")
                        .font(.system(size: 15, weight: .black, design: .monospaced))
                        .tracking(2.0)
                        .foregroundStyle(AppColors.mint)
                }
            }
            .frame(height: 184)

            Text("Land a rare game, win the big window")
                .font(.brand(size: 14, weight: .bold))
                .foregroundStyle(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("5 to 20 minute pass. Your spin decides the window.")
    }

    @ViewBuilder
    private var passHeroTokenRow: some View {
        let appTokens = Array(focusModeService.activitySelection.applicationTokens)
        let categoryTokens = Array(focusModeService.activitySelection.categoryTokens)
        let webCount = focusModeService.activitySelection.webDomainTokens.count
        let visibleAppTokens = Array(appTokens.prefix(3))
        let categorySlots = max(0, 3 - visibleAppTokens.count)
        let visibleCategoryTokens = Array(categoryTokens.prefix(categorySlots))
        let visibleCount = visibleAppTokens.count + visibleCategoryTokens.count
        let hiddenCount = max(0, appTokens.count + categoryTokens.count + webCount - visibleCount)

        if visibleCount > 0 || hiddenCount > 0 {
            HStack(spacing: -10) {
                ForEach(Array(visibleAppTokens.enumerated()), id: \.element) { index, token in
                    Label(token)
                        .labelStyle(.iconOnly)
                        .scaleEffect(1.10)
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .rotationEffect(.degrees([-6, 3, 5][min(index, 2)]))
                        .shadow(color: AppColors.pageBg.opacity(0.62), radius: 8, y: 4)
                }

                ForEach(Array(visibleCategoryTokens.enumerated()), id: \.element) { index, token in
                    Label(token)
                        .labelStyle(.iconOnly)
                        .scaleEffect(1.10)
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .rotationEffect(.degrees([5, -4, 3][min(index, 2)]))
                        .shadow(color: AppColors.pageBg.opacity(0.62), radius: 8, y: 4)
                }

                if hiddenCount > 0 {
                    Text("+\(hiddenCount)")
                        .font(.system(size: 12, weight: .black, design: .monospaced))
                        .foregroundStyle(AppColors.textPrimary)
                        .frame(width: 40, height: 40)
                        .background(AppColors.accent.opacity(0.22), in: Circle())
                        .overlay {
                            Circle()
                                .stroke(AppColors.accent.opacity(0.42), lineWidth: 1)
                        }
                        .rotationEffect(.degrees(6))
                }
            }
            .frame(height: 48)
            .accessibilityHidden(true)
        }
    }

    /// The spin decides the window now — this strip just explains the payout
    /// table, no choice to make.
    private var passTextSelector: some View {
        HStack(spacing: 0) {
            payoutTierColumn(minutes: 5, label: "QUICK", tint: AppColors.textSecondary)
            payoutTierColumn(minutes: 10, label: "SOLID", tint: AppColors.accent)
            payoutTierColumn(minutes: 20, label: "RARE", tint: AppColors.amber)
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(AppColors.cardBorder.opacity(0.48))
                .frame(height: 1)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppColors.cardBorder.opacity(0.48))
                .frame(height: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Payouts: 5 minutes for quick games, 10 for memory games, 20 for the rare hard games.")
    }

    private func payoutTierColumn(minutes: Int, label: String, tint: Color) -> some View {
        VStack(spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("\(minutes)")
                    .font(.system(size: 21, weight: .black, design: .rounded))
                    .monospacedDigit()
                Text("min")
                    .font(.brand(size: 13, weight: .heavy))
            }
            .foregroundStyle(tint)

            Text(label)
                .font(.system(size: 9, weight: .black, design: .monospaced))
                .tracking(1.0)
                .foregroundStyle(tint.opacity(0.78))
        }
        .frame(maxWidth: .infinity, minHeight: 66)
    }

    // MARK: - Helpers

    private func continueButton(_ title: String = "Continue", disabled: Bool = false, action: @escaping () -> Void) -> some View {
        ChunkyButton(title: title, systemImage: nil, action: action)
            .opacity(disabled ? 0.55 : 1.0)
            .disabled(disabled)
            .padding(.horizontal, 32)
    }

    private func scheduleOptionRow(
        title: String,
        subtitle: String,
        icon: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isSelected ? AppColors.accent : .secondary)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(AppColors.accent)
                        .font(.system(size: 20))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
    }

    private func summaryRow(icon: String, label: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppColors.accent)
                .frame(width: 20)
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func formattedTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }
}

// MARK: - FamilyActivityPickerWrapper

/// UIViewControllerRepresentable wrapper so FamilyActivityPicker can be embedded
/// inside a regular SwiftUI layout without needing to be a sheet itself.
private struct FamilyActivityPickerWrapper: UIViewControllerRepresentable {
    @Binding var selection: FamilyActivitySelection

    func makeUIViewController(context: Context) -> UIViewController {
        let picker = FamilyActivityPicker(selection: $selection)
        let host = UIHostingController(rootView: picker)
        host.view.backgroundColor = .clear
        // Recursively strip backgrounds after layout pass
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            Self.clearBackgrounds(in: host.view)
        }
        return host
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        if let host = uiViewController as? UIHostingController<FamilyActivityPicker> {
            host.rootView = FamilyActivityPicker(selection: $selection)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                Self.clearBackgrounds(in: host.view)
            }
        }
    }

    /// Recursively walks the view hierarchy to clear rounded-rect backgrounds
    /// that the system applies to FamilyActivityPicker.
    private static func clearBackgrounds(in view: UIView) {
        view.backgroundColor = .clear
        view.layer.cornerRadius = 0
        view.layer.borderWidth = 0
        view.layer.shadowOpacity = 0

        // Clear any visual effect views or grouped-style table backgrounds
        if let effectView = view as? UIVisualEffectView {
            effectView.effect = nil
            effectView.backgroundColor = .clear
        }

        for subview in view.subviews {
            clearBackgrounds(in: subview)
        }
    }
}

#if DEBUG
#Preview("Focus Pass Duration") {
    FocusModeSetupView(initialStep: 3, onComplete: {})
        .environment(FocusModeService())
        .environment(StoreService())
        .preferredColorScheme(.dark)
}
#endif
