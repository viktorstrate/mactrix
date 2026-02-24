import AppKit

extension NSTableView {
    /// Animates scrolling to row with a given index.
    func animateRowToVisible(_ index: Int) {
        guard index >= 0, index < numberOfRows else { return }
        guard let scrollView = enclosingScrollView else { return }

        let rowRect = rect(ofRow: index)
        let clipView = scrollView.contentView
        let visibleRect = clipView.bounds

        var targetY = visibleRect.origin.y
        if rowRect.origin.y < visibleRect.origin.y {
            // Row is above: Scroll up until the top of the row is at the top
            targetY = rowRect.origin.y
        } else if rowRect.maxY > visibleRect.maxY {
            // Row is below: Scroll down until the bottom of the row is at the bottom
            targetY = rowRect.maxY - visibleRect.height
        } else {
            // Row is already fully visible: Exit
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            context.allowsImplicitAnimation = true

            var newBounds = clipView.bounds
            newBounds.origin.y = targetY
            clipView.animator().bounds = newBounds
        }
    }
}
