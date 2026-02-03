///|
fn merge_import_spec(
  merged : Array[ImportInfo],
  merged_details : Array[ComponentImportDetail],
  merged_sources : Array[ComponentDetail],
  index_map : Map[String, UInt],
  info : ImportInfo,
  detail : ComponentImportDetail,
  source_detail : ComponentDetail,
  best_effort : Bool,
) -> Result[UInt, String] {
  let key = info.name.to_string()
  match index_map.get(key) {
    Some(idx) => {
      let existing_detail = merged_details[idx.reinterpret_as_int()]
      let existing_source = merged_sources[idx.reinterpret_as_int()]
      match
        compare_import_types(
          existing_source,
          existing_detail,
          source_detail,
          detail,
          best_effort~,
        ) {
        Ok(ImportRelation::Equal) => Ok(idx)
        Ok(ImportRelation::BSubtypeA) => Ok(idx)
        Ok(ImportRelation::ASubtypeB) => {
          merged[idx.reinterpret_as_int()] = info
          merged_details[idx.reinterpret_as_int()] = detail
          merged_sources[idx.reinterpret_as_int()] = source_detail
          Ok(idx)
        }
        Err(msg) => Err("import type conflict for `\{key}`: " + msg)
      }
    }
    None => {
      let idx = merged.length().reinterpret_as_uint()
      merged.push(info)
      merged_details.push(detail)
      merged_sources.push(source_detail)
      index_map.set(key, idx)
      Ok(idx)
    }
  }
}

///|
fn build_alias_key(inst : String, name : String) -> String {
  inst + "#" + name
}

///|
fn require_instance_idx(
  map : Map[String, Int],
  name : String,
) -> Result[Int, String] {
  match map.get(name) {
    Some(v) => Ok(v)
    None => Err("unknown instance `\{name}`")
  }
}

///|
fn dirname(path : String) -> String {
  match path.rev_find("/") {
    Some(idx) => {
      let prefix = path[:idx] catch { _ => "." }
      if prefix.is_empty() {
        "."
      } else {
        prefix.to_string()
      }
    }
    None => "."
  }
}

///|
pub fn compose_wac_source(
  source : String,
  base_dir : String,
  best_effort? : Bool = false,
  dce? : Bool = false,
) -> Result[Bytes, String] {
  let doc = match parse_wac(source) {
    Ok(v) => v
    Err(e) => return Err(e.to_string())
  }
  let (instantiations, exports) = match
    resolve_wac(doc, base_dir, best_effort) {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  // NOTE: moon-component extension; upstream wac doesn't apply DCE.
  let (instantiations, exports) = if dce {
    dce_wac_plans(instantiations, exports)
  } else {
    (instantiations, exports)
  }
  let instance_index_map : Map[String, Int] = {}
  for i in 0..<instantiations.length() {
    instance_index_map.set(instantiations[i].name, i)
  }
  let component_sources : Map[String, ComponentSource] = {}
  let component_order : Array[String] = []
  for inst in instantiations {
    let pkg = inst.component.pkg
    if not(component_sources.contains(pkg)) {
      component_sources.set(pkg, inst.component)
      component_order.push(pkg)
    }
  }
  let component_index_map : Map[String, UInt] = {}
  for i in 0..<component_order.length() {
    component_index_map.set(component_order[i], i.reinterpret_as_uint())
  }
  let merged_imports : Array[ImportInfo] = []
  let merged_details : Array[ComponentImportDetail] = []
  let merged_sources : Array[ComponentDetail] = []
  let import_index_map : Map[String, UInt] = {}
  for inst in instantiations {
    let comp = inst.component
    for arg in inst.args {
      match arg.source {
        ArgSource::Import(import_ref) => {
          let info = match comp.import_info_map.get(import_ref.comp_name) {
            Some(v) => v
            None =>
              return Err("missing import info for `\{import_ref.comp_name}`")
          }
          let detail = match comp.import_detail_map.get(import_ref.comp_name) {
            Some(v) => v
            None =>
              return Err("missing import detail for `\{import_ref.comp_name}`")
          }
          let info2 = if import_ref.import_name != import_ref.comp_name {
            ImportInfo::{
              name: @utf8.encode(import_ref.import_name),
              kind: info.kind,
              raw_desc: info.raw_desc,
            }
          } else {
            info
          }
          let detail2 = if import_ref.import_name != import_ref.comp_name {
            ComponentImportDetail::{
              name: @utf8.encode(import_ref.import_name),
              kind: detail.kind,
              type_ref: detail.type_ref,
            }
          } else {
            detail
          }
          match
            merge_import_spec(
              merged_imports,
              merged_details,
              merged_sources,
              import_index_map,
              info2,
              detail2,
              comp.detail,
              best_effort,
            ) {
            Ok(_) => ()
            Err(e) => return Err(e)
          }
        }
        ArgSource::Export(_, _) => ()
        ArgSource::Instance(_) => ()
      }
    }
  }
  let index_state = IndexState::new()
  let component_indices : Array[UInt] = Array::make(
    component_order.length(),
    0U,
  )
  for i in 0..<component_order.length() {
    component_indices[i] = index_state.next(ExternKind::Component)
  }
  let merged_import_indices : Array[UInt] = Array::make(
    merged_imports.length(),
    0U,
  )
  for i in 0..<merged_imports.length() {
    let imp = merged_imports[i]
    merged_import_indices[i] = index_state.next(imp.kind)
  }
  let instance_indices : Array[UInt] = Array::make(instantiations.length(), 0U)
  for i in 0..<instantiations.length() {
    instance_indices[i] = index_state.next(ExternKind::Instance)
  }
  let alias_map : Map[String, UInt] = {}
  let alias_entries : Array[(UInt, Bytes, ExternKind)] = []
  for inst in instantiations {
    for arg in inst.args {
      match arg.source {
        ArgSource::Export(inst_name, export_name) => {
          let key = build_alias_key(inst_name, export_name)
          if not(alias_map.contains(key)) {
            let inst_pos = match
              require_instance_idx(instance_index_map, inst_name) {
              Ok(v) => v
              Err(e) => return Err(e)
            }
            let inst_idx = instance_indices[inst_pos]
            let inst_plan = instantiations[inst_pos]
            let export_detail = match
              find_export(inst_plan.component, export_name, true) {
              Ok(v) => v
              Err(e) => return Err(e)
            }
            let alias_idx = index_state.next(export_detail.kind)
            alias_map.set(key, alias_idx)
            alias_entries.push(
              (inst_idx, export_detail.name, export_detail.kind),
            )
          }
        }
        _ => ()
      }
    }
  }
  for exp in exports {
    match exp {
      ExportPlan::Item(plan) => {
        let inst_name = plan.inst
        let export_name = plan.name
        let key = build_alias_key(inst_name, export_name)
        if not(alias_map.contains(key)) {
          let inst_pos = match
            require_instance_idx(instance_index_map, inst_name) {
            Ok(v) => v
            Err(e) => return Err(e)
          }
          let inst_idx = instance_indices[inst_pos]
          let inst_plan = instantiations[inst_pos]
          let export_detail = match
            find_export(inst_plan.component, export_name, true) {
            Ok(v) => v
            Err(e) => return Err(e)
          }
          let alias_idx = index_state.next(export_detail.kind)
          alias_map.set(key, alias_idx)
          alias_entries.push((inst_idx, export_detail.name, export_detail.kind))
        }
      }
      ExportPlan::All(inst_name) => {
        let inst_pos = match
          require_instance_idx(instance_index_map, inst_name) {
          Ok(v) => v
          Err(e) => return Err(e)
        }
        let inst_idx = instance_indices[inst_pos]
        let inst_plan = instantiations[inst_pos]
        for name, export_detail in inst_plan.component.export_detail_map {
          let key = build_alias_key(inst_name, name)
          if not(alias_map.contains(key)) {
            let alias_idx = index_state.next(export_detail.kind)
            alias_map.set(key, alias_idx)
            alias_entries.push(
              (inst_idx, export_detail.name, export_detail.kind),
            )
          }
        }
      }
    }
  }
  let out : Array[Byte] = []
  append_bytes(out, [
    0x00U.to_byte(),
    0x61U.to_byte(),
    0x73U.to_byte(),
    0x6dU.to_byte(),
  ])
  append_bytes(out, [0x0dU.to_byte(), 0x00U.to_byte()])
  append_bytes(out, [0x01U.to_byte(), 0x00U.to_byte()])

  // Section 4: component definitions
  for pkg in component_order {
    let comp = component_sources[pkg]
    push_section(out, 4U, comp.bytes.to_array())
  }

  // Section 10: imports
  if merged_imports.length() > 0 {
    let payload : Array[Byte] = []
    append_bytes(
      payload,
      encode_u32_leb128(merged_imports.length().reinterpret_as_uint()),
    )
    for imp in merged_imports {
      append_bytes(payload, encode_import(imp))
    }
    push_section(out, 10U, payload)
  }

  // Section 5: instances
  if instantiations.length() > 0 {
    let payload : Array[Byte] = []
    append_bytes(
      payload,
      encode_u32_leb128(instantiations.length().reinterpret_as_uint()),
    )
    for i in 0..<instantiations.length() {
      let inst = instantiations[i]
      let comp_order_idx = component_index_map[inst.component.pkg].reinterpret_as_int()
      let comp_idx = component_indices[comp_order_idx]
      let args : Array[InstantiateArgEntry] = []
      for arg in inst.args {
        match arg.source {
          ArgSource::Import(import_ref) => {
            let merged_idx = import_index_map[import_ref.import_name]
            let idx = merged_import_indices[merged_idx.reinterpret_as_int()]
            args.push(InstantiateArgEntry::{
              name: arg.name,
              kind: arg.kind,
              idx,
            })
          }
          ArgSource::Export(inst_name, export_name) => {
            let key = build_alias_key(inst_name, export_name)
            let idx = alias_map[key]
            args.push(InstantiateArgEntry::{
              name: arg.name,
              kind: arg.kind,
              idx,
            })
          }
          ArgSource::Instance(inst_name) => {
            let inst_pos = match
              require_instance_idx(instance_index_map, inst_name) {
              Ok(v) => v
              Err(e) => return Err(e)
            }
            let idx = instance_indices[inst_pos]
            args.push(InstantiateArgEntry::{
              name: arg.name,
              kind: arg.kind,
              idx,
            })
          }
        }
      }
      let inst_bytes = encode_instance(comp_idx, args)
      append_bytes(payload, inst_bytes)
    }
    push_section(out, 5U, payload)
  }

  // Section 6: aliases
  if alias_entries.length() > 0 {
    let payload : Array[Byte] = []
    append_bytes(
      payload,
      encode_u32_leb128(alias_entries.length().reinterpret_as_uint()),
    )
    for entry in alias_entries {
      let (inst_idx, name, kind) = entry
      append_bytes(payload, encode_alias(kind, inst_idx, name))
    }
    push_section(out, 6U, payload)
  }

  // Section 11: exports
  let export_payload : Array[Byte] = []
  let mut export_count = 0
  for exp in exports {
    match exp {
      ExportPlan::Item(plan) => {
        let inst_name = plan.inst
        let export_name = plan.name
        let inst_pos = match
          require_instance_idx(instance_index_map, inst_name) {
          Ok(v) => v
          Err(e) => return Err(e)
        }
        let inst_plan = instantiations[inst_pos]
        let export_detail = match
          find_export(inst_plan.component, export_name, true) {
          Ok(v) => v
          Err(e) => return Err(e)
        }
        let key = build_alias_key(inst_name, export_name)
        let idx = alias_map[key]
        let export_name_bytes = match plan.as_name {
          Some(as_name) => @utf8.encode(as_name)
          None => export_detail.name
        }
        append_bytes(
          export_payload,
          encode_export(export_name_bytes, export_detail.kind, idx),
        )
        export_count = export_count + 1
      }
      ExportPlan::All(inst_name) => {
        let inst_pos = match
          require_instance_idx(instance_index_map, inst_name) {
          Ok(v) => v
          Err(e) => return Err(e)
        }
        let inst_plan = instantiations[inst_pos]
        for name, export_detail in inst_plan.component.export_detail_map {
          let key = build_alias_key(inst_name, name)
          let idx = alias_map[key]
          append_bytes(
            export_payload,
            encode_export(export_detail.name, export_detail.kind, idx),
          )
          export_count = export_count + 1
        }
      }
    }
  }
  if export_count > 0 {
    let payload : Array[Byte] = []
    append_bytes(payload, encode_u32_leb128(export_count.reinterpret_as_uint()))
    append_bytes(payload, export_payload)
    push_section(out, 11U, payload)
  }
  let result = Bytes::from_array(out)
  match doc.targets {
    Some(target) => {
      let wit_dir = base_dir + "/wit"
      match @wit.resolve_path(wit_dir, world=target) {
        Ok(resolved) =>
          match check_component_targets(result, resolved) {
            Ok(_) => ()
            Err(e) =>
              if not(best_effort) {
                return Err("targets check failed: " + e)
              }
          }
        Err(e) =>
          if not(best_effort) {
            return Err("targets resolve failed: " + e.to_string())
          }
      }
    }
    None => ()
  }
  Ok(result)
}

///|
pub fn resolve_wac_summary(
  source : String,
  base_dir : String,
  best_effort? : Bool = false,
) -> Result[WacResolveSummary, String] {
  let doc = match parse_wac(source) {
    Ok(v) => v
    Err(e) => return Err(e.to_string())
  }
  let (instantiations, exports) = match
    resolve_wac(doc, base_dir, best_effort) {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let components : Array[String] = []
  let component_seen : Map[String, Bool] = {}
  for inst in instantiations {
    let pkg = inst.component.pkg
    if not(component_seen.contains(pkg)) {
      component_seen.set(pkg, true)
      components.push(pkg)
    }
  }
  let import_names : Array[String] = []
  let import_seen : Map[String, Bool] = {}
  for inst in instantiations {
    for arg in inst.args {
      match arg.source {
        ArgSource::Import(import_ref) =>
          if not(import_seen.contains(import_ref.import_name)) {
            import_seen.set(import_ref.import_name, true)
            import_names.push(import_ref.import_name)
          }
        ArgSource::Instance(_) => ()
        _ => ()
      }
    }
  }
  let inst_summaries : Array[WacInstantiationSummary] = []
  for inst in instantiations {
    let args : Array[String] = []
    for arg in inst.args {
      match arg.source {
        ArgSource::Import(import_ref) =>
          args.push("import:" + import_ref.import_name)
        ArgSource::Export(inst_name, export_name) =>
          args.push("export:" + inst_name + "." + export_name)
        ArgSource::Instance(inst_name) => args.push("instance:" + inst_name)
      }
    }
    inst_summaries.push({ name: inst.name, component: inst.component.pkg, args })
  }
  let export_list : Array[String] = []
  for exp in exports {
    match exp {
      ExportPlan::Item(plan) => {
        let base = plan.inst + "." + plan.name
        let entry = match plan.as_name {
          Some(as_name) => base + " as " + as_name
          None => base
        }
        export_list.push(entry)
      }
      ExportPlan::All(inst_name) => export_list.push(inst_name + ".*")
    }
  }
  Ok({
    pkg: doc.pkg,
    components,
    instantiations: inst_summaries,
    exports: export_list,
    imports: import_names,
  })
}

///|
pub fn compose_wac_file(
  path : String,
  best_effort? : Bool = false,
  dce? : Bool = false,
) -> Result[Bytes, String] {
  let source = @fs.read_file_to_string(path) catch {
    _ => return Err("failed to read: " + path)
  }
  let base_dir = dirname(path)
  compose_wac_source(source, base_dir, best_effort~, dce~)
}
