import Foundation

/// A starting list of Part IB courses for the "Add courses" sheet. Everything is editable.
struct CourseTemplate: Hashable, Identifiable, Sendable {
    var id: String { name }
    var name: String
    var term: TermName
    var lectures: Int?

    static let partIB: [CourseTemplate] = [
        CourseTemplate(name: "Linear Algebra", term: .michaelmas, lectures: 24),
        CourseTemplate(name: "Analysis and Topology", term: .michaelmas, lectures: 24),
        CourseTemplate(name: "Methods", term: .michaelmas, lectures: 24),
        CourseTemplate(name: "Quantum Mechanics", term: .michaelmas, lectures: 16),
        CourseTemplate(name: "Markov Chains", term: .michaelmas, lectures: 12),
        CourseTemplate(name: "Groups, Rings and Modules", term: .lent, lectures: 24),
        CourseTemplate(name: "Complex Analysis", term: .lent, lectures: 16),
        CourseTemplate(name: "Complex Methods", term: .lent, lectures: 16),
        CourseTemplate(name: "Geometry", term: .lent, lectures: 16),
        CourseTemplate(name: "Electromagnetism", term: .lent, lectures: 16),
        CourseTemplate(name: "Numerical Analysis", term: .lent, lectures: 16),
        CourseTemplate(name: "Statistics", term: .lent, lectures: 16),
        CourseTemplate(name: "Fluid Dynamics", term: .lent, lectures: 16),
        CourseTemplate(name: "Optimisation", term: .easter, lectures: 12),
        CourseTemplate(name: "Variational Principles", term: .easter, lectures: 12),
    ]
}
