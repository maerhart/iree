!in_tensor_t = tensor<?x?xf32>
!out_tensor_t = tensor<?xf32>

func.func @reduce(%arg : !in_tensor_t) -> (!out_tensor_t) {
  %c0 = arith.constant 0 : index
  %cst = arith.constant -0.000000e+00 : f32
  
  %d0 = tensor.dim %arg, %c0 : !in_tensor_t
  %0 = tensor.empty(%d0) : !out_tensor_t
  %1 = linalg.fill ins(%cst : f32) outs(%0 : !out_tensor_t) ->   !out_tensor_t
  %2 = linalg.generic {
    indexing_maps = [affine_map<(d0, d1) -> (d0, d1)>,
                     affine_map<(d0, d1) -> (d0)>],
    iterator_types = ["parallel", "reduction"]}
    ins(%arg : !in_tensor_t) outs(%1 : !out_tensor_t) {
      ^bb0(%arg3: f32, %arg4: f32):
        %3 = arith.addf %arg3, %arg4 : f32
        linalg.yield %3 : f32
      } -> !out_tensor_t
  return %2 : !out_tensor_t
}

// RUN: iree-opt %s --iree-hal-target-backends=cuda \
// RUN:     --iree-abi-transformation-pipeline \
// RUN:     --iree-flow-transformation-pipeline  \
// RUN:     --iree-stream-transformation-pipeline \
// RUN:     --iree-hal-configuration-pipeline | \
// RUN: iree-opt --pass-pipeline='builtin.module(hal.executable(hal.executable.variant(iree-llvmgpu-lower-executable-target)))' \
// RUN:     --iree-codegen-llvmgpu-use-transform-dialect=%p/reduction_v3_codegen_spec.mlir | \
// RUN: FileCheck %s --check-prefix=CHECK

// RUN: iree-compile %s --iree-hal-target-backends=cuda \
// RUN:     --iree-codegen-llvmgpu-use-transform-dialect=%p/reduction_v3_codegen_spec.mlir | \
// RUN: iree-run-module --entry_function=reduce --device=cuda --function_input="123x4567xf32=1" |\
// RUN: FileCheck %s --check-prefix=EXEC

// RUN: iree-compile %s --iree-hal-target-backends=cuda \
// RUN:     --iree-codegen-llvmgpu-enable-transform-dialect-jit | \
// RUN: iree-run-module --entry_function=reduce --device=cuda --function_input="123x4567xf32=1" |\
// RUN: FileCheck %s --check-prefix=EXEC

  //     CHECK-DAG: %[[C0:.*]] = arith.constant 0 : index
  //     CHECK-DAG: %[[workgroup_id_x:.*]] = hal.interface.workgroup.id[0] : index
  //     CHECK-DAG: %[[SHMEM_ALLOC:.*]] = memref.alloc() {alignment = 64 : i64} : memref<1x1024xf32, 3>
  
  //         CHECK: %[[TIDX:.]] = gpu.thread_id  x
  //         CHECK: %[[SHMEM_VIEW_EXPANDED:.*]] = memref.subview %[[SHMEM_ALLOC]][0, %[[TIDX]]]{{.*}}to memref<1x1xf32, strided<[1024, 1], offset: ?>, 3>
  // Local per-thread scf.for-based reduction.
  //         CHECK: scf.for
  //         CHECK:   vector.transfer_read %{{.*}} : memref<f32, strided<[], offset: ?>>, vector<f32>
  //         CHECK:   arith.addf {{.*}} : f32
  //         CHECK:   scf.yield %{{.*}} : vector<f32>

  //         CHECK: %[[TIDY:.]] = gpu.thread_id  y
  // Distributed reduction: everyone loads then 5 xor + addf expected
  //         CHECK: vector.transfer_read %{{.*}}[%[[TIDY]], %{{.*}}]
  // CHECK-COUNT-5: gpu.shuffle  xor{{.*}}{{[[:space:]].*}}{{.*}} arith.addf

  //         CHECK: %[[RES:.*]] = arith.addf %{{.*}}

  //         CHECK: %[[RES_VEC:.*]] = vector.broadcast %[[RES]] : f32 to vector<f32>
  //         CHECK: %[[CONDXIS0:.*]] = arith.cmpi eq, %[[TIDX]], %[[C0]] : index
  //         CHECK: scf.if %[[CONDXIS0]]
  //         CHECK:   vector.transfer_write %[[RES_VEC]]
  //         CHECK: gpu.barrier

// only checking the first 6 of 123
//      EXEC: result[0]: hal.buffer_view
// EXEC-NEXT: 123xf32=4567 4567 4567 4567 4567 4567