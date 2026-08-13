import Vapor

struct ImageUpload: Content {
    var image: File
}

struct UploadResponse: Content {
    var url: String
}

struct UploadInfo: Content {
    var filename: String
    var sizeBytes: Int
    var width: Int?
    var height: Int?
    var uploadedAt: String?
    var uploadedByName: String?
}

enum Uploads {
    static var directory = "Data/uploads/"

    static func configure(dataDirectory: String) {
        let dir = URL(fileURLWithPath: dataDirectory).appendingPathComponent("uploads").path + "/"
        directory = dir
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    }
}
