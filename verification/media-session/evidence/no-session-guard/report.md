# MediaSession

TLC reached 873 states, more than the chart budget of 500, so the chart draws only the bug paths: 4 states and 3 arrows.

## NoRetiredMetadata breaks
The shortest path has 2 steps:
0. Waiting for video details
1. the media session closes: Closed video cleared
2. media details arrive: Old video cached after closure

## NoRetiredFields breaks
The shortest path has 2 steps:
0. Waiting for video details
1. the media session closes: Closed video cleared
2. player details arrive: Old player details accepted after closure

## Rules that hold
NoSupersededReply, NoDeadlock
