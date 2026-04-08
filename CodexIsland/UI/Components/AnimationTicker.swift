//
//  AnimationTicker.swift
//  CodexIsland
//
//  Shared UI animation clock for lightweight repeated indicators.
//

import Combine
import Foundation

@MainActor
final class AnimationTicker: ObservableObject {
    static let shared = AnimationTicker()

    @Published private(set) var tick: Int = 0

    private var timer: Timer?

    private init() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                tick = (tick + 1) % 3600
            }
        }
    }
}
