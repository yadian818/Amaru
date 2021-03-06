# This file is part of Amaru package. See copyright license in https://github.com/NumSoftware/Amaru

export Orthotropic

mutable struct OrthotropicIpState<:IpState
    shared_data::SharedAnalysisData
    σ::Tensor2
    ε::Tensor2
    fmax::Float64

    unloading::Bool  # flag for loading/unloading conditions
    crushed::Bool    # flag for crashing in compression
    nfails::Int64    # number of failures
    active_fails::Array{Int64,1} # indices for active failure planes
    active_fails::Array{Bool,1} # active_fails = [ true, false, true ]
    V1::Array{Float64,1} # first  failure plane normal
    V2::Array{Float64,1} # second failure plane normal
    V3::Array{Float64,1} # third  failure plane normal

    function OrthotropicIpState(shared_data::SharedAnalysisData=SharedAnalysisData()) 
        this = new(shared_data)
        this.σ  = zeros(6)
        this.ε  = zeros(6)
        this.fmax = 0.0
        this.unloading = true
        this.crushed   = false

        this.V1 = zeros(3)
        this.V2 = zeros(3)
        this.V3 = zeros(3)
        this.nfails= 0
        this
    end
end

mutable struct Orthotropic<:Material
    E0::Float64  # Young's modulus
    ν ::Float64  # Poisson ratio
    ft::Float64  # compression strenght
    fc::Float64  # tensile strenght
    fu::Float64  # ultimate compression strenght
    εc::Float64  # strain corresponding to compression strenght
    εu::Float64  # strain corresponding to ultimate compression strenght
    α ::Float64  # hydrostatic multiplier for the loading function (similar do DP model)
    ηn::Float64  # reduction factor for normal stiffness components
    ηs::Float64  # reduction factor for shear stiffness components

    function Orthotropic(prms::Dict{Symbol,Float64})
        return Orthotropic(;prms...)
    end

    function Orthotropic(;E=NaN, nu=0.0, ft=0.0, fc=0.0, fu=0.0, epsc=0.0, epsu=0.0, alpha=0.4, etan=0.001, etas=0.5)
        @assert E>0.0       
        @assert 0.0<=nu<0.5 
        @assert fc>0.0      
        @assert ft>0.0      
        @assert fu<fc       
        @assert alpha>0     
        @assert epsc>0      
        @assert epsu>epsc  # εu>εc
        @assert etan>0     # ηn
        @assert etas>0     # ηs
        
        this = new(E, nu, ft, fc, fu, epsc, epsu, alpha, etan, etas)
        return this 
    end
end

matching_elem_type(::Orthotropic) = MechSolid

# Create a new instance of Ip data
new_ip_state(mat::Orthotropic, shared_data::SharedAnalysisData) = OrthotropicIpState(shared_data)

function set_state(ipd::OrthotropicIpState; sig=zeros(0), eps=zeros(0))
    if length(sig)==6
        ipd.σ[:] = sig.*V2M
    else
        if length(sig)!=0; error("Orthotropic: Wrong size for stress array: $sig") end
    end
    if length(eps)==6
        ipd.ε[:] = eps.*V2M
    else
        if length(eps)!=0; error("Orthotropic: Wrong size for strain array: $eps") end
    end
end


function loading_func(mat::Orthotropic, σ::Tensor2)
    j2d = J2D(σ)
    j1  = J1(σ)
    return √j2d + mat.α*j1
end


function sigma(mat::Orthotropic, εp::Float64)
    # εp : principal strain
    # σp : principal stress

    E0 = mat.E0
    Eu = mat.fu/mat.εu
    Es = mat.fc/mat.εc
    p  = mat.εu/mat.εc
    A = ( E0/Eu + (p^3-2*p^2)*E0/Es - (2*p^3-3*p^2+1) ) / (p^3-2*p^2+p)
    B = 2*E0/Es - 3 - 2*A
    C = 2 - E0/Es + A
    ξ = εp/mat.εc
    return (E0/Es*ξ) / ( 1 + A*ξ + B*ξ^2 + C*ξ^3) * mat.fc
end


function uniaxial_young_modulus(mat::Orthotropic, εp::Float64, γ1::Float64=1.0)
    # εp : principal strain
    # σp : principal stress

    gamma = 1.0 # factor for strains
    εp = γ1*gamma*εp
    εu = γ1*gamma*mat.εu

    E0 = mat.E0
    Eu = mat.fu/mat.εu
    Es = mat.fc/mat.εc
    p  = mat.εu/mat.εc
    A = ( E0/Eu + (p^3-2*p^2)*E0/Es - (2*p^3-3*p^2+1) ) / (p^3-2*p^2+p)
    B = 2*E0/Es - 3 - 2*A
    C = 2 - E0/Es + A
    ξ = εp/mat.εc
    E = E0*(1 - B*ξ^2 - 2*C*ξ^3) / ( 1 + A*ξ + B*ξ^2 + C*ξ^3)^2
    return E
end

function gamma1(mat::Orthotropic, σp1::Float64, σp2::Float64)
    # Calculate the amplifying factor γ1 for compression strenght due to confinning stresses σp1 and σp2

    λ = σp1/(-mat.fc)
    β = σp2/(-mat.fc)

    λ<0 || β<0 && return 1.0

    p1 = [ 1.2, 1.2 ]
    p2 = [ 0.8, 1.25 ]
    p3 = [ 0.0, 1.0 ]

    p1λ = p1 .+ 0.55*λ/0.25*normalize([1.0 , 1.0])
    p2λ = p2 .+ 0.50*λ/0.25*normalize([0.75, 1.0])
    p2λ = p2 .+ 0.50*λ/0.25*normalize([0.75, 1.0])

    gamma1 = p1λ[2] * (β-p2λ[1]) * (β-p3λ[1]) / ( (p1λ[1]-p2λ[1]) * (p1λ[1]-p3λ[1]) ) +
             p2λ[2] * (β-p1λ[1]) * (β-p3λ[1]) / ( (p2λ[1]-p1λ[1]) * (p2λ[1]-p3λ[1]) ) +
             p3λ[2] * (β-p1λ[1]) * (β-p2λ[1]) / ( (p3λ[1]-p1λ[1]) * (p3λ[1]-p2λ[1]) )

    @assert gamma1>=1

    return gamma1
end

#=
function eigen_with_fixed_dir(σ::Tensor2, Z::Array{Float64,1})
    # σ: Stress tensor
    # Z: Fixed direction

    # find an arbitrary system aligned with Z
    Q = [1., 0 , 0] # auxiliary vector
    if Z==Q
        Q = [0., 1, 0 ]
    end
    X = normalize(cross(Z, Q))
    Y = normalize(cross(Z, X))
    W = [X Y Z] # arbitrary system

    # fourth order rotation tensor
    R = zeros(6,6)
    tensor_rot!(W, R)

    # new temporary tensor
    σt = R*σ
    σz = σt[3]

    lt, Vt = eig( [ σt[1] σt[6]; σt[6] σ[2] ]  )

    # 2D to 3D
    Dt = eye(3)
    Dt[1:2,1:2] .= Vt # new matrix with orthogonal directions

    # new tensor
    V = W*Dt  # new directions in the xyz system
    L  = [ L; λ ]  # new orthotropic stresses
    p = sortperm(L, rev=true)

    # sorting results
    L = L[p]
    V = V[:,p]
    V[:,3] = cross(V[:,1], V[:,2])


    return L, V, index

end =#


function eigen_with_fixed_dir(σ::Tensor2, X::Array{Float64,1})
    # Finds two eigenvectors normal do X. Vector X is returned as the first direction
    #
    # σ: Stress tensor
    # Z: Fixed direction

    # find an arbitrary system aligned with Z
    Q = [1., 0 , 0] # auxiliary vector
    if X==Q
        Q = [0., 1, 0 ]
    end
    Y = normalize(cross(X, Q))
    Z = normalize(cross(X, Y))
    W = [X Y Z] # arbitrary system

    # fourth order rotation tensor
    R = zeros(6,6)
    tensor_rot!(W, R)

    # new temporary tensor
    σt = R*σ
    σx = σt[1]

    lt, Vt = eig( [ σt[2] σt[4]; σt[4] σ[3] ]  )

    # 2D to 3D
    Dt = eye(3)
    Dt[2:3,2:3] .= Vt # new matrix with orthogonal directions

    # new tensor
    V = W*Dt  # new directions in the xyz system
    L  = [ σx; lt ]  # new orthotropic stresses
    return L, V

end


function fixD(mat, D::Array{Float64,2}, active_fails::Array{Bool,1})
    #for i in active_fails
    for (i,active) in enumerate(active_fails)
        !active && continue

        D[i,1:3] *= ηn
        D[1:3,i] *= ηn
        if i==1
            D[5,5] *= ηs
            D[6,6] *= ηs
        elseif i==2
            D[4,4] *= ηs
            D[6,6] *= ηs
        elseif i==3
            D[4,4] *= ηs
            D[5,5] *= ηs
        end
    end

    return D
end


function calcD(mat::Orthotropic, ipd::OrthotropicIpState)

    nactive_fails = length(ipd.active_fails)

    if !ips.crushed && nactive_fails==0 # no fails
        if ipd.unloading
            # isotrophic
            D = calcDe(mat.E0, mat.ν, ipd.shared_data.model_type)
            return D
        else # loading
            σp, V = eig(ipd.σ)
            p  = sortperm(σp, rev=true)
            σp = σp[p] # ordered stresses
            V  = V[:,p]

            R = zeros(6,6)
            tensor_rot!(V, R)
            εp = R*ipd.ε # strain associated with σp

            γ1  = gamma1(mat, σp[1], σp[2])
            fcm = γ1*mat.fc

            Ep1 = uniaxial_young_modulus(mat, εp[1], γ1)
            Ep2 = uniaxial_young_modulus(mat, εp[2], γ1)
            Ep3 = uniaxial_young_modulus(mat, εp[3], γ1)

            κ = 0.4
            if σp[3] >= κ*fcm # σc'  low compression

                Et = ( abs(σp[1])*Ep1 + abs(σp[2])*Ep2 + abs(σp[3])*Ep3 ) / (abs(σp[1]) + abs(σp[2]) + abs(σp[3]))
                D = calcDe(Et, mat.ν, ipd.shared_data.model_type)
                return D

            else # σp[3]<κ*fcmax high compression

                E12 = ( σp[1]*Ep1 + σp[2]*Ep2 ) / ( σp[1] + σp[2] )
                E23 = ( σp[2]*Ep1 + σp[3]*Ep2 ) / ( σp[2] + σp[3] )
                E13 = ( σp[1]*Ep1 + σp[3]*Ep2 ) / ( σp[1] + σp[3] )

                # Orthotropic D matrix
                # Notice that Amaru considers a general shear stress components (e.g. εxy)
                # and not the engineering definitions (e.g, γxy).
                Dp = 1/((1+ν)*(1-2*ν))*[ (1-ν)*Ep1   ν*E12       ν*E13      0.0          0.0          0.0 
                                         ν*E12       (1-ν)*Ep2   ν*E23      0.0          0.0          0.0 
                                         ν*E13       ν*E23      (1-ν)*Ep3   0.0          0.0          0.0 
                                         0.0         0.0         0.0        (1-2*ν)*E12  0.0          0.0
                                         0.0         0.0         0.0        0.0          (1-2*ν)*E13  0.0  
                                         0.0         0.0         0.0        0.0          0.0          (1-2*ν)*E23 ]

                D = R'*Dp*R # rotates tensor Dp to xyz system
                return D
            end
        end

    elseif ipd.crushed
        D = eye(6,6)*ipd.ηn
        return D
    else # nactive_fails>0
        if nfixed_planes==1
            σp, V = eigen_with_fixed_dir(ipd.σ, ipd.V1) # V1 should be the first column of V
        else # nfixed_planes == 3
            V = [ ipd.V1 ipd.V2 ipd.V3 ]
            R = zeros(6,6)
            tensor_rot!(V, R)
            σp = R*ipd.σ # stresses associated with V1, V2 and V3
        end

        # sort principal stresses
        p  = sortperm(σp, rev=true)
        σp = σp[p] # ordered stresses
        V  = V[:,p]
        active_fails = ipd.active_fails[p]
        R  = zeros(6,6)
        tensor_rot!(V, R)

        if ipd.unloading

            # Matrix D based on plane stress conditions
            E = ipd.E
            ν = ipd.ν
            Dp = E/(1-ν^2)*[ 1.0    ν       ν      0.0    0.0    0.0 
                             ν      1.0     ν      0.0    0.0    0.0 
                             ν      ν       1.0    0.0    0.0    0.0 
                             0.0    0.0     0.0    (1-ν)  0.0    0.0
                             0.0    0.0     0.0    0.0    (1-ν)  0.0  
                             0.0    0.0     0.0    0.0    0.0    (1-ν) ]
        else # loading

            εp  = R*ipd.ε # strain associated with σp
            γ1  = gamma1(mat, σp[1], σp[2])
            fcm = γ1*mat.fc

            Ep1 = uniaxial_young_modulus(mat, εp[1], γ1)
            Ep2 = uniaxial_young_modulus(mat, εp[2], γ1)
            Ep3 = uniaxial_young_modulus(mat, εp[3], γ1)

            κ = 0.4

            if σp[3] >= κ*fcm # σc'  low compression
                Et = ( abs(σp[1])*Ep1 + abs(σp[2])*Ep2 + abs(σp[3])*Ep3 ) / (abs(σp[1]) + abs(σp[2]) + abs(σp[3]))
                Ep1 = Ep2 = Ep3 = E12 = E23 = E13 = Et
            else
                E12 = ( σp[1]*Ep1 + σp[2]*Ep2 ) / ( σp[1] + σp[2] )
                E23 = ( σp[2]*Ep1 + σp[3]*Ep2 ) / ( σp[2] + σp[3] )
                E13 = ( σp[1]*Ep1 + σp[3]*Ep2 ) / ( σp[1] + σp[3] )
            end

            # Orthotropic D matrix considering plane stress conditions
            D = 1.0/(1-ν^2)*[ Ep1    ν*E12   ν*E13  0.0        0.0        0.0 
                              ν*E12  Ep2     ν*E23  0.0        0.0        0.0 
                              ν*E13  ν*E23   Ep3    0.0        0.0        0.0 
                              0.0    0.0     0.0    (1-ν)*E12  0.0        0.0
                              0.0    0.0     0.0    0.0        (1-ν)*E13  0.0  
                              0.0    0.0     0.0    0.0        0.0        (1-ν)*E23 ]

        end

        # Fix D
        fixD(mat, Dp, active_fails)
        D = R'*Dp*R # rotates tensor Dp to xyz system
        return D

    end

end


function stress_update(mat::Orthotropic, ipd::OrthotropicIpState, Δε::Array{Float64,1})
    nactive_fails = length(ipd.active_fails)
    ipd.εp += Δε

    if !ips.crushed && nactive_fails==0 # no fails
        σp, V = eigen(ipd.σ)
        R  = zeros(6,6)
        tensor_rot!(V, R)
        εp = R*ipd.ε

        D = calcD(mat, ipd)
        Δσ = D*Δε
    elseif ipd.crushed
        if nfixed_planes==0
            σp, V = eigen(ipd.σ)
        elseif nfixed_planes==1
            σp, V = eigen_with_fixed_dir(ipd.σ, ipd.V1) # V1 should be the first column of V
        else # nfixed_planes == 3
            V = [ ipd.V1 ipd.V2 ipd.V3 ]
        end

        R  = zeros(6,6)
        tensor_rot!(V, R)
        εp = R*ipd.ε
        if min(εp) > mat.εu
            Δσ = -ipd.σ
        else
            # use Eq. 23 ####################
        end

    else # nactive_fails>0
        D = calcD(mat, ipd)
        Δσ = D*Δε

        if nfixed_planes==1
            σp, V = eigen_with_fixed_dir(ipd.σ, ipd.V1) # V1 should be the first column of V
        else # nfixed_planes == 3
            V = [ ipd.V1 ipd.V2 ipd.V3 ]
        end

        R  = zeros(6,6)
        tensor_rot!(V, R)
        εp = R*ipd.ε

    end

    # Check for new failure planes

    # Check for failure plane deactivation

    # Check for compression crushing

    # Release appropriate stresses


    ipd.σ += Δσ
    return Δσ
end







function stress_update(mat::Orthotropic, ipd::OrthotropicIpState, Δε::Array{Float64,1})

    σp, V = eig(ipd.σ)
    T   = tensor_rot(V)
    εp  = T*ipd.ε
    Δεp = T*Δε

    gamma1 = fcmax(mat,σp[1], σp[2])
    fcm    = gamma1*mat.fc
    
    Ep1 = gamma1*( sigma(mat, ipd.ε[1]+Δεp[1]) - sigma(mat, ipd.ε[1]) ) / Δεp[1]
    Ep2 = gamma1*( sigma(mat, ipd.ε[2]+Δεp[2]) - sigma(mat, ipd.ε[2]) ) / Δεp[2]
    Ep3 = gamma1*( sigma(mat, ipd.ε[3]+Δεp[3]) - sigma(mat, ipd.ε[3]) ) / Δεp[3]

    κ = 0.4
    fcm = fcmax(mat,σp[1], σp[2])
    if σp[3] >= κ*fcm # σc'
        Et = ( abs(σp[1])*Ep1 + abs(σp[2])*Ep2 + abs(σp[3])*Ep3 ) / (abs(σp[1]) + abs(σp[2]) + abs(σp[3]))
        ν = mat.ν

        active_dirs = [1,2,3]

        if nactive==0
            D = Et/((1+ν)*(1-2*ν))*[ (1-ν)   ν      ν      0.0          0.0          0.0 
                                     ν       (1-ν)  ν      0.0          0.0          0.0 
                                     ν       ν      (1-ν)  0.0          0.0          0.0 
                                     0.0     0.0    0.0    0.5*(1-2*ν)  0.0          0.0
                                     0.0     0.0    0.0    0.0          0.5*(1-2*ν)  0.0  
                                     0.0     0.0    0.0    0.0          0.0          0.5*(1-2*ν) ]
        else
            D = Et/(1-ν^2)*[ 1.0    ν       ν      0.0        0.0        0.0 
                             ν      1.0     ν      0.0        0.0        0.0 
                             ν      ν       1.0    0.0        0.0        0.0 
                             0.0    0.0     0.0    0.5*(1-ν)  0.0        0.0
                             0.0    0.0     0.0    0.0        0.5*(1-ν)  0.0  
                             0.0    0.0     0.0    0.0        0.0        0.5*(1-ν) ]
            D = fixD(D, ipd.active_fails)
            D = T'*D*T
        end

        return D





#=
        D = Et/((1+ν)*(1-2*ν))*[ (1-ν)   ν      ν      0.0              0.0              0.0 
                                  ν      (1-ν)  ν      0.0              0.0              0.0 
                                  ν      ν      (1-ν)  0.0              0.0              0.0 
                                  0.0    0.0    0.0    0.5*(1-2*ν)      0.0              0.0
                                  0.0    0.0    0.0    0.0              0.5*(1-2*ν)      0.0  
                                  0.0    0.0    0.0    0.0              0.0              0.5*(1-2*ν)]
=#

        # tensile failure
        ft = mat.ft
        if σp[1] > ft
                
            ηn = mat.ηn
            ηs = mat.ηs


            E12 = ( σp[1]*Ep1 + σp[2]*Ep2 ) / ( σp[1] + σp[2] )
            E23 = ( σp[2]*Ep1 + σp[3]*Ep2 ) / ( σp[2] + σp[3] )
            E13 = ( σp[1]*Ep1 + σp[3]*Ep2 ) / ( σp[1] + σp[3] )


            if nactive==0
                D = 1/((1+ν)*(1-2*ν))*[ (1-ν)*Ep1   ν*E12       ν*E13       0.0              0.0              0.0 
                                        ν*E12       (1-ν)*Ep2   ν*E23       0.0              0.0              0.0 
                                        ν*E13       ν*Ep23      (1-ν)*Ep3   0.0              0.0              0.0 
                                        0.0         0.0         0.0         0.5*(1-2*ν)*E12  0.0              0.0
                                        0.0         0.0         0.0         0.0              0.5*(1-2*ν)*E13  0.0  
                                        0.0         0.0         0.0         0.0              0.0              0.5*(1-2*ν)*E23 ]
            else
                D = 1.0/(1-ν^2)*[ Ep1    ν*E12   ν*E13  0.0            0.0            0.0 
                                  ν*E12  Ep2     ν*E23  0.0            0.0            0.0 
                                  ν*E13  ν*E23   Ep3    0.0            0.0            0.0 
                                  0.0    0.0     0.0    0.5*(1-ν)*E12  0.0            0.0
                                  0.0    0.0     0.0    0.0            0.5*(1-ν)*E13  0.0  
                                  0.0    0.0     0.0    0.0            0.0            0.5*(1-ν)*E23 ]
                D = fixD(D, ipd.active_fails)
                D = T'*D*T
            end
            return D
#=
            D = Et/(1-ν^2)*[ ηn     ν*ηn    ν*ηn   0.0           0.0           0.0 
                             ν*ηn   1.0     ν      0.0           0.0           0.0 
                             ν*ηn   ν       1.0    0.0           0.0           0.0 
                             0.0    0.0     0.0    0.5*ηs*(1-ν)  0.0           0.0
                             0.0    0.0     0.0    0.0           0.5*ηs*(1-ν)  0.0  
                             0.0    0.0     0.0    0.0           0.0           0.5*(1-ν)]
            
            return T'*D*T
            D = T'*D*T
=#
        end

        Δσ = D*Δε
        ipd.σ += Δσ
        return Δσ






    else
        E12 = ( σp[1]*Ep1 + σp[2]*Ep2 ) / ( σp[1] + σp[2] )
        E23 = ( σp[2]*Ep1 + σp[3]*Ep2 ) / ( σp[2] + σp[3] )
        E13 = ( σp[1]*Ep1 + σp[3]*Ep2 ) / ( σp[1] + σp[3] )


        D = 1/((1+ν)*(1-2*ν))*[ (1-ν)*Ep1   ν*E12       ν*E13       0.0              0.0              0.0 
                                ν*E12       (1-ν)*Ep2   ν*E23       0.0              0.0              0.0 
                                ν*E13       ν*E23      (1-ν)*Ep3   0.0              0.0              0.0 
                                0.0         0.0         0.0         0.5*(1-2*ν)*E12  0.0              0.0
                                0.0         0.0         0.0         0.0              0.5*(1-2*ν)*E13  0.0  
                                0.0         0.0         0.0         0.0              0.0              0.5*(1-2*ν)*E23 ]

        # tensile failure in higth compression
        if σ[1] > ft

            D = 1/(1+ν^2)*[ ηn*Ep1    ν*ηn*E12   ν*ηn*E13  0.0               0.0               0.0 
                            E12       Ep2        ν*ηn*E23  0.0               0.0               0.0 
                            ν*ηn*E13  ν*ηn*Ep23  Ep3       0.0               0.0               0.0 
                            0.0       0.0        0.0       0.5*ηs*(1-ν)*E12  0.0               0.0
                            0.0       0.0        0.0       0.0               0.5*ηs*(1-ν)*E13  0.0  
                            0.0       0.0        0.0       0.0               0.0               0.5*ηs*(1-ν)*E23 ]
            
            return D
        end
        return T'*D*T
        D = T'*D*T

        Δσ = D*Δε
        ipd.σ += Δσ
        return Δσ
    end


end





function ip_state_vals(mat::Orthotropic, ipd::OrthotropicIpState)
    ndim  = ipd.shared_data.ndim
    σ, ε  = ipd.σ, ipd.ε
    j1    = trace(σ)
    srj2d = √J2D(σ)

    D = stress_strain_dict(σ, ε, ndim)

    return D
end


