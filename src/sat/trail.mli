(** The reason type encodes {i why} an assignment by the CDCL loop was made

    The CDCL loop advances via {b propagatation} when there are unit clauses
    to force truth values for.

    The list held by [Propagated] reasons can be a singleton list in the
    unit clause case. For example [[a ^ b ^ (c v d) ^ (~c v f)]]
    will have it so that [a] is added to the trail as [Propagated [a]]
    and likewise for [b].

    Once there are no more unit propagations to be made, the loop needs to 
    {b decide} on a truth value for a disjunctive prop, in which case
    the [Decided] reason should be added to the trail. 

    Continuing with our working example, after we unit propagate, we are left with:

    [[(c v d) ^ (~c v f)]]

    Suppose CDCL solver decides [c] as the asserted literal. Then the [Decided]
    step entry will be added to the trail, and any implied propagations will
    link back to the decision via its propagated list.

    After deciding on [c], our formula has intermediate state:

    [[ (true v d) ^ (false v f) ]]

    Which simplifies to

    [[ f ]]

    Then when we propagate [f = true], its Propagate list will be:

    [[~c ; f]]

    because f was forced to be [true] because [c = true].
*)
type reason =
  | Decided
  | Propagated of Formula.literal list

(** A step of [{ level ; lit ; reason }] means the solver assigned LIT for REASON at decision LEVEL *)
type step = { level : int ; lit : Formula.literal ; reason : reason }

(** A trail is the list of steps that acts as the source of truth for the solver state *)
type trail = step list

(** [to_model trail] derives the boolean MODEL from TRAIL *)
val to_model : trail -> Model.model

(** [analyze_conflict ~conflict level trail] returns the resolved learned clause derived 
    from CONFLICT and the next highest decision level after LEVEL from a literal
    pointed to by both CONFLICT and TRAIL
*)
val analyze_conflict : conflict:Formula.clause -> int -> trail -> Formula.clause * int

(** [backtrack_learn ~conflict level trail formula] adds CONFLICT to FORMULA and filters out all steps in TRAIL > LEVEL *)
val backtrack_learn : conflict:Formula.clause -> int -> trail -> Formula.formula -> trail * Formula.formula

(** [decide lit level trail] prepends the step record { LIT ; LEVEL ; reason = Decided } to TRAIL...
    so this is really just a named cons function *)
val decide : Formula.literal -> int -> trail -> trail
