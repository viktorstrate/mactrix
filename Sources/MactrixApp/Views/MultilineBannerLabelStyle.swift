//
//  MultilineBanner.swift
//  Mactrix
//
//  Created by Marquis Kurt on 15-02-2026.
//

import SwiftUI

struct MultilineBannerLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline) {
            configuration.icon
            VStack(alignment: .leading) {
                configuration.title
            }
        }
    }
}

extension LabelStyle where Self == MultilineBannerLabelStyle {
    static var multiline: MultilineBannerLabelStyle { MultilineBannerLabelStyle() }
}
