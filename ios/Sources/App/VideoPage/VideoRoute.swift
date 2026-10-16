import Foundation

/// What opens a video page. Without a cid the page plays the part Bilibili last saw, or the first;
/// without a start it resumes where Bilibili last saw it.
struct VideoRoute: Hashable, Identifiable {
    var bvid: String
    var cid: Int64? = nil
    var startSeconds: Double? = nil
    var id = UUID()
}
