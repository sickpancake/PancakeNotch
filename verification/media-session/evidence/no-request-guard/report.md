# MediaSession

TLC reached 384 states and 1664 steps. The chart draws 5 states and 8 arrows.
The chart does not draw 1007 steps that stay in one chart state.
The view hides 384 steps, so the chart does not draw them.

## NoSupersededReply breaks
The shortest path has 2 steps:
0. Waiting for video details
1. the system starts reading media details: Waiting for video details
2. media details arrive: Older reply replaces newer details

## Rules that hold
NoRetiredMetadata, NoRetiredFields, NoDeadlock
