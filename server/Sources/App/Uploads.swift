import Vapor

struct ImageUpload: Content {
    var image: File
}

struct UploadResponse: Content {
    var url: String
}

enum Uploads {
    static var directory = "Data/uploads/"

    static func configure(dataDirectory: String) {
        let dir = URL(fileURLWithPath: dataDirectory).appendingPathComponent("uploads").path + "/"
        directory = dir
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    }
}
