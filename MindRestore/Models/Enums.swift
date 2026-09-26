import Foundation

// MARK: - Subscription Status

enum SubscriptionStatus: String, Codable {
    case free, trial, subscribed
}

// MARK: - Exercise Type

enum ExerciseType: String, Codable, CaseIterable, Identifiable {
    case spacedRepetition, dualNBack, activeRecall, chunkingTraining, prospectiveMemory
    case memoryPalace, reactionTime, sequentialMemory, mathSpeed, speedMatch, visualMemory, colorMatch
    case wordScramble
    case memoryChain
    case chimpTest
    case verbalMemory
    var id: String { rawValue }

    /// The six games still offered anywhere in the app (Train tab, slot, leaderboards).
    static let activeGames: [ExerciseType] = [.visualMemory, .sequentialMemory, .chimpTest, .mathSpeed, .colorMatch, .reactionTime]
    /// Retired games stay decodable for history but are never offered.
    var isRetired: Bool { !Self.activeGames.contains(self) }

    var displayName: String {
        switch self {
        case .spacedRepetition: return "Spaced Repetition"
        case .dualNBack: return "Dual N-Back"
        case .activeRecall: return "Active Recall"
        case .chunkingTraining: return "Chunking Training"
        case .prospectiveMemory: return "Prospective Memory"
        case .memoryPalace: return "Memory Palace"
        case .reactionTime: return "Reaction Time"
        case .sequentialMemory: return "Number Memory"
        case .mathSpeed: return "Math Sprint"
        case .speedMatch: return "Speed Match"
        case .visualMemory: return "Visual Memory"
        case .colorMatch: return "Color Match"
        case .wordScramble: return "Word Scramble"
        case .memoryChain: return "Memory Chain"
        case .chimpTest: return "Chimp Test"
        case .verbalMemory: return "Verbal Memory"
        }
    }

    var icon: String {
        switch self {
        case .spacedRepetition: return "rectangle.on.rectangle.angled"
        case .dualNBack: return "square.grid.3x3"
        case .activeRecall: return "brain.head.profile"
        case .chunkingTraining: return "square.grid.4x3.fill"
        case .prospectiveMemory: return "clock.badge.checkmark"
        case .memoryPalace: return "building.columns.fill"
        case .reactionTime: return "bolt.fill"
        case .sequentialMemory: return "number.circle.fill"
        case .mathSpeed: return "multiply.circle.fill"
        case .speedMatch: return "bolt.square.fill"
        case .visualMemory: return "square.grid.3x3.fill"
        case .colorMatch: return "paintpalette.fill"
        case .wordScramble: return "textformat.abc.dottedunderline"
        case .memoryChain: return "link.circle.fill"
        case .chimpTest: return "pawprint.fill"
        case .verbalMemory: return "text.book.closed.fill"
        }
    }

    var description: String {
        switch self {
        case .spacedRepetition: return "Adaptive flashcard system"
        case .dualNBack: return "Working memory training"
        case .activeRecall: return "Real-world memory challenges"
        case .chunkingTraining: return "Multiply memory capacity with chunking"
        case .prospectiveMemory: return "Remember to do things in the future"
        case .memoryPalace: return "Method of loci spatial memory"
        case .reactionTime: return "Test and improve processing speed"
        case .sequentialMemory: return "Remember digits shown one at a time"
        case .mathSpeed: return "Solve multiplication problems fast"
        case .speedMatch: return "Match symbols as fast as you can"
        case .visualMemory: return "Remember the pattern of highlighted tiles"
        case .colorMatch: return "Stroop effect color-word challenge"
        case .wordScramble: return "Unscramble words against the clock"
        case .memoryChain: return "Remember growing sequences of items"
        case .chimpTest: return "Remember number positions like a chimp"
        case .verbalMemory: return "Have you seen this word before?"
        }
    }

}

// MARK: - Card Category

enum CardCategory: String, Codable, CaseIterable, Identifiable {
    case numbers, words, sequences, faces, locations
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .numbers: return "Number Sequences"
        case .words: return "Word Lists"
        case .sequences: return "Daily Scenarios"
        case .faces: return "Face-Name Pairs"
        case .locations: return "Location Sequences"
        }
    }

    var icon: String {
        switch self {
        case .numbers: return "number"
        case .words: return "textformat.abc"
        case .sequences: return "person.2"
        case .faces: return "face.smiling"
        case .locations: return "map"
        }
    }

    var isPro: Bool {
        self != .numbers
    }
}

// MARK: - Education Category

enum EduCategory: String, Codable, CaseIterable, Identifiable {
    case socialMedia, cannabis, sleep, neuroplasticity, techniques
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .socialMedia: return "Social Media"
        case .cannabis: return "Cannabis"
        case .sleep: return "Sleep"
        case .neuroplasticity: return "Neuroplasticity"
        case .techniques: return "Techniques"
        }
    }

    var icon: String {
        switch self {
        case .socialMedia: return "iphone"
        case .cannabis: return "leaf"
        case .sleep: return "moon.zzz"
        case .neuroplasticity: return "brain"
        case .techniques: return "lightbulb"
        }
    }
}

// MARK: - Challenge Type

enum ChallengeType: String, Codable, CaseIterable, Identifiable {
    case storyRecall, instructionRecall, patternRecognition, conversationRecall
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .storyRecall: return "Story Recall"
        case .instructionRecall: return "Instruction Recall"
        case .patternRecognition: return "Pattern Recognition"
        case .conversationRecall: return "Conversation Recall"
        }
    }
}

// MARK: - User Focus Goal

enum UserFocusGoal: String, Codable, CaseIterable, Identifiable {
    case screenTimeFrying = "screentime"
    case doomscrolling = "doomscroll"
    case attentionShot = "attention"
    case loseFocus = "focus"
    case forgetInstantly = "forget"
    case getSharper = "sharper"
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .screenTimeFrying: return "My screen time is out of control"
        case .doomscrolling: return "I doomscroll way too much"
        case .attentionShot: return "I can't focus like I used to"
        case .loseFocus: return "I lose my train of thought easily"
        case .forgetInstantly: return "I forget things too quickly"
        case .getSharper: return "I want to stay mentally sharp"
        }
    }

    var icon: String {
        switch self {
        case .screenTimeFrying: return "iphone"
        case .doomscrolling: return "infinity"
        case .attentionShot: return "scope"
        case .loseFocus: return "cloud.fill"
        case .forgetInstantly: return "questionmark"
        case .getSharper: return "bolt.fill"
        }
    }

    var emoji: String {
        switch self {
        case .screenTimeFrying: return "📱"
        case .doomscrolling: return "🫠"
        case .attentionShot: return "🧠"
        case .loseFocus: return "💭"
        case .forgetInstantly: return "💨"
        case .getSharper: return "⚡️"
        }
    }
}

// MARK: - Self Rating

enum SelfRating: Int, CaseIterable {
    case again = 0, hard = 1, good = 2, easy = 3

    var displayName: String {
        switch self {
        case .again: return "Again"
        case .hard: return "Hard"
        case .good: return "Good"
        case .easy: return "Easy"
        }
    }
}

// MARK: - User Level

enum UserLevel {
    static let maxLevel = 50

    static func name(for level: Int) -> String {
        switch level {
        case 1: return "Beginner Brain"
        case 2: return "Curious Mind"
        case 3: return "Quick Thinker"
        case 4: return "Memory Apprentice"
        case 5: return "Focus Fighter"
        case 6: return "Pattern Spotter"
        case 7: return "Recall Rookie"
        case 8: return "Brain Builder"
        case 9: return "Mind Sharpener"
        case 10: return "Cognitive Climber"
        case 11: return "Neural Navigator"
        case 12: return "Synapse Surfer"
        case 13: return "Memory Machine"
        case 14: return "Brain Storm"
        case 15: return "Mind Master"
        case 16: return "Cortex Commander"
        case 17: return "Neuron King"
        case 18: return "Memory Titan"
        case 19: return "Cognitive Legend"
        case 20: return "Brain God"
        case 21: return "Ascended Mind"
        case 22: return "Thought Weaver"
        case 23: return "Dendrite Dragon"
        case 24: return "Hippocampus Hero"
        case 25: return "Prefrontal Prime"
        case 26: return "Dopamine Dealer"
        case 27: return "Amygdala Ace"
        case 28: return "Cerebral Sage"
        case 29: return "Neuron Nova"
        case 30: return "Infinite Recall"
        case 31: return "Temporal Titan"
        case 32: return "Brainwave Boss"
        case 33: return "Cortex Crusher"
        case 34: return "Apex Thinker"
        case 35: return "Omega Brain"
        case 36: return "Quantum Mind"
        case 37: return "Neural Architect"
        case 38: return "Cognitive Deity"
        case 39: return "Synapse Sovereign"
        case 40: return "Transcendent Mind"
        case 41: return "Galactic Brain"
        case 42: return "Reality Bender"
        case 43: return "Time Lord Brain"
        case 44: return "Multiverse Mind"
        case 45: return "Cosmic Thinker"
        case 46: return "Eternal Neuron"
        case 47: return "Dimension Breaker"
        case 48: return "Singularity"
        case 49: return "Beyond Cognition"
        case 50: return "The Architect"
        default: return level > 50 ? "The Architect" : "Beginner Brain"
        }
    }

    static func xpRequired(for level: Int) -> Int {
        guard level > 1 else { return 0 }
        // Exponential curve: each level takes ~40% more XP
        return Int(200 * pow(1.4, Double(level - 2)))
    }

    static func level(for xp: Int) -> Int {
        var lvl = 1
        while lvl < maxLevel && xp >= xpRequired(for: lvl + 1) {
            lvl += 1
        }
        return lvl
    }
}
