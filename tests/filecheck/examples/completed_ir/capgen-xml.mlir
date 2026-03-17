// Test the completed MLIR IR (frontend + optimizer, no Fortran backend) for
// the capgen example.  Two suites (ddt_suite, temp_suite) with DDT arguments
// and optional entry points.
//
// RUN: python3 -m xdsl_ccpp.frontend.ccpp_xml --suites examples/capgen/ddt_suite.xml,examples/capgen/temp_suite.xml --scheme-files examples/capgen/make_ddt.meta,examples/capgen/environ_conditions.meta,examples/capgen/setup_coeffs.meta,examples/capgen/temp_set.meta,examples/capgen/temp_calc_adjust.meta,examples/capgen/temp_adjust.meta --host-files examples/capgen/test_host_data.meta,examples/capgen/test_host_mod.meta,examples/capgen/test_host.meta | python3 -m xdsl_ccpp.tools.ccpp_opt -p generate-meta-cap,generate-meta-kinds,generate-suite-cap,generate-ccpp-cap,generate-kinds,strip-ccpp | python3 -m filecheck %s

// CHECK:       builtin.module {
// CHECK-LABEL:   builtin.module @temp_suite_cap {
// CHECK:           "llvm.mlir.global"() <{global_type = !llvm.array<16 x i8>, sym_name = "ccpp_suite_state", linkage = #llvm.linkage<"internal">, addr_space = 0 : i32, value = "uninitialized"}> ({
// CHECK-NEXT:      }) : () -> ()
// CHECK-NEXT:      "llvm.mlir.global"() <{global_type = !llvm.array<16 x i8>, sym_name = "const_in_time_step", linkage = #llvm.linkage<"internal">, addr_space = 0 : i32, constant, value = "in_time_step"}> ({
// CHECK-NEXT:      }) : () -> ()
// CHECK-NEXT:      "llvm.mlir.global"() <{global_type = !llvm.array<16 x i8>, sym_name = "const_initialized", linkage = #llvm.linkage<"internal">, addr_space = 0 : i32, constant, value = "initialized"}> ({
// CHECK-NEXT:      }) : () -> ()
// CHECK-NEXT:      "llvm.mlir.global"() <{global_type = !llvm.array<16 x i8>, sym_name = "const_uninitialized", linkage = #llvm.linkage<"internal">, addr_space = 0 : i32, constant, value = "uninitialized"}> ({
// CHECK-NEXT:      }) : () -> ()
// CHECK-LABEL:     func.func public @temp_suite_suite_initialize(%temp_inc_in : memref<!ccpp_utils.real_kind<"kind_phys">>, %fudge : memref<!ccpp_utils.real_kind<"kind_phys">>) -> (memref<!ccpp_utils.real_kind<"kind_phys">>, memref<512xi8>, memref<i32>) {
// CHECK:             %temp_inc_set = "memref.alloca"() <{operandSegmentSizes = array<i32: 0, 0>}> : () -> memref<!ccpp_utils.real_kind<"kind_phys">>
// CHECK-NEXT:        %errmsg = "memref.alloca"() <{operandSegmentSizes = array<i32: 0, 0>}> : () -> memref<512xi8>
// CHECK-NEXT:        %errflg = "memref.alloca"() <{operandSegmentSizes = array<i32: 0, 0>}> : () -> memref<i32>
// CHECK-NEXT:        %0 = arith.constant 0 : i32
// CHECK-NEXT:        memref.store %0, %errflg[] : memref<i32>
// CHECK-NEXT:        %1 = "llvm.mlir.addressof"() <{global_name = @const_uninitialized}> : () -> !llvm.ptr
// CHECK-NEXT:        %2 = "llvm.load"(%1) <{ordering = 0 : i64}> : (!llvm.ptr) -> !llvm.array<16 x i8>
// CHECK-NEXT:        %3 = "llvm.mlir.addressof"() <{global_name = @ccpp_suite_state}> : () -> !llvm.ptr
// CHECK-NEXT:        %4 = "llvm.load"(%3) <{ordering = 0 : i64}> : (!llvm.ptr) -> !llvm.array<16 x i8>
// CHECK-NEXT:        %5 = "ccpp_utils.strcmp"(%2, %4) <{length = 13 : i64}> : (!llvm.array<16 x i8>, !llvm.array<16 x i8>) -> i1
// CHECK-NEXT:        %6 = arith.constant true
// CHECK-NEXT:        %7 = arith.xori %5, %6 : i1
// CHECK-NEXT:        scf.if %7 {
// CHECK-NEXT:          %8 = "ccpp_utils.trim"(%4) : (!llvm.array<16 x i8>) -> !llvm.array<16 x i8>
// CHECK-NEXT:          "ccpp_utils.write_errmsg"(%errmsg, %8) <{prefix = "Invalid initial CCPP state, '", suffix = "' in temp_suite_initialize"}> : (memref<512xi8>, !llvm.array<16 x i8>) -> ()
// CHECK-NEXT:          %9 = arith.constant 1 : i32
// CHECK-NEXT:          memref.store %9, %errflg[] : memref<i32>
// CHECK-NEXT:        }
// CHECK-NEXT:        %10 = arith.constant 0 : i32
// CHECK-NEXT:        %11 = arith.cmpi eq, %12, %10 : i32
// CHECK-NEXT:        %12 = memref.load %errflg[] : memref<i32>
// CHECK-NEXT:        scf.if %11 {
// CHECK-NEXT:          %13, %14, %15 = func.call @temp_set_init(%temp_inc_in, %fudge) : (memref<!ccpp_utils.real_kind<"kind_phys">>, memref<!ccpp_utils.real_kind<"kind_phys">>) -> (memref<!ccpp_utils.real_kind<"kind_phys">>, memref<512xi8>, memref<i32>)
// CHECK-NEXT:          "memref.copy"(%13, %temp_inc_set) : (memref<!ccpp_utils.real_kind<"kind_phys">>, memref<!ccpp_utils.real_kind<"kind_phys">>) -> ()
// CHECK-NEXT:          "memref.copy"(%14, %errmsg) : (memref<512xi8>, memref<512xi8>) -> ()
// CHECK-NEXT:          "memref.copy"(%15, %errflg) : (memref<i32>, memref<i32>) -> ()
// CHECK-NEXT:        }
// CHECK-NEXT:        %16 = arith.constant 0 : i32
// CHECK-NEXT:        %17 = arith.cmpi eq, %18, %16 : i32
// CHECK-NEXT:        %18 = memref.load %errflg[] : memref<i32>
// CHECK-NEXT:        scf.if %17 {
// CHECK-NEXT:          %19, %20 = func.call @temp_calc_adjust_init() : () -> (memref<512xi8>, memref<i32>)
// CHECK-NEXT:          "memref.copy"(%19, %errmsg) : (memref<512xi8>, memref<512xi8>) -> ()
// CHECK-NEXT:          "memref.copy"(%20, %errflg) : (memref<i32>, memref<i32>) -> ()
// CHECK-NEXT:        }
// CHECK-NEXT:        %21 = arith.constant 0 : i32
// CHECK-NEXT:        %22 = arith.cmpi eq, %23, %21 : i32
// CHECK-NEXT:        %23 = memref.load %errflg[] : memref<i32>
// CHECK-NEXT:        scf.if %22 {
// CHECK-NEXT:          %24, %25 = func.call @temp_adjust_init() : () -> (memref<512xi8>, memref<i32>)
// CHECK-NEXT:          "memref.copy"(%24, %errmsg) : (memref<512xi8>, memref<512xi8>) -> ()
// CHECK-NEXT:          "memref.copy"(%25, %errflg) : (memref<i32>, memref<i32>) -> ()
// CHECK-NEXT:        }
// CHECK-NEXT:        %26 = "llvm.mlir.addressof"() <{global_name = @const_initialized}> : () -> !llvm.ptr
// CHECK-NEXT:        %27 = "llvm.load"(%26) <{ordering = 0 : i64}> : (!llvm.ptr) -> !llvm.array<16 x i8>
// CHECK-NEXT:        %28 = "llvm.mlir.addressof"() <{global_name = @ccpp_suite_state}> : () -> !llvm.ptr
// CHECK-NEXT:        "llvm.store"(%27, %28) <{ordering = 0 : i64}> : (!llvm.array<16 x i8>, !llvm.ptr) -> ()
// CHECK-NEXT:        func.return %temp_inc_set, %errmsg, %errflg : memref<!ccpp_utils.real_kind<"kind_phys">>, memref<512xi8>, memref<i32>
// CHECK-NEXT:      }
// CHECK-LABEL:     func.func public @temp_suite_suite_finalize() -> (memref<512xi8>, memref<i32>) {
// CHECK:             %errmsg = "memref.alloca"() <{operandSegmentSizes = array<i32: 0, 0>}> : () -> memref<512xi8>
// CHECK-NEXT:        %errflg = "memref.alloca"() <{operandSegmentSizes = array<i32: 0, 0>}> : () -> memref<i32>
// CHECK-NEXT:        %0 = arith.constant 0 : i32
// CHECK-NEXT:        memref.store %0, %errflg[] : memref<i32>
// CHECK-NEXT:        %1 = "llvm.mlir.addressof"() <{global_name = @const_initialized}> : () -> !llvm.ptr
// CHECK-NEXT:        %2 = "llvm.load"(%1) <{ordering = 0 : i64}> : (!llvm.ptr) -> !llvm.array<16 x i8>
// CHECK-NEXT:        %3 = "llvm.mlir.addressof"() <{global_name = @ccpp_suite_state}> : () -> !llvm.ptr
// CHECK-NEXT:        %4 = "llvm.load"(%3) <{ordering = 0 : i64}> : (!llvm.ptr) -> !llvm.array<16 x i8>
// CHECK-NEXT:        %5 = "ccpp_utils.strcmp"(%2, %4) <{length = 11 : i64}> : (!llvm.array<16 x i8>, !llvm.array<16 x i8>) -> i1
// CHECK-NEXT:        %6 = arith.constant true
// CHECK-NEXT:        %7 = arith.xori %5, %6 : i1
// CHECK-NEXT:        scf.if %7 {
// CHECK-NEXT:          %8 = "ccpp_utils.trim"(%4) : (!llvm.array<16 x i8>) -> !llvm.array<16 x i8>
// CHECK-NEXT:          "ccpp_utils.write_errmsg"(%errmsg, %8) <{prefix = "Invalid initial CCPP state, '", suffix = "' in temp_suite_finalize"}> : (memref<512xi8>, !llvm.array<16 x i8>) -> ()
// CHECK-NEXT:          %9 = arith.constant 1 : i32
// CHECK-NEXT:          memref.store %9, %errflg[] : memref<i32>
// CHECK-NEXT:        }
// CHECK-NEXT:        %10 = arith.constant 0 : i32
// CHECK-NEXT:        %11 = arith.cmpi eq, %12, %10 : i32
// CHECK-NEXT:        %12 = memref.load %errflg[] : memref<i32>
// CHECK-NEXT:        scf.if %11 {
// CHECK-NEXT:          %13, %14 = func.call @temp_set_finalize() : () -> (memref<512xi8>, memref<i32>)
// CHECK-NEXT:          "memref.copy"(%13, %errmsg) : (memref<512xi8>, memref<512xi8>) -> ()
// CHECK-NEXT:          "memref.copy"(%14, %errflg) : (memref<i32>, memref<i32>) -> ()
// CHECK-NEXT:        }
// CHECK-NEXT:        %15 = arith.constant 0 : i32
// CHECK-NEXT:        %16 = arith.cmpi eq, %17, %15 : i32
// CHECK-NEXT:        %17 = memref.load %errflg[] : memref<i32>
// CHECK-NEXT:        scf.if %16 {
// CHECK-NEXT:          %18, %19 = func.call @temp_calc_adjust_finalize() : () -> (memref<512xi8>, memref<i32>)
// CHECK-NEXT:          "memref.copy"(%18, %errmsg) : (memref<512xi8>, memref<512xi8>) -> ()
// CHECK-NEXT:          "memref.copy"(%19, %errflg) : (memref<i32>, memref<i32>) -> ()
// CHECK-NEXT:        }
// CHECK-NEXT:        %20 = arith.constant 0 : i32
// CHECK-NEXT:        %21 = arith.cmpi eq, %22, %20 : i32
// CHECK-NEXT:        %22 = memref.load %errflg[] : memref<i32>
// CHECK-NEXT:        scf.if %21 {
// CHECK-NEXT:          %23, %24 = func.call @temp_adjust_finalize() : () -> (memref<512xi8>, memref<i32>)
// CHECK-NEXT:          "memref.copy"(%23, %errmsg) : (memref<512xi8>, memref<512xi8>) -> ()
// CHECK-NEXT:          "memref.copy"(%24, %errflg) : (memref<i32>, memref<i32>) -> ()
// CHECK-NEXT:        }
// CHECK-NEXT:        %25 = "llvm.mlir.addressof"() <{global_name = @const_uninitialized}> : () -> !llvm.ptr
// CHECK-NEXT:        %26 = "llvm.load"(%25) <{ordering = 0 : i64}> : (!llvm.ptr) -> !llvm.array<16 x i8>
// CHECK-NEXT:        %27 = "llvm.mlir.addressof"() <{global_name = @ccpp_suite_state}> : () -> !llvm.ptr
// CHECK-NEXT:        "llvm.store"(%26, %27) <{ordering = 0 : i64}> : (!llvm.array<16 x i8>, !llvm.ptr) -> ()
// CHECK-NEXT:        func.return %errmsg, %errflg : memref<512xi8>, memref<i32>
// CHECK-NEXT:      }
// CHECK-LABEL:     func.func public @temp_suite_suite_physics(%col_start : memref<i32>, %col_end : memref<i32>, %lev : memref<i32>, %timestep : memref<!ccpp_utils.real_kind<"kind_phys">>, %temp_level : memref<?x?x!ccpp_utils.real_kind<"kind_phys">>, %temp_diag : memref<?x?x!ccpp_utils.real_kind<"kind_phys">>, %temp : memref<?x?x!ccpp_utils.real_kind<"kind_phys">>, %ps : memref<?x!ccpp_utils.real_kind<"kind_phys">>, %to_promote : memref<?x?x!ccpp_utils.real_kind<"kind_phys">>, %promote_pcnst : memref<?x!ccpp_utils.real_kind<"kind_phys">>, %slev_lbound : memref<i32>, %soil_levs : memref<?x!ccpp_utils.real_kind<"kind_phys">>, %var_array : memref<?x?x?x?x!ccpp_utils.real_kind<"kind_phys">>, %temp_calc : memref<?x!ccpp_utils.real_kind<"kind_phys">>, %temp_prev : memref<?x!ccpp_utils.real_kind<"kind_phys">>, %temp_layer : memref<?x!ccpp_utils.real_kind<"kind_phys">>, %qv : memref<?x!ccpp_utils.real_kind<"kind_phys">>) -> (memref<512xi8>, memref<i32>) {
// CHECK:             %errmsg = "memref.alloca"() <{operandSegmentSizes = array<i32: 0, 0>}> : () -> memref<512xi8>
// CHECK-NEXT:        %errflg = "memref.alloca"() <{operandSegmentSizes = array<i32: 0, 0>}> : () -> memref<i32>
// CHECK-NEXT:        %0 = arith.constant 0 : i32
// CHECK-NEXT:        memref.store %0, %errflg[] : memref<i32>
// CHECK-NEXT:        %ncol = "memref.alloca"() <{operandSegmentSizes = array<i32: 0, 0>}> : () -> memref<i32>
// CHECK-NEXT:        %1 = memref.load %col_start[] : memref<i32>
// CHECK-NEXT:        %2 = memref.load %col_end[] : memref<i32>
// CHECK-NEXT:        %3 = arith.subi %2, %1 : i32
// CHECK-NEXT:        %4 = arith.constant 1 : i32
// CHECK-NEXT:        %5 = arith.addi %3, %4 : i32
// CHECK-NEXT:        memref.store %5, %ncol[] : memref<i32>
// CHECK-NEXT:        %6 = "llvm.mlir.addressof"() <{global_name = @const_in_time_step}> : () -> !llvm.ptr
// CHECK-NEXT:        %7 = "llvm.load"(%6) <{ordering = 0 : i64}> : (!llvm.ptr) -> !llvm.array<16 x i8>
// CHECK-NEXT:        %8 = "llvm.mlir.addressof"() <{global_name = @ccpp_suite_state}> : () -> !llvm.ptr
// CHECK-NEXT:        %9 = "llvm.load"(%8) <{ordering = 0 : i64}> : (!llvm.ptr) -> !llvm.array<16 x i8>
// CHECK-NEXT:        %10 = "ccpp_utils.strcmp"(%7, %9) <{length = 12 : i64}> : (!llvm.array<16 x i8>, !llvm.array<16 x i8>) -> i1
// CHECK-NEXT:        %11 = arith.constant true
// CHECK-NEXT:        %12 = arith.xori %10, %11 : i1
// CHECK-NEXT:        scf.if %12 {
// CHECK-NEXT:          %13 = "ccpp_utils.trim"(%9) : (!llvm.array<16 x i8>) -> !llvm.array<16 x i8>
// CHECK-NEXT:          "ccpp_utils.write_errmsg"(%errmsg, %13) <{prefix = "Invalid initial CCPP state, '", suffix = "' in temp_suite_physics"}> : (memref<512xi8>, !llvm.array<16 x i8>) -> ()
// CHECK-NEXT:          %14 = arith.constant 1 : i32
// CHECK-NEXT:          memref.store %14, %errflg[] : memref<i32>
// CHECK-NEXT:        }
// CHECK-NEXT:        %15 = arith.constant 0 : i32
// CHECK-NEXT:        %16 = arith.cmpi eq, %17, %15 : i32
// CHECK-NEXT:        %17 = memref.load %errflg[] : memref<i32>
// CHECK-NEXT:        scf.if %16 {
// CHECK-NEXT:          %18, %19, %20, %21, %22, %23, %24, %25, %26 = func.call @temp_set_run(%ncol, %lev, %timestep, %temp_level, %temp_diag, %ps, %slev_lbound, %soil_levs, %var_array) : (memref<i32>, memref<i32>, memref<!ccpp_utils.real_kind<"kind_phys">>, memref<?x?x!ccpp_utils.real_kind<"kind_phys">>, memref<?x?x!ccpp_utils.real_kind<"kind_phys">>, memref<?x!ccpp_utils.real_kind<"kind_phys">>, memref<i32>, memref<?x!ccpp_utils.real_kind<"kind_phys">>, memref<?x?x?x?x!ccpp_utils.real_kind<"kind_phys">>) -> (memref<?x?x!ccpp_utils.real_kind<"kind_phys">>, memref<?x?x!ccpp_utils.real_kind<"kind_phys">>, memref<?x?x!ccpp_utils.real_kind<"kind_phys">>, memref<?x?x!ccpp_utils.real_kind<"kind_phys">>, memref<?x!ccpp_utils.real_kind<"kind_phys">>, memref<?x!ccpp_utils.real_kind<"kind_phys">>, memref<?x?x?x?x!ccpp_utils.real_kind<"kind_phys">>, memref<512xi8>, memref<i32>)
// CHECK-NEXT:          "memref.copy"(%18, %temp_level) : (memref<?x?x!ccpp_utils.real_kind<"kind_phys">>, memref<?x?x!ccpp_utils.real_kind<"kind_phys">>) -> ()
// CHECK-NEXT:          "memref.copy"(%19, %temp_diag) : (memref<?x?x!ccpp_utils.real_kind<"kind_phys">>, memref<?x?x!ccpp_utils.real_kind<"kind_phys">>) -> ()
// CHECK-NEXT:          "memref.copy"(%20, %temp) : (memref<?x?x!ccpp_utils.real_kind<"kind_phys">>, memref<?x?x!ccpp_utils.real_kind<"kind_phys">>) -> ()
// CHECK-NEXT:          "memref.copy"(%21, %to_promote) : (memref<?x?x!ccpp_utils.real_kind<"kind_phys">>, memref<?x?x!ccpp_utils.real_kind<"kind_phys">>) -> ()
// CHECK-NEXT:          "memref.copy"(%22, %promote_pcnst) : (memref<?x!ccpp_utils.real_kind<"kind_phys">>, memref<?x!ccpp_utils.real_kind<"kind_phys">>) -> ()
// CHECK-NEXT:          "memref.copy"(%23, %soil_levs) : (memref<?x!ccpp_utils.real_kind<"kind_phys">>, memref<?x!ccpp_utils.real_kind<"kind_phys">>) -> ()
// CHECK-NEXT:          "memref.copy"(%24, %var_array) : (memref<?x?x?x?x!ccpp_utils.real_kind<"kind_phys">>, memref<?x?x?x?x!ccpp_utils.real_kind<"kind_phys">>) -> ()
// CHECK-NEXT:          "memref.copy"(%25, %errmsg) : (memref<512xi8>, memref<512xi8>) -> ()
// CHECK-NEXT:          "memref.copy"(%26, %errflg) : (memref<i32>, memref<i32>) -> ()
// CHECK-NEXT:        }
// CHECK-NEXT:        %27 = arith.constant 0 : i32
// CHECK-NEXT:        %28 = arith.cmpi eq, %29, %27 : i32
// CHECK-NEXT:        %29 = memref.load %errflg[] : memref<i32>
// CHECK-NEXT:        scf.if %28 {
// CHECK-NEXT:          %30, %31, %32 = func.call @temp_calc_adjust_run(%ncol, %timestep, %temp_level) : (memref<i32>, memref<!ccpp_utils.real_kind<"kind_phys">>, memref<?x?x!ccpp_utils.real_kind<"kind_phys">>) -> (memref<?x!ccpp_utils.real_kind<"kind_phys">>, memref<512xi8>, memref<i32>)
// CHECK-NEXT:          "memref.copy"(%30, %temp_calc) : (memref<?x!ccpp_utils.real_kind<"kind_phys">>, memref<?x!ccpp_utils.real_kind<"kind_phys">>) -> ()
// CHECK-NEXT:          "memref.copy"(%31, %errmsg) : (memref<512xi8>, memref<512xi8>) -> ()
// CHECK-NEXT:          "memref.copy"(%32, %errflg) : (memref<i32>, memref<i32>) -> ()
// CHECK-NEXT:        }
// CHECK-NEXT:        %33 = arith.constant 0 : i32
// CHECK-NEXT:        %34 = arith.cmpi eq, %35, %33 : i32
// CHECK-NEXT:        %35 = memref.load %errflg[] : memref<i32>
// CHECK-NEXT:        scf.if %34 {
// CHECK-NEXT:          %36 = builtin.unrealized_conversion_cast %to_promote : memref<?x?x!ccpp_utils.real_kind<"kind_phys">> to memref<?x!ccpp_utils.real_kind<"kind_phys">>
// CHECK-NEXT:          %37, %38, %39, %40, %41 = func.call @temp_adjust_run(%ncol, %timestep, %temp_prev, %temp_layer, %qv, %ps, %36, %promote_pcnst) : (memref<i32>, memref<!ccpp_utils.real_kind<"kind_phys">>, memref<?x!ccpp_utils.real_kind<"kind_phys">>, memref<?x!ccpp_utils.real_kind<"kind_phys">>, memref<?x!ccpp_utils.real_kind<"kind_phys">>, memref<?x!ccpp_utils.real_kind<"kind_phys">>, memref<?x!ccpp_utils.real_kind<"kind_phys">>, memref<?x!ccpp_utils.real_kind<"kind_phys">>) -> (memref<?x!ccpp_utils.real_kind<"kind_phys">>, memref<?x!ccpp_utils.real_kind<"kind_phys">>, memref<?x!ccpp_utils.real_kind<"kind_phys">>, memref<512xi8>, memref<i32>)
// CHECK-NEXT:          "memref.copy"(%37, %temp_layer) : (memref<?x!ccpp_utils.real_kind<"kind_phys">>, memref<?x!ccpp_utils.real_kind<"kind_phys">>) -> ()
// CHECK-NEXT:          "memref.copy"(%38, %qv) : (memref<?x!ccpp_utils.real_kind<"kind_phys">>, memref<?x!ccpp_utils.real_kind<"kind_phys">>) -> ()
// CHECK-NEXT:          "memref.copy"(%39, %ps) : (memref<?x!ccpp_utils.real_kind<"kind_phys">>, memref<?x!ccpp_utils.real_kind<"kind_phys">>) -> ()
// CHECK-NEXT:          "memref.copy"(%40, %errmsg) : (memref<512xi8>, memref<512xi8>) -> ()
// CHECK-NEXT:          "memref.copy"(%41, %errflg) : (memref<i32>, memref<i32>) -> ()
// CHECK-NEXT:        }
// CHECK-NEXT:        func.return %errmsg, %errflg : memref<512xi8>, memref<i32>
// CHECK-NEXT:      }
// CHECK-LABEL:     func.func public @temp_suite_suite_timestep_initial() -> (memref<i32>, memref<512xi8>) {
// CHECK:             %errflg = "memref.alloca"() <{operandSegmentSizes = array<i32: 0, 0>}> : () -> memref<i32>
// CHECK-NEXT:        %errmsg = "memref.alloca"() <{operandSegmentSizes = array<i32: 0, 0>}> : () -> memref<512xi8>
// CHECK-NEXT:        %0 = arith.constant 0 : i32
// CHECK-NEXT:        memref.store %0, %errflg[] : memref<i32>
// CHECK-NEXT:        %1 = "llvm.mlir.addressof"() <{global_name = @const_initialized}> : () -> !llvm.ptr
// CHECK-NEXT:        %2 = "llvm.load"(%1) <{ordering = 0 : i64}> : (!llvm.ptr) -> !llvm.array<16 x i8>
// CHECK-NEXT:        %3 = "llvm.mlir.addressof"() <{global_name = @ccpp_suite_state}> : () -> !llvm.ptr
// CHECK-NEXT:        %4 = "llvm.load"(%3) <{ordering = 0 : i64}> : (!llvm.ptr) -> !llvm.array<16 x i8>
// CHECK-NEXT:        %5 = "ccpp_utils.strcmp"(%2, %4) <{length = 11 : i64}> : (!llvm.array<16 x i8>, !llvm.array<16 x i8>) -> i1
// CHECK-NEXT:        %6 = arith.constant true
// CHECK-NEXT:        %7 = arith.xori %5, %6 : i1
// CHECK-NEXT:        scf.if %7 {
// CHECK-NEXT:          %8 = "ccpp_utils.trim"(%4) : (!llvm.array<16 x i8>) -> !llvm.array<16 x i8>
// CHECK-NEXT:          "ccpp_utils.write_errmsg"(%errmsg, %8) <{prefix = "Invalid initial CCPP state, '", suffix = "' in temp_suite_timestep_initial"}> : (memref<512xi8>, !llvm.array<16 x i8>) -> ()
// CHECK-NEXT:          %9 = arith.constant 1 : i32
// CHECK-NEXT:          memref.store %9, %errflg[] : memref<i32>
// CHECK-NEXT:        }
// CHECK-NEXT:        %10 = "llvm.mlir.addressof"() <{global_name = @const_in_time_step}> : () -> !llvm.ptr
// CHECK-NEXT:        %11 = "llvm.load"(%10) <{ordering = 0 : i64}> : (!llvm.ptr) -> !llvm.array<16 x i8>
// CHECK-NEXT:        %12 = "llvm.mlir.addressof"() <{global_name = @ccpp_suite_state}> : () -> !llvm.ptr
// CHECK-NEXT:        "llvm.store"(%11, %12) <{ordering = 0 : i64}> : (!llvm.array<16 x i8>, !llvm.ptr) -> ()
// CHECK-NEXT:        func.return %errflg, %errmsg : memref<i32>, memref<512xi8>
// CHECK-NEXT:      }
// CHECK-LABEL:     func.func public @temp_suite_suite_timestep_final() -> (memref<i32>, memref<512xi8>) {
// CHECK:             %errflg = "memref.alloca"() <{operandSegmentSizes = array<i32: 0, 0>}> : () -> memref<i32>
// CHECK-NEXT:        %errmsg = "memref.alloca"() <{operandSegmentSizes = array<i32: 0, 0>}> : () -> memref<512xi8>
// CHECK-NEXT:        %0 = arith.constant 0 : i32
// CHECK-NEXT:        memref.store %0, %errflg[] : memref<i32>
// CHECK-NEXT:        %1 = "llvm.mlir.addressof"() <{global_name = @const_in_time_step}> : () -> !llvm.ptr
// CHECK-NEXT:        %2 = "llvm.load"(%1) <{ordering = 0 : i64}> : (!llvm.ptr) -> !llvm.array<16 x i8>
// CHECK-NEXT:        %3 = "llvm.mlir.addressof"() <{global_name = @ccpp_suite_state}> : () -> !llvm.ptr
// CHECK-NEXT:        %4 = "llvm.load"(%3) <{ordering = 0 : i64}> : (!llvm.ptr) -> !llvm.array<16 x i8>
// CHECK-NEXT:        %5 = "ccpp_utils.strcmp"(%2, %4) <{length = 12 : i64}> : (!llvm.array<16 x i8>, !llvm.array<16 x i8>) -> i1
// CHECK-NEXT:        %6 = arith.constant true
// CHECK-NEXT:        %7 = arith.xori %5, %6 : i1
// CHECK-NEXT:        scf.if %7 {
// CHECK-NEXT:          %8 = "ccpp_utils.trim"(%4) : (!llvm.array<16 x i8>) -> !llvm.array<16 x i8>
// CHECK-NEXT:          "ccpp_utils.write_errmsg"(%errmsg, %8) <{prefix = "Invalid initial CCPP state, '", suffix = "' in temp_suite_timestep_final"}> : (memref<512xi8>, !llvm.array<16 x i8>) -> ()
// CHECK-NEXT:          %9 = arith.constant 1 : i32
// CHECK-NEXT:          memref.store %9, %errflg[] : memref<i32>
// CHECK-NEXT:        }
// CHECK-NEXT:        %10 = "llvm.mlir.addressof"() <{global_name = @const_initialized}> : () -> !llvm.ptr
// CHECK-NEXT:        %11 = "llvm.load"(%10) <{ordering = 0 : i64}> : (!llvm.ptr) -> !llvm.array<16 x i8>
// CHECK-NEXT:        %12 = "llvm.mlir.addressof"() <{global_name = @ccpp_suite_state}> : () -> !llvm.ptr
// CHECK-NEXT:        "llvm.store"(%11, %12) <{ordering = 0 : i64}> : (!llvm.array<16 x i8>, !llvm.ptr) -> ()
// CHECK-NEXT:        func.return %errflg, %errmsg : memref<i32>, memref<512xi8>
// CHECK-NEXT:      }
// CHECK-LABEL:     func.func private @temp_set_init(memref<!ccpp_utils.real_kind<"kind_phys">>, memref<!ccpp_utils.real_kind<"kind_phys">>) -> (memref<!ccpp_utils.real_kind<"kind_phys">>, memref<512xi8>, memref<i32>)
// CHECK-LABEL:     func.func private @temp_calc_adjust_init() -> (memref<512xi8>, memref<i32>)
// CHECK-LABEL:     func.func private @temp_adjust_init() -> (memref<512xi8>, memref<i32>)
// CHECK-LABEL:     func.func private @temp_set_finalize() -> (memref<512xi8>, memref<i32>)
// CHECK-LABEL:     func.func private @temp_calc_adjust_finalize() -> (memref<512xi8>, memref<i32>)
// CHECK-LABEL:     func.func private @temp_adjust_finalize() -> (memref<512xi8>, memref<i32>)
// CHECK-LABEL:     func.func private @temp_set_run(memref<i32>, memref<i32>, memref<!ccpp_utils.real_kind<"kind_phys">>, memref<?x?x!ccpp_utils.real_kind<"kind_phys">>, memref<?x?x!ccpp_utils.real_kind<"kind_phys">>, memref<?x!ccpp_utils.real_kind<"kind_phys">>, memref<i32>, memref<?x!ccpp_utils.real_kind<"kind_phys">>, memref<?x?x?x?x!ccpp_utils.real_kind<"kind_phys">>) -> (memref<?x?x!ccpp_utils.real_kind<"kind_phys">>, memref<?x?x!ccpp_utils.real_kind<"kind_phys">>, memref<?x?x!ccpp_utils.real_kind<"kind_phys">>, memref<?x?x!ccpp_utils.real_kind<"kind_phys">>, memref<?x!ccpp_utils.real_kind<"kind_phys">>, memref<?x!ccpp_utils.real_kind<"kind_phys">>, memref<?x?x?x?x!ccpp_utils.real_kind<"kind_phys">>, memref<512xi8>, memref<i32>)
// CHECK-LABEL:     func.func private @temp_calc_adjust_run(memref<i32>, memref<!ccpp_utils.real_kind<"kind_phys">>, memref<?x?x!ccpp_utils.real_kind<"kind_phys">>) -> (memref<?x!ccpp_utils.real_kind<"kind_phys">>, memref<512xi8>, memref<i32>)
// CHECK-LABEL:     func.func private @temp_adjust_run(memref<i32>, memref<!ccpp_utils.real_kind<"kind_phys">>, memref<?x!ccpp_utils.real_kind<"kind_phys">>, memref<?x!ccpp_utils.real_kind<"kind_phys">>, memref<?x!ccpp_utils.real_kind<"kind_phys">>, memref<?x!ccpp_utils.real_kind<"kind_phys">>, memref<?x!ccpp_utils.real_kind<"kind_phys">>, memref<?x!ccpp_utils.real_kind<"kind_phys">>) -> (memref<?x!ccpp_utils.real_kind<"kind_phys">>, memref<?x!ccpp_utils.real_kind<"kind_phys">>, memref<?x!ccpp_utils.real_kind<"kind_phys">>, memref<512xi8>, memref<i32>)
// CHECK:         }
// CHECK-LABEL:   builtin.module @ddt_suite_cap {
// CHECK:           "llvm.mlir.global"() <{global_type = !llvm.array<16 x i8>, sym_name = "ccpp_suite_state", linkage = #llvm.linkage<"internal">, addr_space = 0 : i32, value = "uninitialized"}> ({
// CHECK-NEXT:      }) : () -> ()
// CHECK-NEXT:      "llvm.mlir.global"() <{global_type = !llvm.array<16 x i8>, sym_name = "const_in_time_step", linkage = #llvm.linkage<"internal">, addr_space = 0 : i32, constant, value = "in_time_step"}> ({
// CHECK-NEXT:      }) : () -> ()
// CHECK-NEXT:      "llvm.mlir.global"() <{global_type = !llvm.array<16 x i8>, sym_name = "const_initialized", linkage = #llvm.linkage<"internal">, addr_space = 0 : i32, constant, value = "initialized"}> ({
// CHECK-NEXT:      }) : () -> ()
// CHECK-NEXT:      "llvm.mlir.global"() <{global_type = !llvm.array<16 x i8>, sym_name = "const_uninitialized", linkage = #llvm.linkage<"internal">, addr_space = 0 : i32, constant, value = "uninitialized"}> ({
// CHECK-NEXT:      }) : () -> ()
// CHECK-LABEL:     func.func public @ddt_suite_suite_initialize(%nbox : memref<i32>, %o3 : memref<?x!ccpp_utils.real_kind<"kind_phys">>, %hno3 : memref<?x!ccpp_utils.real_kind<"kind_phys">>, %model_times : memref<?xi32>) -> (memref<!ccpp_utils.derived_type<"vmr_type">>, memref<512xi8>, memref<i32>, memref<i32>) {
// CHECK:             %vmr = "memref.alloca"() <{operandSegmentSizes = array<i32: 0, 0>}> : () -> memref<!ccpp_utils.derived_type<"vmr_type">>
// CHECK-NEXT:        %errmsg = "memref.alloca"() <{operandSegmentSizes = array<i32: 0, 0>}> : () -> memref<512xi8>
// CHECK-NEXT:        %errflg = "memref.alloca"() <{operandSegmentSizes = array<i32: 0, 0>}> : () -> memref<i32>
// CHECK-NEXT:        %ntimes = "memref.alloca"() <{operandSegmentSizes = array<i32: 0, 0>}> : () -> memref<i32>
// CHECK-NEXT:        %0 = arith.constant 0 : i32
// CHECK-NEXT:        memref.store %0, %errflg[] : memref<i32>
// CHECK-NEXT:        %1 = "llvm.mlir.addressof"() <{global_name = @const_uninitialized}> : () -> !llvm.ptr
// CHECK-NEXT:        %2 = "llvm.load"(%1) <{ordering = 0 : i64}> : (!llvm.ptr) -> !llvm.array<16 x i8>
// CHECK-NEXT:        %3 = "llvm.mlir.addressof"() <{global_name = @ccpp_suite_state}> : () -> !llvm.ptr
// CHECK-NEXT:        %4 = "llvm.load"(%3) <{ordering = 0 : i64}> : (!llvm.ptr) -> !llvm.array<16 x i8>
// CHECK-NEXT:        %5 = "ccpp_utils.strcmp"(%2, %4) <{length = 13 : i64}> : (!llvm.array<16 x i8>, !llvm.array<16 x i8>) -> i1
// CHECK-NEXT:        %6 = arith.constant true
// CHECK-NEXT:        %7 = arith.xori %5, %6 : i1
// CHECK-NEXT:        scf.if %7 {
// CHECK-NEXT:          %8 = "ccpp_utils.trim"(%4) : (!llvm.array<16 x i8>) -> !llvm.array<16 x i8>
// CHECK-NEXT:          "ccpp_utils.write_errmsg"(%errmsg, %8) <{prefix = "Invalid initial CCPP state, '", suffix = "' in ddt_suite_initialize"}> : (memref<512xi8>, !llvm.array<16 x i8>) -> ()
// CHECK-NEXT:          %9 = arith.constant 1 : i32
// CHECK-NEXT:          memref.store %9, %errflg[] : memref<i32>
// CHECK-NEXT:        }
// CHECK-NEXT:        %10 = arith.constant 0 : i32
// CHECK-NEXT:        %11 = arith.cmpi eq, %12, %10 : i32
// CHECK-NEXT:        %12 = memref.load %errflg[] : memref<i32>
// CHECK-NEXT:        scf.if %11 {
// CHECK-NEXT:          %13, %14, %15 = func.call @make_ddt_init(%nbox) : (memref<i32>) -> (memref<!ccpp_utils.derived_type<"vmr_type">>, memref<512xi8>, memref<i32>)
// CHECK-NEXT:          "memref.copy"(%13, %vmr) : (memref<!ccpp_utils.derived_type<"vmr_type">>, memref<!ccpp_utils.derived_type<"vmr_type">>) -> ()
// CHECK-NEXT:          "memref.copy"(%14, %errmsg) : (memref<512xi8>, memref<512xi8>) -> ()
// CHECK-NEXT:          "memref.copy"(%15, %errflg) : (memref<i32>, memref<i32>) -> ()
// CHECK-NEXT:        }
// CHECK-NEXT:        %16 = arith.constant 0 : i32
// CHECK-NEXT:        %17 = arith.cmpi eq, %18, %16 : i32
// CHECK-NEXT:        %18 = memref.load %errflg[] : memref<i32>
// CHECK-NEXT:        scf.if %17 {
// CHECK-NEXT:          %19, %20, %21, %22, %23, %24 = func.call @environ_conditions_init(%nbox) : (memref<i32>) -> (memref<?x!ccpp_utils.real_kind<"kind_phys">>, memref<?x!ccpp_utils.real_kind<"kind_phys">>, memref<i32>, memref<?xi32>, memref<512xi8>, memref<i32>)
// CHECK-NEXT:          "memref.copy"(%19, %o3) : (memref<?x!ccpp_utils.real_kind<"kind_phys">>, memref<?x!ccpp_utils.real_kind<"kind_phys">>) -> ()
// CHECK-NEXT:          "memref.copy"(%20, %hno3) : (memref<?x!ccpp_utils.real_kind<"kind_phys">>, memref<?x!ccpp_utils.real_kind<"kind_phys">>) -> ()
// CHECK-NEXT:          "memref.copy"(%21, %ntimes) : (memref<i32>, memref<i32>) -> ()
// CHECK-NEXT:          "memref.copy"(%22, %model_times) : (memref<?xi32>, memref<?xi32>) -> ()
// CHECK-NEXT:          "memref.copy"(%23, %errmsg) : (memref<512xi8>, memref<512xi8>) -> ()
// CHECK-NEXT:          "memref.copy"(%24, %errflg) : (memref<i32>, memref<i32>) -> ()
// CHECK-NEXT:        }
// CHECK-NEXT:        %25 = "llvm.mlir.addressof"() <{global_name = @const_initialized}> : () -> !llvm.ptr
// CHECK-NEXT:        %26 = "llvm.load"(%25) <{ordering = 0 : i64}> : (!llvm.ptr) -> !llvm.array<16 x i8>
// CHECK-NEXT:        %27 = "llvm.mlir.addressof"() <{global_name = @ccpp_suite_state}> : () -> !llvm.ptr
// CHECK-NEXT:        "llvm.store"(%26, %27) <{ordering = 0 : i64}> : (!llvm.array<16 x i8>, !llvm.ptr) -> ()
// CHECK-NEXT:        func.return %vmr, %errmsg, %errflg, %ntimes : memref<!ccpp_utils.derived_type<"vmr_type">>, memref<512xi8>, memref<i32>, memref<i32>
// CHECK-NEXT:      }
// CHECK-LABEL:     func.func public @ddt_suite_suite_finalize(%ntimes : memref<i32>, %model_times : memref<?xi32>) -> (memref<512xi8>, memref<i32>) {
// CHECK:             %errmsg = "memref.alloca"() <{operandSegmentSizes = array<i32: 0, 0>}> : () -> memref<512xi8>
// CHECK-NEXT:        %errflg = "memref.alloca"() <{operandSegmentSizes = array<i32: 0, 0>}> : () -> memref<i32>
// CHECK-NEXT:        %0 = arith.constant 0 : i32
// CHECK-NEXT:        memref.store %0, %errflg[] : memref<i32>
// CHECK-NEXT:        %1 = "llvm.mlir.addressof"() <{global_name = @const_initialized}> : () -> !llvm.ptr
// CHECK-NEXT:        %2 = "llvm.load"(%1) <{ordering = 0 : i64}> : (!llvm.ptr) -> !llvm.array<16 x i8>
// CHECK-NEXT:        %3 = "llvm.mlir.addressof"() <{global_name = @ccpp_suite_state}> : () -> !llvm.ptr
// CHECK-NEXT:        %4 = "llvm.load"(%3) <{ordering = 0 : i64}> : (!llvm.ptr) -> !llvm.array<16 x i8>
// CHECK-NEXT:        %5 = "ccpp_utils.strcmp"(%2, %4) <{length = 11 : i64}> : (!llvm.array<16 x i8>, !llvm.array<16 x i8>) -> i1
// CHECK-NEXT:        %6 = arith.constant true
// CHECK-NEXT:        %7 = arith.xori %5, %6 : i1
// CHECK-NEXT:        scf.if %7 {
// CHECK-NEXT:          %8 = "ccpp_utils.trim"(%4) : (!llvm.array<16 x i8>) -> !llvm.array<16 x i8>
// CHECK-NEXT:          "ccpp_utils.write_errmsg"(%errmsg, %8) <{prefix = "Invalid initial CCPP state, '", suffix = "' in ddt_suite_finalize"}> : (memref<512xi8>, !llvm.array<16 x i8>) -> ()
// CHECK-NEXT:          %9 = arith.constant 1 : i32
// CHECK-NEXT:          memref.store %9, %errflg[] : memref<i32>
// CHECK-NEXT:        }
// CHECK-NEXT:        %10 = arith.constant 0 : i32
// CHECK-NEXT:        %11 = arith.cmpi eq, %12, %10 : i32
// CHECK-NEXT:        %12 = memref.load %errflg[] : memref<i32>
// CHECK-NEXT:        scf.if %11 {
// CHECK-NEXT:          %13, %14 = func.call @environ_conditions_finalize(%ntimes, %model_times) : (memref<i32>, memref<?xi32>) -> (memref<512xi8>, memref<i32>)
// CHECK-NEXT:          "memref.copy"(%13, %errmsg) : (memref<512xi8>, memref<512xi8>) -> ()
// CHECK-NEXT:          "memref.copy"(%14, %errflg) : (memref<i32>, memref<i32>) -> ()
// CHECK-NEXT:        }
// CHECK-NEXT:        %15 = "llvm.mlir.addressof"() <{global_name = @const_uninitialized}> : () -> !llvm.ptr
// CHECK-NEXT:        %16 = "llvm.load"(%15) <{ordering = 0 : i64}> : (!llvm.ptr) -> !llvm.array<16 x i8>
// CHECK-NEXT:        %17 = "llvm.mlir.addressof"() <{global_name = @ccpp_suite_state}> : () -> !llvm.ptr
// CHECK-NEXT:        "llvm.store"(%16, %17) <{ordering = 0 : i64}> : (!llvm.array<16 x i8>, !llvm.ptr) -> ()
// CHECK-NEXT:        func.return %errmsg, %errflg : memref<512xi8>, memref<i32>
// CHECK-NEXT:      }
// CHECK-LABEL:     func.func public @ddt_suite_suite_physics(%cols : memref<i32>, %cole : memref<i32>, %O3 : memref<?x!ccpp_utils.real_kind<"kind_phys">>, %HNO3 : memref<?x!ccpp_utils.real_kind<"kind_phys">>, %vmr : memref<!ccpp_utils.derived_type<"vmr_type">>, %psurf : memref<?x!ccpp_utils.real_kind<"kind_phys">>) -> (memref<!ccpp_utils.derived_type<"vmr_type">>, memref<512xi8>, memref<i32>) {
// CHECK:             %errmsg = "memref.alloca"() <{operandSegmentSizes = array<i32: 0, 0>}> : () -> memref<512xi8>
// CHECK-NEXT:        %errflg = "memref.alloca"() <{operandSegmentSizes = array<i32: 0, 0>}> : () -> memref<i32>
// CHECK-NEXT:        %0 = arith.constant 0 : i32
// CHECK-NEXT:        memref.store %0, %errflg[] : memref<i32>
// CHECK-NEXT:        %1 = "llvm.mlir.addressof"() <{global_name = @const_in_time_step}> : () -> !llvm.ptr
// CHECK-NEXT:        %2 = "llvm.load"(%1) <{ordering = 0 : i64}> : (!llvm.ptr) -> !llvm.array<16 x i8>
// CHECK-NEXT:        %3 = "llvm.mlir.addressof"() <{global_name = @ccpp_suite_state}> : () -> !llvm.ptr
// CHECK-NEXT:        %4 = "llvm.load"(%3) <{ordering = 0 : i64}> : (!llvm.ptr) -> !llvm.array<16 x i8>
// CHECK-NEXT:        %5 = "ccpp_utils.strcmp"(%2, %4) <{length = 12 : i64}> : (!llvm.array<16 x i8>, !llvm.array<16 x i8>) -> i1
// CHECK-NEXT:        %6 = arith.constant true
// CHECK-NEXT:        %7 = arith.xori %5, %6 : i1
// CHECK-NEXT:        scf.if %7 {
// CHECK-NEXT:          %8 = "ccpp_utils.trim"(%4) : (!llvm.array<16 x i8>) -> !llvm.array<16 x i8>
// CHECK-NEXT:          "ccpp_utils.write_errmsg"(%errmsg, %8) <{prefix = "Invalid initial CCPP state, '", suffix = "' in ddt_suite_physics"}> : (memref<512xi8>, !llvm.array<16 x i8>) -> ()
// CHECK-NEXT:          %9 = arith.constant 1 : i32
// CHECK-NEXT:          memref.store %9, %errflg[] : memref<i32>
// CHECK-NEXT:        }
// CHECK-NEXT:        %10 = arith.constant 0 : i32
// CHECK-NEXT:        %11 = arith.cmpi eq, %12, %10 : i32
// CHECK-NEXT:        %12 = memref.load %errflg[] : memref<i32>
// CHECK-NEXT:        scf.if %11 {
// CHECK-NEXT:          %13, %14, %15 = func.call @make_ddt_run(%cols, %cole, %O3, %HNO3, %vmr) : (memref<i32>, memref<i32>, memref<?x!ccpp_utils.real_kind<"kind_phys">>, memref<?x!ccpp_utils.real_kind<"kind_phys">>, memref<!ccpp_utils.derived_type<"vmr_type">>) -> (memref<!ccpp_utils.derived_type<"vmr_type">>, memref<512xi8>, memref<i32>)
// CHECK-NEXT:          "memref.copy"(%13, %vmr) : (memref<!ccpp_utils.derived_type<"vmr_type">>, memref<!ccpp_utils.derived_type<"vmr_type">>) -> ()
// CHECK-NEXT:          "memref.copy"(%14, %errmsg) : (memref<512xi8>, memref<512xi8>) -> ()
// CHECK-NEXT:          "memref.copy"(%15, %errflg) : (memref<i32>, memref<i32>) -> ()
// CHECK-NEXT:        }
// CHECK-NEXT:        %16 = arith.constant 0 : i32
// CHECK-NEXT:        %17 = arith.cmpi eq, %18, %16 : i32
// CHECK-NEXT:        %18 = memref.load %errflg[] : memref<i32>
// CHECK-NEXT:        scf.if %17 {
// CHECK-NEXT:          %19, %20 = func.call @environ_conditions_run(%psurf) : (memref<?x!ccpp_utils.real_kind<"kind_phys">>) -> (memref<512xi8>, memref<i32>)
// CHECK-NEXT:          "memref.copy"(%19, %errmsg) : (memref<512xi8>, memref<512xi8>) -> ()
// CHECK-NEXT:          "memref.copy"(%20, %errflg) : (memref<i32>, memref<i32>) -> ()
// CHECK-NEXT:        }
// CHECK-NEXT:        func.return %vmr, %errmsg, %errflg : memref<!ccpp_utils.derived_type<"vmr_type">>, memref<512xi8>, memref<i32>
// CHECK-NEXT:      }
// CHECK-LABEL:     func.func public @ddt_suite_suite_timestep_initial() -> (memref<i32>, memref<512xi8>) {
// CHECK:             %errflg = "memref.alloca"() <{operandSegmentSizes = array<i32: 0, 0>}> : () -> memref<i32>
// CHECK-NEXT:        %errmsg = "memref.alloca"() <{operandSegmentSizes = array<i32: 0, 0>}> : () -> memref<512xi8>
// CHECK-NEXT:        %0 = arith.constant 0 : i32
// CHECK-NEXT:        memref.store %0, %errflg[] : memref<i32>
// CHECK-NEXT:        %1 = "llvm.mlir.addressof"() <{global_name = @const_initialized}> : () -> !llvm.ptr
// CHECK-NEXT:        %2 = "llvm.load"(%1) <{ordering = 0 : i64}> : (!llvm.ptr) -> !llvm.array<16 x i8>
// CHECK-NEXT:        %3 = "llvm.mlir.addressof"() <{global_name = @ccpp_suite_state}> : () -> !llvm.ptr
// CHECK-NEXT:        %4 = "llvm.load"(%3) <{ordering = 0 : i64}> : (!llvm.ptr) -> !llvm.array<16 x i8>
// CHECK-NEXT:        %5 = "ccpp_utils.strcmp"(%2, %4) <{length = 11 : i64}> : (!llvm.array<16 x i8>, !llvm.array<16 x i8>) -> i1
// CHECK-NEXT:        %6 = arith.constant true
// CHECK-NEXT:        %7 = arith.xori %5, %6 : i1
// CHECK-NEXT:        scf.if %7 {
// CHECK-NEXT:          %8 = "ccpp_utils.trim"(%4) : (!llvm.array<16 x i8>) -> !llvm.array<16 x i8>
// CHECK-NEXT:          "ccpp_utils.write_errmsg"(%errmsg, %8) <{prefix = "Invalid initial CCPP state, '", suffix = "' in ddt_suite_timestep_initial"}> : (memref<512xi8>, !llvm.array<16 x i8>) -> ()
// CHECK-NEXT:          %9 = arith.constant 1 : i32
// CHECK-NEXT:          memref.store %9, %errflg[] : memref<i32>
// CHECK-NEXT:        }
// CHECK-NEXT:        %10 = "llvm.mlir.addressof"() <{global_name = @const_in_time_step}> : () -> !llvm.ptr
// CHECK-NEXT:        %11 = "llvm.load"(%10) <{ordering = 0 : i64}> : (!llvm.ptr) -> !llvm.array<16 x i8>
// CHECK-NEXT:        %12 = "llvm.mlir.addressof"() <{global_name = @ccpp_suite_state}> : () -> !llvm.ptr
// CHECK-NEXT:        "llvm.store"(%11, %12) <{ordering = 0 : i64}> : (!llvm.array<16 x i8>, !llvm.ptr) -> ()
// CHECK-NEXT:        func.return %errflg, %errmsg : memref<i32>, memref<512xi8>
// CHECK-NEXT:      }
// CHECK-LABEL:     func.func public @ddt_suite_suite_timestep_final() -> (memref<i32>, memref<512xi8>) {
// CHECK:             %errflg = "memref.alloca"() <{operandSegmentSizes = array<i32: 0, 0>}> : () -> memref<i32>
// CHECK-NEXT:        %errmsg = "memref.alloca"() <{operandSegmentSizes = array<i32: 0, 0>}> : () -> memref<512xi8>
// CHECK-NEXT:        %0 = arith.constant 0 : i32
// CHECK-NEXT:        memref.store %0, %errflg[] : memref<i32>
// CHECK-NEXT:        %1 = "llvm.mlir.addressof"() <{global_name = @const_in_time_step}> : () -> !llvm.ptr
// CHECK-NEXT:        %2 = "llvm.load"(%1) <{ordering = 0 : i64}> : (!llvm.ptr) -> !llvm.array<16 x i8>
// CHECK-NEXT:        %3 = "llvm.mlir.addressof"() <{global_name = @ccpp_suite_state}> : () -> !llvm.ptr
// CHECK-NEXT:        %4 = "llvm.load"(%3) <{ordering = 0 : i64}> : (!llvm.ptr) -> !llvm.array<16 x i8>
// CHECK-NEXT:        %5 = "ccpp_utils.strcmp"(%2, %4) <{length = 12 : i64}> : (!llvm.array<16 x i8>, !llvm.array<16 x i8>) -> i1
// CHECK-NEXT:        %6 = arith.constant true
// CHECK-NEXT:        %7 = arith.xori %5, %6 : i1
// CHECK-NEXT:        scf.if %7 {
// CHECK-NEXT:          %8 = "ccpp_utils.trim"(%4) : (!llvm.array<16 x i8>) -> !llvm.array<16 x i8>
// CHECK-NEXT:          "ccpp_utils.write_errmsg"(%errmsg, %8) <{prefix = "Invalid initial CCPP state, '", suffix = "' in ddt_suite_timestep_final"}> : (memref<512xi8>, !llvm.array<16 x i8>) -> ()
// CHECK-NEXT:          %9 = arith.constant 1 : i32
// CHECK-NEXT:          memref.store %9, %errflg[] : memref<i32>
// CHECK-NEXT:        }
// CHECK-NEXT:        %10 = "llvm.mlir.addressof"() <{global_name = @const_initialized}> : () -> !llvm.ptr
// CHECK-NEXT:        %11 = "llvm.load"(%10) <{ordering = 0 : i64}> : (!llvm.ptr) -> !llvm.array<16 x i8>
// CHECK-NEXT:        %12 = "llvm.mlir.addressof"() <{global_name = @ccpp_suite_state}> : () -> !llvm.ptr
// CHECK-NEXT:        "llvm.store"(%11, %12) <{ordering = 0 : i64}> : (!llvm.array<16 x i8>, !llvm.ptr) -> ()
// CHECK-NEXT:        func.return %errflg, %errmsg : memref<i32>, memref<512xi8>
// CHECK-NEXT:      }
// CHECK-LABEL:     func.func private @make_ddt_init(memref<i32>) -> (memref<!ccpp_utils.derived_type<"vmr_type">>, memref<512xi8>, memref<i32>)
// CHECK-LABEL:     func.func private @environ_conditions_init(memref<i32>) -> (memref<?x!ccpp_utils.real_kind<"kind_phys">>, memref<?x!ccpp_utils.real_kind<"kind_phys">>, memref<i32>, memref<?xi32>, memref<512xi8>, memref<i32>)
// CHECK-LABEL:     func.func private @environ_conditions_finalize(memref<i32>, memref<?xi32>) -> (memref<512xi8>, memref<i32>)
// CHECK-LABEL:     func.func private @make_ddt_run(memref<i32>, memref<i32>, memref<?x!ccpp_utils.real_kind<"kind_phys">>, memref<?x!ccpp_utils.real_kind<"kind_phys">>, memref<!ccpp_utils.derived_type<"vmr_type">>) -> (memref<!ccpp_utils.derived_type<"vmr_type">>, memref<512xi8>, memref<i32>)
// CHECK-LABEL:     func.func private @environ_conditions_run(memref<?x!ccpp_utils.real_kind<"kind_phys">>) -> (memref<512xi8>, memref<i32>)
// CHECK:         }
// CHECK-LABEL:   builtin.module @ddt_ccpp_cap {
// CHECK:           "llvm.mlir.global"() <{global_type = !llvm.array<1 x i8>, sym_name = "pver", linkage = #llvm.linkage<"external">, addr_space = 0 : i32}> ({
// CHECK-NEXT:      }) {module = "test_host_mod"} : () -> ()
// CHECK-NEXT:      "llvm.mlir.global"() <{global_type = !llvm.array<1 x i8>, sym_name = "dt", linkage = #llvm.linkage<"external">, addr_space = 0 : i32}> ({
// CHECK-NEXT:      }) {module = "test_host_mod"} : () -> ()
// CHECK-NEXT:      "llvm.mlir.global"() <{global_type = !llvm.array<1 x i8>, sym_name = "temp_interfaces", linkage = #llvm.linkage<"external">, addr_space = 0 : i32}> ({
// CHECK-NEXT:      }) {module = "test_host_mod"} : () -> ()
// CHECK-NEXT:      "llvm.mlir.global"() <{global_type = !llvm.array<1 x i8>, sym_name = "temp_diag", linkage = #llvm.linkage<"external">, addr_space = 0 : i32}> ({
// CHECK-NEXT:      }) {module = "test_host_mod"} : () -> ()
// CHECK-NEXT:      "llvm.mlir.global"() <{global_type = !llvm.array<1 x i8>, sym_name = "temp_midpoints", linkage = #llvm.linkage<"external">, addr_space = 0 : i32}> ({
// CHECK-NEXT:      }) {module = "test_host_mod"} : () -> ()
// CHECK-NEXT:      "llvm.mlir.global"() <{global_type = !llvm.array<1 x i8>, sym_name = "slev_lbound", linkage = #llvm.linkage<"external">, addr_space = 0 : i32}> ({
// CHECK-NEXT:      }) {module = "test_host_mod"} : () -> ()
// CHECK-NEXT:      "llvm.mlir.global"() <{global_type = !llvm.array<1 x i8>, sym_name = "var_array", linkage = #llvm.linkage<"external">, addr_space = 0 : i32}> ({
// CHECK-NEXT:      }) {module = "test_host_mod"} : () -> ()
// CHECK-NEXT:      "llvm.mlir.global"() <{global_type = !llvm.array<1 x i8>, sym_name = "pverP", linkage = #llvm.linkage<"external">, addr_space = 0 : i32}> ({
// CHECK-NEXT:      }) {module = "test_host_mod"} : () -> ()
// CHECK-NEXT:      "llvm.mlir.global"() <{global_type = !llvm.array<9 x i8>, sym_name = "str_ddt_suite", linkage = #llvm.linkage<"internal">, addr_space = 0 : i32, constant, value = "ddt_suite"}> ({
// CHECK-NEXT:      }) : () -> ()
// CHECK-NEXT:      "llvm.mlir.global"() <{global_type = !llvm.array<10 x i8>, sym_name = "str_temp_suite", linkage = #llvm.linkage<"internal">, addr_space = 0 : i32, constant, value = "temp_suite"}> ({
// CHECK-NEXT:      }) : () -> ()
// CHECK-NEXT:      "llvm.mlir.global"() <{global_type = !llvm.array<7 x i8>, sym_name = "str_physics", linkage = #llvm.linkage<"internal">, addr_space = 0 : i32, constant, value = "physics"}> ({
// CHECK-NEXT:      }) : () -> ()
// CHECK-LABEL:     func.func public @Ddt_ccpp_physics_initialize(%suite_name : memref<?xi8>) -> (memref<512xi8>, memref<i32>) {
// CHECK:             %errmsg = "memref.alloca"() <{operandSegmentSizes = array<i32: 0, 0>}> : () -> memref<512xi8>
// CHECK-NEXT:        %errflg = "memref.alloca"() <{operandSegmentSizes = array<i32: 0, 0>}> : () -> memref<i32>
// CHECK-NEXT:        %0 = arith.constant 0 : i32
// CHECK-NEXT:        memref.store %0, %errflg[] : memref<i32>
// CHECK-NEXT:        %1 = "ccpp_utils.trim"(%suite_name) : (memref<?xi8>) -> memref<?xi8>
// CHECK-NEXT:        %2 = "ccpp_utils.strcmp"(%1) <{literal = "ddt_suite"}> : (memref<?xi8>) -> i1
// CHECK-NEXT:        scf.if %2 {
// CHECK-NEXT:          %3, %4, %5, %6, %7, %8, %9 = func.call @ddt_suite_suite_initialize() : () -> (memref<!ccpp_utils.derived_type<"vmr_type">>, memref<512xi8>, memref<i32>, memref<!ccpp_utils.real_kind<"kind_phys">>, memref<!ccpp_utils.real_kind<"kind_phys">>, memref<i32>, memref<i32>)
// CHECK-NEXT:          "memref.copy"(%4, %errmsg) : (memref<512xi8>, memref<512xi8>) -> ()
// CHECK-NEXT:          "memref.copy"(%5, %errflg) : (memref<i32>, memref<i32>) -> ()
// CHECK-NEXT:          "memref.copy"(%8, %errflg) : (memref<i32>, memref<i32>) -> ()
// CHECK-NEXT:          "memref.copy"(%9, %errflg) : (memref<i32>, memref<i32>) -> ()
// CHECK-NEXT:        } else {
// CHECK-NEXT:          %10 = "ccpp_utils.strcmp"(%1) <{literal = "temp_suite"}> : (memref<?xi8>) -> i1
// CHECK-NEXT:          scf.if %10 {
// CHECK-NEXT:            %11, %12, %13 = func.call @temp_suite_suite_initialize() : () -> (memref<!ccpp_utils.real_kind<"kind_phys">>, memref<512xi8>, memref<i32>)
// CHECK-NEXT:            "memref.copy"(%12, %errmsg) : (memref<512xi8>, memref<512xi8>) -> ()
// CHECK-NEXT:            "memref.copy"(%13, %errflg) : (memref<i32>, memref<i32>) -> ()
// CHECK-NEXT:          } else {
// CHECK-NEXT:            "ccpp_utils.write_errmsg"(%errmsg, %1) <{prefix = "No suite named ", suffix = "found"}> : (memref<512xi8>, memref<?xi8>) -> ()
// CHECK-NEXT:            %14 = arith.constant 1 : i32
// CHECK-NEXT:            memref.store %14, %errflg[] : memref<i32>
// CHECK-NEXT:          }
// CHECK-NEXT:        }
// CHECK-NEXT:        func.return %errmsg, %errflg : memref<512xi8>, memref<i32>
// CHECK-NEXT:      }
// CHECK-LABEL:     func.func public @Ddt_ccpp_physics_finalize(%suite_name : memref<?xi8>) -> (memref<512xi8>, memref<i32>) {
// CHECK:             %errmsg = "memref.alloca"() <{operandSegmentSizes = array<i32: 0, 0>}> : () -> memref<512xi8>
// CHECK-NEXT:        %errflg = "memref.alloca"() <{operandSegmentSizes = array<i32: 0, 0>}> : () -> memref<i32>
// CHECK-NEXT:        %0 = arith.constant 0 : i32
// CHECK-NEXT:        memref.store %0, %errflg[] : memref<i32>
// CHECK-NEXT:        %1 = "ccpp_utils.trim"(%suite_name) : (memref<?xi8>) -> memref<?xi8>
// CHECK-NEXT:        %2 = "ccpp_utils.strcmp"(%1) <{literal = "ddt_suite"}> : (memref<?xi8>) -> i1
// CHECK-NEXT:        scf.if %2 {
// CHECK-NEXT:          %3, %4 = func.call @ddt_suite_suite_finalize() : () -> (memref<512xi8>, memref<i32>)
// CHECK-NEXT:          "memref.copy"(%3, %errmsg) : (memref<512xi8>, memref<512xi8>) -> ()
// CHECK-NEXT:          "memref.copy"(%4, %errflg) : (memref<i32>, memref<i32>) -> ()
// CHECK-NEXT:        } else {
// CHECK-NEXT:          %5 = "ccpp_utils.strcmp"(%1) <{literal = "temp_suite"}> : (memref<?xi8>) -> i1
// CHECK-NEXT:          scf.if %5 {
// CHECK-NEXT:            %6, %7 = func.call @temp_suite_suite_finalize() : () -> (memref<512xi8>, memref<i32>)
// CHECK-NEXT:            "memref.copy"(%6, %errmsg) : (memref<512xi8>, memref<512xi8>) -> ()
// CHECK-NEXT:            "memref.copy"(%7, %errflg) : (memref<i32>, memref<i32>) -> ()
// CHECK-NEXT:          } else {
// CHECK-NEXT:            "ccpp_utils.write_errmsg"(%errmsg, %1) <{prefix = "No suite named ", suffix = "found"}> : (memref<512xi8>, memref<?xi8>) -> ()
// CHECK-NEXT:            %8 = arith.constant 1 : i32
// CHECK-NEXT:            memref.store %8, %errflg[] : memref<i32>
// CHECK-NEXT:          }
// CHECK-NEXT:        }
// CHECK-NEXT:        func.return %errmsg, %errflg : memref<512xi8>, memref<i32>
// CHECK-NEXT:      }
// CHECK-LABEL:     func.func public @Ddt_ccpp_physics_timestep_initial(%suite_name : memref<?xi8>) -> (memref<512xi8>, memref<i32>) {
// CHECK:             %errmsg = "memref.alloca"() <{operandSegmentSizes = array<i32: 0, 0>}> : () -> memref<512xi8>
// CHECK-NEXT:        %errflg = "memref.alloca"() <{operandSegmentSizes = array<i32: 0, 0>}> : () -> memref<i32>
// CHECK-NEXT:        %0 = arith.constant 0 : i32
// CHECK-NEXT:        memref.store %0, %errflg[] : memref<i32>
// CHECK-NEXT:        %1 = "ccpp_utils.trim"(%suite_name) : (memref<?xi8>) -> memref<?xi8>
// CHECK-NEXT:        %2 = "ccpp_utils.strcmp"(%1) <{literal = "ddt_suite"}> : (memref<?xi8>) -> i1
// CHECK-NEXT:        scf.if %2 {
// CHECK-NEXT:          %3, %4 = func.call @ddt_suite_suite_timestep_initial() : () -> (memref<i32>, memref<512xi8>)
// CHECK-NEXT:          "memref.copy"(%3, %errflg) : (memref<i32>, memref<i32>) -> ()
// CHECK-NEXT:          "memref.copy"(%4, %errmsg) : (memref<512xi8>, memref<512xi8>) -> ()
// CHECK-NEXT:        } else {
// CHECK-NEXT:          %5 = "ccpp_utils.strcmp"(%1) <{literal = "temp_suite"}> : (memref<?xi8>) -> i1
// CHECK-NEXT:          scf.if %5 {
// CHECK-NEXT:            %6, %7 = func.call @temp_suite_suite_timestep_initial() : () -> (memref<i32>, memref<512xi8>)
// CHECK-NEXT:            "memref.copy"(%6, %errflg) : (memref<i32>, memref<i32>) -> ()
// CHECK-NEXT:            "memref.copy"(%7, %errmsg) : (memref<512xi8>, memref<512xi8>) -> ()
// CHECK-NEXT:          } else {
// CHECK-NEXT:            "ccpp_utils.write_errmsg"(%errmsg, %1) <{prefix = "No suite named ", suffix = "found"}> : (memref<512xi8>, memref<?xi8>) -> ()
// CHECK-NEXT:            %8 = arith.constant 1 : i32
// CHECK-NEXT:            memref.store %8, %errflg[] : memref<i32>
// CHECK-NEXT:          }
// CHECK-NEXT:        }
// CHECK-NEXT:        func.return %errmsg, %errflg : memref<512xi8>, memref<i32>
// CHECK-NEXT:      }
// CHECK-LABEL:     func.func public @Ddt_ccpp_physics_timestep_final(%suite_name : memref<?xi8>) -> (memref<512xi8>, memref<i32>) {
// CHECK:             %errmsg = "memref.alloca"() <{operandSegmentSizes = array<i32: 0, 0>}> : () -> memref<512xi8>
// CHECK-NEXT:        %errflg = "memref.alloca"() <{operandSegmentSizes = array<i32: 0, 0>}> : () -> memref<i32>
// CHECK-NEXT:        %0 = arith.constant 0 : i32
// CHECK-NEXT:        memref.store %0, %errflg[] : memref<i32>
// CHECK-NEXT:        %1 = "ccpp_utils.trim"(%suite_name) : (memref<?xi8>) -> memref<?xi8>
// CHECK-NEXT:        %2 = "ccpp_utils.strcmp"(%1) <{literal = "ddt_suite"}> : (memref<?xi8>) -> i1
// CHECK-NEXT:        scf.if %2 {
// CHECK-NEXT:          %3, %4 = func.call @ddt_suite_suite_timestep_final() : () -> (memref<i32>, memref<512xi8>)
// CHECK-NEXT:          "memref.copy"(%3, %errflg) : (memref<i32>, memref<i32>) -> ()
// CHECK-NEXT:          "memref.copy"(%4, %errmsg) : (memref<512xi8>, memref<512xi8>) -> ()
// CHECK-NEXT:        } else {
// CHECK-NEXT:          %5 = "ccpp_utils.strcmp"(%1) <{literal = "temp_suite"}> : (memref<?xi8>) -> i1
// CHECK-NEXT:          scf.if %5 {
// CHECK-NEXT:            %6, %7 = func.call @temp_suite_suite_timestep_final() : () -> (memref<i32>, memref<512xi8>)
// CHECK-NEXT:            "memref.copy"(%6, %errflg) : (memref<i32>, memref<i32>) -> ()
// CHECK-NEXT:            "memref.copy"(%7, %errmsg) : (memref<512xi8>, memref<512xi8>) -> ()
// CHECK-NEXT:          } else {
// CHECK-NEXT:            "ccpp_utils.write_errmsg"(%errmsg, %1) <{prefix = "No suite named ", suffix = "found"}> : (memref<512xi8>, memref<?xi8>) -> ()
// CHECK-NEXT:            %8 = arith.constant 1 : i32
// CHECK-NEXT:            memref.store %8, %errflg[] : memref<i32>
// CHECK-NEXT:          }
// CHECK-NEXT:        }
// CHECK-NEXT:        func.return %errmsg, %errflg : memref<512xi8>, memref<i32>
// CHECK-NEXT:      }
// CHECK-LABEL:     func.func public @Ddt_ccpp_physics_run(%suite_name : memref<?xi8>, %suite_part : memref<?xi8>, %cols : memref<i32>, %cole : memref<i32>, %O3 : memref<?x!ccpp_utils.real_kind<"kind_phys">>, %HNO3 : memref<?x!ccpp_utils.real_kind<"kind_phys">>, %vmr : memref<!ccpp_utils.derived_type<"vmr_type">>, %psurf : memref<?x!ccpp_utils.real_kind<"kind_phys">>, %col_start : memref<i32>, %col_end : memref<i32>, %ps : memref<?x!ccpp_utils.real_kind<"kind_phys">>, %to_promote : memref<?x?x!ccpp_utils.real_kind<"kind_phys">>, %promote_pcnst : memref<?x!ccpp_utils.real_kind<"kind_phys">>, %soil_levs : memref<?x!ccpp_utils.real_kind<"kind_phys">>, %temp_calc : memref<?x!ccpp_utils.real_kind<"kind_phys">>, %temp_prev : memref<?x!ccpp_utils.real_kind<"kind_phys">>, %qv : memref<?x!ccpp_utils.real_kind<"kind_phys">>, %errmsg : memref<512xi8>, %errflg : memref<i32>) -> (memref<512xi8>, memref<i32>) {
// CHECK:             %0 = arith.constant 0 : i32
// CHECK-NEXT:        memref.store %0, %errflg[] : memref<i32>
// CHECK-NEXT:        %1 = "ccpp_utils.trim"(%suite_name) : (memref<?xi8>) -> memref<?xi8>
// CHECK-NEXT:        %2 = "ccpp_utils.strcmp"(%1) <{literal = "ddt_suite"}> : (memref<?xi8>) -> i1
// CHECK-NEXT:        scf.if %2 {
// CHECK-NEXT:          %3 = "ccpp_utils.trim"(%suite_part) : (memref<?xi8>) -> memref<?xi8>
// CHECK-NEXT:          %4 = "ccpp_utils.strcmp"(%3) <{literal = "physics"}> : (memref<?xi8>) -> i1
// CHECK-NEXT:          scf.if %4 {
// CHECK-NEXT:            %5, %6, %7 = func.call @ddt_suite_suite_physics(%cols, %cole, %O3, %HNO3, %vmr, %psurf) : (memref<i32>, memref<i32>, memref<?x!ccpp_utils.real_kind<"kind_phys">>, memref<?x!ccpp_utils.real_kind<"kind_phys">>, memref<!ccpp_utils.derived_type<"vmr_type">>, memref<?x!ccpp_utils.real_kind<"kind_phys">>) -> (memref<!ccpp_utils.derived_type<"vmr_type">>, memref<512xi8>, memref<i32>)
// CHECK-NEXT:            "memref.copy"(%6, %errmsg) : (memref<512xi8>, memref<512xi8>) -> ()
// CHECK-NEXT:            "memref.copy"(%7, %errflg) : (memref<i32>, memref<i32>) -> ()
// CHECK-NEXT:          } else {
// CHECK-NEXT:            "ccpp_utils.write_errmsg"(%errmsg, %3) <{prefix = "No suite part named ", suffix = " found in suite ddt_suite"}> : (memref<512xi8>, memref<?xi8>) -> ()
// CHECK-NEXT:            %8 = arith.constant 1 : i32
// CHECK-NEXT:            memref.store %8, %errflg[] : memref<i32>
// CHECK-NEXT:          }
// CHECK-NEXT:        } else {
// CHECK-NEXT:          %9 = "ccpp_utils.strcmp"(%1) <{literal = "temp_suite"}> : (memref<?xi8>) -> i1
// CHECK-NEXT:          scf.if %9 {
// CHECK-NEXT:            %10 = "ccpp_utils.host_var_ref"() <{var_name = "pver", module_name = "test_host_mod"}> : () -> memref<i32>
// CHECK-NEXT:            %11 = "ccpp_utils.host_var_ref"() <{var_name = "dt", module_name = "test_host_mod"}> : () -> memref<!ccpp_utils.real_kind<"kind_phys">>
// CHECK-NEXT:            %12 = "ccpp_utils.host_var_ref"() <{var_name = "temp_interfaces", module_name = "test_host_mod"}> : () -> memref<?x?x!ccpp_utils.real_kind<"kind_phys">>
// CHECK-NEXT:            %13 = "ccpp_utils.host_var_ref"() <{var_name = "temp_diag", module_name = "test_host_mod"}> : () -> memref<?x?x!ccpp_utils.real_kind<"kind_phys">>
// CHECK-NEXT:            %14 = "ccpp_utils.host_var_ref"() <{var_name = "temp_midpoints", module_name = "test_host_mod"}> : () -> memref<?x?x!ccpp_utils.real_kind<"kind_phys">>
// CHECK-NEXT:            %15 = "ccpp_utils.host_var_ref"() <{var_name = "slev_lbound", module_name = "test_host_mod"}> : () -> memref<i32>
// CHECK-NEXT:            %16 = "ccpp_utils.host_var_ref"() <{var_name = "var_array", module_name = "test_host_mod"}> : () -> memref<?x?x?x?x!ccpp_utils.real_kind<"kind_phys">>
// CHECK-NEXT:            %17 = "ccpp_utils.host_var_ref"() <{var_name = "temp_midpoints", module_name = "test_host_mod"}> : () -> memref<?x!ccpp_utils.real_kind<"kind_phys">>
// CHECK-NEXT:            %18 = arith.constant 1 : i32
// CHECK-NEXT:            %19 = "ccpp_utils.host_var_ref"() <{var_name = "pverP", module_name = "test_host_mod"}> : () -> i32
// CHECK-NEXT:            %20 = "ccpp_utils.array_section"(%12, %col_start, %18, %col_end, %19) {operandSegmentSizes = array<i32: 1, 2, 2>} : (memref<?x?x!ccpp_utils.real_kind<"kind_phys">>, memref<i32>, i32, memref<i32>, i32) -> memref<?x?x!ccpp_utils.real_kind<"kind_phys">>
// CHECK-NEXT:            %21 = "ccpp_utils.array_section"(%14, %col_start, %18, %col_end, %10) {operandSegmentSizes = array<i32: 1, 2, 2>} : (memref<?x?x!ccpp_utils.real_kind<"kind_phys">>, memref<i32>, i32, memref<i32>, memref<i32>) -> memref<?x?x!ccpp_utils.real_kind<"kind_phys">>
// CHECK-NEXT:            %22 = "ccpp_utils.array_section"(%17, %col_start, %18, %col_end, %10) {operandSegmentSizes = array<i32: 1, 2, 2>} : (memref<?x!ccpp_utils.real_kind<"kind_phys">>, memref<i32>, i32, memref<i32>, memref<i32>) -> memref<?x!ccpp_utils.real_kind<"kind_phys">>
// CHECK-NEXT:            %23 = "ccpp_utils.trim"(%suite_part) : (memref<?xi8>) -> memref<?xi8>
// CHECK-NEXT:            %24 = "ccpp_utils.strcmp"(%23) <{literal = "physics"}> : (memref<?xi8>) -> i1
// CHECK-NEXT:            scf.if %24 {
// CHECK-NEXT:              %25, %26 = func.call @temp_suite_suite_physics(%col_start, %col_end, %10, %11, %20, %13, %21, %ps, %to_promote, %promote_pcnst, %15, %soil_levs, %16, %temp_calc, %temp_prev, %22, %qv) : (memref<i32>, memref<i32>, memref<i32>, memref<!ccpp_utils.real_kind<"kind_phys">>, memref<?x?x!ccpp_utils.real_kind<"kind_phys">>, memref<?x?x!ccpp_utils.real_kind<"kind_phys">>, memref<?x?x!ccpp_utils.real_kind<"kind_phys">>, memref<?x!ccpp_utils.real_kind<"kind_phys">>, memref<?x?x!ccpp_utils.real_kind<"kind_phys">>, memref<?x!ccpp_utils.real_kind<"kind_phys">>, memref<i32>, memref<?x!ccpp_utils.real_kind<"kind_phys">>, memref<?x?x?x?x!ccpp_utils.real_kind<"kind_phys">>, memref<?x!ccpp_utils.real_kind<"kind_phys">>, memref<?x!ccpp_utils.real_kind<"kind_phys">>, memref<?x!ccpp_utils.real_kind<"kind_phys">>, memref<?x!ccpp_utils.real_kind<"kind_phys">>) -> (memref<512xi8>, memref<i32>)
// CHECK-NEXT:              "memref.copy"(%25, %errmsg) : (memref<512xi8>, memref<512xi8>) -> ()
// CHECK-NEXT:              "memref.copy"(%26, %errflg) : (memref<i32>, memref<i32>) -> ()
// CHECK-NEXT:            } else {
// CHECK-NEXT:              "ccpp_utils.write_errmsg"(%errmsg, %23) <{prefix = "No suite part named ", suffix = " found in suite temp_suite"}> : (memref<512xi8>, memref<?xi8>) -> ()
// CHECK-NEXT:              %27 = arith.constant 1 : i32
// CHECK-NEXT:              memref.store %27, %errflg[] : memref<i32>
// CHECK-NEXT:            }
// CHECK-NEXT:          } else {
// CHECK-NEXT:            "ccpp_utils.write_errmsg"(%errmsg, %1) <{prefix = "No suite named ", suffix = "found"}> : (memref<512xi8>, memref<?xi8>) -> ()
// CHECK-NEXT:            %28 = arith.constant 1 : i32
// CHECK-NEXT:            memref.store %28, %errflg[] : memref<i32>
// CHECK-NEXT:          }
// CHECK-NEXT:        }
// CHECK-NEXT:        func.return %errmsg, %errflg : memref<512xi8>, memref<i32>
// CHECK-NEXT:      }
// CHECK-LABEL:     func.func public @ccpp_physics_suite_list(%suites : memref<memref<?xi8>>) {
// CHECK:             %0 = arith.constant 9 : index
// CHECK-NEXT:        %1 = memref.alloc(%0) : memref<?xi8>
// CHECK-NEXT:        %2 = "llvm.mlir.addressof"() <{global_name = @str_ddt_suite}> : () -> !llvm.ptr
// CHECK-NEXT:        %3 = "llvm.load"(%2) <{ordering = 0 : i64}> : (!llvm.ptr) -> !llvm.array<9 x i8>
// CHECK-NEXT:        "ccpp_utils.set_string"(%1, %3) : (memref<?xi8>, !llvm.array<9 x i8>) -> ()
// CHECK-NEXT:        memref.store %1, %suites[] : memref<memref<?xi8>>
// CHECK-NEXT:        %4 = arith.constant 10 : index
// CHECK-NEXT:        %5 = memref.alloc(%4) : memref<?xi8>
// CHECK-NEXT:        %6 = "llvm.mlir.addressof"() <{global_name = @str_temp_suite}> : () -> !llvm.ptr
// CHECK-NEXT:        %7 = "llvm.load"(%6) <{ordering = 0 : i64}> : (!llvm.ptr) -> !llvm.array<10 x i8>
// CHECK-NEXT:        "ccpp_utils.set_string"(%5, %7) : (memref<?xi8>, !llvm.array<10 x i8>) -> ()
// CHECK-NEXT:        memref.store %5, %suites[] : memref<memref<?xi8>>
// CHECK-NEXT:        func.return
// CHECK-NEXT:      }
// CHECK-LABEL:     func.func public @ccpp_physics_suite_part_list(%suite_name : memref<?xi8>, %part_list : memref<memref<?xi8>>) -> (memref<512xi8>, memref<i32>) {
// CHECK:             %errmsg = "memref.alloca"() <{operandSegmentSizes = array<i32: 0, 0>}> : () -> memref<512xi8>
// CHECK-NEXT:        %errflg = "memref.alloca"() <{operandSegmentSizes = array<i32: 0, 0>}> : () -> memref<i32>
// CHECK-NEXT:        %0 = arith.constant 0 : i32
// CHECK-NEXT:        memref.store %0, %errflg[] : memref<i32>
// CHECK-NEXT:        %1 = "ccpp_utils.trim"(%suite_name) : (memref<?xi8>) -> memref<?xi8>
// CHECK-NEXT:        %2 = "ccpp_utils.strcmp"(%1) <{literal = "ddt_suite"}> : (memref<?xi8>) -> i1
// CHECK-NEXT:        scf.if %2 {
// CHECK-NEXT:          %3 = arith.constant 7 : index
// CHECK-NEXT:          %4 = memref.alloc(%3) : memref<?xi8>
// CHECK-NEXT:          %5 = "llvm.mlir.addressof"() <{global_name = @str_physics}> : () -> !llvm.ptr
// CHECK-NEXT:          %6 = "llvm.load"(%5) <{ordering = 0 : i64}> : (!llvm.ptr) -> !llvm.array<7 x i8>
// CHECK-NEXT:          "ccpp_utils.set_string"(%4, %6) : (memref<?xi8>, !llvm.array<7 x i8>) -> ()
// CHECK-NEXT:          memref.store %4, %part_list[] : memref<memref<?xi8>>
// CHECK-NEXT:        } else {
// CHECK-NEXT:          %7 = "ccpp_utils.strcmp"(%1) <{literal = "temp_suite"}> : (memref<?xi8>) -> i1
// CHECK-NEXT:          scf.if %7 {
// CHECK-NEXT:            %8 = arith.constant 7 : index
// CHECK-NEXT:            %9 = memref.alloc(%8) : memref<?xi8>
// CHECK-NEXT:            %10 = "llvm.mlir.addressof"() <{global_name = @str_physics}> : () -> !llvm.ptr
// CHECK-NEXT:            %11 = "llvm.load"(%10) <{ordering = 0 : i64}> : (!llvm.ptr) -> !llvm.array<7 x i8>
// CHECK-NEXT:            "ccpp_utils.set_string"(%9, %11) : (memref<?xi8>, !llvm.array<7 x i8>) -> ()
// CHECK-NEXT:            memref.store %9, %part_list[] : memref<memref<?xi8>>
// CHECK-NEXT:          } else {
// CHECK-NEXT:            "ccpp_utils.write_errmsg"(%errmsg, %1) <{prefix = "No suite named ", suffix = " found"}> : (memref<512xi8>, memref<?xi8>) -> ()
// CHECK-NEXT:            %12 = arith.constant 1 : i32
// CHECK-NEXT:            memref.store %12, %errflg[] : memref<i32>
// CHECK-NEXT:          }
// CHECK-NEXT:        }
// CHECK-NEXT:        func.return %errmsg, %errflg : memref<512xi8>, memref<i32>
// CHECK-NEXT:      }
// CHECK-LABEL:     func.func private @ddt_suite_suite_initialize() -> (memref<!ccpp_utils.derived_type<"vmr_type">>, memref<512xi8>, memref<i32>, memref<!ccpp_utils.real_kind<"kind_phys">>, memref<!ccpp_utils.real_kind<"kind_phys">>, memref<i32>, memref<i32>) attributes {module = "ddt_suite_cap"}
// CHECK-LABEL:     func.func private @temp_suite_suite_initialize() -> (memref<!ccpp_utils.real_kind<"kind_phys">>, memref<512xi8>, memref<i32>) attributes {module = "temp_suite_cap"}
// CHECK-LABEL:     func.func private @ddt_suite_suite_finalize() -> (memref<512xi8>, memref<i32>) attributes {module = "ddt_suite_cap"}
// CHECK-LABEL:     func.func private @temp_suite_suite_finalize() -> (memref<512xi8>, memref<i32>) attributes {module = "temp_suite_cap"}
// CHECK-LABEL:     func.func private @ddt_suite_suite_timestep_initial() -> (memref<i32>, memref<512xi8>) attributes {module = "ddt_suite_cap"}
// CHECK-LABEL:     func.func private @temp_suite_suite_timestep_initial() -> (memref<i32>, memref<512xi8>) attributes {module = "temp_suite_cap"}
// CHECK-LABEL:     func.func private @ddt_suite_suite_timestep_final() -> (memref<i32>, memref<512xi8>) attributes {module = "ddt_suite_cap"}
// CHECK-LABEL:     func.func private @temp_suite_suite_timestep_final() -> (memref<i32>, memref<512xi8>) attributes {module = "temp_suite_cap"}
// CHECK-LABEL:     func.func private @temp_suite_suite_physics(memref<i32>, memref<i32>, memref<i32>, memref<!ccpp_utils.real_kind<"kind_phys">>, memref<?x?x!ccpp_utils.real_kind<"kind_phys">>, memref<?x?x!ccpp_utils.real_kind<"kind_phys">>, memref<?x?x!ccpp_utils.real_kind<"kind_phys">>, memref<?x!ccpp_utils.real_kind<"kind_phys">>, memref<?x?x!ccpp_utils.real_kind<"kind_phys">>, memref<?x!ccpp_utils.real_kind<"kind_phys">>, memref<i32>, memref<?x!ccpp_utils.real_kind<"kind_phys">>, memref<?x?x?x?x!ccpp_utils.real_kind<"kind_phys">>, memref<?x!ccpp_utils.real_kind<"kind_phys">>, memref<?x!ccpp_utils.real_kind<"kind_phys">>, memref<?x!ccpp_utils.real_kind<"kind_phys">>, memref<?x!ccpp_utils.real_kind<"kind_phys">>) -> (memref<512xi8>, memref<i32>) attributes {module = "temp_suite_cap"}
// CHECK-LABEL:     func.func private @ddt_suite_suite_physics(memref<i32>, memref<i32>, memref<?x!ccpp_utils.real_kind<"kind_phys">>, memref<?x!ccpp_utils.real_kind<"kind_phys">>, memref<!ccpp_utils.derived_type<"vmr_type">>, memref<?x!ccpp_utils.real_kind<"kind_phys">>) -> (memref<!ccpp_utils.derived_type<"vmr_type">>, memref<512xi8>, memref<i32>) attributes {module = "ddt_suite_cap"}
// CHECK:         }
// CHECK-LABEL:   builtin.module @ccpp_kinds {
// CHECK:           "ccpp_utils.kind_def"() <{kind_name = "kind_phys", kind_value = "REAL64"}> : () -> ()
// CHECK-NEXT:    }
// CHECK-NEXT:  }
