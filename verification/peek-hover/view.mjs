export const title = "Peek strip lifetime";

const labels = {
    idle: "No peek",
    timed: "Peek visible",
    held: "Peek held",
    leaving: "Close delay",
    dismissing: "Peek sliding away",
    expanded: "Notch expanded",
};
export const state = ({ phase }) => labels[phase];
export const group = ({ phase }) => {
    if (phase === "timed" || phase === "held" || phase === "leaving") return "Peek";
    if (phase === "expanded") return "Expanded";
    return "Resting";
};
export const colors = { Peek: "teal", Expanded: "blue", Resting: "tan" };

export function step(action, from, to) {
    switch (action) {
        case "ShowPeek": return from.phase === "idle" ? "a peek appears" : "a newer peek appears";
        case "PeekDeadline": return to.phase === "held" ? "time up while reading" : "time up with pointer off strip";
        case "LeaveObserved": return "pointer leaves the strip";
        case "ReturnObserved":
        case "CloseDeadline": return to.phase === "held" ? "pointer returns to the strip" : "close delay ends off strip";
        case "ClickStrip":
        case "HoverDelayEnds":
        case "OpenElsewhere": return "click strip or open notch elsewhere";
        case "EndPeek": return "module ends the peek";
        case "FinishDismiss": return "strip finishes closing";
        case "CloseExpanded": return "notch closes";
        case "Reset": return from.phase === "dismissing" ? "strip finishes closing" : "notch resets or hides";
        default: return null;
    }
}
