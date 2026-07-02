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
    let formats: [YtDlpFormat]?

    enum CodingKeys: String, CodingKey {
        case type = "_type"
        case id, title, duration, thumbnail, url, formats
        case webpageURL = "webpage_url"
    }
}

struct YtDlpFormat: Decodable {
    let formatID: String
    let ext: String
    let vcodec: String?        // literal "none" for video-less streams (preserved)
    let acodec: String?        // literal "none" for audio-less streams (preserved)
    let height: Int?
    let filesize: Int64?
    let filesizeApprox: Int64?
    let tbr: Double?
    let formatNote: String?

    enum CodingKeys: String, CodingKey {
        case formatID = "format_id"
        case ext, vcodec, acodec, height, filesize, tbr
        case filesizeApprox = "filesize_approx"
        case formatNote = "format_note"
    }
}
