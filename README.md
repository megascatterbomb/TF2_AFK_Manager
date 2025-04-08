# [TF2] AFK Manager

## Description

**[TF2] AFK Manager** is a SourceMod that plugin monitors player activity and notifies others when a player goes AFK.

Additionally, it can display an AFK message above the player's head, making it easy for other players to identify who is inactive.

![image](https://github.com/user-attachments/assets/d813271d-9bec-4190-85e5-0ef1881e2a6d)
Typical dustbowl gameplay.

## Features

- **AFK Detection**: Automatically detects when a player has been inactive for a specified period.
- **AFK Notifications**: Sends a message to the chat when a player goes AFK or returns from being AFK.
- **AFK Text Entities**: Displays a floating "AFK" text and a timer above the AFK player's head.
- **Customizable Settings**: Allows server administrators to configure the AFK time threshold and toggle the display of AFK messages and text entities.

## Installation

1. **Download the Plugin**: Grab the [latest release](https://github.com/roxrosykid/TF2_AFK_Manager/releases/latest). 
2. **Upload the Plugin**: Place the `.smx` file in the `addons/sourcemod/plugins/` directory.

## Usage

The plugin comes with several ConVars that can be configured to customize its behavior. You can adjust these cvars in `cfg/sourcemod/afk-manager.cfg`
- **ConVars**:
  - `sm_afk_time`: Sets the time in seconds before a player is considered AFK. Default is `120.0` seconds (2 minutes).
  - `sm_afk_ignore_dead`: Pauses the AFK timer for dead players. Intended for use with gamemodes where players may be dead for long periods of time, such as Arena or VSH. `1` for enabled, `0` for disabled. Default is `0`.
  - `sm_afk_action`: Determines the action to take against players who have been idle for `mp_idlemaxtime` minutes. `0` to do nothing, `1` to move the player into spectator and later kick, `2` to kick. Default is `1`.
  - `sm_afk_admin_immune`: Determines if admins with the generic (`b`) or root (`z`) flags should be affected by anti-AFK actions. `0` for no immunity, `1` for immunity against all actions, `2` for immunity to kicks only.
  - `sm_afk_message`: Toggles the display of AFK message notifications in the chat. `1` for enabled, `0` for disabled. Default is `1`.
  - `sm_afk_text`: Toggles the display of text entities above AFK players. `1` for enabled, `0` for disabled. Default is `1`.
  - `sm_afk_text_font`: Controls the font used for AFK text entities. See available fonts [here](https://developer.valvesoftware.com/wiki/Point_worldtext). `0` is minimum, `12` is maximum. Default is `0`.

### Example Configuration

```cfg
sm_afk_time "300.0"
sm_afk_message "1"
sm_afk_text "1"
```
