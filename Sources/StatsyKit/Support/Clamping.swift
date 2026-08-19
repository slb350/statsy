public extension Double {
    /// Constrained to `0...1`.
    ///
    /// Fractional metrics drive layout widths and heights directly, and a value
    /// outside the unit range silently draws outside its track.
    var clamped01: Double { min(max(self, 0), 1) }
}
