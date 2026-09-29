import Foundation

public enum VirtualTimelineItem {
    /**
     * A divider between messages of different day or month depending on
     * timeline settings.
     */
    case dateDivider(
        date: Date
    )
    /**
     * The user's own read marker.
     */
    case readMarker
    /**
     * The timeline start, that is, the *oldest* event in time for that room.
     */
    case timelineStart
}
