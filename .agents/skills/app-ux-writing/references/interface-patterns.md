# Interface patterns

Consult the patterns involved in the requested screen or flow. The examples below are original illustrations, not quotations or product behavior specifications. Use their wording only when the stated behavior is true of the app.

## Headings, onboarding, and instructions

Make the main purpose visible in the heading and primary action. Supporting text should add a benefit, explanation, or consequence that those elements do not already convey. Describe the reason for a request before its mechanics when that helps someone decide.

For example, “To get pickup updates, add your phone number” explains a reason for providing information. It is appropriate only if those updates are the actual use; it must not disguise other material uses of that information.

Give each step a distinct purpose. Distinguish completing setup from waiting for activation or processing, and explain how someone will know when they can proceed. Recommend moving information or removing an unnecessary step when hierarchy or timing is the underlying problem.

## Buttons and choices

Use labels that predict their actual effects. Read important choices independently from the body text: someone scanning the buttons should still understand the decision. Established navigation labels such as “Next” can work when the action is simply advancing through a flow.

When cancellation is itself the task, name the alternatives explicitly. For a hypothetical booking flow, “Cancel Booking” and “Keep Booking” make the outcomes clearer than “Confirm” and “Cancel.” Identify the affected booking and disclose relevant consequences based on the actual policy.

Use the platform's control semantics and the project's conventions. The position and color of buttons in an old transcript example are not universal layout rules.

## Errors and blocked actions

Identify the problem in terms the person understands. Explain a supported recovery action and provide a control that reaches it when the app supports that path. If retrying cannot resolve the problem, a generic retry instruction provides no recovery.

For a known connectivity failure, a draft might be:

- Heading: “Upload Paused”
- Body: “Connect to the internet to upload your recording.”
- Action: “Retry Upload”

This draft requires a retained recording and a working retry action. If either is unknown, resolve that behavior before promising it. Keep diagnostic codes secondary to the explanation when support needs them. Use a neutral tone that takes the inconvenience seriously.

## Alerts and permissions

Use an alert for a necessary decision, acknowledgment, or interruption; suggest a contextual inline message when that would better support the task. Explain why requested access is useful at the relevant moment. Distinguish app-authored rationale from system-controlled permission text.

For a destructive choice, identify the object, scope, and whether recovery is possible when known. Preserve critical consequences even when this makes the copy longer. Use exact actions for both alternatives and check that dismissing the alert behaves as described.

## Empty states

Determine why content is absent before choosing the message: first use, no search matches, completed work, or a loading failure call for different explanations. Describe what belongs here and how it will appear when that guidance is useful.

For example, an unused saved-trails list could say “No Saved Trails” with “Save trails while browsing to find them here.” A list of completed tasks can acknowledge completion; a retrieval failure needs recovery language. An empty container alone is not evidence that someone has finished their work.

## Notifications and progress

Lead with the useful event, changed expectation, or benefit. Keep secondary detail relevant to a decision the person can make. Distinguish elapsed delay from remaining time: “delayed 10 minutes” and “arrives in 10 minutes” make different promises. Preserve estimates and uncertainty when the underlying data is uncertain.

For progress, say what is happening and what the person should do or expect next when known. Reserve completion language for an actual completed state. Fit the message to a glance when attention is divided.

## Accessibility and localization

Check that meaning survives the visual presentation. Controls need understandable accessible names; informative images and charts need descriptions of their relevant meaning or intention. Preserve useful native semantics and account for grouping and decorative content so the spoken experience stays coherent. Avoid relying solely on position, color, or imagery for necessary instructions.

Allow for longer words, taller scripts, larger or bold text, and right-to-left layouts. Abbreviations that work in English may have different lengths or no equivalent in another language. Adapt the layout or wording without discarding essential meaning to fit an English-sized space.

Use inclusive terms and culturally portable expressions appropriate to the audience. Flag idioms, jokes, and coined names for language review where needed. A source-language review can identify risks; it cannot certify every translation or the runtime VoiceOver experience.
