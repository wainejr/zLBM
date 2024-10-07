__kernel void square_array(__global int* input_array, __global int* output_array) {
    int i = get_global_id(0);
    int value = input_array[i];
    output_array[i] = value * value;
}

__kernel void lbm_kernel(
    __global float* popA,
    __global float* popB,
    __global float* u,
    __global float* rho,
    __global float* force_ibm,
    const int time_step
) {
    // streaming (popA, popB)

    // macroscopics

    // collision

    // macroscopics
}