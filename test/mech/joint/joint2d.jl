using Amaru
using Test

# mesh generation

bl  = Block2D( [0 0; 0.2 0.1], nx=2, ny=6, cellshape=QUAD4)
msh = Mesh(bl, verbose=true)
generate_joints!(msh)
iptag!(msh.cells[:joints], "jips")

# finite element analysis

E = 27.e6

mats = [
    MaterialBind(:solids, ElasticSolid(E=E, nu=0.2)),
    MaterialBind(:joints, MCJoint(E=E, nu=0.2, ft=2.4e3, mu=1.4, alpha=1.0, wc=1.7e-4, ws=1.85e-5, softcurve="hordijk" ) ),
    #MaterialBind(:joints, ElasticJoint(E=E, nu=0.2, alpha=5), iptag="jnt_ip" ),
]

# Loggers
logger = IpLogger("jips")

dom = Domain(msh, mats, logger, model_type=:plane_stress, thickness=1.0)

# Boundary conditions
bcs = [
       FaceBC(:(x==0), :(ux=0, uy=0 )),
       FaceBC(:(x==0.2), :(ux=2.0*1.7e-4)),
      ]

@test solve!(dom, bcs, autoinc=true, nincs=20, maxits=3, tol=0.01, verbose=true, scheme=:ME, nouts=10)

save(dom, "dom1.vtk")
