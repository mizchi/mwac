///|
fn inline_wit_source(ty : WacImportType) -> (String, String) {
  let inline_name = "inline_import"
  let (source, name) = match ty {
    WacImportType::InlineInterface(body) => {
      let src = "package wac:inline;\n" +
        "world inline {\n" +
        "  import " +
        inline_name +
        ": interface " +
        body +
        "\n" +
        "}\n"
      (src, inline_name)
    }
    WacImportType::InlineFunc(sig) => {
      let src = "package wac:inline;\n" +
        "world inline {\n" +
        "  import " +
        inline_name +
        ": " +
        sig +
        ";\n" +
        "}\n"
      (src, inline_name)
    }
    _ => ("", inline_name)
  }
  (source, name)
}

///|
fn resolve_inline_wit(
  ty : WacImportType,
) -> Result[(@wit.Resolve, @wit.RWorld, String), String] {
  let (source, inline_name) = inline_wit_source(ty)
  let resolved = match @wit.resolve(source) {
    Ok(v) => v
    Err(e) => return Err("inline type parse error: " + e.to_string())
  }
  if resolved.worlds.length() == 0 {
    return Err("inline type parse error: missing world")
  }
  let world = resolved.worlds[0]
  Ok((resolved, world, inline_name))
}

///|
fn check_inline_import_type(
  detail : ComponentDetail,
  import_name : String,
  import_detail : ComponentImportDetail,
  ty : WacImportType,
  best_effort : Bool,
) -> Result[Unit, String] {
  match ty {
    WacImportType::InlineInterface(_) | WacImportType::InlineFunc(_) => ()
    _ => return Ok(())
  }
  let (inline_res, inline_world, inline_name) = match resolve_inline_wit(ty) {
    Ok(v) => v
    Err(e) => return if best_effort { Ok(()) } else { Err(e) }
  }
  let item = match inline_world.imports.get(inline_name) {
    Some(v) => v
    None =>
      return if best_effort {
        Ok(())
      } else {
        Err("inline import item missing")
      }
  }
  let global_space = build_global_space(detail.types)
  let instance_cache : Map[UInt, InstanceExportSet] = {}
  let ctx = TypeResolveContext::{ detail, global_space, instance_cache }
  let result = match item {
    @wit.RWorldItem::Interface(iface_ref) => {
      if import_detail.kind != ExternKind::Instance {
        return if best_effort {
          Ok(())
        } else {
          Err("inline import `\{import_name}` expects instance")
        }
      }
      let iface = inline_res.interfaces[iface_ref.id]
      let errors : Array[String] = []
      match
        resolve_instance_exports_from_type_ref(
          detail,
          import_detail.type_ref,
          global_space,
        ) {
        Ok(export_set) =>
          check_interface(
            iface,
            export_set,
            inline_res,
            ctx,
            "inline import `\{import_name}`",
            errors,
          )
        Err(e) => errors.push("inline import `\{import_name}`: " + e)
      }
      if errors.length() > 0 {
        Err(errors.join("\n"))
      } else {
        Ok(())
      }
    }
    @wit.RWorldItem::Function(func) => {
      if import_detail.kind != ExternKind::Func {
        return if best_effort {
          Ok(())
        } else {
          Err("inline import `\{import_name}` expects func")
        }
      }
      match
        resolve_func_type_in_space(ctx, global_space, import_detail.type_ref) {
        Some(resolved) =>
          match
            check_func_signature(import_name, func, resolved, inline_res, ctx) {
            Ok(_) => Ok(())
            Err(e) => Err("inline import `\{import_name}`: " + e)
          }
        None => Err("inline import `\{import_name}`: not a function type")
      }
    }
    @wit.RWorldItem::Type(_) => Ok(())
  }
  match result {
    Ok(_) => Ok(())
    Err(e) => if best_effort { Ok(()) } else { Err(e) }
  }
}
