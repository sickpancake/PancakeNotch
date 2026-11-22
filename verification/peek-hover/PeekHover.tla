---- MODULE PeekHover ----
EXTENDS TLC

VARIABLES phase, pointer, owner, outcome, queuedHover
vars == <<phase, pointer, owner, outcome, queuedHover>>

Locations == {"strip", "ear", "away"}
Owners == {"first", "second"}
Visible == {"timed", "held", "leaving"}

Init ==
    /\ phase = "idle"
    /\ pointer = "away"
    /\ owner = "none"
    /\ outcome = <<"none", "none">>
    /\ queuedHover = FALSE

ShowPeek ==
    /\ phase # "expanded"
    /\ \E module \in Owners: owner' = module
    /\ phase' = "timed"
    /\ outcome' = <<"none", "none">>
    \* A pointer resting on an ear queued its open when it entered; the peek doesn't cancel it.
    /\ queuedHover' = (pointer = "ear")
    /\ UNCHANGED pointer

MovePointer ==
    /\ \E location \in Locations \ {pointer}:
        /\ pointer' = location
        \* Arriving on an ear queues the hover-open: an outline enter calls hoverChanged(true);
        \* leaving the strip for an ear makes updatePeekHover schedule the same open, since no
        \* enter fires inside the outline. Arriving anywhere else cancels a queued open.
        /\ queuedHover' =
            IF location = "ear" /\ phase \in Visible THEN TRUE
            ELSE IF location # "ear" THEN FALSE
            ELSE queuedHover
    /\ UNCHANGED <<phase, owner, outcome>>

Expiry ==
    /\ IF pointer = "strip"
          THEN /\ phase' = "held"
               /\ UNCHANGED outcome
          ELSE /\ phase' = "dismissing"
               /\ outcome' = <<"timeout", pointer>>
    /\ UNCHANGED <<pointer, owner>>

PeekDeadline ==
    /\ phase = "timed"
    /\ Expiry
    /\ UNCHANGED queuedHover

LeaveObserved ==
    /\ phase = "held"
    /\ pointer # "strip"
    /\ phase' = "leaving"
    /\ UNCHANGED <<pointer, owner, outcome, queuedHover>>

ReturnObserved ==
    /\ phase = "leaving"
    /\ pointer = "strip"
    /\ phase' = "held"
    /\ queuedHover' = FALSE
    /\ UNCHANGED <<pointer, owner, outcome>>

CloseDeadline ==
    /\ phase = "leaving"
    /\ Expiry
    /\ UNCHANGED queuedHover

ClickStrip ==
    /\ phase \in Visible
    /\ pointer = "strip"
    /\ phase' = "expanded"
    /\ outcome' = <<"strip opened", owner>>
    /\ queuedHover' = FALSE
    /\ UNCHANGED <<pointer, owner>>

HoverDelayEnds ==
    /\ phase \in Visible
    /\ queuedHover
    /\ queuedHover' = FALSE
    /\ IF pointer = "strip"
          THEN UNCHANGED <<phase, outcome>>
          ELSE /\ phase' = "expanded"
               /\ outcome' = <<"hover opened", pointer>>
    /\ UNCHANGED <<pointer, owner>>

OpenElsewhere ==
    /\ phase \in Visible
    /\ phase' = "expanded"
    /\ outcome' = <<"other open", "none">>
    /\ queuedHover' = FALSE
    /\ UNCHANGED <<pointer, owner>>

EndPeek ==
    /\ phase \in Visible
    /\ phase' = "dismissing"
    /\ outcome' = <<"explicit", "none">>
    /\ UNCHANGED <<pointer, owner, queuedHover>>

Clear ==
    /\ phase' = "idle"
    /\ owner' = "none"
    /\ outcome' = <<"none", "none">>
    /\ queuedHover' = FALSE
    /\ UNCHANGED pointer

FinishDismiss == phase = "dismissing" /\ Clear
CloseExpanded == phase = "expanded" /\ Clear
Reset == phase \in Visible \cup {"dismissing"} /\ Clear

Next == ShowPeek \/ MovePointer \/ PeekDeadline \/ LeaveObserved \/ ReturnObserved
     \/ CloseDeadline \/ ClickStrip \/ HoverDelayEnds
     \/ OpenElsewhere \/ EndPeek \/ FinishDismiss \/ CloseExpanded \/ Reset

\* The hover delay must eventually fire while it stays queued, so a resting ear hover can
\* be proven to resolve rather than pending forever.
Spec == Init /\ [][Next]_vars /\ WF_vars(HoverDelayEnds)

TypeOK ==
    /\ phase \in {"idle", "timed", "held", "leaving", "dismissing", "expanded"}
    /\ pointer \in Locations
    /\ owner \in Owners \cup {"none"}
    /\ outcome \in {<<"none", "none">>, <<"explicit", "none">>, <<"other open", "none">>}
                       \cup ({"timeout", "hover opened"} \X Locations) \cup ({"strip opened"} \X Owners)
    /\ queuedHover \in BOOLEAN

VisiblePeekHasAnOwner == phase \in Visible => owner \in Owners
TimeoutRespectsPointer == outcome # <<"timeout", "strip">>
StripHoverKeepsPeekCompact == outcome # <<"hover opened", "strip">>
StripActivationOpensItsOwner == outcome[1] = "strip opened" => (phase = "expanded" /\ outcome[2] = owner)
\* Sitting on an ear while a peek shows always has an open queued: entering the outline and
\* crossing the strip both queue it (updatePeekHover). A regression that only queues on the
\* outline enter violates this for the strip -> ear path.
EarRestQueuesOpen == (phase \in Visible /\ pointer = "ear") => queuedHover
\* Resting on an ear resolves: the hover opens, the pointer moves off, or the peek goes away.
EarHoverOpens ==
    (phase \in Visible /\ pointer = "ear") ~>
        (phase = "expanded" \/ pointer # "ear" \/ phase \notin Visible)

====
