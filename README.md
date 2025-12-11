# InfMap2

A "productionalized" full rewrite of InfMap, built for the SSTRP gamemode and made for server owners to more easily separate map geometry from InfMap's custom coordinate system. It is not meant for SANDBOX use, though it could be easily forked to do so.

### New Features:
- Major client performance improvements (5x-10x general client renderer performance)
- Major server performance improvements (teleportation went from O(nlogn) to O(n) amortized)
- Massively improved API and codebase
- Algorithm rewrites to prevent rare bugs and undefined behavior which weren't considered during infmap1 development
- Easy to expand detouring with very minor overhead (+0.0001ms per call)
- Entities to help hammer users implement infmap into their map.
- Virtual BSP (VBSP) 'portals' to embed map geometry and seamlessly transition players in and out of the InfMap coordinate system
- High performance .png heightmaps with builtin LODs (requires server .dll)
- 64 bit chunks allowing travel up to ~450 light years in any direction

### Discarded features:
- Example Base Map
- Gravity Hull support
- prop_vehicle_jeep (and related vehicle) support
- Many detours are not fully implemented and will likely be added over time when they are needed
