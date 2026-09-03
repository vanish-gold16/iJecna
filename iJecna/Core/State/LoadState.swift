import Foundation

/// Stav načítání jedné obrazovky.
///
/// `loaded` si drží i příznak `isRefreshing`, aby šlo při pull-to-refresh
/// nechat na obrazovce stará data a jen naznačit, že se obnovují.
enum LoadState<Value: Sendable>: Sendable {
    case idle
    case loading
    case loaded(Value, isRefreshing: Bool = false)
    case failed(JecnaError)

    var value: Value? {
        if case .loaded(let value, _) = self { return value }
        return nil
    }

    var error: JecnaError? {
        if case .failed(let error) = self { return error }
        return nil
    }

    var isLoading: Bool {
        switch self {
        case .loading: true
        case .loaded(_, let isRefreshing): isRefreshing
        default: false
        }
    }

    /// Zobrazit velký skeleton (na rozdíl od tichého obnovování).
    var isInitialLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    var isIdle: Bool {
        if case .idle = self { return true }
        return false
    }

    mutating func markRefreshing() {
        if case .loaded(let value, _) = self {
            self = .loaded(value, isRefreshing: true)
        } else if case .idle = self {
            self = .loading
        }
    }
}
