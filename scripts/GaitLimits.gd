class_name GaitLimits
## Physical motion-cap fractions shared between the sim engine and the demo-defect
## metrics that audit it against the same numbers. A leaf script with zero preloads
## of its own -- like WorldScale.gd -- so DemoDefects.gd (which must not reference
## Unit or any script that touches the Settings autoload) can read the identical
## value SoldierBodies.gd enforces, and neither side keeps its own copy of the
## literal.

## A soldier's own body can integrate at most this multiple of his unit's sprint
## pace (Unit.move_speed) in a single tick: a man cannot outrun his own sprint just
## because his formation slot is receding out from under him. SoldierBodies.step()
## clamps each body's fully-integrated velocity (march feed-forward plus arrival
## correction combined) to move_speed * this fraction; DemoDefects'
## superphysical_speed check flags any sustained excursion past the same
## threshold, so the engine and the metric agree by construction instead of by two
## separately hand-kept literals.
const SUPERPHYSICAL_SPEED_FRAC := 1.15

## Speed multiplier on move_speed while routing: fleeing soldiers run slightly faster
## than their normal sprint pace (Unit.flee_speed()). Lives here, not only on Unit, so
## DemoDefects can hold a router's bodies to the same flee-pace ceiling
## SoldierBodies.step() applies to them.
const FLEE_SPEED_MULTIPLIER := 1.3
