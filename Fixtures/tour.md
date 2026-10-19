---
title: Marginalia tour
author: sebo
date: 2026-10-18
---

# Marginalia, a tour of every construct

This file exercises everything the app must render. It opens in **edit mode** with the Markdown visible, markers hanging in the gutter, and a few {==margin comments==}{>>@sebo: like this one, anchored to the highlighted text<<} already in place.

## Why a dedicated app

Working with Claude on documents means reading a lot of Markdown. Terminal rendering is fine for a glance, not for an hour. Browsers are heavy. Notion is slow and far from the file. What was missing was something that opens in _under 200 ms_, shows `exactly` what is on disk, and lets me talk back in the margin. {>>@sebo: standalone comment at the end of a paragraph<<}

The principles, in order:

1. Speed is the product.
2. The file is the only truth.
3. Typography first.
4. Chrome disappears.
5. Native, not web.

### Inline styles

Bold with **asterisks** and __underscores__, italic with *asterisks* and _underscores_, ***both***, ~~strikethrough~~, `inline code`, a [link to the spec](SPEC.md), an autolink <https://commonmark.org>, and a footnote reference[^1]. Hard line break follows this line  
and this is the continuation.

[^1]: Footnotes render at the bottom in reading mode and stay where they are in edit mode.

### Lists

- A bullet
- Another bullet with a longer line that wraps onto a second line so the hanging indent can be checked against the text edge above it
  - Nested bullet
  - Another nested one
    - Third level
- Back to the first level

* Asterisk bullets
+ Plus bullets

10. Numbered lists can start anywhere
11. And the marker width grows
12. Which the gutter must absorb

- [ ] An open task
- [x] A done task
- [ ] Another open task with **bold** inside

### Blockquote

> The reader should never have to work to find the text edge. Markers live in the margin, text lives in the column, and the two never fight.
>
> A second paragraph inside the same quote, with a {==comment anchored inside a quote==}{>>@claude: checking that cards position correctly when the anchor is indented<<}{>>@sebo: looks right, thanks<<}

### Code

Inline `let x = 1` and a fenced block:

```swift
import AppKit

final class EditorTextView: NSTextView {
    override func keyDown(with event: NSEvent) {
        // Smart list continuation lives here.
        super.keyDown(with: event)
    }
}
```

```python
def three_way_merge(base: list[str], ours: list[str], theirs: list[str]) -> list[str]:
    """Line-level merge. Conflicts keep ours and are marked."""
    return ours  # placeholder
```

```bash
md Fixtures/tour.md
md --screenshot _build/smoke/light-edit.png Fixtures/tour.md
```

    An indented code block, four spaces, no fence.

### Table

| Metric | Budget | Measured | Status |
|---|---:|---:|:---:|
| Cold launch to first paint, 10 KB | 200 ms | — | pending |
| Open another file while running | 50 ms | — | pending |
| Keystroke to paint | 8 ms | — | pending |
| External change to paint, 100 KB | 50 ms | — | pending |
| Open 1 MB file | 500 ms | — | pending |

### Image

![Sample image, a circle](mark.png)

### Horizontal rule

---

### Headings at every level

#### Fourth level heading

Body under an H4. {>>@sebo: H4 to H6 share the body size, hierarchy by weight and color only<<}

##### Fifth level heading

Body under an H5.

###### Sixth level heading

Body under an H6.

## A long section for scrolling

The paragraphs below are filler so that scroll performance, typewriter mode, and the outline can be checked on something taller than one screen.

Measure merge comment file sans speed viewport newsreader comment theme caret margin truth change diff file heading truth mono change comment quattro glyph paragraph newsreader comment quattro newsreader merge comment paragraph margin mono leading markdown diff measure sans glyph quattro native mono column speed newsreader quattro gutter viewport speed mono file quattro comment geist caret.

Sans change text status newsreader status viewport native heading column heading truth quattro native serif outline kit bar markdown flex file glyph theme diff rhythm kit measure outline diff margin file mono quattro text kit layout flex outline newsreader status file truth sebo palette file comment native quattro bar markdown autosave layout reader status layout rhythm geist glyph outline comment caret markdown leading heading merge merge.

Truth rhythm bar merge mono sebo leading change mono sebo diff layout autosave paragraph measure truth column measure paragraph paragraph the outline newsreader column claude markdown the measure diff sans viewport geist quattro text leading theme geist comment status mono merge merge merge merge speed palette merge comment gutter file caret bar rhythm glyph kit flex comment speed the quattro measure sans speed viewport geist reader.

Caret geist autosave measure claude layout flex viewport palette glyph glyph outline status palette palette native truth measure speed kit claude palette rhythm serif reader caret serif viewport measure sans reader serif native truth claude serif viewport rhythm layout.

### Section 1 marker

Sans sans theme kit paragraph geist gutter heading merge paragraph gutter serif outline layout reader reader sebo palette claude gutter flex layout bar layout viewport truth paragraph speed paragraph palette gutter kit caret palette geist geist the palette layout truth glyph autosave gutter palette column change kit truth merge.

Merge truth rhythm rhythm leading reader measure newsreader status measure geist flex palette layout measure mono mono leading reader the speed serif leading change gutter caret reader claude caret markdown theme heading newsreader text claude sans diff leading comment layout status newsreader serif diff theme leading sans measure serif theme reader bar column flex the measure column measure palette geist glyph mono comment text.

Serif mono palette speed mono comment heading gutter sebo margin speed theme bar mono reader file bar text geist theme flex theme gutter sebo bar theme sans palette theme heading serif claude mono gutter bar leading diff glyph merge bar text file heading change file caret native glyph {==measure==}{>>@claude: is this the right word here?<<} viewport measure claude leading status paragraph speed merge outline rhythm paragraph rhythm change theme merge kit diff gutter layout.

Truth viewport reader kit mono status bar reader autosave kit serif geist markdown theme file glyph paragraph speed truth claude sebo margin column sebo leading change claude merge measure sans theme quattro outline text truth sebo comment column change file sebo reader truth claude truth flex paragraph file claude glyph status the kit mono diff.

Geist leading margin serif heading glyph rhythm claude comment column gutter native native serif caret markdown bar theme column sebo layout reader claude margin the reader theme mono gutter theme palette heading bar speed change outline sans merge theme native caret paragraph kit gutter leading merge layout comment leading the file claude.

Rhythm comment truth autosave theme markdown flex heading markdown margin status column rhythm sebo bar the claude viewport kit mono text heading margin native caret layout column the kit autosave truth palette sebo theme gutter heading theme the truth claude truth measure merge newsreader margin merge reader native native paragraph truth newsreader serif measure flex autosave text outline measure markdown geist measure.

Theme change theme leading serif theme quattro reader newsreader paragraph truth reader margin leading viewport speed autosave bar mono comment reader sans heading outline claude the status file theme sans truth serif file palette claude file claude.

Caret paragraph status outline autosave file palette markdown margin geist gutter file flex measure kit claude native geist quattro leading the palette comment outline sebo speed caret outline markdown serif markdown status status status glyph mono gutter native truth palette reader markdown status file theme bar sebo autosave caret caret.

Newsreader truth measure serif claude viewport leading flex theme sebo glyph viewport paragraph outline outline merge reader rhythm the outline bar merge native measure diff layout autosave text glyph kit the text kit merge glyph gutter the markdown claude.

### Section 2 marker

File merge autosave newsreader file viewport change sebo comment sebo speed comment markdown measure heading sebo change theme text gutter viewport change reader merge mono mono caret truth comment diff bar geist leading markdown outline comment mono leading rhythm palette diff kit markdown native claude claude merge heading native palette mono merge glyph rhythm rhythm file caret theme.

Mono paragraph bar kit bar change leading mono gutter heading truth column kit mono truth text heading viewport claude quattro gutter reader diff autosave diff serif caret autosave sebo kit comment outline sebo quattro viewport leading theme serif caret truth sebo heading autosave merge bar change native reader leading margin change palette newsreader outline the file merge serif status bar heading speed paragraph measure measure serif.

Status truth mono margin the leading paragraph quattro margin native leading claude serif change glyph speed file native serif newsreader gutter autosave claude paragraph flex the the sans native status sebo text heading palette serif heading mono heading reader diff native.

Reader gutter outline diff truth claude paragraph change viewport paragraph outline margin kit diff viewport merge gutter the markdown theme file caret outline gutter native gutter paragraph status paragraph claude markdown speed geist outline geist column paragraph outline.

Comment flex measure merge comment caret reader flex measure diff comment comment column merge bar text glyph truth rhythm kit gutter column serif status margin native autosave viewport kit bar rhythm speed the truth sebo truth layout diff glyph mono caret autosave layout native change truth comment palette gutter viewport sans bar gutter text viewport palette reader diff heading merge margin.

Margin status file comment claude gutter file flex kit viewport sebo kit geist margin claude text sebo native the flex file reader paragraph speed palette status autosave claude change outline leading outline column the native measure flex heading text text status viewport flex truth theme gutter merge rhythm heading diff file margin palette mono sans text rhythm change speed.

Claude geist truth caret speed diff outline bar column paragraph leading diff status geist heading sans glyph markdown markdown sebo quattro sebo viewport claude claude gutter bar heading column heading heading {==measure==}{>>@claude: is this the right word here?<<} markdown newsreader gutter text file merge claude.

Theme serif paragraph speed status margin speed the palette paragraph bar viewport margin markdown paragraph glyph comment gutter flex newsreader gutter file viewport theme column bar flex claude the speed flex geist layout caret margin viewport kit measure margin caret claude margin flex caret the text diff viewport column geist.

File caret margin outline mono palette file diff speed merge mono measure sans truth rhythm merge sebo diff markdown native diff comment native quattro layout diff diff reader viewport gutter merge merge caret the change rhythm change glyph truth merge quattro viewport status rhythm leading the comment mono measure merge truth quattro geist viewport.

### Section 3 marker

Rhythm measure layout markdown rhythm serif rhythm file speed autosave outline gutter native leading margin palette text comment flex autosave truth geist rhythm paragraph geist merge geist gutter palette column quattro caret margin merge serif rhythm autosave layout glyph measure heading gutter margin mono margin text glyph autosave flex status mono native diff native newsreader heading change autosave viewport bar theme bar column reader the geist outline.

Heading bar geist status column palette merge speed file leading layout change viewport truth bar theme theme margin margin leading truth text theme truth comment theme autosave leading reader file geist glyph gutter leading outline markdown rhythm paragraph file layout geist claude rhythm text geist sebo status measure claude theme palette caret newsreader claude geist theme heading text viewport margin gutter column merge rhythm.

Text autosave rhythm claude glyph serif comment viewport bar mono serif newsreader speed claude sans merge viewport claude autosave viewport quattro measure viewport kit truth bar paragraph column geist comment markdown serif claude native newsreader text the margin paragraph measure markdown geist change diff theme viewport comment leading outline paragraph geist margin.

Comment the quattro layout native speed serif layout sans paragraph diff newsreader native newsreader leading caret viewport geist palette rhythm leading the heading measure bar speed file measure sebo merge claude the comment mono layout flex.

Flex serif outline heading rhythm the margin comment sans reader merge column heading rhythm comment speed the geist mono gutter measure diff gutter serif flex theme diff geist column theme native file native comment palette sans the autosave change status truth bar column paragraph speed claude paragraph margin glyph kit claude comment sebo mono change serif claude markdown caret truth theme the rhythm.

Heading gutter rhythm text gutter autosave kit flex heading autosave sans palette palette serif the reader change paragraph quattro native caret merge geist newsreader file quattro rhythm measure margin reader glyph speed geist rhythm layout measure reader reader margin leading margin file margin file newsreader viewport gutter sans file autosave speed.

Caret caret glyph margin margin truth markdown palette speed leading speed caret markdown text kit change claude reader layout claude markdown comment viewport text flex theme palette markdown geist reader diff reader change serif speed layout palette comment sans quattro caret truth quattro markdown rhythm change the serif gutter markdown.

The layout outline speed outline column outline newsreader layout theme claude quattro rhythm markdown caret paragraph outline rhythm glyph truth outline mono speed text layout speed merge merge truth change reader viewport caret native claude change sans theme.

Autosave paragraph status leading sans flex flex margin layout newsreader text serif measure bar mono text rhythm status bar claude newsreader paragraph leading kit status heading theme gutter sebo native geist measure measure heading text flex serif layout rhythm heading text gutter claude speed rhythm.

### Section 4 marker

Gutter autosave measure measure native native change sebo gutter speed speed sebo caret autosave status margin the merge change paragraph theme markdown status reader measure claude flex merge the heading change quattro newsreader diff paragraph newsreader paragraph column glyph status change.

Claude speed diff heading merge rhythm claude change palette status reader geist diff serif column text the autosave outline speed margin claude sans caret rhythm gutter serif layout speed quattro status sans caret palette theme reader viewport serif kit diff status caret column merge theme glyph geist layout comment claude sebo autosave merge comment the.

Diff diff layout newsreader claude speed paragraph native merge serif paragraph merge status caret rhythm leading file gutter palette mono paragraph measure layout diff status markdown mono leading palette layout paragraph sebo autosave claude change column palette the sebo.

Heading native text palette outline change geist truth viewport measure native autosave comment truth quattro text leading serif layout newsreader the the caret file markdown claude flex speed newsreader measure paragraph column bar layout measure caret merge sans rhythm geist flex truth mono native gutter outline caret serif truth bar glyph mono glyph claude diff paragraph leading.

Outline mono comment palette status measure outline heading outline rhythm sans flex the rhythm text status quattro outline markdown status viewport change diff file column viewport reader reader geist margin kit speed theme palette outline measure margin caret diff leading kit speed viewport kit palette serif mono caret markdown change kit change claude mono comment markdown markdown layout outline merge kit theme sebo theme layout.

Outline glyph kit gutter text native leading newsreader truth margin merge mono merge sans quattro comment merge native speed the margin gutter palette flex comment theme sans geist autosave geist measure flex truth caret margin status column speed column margin diff speed the viewport leading native mono claude.

Column diff margin text reader change quattro newsreader comment outline quattro serif margin glyph diff quattro merge bar file the autosave flex newsreader measure palette diff mono speed truth palette caret measure the change the the glyph truth caret glyph leading palette reader sebo quattro heading bar column comment viewport measure truth markdown mono.

Status claude comment margin the comment the geist truth autosave native native flex rhythm outline flex comment text viewport quattro bar palette rhythm measure glyph viewport rhythm diff palette autosave bar sebo quattro kit markdown sebo comment geist flex kit flex the measure flex native newsreader change heading autosave autosave autosave flex paragraph bar markdown the text claude sebo change rhythm newsreader margin markdown measure quattro.

Sebo mono outline layout sans truth sans mono outline autosave gutter paragraph native flex comment merge status caret claude newsreader the autosave status sans truth sans layout file paragraph merge newsreader serif claude serif text palette theme newsreader gutter gutter caret gutter truth column.

### Section 5 marker

Viewport quattro quattro layout merge serif measure heading margin outline viewport speed viewport status truth measure text flex reader layout sebo serif flex reader speed margin caret quattro outline newsreader quattro caret claude sebo change speed bar newsreader flex leading claude margin kit gutter column autosave truth reader comment margin mono viewport status.

File flex merge glyph truth claude text quattro paragraph truth theme merge column bar rhythm viewport heading paragraph column margin claude layout comment mono reader comment claude theme palette comment speed measure text the gutter native newsreader newsreader bar speed palette text viewport claude autosave glyph viewport palette autosave rhythm bar heading measure the status gutter margin rhythm paragraph file geist viewport leading bar speed autosave.

File bar kit text paragraph palette glyph viewport measure kit paragraph comment column bar mono measure bar measure sebo diff diff heading measure reader sebo quattro markdown kit rhythm claude outline speed text status palette glyph.

Theme comment caret mono palette markdown glyph claude gutter viewport change claude heading heading speed autosave markdown diff rhythm comment markdown measure reader bar theme kit theme leading bar the serif markdown column viewport change margin diff caret sebo quattro column leading column serif.

Column gutter flex truth truth flex outline sebo column caret leading geist gutter newsreader native gutter the file serif diff comment serif layout kit markdown outline truth the diff palette leading sebo heading column quattro viewport margin rhythm viewport quattro flex the layout serif bar serif file glyph layout.

Text autosave quattro comment markdown speed outline bar theme reader serif sans leading reader heading truth paragraph geist column rhythm speed native claude mono reader reader speed gutter claude reader flex quattro status serif heading bar speed layout speed column margin sebo glyph status outline newsreader theme sebo glyph glyph.

Merge leading sans newsreader paragraph paragraph measure quattro status merge rhythm reader autosave diff flex flex serif margin merge comment viewport kit merge heading kit change quattro text merge mono comment text serif measure layout heading change the viewport speed serif column.

Text change gutter theme reader paragraph leading diff merge status margin margin margin geist sebo geist sebo sans margin geist speed claude glyph serif the change heading margin markdown glyph native layout rhythm glyph comment flex theme sebo truth.

Newsreader sans measure bar glyph theme leading markdown diff quattro markdown sebo heading truth sans markdown status geist quattro paragraph autosave gutter mono viewport status mono native geist palette palette native reader heading kit paragraph gutter theme sans autosave newsreader merge the layout rhythm heading text mono text outline sebo markdown caret markdown comment reader rhythm mono file flex layout bar comment serif autosave.

### Section 6 marker

Layout speed serif paragraph measure diff kit layout leading gutter geist geist sebo serif speed palette sebo leading diff speed the diff mono newsreader glyph outline merge quattro measure diff sebo geist flex glyph autosave bar status markdown layout markdown layout merge serif mono flex autosave text the outline autosave bar native column sans native measure change quattro autosave newsreader paragraph truth kit.

Flex heading text caret change the reader comment claude quattro outline native sans native sans geist change serif serif change autosave status layout margin flex layout bar the file serif paragraph speed diff viewport theme merge mono quattro measure gutter diff outline merge bar geist newsreader kit serif truth rhythm viewport text viewport file native.

Column glyph markdown kit theme diff rhythm serif markdown theme caret theme gutter diff column comment quattro flex speed layout quattro margin diff the the native mono the native merge speed newsreader the reader gutter column outline mono quattro sebo sans theme measure quattro gutter diff flex glyph measure rhythm serif theme speed reader speed file rhythm serif outline status geist change comment the newsreader text measure.

Layout sebo rhythm margin sebo speed newsreader file layout gutter bar geist autosave reader comment paragraph merge newsreader margin bar comment geist heading heading paragraph margin rhythm newsreader column text the status native diff flex claude outline file heading autosave newsreader paragraph diff native merge outline reader heading truth column.

Layout autosave column the markdown merge mono viewport glyph kit sans autosave kit merge file glyph change layout mono heading autosave gutter status markdown layout heading change margin sebo reader kit measure heading leading truth gutter sebo sans leading mono bar status heading rhythm viewport.

Caret merge autosave newsreader caret native palette theme caret paragraph bar leading claude flex bar newsreader viewport sans heading merge flex theme caret leading glyph theme truth sans sebo autosave reader quattro measure native the autosave truth column paragraph text gutter speed file mono viewport theme native gutter file native truth paragraph markdown leading merge markdown layout.

Status leading sebo column reader viewport layout diff reader status heading merge layout speed column markdown glyph sebo flex paragraph margin merge margin flex rhythm change gutter native measure autosave margin mono native column quattro paragraph quattro outline serif claude change quattro layout the glyph markdown margin newsreader flex comment heading glyph margin text caret layout truth diff merge geist.

Sebo serif truth layout change bar kit theme bar theme comment caret change theme leading outline gutter margin mono claude column sans rhythm heading sans claude heading comment rhythm layout layout diff truth gutter native leading leading outline palette heading heading the theme bar leading layout native leading measure.

Kit glyph mono change rhythm measure flex status merge caret glyph markdown the viewport outline caret margin comment sebo native gutter glyph native bar glyph rhythm text bar status quattro viewport markdown rhythm mono file margin the status outline truth kit quattro claude speed outline change outline gutter sans text.

### Section 7 marker

Layout truth markdown geist claude heading truth leading reader reader merge {==measure==}{>>@claude: is this the right word here?<<} markdown viewport column serif rhythm speed native geist text autosave column layout text paragraph viewport leading mono viewport claude heading comment margin speed.

Comment caret outline change outline rhythm native flex newsreader truth measure paragraph rhythm leading bar merge truth margin bar palette gutter caret viewport the margin geist theme change measure markdown file comment theme diff kit file bar the column rhythm autosave markdown the bar quattro layout quattro gutter palette truth sans text serif status change sans measure merge flex geist.
