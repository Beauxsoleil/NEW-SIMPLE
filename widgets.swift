#if canImport(WidgetKit) && canImport(SwiftUI)
import WidgetKit
import SwiftUI

struct RecruiterEntry: TimelineEntry {
    let date: Date
    let message: String
}

struct RecruiterProvider: TimelineProvider {
    func placeholder(in context: Context) -> RecruiterEntry {
        RecruiterEntry(date: .now, message: "No upcoming events")
    }

    func getSnapshot(in context: Context, completion: @escaping (RecruiterEntry) -> Void) {
        completion(placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RecruiterEntry>) -> Void) {
        let defaults = UserDefaults(suiteName: "group.rops")
        let message = defaults?.string(forKey: "widgetMessage") ?? "Customize in app"
        let entry = RecruiterEntry(date: .now, message: message)
        let timeline = Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(3600)))
        completion(timeline)
    }
}

struct RecruiterWidgetEntryView: View {
    var entry: RecruiterEntry

    var body: some View {
        ZStack {
            Color(.systemBackground)
            Text(entry.message)
                .font(.headline)
                .padding()
        }
    }
}

struct RecruiterWidget: Widget {
    let kind: String = "RecruiterWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: RecruiterProvider()) { entry in
            RecruiterWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Recruiter")
        .description("Shows next task or message set in the app.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct RecruiterWidgetBundle: WidgetBundle {
    var body: some Widget {
        RecruiterWidget()
    }
}
#endif
