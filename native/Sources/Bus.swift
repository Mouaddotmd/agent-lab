// Shared ways in between parts of the app that don't know each other.
import Foundation

extension Notification.Name {
    /// Every engine event (userInfo is the event: "type" and its fields). Posted by Store after its own handling.
    static let engineEvent = Notification.Name("agentlab.engineEvent")
    /// Put text into an agent's message box. userInfo: "agentId": String, "text": String.
    static let addToMessage = Notification.Name("agentlab.addToMessage")
}

enum AddToMessage {
    /// Puts `text` into the box of `agentId`'s chat (after what's there, with the keyboard in the box).
    @MainActor static func send(_ agentId: String, _ text: String) {
        NotificationCenter.default.post(name: .addToMessage, object: nil, userInfo: ["agentId": agentId, "text": text])
    }
}
