import Foundation

enum NotesJSONSchema {
  static let notesSummary: [String: Any] = {
    let topicTimelineItemSchema: [String: Any] = [
      "type": "object",
      "additionalProperties": false,
      "properties": [
        "id": ["type": "string"],
        "startTime": ["type": "number"],
        "title": ["type": "string"],
        "summary": [
          "anyOf": [
            ["type": "string"],
            ["type": "null"],
          ]
        ],
      ],
      "required": ["id", "startTime", "title", "summary"],
    ]

    return [
      "type": "object",
      "additionalProperties": false,
      "properties": [
        "title": ["type": "string"],
        "summaryMarkdown": ["type": "string"],
        "keyPoints": [
          "type": "array",
          "items": ["type": "string"],
        ],
        "actionItems": [
          "type": "array",
          "items": ["type": "string"],
        ],
        "openQuestions": [
          "type": "array",
          "items": ["type": "string"],
        ],
        "topicTimeline": [
          "type": "array",
          "items": topicTimelineItemSchema,
        ],
      ],
      "required": [
        "title",
        "summaryMarkdown",
        "keyPoints",
        "actionItems",
        "openQuestions",
        "topicTimeline",
      ],
    ]
  }()
}
