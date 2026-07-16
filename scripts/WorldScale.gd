class_name WorldScale
## World scale: sim/world units per metre. The single source of truth.
## A leaf script with zero preloads, so ANY script -- including Unit.gd,
## which cannot preload Battle.gd (the documented Unit<->Battle preload
## cycle) -- can preload it without creating a cycle. Deliberately NOT an
## autoload: autoload members are not constant expressions, and this value
## exists precisely so `const` initializers elsewhere can fold
## `<metres> * WorldScaleRef.WU_PER_M` at parse time.

const WU_PER_M := 20.0
const M_PER_WU := 1.0 / WU_PER_M
