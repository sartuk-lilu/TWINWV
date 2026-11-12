***Enjoying the mod?** An **Endorsement** takes one click and helps other players find it. Bug reports and ideas in the comments are always welcome too: most updates came from them.*

*Warfarer vocation* lets you mix in skills from any of the other 9 vocations - but only 5 of them, and without the core traits that normally come with those vocations (like the Thief's Footpad wall-jump). It can wield all 9 weapon types, but switching only cycles one way through a fixed order instead of jumping straight to the one you want. And on top of that, all vocations level up a little at a time instead of the one you're actually playing.
**TWINWV skips Warfarer entirely:**
Bind each of the 9 vocations to its own hotkey or pick one from the Vocation Wheel or flip through them with Vocation Cycling. The mod remembers the weapon, armor and rings you had equipped on each vocation and puts them back on the moment you switch. On top of that, you get 6 extra skill slots per vocation, swapped in with a modifier hotkey or cast directly with their own hotkeys. A vocation icon on screen (configurable, can fade out after a switch) shows which vocation you're on, and an optional Skill Bar shows your skills with the keys that cast them. Ring Presets swap in special rings - say, Dragonsbane for a dragon fight - on the vocations you choose with a single key, and put every vocation's own rings back when you're done.

**How it works**

1. Visit the Vocation Guild NPC and set up each vocation exactly as you normally would - skills, augments, everything.
2. Open the mod's Vocation Switching menu and assign a hotkey to each vocation. Optionally set up extra skills and their modifier hotkey.
3. That's it. Switch vocations freely - your gear and extra skills follow automatically.


**Extra Skills**

- Every vocation gets a second set of 6 skills on top of the 6 the game gives it. Pick them in that vocation's box in the mod's menu, from the skills you have learned - base game, Dark Arisen and Skill Creator / Vocation and Skill Builder skills alike.
- Hold **Ctrl + Alt** (default, rebindable) and your skill slots switch to the Extra Skills - cast them with your usual skill keys. Let go, and your regular skills are back.
- Each vocation keeps its own Extra Skills, and they follow you on every switch like your gear does.
- Prefer one key per skill? See Quick Cast below. Don't need them at all? Extra Skills can be turned off in General settings.


**Vocation Wheel**
*The wheel is drawn with REFramework D2D or D2DX - without one of them the wheel won't open (the vocation hotkeys still work).*


- Made with controllers in mind, works just as well with a mouse. Hold the wheel key, point at a vocation with the right stick or the mouse, and release - one switch, straight to the vocation you want. Works standing still or on the move. Off by default, turn it on in General settings.
- Bind any key or button you like, and set **Hold to open** (0-0.5 s): 0 opens the wheel instantly. If you put it on a key the game also uses - e.g. **L3** for sprint in Toggle mode - give it a short delay (about 0.25-0.3 s) so a quick press still sprints. On keyboard a free side mouse button (M4/M5) with 0 delay is the most comfortable.
- The game slows down while the wheel is open (can be turned off or adjusted), the camera stays put and your character ignores input.
- Pick which vocations show up on the wheel and in what order: give each one a number from 1 to 9 (clockwise from the top), 0 hides it. The wheel needs at least 2 vocations.
- On a gamepad, pick with the right stick, the left stick or either 


**Vocation Cycling**

- For when you only play 2-3 vocations. Give each one a Cycle order (1-9) in its vocation box and flip through them with **R3+LT / R3+RT** on a controller (keyboard keys can be bound separately). Off by default, works alongside the wheel - each has its own order.
- Next/Prev only move a cursor; the switch happens once you stop pressing (0.3 s by default, adjustable), so the mod doesn't re-equip every vocation along the way.
- While cycling is on, a strip of your cycle vocations replaces the single icon, with the one you're about to switch to highlighted. Position and size are adjustable, and it can fade out a moment after a switch (1-3 s) and come back when you switch or cycle.
- While R3 is held the game ignores your buttons, so LT/RT don't also grab or sheathe.


**Quick Cast Extra Skills**

- Bind each of your 6 Extra Skill slots to its own hotkey (default: Alpha1-6) that casts it directly - no more holding Base+Modifier first.
- Works with every skill: all base-game and Dark Arisen skills, and skills from Skill Creator mods.
- Quick Cast presses a skill once. Skills you hold or press again (e.g. Arc of Might) only do their first stage this way - try each skill with Quick Cast and with the Extra Skills combo, and keep the ones that need holding in normal slots.
- Respects Silence: while silenced, Mage and Sorcerer spells can't be cast, just like in the game.


**Skill Bar**
*Drawn with REFramework D2D or D2DX. Off by default - General settings > Skill Bar.*


- Your 6 regular skills and 6 Extra Skills as icons on screen, WoW / Lineage 2 style - in one row or two. The group that's currently in your slots gets a gold frame, so you always see whether you're holding the Extra Skills combo.
- Every cell shows the key that casts it. Regular skills read your key bindings straight from the game's settings, so rebinding in the game updates the bar; Extra Skills show your Base+Modifier combo or your Quick Cast keys.
- Many in-game icons look the same (Archer has about ten identical bows), so each cell also shows a short, recognizable name - "Flagration" instead of "High Flagration", "Mountain" instead of "Mountain Breaker". In the **Skill Labels** section you can give any skill your own name.
- Empty slots in the middle show as dark cells, empty slots at the end are hidden. Position (in % of the screen), size and opacity are adjustable; text always stays readable.
- Bind a **Hide / show key** to tuck the bar away - e.g. when dialogue subtitles appear under it - and press it again to bring it back.


**Skill icons**

- Comes with the original in-game icons for all 119 skills (Dark Arisen included) - only the game's own art, no AI-generated images.
- Want different ones? Drop a PNG with the same name into *reframework/images/TWINWV_skills/<Vocation>/* to replace any icon (all file names are listed in *_icon_file_names.txt*; square images, 96x96 or larger). Skills from Skill Creator mods can get icons too: put *skill_<ID>.png* or *<Skill_Name>.png* into *TWINWV_skills/SkillCreator/* - their IDs and names are written to *re2_framework_log.txt* on start.
- Artists and icon makers: feel free to release your own icon pack as a separate mod that simply overwrites these files, and list TWINWV under "Mods using this mod" - I'll gladly link good packs here.


**Rename your skills**

- Most players remember the button and what a skill does, not names like "Skiedragoun's Feste" or "Ravinour's Hond". In the **Skill Labels** section (shown while the Skill Bar is on) you can give any skill your own short name - "Leap", "Heal", "Big AoE", in any language - and that's what the Skill Bar shows.
- Skills are listed per vocation, each with its full name next to the field. Leave a field empty to keep the default name. Your names are saved with the mod's settings and survive updates and language changes.


**Weapon Slots (per vocation)**

- On top of the auto-remembered loadout, every vocation can keep up to six extra weapon setups of its own, saved and recalled like control groups in StarCraft or Warcraft III: hold a shared modifier key and tap a slot key to save whatever you're wielding into that slot; tap the slot key alone to switch back to it instantly. Off by default. If a slot's weapon isn't in your inventory, or the slot is already equipped, recalling it does nothing.
- Slot hotkeys use the mod's normal keybinding widget, so you're not locked into one fixed modifier: save with Shift+Alpha1 and recall with plain Alpha1, or save with Shift+Alt+Alpha1 and recall with Alt+Alpha1 to keep the bare number row free for Quick Cast.
- If the Rearmament Effect is enabled, recalling a slot plays the same weapon-flash animation as a full vocation switch, so swapping loadouts mid-fight looks like a deliberate rearmament instead of a weapon silently popping into your hands.


**Ring Presets**

- Some fights call for special rings no matter which vocation you're on - Dragonsbane against a dragon, for example. Instead of re-equipping rings on 9 vocations and then putting the old ones back, turn on a Ring Preset: it lays temporary rings on top of what each vocation remembers.
- Up to 6 presets, each with a name, its own hotkey and the vocations it applies to. Unchecked vocations keep their own rings - your buffer can stay on cast-speed rings while everyone else hits the dragon harder.
- Setup: add a preset, turn it on, put the rings on and press **Remember current rings**. The menu lists the saved rings by name.
- Press the preset's key to turn it on - the rings change right away and on every switch to a checked vocation. Press it again to turn it off, and every vocation gets its own rings back.
- While a preset is on, ring auto-remember is paused for its vocations, so the temporary rings never overwrite what they remember. A preset with one ring keeps the vocation's second ring; if a preset ring is missing (sold or on a pawn), the vocation's own rings are used.
- A small HUD in the style of the game's control hints lists your presets with their keys, the active one in gold. Show it always, only while a preset is on, or hide it; position, size and opacity are adjustable.


**Extra features**

- Optional toggles to remove weapon/armor vocation requirements entirely.
- Rearmament Effect on vocation switching (on by default).
- Remembers the exact copy of each item, so two copies of the same weapon with different enchantments or stats never get mixed up. If that copy is in storage or with a pawn, it simply isn't equipped until it's back - never a look-alike instead**.**
- High Spellhold (Mage and Sorcerer) keeps its stored spell when you switch vocations - each of them keeps its own. On the Skill Bar the Spellhold cell shows the stored spell's icon and name in yellow.
- The vocation icon, the cycling strip, the Skill Bar and the Ring Presets HUD hide during cutscenes, and vocation switching is blocked while one plays.
- Health and Stamina keep their percentage when you switch vocations: 80% stays 80% - no free heal, no drop to critical health when going from a low-Health vocation to a high-Health one.
- Never leaves you empty-handed: if a remembered weapon can't be equipped right now (sold, stored or not allowed for the vocation), your current weapon stays.
- The Extra Skills menu only offers skills you have actually learned.


**Compatibility**

- **Skill Creator** mods (e.g. Dullahan, custom vocations like Mystic Knight): skills you've unlocked show up in the Extra Skill slots and on the Skill Bar with their real names, Quick Cast casts them, and while a custom vocation is active TWINWV shows its name instead of "Trickster".
- **Vocation and Skill Builder (VSB)**: its skills show their real names in the Extra Skills menu and on the Skill Bar, and can get Skill Bar icons the same way as Skill Creator skills.
- **Transmogify**: works together - vocation switching and weapon slots apply Transmogify's looks, a drawn weapon is drawn again after the switch, and the Rearmament Effect plays with sound.


**Known issues with Transmogify** (everything works, these are cosmetic — I've contacted the author about a cleaner integration):

- For a split second after switching, your real gear is visible before Transmogify applies its look.
- A drawn weapon briefly goes to your back and is drawn again with the normal animation, instead of appearing in hand right away.


**Troubleshooting**
Black screen or a freeze right after loading a save - even without TWINWV? That's the drawing plugin: try [D2DX](https://www.nexusmods.com/dragonsdogma2/mods/1261) instead of REFramework D2D (remove reframework-d2d.dll). TWINWV works with both.

If fast vocation switching still crashes the game on your PC, open *reframework/autorun/TWINWV.lua*, find **COOLDOWN_SEC = 0.2** (in the SwitchGate block) and raise it - anything from 0.2 to 0.6 seconds.

**Translations**
🇬🇧 English, 🇷🇺 Russian, 🇰🇷 Korean, 🇫🇷 French, 🇨🇳 Chinese

**Shout outs**
Thanks to [Geonode](https://www.nexusmods.com/dragonsdogma2/users/6993355) for the inspiration, [Caites](https://www.nexusmods.com/dragonsdogma2/users/703937) for the vocation images.
