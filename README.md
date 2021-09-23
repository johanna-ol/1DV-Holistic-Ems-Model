# 1DV-Holistic-Ems-Model

To run the model open Ems_1DV.m

Ems_1DV.m - main program with model settings
cDGL.p - equation solver for sediment transport equation
omegaDGL.p - equation solver for omega equation
tkeDGL.p - equation solver for turbulent kinetic energy equation
vDGL.p - equation solver for momentum balance
change_c.p - mass conservation if number of cells changes
UpdateVerticalDiscretisation.p - size of cells is adjusted to current water level
dfdz.p - function for calculating first order derivatives
tideM2M4.p - tidal acceleration from M2 and M4 tidal components
