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

## Installation

You can install the package by running
```julia
using Pkg
Pkg.add("https://github.com/PDE2718/SlurmManagers.jl")
```

## Example of usage

#### Worker setup
First let's import some package. Please note that `MKL/LinearAlgebra` are imported everywhere implicitly when you use `SlurmManagers`. Other packages should be decorated by a `@everywhere` macro.

```julia
using MKL, LinearAlgebra
using Distributed
using SlurmManagers
```
Now, add the processes and set up the worker pool `wpool` by

```julia
addprocs_slurm("yourPartition"; ntasks=8, cpus_per_task=12)
wpool = WorkerPool(workers())
```
The test is done on a cluster where each node has two sockets **Intel Xeon Gold 6240R × 2**, **24** cores each, **48** cores in total. The slurm system automatically assigned 2 nodes, each running 4 tasks with 12 physical cores.

#### Check the workers
We can now interact with the master node and distribute our jobs dynamically! First let's check some information:
```julia
remotecall_fetch(myid, 2) # return 2
remotecall_fetch(worker_info, 3) # return a Dict
```

#### Define a job
Let's define a job `myfun` that requires some input arguments, let's say `x`. We just need to include it on each worker.

```julia
@everywhere begin
    function myfun(x::Real)
        N = 1000
        A = rand(N,N) + x*I |> Symmetric
        t = @elapsed eigvals(A)
        return t
    end
end
```

#### Assign a job to a worker
Now we can get it down on any worker by `remotecall` and `fetch`. Or more simply by a `remotecall_fetch`. For example, we pass `x=5.` to worker 4 and wait it until it finishes its job and return the result:
```julia
remotecall_fetch(myfun, 4, 5.) # return t, on the remote worker
```

#### Assign multiple jobs to all workers. (`pmap`)

```julia
xs = rand(200)

# 20 core local machine, limited to memory bridge
@elapsed myfun.(xs) # 14.27 s

# 8 worker / 12 cores each. => 96 cores in total
@elapsed @sync pmap(myfun, wpool, xs; batch_size=2) # 1.18 s
```
