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
style.max_edge_density = { ground = 0.30, structure = 0.55, prop = 0.60 }
style.default_surface = "prop"

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

-- Dithering ------------------------------------------------------------------
-- Ordered 2x2 Bayer only, anchored to absolute coordinates so neighbouring
-- tiles stay in phase. Density 1..3 out of 4; 4 means "solid", i.e. not dither.
style.dither_matrix = { { 0, 2 }, { 3, 1 } }
style.dither_max_ramp_distance = 1 -- only ever mix two ADJACENT ramp steps

-- Outlines -------------------------------------------------------------------
style.outline_color = "ink_2"      -- near black; objects only, tiles are never outlined
style.outline_diagonals = false    -- 4-neighbour outline, no corner nubs

-- Draw order every generator must follow (documented in ART_STYLE.md) --------
style.draw_order = {
  "silhouette",      -- block in the shape, flat
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
