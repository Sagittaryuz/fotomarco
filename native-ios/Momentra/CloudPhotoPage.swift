import Foundation

struct CloudPhoto: Identifiable, Equatable {
    let id: String
    let name: String
    let thumbnailURL: URL?
    let productURL: URL?
}

struct CloudPhotoPage {
    let photos: [CloudPhoto]
    let nextPageToken: String?

    static func parse(_ data: Data) throws -> CloudPhotoPage {
        struct Response: Decodable {
            struct Item: Decodable {
                let id: String
                let filename: String?
                let mimeType: String?
                let baseUrl: String?
                let productUrl: String?
            }
            let mediaItems: [Item]?
            let nextPageToken: String?
        }
        let response = try JSONDecoder().decode(Response.self, from: data)
        guard (response.mediaItems?.count ?? 0) <= 100, (response.nextPageToken?.utf8.count ?? 0) <= 2048 else {
            throw URLError(.cannotParseResponse)
        }
        let items = (response.mediaItems ?? []).compactMap { item -> CloudPhoto? in
            guard !item.id.isEmpty, item.id.utf8.count <= 512,
                  item.mimeType?.lowercased().hasPrefix("image/") == true else { return nil }
            let thumbnail = item.baseUrl.flatMap(thumbnailURL)
            let product = item.productUrl.flatMap(productURL)
            return CloudPhoto(id: item.id, name: String((item.filename ?? "Foto").prefix(200)), thumbnailURL: thumbnail, productURL: product)
        }
        return CloudPhotoPage(photos: items, nextPageToken: response.nextPageToken)
    }

    static func thumbnailURL(_ value: String) -> URL? {
        guard value.utf8.count <= 4096, let url = URL(string: value), url.scheme == "https",
              let host = url.host?.lowercased(), host.hasSuffix(".googleusercontent.com"),
              url.user == nil, url.password == nil, url.port == nil, url.query == nil, url.fragment == nil else { return nil }
        return URL(string: value + "=w360-h360-c")
    }

    static func productURL(_ value: String) -> URL? {
        guard value.utf8.count <= 4096, let url = URL(string: value), url.scheme == "https",
              url.host?.lowercased() == "photos.google.com", url.user == nil, url.password == nil, url.port == nil else { return nil }
        return url
    }
}
