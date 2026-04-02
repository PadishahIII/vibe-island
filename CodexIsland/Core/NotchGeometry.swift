//
//  NotchGeometry.swift
//  CodexIsland
//
//  Geometry calculations for the notch
//

import CoreGraphics
import Foundation

/// Pure geometry calculations for the notch
struct NotchGeometry: Sendable {
    let deviceNotchRect: CGRect
    let screenRect: CGRect
    let windowHeight: CGFloat

    /// The notch rect in screen coordinates (for hit testing with global mouse position)
    var notchScreenRect: CGRect {
        CGRect(
            x: screenRect.midX - deviceNotchRect.width / 2,
            y: screenRect.maxY - deviceNotchRect.height,
            width: deviceNotchRect.width,
            height: deviceNotchRect.height
        )
    }

    func closedBarScreenRect(width: CGFloat, height: CGFloat) -> CGRect {
        CGRect(
            x: screenRect.midX - width / 2,
            y: screenRect.maxY - height,
            width: width,
            height: height
        )
    }

    func closedBarWindowRect(width: CGFloat, height: CGFloat) -> CGRect {
        CGRect(
            x: (screenRect.width - width) / 2,
            y: windowHeight - height,
            width: width,
            height: height
        )
    }

    /// The opened panel rect in screen coordinates for a given size
    func openedScreenRect(for size: CGSize) -> CGRect {
        return CGRect(
            x: screenRect.midX - size.width / 2,
            y: screenRect.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }

    func openedWindowRect(for size: CGSize) -> CGRect {
        CGRect(
            x: (screenRect.width - size.width) / 2,
            y: windowHeight - size.height,
            width: size.width,
            height: size.height
        )
    }

    func openedHeaderScreenRect(for size: CGSize, width: CGFloat, height: CGFloat) -> CGRect {
        let panelRect = openedScreenRect(for: size)
        let clampedWidth = min(width, panelRect.width)
        return CGRect(
            x: panelRect.midX - clampedWidth / 2,
            y: panelRect.maxY - height,
            width: clampedWidth,
            height: height
        )
    }

    func isPointInClosedBar(_ point: CGPoint, width: CGFloat, height: CGFloat) -> Bool {
        closedBarScreenRect(width: width, height: height)
            .insetBy(dx: -10, dy: -8)
            .contains(point)
    }

    func isPointInOpenedHeader(_ point: CGPoint, size: CGSize, width: CGFloat, height: CGFloat) -> Bool {
        openedHeaderScreenRect(for: size, width: width, height: height)
            .insetBy(dx: -6, dy: -4)
            .contains(point)
    }

    /// Check if a point is in the opened panel area
    func isPointInOpenedPanel(_ point: CGPoint, size: CGSize) -> Bool {
        openedScreenRect(for: size).contains(point)
    }

    /// Check if a point is outside the opened panel (for closing)
    func isPointOutsidePanel(_ point: CGPoint, size: CGSize) -> Bool {
        !openedScreenRect(for: size).contains(point)
    }
}
