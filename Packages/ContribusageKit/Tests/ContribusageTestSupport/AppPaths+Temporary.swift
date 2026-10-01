import ContribusageCore
import Foundation

extension AppPaths {
    /// A fresh root under the temporary directory, not yet created (ADR-015).
    public static func temporary() -> AppPaths {
        AppPaths(root: FileManager.default.temporaryDirectory.appending(path: "contribusage-\(UUID())/root/"))
    }
}
