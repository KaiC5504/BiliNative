# Fix round 1 (b-fix1, from b-int2 95a6273, with b-t15c2 cb0708f merged)

Findings from review-b-app-21-26, review-b-app-20-24 and review-b-app-22-23-25.

## Commits (the ones that matter)

- 4ab7284 Page models no longer hold the page view; each action takes back only its own change
- bcb7121 Sheets after full screen wait for the rotation to finish; the TV login closes before the dislike goes out
- 293a249 历史记录 keeps its rows through a refresh; endless scroll asks on past pages that add nothing
- 82c97c0 Video page minors (player over the end screen, links, counts, drafts, folders, coin balance)
- debaed1 Merge b-t15c2 (flaky PageLifecycle test fix)
- d973c18 Deleting a reply in an open thread no longer trips Swift's exclusivity check (a real crash, found by a new test)
- the leak fix: "A closed page lets go of its host and danmaku views" + "Rich text actions on the page capture the
  model weakly" + "Player surface back to handing SwiftUI the host view directly" (final tip in the CI section)
- tools: "Compile workflow: dispatch inputs ...", LeakCheckDemo + HeapReferrers (DEBUG)
- Temporary bisect commits (1c56a39 .. 0d48e64) are in the history; everything they added is removed again.

## Important

| Finding | Status | Test |
|---|---|---|
| Leak: popped pages never freed (20/24 #1, plus 21's `makeActions`) | Fixed. Two causes. (1) The CommentsModel/ActionsModel login and toast closures captured the page view; they now capture a small `PageSignals` object the page observes. (2) The real root, found with the new heap scan: UIKit views inside the page (the danmaku layer, the host) carry the page's SwiftUI environment in their trait collections (`UITraitCollection` -> `SwiftUIEnvironmentWrapper`), and the environment's `richTextActions` closures captured `PageLayout` (which holds the danmaku view and the page's closures) -> a cycle that kept model, actions, comments and the whole view state alive. The closures now capture `[weak model]` only. Also: the danmaku view belongs to the model (not view state) and `close()` drops it and the host view when it is out of a window. | `PageReleaseTests.testPoppedPageFreesItsModels` (push a real page on a NavigationStack, pop, weak refs to VideoPageModel, ActionsModel, CommentsModel all nil). Leak check run: "nothing left alive". |
| ActionsModel concurrent rollback (21/26 #1) | Fixed: each action reverts only the fields it changed, and only if they still show its value. | `testAFailedLikeLeavesAFollowInFlightAlone`, `testTwoFailuresEachTakeBackOnlyTheirOwn`, `testFailedTripleRollsBackAndKeepsTheDislike` |
| LoginGate fixed 450 ms (21/26 #2) | Fixed once in `InlineFirst` (LoginGate and the TV gate): waits for the scene to report portrait (3 s cap), then for any transition coordinator to finish. | `ActionPresentationTests.testLoginSheetFromLandscapeComesUpOverTheInlinePage` |
| HistoryModel.reload emptied the list (21/26 26#1) | Fixed: rows stay until the first page answers; a generation counter supersedes a load in flight. | `testReloadKeepsTheRowsUntilTheFirstPageAnswers`, `testReloadSupersedesALoadInFlight` |
| TV login fresh token refused -> silent loop (Task 23) | Fixed: the gate closes the sheet on `.done` and sends from `onDismiss`; `toggleDislike(freshToken: true)` toasts the server's words on -101/-2 instead of reopening the sheet. | `testAFreshTokenThatIsRefusedToastsInsteadOfLooping`, `testConfirmedLoginClosesTheSheetBeforeTheTapGoesThrough` |

## Minors

| Finding | Status |
|---|---|
| Player collapses over the end screen | Fixed: `ended` is not paused; the player shrinks only by what is scrolled after the pause. Demos wait 300 ms between pause and scroll. |
| PlayerArea reads `tabs.offset` while playing | Fixed: read only inline and paused. |
| CommentsTab `.task` without id | Fixed: `.task(id: ObjectIdentifier(model))`. |
| Double reply-count change | Fixed; `testAReplyInAnOpenThreadCountsOnce`. That test also exposed an exclusivity abort in `delete` (`thread?.total = max(0, (thread?.total ?? 1) - 1)`): deleting a reply in an open thread crashed. Fixed in d973c18. |
| Only http/https links tappable | Fixed in `RichLink.url(for:)`. |
| Deleting the pinned comment lowers total | Fixed; tested. |
| Description links | The view API sends no jump links for descriptions, so `TitleBlock.webLinks(in:)` makes written-out http(s) addresses links (NSDataDetector). Tested. |
| Endless scroll stalls on pages that add nothing | Fixed: up to three pages per load more while a page adds nothing, plus the footer spinner asks on appear (home and history). Tested. |
| Feed not refreshed after login/logout | Fixed: refresh when the signed-in state flips (ignores `.unknown`). |
| History reload during a load after login | Fixed by the reload generation. |
| Tap vs hold on 点赞 | Fixed: a press that reached the rings is not a tap. Phone check. |
| Burst/haptic only when 三连 is sent | Fixed via `ActionsModel.tripleSends`; tested. |
| 已投满 wording | "已投满N个硬币" only at `maxCoins == 0`, else "最多还能投N个硬币"; tested. |
| Late relation blocked wholesale; triple never restored `disliked` (21/26 #3, #6) | Fixed (per-field `touched`; `settleTriple`); tested. |
| LoadMore-after-refresh and sort generation tests | Added. |
| TV confirm web view navigation delegate | Fixed: top-level navigation stays on `bilibili.com`/`*.bilibili.com`/`about:`, the rest (and `target=_blank`) go to Safari. |
| White literals | `Theme.TVLogin.buttonText`, `Theme.Favourites.doneText`. |
| Composer closed mid-post -> double post | Fixed: no closing while posting, and `CommentDrafts.posting` disables 发布 on any composer for a target still posting. Tested. |
| Drafts lost on a 合集 switch | Fixed: page-owned `CommentDrafts`; the video-level key carries the aid. Tested. |
| Favourites `load()` drops ticks of folders made locally | Fixed; `FavouritesModelTests`. |
| Coin balance failure shows "--" for good | The page asks up to three times while the dialog is open. |

## Skipped

- 20/24 Task 20 minor 3 (full-screen round trip rebuilds PageTabs) and minor 4 (ForEach ids): not in this round's list.
- Rotation loses the typed folder name: skipped as instructed. TV confirm page user agent: phone-test item.
- Edge left: a composer force-closed mid-post (rotation) and reopened after the post finished still shows the old text.

## Tools (kept)

- `ios-compile.yml` workflow_dispatch inputs: `tests` (comma-separated, passed as `-only-testing:BiliNativeTests/<item>`),
  `shots` (false skips screenshots and the Release build), `leaks` (runs the leak check). Example:
  `gh workflow run ios-compile.yml --ref b-fix1 -f tests=PageReleaseTests -f shots=false -f leaks=true` (~7 min).
- `-DemoScreen leak-check` (LeakCheckDemo, DEBUG): opens a page, goes back, writes what is still alive and a
  holder tree from `HeapReferrers` (DEBUG): an in-process scan of every malloc block, with class names, dladdr
  symbols for unnamed blocks, and the symbols beside each reference (a Swift closure's function sits next to its
  context). macOS `leaks` does not work on the runner for simulator processes ("Failed to get DYLD info"), with or
  without sudo, so the step does not call it.

## Evidence

- Tip f9ac01d on b-fix1. check-app clean (debug and `--release`).
- Full "iOS compile check" run 38997162057 (push): success, all tests including PageReleaseTests and the
  PageLifecycle tests from b-t15c2; no crash reports.
- Dispatch run 38996438844 (`tests=PageReleaseTests`, `leaks=true`): test passes; leak check "nothing left alive".
- Screenshots looked at: page-collapsed, comments-thread, composer-emotes (player shrinks after the pause as
  before), 08-end-portrait (end screen at full height), history. No regressions seen.
- Not verifiable in CI, for the phone: tap vs hold on 点赞, the TV-login flow end to end, the confirm page's links.
