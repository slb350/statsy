import Foundation

/// The value following `flag`, or nil when the flag is absent, is the last
/// argument, or is followed by another flag: a flag with no value is a usage
/// error, not an index out of range, and `--render --fixture out.prom` must not
/// write a PNG named `--fixture`. Shared by the panel and the probe.
public func argument(after flag: String, in arguments: [String]) -> String? {
    guard let index = arguments.firstIndex(of: flag) else { return nil }
    let next = arguments.index(after: index)
    guard next < arguments.endIndex else { return nil }
    let value = arguments[next]
    guard !value.hasPrefix("--") else { return nil }
    return value
}
