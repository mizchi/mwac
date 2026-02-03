///|
priv struct WacParser {
  bytes : Bytes
  mut pos : Int
}

///|
fn WacParser::new(input : String) -> WacParser {
  { bytes: @utf8.encode(input), pos: 0 }
}

///|
fn is_space(b : Byte) -> Bool {
  match b {
    b' ' | b'\t' | b'\n' | b'\r' => true
    _ => false
  }
}

///|
fn is_ident_start(b : Byte) -> Bool {
  match b {
    b'a'..=b'z' | b'A'..=b'Z' | b'_' => true
    _ => false
  }
}

///|
fn is_ident_char(b : Byte) -> Bool {
  is_ident_start(b) || (b >= b'0' && b <= b'9') || b == b'-'
}

///|
fn is_pkg_char(b : Byte) -> Bool {
  is_ident_char(b) || b == b':' || b == b'/' || b == b'.'
}

///|
fn wac_bytes_to_string(bytes : Bytes) -> String raise WacParseError {
  @utf8.decode(bytes) catch {
    _ => raise WacParseError::Message("invalid utf-8")
  }
}

///|
fn WacParser::peek(self : WacParser) -> Byte? {
  if self.pos < self.bytes.length() {
    Some(self.bytes[self.pos])
  } else {
    None
  }
}

///|
fn WacParser::skip_ws(self : WacParser) -> Unit {
  while self.pos < self.bytes.length() {
    let b = self.bytes[self.pos]
    if is_space(b) {
      self.pos = self.pos + 1
      continue
    }
    if b == b'/' && self.pos + 1 < self.bytes.length() {
      let b2 = self.bytes[self.pos + 1]
      if b2 == b'/' {
        self.pos = self.pos + 2
        while self.pos < self.bytes.length() && self.bytes[self.pos] != b'\n' {
          self.pos = self.pos + 1
        }
        continue
      }
      if b2 == b'*' {
        self.pos = self.pos + 2
        while self.pos + 1 < self.bytes.length() {
          if self.bytes[self.pos] == b'*' && self.bytes[self.pos + 1] == b'/' {
            self.pos = self.pos + 2
            break
          }
          self.pos = self.pos + 1
        }
        continue
      }
    }
    break
  }
}

///|
fn WacParser::consume_char(self : WacParser, ch : Byte) -> Bool {
  self.skip_ws()
  match self.peek() {
    Some(b) if b == ch => {
      self.pos = self.pos + 1
      true
    }
    _ => false
  }
}

///|
fn WacParser::expect_char(
  self : WacParser,
  ch : Byte,
) -> Unit raise WacParseError {
  if not(self.consume_char(ch)) {
    raise WacParseError::Message(
      "expected `\{String::from_array([ch.to_char()])}`",
    )
  }
}

///|
fn WacParser::starts_with(self : WacParser, kw : String) -> Bool {
  let kw_bytes = @utf8.encode(kw)
  if self.pos + kw_bytes.length() > self.bytes.length() {
    return false
  }
  for i in 0..<kw_bytes.length() {
    if self.bytes[self.pos + i] != kw_bytes[i] {
      return false
    }
  }
  true
}

///|
fn WacParser::consume_keyword(self : WacParser, kw : String) -> Bool {
  self.skip_ws()
  if not(self.starts_with(kw)) {
    return false
  }
  let end_pos = self.pos + kw.length()
  let mut boundary_ok = true
  if end_pos < self.bytes.length() {
    let b = self.bytes[end_pos]
    if is_ident_char(b) {
      boundary_ok = false
    }
  }
  if not(boundary_ok) {
    return false
  }
  self.pos = end_pos
  true
}

///|
fn WacParser::parse_ident(self : WacParser) -> String raise WacParseError {
  self.skip_ws()
  let start = self.pos
  match self.peek() {
    Some(b) if is_ident_start(b) => ()
    _ => raise WacParseError::Message("expected identifier")
  }
  while self.pos < self.bytes.length() {
    let b = self.bytes[self.pos]
    if not(is_ident_char(b)) {
      break
    }
    self.pos = self.pos + 1
  }
  let slice = self.bytes[start:self.pos].to_bytes()
  wac_bytes_to_string(slice)
}

///|
fn WacParser::parse_string_literal(
  self : WacParser,
) -> String raise WacParseError {
  self.skip_ws()
  if not(self.consume_char(b'"')) {
    raise WacParseError::Message("expected string literal")
  }
  let out : Array[Byte] = []
  while true {
    if self.pos >= self.bytes.length() {
      raise WacParseError::Message("unterminated string literal")
    }
    let b = self.bytes[self.pos]
    self.pos = self.pos + 1
    if b == b'"' {
      break
    }
    if b == b'\\' {
      if self.pos >= self.bytes.length() {
        raise WacParseError::Message("unterminated string escape")
      }
      let esc = self.bytes[self.pos]
      self.pos = self.pos + 1
      let mapped = match esc {
        b'\\' => b'\\'
        b'"' => b'"'
        b'n' => b'\n'
        b'r' => b'\r'
        b't' => b'\t'
        _ => raise WacParseError::Message("unknown escape sequence")
      }
      out.push(mapped)
    } else {
      out.push(b)
    }
  }
  wac_bytes_to_string(Bytes::from_array(out))
}

///|
fn WacParser::skip_string(self : WacParser) -> Unit raise WacParseError {
  if not(self.consume_char(b'"')) {
    raise WacParseError::Message("expected string")
  }
  while true {
    if self.pos >= self.bytes.length() {
      raise WacParseError::Message("unterminated string")
    }
    let b = self.bytes[self.pos]
    self.pos = self.pos + 1
    if b == b'"' {
      break
    }
    if b == b'\\' {
      if self.pos >= self.bytes.length() {
        raise WacParseError::Message("unterminated string escape")
      }
      self.pos = self.pos + 1
    }
  }
}

///|
fn WacParser::parse_brace_block(self : WacParser) -> String raise WacParseError {
  self.skip_ws()
  if not(self.consume_char(b'{')) {
    raise WacParseError::Message("expected '{'")
  }
  let start = self.pos - 1
  let mut depth = 1
  while depth > 0 {
    if self.pos >= self.bytes.length() {
      raise WacParseError::Message("unterminated '{'")
    }
    let b = self.bytes[self.pos]
    if b == b'"' {
      self.skip_string()
      continue
    }
    self.pos = self.pos + 1
    if b == b'{' {
      depth = depth + 1
    } else if b == b'}' {
      depth = depth - 1
    }
  }
  let end = self.pos
  wac_bytes_to_string(self.bytes[start:end].to_bytes())
}

///|
fn WacParser::parse_until_semicolon(
  self : WacParser,
) -> String raise WacParseError {
  let start = self.pos
  let mut paren = 0
  let mut bracket = 0
  let mut brace = 0
  while self.pos < self.bytes.length() {
    let b = self.bytes[self.pos]
    if b == b'"' {
      self.skip_string()
      continue
    }
    if paren == 0 && bracket == 0 && brace == 0 && b == b';' {
      break
    }
    self.pos = self.pos + 1
    if b == b'(' {
      paren = paren + 1
    } else if b == b')' {
      paren = paren - 1
    } else if b == b'[' {
      bracket = bracket + 1
    } else if b == b']' {
      bracket = bracket - 1
    } else if b == b'{' {
      brace = brace + 1
    } else if b == b'}' {
      brace = brace - 1
    }
  }
  if self.pos >= self.bytes.length() {
    raise WacParseError::Message("unterminated inline type")
  }
  wac_bytes_to_string(self.bytes[start:self.pos].to_bytes())
}

///|
fn WacParser::parse_import_type(
  self : WacParser,
) -> WacImportType raise WacParseError {
  self.skip_ws()
  if self.starts_with("interface") {
    let _ = self.consume_keyword("interface")
    let body = self.parse_brace_block()
    return WacImportType::InlineInterface(body)
  }
  if self.starts_with("func") {
    let _ = self.consume_keyword("func")
    let sig = self.parse_until_semicolon()
    return WacImportType::InlineFunc("func" + sig)
  }
  match self.peek() {
    Some(b) if b == b'"' => WacImportType::Package(self.parse_string_literal())
    _ => {
      let name = self.parse_package()
      if name.contains("/") || name.contains(":") {
        WacImportType::Package(name)
      } else {
        WacImportType::Ident(name)
      }
    }
  }
}

///|
fn WacParser::parse_name_or_string(
  self : WacParser,
) -> WacName raise WacParseError {
  self.skip_ws()
  match self.peek() {
    Some(b) if b == b'"' => {
      let value = self.parse_string_literal()
      { value, exact: true }
    }
    _ => {
      let value = self.parse_ident()
      { value, exact: false }
    }
  }
}

///|
fn WacParser::parse_package(self : WacParser) -> String raise WacParseError {
  self.skip_ws()
  let start = self.pos
  match self.peek() {
    Some(b) if is_ident_start(b) => ()
    _ => raise WacParseError::Message("expected package name")
  }
  while self.pos < self.bytes.length() {
    let b = self.bytes[self.pos]
    if not(is_pkg_char(b)) {
      break
    }
    self.pos = self.pos + 1
  }
  let slice = self.bytes[start:self.pos].to_bytes()
  wac_bytes_to_string(slice)
}

///|
fn WacParser::consume_dots(self : WacParser) -> Bool {
  self.skip_ws()
  if self.pos + 2 >= self.bytes.length() {
    return false
  }
  if self.bytes[self.pos] == b'.' &&
    self.bytes[self.pos + 1] == b'.' &&
    self.bytes[self.pos + 2] == b'.' {
    self.pos = self.pos + 3
    return true
  }
  false
}

///|
fn WacParser::parse_expr(self : WacParser) -> WacExpr raise WacParseError {
  self.skip_ws()
  if self.consume_keyword("new") {
    let pkg = self.parse_package()
    self.expect_char(b'{')
    let args : Array[WacArg] = []
    while true {
      self.skip_ws()
      if self.consume_char(b'}') {
        break
      }
      if self.consume_dots() {
        self.skip_ws()
        match self.peek() {
          Some(b) if is_ident_start(b) => {
            let name = self.parse_ident()
            args.push(WacArg::SpreadInstance(name))
          }
          _ => args.push(WacArg::SpreadAll)
        }
      } else {
        let name = self.parse_name_or_string()
        self.skip_ws()
        if name.exact {
          if not(self.consume_char(b':')) {
            raise WacParseError::Message("expected ':' after string argument")
          }
          let value = self.parse_expr()
          args.push(WacArg::Named(name, value))
        } else if self.consume_char(b':') {
          let value = self.parse_expr()
          args.push(WacArg::Named(name, value))
        } else {
          let mut expr : WacExpr = WacExpr::Name(name.value)
          expr = self.parse_access_tail(expr)
          args.push(WacArg::Inferred(expr))
        }
      }
      self.skip_ws()
      let _ = self.consume_char(b',')

    }
    return WacExpr::New({ pkg, args })
  }
  if self.consume_char(b'(') {
    let inner = self.parse_expr()
    self.expect_char(b')')
    return self.parse_access_tail(inner)
  }
  let name = self.parse_ident()
  let expr = WacExpr::Name(name)
  self.parse_access_tail(expr)
}

///|
fn WacParser::parse_access_tail(
  self : WacParser,
  expr : WacExpr,
) -> WacExpr raise WacParseError {
  let mut cur = expr
  while true {
    self.skip_ws()
    if self.starts_with("...") {
      break
    }
    if self.consume_char(b'.') {
      let name = self.parse_ident()
      cur = WacExpr::Access(cur, { value: name, exact: false })
      continue
    }
    if self.consume_char(b'[') {
      let name = self.parse_string_literal()
      self.expect_char(b']')
      cur = WacExpr::Access(cur, { value: name, exact: true })
      continue
    }
    break
  }
  cur
}

///|
fn WacParser::parse_stmt(self : WacParser) -> WacStmt raise WacParseError {
  if self.consume_keyword("let") {
    let name = self.parse_ident()
    self.expect_char(b'=')
    let expr = self.parse_expr()
    self.expect_char(b';')
    return WacStmt::Let(name, expr)
  }
  if self.consume_keyword("export") {
    let expr = self.parse_expr()
    let all = self.consume_dots()
    let mut as_name : String? = None
    if self.consume_keyword("as") {
      let name = self.parse_name_or_string()
      as_name = Some(name.value)
    }
    if all && as_name is Some(_) {
      raise WacParseError::Message("export ... cannot have alias")
    }
    self.expect_char(b';')
    return WacStmt::Export({ expr, all, as_name })
  }
  if self.consume_keyword("import") {
    let local_name = self.parse_ident()
    let mut import_name : String? = None
    if self.consume_keyword("as") {
      let name = self.parse_name_or_string()
      import_name = Some(name.value)
    }
    self.expect_char(b':')
    let ty = self.parse_import_type()
    let (default_name, ty) = import_type_default_name(
      ty,
      local_name.to_string(),
    )
    let name = match import_name {
      Some(n) => n
      None => default_name
    }
    self.expect_char(b';')
    return WacStmt::Import({ local_name, import_name: name, ty })
  }
  raise WacParseError::Message("unknown statement")
}

///|
pub fn parse_wac(source : String) -> Result[WacDocument, WacParseError] {
  let parser = WacParser::new(source)
  parser.skip_ws()
  if not(parser.consume_keyword("package")) {
    return Err(WacParseError::Message("missing package directive"))
  }
  let pkg = parser.parse_package() catch { e => return Err(e) }
  let mut targets : String? = None
  parser.skip_ws()
  if parser.consume_keyword("targets") {
    let target = match parser.peek() {
      Some(b) if b == b'"' =>
        parser.parse_string_literal() catch {
          e => return Err(e)
        }
      _ => parser.parse_package() catch { e => return Err(e) }
    }
    targets = Some(target)
  }
  parser.expect_char(b';') catch {
    e => return Err(e)
  }
  let stmts : Array[WacStmt] = []
  while true {
    parser.skip_ws()
    if parser.pos >= parser.bytes.length() {
      break
    }
    let stmt = parser.parse_stmt() catch { e => return Err(e) }
    stmts.push(stmt)
  }
  Ok({ pkg, targets, stmts })
}

///|

///|
fn import_type_default_name(
  ty : WacImportType,
  local_name : String,
) -> (String, WacImportType) {
  match ty {
    WacImportType::Package(pkg) => {
      let name = pkg.to_string()
      (name, WacImportType::Package(pkg))
    }
    WacImportType::Ident(ident) => {
      let name = ident.to_string()
      (name, WacImportType::Ident(ident))
    }
    WacImportType::InlineInterface(body) =>
      (local_name, WacImportType::InlineInterface(body))
    WacImportType::InlineFunc(body) =>
      (local_name, WacImportType::InlineFunc(body))
  }
}
