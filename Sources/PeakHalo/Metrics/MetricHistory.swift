import Foundation

struct MetricHistory {
    private(set) var values: [Double]
    private let capacity: Int

    init(capacity: Int, initialValue: Double = 0) {
        self.capacity = capacity
        self.values = Array(repeating: initialValue, count: capacity)
    }

    mutating func append(_ value: Double) {
        if values.count >= capacity {
            values.removeFirst()
        }
        values.append(min(max(value, 0), 100))
    }
}
