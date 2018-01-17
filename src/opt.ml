open Llvm_scalar_opts
open Llvm_vectorize
open Llvm_ipo

exception OptimizationError

type opt_level = O0 | O1 | O2 | OF

type scalar_opts

let scalar_optimizations = [
  (add_aggressive_dce, "add_aggressive_dce");
  (add_alignment_from_assumptions, "add_alignment_from_assumptions");
  (add_cfg_simplification, "add_cfg_simplification");
  (add_dead_store_elimination, "add_dead_store_elimination");
  (add_scalarizer, "add_scalarizer");
  (add_merged_load_store_motion, "add_merged_load_store_motion");
  (add_gvn, "add_gvn");
  (add_ind_var_simplification, "add_ind_var_simplification");
  (add_instruction_combination, "add_instruction_combination");
  (add_jump_threading, "add_jump_threading");
  (add_licm, "add_licm");
  (add_loop_deletion, "add_loop_deletion");
  (add_loop_idiom, "add_loop_idiom");
  (add_loop_rotation, "add_loop_rotation");
  (add_loop_reroll, "add_loop_reroll");
  (add_loop_unroll, "add_loop_unroll");
  (add_loop_unswitch, "add_loop_unswitch");
  (add_memcpy_opt, "add_memcpy_opt");
  (add_partially_inline_lib_calls, "add_partially_inline_lib_calls");
  (add_lower_switch, "add_lower_switch");
  (add_memory_to_register_promotion, "add_memory_to_register_promotion");
  (add_reassociation, "add_reassociation");
  (add_sccp, "add_sccp");
  (add_scalar_repl_aggregation, "add_scalar_repl_aggregation");
  (add_scalar_repl_aggregation_ssa, "add_scalar_repl_aggregation_ssa");
  (*add_scalar_repl_aggregation_with_threshold; *)
  (add_lib_call_simplification, "add_lib_call_simplification");
  (add_tail_call_elimination, "add_tail_call_elimination");
  (add_constant_propagation, "add_constant_propagation");
  (add_memory_to_register_demotion, "add_memory_to_register_demotion");
  (add_verifier, "add_verifier");
  (add_correlated_value_propagation, "add_correlated_value_propagation");
  (add_early_cse, "add_early_cse");
  (add_lower_expect_intrinsic, "add_lower_expect_intrinsic");
  (add_type_based_alias_analysis, "add_type_based_alias_analysis");
  (add_scoped_no_alias_alias_analysis, "add_scoped_no_alias_alias_analysis");
  (add_basic_alias_analysis, "add_basic_alias_analysis");
]

let vector_optimizations = [
  (add_bb_vectorize, "add_bb_vectorize");
  (add_loop_vectorize, "add_loop_vectorize");
  (add_slp_vectorize, "add_slp_vectorize");
]

let ipo_optimizations = [
  (add_argument_promotion, "add_argument_promotion");
  (add_constant_merge, "add_constant_merge");
  (add_dead_arg_elimination, "add_dead_arg_elimination");
  (add_function_attrs, "add_function_attrs");
  (add_function_inlining, "add_function_inlining");
  (add_always_inliner, "add_always_inliner");
  (add_global_dce, "add_global_dce");
  (add_global_optimizer, "add_global_optimizer");
  (add_ipc_propagation, "add_ipc_propagation");
  (add_prune_eh, "add_prune_eh");
  (add_ipsccp, "add_ipsccp");
  (*add_internalize;*)
  (add_strip_dead_prototypes, "add_strip_dead_prototypes");
  (*(add_strip_symbols, "add_strip_symbols");*)
]

let create_pass_manager () = Llvm.PassManager.create ()

let run_optimization_pipeline pm llmod = Llvm.PassManager.run_module llmod pm

let add_optimization opt pm = opt pm

let print_errors errors =
  Hashtbl.iter
  (fun (des,det) pass ->
    Log.error "%s" 
      (Verify.show_checkerstatus (Verify.Error(pass,des,det))))
  errors

let run_and_verify_opt llmod (opt, name) =
  let llmod_copy = Llvm_transform_utils.clone_module llmod in
  let pm = create_pass_manager () in
  add_optimization opt pm;
  let errors = Hashtbl.create 100 in
  begin
  match run_optimization_pipeline pm llmod with
    | false -> Log.error "Optimization had no effect"
    | true -> Verify.verify errors name llmod
  end;
  match Hashtbl.length errors with
    | 0 -> Log.info "No errors found for optimization `%s`" name; llmod,errors
    | n -> Log.error "Found %d errors with opt `%s`" n name; 
           llmod_copy,errors

let run_fact_pipeline llmod =
  let opts = scalar_optimizations
    @ vector_optimizations
    @ ipo_optimizations in
  let run_and_verify_opt' llmod opt =
    let llmod,_ = run_and_verify_opt llmod opt in
    llmod in
  List.fold_left run_and_verify_opt' llmod opts

let run_optimizations opt_level llmodule =
  let pmb = Llvm_passmgr_builder.create () in
  let opt_level' =
    match opt_level with 
      | O0 -> Some 0
      | O1 -> Some 1
      | O2 -> Some 2
      | OF -> None in
  match opt_level' with
    | None ->
      Log.info "Running custom FaCT optimization pipeline";
      run_fact_pipeline llmodule
    | Some l ->
      Log.info "Optimizing code at O%d" l;
      Llvm_passmgr_builder.set_opt_level l pmb;
      let pm = Llvm.PassManager.create () in
      Llvm_passmgr_builder.populate_module_pass_manager pm pmb;
      begin match Llvm.PassManager.run_module llmodule pm with
        | true -> ()
        | false -> Log.info "Optimization pass had no effect..." end;
      llmodule

let verify_some_opts llmod passes =
  let opts = scalar_optimizations
    @ vector_optimizations
    @ ipo_optimizations in
  let find_opt pass acc (opt,name) =
    if String.equal name pass then Some (opt,name) else acc in
  let print_optimizations () =
    let str = String.concat ", " (List.map (fun (_,pass) -> pass) opts) in
    Log.error "Possible optimizations: %s" str in
  let opts_to_run =
    List.map (fun pass -> (List.fold_left (find_opt pass) None opts)) passes in
  let all_opts_exist =
    List.fold_left
      (fun acc opt -> match opt with 
        | None -> false | Some _ -> acc)
      true
      opts_to_run in
  let run_and_verify_opt' name opt =
    Log.info "Running and verifying optimzation `%s`" name;
    let _,errors = run_and_verify_opt llmod opt in
    print_errors errors in

  match all_opts_exist with
    | false ->
      Log.error "Optimization does not exist";
      print_optimizations ();
      raise OptimizationError
    | true ->
      let opts_to_run' =
        List.map (fun opt -> match opt with | Some o -> o | None -> raise OptimizationError)
                 opts_to_run in
      List.iter2 run_and_verify_opt' passes opts_to_run'

let verify_opts llmod =
  Log.info "\n\n";
  let verify_opt errors llmod opt name =
    Log.info "Verifying `%s`" name;
    let pm = create_pass_manager () in
    add_optimization opt pm;
    match run_optimization_pipeline pm llmod with
      | true  -> Verify.verify errors name llmod
      | false -> () in

  let opts = scalar_optimizations
            @ vector_optimizations
            @ ipo_optimizations in

  let errors = Hashtbl.create 100 in

  (* Run the checkers for each optimization *)
  List.iter
    (fun (opt,name) -> (verify_opt errors llmod opt name))
    opts;
  
  (* Print the results of all the errors found *)
  print_errors errors;

  Log.info "\n\n";
  true