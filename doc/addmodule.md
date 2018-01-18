# Adding a physics module to MPI-AMRVAC

# MPI-AMRVAC library version

MPI-AMRVAC is organized in a library, which in essence only differs according 
to the dimensionality of the problem: the library part of the code will be compiled
in the 

    $AMRVAC_DIR/lib/2d_default 

directory, if you indicated the setup to be 2D, and used 
the default architecture settings, i.e. when your problem used 

    $AMRVAC_DIR/setup.pl -d=2 -arch=default 

or simply

    $AMRVAC_DIR/setup.pl -d=2

What is contained in this library version is controlled by the makefile called

    $AMRVAC_DIR/arch/lib.make

and this file controls which physics modules are contained in the library. To that end,
the line 

    SRC_DIRS := . modules amrvacio physics rho hd mhd particle nonlinear

could be extended with your own newly added physics module called myphysmodule through

    SRC_DIRS := . modules amrvacio physics rho hd mhd particle nonlinear myphysmodule

This must correspond to a newly created subdirectory

    $AMRVAC_DIR/src/myphysmodule

which must contain some essential files that tell MPI-AMRVAC all about the equations your module
contains. These are at least:

    $AMRVAC_DIR/src/myphysmodule/mod_myphysmodule.t
    $AMRVAC_DIR/src/myphysmodule/mod_myphysmodule_phys.t
    $AMRVAC_DIR/src/myphysmodule/mod_myphysmodule_roe.t
    $AMRVAC_DIR/src/myphysmodule/makefile

What the first three of these contain is described further on. The makefile part will specify 
which extra fortran objects the subdirectory contains, and hence in our minimal example reads 

    FOBJECTS += mod_myphysmodule_phys.t mod_myphysmodule.t mod_myphysmodule_roe.t

It is important to correspondingly update the module dependencies in the makefile found at

    $AMRVAC_DIR/src/makefile

You can either do this by hand, but a typo-proof manner to do so is to run the script 

    $AMRVAC_DIR/src/list_module_deps.sh

This produces a dependency list, which is intended to replace the part in 

    $AMRVAC_DIR/src/makefile

which follows the line mentioning

    Dependencies of FOBJECTS (generated by list_module_deps.sh)

Hence, you first edit the `$AMRVAC_DIR/src/makefile`, delete all lines below this line, and then
execute in `$AMRVAC_DIR/src` the command

    list_module_deps.sh >> makefile

Note: the actual makefile you use for a specific application is in general composed of parts collected from

1. $AMRVAC_DIR/src/makefile
2. $AMRVAC_DIR/arch/amrvac.make
3. $AMRVAC_DIR/arch/lib.make
4. $AMRVAC_DIR/arch/default.defs  [overruled by $AMRVAC_DIR/setup.pl -arch=debug which uses debug.defs instead]
5. $AMRVAC_DIR/arch/rules.make

# Physics module bare essentials

The file 

    $AMRVAC_DIR/src/myphysmodule/mod_myphysmodule.t

must specify the way to activate your physics module. At the very least, it will tell the code to use the corresponding 

    $AMRVAC_DIR/src/myphysmodule/mod_myphysmodule_phys.t

which contains info on initialization of the variables, controls the addition of new parameters and corresponding entries in the namelists. 
This is done by `subroutine myphysmodule_phys_init()`.

Furthermore, `mod_myphysmodule_phys.t` provides all info on fluxes, (geometric) source terms, etc.
See especially the examples provided by

    $AMRVAC_DIR/src/rho/mod_rho.t
    $AMRVAC_DIR/src/nonlinear/mod_nonlinear.t
    $AMRVAC_DIR/src/hd/mod_hd.t
    $AMRVAC_DIR/src/mhd/mod_mhd.t

# Adding scheme-specific info, source terms, etc

It is possible to use basic schemes like TVDLF or HLL as soon as the 

    $AMRVAC_DIR/src/myphysmodule/mod_myphysmodule_phys.t

contains the corresponding subroutines to identify the maximal and minimal characteristic wave speeds, the fluxes, and the (geometric) source terms. You are also required to specify the way to convert conservative to primitive variables, and back [if relevant for your module]. It is imperative that you use the LASY syntax to ensure that
your physics module can be compiled meaningfully in any dimensionality. 

Schemes like HLLC, Roe, etc, which require more info on the characteristic decomposition can be added as well,
following the examples provided for rho, hd, mhd modules. The same is true for source terms. The roe solver needs to be organized in the file

    $AMRVAC_DIR/src/myphysmodule/mod_myphysmodule_roe.t