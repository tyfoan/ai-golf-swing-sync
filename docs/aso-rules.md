# ASO rules (App Store / iOS)

Working rules, ordered by how much they move the needle. Each is marked:
**[mechanics]** — how the store provably works; **[directional]** — well-established
effect, exact weight not public; **[judgement]** — my opinion, argue with it.

Apple has never published its ranking weights. Anything claiming "the title counts
3× the keyword field" is folklore. What follows separates the two.

---

## A. What is actually indexed

**1. Only three fields feed search: name (30), subtitle (30), keywords (100).** **[mechanics]**
The description is **not** indexed on the App Store. (It *is* on Google Play — do not
carry Play habits across.) Promotional text is not indexed either.

**2. Those three fields are ONE pool. A word repeated across them buys nothing.** **[mechanics]**
Repeating a name word in the subtitle or keywords does not strengthen it; it spends
characters you cannot get back. Audit for duplicates before adding anything.

**3. Apple builds combinations for you, so single words beat phrases.** **[mechanics]**
`putting` + `tempo` in the pool already matches "putting tempo". Writing the phrase
`putting tempo` instead spends a character on the space and blocks both words from
pairing with anything else.

**4. No spaces after commas in the keyword field.** **[mechanics]**
`a,b,c` not `a, b, c`. Each space is a character that could have been a letter.

**5. Every field should end at its limit.** **[mechanics]**
An unused character is a query that cannot find you. 81/100 is not "almost full",
it is 19 lost.

**6. Skip: your category name, "app", "free", and plurals of words already present.** **[mechanics]**
Apple stems English reasonably (`swing` also matches `swings`); stemming in other
languages is less reliable, so plurals may be worth their characters outside English.

**7. Competitor brand names are a rejection risk, not a clever trick.** **[mechanics]**

**8. Extra locales multiply your keyword surface, often the cheapest win available.** **[mechanics]**
Each localization carries its own 100 characters, and a storefront may index more than
one. In the US, `en-US` **and** `es-MX` are both searched. Elsewhere, `en-GB` plus the
local language. Adding a locale you were not using can nearly double the vocabulary you
are findable by — for the price of a translation, not a feature.

---

## B. What ranks you, beyond the words

**9. Conversion rate is a ranking input, not only a revenue input.** **[directional]**
Impressions that do not convert push you down. This is why the icon and first two
screenshots affect *ranking*, not just install count — the two goals are not separate.

**10. Download velocity and retention feed ranking.** **[directional]**
Recent trend beats lifetime totals. A burst that churns is worth less than steady
installs that stay.

**11. Ratings volume and average affect both ranking and tap-through.** **[directional]**
Prompt after a success moment, never after a failure. Concretely for this app: never
prompt after a take where detection found nothing.

---

## C. The page itself

**12. The icon and the first two screenshots are the whole pitch.** **[directional]**
Most users decide in the search results, without opening the page and without scrolling.
Everything after screenshot 3 is for the minority who are already interested.

**13. Screenshot 1 shows the outcome, not the interface.** **[judgement]**
Caption must be readable at thumbnail size — roughly 5 words, high contrast. A
screenshot that needs to be tapped to be understood has already lost.

**14. The video preview autoplays muted; the first 3 seconds decide.** **[directional]**
No logo intro, no build-up. Open on the result.

**15. First three lines of the description are all that show before "more".** **[judgement]**
Not indexed, but read by the people closest to installing.

---

## D. Process

**16. Promotional text (170 chars) is the only field editable without a new version.** **[mechanics]**
Use it for anything time-bound. Everything else — name, subtitle, keywords, screenshots,
description — ships with an app version.

**17. Change one thing per release, or you learn nothing.** **[judgement]**
Keywords and screenshots at once, and a move in either direction is unattributable.

**18. Use Product Page Optimization for icon/screenshot tests — it is free and gives real numbers.** **[mechanics]**
Apple's own A/B test in App Store Connect. Judgement is not a substitute for it.

**19. Pick keywords from search-volume data, not from brainstorming.** **[judgement]**
Without a tool (AppFollow, Sensor Tower, ASOMobile, or Apple Search Ads' own volume
figures) a keyword set is a hypothesis. Apple Search Ads will quote search volume for
free even if you never run a campaign — that is the cheapest real data available.

**20. Re-audit after every metadata edit.** **[judgement]**
The failure mode is not a bad word, it is a duplicate creeping back in and silently
costing 10 characters. Count the pool, do not eyeball it.

---

## Quick audit

For any app, in order:

1. List the pool: name + subtitle + keyword field, all words lowercased.
2. Any word appearing twice? Remove all but one, reclaim the characters.
3. Any field under its limit? Fill it.
4. Any phrase where two singles would do? Split it.
5. Any locale left untranslated in a storefront that indexes it? That is the biggest
   remaining win.
