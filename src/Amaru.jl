# This file is part of Amaru package. See copyright license in https://github.com/NumSoftware/Amaru

__precompile__() 

"""
**Amaru.jl**

Amaru module implements functions and types to perform finite element analyses.

**Important data types**

Node, Element, Domain, Dof, Ip, NodeBC, FaceBC

**Important functions** 

set_mat, set_bc, clear_bc, solve!, save

"""
module Amaru
using  Base, JSON, Reexport
import DataStructures.OrderedDict
import DataStructures.OrderedSet

#Using non-registered (jet) package FemMesh
#Pkg.installed("FemMesh") == nothing && Pkg.clone("https://github.com/RaulDurand/FemMesh")

try
    eval(:(using FemMesh))
catch err
    if isa(err, ArgumentError)
        contains(err.msg, "FemMesh not found") && pkg.clone("https://github.com/NumSoftware/FemMesh")
    else
        error("Amaru: Error loading FemMesh package.")
    end
end

@reexport using FemMesh
import FemMesh.save # to be extended
import FemMesh.update! # to be extended
import FemMesh.get_x, FemMesh.get_y, FemMesh.get_z # to be extended
import FemMesh.tag!


# Debug
mutable struct DebugFlags
    enabled::Bool
    makeplots::Bool
end
const Debug = DebugFlags(false, true)
#export Debug


# Tools module
include("tools/constants.jl")
include("tools/math.jl")
include("tools/linalg.jl")
include("tools/expr.jl")
include("tools/table.jl")
include("tools/tensors.jl")
include("tools/functor.jl")
include("tools/show.jl")

# generic exports
export max, min, sort, reset, getindex, sort, copy!, show

# Fem module
include("shared-data.jl")
export SharedAnalysisData

include("node.jl")
export Node, Dof, add_dof, nodes_dof_vals

include("ip.jl")
export Ip, ip_vals, maximum, minimum, sort

include("material.jl")
export Material, MaterialBind, read_prms
#export matching_elem_type

include("element.jl")
export Element
export set_mat, get_nodes, get_ips, set_state, getcoords, getvals, get_map, elems_ip_vals

include("facet.jl")
export Facet, Face, Edge

include("tag.jl")
export tag!

include("bc.jl")
#export NodeBC, FaceBC, EdgeBC, apply_bc
export BC, apply_bc

include("logger.jl")
export Logger, GroupLogger
export update_logger!

include("domain.jl")
export reset!, setlogger!


# Mechanical module
include("mech/include.jl")

# Hydromechanical module
include("hydromech/include.jl")

# show functions for common structures and arrays
@show_function Dof
@show_array_function Dof
@show_function Node
@show_array_function Node
@show_function Ip
@show_array_function Ip
@show_function Element
@show_array_function Element
@show_function Material
@show_array_function Material
@show_function MaterialBind
@show_array_function MaterialBind
@show_function BC
@show_array_function BC
@show_function Facet
@show_array_function Facet
@show_function AbstractLogger
@show_array_function AbstractLogger
@show_function Domain

end#module
