# SlurmManagers

This repository is mostly forked from [`ClusterManagers.jl`](https://github.com/JuliaParallel/ClusterManagers.jl) for using Julia interactively on a `Slurm` cluster. I made some hacky changes.

## Changes
1. The `addprocs_slurm` function now properly deals with `cpus_per_task` argument, and set the environment variable `JULIA_NUM_THREADS` accordingly. Further more, threaded BLAS can also be enabled!
2. Add some default slurm arguments:

    ```julia
    Slurm parameter  => default value
    ntasks           => 1                  # how many process
    cpus_per_task    => 1                  # threads per process
    threads_per_core => 1                  # disable hyper-threading
    topology         => :master_worker     # architecture hint
    job_file_loc     => pwd() * "/output"  # log output (relative path)
    t                => "1000"             # unit: min
    ```

## Extra functionalities
1. Now, `Base.Threads` and `LinearAlgebra` are loaded the first when `addprocs_slurm` successful has connected all the required nodes. They are using **everywhere** which is equivalent to a statement in global scope.
    ```julia
    @everywhere using LinearAlgebra, Base.Threads
    ```
2. The `worker_info` can show the information of workers (with the package `Hwloc`) as a dictionary.
    ```julia
    "worker_id"    => myid(),                     # worker ID
    "cpu"          => Sys.cpu_info()[1].model,    # CPU model
    "hwinfo"       => getinfo(),                  # architecture info
    "nthreads"     => Threads.nthreads(),         # Julia threads
    "blas_threads" => BLAS.get_num_threads(),     # BLAS threads
    "blas_config"  => BLAS.get_config(),          # BLAS configuration
    "mem_free_GB"  => Sys.free_memory() / (2^30)  # free memory in GB
    ```
    This can be done by a `remotecall_fetch` :
    ```julia
    worker_info_i = remotecall_fetch(worker_info, i)
    ```

## Test and reliability
The functionalities are tests on a slurm cluster with Intel Xeon CPUs. We assume that `MKL.jl` is being used and by default `enable_MKL=true`. If you use open-blas, or you want to use it on a cluster with AMD CPUs, it is recommended to set `enable_MKL=false`.

## Example of usage

TODO..TODO