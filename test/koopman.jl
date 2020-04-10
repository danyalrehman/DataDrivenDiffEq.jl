
@testset "DMD" begin
    # Create some linear data
    A = [0.9 -0.2; 0.0 0.2]
    y = [[10.; -10.]]
    for i in 1:10
        push!(y, A*y[end])
    end
    X = hcat(y...)
    @test_throws AssertionError ExactDMD(X[:, 1:end-2], dt = -1.0)
    estimator = ExactDMD(X[:,1:end-2])
    @test isstable(estimator)

    @test operator(estimator) ≈ A
    @test eigvals(estimator) ≈ eigvals(A)
    @test eigvecs(estimator) ≈ eigvecs(A)

    @test isupdateable(estimator)
    @test !islifted(estimator)
    @test_nowarn dynamics(estimator)
    @test_throws AssertionError dynamics(estimator, force_continouos = true)
    @test_nowarn update!(estimator, X[:, end-1], X[:,end], threshold = 0.0)

    # Add Linear ODE
    function linear(du, u, p, t)
        du[1] = -0.9*u[1]
        du[2] = -0.1*u[2] + 0.2*u[1]
    end

    u0 = [10.0; -1.0]
    prob = ODEProblem(linear, u0, (0.0, 10.0))
    sol = solve(prob, Tsit5(), saveat = 0.1)

    estimator = ExactDMD(sol[:,:], dt = 0.1)
    @test_nowarn estimator(u0, [], 0.0)
    du0 = similar(u0)
    @test_nowarn estimator(du0, [], 0.0)
    @test estimator(u0, [], 0.0) ≈ [-0.9 0.0; 0.2 -0.1]*u0 atol = 1e-2
    approx_p = ODEProblem(estimator, u0, (0.0, 10.0))
    sol_ = solve(approx_p, Tsit5(), saveat = 0.1)
    @test sol_[:,:] ≈ sol[:,:] atol = 1e-2
end


@testset "EDMD" begin
    # Test for linear system
    function linear_sys(u, p, t)
        x = -0.9*u[1]
        y = -0.3*u[2]
        return [x;y]
    end

    u0 = [π; 1.0]
    tspan = (0.0, 20.0)
    prob = DiscreteProblem(linear_sys, u0, tspan)
    sol = solve(prob,FunctionMap())

    @variables u[1:2]
    h = [1u[1]; 1u[2]; sin(u[1]); cos(u[1]); u[1]*u[2]]
    basis = Basis(h, u)

    @test_throws AssertionError ExtendedDMD(sol[:,:], basis, dt = -1.0)
    estimator = ExtendedDMD(sol[:,:], basis)
    @test basis == lifting(estimator)
    @test islifted(estimator)
    basis_2 = reduce_basis(estimator, threshold = 1e-5)
    dg = zeros(5)
    lifting(estimator)(dg, u0, [], 0.0)
    @test dg ≈ lifting(estimator)(u0, [], 0.0)
    du = zeros(2)
    outputmap(estimator)(du, dg, [], 0.0)
    @test du ≈ outputmap(estimator)(dg, [], 0.0)
    @test size(basis_2)[1] < size(basis)[1]

    estimator_2 = ExtendedDMD(sol[:,:], basis_2)
    p1 = DiscreteProblem(dynamics(estimator)[1], u0, tspan, [])
    s1 = solve(p1,FunctionMap())
    p2 = DiscreteProblem(dynamics(estimator_2)[2], u0, tspan, [])
    s2 = solve(p2,FunctionMap())
    p3 = DiscreteProblem(linear_dynamics(estimator_2)[1], basis_2(u0), tspan, [])
    s3 = solve(p3,FunctionMap())
    @test sol[:,:] ≈ s1[:,:]
    @test sol[:,:] ≈ s2[:,:]
    @test basis_2(sol[:,:])≈ s3[:,:]
    @test eigvals(estimator_2) ≈ [-0.9; -0.3]
    @test_nowarn lifting(estimator_2)
    @test_nowarn outputmap(estimator_2)

    # Test for nonlinear system
    function nonlinear_sys(du, u, p, t)
        du[1] = sin(u[1])
        du[2] = -0.3*u[2] -0.9*u[1]
    end

    basis = Basis(h[1:3], u)
    prob = DiscreteProblem(nonlinear_sys, u0, tspan)
    sol = solve(prob,FunctionMap())
    estimator = ExtendedDMD(sol[:,:], basis)
    p4 = DiscreteProblem(dynamics(estimator)[2], u0, tspan, [])
    s4 = solve(p4,FunctionMap())
    @test sol[:,:] ≈ s4[:,:]

    # Add non-basis test
    f_(x::AbstractVector, p, t) = [x[1]; x[2]; sin(x[1])]
    f_(x::AbstractArray, p, t) = hcat(map(xi->f_(xi,p,t), eachcol(x)))

    estimator = ExtendedDMD(sol[:,:], f_)
    p5 = DiscreteProblem(dynamics(estimator)[1], u0, tspan, [])
    s5 = solve(p5,FunctionMap())
    @test sol[:,:] ≈ s5[:,:]
    @test_throws AssertionError reduce_basis(estimator)

end


@testset "DMDc" begin
    # Define measurements from unstable system with known control input
    X = [4 2 1 0.5 0.25; 7 0.7 0.07 0.007 0.0007]
    U = [-4 -2 -1 -0.5]
    B = [1; 0]

    # But with a little more knowledge
    sys = DMDc(X, U, B = B)
    @test operator(sys) ≈[1.5 0; 0 0.1]
    @test inputmap(sys)(1.0, [], 0.0) ≈ [1.0; 0.0]
    @test !isstable(sys)
    @test_nowarn eigen(sys)
    @test iscontrolled(sys)

    # Check the solution of an unforced and forced system against each other
    #dudt_ = dynamics(sys)
    #prob = DiscreteProblem(dudt_, X[:, 1], (0., 10.))
    #sol_unforced = solve(prob,  FunctionMap())

    #dudt_ = dynamics(sys, control = (u, p, t) -> -0.5u[1])
    #prob = DiscreteProblem(dudt_, X[:, 1], (0., 10.))
    #sol = solve(prob, FunctionMap())

    #@test all(abs.(diff(sol[1,:])) .< 1e-5)
    #@test sol[2,:] ≈ sol_unforced[2,:]
end