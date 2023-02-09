module SlurmManagers

using Distributed
using Sockets
using MKL, LinearAlgebra
export launch, manage, kill, init_worker, connect, SlurmManager, addprocs_slurm, rm_all_procs
import Distributed: launch, manage, kill, init_worker, connect

include("slurmscript.jl")

end