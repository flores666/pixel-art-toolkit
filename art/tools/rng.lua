-- rng.lua -- the seeded variation system.
--
-- Determinism rule: an asset is a pure function of (generator name, seed).
-- Nothing in the toolkit may call math.random, os.time or os.clock. Every
-- random decision goes through an Rng built from a seed, and every generator
-- gets its own independent stream so adding a call in one generator cannot
-- shift the output of another.

local rng = {}

local Rng = {}
Rng.__index = Rng

local MASK = 0xFFFFFFFF

--- FNV-1a 32-bit. Turns a name ("concrete_floor", "rust") into a stream salt.
function rng.hash(str)
  local h = 2166136261
  for i = 1, #str do
    h = (h ~ str:byte(i)) & MASK
    h = (h * 16777619) & MASK
  end
  return h
end

local function mix(seed)
  -- One SplitMix-ish round so that adjacent seeds (1, 2, 3 ...) start far apart.
  local x = (seed ~ 0x9E3779B9) & MASK
  x = (x ~ (x >> 16)) & MASK
  x = (x * 0x85EBCA6B) & MASK
  x = (x ~ (x >> 13)) & MASK
  x = (x * 0xC2B2AE35) & MASK
  x = (x ~ (x >> 16)) & MASK
  return x == 0 and 0x1D872B41 or x
end

--- New stream. `salt` (optional string) namespaces the stream.
function rng.new(seed, salt)
  seed = math.tointeger(seed) or rng.hash(tostring(seed))
  if salt then seed = (seed ~ rng.hash(salt)) & MASK end
  return setmetatable({ state = mix(seed & MASK), seed = seed & MASK, salt = salt }, Rng)
end

--- A named sub-stream of this one. Use it per feature ("rust", "cracks") so
-- feature order inside a generator does not couple the streams together.
function Rng:branch(name)
  return rng.new((self.seed ~ rng.hash(name)) & MASK)
end

--- xorshift32. Returns a 32-bit unsigned integer.
function Rng:next()
  local x = self.state
  x = (x ~ ((x << 13) & MASK)) & MASK
  x = (x ~ (x >> 17)) & MASK
  x = (x ~ ((x << 5) & MASK)) & MASK
  self.state = x
  return x
end

--- Float in [0, 1).
function Rng:float()
  return self:next() / 4294967296.0
end

--- Integer in [lo, hi], inclusive. Unbiased enough for art decisions.
function Rng:range(lo, hi)
  if hi <= lo then return lo end
  return lo + (self:next() % (hi - lo + 1))
end

--- True with probability `p` (0..1).
function Rng:chance(p)
  return self:float() < p
end

--- Uniform element of a list.
function Rng:pick(list)
  return list[self:range(1, #list)]
end

--- Weighted pick: { { value = "a", weight = 3 }, { value = "b", weight = 1 } }.
function Rng:weighted(options)
  local total = 0
  for _, o in ipairs(options) do total = total + (o.weight or 1) end
  local roll = self:float() * total
  for _, o in ipairs(options) do
    roll = roll - (o.weight or 1)
    if roll < 0 then return o.value end
  end
  return options[#options].value
end

--- In-place deterministic Fisher-Yates.
function Rng:shuffle(list)
  for i = #list, 2, -1 do
    local j = self:range(1, i)
    list[i], list[j] = list[j], list[i]
  end
  return list
end

--- A stable variant index in [0, count-1] for (seed, key). Used by previews and
-- by callers who want "the same tile at the same map cell" across runs.
function rng.variant(seed, key, count)
  return rng.new(seed, key):range(0, count - 1)
end

return rng
