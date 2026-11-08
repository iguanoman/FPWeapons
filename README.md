# GobNukedEm3D

GobNukedEm3D transforms your World of Warcraft gameplay into an immersive, retro-style First-Person Shooter experience. Designed with dynamic 3D weapon rendering, combat recoil, and character-bound camera controls, this lightweight addon brings authentic FPS combat dynamics directly into the game engine.

> **Control Modifications Removed**
The control modifications never really worked the way I wanted it to
---

### Key Features

* **True FPS Camera Mode:** Instantly zooms into first-person view, locks camera alignment behind your view axis, and rebinds $A$/$D$ for true WASD strafe movement.
* **Floating 3D Weapon Models:** Displays fully rendered 3D weapon models directly on screen without displaying character meshes or causing frame clipping.
* **Weapon-Specific Recoil & Combos:** Dynamic attack animations triggered on spellcasts and auto-attacks, featuring multi-hit swing combos for melee weapons, heavy cleaves for 2H arms, spell pulses for staves, and kickback recoil for firearms.
* **Auto Weapon Detect & Custom Overrides:** Automatically detects and displays your equipped weapon, while allowing custom Item ID/Link overrides per weapon type.
* **Walking Bobbing:** Optional movement-based head/weapon bobbing with customizable intensity sliders.
* **Per-Hand & Per-Type Tuning:** Customize scale, rotation, and XYZ offsets for Mainhand and Offhand slots, saved separately per weapon category (Guns, Bows, 1H Melee, 2H Melee, Caster Weapons, Staves, Shields).
* **Taint-Safe & Combat Secure:** Built with custom, un-templated UI elements to prevent combat action blocks and protect game execution threads.

---

### Slash Commands

* `/gn3d` or `/gobnuked` – Toggles FPS Mode on or off.
* `/gn3d config` – Opens or closes the configuration settings panel.

### Known Bugs

* Does not currently properly detect transmog appearances

### Changelog

1.0.1 - Removed control remapping, fixed camera view in first person
1.0.0 - Initial release
