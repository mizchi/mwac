///|
// NOTE: moon-component extension (upstream wac has no DCE). This prunes
// unused instances based on export reachability only.
fn collect_inst_dependencies(inst : InstantiationPlan) -> Array[String] {
  let deps : Array[String] = []
  for arg in inst.args {
    match arg.source {
      ArgSource::Export(inst_name, _) => deps.push(inst_name)
      ArgSource::Instance(inst_name) => deps.push(inst_name)
      _ => ()
    }
  }
  deps
}

///|
fn compute_reachable_instances(
  instantiations : Array[InstantiationPlan],
  exports : Array[ExportPlan],
) -> Map[String, Bool] {
  let deps_map : Map[String, Array[String]] = {}
  for inst in instantiations {
    deps_map.set(inst.name, collect_inst_dependencies(inst))
  }
  let queue : Array[String] = []
  let reachable : Map[String, Bool] = {}
  for exp in exports {
    match exp {
      ExportPlan::Item(plan) =>
        if not(reachable.contains(plan.inst)) {
          reachable.set(plan.inst, true)
          queue.push(plan.inst)
        }
      ExportPlan::All(inst_name) =>
        if not(reachable.contains(inst_name)) {
          reachable.set(inst_name, true)
          queue.push(inst_name)
        }
    }
  }
  let mut i = 0
  while i < queue.length() {
    let name = queue[i]
    i = i + 1
    match deps_map.get(name) {
      Some(deps) =>
        for dep in deps {
          if not(reachable.contains(dep)) {
            reachable.set(dep, true)
            queue.push(dep)
          }
        }
      None => ()
    }
  }
  reachable
}

///|
fn dce_wac_plans(
  instantiations : Array[InstantiationPlan],
  exports : Array[ExportPlan],
) -> (Array[InstantiationPlan], Array[ExportPlan]) {
  let reachable = compute_reachable_instances(instantiations, exports)
  let kept_insts : Array[InstantiationPlan] = []
  for inst in instantiations {
    if reachable.contains(inst.name) {
      kept_insts.push(inst)
    }
  }
  let kept_exports : Array[ExportPlan] = []
  for exp in exports {
    match exp {
      ExportPlan::Item(plan) =>
        if reachable.contains(plan.inst) {
          kept_exports.push(exp)
        }
      ExportPlan::All(inst_name) =>
        if reachable.contains(inst_name) {
          kept_exports.push(exp)
        }
    }
  }
  (kept_insts, kept_exports)
}
