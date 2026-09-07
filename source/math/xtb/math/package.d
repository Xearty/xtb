module xtb.math;

public import xtb.math.matrix;
public import xtb.math.noise;
public import xtb.math.random;
public import xtb.math.scalar;
public import xtb.math.vector;

alias min = xtb.math.scalar.min;
alias min = xtb.math.vector.min;

alias max = xtb.math.scalar.max;
alias max = xtb.math.vector.max;

alias clamp = xtb.math.scalar.clamp;
alias clamp = xtb.math.vector.clamp;

alias lerp = xtb.math.scalar.lerp;
alias lerp = xtb.math.vector.lerp;

alias isFinite = xtb.math.scalar.isFinite;
alias isFinite = xtb.math.vector.isFinite;
