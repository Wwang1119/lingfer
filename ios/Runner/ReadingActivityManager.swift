import ActivityKit
import Foundation

@available(iOS 16.2, *)
final class ReadingActivityManager {
  static let shared = ReadingActivityManager()
  private var activity: Activity<ReadingActivityAttributes>?
  private var pending: Task<Void, Never>?
  private var previous: ReadingActivityAttributes.ContentState?
  private var lastUpdatedAt=Date.distantPast

  var active: Bool { activity?.activityState == .active || activity?.activityState == .stale }

  func start(_ state: ReadingActivityAttributes.ContentState) -> String? {
    guard ActivityAuthorizationInfo().areActivitiesEnabled else {
      return "实时活动未获允许，可在系统设置 → 语渡中开启；画中画仍可使用。"
    }
    end()
    // A terminated process cannot keep capturing. Remove its old status before
    // starting the newly authorized session, rather than showing two islands.
    let old = Activity<ReadingActivityAttributes>.activities
    Task { for item in old { await item.end(nil, dismissalPolicy: .immediate) } }
    do {
      let content=ActivityContent(state:state,staleDate:Date().addingTimeInterval(120),relevanceScore:100)
      if #available(iOS 18.0, *) {
        activity = try Activity.request(attributes:ReadingActivityAttributes(startedAt:Date()),content:content,pushType:nil,style:.standard)
      } else {
        activity = try Activity.request(attributes:ReadingActivityAttributes(startedAt:Date()),content:content,pushType:nil)
      }
      previous = state
      lastUpdatedAt=Date()
      return nil
    } catch { return "灵动岛暂未开启：\(error.localizedDescription)" }
  }

  func update(_ state: ReadingActivityAttributes.ContentState) {
    guard let current = activity else { return }
    // The timestamp is not a reason to ask the system to redraw unchanged text.
    if let p = previous, p.paused == state.paused, p.mode == state.mode,
       p.count == state.count, p.terms == state.terms, p.source == state.source,
       p.translation == state.translation, p.status == state.status,p.position==state.position,p.total==state.total,
       p.detailPosition==state.detailPosition,p.detailTotal==state.detailTotal,p.presentation==state.presentation,p.typeCategory==state.typeCategory,p.originalTerm==state.originalTerm,
       Date().timeIntervalSince(lastUpdatedAt)<45 { return }
    previous = state
    lastUpdatedAt=Date()
    let earlier = pending
    pending = Task {
      await earlier?.value
      await current.update(ActivityContent(state:state,staleDate:Date().addingTimeInterval(120),relevanceScore:100))
    }
  }

  func end() {
    let current = activity
    activity = nil; previous = nil
    let earlier = pending; pending = nil
    let remaining = current.map {[$0]} ?? Activity<ReadingActivityAttributes>.activities
    Task { await earlier?.value; for item in remaining { await item.end(nil, dismissalPolicy: .immediate) } }
  }
}
