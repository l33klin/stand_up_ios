import Foundation
import UserNotifications

enum ReminderAuthorization: Equatable {
    case unknown, notDetermined, denied, allowed, quiet
    var canNotify: Bool { self == .allowed || self == .quiet }
}

enum DeskNotice: Equatable {
    case sitting(minutes: Int, id: UUID)
    case goal(day: String, minutes: Int)
    case test(id: UUID)

    var identifier: String {
        switch self {
        case .sitting(_, let id): return "standup.sitting.\(id.uuidString)"
        case .goal(let day, _): return "standup.goal.\(day)"
        case .test(let id): return "standup.test.\(id.uuidString)"
        }
    }
    var title: String {
        switch self {
        case .sitting: return "起来活动一下吧"
        case .goal: return "站立目标达成！"
        case .test: return "StandUp 测试提醒"
        }
    }
    var body: String {
        switch self {
        case .sitting(let minutes, _): return "已连续记录坐姿 \(minutes) 分钟。休息一下，换个姿势，让下一段工作更轻松。"
        case .goal(let day, let minutes): return "\(day) 的 \(minutes) 分钟站立目标已完成。每一次站立，都在积累好习惯。"
        case .test: return "通知已开启。久坐与站立达标时，StandUp 会用这样的通知提醒你。"
        }
    }
}

protocol ReminderDelivering {
    func activate()
    func authorization(_ completion: @escaping (ReminderAuthorization) -> Void)
    func requestAuthorization(_ completion: @escaping (ReminderAuthorization, String?) -> Void)
    func deliver(_ notice: DeskNotice, completion: @escaping (Bool) -> Void)
}

/// Used by command-line tests: never creates a notification center or requests OS permission.
struct NoopReminderDelivery: ReminderDelivering {
    func activate() {}
    func authorization(_ completion: @escaping (ReminderAuthorization) -> Void) { completion(.notDetermined) }
    func requestAuthorization(_ completion: @escaping (ReminderAuthorization, String?) -> Void) { completion(.notDetermined, nil) }
    func deliver(_ notice: DeskNotice, completion: @escaping (Bool) -> Void) { completion(false) }
}

final class ReminderNotificationService: NSObject, ReminderDelivering, UNUserNotificationCenterDelegate {
    private var center: UNUserNotificationCenter { UNUserNotificationCenter.current() }

    func activate() { center.delegate = self }

    private func permission(_ status: UNAuthorizationStatus) -> ReminderAuthorization {
        switch status {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .authorized: return .allowed
        case .provisional: return .quiet
        #if os(iOS)
        case .ephemeral: return .allowed
        #endif
        @unknown default: return .unknown
        }
    }

    func authorization(_ completion: @escaping (ReminderAuthorization) -> Void) {
        center.getNotificationSettings { settings in
            let value = self.permission(settings.authorizationStatus)
            DispatchQueue.main.async { completion(value) }
        }
    }

    func requestAuthorization(_ completion: @escaping (ReminderAuthorization, String?) -> Void) {
        activate()
        center.requestAuthorization(options: [.alert, .sound]) { _, error in
            self.authorization { completion($0, error?.localizedDescription) }
        }
    }

    func deliver(_ notice: DeskNotice, completion: @escaping (Bool) -> Void) {
        // Recheck in case permission was revoked while the app stayed in the background.
        authorization { status in
            guard status.canNotify else { completion(false); return }
            let content = UNMutableNotificationContent()
            content.title = notice.title
            content.body = notice.body
            content.sound = .default
            content.threadIdentifier = "standup.reminders"
            // This event was already measured. Do not predict a future sitting posture
            // with a timer that could fire after a disconnect or during lunch.
            let request = UNNotificationRequest(identifier: notice.identifier, content: content, trigger: nil)
            self.center.add(request) { error in DispatchQueue.main.async { completion(error == nil) } }
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }
}
