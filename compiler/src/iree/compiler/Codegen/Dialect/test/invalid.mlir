// RUN: iree-opt --split-input-file --verify-diagnostics %s

module {
  func.func @export_config_invalid_type() attributes {
    // expected-error @+1 {{expected workgroup size to contain values of index type}}
    export_config = #iree_codegen.export_config<workgroup_size = [4, 1]>
  } {
    return
  }
}

// -----

module {
  func.func @export_config_invalid_type() attributes {
    // expected-error @+1 {{expected workgroup size to have atmost 3 entries}}
    export_config = #iree_codegen.export_config<workgroup_size = [4: index, 1: index, 1: index, 1: index]>
  } {
    return
  }
}
