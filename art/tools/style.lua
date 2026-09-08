-- style.lua -- the single source of truth for every hard visual rule.
--
-- Nothing in the toolkit may hardcode a number that lives here. Generators,
-- materials, validators and previews all read this table, so changing a rule
-- once changes it everywhere (including what the validators enforce).

local style = {}

-- Grid -----------------------------------------------------------------------
style.tile = 16          -- base cell, in pixels. Never change per-asset.
style.max_tiles_x = 4    -- largest asset the toolkit will accept: 64x64
style.max_tiles_y = 4

-- Lighting -------------------------------------------------------------------
-- Light arrives FROM the upper-left. `dx`/`dy` point from a surface towards
-- the light, so a pixel whose (x-1) or (y-1) neighbour is empty is lit and a
-- pixel whose (x+1) or (y+1) neighbour is empty is in shade.
style.light = { dx = -1, dy = -1 }
style.light_step = 1     -- ramp steps added on a lit edge
style.shadow_step = 1    -- ramp steps subtracted on a shaded edge

-- Colour ---------------------------------------------------------------------
style.max_colors_per_asset = 16   -- for the first 16x16 tile of an asset
style.extra_colors_per_tile = 2   -- budget added by each further tile
style.alpha_opaque = 255
-- Alpha is binary. Anything between 1 and 254 is a bug, not a soft edge.

-- Clusters and noise ---------------------------------------------------------
-- Single stray pixels read as noise/AI dust. Detail is authored as clusters.
style.cluster_min = 2
style.cluster_max = 10
style.speck_min = 2      -- smallest allowed "speck": still two pixels
style.speck_max = 3
-- Two caps, and BOTH apply: the validator binds on whichever is tighter.
style.max_isolated_pixels = 6      -- absolute cap per 16x16 tile, and
style.max_isolated_ratio = 0.04    -- never more than 4% of opaque pixels

-- Texture busyness -----------------------------------------------------------
-- Fraction of neighbouring pixel pairs that differ (pixel_utils.edge_density).
-- Measured on the game's own hand-authored art: its platform FIELD tiles -- the
-- ones laid a hundred at a time, which is the case that matters -- sit at
-- 0.10-0.17 and hold 74-82% of their area at a single colour; its wall faces
-- sit at 0.25. (Its busiest authored tiles run far higher, up to 0.66, but
-- those are gravel and void tiles used as accents, not as fields.)
--
-- The measure is blind to CONTRAST: it counts pairs that differ, not by how
-- much, so it cannot tell a calm near-value patch from a loud one. It is a
-- ceiling, never a target.
--
-- The ceiling depends on what the surface is FOR, which each generator
-- declares as `surface`:
--   ground     covers the whole screen and is laid in fields -- it must be the
--              calmest thing in the game or the world reads as static. The
--              per-tile ceiling leaves room for the occasional feature tile
--              (a fracture, a pothole); what actually has to stay calm is the
--              FIELD, and style.grid.max_field_density enforces that;
--   structure  carries construction detail: joints, folds, fixings;
--   prop       adds a silhouette, an outline and internal structure.
--   decal      a transparent overlay dropped ON TOP of ground. It carries a
--              mark and nothing else, so almost all of it is transparent and
--              the busyness of the few pixels it does own is allowed to be
--              high -- the calm around it comes from the ground underneath.
--
-- `decal` is deliberately ABSENT, and that is a finding rather than an
-- omission. edge_density is the fraction of adjacent opaque pairs that differ,
-- and a decal is a handful of pixels each of which carries its own lit cap and
-- its own cast shadow (ART_STYLE.md 5) -- so on a correctly drawn three-pixel
-- stone essentially every adjacent pair differs and the measure reads ~1.0.
-- It cannot distinguish a good decal from a bad one; it only reports that the
-- asset is small. Decals are held to `style.decal` instead, which measures the
-- things that actually go wrong: how much of the cell it covers and how many
-- separate marks it breaks into.
--
-- These are measured against the current library, with headroom. As of the
-- outdoor kit the worst seed of any generator in each class sits at:
-- ground 0.19, transition 0.33, structure 0.44, prop 0.59.
--
-- The `prop` ceiling was 0.60 and its basis changed twice, both times because
-- a bug was fixed rather than because an asset needed to pass:
--
--   * `despeckle` was silently destroying deliberate detail -- the old stray
--     test condemned any pixel with no same-coloured neighbour, which is
--     exactly the documented grammar for a stone (a lit cap plus its own
--     shadow, ART_STYLE.md 5) and for a rivet catch-light. Detail now
--     survives cleanup, so everything measures a little busier;
--   * `edge_density` counted body-against-OUTLINE pairs. An outline is
--     mandatory and differs from every body colour, so the measure was
--     scoring perimeter-to-area rather than texture: a weed drawn as four
--     clean strokes scored 0.68 and a drum covered in corrosion 0.59. With
--     the outline excluded the weed scores 0.25, which is the right order.
--
-- Even corrected, this measure is a backstop on a prop: it is blind to
-- contrast, and on a small object the silhouette rules (style.prop) are what
-- carry real signal.
-- `transition` is 0.38 rather than the ground class's 0.30 because a
-- transition tile holds TWO ground surfaces plus the boundary between them,
-- so its busyness is bounded by the busier of the pair and not by either
-- alone. Measured: the busiest single ground tiles run 0.21-0.24 (dry grass,
-- gravel), and the busiest transition -- crazed tarmac meeting textured dry
-- grass -- reaches 0.36. The number is set from that, with headroom.
--
-- Its FIELD average is still held to the ground limit (style.grid), which is
-- the check that actually matters: a transition band a hundred tiles long is
-- still ground.
style.max_edge_density = { ground = 0.30, transition = 0.38, structure = 0.55, prop = 0.65 }
style.default_surface = "prop"

-- The surface classes that EXIST. Kept separate from max_edge_density, which
-- is the classes that have a busyness ceiling -- `decal` is a real class with
-- no meaningful ceiling (above), and conflating "is this a known class" with
-- "what is its ceiling" made adding one impossible.
-- Below this fraction of opaque pixels being INTERIOR (all four neighbours
-- opaque), edge_density carries no signal and texture_noise does not apply --
-- see pixel_utils.interior_ratio. Measured: solid-bodied props sit at
-- 0.35-0.60, stroke assets (a weed, a branch, every decal) at 0.00-0.12.
style.min_interior_for_density = 0.20

style.surfaces = { "ground", "transition", "structure", "prop", "decal" }
style.is_surface = {}
for _, name in ipairs(style.surfaces) do style.is_surface[name] = true end

-- A transition tile carries the boundary between two terrains, which is one
-- more feature than a field tile has. It gets a little more headroom than
-- `ground` and is exempt from the seam-bias discipline (its whole job is to be
-- different at the edges), but its FIELD average is still held to the ground
-- limit: a transition band a hundred tiles long is still ground.

-- Ground fields ---------------------------------------------------------------
-- A ground tile is laid a hundred at a time. If the tiling shows, the world
-- looks like a spreadsheet, so previews.grid_report measures it and these are
-- the limits it reports against.
-- Calibrated, not invented (the numbers are in ART_STYLE.md):
--   the game's own metro floor variants laid in a field score seam_bias
--   4.2 / 10.3 -- every tile has a baked-in dark edge and the grid is plain to
--   see; continuous, never-tiled reference art scores 0.01.
style.grid = {
  max_seam_bias = 0.35,      -- a CONSISTENTLY signed step along the boundary
                             -- line is what the eye reads as a grid
  -- There is deliberately no upper bound on seam *contrast*. Independently
  -- seeded tiles always differ more across a boundary than inside one, and the
  -- calmer and more coherent the interior gets, the higher that ratio climbs --
  -- it rose from 1.5 to 2.4 when blob growth was made compact, which made the
  -- art better, not worse. A hard edge drawn onto every tile shows up in
  -- seam_bias instead. The lower bound stays: detail that systematically
  -- avoids the edges leaves a calm ring around every cell, and that IS a grid.
  min_seam_contrast = 0.40,
  max_tile_luma_sd = 2.5,    -- per-tile average luminance, 0-255 scale
  -- Busyness averaged over a whole 10x10 field. Held at the level of the
  -- game's own authored platform field tiles (0.10-0.17): individual tiles may carry a
  -- crack or a pothole, but a hundred of them together must still read as
  -- ground rather than as static. This is the number that caught the first
  -- above-ground draft, where every single tile had a feature on it.
  max_field_density = 0.22,
}

-- Decals ---------------------------------------------------------------------
-- A decal is a transparent overlay: one mark, dropped over ground. Its job is
-- to take detail OFF the base tiles -- a field tile that carries its own stone
-- prints that stone a hundred times, whereas a stone decal is placed where the
-- level wants one. So a decal is mostly nothing:
style.decal = {
  max_coverage = 0.40,   -- opaque fraction of the tile. Above this it is not a
                         -- decal, it is a tile.
  -- Below this the decal is an accident rather than a mark. 5 pixels of a
  -- 256-pixel cell: measured, the sparsest legitimate family (broken glass,
  -- which can only be a glint at this size) bottoms out at 0.0195.
  min_coverage = 0.018,
  -- Separate marks per decal, counted by pixel_utils.mark_groups (8-connected,
  -- 2px gap tolerance, so a diagonal crack is one mark and a tuft's spaced
  -- stalks are one clump). A decal is ONE thing in ONE place -- a clump, a
  -- stain, a few chunks together -- and a decal that breaks into eight marks
  -- is a texture again.
  --
  -- 4 rather than 3: measured across the library, "a few stones", "rubble
  -- fragments" and "leaf litter" land on four loose marks and read correctly
  -- as one patch of litter. Set from the measurement, like every other number
  -- in this file.
  max_marks = 4,
}

-- Terrain and transitions ----------------------------------------------------
-- Terrains meet along a boundary drawn by `terrain.lua`. The boundary is a
-- thresholded bilinear blend of the four CORNER weights of the tile (16-tile
-- corner Wang, which is Godot's TERRAIN_MODE_MATCH_CORNERS), so where two
-- corners differ the boundary crosses that edge at its exact midpoint.
--
-- The invariant that makes a ragged natural boundary tileable is the same one
-- that makes a decayed cast joint tileable (concrete.groove):
--
--     A BOUNDARY IS PINNED TO ITS IDEAL POSITION AT THE TILE EDGE, AND MAY
--     WANDER ONLY IN THE MIDDLE.
--
-- Two tiles laid side by side each compute the ideal crossing point from their
-- own corner weights and get the same answer, so the boundary meets. Inside
-- the tile it is free, which is where the raggedness that stops a grass edge
-- reading as a cut lawn has to live.
style.terrain = {
  pin_width = 3,       -- px at each tile edge where the boundary is pinned to
                       -- the ideal position. Wander ramps in over this band.
  noise_cell = 4,      -- value-noise lattice spacing, px. Lobes of ~4-8px:
                       -- per-pixel noise would fringe the boundary with dust.
  masks = 16,          -- corner Wang: 4 corners, so 16 configurations. Mask 0
                       -- is the pure base terrain (the base generator itself),
                       -- so transition sets generate masks 1..15.
}

-- Modular connectivity -------------------------------------------------------
-- A wall or fence piece declares what its four edges present, as socket names
-- (`sockets = { left = "wall_core", ... }`). Two pieces connect when the edge
-- they meet on carries the same socket, and the `sockets` validator checks
-- that claim mechanically: every piece presenting a socket must agree with
-- every other piece on which ROWS of that edge are opaque and which palette
-- RAMP each opaque row belongs to. That is the minimum meaning of "these
-- connect visually" -- the material lines up and the silhouette does not step.
--
-- Nothing constrains the exact colour: a joint is allowed to decay, and one
-- piece's edge may be rustier than its neighbour's.
style.socket_tolerance = 0.0   -- rows of an edge profile allowed to disagree

-- Dithering ------------------------------------------------------------------
-- Ordered 2x2 Bayer only, anchored to absolute coordinates so neighbouring
-- tiles stay in phase. Density 1..3 out of 4; 4 means "solid", i.e. not dither.
style.dither_matrix = { { 0, 2 }, { 3, 1 } }
style.dither_max_ramp_distance = 1 -- only ever mix two ADJACENT ramp steps

-- Variation ------------------------------------------------------------------
-- Two bounds, and a generator has to sit between them:
--   * variants that share too many pixels are the same asset twice, and a
--     level built from them repeats visibly;
--   * variants that share too FEW are not the same object any more. A row of
--     the same crate has to read as a row of the same crate, so the silhouette
--     and the structure hold still and only the wear moves.
-- Measured as the mean fraction of pixels two variants agree on, per class.
style.variant_overlap = {
  ground     = { min = 0.20, max = 0.97 },
  -- A transition tile is chosen by CONNECTIVITY, not by looks: the level asks
  -- for "the piece whose top-left corner is grass" and there is exactly one
  -- answer. So the lower bound -- which exists to stop a prop's variants
  -- drifting until they stop being the same object -- has little to guard
  -- here, and a diagonal mask between two high-contrast terrains legitimately
  -- shares only 29% of its pixels between variants. It is held to the ground
  -- floor instead; the UPPER bound, which catches variants too similar to be
  -- worth shipping, is what matters for this class.
  transition = { min = 0.20, max = 0.98 },
  decal      = { min = 0.05, max = 0.95 },
  structure  = { min = 0.30, max = 0.97 },
  prop       = { min = 0.55, max = 0.995 },
}
-- Byte-identical variants are always a bug: it means the seed did nothing.
style.max_identical_variants = 0

-- Props ----------------------------------------------------------------------
-- A prop is a silhouette. These bound how much of its cell it may fill and how
-- broken up that fill may be: a prop that fills its whole cell has no
-- silhouette left to read, and one that is a scatter of disconnected fragments
-- is rubble whether it meant to be or not.
style.prop = {
  min_occupancy = 0.10,     -- opaque fraction of the bounding cell
  max_occupancy = 0.92,
  max_components = 4,       -- separate opaque islands (a log plus its bark
                            -- flakes is two; eight is a mess)
  max_interior_holes = 2,   -- enclosed transparent regions. A bin has a mouth;
                            -- a prop with six holes has been eaten by rust
                            -- overlays rather than drawn.
  min_hole_size = 2,        -- an enclosed 1px hole is a bug, never a window
}

-- Outlines -------------------------------------------------------------------
style.outline_color = "ink_2"      -- near black; objects only, tiles are never outlined
style.outline_diagonals = false    -- 4-neighbour outline, no corner nubs

-- Categories -----------------------------------------------------------------
-- What an asset IS, for the level editor and for the Godot manifest. The
-- category fixes the sensible defaults for the two things an importer has to
-- decide -- which layer it draws on and whether it collides -- so a generator
-- only states them when it differs from its category.
--
--   layer      "ground"        the terrain layer itself
--              "ground_detail" decals: over ground, under everything
--              "object"        sorted with the player by its baseline
--              "overhead"      drawn over the player (a canopy, a top of wall)
--   collision  "none"          walk straight through
--              "block"         the whole cell is solid
--              "hull"          solid where the silhouette is (the importer
--                              builds the polygon from the alpha)
--              "low"           step over / shoot over: blocks movement, not
--                              line of sight
style.categories = {
  ground      = { layer = "ground",         collision = "none" },
  transition  = { layer = "ground",         collision = "none" },
  -- The tileable wall and fence TEXTURES (as opposed to the modular pieces):
  -- a level lays a run of them on an object layer and they block the cell.
  structure   = { layer = "object",         collision = "block" },
  decal       = { layer = "ground_detail",  collision = "none" },
  vegetation  = { layer = "object",         collision = "none" },
  rock        = { layer = "object",         collision = "hull" },
  wall        = { layer = "object",         collision = "block" },
  fence       = { layer = "object",         collision = "hull" },
  road        = { layer = "object",         collision = "low" },
  industrial  = { layer = "object",         collision = "hull" },
  rubble      = { layer = "ground_detail",  collision = "low" },
  prop        = { layer = "object",         collision = "hull" },
}

-- Draw order every generator must follow (documented in ART_STYLE.md) --------
style.draw_order = {
  "silhouette",      -- block in the shape, flat (a transition tile blocks in
                     -- its two terrain regions here)
  "material",        -- material grammar fills it
  "structure",       -- seams, grooves, rivets, bands
  "lighting",        -- ramp-aware highlights and shadows
  "outline",         -- objects only
  "wear",            -- rust and dirt overlays
  "cleanup",         -- pixel_utils.despeckle: clusters, never dust
  "contact_shadow",  -- objects only, drawn after cleanup so it survives
}

--- Validate an asset size against the grid rules.
-- @return ok, message
function style.check_size(w, h)
  if w % style.tile ~= 0 or h % style.tile ~= 0 then
    return false, ("size %dx%d is not a multiple of %d"):format(w, h, style.tile)
  end
  if w < style.tile or h < style.tile then
    return false, ("size %dx%d is smaller than one tile"):format(w, h)
  end
  local tx, ty = w // style.tile, h // style.tile
  if tx > style.max_tiles_x or ty > style.max_tiles_y then
    return false, ("size %dx%d exceeds %dx%d tiles"):format(w, h, style.max_tiles_x, style.max_tiles_y)
  end
  return true
end

--- Number of whole 16x16 tiles an asset covers (used to scale budgets).
function style.tile_count(w, h)
  return (w // style.tile) * (h // style.tile)
end

return style
