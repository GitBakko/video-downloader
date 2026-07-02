import Foundation

/// Codable mirror of the subset of `yt-dlp -J` output we consume.
/// A single video and each playlist entry share the same shape, so one
/// struct serves both. (A playlist additionally sets `_type == "playlist"`
/// and an `entries` array — added in a later task.)
struct YtDlpInfo: Decodable {
    let type: String?
    let id: String?
    let title: String?
    let duration: Double?
    let thumbnail: String?
    let webpageURL: String?
    let url: String?

    enum CodingKeys: String, CodingKey {
        case type = "_type"
        case id, title, duration, thumbnail, url
        case webpageURL = "webpage_url"
    }
}
