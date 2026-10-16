# Fix round 1 (b-fix1, from b-int2 95a6273)

Findings from review-b-app-21-26, review-b-app-20-24 and review-b-app-22-23-25. Every fix compiles clean in
check-app; CI evidence at the end.

## Commits

- 4ab7284 Page models no longer hold the page view; each action takes back only its own change
- bcb7121 Sheets after full screen wait for the rotation to finish; the TV login closes before the dislike goes out
- 293a249 历史记录 keeps its rows through a refresh; endless scroll asks on past pages that add nothing
- 82c97c0 Video page minors: the player stays up over the end screen, links, counts, drafts, folders

## Important

| Finding | Status | Commit | Test |
|---|---|---|---|
| Leak: CommentsModel / ActionsModel closures captured the page view (20/24 #1) | Fixed. The closures now capture a small `PageSignals` object (`logins` counter, `actionToast`) that the page observes; no model holds the view. `ActionPrompts` gained a weak `comments` so tests can reach the page's comments. | 4ab7284 | `PageReleaseTests.testPoppedPageFreesItsModels`: push a real page (demo data), pop it, weak refs to VideoPageModel, ActionsModel and CommentsModel all nil |
| ActionsModel cross-action rollback (21/26 #1) | Fixed. `perform` snapshots before and after its own change and `undo` reverts only the fields that action changed, and only if they still show its value. | 4ab7284 | `testAFailedLikeLeavesAFollowInFlightAlone`, `testTwoFailuresEachTakeBackOnlyTheirOwn` (two actions in flight on per-path gates), `testFailedTripleRollsBackAndKeepsTheDislike` |
| LoginGate fixed 450 ms (21/26 #2) | Fixed once in `InlineFirst` (used by LoginGate and the TV login gate): waits for the scene to report portrait (3 s cap), then for any running transition coordinator to finish. | bcb7121 | `ActionPresentationTests.testLoginSheetFromLandscapeComesUpOverTheInlinePage`: real page, landscape, a -101 from comments asks for login; sheet comes up with the scene portrait and the page inline, player still in its window, sheet dismissed |
| HistoryModel.reload emptied the list (21/26 26#1) | Fixed. Reload keeps the rows until the first page answers; a generation counter lets it supersede a load in flight and drops the older answer. | 293a249 | `testReloadKeepsTheRowsUntilTheFirstPageAnswers`, `testReloadSupersedesALoadInFlight` |
| TV login: fresh token refused → silent loop (22/23/25, Task 23) | Fixed. The gate closes the sheet on `.done` and calls `onDone` from the sheet's `onDismiss`; the page sends `toggleDislike(freshToken: true)`, and a -101/-2 for that fresh token deletes it and toasts the server's message (logged with the code) instead of reopening the sheet. | bcb7121 | `ActionsDislikeTests.testAFreshTokenThatIsRefusedToastsInsteadOfLooping`; `TVLoginSheetPresentationTests.testConfirmedLoginClosesTheSheetBeforeTheTapGoesThrough` |

## Minors

| Finding | Status | Commit |
|---|---|---|
| Player collapses over the end screen when `ended` | Fixed: `ended` no longer counts as paused, and the player shrinks only by what is scrolled after the pause (`collapseFrom`, lowered when scrolling back above it). Demos wait 300 ms between pause and scroll. | 82c97c0 |
| PlayerArea reads `tabs.offset` while playing | Fixed: the offset is read only while inline and paused. | 82c97c0 |
| CommentsTab `.task` without id | Fixed: `.task(id: ObjectIdentifier(model))`. | 82c97c0 |
| Double reply-count change in `inserted` / `delete` | Fixed (the direct `thread.root` change dropped; `update` covers it). Test `testAReplyInAnOpenThreadCountsOnce`. | 82c97c0 |
| Only http/https links tappable | Fixed in `RichLink.url(for:)`; tested in `testDescriptionWebAddressesAreLinks`. | 82c97c0 |
| Deleting the pinned comment lowers total | Fixed; `testDeletingThePinnedCommentLowersTheTotal`. | 82c97c0 |
| Description links | The view API sends no jump links for a description (desc_v2 is text and @ parts only), so `TitleBlock.webLinks(in:)` finds written-out http(s) addresses with NSDataDetector and passes them as `links`. Tested. | 82c97c0 |
| Endless scroll stalls on a page that adds nothing (home, history) | Fixed both ways: the footer spinner asks on appear, and load more asks up to three pages while a page adds nothing (the footer alone cannot fire again while it stays on screen). `testAPageOfRepeatsGoesOnToTheNext`. | 293a249 |
| Feed not refreshed after login/logout | Fixed: HomeView refreshes when the signed-in state flips (ignoring `.unknown`, so the launch check and `didLogin`'s transient unknown do not double-load). | 293a249 |
| History reload while a load runs after login | Fixed by the reload generation above. | 293a249 |
| Tap vs hold on 点赞 | Fixed: a press that reached the ring (past the 0.2 s delay) marks `ringStarted`, and the tap that may follow the release is ignored. Not verifiable in CI; phone check. | 4ab7284 |
| Burst/haptic only when triple sent | Fixed: `ActionsModel.tripleSends` (logged in, not done, not busy) gates the burst. `testTripleSendsOnlyWhenItWouldGoOut`. | 4ab7284 |
| 已投满 wording only when no coins remain | Fixed: "已投满N个硬币" at `maxCoins == 0`, otherwise "最多还能投N个硬币". Test updated. | 4ab7284 |
| Late relation blocked wholesale by `touched` (21/26 #3) | Fixed alongside the rollback: `touched` is per field. `testALateRelationStillFillsInWhatWasNotTapped`. | 4ab7284 |
| Triple never restored `disliked` (21/26 #6) | Fixed in `settleTriple`. | 4ab7284 |
| LoadMore after refresh not tested (21/26 #5) | Test added: `testALoadMoreThatLandsAfterARefreshIsDropped`. Sort generation (20/24 #6): `testALatePageForTheOldSortIsDropped`. | 293a249, 82c97c0 |
| TV confirm web view without navigation delegate | Fixed: a coordinator keeps top-level navigation on `bilibili.com` / `*.bilibili.com` and `about:`, opens anything else in Safari, and handles `target=_blank` the same way. | bcb7121 |
| `.white` / `Color.white` literals (TV login, favourites) | Moved to `Theme.TVLogin.buttonText` and `Theme.Favourites.doneText`. | bcb7121 |
| Composer closed mid-post → double post | Fixed both ways: the dim tap does nothing while posting, and `CommentDrafts.posting` keeps 发布 disabled on any composer for a target whose post is still running (covers forced closes such as rotation). `testAReopenedComposerCannotPostTheSameTextTwice`. | 82c97c0 |
| Drafts dropped on a 合集 switch | Fixed: drafts live in a page-owned `CommentDrafts` handed to each video's CommentsModel; the video-level key now carries the aid (`video.<aid>`), comment keys are rpids. `testDraftsOutliveASwitchToAnotherVideo`. | 82c97c0 |
| FavouriteSheet load resets ticks of folders made locally | Fixed: folders created in the sheet are kept across a later load, in place and ticked as left. `FavouritesModelTests`. | 82c97c0 |
| Coin balance failure shows "--" with no retry | Fixed: the page asks up to three times (1 s, 2 s backoff) while the dialog is open. CoinDialog untouched. | 82c97c0 |

## Skipped

- 20/24 Task 20 minor 3 (full-screen round trip rebuilds PageTabs): not in this round's list; it needs PageTabs kept alive
  in full screen, a layout change with its own risk. Still open.
- 20/24 Task 20 minor 4 (ForEach ids assume unique cid/bvid): not in the list; low risk.
- 22/23/25 rotation loses the typed folder name: skipped as instructed.
- 22/23/25 TV confirm page user agent: phone-test item, nothing to change before it.
- Remaining edge of the double post: a composer force-closed mid-post (rotation) and reopened after the post finished
  still shows the old text (it read the draft before the post cleared it). Posting it again is then a deliberate tap.

## Evidence

(CI section below.)
