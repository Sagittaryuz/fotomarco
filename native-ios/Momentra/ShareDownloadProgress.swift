import Foundation

/// Per-task download observer. Redirects remain disabled so that an
/// authenticated request can never forward credentials to another host.
final class ShareDownloadProgress: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let report: @Sendable (Double) -> Void

    init(report: @escaping @Sendable (Double) -> Void) {
        self.report = report
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard let response = downloadTask.response as? HTTPURLResponse, response.statusCode == 200,
              totalBytesExpectedToWrite > 0, totalBytesWritten >= 0 else { return }
        report(min(1, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        // URLSession's async download method owns the temporary file.
    }
}
