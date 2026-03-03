import Foundation

public enum IngestDecisions {
    public static func shouldAppendSeenSignature(forStatus status: String) -> Bool {
        status == "processed"
    }

    public static func failedPagesSummaryEntry(filename: String, failedPages: [Int]) -> String? {
        guard !failedPages.isEmpty else {
            return nil
        }

        let pageList = failedPages.sorted().map(String.init).joined(separator: "|")
        return "\(filename):\(failedPages.count)[\(pageList)]"
    }
}
