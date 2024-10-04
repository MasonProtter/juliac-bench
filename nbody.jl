# The Computer Language Benchmarks Game
# https://salsa.debian.org/benchmarksgame-team/benchmarksgame/
#
# Contributed by Andrei Fomiga, Stefan Karpinski, Viral B. Shah, Jeff
# Bezanson, smallnamespaces, Adam Beckmeyer, and Vincent Yu.
# Tweaked and modernized for AOT compilation by Mason Protter


using Base.Cartesian, Printf, PrecompileTools

# Precalculate the pairs of bodies that must be compared so that it
# doesn't have to be done each loop.

# Use a struct instead of mutable struct since a struct can be stored
# inline in an array avoiding the overhead of following a pointer
struct Body
    x::NTuple{3,Float64}
    v::NTuple{3,Float64}
    m::Float64
end


function init_sun(bodies)
    SOLAR_MASS = 4 * pi * pi
    p = (0.0, 0.0, 0.0)
    for b in bodies
        p = p .- b.v .* b.m
    end
    Body((0.0, 0.0, 0.0), p ./ SOLAR_MASS, SOLAR_MASS)
end

@generated function make_pairs()
    Tuple((i, j) for i=1:4 for j=i+1:5)
end

# Advance all bodies in the system by one timestep of 0.01. This
# function always uses a timestep of 0.01 and assumes that there are
# exactly 5 bodies in the system.
@inline function advance!(bodies)
    PAIRS = make_pairs()
    # In a system with 5 bodies, there are 10 unique pairs of
    # bodies. Δx holds the difference in position between these pairs
    # of bodies.
    Δx = @ntuple 10 k-> @inbounds bodies[PAIRS[k][1]].x .- bodies[PAIRS[k][2]].x
    dsq = @ntuple 10 k-> sum(Δx[k] .* Δx[k])

    # When called with @fastmath, 1 / sqrt(x::Float32) will use
    # SSE single-precision rsqrt approximation followed by a single
    # iteration of the Newton-Raphson method. This, followed by an
    # additional double-precision Newton-Raphson iteration gives
    # sufficient precision for this problem and is significantly
    # faster than double-precision division and sqrt.
    rd = @ntuple 10 k-> Float64(1 / sqrt(Float32(dsq[k])))
    # This is a Newton-Raphson iteration.
    rd = @ntuple 10 k-> 1.5rd[k] - 0.5dsq[k] * rd[k] * (rd[k] * rd[k])

    # Alternatively 0.01rd[k] / dsq[k] may be faster. This is what
    # other fast implementations do, but on my machine the 2
    # multiplications are faster than a single division.
    mag = @ntuple 10 k-> 0.01rd[k] * (rd[k] * rd[k])

    # Update the velocities of each body using the precalculated mag.
    k = 1
    @inbounds for i=1:4
        bi = bodies[i]
        # For body i, since velocity is the only part of the object
        # changing on each iteration, it's more efficient to update
        # outside the vector.
        iv = bi.v
        for j=i+1:5
            iv = iv .- Δx[k] .* (mag[k] * bodies[j].m)
            bodies[j] = Body(bodies[j].x,
                             bodies[j].v .+ Δx[k] .* (mag[k] * bi.m),
                             bodies[j].m)
            k += 1
        end
        bodies[i] = Body(bi.x, iv, bi.m)
    end

    # Advance body positions using the updated velocities.
    @inbounds for i=1:5
        bi = bodies[i]
        bodies[i] = Body(bi.x .+ bi.v .* 0.01, bi.v, bi.m)
    end
end

# Total energy of the system
function energy(bodies)
    PAIRS = make_pairs()
    e = 0.0
    # Kinetic energy of bodies
    @inbounds for b in bodies
        e += 0.5b.m * sum(b.v .* b.v)
    end
    
    # Potential energy between body i and body j
    @inbounds for (i, j) in PAIRS
        Δx = bodies[i].x .- bodies[j].x
        e -= bodies[i].m * bodies[j].m / √sum(Δx .* Δx)
    end
    e
end

# Mutate bodies array according to symplectic integrator in advance!
# for n iterations.
nbody!(bodies, n) = for i=1:n
    advance!(bodies)
end

function make_bodies()
    DAYS_PER_YEAR = 365.24
    SOLAR_MASS = 4 * pi * pi
    bodies = [
        # Jupiter
        Body(( 4.84143144246472090e+0,                # x
               -1.16032004402742839e+0,               # y
               -1.03622044471123109e-1),              # z
             ( 1.66007664274403694e-3DAYS_PER_YEAR,   # vx
               7.69901118419740425e-3DAYS_PER_YEAR,   # vy
               -6.90460016972063023e-5DAYS_PER_YEAR), # vz
             9.54791938424326609e-4SOLAR_MASS)        # mass
        # Saturn
        Body(( 8.34336671824457987e+0,
               4.12479856412430479e+0,
               -4.03523417114321381e-1),
             (-2.76742510726862411e-3DAYS_PER_YEAR,
              4.99852801234917238e-3DAYS_PER_YEAR,
              2.30417297573763929e-5DAYS_PER_YEAR),
             2.85885980666130812e-4SOLAR_MASS)
        # Uranus
        Body(( 1.28943695621391310e+1,
               -1.51111514016986312e+1,
               -2.23307578892655734e-1),
             ( 2.96460137564761618e-3DAYS_PER_YEAR,
               2.37847173959480950e-3DAYS_PER_YEAR,
               -2.96589568540237556e-5DAYS_PER_YEAR),
             4.36624404335156298e-5SOLAR_MASS)
        # Neptune
        Body(( 1.53796971148509165e+1,
               -2.59193146099879641e+1,
               1.79258772950371181e-1),
             ( 2.68067772490389322e-3DAYS_PER_YEAR,
               1.62824170038242295e-3DAYS_PER_YEAR,
               -9.51592254519715870e-5DAYS_PER_YEAR),
             5.15138902046611451e-5SOLAR_MASS)
    ]
    push!(bodies, init_sun(bodies))
    bodies
end

function (@main)(args)
    N = parse(Int, args[1])
    bodies = make_bodies()
    @printf("%.9f\n", energy(bodies))
    nbody!(bodies, N)
    @printf("%.9f\n", energy(bodies))
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
    args = ["10"]
    @compile_workload begin
        # trace through a basic version of the program during AOT compilation
        # this is necessary because of the `@printf` calls being
        # opaque to type inference, so we need to actually run the code and then
        # record which methods get hit so they end up in the compilation
        # cache
        main(args)
    end
end
