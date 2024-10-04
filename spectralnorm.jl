#=
The Computer Language Benchmarks Game
https://salsa.debian.org/benchmarksgame-team/benchmarksgame/
contributed by Adam Beckmeyer with help from Vincent Yu
tweaked for AOT compilation by Mason Protter
=#

using Printf, PrecompileTools

A(i, j) = (i + j - 2) * (i + j - 1) / 2 + i
At(i, j) = A(j, i)

# Multiply vector v by the matrix represented by function f (f(i, j) returns the element in
# i-th row and j-th column) and store result in out
function mul_by_f!(f, v, out)
    n = length(v)
    # Threads.@threads has lower overhead than Threads.@spawn
    Threads.@threads :static for i=1:n
        x1 = x2 = 0.0
        # If we used the @simd macro instead of manually iterating by 2s, the compiler would
        # emit instructions using the ymm registers instead of xmm which appears to be
        # slower on ivybridge cpus
        @inbounds for j=1:2:n
            # Manually convert indices to Float64 so that arithmetic in function f can be
            # carried out using vectorized  floating point arithmetic
            x1 += v[j] / f(Float64(i), Float64(j))
            x2 += v[j+1] / f(Float64(i), Float64(j+1))
        end
        @inbounds out[i] = x1 + x2
    end
end

# Multiply vector v by matrix A and store result in out
mul_by_A!(v, out) = mul_by_f!(A, v, out)

# Multiply vector v by matrix A' and store result in out
mul_by_At!(v, out) = mul_by_f!(At, v, out)

# Multiply v by (A' * A) and store result in out using w as a temporary workspace
function mul_by_AtA!(v, out, w)
    mul_by_A!(v, w)
    mul_by_At!(w, out)
end

function snorm(n)
    # This program is not compatible with odd values of n
    isodd(n) && (n += 1)

    u = ones(Float64, n)
    v = Vector{Float64}(undef, n)
    # temporary working vector w
    w = Vector{Float64}(undef, n)

    for _=1:10
        mul_by_AtA!(u, v, w)
        mul_by_AtA!(v, u, w)
    end

    uv = vv = 0.0
    @inbounds for i=1:n
        uv += u[i] * v[i]
        vv += v[i] * v[i]
    end
    sqrt(uv / vv)
end 

function (@main)(args)
    n = parse(Int, args[1])
    @printf("%.9f\n", snorm(n))
    0
end

Base.@ccallable function main(argc::Cint, argv::Ptr{Ptr{UInt8}})::Cint
    args = Vector{String}(undef, argc - 1)
    for i in 2:argc
        argptr = unsafe_load(argv, i)
        arg = unsafe_string(argptr)
        args[i - 1] = arg
    end
    main(args)
end
Base.Experimental.entrypoint(main, (Cint, Ptr{Ptr{UInt8}}))

@setup_workload begin
    args = ["50"]
    @compile_workload begin
        # trace through a basic version of the program during AOT compilation
        # this is necessary because of the `@printf` calls being
        # opaque to type inference, so we need to actually run the code and then
        # record which methods get hit so they end up in the compilation
        # cache
        main(args)
    end
end


