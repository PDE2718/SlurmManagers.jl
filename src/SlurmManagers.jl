module SlurmManagers

using Distributed
using Sockets
using Pkg

export launch, manage, kill, init_worker, connect
import Distributed: launch, manage, kill, init_worker, connect

worker_cookie() = begin
    Distributed.init_multi()
    cluster_cookie()
end
worker_arg() = `--worker=$(worker_cookie())`

# ClusterManager for Slurm

export SlurmManager, addprocs_slurm, rm_all_procs

import Logging.@warn

struct SlurmManager <: ClusterManager
    np::Integer
    retry_delays
end

struct SlurmException <: Exception
    msg
end

function launch(manager::SlurmManager, params::Dict, instances_arr::Array,
    c::Condition)
    try
        exehome = params[:dir]
        exename = params[:exename]
        exeflags = params[:exeflags]

        stdkeys = keys(Distributed.default_addprocs_params())

        p = filter(x -> (!(x[1] in stdkeys) && x[1] != :job_file_loc), params)
        cpus_per_task = params[:cpus_per_task]

        srunargs = []
        for k in keys(p)
            if length(string(k)) == 1
                push!(srunargs, "-$k")
                val = p[k]
                if length(val) > 0
                    push!(srunargs, "$(p[k])")
                end
            else
                k2 = replace(string(k), "_" => "-")
                val = p[k]
                if length(val) > 0
                    push!(srunargs, "--$(k2)=$(p[k])")
                else
                    push!(srunargs, "--$(k2)")
                end
            end
        end

        # Get job file location from parameter dictionary.
        job_file_loc = joinpath(exehome, get(params, :job_file_loc, "."))

        # Make directory if not already made.
        if !isdir(job_file_loc)
            mkdir(job_file_loc)
        end

        np = manager.np
        jobname = "julia-$(getpid())"
        job_output_name = "$(jobname)-$(trunc(Int, Base.time() * 10))"
        make_job_output_path(task_num) = joinpath(job_file_loc, "$(job_output_name)-$(task_num).out")
        job_output_template = make_job_output_path("%4t")
        srun_cmd = `srun -J $jobname -n $np -o "$(job_output_template)" -D $exehome $(srunargs) --export=JULIA_NUM_THREADS=$(cpus_per_task) $exename $exeflags $(worker_arg())`
        srun_proc = open(srun_cmd)
        slurm_spec_regex = r"([\w]+):([\d]+)#(\d{1,3}.\d{1,3}.\d{1,3}.\d{1,3})"
        retry_delays = manager.retry_delays
        for i = 0:np-1
            println("connecting to worker $(i + 1) out of $np")
            slurm_spec_match = nothing
            fn = make_job_output_path(lpad(i, 4, "0"))
            t0 = time()
            for retry_delay in retry_delays
                # Wait for output log to be created and populated, then parse
                if isfile(fn) && filesize(fn) > 0
                    slurm_spec_match = open(fn) do f
                        # Due to error and warning messages, the specification
                        # may not appear on the file's first line
                        for line in eachline(f)
                            re_match = match(slurm_spec_regex, line)
                            if re_match !== nothing
                                return re_match    # only returns from do-block
                            end
                        end
                    end
                    if slurm_spec_match !== nothing
                        break   # break if specification found
                    end
                end
                # Sleep for some time to limit ressource usage while waiting for the job to start
                sleep(retry_delay)
            end

            if slurm_spec_match === nothing
                throw(SlurmException("Timeout while trying to connect to worker"))
            end

            config = WorkerConfig()
            config.port = parse(Int, slurm_spec_match[2])
            config.host = strip(slurm_spec_match[3])
            # Keep a reference to the proc, so it's properly closed once
            # the last worker exits.
            config.userdata = srun_proc
            push!(instances_arr, config)
            notify(c)
        end
    catch e
        println("Error launching Slurm job:")
        rethrow(e)
    end
end

function manage(manager::SlurmManager, id::Integer, config::WorkerConfig,
    op::Symbol)
    # This function needs to exist, but so far we don't do anything
end

SlurmManager(np::Integer) = SlurmManager(np, ExponentialBackOff(n=10, first_delay=1, max_delay=512, factor=2))

function addprocs_slurm(partition::String, enable_MKL=true; kwargs...)
    @assert length(workers()) == 1 "there are already remote workers"
    default_params = Dict(
        :partition => partition,
        :ntasks => 1,
        :cpus_per_task => 1,
        :threads_per_core => 1,
        :topology => :master_worker,
        :job_file_loc => pwd() * "/output",
        :t => "1000",
    )
    nkwargs = merge(NamedTuple(), merge(default_params, kwargs))
    println("[Task Summary]")
    println(nkwargs)
    @sync addprocs(SlurmManager(nkwargs[:ntasks]); nkwargs...)
    if enable_MKL
        eval(quote
            @everywhere using MKL
        end)
    end
    eval(quote
        @everywhere using LinearAlgebra, Base.Threads
        @everywhere using Hwloc:getinfo
        @everywhere function worker_info()
            info = Dict(
                "worker_id" => myid(),
                "cpu" => Sys.cpu_info()[1].model,
                "hwinfo" => getinfo(),
                "nthreads" => Threads.nthreads(),
                "blas_threads" => BLAS.get_num_threads(),
                "blas_config" => BLAS.get_config(),
                "mem_free" => Sys.free_memory() / (2^30)
            )
            return info
        end
    end)
end

function rm_all_procs()
    @sync rmprocs(workers()...)
end

end