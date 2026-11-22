import Foundation

// FSRS-6 scheduler (design plan §4.6): a Swift port of the open-source reference implementation,
// py-fsrs 6.x (MIT, github.com/open-spaced-repetition/py-fsrs). Formulas, state machine, clamps,
// rounding and fuzz ranges follow `fsrs/scheduler.py`; unit tests compare against values computed by it.
//
// Card state is never stored: `FSRS.replay` folds the merged, time-sorted review logs.

struct FSRSParameters: Hashable, Sendable {
    /// FSRS-6 default parameters (21 weights).
    static let defaultWeights: [Double] = [
        0.212, 1.2931, 2.3065, 8.2956, 6.4133, 0.8334, 3.0194, 0.001, 1.8722, 0.1666, 0.796,
        1.4835, 0.0614, 0.2629, 1.6483, 0.6014, 1.8729, 0.5425, 0.0912, 0.0658, 0.1542,
    ]
    static let stabilityMin = 0.001

    var w: [Double]
    var desiredRetention: Double
    var learningSteps: [TimeInterval]
    var relearningSteps: [TimeInterval]
    var maximumInterval: Int
    var enableFuzz: Bool

    /// - Parameter weights: 21 (FSRS-6), 19 (FSRS-5) or 17 (FSRS-4.5) weights, e.g. from an imported Anki preset.
    ///   Older sets are extended so FSRS-6 reproduces them (w19 = 0, w20 = 0.5 gives the old fixed decay).
    init(weights: [Double]? = nil, desiredRetention: Double = 0.9,
         learningSteps: [TimeInterval] = [600], relearningSteps: [TimeInterval] = [600],
         maximumInterval: Int = 36500, enableFuzz: Bool = true) {
        self.w = FSRSParameters.normalise(weights)
        self.desiredRetention = min(max(desiredRetention, 0.7), 0.99)
        self.learningSteps = learningSteps
        self.relearningSteps = relearningSteps
        self.maximumInterval = maximumInterval
        self.enableFuzz = enableFuzz
    }

    static func normalise(_ weights: [Double]?) -> [Double] {
        guard let weights, weights.allSatisfy({ $0.isFinite }) else { return defaultWeights }
        switch weights.count {
        case 21: return weights
        case 19: return weights + [0.0, 0.5]
        case 17: return weights + [0.0, 0.0, 0.0, 0.5]
        default: return defaultWeights
        }
    }

    var decay: Double { -w[20] }
    var factor: Double { pow(0.9, 1 / decay) - 1 }
}

enum CardPhase: String, Codable, Hashable, Sendable {
    case new, learning, review, relearning
}

/// A card's scheduling state, derived from its review history.
struct CardSchedule: Hashable, Sendable {
    var phase: CardPhase = .new
    /// Index into the (re)learning steps while learning or relearning.
    var step: Int = 0
    var stability: Double?
    var difficulty: Double?
    var due: Date?
    var lastReview: Date?
    /// Last scheduled interval in whole days (0 while in a learning step).
    var intervalDays: Int = 0
    var reps: Int = 0
    var lapses: Int = 0
    var firstReview: Date?
    var totalMs: Int = 0

    static let new = CardSchedule()

    var isNew: Bool { phase == .new }
    var isLearning: Bool { phase == .learning || phase == .relearning }
    /// Mature = interval of 21 days or more (Anki's definition).
    var isMature: Bool { phase == .review && intervalDays >= 21 }
}

struct FSRS: Sendable {
    var p: FSRSParameters

    init(_ parameters: FSRSParameters = FSRSParameters()) {
        p = parameters
    }

    // MARK: Formulas

    /// Probability of recall after `elapsedDays` for a memory of stability `stability`.
    func retrievability(elapsedDays: Double, stability: Double) -> Double {
        pow(1 + p.factor * max(elapsedDays, 0) / stability, p.decay)
    }

    /// As py-fsrs: whole days elapsed since the last review.
    func retrievability(of card: CardSchedule, at now: Date) -> Double {
        guard let s = card.stability, let last = card.lastReview else { return 0 }
        return retrievability(elapsedDays: Double(FSRS.wholeDays(from: last, to: now)), stability: s)
    }

    /// Same, with fractional days: used to order the queue and for exam-day predictions.
    func exactRetrievability(of card: CardSchedule, at now: Date) -> Double {
        guard let s = card.stability, let last = card.lastReview else { return 0 }
        return retrievability(elapsedDays: now.timeIntervalSince(last) / 86_400, stability: s)
    }

    func nextInterval(stability: Double) -> Int {
        let raw = stability / p.factor * (pow(p.desiredRetention, 1 / p.decay) - 1)
        let days = Int(raw.rounded(.toNearestOrEven))
        return min(max(days, 1), p.maximumInterval)
    }

    func initialStability(_ rating: Rating) -> Double {
        max(p.w[rating.rawValue - 1], FSRSParameters.stabilityMin)
    }

    func initialDifficulty(_ rating: Rating, clamp: Bool = true) -> Double {
        let d = p.w[4] - exp(p.w[5] * Double(rating.rawValue - 1)) + 1
        return clamp ? FSRS.clampDifficulty(d) : d
    }

    func nextDifficulty(_ d: Double, _ rating: Rating) -> Double {
        let delta = -(p.w[6] * Double(rating.rawValue - 3))
        let damped = d + (10 - d) * delta / 9
        let reverted = p.w[7] * initialDifficulty(.easy, clamp: false) + (1 - p.w[7]) * damped
        return FSRS.clampDifficulty(reverted)
    }

    func shortTermStability(_ s: Double, _ rating: Rating) -> Double {
        var increase = exp(p.w[17] * (Double(rating.rawValue) - 3 + p.w[18])) * pow(s, -p.w[19])
        if rating != .again { increase = max(increase, 1) }
        return max(s * increase, FSRSParameters.stabilityMin)
    }

    func nextStability(d: Double, s: Double, r: Double, rating: Rating) -> Double {
        let next: Double
        if rating == .again {
            let longTerm = p.w[11] * pow(d, -p.w[12]) * (pow(s + 1, p.w[13]) - 1) * exp((1 - r) * p.w[14])
            let shortTerm = s / exp(p.w[17] * p.w[18])
            next = min(longTerm, shortTerm)
        } else {
            let hardPenalty = rating == .hard ? p.w[15] : 1
            let easyBonus = rating == .easy ? p.w[16] : 1
            next = s * (1 + exp(p.w[8]) * (11 - d) * pow(s, -p.w[9]) * (exp((1 - r) * p.w[10]) - 1) * hardPenalty * easyBonus)
        }
        return max(next, FSRSParameters.stabilityMin)
    }

    static func clampDifficulty(_ d: Double) -> Double { min(max(d, 1), 10) }

    static func wholeDays(from: Date, to: Date) -> Int {
        Int((to.timeIntervalSince(from) / 86_400).rounded(.down))
    }

    // MARK: Reviewing

    /// The state after grading `card` with `rating` at `now`. `fuzz` is a number in [0, 1) used to
    /// spread review intervals (deterministic per review, so replays are reproducible).
    func review(_ card: CardSchedule, rating: Rating, at now: Date, fuzz: Double? = nil) -> CardSchedule {
        var c = card
        let elapsed: Int? = card.lastReview.map { FSRS.wholeDays(from: $0, to: now) }

        // 1. Memory state
        if card.phase == .new || c.stability == nil || c.difficulty == nil {
            c.stability = initialStability(rating)
            c.difficulty = initialDifficulty(rating)
            c.phase = .learning
            c.step = 0
        } else if let s = c.stability, let d = c.difficulty {
            if let elapsed, elapsed < 1 {
                c.stability = shortTermStability(s, rating)
            } else {
                c.stability = nextStability(d: d, s: s, r: retrievability(of: card, at: now), rating: rating)
            }
            c.difficulty = nextDifficulty(d, rating)
        }
        let s = c.stability ?? FSRSParameters.stabilityMin

        // 2. Next interval
        var stepInterval: TimeInterval?
        var reviewDays: Int?
        switch c.phase {
        case .new, .learning, .relearning:
            let steps = c.phase == .relearning ? p.relearningSteps : p.learningSteps
            if steps.isEmpty || (c.step >= steps.count && rating != .again) {
                reviewDays = nextInterval(stability: s)
            } else {
                switch rating {
                case .again:
                    c.step = 0
                    stepInterval = steps[0]
                case .hard:
                    if c.step == 0 && steps.count == 1 {
                        stepInterval = steps[0] * 1.5
                    } else if c.step == 0 {
                        stepInterval = (steps[0] + steps[1]) / 2
                    } else {
                        stepInterval = steps[min(c.step, steps.count - 1)]
                    }
                case .good:
                    if c.step + 1 >= steps.count {
                        reviewDays = nextInterval(stability: s)
                    } else {
                        c.step += 1
                        stepInterval = steps[c.step]
                    }
                case .easy:
                    reviewDays = nextInterval(stability: s)
                }
            }
        case .review:
            if rating == .again {
                c.lapses += 1
                if p.relearningSteps.isEmpty {
                    reviewDays = nextInterval(stability: s)
                } else {
                    c.phase = .relearning
                    c.step = 0
                    stepInterval = p.relearningSteps[0]
                }
            } else {
                reviewDays = nextInterval(stability: s)
            }
        }

        if var days = reviewDays {
            if p.enableFuzz, let fuzz { days = fuzzed(days, random: fuzz) }
            c.phase = .review
            c.step = 0
            c.intervalDays = days
            c.due = now.addingTimeInterval(Double(days) * 86_400)
        } else {
            c.intervalDays = 0
            c.due = now.addingTimeInterval(stepInterval ?? 600)
        }
        c.lastReview = now
        c.reps += 1
        if c.firstReview == nil { c.firstReview = now }
        return c
    }

    /// All four outcomes, as shown on the grade buttons. Review intervals are kept in order
    /// (Hard ≤ Good < Easy) like Anki, so the buttons never contradict each other.
    func outcomes(for card: CardSchedule, at now: Date, fuzz: Double? = nil) -> [Rating: CardSchedule] {
        var result: [Rating: CardSchedule] = [:]
        for rating in Rating.allCases {
            result[rating] = review(card, rating: rating, at: now, fuzz: fuzz)
        }
        if card.phase == .review, var hard = result[.hard], var good = result[.good], var easy = result[.easy],
           hard.phase == .review, good.phase == .review, easy.phase == .review {
            hard.intervalDays = min(hard.intervalDays, good.intervalDays)
            good.intervalDays = max(good.intervalDays, hard.intervalDays + 1)
            easy.intervalDays = max(easy.intervalDays, good.intervalDays + 1)
            let adjusted: [(Rating, CardSchedule)] = [(.hard, hard), (.good, good), (.easy, easy)]
            for (rating, outcome) in adjusted {
                var o = outcome
                o.intervalDays = min(o.intervalDays, p.maximumInterval)
                o.due = now.addingTimeInterval(Double(o.intervalDays) * 86_400)
                result[rating] = o
            }
        }
        return result
    }

    /// The state after a grade, consistent with what `outcomes` showed on the buttons. Used by replay.
    func schedule(_ card: CardSchedule, rating: Rating, at now: Date, fuzz: Double? = nil) -> CardSchedule {
        guard card.phase == .review else { return review(card, rating: rating, at: now, fuzz: fuzz) }
        return outcomes(for: card, at: now, fuzz: fuzz)[rating] ?? review(card, rating: rating, at: now, fuzz: fuzz)
    }

    /// py-fsrs fuzz: spreads an interval of ≥ 3 days over a range that grows with the interval.
    func fuzzed(_ days: Int, random: Double) -> Int {
        guard Double(days) >= 2.5 else { return days }
        let ranges: [(start: Double, end: Double, factor: Double)] = [(2.5, 7, 0.15), (7, 20, 0.1), (20, .infinity, 0.05)]
        var delta = 1.0
        for r in ranges {
            delta += r.factor * max(min(Double(days), r.end) - r.start, 0)
        }
        var minIvl = Int((Double(days) - delta).rounded(.toNearestOrEven))
        var maxIvl = Int((Double(days) + delta).rounded(.toNearestOrEven))
        minIvl = max(2, minIvl)
        maxIvl = min(maxIvl, p.maximumInterval)
        minIvl = min(minIvl, maxIvl)
        let value = random * Double(maxIvl - minIvl + 1) + Double(minIvl)
        return min(Int(value.rounded(.down)), p.maximumInterval)
    }

    /// A stable number in [0, 1) from a review id, so the same log always replays to the same schedule.
    static func fuzzValue(for id: UUID) -> Double {
        let b = id.uuid
        let bytes = [b.0, b.1, b.2, b.3, b.4, b.5, b.6, b.7, b.8, b.9, b.10, b.11, b.12, b.13, b.14, b.15]
        var x: UInt64 = 0xcbf2_9ce4_8422_2325           // FNV-1a
        for byte in bytes {
            x ^= UInt64(byte)
            x = x &* 0x0000_0100_0000_01b3
        }
        return Double(x >> 11) / Double(UInt64(1) << 53)
    }

    // MARK: Replay

    /// The lines that count, in replay order: de-duplicated by id, without `undo` lines or the lines they cancel.
    static func effective(_ entries: [ReviewEntry]) -> [ReviewEntry] {
        let undone = Set(entries.compactMap { $0.kind == .undo ? $0.undoes : nil })
        var seen = Set<UUID>()
        return entries
            .filter { $0.kind != .undo && !undone.contains($0.id) && seen.insert($0.id).inserted }
            .sorted { $0.t != $1.t ? $0.t < $1.t : $0.id.uuidString < $1.id.uuidString }
    }

    /// Folds review logs into card states. Entries may come from several files in any order:
    /// they are de-duplicated by id, `undo` lines cancel their target, and cram lines are ignored.
    /// - Parameters:
    ///   - parameters: per-card parameters (e.g. a deck's imported FSRS weights); default `p`.
    ///   - onReview: called for every graded review with the state before and after (stats use it).
    func replay(_ entries: [ReviewEntry], parameters: ((UUID) -> FSRSParameters?)? = nil,
                onReview: ((ReviewEntry, CardSchedule, CardSchedule) -> Void)? = nil) -> [UUID: CardSchedule] {
        var states: [UUID: CardSchedule] = [:]
        var schedulers: [UUID: FSRS] = [:]
        for entry in FSRS.effective(entries) where entry.kind != .cram {
            let before = states[entry.card] ?? .new
            var state = before
            if let rating = entry.rating {
                let scheduler: FSRS
                if let cached = schedulers[entry.card] {
                    scheduler = cached
                } else {
                    scheduler = parameters?(entry.card).map { FSRS($0) } ?? self
                    schedulers[entry.card] = scheduler
                }
                state = scheduler.schedule(state, rating: rating, at: entry.t, fuzz: FSRS.fuzzValue(for: entry.id))
                state.totalMs += max(entry.ms, 0)
                onReview?(entry, before, state)
            } else if entry.kind == .manual || entry.kind == .reschedule {
                let days = entry.anki?.intervalDays ?? 0
                if entry.kind == .manual && days == 0 {
                    state = .new                                      // Anki "Forget"
                } else if days > 0 && !state.isNew {
                    state.due = entry.t.addingTimeInterval(Double(days) * 86_400)
                    state.intervalDays = days
                }
            }
            states[entry.card] = state
        }
        return states
    }
}
