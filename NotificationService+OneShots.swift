import Foundation
import UserNotifications

extension NotificationService {

    /// Schedules a one-time reminder for submitting SAS PDF on a specific date at 09:00 local.
    func scheduleSubmitSASPDF(on date: Date, applicantName: String) {
        let comps = Calendar.current.dateComponents([.year, .month, .day], from: date)
        var triggerComps = DateComponents()
        triggerComps.year = comps.year
        triggerComps.month = comps.month
        triggerComps.day = comps.day
        triggerComps.hour = 9
        triggerComps.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerComps, repeats: false)
        let content = UNMutableNotificationContent()
        content.title = "Submit SAS PDF"
        content.body = "Send SAS report for \(applicantName)."

        let id = "SASSubmit-\(applicantName)-\(comps.year ?? 0)-\(comps.month ?? 0)-\(comps.day ?? 0)"
        let req = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(req)
    }

    /// Cancels any pending SAS PDF submit reminder for the given applicant.
    func cancelSubmitSASPDF(applicantName: String) {
        UNUserNotificationCenter.current().getPendingNotificationRequests { reqs in
            let prefix = "SASSubmit-\(applicantName)-"
            let ids = reqs.filter { $0.identifier.hasPrefix(prefix) }.map { $0.identifier }
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
        }
    }

    /// Schedules local reminders relative to the event start time.
    func scheduleEventReminders(for event: RecruitEvent) {
        cancelEventReminders(for: event)
        let center = UNUserNotificationCenter.current()
        for mins in event.reminders {
            let fire = event.start.addingTimeInterval(TimeInterval(-mins * 60))
            guard fire > Date() else { continue }
            var comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let content = UNMutableNotificationContent()
            content.title = event.title
            content.body = event.start.formatted(date: .abbreviated, time: .shortened)
            let id = "EventReminder-\(event.id.uuidString)-\(mins)"
            let req = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
            center.add(req)
        }
    }

    /// Cancels all reminders scheduled for the given event.
    func cancelEventReminders(for event: RecruitEvent) {
        let ids = event.reminders.map { "EventReminder-\(event.id.uuidString)-\($0)" }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }
}
