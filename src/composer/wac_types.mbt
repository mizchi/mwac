///|
suberror WacParseError {
  Message(String)
} derive(Show)

///|
pub(all) struct WacDocument {
  pkg : String
  targets : String?
  stmts : Array[WacStmt]
} derive(Show, ToJson)

///|
pub(all) enum WacStmt {
  Let(String, WacExpr)
  Export(WacExport)
  Import(WacImport)
} derive(Show, ToJson)

///|
pub(all) struct WacName {
  value : String
  exact : Bool
} derive(Show, ToJson)

///|
pub(all) struct WacImport {
  local_name : String
  import_name : String
  ty : WacImportType
} derive(Show, ToJson)

///|
pub(all) enum WacImportType {
  Package(String)
  Ident(String)
  InlineInterface(String)
  InlineFunc(String)
} derive(Show, ToJson)

///|
pub(all) struct WacExport {
  expr : WacExpr
  all : Bool
  as_name : String?
} derive(Show, ToJson)

///|
pub(all) enum WacExpr {
  Name(String)
  Access(WacExpr, WacName)
  New(WacNew)
} derive(Show, ToJson)

///|
pub(all) struct WacNew {
  pkg : String
  args : Array[WacArg]
} derive(Show, ToJson)

///|
pub(all) enum WacArg {
  SpreadAll
  SpreadInstance(String)
  Named(WacName, WacExpr)
  Inferred(WacExpr)
} derive(Show, ToJson)

///|
pub(all) struct WacResolveSummary {
  pkg : String
  components : Array[String]
  instantiations : Array[WacInstantiationSummary]
  exports : Array[String]
  imports : Array[String]
} derive(Show, ToJson)

///|
pub(all) struct WacInstantiationSummary {
  name : String
  component : String
  args : Array[String]
} derive(Show, ToJson)

///|
