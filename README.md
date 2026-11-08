# First Person Weapons

First Person Weapons is an immersive addon that aims to provide more animated effects to the first person view in World of Warcraft. Utilizing in game model rendering and animations, the goal is to make the game feel very close to other first person RPGs. Currently being developed for Forever.

It is HIGHLY recommended to use this addon alongside the "Action Combat Mode" addon with the minimum zoom and crosshair set to 0 for best experience. It should also be noted that races other than Skyborne may experience slightly off model/animation orientation by default, but this can be modified for each race in the configuration menu at the user's discretion.

Please be aware that this addon is in a very early state and may not work as intended as it has not been tested in every scenario. 
Please report all LUA errors and bugs encountered with a bug report. 

Race orientation parameters may also be provided to the author for updating the defaults in future patches.

### Key Features

* **Fully rendered 3D Models:** Displays fully rendered 3D weapon models directly on screen using in-game characters, items and animations.
* **Transmog Support:** Works with transmogrified weapon models, applied effects and enchantments (experimental).
* **Automatic First Person:** Will automatically display weapons when zoomed all the way in to first person and disable when zooming out.
* **Weapon Specific Animations and Main Hand/Off Hand combos:** Every weapon type will use its own animations for idling, attacking, and casting. Certain weapons will combo with others to change the animation. 
* **Walk Sway:** Optional movement-based head/weapon bobbing with customizable intensity sliders.
* **Per-Hand & Per-Type Settings:** Customize roll, pitch, yaw, and XYZ offsets for Mainhand and Offhand slots and attack/cast pose animations. Saved separately per weapon category and for race/gender combo (1H Melee, 2H Melee, Caster Weapon, Caster Hand, Shields, Offhand Weapons, and Ranged Weapons)
* **Auto Weapon Detect** Automatically detects what weapons you are using and assigns them appropriately - can be overridden in settings. 

---

### Slash Commands

* `/fpw` – Toggles first person weapon mode on or off.
* `/fpw config` – Opens or closes the configuration settings panel.
* `/fpw sheathe`– Switches the “Sheathe out of combat” option on or off, the same as the Sheathe / Draw key.
* `/fpw ignorelast` –	Stops the last spell that made your weapons swing from doing so again. 
* `/fpw ignore <spellID>` –	Ignores spell from animating
* `/fpw unignore <spellID>` –	Removes a spell from the ignore list.
* `/fpw ignored` – Lists the ignored spells.

---

### Potential future features

* Druid forms are not currently supported.
* Ranged weapons do not have animation support.
* Full support for all races.
* Class/spell specific animations.
* More fleshed out animation sequences for weapons and casts.
* Support for non-combat abilities like fishing or cooking.

### Known Issues / Bugs

* When first loading in the model may load in an odd way, but the addon will refresh it into the right orientation automatically.
* If models do not load, please check the Sheathe toggle to see how it is configured or try /reload.  
* Animations for some weapons are not 100% tested and may experience model clipping.
* Weapon attack animations may not line up correctly with auto-attacks due to combat log restrictions. Current system utilizes weapon speed and haste modifiers.
* Movement sway set past default high may increase chances of model clipping.
* If you encounter a bug not listed here, please enter a bug report. If you encounter LUA errors please use BugSack to provide the error messages.


### Changelog

* 1.0.1 - Bug fixes and added RaceDefaults .lua data file - also added Retail download option for testing.
* 1.0.0 - Initial release

### Credit

Credit Radio Free Hub City's addon Gob Nuked 'Em 3D for inspiration and granting permission for forking and modification.

