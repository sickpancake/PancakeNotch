---------------------------- MODULE ReduceMotion ----------------------------
(***************************************************************************)
(* PancakeNotch's Reduce motion (issue #99): its own switch, the Mac's      *)
(* switch, Home's page scrolling and the compact notch's sound bars.        *)
(*                                                                         *)
(* Each action is one synchronous MainActor step in the Swift code:         *)
(*  YouClickSwitch    MotionSettings.reduceMotionInApp didSet, guarded by   *)
(*                    MotionCard's binding while the Mac's switch is on;    *)
(*                    its announcement runs NotchViewModel.motionChanged    *)
(*                    in the same step (queue: nil observer).               *)
(*  MacFlips          you change Reduce motion in System Settings.          *)
(*  MacTellsApp       accessibilityDisplayOptionsDidChangeNotification ->   *)
(*                    MotionSettings.macSettingChanged (+ motionChanged).   *)
(*  FingersDown/Move/Lift  NotchViewModel.scrollHome ->                     *)
(*                    handleHomePreciseScroll (.began+.changed / .changed / *)
(*                    .ended), or the one-page path while reduced.          *)
(*  PageKey           showHomePage from the wheel, arrow keys, dots.        *)
(*  SettleEnds        settleHome's withAnimation completion.                *)
(*  ViewsRedraw       SwiftUI redraws with followsMotionSettings' value:    *)
(*                    NowPlayingBarsEar -> SoundBarsNSView.refresh.         *)
(*  MusicStartsOrStops  the track's isPlaying changes.                      *)
(***************************************************************************)
CONSTANTS
    ResetOnChange,        \* motionChanged() clears Home's scroll on every change
    ReducedTakesFadePath, \* showHomePage / scrollHome check motion.reducesMotion
    BarsHonorReduce,      \* SoundBarsMode.resolve returns .still with Reduce motion
    LockWhileMac          \* MotionCard ignores its switch while the Mac's is on

VARIABLES
    own,          \* MotionSettings.reduceMotionInApp
    mac,          \* the Mac's switch itself
    macSeen,      \* MotionSettings.macReducesMotion (last read)
    fingers,      \* fingers are on the trackpad over Home
    active,       \* homeMotion.active (the model follows the fingers)
    between,      \* homeScrollPosition is set: Home drawn between two pages
    settling,     \* settleHome's animation runs and its completion is current
    drawnReduced, \* the value the views last drew with
    playing,      \* the song plays
    bars,         \* SoundBarsNSView.pose: "rest", "still" or "dance"
    deadClick     \* your last click on the switch changed nothing you can see

vars == <<own, mac, macSeen, fingers, active, between, settling, drawnReduced, playing, bars, deadClick>>

Reduced == own \/ macSeen

Init ==
    /\ own \in BOOLEAN
    /\ mac \in BOOLEAN
    /\ macSeen = mac
    /\ fingers = FALSE /\ active = FALSE /\ between = FALSE /\ settling = FALSE
    /\ drawnReduced = (own \/ mac)
    /\ playing \in BOOLEAN
    /\ bars = IF ~playing THEN "rest"
              ELSE IF (own \/ mac) /\ BarsHonorReduce THEN "still" ELSE "dance"
    /\ deadClick = FALSE

\* motionChanged(): resetHomeMotion() when the combined value changed.
HomeAfterChange(changed) ==
    IF changed /\ ResetOnChange
    THEN /\ active' = FALSE /\ between' = FALSE /\ settling' = FALSE
    ELSE UNCHANGED <<active, between, settling>>

\* The switch shows Reduced; a click asks for the opposite (MotionCard's Binding set).
YouClickSwitch ==
    /\ ~(LockWhileMac /\ macSeen)
    /\ own' = ~Reduced
    /\ deadClick' = ((own' \/ macSeen) = Reduced)
    /\ HomeAfterChange((own' \/ macSeen) # Reduced)
    /\ UNCHANGED <<mac, macSeen, fingers, drawnReduced, playing, bars>>

MacFlips ==
    /\ mac' = ~mac
    /\ UNCHANGED <<deadClick, own, macSeen, fingers, active, between, settling, drawnReduced, playing, bars>>

MacTellsApp ==
    /\ macSeen # mac
    /\ macSeen' = mac
    /\ HomeAfterChange((own \/ macSeen') # Reduced)
    /\ UNCHANGED <<deadClick, own, mac, fingers, drawnReduced, playing, bars>>

\* .began then .changed. Reduced: the one-page path counts a step, no position.
FingersDown ==
    /\ ~fingers
    /\ fingers' = TRUE
    /\ IF Reduced /\ ReducedTakesFadePath
       THEN UNCHANGED <<active, between, settling>>
       ELSE /\ active' = TRUE /\ between' = TRUE /\ settling' = FALSE
    /\ UNCHANGED <<deadClick, own, mac, macSeen, drawnReduced, playing, bars>>

\* .changed while reduced and enough travel: showHomePage's cross-fade path resets Home.
FingersTurnPageReduced ==
    /\ fingers /\ Reduced /\ ReducedTakesFadePath
    /\ active' = FALSE /\ between' = FALSE /\ settling' = FALSE
    /\ UNCHANGED <<deadClick, own, mac, macSeen, fingers, drawnReduced, playing, bars>>

\* .ended: the precise path settles; the one-page path does nothing more.
FingersLift ==
    /\ fingers
    /\ fingers' = FALSE
    /\ IF (~Reduced \/ ~ReducedTakesFadePath) /\ active
       THEN /\ settling' = TRUE /\ active' = FALSE /\ UNCHANGED between
       ELSE UNCHANGED <<active, between, settling>>
    /\ UNCHANGED <<deadClick, own, mac, macSeen, drawnReduced, playing, bars>>

\* Wheel, arrow keys or a page dot: showHomePage.
PageKey ==
    /\ IF Reduced /\ ReducedTakesFadePath
       THEN /\ active' = FALSE /\ between' = FALSE /\ settling' = FALSE
       ELSE /\ between' = TRUE /\ settling' = TRUE /\ active' = FALSE
    /\ UNCHANGED <<deadClick, own, mac, macSeen, fingers, drawnReduced, playing, bars>>

SettleEnds ==
    /\ settling
    /\ settling' = FALSE /\ between' = FALSE
    /\ UNCHANGED <<deadClick, own, mac, macSeen, fingers, active, drawnReduced, playing, bars>>

BarsFor(reduced, isPlaying) ==
    IF ~isPlaying THEN "rest"
    ELSE IF reduced /\ BarsHonorReduce THEN "still" ELSE "dance"

ViewsRedraw ==
    /\ drawnReduced # Reduced
    /\ drawnReduced' = Reduced
    /\ bars' = BarsFor(Reduced, playing)
    /\ UNCHANGED <<deadClick, own, mac, macSeen, fingers, active, between, settling, playing>>

MusicStartsOrStops ==
    /\ playing' = ~playing
    /\ bars' = BarsFor(drawnReduced, playing')
    /\ UNCHANGED <<deadClick, own, mac, macSeen, fingers, active, between, settling, drawnReduced>>

Next ==
    \/ YouClickSwitch \/ MacFlips \/ MacTellsApp
    \/ FingersDown \/ FingersTurnPageReduced \/ FingersLift \/ PageKey \/ SettleEnds
    \/ ViewsRedraw \/ MusicStartsOrStops

Spec == Init /\ [][Next]_vars

TypeOK ==
    /\ own \in BOOLEAN /\ mac \in BOOLEAN /\ macSeen \in BOOLEAN
    /\ fingers \in BOOLEAN /\ active \in BOOLEAN /\ between \in BOOLEAN /\ settling \in BOOLEAN
    /\ drawnReduced \in BOOLEAN /\ playing \in BOOLEAN /\ bars \in {"rest", "still", "dance"}
    /\ deadClick \in BOOLEAN

(* A Home page is never left between two pages with nothing moving it: either the fingers
   still hold it, or its settle animation will finish it. Otherwise it stays halfway and its
   widgets can't be clicked (homeIsLive / allowsHitTesting need homeScrollPosition == nil). *)
NoHomePageStuckHalfway ==
    between => ((fingers /\ active) \/ settling)

(* With Reduce motion on, Home's pages never slide: no in-between position at all. *)
NoHomeScrollWhileReduced ==
    Reduced => ~between

(* With Reduce motion on (once the views have drawn it), the sound bars never dance. *)
BarsStillWhenReduced ==
    drawnReduced => bars # "dance"

(* With both switches off, nothing changes: playing music still makes the bars dance. *)
DefaultMotionUnchanged ==
    (~drawnReduced /\ playing) => bars = "dance"

(* Every click on the Reduce motion switch changes what you see. While the Mac's switch is on
   the switch is locked on, so a click can't be swallowed (or quietly clear your own choice). *)
NoDeadSwitch ==
    ~deadClick

=============================================================================
