///|
priv struct ComponentSource {
  pkg : String
  bytes : Bytes
  detail : ComponentDetail
  import_info_map : Map[String, ImportInfo]
  import_detail_map : Map[String, ComponentImportDetail]
  export_detail_map : Map[String, ComponentExportDetail]
}

///|
fn build_import_info_map(info : ComponentInfo) -> Map[String, ImportInfo] {
  let map : Map[String, ImportInfo] = {}
  for imp in info.imports {
    map.set(imp.name.to_string(), imp)
  }
  map
}

///|
fn build_import_detail_map2(
  detail : ComponentDetail,
) -> Map[String, ComponentImportDetail] {
  let map : Map[String, ComponentImportDetail] = {}
  for imp in detail.imports {
    map.set(imp.name.to_string(), imp)
  }
  map
}

///|
fn build_export_detail_map(
  detail : ComponentDetail,
) -> Map[String, ComponentExportDetail] {
  let map : Map[String, ComponentExportDetail] = {}
  for exp in detail.exports {
    map.set(exp.name.to_string(), exp)
  }
  map
}

///|
fn resolve_component_path(
  base_dir : String,
  pkg_name : String,
) -> String raise WacParseError {
  let parts : Array[String] = []
  for part in pkg_name.split(":") {
    parts.push(part.to_string())
  }
  if parts.length() != 2 {
    raise WacParseError::Message("invalid package name: " + pkg_name)
  }
  let ns = parts[0]
  let rest = parts[1]
  base_dir + "/deps/" + ns + "/" + rest + ".wasm"
}

///|
fn load_component_source(
  base_dir : String,
  pkg_name : String,
) -> Result[ComponentSource, String] {
  let path = resolve_component_path(base_dir, pkg_name) catch {
    e => return Err(e.to_string())
  }
  let bytes = @fs.read_file_to_bytes(path) catch {
    _ => return Err("failed to read component: " + path)
  }
  let info = match parse_component_info(bytes) {
    Ok(v) => v
    Err(e) => return Err("failed to parse component info: " + e.to_string())
  }
  let detail = match parse_component_detail(bytes) {
    Ok(v) => v
    Err(e) => return Err("failed to parse component detail: " + e.to_string())
  }
  Ok({
    pkg: pkg_name,
    bytes,
    detail,
    import_info_map: build_import_info_map(info),
    import_detail_map: build_import_detail_map2(detail),
    export_detail_map: build_export_detail_map(detail),
  })
}

///|
priv enum ArgSource {
  Import(ImportRef)
  Export(String, String)
  Instance(String)
}

///|
priv struct ImportBinding {
  local_name : String
  import_name : String
  target : String
  ty : WacImportType
}

///|
priv struct ImportRef {
  comp_name : String
  import_name : String
}

///|
priv struct InstanceBinding {
  index : Int
  pkg : String
}

///|
priv struct ArgPlan {
  name : Bytes
  kind : ExternKind
  source : ArgSource
}

///|
priv struct InstantiationPlan {
  name : String
  component : ComponentSource
  args : Array[ArgPlan]
}

///|
priv struct ExportItemPlan {
  inst : String
  name : String
  as_name : String?
}

///|
priv enum ExportPlan {
  All(String)
  Item(ExportItemPlan)
}

///|
priv enum ArgValue {
  Import(ImportBinding)
  Export(String, WacName)
  Instance(String)
}

///|

///|
fn resolve_arg_value(
  expr : WacExpr,
  import_bindings : Map[String, ImportBinding],
  instance_bindings : Map[String, InstanceBinding],
) -> Result[ArgValue, String] {
  match expr {
    WacExpr::Name(name) => {
      let key = name.to_string()
      match resolve_import_binding(import_bindings, key.to_string()) {
        Some(binding) => Ok(ArgValue::Import(binding))
        None =>
          if instance_bindings.contains(key) {
            Ok(ArgValue::Instance(name))
          } else {
            Err("unknown value `\{name}`")
          }
      }
    }
    WacExpr::Access(base, name) =>
      match base {
        WacExpr::Name(inst) => Ok(ArgValue::Export(inst, name))
        _ => Err("unsupported access base")
      }
    _ => Err("unsupported value")
  }
}

///|
fn import_name_matches(actual : String, alias_name : String) -> Bool {
  if actual == alias_name {
    return true
  }
  if actual.has_suffix("/" + alias_name) {
    return true
  }
  if actual.has_suffix(":" + alias_name) {
    return true
  }
  false
}

///|
fn last_segment(name : String) -> String {
  match name.rev_find("/") {
    Some(idx) => normalize_segment(name[idx + 1:].to_string())
    None =>
      match name.rev_find(":") {
        Some(idx) => normalize_segment(name[idx + 1:].to_string())
        None => normalize_segment(name.to_string())
      }
  }
}

///|
fn normalize_segment(segment : String) -> String {
  match segment.rev_find("@") {
    Some(idx) => segment[:idx].to_string()
    None => segment
  }
}

///|
fn find_unique_suffix_match(names : Array[String], suffix : String) -> String? {
  let mut found : String? = None
  for name in names {
    if last_segment(name.to_string()) == suffix {
      match found {
        Some(_) => return None
        None => found = Some(name)
      }
    }
  }
  found
}

///|
fn import_names(comp : ComponentSource) -> Array[String] {
  let names : Array[String] = []
  for imp in comp.detail.imports {
    names.push(imp.name.to_string())
  }
  names
}

///|
fn export_names(comp : ComponentSource) -> Array[String] {
  let names : Array[String] = []
  for exp in comp.detail.exports {
    names.push(exp.name.to_string())
  }
  names
}

///|
fn infer_import_name(comp : ComponentSource, name : WacName) -> String {
  if name.exact {
    return name.value
  }
  let names = import_names(comp)
  match find_unique_suffix_match(names, name.value) {
    Some(v) => v
    None => name.value
  }
}

///|
fn infer_export_name(comp : ComponentSource, name : WacName) -> String {
  if name.exact {
    return name.value
  }
  let names = export_names(comp)
  match find_unique_suffix_match(names, name.value) {
    Some(v) => v
    None => name.value
  }
}

///|
fn infer_import_name_for_instance(
  comp : ComponentSource,
  pkg : String,
  local_name : String,
) -> String {
  if comp.import_detail_map.contains(pkg) {
    return pkg
  }
  let names = import_names(comp)
  match find_unique_suffix_match(names, local_name) {
    Some(v) => v
    None => local_name
  }
}

///|
fn resolve_import_binding(
  bindings : Map[String, ImportBinding],
  name : String,
) -> ImportBinding? {
  bindings.get(name)
}

///|
fn import_type_target(ty : WacImportType, import_name : String) -> String {
  match ty {
    WacImportType::Package(pkg) => pkg
    WacImportType::Ident(ident) => ident
    WacImportType::InlineInterface(_) => import_name
    WacImportType::InlineFunc(_) => import_name
  }
}

///|
fn match_import_binding(
  bindings : Map[String, ImportBinding],
  import_name : String,
) -> ImportBinding? {
  for _, binding in bindings {
    if import_name_matches(import_name, binding.target) ||
      import_name_matches(binding.target, import_name) {
      return Some(binding)
    }
  }
  for _, binding in bindings {
    if import_name_matches(import_name, binding.import_name) ||
      import_name_matches(binding.import_name, import_name) {
      return Some(binding)
    }
  }
  None
}

///|
fn find_import(
  comp : ComponentSource,
  alias_name : String,
  exact : Bool,
) -> Result[(String, ComponentImportDetail), String] {
  if exact {
    match comp.import_detail_map.get(alias_name) {
      Some(detail) => Ok((alias_name, detail))
      None => Err("unknown import `\{alias_name}` for `\{comp.pkg}`")
    }
  } else {
    match comp.import_detail_map.get(alias_name) {
      Some(detail) => Ok((alias_name, detail))
      None => {
        let alias_bytes = @utf8.encode(alias_name)
        for imp in comp.detail.imports {
          if imp.name == alias_bytes {
            return Ok((imp.name.to_string(), imp))
          }
          let name = imp.name.to_string()
          if import_name_matches(name, alias_name) {
            return Ok((name, imp))
          }
        }
        Err("unknown import `\{alias_name}` for `\{comp.pkg}`")
      }
    }
  }
}

///|
fn find_import_for_binding(
  comp : ComponentSource,
  binding : ImportBinding,
) -> Result[(String, ComponentImportDetail), String] {
  let mut found : (String, ComponentImportDetail)? = None
  for imp in comp.detail.imports {
    let name = imp.name.to_string()
    if import_name_matches(name, binding.target) ||
      import_name_matches(binding.target, name) {
      match found {
        Some(_) =>
          return Err(
            "ambiguous import for `\{binding.local_name}` in `\{comp.pkg}`",
          )
        None => found = Some((name, imp))
      }
    }
  }
  match found {
    Some(v) => Ok(v)
    None => {
      for imp in comp.detail.imports {
        let name = imp.name.to_string()
        if import_name_matches(name, binding.import_name) ||
          import_name_matches(binding.import_name, name) {
          return Ok((name, imp))
        }
      }
      Err("missing import `\{binding.target}` for `\{comp.pkg}`")
    }
  }
}

///|
fn find_export(
  comp : ComponentSource,
  alias_name : String,
  exact : Bool,
) -> Result[ComponentExportDetail, String] {
  if exact {
    match comp.export_detail_map.get(alias_name) {
      Some(detail) => Ok(detail)
      None => Err("unknown export `\{alias_name}` for `\{comp.pkg}`")
    }
  } else {
    match comp.export_detail_map.get(alias_name) {
      Some(detail) => Ok(detail)
      None => {
        let alias_bytes = @utf8.encode(alias_name)
        for exp in comp.detail.exports {
          if exp.name == alias_bytes {
            return Ok(exp)
          }
          let name = exp.name.to_string()
          if import_name_matches(name, alias_name) {
            return Ok(exp)
          }
        }
        Err("unknown export `\{alias_name}` for `\{comp.pkg}`")
      }
    }
  }
}

///|
fn get_component_from_cache(
  cache : Map[String, ComponentSource],
  base_dir : String,
  pkg_name : String,
) -> Result[ComponentSource, String] {
  match cache.get(pkg_name) {
    Some(c) => Ok(c)
    None => {
      let comp = match load_component_source(base_dir, pkg_name) {
        Ok(v) => v
        Err(e) => return Err(e)
      }
      cache.set(pkg_name, comp)
      Ok(comp)
    }
  }
}

///|
fn resolve_wac(
  doc : WacDocument,
  base_dir : String,
  best_effort : Bool,
) -> Result[(Array[InstantiationPlan], Array[ExportPlan]), String] {
  let component_cache : Map[String, ComponentSource] = {}
  let instantiations : Array[InstantiationPlan] = []
  let exports : Array[ExportPlan] = []
  let instance_bindings : Map[String, InstanceBinding] = {}
  let import_bindings : Map[String, ImportBinding] = {}
  for stmt in doc.stmts {
    match stmt {
      WacStmt::Import(import_stmt) => {
        if import_bindings.contains(import_stmt.local_name) ||
          instance_bindings.contains(import_stmt.local_name) {
          return Err("duplicate binding `\{import_stmt.local_name}`")
        }
        let target = import_type_target(
          import_stmt.ty,
          import_stmt.import_name.to_string(),
        )
        import_bindings.set(import_stmt.local_name, {
          local_name: import_stmt.local_name,
          import_name: import_stmt.import_name,
          target,
          ty: import_stmt.ty,
        })
      }
      WacStmt::Let(name, expr) =>
        match expr {
          WacExpr::New(new_expr) => {
            if import_bindings.contains(name) ||
              instance_bindings.contains(name) {
              return Err("duplicate binding `\{name}`")
            }
            let comp = match
              get_component_from_cache(component_cache, base_dir, new_expr.pkg) {
              Ok(v) => v
              Err(e) => return Err(e)
            }
            let explicit_args : Map[String, ArgPlan] = {}
            let mut has_spread_all = false
            let spread_instances : Array[String] = []
            for arg in new_expr.args {
              match arg {
                WacArg::SpreadAll => has_spread_all = true
                WacArg::SpreadInstance(inst_name) =>
                  spread_instances.push(inst_name)
                WacArg::Named(arg_name, value_expr) => {
                  let arg_label = arg_name.value.to_string()
                  let import_lookup = infer_import_name(comp, arg_name)
                  let (import_name, import_detail) = match
                    find_import(comp, import_lookup, true) {
                    Ok(v) => v
                    Err(_) =>
                      match find_import(comp, arg_label.to_string(), false) {
                        Ok(v) => v
                        Err(e) => return Err(e)
                      }
                  }
                  let value = match
                    resolve_arg_value(
                      value_expr, import_bindings, instance_bindings,
                    ) {
                    Ok(v) => v
                    Err(e) => return Err(e)
                  }
                  match value {
                    ArgValue::Import(binding) => {
                      if !import_name_matches(import_name, binding.target) &&
                        !import_name_matches(binding.target, import_name) &&
                        !import_name_matches(import_name, binding.import_name) &&
                        !import_name_matches(binding.import_name, import_name) {
                        return Err(
                          "import `\{binding.local_name}` does not match `\{import_name}`",
                        )
                      }
                      match
                        check_inline_import_type(
                          comp.detail,
                          import_name,
                          import_detail,
                          binding.ty,
                          best_effort,
                        ) {
                        Ok(_) => ()
                        Err(e) =>
                          return Err(
                            "import `\{binding.local_name}` inline type mismatch: " +
                            e,
                          )
                      }
                      let plan : ArgPlan = {
                        name: @utf8.encode(import_name),
                        kind: import_detail.kind,
                        source: ArgSource::Import({
                          comp_name: import_name,
                          import_name: binding.import_name,
                        }),
                      }
                      explicit_args.set(import_name, plan)
                    }
                    ArgValue::Export(inst_name, export_name) => {
                      let inst_idx = match instance_bindings.get(inst_name) {
                        Some(v) => v.index
                        None => return Err("unknown instance `\{inst_name}`")
                      }
                      let inst_plan = instantiations[inst_idx]
                      let export_label = export_name.value.to_string()
                      let export_lookup = infer_export_name(
                        inst_plan.component,
                        export_name,
                      )
                      let export_detail = match
                        find_export(inst_plan.component, export_lookup, true) {
                        Ok(v) => v
                        Err(_) =>
                          match
                            find_export(
                              inst_plan.component,
                              export_label,
                              false,
                            ) {
                            Ok(v) => v
                            Err(e) => return Err(e)
                          }
                      }
                      match
                        check_plug_import_export_type(
                          comp.detail,
                          inst_plan.component.detail,
                          import_detail,
                          export_detail,
                          best_effort~,
                        ) {
                        Ok(_) => ()
                        Err(e) =>
                          return Err("import `\{arg_label}` mismatch: " + e)
                      }
                      let plan : ArgPlan = {
                        name: @utf8.encode(import_name),
                        kind: import_detail.kind,
                        source: ArgSource::Export(
                          inst_name,
                          export_detail.name.to_string(),
                        ),
                      }
                      explicit_args.set(import_name, plan)
                    }
                    ArgValue::Instance(inst_name) => {
                      if import_detail.kind != ExternKind::Instance {
                        return Err("import `\{import_name}` expects instance")
                      }
                      if !instance_bindings.contains(inst_name) {
                        return Err("unknown instance `\{inst_name}`")
                      }
                      let plan : ArgPlan = {
                        name: @utf8.encode(import_name),
                        kind: import_detail.kind,
                        source: ArgSource::Instance(inst_name),
                      }
                      explicit_args.set(import_name, plan)
                    }
                  }
                }
                WacArg::Inferred(value_expr) => {
                  let value = match
                    resolve_arg_value(
                      value_expr, import_bindings, instance_bindings,
                    ) {
                    Ok(v) => v
                    Err(e) => return Err(e)
                  }
                  match value {
                    ArgValue::Import(binding) => {
                      let (import_name, import_detail) = match
                        find_import_for_binding(comp, binding) {
                        Ok(v) => v
                        Err(e) => return Err(e)
                      }
                      match
                        check_inline_import_type(
                          comp.detail,
                          import_name,
                          import_detail,
                          binding.ty,
                          best_effort,
                        ) {
                        Ok(_) => ()
                        Err(e) =>
                          return Err(
                            "import `\{binding.local_name}` inline type mismatch: " +
                            e,
                          )
                      }
                      let plan : ArgPlan = {
                        name: @utf8.encode(import_name),
                        kind: import_detail.kind,
                        source: ArgSource::Import({
                          comp_name: import_name,
                          import_name: binding.import_name,
                        }),
                      }
                      explicit_args.set(import_name, plan)
                    }
                    ArgValue::Export(inst_name, export_name) => {
                      let export_label = export_name.value.to_string()
                      let import_lookup = infer_import_name(comp, export_name)
                      let (import_name, import_detail) = match
                        find_import(comp, import_lookup, true) {
                        Ok(v) => v
                        Err(_) =>
                          match find_import(comp, export_label, false) {
                            Ok(v) => v
                            Err(e) => return Err(e)
                          }
                      }
                      let inst_idx = match instance_bindings.get(inst_name) {
                        Some(v) => v.index
                        None => return Err("unknown instance `\{inst_name}`")
                      }
                      let inst_plan = instantiations[inst_idx]
                      let export_lookup = infer_export_name(
                        inst_plan.component,
                        export_name,
                      )
                      let export_detail = match
                        find_export(inst_plan.component, export_lookup, true) {
                        Ok(v) => v
                        Err(_) =>
                          match
                            find_export(
                              inst_plan.component,
                              export_label,
                              false,
                            ) {
                            Ok(v) => v
                            Err(e) => return Err(e)
                          }
                      }
                      match
                        check_plug_import_export_type(
                          comp.detail,
                          inst_plan.component.detail,
                          import_detail,
                          export_detail,
                          best_effort~,
                        ) {
                        Ok(_) => ()
                        Err(e) =>
                          return Err("import `\{import_name}` mismatch: " + e)
                      }
                      let plan : ArgPlan = {
                        name: @utf8.encode(import_name),
                        kind: import_detail.kind,
                        source: ArgSource::Export(
                          inst_name,
                          export_detail.name.to_string(),
                        ),
                      }
                      explicit_args.set(import_name, plan)
                    }
                    ArgValue::Instance(inst_name) => {
                      let binding = match instance_bindings.get(inst_name) {
                        Some(v) => v
                        None => return Err("unknown instance `\{inst_name}`")
                      }
                      let local_name = inst_name.to_string()
                      let import_lookup = infer_import_name_for_instance(
                        comp,
                        binding.pkg.to_string(),
                        local_name,
                      )
                      let (import_name, import_detail) = match
                        find_import(comp, import_lookup, true) {
                        Ok(v) => v
                        Err(_) =>
                          match
                            find_import(comp, inst_name.to_string(), false) {
                            Ok(v) => v
                            Err(e) => return Err(e)
                          }
                      }
                      if import_detail.kind != ExternKind::Instance {
                        return Err("import `\{import_name}` expects instance")
                      }
                      let plan : ArgPlan = {
                        name: @utf8.encode(import_name),
                        kind: import_detail.kind,
                        source: ArgSource::Instance(inst_name),
                      }
                      explicit_args.set(import_name, plan)
                    }
                  }
                }
              }
            }
            for inst_name in spread_instances {
              let inst_idx = match instance_bindings.get(inst_name) {
                Some(v) => v.index
                None => return Err("unknown instance `\{inst_name}`")
              }
              let inst_plan = instantiations[inst_idx]
              let mut used = false
              for imp in comp.detail.imports {
                let imp_name = imp.name.to_string()
                if explicit_args.contains(imp_name) {
                  continue
                }
                let export_detail = match
                  find_export(inst_plan.component, imp_name, false) {
                  Ok(v) => v
                  Err(_) => continue
                }
                match
                  check_plug_import_export_type(
                    comp.detail,
                    inst_plan.component.detail,
                    imp,
                    export_detail,
                    best_effort~,
                  ) {
                  Ok(_) => ()
                  Err(_) => continue
                }
                let plan : ArgPlan = {
                  name: imp.name,
                  kind: imp.kind,
                  source: ArgSource::Export(
                    inst_name,
                    export_detail.name.to_string(),
                  ),
                }
                explicit_args.set(imp_name, plan)
                used = true
              }
              if !used {
                return Err(
                  "spread instance `\{inst_name}` has no matching exports",
                )
              }
            }
            let args : Array[ArgPlan] = []
            for imp in comp.detail.imports {
              let imp_name = imp.name.to_string()
              match explicit_args.get(imp_name) {
                Some(p) => args.push(p)
                None =>
                  if has_spread_all {
                    let binding = match_import_binding(
                      import_bindings, imp_name,
                    )
                    let import_name = match binding {
                      Some(b) => b.import_name
                      None => imp_name
                    }
                    match binding {
                      Some(b) =>
                        match
                          check_inline_import_type(
                            comp.detail,
                            imp_name,
                            imp,
                            b.ty,
                            best_effort,
                          ) {
                          Ok(_) => ()
                          Err(e) =>
                            return Err(
                              "import `\{b.local_name}` inline type mismatch: " +
                              e,
                            )
                        }
                      None => ()
                    }
                    args.push({
                      name: imp.name,
                      kind: imp.kind,
                      source: ArgSource::Import({
                        comp_name: imp_name,
                        import_name,
                      }),
                    })
                  } else {
                    return Err(
                      "missing import `\{imp_name}` for `\{new_expr.pkg}`",
                    )
                  }
              }
            }
            let plan : InstantiationPlan = { name, component: comp, args }
            instance_bindings.set(name, {
              index: instantiations.length(),
              pkg: new_expr.pkg,
            })
            instantiations.push(plan)
          }
          _ => return Err("let must bind a new expression")
        }
      WacStmt::Export(export_stmt) =>
        match export_stmt.expr {
          WacExpr::Name(name) =>
            if export_stmt.all {
              exports.push(ExportPlan::All(name))
            } else {
              return Err("export expects access or ...")
            }
          WacExpr::Access(base, name) =>
            match base {
              WacExpr::Name(inst) =>
                if export_stmt.all {
                  return Err("export ... expects instance name")
                } else {
                  let inst_idx = match instance_bindings.get(inst) {
                    Some(v) => v.index
                    None => return Err("unknown instance `\{inst}`")
                  }
                  let inst_plan = instantiations[inst_idx]
                  let export_lookup = infer_export_name(
                    inst_plan.component,
                    name,
                  )
                  let export_detail = match
                    find_export(inst_plan.component, export_lookup, true) {
                    Ok(v) => v
                    Err(_) =>
                      match
                        find_export(
                          inst_plan.component,
                          name.value.to_string(),
                          false,
                        ) {
                        Ok(v) => v
                        Err(e) => return Err(e)
                      }
                  }
                  exports.push(
                    ExportPlan::Item({
                      inst,
                      name: export_detail.name.to_string(),
                      as_name: export_stmt.as_name,
                    }),
                  )
                }
              _ => return Err("unsupported export expression")
            }
          _ => return Err("unsupported export expression")
        }
    }
  }
  Ok((instantiations, exports))
}
