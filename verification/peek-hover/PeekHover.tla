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
    /\ UNCHANGED <<pointer, queuedHover>>

MovePointer ==
    /\ \E location \in Locations \ {pointer}: pointer' = location
    /\ UNCHANGED <<phase, owner, outcome, queuedHover>>

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

EarHoverObserved ==
    /\ phase \in Visible
    /\ pointer = "ear"
    /\ ~queuedHover
    /\ queuedHover' = TRUE
    /\ UNCHANGED <<phase, pointer, owner, outcome>>

HoverExitObserved ==
    /\ phase \in Visible
    /\ pointer # "ear"
    /\ queuedHover
    /\ queuedHover' = FALSE
    /\ UNCHANGED <<phase, pointer, owner, outcome>>

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
     \/ CloseDeadline \/ ClickStrip \/ EarHoverObserved \/ HoverExitObserved \/ HoverDelayEnds
     \/ OpenElsewhere \/ EndPeek \/ FinishDismiss \/ CloseExpanded \/ Reset

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

====
