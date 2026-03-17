// Test the completed IR for the advection XML frontend.
// Exercises: 3-D array types (memref<?x?x?x...>), four distinct schemes,
// apply_constituent_tendencies deduplicated to one call despite appearing
// twice in the suite XML, and host-derived arguments threaded through caps.
//
// RUN: python3 -m xdsl_ccpp.frontend.ccpp_xml --suites examples/advection/cld_suite.xml --scheme-files examples/advection/const_indices.meta,examples/advection/cld_liq.meta,examples/advection/cld_ice.meta,examples/advection/apply_constituent_tendencies.meta --host-files examples/advection/test_host_data.meta,examples/advection/test_host.meta,examples/advection/test_host_mod.meta | python3 -m xdsl_ccpp.tools.ccpp_opt -p generate-meta-cap,generate-meta-kinds,generate-suite-cap,generate-ccpp-cap,generate-kinds,strip-ccpp | python3 -m filecheck %s

// --- Suite cap module ---

// CHECK:       builtin.module {
// CHECK-LABEL:   builtin.module @cld_suite_cap {
// CHECK:           "llvm.mlir.global"() <{global_type = !llvm.array<16 x i8>, sym_name = "ccpp_suite_state", linkage = #llvm.linkage<"internal">, addr_space = 0 : i32, value = "uninitialized"}> ({
// CHECK-NEXT:      }) : () -> ()
// CHECK-NEXT:      "llvm.mlir.global"() <{global_type = !llvm.array<16 x i8>, sym_name = "const_in_time_step", linkage = #llvm.linkage<"internal">, addr_space = 0 : i32, constant, value = "in_time_step"}> ({
// CHECK-NEXT:      }) : () -> ()
// CHECK-NEXT:      "llvm.mlir.global"() <{global_type = !llvm.array<16 x i8>, sym_name = "const_initialized", linkage = #llvm.linkage<"internal">, addr_space = 0 : i32, constant, value = "initialized"}> ({
// CHECK-NEXT:      }) : () -> ()
// CHECK-NEXT:      "llvm.mlir.global"() <{global_type = !llvm.array<16 x i8>, sym_name = "const_uninitialized", linkage = #llvm.linkage<"internal">, addr_space = 0 : i32, constant, value = "uninitialized"}> ({
// CHECK-NEXT:      }) : () -> ()
// CHECK-LABEL:     func.func public @cld_suite_suite_initialize(%const_std_name : memref<?xi8>, %num_consts : memref<i32>, %test_stdname_array : memref<?xi8>, %const_inds : memref<?xi32>, %tfreeze : memref<!ccpp_utils.real_kind<"kind_phys">>, %cld_liq_array : memref<?x?x!ccpp_utils.real_kind<"kind_phys">>, %cld_ice_array : memref<?x?x!ccpp_utils.real_kind<"kind_phys">>) -> (memref<i32>, memref<512xi8>, memref<i32>, memref<!ccpp_utils.real_kind<"kind_phys">>) {
// CHECK:             %const_index = "memref.alloca"() <{operandSegmentSizes = array<i32: 0, 0>}> : () -> memref<i32>
// CHECK-NEXT:        %errmsg = "memref.alloca"() <{operandSegmentSizes = array<i32: 0, 0>}> : () -> memref<512xi8>
// CHECK-NEXT:        %errflg = "memref.alloca"() <{operandSegmentSizes = array<i32: 0, 0>}> : () -> memref<i32>
// CHECK-NEXT:        %tcld = "memref.alloca"() <{operandSegmentSizes = array<i32: 0, 0>}> : () -> memref<!ccpp_utils.real_kind<"kind_phys">>
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
// CHECK-NEXT:          "ccpp_utils.write_errmsg"(%errmsg, %8) <{prefix = "Invalid initial CCPP state, '", suffix = "' in cld_suite_initialize"}> : (memref<512xi8>, !llvm.array<16 x i8>) -> ()
// CHECK-NEXT:          %9 = arith.constant 1 : i32
// CHECK-NEXT:          memref.store %9, %errflg[] : memref<i32>
// CHECK-NEXT:        }
// CHECK-NEXT:        %10 = arith.constant 0 : i32
// CHECK-NEXT:        %11 = arith.cmpi eq, %12, %10 : i32
// CHECK-NEXT:        %12 = memref.load %errflg[] : memref<i32>
// CHECK-NEXT:        scf.if %11 {
// CHECK-NEXT:          %13, %14, %15, %16 = func.call @const_indices_init(%const_std_name, %num_consts, %test_stdname_array) : (memref<?xi8>, memref<i32>, memref<?xi8>) -> (memref<i32>, memref<?xi32>, memref<512xi8>, memref<i32>)
// CHECK-NEXT:          "memref.copy"(%13, %const_index) : (memref<i32>, memref<i32>) -> ()
// CHECK-NEXT:          "memref.copy"(%14, %const_inds) : (memref<?xi32>, memref<?xi32>) -> ()
// CHECK-NEXT:          "memref.copy"(%15, %errmsg) : (memref<512xi8>, memref<512xi8>) -> ()
// CHECK-NEXT:          "memref.copy"(%16, %errflg) : (memref<i32>, memref<i32>) -> ()
// CHECK-NEXT:        }
// CHECK-NEXT:        %17 = arith.constant 0 : i32
// CHECK-NEXT:        %18 = arith.cmpi eq, %19, %17 : i32
// CHECK-NEXT:        %19 = memref.load %errflg[] : memref<i32>
// CHECK-NEXT:        scf.if %18 {
// CHECK-NEXT:          %20, %21, %22, %23 = func.call @cld_liq_init(%tfreeze) : (memref<!ccpp_utils.real_kind<"kind_phys">>) -> (memref<?x?x!ccpp_utils.real_kind<"kind_phys">>, memref<!ccpp_utils.real_kind<"kind_phys">>, memref<512xi8>, memref<i32>)
// CHECK-NEXT:          "memref.copy"(%20, %cld_liq_array) : (memref<?x?x!ccpp_utils.real_kind<"kind_phys">>, memref<?x?x!ccpp_utils.real_kind<"kind_phys">>) -> ()
// CHECK-NEXT:          "memref.copy"(%21, %tcld) : (memref<!ccpp_utils.real_kind<"kind_phys">>, memref<!ccpp_utils.real_kind<"kind_phys">>) -> ()
// CHECK-NEXT:          "memref.copy"(%22, %errmsg) : (memref<512xi8>, memref<512xi8>) -> ()
// CHECK-NEXT:          "memref.copy"(%23, %errflg) : (memref<i32>, memref<i32>) -> ()
// CHECK-NEXT:        }
// CHECK-NEXT:        %24 = arith.constant 0 : i32
// CHECK-NEXT:        %25 = arith.cmpi eq, %26, %24 : i32
// CHECK-NEXT:        %26 = memref.load %errflg[] : memref<i32>
// CHECK-NEXT:        scf.if %25 {
// CHECK-NEXT:          %27, %28, %29 = func.call @cld_ice_init(%tfreeze, %cld_ice_array) : (memref<!ccpp_utils.real_kind<"kind_phys">>, memref<?x?x!ccpp_utils.real_kind<"kind_phys">>) -> (memref<?x?x!ccpp_utils.real_kind<"kind_phys">>, memref<512xi8>, memref<i32>)
// CHECK-NEXT:          "memref.copy"(%27, %cld_ice_array) : (memref<?x?x!ccpp_utils.real_kind<"kind_phys">>, memref<?x?x!ccpp_utils.real_kind<"kind_phys">>) -> ()
// CHECK-NEXT:          "memref.copy"(%28, %errmsg) : (memref<512xi8>, memref<512xi8>) -> ()
// CHECK-NEXT:          "memref.copy"(%29, %errflg) : (memref<i32>, memref<i32>) -> ()
// CHECK-NEXT:        }
// CHECK-NEXT:        %30 = "llvm.mlir.addressof"() <{global_name = @const_initialized}> : () -> !llvm.ptr
// CHECK-NEXT:        %31 = "llvm.load"(%30) <{ordering = 0 : i64}> : (!llvm.ptr) -> !llvm.array<16 x i8>
// CHECK-NEXT:        %32 = "llvm.mlir.addressof"() <{global_name = @ccpp_suite_state}> : () -> !llvm.ptr
// CHECK-NEXT:        "llvm.store"(%31, %32) <{ordering = 0 : i64}> : (!llvm.array<16 x i8>, !llvm.ptr) -> ()
// CHECK-NEXT:        func.return %const_index, %errmsg, %errflg, %tcld : memref<i32>, memref<512xi8>, memref<i32>, memref<!ccpp_utils.real_kind<"kind_phys">>
// CHECK-NEXT:      }
// CHECK-LABEL:     func.func public @cld_suite_suite_finalize() -> (memref<i32>, memref<512xi8>) {
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
// CHECK-NEXT:          "ccpp_utils.write_errmsg"(%errmsg, %8) <{prefix = "Invalid initial CCPP state, '", suffix = "' in cld_suite_finalize"}> : (memref<512xi8>, !llvm.array<16 x i8>) -> ()
// CHECK-NEXT:          %9 = arith.constant 1 : i32
// CHECK-NEXT:          memref.store %9, %errflg[] : memref<i32>
// CHECK-NEXT:        }
// CHECK-NEXT:        %10 = "llvm.mlir.addressof"() <{global_name = @const_uninitialized}> : () -> !llvm.ptr
// CHECK-NEXT:        %11 = "llvm.load"(%10) <{ordering = 0 : i64}> : (!llvm.ptr) -> !llvm.array<16 x i8>
// CHECK-NEXT:        %12 = "llvm.mlir.addressof"() <{global_name = @ccpp_suite_state}> : () -> !llvm.ptr
// CHECK-NEXT:        "llvm.store"(%11, %12) <{ordering = 0 : i64}> : (!llvm.array<16 x i8>, !llvm.ptr) -> ()
// CHECK-NEXT:        func.return %errflg, %errmsg : memref<i32>, memref<512xi8>
// CHECK-NEXT:      }
// CHECK-LABEL:     func.func public @cld_suite_suite_physics(%const_std_name : memref<?xi8>, %num_consts : memref<i32>, %test_stdname_array : memref<?xi8>, %const_inds : memref<?xi32>, %col_start : memref<i32>, %col_end : memref<i32>, %timestep : memref<!ccpp_utils.real_kind<"kind_phys">>, %tcld : memref<!ccpp_utils.real_kind<"kind_phys">>, %temp : memref<?x?x!ccpp_utils.real_kind<"kind_phys">>, %qv : memref<?x?x!ccpp_utils.real_kind<"kind_phys">>, %ps : memref<?x!ccpp_utils.real_kind<"kind_phys">>, %cld_liq_tend : memref<?x?x!ccpp_utils.real_kind<"kind_phys">>, %const_tend : memref<?x?x?x!ccpp_utils.real_kind<"kind_phys">>, %const : memref<?x?x?x!ccpp_utils.real_kind<"kind_phys">>, %cld_ice_array : memref<?x?x!ccpp_utils.real_kind<"kind_phys">>) -> (memref<i32>, memref<512xi8>, memref<i32>, memref<i32>) {
// CHECK:             %const_index = "memref.alloca"() <{operandSegmentSizes = array<i32: 0, 0>}> : () -> memref<i32>
// CHECK-NEXT:        %errmsg = "memref.alloca"() <{operandSegmentSizes = array<i32: 0, 0>}> : () -> memref<512xi8>
// CHECK-NEXT:        %errflg = "memref.alloca"() <{operandSegmentSizes = array<i32: 0, 0>}> : () -> memref<i32>
// CHECK-NEXT:        %errcode = "memref.alloca"() <{operandSegmentSizes = array<i32: 0, 0>}> : () -> memref<i32>
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
// CHECK-NEXT:          "ccpp_utils.write_errmsg"(%errmsg, %13) <{prefix = "Invalid initial CCPP state, '", suffix = "' in cld_suite_physics"}> : (memref<512xi8>, !llvm.array<16 x i8>) -> ()
// CHECK-NEXT:          %14 = arith.constant 1 : i32
// CHECK-NEXT:          memref.store %14, %errflg[] : memref<i32>
// CHECK-NEXT:        }
// CHECK-NEXT:        %15 = arith.constant 0 : i32
// CHECK-NEXT:        %16 = arith.cmpi eq, %17, %15 : i32
// CHECK-NEXT:        %17 = memref.load %errflg[] : memref<i32>
// CHECK-NEXT:        scf.if %16 {
// CHECK-NEXT:          %18, %19, %20, %21 = func.call @const_indices_run(%const_std_name, %num_consts, %test_stdname_array) : (memref<?xi8>, memref<i32>, memref<?xi8>) -> (memref<i32>, memref<?xi32>, memref<512xi8>, memref<i32>)
// CHECK-NEXT:          "memref.copy"(%18, %const_index) : (memref<i32>, memref<i32>) -> ()
// CHECK-NEXT:          "memref.copy"(%19, %const_inds) : (memref<?xi32>, memref<?xi32>) -> ()
// CHECK-NEXT:          "memref.copy"(%20, %errmsg) : (memref<512xi8>, memref<512xi8>) -> ()
// CHECK-NEXT:          "memref.copy"(%21, %errflg) : (memref<i32>, memref<i32>) -> ()
// CHECK-NEXT:        }
// CHECK-NEXT:        %22 = arith.constant 0 : i32
// CHECK-NEXT:        %23 = arith.cmpi eq, %24, %22 : i32
// CHECK-NEXT:        %24 = memref.load %errflg[] : memref<i32>
// CHECK-NEXT:        scf.if %23 {
// CHECK-NEXT:          %25, %26, %27, %28, %29 = func.call @cld_liq_run(%ncol, %timestep, %tcld, %temp, %qv, %ps, %cld_liq_tend) : (memref<i32>, memref<!ccpp_utils.real_kind<"kind_phys">>, memref<!ccpp_utils.real_kind<"kind_phys">>, memref<?x?x!ccpp_utils.real_kind<"kind_phys">>, memref<?x?x!ccpp_utils.real_kind<"kind_phys">>, memref<?x!ccpp_utils.real_kind<"kind_phys">>, memref<?x?x!ccpp_utils.real_kind<"kind_phys">>) -> (memref<?x?x!ccpp_utils.real_kind<"kind_phys">>, memref<?x?x!ccpp_utils.real_kind<"kind_phys">>, memref<?x?x!ccpp_utils.real_kind<"kind_phys">>, memref<512xi8>, memref<i32>)
// CHECK-NEXT:          "memref.copy"(%25, %temp) : (memref<?x?x!ccpp_utils.real_kind<"kind_phys">>, memref<?x?x!ccpp_utils.real_kind<"kind_phys">>) -> ()
// CHECK-NEXT:          "memref.copy"(%26, %qv) : (memref<?x?x!ccpp_utils.real_kind<"kind_phys">>, memref<?x?x!ccpp_utils.real_kind<"kind_phys">>) -> ()
// CHECK-NEXT:          "memref.copy"(%27, %cld_liq_tend) : (memref<?x?x!ccpp_utils.real_kind<"kind_phys">>, memref<?x?x!ccpp_utils.real_kind<"kind_phys">>) -> ()
// CHECK-NEXT:          "memref.copy"(%28, %errmsg) : (memref<512xi8>, memref<512xi8>) -> ()
// CHECK-NEXT:          "memref.copy"(%29, %errflg) : (memref<i32>, memref<i32>) -> ()
// CHECK-NEXT:        }
// CHECK-NEXT:        %30 = arith.constant 0 : i32
// CHECK-NEXT:        %31 = arith.cmpi eq, %32, %30 : i32
// CHECK-NEXT:        %32 = memref.load %errflg[] : memref<i32>
// CHECK-NEXT:        scf.if %31 {
// CHECK-NEXT:          %33, %34, %35, %36 = func.call @apply_constituent_tendencies_run(%const_tend, %const) : (memref<?x?x?x!ccpp_utils.real_kind<"kind_phys">>, memref<?x?x?x!ccpp_utils.real_kind<"kind_phys">>) -> (memref<?x?x?x!ccpp_utils.real_kind<"kind_phys">>, memref<?x?x?x!ccpp_utils.real_kind<"kind_phys">>, memref<i32>, memref<512xi8>)
// CHECK-NEXT:          "memref.copy"(%33, %const_tend) : (memref<?x?x?x!ccpp_utils.real_kind<"kind_phys">>, memref<?x?x?x!ccpp_utils.real_kind<"kind_phys">>) -> ()
// CHECK-NEXT:          "memref.copy"(%34, %const) : (memref<?x?x?x!ccpp_utils.real_kind<"kind_phys">>, memref<?x?x?x!ccpp_utils.real_kind<"kind_phys">>) -> ()
// CHECK-NEXT:          "memref.copy"(%35, %errcode) : (memref<i32>, memref<i32>) -> ()
// CHECK-NEXT:          "memref.copy"(%36, %errmsg) : (memref<512xi8>, memref<512xi8>) -> ()
// CHECK-NEXT:        }
// CHECK-NEXT:        %37 = arith.constant 0 : i32
// CHECK-NEXT:        %38 = arith.cmpi eq, %39, %37 : i32
// CHECK-NEXT:        %39 = memref.load %errflg[] : memref<i32>
// CHECK-NEXT:        scf.if %38 {
// CHECK-NEXT:          %40, %41, %42, %43, %44 = func.call @cld_ice_run(%ncol, %timestep, %temp, %qv, %ps, %cld_ice_array) : (memref<i32>, memref<!ccpp_utils.real_kind<"kind_phys">>, memref<?x?x!ccpp_utils.real_kind<"kind_phys">>, memref<?x?x!ccpp_utils.real_kind<"kind_phys">>, memref<?x!ccpp_utils.real_kind<"kind_phys">>, memref<?x?x!ccpp_utils.real_kind<"kind_phys">>) -> (memref<?x?x!ccpp_utils.real_kind<"kind_phys">>, memref<?x?x!ccpp_utils.real_kind<"kind_phys">>, memref<?x?x!ccpp_utils.real_kind<"kind_phys">>, memref<512xi8>, memref<i32>)
// CHECK-NEXT:          "memref.copy"(%40, %temp) : (memref<?x?x!ccpp_utils.real_kind<"kind_phys">>, memref<?x?x!ccpp_utils.real_kind<"kind_phys">>) -> ()
// CHECK-NEXT:          "memref.copy"(%41, %qv) : (memref<?x?x!ccpp_utils.real_kind<"kind_phys">>, memref<?x?x!ccpp_utils.real_kind<"kind_phys">>) -> ()
// CHECK-NEXT:          "memref.copy"(%42, %cld_ice_array) : (memref<?x?x!ccpp_utils.real_kind<"kind_phys">>, memref<?x?x!ccpp_utils.real_kind<"kind_phys">>) -> ()
// CHECK-NEXT:          "memref.copy"(%43, %errmsg) : (memref<512xi8>, memref<512xi8>) -> ()
// CHECK-NEXT:          "memref.copy"(%44, %errflg) : (memref<i32>, memref<i32>) -> ()
// CHECK-NEXT:        }
// CHECK-NEXT:        func.return %const_index, %errmsg, %errflg, %errcode : memref<i32>, memref<512xi8>, memref<i32>, memref<i32>
// CHECK-NEXT:      }
// CHECK-LABEL:     func.func public @cld_suite_suite_timestep_initial() -> (memref<i32>, memref<512xi8>) {
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
// CHECK-NEXT:          "ccpp_utils.write_errmsg"(%errmsg, %8) <{prefix = "Invalid initial CCPP state, '", suffix = "' in cld_suite_timestep_initial"}> : (memref<512xi8>, !llvm.array<16 x i8>) -> ()
// CHECK-NEXT:          %9 = arith.constant 1 : i32
// CHECK-NEXT:          memref.store %9, %errflg[] : memref<i32>
// CHECK-NEXT:        }
// CHECK-NEXT:        %10 = "llvm.mlir.addressof"() <{global_name = @const_in_time_step}> : () -> !llvm.ptr
// CHECK-NEXT:        %11 = "llvm.load"(%10) <{ordering = 0 : i64}> : (!llvm.ptr) -> !llvm.array<16 x i8>
// CHECK-NEXT:        %12 = "llvm.mlir.addressof"() <{global_name = @ccpp_suite_state}> : () -> !llvm.ptr
// CHECK-NEXT:        "llvm.store"(%11, %12) <{ordering = 0 : i64}> : (!llvm.array<16 x i8>, !llvm.ptr) -> ()
// CHECK-NEXT:        func.return %errflg, %errmsg : memref<i32>, memref<512xi8>
// CHECK-NEXT:      }
// CHECK-LABEL:     func.func public @cld_suite_suite_timestep_final() -> (memref<i32>, memref<512xi8>) {
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
// CHECK-NEXT:          "ccpp_utils.write_errmsg"(%errmsg, %8) <{prefix = "Invalid initial CCPP state, '", suffix = "' in cld_suite_timestep_final"}> : (memref<512xi8>, !llvm.array<16 x i8>) -> ()
// CHECK-NEXT:          %9 = arith.constant 1 : i32
// CHECK-NEXT:          memref.store %9, %errflg[] : memref<i32>
// CHECK-NEXT:        }
// CHECK-NEXT:        %10 = "llvm.mlir.addressof"() <{global_name = @const_initialized}> : () -> !llvm.ptr
// CHECK-NEXT:        %11 = "llvm.load"(%10) <{ordering = 0 : i64}> : (!llvm.ptr) -> !llvm.array<16 x i8>
// CHECK-NEXT:        %12 = "llvm.mlir.addressof"() <{global_name = @ccpp_suite_state}> : () -> !llvm.ptr
// CHECK-NEXT:        "llvm.store"(%11, %12) <{ordering = 0 : i64}> : (!llvm.array<16 x i8>, !llvm.ptr) -> ()
// CHECK-NEXT:        func.return %errflg, %errmsg : memref<i32>, memref<512xi8>
// CHECK-NEXT:      }
// CHECK-LABEL:     func.func private @const_indices_init(memref<?xi8>, memref<i32>, memref<?xi8>) -> (memref<i32>, memref<?xi32>, memref<512xi8>, memref<i32>)
// CHECK-LABEL:     func.func private @cld_liq_init(memref<!ccpp_utils.real_kind<"kind_phys">>) -> (memref<?x?x!ccpp_utils.real_kind<"kind_phys">>, memref<!ccpp_utils.real_kind<"kind_phys">>, memref<512xi8>, memref<i32>)
// CHECK-LABEL:     func.func private @cld_ice_init(memref<!ccpp_utils.real_kind<"kind_phys">>, memref<?x?x!ccpp_utils.real_kind<"kind_phys">>) -> (memref<?x?x!ccpp_utils.real_kind<"kind_phys">>, memref<512xi8>, memref<i32>)
// CHECK-LABEL:     func.func private @const_indices_run(memref<?xi8>, memref<i32>, memref<?xi8>) -> (memref<i32>, memref<?xi32>, memref<512xi8>, memref<i32>)
// CHECK-LABEL:     func.func private @cld_liq_run(memref<i32>, memref<!ccpp_utils.real_kind<"kind_phys">>, memref<!ccpp_utils.real_kind<"kind_phys">>, memref<?x?x!ccpp_utils.real_kind<"kind_phys">>, memref<?x?x!ccpp_utils.real_kind<"kind_phys">>, memref<?x!ccpp_utils.real_kind<"kind_phys">>, memref<?x?x!ccpp_utils.real_kind<"kind_phys">>) -> (memref<?x?x!ccpp_utils.real_kind<"kind_phys">>, memref<?x?x!ccpp_utils.real_kind<"kind_phys">>, memref<?x?x!ccpp_utils.real_kind<"kind_phys">>, memref<512xi8>, memref<i32>)
// CHECK-LABEL:     func.func private @apply_constituent_tendencies_run(memref<?x?x?x!ccpp_utils.real_kind<"kind_phys">>, memref<?x?x?x!ccpp_utils.real_kind<"kind_phys">>) -> (memref<?x?x?x!ccpp_utils.real_kind<"kind_phys">>, memref<?x?x?x!ccpp_utils.real_kind<"kind_phys">>, memref<i32>, memref<512xi8>)
// CHECK-LABEL:     func.func private @cld_ice_run(memref<i32>, memref<!ccpp_utils.real_kind<"kind_phys">>, memref<?x?x!ccpp_utils.real_kind<"kind_phys">>, memref<?x?x!ccpp_utils.real_kind<"kind_phys">>, memref<?x!ccpp_utils.real_kind<"kind_phys">>, memref<?x?x!ccpp_utils.real_kind<"kind_phys">>) -> (memref<?x?x!ccpp_utils.real_kind<"kind_phys">>, memref<?x?x!ccpp_utils.real_kind<"kind_phys">>, memref<?x?x!ccpp_utils.real_kind<"kind_phys">>, memref<512xi8>, memref<i32>)
// CHECK:         }
// CHECK-LABEL:   builtin.module @cld_ccpp_cap {
// CHECK:           "llvm.mlir.global"() <{global_type = !llvm.array<1 x i8>, sym_name = "const_std_name", linkage = #llvm.linkage<"external">, addr_space = 0 : i32}> ({
// CHECK-NEXT:      }) {module = "test_host_data"} : () -> ()
// CHECK-NEXT:      "llvm.mlir.global"() <{global_type = !llvm.array<1 x i8>, sym_name = "num_consts", linkage = #llvm.linkage<"external">, addr_space = 0 : i32}> ({
// CHECK-NEXT:      }) {module = "test_host_data"} : () -> ()
// CHECK-NEXT:      "llvm.mlir.global"() <{global_type = !llvm.array<1 x i8>, sym_name = "std_name_array", linkage = #llvm.linkage<"external">, addr_space = 0 : i32}> ({
// CHECK-NEXT:      }) {module = "test_host_data"} : () -> ()
// CHECK-NEXT:      "llvm.mlir.global"() <{global_type = !llvm.array<1 x i8>, sym_name = "const_inds", linkage = #llvm.linkage<"external">, addr_space = 0 : i32}> ({
// CHECK-NEXT:      }) {module = "test_host_data"} : () -> ()
// CHECK-NEXT:      "llvm.mlir.global"() <{global_type = !llvm.array<1 x i8>, sym_name = "dt", linkage = #llvm.linkage<"external">, addr_space = 0 : i32}> ({
// CHECK-NEXT:      }) {module = "test_host_mod"} : () -> ()
// CHECK-NEXT:      "llvm.mlir.global"() <{global_type = !llvm.array<9 x i8>, sym_name = "str_cld_suite", linkage = #llvm.linkage<"internal">, addr_space = 0 : i32, constant, value = "cld_suite"}> ({
// CHECK-NEXT:      }) : () -> ()
// CHECK-NEXT:      "llvm.mlir.global"() <{global_type = !llvm.array<7 x i8>, sym_name = "str_physics", linkage = #llvm.linkage<"internal">, addr_space = 0 : i32, constant, value = "physics"}> ({
// CHECK-NEXT:      }) : () -> ()
// CHECK-LABEL:     func.func public @Cld_ccpp_physics_initialize(%suite_name : memref<?xi8>) -> (memref<512xi8>, memref<i32>) {
// CHECK:             %errmsg = "memref.alloca"() <{operandSegmentSizes = array<i32: 0, 0>}> : () -> memref<512xi8>
// CHECK-NEXT:        %errflg = "memref.alloca"() <{operandSegmentSizes = array<i32: 0, 0>}> : () -> memref<i32>
// CHECK-NEXT:        %0 = arith.constant 0 : i32
// CHECK-NEXT:        memref.store %0, %errflg[] : memref<i32>
// CHECK-NEXT:        %1 = "ccpp_utils.trim"(%suite_name) : (memref<?xi8>) -> memref<?xi8>
// CHECK-NEXT:        %2 = "ccpp_utils.strcmp"(%1) <{literal = "cld_suite"}> : (memref<?xi8>) -> i1
// CHECK-NEXT:        scf.if %2 {
// CHECK-NEXT:          %3, %4, %5, %6, %7, %8 = func.call @cld_suite_suite_initialize() : () -> (memref<i32>, memref<i32>, memref<512xi8>, memref<i32>, memref<!ccpp_utils.real_kind<"kind_phys">>, memref<!ccpp_utils.real_kind<"kind_phys">>)
// CHECK-NEXT:          "memref.copy"(%3, %errflg) : (memref<i32>, memref<i32>) -> ()
// CHECK-NEXT:          "memref.copy"(%4, %errflg) : (memref<i32>, memref<i32>) -> ()
// CHECK-NEXT:          "memref.copy"(%5, %errmsg) : (memref<512xi8>, memref<512xi8>) -> ()
// CHECK-NEXT:          "memref.copy"(%6, %errflg) : (memref<i32>, memref<i32>) -> ()
// CHECK-NEXT:        } else {
// CHECK-NEXT:          "ccpp_utils.write_errmsg"(%errmsg, %1) <{prefix = "No suite named ", suffix = "found"}> : (memref<512xi8>, memref<?xi8>) -> ()
// CHECK-NEXT:          %9 = arith.constant 1 : i32
// CHECK-NEXT:          memref.store %9, %errflg[] : memref<i32>
// CHECK-NEXT:        }
// CHECK-NEXT:        func.return %errmsg, %errflg : memref<512xi8>, memref<i32>
// CHECK-NEXT:      }
// CHECK-LABEL:     func.func public @Cld_ccpp_physics_finalize(%suite_name : memref<?xi8>) -> (memref<512xi8>, memref<i32>) {
// CHECK:             %errmsg = "memref.alloca"() <{operandSegmentSizes = array<i32: 0, 0>}> : () -> memref<512xi8>
// CHECK-NEXT:        %errflg = "memref.alloca"() <{operandSegmentSizes = array<i32: 0, 0>}> : () -> memref<i32>
// CHECK-NEXT:        %0 = arith.constant 0 : i32
// CHECK-NEXT:        memref.store %0, %errflg[] : memref<i32>
// CHECK-NEXT:        %1 = "ccpp_utils.trim"(%suite_name) : (memref<?xi8>) -> memref<?xi8>
// CHECK-NEXT:        %2 = "ccpp_utils.strcmp"(%1) <{literal = "cld_suite"}> : (memref<?xi8>) -> i1
// CHECK-NEXT:        scf.if %2 {
// CHECK-NEXT:          func.call @cld_suite_suite_finalize() : () -> ()
// CHECK-NEXT:        } else {
// CHECK-NEXT:          "ccpp_utils.write_errmsg"(%errmsg, %1) <{prefix = "No suite named ", suffix = "found"}> : (memref<512xi8>, memref<?xi8>) -> ()
// CHECK-NEXT:          %3 = arith.constant 1 : i32
// CHECK-NEXT:          memref.store %3, %errflg[] : memref<i32>
// CHECK-NEXT:        }
// CHECK-NEXT:        func.return %errmsg, %errflg : memref<512xi8>, memref<i32>
// CHECK-NEXT:      }
// CHECK-LABEL:     func.func public @Cld_ccpp_physics_timestep_initial(%suite_name : memref<?xi8>) -> (memref<512xi8>, memref<i32>) {
// CHECK:             %errmsg = "memref.alloca"() <{operandSegmentSizes = array<i32: 0, 0>}> : () -> memref<512xi8>
// CHECK-NEXT:        %errflg = "memref.alloca"() <{operandSegmentSizes = array<i32: 0, 0>}> : () -> memref<i32>
// CHECK-NEXT:        %0 = arith.constant 0 : i32
// CHECK-NEXT:        memref.store %0, %errflg[] : memref<i32>
// CHECK-NEXT:        %1 = "ccpp_utils.trim"(%suite_name) : (memref<?xi8>) -> memref<?xi8>
// CHECK-NEXT:        %2 = "ccpp_utils.strcmp"(%1) <{literal = "cld_suite"}> : (memref<?xi8>) -> i1
// CHECK-NEXT:        scf.if %2 {
// CHECK-NEXT:          %3, %4 = func.call @cld_suite_suite_timestep_initial() : () -> (memref<i32>, memref<512xi8>)
// CHECK-NEXT:          "memref.copy"(%3, %errflg) : (memref<i32>, memref<i32>) -> ()
// CHECK-NEXT:          "memref.copy"(%4, %errmsg) : (memref<512xi8>, memref<512xi8>) -> ()
// CHECK-NEXT:        } else {
// CHECK-NEXT:          "ccpp_utils.write_errmsg"(%errmsg, %1) <{prefix = "No suite named ", suffix = "found"}> : (memref<512xi8>, memref<?xi8>) -> ()
// CHECK-NEXT:          %5 = arith.constant 1 : i32
// CHECK-NEXT:          memref.store %5, %errflg[] : memref<i32>
// CHECK-NEXT:        }
// CHECK-NEXT:        func.return %errmsg, %errflg : memref<512xi8>, memref<i32>
// CHECK-NEXT:      }
// CHECK-LABEL:     func.func public @Cld_ccpp_physics_timestep_final(%suite_name : memref<?xi8>) -> (memref<512xi8>, memref<i32>) {
// CHECK:             %errmsg = "memref.alloca"() <{operandSegmentSizes = array<i32: 0, 0>}> : () -> memref<512xi8>
// CHECK-NEXT:        %errflg = "memref.alloca"() <{operandSegmentSizes = array<i32: 0, 0>}> : () -> memref<i32>
// CHECK-NEXT:        %0 = arith.constant 0 : i32
// CHECK-NEXT:        memref.store %0, %errflg[] : memref<i32>
// CHECK-NEXT:        %1 = "ccpp_utils.trim"(%suite_name) : (memref<?xi8>) -> memref<?xi8>
// CHECK-NEXT:        %2 = "ccpp_utils.strcmp"(%1) <{literal = "cld_suite"}> : (memref<?xi8>) -> i1
// CHECK-NEXT:        scf.if %2 {
// CHECK-NEXT:          %3, %4 = func.call @cld_suite_suite_timestep_final() : () -> (memref<i32>, memref<512xi8>)
// CHECK-NEXT:          "memref.copy"(%3, %errflg) : (memref<i32>, memref<i32>) -> ()
// CHECK-NEXT:          "memref.copy"(%4, %errmsg) : (memref<512xi8>, memref<512xi8>) -> ()
// CHECK-NEXT:        } else {
// CHECK-NEXT:          "ccpp_utils.write_errmsg"(%errmsg, %1) <{prefix = "No suite named ", suffix = "found"}> : (memref<512xi8>, memref<?xi8>) -> ()
// CHECK-NEXT:          %5 = arith.constant 1 : i32
// CHECK-NEXT:          memref.store %5, %errflg[] : memref<i32>
// CHECK-NEXT:        }
// CHECK-NEXT:        func.return %errmsg, %errflg : memref<512xi8>, memref<i32>
// CHECK-NEXT:      }
// CHECK-LABEL:     func.func public @Cld_ccpp_physics_run(%suite_name : memref<?xi8>, %suite_part : memref<?xi8>, %col_start : memref<i32>, %col_end : memref<i32>, %tcld : memref<!ccpp_utils.real_kind<"kind_phys">>, %temp : memref<?x?x!ccpp_utils.real_kind<"kind_phys">>, %qv : memref<?x?x!ccpp_utils.real_kind<"kind_phys">>, %ps : memref<?x!ccpp_utils.real_kind<"kind_phys">>, %cld_liq_tend : memref<?x?x!ccpp_utils.real_kind<"kind_phys">>, %const_tend : memref<?x?x?x!ccpp_utils.real_kind<"kind_phys">>, %const : memref<?x?x?x!ccpp_utils.real_kind<"kind_phys">>, %cld_ice_array : memref<?x?x!ccpp_utils.real_kind<"kind_phys">>, %errmsg : memref<512xi8>, %errflg : memref<i32>) -> (memref<512xi8>, memref<i32>) {
// CHECK:             %0 = arith.constant 0 : i32
// CHECK-NEXT:        memref.store %0, %errflg[] : memref<i32>
// CHECK-NEXT:        %1 = "ccpp_utils.trim"(%suite_name) : (memref<?xi8>) -> memref<?xi8>
// CHECK-NEXT:        %2 = "ccpp_utils.strcmp"(%1) <{literal = "cld_suite"}> : (memref<?xi8>) -> i1
// CHECK-NEXT:        scf.if %2 {
// CHECK-NEXT:          %3 = "ccpp_utils.host_var_ref"() <{var_name = "const_std_name", module_name = "test_host_data"}> : () -> memref<?xi8>
// CHECK-NEXT:          %4 = "ccpp_utils.host_var_ref"() <{var_name = "num_consts", module_name = "test_host_data"}> : () -> memref<i32>
// CHECK-NEXT:          %5 = "ccpp_utils.host_var_ref"() <{var_name = "std_name_array", module_name = "test_host_data"}> : () -> memref<?xi8>
// CHECK-NEXT:          %6 = "ccpp_utils.host_var_ref"() <{var_name = "const_inds", module_name = "test_host_data"}> : () -> memref<?xi32>
// CHECK-NEXT:          %7 = "ccpp_utils.host_var_ref"() <{var_name = "dt", module_name = "test_host_mod"}> : () -> memref<!ccpp_utils.real_kind<"kind_phys">>
// CHECK-NEXT:          %8 = "ccpp_utils.trim"(%suite_part) : (memref<?xi8>) -> memref<?xi8>
// CHECK-NEXT:          %9 = "ccpp_utils.strcmp"(%8) <{literal = "physics"}> : (memref<?xi8>) -> i1
// CHECK-NEXT:          scf.if %9 {
// CHECK-NEXT:            %10, %11, %12, %13 = func.call @cld_suite_suite_physics(%3, %4, %5, %6, %col_start, %col_end, %7, %tcld, %temp, %qv, %ps, %cld_liq_tend, %const_tend, %const, %cld_ice_array) : (memref<?xi8>, memref<i32>, memref<?xi8>, memref<?xi32>, memref<i32>, memref<i32>, memref<!ccpp_utils.real_kind<"kind_phys">>, memref<!ccpp_utils.real_kind<"kind_phys">>, memref<?x?x!ccpp_utils.real_kind<"kind_phys">>, memref<?x?x!ccpp_utils.real_kind<"kind_phys">>, memref<?x!ccpp_utils.real_kind<"kind_phys">>, memref<?x?x!ccpp_utils.real_kind<"kind_phys">>, memref<?x?x?x!ccpp_utils.real_kind<"kind_phys">>, memref<?x?x?x!ccpp_utils.real_kind<"kind_phys">>, memref<?x?x!ccpp_utils.real_kind<"kind_phys">>) -> (memref<i32>, memref<512xi8>, memref<i32>, memref<i32>)
// CHECK-NEXT:            "memref.copy"(%10, %errflg) : (memref<i32>, memref<i32>) -> ()
// CHECK-NEXT:            "memref.copy"(%11, %errmsg) : (memref<512xi8>, memref<512xi8>) -> ()
// CHECK-NEXT:            "memref.copy"(%12, %errflg) : (memref<i32>, memref<i32>) -> ()
// CHECK-NEXT:            "memref.copy"(%13, %errflg) : (memref<i32>, memref<i32>) -> ()
// CHECK-NEXT:          } else {
// CHECK-NEXT:            "ccpp_utils.write_errmsg"(%errmsg, %8) <{prefix = "No suite part named ", suffix = " found in suite cld_suite"}> : (memref<512xi8>, memref<?xi8>) -> ()
// CHECK-NEXT:            %14 = arith.constant 1 : i32
// CHECK-NEXT:            memref.store %14, %errflg[] : memref<i32>
// CHECK-NEXT:          }
// CHECK-NEXT:        } else {
// CHECK-NEXT:          "ccpp_utils.write_errmsg"(%errmsg, %1) <{prefix = "No suite named ", suffix = "found"}> : (memref<512xi8>, memref<?xi8>) -> ()
// CHECK-NEXT:          %15 = arith.constant 1 : i32
// CHECK-NEXT:          memref.store %15, %errflg[] : memref<i32>
// CHECK-NEXT:        }
// CHECK-NEXT:        func.return %errmsg, %errflg : memref<512xi8>, memref<i32>
// CHECK-NEXT:      }
// CHECK-LABEL:     func.func public @ccpp_physics_suite_list(%suites : memref<memref<?xi8>>) {
// CHECK:             %0 = arith.constant 9 : index
// CHECK-NEXT:        %1 = memref.alloc(%0) : memref<?xi8>
// CHECK-NEXT:        %2 = "llvm.mlir.addressof"() <{global_name = @str_cld_suite}> : () -> !llvm.ptr
// CHECK-NEXT:        %3 = "llvm.load"(%2) <{ordering = 0 : i64}> : (!llvm.ptr) -> !llvm.array<9 x i8>
// CHECK-NEXT:        "ccpp_utils.set_string"(%1, %3) : (memref<?xi8>, !llvm.array<9 x i8>) -> ()
// CHECK-NEXT:        memref.store %1, %suites[] : memref<memref<?xi8>>
// CHECK-NEXT:        func.return
// CHECK-NEXT:      }
// CHECK-LABEL:     func.func public @ccpp_physics_suite_part_list(%suite_name : memref<?xi8>, %part_list : memref<memref<?xi8>>) -> (memref<512xi8>, memref<i32>) {
// CHECK:             %errmsg = "memref.alloca"() <{operandSegmentSizes = array<i32: 0, 0>}> : () -> memref<512xi8>
// CHECK-NEXT:        %errflg = "memref.alloca"() <{operandSegmentSizes = array<i32: 0, 0>}> : () -> memref<i32>
// CHECK-NEXT:        %0 = arith.constant 0 : i32
// CHECK-NEXT:        memref.store %0, %errflg[] : memref<i32>
// CHECK-NEXT:        %1 = "ccpp_utils.trim"(%suite_name) : (memref<?xi8>) -> memref<?xi8>
// CHECK-NEXT:        %2 = "ccpp_utils.strcmp"(%1) <{literal = "cld_suite"}> : (memref<?xi8>) -> i1
// CHECK-NEXT:        scf.if %2 {
// CHECK-NEXT:          %3 = arith.constant 7 : index
// CHECK-NEXT:          %4 = memref.alloc(%3) : memref<?xi8>
// CHECK-NEXT:          %5 = "llvm.mlir.addressof"() <{global_name = @str_physics}> : () -> !llvm.ptr
// CHECK-NEXT:          %6 = "llvm.load"(%5) <{ordering = 0 : i64}> : (!llvm.ptr) -> !llvm.array<7 x i8>
// CHECK-NEXT:          "ccpp_utils.set_string"(%4, %6) : (memref<?xi8>, !llvm.array<7 x i8>) -> ()
// CHECK-NEXT:          memref.store %4, %part_list[] : memref<memref<?xi8>>
// CHECK-NEXT:        } else {
// CHECK-NEXT:          "ccpp_utils.write_errmsg"(%errmsg, %1) <{prefix = "No suite named ", suffix = " found"}> : (memref<512xi8>, memref<?xi8>) -> ()
// CHECK-NEXT:          %7 = arith.constant 1 : i32
// CHECK-NEXT:          memref.store %7, %errflg[] : memref<i32>
// CHECK-NEXT:        }
// CHECK-NEXT:        func.return %errmsg, %errflg : memref<512xi8>, memref<i32>
// CHECK-NEXT:      }
// CHECK-LABEL:     func.func private @cld_suite_suite_initialize() -> (memref<i32>, memref<i32>, memref<512xi8>, memref<i32>, memref<!ccpp_utils.real_kind<"kind_phys">>, memref<!ccpp_utils.real_kind<"kind_phys">>) attributes {module = "cld_suite_cap"}
// CHECK-LABEL:     func.func private @cld_suite_suite_finalize() -> () attributes {module = "cld_suite_cap"}
// CHECK-LABEL:     func.func private @cld_suite_suite_timestep_initial() -> (memref<i32>, memref<512xi8>) attributes {module = "cld_suite_cap"}
// CHECK-LABEL:     func.func private @cld_suite_suite_timestep_final() -> (memref<i32>, memref<512xi8>) attributes {module = "cld_suite_cap"}
// CHECK-LABEL:     func.func private @cld_suite_suite_physics(memref<?xi8>, memref<i32>, memref<?xi8>, memref<?xi32>, memref<i32>, memref<i32>, memref<!ccpp_utils.real_kind<"kind_phys">>, memref<!ccpp_utils.real_kind<"kind_phys">>, memref<?x?x!ccpp_utils.real_kind<"kind_phys">>, memref<?x?x!ccpp_utils.real_kind<"kind_phys">>, memref<?x!ccpp_utils.real_kind<"kind_phys">>, memref<?x?x!ccpp_utils.real_kind<"kind_phys">>, memref<?x?x?x!ccpp_utils.real_kind<"kind_phys">>, memref<?x?x?x!ccpp_utils.real_kind<"kind_phys">>, memref<?x?x!ccpp_utils.real_kind<"kind_phys">>) -> (memref<i32>, memref<512xi8>, memref<i32>, memref<i32>) attributes {module = "cld_suite_cap"}
// CHECK:         }
// CHECK-LABEL:   builtin.module @ccpp_kinds {
// CHECK:           "ccpp_utils.kind_def"() <{kind_name = "kind_phys", kind_value = "REAL64"}> : () -> ()
// CHECK-NEXT:    }
// CHECK-NEXT:  }
