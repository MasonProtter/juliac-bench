# The Computer Language Benchmarks Game
# https://salsa.debian.org/benchmarksgame-team/benchmarksgame/
#
# Contributed by Adam Beckmeyer. Based on code by Jarret Revels, Alex
# Arslan, Michal Stransky, Jens Adam.
# Tweaked for multithreading and AOT compilation by Mason Protter

using OhMyThreads, PrecompileTools

struct Node
    l::Union{Node,Nothing}
    r::Union{Node,Nothing}
end

make(n) = n === 0 ? Node(nothing, nothing) : Node(make(n-1), make(n-1))

check(node) = node.l === nothing ? 1 : 1 + check(node.l) + check(node.r)

function binary_trees(io, n)
    write(io, "stretch tree of depth $(n+1)\t check: $(check(make(n+1)))\n")

    long_tree = make(n)

    d = 4
    while d <= n
        niter = 1 << (n - d + 4)
        c = tmapreduce(+,1:niter) do _
            check(make(d))
        end
        write(io, "$niter\t trees of depth $d\t check: $c\n")
        d += 2
    end

    write(io, "long lived tree of depth $n\t check: $(check(long_tree))\n")
end


function (@main)(args)
    binary_trees(stdout, parse(Int, args[1]))
    0
end

Base.@ccallable function main(argc::Cint, argv::Ptr{Ptr{UInt8}}) :: Cint
    args = Vector{String}(undef, argc - 1)
    for i in 2:argc
        argptr = unsafe_load(argv, i)
        arg = unsafe_string(argptr)
        args[i - 1] = arg
    end
    main(args)
end
Base.Experimental.entrypoint(main, (Cint, Ptr{Ptr{UInt8}}))

@compile_workload begin
    # trace through a basic version of the program during AOT compilation
    # this is necessary because of i/o calls being
    # opaque to type inference, so we need to actually run the code and then
    # record which methods get hit so they end up in the compilation
    # cache
    binary_trees(stdout, 5)
end
