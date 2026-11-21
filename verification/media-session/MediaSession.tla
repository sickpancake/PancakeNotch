---------------------------- MODULE MediaSession ----------------------------
EXTENDS Integers, FiniteSets, TLC
CONSTANTS GuardSession, GuardRequest, MaxReads
VARIABLES sessionGeneration, infoGeneration, pendingInfo, pendingFields,
          fieldSession, title, titleSession, closed, appliedOldReply
vars == <<sessionGeneration, infoGeneration, pendingInfo, pendingFields,
          fieldSession, title, titleSession, closed, appliedOldReply>>
Fields == {"PID", "Playing", "Parent"}
Empty == "Nothing"
Init == /\ sessionGeneration = 0 /\ infoGeneration = 1
        /\ pendingInfo \in {{[request |-> 1, session |-> 0, content |-> value]}:
                               value \in {Empty, "Video"}}
        /\ pendingFields = Fields
        /\ fieldSession = [f \in Fields |-> -1]
        /\ title = Empty /\ titleSession = -1
        /\ closed = FALSE /\ appliedOldReply = FALSE

\* A queue-change request captures a possible response. MediaRemote may deliver it later.
RequestNowPlayingInfo ==
    /\ infoGeneration < MaxReads
    /\ \E value \in {Empty, "Video"}:
        /\ infoGeneration' = infoGeneration + 1
        /\ pendingInfo' = pendingInfo \cup {
            [request |-> infoGeneration + 1, session |-> sessionGeneration, content |-> value]}
    /\ UNCHANGED <<sessionGeneration, pendingFields, fieldSession, title,
                    titleSession, closed, appliedOldReply>>

InfoReply ==
    \E reply \in pendingInfo:
      /\ pendingInfo' = pendingInfo \ {reply}
      /\ IF (~GuardSession \/ reply.session = sessionGeneration)
              /\ (~GuardRequest \/ reply.request = infoGeneration)
          THEN /\ title' = reply.content
               /\ titleSession' = IF reply.content = Empty THEN -1 ELSE reply.session
               /\ appliedOldReply' = (appliedOldReply \/ reply.request # infoGeneration)
          ELSE UNCHANGED <<title, titleSession, appliedOldReply>>
      /\ UNCHANGED <<sessionGeneration, infoGeneration, pendingFields,
                      fieldSession, closed>>

\* Three independent callbacks issued at startup. A field tag records its source session.
FieldReply ==
    \E field \in pendingFields:
      /\ pendingFields' = pendingFields \ {field}
      /\ fieldSession' = IF ~GuardSession \/ sessionGeneration = 0
                         THEN [fieldSession EXCEPT ![field] = 0] ELSE fieldSession
      /\ UNCHANGED <<sessionGeneration, infoGeneration, pendingInfo, title,
                      titleSession, closed, appliedOldReply>>

\* No-process notification: resetAll + handle are synchronous, with no new metadata read.
CloseSession ==
    /\ ~closed /\ sessionGeneration = 0
    /\ sessionGeneration' = 1 /\ closed' = TRUE
    /\ fieldSession' = [f \in Fields |-> -1]
    /\ title' = Empty /\ titleSession' = -1
    /\ UNCHANGED <<infoGeneration, pendingInfo, pendingFields, appliedOldReply>>

Idle == UNCHANGED vars
Next == RequestNowPlayingInfo \/ InfoReply \/ FieldReply \/ CloseSession \/ Idle

NoRetiredMetadata == title = Empty \/ titleSession = sessionGeneration
NoRetiredFields == \A field \in Fields: fieldSession[field] \in {-1, sessionGeneration}
NoSupersededReply == ~appliedOldReply
=============================================================================
