-------------------------- MODULE ClickOnly --------------------------
EXTENDS Naturals
CONSTANTS CancelPendingOpen, PreservePendingClose, BlockHoverEntry
VARIABLES clickOnly, expanded, inside, pending, hoverOpenedInClickMode, lostClose
vars == <<clickOnly, expanded, inside, pending, hoverOpenedInClickMode, lostClose>>

Init == /\ clickOnly = FALSE /\ expanded = FALSE /\ inside = FALSE
        /\ pending = "none" /\ hoverOpenedInClickMode = FALSE /\ lostClose = FALSE

\* NotchViewModel.hoverChanged(true): cancel the shared task before checking opening guards.
Enter == /\ ~inside /\ inside' = TRUE
         /\ pending' = IF ~expanded /\ (~clickOnly \/ ~BlockHoverEntry) THEN "open" ELSE "none"
         /\ UNCHANGED <<clickOnly, expanded, hoverOpenedInClickMode, lostClose>>
\* hoverChanged(false), without a module hold or synthetic resize exit.
Leave == /\ inside /\ inside' = FALSE
         /\ pending' = IF expanded THEN "close" ELSE "none"
         /\ UNCHANGED <<clickOnly, expanded, hoverOpenedInClickMode, lostClose>>
\* behavior.didSet: one synchronous MainActor mutation. No task can interleave inside it.
ChangeSetting == /\ clickOnly' = ~clickOnly
                 /\ pending' = IF ~clickOnly /\
                         ((~expanded /\ CancelPendingOpen) \/ (expanded /\ ~PreservePendingClose))
                         THEN "none" ELSE pending
                 /\ lostClose' = (lostClose \/ (~clickOnly /\ expanded /\ pending = "close" /\ ~PreservePendingClose))
                 /\ UNCHANGED <<expanded, inside, hoverOpenedInClickMode>>
\* schedule's cancellation check and callback run without suspension on MainActor.
DelayEnds == /\ pending # "none"
             /\ expanded' = (pending = "open")
             /\ hoverOpenedInClickMode' = (hoverOpenedInClickMode \/ (pending = "open" /\ clickOnly))
             /\ pending' = "none"
             /\ UNCHANGED <<clickOnly, inside, lostClose>>
\* The click's opening branch. Shrink/second-click details are covered by Swift tests.
Click == /\ ~expanded /\ inside
         /\ expanded' = TRUE /\ pending' = "none"
         /\ UNCHANGED <<clickOnly, inside, hoverOpenedInClickMode, lostClose>>
\* Explicit close/reset: abstracts the resting Closed/Compact shape, not its drawing.
Close == /\ expanded /\ expanded' = FALSE /\ pending' = "none"
         /\ UNCHANGED <<clickOnly, inside, hoverOpenedInClickMode, lostClose>>
Idle == UNCHANGED vars
Next == Enter \/ Leave \/ ChangeSetting \/ DelayEnds \/ Click \/ Close \/ Idle
Spec == Init /\ [][Next]_vars
NoQueuedHoverInClickMode == clickOnly => pending # "open"
NoHoverOpeningInClickMode == ~hoverOpenedInClickMode
PendingCloseSurvivesSetting == ~lostClose
======================================================================
