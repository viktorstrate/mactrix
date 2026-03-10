import AppKit
import Foundation
import ZMarkupParser

@MainActor
public func parseFormattedBody(_ body: String, baseFontSize: CGFloat = 13) -> NSAttributedString {
    let headingParagraphSpacing = MarkupStyleParagraphStyle(
        // paragraphSpacing: 5,
        paragraphSpacingBefore: baseFontSize * 0.8
    )

    let parser = ZHTMLParserBuilder
        .initWithDefault()
        .set(rootStyle: MarkupStyle(font: MarkupStyleFont(size: baseFontSize)))
        .add(
            H1_HTMLTagName(),
            withCustomStyle: MarkupStyle(
                font: MarkupStyleFont(size: baseFontSize * 1.8),
                paragraphStyle: headingParagraphSpacing
            )
        )
        .add(
            H2_HTMLTagName(),
            withCustomStyle: MarkupStyle(
                font: MarkupStyleFont(size: baseFontSize * 1.4),
                paragraphStyle: headingParagraphSpacing
            )
        )
        .add(
            H3_HTMLTagName(),
            withCustomStyle: MarkupStyle(
                font: MarkupStyleFont(size: baseFontSize * 1.2),
                paragraphStyle: headingParagraphSpacing
            )
        )
        .add(
            H4_HTMLTagName(),
            withCustomStyle: MarkupStyle(
                font: MarkupStyleFont(size: baseFontSize * 1.1, weight: .style(.medium)),
                paragraphStyle: headingParagraphSpacing
            )
        )
        .add(
            H5_HTMLTagName(),
            withCustomStyle: MarkupStyle(
                font: MarkupStyleFont(size: baseFontSize, weight: .style(.semibold)),
                paragraphStyle: headingParagraphSpacing
            )
        )
        .add(
            H6_HTMLTagName(),
            withCustomStyle: MarkupStyle(
                font: MarkupStyleFont(size: baseFontSize, weight: .style(.semibold)),
                paragraphStyle: headingParagraphSpacing
            )
        )
        .add(
            P_HTMLTagName(),
            withCustomStyle: MarkupStyle(
                paragraphStyle: MarkupStyleParagraphStyle(
                    paragraphSpacing: baseFontSize * 0.4,
                    paragraphSpacingBefore: baseFontSize * 0.4
                )
            )
        )
        .add(
            CODE_HTMLTagName(),
            withCustomStyle: MarkupStyle(
                font: MarkupStyleFont(size: baseFontSize, familyName: .familyNames(["Menlo"]))
                // backgroundColor: .init(color: NSColor(red: 0.8, green: 0.8, blue: 1, alpha: 0.5))
            )
        )
        .build()

    return parser.render(body)
}
