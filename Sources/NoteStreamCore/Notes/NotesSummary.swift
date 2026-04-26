import Foundation

public struct TopicTimelineItem: Codable, Sendable, Equatable, Identifiable {
  public var id: UUID
  public var startTime: TimeInterval
  public var title: String
  public var summary: String?

  enum CodingKeys: String, CodingKey {
    case id
    case startTime
    case title
    case summary
  }

  public init(
    id: UUID = UUID(),
    startTime: TimeInterval,
    title: String,
    summary: String? = nil
  ) {
    self.id = id
    self.startTime = startTime
    self.title = title
    self.summary = summary
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    if let u = try? c.decode(UUID.self, forKey: .id) {
      id = u
    } else if let s = try? c.decode(String.self, forKey: .id), let u = UUID(uuidString: s) {
      id = u
    } else {
      id = UUID()
    }
    startTime = try c.decode(TimeInterval.self, forKey: .startTime)
    title = try c.decode(String.self, forKey: .title)
    summary = try c.decodeIfPresent(String.self, forKey: .summary)
  }
}

public struct NotesSummary: Codable, Sendable, Equatable {
  public var title: String
  public var summaryMarkdown: String
  public var keyPoints: [String]
  public var actionItems: [String]
  public var openQuestions: [String]
  public var topicTimeline: [TopicTimelineItem]?

  enum CodingKeys: String, CodingKey {
    case title
    case summaryMarkdown
    case keyPoints
    case actionItems
    case openQuestions
    case topicTimeline
  }

  public init(
    title: String,
    summaryMarkdown: String,
    keyPoints: [String] = [],
    actionItems: [String] = [],
    openQuestions: [String] = [],
    topicTimeline: [TopicTimelineItem]? = nil
  ) {
    self.title = title
    self.summaryMarkdown = summaryMarkdown
    self.keyPoints = keyPoints
    self.actionItems = actionItems
    self.openQuestions = openQuestions
    self.topicTimeline = topicTimeline
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    title = try c.decode(String.self, forKey: .title)
    summaryMarkdown = try c.decode(String.self, forKey: .summaryMarkdown)
    keyPoints = try c.decodeIfPresent([String].self, forKey: .keyPoints) ?? []
    actionItems = try c.decodeIfPresent([String].self, forKey: .actionItems) ?? []
    openQuestions = try c.decodeIfPresent([String].self, forKey: .openQuestions) ?? []
    topicTimeline = try c.decodeIfPresent([TopicTimelineItem].self, forKey: .topicTimeline)
  }
}
