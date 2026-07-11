import WidgetKit
import SwiftUI

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date(), courses: [], assignments: [])
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> ()) {
        let entry = SimpleEntry(date: Date(),
                                courses: WidgetDataManager.shared.courses,
                                assignments: WidgetDataManager.shared.assignments)
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SimpleEntry>) -> ()) {
        let entry = SimpleEntry(date: Date(),
                                courses: WidgetDataManager.shared.courses,
                                assignments: WidgetDataManager.shared.assignments)
        
        // Update widget occasionally or when told by Flutter
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date().addingTimeInterval(30 * 60)
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

struct SimpleEntry: TimelineEntry {
    let date: Date
    let courses: [Course]
    let assignments: [Assignment]
}

struct TechPieWidgetEntryView : View {
    var entry: Provider.Entry
    @Environment(\.widgetFamily) var family

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 10) {
                if family == .systemSmall {
                    smallView
                } else {
                    mediumView
                }
            }
            .padding()
        }
    }
    
    var smallView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "book.fill")
                    .foregroundColor(.blue)
                Text("Next Class")
                    .font(.headline)
            }
            
            if let firstClass = entry.courses.first {
                Text(firstClass.name)
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .lineLimit(2)
                Text("\(firstClass.startTime) - \(firstClass.endTime)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(firstClass.location)
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text("No more classes today! 🎉")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    var mediumView: some View {
        HStack(alignment: .top, spacing: 16) {
            // Left Side: Schedule
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "calendar")
                        .foregroundColor(.blue)
                    Text("Today's Classes")
                        .font(.headline)
                }
                
                if entry.courses.isEmpty {
                    Text("Free day! 🎉")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(entry.courses.prefix(2)) { course in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(course.name)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .lineLimit(1)
                            Text("\(course.startTime) | \(course.location)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Divider()
            
            // Right Side: Assignments
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "doc.text.fill")
                        .foregroundColor(.orange)
                    Text("Pending Work")
                        .font(.headline)
                }
                
                if entry.assignments.isEmpty {
                    Text("All caught up! ✅")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(entry.assignments.prefix(2)) { assignment in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(assignment.title)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .lineLimit(1)
                            Text(assignment.course)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct TechPieWidget: Widget {
    let kind: String = "TechPieWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            if #available(iOS 17.0, *) {
                TechPieWidgetEntryView(entry: entry)
                    .containerBackground(Color(UIColor.systemBackground), for: .widget)
            } else {
                TechPieWidgetEntryView(entry: entry)
                    .background(Color(UIColor.systemBackground))
            }
        }
        .configurationDisplayName("TechPie Tracker")
        .description("Track your daily schedule and pending assignments.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Data Models

struct Course: Codable, Identifiable {
    var id: String { name + startTime }
    let name: String
    let location: String
    let startTime: String
    let endTime: String
}

struct Assignment: Codable, Identifiable {
    var id: String { title + course }
    let title: String
    let course: String
    let due: String
}

class WidgetDataManager {
    static let shared = WidgetDataManager()
    // IMPORTANT: Match this with your App Group ID configured in Xcode
    let appGroupID = "group.com.example.techpie"
    
    var courses: [Course] {
        guard let defaults = UserDefaults(suiteName: appGroupID),
              let dataString = defaults.string(forKey: "schedule_data"),
              let data = dataString.data(using: .utf8) else {
            return []
        }
        
        do {
            return try JSONDecoder().decode([Course].self, from: data)
        } catch {
            print("Error decoding courses: \(error)")
            return []
        }
    }
    
    var assignments: [Assignment] {
        guard let defaults = UserDefaults(suiteName: appGroupID),
              let dataString = defaults.string(forKey: "assignment_data"),
              let data = dataString.data(using: .utf8) else {
            return []
        }
        
        do {
            return try JSONDecoder().decode([Assignment].self, from: data)
        } catch {
            print("Error decoding assignments: \(error)")
            return []
        }
    }
}
