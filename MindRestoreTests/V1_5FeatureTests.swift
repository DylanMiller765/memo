import XCTest
@testable import MindRestore

@MainActor
final class RemovedV15ChallengeFeatureTests: XCTestCase {
    func testPaywallTrainingCountDoesNotGateGames() {
        UserDefaults.standard.removeObject(forKey: "training_exercise_count")
        UserDefaults.standard.removeObject(forKey: "training_exercise_date")

        let service = PaywallTriggerService()

        for _ in 0..<10 {
            service.recordExerciseCompleted(gameType: .reactionTime)
        }

        XCTAssertEqual(service.exercisesToday, 10)
        XCTAssertFalse(service.shouldShowPaywall)
    }
}

final class AnalyticsFunnelTests: XCTestCase {
    func testOnboardingStepPropertiesIncludeFunnelContext() {
        let properties = Analytics.onboardingStepProperties(
            step: "screenTimeAccessApproved",
            stepIndex: 7,
            totalSteps: 15,
            secondsSinceStart: 91.4,
            secondsOnStep: 12.8,
            goals: ["doomscrolling", "loseFocus"],
            selectedAge: 22,
            screenTimeHours: 5.25,
            screenTimeIsEstimate: false,
            brainAge: 29,
            brainScore: 612,
            receiptCount: 3
        )

        XCTAssertEqual(properties["step"] as? String, "screenTimeAccessApproved")
        XCTAssertEqual(properties["step_index"] as? Int, 7)
        XCTAssertEqual(properties["total_steps"] as? Int, 15)
        XCTAssertEqual(properties["progress_percent"] as? Int, 53)
        XCTAssertEqual(properties["seconds_since_onboarding_start"] as? Int, 91)
        XCTAssertEqual(properties["seconds_on_step"] as? Int, 13)
        XCTAssertEqual(properties["goal_count"] as? Int, 2)
        XCTAssertEqual(properties["goals"] as? String, "doomscrolling,loseFocus")
        XCTAssertEqual(properties["selected_age"] as? Int, 22)
        XCTAssertEqual(properties["screen_time_hours"] as? Double, 5.25)
        XCTAssertEqual(properties["screen_time_is_estimate"] as? Bool, false)
        XCTAssertEqual(properties["brain_age"] as? Int, 29)
        XCTAssertEqual(properties["brain_score"] as? Int, 612)
        XCTAssertEqual(properties["brain_age_delta"] as? Int, 7)
        XCTAssertEqual(properties["receipt_count"] as? Int, 3)
    }

    func testPaywallPurchasePropertiesIncludeConversionContext() {
        let properties = Analytics.paywallPurchaseProperties(
            productID: "com.memori.ultra.annual",
            plan: "annual",
            trigger: "onboarding",
            isHighIntent: true,
            isExitOffer: false,
            price: 39.99,
            errorReason: nil
        )

        XCTAssertEqual(properties["product_id"] as? String, "com.memori.ultra.annual")
        XCTAssertEqual(properties["plan"] as? String, "annual")
        XCTAssertEqual(properties["trigger"] as? String, "onboarding")
        XCTAssertEqual(properties["is_high_intent"] as? Bool, true)
        XCTAssertEqual(properties["is_exit_offer"] as? Bool, false)
        XCTAssertEqual(properties["$revenue"] as? Double, 39.99)
        XCTAssertNil(properties["error_reason"])
    }

    func testExitOfferPropertiesIncludeDiscountContext() {
        let properties = Analytics.paywallExitOfferProperties(
            trigger: "onboarding",
            selectedPlan: "annual",
            offerProductID: "com.memori.ultra.annual.firstyear",
            displayedPrice: 29.99,
            regularPrice: 39.99,
            discountLabel: "first_year_offer",
            displayedPriceText: "$29.99",
            regularPriceText: "$39.99"
        )

        XCTAssertEqual(properties["trigger"] as? String, "onboarding")
        XCTAssertEqual(properties["selected_plan"] as? String, "annual")
        XCTAssertEqual(properties["offer_product_id"] as? String, "com.memori.ultra.annual.firstyear")
        XCTAssertEqual(properties["displayed_price"] as? Double, 29.99)
        XCTAssertEqual(properties["regular_price"] as? Double, 39.99)
        XCTAssertEqual(properties["discount_label"] as? String, "first_year_offer")
        XCTAssertEqual(properties["displayed_price_text"] as? String, "$29.99")
        XCTAssertEqual(properties["regular_price_text"] as? String, "$39.99")
        XCTAssertEqual(properties["is_exit_offer"] as? Bool, true)
    }
}

final class OnboardingLifetimeProjectionTests: XCTestCase {
    func testLifetimeReceiptQuestionUsesFreeYearsAndPhoneYears() {
        let projection = OnboardingLifetimeProjection(age: 25, dailyScreenTimeHours: 4)

        XCTAssertEqual(projection.freeYearsBeforePhoneText, "24.8")
        XCTAssertEqual(projection.phoneYearsText, "9.2 years")
        XCTAssertEqual(
            projection.finalQuestion,
            "You have about 24.8 free years left. At this pace, your phone takes 9.2 years of them (37%). Do you really want that?"
        )
    }

    func testLifetimeReceiptQuestionUsesMeasuredWeeklyScreenTimeAverage() {
        let measuredWeeklyHours = 50.2
        let projection = OnboardingLifetimeProjection(age: 25, dailyScreenTimeHours: measuredWeeklyHours / 7)

        XCTAssertEqual(projection.freeYearsBeforePhoneText, "24.8")
        XCTAssertEqual(projection.phoneYearsText, "16.4 years")
        XCTAssertEqual(
            projection.finalQuestion,
            "You have about 24.8 free years left. At this pace, your phone takes 16.4 years of them (66%). Do you really want that?"
        )
    }

    func testLifeReceiptDoublesMemoProtectedPhoneYears() {
        let projection = OnboardingLifetimeProjection(age: 25, dailyScreenTimeHours: 50.2 / 7)
        let model = OnboardingLifeReceiptSquareModel(projection: projection)

        XCTAssertGreaterThanOrEqual(
            Double(model.protectedPhoneCount) / Double(model.phoneCount),
            0.50
        )
    }

    func testScreenTimeProjectionTreatsUserReportedWeeklyHoursAsRealData() {
        let userReported = OnboardingScreenTimeProjectionState(
            isAuthorized: true,
            useEstimate: false
        )

        XCTAssertFalse(userReported.isEstimate)
        XCTAssertTrue(userReported.canContinueFromScreenTime)
        XCTAssertEqual(userReported.receiptSourceLine, "Using your Screen Time")

        let confirmedEstimate = OnboardingScreenTimeProjectionState(
            isAuthorized: true,
            useEstimate: true
        )

        XCTAssertTrue(confirmedEstimate.isEstimate)
        XCTAssertTrue(confirmedEstimate.canContinueFromScreenTime)
        XCTAssertEqual(confirmedEstimate.receiptSourceLine, "Using your estimate")

        let unauthorized = OnboardingScreenTimeProjectionState(
            isAuthorized: false,
            useEstimate: false
        )

        XCTAssertFalse(unauthorized.canContinueFromScreenTime)
    }

    func testScreenTimeAccessCTAEnablesImmediatelyOnceAuthorized() {
        let cta = OnboardingScreenTimeAccessButtonState(
            isRequestingAccess: false,
            isAuthorized: true
        )

        XCTAssertEqual(cta.title, "Show my lifetime cost")
        XCTAssertFalse(cta.isDisabled)
    }

    func testScreenTimeAccessCTADisabledOnlyWhileSystemPromptIsPending() {
        let requesting = OnboardingScreenTimeAccessButtonState(
            isRequestingAccess: true,
            isAuthorized: false
        )

        XCTAssertEqual(requesting.title, "Checking Screen Time...")
        XCTAssertTrue(requesting.isDisabled)

        let unauthorized = OnboardingScreenTimeAccessButtonState(
            isRequestingAccess: false,
            isAuthorized: false
        )

        XCTAssertEqual(unauthorized.title, "Allow Screen Time")
        XCTAssertFalse(unauthorized.isDisabled)
    }

    func testUserReportedWeeklyHoursConvertToDailyAverageForLifetimeReceipt() {
        let reportedWeeklyHours = 52.0
        let projection = OnboardingLifetimeProjection(age: 25, dailyScreenTimeHours: reportedWeeklyHours / 7.0)

        XCTAssertEqual(projection.phoneYearsText, "17.0 years")
    }

    func testMeasuredWeeklyScreenTimeFormatsDailyAverageInHoursAndMinutes() {
        let measuredWeeklyHours = 50.2

        XCTAssertEqual(
            OnboardingScreenTimeHoursFormatter.dailyLabel(
                hours: measuredWeeklyHours / 7,
                isEstimate: false
            ),
            "7h 10m"
        )
    }

    func testLifetimeReceiptCanContinueOnlyAfterFinalLineFinishes() {
        XCTAssertFalse(OnboardingLifeReceiptProgress.canContinue(stage: 5, receiptFinished: false))
        XCTAssertFalse(OnboardingLifeReceiptProgress.canContinue(stage: 6, receiptFinished: false))
        XCTAssertFalse(OnboardingLifeReceiptProgress.canContinue(stage: OnboardingLifeReceiptBeat.phoneTruth.rawValue, receiptFinished: true))
        XCTAssertFalse(OnboardingLifeReceiptProgress.canContinue(stage: OnboardingLifeReceiptBeat.rescue.rawValue, receiptFinished: false))
        XCTAssertTrue(OnboardingLifeReceiptProgress.canContinue(stage: OnboardingLifeReceiptBeat.rescue.rawValue, receiptFinished: true))
    }

    func testLifeReceiptSquareModelKeepsCostsContiguousAndConserved() {
        let projection = OnboardingLifetimeProjection(age: 25, dailyScreenTimeHours: 50.2 / 7.0)
        let model = OnboardingLifeReceiptSquareModel(projection: projection)

        XCTAssertEqual(model.totalYearsCount, 80)
        XCTAssertEqual(model.yearsAheadCount, 55)
        XCTAssertEqual(
            model.livedCount + model.sleepCount + model.workSchoolCount + model.yourTimeAfterPhoneCount + model.phoneCount,
            model.totalYearsCount
        )
        XCTAssertEqual(model.yourTimeBeforePhoneCount, model.yourTimeAfterPhoneCount + model.phoneCount)

        let costRoles = model.finalCostRoles
        XCTAssertEqual(costRoles.count, 80)
        XCTAssertTrue(costRoles.isContiguous(.lived))
        XCTAssertTrue(costRoles.isContiguous(.sleep))
        XCTAssertTrue(costRoles.isContiguous(.workSchool))
        XCTAssertTrue(costRoles.isContiguous(.yourTime))
        XCTAssertTrue(costRoles.isContiguous(.phone))

        XCTAssertEqual(model.roles(for: .allLife).count, 80)
        XCTAssertTrue(model.roles(for: .yearsAhead).contains(.lived))
        XCTAssertTrue(model.roles(for: .yourTime).contains(.sleep))
        XCTAssertTrue(model.roles(for: .yourTime).contains(.workSchool))
        XCTAssertFalse(model.roles(for: .yourTime).contains(.phone))
        XCTAssertEqual(model.roles(for: .phoneTakeover).filter { $0 == .phone }.count, model.phoneCount)
        XCTAssertEqual(model.roles(for: .phoneTruth).filter { $0 == .phone }.count, model.phoneCount)
        XCTAssertEqual(model.roles(for: .rescue).count, 80)
        XCTAssertEqual(model.roles(for: .rescue).filter { $0 == .phone }.count, model.remainingPhoneCountAfterProtection)
        XCTAssertEqual(model.roles(for: .rescue).filter { $0 == .protectedPhone }.count, model.protectedPhoneCount)
    }

    func testLifeReceiptViewportShrinksToRemainingYearsAfterAge() {
        let projection = OnboardingLifetimeProjection(age: 20, dailyScreenTimeHours: 50.2 / 7.0)
        let model = OnboardingLifeReceiptSquareModel(projection: projection)

        XCTAssertEqual(model.viewportRoles(for: .allLife).count, 80)
        XCTAssertEqual(model.viewportRoles(for: .yearsAhead).count, 60)
        XCTAssertFalse(model.viewportRoles(for: .yearsAhead).contains(.lived))
        XCTAssertEqual(model.viewportRoles(for: .sleepLocked).count, 60)
        XCTAssertLessThan(model.viewportRoles(for: .workSchoolLocked).count, model.viewportRoles(for: .sleepLocked).count)
        XCTAssertEqual(model.viewportRoles(for: .yourTime).count, model.yourTimeBeforePhoneCount)
        XCTAssertEqual(model.viewportRoles(for: .phoneTakeover).count, model.yourTimeBeforePhoneCount)
        XCTAssertEqual(model.viewportRoles(for: .rescue).count, model.yourTimeBeforePhoneCount)
    }

    func testOnboardingMonetizationFlowPlacesTrialBridgeBeforeFinalPlanAndPaywall() {
        XCTAssertEqual(OnboardingFlowOrder.monetizationPages, [.trialTrustBridge, .planPersonalizing])
        XCTAssertEqual(OnboardingFlowOrder.page(afterScreenTimeAccess: true), .lifetimeShock)
        XCTAssertEqual(OnboardingFlowOrder.page(afterLifetimeShock: true), .lifeSquaresReceipt)
        XCTAssertEqual(OnboardingFlowOrder.page(afterLifeSquaresReceipt: true), .protectTarget)
        XCTAssertEqual(OnboardingFlowOrder.page(afterProtectTarget: true), .feedWinMoment)
        XCTAssertEqual(OnboardingFlowOrder.page(afterFeedWinMoment: true), .personalizationBeat)
        XCTAssertEqual(OnboardingFlowOrder.page(afterPersonalizationBeat: true), .memoPlan)
        XCTAssertEqual(OnboardingFlowOrder.page(afterMemoPlan: true), .trialTrustBridge)
        XCTAssertEqual(OnboardingFlowOrder.page(afterTrialTrustBridge: true), .planPersonalizing)
        XCTAssertEqual(OnboardingFlowOrder.page(afterPaywallConverted: true), .focusMode)
        XCTAssertEqual(Analytics.onboardingStepName(for: OnboardingPage.protectTarget.rawValue), "protectTarget")
        XCTAssertEqual(Analytics.onboardingStepName(for: OnboardingPage.feedWinMoment.rawValue), "feedWinMoment")
        XCTAssertEqual(Analytics.onboardingStepName(for: OnboardingPage.personalizationBeat.rawValue), "personalizationBeat")
        XCTAssertEqual(Analytics.onboardingStepName(for: OnboardingPage.lifetimeShock.rawValue), "lifetimeShock")
        XCTAssertEqual(Analytics.onboardingStepName(for: OnboardingPage.trialTrustBridge.rawValue), "trialTrustBridge")
        XCTAssertEqual(Analytics.onboardingStepName(for: OnboardingPage.trialReminderBridge.rawValue), "trialReminderBridge")
        XCTAssertEqual(Analytics.onboardingStepName(for: OnboardingPage.planPersonalizing.rawValue), "planPersonalizing")
    }
}

private extension Array where Element == OnboardingLifeReceiptSquareRole {
    func isContiguous(_ role: OnboardingLifeReceiptSquareRole) -> Bool {
        let matchingIndices = indices.filter { self[$0] == role }
        guard let first = matchingIndices.first, let last = matchingIndices.last else { return true }
        return matchingIndices == Swift.Array(first...last)
    }
}

final class FocusUnlockSlotTests: XCTestCase {
    func testFocusUnlockSlotCopyStaysShortAndNative() {
        XCTAssertEqual(FocusUnlockSlotCopy.eyebrow, "MEMO'S BOOTH")
        XCTAssertEqual(FocusUnlockSlotCopy.headline, "NO FEED TIL YOU TRAIN")
        // "win" is banned for the core loop (AGENTS.md) — play / finish / complete.
        XCTAssertEqual(FocusUnlockSlotCopy.subhead, "Play a brain game. Get your time back.")
        XCTAssertEqual(FocusUnlockSlotCopy.idleStatus, "spin when you're ready")
        XCTAssertEqual(FocusUnlockSlotCopy.spinningStatus, "MEMO'S PICKING")
        XCTAssertEqual(FocusUnlockSlotCopy.landedStatus(for: nil), "LOCKED IN")

        // Landed lines rotate from a per-tier pool but always lead with the
        // game name so the stake is unambiguous.
        let game = TrainingGameCatalog.focusUnlockGames.first!
        XCTAssertTrue(FocusUnlockSlotCopy.landedStatus(for: game).hasPrefix("NUMBER MEMORY. "))
    }

    func testFocusUnlockCatalogMatchesVisibleTrainGames() {
        let games = TrainingGameCatalog.focusUnlockGames

        XCTAssertEqual(games.map(\.type), [
            .sequentialMemory,
            .visualMemory,
            .chunkingTraining,
            .verbalMemory,
            .reactionTime,
            .mathSpeed,
            .speedMatch,
            .colorMatch,
            .dualNBack,
            .chimpTest,
        ])
        XCTAssertEqual(games.map(\.title), [
            "Number Memory",
            "Visual Memory",
            "Chunking",
            "Verbal Memory",
            "Reaction Time",
            "Math Speed",
            "Speed Match",
            "Color Match",
            "Dual N-Back",
            "Chimp Test",
        ])
    }

    func testFocusUnlockCompletionGateOnlyGrantsForSelectedGame() {
        XCTAssertTrue(
            FocusUnlockCompletionGate.shouldGrant(
                completedGameRawValue: ExerciseType.colorMatch.rawValue,
                expectedGame: .colorMatch
            )
        )

        XCTAssertFalse(
            FocusUnlockCompletionGate.shouldGrant(
                completedGameRawValue: ExerciseType.reactionTime.rawValue,
                expectedGame: .colorMatch
            )
        )

        XCTAssertFalse(
            FocusUnlockCompletionGate.shouldGrant(
                completedGameRawValue: ExerciseType.colorMatch.rawValue,
                expectedGame: nil
            )
        )

        XCTAssertFalse(
            FocusUnlockCompletionGate.shouldGrant(
                completedGameRawValue: "not-a-game",
                expectedGame: .colorMatch
            )
        )
    }
}

final class FocusUnlockPayoutTests: XCTestCase {
    func testPayoutMinutesMatchTierPerGame() {
        XCTAssertEqual(FocusUnlockPayout.minutes(for: .dualNBack), 20)
        XCTAssertEqual(FocusUnlockPayout.minutes(for: .chimpTest), 20)
        XCTAssertEqual(FocusUnlockPayout.minutes(for: .sequentialMemory), 10)
        XCTAssertEqual(FocusUnlockPayout.minutes(for: .visualMemory), 10)
        XCTAssertEqual(FocusUnlockPayout.minutes(for: .chunkingTraining), 10)
        XCTAssertEqual(FocusUnlockPayout.minutes(for: .verbalMemory), 10)
        XCTAssertEqual(FocusUnlockPayout.minutes(for: .reactionTime), 5)
        XCTAssertEqual(FocusUnlockPayout.minutes(for: .mathSpeed), 5)
        XCTAssertEqual(FocusUnlockPayout.minutes(for: .speedMatch), 5)
        XCTAssertEqual(FocusUnlockPayout.minutes(for: .colorMatch), 5)
    }

    func testWeightedSpinSelectsTierByRoll() {
        let games = TrainingGameCatalog.focusUnlockGames

        let quick = FocusUnlockPayout.weightedRandomGame(from: games, roll: 0.10)
        XCTAssertEqual(quick.map { FocusUnlockPayout.tier(for: $0.type) }, .quick)

        let solid = FocusUnlockPayout.weightedRandomGame(from: games, roll: 0.75)
        XCTAssertEqual(solid.map { FocusUnlockPayout.tier(for: $0.type) }, .solid)

        let jackpot = FocusUnlockPayout.weightedRandomGame(from: games, roll: 0.95)
        XCTAssertEqual(jackpot.map { FocusUnlockPayout.tier(for: $0.type) }, .jackpot)
    }

    func testWeightedSpinFallsBackWhenTierPoolIsEmpty() {
        let onlyQuickGames = TrainingGameCatalog.speedGames
        let landed = FocusUnlockPayout.weightedRandomGame(from: onlyQuickGames, roll: 0.95)
        XCTAssertNotNil(landed)
        XCTAssertEqual(landed.map { FocusUnlockPayout.tier(for: $0.type) }, .quick)
    }

    func testWeightedSpinEmptyPoolReturnsNil() {
        XCTAssertNil(FocusUnlockPayout.weightedRandomGame(from: [], roll: 0.5))
    }
}

@MainActor
final class VisualMemoryGridGrowthTests: XCTestCase {
    /// The grid keeps growing so long runs never plateau on a 5x5 board.
    func testGridGrowsWithLevel() {
        let viewModel = VisualMemoryViewModel()
        let expected: [(level: Int, grid: Int)] = [(1, 4), (3, 4), (4, 5), (7, 5), (8, 6), (12, 6), (13, 7), (20, 7)]
        for (level, grid) in expected {
            viewModel.level = level
            viewModel.startLevel()
            XCTAssertEqual(viewModel.gridSize, grid, "level \(level)")
            XCTAssertEqual(viewModel.highlightedCells.count, min(2 + level, grid * grid - 1), "level \(level)")
        }
        viewModel.reset()
    }
}
