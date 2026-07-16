//
//  ContextualGlossProviding.swift
//  shizen
//
//  Backend-agnostic contract for "explain this token in this sentence" gloss providers,
//  so WordDictionaryDetailView can swap between on-device-only and cloud-backed fallback behavior.
//

import Foundation

struct ContextualGlossRequest: Equatable {
    let sentence: String
    let surface: String
    let dictionaryForm: String?
    let dictionaryGloss: String?
}

struct ContextualGlossResult: Equatable {
    let meaning: String
    let grammarNote: String
}

protocol ContextualGlossProviding {
    var isAvailable: Bool { get }
    func cachedResult(for request: ContextualGlossRequest) async -> ContextualGlossResult?
    func explain(_ request: ContextualGlossRequest) async throws -> ContextualGlossResult
}

/// Today's default behavior: on-device only, hides the contextual card when Apple Intelligence
/// is unavailable rather than falling back to a cloud call.
struct OnDeviceOnlyContextualGlossProvider: ContextualGlossProviding {
    var isAvailable: Bool {
        FoundationModelContextualGloss.isAvailable
    }

    func cachedResult(for request: ContextualGlossRequest) async -> ContextualGlossResult? {
        guard let cached = await FoundationModelContextualGloss.cachedResult(for: request.asFoundationModelRequest) else {
            return nil
        }
        return cached.asContextualGlossResult
    }

    func explain(_ request: ContextualGlossRequest) async throws -> ContextualGlossResult {
        try await FoundationModelContextualGloss.explain(request.asFoundationModelRequest).asContextualGlossResult
    }
}

/// Cloud-only: always asks Gemini, never touches the on-device model.
struct GeminiOnlyContextualGlossProvider: ContextualGlossProviding {
    var isAvailable: Bool {
        GeminiContextualGloss.isConfigured
    }

    func cachedResult(for request: ContextualGlossRequest) async -> ContextualGlossResult? {
        await GeminiContextualGloss.cachedResult(for: request.asGeminiRequest)?.asContextualGlossResult
    }

    func explain(_ request: ContextualGlossRequest) async throws -> ContextualGlossResult {
        try await GeminiContextualGloss.explain(request.asGeminiRequest).asContextualGlossResult
    }
}

/// Tries the on-device model first (private, no network) and falls back to Gemini when
/// Apple Intelligence is unavailable or the on-device call fails — used by the sentence-scrub
/// experiment, which wants contextual insights to work even on devices without Apple Intelligence.
struct HybridContextualGlossProvider: ContextualGlossProviding {
    var isAvailable: Bool {
        FoundationModelContextualGloss.isAvailable || GeminiContextualGloss.isConfigured
    }

    func cachedResult(for request: ContextualGlossRequest) async -> ContextualGlossResult? {
        if FoundationModelContextualGloss.isAvailable,
           let cached = await FoundationModelContextualGloss.cachedResult(for: request.asFoundationModelRequest) {
            return cached.asContextualGlossResult
        }
        if let cached = await GeminiContextualGloss.cachedResult(for: request.asGeminiRequest) {
            return cached.asContextualGlossResult
        }
        return nil
    }

    func explain(_ request: ContextualGlossRequest) async throws -> ContextualGlossResult {
        if FoundationModelContextualGloss.isAvailable {
            do {
                return try await FoundationModelContextualGloss.explain(request.asFoundationModelRequest).asContextualGlossResult
            } catch {
                print("[HybridContextualGlossProvider] on-device gloss failed (\(error)); falling back to Gemini")
            }
        }
        return try await GeminiContextualGloss.explain(request.asGeminiRequest).asContextualGlossResult
    }
}

// MARK: - Backend preference

enum ContextualGlossBackend: String, CaseIterable {
    case onDevice
    case gemini
    case hybrid

    private static let defaultsKey = "ContextualGlossBackend"

    /// Persisted app-wide contextual gloss backend. Defaults to **hybrid** (on-device first, Gemini fallback).
    static var preferred: ContextualGlossBackend {
        get {
            guard let raw = UserDefaults.standard.string(forKey: defaultsKey),
                  let backend = ContextualGlossBackend(rawValue: raw) else { return .hybrid }
            return backend
        }
        set {
            guard preferred != newValue else { return }
            UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey)
            NotificationCenter.default.post(name: .contextualGlossBackendDidChange, object: nil)
        }
    }

    var displayName: String {
        switch self {
        case .onDevice: return "On-device only"
        case .gemini: return "Gemini only"
        case .hybrid: return "Hybrid (on-device, Gemini fallback)"
        }
    }

    var provider: ContextualGlossProviding {
        switch self {
        case .onDevice: return OnDeviceOnlyContextualGlossProvider()
        case .gemini: return GeminiOnlyContextualGlossProvider()
        case .hybrid: return HybridContextualGlossProvider()
        }
    }
}

extension Notification.Name {
    static let contextualGlossBackendDidChange = Notification.Name("ContextualGlossBackendDidChange")
}

private extension ContextualGlossRequest {
    var asFoundationModelRequest: FoundationModelContextualGloss.Request {
        .init(sentence: sentence, surface: surface, dictionaryForm: dictionaryForm, dictionaryGloss: dictionaryGloss)
    }

    var asGeminiRequest: GeminiContextualGloss.Request {
        .init(sentence: sentence, surface: surface, dictionaryForm: dictionaryForm, dictionaryGloss: dictionaryGloss)
    }
}

private extension FoundationModelContextualGloss.Result {
    var asContextualGlossResult: ContextualGlossResult {
        .init(meaning: meaning, grammarNote: grammarNote)
    }
}

private extension GeminiContextualGloss.Result {
    var asContextualGlossResult: ContextualGlossResult {
        .init(meaning: meaning, grammarNote: grammarNote)
    }
}
