import AppKit
import Foundation
import ZMarkupParser

@MainActor
let headingParagraphSpacing = MarkupStyleParagraphStyle(
    // paragraphSpacing: 5,
    paragraphSpacingBefore: 10
)

@MainActor
let parser = ZHTMLParserBuilder
    .initWithDefault()
    .set(rootStyle: MarkupStyle(font: MarkupStyleFont(size: 12)))
    .add(
        H1_HTMLTagName(),
        withCustomStyle: MarkupStyle(
            font: MarkupStyleFont(size: 24),
            paragraphStyle: headingParagraphSpacing
        )
    )
    .add(
        H2_HTMLTagName(),
        withCustomStyle: MarkupStyle(
            font: MarkupStyleFont(size: 18),
            paragraphStyle: headingParagraphSpacing
        )
    )
    .add(
        H3_HTMLTagName(),
        withCustomStyle: MarkupStyle(
            font: MarkupStyleFont(size: 16),
            paragraphStyle: headingParagraphSpacing
        )
    )
    .add(
        H4_HTMLTagName(),
        withCustomStyle: MarkupStyle(
            font: MarkupStyleFont(size: 14, weight: .style(.medium)),
            paragraphStyle: headingParagraphSpacing
        )
    )
    .add(
        H5_HTMLTagName(),
        withCustomStyle: MarkupStyle(
            font: MarkupStyleFont(size: 12, weight: .style(.semibold)),
            paragraphStyle: headingParagraphSpacing
        )
    )
    .add(
        H6_HTMLTagName(),
        withCustomStyle: MarkupStyle(
            font: MarkupStyleFont(size: 12, weight: .style(.semibold)),
            paragraphStyle: headingParagraphSpacing
        )
    )
    .add(
        P_HTMLTagName(),
        withCustomStyle: MarkupStyle(
            paragraphStyle: MarkupStyleParagraphStyle(
                paragraphSpacing: 5,
                paragraphSpacingBefore: 5
            )
        )
    )
    .add(
        CODE_HTMLTagName(),
        withCustomStyle: MarkupStyle(
            font: MarkupStyleFont(size: 12, familyName: .familyNames(["Menlo"]))
            // backgroundColor: .init(color: NSColor(red: 0.8, green: 0.8, blue: 1, alpha: 0.5))
        )
    )
    .build()

@MainActor
public func parseFormattedBody(_ body: String) -> NSAttributedString {
    return parser.render(body)
}
