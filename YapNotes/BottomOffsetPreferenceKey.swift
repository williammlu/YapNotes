//
//  BottomOffsetPreferenceKey.swift
//  YapNotes
//
//  Created by William Lu on 3/27/25.
//
import SwiftUI

struct BottomOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
