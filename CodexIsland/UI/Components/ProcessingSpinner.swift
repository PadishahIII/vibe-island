//
//  ProcessingSpinner.swift
//  CodexIsland
//
//  Animated symbol spinner for processing state
//

import SwiftUI

struct ProcessingSpinner: View {
    let color: Color
    @ObservedObject private var animationTicker = AnimationTicker.shared

    private let symbols = ["·", "✢", "✳", "∗", "✻", "✽"]

    init(color: Color = TerminalColors.prompt) {
        self.color = color
    }

    var body: some View {
        Text(symbols[animationTicker.tick % symbols.count])
            .font(.system(size: 12, weight: .bold))
            .foregroundColor(color)
            .frame(width: 12, alignment: .center)
    }
}

#Preview {
    ProcessingSpinner()
        .frame(width: 30, height: 30)
        .background(.black)
}
