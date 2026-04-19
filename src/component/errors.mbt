///|
/// Parse error types for both Core WASM and Component Model
pub(all) suberror ParseError {
  // Common errors
  UnexpectedEof // Unexpected end of file
  InvalidMagic // Invalid magic number
  UnsupportedVersion // Unsupported version
  InvalidFormat(String) // Invalid format
  // Component Model specific errors
  InvalidLayer // Invalid component layer byte
  UnsupportedSection(UInt) // Unsupported section type
  InvalidSectionOrder // Invalid section order
  NestedError(String) // Error in nested module/component
}

///|
pub impl Show for ParseError with output(self, logger) {
  match self {
    UnexpectedEof => logger.write_string("UnexpectedEof")
    InvalidMagic => logger.write_string("InvalidMagic")
    UnsupportedVersion => logger.write_string("UnsupportedVersion")
    InvalidFormat(s) => {
      logger.write_string("InvalidFormat(")
      Show::output(s, logger)
      logger.write_string(")")
    }
    InvalidLayer => logger.write_string("InvalidLayer")
    UnsupportedSection(n) => {
      logger.write_string("UnsupportedSection(")
      Show::output(n, logger)
      logger.write_string(")")
    }
    InvalidSectionOrder => logger.write_string("InvalidSectionOrder")
    NestedError(s) => {
      logger.write_string("NestedError(")
      Show::output(s, logger)
      logger.write_string(")")
    }
  }
}
