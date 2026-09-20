public extension Double {
    /// Constrained to `0...1`.
    ///
    /// Fractional metrics drive layout widths and heights directly, and a value
    /// outside the unit range silently draws outside its track.
    var clamped01: Double { min(max(self, 0), 1) }
}

public extension Double {
    /// `part / whole`, or zero when there is no whole.
    ///
    /// Every metric on the panel divides one byte count by another, and each
    /// site had written the same zero guard. A division by zero here would
    /// reach a layout width as a NaN and collapse the bar silently.
    static func ratio(_ part: UInt64, of whole: UInt64) -> Double {
        whole == 0 ? 0 : Double(part) / Double(whole)
    }
}
