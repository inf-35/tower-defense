# Tower Defense Architecture

This document describes the project architecture by subsystem.

The game is a Godot 4 2D roguelike tower defense project built around:

- autoload singletons for long-lived services
- a central `Island` world model for terrain and tower state
- component-based `Unit` and `Tower` entities
- data-driven content authored mostly as `.tres` resources
- signal-based coordination between gameplay, UI, and presentation

## High-Level Runtime Flow

1. `project.godot` starts the game in `main_menu.tscn`.
2. `UI/main_menu.gd` either starts a new run or loads into `island.tscn`.
3. `Scene Elements/island.gd` becomes the active world scene.
4. `Island._ready()` marks the game as in-run, creates an `ExpansionService`, registers the island with shared services, and calls `Phases.start_game()`.
5. `Singletons/phase_manager.gd` starts the core services (`Clock`, `References`, `ClickHandler`, `Units`, `Towers`, `Player`, `SpawnPointService`, `TowerNetworkManager`) and either:
   - loads a save via `SaveLoad`, or
   - starts a fresh run and asks the island to generate the starting terrain.
6. The run then alternates between:
   - choice phases (expansion and rewards),
   - building phases,
   - combat waves.

## Cross-Cutting Patterns

### 1. Autoload service layer

Most global coordination lives in autoloads configured in `project.godot`.

Examples:

- `Phases`: run state machine
- `Player`: player state, relics, trader, tutorial flags
- `Waves`: combat wave spawning
- `Navigation`: pathfinding and flow-field cache
- `CombatManager`: hit resolution and projectile simulation
- `RewardService`: reward generation and selection
- `KeywordService`: UI keyword/tooltip resolution

This gives the project fast access to shared state, but it also creates fairly strong coupling between subsystems.

### 2. World state centered in `Island`

`Scene Elements/island.gd` is the main state owner for the active map. It owns:

- `terrain_base_grid`
- `tower_grid`
- boundary and adjacency bookkeeping
- tower construction, upgrade, and removal
- navigation-grid rebuild triggers
- world save/load reconstruction

Most systems read world state through `References.island`.

### 3. Component-based entities

`Unit` and `Tower` act as gameplay chassis, while behavior is split into reusable components:

- `MovementComponent`
- `NavigationComponent`
- `HealthComponent`
- `ModifiersComponent`
- `RangeComponent`
- `AttackComponent`
- `Behavior`

This is the main gameplay abstraction in the project.

### 4. Event/effect architecture

The project has a local and global event model:

- `Unit.on_event` handles per-unit reactions
- `Player.on_event` acts as the global event bus
- `EffectPrototype` and `EffectInstance` implement reactive gameplay effects
- relics often register global effects through `GlobalEventService`

This lets towers, relics, and statuses react to hits, deaths, adjacency changes, wave transitions, and other gameplay events.

### 5. Data-driven content

Many gameplay definitions live in resources rather than hardcoded logic:

- tower metadata in `TowerData`
- enemy metadata in `UnitData`
- combat payloads in `AttackData`
- terrain modifiers in terrain database resources
- relics and rewards in `.tres` files under `Content`

The scripts under `Singletons/towers.gd` and `Singletons/units.gd` scan content folders and build repositories at startup.

## Subsystems

## 1. Entry Points and Scene Composition

### Responsibility

Own the scene tree roots and switch between menu and gameplay.

### Key files

- `project.godot`
- `main_menu.tscn`
- `UI/main_menu.gd`
- `island.tscn`
- `Scene Elements/island.gd`

### Notes

- `main_menu.tscn` is the configured main scene.
- `island.tscn` assembles the gameplay world:
  - camera
  - UI
  - terrain renderers
  - path renderer
  - projectile layer
  - range indicator
  - in-world UI/floating text

## 2. Game Flow and Run State

### Responsibility

Drive the macro loop of the run.

### Key files

- `Singletons/phase_manager.gd`
- `Singletons/waves.gd`
- `Singletons/save_load.gd`
- `Indexes/wave_enemies.gd`

### Owned state

- current wave number
- current phase
- difficulty/environment/scaling
- wave plan
- queued choice events
- game over state

### Main interactions

- tells UI when phases/waves start and end
- starts combat through `Waves`
- starts choice phases through `ExpansionService` or `RewardService`
- calls save/load boundaries

### Key idea

`Phases` is the authoritative run-state machine. It decides what the player is allowed to do at any given time.

## 3. World, Terrain, and Expansion

### Responsibility

Represent the map and grow it over time.

### Key files

- `Scene Elements/island.gd`
- `Singletons/terrain.gd`
- `Singletons/terrain_service.gd`
- `Singletons/expansion_service.gd`
- `Objects/expansion_choice.gd`
- `Objects/generation_parameters.gd`
- `Objects/Indexes/terrain_database.gd`
- `Indexes/default_terrain.tres`

### Owned state

- terrain cells and terrain types
- tower occupancy grid
- shoreline/boundary cells
- expansion previews
- tower adjacency caches by type

### Main interactions

- `ExpansionService` procedurally builds new island blocks
- `TerrainService` applies blocks into the live island
- `Island` constructs environmental towers found in generated blocks
- `Island` rebuilds navigation whenever geometry changes

### Key idea

Expansion is not just visual. It changes:

- navigable space
- spawn locations via breaches
- available buildable terrain
- environmental features such as forests, anomalies, artifacts, and rites

## 4. Rendering the World

### Responsibility

Draw terrain, path previews, camera behavior, and in-world overlays.

### Key files

- `terrain_renderer.gd`
- `path_renderer.gd`
- `camera.gd`
- `Scene Elements/tower_preview.gd`
- `UnitComponents/range_indicator.gd`
- `Scene Elements/nav_debugger.gd`

### Main interactions

- `TerrainRenderer` draws watercolor-style terrain using shader-backed image data plus stamped decorations.
- `PathRenderer` draws enemy route previews and hypothetical path changes during tower placement.
- `Camera` supports manual pan/zoom plus temporary scripted overrides used by expansion choice overviews.
- `TowerPreview` and `RangeIndicator` provide build/selection feedback.

### Key idea

The game separates gameplay state from rendering state. Terrain and paths are computed from grid data, then rendered through custom presentation systems.

## 5. Entity Model: Units and Towers

### Responsibility

Represent all enemies, structures, and interactive gameplay actors.

### Key files

- `UnitComponents/unit.gd`
- `UnitComponents/tower.gd`
- `Singletons/units.gd`
- `Singletons/towers.gd`
- `Content/unit_data..gd`
- `Content/tower_data.gd`

### Main interactions

- `Units` repository loads enemy definitions from `Units/Enemies/*/*.tres`
- `Towers` repository loads tower definitions from `Units/Towers/*/*.tres`
- `create_unit()` and `create_tower()` instantiate the actual scenes
- prototype instances are also created for stat lookups, previews, and inspector rendering

### Key idea

`Unit` is the generic gameplay actor.

`Tower` extends `Unit` with:

- placement and occupied-cell logic
- ruin/resurrection flow
- adjacency updates
- rotation/facing
- build/sell/upgrade interactions

## 6. Unit Components

### Responsibility

Provide reusable gameplay capabilities.

### Key files

- `UnitComponents/component.gd`
- `UnitComponents/behavior_component.gd`
- `UnitComponents/movement_component.gd`
- `UnitComponents/navigation_component.gd`
- `UnitComponents/health_component.gd`
- `UnitComponents/modifiers_component.gd`
- `UnitComponents/range_component.gd`
- `UnitComponents/attack_component.gd`
- `UnitComponents/hitbox.gd`

### Component roles

- `MovementComponent`: physics movement, facing, walk animation jiggle
- `NavigationComponent`: path-following, obstacle checks, future-position prediction
- `HealthComponent`: health, shield, regen, death thresholds
- `ModifiersComponent`: stat aggregation, status effects, dynamic attributes, reactions
- `RangeComponent`: target acquisition and targeting modes
- `AttackComponent`: attack payload creation and cooldowns
- `Behavior`: high-level unit decision-making

### Key idea

Most gameplay variation comes from combining:

- content resources
- a unit scene composition
- one behavior script
- zero or more attached effects

## 7. Behaviors and Special Unit Logic

### Responsibility

Define the per-entity decision logic that components alone do not cover.

### Key files

- `Content/Behaviors/_default_behavior.gd`
- `Content/Behaviors/_default_tower_behavior.gd`
- tower-specific behavior scripts under `Content/Behaviors/`
- enemy/tower-specific behavior scripts under `Units/.../*behavior.gd`

### Examples

- `DefaultTowerBehavior`: wind-up targeting and turret rotation
- `AmplifierBehavior`: adjacency-based stat buffs
- `BreachBehavior`: seed to active spawn-point lifecycle
- `PrismBehavior`: registers with the tower network manager
- `HealerBehavior`: ally-heal aura
- `SummonerBehavior`: spends attack value as summon count
- `SnowballBehavior`: lane scanning instead of simple single-target attacks

### Key idea

Behavior scripts are usually narrow and focused. The shared gameplay framework does most of the heavy lifting.

## 8. Combat, Targeting, and Projectiles

### Responsibility

Resolve hits, area queries, projectile travel, and damage reservation.

### Key files

- `Singletons/combat_manager.gd`
- `Singletons/targeting_coordinator.gd`
- `Content/attack_data.gd`
- `Content/delivery_data.gd`
- `Objects/EventData/hit_data.gd`
- `Objects/EventData/hit_report.gd`
- `Units/Entities/hurtbox.gd`
- `Units/Towers/prism/prism_laser.gd`

### Main interactions

- `AttackComponent` builds `HitData` and `DeliveryData`
- `CombatManager` resolves hitscan, cone, line AOE, abstract projectile, and simulated projectile delivery
- `TargetingCoordinator` tracks reserved damage to reduce overkill waste
- `Hitbox` layers and physics queries define who can be hit

### Key idea

Combat payloads are data-first. Attack scripts mostly create hit definitions; `CombatManager` interprets the delivery model.

## 9. Navigation and Enemy Spawning

### Responsibility

Generate enemy routes and run combat-wave spawning.

### Key files

- `Singletons/navigation.gd`
- `Singletons/waves.gd`
- `Singletons/spawn_point_service.gd`
- `Indexes/wave_enemies.gd`

### Main interactions

- `Island.update_navigation_grid()` rebuilds the walkability grid from terrain and towers
- `Navigation.find_path()` computes cached paths
- `SpawnPointService` tracks active breach towers as enemy spawn locations
- `Waves` expands wave definitions into enemy spawns and reconciles enemy counts

### Key idea

The navigation service is global, but the island is the source of truth for obstacle placement.

## 10. Effects, Relics, and Reactive Gameplay

### Responsibility

Implement passives, triggered effects, and event-driven rule changes.

### Key files

- `Content/effect_prototype.gd`
- `Content/effect_instance.gd`
- `Player Services/global_event_service.gd`
- `Objects/modifier.gd`
- `Objects/status_effect.gd`
- relic effect scripts under `Content/Relics/**`
- general effect scripts under `Content/Effects/**`

### Main interactions

- local effects attach to units and run from `Unit.on_event`
- global effects register into `GlobalEventService` and listen to `Player.on_event`
- statuses become modifiers through `ModifiersComponent`
- relics can contribute:
  - global stat modifiers
  - global event effects
  - active effect scenes

### Key idea

This subsystem is one of the main extensibility points in the project. New relics and special mechanics are often small scripts plus data resources rather than deep engine changes.

## 11. Player, Economy, Rewards, and Progression

### Responsibility

Track player-owned run state and spending.

### Key files

- `Singletons/player.gd`
- `Singletons/reward_service.gd`
- `Player Services/trader_service.gd`
- `Player Services/ruin_service.gd`
- `Singletons/power_service.gd`
- reward resources under `Content/Rewards/`
- relic resources under `Content/Relics/`

### Owned state

- flux
- HP
- tower capacity and used capacity
- unlocked towers
- rite inventory
- active relics
- tutorial completion profile
- trader stock

### Main interactions

- build/upgrade/sell requests come in through the UI bus
- `Player` validates cost/capacity and delegates placement to `Island`
- `RewardService` samples weighted rewards
- `TraderService` maintains a shop inventory separate from one-off reward phases
- `PowerService` disables towers when population/capacity deficits occur
- `RuinService` manages temporary ruined towers across wave boundaries

## 12. Input, Selection, and World Interaction

### Responsibility

Translate player input into selection, preview, building, and inspection actions.

### Key files

- `Singletons/click_handler.gd`
- `UI/sidebar_ui.gd`
- `UI/inspector/inspector.gd`
- `UI/cursor_info/cursor_info.gd`

### Main interactions

- `SidebarUI` emits tower-selection intents
- `ClickHandler` owns preview mode, selected mode, rotation, placement, and ghost-inspection behavior
- `Inspector` renders unit/tower state, upgrade previews, actions, and statuses

### Key idea

The input model is effectively a small state machine:

- idle
- previewing
- tower selected

## 13. UI and HUD

### Responsibility

Present game state and coordinate non-world UI flows.

### Key files

- `UI/_ui_bus.gd`
- `UI/_ui.tscn`
- `UI/sidebar_ui.gd`
- `UI/reward_ui.gd`
- `UI/trade_menu/trade_panel.gd`
- `UI/expansion_ui/expansion_ui.gd`
- `UI/wave_timeline/wave_timeline.gd`
- `UI/game_over_screen/game_over_screen.gd`
- `UI/settings_menu/settings_menu.gd`

### Main interactions

- the UI bus is the main decoupling layer between gameplay code and UI nodes
- gameplay systems emit state changes
- UI emits player intents back to services

### Key idea

This subsystem is relatively well separated from core gameplay because most communication is routed through signals on `UI`.

## 14. Tutorials, Tooltips, and Keyword Presentation

### Responsibility

Explain the game and provide inspectable rich text.

### Key files

- `UI/tutorial/tutorial_manager.gd`
- `UI/tutorial/tutorial_step.gd`
- `Singletons/keyword_service.gd`
- `UI/_interactive_rich_text_label.gd`
- `UI/_tooltip_panel.gd`

### Main interactions

- tutorial steps are authored as resources and run through `TutorialManager`
- text labels use keyword parsing such as `{GOLD}` or `{T_TURRET}`
- hovering text opens nested tooltips backed by `KeywordService`

### Key idea

The keyword system doubles as both presentation and content lookup, which keeps UI text expressive without hardcoding every tooltip manually.

## 15. Persistence

### Responsibility

Save and restore run and profile state.

### Key files

- `Singletons/save_load.gd`
- `Scene Elements/island.gd`
- `Singletons/player.gd`
- `Singletons/phase_manager.gd`
- save helpers on `Tower`, `HealthComponent`, and other major scripts

### Save boundaries

- player state
- phase state and wave plan
- terrain grid
- tower list and per-tower state
- profile data such as tutorial completion

### Notes

The save system is JSON-based and straightforward, but not every subsystem is fully serialized yet. Some comments in the code mark partially implemented persistence paths.

## 16. Audio, Particles, and VFX

### Responsibility

Handle audiovisual feedback and pooled transient effects.

### Key files

- `Singletons/audio.gd`
- `Singletons/particle_manager.gd`
- `Singletons/vfx_manager.gd`
- `Singletons/clock.gd`
- `Content/vfx_info.gd`

### Main interactions

- `Audio` pools `AudioStreamPlayer2D` nodes
- `ParticleManager` pools particle scenes
- `VFXManager` draws lightweight effects directly through `RenderingServer`
- `Clock` provides game-speed-aware timers and scaled delta values used throughout gameplay

### Key idea

Presentation timing is intentionally centralized in `Clock`, which lets gameplay and many visuals respect pause and fast-forward.

## 17. Static Data, IDs, and Indexes

### Responsibility

Define enums, IDs, and reference data used across systems.

### Key files

- `Indexes/attributes.gd`
- `Indexes/effects.gd`
- `Indexes/relics.gd`
- `Indexes/identifiers.gd`
- `Indexes/layers.gd`

### Examples

- attribute IDs and status reaction definitions
- string identifiers for sounds and particles
- Z-layer constants
- relic registries and effect enums

## Dependency Summary

At a high level, the architecture looks like this:

- scenes create the live world
- autoloads coordinate the run
- `Island` owns terrain and towers
- units and towers are built from components
- behaviors and effects customize those entities
- content resources define most stats and unlockables
- the UI bus connects presentation with services

In shorthand:

`Main Menu -> Island Scene -> Phases -> Services -> Island -> Units/Towers -> Components -> Effects/Combat -> UI`

## Directory Guide

- `Singletons/`: global services and repositories
- `Scene Elements/`: world-scene scripts
- `UnitComponents/`: reusable gameplay components
- `Units/`: concrete unit and tower scenes plus their local behaviors/resources
- `Content/`: data resources, effect prototypes, reward definitions, relic definitions
- `Objects/`: lightweight runtime data classes
- `Indexes/`: enums, constants, lookup registries
- `UI/`: HUD, menus, inspector, timeline, tutorials, tooltip systems
- `Shaders/`: terrain and unit shaders
- `Assets/`, `Sounds/`, `Fonts/`: content assets

## Architectural Strengths

- clear component model for units and towers
- strong data-driven content pipeline
- flexible effect and event system
- good separation between world rendering and world state
- UI mostly communicates through a dedicated signal bus

## Architectural Tradeoffs

- heavy reliance on autoload singletons increases coupling
- several systems read each other's internal state directly
- some save/load paths are only partially implemented
- a few legacy or duplicate files remain in the repository (`*.txt` snapshots and similar artifacts)
- repositories and enums have some drift from live content in a few places

## Best Entry Points for New Contributors

If you are new to the project, start here:

1. `Scene Elements/island.gd`
2. `Singletons/phase_manager.gd`
3. `UnitComponents/unit.gd`
4. `UnitComponents/tower.gd`
5. `Singletons/combat_manager.gd`
6. `Singletons/navigation.gd`
7. `Singletons/player.gd`
8. `UI/_ui_bus.gd`
9. one simple tower scene such as `Units/Towers/turret/`
10. one simple enemy scene such as `Units/Enemies/basic/`

That sequence gives the clearest top-down picture of how the game boots, runs, and resolves gameplay.
